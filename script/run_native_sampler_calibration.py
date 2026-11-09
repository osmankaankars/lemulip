#!/usr/bin/env python3
"""D22: calibrate the fixed bounded sampler against one owned native child."""

from __future__ import annotations

import argparse
import errno
import json
import math
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

from collect_native_trace_capabilities import write_json
import run_native_system_trace_startup as transport
import run_native_recorder_startup_observation as observation


EXPECTED_FRAME = "lemulip_d22_wait_for_release"
TRIGGER_SECONDS = 3.0
CUTOFF_SECONDS = 14.0
REQUIRED_WINDOW_SECONDS = 8.0
EOF_GRACE_SECONDS = 1.0
FORCED_CLEANUP_SECONDS = 1.0
HEX40 = re.compile(r"[0-9a-f]{40}")
HEX64 = re.compile(r"[0-9a-f]{64}")


def canonical_uuid(value):
    if not isinstance(value, str):
        raise transport.EvidenceError("Missing UUID")
    return str(uuid.UUID(value)).upper()


def validate_provenance(value, *, helper):
    if (value.get("schema") != 1 or value.get("diagnostic") != "D22-native-sampler-calibration"
            or value.get("architecture") not in ("arm64", "x86_64")
            or value["architecture"] != platform.machine()
            or value.get("expectedFrame") != EXPECTED_FRAME
            or not HEX40.fullmatch(value.get("experimentCommit", ""))
            or not HEX40.fullmatch(value.get("experimentTree", ""))
            or not HEX64.fullmatch(value.get("sourceSHA256", ""))):
        raise transport.EvidenceError("Invalid D22 source or architecture provenance")
    build = value.get("helper", {})
    if (build.get("path") != str(helper) or build.get("architecture") != value["architecture"]
            or not HEX64.fullmatch(build.get("sha256", ""))
            or canonical_uuid(build.get("uuid")) != build.get("uuid")):
        raise transport.EvidenceError("Invalid D22 helper build identity")
    if transport.digest(transport.read_regular(helper, 64 * 1024 * 1024)) != build["sha256"]:
        raise transport.EvidenceError("Helper bytes differ from build provenance")


def validate_native_receipt(value, *, kind, target, helper, provenance, nonce):
    if kind not in ("d22-sampler-calibration-ready", "d22-sampler-calibration-complete"):
        raise transport.EvidenceError("Unsupported D22 native receipt kind")
    expected = {"schema": 1, "kind": kind, "pid": target.process.pid, "ppid": os.getpid(),
                "pgid": target.process.pid, "euid": os.geteuid(), "nonce": nonce,
                "executablePath": str(helper), "executableSHA256": provenance["helper"]["sha256"],
                "machOUUID": provenance["helper"]["uuid"], "architecture": provenance["architecture"],
                "sourceSHA256": provenance["sourceSHA256"], "experimentCommit": provenance["experimentCommit"],
                "experimentTree": provenance["experimentTree"], "expectedFrame": EXPECTED_FRAME,
                "safetyTimeoutSeconds": 15, "identityValidated": True,
                "nativeInputExecuted": False, "settingsChanged": False,
                "applicationLaunchRequested": False, "recordingRequested": False}
    if any(type(value.get(key)) is not type(wanted) or value.get(key) != wanted for key, wanted in expected.items()):
        raise transport.EvidenceError("Native receipt instance/build/nonce identity differs")
    if kind == "d22-sampler-calibration-ready" and (value.get("expectedFrameEntered") is not True
                                                    or type(value.get("receivedInputBytes")) is not int
                                                    or value["receivedInputBytes"] != 0):
        raise transport.EvidenceError("Ready receipt does not bind entry to the input-free named frame")
    if (canonical_uuid(value.get("bootUUID")) != value.get("bootUUID")
            or any(type(value.get(name)) is not int or value[name] <= 0 for name in ("machTimebaseNumer", "machTimebaseDenom"))):
        raise transport.EvidenceError("Native boot/timebase identity is invalid")
    translation = value.get("translationProbe", {})
    if translation not in ({"returnCode": 0, "errno": 0, "value": 0},
                            {"returnCode": -1, "errno": errno.ENOENT, "value": None}):
        raise transport.EvidenceError("Native target translation probe is unqualified")
    clock_names = ["nativeStartClock", "readinessClock"]
    if kind == "d22-sampler-calibration-complete":
        clock_names.extend(("releaseClock", "completionClock"))
    previous = None
    for name in clock_names:
        clock = value.get(name, {})
        integers = ("machAbsoluteBefore", "machAbsoluteAfter", "machContinuousBefore", "machContinuousAfter", "wallTimeUnixNS")
        if (any(type(clock.get(field)) is not int or clock[field] <= 0 for field in integers)
                or type(clock.get("systemUptime")) not in (float, int) or not math.isfinite(clock["systemUptime"])
                or clock["systemUptime"] <= 0
                or clock["machAbsoluteBefore"] > clock["machAbsoluteAfter"]
                or clock["machContinuousBefore"] > clock["machContinuousAfter"]):
            raise transport.EvidenceError("Invalid native clock bracket: " + name)
        if previous is not None and (previous["machAbsoluteAfter"] > clock["machAbsoluteBefore"]
                                     or previous["machContinuousAfter"] > clock["machContinuousBefore"]
                                     or previous["systemUptime"] > clock["systemUptime"]):
            raise transport.EvidenceError("Native lifecycle clock order differs: " + name)
        previous = clock
    if kind == "d22-sampler-calibration-complete":
        elapsed = value.get("elapsedSeconds")
        expected_elapsed = ((value["completionClock"]["machContinuousAfter"] - value["nativeStartClock"]["machContinuousBefore"])
                            * value["machTimebaseNumer"] / value["machTimebaseDenom"] / 1e9)
        if (type(elapsed) not in (int, float) or not math.isfinite(elapsed) or not 0 <= elapsed < 15
                or abs(elapsed - expected_elapsed) > 1e-6):
            raise transport.EvidenceError("Native elapsed time does not bind the bounded lifecycle clocks")


def qualify_sample(raw, *, pid, helper, expected_uuid, architecture):
    """Accept only counted target-image frames inside an actual call-tree section."""
    image = observation.inspect_sample(raw, pid=pid)
    if image["observedPath"] != str(helper) or canonical_uuid(image["observedUUID"]) != expected_uuid:
        raise transport.EvidenceError("Sample image path or Mach-O UUID differs from the built target")
    text = raw.decode("utf-8")
    image_sections = list(re.finditer(r"(?m)^[ \t]*Binary Images:[ \t]*$", text))
    if len(image_sections) != 1:
        raise transport.EvidenceError("Sample must contain one binary-image section")
    code_types = re.findall(r"^Code Type:\s*([^\n\r]+?)\s*$", text, re.M)
    native_codes = ("ARM64", "ARM-64") if architecture == "arm64" else ("X86-64",)
    accepted_codes = {*native_codes, *(code + " (Native)" for code in native_codes)}
    if len(code_types) != 1 or code_types[0] not in accepted_codes:
        raise transport.EvidenceError("Sample does not identify the expected native architecture")
    starts = list(re.finditer(r"(?m)^[ \t]*Call graph:[ \t]*$", text))
    if len(starts) != 1 or image_sections[0].start() <= starts[0].end():
        raise transport.EvidenceError("Sample must contain one recognized call graph")
    rest = text[starts[0].end():]
    boundary = re.search(r"(?m)^[ \t]*(?:Total number in stack\b|Sort by top of stack\b|Binary Images:)", rest)
    if boundary is None:
        raise transport.EvidenceError("Call graph has no recognized end boundary")
    graph = rest[:boundary.start()]
    frame_pattern = (r"^[ \t+|!:]*(\d+)\s+" + re.escape(EXPECTED_FRAME)
                     + r"\s+\(in\s+" + re.escape(helper.name) + r"\)(?:\s|$)")
    frames = [{"sampleCount": int(match[1]), "line": match[0].rstrip()}
              for line in graph.splitlines()
              if (match := re.match(frame_pattern + r".*$", line)) is not None and int(match[1]) > 0]
    if not frames:
        raise transport.EvidenceError("No positive counted expected target frame exists in the call graph")
    return {"qualified": True, "image": image, "codeType": code_types[0], "architecture": architecture,
            "expectedFrame": EXPECTED_FRAME, "countedFrameWitnesses": frames,
            "scope": "controlled-child-sampler-and-report-path-only",
            "recorderImageOrStackQualified": False, "activationRouteCoverageEstablished": False}


class OwnedTarget(transport.MonitoredCommand):
    """D20's bounded pipe transport with a separately owned stdin EOF channel."""

    def __init__(self, argv, *, cwd, env):
        self.started = time.monotonic()
        self.streams = {"stdout": bytearray(), "stderr": bytearray()}
        self.selector = selectors.DefaultSelector()
        self.process = None
        self.reap_deferred = True
        self.closed = False
        self.selector_failed = False
        self.stdin_closed = False
        self.receipt = {"argv": list(argv), "pid": None, "status": "running", "exitCode": None,
                        "maximumCombinedBytes": observation.STREAM_LIMIT, "observedBytes": 0, "retainedBytes": 0,
                        "stopReason": None, "signals": [], "signalErrors": [], "streamErrors": [],
                        "cleanupFailed": False, "stdinBytesSent": 0, "stdinEOFRequested": False,
                        "forcedCleanupUsed": False, "clockBeforeSpawn": observation.clock()}
        try:
            self.process = subprocess.Popen(tuple(argv), cwd=cwd, env=env, stdin=subprocess.PIPE,
                                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
        except (OSError, subprocess.SubprocessError) as error:
            self.receipt.update(status="spawn-error", error=str(error))
            return
        self.receipt["pid"] = self.process.pid
        try:
            for name, pipe in (("stdout", self.process.stdout), ("stderr", self.process.stderr)):
                os.set_blocking(pipe.fileno(), False)
                self.selector.register(pipe, selectors.EVENT_READ, name)
        except Exception as error:
            self.stream_error("setup", error)

    def request_eof(self):
        if self.process is None or self.stdin_closed:
            return
        self.receipt["stdinEOFRequested"] = True
        self.receipt["stdinEOFClock"] = observation.clock()
        try:
            self.process.stdin.close()
            self.stdin_closed = True
            self.receipt["stdinEOFDelivered"] = True
        except Exception as error:
            self.stream_error("close-stdin", error)
            self.stdin_closed = bool(getattr(self.process.stdin, "closed", False))
            self.receipt["stdinEOFDelivered"] = self.stdin_closed

    def close(self):
        if self.closed:
            return
        if self.process is not None and not self.stdin_closed:
            try:
                self.process.stdin.close()
                self.stdin_closed = True
            except Exception as error:
                self.stream_error("final-close-stdin", error)
                self.stdin_closed = bool(getattr(self.process.stdin, "closed", False))
        # Do not dispatch through a potentially failed target drain override
        # while closing independent stream resources.
        try:
            transport.MonitoredCommand.drain(self)
        except Exception as error:
            self.stream_error("final-drain", error)
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
        self.receipt["stdinClosed"] = self.stdin_closed
        if self.receipt["cleanupFailed"]:
            self.receipt["status"] = "cleanup-incomplete"
        elif self.receipt["status"] != "spawn-error":
            self.receipt["status"] = self.receipt["stopReason"] or ("completed" if self.receipt["exitCode"] == 0 else "nonzero")


def drain_target(target):
    """A broken target override cannot bypass the inherited bounded drain."""
    try:
        if target.receipt.get("outerDrainFailed"):
            transport.MonitoredCommand.drain(target)
        else:
            target.drain()
    except Exception as error:
        target.receipt["outerDrainFailed"] = True
        target.stream_error("outer-target-drain", error)
        target.receipt["cleanupFailed"] = True
        try:
            transport.MonitoredCommand.drain(target)
        except Exception as fallback_error:
            target.stream_error("fallback-target-drain", fallback_error)


def command_completed(command):
    receipt = command.transport.receipt
    return (receipt["status"] == "completed" and receipt["exitCode"] == 0
            and receipt["stopReason"] is None and not receipt["signals"] and not receipt["signalErrors"]
            and not receipt["streamErrors"] and not receipt["cleanupFailed"])


def emergency_command_cleanup(command, reason):
    """Transport-only fallback, also for checkers spawned inside finalization."""
    owned = command.transport
    owned.receipt["cleanupFailed"] = True
    owned.receipt["cleanupFailureReasons"].append(reason)
    owned.receipt["stopReason"] = owned.receipt["stopReason"] or reason
    if owned.process is not None and owned.process.returncode is None:
        try:
            owned.signal(signal.SIGKILL, group=True)
        except Exception as error:
            owned.receipt["emergencyKillError"] = type(error).__name__ + ": " + str(error)
    end = time.monotonic() + FORCED_CLEANUP_SECONDS
    while time.monotonic() < end:
        try:
            owned.drain()
            exited = owned.process is None or owned.poll() is not None
            if exited and not owned.selector.get_map():
                break
        except Exception as error:
            owned.receipt["emergencyDrainError"] = type(error).__name__ + ": " + str(error)
            break
        time.sleep(.01)
    command.done = owned.process is None or owned.process.returncode is not None
    owned.receipt["inheritedStreamsStillOpen"] = bool(owned.selector.get_map())
    try:
        owned.close()
    except Exception as error:
        owned.receipt["emergencyCloseError"] = type(error).__name__ + ": " + str(error)


def group_proof(commands, checker, *, extra_pgids=()):
    receipt = {"status": "unresolved", "members": [], "clock": observation.clock()}
    try:
        rows = [row.split() for row in bytes(checker.transport.streams["stdout"]).decode("ascii").splitlines() if row.strip()]
        valid = bool(rows) and all(len(row) == 3 and row[0].isdigit() and row[1].isdigit() for row in rows)
        pgids = {command.transport.process.pid for command in commands.values() if command.transport.process is not None}
        pgids.update(extra_pgids)
        members = [{"pid": int(row[0]), "pgid": int(row[1]), "state": row[2]}
                   for row in rows if valid and int(row[1]) in pgids
                   and int(row[0]) != checker.transport.process.pid]
        receipt["members"] = members
        resolved = (valid and command_completed(checker) and not checker.transport.streams["stderr"]
                    and all(row["state"].startswith("Z") for row in members)
                    and all(command.transport.process is None or command.transport.process.returncode is not None
                            for command in commands.values()))
        if resolved:
            for command in commands.values():
                value = command.transport.receipt
                if (value["cleanupFailed"] and value["signalErrors"]
                        and all(error["errno"] == errno.EPERM for error in value["signalErrors"])
                        and not value["cleanupFailureReasons"] and not value["streamErrors"]
                        and not value.get("inheritedStreamsStillOpen", True)
                        and value["exitCode"] is not None and value["stopReason"] is not None):
                    value["cleanupFailed"] = False
                    value["cleanupResolvedByGroupSnapshot"] = True
                    value["status"] = value["stopReason"]
            resolved = all(not command.transport.receipt["cleanupFailed"] for command in commands.values())
        if resolved:
            receipt["status"] = "no-live-owned-group-members-observed"
    except (UnicodeDecodeError, ValueError) as error:
        receipt["error"] = str(error)
    return receipt


def helper_command(helper, *, ready, completion, nonce, provenance):
    return (str(helper), "--ready", str(ready), "--completion", str(completion), "--nonce", nonce,
            "--expected-executable", str(helper), "--expected-sha256", provenance["helper"]["sha256"],
            "--expected-uuid", provenance["helper"]["uuid"], "--expected-architecture", provenance["architecture"],
            "--source-sha256", provenance["sourceSHA256"], "--experiment-commit", provenance["experimentCommit"],
            "--experiment-tree", provenance["experimentTree"])


def cleanup_target(target, *, observer_groups_resolved):
    """Cooperative EOF first only after observer cleanup; any force disqualifies."""
    if target is None or target.process is None:
        return
    if observer_groups_resolved:
        target.request_eof()
        end = time.monotonic() + EOF_GRACE_SECONDS
        while time.monotonic() < end:
            drain_target(target)
            if not target.selector.get_map():
                target.reap_deferred = False
                if target.poll() is not None:
                    break
            time.sleep(.01)
    if target.process.returncode is None:
        target.receipt["forcedCleanupUsed"] = True
        target.receipt["stopReason"] = target.receipt["stopReason"] or "target-cooperative-cleanup-unresolved"
        target.signal(signal.SIGTERM, group=True)
        term_at = time.monotonic()
        killed = False
        while time.monotonic() - term_at < FORCED_CLEANUP_SECONDS:
            drain_target(target)
            if not killed and time.monotonic() - term_at >= observation.TERM_GRACE_SECONDS:
                target.signal(signal.SIGKILL, group=True)
                killed = True
            if killed or target.receipt["signalErrors"]:
                # If observer group cleanup is unresolved, preserve the numeric
                # target reservation even through emergency termination.
                if observer_groups_resolved:
                    target.reap_deferred = False
                    target.poll()
                if target.process.returncode is not None and not target.selector.get_map():
                    break
            time.sleep(.01)
    drain_target(target)
    target.receipt["inheritedStreamsStillOpen"] = bool(target.selector.get_map())
    target.receipt["cleanupFailed"] = (target.process.returncode is None or bool(target.selector.get_map())
                                       or bool(target.receipt["streamErrors"]))
    target.receipt["pidLeaseReleased"] = not target.reap_deferred
    target.receipt["clockAfterCleanup"] = observation.clock()


def run(helper, output, provenance_path):
    provenance, provenance_raw = transport.read_object(provenance_path, observation.STREAM_LIMIT)
    validate_provenance(provenance, helper=helper)
    work = output.parent / "work"
    work.mkdir(exist_ok=False)
    ready_path, completion_path = output / "target-ready.json", output / "target-completion.json"
    sample_path = work / "controlled-sample.txt"
    for path in (ready_path, completion_path, output / "sampler-calibration.json", sample_path):
        if path.exists() or path.is_symlink():
            raise transport.EvidenceError("Reserved D22 output already exists: " + path.name)
    nonce = str(uuid.uuid4()).upper()
    report = {"schema": 1, "diagnostic": "D22-native-sampler-calibration", "status": "calibration-incomplete",
              "nonce": nonce, "architecture": provenance["architecture"], "experimentCommit": provenance["experimentCommit"],
              "experimentTree": provenance["experimentTree"], "sourceSHA256": provenance["sourceSHA256"],
              "helper": provenance["helper"], "provenance": {"bytes": len(provenance_raw), "sha256": transport.digest(provenance_raw)},
              "commands": {}, "errors": [], "sampleInvocationCount": 0, "helperStarted": False,
              "controlledSamplerCalibrationComplete": False, "observerCleanupComplete": False, "targetCleanupComplete": False,
              "recordingExecuted": False, "nativeApplicationsLaunched": False, "nativeInputExecuted": False,
              "settingsChanged": False, "recorderImageOrStackQualified": False, "activationRouteCoverageEstablished": False,
              "ipcRequestChainEstablished": False, "C12": "HOLD", "releaseReady": False,
              "bounds": {"triggerAfterTargetSpawnSeconds": TRIGGER_SECONDS, "cutoffAfterParentBeforeSpawnSeconds": CUTOFF_SECONDS,
                         "requiredRemainingWindowSeconds": REQUIRED_WINDOW_SECONDS, "sampleTotalSeconds": observation.SAMPLE_BUDGET_SECONDS,
                         "sampleNormalSeconds": observation.SAMPLE_BUDGET_SECONDS - observation.CLEANUP_RESERVE_SECONDS,
                         "psTotalSeconds": observation.PS_BUDGET_SECONDS, "streamBytes": observation.STREAM_LIMIT,
                         "reportBytes": observation.REPORT_LIMIT, "targetEOFGraceSeconds": EOF_GRACE_SECONDS,
                         "targetForcedCleanupSeconds": FORCED_CLEANUP_SECONDS}}
    write_json(output / "calibration-scope.json", report)
    env = dict(os.environ, PAGER="cat", MANPAGER="cat", MANWIDTH="120", TERM="dumb", LC_ALL="C", LANG="C")
    target, commands, ready_raw, ready = None, {}, b"", None
    observation_ok = False
    cutoff = None

    def execute(name, argv, *, budget, limit, target_observation=True):
        if name in commands:
            raise transport.EvidenceError("A D22 command cannot be repeated")
        if target_observation and time.monotonic() >= cutoff:
            raise transport.EvidenceError("No observation command may start after the fixed cutoff")
        if target_observation and (completion_path.exists() or not target.selector.get_map()):
            raise transport.EvidenceError("No observation may start after controlled target completion")
        command = observation.ObservationCommand(argv, cwd=work, env=env, budget=budget, limit=limit)
        commands[name] = command
        report["commands"][name] = command.transport.receipt
        if name == "sample":
            report["sampleInvocationCount"] += 1
        try:
            while not command.done:
                if target is not None:
                    drain_target(target)
                if target_observation and time.monotonic() >= cutoff:
                    command.stop("fixed-observation-cutoff")
                if target_observation and (completion_path.exists() or not target.selector.get_map()):
                    command.stop("controlled-target-completed-during-observation")
                if target_observation and target.receipt["stopReason"] in ("stream-error", "output-limit"):
                    command.stop("target-transport-failed")
                if name == "sample" and command.term_at is None:
                    try:
                        info = sample_path.lstat()
                        if not stat.S_ISREG(info.st_mode) or info.st_size > observation.REPORT_LIMIT:
                            raise transport.EvidenceError("Sample report exceeds type/size bound")
                    except FileNotFoundError:
                        pass
                    except (OSError, ValueError) as error:
                        report["errors"].append(str(error))
                        command.stop("sample-report-bound-or-read-failure")
                command.tick()
                if not command.done:
                    time.sleep(.01)
        except Exception:
            emergency_command_cleanup(command, "command-exception")
            raise
        return command

    def prove_observer_cleanup():
        if "observer-groups" in commands:
            return report.get("observerGroupProof", {}).get("status") == "no-live-owned-group-members-observed"
        if not commands:
            report["observerGroupProof"] = {"status": "no-observer-children-created"}
            return True
        check = execute("observer-groups", ("/bin/ps", "-A", "-o", "pid=,pgid=,stat="),
                        budget=observation.PS_BUDGET_SECONDS, limit=observation.PS_STREAM_LIMIT, target_observation=False)
        proof = group_proof(commands, check)
        report["observerGroupProof"] = proof
        return proof["status"] == "no-live-owned-group-members-observed"

    try:
        preflight = observation.preflight(output, cwd=work, env=env)
        report["manualPreflightPassed"] = preflight["passed"]
        if not preflight["passed"]:
            raise transport.EvidenceError("Installed manual preflight did not qualify the unchanged command")
        parent_before_spawn = time.monotonic()
        cutoff = parent_before_spawn + CUTOFF_SECONDS
        target = OwnedTarget(helper_command(helper, ready=ready_path, completion=completion_path, nonce=nonce,
                                           provenance=provenance), cwd=work, env=env)
        if target.process is None:
            raise transport.EvidenceError("Controlled target could not start")
        report.update(helperStarted=True, targetPID=target.process.pid, targetParentPID=os.getpid(),
                      parentBeforeSpawnMonotonic=parent_before_spawn, targetMonotonicStart=target.started,
                      triggerMonotonic=target.started + TRIGGER_SECONDS, cutoffMonotonic=cutoff,
                      pidLeaseAcquired=True, pidLeaseClock=observation.clock())
        ready = None
        while time.monotonic() < target.started + TRIGGER_SECONDS:
            drain_target(target)
            if target.receipt["stopReason"] is not None:
                raise transport.EvidenceError("Controlled target transport failed before observation")
            if ready is None and ready_path.exists():
                ready, ready_raw = transport.read_object(ready_path, 262144)
                validate_native_receipt(ready, kind="d22-sampler-calibration-ready", target=target,
                                        helper=helper, provenance=provenance, nonce=nonce)
                report["readyReceipt"] = {"name": ready_path.name, "bytes": len(ready_raw), "sha256": transport.digest(ready_raw)}
            time.sleep(.01)
        if ready is None:
            raise transport.EvidenceError("No valid ready receipt preceded the fixed observation point")
        if time.monotonic() + REQUIRED_WINDOW_SECONDS > cutoff:
            raise transport.EvidenceError("Insufficient original observation window remains")
        before_command = execute("identity-before", ("/bin/ps", "-ww", "-p", str(target.process.pid), "-o", observation.PS_FORMAT),
                                 budget=observation.PS_BUDGET_SECONDS, limit=observation.PS_STREAM_LIMIT)
        if not command_completed(before_command):
            raise transport.EvidenceError("Initial exact-process identity command did not complete")
        before = observation.parse_identity(bytes(before_command.transport.streams["stdout"]), pid=target.process.pid,
                                            ppid=os.getpid(), pgid=target.process.pid, uid=os.geteuid())
        report["beforeIdentity"] = before
        sample = execute("sample", ("/usr/bin/sample", str(target.process.pid), "1", "10", "-mayDie", "-file", str(sample_path)),
                         budget=observation.SAMPLE_BUDGET_SECONDS, limit=observation.STREAM_LIMIT)
        if not command_completed(sample):
            raise transport.EvidenceError("Sampler did not finish successfully without interruption")
        raw = transport.read_regular(sample_path, observation.REPORT_LIMIT)
        report["sampleQualification"] = qualify_sample(raw, pid=target.process.pid, helper=helper,
                                                       expected_uuid=provenance["helper"]["uuid"], architecture=provenance["architecture"])
        report["qualifiedSampleReport"] = {"name": "controlled-sample.txt", "bytes": len(raw), "sha256": transport.digest(raw)}
        after_command = execute("identity-after", ("/bin/ps", "-ww", "-p", str(target.process.pid), "-o", observation.PS_FORMAT),
                                budget=observation.PS_BUDGET_SECONDS, limit=observation.PS_STREAM_LIMIT)
        if not command_completed(after_command):
            raise transport.EvidenceError("Final exact-process identity command did not complete")
        after = observation.parse_identity(bytes(after_command.transport.streams["stdout"]), pid=target.process.pid,
                                           ppid=os.getpid(), pgid=target.process.pid, uid=os.geteuid())
        report["afterIdentity"] = after
        if any(before[key] != after[key] for key in ("pid", "ppid", "pgid", "uid", "startTime")):
            raise transport.EvidenceError("Target process-instance fields changed")
        report["processInstanceFieldsAgree"] = True
        if time.monotonic() >= cutoff:
            raise transport.EvidenceError("Target observation exceeded its fixed cutoff")
        observation_ok = True
    except Exception as error:
        report["errors"].append(type(error).__name__ + ": " + str(error))
    finally:
        # Drive cleanup without reentering report parsing. All known observer
        # children retain their Popen ownership through this fallback.
        faulted_commands = set()
        for name, command in commands.items():
            if not command.done:
                try:
                    command.stop("calibration-finalization")
                except Exception as error:
                    report["errors"].append("Observer stop: " + name + ": " + str(error))
                    faulted_commands.add(name)
                    command.transport.receipt["cleanupFailed"] = True
        end = time.monotonic() + FORCED_CLEANUP_SECONDS
        while any(not command.done for command in commands.values()) and time.monotonic() < end:
            for name, command in commands.items():
                if command.done:
                    continue
                try:
                    if name in faulted_commands:
                        owned = command.transport
                        if not owned.receipt.get("exceptionalKillAttempted"):
                            owned.receipt["exceptionalKillAttempted"] = True
                            if owned.process is not None and owned.process.returncode is None:
                                owned.signal(signal.SIGKILL, group=True)
                        owned.drain()
                        command.done = owned.process is None or owned.poll() is not None
                    else:
                        command.tick()
                except Exception as error:
                    if name not in faulted_commands:
                        report["errors"].append("Observer cleanup: " + name + ": " + str(error))
                    faulted_commands.add(name)
                    command.transport.receipt["cleanupFailed"] = True
            if target is not None:
                drain_target(target)
            time.sleep(.01)
        try:
            report["observerCleanupComplete"] = prove_observer_cleanup()
        except Exception as error:
            report["errors"].append("Observer cleanup proof: " + type(error).__name__ + ": " + str(error))
        try:
            cleanup_target(target, observer_groups_resolved=report["observerCleanupComplete"])
        except Exception as error:
            report["errors"].append("Target cleanup: " + type(error).__name__ + ": " + str(error))
            if target is not None:
                target.receipt["cleanupFailed"] = True
                target.receipt["forcedCleanupUsed"] = True
                # An unexpected cleanup failure cannot skip the one remaining
                # safe owned-group kill attempt or stream closure.
                if target.process is not None and target.process.returncode is None:
                    try:
                        target.signal(signal.SIGKILL, group=True)
                    except OSError as kill_error:
                        report["errors"].append("Target emergency kill: " + str(kill_error))
        if target is not None and target.process is not None:
            try:
                check = execute("target-groups", ("/bin/ps", "-A", "-o", "pid=,pgid=,stat="),
                                budget=observation.PS_BUDGET_SECONDS, limit=observation.PS_STREAM_LIMIT, target_observation=False)
                proof = group_proof({"target-groups": check}, check, extra_pgids=(target.process.pid,))
                report["targetGroupProof"] = proof
                report["targetCleanupComplete"] = (proof["status"] == "no-live-owned-group-members-observed"
                                                    and not target.receipt["cleanupFailed"])
            except Exception as error:
                report["errors"].append("Target cleanup proof: " + type(error).__name__ + ": " + str(error))
        for command in commands.values():
            try:
                command.transport.close()
            except Exception as error:
                command.transport.receipt["cleanupFailed"] = True
                report["errors"].append("Observer transport close: " + str(error))
                try:
                    transport.MonitoredCommand.close(command.transport)
                except Exception as fallback_error:
                    report["errors"].append("Observer fallback close: " + str(fallback_error))
        if target is not None:
            try:
                target.close()
            except Exception as error:
                target.receipt["cleanupFailed"] = True
                target.stream_error("outer-target-close", error)
                report["errors"].append("Target transport close: " + str(error))
                try:
                    if target.process is not None:
                        target.process.stdin.close()
                    transport.MonitoredCommand.close(target)
                except Exception as fallback_error:
                    target.stream_error("fallback-target-close", fallback_error)
            report["target"] = target.receipt
        # Filesystem failures below cannot bypass owned process/stream cleanup.
        for name, command in commands.items():
            try:
                transport.preserve_command(output, name, command.transport.receipt, command.transport.streams)
            except OSError as error:
                report["errors"].append("Command evidence write: " + name + ": " + str(error))
        if target is not None:
            try:
                transport.preserve_command(output, "target", target.receipt, target.streams)
            except OSError as error:
                report["errors"].append("Target evidence write: " + str(error))
        try:
            raw = transport.read_regular(sample_path, observation.REPORT_LIMIT)
            with (output / "controlled-sample.txt").open("xb") as handle:
                handle.write(raw)
            report["sampleReport"] = {"name": "controlled-sample.txt", "bytes": len(raw), "sha256": transport.digest(raw)}
            if "qualifiedSampleReport" in report and report["sampleReport"] != report["qualifiedSampleReport"]:
                raise transport.EvidenceError("Retained sample bytes differ from the report that was qualified")
        except FileNotFoundError:
            pass
        except (OSError, ValueError) as error:
            report["errors"].append("Sample evidence retention: " + str(error))
    if target is not None and target.process is not None:
        try:
            completion, completion_raw = transport.read_object(completion_path, 262144)
            validate_native_receipt(completion, kind="d22-sampler-calibration-complete", target=target,
                                    helper=helper, provenance=provenance, nonce=nonce)
            if (completion.get("reason") != "stdin-eof" or type(completion.get("receivedInputBytes")) is not int
                    or completion["receivedInputBytes"] != 0
                    or completion.get("cooperativeEOFObserved") is not True
                    or completion.get("safetyTimeoutExpired") is not False
                    or completion.get("finalIdentityMatches") is not True or type(completion.get("exitCode")) is not int
                    or completion["exitCode"] != 0
                    or completion.get("readyReceiptSHA256") != transport.digest(ready_raw)
                    or completion.get("readyReceiptBytes") != len(ready_raw)):
                raise transport.EvidenceError("Native target did not bind a normal, input-free ready-to-EOF lifecycle")
            if not isinstance(ready, dict) or any(completion.get(key) != ready.get(key) for key in
                   ("bootUUID", "machTimebaseNumer", "machTimebaseDenom", "nativeStartClock", "readinessClock")):
                raise transport.EvidenceError("Completion boot/start-clock identity differs from readiness")
            report["completionReceipt"] = {"name": completion_path.name, "bytes": len(completion_raw), "sha256": transport.digest(completion_raw)}
        except (OSError, ValueError) as error:
            report["errors"].append("Completion receipt: " + str(error))
    try:
        report["immutableInputsUnchanged"] = (transport.digest(transport.read_regular(helper, 64 * 1024 * 1024)) == provenance["helper"]["sha256"]
                                               and transport.read_regular(provenance_path, observation.STREAM_LIMIT) == provenance_raw)
    except (OSError, ValueError) as error:
        report["immutableInputsUnchanged"] = False
        report["errors"].append(str(error))
    try:
        report["readyReceiptUnchanged"] = bool(ready_raw) and transport.read_regular(ready_path, 262144) == ready_raw
    except (OSError, ValueError) as error:
        report["readyReceiptUnchanged"] = False
        report["errors"].append("Retained ready receipt: " + str(error))
    normal_target = (target is not None and target.receipt["exitCode"] == 0 and target.receipt["status"] == "completed"
                     and target.receipt["stdinEOFRequested"] and not target.receipt["forcedCleanupUsed"]
                     and not target.receipt["signals"] and not target.receipt["signalErrors"] and not target.receipt["streamErrors"])
    qualified = (observation_ok and report["sampleInvocationCount"] == 1 and report["observerCleanupComplete"]
                 and report["targetCleanupComplete"] and normal_target and report["immutableInputsUnchanged"]
                 and report["readyReceiptUnchanged"]
                 and "completionReceipt" in report and report.get("sampleReport") == report.get("qualifiedSampleReport")
                 and not report["errors"])
    report["controlledSamplerCalibrationComplete"] = qualified
    report["status"] = "controlled-sampler-qualified" if qualified else "calibration-incomplete"
    write_json(output / "sampler-calibration.json", report)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("helper", "output", "provenance"):
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    if platform.system() != "Darwin":
        parser.error("Controlled native sampler calibration requires macOS")
    for name in ("helper", "output", "provenance"):
        path = getattr(args, name)
        if not path.is_absolute() or path.resolve(strict=True) != path:
            parser.error("Require existing canonical absolute paths")
    if not args.helper.is_file() or not args.provenance.is_file() or not args.output.is_dir():
        parser.error("Require helper/provenance files and an existing output directory")
    for name in ("build", "sources"):
        directory = args.output / name
        if not directory.is_dir() or directory.resolve(strict=True) != directory:
            parser.error("Existing canonical build/source provenance directories must precede calibration")
    report = run(args.helper, args.output, args.provenance)
    print(report["status"], flush=True)
    return 0 if report["controlledSamplerCalibrationComplete"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
