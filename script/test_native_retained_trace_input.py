#!/usr/bin/env python3
"""Synthetic archive and preservation checks for the pinned D25 input reader."""

import hashlib
import io
import os
from pathlib import Path
import stat
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import warnings
import zipfile

import native_retained_trace_input as subject


def zip_bytes(entries, compression=zipfile.ZIP_STORED):
    output = io.BytesIO()
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", UserWarning)
        with zipfile.ZipFile(output, "w", compression=compression) as archive:
            for name, payload, mode in entries:
                item = zipfile.ZipInfo(name)
                item.create_system = 3
                item.external_attr = mode << 16
                if name.endswith("/"):
                    item.external_attr |= 0x10
                item.compress_type = compression
                archive.writestr(item, payload)
    return output.getvalue()


def zip_identity(raw):
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        return {"bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest(),
                "entryCount": len(archive.infolist()),
                "expandedBytes": sum(item.file_size for item in archive.infolist())}


class RetainedInputTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="d25-input-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.counter = 0

    def fixture(self):
        files = [
            ("recording.trace/", b"", stat.S_IFDIR | 0o755),
            ("recording.trace/Trace1.run/", b"", stat.S_IFDIR | 0o755),
            ("recording.trace/Trace1.run/Attachments/", b"", stat.S_IFDIR | 0o755),
            ("recording.trace/Trace1.run/Attachments/trace-data.atrc", b"synthetic trace bytes", stat.S_IFREG | 0o600),
            ("recording.trace/Trace1.run/RunIssues.storedata", b"synthetic issue bytes", stat.S_IFREG | 0o600),
        ]
        inner = zip_bytes(files)
        entries = {}
        with zipfile.ZipFile(io.BytesIO(inner)) as archive:
            for name, payload, _ in files:
                item = archive.getinfo(name)
                entries[name] = {"kind": "directory" if name.endswith("/") else "file",
                                 "bytes": len(payload), "crc32": item.CRC}
                if not name.endswith("/"):
                    entries[name]["sha256"] = hashlib.sha256(payload).hexdigest()
        outer = zip_bytes([(subject.SELECTED_MEMBER, inner, stat.S_IFREG | 0o600),
                           ("sources/do-not-execute.py", b"not executable evidence", stat.S_IFREG | 0o700)])
        self.counter += 1
        path = self.root / f"synthetic-{self.counter}.zip"
        path.write_bytes(outer)
        return path, zip_identity(outer), zip_identity(inner), entries

    def prepare(self, fixture=None, workspace=None):
        path, outer, inner, entries = fixture or self.fixture()
        workspace = workspace or self.root / (path.stem + "-work")
        return subject._prepare_input(path, workspace, outer, inner, entries,
                                      {"evidenceKind": "synthetic-portable-test"})

    def catalog(self, entries, **kwargs):
        with zipfile.ZipFile(io.BytesIO(zip_bytes(entries))) as archive:
            return subject._catalog(archive, **kwargs)

    def test_selected_trace_only_is_extracted_read_only_and_source_is_preserved(self):
        fixture = self.fixture()
        original = fixture[0].read_bytes()
        result = self.prepare(fixture)
        trace = Path(result["tracePath"])
        self.assertEqual(original, fixture[0].read_bytes())
        self.assertEqual(result["manifest"], subject.snapshot_trace(trace))
        self.assertEqual(2, result["manifest"]["fileCount"])
        self.assertEqual(3, result["manifest"]["directoryCount"])
        self.assertEqual(b"synthetic trace bytes", (trace / "Trace1.run/Attachments/trace-data.atrc").read_bytes())
        self.assertFalse((trace.parent / "sources").exists())
        self.assertEqual({"recording.trace", "recording.trace.zip"}, {p.name for p in trace.parent.iterdir()})
        for entry in result["manifest"]["entries"]:
            self.assertEqual(0o400 if entry["kind"] == "file" else 0o500, entry["mode"])
        self.assertEqual(0o400, stat.S_IMODE(Path(result["innerArchivePath"]).stat().st_mode))
        self.assertFalse(result["retainedCodeExecuted"])

    def test_public_entry_point_rejects_synthetic_identity_before_workspace_creation(self):
        fixture = self.fixture()
        workspace = self.root / "public-work"
        with self.assertRaisesRegex(subject.EvidenceError, "pinned identity"):
            subject.prepare_input(fixture[0], workspace)
        self.assertFalse(workspace.exists())

    def test_outer_digest_mismatch_does_not_create_workspace(self):
        fixture = self.fixture()
        raw = bytearray(fixture[0].read_bytes())
        raw[-1] ^= 1
        fixture[0].write_bytes(raw)
        with self.assertRaisesRegex(subject.EvidenceError, "SHA-256"):
            self.prepare(fixture)
        self.assertFalse((self.root / (fixture[0].stem + "-work")).exists())

    def test_inner_digest_mismatch_does_not_extract_trace(self):
        fixture = list(self.fixture())
        fixture[2] = dict(fixture[2], sha256="0" * 64)
        with self.assertRaisesRegex(subject.EvidenceError, "SHA-256"):
            self.prepare(fixture)
        self.assertFalse((self.root / (fixture[0].stem + "-work") / "recording.trace").exists())

    def test_unsafe_relative_names_are_rejected(self):
        for name in ("/absolute", "../escape", "a/../b", "a//b", "a/./b", "a\\b", "C:/b", "a\nb", "é"):
            with self.subTest(name=repr(name)), self.assertRaisesRegex(subject.EvidenceError, "unsafe relative path"):
                self.catalog([(name, b"x", stat.S_IFREG | 0o600)])

    def test_nul_truncated_zip_name_is_rejected(self):
        raw = zip_bytes([("aXb", b"x", stat.S_IFREG | 0o600)]).replace(b"aXb", b"a\x00b")
        with zipfile.ZipFile(io.BytesIO(raw)) as archive:
            with self.assertRaisesRegex(subject.EvidenceError, "unsafe relative path"):
                subject._catalog(archive)

    def test_duplicate_case_alias_and_file_directory_alias_names_are_rejected(self):
        for names in (("a", "a"), ("A", "a"), ("a", "a/")):
            with self.subTest(names=names), self.assertRaisesRegex(subject.EvidenceError, "duplicate or case aliases"):
                self.catalog([(name, b"" if name.endswith("/") else b"x",
                               (stat.S_IFDIR if name.endswith("/") else stat.S_IFREG) | 0o600) for name in names])

    def test_case_insensitive_file_parent_conflict_is_rejected(self):
        with self.assertRaisesRegex(subject.EvidenceError, "parent directory"):
            self.catalog([("Parent", b"x", stat.S_IFREG | 0o600),
                          ("parent/child", b"x", stat.S_IFREG | 0o600)])

    def test_zip_links_and_special_files_are_rejected(self):
        for kind in (stat.S_IFLNK, stat.S_IFIFO, stat.S_IFCHR, stat.S_IFBLK, stat.S_IFSOCK):
            with self.subTest(kind=kind), self.assertRaisesRegex(subject.EvidenceError, "link or special file"):
                self.catalog([("payload", b"target", kind | 0o600)])

    def test_encryption_flag_is_rejected_before_member_read(self):
        raw = bytearray(zip_bytes([("payload", b"x", stat.S_IFREG | 0o600)]))
        central = raw.index(b"PK\x01\x02")
        struct.pack_into("<H", raw, central + 8, 1)
        with zipfile.ZipFile(io.BytesIO(raw)) as archive:
            with self.assertRaisesRegex(subject.EvidenceError, "encryption"):
                subject._catalog(archive)

    def test_unsupported_compression_is_rejected_before_inflation(self):
        raw = zip_bytes([("payload", b"x", stat.S_IFREG | 0o600)], compression=zipfile.ZIP_BZIP2)
        with zipfile.ZipFile(io.BytesIO(raw)) as archive:
            with self.assertRaisesRegex(subject.EvidenceError, "compression"):
                subject._catalog(archive)

    def test_entry_and_expanded_byte_limits_fail_on_small_fixtures(self):
        entries = [("a", b"123", stat.S_IFREG | 0o600), ("b", b"456", stat.S_IFREG | 0o600)]
        with self.assertRaisesRegex(subject.EvidenceError, "entry count"):
            self.catalog(entries, maximum_entries=1)
        with self.assertRaisesRegex(subject.EvidenceError, "expanded-byte"):
            self.catalog(entries, maximum_bytes=5)

    def test_directory_payload_is_rejected(self):
        with self.assertRaisesRegex(subject.EvidenceError, "size is invalid"):
            self.catalog([("directory/", b"payload", stat.S_IFDIR | 0o700)])

    def test_inner_extra_entry_is_rejected_before_trace_extraction(self):
        fixture = list(self.fixture())
        fixture[3] = dict(fixture[3])
        fixture[3].pop("recording.trace/Trace1.run/RunIssues.storedata")
        with self.assertRaisesRegex(subject.EvidenceError, "names differ"):
            self.prepare(fixture)
        self.assertFalse((self.root / (fixture[0].stem + "-work") / "recording.trace").exists())

    def test_corrupt_selected_member_crc_is_rejected(self):
        fixture = list(self.fixture())
        raw = bytearray(fixture[0].read_bytes())
        with zipfile.ZipFile(io.BytesIO(raw)) as archive:
            item = archive.getinfo(subject.SELECTED_MEMBER)
            offset = item.header_offset + 30 + len(item.filename.encode()) + len(item.extra)
        raw[offset] ^= 1
        fixture[0].write_bytes(raw)
        fixture[1] = dict(fixture[1], sha256=hashlib.sha256(raw).hexdigest())
        with self.assertRaisesRegex(subject.EvidenceError, "CRC check"):
            self.prepare(fixture)
        self.assertFalse((self.root / (fixture[0].stem + "-work") / "recording.trace").exists())

    def test_truncated_source_rejected_before_extraction(self):
        fixture = self.fixture()
        fixture[0].write_bytes(fixture[0].read_bytes()[:-12])
        with self.assertRaisesRegex(subject.EvidenceError, "byte count"):
            self.prepare(fixture)
        self.assertFalse((self.root / (fixture[0].stem + "-work")).exists())

    def test_fifo_input_fails_without_blocking(self):
        fifo = self.root / "fifo"
        os.mkfifo(fifo)
        code = ("from pathlib import Path; import native_retained_trace_input as m; "
                "m.prepare_input(Path(__import__('sys').argv[1]),Path(__import__('sys').argv[2]))")
        result = subprocess.run([sys.executable, "-c", code, str(fifo), str(self.root / "fifo-work")],
                                cwd=Path(subject.__file__).parent, capture_output=True, timeout=2)
        self.assertNotEqual(0, result.returncode)
        self.assertIn(b"Input is not a regular file", result.stderr)
        self.assertFalse((self.root / "fifo-work").exists())

    def test_source_symlink_is_not_followed(self):
        fixture = list(self.fixture())
        link = self.root / "source-link.zip"
        link.symlink_to(fixture[0])
        fixture[0] = link
        with self.assertRaises(OSError):
            self.prepare(fixture)
        self.assertFalse((self.root / "source-link-work").exists())

    def test_existing_workspace_or_symlink_is_not_overwritten(self):
        fixture = self.fixture()
        existing = self.root / "existing"
        existing.mkdir()
        marker = existing / "keep"
        marker.write_bytes(b"unchanged")
        link = self.root / "workspace-link"
        link.symlink_to(existing, target_is_directory=True)
        for destination in (existing, link):
            with self.subTest(destination=destination.name), self.assertRaises(FileExistsError):
                self.prepare(fixture, destination)
        self.assertEqual(b"unchanged", marker.read_bytes())
        self.assertEqual([marker], list(existing.iterdir()))

    def test_parent_alias_is_canonicalized_before_deriving_trace_path(self):
        fixture = self.fixture()
        link = self.root / "alias"
        link.symlink_to(self.root, target_is_directory=True)
        result = self.prepare(fixture, link / "canonical-work")
        self.assertEqual(str(self.root / "canonical-work/recording.trace"), result["tracePath"])

    def test_snapshot_detects_content_path_deletion_addition_and_permission_changes(self):
        for change in ("content", "deleted", "added", "renamed", "permission"):
            with self.subTest(change=change):
                result = self.prepare()
                trace = Path(result["tracePath"])
                target = trace / "Trace1.run/RunIssues.storedata"
                target.parent.chmod(0o700)
                if change == "content":
                    target.chmod(0o600)
                    target.write_bytes(b"different issue bytes")
                    target.chmod(0o400)
                elif change == "deleted":
                    target.unlink()
                elif change == "added":
                    (target.parent / "extra").write_bytes(b"extra")
                    (target.parent / "extra").chmod(0o400)
                elif change == "renamed":
                    target.rename(target.with_name("renamed"))
                else:
                    target.chmod(0o600)
                target.parent.chmod(0o500)
                self.assertNotEqual(result["manifest"], subject.snapshot_trace(trace))

    def test_snapshot_rejects_symlink_fifo_and_external_hardlink(self):
        for kind in ("symlink", "fifo", "hardlink"):
            with self.subTest(kind=kind):
                result = self.prepare()
                trace = Path(result["tracePath"])
                target = trace / "Trace1.run/RunIssues.storedata"
                target.parent.chmod(0o700)
                if kind == "hardlink":
                    os.link(target, trace.parent / "external-link")
                else:
                    target.unlink()
                    if kind == "symlink":
                        target.symlink_to(trace / "Trace1.run/Attachments/trace-data.atrc")
                    else:
                        os.mkfifo(target)
                target.parent.chmod(0o500)
                with self.assertRaises(subject.EvidenceError):
                    subject.snapshot_trace(trace)

    def test_snapshot_bounds_reject_excess_entries_bytes_and_depth(self):
        result = self.prepare()
        trace = Path(result["tracePath"])
        for constant, value in (("MAX_ENTRIES", 4), ("MAX_EXPANDED_BYTES", 4), ("MAX_DEPTH", 0)):
            with self.subTest(constant=constant), patch.object(subject, constant, value):
                with self.assertRaises(subject.EvidenceError):
                    subject.snapshot_trace(trace)


if __name__ == "__main__":
    unittest.main()
