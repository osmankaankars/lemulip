#!/usr/bin/env python3
"""Package generated Office examples for a separate, hands-on application review."""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import platform
import plistlib
import posixpath
import re
import stat
import struct
import sys
from urllib.parse import unquote, urlsplit
import xml.etree.ElementTree as ET
import zipfile
import zlib

import privacy_check

ROOT = Path(__file__).resolve().parent.parent
CASES = {
    "word-text": ("macOS TXT → DOCX", ["source.txt", "converted.docx"]),
    "word-rtf": ("macOS Basic RTF → DOCX", ["source.rtf", "converted.docx"]),
    "word-layout": ("LibreOffice DOCX → ODT → DOCX", ["source.docx", "intermediate.odt", "converted.docx"]),
    "word-html": ("LibreOffice HTML → DOCX", ["source.html", "converted.docx"]),
    "word-markdown": ("Pandoc Markdown → DOCX", ["source.md", "converted.docx"]),
    "excel-text": ("Built-In CSV → XLSX", ["source.csv", "converted.xlsx"]),
    "excel-formulas": ("LibreOffice XLSX → ODS → XLSX", ["source.xlsx", "intermediate.ods", "converted.xlsx"]),
    "powerpoint-layout": ("LibreOffice PPTX → ODP → PPTX", ["source.pptx", "intermediate.odp", "converted.pptx"]),
}
MAX_FILE_BYTES = 4 * 1024 * 1024
MAX_PACKAGE_BYTES = 16 * 1024 * 1024
PRIVATE_METADATA = {"creator", "initial-creator", "lastModifiedBy", "printed-by", "Company", "Manager"}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def read_file(path: Path) -> bytes:
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(descriptor, "rb") as stream:
        info = os.fstat(stream.fileno())
        require(stat.S_ISREG(info.st_mode) and 0 < info.st_size <= MAX_FILE_BYTES,
                "Review files must be small, nonempty regular files.")
        data = stream.read(MAX_FILE_BYTES + 1)
    require(0 < len(data) <= MAX_FILE_BYTES, "A review file exceeded its size limit.")
    return data


def check_text(data: bytes) -> None:
    require(not privacy_check.content_failures("office-review.txt", data),
            "A review document contains unexpected private or non-text content.")


def check_zip_metadata(extra: bytes) -> None:
    require(not any(re.search(pattern, extra) for pattern in privacy_check.RULES.values()),
            "Office ZIP metadata contains private content.")
    while extra:
        require(len(extra) >= 4, "Invalid Office ZIP metadata.")
        kind, size = struct.unpack_from("<HH", extra)
        payload, extra = extra[4:4 + size], extra[4 + size:]
        require(len(payload) == size, "Invalid Office ZIP metadata.")
        # The existing libarchive writer emits timestamps and numeric Unix IDs.
        if kind == 0x5455:
            require(bool(payload) and payload[0] & ~7 == 0 and
                    size in {5, 9, 13}, "Invalid ZIP timestamp metadata.")
        elif kind == 0x7875:
            require(size >= 5 and payload[0] == 1 and 1 <= payload[1] <= 8,
                    "Invalid ZIP owner metadata.")
            group_position = 2 + payload[1]
            require(group_position < size and 1 <= payload[group_position] <= 8
                    and group_position + 1 + payload[group_position] == size, "Invalid ZIP owner metadata.")
        else:
            raise ValueError("Unexpected Office ZIP metadata.")


def check_thumbnail(data: bytes) -> None:
    require(data.startswith(b"\x89PNG\r\n\x1a\n"), "Invalid Office thumbnail.")
    position, has_header, has_pixels = 8, False, False
    while position + 12 <= len(data):
        size, kind = struct.unpack_from(">I4s", data, position)
        end = position + size + 12
        require(end <= len(data) and kind in {b"IHDR", b"PLTE", b"tRNS", b"IDAT", b"IEND", b"sRGB", b"gAMA", b"cHRM", b"pHYs"},
                "Office thumbnails must not contain text, EXIF, or other private metadata.")
        payload = data[position + 8:end - 4]
        require(zlib.crc32(kind + payload) & 0xffffffff == struct.unpack_from(">I", data, end - 4)[0],
                "Invalid Office thumbnail checksum.")
        if not has_header:
            require(kind == b"IHDR" and size == 13, "Invalid Office thumbnail header.")
            width, height = struct.unpack_from(">II", payload)
            require(0 < width <= 2048 and 0 < height <= 2048, "Office thumbnail dimensions exceeded their limit.")
            has_header = True
        else:
            require(kind != b"IHDR", "Invalid Office thumbnail header.")
        has_pixels = has_pixels or kind == b"IDAT"
        if kind == b"IEND":
            require(size == 0 and end == len(data) and has_pixels, "Invalid or trailing Office thumbnail data.")
            return
        position = end
    raise ValueError("Incomplete Office thumbnail.")


def check_document(name: str, data: bytes) -> None:
    suffix = PurePosixPath(name).suffix
    if suffix in {".txt", ".rtf", ".csv", ".html", ".md"}:
        check_text(data)
        return
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        entries = archive.infolist()
        require(not archive.comment, "Office ZIP comments are not part of generated review files.")
        require(len(entries) <= 256 and sum(item.file_size for item in entries) <= MAX_PACKAGE_BYTES,
                "A generated Office document exceeded its package limits.")
        seen = set()
        for item in entries:
            path = PurePosixPath(item.filename)
            check_text(item.filename.encode("utf-8"))
            require(not item.comment, "Office ZIP comments are not part of generated review files.")
            check_zip_metadata(item.extra)
            require(not path.is_absolute() and ".." not in path.parts and "\\" not in item.filename
                    and not any(ord(c) < 32 or ord(c) == 127 for c in item.filename)
                    and item.filename not in seen and not stat.S_ISLNK(item.external_attr >> 16)
                    and not item.flag_bits & 1, "An Office document contains an unsafe package entry.")
            seen.add(item.filename)
            if item.is_dir():
                continue
            contents = archive.read(item)
            if item.filename.endswith((".xml", ".rels")) or item.filename == "manifest.rdf":
                check_text(contents)
                require(b"<!DOCTYPE" not in contents.upper() and b"<!ENTITY" not in contents.upper(),
                        "Office review XML must not contain entity declarations.")
                document = ET.fromstring(contents)
                for element in document.iter():
                    local = element.tag.rsplit("}", 1)[-1]
                    if local in PRIVATE_METADATA:
                        require("".join(element.itertext()).strip() in {"", "Lemulip"},
                                "Office author or organization metadata is not public.")
                    require(element.attrib.get("TargetMode", "").lower() != "external",
                            "Office review documents must not reference external resources.")
                    for attribute, value in element.attrib.items():
                        if attribute.rsplit("}", 1)[-1] == "href":
                            link = urlsplit(unquote(value))
                            target = posixpath.normpath(str(path.parent / link.path))
                            require(not link.scheme and not link.netloc and "\\" not in link.path
                                    and not link.path.startswith("/") and target != ".." and not target.startswith("../"),
                                    "Office review documents must not reference external resources.")
            elif item.filename == "mimetype":
                expected = {".odt": "text", ".ods": "spreadsheet", ".odp": "presentation"}.get(suffix)
                require(contents == ("application/vnd.oasis.opendocument." + str(expected)).encode(),
                        "Unexpected OpenDocument type.")
            else:
                # LibreOffice's preview contains only the generated fixture.
                require(item.filename == "Thumbnails/thumbnail.png",
                        "An Office review document contains an unexpected binary attachment.")
                check_thumbnail(contents)
        required = {".docx": "word/document.xml", ".xlsx": "xl/workbook.xml", ".pptx": "ppt/presentation.xml",
                    ".odt": "content.xml", ".ods": "content.xml", ".odp": "content.xml"}
        require(required.get(suffix) in seen, "A generated Office document is missing its main part.")


def collect_samples(directory: Path, source_commit: str) -> dict[str, bytes]:
    require(directory.is_absolute() and not directory.is_symlink() and directory.is_dir(),
            "Use the absolute generated review directory, not a link.")
    require({entry.name for entry in directory.iterdir()} == set(CASES) | {"source-commit.txt"},
            "The review directory must contain all expected Mac cases and no extra files.")
    require(read_file(directory / "source-commit.txt") == (source_commit + "\n").encode(),
            "The captured examples belong to a different source commit. Generate a new review directory.")
    files = {}
    for case, (_, names) in CASES.items():
        folder = directory / case
        require(not folder.is_symlink() and folder.is_dir()
                and {entry.name for entry in folder.iterdir()} == set(names),
                "A review case is incomplete or contains unexpected files.")
        for name in names:
            data = read_file(folder / name)
            check_document(name, data)
            files[f"cases/{case}/{name}"] = data
    require(sum(map(len, files.values())) <= MAX_PACKAGE_BYTES, "The review pack exceeded its size limit.")
    return files


def provenance() -> dict:
    require(platform.system() == "Darwin", "Generate the complete review pack on macOS, including native Word exports.")
    commit = privacy_check.git("rev-parse", "HEAD").decode().strip()
    require(re.fullmatch(r"[0-9a-f]{40}", commit) is not None, "Could not identify the source commit.")
    require(not privacy_check.git("status", "--porcelain", "--untracked-files=normal").strip(),
            "Commit or remove unreviewed source changes before generating a review pack.")
    version = plistlib.loads((ROOT / "Resources/Info.plist").read_bytes())
    os_version, architecture = platform.mac_ver()[0], platform.machine()
    require(re.fullmatch(r"[0-9.]+", os_version) is not None and architecture in {"arm64", "x86_64"},
            "Could not identify the Mac generation environment.")
    result = {"commit": commit, "version": version["CFBundleShortVersionString"],
              "build": version["CFBundleVersion"], "platform": "macOS", "os_version": os_version,
              "architecture": architecture, "source_worktree": "Clean"}
    run_id = os.environ.get("GITHUB_RUN_ID", "")
    if run_id and os.environ.get("GITHUB_REPOSITORY") == "osmankaankars/lemulip":
        require(re.fullmatch(r"[0-9]+", run_id) is not None, "Invalid workflow run identifier.")
        result["workflow_url"] = f"https://github.com/osmankaankars/lemulip/actions/runs/{run_id}"
    return result


def review_files(samples: dict[str, bytes], source: dict) -> dict[str, bytes]:
    files = dict(samples)
    files["README.md"] = (ROOT / "docs/OFFICE_REVIEW.md").read_bytes()
    cases = [{"id": case, "route": route, "target_application_review": "Not Reviewed",
              "files": [f"cases/{case}/{name}" for name in names]} for case, (route, names) in CASES.items()]
    manifest = {"schema": 1, "source": source, "target_application_review": "Not Reviewed",
                "scope": "Generated conversion examples. Check the matching workflow for automated results. Actual Microsoft Office review is still required.",
                "cases": cases, "files": {name: {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
                                          for name, data in sorted(samples.items())}}
    files["manifest.json"] = (json.dumps(manifest, indent=2, ensure_ascii=False) + "\n").encode()
    rows = "\n".join(f"| {case} | Not Reviewed | |" for case in CASES)
    files["REVIEW_RESULTS.md"] = (f"# Office Review Results\n\nSource Commit: `{source['commit']}`\n\n"
        "Word Version: \n\nExcel Version: \n\nPowerPoint Version: \n\nmacOS Version: \n\n"
        "Keep a copy of the original archive. Edit only this review copy. Use **Pass**, **Needs Review**, "
        "or **Fail** after inspecting each case in its target application. Leave unavailable applications "
        "as **Not Reviewed**. Record missing fonts, repair prompts, page counts, recalculated values, "
        "or slide differences without account names, device names, or personal paths.\n\n"
        f"| Case | Result | Observation |\n| --- | --- | --- |\n{rows}\n\n"
        "Reports stay local. Nothing is uploaded automatically.\n").encode()
    for name in ("README.md", "manifest.json", "REVIEW_RESULTS.md"):
        check_text(files[name])
    files["SHA256SUMS.txt"] = "".join(f"{hashlib.sha256(data).hexdigest()}  {name}\n"
                                        for name, data in sorted(files.items())).encode()
    return files


def write_archive(output: Path, files: dict[str, bytes]) -> None:
    # Exclusive creation prevents replacing an existing archive or following its link.
    with output.open("xb") as stream:
        try:
            with zipfile.ZipFile(stream, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
                for name, data in sorted(files.items()):
                    entry = zipfile.ZipInfo("Lemulip-Office-Review/" + name, (2026, 1, 1, 0, 0, 0))
                    entry.create_system = 3
                    entry.external_attr = (stat.S_IFREG | 0o644) << 16
                    entry.compress_type = zipfile.ZIP_DEFLATED
                    archive.writestr(entry, data)
        except BaseException:
            output.unlink()
            raise


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path, help="Absolute, complete capture directory from the Mac integration run")
    parser.add_argument("--output", type=Path, required=True, help="New ZIP filename outside the source checkout")
    options = parser.parse_args()
    try:
        source = provenance()
        files = review_files(collect_samples(options.directory, source["commit"]), source)
        write_archive(options.output, files)
    except (OSError, ValueError, zipfile.BadZipFile, ET.ParseError):
        print("Office review packaging stopped. Require clean Mac source, all expected generated cases, public metadata, and a new output filename.", file=sys.stderr)
        return 1
    print(f"Prepared {len(CASES)} Office review cases. Microsoft Word, Excel, and PowerPoint acceptance: Not Reviewed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
