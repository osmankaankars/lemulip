#!/usr/bin/env python3
"""D23: read-only identity/frame review of the two immutable D22 archives.

This program never runs retained code, Apple tools, or a native executable.  The
command line accepts only the two archives fixed by the versioned trust file.
``validate_evidence`` is a lower-level semantic checker for coherent synthetic
negative tests; its result deliberately does not certify original archive bytes.
The original D22 calibration and its missing after-sample ps remain incomplete.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import math
import os
from pathlib import Path, PurePosixPath
import re
import stat
import struct
import sys
import uuid
import zipfile


FRAME = "lemulip_d22_wait_for_release"
IMAGE = "NativeSamplerCalibration"
EXECUTABLE = "build/" + IMAGE
DSYM = "build/NativeSamplerCalibration.dSYM/Contents/Resources/DWARF/" + IMAGE
TRUST_PATH = Path(__file__).resolve().parent / "fixtures/native_sampler_identity/D22-trust.json"
MAX_ARCHIVE_BYTES = 8 * 1024 * 1024
MAX_MEMBER_BYTES = 16 * 1024 * 1024
MAX_EXPANDED_BYTES = 64 * 1024 * 1024
MAX_MEMBERS = 1024
ORIGINAL_ERROR = "EvidenceError: Reported process path lacks one matching loaded binary-image entry"
BOUNDS = {
    "cutoffAfterParentBeforeSpawnSeconds": 14.0, "psTotalSeconds": 1.0,
    "reportBytes": 8388608, "requiredRemainingWindowSeconds": 8.0,
    "sampleNormalSeconds": 3.5, "sampleTotalSeconds": 4.0,
    "streamBytes": 2097152, "targetEOFGraceSeconds": 1.0,
    "targetForcedCleanupSeconds": 1.0, "triggerAfterTargetSpawnSeconds": 3.0,
}


class EvidenceError(ValueError):
    """The supplied bytes do not support the narrowly defined D23 witness."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise EvidenceError(message)


def identity(data: bytes) -> dict:
    return {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}


def integer(value, label: str, minimum: int = 0) -> int:
    require(type(value) is int and value >= minimum, label + ": expected integer")
    return value


def number(value, label: str, minimum: float = 0) -> float:
    require(type(value) in (int, float) and math.isfinite(value) and value >= minimum,
            label + ": expected finite number")
    return value


def json_bytes(data: bytes, label: str) -> dict:
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, label + ": duplicate JSON key")
            result[key] = value
        return result

    def constant(_):
        raise EvidenceError(label + ": non-finite JSON number")

    def finite_float(value):
        parsed = float(value)
        require(math.isfinite(parsed), label + ": non-finite JSON number")
        return parsed

    try:
        value = json.loads(data.decode("utf-8"), object_pairs_hook=pairs,
                           parse_constant=constant, parse_float=finite_float)
    except (UnicodeError, json.JSONDecodeError) as exc:
        raise EvidenceError(label + ": invalid UTF-8 JSON") from exc
    require(type(value) is dict, label + ": expected JSON object")
    return value


def _load_trust_snapshot() -> tuple[dict, dict]:
    try:
        raw = TRUST_PATH.read_bytes()
        trust = json_bytes(raw, "trust manifest")
    except OSError as exc:
        raise EvidenceError("Cannot read the versioned D22 trust manifest") from exc
    require(trust.get("schema") == 1, "trust manifest: unsupported schema")
    require(set(trust.get("architectures", {})) == {"arm64", "x86_64"},
            "trust manifest: expected both native architectures")
    return trust, identity(raw)


def load_trust() -> dict:
    return _load_trust_snapshot()[0]


def read_zip_bytes(data: bytes) -> dict[str, bytes]:
    """Read a bounded ZIP in memory, without extraction or executable loading."""
    require(len(data) <= MAX_ARCHIVE_BYTES, "archive: byte limit exceeded")
    files, seen, total = {}, set(), 0
    try:
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            entries = archive.infolist()
            require(0 < len(entries) <= MAX_MEMBERS, "archive: member count limit")
            for entry in entries:
                name = entry.filename
                path = PurePosixPath(name)
                require(name and path.parts and name == entry.orig_filename and "\\" not in name and "\0" not in name
                        and not path.is_absolute() and ".." not in path.parts
                        and ":" not in path.parts[0]
                        and path.as_posix() == name.rstrip("/"), "archive: unsafe member path")
                canonical = name.rstrip("/")
                require(canonical not in seen, "archive: duplicate member path")
                seen.add(canonical)
                mode = stat.S_IFMT(entry.external_attr >> 16)
                require(mode in (0, stat.S_IFREG, stat.S_IFDIR), "archive: nonregular member")
                require(not entry.flag_bits & 1, "archive: encrypted member")
                require(entry.compress_type in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED),
                        "archive: unsupported compression")
                require(0 <= entry.file_size <= MAX_MEMBER_BYTES,
                        "archive: member byte limit exceeded")
                total += entry.file_size
                require(total <= MAX_EXPANDED_BYTES, "archive: expanded byte limit exceeded")
                if entry.is_dir():
                    require(entry.file_size == 0 and mode in (0, stat.S_IFDIR),
                            "archive: invalid directory entry")
                    continue
                require(mode != stat.S_IFDIR, "archive: directory mode on file")
                with archive.open(entry) as stream:
                    raw = stream.read(MAX_MEMBER_BYTES + 1)
                    require(len(raw) == entry.file_size, "archive: member length mismatch")
                files[name] = raw  # ZipFile also verifies CRC while reading to EOF.
            for name in files:
                require(not any(parent.as_posix() in files for parent in PurePosixPath(name).parents
                                if parent.as_posix() != "."), "archive: file/directory collision")
    except (zipfile.BadZipFile, RuntimeError, NotImplementedError, OSError, EOFError) as exc:
        raise EvidenceError("archive: invalid ZIP or CRC") from exc
    return files


def _bounded_read(path: Path, expected: dict) -> bytes:
    size = integer(expected["bytes"], "archive expected length", 1)
    require(size <= MAX_ARCHIVE_BYTES, "archive: trusted size exceeds bound")
    try:
        descriptor = os.open(path, os.O_RDONLY | os.O_NONBLOCK | getattr(os, "O_NOFOLLOW", 0))
        with os.fdopen(descriptor, "rb") as stream:
            require(stat.S_ISREG(os.fstat(stream.fileno()).st_mode), "archive: expected regular file")
            raw = stream.read(size + 1)
    except OSError as exc:
        raise EvidenceError("Cannot read the supplied D22 archive") from exc
    require(identity(raw) == expected, "archive: original D22 length/SHA-256 mismatch")
    return raw


def _binding(files: dict[str, bytes], name: str, expected: dict, label: str) -> None:
    integer(expected["bytes"], label + " length")
    require(re.fullmatch(r"[0-9a-f]{64}", expected["sha256"]) is not None,
            label + ": invalid SHA-256")
    require(name in files and identity(files[name]) == {
        "bytes": expected["bytes"], "sha256": expected["sha256"]},
        label + ": length/SHA-256 mismatch")


def inspect_macho(data: bytes, architecture: str, *, debug: bool = False) -> dict:
    """Parse the retained thin little-endian Mach-O; do not dlopen or execute it."""
    require(len(data) >= 32 and data[:4] == b"\xcf\xfa\xed\xfe", "Mach-O: invalid 64-bit header")
    header = struct.unpack_from("<8I", data)
    require(header[1] == {"arm64": 0x0100000C, "x86_64": 0x01000007}[architecture],
            "Mach-O: foreign architecture")
    require(header[3] == (10 if debug else 2), "Mach-O: wrong file type")
    count, extent = header[4:6]
    require(count > 0 and count <= 4096 and 32 + extent <= len(data), "Mach-O: load command bounds")
    cursor, ids, segments, sections, symtabs = 32, [], [], [], []
    for _ in range(count):
        require(cursor + 8 <= 32 + extent, "Mach-O: truncated load command")
        kind, size = struct.unpack_from("<2I", data, cursor)
        require(size >= 8 and size % 8 == 0 and cursor + size <= 32 + extent,
                "Mach-O: invalid load command size")
        if kind == 0x1B:
            require(size == 24, "Mach-O: invalid UUID command")
            ids.append(str(uuid.UUID(bytes=data[cursor + 8:cursor + 24])).upper())
        elif kind == 0x19:
            require(size >= 72, "Mach-O: truncated segment")
            name = data[cursor + 8:cursor + 24].rstrip(b"\0")
            vmaddr, vmsize, fileoff, filesize, maxprot, initprot, nsects, _flags = struct.unpack_from(
                "<4Q4I", data, cursor + 24)
            require(size == 72 + nsects * 80, "Mach-O: section command bounds")
            require(debug or fileoff + filesize <= len(data), "Mach-O: segment file bounds")
            segments.append({"name": name, "vmaddr": vmaddr, "vmsize": vmsize,
                             "fileoff": fileoff, "filesize": filesize, "initprot": initprot})
            for i in range(nsects):
                offset = cursor + 72 + i * 80
                section_name, segment_name = struct.unpack_from("<16s16s", data, offset)
                address, section_size = struct.unpack_from("<2Q", data, offset + 32)
                require(segment_name.rstrip(b"\0") == name, "Mach-O: section/segment name mismatch")
                require(address >= vmaddr and address + section_size <= vmaddr + vmsize,
                        "Mach-O: section virtual bounds")
                sections.append({"name": section_name.rstrip(b"\0"),
                                 "segment": segment_name.rstrip(b"\0"),
                                 "address": address, "size": section_size,
                                 "executable": bool(initprot & 4)})
        elif kind == 0x2:
            require(size == 24, "Mach-O: invalid symbol table command")
            symtabs.append(struct.unpack_from("<4I", data, cursor + 8))
        cursor += size
    require(cursor == 32 + extent and len(ids) == 1, "Mach-O: ambiguous UUID/load commands")
    result = {"architecture": architecture, "cpuType": header[1], "fileType": header[3],
              "uuid": ids[0], **identity(data)}
    if debug:
        return result
    texts = [segment for segment in segments if segment["name"] == b"__TEXT"]
    require(len(texts) == 1 and texts[0]["fileoff"] == 0 and texts[0]["initprot"] & 4,
            "Mach-O: ambiguous or non-executable __TEXT")
    require(len(symtabs) == 1, "Mach-O: ambiguous symbol table")
    symoff, nsyms, stroff, strsize = symtabs[0]
    require(0 < nsyms <= 1000000 and symoff >= 32 + extent
            and symoff + 16 * nsyms <= len(data) and stroff >= symoff + 16 * nsyms
            and strsize > 0 and stroff + strsize <= len(data), "Mach-O: symbol/string table bounds")
    strings = data[stroff:stroff + strsize]
    selected = {"_" + FRAME: [], "__mh_execute_header": []}
    symbol_records = []
    for i in range(nsyms):
        string_index, symbol_type, section, _description, value = struct.unpack_from(
            "<IBBHQ", data, symoff + i * 16)
        require(string_index < strsize, "Mach-O: symbol string bounds")
        end = strings.find(b"\0", string_index)
        require(end >= 0, "Mach-O: unterminated symbol string")
        name = strings[string_index:end]
        symbol_records.append((name, symbol_type, section, value))
        if symbol_type & 0xE0:  # STABS are debugging records, not defined symbols.
            continue
        for expected in selected:
            if name == expected.encode("ascii"):
                require(symbol_type == 0x0F and 1 <= section <= len(sections),
                        "Mach-O: required symbol is not defined external N_SECT")
                selected[expected].append((value, sections[section - 1]))
    require(all(len(values) == 1 for values in selected.values()), "Mach-O: missing/duplicate required symbol")
    wait_value, wait_section = selected["_" + FRAME][0]
    header_value, header_section = selected["__mh_execute_header"][0]
    require(wait_section["segment"] == b"__TEXT" and wait_section["name"] == b"__text"
            and wait_section["executable"] and wait_section["address"] <= wait_value
            < wait_section["address"] + wait_section["size"], "Mach-O: wait symbol outside executable text")
    require(header_value == texts[0]["vmaddr"] and header_section["segment"] == b"__TEXT",
            "Mach-O: header symbol does not bind preferred load address")
    starts = [i for i, row in enumerate(symbol_records) if row[0] == ("_" + FRAME).encode("ascii")
              and row[1] == 0x24]
    require(len(starts) == 1 and starts[0] + 1 < len(symbol_records),
            "Mach-O: missing/duplicate wait function extent")
    start = symbol_records[starts[0]]
    end_record = symbol_records[starts[0] + 1]
    require(start[3] == wait_value and 1 <= start[2] <= len(sections)
            and sections[start[2] - 1] == wait_section and end_record[:3] == (b"", 0x24, 0)
            and end_record[3] > 0, "Mach-O: wait function extent binding")
    function_end = wait_value + end_record[3]
    following = [row[3] for row in symbol_records if not row[1] & 0xE0
                 and row[1] & 0x0E == 0x0E and row[2] == start[2] and row[3] > wait_value]
    require(following and function_end == min(following)
            and function_end <= wait_section["address"] + wait_section["size"],
            "Mach-O: wait function extent/next defined symbol mismatch")
    result.update(preferredTextVMAddress=header_value, waitSymbolAddress=wait_value,
                  waitFunctionEndExclusive=function_end, waitFunctionBytes=end_record[3],
                  waitSectionStart=wait_section["address"],
                  waitSectionEndExclusive=wait_section["address"] + wait_section["size"])
    return result


def _text(files: dict[str, bytes], name: str) -> str:
    try:
        return files[name].decode("utf-8")
    except UnicodeError as exc:
        raise EvidenceError(name + ": invalid UTF-8") from exc


def _nm(files: dict[str, bytes], binary: dict) -> None:
    text = _text(files, "build/helper-symbols.txt")
    for name, value in (("_" + FRAME, binary["waitSymbolAddress"]),
                        ("__mh_execute_header", binary["preferredTextVMAddress"])):
        rows = re.findall(r"^([0-9a-fA-F]+)\s+T " + re.escape(name) + r"\s*$", text, re.M)
        require(len(rows) == 1 and int(rows[0], 16) == value,
                "nm: missing/duplicate/mismatched retained symbol")


def inspect_report(text: str, architecture: str, binary: dict, ready: dict) -> dict:
    """Bind report fields and actual graph frames without resolving masked paths."""
    require("\0" not in text, "report: NUL in text")
    lines = text.splitlines()
    require(lines.count("Call graph:") == lines.count("Binary Images:") == 1,
            "report: ambiguous Call graph/Binary Images sections")
    graph_index, image_index = lines.index("Call graph:"), lines.index("Binary Images:")
    require(graph_index < image_index, "report: section order")
    header = "\n".join(lines[:graph_index])

    def field(name: str) -> str:
        rows = re.findall(r"^" + re.escape(name) + r":[ \t]*(.*?)[ \t]*$", header, re.M)
        require(len(rows) == 1, "report: missing/duplicate " + name)
        return rows[0]

    require(field("Process") == IMAGE + " [" + str(ready["pid"]) + "]", "report: foreign process PID/name")
    parent = re.fullmatch(r"[^\[\]\n]+ \[([0-9]+)\]", field("Parent Process"))
    require(parent is not None and int(parent[1]) == ready["ppid"], "report: foreign parent PID")
    acceptable = {"arm64": ("ARM64", "ARM64 (Native)", "ARM-64", "ARM-64 (Native)"),
                  "x86_64": ("X86-64", "X86-64 (Native)")}[architecture]
    code = field("Code Type")
    require(code in acceptable, "report: foreign/translated architecture")
    require(field("Platform") == "macOS" and field("Target Type") == "live task"
            and field("Analysis Tool") == "/usr/bin/sample" and field("Report Version") == "7",
            "report: unexpected report provenance")
    banner = (r"Analysis of sampling " + IMAGE + r" \(pid " + str(ready["pid"])
              + r"\) every 10 milliseconds")
    require(len(lines) > 0 and re.fullmatch(banner, lines[0]) is not None,
            "report: sampling PID/interval banner")
    path = field("Path")
    load_text = field("Load Address")
    require(re.fullmatch(r"0x[0-9a-fA-F]+", load_text) is not None, "report: invalid load address")
    load = int(load_text, 16)
    image_re = re.compile(r"[ \t]*(0x[0-9a-fA-F]+)[ \t]*-[ \t]*(0x[0-9a-fA-F]+)"
                          r"[ \t]+\+?([^\s]+)[ \t]+\([^)]*\)[ \t]+<([0-9a-fA-F-]{36})>"
                          r"[ \t]+(.+?)[ \t]*")
    images = []
    for line in lines[image_index + 1:]:
        if not line.strip():
            continue
        match = image_re.fullmatch(line)
        require(match is not None, "report: malformed/ambiguous binary image row")
        try:
            image_uuid = str(uuid.UUID(match[4])).upper()
        except ValueError as exc:
            raise EvidenceError("report: invalid image UUID") from exc
        start, end = int(match[1], 16), int(match[2], 16)
        require(start <= end, "report: invalid image range")
        images.append({"start": start, "end": end, "name": match[3],
                       "uuid": image_uuid, "path": match[5]})
    expected = [image for image in images if image["uuid"] == binary["uuid"]]
    require(len(expected) == 1, "report: missing/duplicate expected UUID image")
    image = expected[0]
    require(image["name"] == IMAGE and sum(row["name"] == IMAGE for row in images) == 1,
            "report: foreign/duplicate main image")
    require(load == image["start"], "report: main load address mismatch")
    require(path == "/Users/USER/*/NativeSamplerCalibration"
            and image["path"] == "/Users/*/NativeSamplerCalibration",
            "report: unexpected advisory masked path text")
    require(path != image["path"] and path != ready["executablePath"]
            and image["path"] != ready["executablePath"], "report: exact path status is inconsistent")
    boundary = next((i for i in range(graph_index + 1, image_index + 1)
                     if re.match(r"^[ \t]*(?:Total number in stack|Sort by top of stack|Binary Images:)",
                                 lines[i])), None)
    require(boundary is not None, "report: missing graph boundary")
    witnesses = []
    frame_re = re.compile(r"[ \t+|!:]*([0-9]+)[ \t]+" + FRAME + r"[ \t]+\(in " + IMAGE
                          + r"\)[ \t]+\+[ \t]+([0-9]+)[ \t]+\[(0x[0-9a-fA-F]+)\][ \t]*")
    slide = load - binary["preferredTextVMAddress"]
    require(slide >= 0, "report: negative image slide")
    for line in lines[graph_index + 1:boundary]:
        if re.search(r"\b" + FRAME + r"\b", line) is None:
            continue
        match = frame_re.fullmatch(line)
        require(match is not None, "report: malformed/foreign known frame")
        count, displacement, pc = int(match[1]), int(match[2]), int(match[3], 16)
        require(count > 0, "report: zero sample count")
        require(image["start"] <= pc <= image["end"], "report: frame PC outside image range")
        require(sum(row["start"] <= pc <= row["end"] for row in images) == 1,
                "report: ambiguous overlapping image ownership for sampled PC")
        require(pc == binary["waitSymbolAddress"] + slide + displacement,
                "report: symbol displacement does not reach sampled PC")
        require(binary["waitSectionStart"] <= pc - slide < binary["waitSectionEndExclusive"],
                "report: sampled PC outside executable text section")
        require(binary["waitSymbolAddress"] <= pc - slide < binary["waitFunctionEndExclusive"],
                "report: sampled PC outside retained wait function extent")
        witnesses.append({"sampleCount": count, "reportedSymbolOffset": displacement,
                          "pc": pc, "line": line})
    require(bool(witnesses), "report: no counted known frame in actual Call graph")
    return {"targetPID": ready["pid"], "parentPID": ready["ppid"], "codeType": code,
            "reportedHeaderPath": path, "reportedBinaryImagePath": image["path"],
            "displayedPathsAreAdvisoryMaskedText": True, "pathsWereGlobMatched": False,
            "canonicalReportPathReconstructed": False, "imageUUID": image["uuid"],
            "imageStart": image["start"], "imageEnd": image["end"], "mainLoadAddress": load,
            "preferredTextVMAddress": binary["preferredTextVMAddress"],
            "retainedSymbolAddress": binary["waitSymbolAddress"], "observedSlide": slide,
            "countedKnownFrameWitnesses": witnesses,
            "framePCsMatchImageRangeAndRetainedSymbol": True}


def _clock(clock: dict, label: str) -> tuple[int, int]:
    before = integer(clock["monotonicBeforeNS"], label + " before", 1)
    after = integer(clock["monotonicAfterNS"], label + " after", 1)
    integer(clock["wallTimeNS"], label + " wall", 1)
    require(before <= after, label + ": reversed clock bracket")
    return before, after


def _clock_order(clocks: list[tuple[str, dict]]) -> None:
    previous = None
    for label, clock in clocks:
        before, after = _clock(clock, label)
        if previous is not None:
            require(previous[0] <= before and previous[1] <= clock["wallTimeNS"],
                    "lifecycle: parent clock order violated at " + label)
        previous = (after, clock["wallTimeNS"])


def _native_clocks(receipt: dict, *, complete: bool) -> dict:
    numer = integer(receipt["machTimebaseNumer"], "native timebase numerator", 1)
    denom = integer(receipt["machTimebaseDenom"], "native timebase denominator", 1)
    names = ["nativeStartClock", "readinessClock"]
    if complete:
        names += ["releaseClock", "completionClock"]
    previous, converted = None, {}
    for name in names:
        clock = receipt[name]
        for field in ("machAbsoluteBefore", "machAbsoluteAfter", "machContinuousBefore",
                      "machContinuousAfter", "wallTimeUnixNS"):
            integer(clock[field], "native " + name + " " + field, 1)
        number(clock["systemUptime"], "native uptime")
        require(clock["machAbsoluteBefore"] <= clock["machAbsoluteAfter"]
                and clock["machContinuousBefore"] <= clock["machContinuousAfter"],
                "lifecycle: reversed native clock bracket")
        before = clock["machAbsoluteBefore"] * numer / denom
        after = clock["machAbsoluteAfter"] * numer / denom
        require(abs(clock["systemUptime"] * 1e9 - before) <= 1000,
                "lifecycle: native uptime/timebase mismatch")
        if previous is not None:
            require(previous["machAbsoluteAfter"] <= clock["machAbsoluteBefore"]
                    and previous["machContinuousAfter"] <= clock["machContinuousBefore"]
                    and previous["wallTimeUnixNS"] <= clock["wallTimeUnixNS"],
                    "lifecycle: native clock order violated")
        converted[name] = (before, after)
        previous = clock
    if complete:
        elapsed = (receipt["completionClock"]["machContinuousAfter"]
                   - receipt["nativeStartClock"]["machContinuousBefore"]) * numer / denom / 1e9
        require(0 < number(receipt["elapsedSeconds"], "native elapsed") < 15
                and abs(elapsed - receipt["elapsedSeconds"]) <= 1e-6,
                "lifecycle: native elapsed/clock mismatch")
    return converted


def _command(files: dict[str, bytes], name: str, command: dict, *, target: bool = False) -> None:
    require(json_bytes(files[name + ".json"], name) == command, "command: duplicated receipt mismatch")
    integer(command["pid"], name + " PID", 1)
    require(command["status"] == "completed" and command["exitCode"] == 0
            and command["stopReason"] is None and command["cleanupFailed"] is False
            and command["inheritedStreamsStillOpen"] is False,
            name + ": unsuccessful command/cleanup")
    for key in ("signals", "signalErrors", "streamErrors"):
        require(command[key] == [], name + ": signals/stream errors")
    if not target:
        require(command["cleanupFailureReasons"] == [], name + ": cleanup failure reasons")
    total = 0
    for stream in ("stdout", "stderr"):
        binding = command["files"][stream]
        require(binding["name"] == name + "." + stream + ".txt", name + ": foreign stream filename")
        _binding(files, binding["name"], binding, name + " " + stream)
        total += len(files[binding["name"]])
    require(integer(command["retainedBytes"], name + " retained") == total
            == integer(command["observedBytes"], name + " observed")
            <= integer(command["maximumCombinedBytes"], name + " stream limit", 1),
            name + ": stream byte accounting")
    elapsed = number(command["elapsedSeconds"], name + " elapsed")
    observed = number(command["exitObservedAfterSeconds"], name + " exit time")
    require(0 < observed <= elapsed, name + ": exit/elapsed order")
    if not target:
        normal, total_budget, limit = (3.5, 4.0, 2097152) if name == "sample" else (0.5, 1.0, 65536)
        require(command["normalOperationBudgetSeconds"] == normal
                and command["totalBudgetSeconds"] == total_budget
                and command["maximumCombinedBytes"] == limit and elapsed < normal,
                name + ": fixed command budget")
        _clock_order([(name + " spawn", command["clockAtSpawn"]),
                      (name + " completion", command["clockAtCompletion"])])
        duration_ns = (command["clockAtCompletion"]["monotonicAfterNS"]
                       - command["clockAtSpawn"]["monotonicBeforeNS"])
        require(elapsed * 1e9 + 1 >= duration_ns, name + ": elapsed/command clock duration mismatch")


def _identity_before(files: dict[str, bytes], report: dict, ready: dict) -> None:
    text = _text(files, "identity-before.stdout.txt")
    rows = [row for row in text.splitlines() if row.strip()]
    require(len(rows) == 1, "identity-before: ambiguous ps rows")
    fields = rows[0].split(None, 10)
    require(len(fields) == 11 and all(value.isdigit() for value in fields[:4]),
            "identity-before: malformed ps row")
    expected = [ready[key] for key in ("pid", "ppid", "pgid", "euid")]
    observed = report["beforeIdentity"]
    require(list(map(int, fields[:4])) == expected
            and [observed[key] for key in ("pid", "ppid", "pgid", "uid")] == expected,
            "identity-before: foreign PID/parent/group/eUID")
    require(observed["startTime"] == " ".join(fields[4:9]) and observed["state"] == fields[9]
            and fields[9][0] in "IRSTU" and observed["advisoryCommandAndArguments"] == fields[10]
            and observed["commandTextProvesImage"] is False, "identity-before: state/start/command binding")


def _groups(files: dict[str, bytes], name: str, command: dict, pgids: set[int]) -> list:
    rows = [row.split() for row in _text(files, name + ".stdout.txt").splitlines() if row.strip()]
    require(rows and all(len(row) == 3 and row[0].isdigit() and row[1].isdigit() for row in rows),
            name + ": malformed group inventory")
    require(len({int(row[0]) for row in rows}) == len(rows), name + ": duplicate process inventory")
    members = [{"pid": int(row[0]), "pgid": int(row[1]), "state": row[2]} for row in rows
               if int(row[1]) in pgids and int(row[0]) != command["pid"]]
    require(all(row["state"].startswith("Z") for row in members), name + ": live owned group member")
    return members


def _native_identity(files: dict[str, bytes], report: dict, provenance: dict, binary: dict,
                     ready: dict, complete: dict) -> dict:
    target, commands = report["target"], report["commands"]
    require(set(commands) == {"identity-before", "sample", "observer-groups", "target-groups"},
            "original D22: unexpected command set or after-sample ps")
    require(not any(name.startswith("identity-after.") for name in files)
            and all(key not in report for key in ("afterIdentity", "sampleQualification", "qualifiedSampleReport")),
            "original D22: unexpected post-sample identity/qualification")
    require(report["controlledSamplerCalibrationComplete"] is False
            and report["status"] == "calibration-incomplete" and report["errors"] == [ORIGINAL_ERROR],
            "original D22: original incomplete result changed")
    require(report["helperStarted"] is True and report["sampleInvocationCount"] == 1
            and report["bounds"] == BOUNDS, "original D22: helper/sample scope or bounds changed")
    for key in ("observerCleanupComplete", "targetCleanupComplete", "immutableInputsUnchanged",
                "readyReceiptUnchanged", "pidLeaseAcquired", "manualPreflightPassed"):
        require(report[key] is True, "lifecycle: missing " + key)
    for key in ("recordingExecuted", "nativeApplicationsLaunched", "nativeInputExecuted", "settingsChanged",
                "recorderImageOrStackQualified", "activationRouteCoverageEstablished",
                "ipcRequestChainEstablished", "releaseReady"):
        require(report[key] is False, "original D22: scope flag changed")
    require(report["C12"] == "HOLD", "original D22: candidate status changed")
    require(ready["schema"] == complete["schema"] == 1
            and ready["kind"] == "d22-sampler-calibration-ready"
            and complete["kind"] == "d22-sampler-calibration-complete", "native: receipt schema/kind")
    for receipt in (ready, complete):
        for key in ("pid", "ppid", "pgid", "euid"):
            integer(receipt[key], "native " + key, 1 if key != "euid" else 0)
        require(receipt["pid"] == target["pid"] == report["targetPID"]
                and receipt["ppid"] == report["targetParentPID"]
                and receipt["pgid"] == receipt["pid"] and receipt["pid"] != receipt["ppid"]
                and receipt["euid"] == report["beforeIdentity"]["uid"], "native: PID/parent/group/eUID mismatch")
        require(receipt["executablePath"] == provenance["helper"]["path"]
                and receipt["executableSHA256"] == binary["sha256"]
                and receipt["machOUUID"] == binary["uuid"]
                and receipt["architecture"] == provenance["architecture"], "native: executable/UUID/architecture mismatch")
        for key in ("nonce", "sourceSHA256", "experimentCommit", "experimentTree"):
            require(receipt[key] == report[key], "native: instance/source identity mismatch")
        require(str(uuid.UUID(receipt["nonce"])).upper() == receipt["nonce"]
                and str(uuid.UUID(receipt["bootUUID"])).upper() == receipt["bootUUID"], "native: invalid nonce/boot UUID")
        require(receipt["expectedFrame"] == FRAME and receipt["identityValidated"] is True
                and receipt["safetyTimeoutSeconds"] == 15 and receipt["receivedInputBytes"] == 0,
                "native: frame/identity/safety receipt")
        require(receipt["translationProbe"] in ({"returnCode": 0, "errno": 0, "value": 0},
                                                {"returnCode": -1, "errno": 2, "value": None}),
                "native: translated architecture")
        for flag in ("nativeInputExecuted", "settingsChanged", "applicationLaunchRequested", "recordingRequested"):
            require(receipt[flag] is False, "native: side-effect scope flag")
    for key in ("bootUUID", "machTimebaseNumer", "machTimebaseDenom", "nativeStartClock", "readinessClock",
                "nonce", "pid", "ppid", "pgid", "euid", "translationProbe"):
        require(ready[key] == complete[key], "native: mixed ready/completion instance or clocks")
    require(ready["expectedFrameEntered"] is True, "native: known frame was not entered")
    require(complete["readyReceiptSHA256"] == identity(files["target-ready.json"])["sha256"]
            and complete["readyReceiptBytes"] == len(files["target-ready.json"]), "native: ready receipt hash binding")
    require(complete["reason"] == "stdin-eof" and complete["cooperativeEOFObserved"] is True
            and complete["safetyTimeoutExpired"] is False and complete["finalIdentityMatches"] is True
            and complete["exitCode"] == 0, "native: completion was not normal cooperative EOF")
    for key in ("stdinEOFRequested", "stdinEOFDelivered", "stdinClosed", "pidLeaseReleased"):
        require(target[key] is True, "lifecycle: missing " + key)
    require(target["stdinBytesSent"] == 0 and target["forcedCleanupUsed"] is False,
            "lifecycle: target input or forced cleanup")
    require(target["argv"] == [provenance["helper"]["path"], "--ready",
        str(PurePosixPath(provenance["helper"]["path"]).parent.parent / "target-ready.json"),
        "--completion", str(PurePosixPath(provenance["helper"]["path"]).parent.parent / "target-completion.json"),
        "--nonce", ready["nonce"], "--expected-executable", ready["executablePath"],
        "--expected-sha256", ready["executableSHA256"], "--expected-uuid", ready["machOUUID"],
        "--expected-architecture", ready["architecture"], "--source-sha256", ready["sourceSHA256"],
        "--experiment-commit", ready["experimentCommit"], "--experiment-tree", ready["experimentTree"]],
        "target: native invocation identity mismatch")
    _command(files, "target", target, target=True)
    for name, command in commands.items():
        _command(files, name, command)
    pids = [target["pid"], ready["ppid"], *[command["pid"] for command in commands.values()]]
    require(len(pids) == len(set(pids)), "lifecycle: ambiguous/reused owned PID")
    require(commands["identity-before"]["argv"] == ["/bin/ps", "-ww", "-p", str(ready["pid"]), "-o",
        "pid=,ppid=,pgid=,uid=,lstart=,stat=,comm=,args="], "identity-before: command mismatch")
    report_path = str(PurePosixPath(provenance["helper"]["path"]).parent.parent.parent / "work/controlled-sample.txt")
    require(commands["sample"]["argv"] == ["/usr/bin/sample", str(ready["pid"]), "1", "10", "-mayDie", "-file", report_path],
            "sample: fixed invocation mismatch")
    for name in ("observer-groups", "target-groups"):
        require(commands[name]["argv"] == ["/bin/ps", "-A", "-o", "pid=,pgid=,stat="], name + ": command mismatch")
    _identity_before(files, report, ready)
    observers = {commands[name]["pid"] for name in ("identity-before", "sample", "observer-groups")}
    observer_members = _groups(files, "observer-groups", commands["observer-groups"], observers)
    target_members = _groups(files, "target-groups", commands["target-groups"], {target["pid"], commands["target-groups"]["pid"]})
    for key, members in (("observerGroupProof", observer_members), ("targetGroupProof", target_members)):
        require(report[key]["members"] == members
                and report[key]["status"] == "no-live-owned-group-members-observed", key + ": group proof mismatch")
    clock_sequence = [("target before spawn", target["clockBeforeSpawn"]),
                      ("PID lease", report["pidLeaseClock"])]
    for name in ("identity-before", "sample", "observer-groups"):
        clock_sequence += [(name + " spawn", commands[name]["clockAtSpawn"]),
                           (name + " completion", commands[name]["clockAtCompletion"])]
    clock_sequence += [("observer proof", report["observerGroupProof"]["clock"]),
                       ("EOF", target["stdinEOFClock"]), ("target cleanup", target["clockAfterCleanup"]),
                       ("final inventory spawn", commands["target-groups"]["clockAtSpawn"]),
                       ("final inventory completion", commands["target-groups"]["clockAtCompletion"]),
                       ("target proof", report["targetGroupProof"]["clock"])]
    _clock_order(clock_sequence)
    _native_clocks(ready, complete=False)
    native = _native_clocks(complete, complete=True)
    require(target["clockBeforeSpawn"]["monotonicAfterNS"] <= native["nativeStartClock"][0]
            and native["readinessClock"][1] <= commands["sample"]["clockAtSpawn"]["monotonicBeforeNS"]
            and commands["sample"]["clockAtCompletion"]["monotonicAfterNS"] <= target["stdinEOFClock"]["monotonicBeforeNS"]
            and target["stdinEOFClock"]["monotonicAfterNS"] <= native["releaseClock"][0]
            and native["completionClock"][1] <= target["clockAfterCleanup"]["monotonicBeforeNS"],
            "lifecycle: native/parent readiness-sample-EOF-completion clock order")
    require(ready["readinessClock"]["wallTimeUnixNS"] < commands["sample"]["clockAtSpawn"]["wallTimeNS"]
            < commands["sample"]["clockAtCompletion"]["wallTimeNS"] < complete["releaseClock"]["wallTimeUnixNS"]
            <= complete["completionClock"]["wallTimeUnixNS"], "lifecycle: native/sample wall clock order")
    for key in ("triggerMonotonic", "targetMonotonicStart", "cutoffMonotonic", "parentBeforeSpawnMonotonic"):
        number(report[key], "lifecycle " + key)
    require(report["parentBeforeSpawnMonotonic"] <= report["targetMonotonicStart"]
            <= target["clockBeforeSpawn"]["monotonicBeforeNS"] / 1e9,
            "lifecycle: target/parent spawn clock anchor mismatch")
    exit_ns = (report["targetMonotonicStart"] + target["exitObservedAfterSeconds"]) * 1e9
    require(native["completionClock"][1] <= exit_ns + 1
            and exit_ns <= target["clockAfterCleanup"]["monotonicAfterNS"] + 1,
            "lifecycle: target exit/cleanup clock order")
    require(abs(report["triggerMonotonic"] - report["targetMonotonicStart"] - 3) < 1e-6
            and abs(report["cutoffMonotonic"] - report["parentBeforeSpawnMonotonic"] - 14) < 1e-6
            and commands["identity-before"]["clockAtSpawn"]["monotonicBeforeNS"] / 1e9 >= report["triggerMonotonic"]
            and report["cutoffMonotonic"] - commands["identity-before"]["clockAtSpawn"]["monotonicAfterNS"] / 1e9 >= 8
            and commands["sample"]["clockAtCompletion"]["monotonicAfterNS"] / 1e9 < report["cutoffMonotonic"],
            "lifecycle: fixed observation/cutoff window")
    return {"pid": ready["pid"], "parentPID": ready["ppid"], "pgid": ready["pgid"], "euid": ready["euid"],
            "nonce": ready["nonce"], "bootUUID": ready["bootUUID"], "sampleInvocations": 1,
            "sampleElapsedSeconds": commands["sample"]["elapsedSeconds"], "sampleExitCode": 0,
            "nativeElapsedSeconds": complete["elapsedSeconds"], "cooperativeEOFCompleted": True,
            "forcedTargetCleanup": False, "finalObserverMembers": observer_members,
            "finalTargetMembers": target_members, "receiptAndStreamBindingsVerified": True,
            "nativeClockOrderAndElapsedVerified": True, "parentLeaseObservationEOFOrderVerified": True,
            "nativeParentClockOrderVerified": True, "beforePSIdentityVerified": True,
            "finalPSIsCleanupInventoryOnly": True}


def _inputs(files: dict[str, bytes]) -> int:
    actual = {}
    for name, raw in files.items():
        if not (name.startswith("build/") or name.startswith("sources/")):
            continue
        actual[name] = {"kind": "file", **identity(raw)}
        for parent in PurePosixPath(name).parents:
            if parent.as_posix() not in (".", "build", "sources"):
                actual[parent.as_posix()] = {"kind": "directory"}
    before = json_bytes(files["inputs-before.json"], "inputs-before")
    after = json_bytes(files["inputs-after.json"], "inputs-after")
    require(before == after == actual, "inputs: changed/missing before-after build/source bytes")
    require(json_bytes(files["input-preservation.json"], "input-preservation") == {
        "schema": 1, "inputsUnchanged": True, "beforeEntries": len(actual), "afterEntries": len(actual)},
        "inputs: preservation receipt mismatch")
    return len(actual)


def _validate_evidence(files: dict[str, bytes], architecture: str, trust: dict) -> dict:
    require(architecture in ("arm64", "x86_64"), "Unsupported native architecture")
    expected = trust["architectures"][architecture]
    require(set(files) == set(expected["members"]), "members: missing/unexpected archive files")
    for name, binding in expected["members"].items():
        _binding(files, name, binding, "member " + name)
    record = lambda name: json_bytes(files[name], name)
    provenance, report = record("build-provenance.json"), record("sampler-calibration.json")
    ready, complete = record("target-ready.json"), record("target-completion.json")
    require(provenance["schema"] == report["schema"] == 1
            and provenance["diagnostic"] == report["diagnostic"] == "D22-native-sampler-calibration",
            "provenance: unsupported schema/diagnostic")
    for key in ("experimentCommit", "experimentTree"):
        require(provenance[key] == report[key] == trust[key], "provenance: executed source commit/tree mismatch")
    require(_text(files, "build/experiment-commit.txt").strip() == trust["experimentCommit"]
            and _text(files, "build/experiment-tree.txt").strip() == trust["experimentTree"],
            "provenance: retained Git identity mismatch")
    require(provenance["frozenCandidate"] == trust["frozenCandidate"]
            and provenance["dependencyBase"] == trust["dependencyBase"], "provenance: candidate/dependency mismatch")
    require(provenance["architecture"] == report["architecture"] == architecture,
            "provenance: foreign architecture")
    require(provenance["expectedFrame"] == FRAME and provenance["diagnosticOnly"] is True
            and provenance["C12"] == "HOLD", "provenance: diagnostic/frame scope mismatch")
    for key in ("releaseReady", "recorderInvoked", "nativeInputExecuted", "settingsChanged",
                "activationRouteCoverageEstablished"):
        require(provenance[key] is False, "provenance: side-effect scope flag")
    require(set(provenance["retainedDiagnosticSourcesSHA256"]) == set(trust["sources"])
            == {PurePosixPath(name).name for name in files if name.startswith("sources/")},
            "sources: missing/extra retained source")
    source_bindings = {}
    for name, binding in trust["sources"].items():
        raw = files["sources/" + name]
        _binding(files, "sources/" + name, binding, "source " + name)
        git_blob = hashlib.sha1(b"blob " + str(len(raw)).encode("ascii") + b"\0" + raw).hexdigest()
        require(git_blob == binding["gitBlob"]
                and identity(raw)["sha256"] == provenance["retainedDiagnosticSourcesSHA256"][name],
                "sources: executed Git blob/hash mismatch")
        source_bindings[name] = {"path": binding["path"], "gitBlob": git_blob, **identity(raw)}
    source_hash = identity(files["sources/NativeSamplerCalibration.c"])["sha256"]
    require(provenance["sourceSHA256"] == report["sourceSHA256"] == source_hash,
            "sources: native source SHA mismatch")
    binary = inspect_macho(files[EXECUTABLE], architecture)
    debug = inspect_macho(files[DSYM], architecture, debug=True)
    helper = provenance["helper"]
    require(binary["uuid"] == debug["uuid"] == helper["uuid"]
            and binary["sha256"] == helper["sha256"]
            and helper["architecture"] == architecture and helper["architectures"] == [architecture]
            and report["helper"] == helper, "binary: executable/dSYM/provenance identity mismatch")
    require(source_hash.encode("ascii") in files[EXECUTABLE], "binary: compiled source SHA marker missing")
    require(provenance["translationProbe"] == ready["translationProbe"], "provenance: translation probe mismatch")
    _nm(files, binary)
    for name in ("helper-uuid.txt", "helper-dsym-uuid.txt"):
        rows = _text(files, "build/" + name).splitlines()
        match = re.fullmatch(r"UUID: ([0-9A-Fa-f-]{36}) \((arm64|x86_64)\) .+", rows[0]) if len(rows) == 1 else None
        require(match is not None and match[1].upper() == binary["uuid"] and match[2] == architecture,
                "binary: retained UUID tool output mismatch")
    require(_text(files, "build/helper-uuid.txt") == helper["uuidOutput"], "binary: UUID output binding")
    _binding(files, "build-provenance.json", report["provenance"], "provenance")
    for key, name in (("readyReceipt", "target-ready.json"), ("completionReceipt", "target-completion.json"),
                      ("sampleReport", "controlled-sample.txt")):
        require(report[key]["name"] == name, key + ": foreign filename")
        _binding(files, name, report[key], key)
    input_count = _inputs(files)
    native = _native_identity(files, report, provenance, binary, ready, complete)
    witness = inspect_report(_text(files, "controlled-sample.txt"), architecture, binary, ready)
    return {"schema": 1, "review": "D23-native-sampler-identity-witness",
            "evidenceRole": "semantic-validation-only", "archiveBytesVerified": False,
            "architecture": architecture, "runID": trust["runID"], "artifactID": expected["artifactID"],
            "status": "consistent-counted-known-frame-witness", "identityFrameWitnessConsistent": True,
            "originalD22Complete": False, "exactReportPathMatched": False, "postSamplePSAvailable": False,
            "originalD22Status": report["status"], "originalD22Errors": report["errors"],
            "recorderOrActivationCoverageEstablished": False, "releaseReady": False, "C12": "HOLD",
            "archivedCodeOrBinariesExecuted": False, "executedCommit": trust["experimentCommit"],
            "executedTree": trust["experimentTree"], "memberCount": len(files),
            "memberByteBindingsVerified": True, "immutableInputEntries": input_count,
            "immutableInputBytesVerified": True, "retainedSources": source_bindings,
            "bindings": {name: identity(files[name]) for name in (
                "build-provenance.json", "sampler-calibration.json", "target-ready.json",
                "target-completion.json", "controlled-sample.txt")},
            "binary": binary, "debugSymbols": debug, "nativeLifecycle": native, "reportWitness": witness}


def validate_evidence(files: dict[str, bytes], architecture: str, trust: dict) -> dict:
    """Check byte bindings and semantics; synthetic fixtures are never archives."""
    try:
        return _validate_evidence(files, architecture, trust)
    except EvidenceError:
        raise
    except (KeyError, TypeError, ValueError, IndexError, struct.error, OverflowError) as exc:
        raise EvidenceError("Evidence schema is missing, malformed, or ambiguous (" + type(exc).__name__ + ")") from exc


def verify_archive(path: str | Path, architecture: str) -> dict:
    """Verify one original D22 ZIP using only the fixed versioned trust file."""
    trust, trust_identity = _load_trust_snapshot()
    require(architecture in trust["architectures"], "Unsupported native architecture")
    expected = trust["architectures"][architecture]
    raw = _bounded_read(Path(path), expected["archive"])
    result = validate_evidence(read_zip_bytes(raw), architecture, trust)
    result.update(evidenceRole="derived-review-of-immutable-D22-archive", archiveBytesVerified=True,
                  archive=identity(raw), trustManifest=trust_identity)
    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arm64", required=True, type=Path, help="Original D22 ARM64 archive")
    parser.add_argument("--x86-64", required=True, type=Path, help="Original D22 Intel archive")
    parser.add_argument("--output", type=Path, help="Create a new JSON file; default is stdout")
    args = parser.parse_args(argv)
    try:
        results = [verify_archive(args.arm64, "arm64"), verify_archive(args.x86_64, "x86_64")]
        output = {"schema": 1, "review": "D23-native-sampler-identity-witness",
                  "status": "both-immutable-archives-consistent",
                  "originalD22Complete": False, "exactReportPathMatched": False,
                  "postSamplePSAvailable": False, "newNativeObservationExecuted": False,
                  "recorderOrActivationCoverageEstablished": False, "releaseReady": False,
                  "C12": "HOLD", "results": results}
        rendered = json.dumps(output, indent=2, sort_keys=True, allow_nan=False) + "\n"
        if args.output is None:
            sys.stdout.write(rendered)
        else:
            with args.output.open("x", encoding="utf-8") as stream:
                stream.write(rendered)
    except (EvidenceError, OSError) as exc:
        message = str(exc) if isinstance(exc, EvidenceError) else "Cannot create the requested new output file"
        print("D23 review rejected: " + message, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
