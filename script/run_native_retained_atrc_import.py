#!/usr/bin/env python3
"""D27: one bounded import of the unchanged retained Intel ATRC into a new document."""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess

from collect_native_trace_capabilities import write_json
from native_retained_atrc_output import OutputGuard, capture_import
from native_retained_trace_command import capture_owned
from native_retained_trace_input import INNER_ENTRIES, INNER_IDENTITY, OUTER_IDENTITY, prepare_input, snapshot_trace
from native_sampler_tool_identity import inspect_tool, MAX_TOOL_BYTES
from run_native_recorder_progress_observation import read_regular, waitid_preflight
from run_native_system_trace_startup import preserve_command


BASE = "71909054ccf9d3a174e4de13fdb7c9559387baef"
XCODE_VERSION = b"Xcode 26.3\nBuild version 17C529\n"
DEVELOPER_DIR = "/Applications/Xcode_26.3.app/Contents/Developer"
READER_IDENTITY = {
    "bytes": 121520,
    "sha256": "abf89e498e0bdb43dd48a3ccb545313a83b413a8d329503401ade7fa4e1a5674",
}
RAW_MEMBER = "Trace1.run/Attachments/trace-data.atrc"
RAW_IDENTITY = {
    "bytes": 115782056,
    "sha256": "dd55ca66c46a4651df145287d2db8573e6dcf5f9387dcea73bec21a7a37719f0",
}
TEMPLATE = "System Trace"
METADATA_STREAM_LIMIT = 2 * 1024 * 1024
MINIMUM_FREE_BYTES = 2 * 1024 * 1024 * 1024
NEW_PATHS = (
    ".github/workflows/native-retained-atrc-import.yml",
    "docs/NATIVE_RETAINED_ATRC_IMPORT.md",
    "script/native_retained_atrc_output.py",
    "script/run_native_retained_atrc_import.py",
    "script/test_native_retained_atrc_output.py",
    "script/test_run_native_retained_atrc_import.py",
)
SOURCE_PATHS = NEW_PATHS + (
    "script/collect_native_trace_capabilities.py",
    "script/native_retained_trace_command.py",
    "script/native_retained_trace_input.py",
    "script/native_sampler_tool_identity.py",
    "script/run_native_recorder_progress_observation.py",
    "script/run_native_recorder_startup_observation.py",
    "script/run_native_system_trace_startup.py",
    "script/test_native_retained_trace_command.py",
    "script/test_native_retained_trace_input.py",
    "script/test_run_native_recorder_progress_observation.py",
    "script/privacy_check.py",
    "docs/NATIVE_RETAINED_ATRC_CONTRACT.md",
    "docs/evidence/D26-retained-atrc-contract.json",
)
CONTRACT_EVIDENCE = {
    "publicationCommit": BASE,
    "executedSourceCommit": "e8e0cbe351c82f3804a8f5bfa2c0b22ab54f69b4",
    "runID": 42629940773,
    "attempt": 1,
    "helpStdout": {
        "bytes": 1512,
        "sha256": "4c303ff573648b3acf5db1b647194036565257617779b9a2e81195643b0de340",
    },
    "sourcePaths": ["docs/NATIVE_RETAINED_ATRC_CONTRACT.md", "docs/evidence/D26-retained-atrc-contract.json"],
    "meaning": "D26 establishes command grammar and a System Trace example; exact retained payload acceptance is this experiment's hypothesis.",
}


def require(value, message):
    if not value:
        raise ValueError(message)


def byte_identity(raw):
    return {"bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest()}


def retained_source_path(relative):
    return "sources/" + relative.removeprefix(".github/")


def source_snapshot(repo, retained=None):
    result = {}
    copies = [retained_source_path(relative) for relative in SOURCE_PATHS]
    require(len(copies) == len(set(copies)), "Source copy paths must be unique")
    for relative, copied in zip(SOURCE_PATHS, copies):
        raw = read_regular(repo / relative, 4 * 1024 * 1024)
        result[relative] = byte_identity(raw)
        if retained is not None:
            destination = retained / copied
            destination.parent.mkdir(parents=True, exist_ok=True)
            with destination.open("xb") as output:
                output.write(raw)
    return result


def inspect_templates(raw):
    """Require a fresh exact Standard Templates entry, not a name substring."""
    require(0 < len(raw) <= METADATA_STREAM_LIMIT, "Template listing is empty or exceeds its bound")
    text = raw.decode("utf-8", errors="strict")
    require(not any(ord(character) < 32 and character not in "\t\r\n" for character in text),
            "Template listing contains control characters")
    require(not re.search(r"^\s*(?:error|fatal):|^Traceback \(most recent call last\):", text, re.M | re.I),
            "Template listing has an error envelope")
    lines = text.splitlines()
    headers = [index for index, line in enumerate(lines) if line == "== Standard Templates =="]
    require(len(headers) == 1, "Standard Templates section is missing or ambiguous")
    start = headers[0]
    end = next((index for index in range(start + 1, len(lines))
                if re.fullmatch(r"== .+ ==", lines[index])), len(lines))
    matches = [index + 1 for index, line in enumerate(lines) if line == TEMPLATE]
    require(len(matches) == 1 and start + 1 < matches[0] <= end,
            "A single exact System Trace entry is not present in Standard Templates")
    return {
        "identity": byte_identity(raw), "lineCount": len(lines), "selectedTemplate": TEMPLATE,
        "sectionLine": start + 1, "matchingLine": matches[0], "freshSameRunAvailabilityEstablished": True,
        "templateBytesOrInstrumentMembershipEstablished": False,
    }


def inspect_prepared_input(prepared):
    """Bind the exact raw member of the already fully verified protected tree."""
    manifest = prepared["manifest"]
    entries = manifest["entries"]
    expected = INNER_ENTRIES["recording.trace/" + RAW_MEMBER]
    require({key: expected[key] for key in ("bytes", "sha256")} == RAW_IDENTITY,
            "Frozen D25 raw identity differs from D27")
    raw_entries = [entry for entry in entries if entry.get("path") == RAW_MEMBER]
    require(len(raw_entries) == 1, "Pinned raw ATRC member is missing or ambiguous")
    selected = raw_entries[0]
    require(selected.get("kind") == "file"
            and {key: selected.get(key) for key in ("bytes", "sha256")} == RAW_IDENTITY,
            "Raw ATRC identity differs from the retained input")
    require(all(entry.get("mode") == (0o400 if entry.get("kind") == "file" else 0o500)
                and entry.get("kind") in ("file", "directory") for entry in entries),
            "Prepared input does not have the fixed protected modes")
    require(manifest.get("fileCount") == 2 and manifest.get("directoryCount") == 3
            and manifest.get("expandedBytes") == INNER_IDENTITY["expandedBytes"],
            "Prepared input inventory differs from the retained trace")
    trace = Path(prepared["tracePath"])
    require(trace.is_absolute(), "Prepared trace path must be absolute")
    raw_path = trace / RAW_MEMBER
    require(raw_path.resolve(strict=True) == raw_path and raw_path.is_file(),
            "Prepared raw path is not its canonical regular-file location")
    return {"path": str(raw_path), "member": "recording.trace/" + RAW_MEMBER,
            **RAW_IDENTITY, "mode": selected["mode"], "fullInputTreeHashed": True,
            "retainedCodeExecuted": False}


def classify_import(receipt, streams, output_report, *, input_unchanged, source_unchanged,
                    tool_unchanged, preflight_complete, synthetic=False):
    """A bounded rejection is evidence; success qualifies only this import's acceptance."""
    code = receipt.get("exitCode")
    result = {
        "status": "diagnostic-incomplete", "diagnosticExecutionComplete": False,
        "commandExitedSuccessfully": type(code) is int and code == 0,
        "importAcceptedWithSelection": False, "derivedAnalysisDocumentObserved": False,
        "retainedPayloadAcceptanceEstablished": False, "nativeImportEvidenceEstablished": False,
        "stderrPresent": bool(streams["stderr"]), "inputUnchanged": input_unchanged,
        "sourceUnchanged": source_unchanged, "installedToolUnchanged": tool_unchanged,
        "ATRCFormatAcceptanceEstablished": False, "importSelectionSemanticsEstablished": False,
        "derivedDocumentReadableEstablished": False, "recordingCompletionEstablished": False,
        "traceTableDataExportEstablished": False, "usableClockMappingEstablished": False,
        "eventTimeRangeEstablished": False, "samplerWindowCoverageEstablished": False,
        "phaseEstablished": False, "activationRouteCoverageEstablished": False,
        "ipcRequestChainEstablished": False,
    }
    complete = (type(code) is int and receipt.get("transportComplete") is True
                and receipt.get("cleanupComplete") is True and receipt.get("outputBoundsPass") is True
                and output_report.get("outputBoundsPass") is True
                and output_report.get("retentionComplete") is True
                and output_report.get("inventoryComplete") is True
                and input_unchanged is True and source_unchanged is True
                and tool_unchanged is True and preflight_complete is True)
    if not complete:
        return result
    result["diagnosticExecutionComplete"] = True
    if code != 0:
        result["status"] = "import-terminated-by-signal" if code < 0 else "import-refused"
        return result
    archive = output_report.get("archive")
    archive_qualified = (isinstance(archive, dict) and archive.get("name") == "derived.trace.zip"
                         and type(archive.get("bytes")) is int and archive["bytes"] > 0
                         and isinstance(archive.get("sha256"), str)
                         and re.fullmatch(r"[0-9a-f]{64}", archive["sha256"]) is not None
                         and archive.get("crcAndSHA256Verified") is True)
    if output_report.get("newAnalysisDocumentObserved") is not True or not archive_qualified:
        result["status"] = "import-output-unqualified"
        return result
    result.update(status="import-accepted-with-stderr" if streams["stderr"] else "import-accepted",
                  importAcceptedWithSelection=True, derivedAnalysisDocumentObserved=True,
                  retainedPayloadAcceptanceEstablished=not synthetic, nativeImportEvidenceEstablished=not synthetic)
    return result


def run(artifact_zip, output, experiment_commit):
    require(platform.system() == "Darwin" and platform.machine() == "x86_64", "D27 requires native Intel macOS")
    require(os.geteuid() != 0, "D27 must run without root privileges")
    require(tuple(map(int, platform.python_version_tuple()[:2])) >= (3, 13),
            "D27 requires Python 3.13 or later for macOS non-reaping child status")
    require(os.environ.get("DEVELOPER_DIR") == DEVELOPER_DIR, "Require the original Xcode 26.3 selection")
    require(re.fullmatch(r"[0-9a-f]{40}", experiment_commit), "Require an immutable experiment commit")
    repo = Path(__file__).resolve().parent.parent

    def git(*args):
        return subprocess.check_output(["git", *args], cwd=repo, text=True, timeout=5).strip()

    require(git("rev-parse", "HEAD") == experiment_commit, "Experiment commit differs")
    require(not git("status", "--porcelain"), "Require a clean experiment worktree")
    git("merge-base", "--is-ancestor", BASE, "HEAD")
    require(set(git("diff", "--name-only", BASE, "HEAD").splitlines()) <= set(NEW_PATHS),
            "Unexpected changes outside the isolated D27 allowlist")
    tree = git("rev-parse", "HEAD^{tree}")
    output = Path(output)
    require(output.is_absolute() and output.parent.is_dir() and output.name not in ("", ".", ".."),
            "Require a new absolute evidence directory")
    output = output.parent.resolve(strict=True) / output.name
    require(not output.is_relative_to(repo), "Evidence must be outside the clean experiment worktree")
    output.mkdir(mode=0o700, exist_ok=False)
    work = output.parent / (output.name + "-input")
    report = {
        "schema": 1, "diagnostic": "D27-retained-atrc-import", "evidenceKind": "native-retained-input-compatibility-diagnostic",
        "experimentCommit": experiment_commit, "experimentTree": tree, "baseCommit": BASE,
        "architecture": "x86_64", "pythonVersion": platform.python_version(),
        "status": "diagnostic-incomplete", "diagnosticExecutionComplete": False,
        "importAttemptCount": 0, "importInvocationCount": 0, "exportInvocationCount": 0,
        "recordingInvocationCount": 0, "samplerInvocationCount": 0, "traceInputSupplied": False,
        "retainedCodeExecuted": False, "applicationLaunchRequested": False, "settingsChanged": False,
        "inputRepairRequested": False, "C12": "HOLD", "releaseReady": False,
        "commands": {}, "errors": [], "preflightComplete": False,
        "inputUnchanged": False, "sourceUnchanged": False, "installedToolUnchanged": False,
        "sourceCopies": {relative: retained_source_path(relative) for relative in SOURCE_PATHS},
        "importContractEvidence": CONTRACT_EVIDENCE,
        "bounds": {"importNormalSeconds": 90, "importTotalSeconds": 95,
                   "importCombinedStreamBytes": 8 * 1024 * 1024,
                   "outputLogicalBytes": 512 * 1024 * 1024, "outputAllocatedBytes": 512 * 1024 * 1024,
                   "outputEntries": 16384, "outputDepth": 32, "outputSampleIntervalSeconds": .05,
                   "outputScanSeconds": .25, "outputRetentionSeconds": 30,
                   "minimumInitialFreeBytes": MINIMUM_FREE_BYTES,
                   "metadataNormalSeconds": 17, "metadataTotalSeconds": 20,
                   "metadataStreamBytes": METADATA_STREAM_LIMIT,
                   "groupInventorySeconds": 2, "groupInventoryBytes": 65536},
        "limitations": [
            "Import acceptance qualifies only this unchanged input, selected reader and explicit System Trace selection; general ATRC compatibility is not established.",
            "The observed new document is not reopened or exported here; its readability, event preservation and clock coverage are unestablished.",
            "Output growth limits are sampled stop conditions, not a kernel-enforced aggregate storage quota; initial free space is not reserved capacity.",
            "Read-only modes and unchanged final hashes do not prove that no write was attempted or that no caches were created elsewhere.",
            "The pinned xctrace bytes and Xcode version do not establish equality of every framework, plugin or template byte.",
            "Final process-group snapshots establish no live members at the snapshot, not retrospective descendant exit times.",
            "D24's abnormal recording and D25's missing-template export refusal remain unchanged; original product acceptance remains HOLD.",
        ],
    }
    before = tool_before = tool_path = prepared = guard = import_receipt = None
    import_streams = {"stdout": b"", "stderr": b""}
    output_report = {}
    env = dict(os.environ, LC_ALL="C", LANG="C", TERM="dumb")
    for key in ("GH_TOKEN", "GITHUB_TOKEN"):
        env.pop(key, None)

    def preserve(name, receipt, streams, checks):
        report["commands"][name] = receipt
        for check in checks:
            preserve_command(output, check["name"], check["receipt"], check["streams"])
        receipt["cleanupCommandNames"] = [check["name"] for check in checks]
        report["commands"][name] = preserve_command(output, name, receipt, streams)

    def metadata(name, argv):
        require(name not in report["commands"], "A D27 command cannot be repeated")
        receipt, streams, checks = capture_owned(name, argv, cwd=output.parent, env=env,
                                                budget=20.0, reserve=3.0, limit=METADATA_STREAM_LIMIT)
        preserve(name, receipt, streams, checks)
        require(receipt.get("transportComplete") is True and receipt.get("cleanupComplete") is True
                and type(receipt.get("exitCode")) is int and receipt["exitCode"] == 0,
                name + " did not complete")
        return streams

    try:
        before = source_snapshot(repo, output)
        report["sourcesBefore"] = before
        report["waitidPreflight"] = waitid_preflight()
        report["initialFreeSpace"] = {"path": str(output.parent), "freeBytes": shutil.disk_usage(output.parent).free,
                                      "minimumBytes": MINIMUM_FREE_BYTES, "capacityReserved": False}
        require(report["initialFreeSpace"]["freeBytes"] >= MINIMUM_FREE_BYTES,
                "Initial free space is below the D27 eligibility threshold")
        prepared = prepare_input(Path(artifact_zip), work)
        report["input"] = prepared
        report["rawInput"] = inspect_prepared_input(prepared)
        write_json(output / "input-before.json", prepared["manifest"])
        inner = read_regular(Path(prepared["innerArchivePath"]), 16 * 1024 * 1024)
        require(byte_identity(inner) == {key: INNER_IDENTITY[key] for key in ("bytes", "sha256")},
                "Retained inner archive identity changed")
        with (output / "retained-input.trace.zip").open("xb") as retained:
            retained.write(inner)
        guard = OutputGuard(output.parent / (output.name + "-derived"), intended_name="derived.trace")
        report["derivedOutputPath"] = str(guard.target)
        metadata("os-version", ("/usr/bin/sw_vers",))
        version = metadata("xcode-version", ("/usr/bin/xcodebuild", "-version"))
        require(version["stdout"] == XCODE_VERSION, "Reader Xcode version differs from D25/D26")
        report["D25XcodeVersionMatched"] = True
        found = metadata("xctrace-path", ("/usr/bin/xcrun", "--find", "xctrace"))
        lines = found["stdout"].decode("utf-8", errors="strict").splitlines()
        require(len(lines) == 1 and lines[0].strip() == lines[0], "Installed tool path is ambiguous")
        tool_path = Path(lines[0])
        require(tool_path.is_absolute() and tool_path.name == "xctrace"
                and tool_path.resolve(strict=True).is_relative_to(Path(DEVELOPER_DIR).resolve(strict=True)),
                "Installed tool is outside the selected developer directory")
        raw_tool = read_regular(tool_path, MAX_TOOL_BYTES)
        require(byte_identity(raw_tool) == READER_IDENTITY, "Installed reader bytes differ from D25/D26")
        report["D25ReaderBytesMatched"] = True
        tool_before = inspect_tool(raw_tool, "x86_64")
        report["installedToolBefore"] = {"path": str(tool_path), **tool_before}
        with (output / "installed-xctrace.macho").open("xb") as retained:
            retained.write(raw_tool)
        metadata("xctrace-uuid", ("/usr/bin/xcrun", "dwarfdump", "--uuid", str(tool_path)))
        templates = metadata("xctrace-templates", ("/usr/bin/xcrun", "xctrace", "list", "templates"))
        report["templateAvailability"] = inspect_templates(templates["stdout"])
        launch_input = snapshot_trace(Path(prepared["tracePath"]))
        report["inputMatchedImmediatelyBeforeImport"] = launch_input == prepared["manifest"]
        require(report["inputMatchedImmediatelyBeforeImport"], "Protected input changed before the import")
        report["preflightComplete"] = True
        report["importAttemptCount"] = 1
        argv = ("/usr/bin/xcrun", "xctrace", "import", "--input", report["rawInput"]["path"],
                "--template", TEMPLATE, "--output", str(guard.target))
        import_receipt, import_streams, checks = capture_import(
            "atrc-import", argv, cwd=guard.root, env=env, guard=guard)
        report["importInvocationCount"] = int(import_receipt.get("pid") is not None)
        report["traceInputSupplied"] = report["importInvocationCount"] == 1
        preserve("atrc-import", import_receipt, import_streams, checks)
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        report["errors"].append(type(error).__name__ + ": " + str(error))
    finally:
        if guard is not None:
            try:
                output_report = guard.finalize(output / "derived.trace.zip",
                    safe_to_read=import_receipt is not None and import_receipt.get("cleanupComplete") is True)
                report["derivedOutput"] = output_report
            except (OSError, ValueError, RuntimeError) as error:
                report["errors"].append("Output retention: " + str(error))
            finally:
                try:
                    guard.close()
                except (OSError, ValueError, RuntimeError) as error:
                    report["errors"].append("Output guard close: " + str(error))
        if prepared is not None:
            try:
                after = snapshot_trace(Path(prepared["tracePath"]))
                write_json(output / "input-after.json", after)
                report["inputTreeUnchanged"] = after == prepared["manifest"]
                inner_after = byte_identity(read_regular(Path(prepared["innerArchivePath"]), 16 * 1024 * 1024))
                outer_after = byte_identity(read_regular(Path(prepared["artifactPath"]), 16 * 1024 * 1024))
                report["inputArchiveUnchanged"] = inner_after == {key: INNER_IDENTITY[key] for key in ("bytes", "sha256")}
                report["sourceArtifactUnchanged"] = outer_after == {key: OUTER_IDENTITY[key] for key in ("bytes", "sha256")}
                report["inputUnchanged"] = (report["inputTreeUnchanged"] and report["inputArchiveUnchanged"]
                                            and report["sourceArtifactUnchanged"])
            except (OSError, ValueError) as error:
                report["errors"].append("Input preservation: " + str(error))
        if before is not None:
            try:
                report["sourcesAfter"] = source_snapshot(repo)
                report["sourceBytesUnchanged"] = report["sourcesAfter"] == before
                report["repositoryAfter"] = {"commit": git("rev-parse", "HEAD"),
                                               "tree": git("rev-parse", "HEAD^{tree}"),
                                               "clean": not git("status", "--porcelain")}
                report["sourceUnchanged"] = (report["sourceBytesUnchanged"]
                    and report["repositoryAfter"] == {"commit": experiment_commit, "tree": tree, "clean": True})
            except (OSError, ValueError, subprocess.SubprocessError) as error:
                report["errors"].append("Source preservation: " + str(error))
        if tool_before is not None:
            try:
                raw_after = read_regular(tool_path, MAX_TOOL_BYTES)
                report["installedToolAfter"] = inspect_tool(raw_after, "x86_64")
                report["installedToolUnchanged"] = (byte_identity(raw_after) == READER_IDENTITY
                    and report["installedToolAfter"] == tool_before)
            except (OSError, ValueError) as error:
                report["errors"].append("Installed tool preservation: " + str(error))
    report.update(classify_import(import_receipt or {}, import_streams, output_report,
                  input_unchanged=report["inputUnchanged"], source_unchanged=report["sourceUnchanged"],
                  tool_unchanged=report["installedToolUnchanged"],
                  preflight_complete=report["preflightComplete"] and not report["errors"]))
    write_json(output / "retained-atrc-import.json", report)
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
