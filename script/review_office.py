#!/usr/bin/env python3
"""Guide a local, human review of captured conversions in Microsoft Office."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import stat
import subprocess
import sys
import tempfile


CASES = {
    "word-text": ("Word", "macOS TXT → DOCX", ("source.txt", "converted.docx"),
                  "Check paragraph/blank-line order, tabs, repeated spaces, literal & and <Symbols>, and İstanbul • 東京."),
    "word-rtf": ("Word", "macOS Basic RTF → DOCX", ("source.rtf", "converted.docx"),
                 "Check centered bold/italic Orchard Notes in Arial 14 pt, left-aligned Second Paragraph in Arial 11 pt, and spacing/font substitution."),
    "word-layout": ("Word", "LibreOffice DOCX → ODT → DOCX", ("source.docx", "intermediate.odt", "converted.docx"),
                    "In Print Layout, compare two pages, explicit page break, heading, Unicode, table and margins. Check for clipping or an unexpected third page."),
    "word-html": ("Word", "LibreOffice HTML → DOCX", ("source.html", "converted.docx"),
                  "Check the level-one heading, bold/italic phrases, decoded symbols, Fruit/Count and Lemon/12 table, and After the Table outside it."),
    "word-markdown": ("Word", "Built-In Markdown → DOCX", ("source.md", "converted.docx"),
                      "Check heading, emphasis, real bullet/numbered lists, Unicode, two-row/two-column table, and literal three-line code including indentation. After the Table stays outside the table."),
    "excel-text": ("Excel", "Built-In CSV → XLSX", ("source.csv", "converted.xlsx"),
                   "In Sheet1 and the formula bar, check literal 00123, 12345678901234567890, _x0041_, 12/03/2026 and =1+2. The expression must not calculate to 3."),
    "excel-formulas": ("Excel", "LibreOffice XLSX → ODS → XLSX", ("source.xlsx", "intermediate.ods", "converted.xlsx"),
                       "Check Budget before Summary, two-decimal numbers and text identifiers. In the working converted copy, change Budget!B2 from 12.5 to 22.5, then Calculate Now. Budget!B4 must change 20→30 and Summary!A1 40→60; both remain formulas."),
    "powerpoint-layout": ("PowerPoint", "LibreOffice PPTX → ODP → PPTX", ("source.pptx", "intermediate.odp", "converted.pptx"),
                          "Compare Orchard Overview then Lemon Details, widescreen size, Arial 24 pt titles and green panel positions. Inspect editing view and Play From Start for clipping, shifted shapes or colors."),
}
APPLICATIONS = {"Word": "com.microsoft.Word", "Excel": "com.microsoft.Excel", "PowerPoint": "com.microsoft.Powerpoint"}
CAPTURE_PATHS = {f"cases/{case}/{name}" for case, (_, _, names, _) in CASES.items() for name in names}
DOCUMENTATION = {"README.md", "REVIEW_RESULTS.md", "manifest.json"}
RESULT_NAMES = {"review-results.json", "REVIEW_RESULTS.md", "working"}
MAX_FILE_BYTES = 4 * 1024 * 1024
MAX_CAPTURE_BYTES = 16 * 1024 * 1024
VERSION = re.compile(r"[0-9]+(?:\.[0-9]+){0,4}\Z")
COMMIT = re.compile(r"[0-9a-f]{40}\Z")
SHA256 = re.compile(r"[0-9a-f]{64}\Z")
OUTCOMES = {"p": "Pass", "n": "Needs Review", "f": "Fail"}
NOTE_BLOCKS = (
    r"(?:/Users/|/home/|/Volumes/|/private/|/tmp/|file://|[A-Za-z]:[\\/]|~/)",
    r"[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}",
    r"(?:https?://|-----BEGIN|github_pat_|\bgh[pousr]_|\bsk-(?:proj-|svcacct-)?|\bxox[baprs]-)",
    r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b",
    r"(?i:\b(?:password|passwd|api[_ -]?key|secret|token|account|username|serial[_ -]?number)\s*[:=])",
    r"(?i:\b[\w'-]+[- ](?:MacBook|iMac|Mac-Pro|Mac-mini)\b)",
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def checked_path(value: Path) -> Path:
    path = Path(os.path.abspath(os.path.expanduser(str(value))))
    require(not any(part.is_symlink() for part in (path, *path.parents)), "Use ordinary folders and files, not symbolic links.")
    return path


def read_file(path: Path, limit: int = MAX_FILE_BYTES) -> bytes:
    checked_path(path)
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(descriptor, "rb") as stream:
        info = os.fstat(stream.fileno())
        require(stat.S_ISREG(info.st_mode) and 0 < info.st_size <= limit, "A review file is missing, empty, oversized, or not a regular file.")
        data = stream.read(limit + 1)
        require(len(data) == info.st_size and len(data) <= limit, "A review file changed while being read.")
        return data


def unique_object(pairs: list[tuple]) -> dict:
    result = {}
    for key, value in pairs:
        require(key not in result, "Duplicate JSON fields are not allowed.")
        result[key] = value
    return result


def decode_json(data: bytes) -> dict:
    result = json.loads(data, object_pairs_hook=unique_object)
    require(isinstance(result, dict), "Expected a JSON object.")
    return result


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def validate_capture(directory: Path) -> dict:
    root = checked_path(directory)
    require(root.is_dir(), "Choose the extracted Lemulip-Office-Review folder.")
    manifest_data = read_file(root / "manifest.json", 256 * 1024)
    manifest = decode_json(manifest_data)
    require(set(manifest) == {"schema", "source", "target_application_review", "scope", "cases", "files"}
            and type(manifest["schema"]) is int and manifest["schema"] == 1
            and manifest["target_application_review"] == "Not Reviewed"
            and isinstance(manifest["scope"], str), "Unsupported review manifest.")
    source = manifest["source"]
    expected_source = {"commit", "version", "build", "platform", "os_version", "architecture", "source_worktree"}
    require(isinstance(source, dict) and expected_source <= set(source)
            and set(source) <= expected_source | {"workflow_url"}, "Invalid capture provenance.")
    require(all(isinstance(value, str) for value in source.values())
            and COMMIT.fullmatch(source["commit"]) is not None
            and re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", source["version"]) is not None
            and re.fullmatch(r"[0-9]+", source["build"]) is not None
            and VERSION.fullmatch(source["os_version"]) is not None
            and source["platform"] == "macOS" and source["architecture"] in {"arm64", "x86_64"}
            and source["source_worktree"] == "Clean", "Invalid capture provenance.")
    if "workflow_url" in source:
        require(re.fullmatch(r"https://github\.com/osmankaankars/lemulip/actions/runs/[0-9]+", source["workflow_url"]) is not None,
                "Unexpected capture workflow URL.")
    cases = manifest["cases"]
    require(isinstance(cases, list) and len(cases) == len(CASES), "All eight review cases are required.")
    routes = {}
    for case in cases:
        require(isinstance(case, dict) and set(case) == {"id", "route", "target_application_review", "files"}, "Invalid review case.")
        identifier = case["id"]
        require(isinstance(identifier, str) and identifier in CASES and identifier not in routes, "Unknown or duplicate review case.")
        _, route, names, _ = CASES[identifier]
        allowed_routes = {route} | ({"Pandoc Markdown → DOCX"} if identifier == "word-markdown" else set())
        require(isinstance(case["route"], str) and case["route"] in allowed_routes
                and case["target_application_review"] == "Not Reviewed"
                and case["files"] == [f"cases/{identifier}/{name}" for name in names], "Unexpected review route or filenames.")
        routes[identifier] = case["route"]
    metadata = manifest["files"]
    require(isinstance(metadata, dict) and set(metadata) == CAPTURE_PATHS, "The manifest must identify exactly the expected captured files.")
    files = {}
    for name, info in metadata.items():
        require(isinstance(info, dict) and set(info) == {"bytes", "sha256"}
                and type(info["bytes"]) is int and 0 < info["bytes"] <= MAX_FILE_BYTES
                and isinstance(info["sha256"], str) and SHA256.fullmatch(info["sha256"]) is not None, "Invalid captured-file metadata.")
        data = read_file(root / name)
        require(len(data) == info["bytes"] and digest(data) == info["sha256"], "A captured file no longer matches its manifest. Extract a fresh copy of the original archive.")
        files[name] = data
    require(sum(map(len, files.values())) <= MAX_CAPTURE_BYTES, "The capture exceeds the review size limit.")
    checksums_data = read_file(root / "SHA256SUMS.txt", 16 * 1024)
    checksums = {}
    for line in checksums_data.decode("utf-8").splitlines():
        match = re.fullmatch(r"([0-9a-f]{64})  (.+)", line)
        require(match is not None, "Invalid capture checksum list.")
        checksum, name = match.groups()
        require(name in CAPTURE_PATHS | DOCUMENTATION and name not in checksums, "Unexpected or duplicate capture checksum filename.")
        checksums[name] = checksum
    require(set(checksums) == CAPTURE_PATHS | DOCUMENTATION, "The capture checksum list is incomplete.")
    for name, checksum in checksums.items():
        data = files[name] if name in files else read_file(root / name, 256 * 1024)
        require(digest(data) == checksum, "A capture or guide changed. Keep original capture files unchanged and use a separate results folder.")
    capture_id = {"commit": source["commit"], "version": source["version"], "build": source["build"],
                  "manifest_sha256": digest(manifest_data), "checksums_sha256": digest(checksums_data)}
    note = None
    if source["commit"] == "e4f72b3a193437b6d9486ad2ee6785fd20a07e3b" and routes["word-markdown"] == "Pandoc Markdown → DOCX":
        note = "The original v0.1.15 manifest labels word-markdown as Pandoc. This source's captured case uses Lemulip's built-in writer. Original capture metadata and bytes are preserved."
    return {"root": root, "id": capture_id, "files": files, "routes": routes, "note": note}


def clean_note(value: str) -> bool:
    return (0 < len(value.strip()) <= 600 and not any(ord(c) < 32 or ord(c) == 127 for c in value)
            and not any(re.search(pattern, value) for pattern in NOTE_BLOCKS))


def now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def load_results(output: Path, capture: dict) -> dict:
    checked_path(output)
    require(output != capture["root"] and capture["root"] not in output.parents
            and output not in capture["root"].parents, "Choose a results folder separate from the captured files.")
    require(not any((parent / ".git").exists() or (parent / ".git").is_symlink()
                    for parent in (output, *output.parents)), "Keep review results outside Git checkouts. Choose a separate local folder.")
    if not output.exists():
        output.mkdir(mode=0o700)
    require(output.is_dir(), "The results destination must be a folder.")
    require(all(entry.name in RESULT_NAMES or entry.name == ".DS_Store" for entry in output.iterdir()),
            "Use a new results folder or the folder from an earlier guided review.")
    for name in RESULT_NAMES:
        checked_path(output / name)
    path = output / "review-results.json"
    if not path.exists():
        require(not any((output / name).exists() for name in RESULT_NAMES), "An incomplete results folder already exists. Preserve it and choose a new folder.")
        return {"schema": 1, "capture": capture["id"], "method": "Human Review in Desktop Microsoft Office",
                "created_at": now(), "updated_at": now(), "cases": {case: [] for case in CASES}}
    results = decode_json(read_file(path, 256 * 1024))
    require(set(results) == {"schema", "capture", "method", "created_at", "updated_at", "cases"}
            and type(results["schema"]) is int and results["schema"] == 1
            and results["capture"] == capture["id"]
            and results["method"] == "Human Review in Desktop Microsoft Office",
            "Existing results belong to another capture or use an unsupported format. Choose a new results folder.")
    require(isinstance(results["cases"], dict) and set(results["cases"]) == set(CASES), "Invalid existing review results.")
    for key in ("created_at", "updated_at"):
        require(isinstance(results[key], str) and re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z", results[key]) is not None,
                "Invalid review timestamp.")
    for records in results["cases"].values():
        require(isinstance(records, list) and len(records) <= 100, "Invalid review history.")
        for record in records:
            require(isinstance(record, dict) and set(record) == {"result", "observation", "application_version", "reviewed_at"}
                    and record["result"] in OUTCOMES.values() and isinstance(record["observation"], str)
                    and clean_note(record["observation"]) and isinstance(record["application_version"], str)
                    and VERSION.fullmatch(record["application_version"]) is not None
                    and isinstance(record["reviewed_at"], str)
                    and re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z", record["reviewed_at"]) is not None,
                    "Existing observations contain invalid or sensitive-looking data. Preserve the folder and correct its report before resuming.")
    return results


def atomic_write(path: Path, data: bytes) -> None:
    checked_path(path)
    if path.exists():
        require(path.is_file(), "A results filename is not a regular file.")
    descriptor, temporary = tempfile.mkstemp(prefix=".review-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        checked_path(path)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def escape_markdown(value: str) -> str:
    return value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\\", "\\\\").replace("|", "\\|").replace("`", "\\`")


def save_results(output: Path, capture: dict, results: dict) -> None:
    results["updated_at"] = now()
    # JSON is authoritative; Markdown can be regenerated if writing it is interrupted.
    atomic_write(output / "review-results.json", (json.dumps(results, indent=2, ensure_ascii=False) + "\n").encode())
    rows = []
    for case, (application, _, _, _) in CASES.items():
        records = results["cases"][case]
        if records:
            latest = records[-1]
            rows.append(f"| {case} | {latest['result']} | {application} {latest['application_version']} | {escape_markdown(latest['observation'])} |")
        else:
            rows.append(f"| {case} | Not Reviewed | | |")
    passed = sum(bool(records) and records[-1]["result"] == "Pass" for records in results["cases"].values())
    body = (f"# Office Review Results\n\nLemulip Version: {capture['id']['version']} · Build {capture['id']['build']}\n\n"
            f"Source Commit: `{capture['id']['commit']}`\n\n"
            f"Manifest SHA-256: `{capture['id']['manifest_sha256']}`\n\n"
            f"User-Recorded Passes: **{passed} / {len(CASES)}**\n\n"
            "Outcomes below were entered by the reviewer after desktop Microsoft Office inspection. "
            "Opening files and validating checksums do not establish visual or behavioral acceptance. "
            "Blank cases remain Not Reviewed. Earlier observations are retained in review-results.json.\n\n"
            "| Case | Result | Application Version | Observation |\n| --- | --- | --- | --- |\n" + "\n".join(rows) + "\n\n")
    if capture["note"]:
        body += "## Capture Note\n\n" + capture["note"] + "\n\n"
    body += "These results apply only to the captured examples and recorded app versions. Reports stay local; nothing is uploaded automatically.\n"
    atomic_write(output / "REVIEW_RESULTS.md", body.encode())


def application_info(path: Path, identifier: str) -> dict | None:
    try:
        info = plistlib.loads(read_file(path / "Contents/Info.plist", 256 * 1024))
        if not isinstance(info, dict):
            return None
        version = info.get("CFBundleShortVersionString")
        if info.get("CFBundleIdentifier") == identifier and isinstance(version, str) and VERSION.fullmatch(version):
            return {"path": path, "version": version}
    except (OSError, ValueError, plistlib.InvalidFileException):
        pass
    return None


def installed_applications() -> dict[str, dict | None]:
    # NSWorkspace uses LaunchServices without sending Apple Events to Office or
    # asking for Accessibility/Automation access. Paths are never saved in reports.
    script = """ObjC.import('AppKit');
const ids = ['com.microsoft.Word', 'com.microsoft.Excel', 'com.microsoft.Powerpoint'];
const result = {};
ids.forEach(function(id) {
  try {
    const url = $.NSWorkspace.sharedWorkspace.URLForApplicationWithBundleIdentifier(id);
    result[id] = url && !url.isNil() ? ObjC.unwrap(url.path) : null;
  } catch (error) {
    result[id] = null;
  }
});
JSON.stringify(result);"""
    paths = {}
    try:
        process = subprocess.run(["/usr/bin/osascript", "-l", "JavaScript", "-e", script],
                                 stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                 text=True, timeout=15, check=False)
        if process.returncode == 0:
            parsed = json.loads(process.stdout)
            if isinstance(parsed, dict):
                paths = parsed
    except (OSError, ValueError, subprocess.TimeoutExpired):
        pass
    applications = {}
    for application, identifier in APPLICATIONS.items():
        candidates = []
        discovered = paths.get(identifier)
        if isinstance(discovered, str) and Path(discovered).is_absolute() and discovered.endswith(".app"):
            candidates.append(Path(discovered))
        candidates.extend([Path("/Applications") / f"Microsoft {application}.app",
                           Path.home() / "Applications" / f"Microsoft {application}.app"])
        applications[application] = None
        for candidate in candidates:
            information = application_info(candidate, identifier)
            if information:
                applications[application] = information
                break
    return applications


def working_copy(output: Path, capture: dict, case: str) -> Path:
    working = checked_path(output / "working")
    working.mkdir(mode=0o700, exist_ok=True)
    folder = checked_path(working / case)
    folder.mkdir(mode=0o700, exist_ok=True)
    attempt = Path(tempfile.mkdtemp(prefix="attempt-", dir=folder))
    for name in CASES[case][2]:
        data = capture["files"][f"cases/{case}/{name}"]
        destination = attempt / (case + "-" + name)
        with destination.open("xb") as stream:
            stream.write(data)
        destination.chmod(0o600)
    return attempt


def open_case(folder: Path, case: str, installed: dict) -> bool:
    application, _, names, _ = CASES[case]
    # Launch the exact verified installation, including when Office lives on an
    # external disk. A different default app must not supply the recorded version.
    current = application_info(installed["path"], APPLICATIONS[application])
    if current is None or current["version"] != installed["version"]:
        return False
    source = case + "-" + names[0]
    converted = case + "-" + names[-1]
    target_files = [str(folder / converted)]
    commands = []
    if Path(source).suffix in {".txt", ".csv", ".html", ".md"}:
        # Force a .txt extension so HTML is shown as source and CSV isn't inferred.
        plain = folder / (source + ".txt")
        with plain.open("xb") as stream:
            stream.write(read_file(folder / source))
        plain.chmod(0o600)
        commands.append(["/usr/bin/open", "-b", "com.apple.TextEdit", str(plain)])
    else:
        target_files.insert(0, str(folder / source))
    commands.append(["/usr/bin/open", "-a", str(installed["path"]), *target_files])
    for command in commands:
        try:
            completed = subprocess.run(command, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                       stderr=subprocess.DEVNULL, timeout=20, check=False)
            if completed.returncode != 0:
                return False
        except (OSError, subprocess.TimeoutExpired):
            return False
    return True


def review(capture: dict, output: Path, prompt=input) -> int:
    results = load_results(output, capture)
    save_results(output, capture, results)
    applications = installed_applications()
    print("Microsoft Office Review · Eight Captured Comparisons")
    print("Use the target desktop app. A repair prompt, missing content, wrong calculation, or clear layout defect is a Fail.")
    print("Observations must omit account details, personal/device names, local paths and credentials. Reports stay local.")
    for application, information in applications.items():
        print(f"{application}: {information['version'] if information else 'Not Available; Cases Remain Not Reviewed'}")
    if capture["note"]:
        print("Capture Note: " + capture["note"])
    for case, (application, _, _, instructions) in CASES.items():
        records = results["cases"][case]
        current = records[-1]["result"] if records else "Not Reviewed"
        print(f"\n{case} · {current}\n{instructions}")
        if not applications[application]:
            print(f"{application} is unavailable or its version could not be verified. Existing observations are preserved.")
            continue
        if records:
            choice = prompt("[Enter] Keep Recorded Result / R Review Again / Q Finish: ").strip().lower()
            if choice == "q":
                break
            if choice != "r":
                continue
        else:
            choice = prompt("[Enter] Open Working Copies / S Skip / Q Finish: ").strip().lower()
            if choice == "q":
                break
            if choice != "":
                continue
        folder = working_copy(output, capture, case)
        if not open_case(folder, case, applications[application]):
            print("The files could not be opened in the requested apps. No outcome was recorded; working copies are preserved.")
            continue
        print("Compare the opened copies. Original capture files are unchanged. A successful open alone does not mean Pass.")
        while True:
            skip = "S Skip Without Changing Saved Result" if records else "S Leave Not Reviewed"
            choice = prompt(f"After Inspection: P Pass / N Needs Review / F Fail / {skip} / Q Finish: ").strip().lower()
            if choice in {*OUTCOMES, "s", "q"}:
                break
        if choice == "q":
            break
        if choice == "s":
            print("No new observation was recorded.")
            continue
        while True:
            observation = prompt("Observed Result (include relevant page, cell, slide, spacing or font details): ").strip()
            if clean_note(observation):
                break
            print("Use 1–600 characters without private details, URLs, credentials, paths or control characters.")
        require(len(records) < 100, "This case has reached the review history limit. Preserve these results and start a new results folder.")
        records.append({"result": OUTCOMES[choice], "observation": observation,
                        "application_version": applications[application]["version"], "reviewed_at": now()})
        save_results(output, capture, results)
        print(f"Recorded {OUTCOMES[choice]}. Any earlier observations remain in the JSON history.")
        print("Close this case's working documents before continuing to the next comparison.")
    print("\nResults Saved: REVIEW_RESULTS.md and review-results.json in the selected results folder.")
    print("Only explicitly reviewed cases have outcomes. No report was uploaded.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path, help="Extracted, unchanged Lemulip-Office-Review folder")
    parser.add_argument("--output", type=Path, help="Separate new or existing local guided-review results folder")
    parser.add_argument("--verify-only", action="store_true", help="Verify capture structure and checksums without opening apps or writing results")
    options = parser.parse_args()
    try:
        capture = validate_capture(options.directory)
        print(f"Capture Verified: Lemulip {capture['id']['version']} · Build {capture['id']['build']} · {capture['id']['commit']}")
        if options.verify_only:
            print("Eight comparisons verified. Microsoft Office acceptance remains Not Reviewed by this check.")
            if capture["note"]:
                print("Capture Note: " + capture["note"])
            return 0
        require(platform.system() == "Darwin", "Run guided Office review on a Mac with desktop Microsoft Office. --verify-only works on other systems.")
        require(options.output is not None, "Choose a separate results folder using --output.")
        require(sys.stdin.isatty(), "Guided review needs an interactive Terminal to record human observations.")
        return review(capture, checked_path(options.output))
    except (OSError, ValueError, TypeError, KeyError, RecursionError, EOFError) as error:
        # Do not echo OS errors, arbitrary malformed data, or local filenames.
        message = str(error) if type(error) is ValueError and not isinstance(error, (json.JSONDecodeError, UnicodeError)) else "Could not read or validate the review files. Preserve existing results and check the selected folders."
        print("Office Review: " + message, file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("\nReview Stopped. Previously saved observations and original capture files are preserved.")
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
