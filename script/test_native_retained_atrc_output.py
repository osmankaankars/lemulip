#!/usr/bin/env python3
"""Synthetic portable checks of D27 output bounds; never runs xctrace."""
from __future__ import annotations

import hashlib
import os
from pathlib import Path
import signal
import sys
import tempfile
import time
import unittest
from unittest import mock
import zipfile

import native_retained_atrc_output as subject
import run_native_system_trace_startup as startup


class OutputRetentionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name).resolve(strict=True)
        self.evidence = self.root / "evidence"
        self.evidence.mkdir()
        self.archive = self.evidence / "derived.trace.zip"
        self.guards = []

    def tearDown(self):
        for guard in self.guards:
            guard.close()
        self.temporary.cleanup()

    def guard(self, **kwargs):
        guard = subject.OutputGuard(self.root / ("output-"+str(len(self.guards))), **kwargs)
        self.guards.append(guard)
        return guard

    def write(self, guard, payload=b"retained evidence"):
        guard.target.mkdir()
        target = guard.target / "payload.bin"
        target.write_bytes(payload)
        return target

    def test_empty_output_is_retained_observation_without_an_analysis_document(self):
        guard = self.guard()
        result = guard.finalize(self.archive, safe_to_read=True)
        self.assertEqual("no-output", result["status"])
        self.assertTrue(result["retentionComplete"])
        self.assertTrue(result["inventoryComplete"])
        self.assertTrue(result["outputBoundsPass"])
        self.assertFalse(result["newAnalysisDocumentObserved"])
        self.assertIsNone(result["archive"])
        self.assertFalse(self.archive.exists())

    def test_nonempty_document_retains_exact_bytes_hashes_crc_and_complete_inventory(self):
        guard = self.guard()
        payload = bytes(range(256))*300
        path = self.write(guard, payload)
        result = guard.finalize(self.archive, safe_to_read=True)
        self.assertTrue(result["retentionComplete"])
        self.assertTrue(result["newAnalysisDocumentObserved"])
        self.assertFalse(result["semanticAnalysisValidityEstablished"])
        self.assertTrue(result["archive"]["crcAndSHA256Verified"])
        self.assertEqual(len(payload), result["archive"]["expandedBytes"])
        self.assertEqual(hashlib.sha256(self.archive.read_bytes()).hexdigest(), result["archive"]["sha256"])
        with zipfile.ZipFile(self.archive) as archive:
            self.assertEqual(payload, archive.read("derived-output/derived.trace/payload.bin"))
            self.assertIsNone(archive.testzip())
        self.assertEqual(payload, path.read_bytes())
        self.assertEqual(0, result["retentionDeadlineOvershootSeconds"])
        self.assertEqual([], list(self.root.glob(".d27-retention-*")))

    def test_empty_trace_directory_is_retained_but_unqualified(self):
        guard = self.guard()
        guard.target.mkdir()
        result = guard.finalize(self.archive, safe_to_read=True)
        self.assertTrue(result["retentionComplete"])
        self.assertFalse(result["newAnalysisDocumentObserved"])
        self.assertIsNotNone(result["archive"])

    def test_unexpected_sibling_is_retained_without_qualifying_document(self):
        guard = self.guard()
        self.write(guard)
        (guard.root / "unexpected.tmp").write_bytes(b"temporary result")
        result = guard.finalize(self.archive, safe_to_read=True)
        self.assertTrue(result["retentionComplete"])
        self.assertFalse(result["newAnalysisDocumentObserved"])
        with zipfile.ZipFile(self.archive) as archive:
            self.assertEqual(b"temporary result", archive.read("derived-output/unexpected.tmp"))

    def test_missing_cleanup_skips_all_output_reads_and_archiving(self):
        guard = self.guard()
        self.write(guard)
        with mock.patch.object(guard, "_scan", side_effect=AssertionError("Must not inspect unsafe output")):
            result = guard.finalize(self.archive, safe_to_read=False)
        self.assertEqual("skipped-cleanup-incomplete", result["status"])
        self.assertFalse(result["retentionComplete"])
        self.assertFalse(result["inventoryComplete"])
        self.assertFalse(self.archive.exists())

    def test_observed_growth_fails_closed_and_cannot_be_requalified(self):
        guard = self.guard(test_limits={"logicalBytes": 32})
        path = self.write(guard, b"x"*33)
        self.assertFalse(guard.sample(force=True))
        path.write_bytes(b"now small")
        result = guard.finalize(self.archive, safe_to_read=True)
        self.assertFalse(result["outputBoundsPass"])
        self.assertFalse(result["retentionComplete"])
        self.assertFalse(self.archive.exists())
        self.assertGreater(guard.summary()["highWaterObserved"]["logicalBytes"], 32)

    def test_late_growth_first_observed_in_finalization_fails_bounds(self):
        guard = self.guard(test_limits={"logicalBytes": 32})
        self.write(guard, b"x"*33)
        result = guard.finalize(self.archive, safe_to_read=True)
        self.assertFalse(result["outputBoundsPass"])
        self.assertEqual("derived-output-final-observation-failed", guard.failure["code"])
        self.assertFalse(result["retentionComplete"])

    def test_allocated_bytes_are_bounded_independently(self):
        guard = self.guard(test_limits={"allocatedBytes": 8192})
        self.write(guard, b"x"*65536)
        self.assertFalse(guard.sample(force=True))
        self.assertIn("allocatedBytes", guard.failure["error"])
        self.assertLess(guard.summary()["highWaterObserved"]["logicalBytes"], subject.LIMITS["logicalBytes"])

    def test_entry_and_depth_bounds_fail_before_unbounded_walk(self):
        with self.subTest("entries"):
            guard = self.guard(test_limits={"entries": 3})
            guard.target.mkdir()
            (guard.target / "one").touch()
            (guard.target / "two").touch()
            self.assertFalse(guard.sample(force=True))
            self.assertIn("entries", guard.failure["error"])
        with self.subTest("depth"):
            guard = self.guard(test_limits={"depth": 2})
            (guard.target / "nested" / "deep").mkdir(parents=True)
            self.assertFalse(guard.sample(force=True))
            self.assertIn("depth", guard.failure["error"])

    def test_symlinks_hardlinks_and_special_files_are_never_read(self):
        outside = self.root / "outside"
        outside.write_bytes(b"outside contents")
        for kind in ("symlink", "hardlink", "fifo"):
            with self.subTest(kind):
                guard = self.guard()
                if kind == "symlink":
                    (guard.root / "entry").symlink_to(outside)
                elif kind == "hardlink":
                    os.link(outside, guard.root / "entry")
                else:
                    os.mkfifo(guard.root / "entry")
                self.assertFalse(guard.sample(force=True))
                self.assertFalse(guard.finalize(self.archive, safe_to_read=True)["retentionComplete"])
        self.assertEqual(b"outside contents", outside.read_bytes())

    def test_replaced_root_cannot_redirect_observation(self):
        guard = self.guard()
        guard.root.rename(self.root / "old-output")
        guard.root.mkdir(mode=0o700)
        self.assertFalse(guard.sample(force=True))
        self.assertIn("root identity", guard.failure["error"])

    def test_existing_parent_and_existing_archive_are_not_overwritten(self):
        existing = self.root / "already-present"
        existing.mkdir()
        with self.assertRaises(FileExistsError):
            subject.OutputGuard(existing)
        guard = self.guard()
        self.write(guard)
        self.archive.write_bytes(b"preserved")
        result = guard.finalize(self.archive, safe_to_read=True)
        self.assertFalse(result["retentionComplete"])
        self.assertEqual(b"preserved", self.archive.read_bytes())

    def test_file_mutation_during_retention_rejects_and_removes_partial_archive(self):
        guard = self.guard()
        path = self.write(guard, b"a"*100000)
        original = os.read
        mutated = False
        def read(fd, size):
            nonlocal mutated
            data = original(fd, size)
            if not mutated:
                mutated = True
                path.write_bytes(b"b"*100000)
            return data
        with mock.patch.object(subject.os, "read", side_effect=read):
            result = guard.finalize(self.archive, safe_to_read=True)
        self.assertFalse(result["retentionComplete"])
        self.assertFalse(result["newAnalysisDocumentObserved"])
        self.assertFalse(self.archive.exists())
        self.assertEqual([], list(self.root.glob(".d27-retention-*")))

    def test_scan_deadline_and_actual_overshoot_are_retained(self):
        guard = self.guard()
        original = subject.os.stat
        def slow_stat(*args, **kwargs):
            time.sleep(.005)
            return original(*args, **kwargs)
        with mock.patch.object(subject, "SCAN_SECONDS", .001), mock.patch.object(subject.os, "stat", side_effect=slow_stat):
            self.assertFalse(guard.sample(force=True))
        latest = guard.summary()["observations"][-1]
        self.assertFalse(latest["completed"])
        self.assertGreater(latest["scanDeadlineOvershootSeconds"], 0)
        self.assertFalse(guard.summary()["hardFilesystemQuotaEnforced"])

    def test_retention_deadline_is_finite_and_partial_archive_stays_unpublished(self):
        guard = self.guard()
        self.write(guard, b"x"*200000)
        original = os.read
        def slow_read(fd, size):
            data = original(fd, size)
            time.sleep(.02)
            return data
        with mock.patch.object(subject, "RETENTION_SECONDS", .01), mock.patch.object(subject.os, "read", side_effect=slow_read):
            result = guard.finalize(self.archive, safe_to_read=True)
        self.assertFalse(result["retentionComplete"])
        self.assertGreater(result["retentionDeadlineOvershootSeconds"], 0)
        self.assertFalse(self.archive.exists())

    def test_observation_history_is_bounded_and_omissions_are_explicit(self):
        guard = self.guard()
        for _ in range(300):
            self.assertTrue(guard.sample(force=True))
        summary = guard.summary()
        self.assertEqual(256, len(summary["observations"]))
        self.assertEqual(45, summary["omittedCompletedObservationCount"])


@unittest.skipUnless(hasattr(os, "waitid") and hasattr(os, "WNOWAIT"), "Requires non-reaping POSIX child status")
class OutputCommandTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name).resolve(strict=True)
        self.transports = []
        self.guard = subject.OutputGuard(self.root / "derived", test_limits={"logicalBytes": 128})
        self.probe_observations = []
        self.on_probe = None

    def tearDown(self):
        for transport in self.transports:
            child = transport.process
            if child is None or child.returncode is not None:
                transport.close()
                continue
            try:
                os.waitid(os.P_PID, child.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)
            except ChildProcessError:
                transport.close()
                continue
            try:
                os.killpg(child.pid, signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                pass
            child.wait(timeout=1)
            transport.close()
        self.guard.close()
        self.temporary.cleanup()

    def factory(self, name, argv, *, cwd, env, limit):
        if argv[0] == "/bin/ps":
            target = self.transports[0].process
            observed = os.waitid(os.P_PID, target.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)
            self.probe_observations.append({"waitable": observed is not None, "returncode": target.returncode})
            if self.on_probe:
                self.on_probe()
            rows = [(os.getpid(), os.getpgrp(), "S")]
            for previous in self.transports:
                child = previous.process
                if child is None or child.returncode is not None:
                    continue
                state = os.waitid(os.P_PID, child.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)
                rows.append((child.pid, child.pid, "Z" if state is not None else "S"))
            text = "".join(" ".join(map(str, row))+"\n" for row in rows)
            argv = (sys.executable, "-c", "import sys;sys.stdout.write(sys.argv[1])", text)
        transport = startup.MonitoredCommand(argv, cwd=cwd, env=env, limit=limit)
        self.transports.append(transport)
        return transport

    def capture(self, code):
        return subject.capture_import("synthetic-import", (sys.executable, "-u", "-c", code),
                                      cwd=self.guard.root, env=dict(os.environ), guard=self.guard,
                                      test_factory=self.factory, test_budget=1.5, test_reserve=.5)

    def test_successful_command_keeps_lease_and_retains_new_document(self):
        code = "from pathlib import Path; p=Path('derived.trace');p.mkdir();(p/'data').write_bytes(b'raw');print('done')"
        receipt, streams, probes = self.capture(code)
        self.assertTrue(receipt["transportComplete"])
        self.assertTrue(receipt["cleanupComplete"])
        self.assertTrue(receipt["outputBoundsPass"])
        self.assertEqual(b"done\n", streams["stdout"])
        self.assertEqual([{"waitable": True, "returncode": None}], self.probe_observations)
        self.assertEqual(1, len(probes))
        result = self.guard.finalize(self.root / "result.zip", safe_to_read=receipt["cleanupComplete"])
        self.assertTrue(result["newAnalysisDocumentObserved"])

    def test_natural_refusal_with_no_output_remains_completed_diagnostic_transport(self):
        receipt, streams, _ = self.capture("import sys; print('refused',file=sys.stderr);raise SystemExit(7)")
        self.assertEqual(7, receipt["exitCode"])
        self.assertTrue(receipt["transportComplete"])
        self.assertTrue(receipt["outputBoundsPass"])
        result = self.guard.finalize(self.root / "result.zip", safe_to_read=receipt["cleanupComplete"])
        self.assertTrue(result["retentionComplete"])
        self.assertFalse(result["newAnalysisDocumentObserved"])
        self.assertEqual(b"refused\n", streams["stderr"])

    def test_zero_exit_without_output_does_not_create_document_evidence(self):
        receipt, _, _ = self.capture("raise SystemExit(0)")
        self.assertTrue(receipt["transportComplete"])
        self.assertEqual(0, receipt["exitCode"])
        result = self.guard.finalize(self.root / "result.zip", safe_to_read=receipt["cleanupComplete"])
        self.assertTrue(result["retentionComplete"])
        self.assertFalse(result["newAnalysisDocumentObserved"])

    def test_live_output_growth_stops_the_owned_process_and_preserves_failure(self):
        code = "from pathlib import Path; import time; Path('large').write_bytes(b'x'*129);time.sleep(5)"
        receipt, _, _ = self.capture(code)
        self.assertFalse(receipt["transportComplete"])
        self.assertTrue(receipt["cleanupComplete"])
        self.assertFalse(receipt["outputBoundsPass"])
        self.assertEqual("derived-output-observation-failed", receipt["stopReason"])
        self.assertLess(receipt["operationElapsedSeconds"], 1.5)
        self.assertTrue(receipt["pidLeaseReleased"])

    def test_growth_during_group_inspection_cannot_be_promoted_to_success(self):
        self.on_probe = lambda: (self.guard.root / "late").write_bytes(b"x"*129)
        receipt, _, _ = self.capture("raise SystemExit(0)")
        self.assertEqual(0, receipt["exitCode"])
        self.assertFalse(receipt["transportComplete"])
        self.assertFalse(receipt["outputBoundsPass"])
        self.assertTrue(receipt["pidLeaseReleased"])

    def test_command_timeout_remains_failed_after_owned_cleanup(self):
        receipt, _, _ = self.capture("import time;time.sleep(5)")
        self.assertEqual("command-budget", receipt["stopReason"])
        self.assertFalse(receipt["transportComplete"])
        self.assertTrue(receipt["cleanupComplete"])
        self.assertTrue(receipt["outputBoundsPass"])

    def test_preexisting_derived_entry_prevents_any_process_launch(self):
        (self.guard.root / "unexpected").touch()
        with self.assertRaisesRegex(ValueError, "must still be empty"):
            self.capture("raise SystemExit(0)")
        self.assertEqual([], self.transports)

    def test_output_guard_rejects_a_second_attempt(self):
        self.capture("raise SystemExit(0)")
        with self.assertRaisesRegex(ValueError, "second import"):
            self.capture("raise SystemExit(0)")
        self.assertEqual(2, len(self.transports))


if __name__ == "__main__":
    unittest.main()
