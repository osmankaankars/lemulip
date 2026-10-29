#!/usr/bin/env python3
"""Run opt-in own-window PDF pointer diagnostics, each in a bounded fresh process.

Requires a completed macOS `swift test` build. This is synthetic AppKit input in
our own XCTest window, not hardware mouse, global input, or manual UI evidence.
Launches the built bundle directly with XCTest, without a SwiftPM driver that
would put the actual test host in a separate process group from the watchdog.
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


def xctest_paths(root: Path) -> tuple[Path, Path]:
    # Match SwiftPM's macOS XCTest host discovery and -XCTest launch form.
    # Sources/PackageModel/UserToolchain.swift and Commands/SwiftTestCommand.swift
    # in swiftlang/swift-package-manager, tag swift-6.2-RELEASE.
    output = subprocess.check_output(
        ["/usr/bin/xcrun", "--sdk", "macosx", "--find", "xctest"],
        cwd=root, text=True, timeout=10).strip()
    runner = Path(output)
    if not runner.is_absolute():
        raise ValueError("xcrun did not return an absolute XCTest host path")
    runner = runner.resolve(strict=True)
    if not runner.is_file() or not os.access(runner, os.X_OK):
        raise ValueError("The resolved XCTest host is not an executable file")
    build = (root / ".build").resolve(strict=True)
    bundle = (build / "debug" / "LemulipPackageTests.xctest").resolve(strict=True)
    if not bundle.is_dir() or not bundle.is_relative_to(build):
        raise ValueError("The built XCTest bundle must be a directory inside this checkout's .build")
    executable = bundle / "Contents" / "MacOS" / "LemulipPackageTests"
    if not executable.is_file() or not os.access(executable, os.X_OK):
        raise ValueError("The existing Lemulip XCTest bundle has no executable; run swift test first")
    return runner, bundle


def xctest_environment(root: Path) -> dict[str, str]:
    # Match SwiftPM's TestingSupport.constructTestEnvironment for XCTest.
    # Resolve the platform, not the SDK root: XCTest lives under Developer.
    environment = os.environ.copy()
    platform_value = environment.get("SWIFTPM_PLATFORM_PATH_macosx")
    if platform_value is None:
        platform_value = subprocess.check_output(
            ["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-platform-path"],
            cwd=root, text=True, timeout=10).strip()
    platform = Path(platform_value)
    if not platform.is_absolute() or not platform.is_dir():
        raise ValueError("The macOS XCTest platform path must be an existing absolute directory")
    developer = platform / "Developer"
    paths = {
        "DYLD_FRAMEWORK_PATH": [developer / "Library" / "Frameworks",
                                developer / "Library" / "PrivateFrameworks"],
        "DYLD_LIBRARY_PATH": [developer / "usr" / "lib"],
    }
    for key, additions in paths.items():
        environment[key] = os.pathsep.join(
            ([environment[key]] if environment.get(key) else [])
            + [str(path) for path in additions])
    environment.update({"NO_COLOR": "1", "SWIFT_TESTING_ENABLED": "0"})
    return environment


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
            # test host exits before a TERM-resistant same-group descendant, its
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
    try:
        runner, bundle = xctest_paths(root)
        test_environment = xctest_environment(root)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        parser.error(f"Cannot launch the existing XCTest bundle directly: {error}")
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
        "launcher": "Direct XCTest executable; no SwiftPM driver",
        "xctestRunner": str(runner), "xctestBundle": str(bundle),
        "hardwareMouseVerified": False, "globalInputPosted": False,
        "watchdogScope": "Only each new child process group; 45 seconds per case",
        "cases": [], "status": "running",
    }
    write_report(report_path, report)
    all_passed = True
    for case in CASES:
        case_directory = directory / case
        case_directory.mkdir()
        environment = test_environment.copy()
        environment.update({
            "LEMULIP_PDF_POINTER_PROBE": "1",
            "LEMULIP_PDF_POINTER_WATCHDOG": "45",
            "LEMULIP_PDF_REVIEW_DIR": str(case_directory),
            "LEMULIP_PDF_REVIEW_COMMIT": commit,
        })
        log = case_directory / "xctest.log"
        selector = "LemulipAppTests.PDFEditorInteractionTests/" + case
        command = [str(runner), "-XCTest", selector, str(bundle)]
        result = run_bounded(command, log=log, environment=environment, cwd=root)
        text = log.read_text(errors="replace")
        exact_pass = re.search(
            r"Test Case '-\[LemulipAppTests\.PDFEditorInteractionTests "
            + re.escape(case) + r"\]' passed \(", text) is not None
        passed = result["returnCode"] == 0 and not result["timedOut"] and exact_pass
        result.update({"test": case, "passed": passed, "exactTestPassLineFound": exact_pass,
                       "xctestSelector": selector,
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
