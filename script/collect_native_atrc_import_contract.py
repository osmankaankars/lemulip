#!/usr/bin/env python3
"""D26: collect one installed import-help response without supplying trace data."""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import platform
import re
import subprocess

from collect_native_trace_capabilities import write_json
from native_retained_trace_command import capture_owned
from native_sampler_tool_identity import inspect_tool, MAX_TOOL_BYTES
from run_native_recorder_progress_observation import read_regular, waitid_preflight
from run_native_system_trace_startup import preserve_command


BASE = "6102d5d209d5918bc6ae61056917fbb9e3b16987"
XCODE_VERSION = b"Xcode 26.3\nBuild version 17C529\n"
DEVELOPER_DIR = "/Applications/Xcode_26.3.app/Contents/Developer"
READER_IDENTITY = {
    "bytes": 121520,
    "sha256": "abf89e498e0bdb43dd48a3ccb545313a83b413a8d329503401ade7fa4e1a5674",
}
STREAM_LIMIT = 2 * 1024 * 1024
NEW_PATHS = (
    ".github/workflows/native-atrc-import-contract.yml",
    "docs/NATIVE_RETAINED_ATRC_CONTRACT.md",
    "script/collect_native_atrc_import_contract.py",
    "script/test_collect_native_atrc_import_contract.py",
)
SOURCE_PATHS = NEW_PATHS + (
    "script/collect_native_trace_capabilities.py",
    "script/native_retained_trace_command.py",
    "script/native_sampler_tool_identity.py",
    "script/run_native_recorder_progress_observation.py",
    "script/run_native_recorder_startup_observation.py",
    "script/run_native_system_trace_startup.py",
    "script/test_native_retained_trace_command.py",
    "script/test_run_native_recorder_progress_observation.py",
    "script/privacy_check.py",
)


def require(value, message):
    if not value:
        raise ValueError(message)


def byte_identity(raw):
    return {"bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest()}


def retained_source_path(relative):
    # A hidden .github directory was omitted by D25's artifact upload. Keep
    # this single approved workflow copy visible without uploading hidden files.
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


def inspect_import_help(raw):
    """Recognize help grammar, retaining literal lines without format inference."""
    require(0 < len(raw) <= STREAM_LIMIT, "Import help is empty or exceeds its bound")
    text = raw.decode("utf-8", errors="strict")
    require(not any(ord(character) < 32 and character not in "\t\r\n"
                    for character in text), "Import help contains control characters")
    usage = re.findall(r"^\s*usage:\s*(.+)$", text, re.M | re.I)
    inputs = re.findall(r"^\s*--input\s+(<[^>\r\n]+>)(?=\s|$)", text, re.M)
    outputs = re.findall(r"^\s*--output\s+(<[^>\r\n]+>)(?=\s|$)", text, re.M)
    checks = {
        "singleImportUsage": len(usage) == 1 and bool(re.match(r"xctrace\s+import(?:\s|$)", usage[0])),
        "singleInputOption": len(inputs) == 1 and inputs[0] in ("<file>", "<path>"),
        "singleOutputOption": len(outputs) == 1 and outputs[0] in ("<file>", "<path>"),
        "noErrorEnvelope": not bool(re.search(r"^\s*(?:error|fatal):|^Traceback \(most recent call last\):", text, re.M | re.I)),
    }
    require(all(checks.values()), "Import help grammar is unrecognized or ambiguous")
    observations = {}
    lines = text.splitlines()
    for term in ("ATRC", "ktrace", "logarchive", "--template", "--instrument"):
        matches = [{"line": index, "text": line} for index, line in enumerate(lines, 1)
                   if term.casefold() in line.casefold()]
        observations[term] = {"matchingLineCount": len(matches), "retainedLines": matches[:64],
                              "linesOmitted": max(0, len(matches) - 64)}
    return {
        "identity": byte_identity(raw), "grammarChecks": checks,
        "lineCount": len(lines), "literalObservations": observations,
        "interpretation": "Literal matching lines only; a keyword does not establish supported format, accepted payload, selection semantics or event coverage.",
    }


def classify_help(receipt, streams, *, source_unchanged, tool_unchanged,
                  preflight_complete, synthetic=False):
    code = receipt.get("exitCode")
    result = {
        "status": "diagnostic-incomplete", "diagnosticExecutionComplete": False,
        "commandExitedSuccessfully": type(code) is int and code == 0,
        "helpGrammarRecognized": False, "nativeHelpEvidenceEstablished": False,
        "helpText": None, "stderrPresent": bool(streams["stderr"]),
        "interpretationErrors": [], "sourceUnchanged": source_unchanged,
        "installedToolUnchanged": tool_unchanged,
        "ATRCFormatAcceptanceEstablished": False, "retainedPayloadAcceptanceEstablished": False,
        "importSelectionSemanticsEstablished": False, "recordingCompletionEstablished": False,
        "usableClockMappingEstablished": False, "eventTimeRangeEstablished": False,
        "samplerWindowCoverageEstablished": False, "phaseEstablished": False,
        "activationRouteCoverageEstablished": False, "ipcRequestChainEstablished": False,
    }
    complete = (type(code) is int and receipt.get("transportComplete") is True
                and receipt.get("cleanupComplete") is True and source_unchanged is True
                and tool_unchanged is True and preflight_complete is True)
    if not complete:
        return result
    result["diagnosticExecutionComplete"] = True
    if code != 0:
        result["status"] = "help-terminated-by-signal" if code < 0 else "help-refused"
        return result
    try:
        result["helpText"] = inspect_import_help(streams["stdout"])
    except (ValueError, UnicodeError) as error:
        result["status"] = "help-output-unqualified"
        result["interpretationErrors"].append(type(error).__name__ + ": " + str(error))
        return result
    result.update(status="help-collected", helpGrammarRecognized=True,
                  nativeHelpEvidenceEstablished=not synthetic)
    return result


def run(output, experiment_commit):
    require(platform.system() == "Darwin" and platform.machine() == "x86_64",
            "D26 requires native Intel macOS")
    require(os.geteuid() != 0, "D26 must run without root privileges")
    require(tuple(map(int, platform.python_version_tuple()[:2])) >= (3, 13),
            "D26 requires Python 3.13 or later for macOS non-reaping child status")
    require(os.environ.get("DEVELOPER_DIR") == DEVELOPER_DIR, "Require the original Xcode 26.3 selection")
    require(re.fullmatch(r"[0-9a-f]{40}", experiment_commit), "Require an immutable experiment commit")
    repo = Path(__file__).resolve().parent.parent

    def git(*args):
        return subprocess.check_output(["git", *args], cwd=repo, text=True, timeout=5).strip()

    require(git("rev-parse", "HEAD") == experiment_commit, "Experiment commit differs")
    require(not git("status", "--porcelain"), "Require a clean experiment worktree")
    git("merge-base", "--is-ancestor", BASE, "HEAD")
    require(set(git("diff", "--name-only", BASE, "HEAD").splitlines()) <= set(NEW_PATHS),
            "Unexpected changes outside the isolated D26 allowlist")
    tree = git("rev-parse", "HEAD^{tree}")
    output = Path(output)
    require(output.is_absolute() and output.parent.is_dir(), "Require a new absolute output directory")
    output = output.parent.resolve(strict=True) / output.name
    require(not output.is_relative_to(repo), "Evidence output must be outside the clean experiment worktree")
    output.mkdir(exist_ok=False)
    report = {
        "schema": 1, "diagnostic": "D26-atrc-import-contract", "evidenceKind": "native-installed-help-diagnostic",
        "experimentCommit": experiment_commit, "experimentTree": tree, "baseCommit": BASE,
        "architecture": "x86_64", "pythonVersion": platform.python_version(),
        "status": "diagnostic-incomplete", "diagnosticExecutionComplete": False,
        "importHelpAttemptCount": 0, "importHelpInvocationCount": 0,
        "importInvocationCount": 0, "exportInvocationCount": 0, "recordingInvocationCount": 0,
        "samplerInvocationCount": 0, "traceInputSupplied": False, "inputDownloadRequested": False,
        "nativeInputExecuted": False, "applicationLaunchRequested": False, "settingsChanged": False,
        "inputRepairRequested": False, "C12": "HOLD", "releaseReady": False,
        "commands": {}, "errors": [], "preflightComplete": False,
        "sourceUnchanged": False, "installedToolUnchanged": False,
        "sourceCopies": {relative: retained_source_path(relative) for relative in SOURCE_PATHS},
        "bounds": {"commandNormalSeconds": 17, "commandTotalSeconds": 20,
                   "commandStreamBytes": STREAM_LIMIT, "groupInventorySeconds": 2,
                   "groupInventoryBytes": 65536},
        "limitations": [
            "Collected help text and literal format mentions are not proof that the retained payload is accepted or contains usable events.",
            "The reader executable is pinned to D25; all producer/reader framework bytes are not thereby proven identical.",
            "Final process-group snapshots establish no live members at the snapshot, not every descendant exit time at the operation deadline.",
            "D25's refused document export and D24's abnormal recording remain unchanged; this command supplies no input and creates no derived trace.",
        ],
    }
    before = tool_before = tool_path = help_receipt = None
    help_streams = {"stdout": b"", "stderr": b""}
    env = dict(os.environ, LC_ALL="C", LANG="C", TERM="dumb")
    for key in ("GH_TOKEN", "GITHUB_TOKEN"):
        env.pop(key, None)

    def command(name, argv):
        require(name not in report["commands"], "A D26 command cannot be repeated")
        receipt, streams, checks = capture_owned(name, argv, cwd=output.parent, env=env,
                                                budget=20.0, reserve=3.0, limit=STREAM_LIMIT)
        report["commands"][name] = receipt
        if name == "xctrace-import-help":
            report["importHelpInvocationCount"] = int(receipt.get("pid") is not None)
        for check in checks:
            preserve_command(output, check["name"], check["receipt"], check["streams"])
        receipt["cleanupCommandNames"] = [check["name"] for check in checks]
        report["commands"][name] = preserve_command(output, name, receipt, streams)
        return receipt, streams

    def metadata(name, argv):
        receipt, streams = command(name, argv)
        require(receipt.get("transportComplete") is True and receipt.get("cleanupComplete") is True
                and type(receipt.get("exitCode")) is int and receipt["exitCode"] == 0,
                name + " did not complete")
        return streams

    try:
        before = source_snapshot(repo, output)
        report["sourcesBefore"] = before
        report["waitidPreflight"] = waitid_preflight()
        metadata("os-version", ("/usr/bin/sw_vers",))
        version = metadata("xcode-version", ("/usr/bin/xcodebuild", "-version"))
        require(version["stdout"] == XCODE_VERSION, "Reader Xcode version differs from D25")
        report["D25XcodeVersionMatched"] = True
        found = metadata("xctrace-path", ("/usr/bin/xcrun", "--find", "xctrace"))
        lines = found["stdout"].decode("utf-8", errors="strict").splitlines()
        require(len(lines) == 1 and lines[0].strip() == lines[0], "Installed tool path is ambiguous")
        tool_path = Path(lines[0])
        require(tool_path.is_absolute() and tool_path.name == "xctrace"
                and tool_path.resolve(strict=True).is_relative_to(Path(DEVELOPER_DIR).resolve(strict=True)),
                "Installed tool is outside the selected developer directory")
        raw_tool = read_regular(tool_path, MAX_TOOL_BYTES)
        require(byte_identity(raw_tool) == READER_IDENTITY, "Installed reader bytes differ from D25")
        report["D25ReaderBytesMatched"] = True
        tool_before = inspect_tool(raw_tool, "x86_64")
        report["installedToolBefore"] = {"path": str(tool_path), **tool_before}
        with (output / "installed-xctrace.macho").open("xb") as retained:
            retained.write(raw_tool)
        metadata("xctrace-uuid", ("/usr/bin/xcrun", "dwarfdump", "--uuid", str(tool_path)))
        report["preflightComplete"] = True
        report["importHelpAttemptCount"] = 1
        help_receipt, help_streams = command("xctrace-import-help", ("/usr/bin/xcrun", "xctrace", "help", "import"))
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        report["errors"].append(type(error).__name__ + ": " + str(error))
    finally:
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
    report.update(classify_help(help_receipt or {}, help_streams,
                  source_unchanged=report["sourceUnchanged"], tool_unchanged=report["installedToolUnchanged"],
                  preflight_complete=report["preflightComplete"] and not report["errors"]))
    write_json(output / "atrc-import-contract.json", report)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--experiment-commit", required=True)
    args = parser.parse_args()
    report = run(args.output, args.experiment_commit)
    print(report["status"], flush=True)
    return 0 if report["diagnosticExecutionComplete"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
