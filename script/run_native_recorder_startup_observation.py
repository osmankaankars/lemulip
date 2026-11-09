#!/usr/bin/env python3
"""D21: one bounded observation of the still-owned D20 recorder process."""

from __future__ import annotations

import argparse
import errno
import json
import os
from pathlib import Path
import platform
import re
import signal
import stat
import time

from collect_native_trace_capabilities import capture, write_json
import run_native_system_trace_startup as startup


OBSERVE_AFTER_SECONDS = 3.0
SAFE_END_AFTER_HELPER_SPAWN = 14.0
REQUIRED_WINDOW_SECONDS = 8.0
PS_BUDGET_SECONDS = 1.0
SAMPLE_BUDGET_SECONDS = 4.0
CLEANUP_RESERVE_SECONDS = 0.5
TERM_GRACE_SECONDS = 0.25
STREAM_LIMIT = 2 * 1024 * 1024
PS_STREAM_LIMIT = 65536
REPORT_LIMIT = 8 * 1024 * 1024
PS_FORMAT = "pid=,ppid=,pgid=,uid=,lstart=,stat=,comm=,args="


def clock() -> dict:
    before = time.monotonic_ns()
    wall = time.time_ns()
    after = time.monotonic_ns()
    return {"monotonicBeforeNS": before, "wallTimeNS": wall, "monotonicAfterNS": after}


def manual_layout(raw: bytes) -> str:
    text = raw.decode("utf-8")
    while "\b" in text:
        changed = re.sub(r"[^\n]\x08", "", text)
        if changed == text:
            raise startup.EvidenceError("Unsupported manual overstrike sequence")
        text = changed
    if "\x00" in text or "\x1b" in text:
        raise startup.EvidenceError("Unexpected manual control sequence")
    return "\n".join(re.sub(r"[ \t]+", " ", line).strip() for line in text.splitlines())


def manual_text(raw: bytes) -> str:
    return re.sub(r"\s+", " ", manual_layout(raw)).strip()


def manual_sections(layout: str) -> dict:
    matches = list(re.finditer(r"(?m)^([A-Z][A-Z /-]{2,})$", layout))
    return {match[1]: layout[match.end():matches[index + 1].start() if index + 1 < len(matches) else len(layout)]
            for index, match in enumerate(matches)}


def option_block(sections: dict, name: str) -> str:
    area = sections.get("OPTIONS", sections.get("DESCRIPTION", ""))
    lines = area.splitlines()
    start = next((index for index, line in enumerate(lines) if re.match(r"^" + re.escape(name) + r"(?:\s|$)", line)), None)
    if start is None:
        return ""
    end = next((index for index in range(start + 1, len(lines)) if re.match(r"^-[A-Za-z]", lines[index])), len(lines))
    return " ".join(lines[start:end]).strip()


def validate_manuals(sample_raw: bytes, ps_raw: bytes) -> dict:
    """Require option paragraphs/definitions, retaining each matched passage."""
    layouts = {"sample": manual_layout(sample_raw), "ps": manual_layout(ps_raw)}
    sample, ps = (manual_sections(layouts[topic]) for topic in ("sample", "ps"))
    checks, passages = {}, {}

    def require(name, text, *patterns):
        text = re.sub(r"\s+", " ", text).strip()
        found = [re.search(pattern, text, re.I) for pattern in patterns]
        checks[name] = all(match is not None for match in found)
        passages[name] = {"matches": [match[0] if match else None for match in found],
                          "contexts": [text[max(0, match.start() - 80):min(len(text), match.end() + 80)] if match else None
                                       for match in found]}

    description = sample.get("DESCRIPTION", "")
    require("sampleSynopsisOrder", sample.get("SYNOPSIS", ""),
            r"\bsample\s+(?:pid|process)(?:\s*\|\s*partial-executable-name)?\s+\[?duration\s+\[?(?:samplingInterval|interval)")
    require("samplePID", description, r"(?:process|pid).{0,220}(?:process ID|process identifier)")
    flat_description = re.sub(r"\s+", " ", description)
    def unit_statements(argument):
        candidates = re.findall(r"\b(?:" + argument + r")\b[^.]{0,400}(?:\.|$)", flat_description, re.I)
        return " ".join(value for value in candidates if re.search(r"\b(?:seconds|milliseconds)\b", value, re.I))
    require("durationSeconds", unit_statements("duration"), r"\bseconds\b", r"^(?!.*\bmilliseconds\b).*$")
    require("intervalMilliseconds", unit_statements("samplingInterval|interval"), r"\bmilliseconds\b", r"^(?!.*\bseconds\b).*$")
    require("mayDieSymbolsFirst", option_block(sample, "-mayDie"),
            r"(?:symbol.{0,400}(?:before|first)|(?:before|first).{0,400}symbol|immediately.{0,400}(?:symbol|location))")
    require("explicitReportFile", option_block(sample, "-file"),
            r"^-file\s+<?(?:filename|file|path)>?", r"(?:write|written|save|output).{0,250}(?:file|path)|(?:file|path).{0,250}(?:write|written|save|output)")
    require("psPIDSelection", option_block(ps, "-p"), r"(?:process ID|processes)", r"(?:match|specif|list)")
    require("psAllSelection", option_block(ps, "-A"),
            r"(?:all processes|every process|other users.{0,60}processes.{0,120}including.{0,80}without.{0,40}controlling terminals)")
    require("psRepeatedWide", option_block(ps, "-w"), r"(?:more than once|twice|repeated)",
            r"(?:wide|width|column)", r"(?:restrict|limit|without regard.{0,100}window)")
    output = option_block(ps, "-o")
    require("psKeywordFormat", output, r"(?:space.{0,80}comma|comma.{0,80}space)", r"keyword", r"=")
    require("psEmptyHeaders", output, r"(?:header|heading).{0,300}empty", r"(?:not print|no header|suppress|not display)")
    keywords = ps.get("KEYWORDS", "")
    for name, pattern in {
        "psPIDField": r"\bpid\s+process\s+ID", "psParentField": r"\bppid\s+parent\s+process\s+ID",
        "psGroupField": r"\bpgid\s+process\s+group\s+(?:ID|number)",
        "psUIDField": r"\buid\s+effective\s+user\s+ID", "psStartField": r"\blstart\s+time\s+started",
        "psStateField": r"\b(?:state|stat)\s+symbolic\s+process\s+state.{0,200}\bstat\b",
        "psCommandField": r"\bcomm\s+command", "psArgsField": r"\bargs\s+command\s+and\s+arguments",
    }.items():
        require(name, keywords, pattern)
    return {"schema": 1, "passed": all(checks.values()), "semanticChecks": checks, "matchedPassages": passages,
            "manuals": {topic: {"bytes": len(raw), "sha256": startup.digest(raw),
                                 "normalizedBytes": len(layouts[topic].encode()),
                                 "normalizedSHA256": startup.digest(layouts[topic].encode())}
                        for topic, raw in (("sample", sample_raw), ("ps", ps_raw))},
            "recognizedArguments": {"sample": ["PID", "1", "10", "-mayDie", "-file", "EXCLUSIVE_REPORT_PATH"],
                                    "ps": ["-ww", "-p", "PID", "-o", PS_FORMAT],
                                    "cleanupPS": ["-A", "-o", "pid=,pgid=,stat="]}}


def preflight(output: Path, *, cwd: Path, env: dict[str, str]) -> dict:
    commands, manuals = {}, {}
    for topic in ("sample", "ps"):
        name = "observer-manual-" + topic
        receipt, streams = capture(("/usr/bin/man", "1", topic), cwd=cwd, env=env,
                                   timeout=20, limit=STREAM_LIMIT)
        commands[topic] = startup.preserve_command(output, name, receipt, streams)
        manuals[topic] = streams["stdout"]
        if receipt["cleanupFailed"]:
            break
    report = {"schema": 1, "diagnostic": "D21-recorder-startup-manual-preflight", "commands": commands,
              "passed": False, "helperStarted": False, "recorderStarted": False, "sampleStarted": False,
              "nativeInputExecuted": False, "settingsChanged": False, "errors": []}
    if (len(commands) == 2 and all(c["status"] == "completed" and not c["cleanupFailed"]
                                  and c["files"]["stderr"]["bytes"] == 0 for c in commands.values())):
        try:
            for topic in ("sample", "ps"):
                with (output / ("observer-manual-" + topic + ".normalized.txt")).open("x", encoding="utf-8") as handle:
                    handle.write(manual_layout(manuals[topic]))
            report["contract"] = validate_manuals(manuals["sample"], manuals["ps"])
            report["passed"] = report["contract"]["passed"]
        except (UnicodeDecodeError, ValueError) as error:
            report["errors"].append(str(error))
    write_json(output / "observer-preflight.json", report)
    return report


def parse_identity(raw: bytes, *, pid: int, ppid: int, pgid: int, uid: int) -> dict:
    text = raw.decode("utf-8")
    rows = [line for line in text.splitlines() if line.strip()]
    if len(rows) != 1:
        raise startup.EvidenceError("Identity snapshot must contain exactly one selected process")
    match = re.fullmatch(r"\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+"
                         r"([A-Za-z]{3}\s+[A-Za-z]{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}\s+\d{4})\s+"
                         r"(\S+)\s+(.+?)\s*", rows[0])
    if match is None:
        raise startup.EvidenceError("Unrecognized C-locale ps identity layout")
    actual = dict(zip(("pid", "ppid", "pgid", "uid"), map(int, match.groups()[:4])))
    if actual != {"pid": pid, "ppid": ppid, "pgid": pgid, "uid": uid}:
        raise startup.EvidenceError("Selected process does not match the owned recorder instance")
    if match[6].startswith("Z"):
        raise startup.EvidenceError("Selected recorder is a zombie; no live target was observed")
    if match[6][0] not in "IRSTU":
        raise startup.EvidenceError("Selected recorder state is not a recognized non-zombie macOS state")
    actual.update(startTime=" ".join(match[5].split()), state=match[6],
                  advisoryCommandAndArguments=match[7], commandTextProvesImage=False)
    return actual


def inspect_sample(raw: bytes, *, pid: int) -> dict:
    text = raw.decode("utf-8")
    process_rows = re.findall(r"^Process:\s*(.*?)\s*\[(\d+)\]\s*$", text, re.M)
    paths = re.findall(r"^Path:\s*(.+?)\s*$", text, re.M)
    if len(process_rows) != 1 or int(process_rows[0][1]) != pid or len(paths) != 1 or not paths[0].startswith("/"):
        raise startup.EvidenceError("Sample report does not bind one observed image to the owned PID")
    images = text.split("Binary Images:", 1)
    if len(images) != 2 or not images[1].strip():
        raise startup.EvidenceError("Sample report has no observed binary-image section")
    image_lines = [line for line in images[1].splitlines()
                   if re.match(r"\s*0x[0-9a-fA-F]+\s*-\s*0x[0-9a-fA-F]+\s+", line)
                   and re.search(r"\s" + re.escape(paths[0]) + r"\s*$", line)]
    if len(image_lines) != 1:
        raise startup.EvidenceError("Reported process path lacks one matching loaded binary-image entry")
    image_uuid = re.search(r"<([0-9a-fA-F-]{36})>", image_lines[0])
    return {"processName": process_rows[0][0], "pid": pid, "observedPath": paths[0],
            "matchingBinaryImageLine": image_lines[0], "observedUUID": image_uuid[1] if image_uuid else None,
            "binaryImagesSectionPresent": True, "sampledImageProvesUnperturbedD20Image": False,
            "activationRouteCoverageEstablished": False}


class ObservationCommand:
    """One nonblocking child; total budget includes reserved TERM/KILL cleanup."""

    def __init__(self, argv, *, cwd, env, budget, limit):
        self.transport = startup.MonitoredCommand(tuple(argv), cwd=cwd, env=env, limit=limit)
        self.deadline = self.transport.started + budget
        self.term_at = None
        self.kill_sent = False
        self.done = self.transport.process is None
        self.transport.receipt.update(clockAtSpawn=clock(), totalBudgetSeconds=budget,
                                      normalOperationBudgetSeconds=budget - CLEANUP_RESERVE_SECONDS,
                                      cleanupFailureReasons=[])

    def stop(self, reason):
        command = self.transport
        if self.done or self.term_at is not None:
            return
        command.receipt["stopReason"] = command.receipt["stopReason"] or reason
        # No poll here: the direct child has not been reaped while running, so
        # its reserved PID still identifies this process group.
        self.term_at = time.monotonic()
        if command.process.returncode is None:
            command.signal(signal.SIGTERM, group=True)

    def tick(self):
        if self.done:
            return
        command, now = self.transport, time.monotonic()
        command.drain()
        if command.receipt["stopReason"] in ("stream-error", "output-limit"):
            self.stop(command.receipt["stopReason"])
        if now >= self.deadline - CLEANUP_RESERVE_SECONDS:
            self.stop("command-budget")
        if command.process.returncode is not None:
            exited = True
        elif self.term_at is not None:
            # Never reap between TERM and KILL: closed pipes or an exited
            # leader must not permit surviving descendants to escape cleanup.
            if not self.kill_sent and now - self.term_at >= TERM_GRACE_SECONDS:
                command.signal(signal.SIGKILL, group=True)
                self.kill_sent = True
            if self.kill_sent or command.receipt["signalErrors"]:
                exited = command.poll() is not None
            else:
                exited = False
        else:
            # Retain the leader while any inherited stream is still open. If
            # a descendant outlives it while retaining a pipe, the group can
            # still be stopped before a reap permits numeric PGID reuse.
            exited = command.poll() is not None if not command.selector.get_map() else False
        if exited and not command.selector.get_map():
            # A reaped group is never signaled again. The final separate ps
            # snapshot decides whether any live descendants remain unresolved.
            self.done = True
        elif now >= self.deadline:
            command.receipt["cleanupFailed"] = True
            command.receipt["cleanupFailureReasons"].append("child-or-streams-exceeded-total-budget")
            self.done = True
        if self.done:
            command.drain()
            command.receipt["inheritedStreamsStillOpen"] = bool(command.selector.get_map())
            if command.receipt["inheritedStreamsStillOpen"]:
                command.receipt["cleanupFailed"] = True
                command.receipt["cleanupFailureReasons"].append("inherited-streams-still-open")
            command.receipt["clockAtCompletion"] = clock()
            command.close()


class RecorderObservation:
    def __init__(self, output: Path):
        self.output = output
        self.recorder = None
        self.active = None
        self.active_name = None
        self.commands = {}
        self.state = "awaiting-recorder"
        self.done = False
        self.cancel_reason = None
        self.report_path = None
        self.before = None
        self.report = {"schema": 1, "diagnostic": "D21-recorder-startup-observation", "status": "not-started",
                       "commands": {}, "errors": [], "sampleInvocationCount": 0,
                       "pidLeaseAcquired": False, "pidLeaseReleased": False, "cleanupComplete": False,
                       "observedImageBound": False, "nativeInputExecuted": False, "settingsChanged": False,
                       "activationRouteCoverageEstablished": False, "ipcRequestChainEstablished": False,
                       "perturbsObservedProcess": True, "C12": "HOLD", "releaseReady": False,
                       "bounds": {"observeAfterRecorderSeconds": OBSERVE_AFTER_SECONDS,
                                  "safeEndAfterHelperSpawnSeconds": SAFE_END_AFTER_HELPER_SPAWN,
                                  "requiredRemainingWindowSeconds": REQUIRED_WINDOW_SECONDS,
                                  "psCommandSeconds": PS_BUDGET_SECONDS, "sampleCommandSeconds": SAMPLE_BUDGET_SECONDS,
                                  "streamBytes": STREAM_LIMIT, "reportBytes": REPORT_LIMIT}}

    def attach(self, recorder, *, helper_started, prepared, cwd, env):
        if self.recorder is not None:
            raise startup.EvidenceError("A second recorder cannot be observed")
        self.recorder, self.cwd = recorder, cwd
        self.env = dict(env, LC_ALL="C", LANG="C")
        self.trigger = recorder.started + OBSERVE_AFTER_SECONDS
        self.safe_end = helper_started + SAFE_END_AFTER_HELPER_SPAWN
        self.report_path = cwd / "recorder-sample.txt"
        if self.report_path.exists() or self.report_path.is_symlink():
            raise startup.EvidenceError("Reserved sample report already exists")
        self.state = "scheduled"
        self.report.update(recorderPID=recorder.process.pid, recorderParentPID=os.getpid(), recorderUID=os.geteuid(),
                           recorderMonotonicStart=recorder.started, helperMonotonicStart=helper_started,
                           safeEndMonotonic=self.safe_end, triggerMonotonic=self.trigger,
                           bootUUID=prepared["bootUUID"], nonce=prepared["nonce"],
                           recordingNotificationName=prepared["recordingNotificationName"],
                           notificationOrder="unqualified-until-final-helper-receipt")

    def launch(self, name, argv, budget, limit=PS_STREAM_LIMIT):
        if name in self.commands:
            raise startup.EvidenceError("Observer command cannot be repeated")
        if name != "observer-groups" and time.monotonic() >= self.safe_end:
            self.cancel("original-window-bound")
            raise startup.EvidenceError("No target observation may begin after the original-window cutoff")
        self.active = ObservationCommand(argv, cwd=self.cwd, env=self.env, budget=budget, limit=limit)
        self.active_name = name
        self.commands[name] = self.active
        self.report["commands"][name] = self.active.transport.receipt
        if name == "observer-sample":
            self.report["sampleInvocationCount"] += 1

    def metadata(self, name):
        self.launch(name, ("/bin/ps", "-ww", "-p", str(self.recorder.process.pid), "-o", PS_FORMAT), PS_BUDGET_SECONDS)

    def cancel(self, reason):
        self.cancel_reason = self.cancel_reason or reason
        if self.active is not None and self.state != "group-check":
            self.active.stop(self.cancel_reason)

    def finalize_group(self):
        self.state = "group-check"
        self.launch("observer-groups", ("/bin/ps", "-A", "-o", "pid=,pgid=,stat="), PS_BUDGET_SECONDS)

    def command_ok(self, command):
        receipt = command.transport.receipt
        return (receipt["exitCode"] == 0 and receipt["status"] == "completed"
                and not receipt["cleanupFailed"] and not receipt["streamErrors"])

    def tick(self, *, helper_running, recorder_stopping):
        if self.done:
            return
        if not helper_running or recorder_stopping:
            self.cancel("helper-finished-or-recorder-stopping")
        now = time.monotonic()
        if self.state in ("awaiting-recorder", "scheduled"):
            if self.cancel_reason is not None:
                self.report.update(status="skipped-" + self.cancel_reason, cleanupComplete=True)
                self.done = True
                return
            if self.recorder is None or now < self.trigger:
                return
            if self.recorder.poll() is not None:
                self.report.update(status="skipped-recorder-already-exited", cleanupComplete=True)
                self.done = True
                return
            if now + REQUIRED_WINDOW_SECONDS > self.safe_end:
                self.report.update(status="skipped-insufficient-original-window", cleanupComplete=True)
                self.done = True
                return
            self.recorder.reap_deferred = True
            self.report.update(pidLeaseAcquired=True, pidLeaseClock=clock())
            self.state = "before"
            self.metadata("observer-identity-before")
        if now >= getattr(self, "safe_end", float("inf")) and self.state != "group-check":
            self.cancel("original-window-bound")
        if self.active is None:
            return
        # Growth/type checks happen while the sampler is active. The final
        # no-follow read independently rechecks the complete bounded report.
        if self.state == "sample" and self.cancel_reason is None:
            try:
                info = self.report_path.lstat()
                if not stat.S_ISREG(info.st_mode) or info.st_size > REPORT_LIMIT:
                    raise startup.EvidenceError("sample-report-type-or-size-bound")
            except FileNotFoundError:
                pass
            except (OSError, ValueError) as error:
                self.report["errors"].append("sample-report-growth-check: " + str(error))
                self.cancel("sample-report-growth-check-failed")
        self.active.tick()
        if not self.active.done:
            return
        completed, name = self.active, self.active_name
        self.active = None
        if self.state == "group-check":
            self.resolve_groups(completed)
            return
        if self.cancel_reason is not None or not self.command_ok(completed):
            self.report["errors"].append(name + ": " + completed.transport.receipt["status"])
            self.finalize_group()
            return
        try:
            if self.state in ("before", "after"):
                identity = parse_identity(bytes(completed.transport.streams["stdout"]), pid=self.recorder.process.pid,
                                          ppid=os.getpid(), pgid=self.recorder.process.pid, uid=os.geteuid())
                self.report[self.state + "Identity"] = identity
                if self.state == "before":
                    self.before = identity
                    self.state = "sample"
                    self.launch("observer-sample", ("/usr/bin/sample", str(self.recorder.process.pid), "1", "10",
                                "-mayDie", "-file", str(self.report_path)), SAMPLE_BUDGET_SECONDS, STREAM_LIMIT)
                else:
                    same = all(identity[key] == self.before[key] for key in ("pid", "ppid", "pgid", "uid", "startTime"))
                    self.report["processInstanceFieldsAgree"] = same
                    if not same:
                        raise startup.EvidenceError("Before/after process-instance fields changed")
                    self.finalize_group()
            elif self.state == "sample":
                raw = startup.read_regular(self.report_path, REPORT_LIMIT)
                self.report["sampleReport"] = {"name": "recorder-sample.txt", "bytes": len(raw), "sha256": startup.digest(raw)}
                self.report["observedImage"] = inspect_sample(raw, pid=self.recorder.process.pid)
                self.report["observedImageBound"] = True
                self.state = "after"
                self.metadata("observer-identity-after")
        except (OSError, ValueError) as error:
            self.report["errors"].append(str(error))
            self.finalize_group()

    def resolve_groups(self, command):
        resolved = False
        try:
            rows = [row.split() for row in bytes(command.transport.streams["stdout"]).decode("ascii").splitlines() if row.strip()]
            valid = bool(rows) and all(len(row) == 3 and row[0].isdigit() and row[1].isdigit() for row in rows)
            pgids = {c.transport.process.pid for c in self.commands.values() if c.transport.process is not None}
            members = [{"pid": int(row[0]), "pgid": int(row[1]), "state": row[2]}
                       for row in rows if valid and int(row[1]) in pgids
                       and int(row[0]) != command.transport.process.pid]
            self.report["observerGroupMembers"] = members
            resolved = (valid and self.command_ok(command) and not command.transport.streams["stderr"]
                        and all(row["state"].startswith("Z") for row in members)
                        and all(c.transport.process is None or c.transport.process.returncode is not None
                                for c in self.commands.values()))
        except (UnicodeDecodeError, ValueError) as error:
            self.report["errors"].append(str(error))
        if resolved:
            for name, observed in self.commands.items():
                receipt = observed.transport.receipt
                # Darwin can return EPERM for a zombie-only group after TERM.
                # Preserve that error and the interrupted classification. A
                # single independent positive snapshot can resolve only this
                # cleanup uncertainty; it cannot erase any other fault.
                if (name != "observer-groups" and receipt["cleanupFailed"]
                        and receipt["signalErrors"] and all(error["errno"] == errno.EPERM for error in receipt["signalErrors"])
                        and not receipt["cleanupFailureReasons"] and not receipt["streamErrors"]
                        and not receipt.get("inheritedStreamsStillOpen", True)
                        and receipt["exitCode"] is not None and receipt["stopReason"] is not None):
                    receipt["cleanupFailed"] = False
                    receipt["cleanupResolvedByGroupSnapshot"] = True
                    receipt["status"] = receipt["stopReason"]
        self.report["cleanupComplete"] = resolved and all(not c.transport.receipt["cleanupFailed"]
                                                        for c in self.commands.values())
        if self.report["cleanupComplete"]:
            self.recorder.reap_deferred = False
            self.report.update(pidLeaseReleased=True, pidLeaseReleasedClock=clock())
        else:
            self.recorder.receipt["cleanupFailed"] = True
            self.report["errors"].append("observer-group-cleanup-unresolved-target-PID-remains-pinned")
        self.done = True
        self.report["status"] = ("observed-image-and-process-instance" if self.report["cleanupComplete"]
                                 and self.report["observedImageBound"] and self.report.get("processInstanceFieldsAgree")
                                 and not self.report["errors"] and self.cancel_reason is None
                                 else "observation-incomplete")

    def finish(self):
        if not self.done:
            self.cancel("orchestrator-finalization")
            deadline = time.monotonic() + 2
            while not self.done and time.monotonic() < deadline:
                try:
                    self.tick(helper_running=False, recorder_stopping=True)
                except Exception as error:
                    self.report["errors"].append("Observer cleanup state: " + type(error).__name__ + ": " + str(error))
                    break
                time.sleep(.01)
            if not self.done:
                # Final exception cleanup is independent of report parsing,
                # filesystem checks and state transitions. Each transport still
                # owns its child and cannot signal a reaped process group.
                for command in self.commands.values():
                    command.stop("observer-finalization-fallback")
                emergency_end = time.monotonic() + 1
                while any(not command.done for command in self.commands.values()) and time.monotonic() < emergency_end:
                    for command in self.commands.values():
                        if not command.done:
                            command.tick()
                    time.sleep(.01)
                self.report["errors"].append("observer-finalization-unresolved")
                self.report["cleanupComplete"] = False
                self.report["status"] = "observation-incomplete"
                if self.recorder is not None:
                    self.recorder.receipt["cleanupFailed"] = True
                self.done = True
        # Close every transport before the first filesystem write, so a failed
        # evidence write cannot skip another owned child's stream cleanup.
        for command in self.commands.values():
            command.transport.close()
        for name, command in self.commands.items():
            startup.preserve_command(self.output, name, command.transport.receipt, command.transport.streams)
        if self.report_path is not None:
            try:
                raw = startup.read_regular(self.report_path, REPORT_LIMIT)
                with (self.output / "recorder-sample.txt").open("xb") as handle:
                    handle.write(raw)
                self.report["retainedSampleReport"] = {"name": "recorder-sample.txt", "bytes": len(raw), "sha256": startup.digest(raw)}
            except FileNotFoundError:
                pass
            except (OSError, ValueError) as error:
                self.report["errors"].append("Sample report retention: " + str(error))
                self.report["status"] = "observation-incomplete"
        self.report["cancelReason"] = self.cancel_reason
        write_json(self.output / "recorder-observation.json", self.report)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    for argument in ("staged", "output", "helper"):
        parser.add_argument("--" + argument, required=True, type=Path)
    args = parser.parse_args()
    if platform.system() != "Darwin":
        parser.error("Recorder observation requires native macOS")
    for name in ("staged", "output", "helper"):
        path = getattr(args, name)
        if not path.is_absolute() or path.resolve(strict=True) != path:
            parser.error("Require existing canonical absolute paths")
    if not args.staged.is_dir() or not args.output.is_dir() or not args.helper.is_file():
        parser.error("Require staged/output directories and built helper")
    if not (args.output / "build").is_dir() or not (args.output / "sources").is_dir():
        parser.error("Build/source provenance must precede observation")
    env = dict(os.environ, PAGER="cat", MANPAGER="cat", MANWIDTH="120", TERM="dumb", LC_ALL="C", LANG="C")
    checked = preflight(args.output, cwd=args.output, env=env)
    if not checked["passed"]:
        print("observer-preflight-incomplete", flush=True)
        return 1
    observer = RecorderObservation(args.output)
    result = startup.run(args.staged, args.output, args.helper, observer=observer)
    print("D20 transport: " + result["status"] + "; D21 observation: " + observer.report["status"], flush=True)
    return 0 if observer.report["status"] == "observed-image-and-process-instance" else 1


if __name__ == "__main__":
    raise SystemExit(main())
