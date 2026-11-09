#!/usr/bin/env python3
"""D25: verify and extract only the pinned D24 Intel trace, without executing it."""

from __future__ import annotations

from contextlib import contextmanager
import hashlib
import os
from pathlib import Path
import stat
import zipfile
import zlib


CHUNK_BYTES = 65536
MAX_ENTRIES = 16384
MAX_EXPANDED_BYTES = 256 * 1024 * 1024
MAX_DEPTH = 32
SELECTED_MEMBER = "recording.trace.zip"
SOURCE = {
    "runID": 42609635410,
    "attempt": 1,
    "artifactID": 13669502448,
    "sourceCommit": "73464e30f278203cbd129025f1db814b6c549b2b",
    "sourceTree": "0d0b8c476fb052cd7b3a5b7ac98d0c6977069bf5",
}
OUTER_IDENTITY = {
    "bytes": 12948336,
    "sha256": "5e80502e00e9da7cd857ab45b5324d637c4c09195dfe6e70b2d5569976e7b041",
    "entryCount": 95,
    "expandedBytes": 14067380,
}
INNER_IDENTITY = {
    "bytes": 13283084,
    "sha256": "d4a6e955f18b79d99530ec92690fad043422cb4897c0fb303f3066150cfb4bde",
    "entryCount": 5,
    "expandedBytes": 115835304,
}
INNER_ENTRIES = {
    "recording.trace/": {"kind": "directory", "bytes": 0, "crc32": 0},
    "recording.trace/Trace1.run/": {"kind": "directory", "bytes": 0, "crc32": 0},
    "recording.trace/Trace1.run/Attachments/": {"kind": "directory", "bytes": 0, "crc32": 0},
    "recording.trace/Trace1.run/Attachments/trace-data.atrc": {
        "kind": "file", "bytes": 115782056, "crc32": 3125956842,
        "sha256": "dd55ca66c46a4651df145287d2db8573e6dcf5f9387dcea73bec21a7a37719f0",
    },
    "recording.trace/Trace1.run/RunIssues.storedata": {
        "kind": "file", "bytes": 53248, "crc32": 1480474241,
        "sha256": "50e5b458ca4dcfa54f0186c41195fb90ee85ed733eb55e5f64017251182593e0",
    },
}


class EvidenceError(ValueError):
    pass


def _stable_identity(value):
    return (value.st_dev, value.st_ino, value.st_mode, value.st_size,
            value.st_mtime_ns, value.st_ctime_ns, value.st_nlink)


def _canonical_parent(path: Path) -> Path:
    path = Path(path)
    if not path.is_absolute() or path.name in ("", ".", ".."):
        raise EvidenceError("Require an absolute path with an ordinary final component")
    # Resolve temporary-directory aliases, never the final input/output component.
    return path.parent.resolve(strict=True) / path.name


@contextmanager
def _regular_reader(path: Path):
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode):
            raise EvidenceError("Input is not a regular file")
        with os.fdopen(descriptor, "rb", buffering=0, closefd=False) as source:
            yield source, before
        after = os.fstat(descriptor)
        if _stable_identity(before) != _stable_identity(after):
            raise EvidenceError("Input changed while it was being read")
        if _stable_identity(after) != _stable_identity(os.stat(path, follow_symlinks=False)):
            raise EvidenceError("Input path was replaced while it was being read")
    finally:
        os.close(descriptor)


def _hash_regular(source, *, expected_bytes=None, maximum=MAX_EXPANDED_BYTES):
    before = os.fstat(source.fileno())
    if not stat.S_ISREG(before.st_mode) or before.st_size > maximum:
        raise EvidenceError("File exceeds the bounded regular-input contract")
    if expected_bytes is not None and before.st_size != expected_bytes:
        raise EvidenceError("Input byte count differs from the pinned identity")
    source.seek(0)
    digest = hashlib.sha256()
    count = 0
    while True:
        chunk = source.read(min(CHUNK_BYTES, maximum - count + 1))
        if not chunk:
            break
        count += len(chunk)
        if count > maximum:
            raise EvidenceError("File grew beyond its byte bound")
        digest.update(chunk)
    if count != before.st_size or _stable_identity(before) != _stable_identity(os.fstat(source.fileno())):
        raise EvidenceError("File changed while hashing")
    return {"bytes": count, "sha256": digest.hexdigest()}


def _verify_identity(source, expected):
    actual = _hash_regular(source, expected_bytes=expected["bytes"], maximum=expected["bytes"])
    if actual["sha256"] != expected["sha256"]:
        raise EvidenceError("Input SHA-256 differs from the pinned identity")
    return actual


def _catalog(archive, *, maximum_entries=MAX_ENTRIES, maximum_bytes=MAX_EXPANDED_BYTES):
    infos = archive.infolist()
    if not infos or len(infos) > maximum_entries:
        raise EvidenceError("ZIP entry count is outside its bound")
    catalog = {}
    folded = set()
    expanded = 0
    for item in infos:
        name = item.filename
        plain = name[:-1] if name.endswith("/") else name
        parts = plain.split("/")
        if (item.orig_filename != name or not name or not name.isascii() or len(name) > 1024
                or "\\" in name or ":" in name or "\x00" in name
                or any(ord(character) < 32 for character in name)
                or any(part in ("", ".", "..") for part in parts)
                or len(parts) > MAX_DEPTH):
            raise EvidenceError("ZIP member has an unsafe relative path")
        key = plain.casefold()
        if key in folded:
            raise EvidenceError("ZIP member names are duplicate or case aliases")
        folded.add(key)
        if item.flag_bits & (1 | 64) or item.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED):
            raise EvidenceError("ZIP encryption or compression is unsupported")
        kind = "directory" if item.is_dir() else "file"
        unix_type = stat.S_IFMT(item.external_attr >> 16)
        expected_type = stat.S_IFDIR if kind == "directory" else stat.S_IFREG
        if unix_type not in (0, expected_type):
            raise EvidenceError("ZIP member is a link or special file")
        if item.external_attr & 0x10 and kind != "directory":
            raise EvidenceError("ZIP directory attributes disagree with its path")
        if item.file_size < 0 or item.compress_size < 0 or (kind == "directory" and item.file_size != 0):
            raise EvidenceError("ZIP member size is invalid")
        expanded += item.file_size
        if expanded > maximum_bytes:
            raise EvidenceError("ZIP expanded-byte bound exceeded")
        catalog[name] = {"info": item, "kind": kind, "bytes": item.file_size, "crc32": item.CRC}
    paths = {name.rstrip("/").casefold(): value["kind"] for name, value in catalog.items()}
    for name in paths:
        components = name.split("/")
        if any(paths.get("/".join(components[:index])) == "file" for index in range(1, len(components))):
            raise EvidenceError("ZIP file is also a parent directory")
    return catalog, expanded


def _verify_catalog_identity(catalog, expanded, expected):
    if len(catalog) != expected["entryCount"] or expanded != expected["expandedBytes"]:
        raise EvidenceError("ZIP inventory totals differ from the pinned identity")


def _copy_member(archive, item, descriptor, expected):
    digest = hashlib.sha256()
    count = 0
    try:
        with archive.open(item) as source:
            while True:
                chunk = source.read(min(CHUNK_BYTES, expected["bytes"] - count + 1))
                if not chunk:
                    break
                count += len(chunk)
                if count > expected["bytes"]:
                    raise EvidenceError("Expanded member exceeds its pinned size")
                digest.update(chunk)
                pending = memoryview(chunk)
                while pending:
                    written = os.write(descriptor, pending)
                    if written <= 0:
                        raise EvidenceError("Extracted-file write made no progress")
                    pending = pending[written:]
    except (zipfile.BadZipFile, EOFError, RuntimeError, zlib.error) as error:
        raise EvidenceError("ZIP member failed its format or CRC check") from error
    if count != expected["bytes"] or digest.hexdigest() != expected["sha256"]:
        raise EvidenceError("Extracted member differs from the pinned size or SHA-256")


@contextmanager
def _directory_at(parent_fd, parts):
    descriptor = os.dup(parent_fd)
    try:
        for part in parts:
            next_fd = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=descriptor)
            os.close(descriptor)
            descriptor = next_fd
        yield descriptor
    finally:
        os.close(descriptor)


def _extract_inner(inner_path, workspace_fd, expected_identity, expected_entries):
    with _regular_reader(inner_path) as (source, _):
        _verify_identity(source, expected_identity)
        with zipfile.ZipFile(source) as archive:
            catalog, expanded = _catalog(archive)
            _verify_catalog_identity(catalog, expanded, expected_identity)
            if set(catalog) != set(expected_entries):
                raise EvidenceError("Inner ZIP names differ from the pinned inventory")
            for name, expected in expected_entries.items():
                if any(catalog[name][key] != expected[key] for key in ("kind", "bytes", "crc32")):
                    raise EvidenceError("Inner ZIP metadata differs from the pinned inventory")
                parent = name.rstrip("/").rsplit("/", 1)
                if len(parent) == 2 and catalog.get(parent[0] + "/", {}).get("kind") != "directory":
                    raise EvidenceError("Inner ZIP parent directory is missing")
            directories = sorted((name for name, row in catalog.items() if row["kind"] == "directory"),
                                 key=lambda name: (name.count("/"), name))
            for name in directories:
                parts = name.rstrip("/").split("/")
                with _directory_at(workspace_fd, parts[:-1]) as parent:
                    os.mkdir(parts[-1], 0o700, dir_fd=parent)
                with archive.open(catalog[name]["info"]) as empty:
                    if empty.read(1):
                        raise EvidenceError("ZIP directory has payload bytes")
            for name, row in catalog.items():
                if row["kind"] != "file":
                    continue
                parts = name.split("/")
                with _directory_at(workspace_fd, parts[:-1]) as parent:
                    descriptor = os.open(parts[-1], os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                                         0o600, dir_fd=parent)
                    try:
                        _copy_member(archive, row["info"], descriptor, expected_entries[name])
                        os.fchmod(descriptor, 0o400)
                    finally:
                        os.close(descriptor)
            for name in reversed(directories):
                with _directory_at(workspace_fd, name.rstrip("/").split("/")) as descriptor:
                    os.fchmod(descriptor, 0o500)


def _prepare_input(artifact_zip, workspace, outer_identity, inner_identity, inner_entries, source_identity):
    """Internal seam for small synthetic fixtures; public prepare_input has fixed identities."""
    artifact_zip = _canonical_parent(artifact_zip)
    workspace = _canonical_parent(workspace)
    with _regular_reader(artifact_zip) as (source, _):
        _verify_identity(source, outer_identity)
        with zipfile.ZipFile(source) as outer:
            catalog, expanded = _catalog(outer)
            _verify_catalog_identity(catalog, expanded, outer_identity)
            selected = catalog.get(SELECTED_MEMBER)
            if selected is None or selected["kind"] != "file" or selected["bytes"] != inner_identity["bytes"]:
                raise EvidenceError("Pinned inner ZIP member is missing or has the wrong size")
            workspace.mkdir(mode=0o700, exist_ok=False)
            workspace_fd = os.open(workspace, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
            try:
                descriptor = os.open(SELECTED_MEMBER, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                                     0o600, dir_fd=workspace_fd)
                try:
                    _copy_member(outer, selected["info"], descriptor, inner_identity)
                    os.fchmod(descriptor, 0o400)
                finally:
                    os.close(descriptor)
                inner_path = workspace / SELECTED_MEMBER
                _extract_inner(inner_path, workspace_fd, inner_identity, inner_entries)
            finally:
                os.close(workspace_fd)
    trace = workspace / "recording.trace"
    return {
        "schema": 1, "source": dict(source_identity),
        "artifactPath": str(artifact_zip), "innerArchivePath": str(inner_path), "tracePath": str(trace),
        "outerArchive": dict(outer_identity, selectedMember=SELECTED_MEMBER),
        "innerArchive": dict(inner_identity), "manifest": snapshot_trace(trace),
        "archiveBytesUnchangedDuringPreparation": True,
        "readOnlyTraceModesApplied": True, "retainedCodeExecuted": False,
    }


def prepare_input(artifact_zip: Path, workspace: Path) -> dict:
    """Create a new private workspace containing only the exact retained D24 Intel trace.

    workspace must be absolute, absent, and have an existing parent. Its parent
    may be a canonical filesystem alias. No manifest override or native command
    is exposed. A failure can leave bounded partial files in this new workspace.
    """
    return _prepare_input(artifact_zip, workspace, OUTER_IDENTITY, INNER_IDENTITY, INNER_ENTRIES, SOURCE)


def snapshot_trace(trace: Path) -> dict:
    """Hash a bounded tree without following links; include paths, types and permission modes."""
    trace = _canonical_parent(trace)
    descriptor = os.open(trace, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    entries = []
    expanded = 0

    def walk(directory_fd, relative, depth):
        nonlocal expanded
        if depth > MAX_DEPTH:
            raise EvidenceError("Snapshot directory-depth bound exceeded")
        before = os.fstat(directory_fd)
        entries.append({"path": relative, "kind": "directory", "mode": stat.S_IMODE(before.st_mode)})
        if len(entries) > MAX_ENTRIES:
            raise EvidenceError("Snapshot entry-count bound exceeded")
        names = []
        with os.scandir(directory_fd) as directory:
            for entry in directory:
                names.append(entry.name)
                if len(entries) + len(names) > MAX_ENTRIES:
                    raise EvidenceError("Snapshot entry-count bound exceeded")
        for name in sorted(names):
            child = name if relative == "." else relative + "/" + name
            metadata = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
            if stat.S_ISDIR(metadata.st_mode):
                with _directory_at(directory_fd, [name]) as nested:
                    if _stable_identity(metadata) != _stable_identity(os.fstat(nested)):
                        raise EvidenceError("Snapshot directory changed before opening")
                    walk(nested, child, depth + 1)
            elif stat.S_ISREG(metadata.st_mode):
                if metadata.st_nlink != 1:
                    raise EvidenceError("Snapshot file is linked outside the extracted tree")
                file_fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory_fd)
                try:
                    if _stable_identity(metadata) != _stable_identity(os.fstat(file_fd)):
                        raise EvidenceError("Snapshot file changed before opening")
                    with os.fdopen(file_fd, "rb", buffering=0, closefd=False) as source:
                        identity = _hash_regular(source, maximum=MAX_EXPANDED_BYTES - expanded)
                    if _stable_identity(metadata) != _stable_identity(os.stat(name, dir_fd=directory_fd,
                                                                              follow_symlinks=False)):
                        raise EvidenceError("Snapshot file path changed while reading")
                finally:
                    os.close(file_fd)
                expanded += identity["bytes"]
                entries.append({"path": child, "kind": "file", "mode": stat.S_IMODE(metadata.st_mode), **identity})
                if len(entries) > MAX_ENTRIES:
                    raise EvidenceError("Snapshot entry-count bound exceeded")
            else:
                raise EvidenceError("Snapshot contains a symlink or special file")
        if _stable_identity(before) != _stable_identity(os.fstat(directory_fd)):
            raise EvidenceError("Snapshot directory changed while reading")

    try:
        root_stat = os.fstat(descriptor)
        walk(descriptor, ".", 0)
        if _stable_identity(root_stat) != _stable_identity(os.stat(trace, follow_symlinks=False)):
            raise EvidenceError("Snapshot root path changed while reading")
    finally:
        os.close(descriptor)
    entries.sort(key=lambda row: row["path"])
    return {"schema": 1, "entries": entries, "expandedBytes": expanded,
            "fileCount": sum(row["kind"] == "file" for row in entries),
            "directoryCount": sum(row["kind"] == "directory" for row in entries)}
