#!/usr/bin/env python3
"""D25: one bounded read-only TOC export of the exact retained D24 Intel trace."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess

from collect_native_trace_capabilities import write_json
from native_retained_trace_command import capture_owned
from native_retained_trace_input import prepare_input, snapshot_trace
from native_retained_trace_toc import inspect_toc
from native_sampler_tool_identity import inspect_tool, MAX_TOOL_BYTES
from run_native_recorder_progress_observation import read_regular, waitid_preflight
from run_native_system_trace_startup import preserve_command


BASE = "ee4ceaecee43d7f982e0523a52236799b5f2a603"
XCODE_VERSION = b"Xcode 26.3\nBuild version 17C529\n"
DEVELOPER_DIR = "/Applications/Xcode_26.3.app/Contents/Developer"
NEW_PATHS = (
    ".github/workflows/native-retained-trace-export.yml",
    "docs/NATIVE_RETAINED_TRACE_EXPORT.md",
    "script/native_retained_trace_command.py",
    "script/native_retained_trace_input.py",
    "script/native_retained_trace_toc.py",
    "script/run_native_retained_trace_export.py",
    "script/test_native_retained_trace_command.py",
    "script/test_native_retained_trace_input.py",
    "script/test_native_retained_trace_toc.py",
    "script/test_run_native_retained_trace_export.py",
)
SOURCE_PATHS = NEW_PATHS + (
    "script/collect_native_trace_capabilities.py",
    "script/native_sampler_tool_identity.py",
    "script/run_native_recorder_progress_observation.py",
    "script/run_native_recorder_startup_observation.py",
    "script/run_native_system_trace_startup.py",
    "script/test_collect_native_trace_capabilities.py",
    "script/test_run_native_recorder_progress_observation.py",
    "script/test_run_native_system_trace_startup.py",
    "docs/evidence/D24-recorder-progress-observation.json",
    "docs/evidence/D24-verification.json",
)


def require(value, message):
    if not value:
        raise ValueError(message)


def byte_identity(raw):
    return {"bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest()}


def source_snapshot(repo, retained=None):
    result = {}
    for relative in SOURCE_PATHS:
        raw = read_regular(repo / relative, 4 * 1024 * 1024)
        result[relative] = byte_identity(raw)
        if retained is not None:
            destination = retained / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            with destination.open("xb") as output:
                output.write(raw)
    return result


def validate_export_help(raw):
    text = raw.decode("utf-8", errors="strict")
    normalized = " ".join(text.split())
    checks = {
        "exportCommand": "usage: xctrace export" in normalized,
        "readsGivenTrace": "Export data from the given .trace file" in normalized,
        "inputOption": bool(re.search(r"^\s*--input\s+<file>", text, re.M)),
        "tocOption": bool(re.search(r"^\s*--toc\s+Present entities to export", text, re.M)),
        "xmlOutput": "XML file format" in normalized,
        "stdoutWithoutOutputPath": "If output path is not specified, the export operation output will be written to the standard output." in normalized,
        "separateQueryModes": "Table of Contents and XPath query are two separate modes and they cannot be specified together." in normalized,
    }
    require(all(checks.values()), "Installed export help does not establish the fixed TOC command")
    return {"identity": byte_identity(raw), "semanticChecks": checks, "passed": True}


def classify_export(receipt, streams, *, input_unchanged, source_unchanged,
                    tool_unchanged, preflight_complete, synthetic=False):
    """A finite refusal is a result; it cannot qualify trace/table/time coverage."""
    result = {
        "status": "diagnostic-incomplete", "diagnosticExecutionComplete": False,
        "commandExitedSuccessfully": receipt.get("exitCode") == 0,
        "tocExportEstablished": False, "nativeTOCEvidenceEstablished": False,
        "traceTableDataExportEstablished": False, "toc": None,
        "stderrPresent": bool(streams["stderr"]),
        "interpretationErrors": [],
        "inputUnchanged": input_unchanged, "sourceUnchanged": source_unchanged,
        "installedToolUnchanged": tool_unchanged,
        "usableClockMappingEstablished": False, "eventTimeRangeEstablished": False,
        "samplerWindowCoverageEstablished": False, "phaseEstablished": False,
        "activationRouteCoverageEstablished": False, "ipcRequestChainEstablished": False,
    }
    complete = (receipt.get("transportComplete") is True
                and receipt.get("cleanupComplete") is True
                and input_unchanged is True and source_unchanged is True
                and tool_unchanged is True and preflight_complete is True)
    if not complete:
        return result
    result["diagnosticExecutionComplete"] = True
    if receipt.get("exitCode") != 0:
        result["status"] = ("export-terminated-by-signal" if isinstance(receipt.get("exitCode"), int)
                            and receipt["exitCode"] < 0 else "export-refused")
        return result
    try:
        result["toc"] = inspect_toc(streams["stdout"])
    except (ValueError, UnicodeError) as error:
        result["status"] = "export-output-unqualified"
        result["interpretationErrors"].append(type(error).__name__ + ": " + str(error))
        return result
    result.update(status="toc-exported-with-stderr" if streams["stderr"] else "toc-exported",
                  tocExportEstablished=True, nativeTOCEvidenceEstablished=not synthetic)
    return result


def run(artifact_zip, output, experiment_commit):
    require(platform.system() == "Darwin" and platform.machine() == "x86_64",
            "D25 requires native Intel macOS")
    require(os.geteuid() != 0, "D25 must run without root privileges")
    require(tuple(map(int, platform.python_version_tuple()[:2])) >= (3, 13),
            "D25 requires macOS non-reaping child status from Python 3.13 or later")
    require(os.environ.get("DEVELOPER_DIR") == DEVELOPER_DIR, "Require the original Xcode 26.3 selection")
    require(re.fullmatch(r"[0-9a-f]{40}", experiment_commit), "Require an immutable experiment commit")
    repo = Path(__file__).resolve().parent.parent
    git = lambda *args: subprocess.check_output(["git", *args], cwd=repo, text=True, timeout=5).strip()
    require(git("rev-parse", "HEAD") == experiment_commit, "Experiment commit differs")
    require(not git("status", "--porcelain"), "Require a clean experiment worktree")
    require(not git("diff", "--name-only", BASE, "HEAD", "--", ".", *[":(exclude)" + p for p in NEW_PATHS]),
            "Unexpected changes outside the isolated D25 allowlist")
    tree = git("rev-parse", "HEAD^{tree}")
    output = Path(output)
    require(output.is_absolute() and output.parent.is_dir(), "Require a new absolute output directory")
    output.mkdir(exist_ok=False)
    output = output.resolve(strict=True)
    work = output.parent / (output.name + "-input")
    report = {
        "schema": 1, "diagnostic": "D25-retained-trace-export", "evidenceKind": "native-retained-input-diagnostic",
        "experimentCommit": experiment_commit, "experimentTree": tree, "baseCommit": BASE,
        "architecture": "x86_64", "pythonVersion": platform.python_version(),
        "status": "diagnostic-incomplete", "diagnosticExecutionComplete": False,
        "exportAttemptCount": 0, "exportInvocationCount": 0,
        "recordingInvocationCount": 0, "samplerInvocationCount": 0,
        "nativeInputExecuted": False, "applicationLaunchRequested": False, "settingsChanged": False,
        "inputRepairOrImportRequested": False, "C12": "HOLD", "releaseReady": False,
        "commands": {}, "errors": [], "preflightComplete": False,
        "inputUnchanged": False, "sourceUnchanged": False, "installedToolUnchanged": False,
        "bounds": {"exportNormalSeconds": 30, "exportTotalSeconds": 33,
                   "combinedExportStreamBytes": 8 * 1024 * 1024,
                   "metadataNormalSeconds": 17, "metadataTotalSeconds": 20,
                   "metadataStreamBytes": 2 * 1024 * 1024,
                   "groupInventorySeconds": 2, "groupInventoryBytes": 65536},
        "limitations": [
            "TOC exportability is separate from recording completion, usable clocks and event/table coverage.",
            "Read-only mode bits and unchanged final hashes do not prove the tool attempted no writes or created no caches elsewhere.",
            "Final process-group snapshots establish no live members at the snapshot time, not every descendant's exit time at the command deadline.",
            "The original D24 recorder exited on signal 11; this diagnostic does not reclassify that recording as complete.",
        ],
    }
    before = tool_before = prepared = None
    export_receipt = None
    export_streams = {"stdout": b"", "stderr": b""}
    tool_path = None
    env = dict(os.environ, LC_ALL="C", LANG="C", PAGER="cat", MANPAGER="cat", MANWIDTH="120", TERM="dumb")
    # Download authentication is not part of any native tool environment or receipt.
    for key in ("GH_TOKEN", "GITHUB_TOKEN"):
        env.pop(key, None)

    def command(name, argv, *, export=False):
        require(name not in report["commands"], "A D25 command cannot be repeated")
        receipt, streams, checks = capture_owned(name, argv, cwd=output.parent, env=env,
                                                budget=33.0 if export else 20.0, reserve=3.0,
                                                limit=(8 if export else 2) * 1024 * 1024)
        for check in checks:
            preserve_command(output, check["name"], check["receipt"], check["streams"])
        receipt["cleanupCommandNames"] = [check["name"] for check in checks]
        report["commands"][name] = preserve_command(output, name, receipt, streams, xml=export)
        return receipt, streams

    def metadata(name, argv):
        receipt, streams = command(name, argv)
        require(receipt.get("transportComplete") and receipt.get("cleanupComplete")
                and receipt.get("exitCode") == 0, name + " did not complete")
        return streams

    try:
        before = source_snapshot(repo, output / "sources")
        report["sourcesBefore"] = before
        report["waitidPreflight"] = waitid_preflight()
        prepared = prepare_input(Path(artifact_zip), work)
        report["input"] = prepared
        write_json(output / "input-before.json", prepared["manifest"])
        raw_input = read_regular(Path(prepared["innerArchivePath"]), 16 * 1024 * 1024)
        require(byte_identity(raw_input) == {k: prepared["innerArchive"][k] for k in ("bytes", "sha256")},
                "Retained inner archive identity changed")
        with (output / "retained-input.trace.zip").open("xb") as retained:
            retained.write(raw_input)
        metadata("os-version", ("/usr/bin/sw_vers",))
        versions = metadata("xcode-version", ("/usr/bin/xcodebuild", "-version"))
        require(versions["stdout"] == XCODE_VERSION, "Reader Xcode version differs from D24 producer")
        report["producerXcodeVersionMatched"] = True
        path_streams = metadata("xctrace-path", ("/usr/bin/xcrun", "--find", "xctrace"))
        tool_path = Path(path_streams["stdout"].decode("utf-8").strip())
        require(tool_path.is_absolute() and tool_path.name == "xctrace"
                and tool_path.resolve(strict=True).is_relative_to(Path(DEVELOPER_DIR).resolve(strict=True)),
                "Installed tool is outside the selected developer directory")
        raw_tool = read_regular(tool_path, MAX_TOOL_BYTES)
        tool_before = inspect_tool(raw_tool, "x86_64")
        report["installedToolBefore"] = {"path": str(tool_path), **tool_before}
        with (output / "installed-xctrace.macho").open("xb") as retained:
            retained.write(raw_tool)
        metadata("xctrace-uuid", ("/usr/bin/xcrun", "dwarfdump", "--uuid", str(tool_path)))
        help_streams = metadata("xctrace-export-help", ("/usr/bin/xcrun", "xctrace", "help", "export"))
        report["exportHelpContract"] = validate_export_help(help_streams["stdout"])
        metadata("xctrace-manual", ("/usr/bin/xcrun", "man", "xctrace"))
        report["preflightComplete"] = True
        # There is one immutable command, no alternate flags or retry path.
        report["exportAttemptCount"] = 1
        export_receipt, export_streams = command(
            "trace-toc", ("/usr/bin/xcrun", "xctrace", "export", "--input", prepared["tracePath"], "--toc"),
            export=True)
        report["exportInvocationCount"] = int(export_receipt.get("pid") is not None)
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        report["errors"].append(type(error).__name__ + ": " + str(error))
    finally:
        if prepared is not None:
            try:
                after = snapshot_trace(Path(prepared["tracePath"]))
                write_json(output / "input-after.json", after)
                report["inputUnchanged"] = after == prepared["manifest"]
                inner = read_regular(Path(prepared["innerArchivePath"]), 16 * 1024 * 1024)
                report["inputArchiveUnchanged"] = byte_identity(inner) == {k: prepared["innerArchive"][k] for k in ("bytes", "sha256")}
                report["inputUnchanged"] = report["inputUnchanged"] and report["inputArchiveUnchanged"]
            except (OSError, ValueError) as error:
                report["errors"].append("Input preservation: " + str(error))
        if before is not None:
            try:
                report["sourcesAfter"] = source_snapshot(repo)
                report["sourceUnchanged"] = report["sourcesAfter"] == before
            except (OSError, ValueError) as error:
                report["errors"].append("Source preservation: " + str(error))
        if tool_before is not None:
            try:
                report["installedToolAfter"] = inspect_tool(read_regular(tool_path, MAX_TOOL_BYTES), "x86_64")
                report["installedToolUnchanged"] = report["installedToolAfter"] == tool_before
            except (OSError, ValueError) as error:
                report["errors"].append("Installed tool preservation: " + str(error))
    if export_receipt is not None:
        report.update(classify_export(export_receipt, export_streams,
                      input_unchanged=report["inputUnchanged"], source_unchanged=report["sourceUnchanged"],
                      tool_unchanged=report["installedToolUnchanged"],
                      preflight_complete=report["preflightComplete"] and not report["errors"]))
    write_json(output / "retained-trace-export.json", report)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--artifact-zip", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--experiment-commit", required=True)
    args = parser.parse_args()
    report = run(args.artifact_zip, args.output, args.experiment_commit)
    print(report["status"], flush=True)
    return 0 if report["diagnosticExecutionComplete"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
