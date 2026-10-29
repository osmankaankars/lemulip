#!/usr/bin/env python3
"""Run opt-in own-window PDF pointer diagnostics, each in a bounded fresh process.

Requires a completed macOS `swift test` build. This is synthetic AppKit input in
our own XCTest window, not hardware mouse, global input, or manual UI evidence.
Each exact test gets 45 seconds. A stuck native tracking loop is terminated only
inside the new process group created for that test; logs and partial artifacts
remain available. A timeout or failed test is never reported as a UI pass.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time


CASES = (
    "testMergeVisibleCancelPointerProbe",
    "testOrganizerVisibleCancelPointerProbe",
    "testMergeDragPointerProbe",
    "testOrganizerDragPointerProbe",
)


def run_bounded(command: list[str], *, log: Path, environment: dict[str, str],
                cwd: Path, timeout_seconds: float = 45) -> dict[str, object]:
    started = time.monotonic()
    timed_out = False
    with log.open("xb") as output:
        process = subprocess.Popen(command, cwd=cwd, env=environment,
                                   stdout=output, stderr=subprocess.STDOUT,
                                   start_new_session=True)
        try:
            process.wait(timeout=timeout_seconds)
        except subprocess.TimeoutExpired:
            timed_out = True
            # start_new_session makes this known child PID its own process group.
            # Never enumerate or signal unrelated app, desktop, or test processes.
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            # Do not poll/wait/reap the leader during this grace period. If the
            # Swift driver exits before a TERM-resistant XCTest descendant, its
            # unreaped PID keeps the owned group ID reserved until the final kill.
            time.sleep(3)
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait(timeout=3)
    return {"returnCode": process.returncode, "timedOut": timed_out,
            "timeoutSeconds": timeout_seconds,
            "terminationGraceSeconds": 3 if timed_out else 0,
            "elapsedSeconds": round(time.monotonic() - started, 3)}


def write_report(path: Path, report: dict[str, object]) -> None:
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    temporary.replace(path)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True,
                        help="Artifact directory; each case creates a fresh child directory")
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("The own-window PDF pointer diagnostic requires macOS")
    root = Path(__file__).resolve().parents[1]
    directory = args.output.resolve()
    directory.mkdir(parents=True, exist_ok=True)
    report_path = directory / "pointer-review.json"
    if report_path.exists():
        parser.error("Choose a fresh output directory; existing review evidence is not overwritten")
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
    report: dict[str, object] = {
        "sourceCommit": commit,
        "workflowRun": os.environ.get("GITHUB_RUN_ID", "local"),
        "createdAtUTC": dt.datetime.now(dt.timezone.utc).isoformat(),
        "method": "Four opt-in XCTest cases, each in its own fresh process and synthetic AppKit window",
        "hardwareMouseVerified": False, "globalInputPosted": False,
        "watchdogScope": "Only each new child process group; 45 seconds per case",
        "cases": [], "status": "running",
    }
    write_report(report_path, report)
    all_passed = True
    for case in CASES:
        case_directory = directory / case
        case_directory.mkdir()
        environment = os.environ.copy()
        environment.update({
            "LEMULIP_PDF_POINTER_PROBE": "1",
            "LEMULIP_PDF_POINTER_WATCHDOG": "45",
            "LEMULIP_PDF_REVIEW_DIR": str(case_directory),
            "LEMULIP_PDF_REVIEW_COMMIT": commit,
        })
        log = case_directory / "xctest.log"
        command = ["xcrun", "--sdk", "macosx", "swift", "test", "--skip-build",
                   "--filter", "PDFEditorInteractionTests/" + case]
        result = run_bounded(command, log=log, environment=environment, cwd=root)
        text = log.read_text(errors="replace")
        exact_pass = re.search(
            r"Test Case '-\[LemulipAppTests\.PDFEditorInteractionTests "
            + re.escape(case) + r"\]' passed \(", text) is not None
        passed = result["returnCode"] == 0 and not result["timedOut"] and exact_pass
        result.update({"test": case, "passed": passed, "exactTestPassLineFound": exact_pass,
                       "log": str(log.relative_to(directory)),
                       "artifacts": sorted(p.name for p in case_directory.iterdir() if p != log)})
        if result["timedOut"]:
            result["limitation"] = "Native event tracking did not complete inside the bounded own-process test; no pointer success is established"
        elif not passed:
            result["limitation"] = "Inspect the exact XCTest failure and retained production state; do not treat local event delivery as a successful gesture"
        report["cases"].append(result)
        all_passed = all_passed and passed
        write_report(report_path, report)
        print(f"{case}: {'PASS' if passed else 'TIMEOUT' if result['timedOut'] else 'FAIL'}", flush=True)
    report["status"] = "passed-synthetic-own-window-cases" if all_passed else "incomplete-or-failed"
    write_report(report_path, report)
    return 0 if all_passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
