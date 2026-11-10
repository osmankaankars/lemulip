#!/usr/bin/env python3
"""Focused D30 fixture checks; no descendant or Apple tool is launched."""
from __future__ import annotations

import contextlib
import io
import json
import os
from pathlib import Path
import tempfile
import time
import unittest
from unittest import mock

import isolated_atrc_macos_fixture as target
import isolated_atrc_macos_worker_fixture as worker_fixture


class FixtureTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.case = Path(self.temporary.name).resolve(strict=True)
        self.observed = self.case / "observed"
        self.observed.mkdir(mode=0o700)
        self.context = target.validate_context(self.case, self.observed)

    def tearDown(self):
        self.temporary.cleanup()

    def test_success_creates_only_fixed_payloads_and_requested_live_window(self):
        stdout = io.StringIO()
        with mock.patch.object(target.time, "sleep") as sleep, contextlib.redirect_stdout(stdout):
            self.assertEqual(0, target.run_success(self.context))
        sleep.assert_called_once_with(0.15)
        actual = {str(p.relative_to(self.observed)): p.read_bytes()
                  for p in self.observed.rglob("*") if p.is_file()}
        self.assertEqual(target.EXPECTED_FILES, actual)
        self.assertEqual(4, len(actual))
        self.assertLess(sum(map(len, actual.values())), 1024)
        self.assertEqual(target.SUCCESS_STDOUT.decode(), stdout.getvalue())

    def test_context_rejects_relative_symlink_foreign_and_nonexclusive_root(self):
        with self.assertRaises(target.FixtureError):
            target.validate_context(Path("relative"), self.observed)
        linked = self.case / "control-link"
        linked.symlink_to(self.case, target_is_directory=True)
        with self.assertRaises(target.FixtureError):
            target.validate_context(linked, self.observed)
        other = self.case / "other"
        other.mkdir(mode=0o700)
        with self.assertRaises(target.FixtureError):
            target.validate_context(other, self.observed)
        self.observed.chmod(0o755)
        with self.assertRaises(target.FixtureError):
            target.validate_context(self.case, self.observed)

    def test_marker_publication_is_bounded_complete_and_does_not_overwrite(self):
        original = {"schema": 1, "pid": 123, "monotonicNS": 456}
        target.publish_marker(self.case, "worker-operation.json", original)
        self.assertEqual(original, target.read_marker(self.case, "worker-operation.json"))
        with self.assertRaises(FileExistsError):
            target.publish_marker(self.case, "worker-operation.json", {"changed": True})
        self.assertEqual(original, target.read_marker(self.case, "worker-operation.json"))
        self.assertFalse((self.case / "worker-operation.json.pending").exists())
        with self.assertRaises(target.FixtureError):
            target.publish_marker(self.case, "descendant.json", {"oversized": "x" * 4096})
        with self.assertRaises(target.FixtureError):
            target.publish_marker(self.case, "../foreign.json", {})
        self.assertFalse((self.case / "descendant.json").exists())

    def test_marker_reader_rejects_symlinks_and_fifo_without_waiting(self):
        referent = self.case / "actual.json"
        referent.write_text('{"schema":1}\n')
        marker = self.case / "worker-operation.json"
        marker.symlink_to(referent)
        with self.assertRaises(OSError):
            target.read_marker(self.case, marker.name)
        marker.unlink()
        os.mkfifo(marker, mode=0o600)
        with self.assertRaises(target.FixtureError):
            target.read_marker(self.case, marker.name)

    def test_readiness_wait_has_a_fixed_deadline(self):
        now = [0.0]
        sleeps = []
        def sleep(seconds):
            self.assertGreaterEqual(seconds, 0)
            sleeps.append(seconds)
            now[0] += seconds
        with mock.patch.object(target.time, "monotonic", side_effect=lambda: now[0]), \
                mock.patch.object(target.time, "sleep", side_effect=sleep):
            with self.assertRaisesRegex(target.FixtureError, "readiness deadline"):
                target.wait_marker(self.case, "worker-operation.json", 1.5)
        self.assertAlmostEqual(1.5, now[0])
        self.assertLessEqual(max(sleeps), target.POLL_SECONDS)
        self.assertFalse((self.observed / "stall.bin").exists())

    def test_pending_exit_requires_a_marker_from_its_own_interval(self):
        def ready(directory, name, timeout):
            self.assertEqual(target.WORKER_MARKER_WAIT_SECONDS, timeout)
            marker = {"schema": 1, "mode": "delay-stat", "operation": "stat",
                      "relativePath": "stall.bin", "pid": os.getpid(), "pgid": os.getpgrp(),
                      "monotonicNS": time.monotonic_ns()}
            target.publish_marker(directory, name, marker)
            return target.read_marker(directory, name)
        stdout = io.StringIO()
        with mock.patch.object(target, "wait_marker", side_effect=ready), contextlib.redirect_stdout(stdout):
            self.assertEqual(0, target.run_pending_exit(self.context))
        self.assertTrue((self.observed / "stall.bin").is_file())
        self.assertEqual(target.PENDING_EXIT_STDOUT.decode(), stdout.getvalue())
        (self.observed / "stall.bin").unlink()
        stale = json.loads((self.case / "worker-operation.json").read_text())
        stale["monotonicNS"] = 1
        with mock.patch.object(target, "wait_marker", return_value=stale):
            with self.assertRaises(target.FixtureError):
                target.run_pending_exit(self.context)

    def test_invalid_target_arguments_cannot_start_descendant(self):
        with mock.patch.object(target, "run_descendant") as descendant, \
                contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(2, target.main(["descendant", "--control-dir", "relative"]))
            with self.assertRaises(SystemExit) as raised:
                target.main(["arbitrary-command", "--control-dir", str(self.case)])
        self.assertEqual(2, raised.exception.code)
        descendant.assert_not_called()

    def test_descendant_mode_refuses_a_foreign_group_before_fork(self):
        with mock.patch.object(target.os, "getpid", return_value=123), \
                mock.patch.object(target.os, "getpgrp", return_value=456), \
                mock.patch.object(target.os, "fork") as fork:
            with self.assertRaisesRegex(target.FixtureError, "process-group leader"):
                target.run_descendant(self.context)
        fork.assert_not_called()

    def test_worker_environment_requires_fixed_mode_and_bound_paths(self):
        valid = {"D30_WORKER_MODE": "delay-stat", "D30_CONTROL_DIR": str(self.case)}
        mode, context = worker_fixture.environment_context(valid, ["--root", str(self.observed), "--nonce", "a" * 32])
        self.assertEqual("delay-stat", mode)
        self.assertEqual(self.context, context)
        for environment in ({}, {**valid, "D30_WORKER_MODE": "arbitrary"},
                            {**valid, "D30_CONTROL_DIR": "relative"}):
            with self.subTest(environment=environment):
                with self.assertRaises(target.FixtureError):
                    worker_fixture.environment_context(environment, ["--root", str(self.observed)])

    def test_worker_delay_records_entry_before_sleep_and_restores_real_stat(self):
        (self.observed / "stall.bin").write_bytes(b"fixed")
        descriptor = os.open(self.observed, os.O_RDONLY | os.O_DIRECTORY)
        original = worker_fixture.worker.REAL_STAT
        events = []
        def fake_main():
            self.assertFalse((self.case / "worker-operation.json").exists())
            worker_fixture.worker.REAL_STAT(self.observed, follow_symlinks=False)
            self.assertFalse((self.case / "worker-operation.json").exists())
            info = worker_fixture.worker.REAL_STAT("stall.bin", dir_fd=descriptor, follow_symlinks=False)
            self.assertEqual(5, info.st_size)
            events.append("stat-returned")
            return 0
        def sleep(seconds):
            marker = target.read_marker(self.case, "worker-operation.json")
            self.assertEqual("stat", marker["operation"])
            self.assertEqual("stall.bin", marker["relativePath"])
            self.assertEqual(os.getpid(), marker["pid"])
            self.assertEqual(worker_fixture.DELAY_SECONDS, seconds)
            events.append("wait-entered-with-marker")
        try:
            with mock.patch.object(worker_fixture.worker, "main", side_effect=fake_main), \
                    mock.patch.object(worker_fixture.time, "sleep", side_effect=sleep):
                self.assertEqual(0, worker_fixture.run("delay-stat", self.context))
        finally:
            os.close(descriptor)
        self.assertEqual(["wait-entered-with-marker", "stat-returned"], events)
        self.assertIs(original, worker_fixture.worker.REAL_STAT)
        with mock.patch.object(worker_fixture.worker, "main", side_effect=OSError("fixture failure")):
            with self.assertRaises(OSError):
                worker_fixture.run("delay-stat", self.context)
        self.assertIs(original, worker_fixture.worker.REAL_STAT)

    def test_exit_seven_only_replaces_a_normal_successful_worker_result(self):
        original = worker_fixture.worker.REAL_STAT
        for status, expected in ((0, 7), (2, 2), (-15, -15)):
            with self.subTest(status=status), mock.patch.object(worker_fixture.worker, "main", return_value=status):
                self.assertEqual(expected, worker_fixture.run("exit-seven", self.context))
                self.assertIs(original, worker_fixture.worker.REAL_STAT)


if __name__ == "__main__":
    unittest.main()
