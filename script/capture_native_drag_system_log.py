"""Read existing, narrowly scoped system logs after the D14 comparison.

`log(1)` defines show --info/--debug as output selection, not configuration.
Apple's WWDC22/10119 demonstrates bounded show queries and app-bound daemon
predicates. No public activation-origin logging schema or coverage is assumed.
"""
import argparse
from datetime import datetime, timedelta, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import selectors
import subprocess
import sys
import time

import compare_native_drag_mouse_driver as mouse

capture = mouse.capture
TIMEOUT_SECONDS = 20
BYTE_LIMIT = 10 * 1024 * 1024
SYSTEM_PROCESSES = ("WindowServer", "lsd", "runningboardd", "loginwindow")
BUNDLES = ("app.lemulip.NativeDragControl", "app.lemulip.NativeDragSource", mouse.RUNNER_ID)
PROTOCOL = {"schema": 1, "protocolBaseCommit": "d69f6b344a0dc069027f04061686a308dae79ba4",
            "inputProtocol": "D13-R3-unchanged", "targetMouseEventIdentitySchema": 1}
KEYWORDS = ("activat", "active", "front", "focus", "drag")
ENTRY_FIELDS = ("timestamp", "machTimestamp", "bootUUID", "processID", "processImagePath",
                "senderImagePath", "subsystem", "category", "eventMessage", "formatString",
                "messageType", "eventType", "threadID", "activityIdentifier", "traceID")


def timestamp(value):
    capture.require(isinstance(value, str), "log-time-missing")
    result = datetime.fromisoformat(value.replace("Z", "+00:00"))
    capture.require(result.tzinfo is not None, "log-time-zone-missing")
    return result.astimezone(timezone.utc)


def reference_pattern(pids):
    # Bare numbers are not PID evidence; require an explicit PID/process label.
    bundles = "|".join(re.escape(value) for value in BUNDLES)
    numbers = "|".join(str(value) for value in sorted(pids))
    return (r"(?<![A-Za-z0-9_.-])(?:" + bundles + r")(?![A-Za-z0-9_.-])|"
            r"\b(?:pid|process(?:[ _-]?id)?)[ \t]*(?:[=:][ \t]*|[ \t]+)(?:" + numbers + r")(?![0-9])")


def load_context(stage, comparison_dir, analysis_path, experiment_commit):
    comparison_path = comparison_dir / "comparison.json"
    comparison = mouse.read_json(comparison_path)
    analysis = mouse.read_json(analysis_path)
    provenance_path = stage / "provenance.json"
    provenance = mouse.read_json(provenance_path)
    capture.require(re.fullmatch(r"[0-9a-f]{40}", experiment_commit) is not None, "experiment-commit")
    capture.fields_match(provenance, {"observerExperimentCommit": experiment_commit,
        "eventOriginDiagnostic": PROTOCOL,
        "eventOriginSystemLogCollectorSourceSHA256": capture.sha256(Path(__file__))}, "log-provenance")
    capture.require(comparison.get("provenance") == provenance, "log-comparison-provenance")
    capture.fields_match(analysis, {"schema": 1, "diagnostic": "native-drag-event-origin",
        "experimentCommit": experiment_commit, "experimentTree": provenance["observerExperimentTree"],
        "architecture": provenance["architecture"], "protocolBaseCommit": PROTOCOL["protocolBaseCommit"],
        "inputProtocol": PROTOCOL["inputProtocol"], "provenanceSHA256": capture.sha256(provenance_path),
        "comparisonSHA256": capture.sha256(comparison_path)}, "log-analysis-binding")
    capture.require([row.get("case") for row in analysis["cases"]] == list(mouse.CASES)
                    and [row.get("mouseDriverCase") for row in comparison["cases"]] == list(mouse.CASES),
                    "log-case-order")
    cases, excluded = [], []
    for row, classified in zip(analysis["cases"], comparison["cases"]):
        name = row["case"]
        if row.get("status") != "analyzed":
            excluded.append({"case": name, "analysisStatus": row.get("status")})
            continue
        directory = mouse.evidence_for(stage, name) / "orchard"
        raw_path = directory / "report.json"
        raw = mouse.read_json(raw_path)
        digest = capture.sha256(raw_path)
        capture.require(row.get("caseSHA256") == classified.get("caseSHA256") == digest
                        and row.get("caseReportPath") == str(raw_path), "log-case-hash-binding")
        driver = raw.get("mouseControlDriver", {})
        pids = {"observer": raw.get("observerProcessID"), "source": raw.get("sourceApplicationPID"),
                "target": raw.get("targetApplicationPID"), "runner": driver.get("runnerPID")}
        capture.require(all(type(pid) is int and pid > 0 for pid in pids.values())
                        and len(set(pids.values())) == 4 and row.get("ownedPIDs") == pids,
                        "log-owned-pid-binding")
        paths = {"observer": str(stage / mouse.OBSERVER),
            "source": str(stage / "Native Drag Source.app/Contents/MacOS/NativeDragSource"),
            "target": str(stage / "Native Drag Control.app/Contents/MacOS/NativeDragControl"),
            "runner": str(stage / mouse.RUNNER_RELATIVE / "Contents/MacOS/QualityReview-Runner")}
        capture.require(raw.get("applicationPath") == str(stage / "Native Drag Control.app")
                        and raw.get("sourceApplicationPath") == str(stage / "Native Drag Source.app")
                        and driver.get("runnerExecutablePath") == paths["runner"], "log-owned-path-binding")
        receiver_path = directory / "receiver.jsonl"
        receiver_hash = capture.sha256(receiver_path)
        capture.require(row.get("receiverSHA256") == classified.get("receiver", {}).get("receiverSHA256")
                        == receiver_hash and receiver_path.stat().st_size <= BYTE_LIMIT, "log-receiver-binding")
        rows = [mouse.decoded_json(line, "log-receiver") for line in receiver_path.read_bytes().splitlines()]
        capture.require(rows and all(value.get("pid") == pids["target"] and value.get("mouseDriverCase") == name
                                    for value in rows), "log-receiver-identity")
        times = [timestamp(value.get("time")) for value in rows]
        first, last = min(times), max(times)
        wall = row.get("wallTimeRange", {})
        capture.require(timestamp(wall.get("start")) == first and timestamp(wall.get("end")) == last
                        and wall.get("precision") == "seconds" and 0 <= (last - first).total_seconds() <= 300,
                        "log-wall-time-binding")
        cases.append({"case": name, "caseSHA256": digest, "receiverSHA256": receiver_hash,
            "ownedPIDs": pids, "ownedExecutablePaths": paths, "wallTimeRange": wall,
            "start": first - timedelta(seconds=1), "end": last + timedelta(seconds=1)})
    capture.require(cases, "log-no-analyzed-cases")
    start, end = min(case["start"] for case in cases), max(case["end"] for case in cases)
    capture.require(0 < (end - start).total_seconds() <= 1200, "log-query-time-span")
    return {"cases": cases, "excludedCases": excluded, "start": start, "end": end,
        "comparisonSHA256": capture.sha256(comparison_path), "analysisSHA256": capture.sha256(analysis_path),
        "provenanceSHA256": capture.sha256(provenance_path)}


def command_for(context):
    pids = sorted({pid for case in context["cases"] for pid in case["ownedPIDs"].values()})
    owned = " OR ".join(f"processID == {pid}" for pid in pids)
    shared = " OR ".join("process == " + json.dumps(name) for name in SYSTEM_PROCESSES)
    reference = json.dumps("(?s).*(?:" + reference_pattern(pids) + ").*")
    relevant = " OR ".join("eventMessage CONTAINS[c] " + json.dumps(word) for word in KEYWORDS)
    predicate = f"(({owned}) OR (({shared}) AND eventMessage MATCHES[c] {reference})) AND ({relevant})"
    return ["/usr/bin/log", "show", "--style", "json", "--timezone", "UTC", "--info", "--debug",
        "--start", context["start"].strftime("%Y-%m-%d %H:%M:%S%z"),
        "--end", context["end"].strftime("%Y-%m-%d %H:%M:%S%z"), "--predicate", predicate]


def run_log(command, timeout=TIMEOUT_SECONDS, byte_limit=BYTE_LIMIT):
    """Drain both pipes with one deadline and a shared byte cap; signal only this child."""
    started = time.monotonic()
    buffers = {"stdout": bytearray(), "stderr": bytearray()}
    outcome, observed, child = "completed", 0, None
    try:
        child = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        with selectors.DefaultSelector() as selector:
            for label, pipe in (("stdout", child.stdout), ("stderr", child.stderr)):
                os.set_blocking(pipe.fileno(), False)
                selector.register(pipe, selectors.EVENT_READ, label)
            while selector.get_map():
                remaining = timeout - (time.monotonic() - started)
                if remaining <= 0:
                    outcome = "timeout"
                    break
                for key, _ in selector.select(min(remaining, .1)):
                    data = os.read(key.fd, 65536)
                    if not data:
                        selector.unregister(key.fileobj)
                        continue
                    room = byte_limit - observed
                    observed += len(data)
                    buffers[key.data].extend(data[:max(0, room)])
                    if observed > byte_limit:
                        outcome = "truncated"
                        break
                if outcome != "completed":
                    break
        if outcome != "completed" and child.poll() is None:
            child.kill()
        try:
            child.wait(timeout=max(.001, timeout - (time.monotonic() - started)) if outcome == "completed" else 1)
        except subprocess.TimeoutExpired:
            outcome = "timeout"
            child.kill()
            child.wait(timeout=1)
    finally:
        if child is not None:
            if child.poll() is None:
                child.kill()
            child.stdout.close()
            child.stderr.close()
    return {"status": outcome, "returnCode": child.returncode, "stdout": bytes(buffers["stdout"]),
        "stderr": bytes(buffers["stderr"]), "bytesObserved": observed,
        "elapsedSeconds": time.monotonic() - started}


def select_records(rows, cases):
    capture.require(isinstance(rows, list) and all(isinstance(row, dict) for row in rows), "log-json-array")
    selected, rejected = [], 0
    for index, row in enumerate(rows):
        message, image, pid = row.get("eventMessage"), row.get("processImagePath"), row.get("processID")
        if not isinstance(message, str) or not isinstance(image, str) or type(pid) is not int:
            rejected += 1
            continue
        try:
            when = timestamp(row.get("timestamp"))
        except (ValueError, TypeError):
            rejected += 1
            continue
        matches = []
        for case in cases:
            if not case["start"] <= when < case["end"] or not any(word in message.lower() for word in KEYWORDS):
                continue
            roles = [role for role, owned in case["ownedPIDs"].items()
                     if pid == owned and image == case["ownedExecutablePaths"][role]]
            if roles:
                matches.append({"case": case["case"], "kind": "owned-process", "roles": roles})
            elif Path(image).name in SYSTEM_PROCESSES and re.search(reference_pattern(case["ownedPIDs"].values()), message, re.I):
                matches.append({"case": case["case"], "kind": "shared-process-owned-reference"})
        if matches:
            selected.append({"sourceRecordIndex": index, "bindings": matches,
                             "entry": {key: row[key] for key in ENTRY_FIELDS if key in row}})
        else:
            rejected += 1
    return selected, rejected


def collect(stage, comparison, analysis, output, experiment_commit, runner=run_log):
    capture.require(not output.exists() and not output.is_symlink(), "log-output-already-exists")
    output.mkdir(parents=False)
    receipt = {"schema": 1, "diagnostic": "native-drag-system-log", "experimentCommit": experiment_commit,
        "status": "error", "collectionCompleted": False, "originAttribution": "not-assessed",
        "nativeInputExecuted": False, "loggingConfigurationChanged": False,
        "timeoutSeconds": TIMEOUT_SECONDS, "byteLimit": BYTE_LIMIT, "windowPaddingSeconds": 1,
        "wallClockPrecisionSeconds": 1, "systemProcessAllowlist": list(SYSTEM_PROCESSES),
        "ownedBundleIdentifiers": list(BUNDLES), "recordsFile": "records.ndjson", "selectedRecordCount": 0,
        "startedAt": datetime.now(timezone.utc).isoformat(),
        "interpretation": "Selected existing log entries only. Empty, redacted or unavailable records do not establish absence of an activation request. Emitting PID does not identify the requester; no origin or acceptance conclusion is made."}
    selected = []
    try:
        context = load_context(stage, comparison, analysis, experiment_commit)
        receipt.update({key: value for key, value in context.items() if key not in ("cases", "start", "end")})
        receipt["cases"] = [{**case, "start": case["start"].isoformat(), "end": case["end"].isoformat()}
                            for case in context["cases"]]
        command = command_for(context)
        receipt["command"] = command
        run = runner(command)
        stdout, stderr = run.pop("stdout"), run.pop("stderr")
        receipt.update(run)
        receipt.update(stdoutBytes=len(stdout), stderrBytes=len(stderr), stderr=stderr[:4096].decode("utf-8", "replace"),
            stdoutSHA256=hashlib.sha256(stdout).hexdigest(), stderrSHA256=hashlib.sha256(stderr).hexdigest(),
            stdoutComplete=run["status"] == "completed", fullRawSHA256=hashlib.sha256(stdout).hexdigest()
            if run["status"] == "completed" else None)
        if run["status"] == "completed":
            capture.require(run["returnCode"] == 0, "log-command-nonzero-exit")
            rows = mouse.decoded_json(stdout, "log-output")
            selected, rejected = select_records(rows, context["cases"])
            redacted = sum(any(token in row["entry"]["eventMessage"].lower() for token in ("<private>", "<redacted>"))
                           for row in selected)
            receipt.update(collectionCompleted=True, rawRecordCount=len(rows), rejectedRecordCount=rejected,
                redactedRecordCount=redacted, status="redacted" if redacted else "completed-records" if selected else "completed-empty")
    except Exception as error:
        receipt.update(status="error", errorCode=str(error)[:512] if isinstance(error, capture.ComparisonError) else type(error).__name__)
    with (output / "records.ndjson").open("x") as stream:
        for row in selected:
            stream.write(json.dumps(row, sort_keys=True, allow_nan=False) + "\n")
    receipt.update(selectedRecordCount=len(selected), recordsSHA256=capture.sha256(output / "records.ndjson"),
                   finishedAt=datetime.now(timezone.utc).isoformat())
    capture.write_json(output / "receipt.json", receipt)
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("staged", "comparison", "analysis", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--experiment-commit", required=True)
    args = parser.parse_args()
    result = collect(args.staged.absolute(), args.comparison.absolute(), args.analysis.absolute(),
                     args.output.absolute(), args.experiment_commit)
    print(json.dumps(result, sort_keys=True, indent=2, allow_nan=False))
    return 0 if result["collectionCompleted"] else 1


if __name__ == "__main__":
    sys.exit(main())
