#!/usr/bin/env python3
"""Portable D30 pressure tests; the process-group fixture is synthetic.

The worker, filesystem, sockets, required report failure and WNOWAIT leases
are real. Only /bin/ps output is replaced in these tests because this portable
executor does not expose a usable system process census. The live pressure
API has no such fallback.
"""
from __future__ import annotations

import errno
import json
import os
from pathlib import Path
import signal
import socket
import sys
import tempfile
import unittest
from unittest import mock

import qualify_isolated_atrc_pressure as subject


class LeaderVisibilityTests(unittest.TestCase):
    def receipt(self, members):
        return {"pid": 42, "finalOwnedGroups": {subject.NAME: {
            "pidLeaseHeldAtSnapshot": True, "noLiveMembersObserved": True,
            "members": members}}}

    def test_empty_group_does_not_substitute_for_a_visible_held_leader(self):
        self.assertFalse(subject._leader_visible(self.receipt([])))
        row = {"pid": 42, "pgid": 42, "state": "Z+"}
        self.assertTrue(subject._leader_visible(self.receipt([row])))
        for members in ([row, row], [{**row, "pgid": 41}], [{**row, "state": "S"}]):
            with self.subTest(members=members):
                self.assertFalse(subject._leader_visible(self.receipt(members)))


@unittest.skipUnless(hasattr(os, "waitid") and hasattr(os, "WNOWAIT"),
                     "Requires real non-reaping POSIX child status")
class PressureCaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name).resolve(strict=True)
        self.transports = []
        self.omit_leader = False
        self.native_transport = subject.progress.startup.MonitoredCommand
        self.descriptor_transport = subject.isolated.DescriptorTransport
        self.worker_patch = mock.patch.object(subject.isolated, "DescriptorTransport", side_effect=self.owned_worker)
        self.group_patch = mock.patch.object(subject.progress.startup, "MonitoredCommand", side_effect=self.synthetic_group)
        self.worker_patch.start()
        self.group_patch.start()
        self.witness = {"groupEnumeration": "synthetic-direct-owned-child-list",
                        "realKernelSocketPressure": True, "nativeQualification": False}

    def tearDown(self):
        self.group_patch.stop()
        self.worker_patch.stop()
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
        self.temp.cleanup()

    def owned_worker(self, *args, **kwargs):
        transport = self.descriptor_transport(*args, **kwargs)
        self.transports.append(transport)
        return transport

    def synthetic_group(self, argv, *, cwd, env, limit):
        self.assertEqual(subject.PS_ARGV, tuple(argv))
        rows = [(os.getpid(), os.getpgrp(), "S")]
        if not self.omit_leader:
            for transport in self.transports:
                child = transport.process
                if child is None or child.returncode is not None:
                    continue
                status = os.waitid(os.P_PID, child.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)
                rows.append((child.pid, os.getpgid(child.pid), "Z" if status is not None else "S"))
        raw = "".join(" ".join(map(str, row)) + "\n" for row in rows)
        transport = self.native_transport((sys.executable, "-c", "import sys;sys.stdout.write(sys.argv[1])", raw),
                                          cwd=cwd, env=env, limit=limit)
        self.transports.append(transport)
        return transport

    def run_case(self):
        result = subject.run_pressure_case(self.root, dict(os.environ))
        self.witness["details"] = result["details"]
        self.witness["receipt"] = result["receipt"]
        self.witness["reportRawHex"] = result["report_raw"].hex()
        return result

    def assert_collected_and_closed(self):
        self.assertTrue(self.transports)
        for transport in self.transports:
            child = transport.process
            self.assertTrue(child is None or child.returncode is not None,
                            "All children must be collected before fixture teardown")
            self.assertTrue(transport.closed)
            if child is not None:
                self.assertTrue(child.stdout.closed)
                self.assertTrue(child.stderr.closed)

    def test_real_socket_saturation_exits_two_without_report_retry(self):
        result = self.run_case()
        self.assertTrue(result["details"]["passed"], result["details"])
        self.assertEqual(2, result["receipt"]["exitCode"])
        self.assertIn(b"Required report unavailable", result["streams"]["stderr"])
        self.assertEqual(1, result["details"]["scanRequestAttempts"])
        self.assertEqual(0, result["details"]["postDispatchLiveReportReads"])
        self.assertEqual(128, len(list((self.root / "observed").iterdir())))
        self.assertLessEqual(result["details"]["socketBuffers"]["actualSendBytes"], 65536)
        self.assertLessEqual(len(result["report_raw"]), 65536)
        prefix = result["details"]["prefixLifecycle"]
        self.assertTrue(prefix["operationStarted"])
        self.assertEqual(0, prefix["completedScanCount"])
        self.assertFalse(prefix["receiveTimeDeadlineValidationClaimed"])
        self.assert_collected_and_closed()
        before = len(self.transports)
        with self.assertRaises(FileExistsError):
            subject.run_pressure_case(self.root, dict(os.environ))
        self.assertEqual(before, len(self.transports))

    def test_missing_held_leader_cannot_qualify_even_when_adapter_accepts_empty_group(self):
        self.omit_leader = True
        result = self.run_case()
        self.assertTrue(result["receipt"]["cleanupComplete"])
        self.assertTrue(result["receipt"]["transportComplete"])
        self.assertFalse(result["details"]["checks"]["leader_visible_while_leased"])
        self.assertFalse(result["details"]["passed"])
        self.assert_collected_and_closed()

    def test_prefix_duplicate_sequence_is_not_accepted_as_pressure_evidence(self):
        result = self.run_case()
        self.assertTrue(result["details"]["passed"])
        lines = result["report_raw"].split(b"\n")
        self.assertGreater(len(lines), 2)
        ready, second = json.loads(lines[0]), json.loads(lines[1])
        second["seq"] = ready["seq"]
        lines[1] = json.dumps(second, separators=(",", ":")).encode()
        bad = subject._prefix(b"\n".join(lines), nonce=ready["nonce"], identity=ready["rootIdentity"],
                              limits=ready["limits"], pid=ready["pid"],
                              ready_received_ns=result["details"]["readyReceivedNS"],
                              dispatched_ns=result["details"]["scanDispatchedNS"])
        self.assertFalse(bad["orderedBoundPrefix"])
        self.assertTrue(bad["errors"])
        self.assert_collected_and_closed()

    def test_socket_setup_failure_closes_acquired_pipe_and_root_without_child(self):
        original_pipe = os.pipe
        descriptors = []
        def tracked_pipe():
            pair = original_pipe()
            descriptors.extend(pair)
            return pair
        original_guard = subject.output.OutputGuard
        def tracked_guard(*args, **kwargs):
            guard = original_guard(*args, **kwargs)
            descriptors.append(guard.fd)
            return guard
        with mock.patch.object(subject.os, "pipe", side_effect=tracked_pipe), \
             mock.patch.object(subject.output, "OutputGuard", side_effect=tracked_guard), \
             mock.patch.object(subject.socket, "socketpair", side_effect=OSError(errno.EMFILE, "fixture sockets")):
            with self.assertRaises(OSError):
                self.run_case()
        self.assertEqual([], self.transports)
        self.assertEqual(3, len(descriptors))
        for descriptor in descriptors:
            with self.assertRaises(OSError) as error:
                os.fstat(descriptor)
            self.assertEqual(errno.EBADF, error.exception.errno)

    def test_post_capture_close_error_preserves_receipt_and_closes_remaining_resources(self):
        original_socketpair = socket.socketpair
        endpoints = []
        def tracked_socketpair():
            reader, writer = original_socketpair()
            endpoints.extend((reader, writer))
            class Reader:
                def __getattr__(self, name):
                    return getattr(reader, name)
                def close(self):
                    reader.close()
                    raise OSError(errno.EIO, "fixture report close after real close")
            return Reader(), writer
        with mock.patch.object(subject.socket, "socketpair", side_effect=tracked_socketpair):
            result = self.run_case()
        self.assertFalse(result["details"]["passed"])
        self.assertFalse(result["details"]["checks"]["no_harness_errors"])
        self.assertTrue(result["receipt"]["cleanupComplete"])
        self.assertTrue(all(endpoint.fileno() == -1 for endpoint in endpoints))
        self.assert_collected_and_closed()

    def test_unexpected_post_spawn_exception_preserves_failure_and_accounts_child(self):
        original_capture = subject.command.capture_owned
        def interrupted(name, argv, **kwargs):
            if name != subject.NAME:
                return original_capture(name, argv, **kwargs)
            subject.progress.OwnedCommand(name, argv, cwd=kwargs["cwd"], env=kwargs["env"],
                                          budget=kwargs["budget"], reserve=kwargs["reserve"],
                                          limit=kwargs["limit"], factory=kwargs["test_factory"])
            raise RuntimeError("fixture adapter exception after lease acquisition")
        with mock.patch.object(subject.command, "capture_owned", side_effect=interrupted):
            result = self.run_case()
        self.assertFalse(result["details"]["passed"])
        self.assertTrue(any("fixture adapter exception" in error for error in result["details"]["errors"]))
        self.assertTrue(result["receipt"]["recoveryCollection"])
        self.assertTrue(result["receipt"]["recoveryCollectedExitMatchesPeek"])
        self.assertTrue(result["receipt"]["pidLeaseReleased"])
        self.assertFalse(result["receipt"]["pidLeaseLost"])
        self.assertTrue(result["receipt"]["pidDirectedActionsRevoked"])
        self.assertFalse(result["receipt"]["transportComplete"])
        self.assert_collected_and_closed()


if __name__ == "__main__":
    unittest.main()
