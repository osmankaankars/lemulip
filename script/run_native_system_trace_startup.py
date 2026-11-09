#!/usr/bin/env python3
"""D20: one bounded System Trace recording around notification-gated startup."""

from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import selectors
import signal
import stat
import subprocess
import time
import uuid
import xml.etree.ElementTree as ET
import zipfile

from collect_native_trace_capabilities import capture, write_json


STREAM_LIMIT = 2 * 1024 * 1024
TRACE_LIMIT = 256 * 1024 * 1024
TRACE_ENTRIES = 16384
HELPER_TIMEOUT = 80.0
HELPER_ABORT_GRACE = 45.0
PREPARED_TIMEOUT = 10.0
RECORD_WALL_TIMEOUT = 45.0
RECORD_INTERRUPT_GRACE = 10.0
PROCESSES_XPATH = '/trace-toc/run[@number="1"]/processes'
TABLES_XPATH = '/trace-toc/run[@number="1"]/data/table'


class EvidenceError(ValueError):
    pass


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_regular(path: Path, limit: int = STREAM_LIMIT) -> bytes:
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode) or before.st_size > limit:
            raise EvidenceError("Receipt is not a bounded regular file: " + path.name)
        chunks = []
        remaining = limit + 1
        while remaining:
            chunk = os.read(descriptor, min(65536, remaining))
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        data = b"".join(chunks)
        after = os.fstat(descriptor)
        if (len(data) > limit or len(data) != before.st_size
                or (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns)):
            raise EvidenceError("Receipt changed or exceeded its bound: " + path.name)
        return data
    finally:
        os.close(descriptor)


def read_object(path: Path, limit: int = STREAM_LIMIT) -> tuple[dict, bytes]:
    data = read_regular(path, limit)
    value = json.loads(data)
    if not isinstance(value, dict):
        raise EvidenceError("Expected a JSON object: " + path.name)
    return value, data


def recording_command(trace: Path, notification: str) -> tuple[str, ...]:
    return ("/usr/bin/xcrun", "xctrace", "record", "--template", "System Trace",
            "--all-processes", "--time-limit", "30s", "--no-prompt",
            "--notify-tracing-started", notification, "--output", str(trace))


def export_command(trace: Path, *, xpath: str | None = None) -> tuple[str, ...]:
    base = ("/usr/bin/xcrun", "xctrace", "export", "--input", str(trace))
    return base + (("--toc",) if xpath is None else ("--xpath", xpath))


def xml_root(data: bytes) -> ET.Element:
    try:
        text = data.decode("utf-8-sig")
    except UnicodeDecodeError as error:
        raise EvidenceError("XML is not UTF-8") from error
    if "\x00" in text or re.search(r"<!\s*(?:DOCTYPE|ENTITY)\b", text, re.IGNORECASE):
        raise EvidenceError("XML declarations with entities or a document type are not accepted")
    try:
        root = ET.fromstring(text)
    except ET.ParseError as error:
        raise EvidenceError("Export is not complete, well-formed XML") from error
    if sum(1 for _ in root.iter()) > 1000000:
        raise EvidenceError("XML element bound exceeded")
    return root


def parse_toc(data: bytes) -> dict:
    root = xml_root(data)
    runs = root.findall("run")
    if root.tag != "trace-toc" or len(runs) != 1 or runs[0].get("number") != "1":
        raise EvidenceError("A fresh trace must contain exactly one run numbered 1")
    if len(root.findall(".//run")) != 1:
        raise EvidenceError("Unexpected nested or additional run")
    data_nodes = runs[0].findall("data")
    if len(data_nodes) > 1:
        raise EvidenceError("Ambiguous table container")
    tables = [] if not data_nodes else data_nodes[0].findall("table")
    return {"runNumber": 1, "tableCount": len(tables),
            "observedTables": [dict(sorted(node.attrib.items())) for node in tables],
            "processesXPath": PROCESSES_XPATH,
            "tablesXPath": TABLES_XPATH if tables else None}


def inspect_query_export(data: bytes, *, kind: str, toc: dict) -> dict:
    """Recognize a bounded export envelope; unknown shapes remain unqualified."""
    root = xml_root(data)
    nodes = root.findall("node")
    if root.tag != "trace-query-result" or not nodes or root.findall(".//error"):
        raise EvidenceError("Unrecognized, empty, or error query-result envelope")
    normalized = lambda value: value.replace("'", '"') if isinstance(value, str) else ""
    if kind == "processes":
        if len(nodes) != 1 or normalized(nodes[0].get("xpath")) != PROCESSES_XPATH:
            raise EvidenceError("Process export does not bind the requested entity")
        processes = nodes[0].findall("process") + nodes[0].findall("processes/process")
        if not processes:
            raise EvidenceError("Process export contains no recognized process entities")
        return {"recognizedEnvelope": True, "matchedNodeCount": 1, "processCount": len(processes)}
    if kind != "tables":
        raise EvidenceError("Unsupported export kind")
    expected = [table.get("schema") for table in toc["observedTables"]]
    if not expected or any(not isinstance(name, str) or not name for name in expected):
        raise EvidenceError("Actual TOC lacks a recognized schema identity for every table")
    actual = []
    rows = 0
    for node in nodes:
        path = normalized(node.get("xpath"))
        if not re.fullmatch(re.escape(TABLES_XPATH) + r"(?:\[[^\]]+\])*", path):
            raise EvidenceError("Table export contains an unrelated selection")
        schemas = node.findall("schema")
        if len(schemas) != 1 or not schemas[0].get("name"):
            raise EvidenceError("Table export has an unsupported or missing schema envelope")
        name = schemas[0].get("name")
        selector = re.search(r'\[@schema="([^"]+)"\]', path)
        if selector is not None and selector.group(1) != name:
            raise EvidenceError("Table selection and exported schema disagree")
        actual.append(name)
        rows += len(node.findall("row"))
    if Counter(actual) != Counter(expected):
        raise EvidenceError("Exported table schemas do not match all actual TOC tables")
    return {"recognizedEnvelope": True, "matchedNodeCount": len(nodes), "schemaNames": actual,
            "rowCount": rows, "activationCoverageInferred": False}


def apply_final_transport_gates(report: dict) -> None:
    """Late bytes/close errors must be considered after the final drain."""
    for name in ("helper", "record"):
        command = report["commands"].get(name)
        complete = (command is not None and command["status"] == "completed" and command["exitCode"] == 0
                    and command["stopReason"] is None and not command["streamErrors"]
                    and not command["cleanupFailed"])
        if not complete:
            report["recordingComplete"] = False
            if name == "helper":
                report["startupComplete"] = False


def validate_prepared(value: dict, *, pid: int, helper: Path, helper_hash: str,
                      staged: Path, output: Path, notification: str, nonce: str) -> None:
    expected = {"schema": 1, "kind": "native-system-trace-startup-prepared", "helperPID": pid,
                "helperExecutablePath": str(helper), "helperExecutableSHA256": helper_hash,
                "stagedPath": str(staged), "outputPath": str(output),
                "recordingNotificationName": notification, "nonce": nonce,
                "architecture": platform.machine()}
    if any(value.get(key) != wanted for key, wanted in expected.items()):
        raise EvidenceError("Prepared helper identity, path, architecture, or nonce differs")
    if (not isinstance(value.get("bootUUID"), str)
            or str(uuid.UUID(value["bootUUID"])).upper() != value["bootUUID"]
            or any(type(value.get(key)) is not int or value[key] <= 0
                   for key in ("machTimebaseNumer", "machTimebaseDenom"))):
        raise EvidenceError("Prepared boot/timebase identity is invalid")
    registration = value.get("recordingNotification", {})
    if (value.get("preparationComplete") is not True or value.get("startupRan") is not False
            or value.get("inputGenerated") is not False or registration.get("registered") is not True
            or registration.get("registrationStatus") != 0 or value.get("cooperativeAbortSupported") is not True):
        raise EvidenceError("Helper did not prepare a registered, input-free startup barrier")


def validate_startup(value: dict, prepared: dict, prepared_bytes: bytes) -> None:
    for key in ("helperPID", "helperExecutablePath", "helperExecutableSHA256", "architecture",
                "bootUUID", "nonce", "recordingNotificationName", "stagedPath", "outputPath"):
        if value.get(key) != prepared.get(key):
            raise EvidenceError("Final helper identity differs: " + key)
    if (value.get("schema") != 1 or value.get("kind") != "native-system-trace-startup"
            or value.get("status") != "complete" or value.get("processStartupComplete") is not True
            or value.get("startupRan") is not True or value.get("startupNeverRan") is not False):
        raise EvidenceError("Helper startup did not complete")
    receipt = value.get("preparedReceipt", {})
    if receipt.get("sha256") != digest(prepared_bytes) or receipt.get("byteCount") != len(prepared_bytes):
        raise EvidenceError("Final helper does not bind the prepared receipt")
    notification = value.get("recordingNotification", {})
    count = notification.get("receivedCount")
    if (notification.get("received") is not True or type(count) is not int or count < 1
            or notification.get("cancelled") is not True or notification.get("cancelStatus") != 0
            or notification.get("countOverflow") is not False):
        raise EvidenceError("No recording-start notification was observed")
    if value.get("cooperativeAbort", {}).get("requested") is True:
        raise EvidenceError("Helper was cooperatively aborted")
    for flag in ("inputGenerated", "mouseInputGenerated", "keyboardInputGenerated", "accessibilityCallsMade"):
        if value.get(flag) is not False:
            raise EvidenceError("Missing or nonzero input exclusion: " + flag)
    if value.get("unexpectedNativeInputObserved") is not False:
        raise EvidenceError("Unexpected native input or missing input check")
    if (any(value.get(key) is not True for key in
            ("nativeLifecycleRecordsComplete", "stagedInputsUnchanged", "helperExecutableUnchanged"))
            or value.get("errors") != []):
        raise EvidenceError("Native lifecycle or immutable-input evidence is incomplete")
    for role in ("control", "source"):
        process = value.get("processes", {}).get(role, {})
        cleanup = process.get("cleanup", {})
        if (not isinstance(process.get("pid"), int) or process["pid"] <= 0
                or cleanup.get("completedNormally") is not True or cleanup.get("terminated") is not True
                or cleanup.get("normalTerminationRequested") is not True or cleanup.get("terminateReturn") is not True
                or cleanup.get("fallbackUsed") is not False or cleanup.get("signals") != []
                or cleanup.get("outstandingLaunchCompletion") is not False):
            raise EvidenceError("Owned application did not complete normal cleanup: " + role)


def helper_cleanup_resolved(value: dict | None, pid: int, nonce: str) -> bool:
    """Failed startup can still clean up; a missing receipt proves neither."""
    if (not isinstance(value, dict) or value.get("kind") != "native-system-trace-startup"
            or value.get("helperPID") != pid or value.get("nonce") != nonce
            or not isinstance(value.get("processes"), dict)):
        return False
    processes = list(value["processes"].values())
    if any(not isinstance(process, dict) or type(process.get("launchRequested")) is not bool for process in processes):
        return False
    launched = [process for process in processes if process["launchRequested"]]
    if not launched:
        return value.get("startupNeverRan") is True and value.get("startupRan") is False
    return all(process.get("cleanup", {}).get("terminated") is True
               and process["cleanup"].get("outstandingLaunchCompletion") is False for process in launched)


def group_snapshot(pgid: int, *, cwd: Path, env: dict[str, str]) -> dict:
    check, data = capture(("/bin/ps", "-A", "-o", "pid=,pgid=,stat="), cwd=cwd, env=env,
                          timeout=2, limit=65536, allow_group_snapshot=False)
    result = {"status": "unresolved", "commandStatus": check["status"], "exitCode": check["exitCode"],
              "stdoutSHA256": digest(data["stdout"]), "stderrSHA256": digest(data["stderr"]), "members": []}
    try:
        rows = [row.split() for row in data["stdout"].decode("ascii").splitlines() if row.strip()]
        valid = bool(rows) and all(len(row) == 3 and row[0].isdigit() and row[1].isdigit() for row in rows)
        if valid:
            result["members"] = [{"pid": int(row[0]), "pgid": int(row[1]), "state": row[2]}
                                 for row in rows if int(row[1]) == pgid]
        if (valid and check["status"] == "completed" and not check["cleanupFailed"] and not data["stderr"]
                and all(row["state"].startswith("Z") for row in result["members"])):
            result["status"] = "no-live-group-members-observed"
    except (UnicodeDecodeError, ValueError):
        pass
    return result


class MonitoredCommand:
    """Concurrent bounded streams; the orchestrator chooses each role's cleanup."""

    def __init__(self, argv: tuple[str, ...], *, cwd: Path, env: dict[str, str], limit: int = STREAM_LIMIT):
        self.started = time.monotonic()
        self.streams = {"stdout": bytearray(), "stderr": bytearray()}
        self.selector = selectors.DefaultSelector()
        self.process = None
        # Optional D21 PID lease: a numeric-PID observer must finish before this
        # sole child owner may reap the recorder and permit PID reuse.
        self.reap_deferred = False
        self.closed = False
        self.selector_failed = False
        self.receipt = {"argv": list(argv), "pid": None, "status": "running", "exitCode": None,
                        "maximumCombinedBytes": limit, "observedBytes": 0, "retainedBytes": 0,
                        "stopReason": None, "signals": [], "signalErrors": [], "streamErrors": [],
                        "cleanupFailed": False}
        try:
            self.process = subprocess.Popen(argv, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
        except OSError as error:
            self.receipt.update(status="spawn-error", error=str(error))
            return
        self.receipt["pid"] = self.process.pid
        try:
            for name, pipe in (("stdout", self.process.stdout), ("stderr", self.process.stderr)):
                os.set_blocking(pipe.fileno(), False)
                self.selector.register(pipe, selectors.EVENT_READ, name)
        except Exception as error:
            # Keep the Popen ownership reference even when pipe setup fails.
            self.stream_error("setup", error)

    def stream_error(self, stage: str, error: Exception) -> None:
        self.receipt["streamErrors"].append({"stage": stage, "error": type(error).__name__ + ": " + str(error)})
        self.receipt["stopReason"] = self.receipt["stopReason"] or "stream-error"

    def drain(self) -> None:
        if self.closed or self.selector_failed:
            return
        try:
            ready = self.selector.select(0)
        except Exception as error:
            self.stream_error("select", error)
            self.selector_failed = True
            return
        for key, _ in ready:
            try:
                chunk = os.read(key.fileobj.fileno(), 65536)
            except BlockingIOError:
                continue
            except Exception as error:
                self.stream_error("read-" + key.data, error)
                try:
                    self.selector.unregister(key.fileobj)
                except Exception as unregister_error:
                    self.stream_error("unregister", unregister_error)
                    self.selector_failed = True
                continue
            if not chunk:
                try:
                    self.selector.unregister(key.fileobj)
                except Exception as error:
                    self.stream_error("unregister", error)
                    self.selector_failed = True
                continue
            self.receipt["observedBytes"] += len(chunk)
            remaining = max(0, self.receipt["maximumCombinedBytes"] - self.receipt["retainedBytes"])
            kept = chunk[:remaining]
            self.streams[key.data].extend(kept)
            self.receipt["retainedBytes"] += len(kept)
            if len(kept) != len(chunk) and self.receipt["stopReason"] is None:
                self.receipt["stopReason"] = "output-limit"

    def poll(self) -> int | None:
        if self.process is None:
            return None
        if self.reap_deferred:
            return self.process.returncode
        code = self.process.poll()
        if code is not None and self.receipt["exitCode"] is None:
            self.receipt.update(exitCode=code, exitObservedAfterSeconds=time.monotonic() - self.started)
        return code

    def signal(self, sig: signal.Signals, *, group: bool = False) -> bool:
        if self.process is None or self.receipt["signalErrors"]:
            return False
        try:
            if group:
                os.killpg(self.process.pid, sig)
            else:
                os.kill(self.process.pid, sig)
            self.receipt["signals"].append({"signal": sig.name, "target": "owned-group" if group else "owned-process",
                                            "afterSeconds": time.monotonic() - self.started})
            return True
        except ProcessLookupError:
            return False
        except PermissionError as error:
            self.receipt["signalErrors"].append({"signal": sig.name, "errno": error.errno,
                                                "target": "owned-group" if group else "owned-process"})
            self.receipt["cleanupFailed"] = True
            return False

    def close(self) -> None:
        if self.closed:
            return
        self.drain()
        if self.process is not None:
            for pipe in (self.process.stdout, self.process.stderr):
                try:
                    pipe.close()
                except Exception as error:
                    self.stream_error("close-pipe", error)
        try:
            self.selector.close()
        except Exception as error:
            self.stream_error("close-selector", error)
        self.closed = True
        self.receipt["elapsedSeconds"] = time.monotonic() - self.started
        if self.receipt["cleanupFailed"]:
            self.receipt["status"] = "cleanup-incomplete"
        elif self.receipt["status"] != "spawn-error":
            self.receipt["status"] = self.receipt["stopReason"] or ("completed" if self.receipt["exitCode"] == 0 else "nonzero")


def preserve_command(output: Path, name: str, receipt: dict, streams: dict, *, xml: bool = False) -> dict:
    receipt["files"] = {}
    for stream in ("stdout", "stderr"):
        data = bytes(streams[stream])
        filename = name + "." + stream + (".xml" if xml and stream == "stdout" else ".txt")
        with (output / filename).open("xb") as handle:
            handle.write(data)
        receipt["files"][stream] = {"name": filename, "bytes": len(data), "sha256": digest(data)}
    write_json(output / (name + ".json"), receipt)
    return receipt


def trace_inventory(root: Path, *, limit: int = TRACE_LIMIT, maximum_entries: int = TRACE_ENTRIES) -> list[tuple[Path, os.stat_result]]:
    if not root.exists():
        raise EvidenceError("Trace package does not exist")
    entries = []
    total = 0
    pending = [root]
    while pending:
        path = pending.pop()
        if path.resolve(strict=True) != path:
            raise EvidenceError("Trace package path resolves through a symlink")
        info = path.lstat()
        if stat.S_ISLNK(info.st_mode) or not (stat.S_ISREG(info.st_mode) or stat.S_ISDIR(info.st_mode)):
            raise EvidenceError("Trace package contains a symlink or nonregular entry")
        if len(path.relative_to(root.parent).as_posix().encode("utf-8")) > 4096:
            raise EvidenceError("Trace package path bound exceeded")
        entries.append((path, info))
        if len(entries) > maximum_entries:
            raise EvidenceError("Trace package entry bound exceeded")
        if stat.S_ISDIR(info.st_mode):
            # scandir entries are counted before recursion; never follow links.
            with os.scandir(path) as children:
                for child in children:
                    pending.append(Path(child.path))
                    if len(pending) + len(entries) > maximum_entries:
                        raise EvidenceError("Trace package entry bound exceeded")
        else:
            total += info.st_size
            if total > limit:
                raise EvidenceError("Trace package uncompressed-byte bound exceeded")
    if not stat.S_ISDIR(entries[0][1].st_mode):
        raise EvidenceError("Expected a trace package directory")
    return sorted(entries, key=lambda entry: entry[0].as_posix())


def package_trace(trace: Path, output: Path, work: Path, *, limit: int = TRACE_LIMIT,
                  maximum_entries: int = TRACE_ENTRIES) -> dict:
    result = {"status": "unavailable", "maximumUncompressedBytes": limit, "maximumEntries": maximum_entries,
              "archive": None, "entries": []}
    try:
        entries = trace_inventory(trace, limit=limit, maximum_entries=maximum_entries)
        pending = work / "recording.trace.zip.pending"
        total = 0
        with zipfile.ZipFile(pending, mode="x", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
            for path, expected in entries:
                name = path.relative_to(trace.parent).as_posix()
                if stat.S_ISDIR(expected.st_mode):
                    archive.writestr(name + "/", b"")
                    result["entries"].append({"path": name + "/", "kind": "directory", "bytes": 0})
                    continue
                descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
                try:
                    before = os.fstat(descriptor)
                    if (not stat.S_ISREG(before.st_mode) or (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns)
                            != (expected.st_dev, expected.st_ino, expected.st_size, expected.st_mtime_ns)):
                        raise EvidenceError("Trace entry changed before archiving")
                    hashed = hashlib.sha256()
                    count = 0
                    with archive.open(name, "w") as target:
                        while True:
                            chunk = os.read(descriptor, 65536)
                            if not chunk:
                                break
                            count += len(chunk)
                            total += len(chunk)
                            if total > limit or count > expected.st_size:
                                raise EvidenceError("Trace grew beyond the validated archive bound")
                            target.write(chunk)
                            hashed.update(chunk)
                    after = os.fstat(descriptor)
                    if count != expected.st_size or (after.st_size, after.st_mtime_ns) != (before.st_size, before.st_mtime_ns):
                        raise EvidenceError("Trace entry changed while archiving")
                    result["entries"].append({"path": name, "kind": "file", "bytes": count, "sha256": hashed.hexdigest(),
                                               "crc32": archive.getinfo(name).CRC})
                finally:
                    os.close(descriptor)
        after = trace_inventory(trace, limit=limit, maximum_entries=maximum_entries)
        fingerprint = lambda rows: [(str(p), s.st_dev, s.st_ino, s.st_mode, s.st_size, s.st_mtime_ns) for p, s in rows]
        if fingerprint(entries) != fingerprint(after):
            raise EvidenceError("Trace package changed while archiving")
        with zipfile.ZipFile(pending) as verification:
            if verification.testzip() is not None:
                raise EvidenceError("Trace archive CRC verification failed")
        final = output / "recording.trace.zip"
        os.link(pending, final)
        pending.unlink()
        hashed = hashlib.sha256()
        with final.open("rb") as handle:
            for chunk in iter(lambda: handle.read(65536), b""):
                hashed.update(chunk)
        result.update(status="packaged", uncompressedBytes=total, entryCount=len(entries),
                      crcVerified=True,
                      archive={"name": final.name, "bytes": final.stat().st_size, "sha256": hashed.hexdigest()})
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        result.update(status="rejected", error=str(error))
    return result


def run(staged: Path, output: Path, helper: Path, *, observer=None) -> dict:
    reserved = ["orchestration.json", "orchestration-scope.json", "helper-prepared.json",
                "helper-prepared.json.pending", "startup-run.json", "startup-run.json.pending",
                "trace-package.json", "recording.trace.zip"]
    for name in ("helper", "record", "export-toc", "export-processes", "export-tables"):
        reserved.extend((name + ".json", name + ".stdout.txt", name + ".stdout.xml", name + ".stderr.txt"))
    if any((output / name).exists() or (output / name).is_symlink() for name in reserved):
        raise EvidenceError("A reserved D20 output already exists")
    work = output.parent / "work"
    work.mkdir(exist_ok=False)
    trace = work / "recording.trace"
    nonce = str(uuid.uuid4()).upper()
    notification = "app.lemulip.d20.recording." + nonce
    helper_hash = digest(read_regular(helper, 64 * 1024 * 1024))
    env = dict(os.environ, PAGER="cat", MANPAGER="cat", TERM="dumb")
    report = {"schema": 1, "diagnostic": "D20-system-trace-startup", "nonce": nonce,
              "recordingNotificationName": notification, "stagedPath": str(staged), "outputPath": str(output),
              "helperExecutablePath": str(helper), "helperExecutableSHA256": helper_hash,
              "architecture": platform.machine(), "commands": {}, "errors": [],
              "recordingComplete": False, "startupComplete": False, "exportsComplete": False,
              "tracePackageComplete": False, "activationCalibration": "unproven",
              "activationRouteCoverageEstablished": False, "ipcRequestChainEstablished": False,
              "nativeInputExecuted": False, "settingsChanged": False, "C12": "HOLD", "releaseReady": False,
              "traceClockEpochAssumedFromNotification": False,
              "bounds": {"helperSeconds": HELPER_TIMEOUT, "helperAbortGraceSeconds": HELPER_ABORT_GRACE,
                         "preparedSeconds": PREPARED_TIMEOUT, "recordingSeconds": 30,
                         "recorderWallSeconds": RECORD_WALL_TIMEOUT, "streamBytes": STREAM_LIMIT}}
    commit_file = output / "build/experiment-commit.txt"
    commit = read_regular(commit_file, 128).decode("ascii").strip()
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise EvidenceError("Missing complete experiment commit identity")
    report["experimentCommit"] = commit
    tree = read_regular(output / "build/experiment-tree.txt", 128).decode("ascii").strip()
    if not re.fullmatch(r"[0-9a-f]{40}", tree):
        raise EvidenceError("Missing complete experiment tree identity")
    report["experimentTree"] = tree
    write_json(output / "orchestration-scope.json", report)
    helper_command = (str(helper), "--staged", str(staged), "--output", str(output),
                      "--recording-notification", notification)
    helper_process = MonitoredCommand(helper_command, cwd=staged, env=env)
    recorder = None
    prepared = None
    prepared_bytes = b""
    startup = None
    helper_abort_at = None
    recorder_interrupt_at = None
    recorder_term_at = None
    record_covered_helper = False
    record_early_exit = False
    record_force_used = False
    last_trace_check = 0.0
    fatal = False

    def abort_helper(reason: str) -> None:
        nonlocal helper_abort_at
        if helper_abort_at is None and helper_process.process is not None and helper_process.poll() is None:
            helper_abort_at = time.monotonic()
            helper_process.receipt["stopReason"] = helper_process.receipt["stopReason"] or reason
            helper_process.signal(signal.SIGTERM)

    def stop_recorder(reason: str) -> None:
        nonlocal recorder_interrupt_at
        if recorder is not None and recorder.process is not None and recorder_interrupt_at is None:
            if recorder.poll() is None:
                recorder_interrupt_at = time.monotonic()
                if reason != "helper-completed":
                    recorder.receipt["stopReason"] = recorder.receipt["stopReason"] or reason
                recorder.receipt["interruptReason"] = reason
                recorder.signal(signal.SIGINT)

    try:
        while True:
            now = time.monotonic()
            helper_process.drain()
            helper_code = helper_process.poll()
            if recorder is not None:
                recorder.drain()
            if helper_process.process is None:
                report["errors"].append("helper-spawn-error")
                break
            if prepared is None and not fatal:
                prepared_path = output / "helper-prepared.json"
                if prepared_path.exists():
                    try:
                        candidate, candidate_bytes = read_object(prepared_path, 262144)
                        validate_prepared(candidate, pid=helper_process.process.pid, helper=helper,
                                          helper_hash=helper_hash, staged=staged, output=output,
                                          notification=notification, nonce=nonce)
                        if helper_code is not None:
                            raise EvidenceError("Helper exited before the recording was launched")
                        prepared, prepared_bytes = candidate, candidate_bytes
                        report["preparedReceipt"] = {"name": prepared_path.name, "bytes": len(prepared_bytes),
                                                       "sha256": digest(prepared_bytes)}
                        recorder = MonitoredCommand(recording_command(trace, notification), cwd=work, env=env)
                        if recorder.process is None:
                            report["errors"].append("recorder-spawn-error")
                            fatal = True
                        elif observer is not None:
                            observer.attach(recorder, helper_started=helper_process.started,
                                            prepared=prepared, cwd=work, env=env)
                    except (OSError, ValueError) as error:
                        report["errors"].append(str(error))
                        fatal = True
                elif now - helper_process.started >= PREPARED_TIMEOUT:
                    report["errors"].append("helper-prepared-timeout")
                    fatal = True
                if fatal:
                    abort_helper("preparation-or-recording-failure")
            if helper_process.receipt["stopReason"] in ("output-limit", "stream-error"):
                fatal = True
                stop_recorder("helper-" + helper_process.receipt["stopReason"])
                abort_helper(helper_process.receipt["stopReason"])
            if helper_code is not None:
                if startup is None:
                    startup = {}
                    try:
                        startup, raw = read_object(output / "startup-run.json", 32 * 1024 * 1024)
                        report["startupReceipt"] = {"name": "startup-run.json", "bytes": len(raw), "sha256": digest(raw)}
                        if prepared is None:
                            raise EvidenceError("No valid prepared receipt")
                        validate_startup(startup, prepared, prepared_bytes)
                        if helper_code != 0 or helper_process.receipt["stopReason"] is not None:
                            raise EvidenceError("Helper process did not exit successfully without interruption")
                        report["startupComplete"] = True
                    except (OSError, ValueError) as error:
                        report["errors"].append(str(error))
                if recorder is not None and recorder_interrupt_at is None:
                    if recorder.poll() is None:
                        record_covered_helper = report["startupComplete"] and not record_early_exit
                        stop_recorder("helper-completed")
                    else:
                        record_early_exit = True
            elif now - helper_process.started >= HELPER_TIMEOUT:
                abort_helper("helper-wall-timeout")
                stop_recorder("helper-wall-timeout")
            if helper_abort_at is not None and helper_code is None and now - helper_abort_at >= HELPER_ABORT_GRACE:
                helper_process.receipt["cleanupFailed"] = True
                report["errors"].append("helper-cleanup-unresolved-after-cooperative-abort")
                stop_recorder("helper-cleanup-unresolved")
            if recorder is not None and recorder.process is not None:
                # During forced group cleanup retain the unreaped leader until
                # the group KILL attempt; closed pipes do not bypass escalation.
                recorder_code = recorder.receipt["exitCode"] if recorder_term_at is not None else recorder.poll()
                if recorder_code is not None and helper_code is None:
                    record_early_exit = True
                if recorder_code is None and recorder_term_at is None:
                    if recorder.receipt["stopReason"] in ("output-limit", "stream-error"):
                        stop_recorder(recorder.receipt["stopReason"])
                    if now - recorder.started >= RECORD_WALL_TIMEOUT:
                        stop_recorder("record-wall-timeout")
                    if now - last_trace_check >= 1:
                        last_trace_check = now
                        if trace.exists():
                            try:
                                trace_inventory(trace)
                            except (OSError, ValueError) as error:
                                recorder.receipt["traceBoundError"] = str(error)
                                stop_recorder("trace-package-bound-or-type-failure")
                    if recorder_interrupt_at is not None and now - recorder_interrupt_at >= RECORD_INTERRUPT_GRACE:
                        record_force_used = True
                        recorder_term_at = now
                        recorder.receipt["stopReason"] = recorder.receipt["stopReason"] or "recorder-graceful-stop-timeout"
                        recorder.signal(signal.SIGTERM, group=True)
                if recorder_term_at is not None and now - recorder_term_at >= 2:
                    if not recorder.receipt.get("groupEscalationAttempted"):
                        recorder.receipt["groupEscalationAttempted"] = True
                        recorder.signal(signal.SIGKILL, group=True)
                        recorder.receipt["groupKillAfterSeconds"] = time.monotonic() - recorder.started
                    recorder_code = recorder.poll()
                    if recorder_code is None and now - recorder_term_at >= 4:
                        recorder.receipt["cleanupFailed"] = True
                if recorder.receipt["signalErrors"] and recorder.poll() is None:
                    # No group is signalled again after a permission failure.
                    if now - recorder.started >= RECORD_WALL_TIMEOUT + RECORD_INTERRUPT_GRACE + 4:
                        recorder.receipt["cleanupFailed"] = True
                recorder_finished = recorder.poll() is not None if recorder_term_at is None else recorder_code is not None
                recorder_unresolved = recorder.receipt["cleanupFailed"] and now - recorder.started >= RECORD_WALL_TIMEOUT + RECORD_INTERRUPT_GRACE + 4
            else:
                recorder_finished = True
                recorder_unresolved = False
            helper_finished = helper_code is not None or helper_process.receipt["cleanupFailed"]
            if observer is not None:
                # Existing helper/recorder stop decisions above take priority;
                # this nonblocking tick cannot postpone their signal boundary.
                observer.tick(helper_running=not helper_finished,
                              recorder_stopping=recorder_interrupt_at is not None)
            if helper_finished and (recorder_finished or recorder_unresolved) and (observer is None or observer.done):
                break
            time.sleep(0.02)
        # Drain bytes already buffered after child exit, without waiting forever
        # for inherited pipes held by an unknown descendant.
        drain_deadline = time.monotonic() + 2
        commands = [command for command in (helper_process, recorder) if command is not None]
        while any(command.selector.get_map() for command in commands) and time.monotonic() < drain_deadline:
            for command in commands:
                command.drain()
            time.sleep(0.01)
        for command in commands:
            command.receipt["inheritedStreamsStillOpen"] = bool(command.selector.get_map())
            if command.receipt["inheritedStreamsStillOpen"]:
                command.receipt["cleanupFailed"] = True
        helper_process.receipt["ownedApplicationCleanupResolved"] = (
            helper_process.process is None or helper_cleanup_resolved(startup, helper_process.process.pid, nonce))
        if not helper_process.receipt["ownedApplicationCleanupResolved"]:
            helper_process.receipt["cleanupFailed"] = True
        if recorder is not None and recorder.process is not None:
            recorder.poll()
            if recorder.receipt["exitCode"] is not None:
                snapshot = group_snapshot(recorder.process.pid, cwd=work, env=env)
                recorder.receipt["groupSnapshot"] = snapshot
                recorder.receipt["cleanupFailed"] = (snapshot["status"] != "no-live-group-members-observed"
                                                       or recorder.receipt["inheritedStreamsStillOpen"])
            else:
                recorder.receipt["cleanupFailed"] = True
            report["recordingComplete"] = (record_covered_helper and not record_early_exit and not record_force_used
                                             and recorder.receipt["exitCode"] == 0
                                             and recorder.receipt["stopReason"] is None
                                             and not recorder.receipt["cleanupFailed"]
                                             and not recorder.receipt["signalErrors"])
        report["recorderExitedBeforeHelperCompletion"] = record_early_exit
        report["recorderForcedCleanupUsed"] = record_force_used
    except Exception as error:
        # An unexpected parser/pipe/filesystem error cannot bypass owned cleanup.
        # Never signal application PIDs or the helper's group here.
        report["errors"].append(type(error).__name__ + ": " + str(error))
        report["recordingComplete"] = False
        abort_helper("orchestration-exception")
        stop_recorder("orchestration-exception")
        observer_cleanup_fault = False
        if observer is not None:
            try:
                observer.cancel("orchestration-exception")
            except Exception as observer_error:
                report["errors"].append("Observer cancellation: " + type(observer_error).__name__ + ": " + str(observer_error))
                observer_cleanup_fault = True
        end = time.monotonic() + HELPER_ABORT_GRACE
        force_at = None
        force_killed = False
        while time.monotonic() < end:
            now = time.monotonic()
            helper_process.drain()
            helper_done = helper_process.process is None or helper_process.poll() is not None
            record_done = recorder is None or recorder.process is None
            if not record_done:
                recorder.drain()
                if force_at is None:
                    record_done = recorder.poll() is not None
                    if not record_done and recorder_interrupt_at is not None and now - recorder_interrupt_at >= RECORD_INTERRUPT_GRACE:
                        force_at = now
                        recorder.signal(signal.SIGTERM, group=True)
                elif now - force_at >= 2:
                    if not force_killed:
                        recorder.signal(signal.SIGKILL, group=True)
                        force_killed = True
                    record_done = recorder.poll() is not None
            if observer is not None and not observer_cleanup_fault:
                try:
                    observer.tick(helper_running=False, recorder_stopping=True)
                except Exception as observer_error:
                    report["errors"].append("Observer cleanup tick: " + type(observer_error).__name__ + ": " + str(observer_error))
                    observer_cleanup_fault = True
            if helper_done and record_done and (observer is None or observer.done or observer_cleanup_fault):
                break
            time.sleep(0.02)
        # Exceptional completion is not promoted to normal cleanup without the
        # ordinary final-receipt validation; no exports or archive follow.
        helper_process.receipt["cleanupFailed"] = True
        if recorder is not None:
            recorder.receipt["cleanupFailed"] = True
    finally:
        if observer is not None:
            # The recorder has already received its original stop request.
            # Exceptional observer cleanup never precedes or delays that signal.
            try:
                observer.finish()
            except Exception as error:
                report["errors"].append("Observer finalization: " + type(error).__name__ + ": " + str(error))
                report["recordingComplete"] = False
                helper_process.receipt["cleanupFailed"] = True
                if recorder is not None:
                    recorder.receipt["cleanupFailed"] = True
        # Close both transports even if a later evidence write fails.
        for command in (helper_process, recorder):
            if command is not None:
                command.close()
        for name, command in (("helper", helper_process), ("record", recorder)):
            if command is not None:
                report["commands"][name] = command.receipt
                try:
                    preserve_command(output, name, command.receipt, command.streams)
                except OSError as error:
                    command.receipt["evidenceWriteError"] = str(error)
                    command.receipt["cleanupFailed"] = True
                    report["errors"].append("Could not preserve " + name + " transport: " + str(error))
    apply_final_transport_gates(report)
    cleanup_ok = all(not command["cleanupFailed"] for command in report["commands"].values())
    report["cleanupComplete"] = cleanup_ok
    if report["recordingComplete"] and report["startupComplete"] and cleanup_ok:
        exports = (("export-toc", None, 30, STREAM_LIMIT),)
        try:
            name, xpath, timeout, limit = exports[0]
            receipt, data = capture(export_command(trace, xpath=xpath), cwd=work, env=env, timeout=timeout, limit=limit)
            report["commands"][name] = preserve_command(output, name, receipt, data, xml=True)
            if receipt["status"] != "completed" or receipt["cleanupFailed"]:
                raise EvidenceError("TOC export did not complete")
            toc = parse_toc(data["stdout"])
            report["toc"] = toc
            for name, xpath, limit in (("export-processes", PROCESSES_XPATH, 32 * 1024 * 1024),
                                       ("export-tables", toc["tablesXPath"], 64 * 1024 * 1024)):
                if xpath is None:
                    raise EvidenceError("The actual TOC contains no data tables")
                receipt, data = capture(export_command(trace, xpath=xpath), cwd=work, env=env, timeout=45, limit=limit)
                report["commands"][name] = preserve_command(output, name, receipt, data, xml=True)
                if receipt["status"] != "completed" or receipt["cleanupFailed"]:
                    raise EvidenceError(name + " did not complete")
                report.setdefault("exportEntities", {})[name] = inspect_query_export(
                    data["stdout"], kind="processes" if name == "export-processes" else "tables", toc=toc)
            report["exportsComplete"] = True
        except (OSError, ValueError) as error:
            report["errors"].append(str(error))
    cleanup_ok = all(not command["cleanupFailed"] for command in report["commands"].values())
    report["cleanupComplete"] = cleanup_ok
    if cleanup_ok:
        package = package_trace(trace, output, work)
    else:
        package = {"status": "skipped-cleanup-incomplete", "archive": None,
                   "maximumUncompressedBytes": TRACE_LIMIT, "maximumEntries": TRACE_ENTRIES}
    write_json(output / "trace-package.json", package)
    report["tracePackageComplete"] = package["status"] == "packaged"
    report["status"] = ("recording-export-complete-activation-unproven"
                        if all(report[key] for key in ("recordingComplete", "startupComplete", "exportsComplete",
                                                       "tracePackageComplete", "cleanupComplete"))
                        else "evidence-incomplete")
    write_json(output / "orchestration.json", report)
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--staged", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--helper", required=True, type=Path)
    args = parser.parse_args()
    if platform.system() != "Darwin":
        parser.error("Native recording requires macOS")
    for name in ("staged", "output", "helper"):
        path = getattr(args, name)
        if not path.is_absolute() or path.resolve(strict=True) != path:
            parser.error("Require existing canonical absolute paths")
    if not args.staged.is_dir() or not args.output.is_dir() or not args.helper.is_file():
        parser.error("Require staged/output directories and the built helper file")
    if not (args.output / "build").is_dir() or not (args.output / "sources").is_dir():
        parser.error("Build/source provenance must precede orchestration")
    report = run(args.staged, args.output, args.helper)
    print(report["status"], flush=True)
    return 0 if report["status"] == "recording-export-complete-activation-unproven" else 1


if __name__ == "__main__":
    raise SystemExit(main())
