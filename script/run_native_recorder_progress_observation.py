#!/usr/bin/env python3
"""D24: one owned sampler-of-sampler observation, with finite PID leases.

The normal command line has fixed Apple tools and bounds. TestHooks is an
explicitly synthetic portable-test seam; it never produces native evidence.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import errno
import json
import math
import os
from pathlib import Path
import platform
import re
import signal
import stat
import subprocess
import sys
import time
import uuid

from collect_native_trace_capabilities import write_json
import run_native_system_trace_startup as startup
import run_native_recorder_startup_observation as observation


EvidenceError = startup.EvidenceError
STREAM_LIMIT = 2 * 1024 * 1024
PS_LIMIT = 65536
REPORT_LIMIT = 8 * 1024 * 1024
PS_FORMAT = observation.PS_FORMAT
SAMPLE_BUDGET = 4.0
CLEANUP_RESERVE = 0.5
TERM_GRACE = 0.25
HELPER_WINDOW = 15.0
HELPER_HARD_END = 17.0
OBSERVATION_CUTOFF = 14.0
OBSERVATION_TRIGGER = 3.0
HEX40 = re.compile(r"[0-9a-f]{40}")
HEX64 = re.compile(r"[0-9a-f]{64}")


def require(value, message):
    if not value:
        raise EvidenceError(message)


def clock():
    return observation.clock()


def identity(raw):
    return {"bytes": len(raw), "sha256": startup.digest(raw)}


def read_regular(path, limit):
    """A rejected FIFO/device cannot block even before the regular-file check."""
    path = Path(path)
    descriptor = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW | os.O_CLOEXEC)
    try:
        before = os.fstat(descriptor)
        require(stat.S_ISREG(before.st_mode) and 0 <= before.st_size <= limit,
                "Receipt is not a bounded regular file: "+path.name)
        chunks, remaining = [], limit+1
        while remaining:
            chunk = os.read(descriptor, min(65536, remaining))
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        raw = b"".join(chunks)
        after = os.fstat(descriptor)
        require(len(raw) == before.st_size and len(raw) <= limit
                and (before.st_size, before.st_mtime_ns) == (after.st_size, after.st_mtime_ns),
                "Receipt changed or exceeded its bound: "+path.name)
        return raw
    finally:
        os.close(descriptor)


@dataclass(frozen=True)
class TestHooks:
    factory: object = None
    scale: float = 0.1
    skip_manual_preflight: bool = True


def waitid_preflight():
    """Prove peek-then-wait on a tiny directly owned Python child."""
    required = ("waitid", "P_PID", "WEXITED", "WNOHANG", "WNOWAIT")
    require(all(hasattr(os, name) for name in required), "Non-reaping waitid is unavailable")
    child = subprocess.Popen((sys.executable, "-c", "raise SystemExit(23)"),
                             stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL, start_new_session=True)
    try:
        deadline = time.monotonic() + 2
        observed = None
        while time.monotonic() < deadline:
            observed = os.waitid(os.P_PID, child.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)
            if observed is not None:
                break
            time.sleep(.005)
        require(observed is not None and observed.si_pid == child.pid
                and observed.si_code == os.CLD_EXITED and observed.si_status == 23
                and child.returncode is None, "Non-reaping waitid capability probe failed")
        again = os.waitid(os.P_PID, child.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)
        require(again is not None and again.si_pid == child.pid and again.si_status == 23,
                "waitid peek unexpectedly consumed child status")
        require(child.wait(timeout=1) == 23, "waitid child collection disagreed")
        return {"available": True, "peekDidNotReap": True, "exitCode": 23,
                "pythonVersion": platform.python_version()}
    except (OSError, AttributeError, NotImplementedError, subprocess.TimeoutExpired) as error:
        raise EvidenceError("Non-reaping waitid capability probe failed") from error
    finally:
        if child.returncode is None:
            child.kill()
            child.wait(timeout=1)


class OwnedCommand:
    """A direct child whose operation and PID collection are separate events."""
    def __init__(self, name, argv, *, cwd, env, budget, limit=STREAM_LIMIT,
                 reserve=CLEANUP_RESERVE, term_grace=TERM_GRACE, factory=None):
        self.name = name
        self.before_spawn = clock()
        self.transport = (factory(name, tuple(argv), cwd=cwd, env=env, limit=limit)
                          if factory is not None else
                          startup.MonitoredCommand(tuple(argv), cwd=cwd, env=env, limit=limit))
        self.transport.reap_deferred = True
        self.receipt = self.transport.receipt
        self.pid = self.transport.process.pid if self.transport.process is not None else None
        self.started = self.transport.started
        self.deadline = self.started + budget
        self.normal_deadline = self.deadline - reserve
        self.term_grace = term_grace
        self.term_at = None
        self.kill_sent = False
        self.terminal = False
        self.operation_done = self.pid is None
        self.collected = False
        self.pid_actions_revoked = False
        self.last_bytes = 0
        self.receipt.update(intendedArgv=list(argv), clockBeforeSpawn=self.before_spawn,
                            clockAtSpawn=clock(), totalBudgetSeconds=budget,
                            normalOperationBudgetSeconds=budget-reserve,
                            pidLeaseAcquired=self.pid is not None, pidLeaseReleased=False,
                            pidLeaseLost=False, pidDirectedActionsRevoked=False,
                            exitObservedWithoutReap=False, operationTerminalClock=None,
                            operationDoneClock=None, operationElapsedSeconds=None,
                            collectedClock=None, inheritedStreamsStillOpen=False,
                            cleanupFailureReasons=[], streamProgress=[])

    def peek(self):
        if self.pid is None:
            return None
        if self.terminal or self.collected or self.pid_actions_revoked:
            return self.receipt.get("exitCode")
        try:
            result = os.waitid(os.P_PID, self.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)
        except (OSError, AttributeError) as error:
            if isinstance(error, ChildProcessError) or getattr(error, "errno", None) == errno.ECHILD:
                # ECHILD invalidates the ownership premise. No later cleanup
                # may address this numeric PID/PGID, which may already be reused.
                self.pid_actions_revoked = True
                self.operation_done = True
                self.receipt.update(pidLeaseLost=True, pidDirectedActionsRevoked=True,
                                    lostLeaseClock=clock(), cleanupFailed=True,
                                    stopReason="owned-child-lease-lost")
                self.receipt["cleanupFailureReasons"].append("owned-child-no-longer-waitable")
            raise EvidenceError(self.name + ": owned-child non-reaping peek failed") from error
        if result is None:
            return None
        require(result.si_pid == self.pid, self.name + ": waitid returned a foreign PID")
        require(result.si_code in (os.CLD_EXITED, os.CLD_KILLED, os.CLD_DUMPED),
                self.name + ": waitid returned an unsupported event")
        code = result.si_status if result.si_code == os.CLD_EXITED else -result.si_status
        self.terminal = True
        self.receipt.update(exitCode=code, exitObservedWithoutReap=True,
                            exitObservedAfterSeconds=time.monotonic()-self.started,
                            operationTerminalClock=clock(), waitidCode=result.si_code,
                            waitidStatus=result.si_status)
        return code

    def signal(self, sig, *, group=False):
        if self.pid is None or self.pid_actions_revoked or self.collected:
            return False
        return self.transport.signal(sig, group=group)

    def stop(self, reason):
        if self.pid is None or self.collected or self.pid_actions_revoked or self.term_at is not None:
            return
        self.receipt["stopReason"] = self.receipt["stopReason"] or reason
        self.term_at = time.monotonic()
        self.receipt.update(stopRequestedClock=clock(),
                            normalDeadlineOvershootSeconds=max(0.0, self.term_at-self.normal_deadline))
        # The unreaped direct child reserves its PID/PGID even if it has exited.
        self.signal(signal.SIGTERM, group=True)

    def tick(self):
        if self.pid is None or self.collected or self.pid_actions_revoked:
            return
        self.transport.drain()
        total = self.receipt["observedBytes"]
        if total != self.last_bytes:
            progress = self.receipt["streamProgress"]
            if len(progress) < 256:
                progress.append({"clock": clock(), "observedBytes": total,
                                 "stdoutBytes": len(self.transport.streams["stdout"]),
                                 "stderrBytes": len(self.transport.streams["stderr"])})
            else:
                self.receipt["streamProgressTruncated"] = True
            self.last_bytes = total
        self.peek()
        now = time.monotonic()
        streams_open = bool(self.transport.selector.get_map())
        if self.terminal and not streams_open and (self.term_at is None or self.kill_sent):
            self.operation_done = True
        if not self.operation_done:
            if self.receipt["stopReason"] in ("stream-error", "output-limit"):
                self.stop(self.receipt["stopReason"])
            if now >= self.normal_deadline:
                self.stop("command-budget")
            if self.term_at is not None and not self.kill_sent and now-self.term_at >= self.term_grace:
                # Do not let an exited leader or closed pipes hide descendants
                # that survived TERM in this still-owned process group.
                self.signal(signal.SIGKILL, group=True)
                self.kill_sent = True
                self.peek()
                if self.terminal and not self.transport.selector.get_map():
                    self.operation_done = True
            if now >= self.deadline:
                if not self.terminal or self.transport.selector.get_map():
                    self.receipt["cleanupFailed"] = True
                    if "child-or-streams-exceeded-total-budget" not in self.receipt["cleanupFailureReasons"]:
                        self.receipt["cleanupFailureReasons"].append("child-or-streams-exceeded-total-budget")
                self.operation_done = True
        self.receipt["inheritedStreamsStillOpen"] = bool(self.transport.selector.get_map())
        if self.operation_done and self.receipt["operationDoneClock"] is None:
            overshoot = max(0.0, time.monotonic()-self.deadline)
            self.receipt.update(operationDoneClock=clock(),
                                operationElapsedSeconds=time.monotonic()-self.started,
                                totalDeadlineOvershootSeconds=overshoot,
                                completionObservedWithinTotalBudget=overshoot == 0)
            if overshoot:
                self.receipt["cleanupFailed"] = True
                self.receipt["cleanupFailureReasons"].append("completion-not-observed-within-total-budget")

    def collect(self):
        require(self.pid is not None and self.terminal and not self.transport.selector.get_map(),
                self.name + ": cannot collect before terminal/closed streams")
        require(not self.collected, self.name + ": PID lease already released")
        require(not self.pid_actions_revoked, self.name + ": PID lease was lost before collection")
        # Collection can consume the PID before a subsequent invariant raises.
        # Revoke every signal/peek permission before crossing that boundary.
        self.collected = True
        self.pid_actions_revoked = True
        self.receipt.update(pidDirectedActionsRevoked=True, collectionStartedClock=clock())
        self.transport.reap_deferred = False
        code = self.transport.poll()
        self.receipt.update(pidLeaseReleased=code is not None, collectedClock=clock())
        require(code == self.receipt["exitCode"], self.name + ": collected exit differs from peek")
        return code

    def close(self):
        self.transport.close()
        self.receipt["ownershipElapsedSeconds"] = self.receipt.get("elapsedSeconds")
        if self.receipt["operationElapsedSeconds"] is not None:
            self.receipt["elapsedSeconds"] = self.receipt["operationElapsedSeconds"]


def classify_sample_stderr(raw, *, target_pid):
    require(len(raw) <= STREAM_LIMIT and b"\0" not in raw, "Sampler stream is invalid or oversized")
    expected = ("Sampling process " + str(target_pid)
                + " for 1 second with 10 milliseconds of run time between samples\n").encode("ascii")
    complete_lines = raw.splitlines(keepends=True)
    count = complete_lines.count(expected)
    complete_sampling_lines = [line for line in complete_lines
                               if line.startswith(b"Sampling process ") and line.endswith(b"\n")]
    ambiguous = count > 1 or any(line != expected for line in complete_sampling_lines)
    return {"expectedBannerObserved": count == 1 and not ambiguous,
            "expectedBannerCount": count, "ambiguous": ambiguous,
            "expectedBannerEndByte": sum(map(len, complete_lines[:complete_lines.index(expected)+1])) if count == 1 else None,
            "samplingCompletedMarkerObserved": b"Sampling completed, processing symbols..." in raw,
            "reportWrittenMarkerObserved": b"Sample analysis of process " in raw and b"written to file" in raw,
            "observedTextOnly": True, "bannerEstablishesCapturePhase": False}


def inspect_sampler_report(raw, *, target_pid, target_parent, architecture, tool_identity):
    """Bind a counted system-sampler stack to its PID and native image UUID."""
    require(0 < len(raw) <= REPORT_LIMIT, "Sampler report missing or oversized")
    try:
        text = raw.decode("utf-8")
    except UnicodeError as error:
        raise EvidenceError("Sampler report is not UTF-8") from error
    require("\0" not in text, "Sampler report contains NUL")
    lines = text.splitlines()
    require(lines.count("Call graph:") == lines.count("Binary Images:") == 1,
            "Sampler report has ambiguous graph/image sections")
    graph_at, images_at = lines.index("Call graph:"), lines.index("Binary Images:")
    require(graph_at < images_at, "Sampler report section order is invalid")
    header = "\n".join(lines[:graph_at])
    def field(name):
        values = re.findall(r"^"+re.escape(name)+r":[ \t]*(.*?)[ \t]*$", header, re.M)
        require(len(values) == 1, "Sampler report missing/duplicate " + name)
        return values[0]
    process = re.fullmatch(r"(.+?) \[([0-9]+)\]", field("Process"))
    parent = re.fullmatch(r"(.+?) \[([0-9]+)\]", field("Parent Process"))
    require(process is not None and process[1] == "sample" and int(process[2]) == target_pid,
            "Sampler report PID/name mismatch")
    require(parent is not None and int(parent[2]) == target_parent, "Sampler report parent PID mismatch")
    native_codes = {"arm64": {"ARM64", "ARM64 (Native)", "ARM-64", "ARM-64 (Native)",
                               "ARM64E", "ARM64E (Native)", "ARM-64E", "ARM-64E (Native)"},
                    "x86_64": {"X86-64", "X86-64 (Native)"}}
    code_type = field("Code Type")
    require(code_type in native_codes[architecture], "Sampler report is foreign/translated architecture")
    require(field("Platform") == "macOS" and field("Target Type") == "live task"
            and field("Analysis Tool") == "/usr/bin/sample" and field("Report Version") == "7",
            "Sampler report provenance fields differ")
    load_text = field("Load Address")
    require(re.fullmatch(r"0x[0-9A-Fa-f]+", load_text), "Sampler report invalid load address")
    load_address = int(load_text, 16)
    image_re = re.compile(r"\s*(0x[0-9A-Fa-f]+)\s*-\s*(0x[0-9A-Fa-f]+)\s+\+?([^\s]+)\s+"
                          r"\([^)]*\)\s+<([0-9A-Fa-f-]{36})>\s+(.+?)\s*")
    images = []
    for line in lines[images_at+1:]:
        if not line.strip():
            continue
        match = image_re.fullmatch(line)
        require(match is not None, "Sampler report malformed image row")
        try:
            image_uuid = str(uuid.UUID(match[4])).upper()
        except ValueError as error:
            raise EvidenceError("Sampler report malformed image UUID") from error
        start, end = int(match[1], 16), int(match[2], 16)
        require(start <= end, "Sampler report reversed image range")
        images.append({"name": match[3], "uuid": image_uuid, "start": start, "end": end, "path": match[5]})
    expected_uuids = set(tool_identity["nativeUUIDs"])
    matching = [entry for entry in images if entry["uuid"] in expected_uuids]
    require(len(matching) == 1, "Sampler report missing/duplicate native tool UUID")
    main_image = matching[0]
    require(main_image["name"] == "sample" and main_image["start"] == load_address
            and sum(entry["name"] == "sample" for entry in images) == 1,
            "Sampler report main image identity/load mismatch")
    boundary = next((i for i in range(graph_at+1, images_at+1)
                     if re.match(r"^[ \t]*(?:Total number in stack|Sort by top of stack|Binary Images:)", lines[i])), None)
    require(boundary is not None, "Sampler report has no call-graph boundary")
    frame_re = re.compile(r"[ \t+|!:]*([0-9]+)\s+(.+?)\s+\(in ([^)]+)\)(?:\s+\+\s+([0-9]+))?\s+"
                          r"\[(0x[0-9A-Fa-f]+)\]\s*")
    frames = []
    for line in lines[graph_at+1:boundary]:
        match = frame_re.fullmatch(line)
        if match is None:
            continue
        count, pc = int(match[1]), int(match[5], 16)
        require(count > 0, "Sampler report contains a zero-count frame")
        owners = [entry for entry in images if entry["start"] <= pc <= entry["end"]]
        require(len(owners) == 1 and owners[0]["name"] == match[3],
                "Sampler frame has ambiguous/mismatched image ownership")
        frames.append({"sampleCount": count, "symbol": match[2], "image": match[3],
                       "reportedSymbolOffset": int(match[4]) if match[4] is not None else None,
                       "pc": pc, "imageUUID": owners[0]["uuid"], "line": line})
    require(frames and any(frame["image"] == "sample" and frame["imageUUID"] == main_image["uuid"]
                          for frame in frames), "Sampler report lacks a counted main-tool frame in Call graph")
    return {"pid": target_pid, "parentPID": target_parent, "codeType": code_type,
            "observedHeaderPath": field("Path"), "observedMainImagePath": main_image["path"],
            "pathsAreAdvisory": True, "pathsWereGlobMatched": False,
            "mainImageUUID": main_image["uuid"], "mainLoadAddress": load_address,
            "mainImageRange": {"start": main_image["start"], "end": main_image["end"]},
            "countedFrames": frames, "report": identity(raw),
            "establishesUnperturbedRecorderState": False, "establishesD23KnownFrameContract": False}


SOURCE_NAMES = {
    "NativeRecorderProgressNotify.c", "native_sampler_tool_identity.py",
    "run_native_recorder_progress_observation.py", "test_run_native_recorder_progress_observation.py",
    "run_native_recorder_startup_observation.py", "test_run_native_recorder_startup_observation.py",
    "run_native_system_trace_startup.py", "test_run_native_system_trace_startup.py",
    "collect_native_trace_capabilities.py", "test_collect_native_trace_capabilities.py",
    "privacy_check.py", "native-recorder-progress-observation.yml", "NATIVE_RECORDER_PROGRESS_OBSERVATION.md",
}
COMMON_HELPER_KEYS = (
    "schema", "pid", "ppid", "pgid", "euid", "executablePath", "executableSHA256",
    "machOUUID", "architecture", "nonce", "sourceSHA256", "experimentCommit", "experimentTree",
    "bootUUID", "identityValidated", "translationProbe", "machTimebaseNumer", "machTimebaseDenom",
    "nativeStartClock", "readinessClock", "windowSeconds", "nativeInputExecuted", "settingsChanged",
    "applicationLaunchRequested", "recordingRequested",
)
REGISTRATION_KEYS = ("name", "registered", "registrationStatus", "token",
                     "registrationBeforeClock", "registrationAfterClock")


def canonical_uuid(value):
    try:
        return isinstance(value, str) and str(uuid.UUID(value)).upper() == value
    except (ValueError, AttributeError):
        return False


def integer(value, *, minimum=0):
    return type(value) is int and minimum <= value <= 2**64-1


def native_clock(value, *, numer, denom):
    require(isinstance(value, dict), "Missing native clock")
    for key in ("machAbsoluteBefore", "machAbsoluteAfter", "machContinuousBefore",
                "machContinuousAfter", "wallTimeUnixNS"):
        require(integer(value.get(key)), "Invalid native clock field " + key)
    require(value["machAbsoluteBefore"] <= value["machAbsoluteAfter"]
            and value["machContinuousBefore"] <= value["machContinuousAfter"],
            "Native clock has a reversed bracket")
    uptime = value.get("systemUptime")
    require(type(uptime) in (int, float) and math.isfinite(uptime) and uptime >= 0
            and abs(uptime-value["machAbsoluteBefore"]*numer/denom/1e9) <= .000001,
            "Native uptime does not bind its mach clock")
    return value


def clock_before(first, second):
    return (first["machAbsoluteAfter"] <= second["machAbsoluteBefore"]
            and first["machContinuousAfter"] <= second["machContinuousBefore"])


def validate_ready(value, *, command, provenance, nonce, window=HELPER_WINDOW):
    require(isinstance(value, dict) and value.get("schema") == 1
            and value.get("kind") == "d24-recorder-progress-ready", "Invalid helper ready kind/schema")
    expected = {
        "pid": command.pid, "ppid": os.getpid(), "pgid": command.pid, "euid": os.geteuid(),
        "executablePath": provenance["helper"]["path"],
        "executableSHA256": provenance["helper"]["sha256"],
        "machOUUID": provenance["helper"]["uuid"], "architecture": provenance["architecture"],
        "nonce": nonce, "sourceSHA256": provenance["sourceSHA256"],
        "experimentCommit": provenance["experimentCommit"], "experimentTree": provenance["experimentTree"],
        "windowSeconds": window,
    }
    require(all(value.get(key) == entry for key, entry in expected.items()),
            "Helper ready does not bind the owned process/build/window")
    require(value.get("identityValidated") is True and canonical_uuid(value.get("bootUUID")),
            "Helper native/boot identity is unqualified")
    require(all(value.get(key) is False for key in ("nativeInputExecuted", "settingsChanged",
                                                  "applicationLaunchRequested", "recordingRequested")),
            "Helper declares an out-of-scope side effect")
    probe = value.get("translationProbe", {})
    require(probe == {"returnCode": 0, "errno": 0, "value": 0}
            or probe == {"returnCode": -1, "errno": errno.ENOENT, "value": None},
            "Helper translation state is unqualified")
    numer, denom = value.get("machTimebaseNumer"), value.get("machTimebaseDenom")
    require(integer(numer, minimum=1) and integer(denom, minimum=1), "Invalid native timebase")
    start = native_clock(value.get("nativeStartClock"), numer=numer, denom=denom)
    readiness = native_clock(value.get("readinessClock"), numer=numer, denom=denom)
    notification = value.get("notification", {})
    require(notification.get("name") == "app.lemulip.d24.recording."+nonce
            and notification.get("registered") is True and notification.get("registrationStatus") == 0
            and integer(notification.get("token")), "Helper notification registration is unqualified")
    before = native_clock(notification.get("registrationBeforeClock"), numer=numer, denom=denom)
    after = native_clock(notification.get("registrationAfterClock"), numer=numer, denom=denom)
    require(clock_before(start, before) and clock_before(before, after) and clock_before(after, readiness),
            "Helper readiness/registration clocks are out of order")
    return value


def validate_completion(value, *, ready, ready_raw, command, provenance, nonce, window=HELPER_WINDOW):
    require(isinstance(value, dict) and value.get("kind") == "d24-recorder-progress-complete",
            "Invalid helper completion kind")
    require(all(value.get(key) == ready[key] for key in COMMON_HELPER_KEYS),
            "Helper completion changed a ready identity/clock")
    require(value.get("readyReceiptSHA256") == startup.digest(ready_raw)
            and value.get("readyReceiptBytes") == len(ready_raw), "Helper ready receipt hash/size mismatch")
    require(value.get("finalIdentityMatches") is True, "Helper final identity is unqualified")
    numer, denom = ready["machTimebaseNumer"], ready["machTimebaseDenom"]
    final = native_clock(value.get("completionClock"), numer=numer, denom=denom)
    notification = value.get("notification", {})
    require(all(notification.get(key) == ready["notification"][key] for key in REGISTRATION_KEYS),
            "Helper completion changed notification registration")
    closed = native_clock(notification.get("closedClock"), numer=numer, denom=denom)
    require(clock_before(ready["readinessClock"], closed) and clock_before(closed, final),
            "Helper completion/notification closure clocks are out of order")
    require(notification.get("cancelStatus") == 0 and notification.get("cancelled") is True
            and notification.get("countOverflow") is False and notification.get("callbackClockFailed") is False,
            "Helper notification closure is incomplete")
    count = notification.get("receivedCount")
    require(integer(count), "Helper notification count is invalid")
    if count == 0:
        require(notification.get("firstReceivedToken") is None and notification.get("firstReceivedClock") is None,
                "Zero-count notification includes a callback")
    else:
        require(notification.get("firstReceivedToken") == notification["token"],
                "Helper callback token differs from its registration")
        first = native_clock(notification.get("firstReceivedClock"), numer=numer, denom=denom)
        # The dispatch callback can run before notify_register_dispatch returns.
        require(clock_before(notification["registrationBeforeClock"], first) and clock_before(first, closed),
                "Helper callback clock is outside the registered/closed interval")
    elapsed = value.get("elapsedSeconds")
    native_elapsed = (final["machContinuousAfter"]-ready["nativeStartClock"]["machContinuousBefore"])*numer/denom/1e9
    require(type(elapsed) in (int, float) and math.isfinite(elapsed)
            and abs(elapsed-native_elapsed) <= .000001 and elapsed >= 0, "Helper elapsed clock is inconsistent")
    normal = value.get("reason") == "window-complete"
    registered_window = (closed["machContinuousBefore"]-ready["nativeStartClock"]["machContinuousBefore"])*numer/denom/1e9
    require((normal and value.get("normalWindowCompleted") is True
             and value.get("cooperativeAbortObserved") is False and elapsed >= window
             and registered_window >= window and value.get("exitCode") == 0)
            or (value.get("reason") == "cooperative-abort" and value.get("normalWindowCompleted") is False
                and value.get("cooperativeAbortObserved") is True and value.get("exitCode") == 143),
            "Helper final reason/window/exit contract is inconsistent")
    require(command.terminal and command.receipt["exitCode"] == value["exitCode"],
            "Helper completion exit differs from its owned child")
    return value


def validate_inputs(helper, output, provenance_path, *, synthetic):
    raw = read_regular(provenance_path, 256*1024)
    provenance = json.loads(raw)
    require(isinstance(provenance, dict) and provenance.get("schema") == 1
            and provenance.get("diagnostic") == "D24-recorder-progress-observation", "Invalid build provenance")
    require(all(isinstance(provenance.get(key), str) and HEX40.fullmatch(provenance[key])
                for key in ("experimentCommit", "experimentTree")), "Invalid experiment revision identity")
    require(provenance.get("dependencyBase") == "c1844a1ecb1650336d2cd584d23e2c3c6ed33a29"
            and provenance.get("frozenCandidate") == {
                "commit": "d821d7343675e2850705d141ef9b3b93a6aee945",
                "tree": "425baa28f00ec24551dd70c0cc874a75fa3be0c1"}, "Frozen candidate/dependency identity differs")
    architecture = provenance.get("architecture")
    require(architecture in ("arm64", "x86_64") and (synthetic or architecture == platform.machine()),
            "Provenance is not this native architecture")
    require(provenance["helper"].get("path") == str(helper)
            and provenance["helper"].get("architecture") == architecture
            and provenance["helper"].get("architectures") == [architecture]
            and canonical_uuid(provenance["helper"].get("uuid")), "Helper build identity is invalid")
    source_hashes = provenance.get("retainedDiagnosticSourcesSHA256")
    require(isinstance(source_hashes, dict) and "NativeRecorderProgressNotify.c" in source_hashes
            and (synthetic or set(source_hashes) == SOURCE_NAMES), "Retained source set is incomplete")
    inputs = {"provenance": {"path": str(provenance_path), **identity(raw)}}
    for name, expected_hash in source_hashes.items():
        require(isinstance(name, str) and Path(name).name == name and name not in (".", "..")
                and isinstance(expected_hash, str) and HEX64.fullmatch(expected_hash), "Invalid retained source entry")
        path = output / "sources" / name
        source_raw = read_regular(path, 2*1024*1024)
        require(startup.digest(source_raw) == expected_hash, "Retained source digest differs: " + name)
        inputs["source:"+name] = {"path": str(path), **identity(source_raw)}
    require(provenance.get("sourceSHA256") == source_hashes["NativeRecorderProgressNotify.c"],
            "Compiled helper source hash differs from retained source")
    tool_path = Path(provenance["sampleTool"]["path"])
    require(tool_path.is_absolute() and (synthetic or str(tool_path) == "/usr/bin/sample"),
            "The installed sampler path is not fixed")
    for name, path, expected, bound in (("helper", helper, provenance["helper"], 16*1024*1024),
                                         ("sampleTool", tool_path, provenance["sampleTool"], 64*1024*1024)):
        content = read_regular(path, bound)
        require(identity(content) == {"bytes": expected["bytes"], "sha256": expected["sha256"]},
                name + " bytes differ from provenance")
        inputs[name] = {"path": str(path), **identity(content)}
        if not synthetic:
            from native_sampler_tool_identity import inspect_tool
            parsed = inspect_tool(content, architecture)
            if name == "sampleTool":
                require(all(expected.get(key) == entry for key, entry in parsed.items()),
                        "Installed sampler native slice identity differs")
            else:
                require(parsed["nativeUUIDs"] == [expected["uuid"]] and len(parsed["slices"]) == 1,
                        "Helper native image identity differs")
    require(isinstance(provenance["sampleTool"].get("nativeUUIDs"), list)
            and provenance["sampleTool"]["nativeUUIDs"]
            and all(canonical_uuid(item) for item in provenance["sampleTool"]["nativeUUIDs"]),
            "Sampler native UUID identity is missing")
    return provenance, inputs


def successful(command):
    return (command.operation_done and command.terminal and command.receipt["exitCode"] == 0
            and command.receipt["stopReason"] is None and not command.receipt["streamErrors"]
            and not command.receipt["cleanupFailed"] and not command.transport.streams["stderr"])


def selected_identity(command, target):
    require(successful(command), command.name + ": selected-process snapshot did not complete cleanly")
    return observation.parse_identity(bytes(command.transport.streams["stdout"]), pid=target.pid,
                                      ppid=os.getpid(), pgid=target.pid, uid=os.geteuid())


def same_process(first, second):
    return all(first[key] == second[key] for key in ("pid", "ppid", "pgid", "uid", "startTime"))


def group_inventory(command, targets):
    require(successful(command), "Final owned-group snapshot did not complete cleanly")
    rows = [line.split() for line in bytes(command.transport.streams["stdout"]).decode("ascii").splitlines()
            if line.strip()]
    require(rows and all(len(row) == 3 and row[0].isdigit() and row[1].isdigit() and row[2]
                        for row in rows), "Final owned-group snapshot is malformed")
    result = {}
    for target in targets:
        members = [{"pid": int(row[0]), "pgid": int(row[1]), "state": row[2]}
                   for row in rows if int(row[1]) == target.pid]
        result[target.name] = {"pgid": target.pid, "pidLeaseHeldAtSnapshot": not target.pid_actions_revoked,
                               "members": members,
                               "noLiveMembersObserved": all(row["state"].startswith("Z") for row in members)}
    return result


def run(helper, output, provenance_path, *, test_hooks=None):
    """Run exactly one finite recorder/primary/secondary protocol and retain it."""
    output = Path(output)
    output.mkdir(parents=True, exist_ok=True)
    output = output.resolve(strict=True)
    helper, provenance_path = Path(helper).resolve(strict=True), Path(provenance_path).resolve(strict=True)
    summary_path = output / "recorder-progress-observation.json"
    require(not summary_path.exists(), "Refusing an existing D24 summary")
    synthetic = test_hooks is not None
    scale = test_hooks.scale if synthetic else 1.0
    require(type(scale) in (int, float) and math.isfinite(scale) and 0 < scale <= 1,
            "Invalid synthetic schedule scale")
    env = dict(os.environ, LC_ALL="C", LANG="C", PAGER="cat", MANPAGER="cat", TERM="dumb")
    if synthetic:
        env["LEMULIP_D24_TEST_SCALE"] = str(scale)
    factory = test_hooks.factory if synthetic else None
    # Unvalidated/oversized producer files must stay outside uploaded evidence.
    # Only bounded, validated copies and the existing trace packager enter it.
    work = output.parent / (output.name+"-operation")
    ready_path, completion_path = output / "helper-ready.json", output / "helper-completion.json"
    primary_path, secondary_path = work / "primary-sample.txt", work / "secondary-sample.txt"
    trace_path = work / "recording.trace"
    nonce = str(uuid.uuid4()).upper()
    notification_name = "app.lemulip.d24.recording."+nonce
    report = {
        "schema": 1, "diagnostic": "D24-recorder-progress-observation",
        "status": "incomplete", "evidenceKind": "synthetic-portable-test" if synthetic else "native-diagnostic",
        "diagnosticExecutionComplete": False, "samplerStackQualified": False, "cleanupComplete": False,
        "nativeEvidenceEstablished": False, "nativeInputExecuted": False, "settingsChanged": False,
        "applicationLaunchRequested": False, "perturbsObservedProcess": True,
        "activationRouteCoverageEstablished": False, "ipcRequestChainEstablished": False,
        "C12": "HOLD", "releaseReady": False, "nonce": nonce,
        "recordingNotificationName": notification_name, "commands": {}, "errors": [],
        "observation": {"primaryInvocationCount": 0, "secondaryInvocationCount": 0,
                        "bannerEstablishesCapturePhase": False, "nativeClockCorrelation": None,
                        "primaryProgressEvents": [],
                        "primaryBefore": None, "primaryAfter": None, "samePrimaryObservedBeforeAfter": False,
                        "secondaryCancellationReason": None, "stack": None, "unqualifiedReasons": []},
        "bounds": {"sampleTotalSeconds": SAMPLE_BUDGET, "sampleNormalSeconds": SAMPLE_BUDGET-CLEANUP_RESERVE,
                   "helperNativeWindowSeconds": HELPER_WINDOW, "helperParentHardSeconds": HELPER_HARD_END,
                   "observeAfterRecorderSeconds": OBSERVATION_TRIGGER,
                   "observationCutoffAfterHelperSpawnSeconds": OBSERVATION_CUTOFF,
                   "testOnlyTimeScale": scale if synthetic else None, "streamBytes": STREAM_LIMIT,
                   "reportBytes": REPORT_LIMIT, "snapshotBytes": PS_LIMIT},
    }
    commands, inputs = {}, {}
    provenance = ready = ready_raw = completion = None
    helper_command = recorder = primary = secondary = None
    recorder_before = primary_before = primary_after = None
    recorder_identity = primary_identity = None
    helper_spawn = cutoff = recorder_interrupt = None
    trigger_seen = False
    ready_observed = completion_observed = None
    report_progress = {"primary": [], "secondary": []}
    report_fingerprints = {}
    last_primary_stderr_bytes = None
    progress_markers_seen = set()

    def error(message):
        if message not in report["errors"]:
            report["errors"].append(message)

    def launch(name, argv, *, budget, limit=STREAM_LIMIT, reserve=CLEANUP_RESERVE, term_grace=TERM_GRACE):
        require(name not in commands, "A diagnostic command cannot be repeated: " + name)
        command = OwnedCommand(name, argv, cwd=work, env=env, budget=budget*scale, limit=limit,
                               reserve=reserve*scale, term_grace=term_grace*scale, factory=factory)
        commands[name] = command
        require(command.pid is not None, name + ": failed to spawn an owned child")
        return command

    def target_live(target):
        return (target is not None and target.pid is not None and not target.collected and not target.pid_actions_revoked
                and target.peek() is None and target.term_at is None and not target.operation_done)

    def snapshot(name, target):
        require(target_live(target), name + ": no live owned target for numeric-PID observation")
        require(time.monotonic() < cutoff, name + ": observation cutoff already passed")
        command = launch(name, ("/bin/ps", "-ww", "-p", str(target.pid), "-o", PS_FORMAT),
                         budget=1, limit=PS_LIMIT)
        command.receipt.update(targetPID=target.pid, targetPIDLeaseHeld=True,
                               targetOwnerPID=os.getpid(), targetSpawnClock=target.receipt["clockAtSpawn"])
        return command

    def cancel_secondary(reason):
        if secondary is not None and not secondary.operation_done:
            secondary.stop(reason)
            report["observation"]["secondaryCancellationReason"] = reason

    def cancel_observers(reason):
        cancel_secondary(reason)
        for item in (recorder_before, primary_before, primary_after, primary):
            if item is not None and not item.operation_done:
                item.stop(reason)

    def interrupt_recorder(reason):
        nonlocal recorder_interrupt
        if recorder is None or recorder_interrupt is not None:
            return
        recorder_interrupt = time.monotonic()
        recorder.receipt["interruptReason"] = reason
        recorder.receipt["interruptClock"] = clock()
        if not recorder.terminal:
            recorder.signal(signal.SIGINT, group=False)

    def tick_all():
        # Every independent operation deadline is checked on every loop pass.
        # A metadata query or retained PID lease cannot extend a sample budget.
        if primary is not None and (time.monotonic() >= primary.normal_deadline or primary.terminal
                                    or primary.term_at is not None):
            cancel_secondary("primary-operation-boundary")
            for item in (primary_before, primary_after):
                if item is not None and not item.operation_done:
                    item.stop("primary-operation-boundary")
        for command in tuple(commands.values()):
            command.tick()
        if primary is not None and (primary.terminal or primary.term_at is not None):
            cancel_secondary("primary-operation-boundary")
        if recorder is not None and (recorder.terminal or recorder.term_at is not None):
            cancel_observers("recorder-operation-boundary")
        if recorder_interrupt is not None and recorder is not None:
            if time.monotonic()-recorder_interrupt >= 10*scale:
                recorder.stop("recorder-interrupt-grace-expired")

    def observe_report_files():
        for name, path in (("primary", primary_path), ("secondary", secondary_path)):
            try:
                info = path.lstat()
            except FileNotFoundError:
                continue
            require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1 and info.st_size <= REPORT_LIMIT,
                    name + " sample report is nonregular, linked, or oversized")
            fingerprint = (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns)
            if report_fingerprints.get(name) != fingerprint:
                require(len(report_progress[name]) < 256, name + " sample report progress bound exceeded")
                report_progress[name].append({"clock": clock(), "bytes": info.st_size,
                                               "mtimeNS": info.st_mtime_ns, "device": info.st_dev,
                                               "inode": info.st_ino})
                report_fingerprints[name] = fingerprint

    try:
        require(synthetic or (sys.platform == "darwin" and sys.version_info >= (3, 13)),
                "Native D24 requires macOS and Python 3.13+ non-reaping waitid")
        require(not work.exists() and not ready_path.exists() and not completion_path.exists(),
                "Refusing an existing operation/receipt path")
        work.mkdir(mode=0o700)
        provenance, inputs = validate_inputs(helper, output, provenance_path, synthetic=synthetic)
        report["provenance"] = provenance
        report["inputsBefore"] = inputs
        report["waitidPreflight"] = waitid_preflight()
        if not (synthetic and test_hooks.skip_manual_preflight):
            report["manualPreflight"] = observation.preflight(output, cwd=work, env=env)
            require(report["manualPreflight"]["passed"], "Installed sample/ps manual preflight failed")
        else:
            report["manualPreflight"] = {"passed": False, "skippedForSyntheticTest": True}
        helper_argv = [str(helper)]
        arguments = {
            "ready": str(ready_path), "completion": str(completion_path), "nonce": nonce,
            "expected-executable": str(helper), "expected-sha256": provenance["helper"]["sha256"],
            "expected-uuid": provenance["helper"]["uuid"], "expected-architecture": provenance["architecture"],
            "source-sha256": provenance["sourceSHA256"], "experiment-commit": provenance["experimentCommit"],
            "experiment-tree": provenance["experimentTree"], "recording-notification": notification_name,
        }
        for key, value in arguments.items():
            helper_argv.extend(("--"+key, value))
        helper_spawn = time.monotonic()
        report["helperSpawnBeforeClock"] = clock()
        cutoff = helper_spawn+OBSERVATION_CUTOFF*scale
        helper_command = launch("helper", helper_argv, budget=HELPER_HARD_END)
        whole_deadline = helper_command.started+(HELPER_HARD_END+14)*scale
        report["observation"]["cutoffMonotonic"] = cutoff
        state = "waiting-for-helper-ready"
        next_file_observation = 0.0
        while time.monotonic() < whole_deadline:
            tick_all()
            now = time.monotonic()
            if now >= next_file_observation:
                observe_report_files()
                next_file_observation = now+max(.005, .05*scale)
            if now >= cutoff:
                cancel_observers("helper-observation-cutoff")
                if state not in ("observed", "finished"):
                    report["observation"]["unqualifiedReasons"].append("helper-observation-cutoff")
                    state = "finished"
            if ready is None and ready_path.exists():
                ready_observed = clock()
                ready_raw = read_regular(ready_path, 32768)
                ready = validate_ready(json.loads(ready_raw), command=helper_command, provenance=provenance,
                                       nonce=nonce, window=HELPER_WINDOW*scale)
                report["helperReady"] = {"file": ready_path.name, **identity(ready_raw),
                                         "observedClock": ready_observed, "validated": True}
                require(target_live(helper_command), "Helper exited before recorder admission")
                require(now < helper_spawn+3*scale, "Helper readiness exceeded its fixed admission window")
                recorder = launch("record", startup.recording_command(trace_path, notification_name),
                                  budget=45, reserve=4, term_grace=2)
                recorder.receipt["helperReadyObservedClock"] = ready_observed
                report["observation"].update(recorderPID=recorder.pid, recorderParentPID=os.getpid(),
                                               recorderGroupID=recorder.pid,
                                               recorderTriggerMonotonic=recorder.started+OBSERVATION_TRIGGER*scale)
                state = "waiting-for-recorder-trigger"
            if ready is None and (helper_command.operation_done or now >= helper_spawn+3*scale):
                raise EvidenceError("Helper did not publish a live, validated ready receipt within its admission window")
            if recorder is not None and state == "waiting-for-recorder-trigger":
                if not target_live(recorder):
                    raise EvidenceError("Recorder exited before the one-shot observation trigger")
                if now >= recorder.started+OBSERVATION_TRIGGER*scale:
                    require(cutoff-now >= (SAMPLE_BUDGET+2)*scale, "Insufficient fixed window for primary admission")
                    recorder_before = snapshot("recorder-before", recorder)
                    state = "waiting-for-recorder-identity"
            if state == "waiting-for-recorder-identity" and recorder_before.operation_done:
                recorder_identity = selected_identity(recorder_before, recorder)
                require(target_live(recorder), "Recorder exited before primary sampler admission")
                report["observation"]["recorderBefore"] = recorder_identity
                primary = launch("primary-sample", ("/usr/bin/sample", str(recorder.pid), "1", "10", "-mayDie",
                                                     "-file", str(primary_path)), budget=SAMPLE_BUDGET)
                primary.receipt.update(targetPID=recorder.pid, targetPIDLeaseHeld=True, targetOwnerPID=os.getpid())
                report["observation"].update(primaryInvocationCount=1, primaryPID=primary.pid,
                                               primaryParentPID=os.getpid(), primaryGroupID=primary.pid)
                state = "waiting-for-primary-banner"
            if primary is not None:
                stderr_bytes = len(primary.transport.streams["stderr"])
                if stderr_bytes != last_primary_stderr_bytes:
                    stderr_raw = bytes(primary.transport.streams["stderr"])
                    progress = classify_sample_stderr(stderr_raw, target_pid=recorder.pid)
                    report["observation"]["primaryProgressText"] = progress
                    last_primary_stderr_bytes = stderr_bytes
                    for marker in ("expectedBannerObserved", "samplingCompletedMarkerObserved", "reportWrittenMarkerObserved"):
                        if progress[marker] and marker not in progress_markers_seen:
                            progress_markers_seen.add(marker)
                            report["observation"]["primaryProgressEvents"].append({
                                "marker": marker, "clock": clock(), "stderrBytesObserved": stderr_bytes,
                                "stderrSHA256AtObservation": startup.digest(stderr_raw), "observedTextOnly": True})
                else:
                    progress = report["observation"]["primaryProgressText"]
                require(not progress["ambiguous"], "Primary sampler emitted ambiguous PID/banner text")
                if progress["expectedBannerObserved"] and not trigger_seen:
                    trigger_seen = True
                    report["observation"]["bannerTrigger"] = {"clock": clock(), **progress,
                        "stderrBytesObserved": len(primary.transport.streams["stderr"]),
                        "stderrSHA256AtTrigger": startup.digest(bytes(primary.transport.streams["stderr"]))}
                if state == "waiting-for-primary-banner" and trigger_seen:
                    if target_live(primary) and now < primary.normal_deadline and now < cutoff:
                        primary_before = snapshot("primary-before", primary)
                        state = "waiting-for-primary-identity"
                    else:
                        report["observation"]["unqualifiedReasons"].append("primary-not-live-at-banner-trigger")
                        state = "finished"
                if state == "waiting-for-primary-banner" and primary.operation_done:
                    report["observation"]["unqualifiedReasons"].append("primary-ended-without-complete-expected-banner")
                    state = "finished"
            if state == "waiting-for-primary-identity" and primary_before.operation_done:
                if target_live(primary) and now < primary.normal_deadline:
                    primary_identity = selected_identity(primary_before, primary)
                    report["observation"]["primaryBefore"] = primary_identity
                    secondary = launch("secondary-sample", ("/usr/bin/sample", str(primary.pid), "1", "10", "-mayDie",
                                                             "-file", str(secondary_path)), budget=SAMPLE_BUDGET)
                    secondary.deadline = min(secondary.deadline, primary.deadline, cutoff)
                    secondary.normal_deadline = min(secondary.normal_deadline, primary.normal_deadline,
                                                    cutoff-CLEANUP_RESERVE*scale)
                    secondary.receipt.update(targetPID=primary.pid, targetPIDLeaseHeld=True, targetOwnerPID=os.getpid(),
                        deadlineBoundedByPrimary=True, effectiveTotalBudgetSeconds=secondary.deadline-secondary.started,
                        effectiveNormalBudgetSeconds=secondary.normal_deadline-secondary.started)
                    report["observation"].update(secondaryInvocationCount=1, secondaryPID=secondary.pid)
                    state = "waiting-for-secondary"
                else:
                    report["observation"]["unqualifiedReasons"].append("primary-ended-before-secondary-admission")
                    state = "finished"
            if state == "waiting-for-secondary" and secondary.operation_done:
                if (secondary.terminal and secondary.receipt["exitCode"] == 0
                        and secondary.receipt["stopReason"] is None and secondary_path.exists()
                        and target_live(primary) and now < primary.normal_deadline and now < cutoff):
                    primary_after = snapshot("primary-after", primary)
                    state = "waiting-for-primary-after"
                else:
                    report["observation"]["unqualifiedReasons"].append("secondary-ended-without-admissible-after-snapshot")
                    state = "finished"
            if state == "waiting-for-primary-after" and primary_after.operation_done:
                try:
                    after_identity = selected_identity(primary_after, primary)
                    require(same_process(primary_identity, after_identity), "Primary before/after start identity differs")
                    report["observation"].update(primaryAfter=after_identity, samePrimaryObservedBeforeAfter=True)
                except EvidenceError as caught:
                    expected_loss = (not bytes(primary_after.transport.streams["stdout"]).strip()
                                     or str(caught) == "Selected recorder is a zombie; no live target was observed")
                    if (primary.terminal or primary.term_at is not None) and expected_loss:
                        report["observation"]["unqualifiedReasons"].append("primary-ended-during-after-snapshot")
                    else:
                        raise
                state = "observed"
            if helper_command.operation_done:
                cancel_observers("helper-operation-ended")
                interrupt_recorder("helper-operation-ended")
                if recorder is None or recorder.operation_done:
                    break
            if recorder is not None and recorder.operation_done and not helper_command.operation_done:
                if recorder_interrupt is None:
                    error("Recorder ended before the fixed native helper window")
                    helper_command.stop("recorder-ended-before-helper-window")
            time.sleep(min(.005, .01*scale))
        else:
            raise EvidenceError("Fixed parent protocol deadline exceeded")
    except (EvidenceError, OSError, ValueError, KeyError, TypeError, RuntimeError) as caught:
        error(type(caught).__name__+": "+str(caught))
    finally:
        # Failed preconditions and report parsing never bypass owned cleanup.
        cancel_observers("protocol-cleanup")
        if helper_command is not None and not helper_command.operation_done:
            helper_command.stop("protocol-cleanup")
        interrupt_recorder("protocol-cleanup")
        cleanup_deadline = time.monotonic()+14*scale
        while commands and time.monotonic() < cleanup_deadline:
            try:
                tick_all()
            except (EvidenceError, OSError) as caught:
                error("Cleanup peek failed: "+str(caught))
                break
            if all(command.operation_done for command in commands.values()):
                break
            time.sleep(min(.005, .01*scale))
        targets = [command for command in commands.values() if command.pid is not None]
        if targets:
            try:
                checker = launch("owned-groups", ("/bin/ps", "-A", "-o", "pid=,pgid=,stat="),
                                 budget=2, limit=PS_LIMIT)
                check_deadline = checker.deadline
                while not checker.operation_done and time.monotonic() < check_deadline:
                    tick_all()
                    time.sleep(min(.005, .01*scale))
                checker.tick()
                report["ownedGroups"] = group_inventory(checker, targets)
                unresolved = [command for command in targets
                              if not report["ownedGroups"][command.name]["noLiveMembersObserved"]]
                if unresolved:
                    # This is bounded emergency cleanup, not an extension of
                    # the sampler operation. The original budget remains failed.
                    error("Live owned descendants survived their original operation/cleanup bound")
                    report["ownedGroupsBeforeEmergencyCleanup"] = report["ownedGroups"]
                    for command in unresolved:
                        command.receipt["emergencyGroupCleanup"] = True
                        command.signal(signal.SIGTERM, group=True)
                    force_at = time.monotonic()+TERM_GRACE*scale
                    while time.monotonic() < force_at:
                        tick_all()
                        time.sleep(min(.005, .01*scale))
                    for command in unresolved:
                        command.signal(signal.SIGKILL, group=True)
                        command.kill_sent = True
                    follow = launch("owned-groups-after-cleanup", ("/bin/ps", "-A", "-o", "pid=,pgid=,stat="),
                                    budget=2, limit=PS_LIMIT)
                    while not follow.operation_done and time.monotonic() < follow.deadline:
                        tick_all()
                        time.sleep(min(.005, .01*scale))
                    follow.tick()
                    report["ownedGroups"] = group_inventory(follow, targets)
                require(all(entry["noLiveMembersObserved"] for entry in report["ownedGroups"].values()),
                        "A live owned process-group member remained at final inventory")
                require(all(command.terminal and not command.transport.selector.get_map()
                            for command in commands.values()), "A child or inherited stream remained after cleanup")
                # Resolve only a proven obsolete EPERM against an exited group;
                # this is cleanup evidence, never sampler permission evidence.
                for command in targets:
                    failures = command.receipt["signalErrors"]
                    if failures and all(item["errno"] == errno.EPERM and item["target"] == "owned-group"
                                        for item in failures) and not command.receipt["cleanupFailureReasons"]:
                        command.receipt["cleanupFailed"] = False
                        command.receipt["signalFailureResolvedByNoLiveOwnedGroup"] = True
                require(all(not command.receipt["cleanupFailed"] for command in commands.values()),
                        "A command exceeded its fixed cleanup bound")
                report["cleanupComplete"] = True
            except (EvidenceError, OSError, ValueError, UnicodeError, KeyError, TypeError, RuntimeError) as caught:
                error("Owned cleanup incomplete: "+str(caught))
            # Dependency order: secondary and metadata finish before primary is
            # collected; primary finishes before recorder is collected.
            collection_order = ("secondary-sample", "primary-after", "primary-before", "primary-sample",
                                "recorder-before", "record", "helper", "owned-groups", "owned-groups-after-cleanup")
            dependencies = {"primary-sample": ("secondary-sample", "primary-before", "primary-after"),
                            "record": ("primary-sample", "recorder-before")}
            for name in collection_order:
                command = commands.get(name)
                if command is None:
                    continue
                if not command.terminal or command.transport.selector.get_map():
                    if not command.kill_sent:
                        command.signal(signal.SIGKILL, group=True)
                        command.kill_sent = True
                    command.tick()
                dependents_done = all(commands[item].collected for item in dependencies.get(name, ())
                                      if item in commands)
                group_safe = (name.startswith("owned-groups") or
                              report.get("ownedGroups", {}).get(name, {}).get("noLiveMembersObserved") is True)
                if command.terminal and not command.transport.selector.get_map() and dependents_done and group_safe:
                    try:
                        command.collect()
                    except (EvidenceError, OSError) as caught:
                        error(name+": child collection failed: "+str(caught))
                        report["cleanupComplete"] = False
                else:
                    error(name+": child could not be collected within its fixed cleanup bound")
                    report["cleanupComplete"] = False
        for name, command in commands.items():
            command.close()
            report["commands"][name] = startup.preserve_command(output, name, command.receipt,
                                                                command.transport.streams)

    # All interpretation is done after independent deadlines and PID leases.
    if ready is not None and helper_command is not None:
        try:
            completion_observed = clock()
            complete_raw = read_regular(completion_path, 32768)
            completion = validate_completion(json.loads(complete_raw), ready=ready, ready_raw=ready_raw,
                command=helper_command, provenance=provenance, nonce=nonce, window=HELPER_WINDOW*scale)
            report["helperCompletion"] = {"file": completion_path.name, **identity(complete_raw),
                                           "observedClock": completion_observed, "validated": True,
                                           "receipt": completion}
            require(completion["normalWindowCompleted"], "Native helper window was cooperatively aborted")
            report["observation"]["nativeClockCorrelation"] = {
                "bootUUID": ready["bootUUID"], "machTimebaseNumer": ready["machTimebaseNumer"],
                "machTimebaseDenom": ready["machTimebaseDenom"], "nativeStartClock": ready["nativeStartClock"],
                "nativeReadyClock": ready["readinessClock"], "parentBeforeHelperSpawnClock": report["helperSpawnBeforeClock"],
                "parentReadyReceiptObservedClock": ready_observed, "nativeCompletionClock": completion["completionClock"],
                "parentCompletionReceiptObservedClock": completion_observed,
                "notificationSenderEstablished": False, "notificationEstablishesTraceEpoch": False,
                "wallTimeEquatesClockDomains": False,
            }
        except (EvidenceError, OSError, ValueError, KeyError, TypeError) as caught:
            error("Helper final validation failed: "+str(caught))
    report["observation"]["reportProgress"] = report_progress
    for name, path in (("primary", primary_path), ("secondary", secondary_path)):
        try:
            if not path.exists() and not path.is_symlink():
                report["observation"][name+"Report"] = {"status": "absent"}
                continue
            raw = read_regular(path, REPORT_LIMIT)
            retained = output / (name+"-sample-report.txt")
            with retained.open("xb") as handle:
                handle.write(raw)
            report["observation"][name+"Report"] = {"status": "retained", "file": retained.name,
                                                      "readClock": clock(), **identity(raw)}
            if name == "secondary":
                require(primary is not None, "Secondary report lacks its primary invocation")
                parsed = inspect_sampler_report(raw, target_pid=primary.pid, target_parent=os.getpid(),
                    architecture=provenance["architecture"], tool_identity=provenance["sampleTool"])
                report["observation"]["stack"] = parsed
                report["samplerStackQualified"] = bool(
                    secondary is not None and secondary.receipt["exitCode"] == 0
                    and secondary.receipt["stopReason"] is None
                    and not secondary.receipt["streamErrors"] and not secondary.receipt["cleanupFailed"]
                    and report["observation"]["samePrimaryObservedBeforeAfter"])
        except (EvidenceError, OSError, ValueError, KeyError, TypeError) as caught:
            error(name+" report validation failed: "+str(caught))
    report["inputsAfter"] = {}
    for name, expected in inputs.items():
        try:
            bound = 64*1024*1024 if name == "sampleTool" else 16*1024*1024
            actual = identity(read_regular(Path(expected["path"]), bound))
            report["inputsAfter"][name] = {"path": expected["path"], **actual}
            require(actual == {"bytes": expected["bytes"], "sha256": expected["sha256"]},
                    "Input changed during observation: "+name)
        except (EvidenceError, OSError) as caught:
            error(str(caught))
    if trace_path.exists() and report["cleanupComplete"]:
        report["trace"] = startup.package_trace(trace_path, output, work)
        if report["trace"]["status"] != "packaged":
            error("Trace package could not be retained within existing bounds")
    else:
        report["trace"] = {"status": "unavailable", "archive": None}
    for name, command in commands.items():
        if command.receipt["streamErrors"] or command.receipt["stopReason"] in ("stream-error", "output-limit"):
            error(name+": bounded stream contract failed")
    report["diagnosticExecutionComplete"] = bool(not report["errors"] and report["cleanupComplete"]
        and completion is not None and completion["normalWindowCompleted"]
        and report["observation"]["primaryInvocationCount"] == 1)
    report["nativeEvidenceEstablished"] = bool(not synthetic and report["diagnosticExecutionComplete"]
                                                and report["samplerStackQualified"])
    if report["diagnosticExecutionComplete"]:
        report["status"] = ("diagnostic-complete-stack-qualified" if report["samplerStackQualified"]
                            else "diagnostic-complete-stack-unqualified")
    if not report["samplerStackQualified"] and not report["observation"]["unqualifiedReasons"]:
        report["observation"]["unqualifiedReasons"].append("no-qualified-secondary-stack-and-live-after-identity")
    report["completedClock"] = clock()
    write_json(summary_path, report)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--helper", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--provenance", type=Path, required=True)
    args = parser.parse_args()
    try:
        result = run(args.helper, args.output, args.provenance)
    except (EvidenceError, OSError, ValueError) as caught:
        print("D24 precondition failed: "+str(caught), file=sys.stderr)
        return 1
    print(json.dumps({key: result[key] for key in ("status", "diagnosticExecutionComplete",
                                                  "samplerStackQualified", "cleanupComplete", "errors")}, sort_keys=True))
    return 0 if result["diagnosticExecutionComplete"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
