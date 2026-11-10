#!/usr/bin/env python3
"""D30: one finite Intel macOS qualification using disposable Python fixtures.

Project modules are imported only after source and interpreter fingerprints.
This collector invokes no Apple tracing tool, GUI input or existing trace.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import stat
import subprocess
import sys
import time
import zipfile

BASE = "35e83645c036f90aa1678aca51ad2323d33044e4"
BASE_TREE = "e147d3d924f644615dac7571599166746020b46d"
WORKFLOW = ".github/workflows/isolated-atrc-macos-qualification.yml"
CASES = ("success", "pending-exit", "deadline", "exit-seven", "descendant", "pressure")
NEW_PATHS = (
    WORKFLOW, "script/run_isolated_atrc_macos_qualification.py",
    "script/test_run_isolated_atrc_macos_qualification.py",
    "script/isolated_atrc_macos_fixture.py", "script/isolated_atrc_macos_worker_fixture.py",
    "script/test_isolated_atrc_macos_fixture.py",
    "script/qualify_isolated_atrc_pressure.py", "script/test_qualify_isolated_atrc_pressure.py",
    "docs/ISOLATED_ATRC_MACOS_QUALIFICATION.md",
    "docs/evidence/D30-isolated-atrc-macos.json", "docs/evidence/D30-verification.json",
)
FIXED_RUNTIME = {
    "script/native_retained_atrc_isolated.py": "4e0abd41326d3d7be8a5e8826a572fcce445250d379659d8a4d1781ec195d103",
    "script/native_retained_atrc_worker.py": "585aa89d051f983afadcea7f425064575bd3643357b0e4400c786220771a3b0e",
}
PS_ARGV = ("/bin/ps", "-A", "-o", "pid=,pgid=,stat=")
MAX_JSON = 16 * 1024 * 1024
SOURCE_TOTAL = 16 * 1024 * 1024


def require(condition, message):
    if not condition:
        raise ValueError(message)


def integer(value):
    return type(value) is int and 0 < value < 2**63


def clock_interval(value):
    if not isinstance(value, dict):
        return None
    lo, hi = value.get("monotonicBeforeNS"), value.get("monotonicAfterNS")
    return (lo, hi) if integer(lo) and integer(hi) and lo <= hi else None


def parse_ps(raw):
    require(type(raw) is bytes and 0 < len(raw) <= 65536, "Invalid ps stream bound")
    rows = []
    for line in raw.decode("ascii", errors="strict").splitlines():
        if not line.strip():
            continue
        parts = line.split()
        require(len(parts) == 3 and parts[0].isdigit() and parts[1].isdigit()
                and re.fullmatch(r"[A-Za-z+<=>NsXWwEl]+", parts[2]), "Invalid ps row")
        pid, pgid = int(parts[0]), int(parts[1])
        require(pid > 0 and pgid >= 0, "Invalid ps identity")
        rows.append({"pid": pid, "pgid": pgid, "state": parts[2]})
    require(rows and len({r["pid"] for r in rows}) == len(rows), "Empty or duplicated ps identities")
    return rows


def probe_records(cleanup_records):
    return [r for r in cleanup_records
            if tuple(r.get("receipt", {}).get("intendedArgv", ())) == PS_ARGV]


def clean_probe(record):
    r = record.get("receipt", {})
    return (r.get("pidLeaseReleased") is True and r.get("pidLeaseLost") is False
            and r.get("exitObservedWithoutReap") is True and type(r.get("exitCode")) is int
            and r["exitCode"] == 0 and r.get("stopReason") is None
            and r.get("cleanupFailed") is False and r.get("streamErrors") == []
            and record.get("streams", {}).get("stderr") == b"")


def owned_children_accounted(receipt, cleanup_records):
    """Safety evidence for every launched child, separate from case outcome."""
    try:
        children = [receipt.get(key) for key in ("target", "worker")]
        children = [r for r in children if isinstance(r, dict) and r.get("pid") is not None]
        probes = probe_records(cleanup_records)
        if not children or not probes or not all(clean_probe(p) for p in probes):
            return False
        inventories = [parse_ps(p["streams"]["stdout"]) for p in probes]
        groups = receipt["finalOwnedGroups"]
        for child in children:
            pid = child.get("pid")
            if (not integer(pid) or child.get("pidLeaseReleased") is not True
                    or child.get("pidLeaseLost") is not False
                    or child.get("exitObservedWithoutReap") is not True
                    or child.get("pidDirectedActionsRevoked") is not True
                    or child.get("cleanupFailed") is not False
                    or child.get("streamErrors") != []
                    or child.get("inheritedStreamsStillOpen") is not False):
                return False
            matches = [g for g in groups.values() if g.get("pgid") == pid]
            if len(matches) != 1:
                return False
            group = matches[0]
            members = group.get("members", [])
            leader = [r for r in members if r.get("pid") == pid and r.get("pgid") == pid]
            if (group.get("pidLeaseHeldAtSnapshot") is not True
                    or group.get("noLiveMembersObserved") is not True
                    or len(leader) != 1 or not leader[0].get("state", "").startswith("Z")
                    or not all(r.get("pgid") == pid and r.get("state", "").startswith("Z") for r in members)):
                return False
            if [r for r in inventories[-1] if r["pgid"] == pid] != members:
                return False
        return True
    except (KeyError, TypeError, ValueError, UnicodeError, AttributeError):
        return False


def classify_case(name, receipt, streams, cleanup_records, controls, retention=None):
    """Classify observed receipts; expected negative capture is never a PASS capture."""
    checks = {}
    def check(key, value):
        checks[key] = bool(value)
    try:
        require(name in CASES[:-1], "Unknown adapter case")
        target, worker, observer = receipt.get("target"), receipt.get("worker"), receipt["observer"]
        check("both_children_started", isinstance(target, dict) and isinstance(worker, dict)
              and integer(target.get("pid")) and integer(worker.get("pid")))
        check("owned_children_accounted", owned_children_accounted(receipt, cleanup_records))
        check("explicit_synthetic_controls", receipt.get("testControlsUsed") is True)
        check("startup_complete", receipt.get("startupComplete") is True)
        check("no_target_stderr", streams.get("stderr") == b"")
        observed = controls.get("probeLeaseObservations", [])
        latest = probe_records(cleanup_records)[-1]["name"]
        matching_observations = [p for p in observed if p.get("probeName") == latest]
        latest_receipt = probe_records(cleanup_records)[-1]["receipt"]
        probe_before = clock_interval(latest_receipt.get("clockBeforeSpawn"))
        probe_after = clock_interval(latest_receipt.get("clockAtSpawn"))
        check("both_leases_peeked_before_probe", len(matching_observations) == 1 and all(any(
            row.get("pid") == child["pid"] and row.get("pgid") == child["pid"]
            and row.get("waitable") is True and row.get("returncodeBeforeProbe") is None
            and integer(row.get("observedClockNS"))
            and clock_interval(child.get("collectionStartedClock"))
            and row["observedClockNS"] < clock_interval(child["collectionStartedClock"])[0]
            and probe_before and probe_after
            and probe_before[0] <= row["observedClockNS"] <= probe_after[1]
            for probe in matching_observations for row in probe.get("children", []))
            for child in (target, worker) if isinstance(child, dict)))
        failure = observer.get("failure")
        if name == "success":
            check("successful_capture", all(receipt.get(k) is True for k in
                  ("transportComplete", "observationComplete", "cleanupComplete", "finalFreshScanComplete"))
                  and target.get("exitCode") == 0 and worker.get("exitCode") == 0
                  and target.get("stopReason") is None and worker.get("stopReason") is None
                  and observer.get("stopped") is True and failure is None)
            initial, final = receipt["initialScanGeneration"], receipt["finalScanGeneration"]
            rows = observer["scanHistory"]["records"]
            first = next(r for r in rows if r["request"]["scan"] == initial)
            last = next(r for r in rows if r["request"]["scan"] == final)
            spawn = clock_interval(target["clockBeforeSpawn"])
            done = clock_interval(target["operationDoneClock"])
            check("initial_empty_before_target", first["completed"] is True
                  and first["report"]["totals"]["entries"] == 1
                  and first["report"]["totals"]["logicalBytes"] == 0
                  and spawn and first["receivedNS"] <= spawn[0])
            check("fresh_final_census", final > initial and last["completed"] is True
                  and observer["lastCompletedScan"] == final and done
                  and last["request"]["dispatchedNS"] >= done[1])
            check("live_command_census", spawn and done and any(r["completed"] is True
                  and initial < r["request"]["scan"] < final
                  and spawn[1] <= r["request"]["dispatchedNS"] <= r["receivedNS"] < done[0] for r in rows))
            check("exact_verified_retention", retention and retention.get("retentionComplete") is True
                  and retention.get("newAnalysisDocumentObserved") is True
                  and retention.get("semanticAnalysisValidityEstablished") is False
                  and all(retention.get("payloadVerification", {}).get(k) is True for k in
                          ("exactPayloads", "crcValid", "sha256Matches", "originalsPreserved")))
        else:
            check("negative_capture_stays_negative", receipt.get("observationComplete") is False
                  and receipt.get("transportComplete") is False and isinstance(failure, dict))
            check("retention_denied", retention and retention.get("retentionComplete") is False
                  and retention.get("newAnalysisDocumentObserved") is False)
            if name in ("pending-exit", "deadline"):
                pending = failure["pendingOperation"]
                scan = failure["pendingScan"]
                start, deadline, failed = pending["clockNS"], scan["deadlineNS"], failure["parentClockNS"]
                marker = controls.get("workerMarker", {})
                check("pending_metadata_failure", pending.get("category") == "stat"
                      and pending.get("path") == "stall.bin"
                      and observer.get("pendingOperation") == pending
                      and observer.get("pendingScan") == scan and integer(start)
                      and integer(deadline) and integer(failed) and start < deadline <= failed
                      and "completion not observed within parent dispatch budget" in failure.get("error", ""))
                check("actual_callback_marker", marker.get("pid") == worker["pid"]
                      and integer(marker.get("monotonicNS")) and start <= marker["monotonicNS"] < deadline)
                signals = [row.get("signal") for row in worker.get("signals", [])
                           if row.get("target") == "owned-group"]
                check("owned_worker_termination", worker.get("stopReason") == "observation-failed"
                      and ((worker.get("exitCode") == -15 and "SIGTERM" in signals)
                           or (worker.get("exitCode") == -9 and "SIGKILL" in signals)))
                if name == "pending-exit":
                    end = clock_interval(target.get("operationTerminalClock"))
                    progress = [clock_interval(row.get("clock")) for row in target.get("streamProgress", [])
                                if row.get("stdoutBytes", 0) > 0]
                    check("stream_and_exit_while_pending", target.get("exitCode") == 0
                          and streams.get("stdout") == b"D30 pending progress\n"
                          and end and start <= end[0] <= end[1] < deadline
                          and any(p and start <= p[0] <= p[1] < deadline for p in progress))
                else:
                    stopped = clock_interval(target.get("stopRequestedClock"))
                    check("target_deadline_serviced_while_pending", target.get("stopReason") == "command-budget"
                          and stopped and start <= stopped[0] <= stopped[1] < deadline
                          and type(target.get("exitCode")) is int and target["exitCode"] < 0)
            elif name == "exit-seven":
                check("acknowledged_unsuccessful_worker", target.get("exitCode") == 0
                      and worker.get("exitCode") == 7 and worker.get("stopReason") is None
                      and observer.get("stopped") is True and receipt.get("finalFreshScanComplete") is True
                      and failure.get("error") == "Observer did not exit successfully after acknowledged shutdown")
            elif name == "descendant":
                marker = controls.get("descendant", {})
                pid, pgid = marker.get("pid"), target["pid"]
                check("bound_descendant_marker", integer(pid) and pid != pgid
                      and marker.get("pgid") == pgid and marker.get("ready") is True
                      and marker.get("leaderPID") == pgid and marker.get("termIgnored") is True)
                initial = next(r for r in probe_records(cleanup_records) if r["name"] == "groups-initial")
                rows = parse_ps(initial["streams"]["stdout"])
                leaders = [r for r in rows if r["pid"] == pgid and r["pgid"] == pgid and r["state"].startswith("Z")]
                leaves = [r for r in rows if r["pid"] == pid and r["pgid"] == pgid and not r["state"].startswith("Z")]
                check("real_initial_live_descendant", len(leaders) == len(leaves) == 1)
                signals = [r["signal"] for r in target.get("signals", []) if r.get("target") == "owned-group"]
                check("owned_group_term_then_kill", signals.count("SIGTERM") == signals.count("SIGKILL") == 1
                      and signals.index("SIGTERM") < signals.index("SIGKILL"))
                check("original_group_failure_sticky", target.get("exitCode") == 0
                      and failure.get("error") == "Original cleanup did not establish both owned groups")
                worker_end = clock_interval(worker.get("operationDoneClock"))
                check("worker_completed_before_group_failure", worker.get("exitCode") == 0
                      and observer.get("stopped") is True and worker_end
                      and worker_end[1] <= failure.get("parentClockNS", 0))
    except (KeyError, IndexError, TypeError, ValueError, UnicodeError, AttributeError, StopIteration) as error:
        checks["complete_receipt_schema"] = False
        schema_error = type(error).__name__ + ": " + str(error)[:300]
    else:
        schema_error = None
    errors = [name for name, passed in checks.items() if not passed]
    if schema_error:
        errors.append(schema_error)
    return {"passed": bool(checks) and all(checks.values()), "checks": checks, "errors": errors}


def bounded_file(path, limit):
    fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW | os.O_CLOEXEC)
    try:
        before = os.fstat(fd)
        require(stat.S_ISREG(before.st_mode) and 0 <= before.st_size <= limit, "Unbounded or nonregular input")
        result = bytearray()
        while len(result) <= limit:
            chunk = os.read(fd, min(65536, limit + 1 - len(result)))
            if not chunk:
                break
            result.extend(chunk)
        after = os.fstat(fd)
        require(len(result) == before.st_size <= limit
                and (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns)
                == (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns), "Input changed or exceeded bound")
        return bytes(result)
    finally:
        os.close(fd)


def identity(raw):
    return {"bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest()}


def save_json(path, value):
    raw = (json.dumps(value, ensure_ascii=False, allow_nan=False, indent=2) + "\n").encode()
    require(len(raw) <= MAX_JSON, "JSON evidence exceeds fixed bound")
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as stream:
        stream.write(raw)


def sources(repo, retained=None):
    paths = sorted(p.relative_to(repo).as_posix() for p in (repo / "script").glob("*.py")) + [WORKFLOW]
    require(len(paths) <= 256, "Source count exceeded")
    result, total = {}, 0
    for name in paths:
        raw = bounded_file(repo / name, 2 * 1024 * 1024)
        total += len(raw)
        require(total <= SOURCE_TOTAL, "Source byte cap exceeded")
        result[name] = identity(raw)
        if retained is not None:
            dest = retained / "sources" / name.removeprefix(".github/")
            dest.parent.mkdir(parents=True, exist_ok=True)
            with dest.open("xb") as stream:
                stream.write(raw)
    return result


def preserve_capture(folder, receipt, streams, cleanup):
    folder.mkdir(parents=True, exist_ok=True)
    save_json(folder / "receipt.json", receipt)
    for key in ("stdout", "stderr"):
        raw = streams[key]
        require(type(raw) is bytes and len(raw) <= 8 * 1024 * 1024, "Stream evidence exceeded")
        (folder / (key + ".bin")).write_bytes(raw)
    records = []
    for record in cleanup:
        name = record["name"]
        require(re.fullmatch(r"[A-Za-z0-9_-]{1,100}", name), "Unsafe command receipt name")
        child = folder / "cleanup" / name
        child.mkdir(parents=True, exist_ok=False)
        save_json(child / "receipt.json", record["receipt"])
        for key, raw in record["streams"].items():
            require(key in ("stdout", "stderr") and len(raw) <= 65536, "Cleanup stream exceeded")
            (child / (key + ".bin")).write_bytes(raw)
        records.append({"name": name, "receipt": record["receipt"],
                        "streams": {k: identity(v) for k, v in record["streams"].items()}})
    return records


@contextmanager
def real_process_observations(adapter, observations):
    """Record real constructor references and peeks without replacing OS work."""
    original = adapter.progress.OwnedCommand
    commands = []
    class ObservedOwnedCommand(original):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, **kwargs)
            commands.append(self)
    def factory(name, argv, *, cwd, env, limit):
        if tuple(argv) == PS_ARGV:
            rows = []
            for command in commands:
                child = command.transport.process
                if (tuple(command.receipt["intendedArgv"]) == PS_ARGV or child is None
                        or command.collected or command.pid_actions_revoked or child.returncode is not None):
                    continue
                # The unchanged OwnedCommand already performs WNOWAIT peeks.
                # Do not introduce a second ownership/status consumer here.
                rows.append({"role": "worker" if command.name == "output-observer" else "target",
                             "pid": child.pid, "pgid": os.getpgid(child.pid),
                             "waitable": command.terminal and command.receipt["exitObservedWithoutReap"] is True,
                             "returncodeBeforeProbe": child.returncode,
                             "basis": "owned-command non-reaping terminal receipt and retained Popen status",
                             "observedClockNS": time.monotonic_ns()})
            observations.append({"probeName": name, "children": rows})
        transport = adapter.progress.startup.MonitoredCommand(argv, cwd=cwd, env=env, limit=limit)
        return transport
    adapter.progress.OwnedCommand = ObservedOwnedCommand
    try:
        yield factory
    finally:
        adapter.progress.OwnedCommand = original


def verify_payload(retention, archive, guard, expected):
    result = {"exactPayloads": False, "crcValid": False, "sha256Matches": False, "originalsPreserved": False}
    if retention.get("retentionComplete") is not True:
        return result
    raw = bounded_file(archive, 8 * 1024 * 1024)
    with zipfile.ZipFile(archive) as bundle:
        names = {name for name in bundle.namelist() if not name.endswith("/")}
        wanted = {"derived-output/" + name: value for name, value in expected.items()}
        result["exactPayloads"] = names == set(wanted) and all(bundle.read(name) == value for name, value in wanted.items())
        result["crcValid"] = bundle.testzip() is None
    result["sha256Matches"] = identity(raw)["sha256"] == retention["archive"]["sha256"]
    result["originalsPreserved"] = all(bounded_file(guard.root / name, 4096) == value for name, value in expected.items())
    return result


def run(output, experiment_commit):
    repo = Path(__file__).resolve().parent.parent
    supplied = Path(output)
    require(supplied.is_absolute() and ".." not in supplied.parts
            and supplied.name not in ("", ".", "..", "fixture-work"), "Invalid evidence destination")
    output = supplied.parent.resolve(strict=True) / supplied.name
    require(not output.is_relative_to(repo), "Evidence must be outside checkout")
    output.mkdir(mode=0o700, exist_ok=False)
    work = output.parent / "fixture-work"
    report = {"schema": 1, "diagnostic": "D30-isolated-atrc-macos-qualification",
              "evidenceKind": "real-macos-processes-synthetic-output",
              "experimentCommit": experiment_commit, "baseCommit": BASE, "baseTree": BASE_TREE,
              "status": "diagnostic-incomplete", "qualificationComplete": False,
              "sourceUnchanged": False, "interpreterUnchanged": False, "preflightComplete": False,
              "groupEnumeration": "real-/bin/ps-no-fallback", "cases": {name: {"status": "NOT RUN"} for name in CASES},
              "errors": [], "nativeTraceOperations": {"import": 0, "export": 0, "record": 0, "sample": 0},
              "GUIInputExecuted": False, "C12": "HOLD", "releaseReady": False,
              "bounds": {"ordinarySyntheticTargetNormalSeconds": 3, "ordinarySyntheticTargetTotalSeconds": 5,
                         "deadlineCaseNormalSeconds": .15, "deadlineCaseTotalSeconds": .5,
                         "workerStartupSeconds": 2, "workerCleanupAccountingSeconds": 2,
                         "scanSeconds": .25, "outerWorkflowMinutes": 8},
              "limitations": ["Synthetic Python workload does not qualify a native ATRC import or Finder cancellation.",
                              "Injected Python wait is not a kernel stall or attribution of D27 delay.",
                              "Recorded executable identity does not pin every Python standard-library/framework byte.",
                              "Group snapshots establish no live members at the snapshot, not exact historical descendant exit times."]}
    before = interpreter_before = None
    interpreter = Path(sys.executable).resolve(strict=True)
    started = time.monotonic()
    env = dict(os.environ, LC_ALL="C", LANG="C", TERM="dumb", PYTHONDONTWRITEBYTECODE="1")
    for key in ("GH_TOKEN", "GITHUB_TOKEN", "D30_WORKER_MODE", "D30_CONTROL_DIR"):
        env.pop(key, None)
    try:
        require(re.fullmatch(r"[0-9a-f]{40}", experiment_commit or ""), "Invalid experiment commit")
        def git(*args):
            return subprocess.check_output(("git", *args), cwd=repo, timeout=10, text=True).strip()
        require(git("rev-parse", "HEAD") == experiment_commit, "Checkout/experiment mismatch")
        require(git("rev-parse", BASE + "^{tree}") == BASE_TREE, "D29 base tree mismatch")
        require(not git("status", "--porcelain", "--untracked-files=normal"), "Checkout is not clean")
        subprocess.run(("git", "merge-base", "--is-ancestor", BASE, "HEAD"), cwd=repo, check=True, timeout=10)
        changed = git("diff", "--name-only", BASE, "HEAD").splitlines()
        require(set(changed) <= set(NEW_PATHS), "Change outside D30 allowlist")
        report["experimentTree"] = git("rev-parse", "HEAD^{tree}")
        before = sources(repo, output)
        report["sourcesBefore"] = before
        require(all(before[p]["sha256"] == digest for p, digest in FIXED_RUNTIME.items()), "D29 runtime changed")
        interpreter_before = identity(bounded_file(interpreter, 128 * 1024 * 1024))
        report["interpreterBefore"] = {"path": str(interpreter), **interpreter_before}
        report["platform"] = {"system": platform.system(), "machine": platform.machine(),
                              "macVersion": platform.mac_ver()[0], "kernelRelease": platform.release(),
                              "pythonVersion": sys.version, "implementation": platform.python_implementation(),
                              "effectiveUID": os.geteuid(),
                              "runnerImage": {key: env.get(key) for key in ("ImageOS", "ImageVersion", "RUNNER_OS", "RUNNER_ARCH")}}
        require(platform.system() == "Darwin" and platform.machine() == "x86_64"
                and os.geteuid() != 0 and sys.version_info >= (3, 13), "Require non-root Intel macOS with Python 3.13+")
        import native_retained_atrc_isolated as adapter
        import native_retained_atrc_output as legacy
        import native_retained_trace_command as command
        import run_native_recorder_progress_observation as progress
        from isolated_atrc_macos_fixture import EXPECTED_FILES
        from qualify_isolated_atrc_pressure import run_pressure_case
        report["waitidPreflight"] = progress.waitid_preflight()
        ps, ps_streams, ps_cleanup = command.capture_owned(
            "platform-groups", PS_ARGV, cwd=output.parent, env=env, budget=5, reserve=2, limit=65536)
        report["groupPreflight"] = {"receipt": ps,
            "cleanup": preserve_capture(output / "preflight-ps", ps, ps_streams, ps_cleanup)}
        rows = parse_ps(ps_streams["stdout"])
        require(any(row["pid"] == os.getpid() and row["pgid"] == os.getpgrp() for row in rows),
                "Real ps does not show collector process/group")
        require(ps.get("transportComplete") is True and ps.get("cleanupComplete") is True
                and ps.get("exitCode") == 0 and ps_streams["stderr"] == b""
                and owned_children_accounted({"target": ps, "worker": None,
                    "finalOwnedGroups": ps["finalOwnedGroups"]}, ps_cleanup), "Real process-group preflight failed")
        report["preflightComplete"] = True
        work.mkdir(mode=0o700, exist_ok=False)
        for name in CASES:
            case = {"status": "RUNNING", "passed": False, "kind": "synthetic-fixture-real-process-APIs"}
            report["cases"][name] = case
            case_root, retained = work / name, output / "cases" / name
            case_root.mkdir(mode=0o700)
            retained.mkdir(parents=True, mode=0o700)
            if name == "pressure":
                result = run_pressure_case(case_root, env)
                case.update(result["details"])
                case["receipt"] = result["receipt"]
                case["cleanup"] = preserve_capture(retained, result["receipt"], result["streams"], result["cleanup_records"])
                case["allLaunchedOwnedChildrenAccounted"] = owned_children_accounted(
                    {"target": result["receipt"], "worker": None,
                     "finalOwnedGroups": result["receipt"].get("finalOwnedGroups", {})}, result["cleanup_records"])
                require(len(result["report_raw"]) <= 65536, "Pressure report cap exceeded")
                (retained / "report-channel.bin").write_bytes(result["report_raw"])
                case["reportChannelIdentity"] = identity(result["report_raw"])
                case["passed"] = (result["details"].get("passed") is True
                                  and case["allLaunchedOwnedChildrenAccounted"])
            else:
                guard = legacy.OutputGuard(case_root / "observed")
                controls = {"probeLeaseObservations": []}
                case_env = dict(env)
                mode = "success" if name == "exit-seven" else name
                worker_script = None
                if name in ("pending-exit", "deadline", "exit-seven"):
                    worker_script = repo / "script/isolated_atrc_macos_worker_fixture.py"
                    case_env.update(D30_CONTROL_DIR=str(case_root),
                                    D30_WORKER_MODE="exit-seven" if name == "exit-seven" else "delay-stat")
                try:
                    with real_process_observations(adapter, controls["probeLeaseObservations"]) as factory:
                        result = adapter.capture_isolated("d30-" + name,
                            (sys.executable, "-u", str(repo / "script/isolated_atrc_macos_fixture.py"),
                             mode, "--control-dir", str(case_root)),
                            cwd=guard.root, env=case_env, guard=guard, test_factory=factory,
                            test_budget=.5 if name == "deadline" else 5,
                            test_reserve=.35 if name == "deadline" else 2, test_worker_script=worker_script)
                    case["receipt"], case["controls"] = result.receipt, controls
                    case["cleanup"] = preserve_capture(retained, result.receipt, result.streams, result.cleanup_records)
                    safe = owned_children_accounted(result.receipt, result.cleanup_records)
                    case["allLaunchedOwnedChildrenAccounted"] = safe
                    retention = {"status": "skipped-d30-ownership-gate", "retentionComplete": False,
                                 "newAnalysisDocumentObserved": False}
                    case["retention"] = retention
                    if safe:
                        for filename, key in (("worker-operation.json", "workerMarker"), ("descendant.json", "descendant")):
                            path = case_root / filename
                            if path.exists():
                                controls[key] = json.loads(bounded_file(path, 4096))
                        archive = retained / "retained-output.zip"
                        retention = result.finalize(archive)
                        case["retention"] = retention
                        if name == "success":
                            retention["payloadVerification"] = verify_payload(retention, archive, guard, EXPECTED_FILES)
                    case["classification"] = classify_case(name, result.receipt, result.streams,
                                                         result.cleanup_records, controls, retention)
                    case["passed"] = case["classification"]["passed"]
                finally:
                    guard.close()
            case["status"] = "PASS" if case["passed"] else "FAIL"
            save_json(retained / "case.json", case)
            if not case["passed"]:
                report["errors"].append("Case failed; remaining cases not run: " + name)
                break
        report["qualificationComplete"] = all(case.get("passed") is True for case in report["cases"].values())
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        report["errors"].append(type(error).__name__ + ": " + str(error)[:1000])
        for name, case in report["cases"].items():
            if case["status"] == "RUNNING":
                case.update(status="FAIL", passed=False, error=report["errors"][-1])
                partial = output / "cases" / name / "case.json"
                if not partial.exists():
                    save_json(partial, case)
    finally:
        try:
            after = sources(repo)
            report["sourcesAfter"] = after
            report["sourceUnchanged"] = before is not None and after == before
            interpreter_after = identity(bounded_file(interpreter, 128 * 1024 * 1024))
            report["interpreterAfter"] = {"path": str(interpreter), **interpreter_after}
            report["interpreterUnchanged"] = interpreter_before is not None and interpreter_after == interpreter_before
        except (OSError, ValueError) as error:
            report["errors"].append("Final identity: " + str(error)[:1000])
        if not (report["sourceUnchanged"] and report["interpreterUnchanged"] and report["preflightComplete"] and not report["errors"]):
            report["qualificationComplete"] = False
        report["status"] = "qualified-for-recorded-synthetic-scope" if report["qualificationComplete"] else "diagnostic-incomplete"
        report["elapsedSeconds"] = time.monotonic() - started
        save_json(output / "qualification.json", report)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--experiment-commit", required=True)
    args = parser.parse_args()
    report = run(args.output, args.experiment_commit)
    print(json.dumps({key: report[key] for key in ("status", "qualificationComplete", "elapsedSeconds", "errors")}))
    return 0 if report["qualificationComplete"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
