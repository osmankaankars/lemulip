#!/usr/bin/env python3
"""D29 resource-failure checks using real disposable Python child processes.

The shared fixture supplies explicitly synthetic group enumeration, based on
its retained direct children and real WNOWAIT status. These tests do not run
Apple tools or establish native trace behavior.
"""
from __future__ import annotations

from contextlib import ExitStack
import errno
import os
import unittest
from unittest import mock

import native_retained_atrc_isolated as subject
import test_native_retained_atrc_isolated as fixtures


class TrackedChannels:
    """Retain descriptor numbers so cleanup is checked before fixture teardown."""

    def __init__(self, *, socket_error=False, option_error=False, close_error=False):
        self.pipe = os.pipe
        self.socketpair = subject.socket.socketpair
        self.descriptors = []
        self.sockets = []
        self.socket_error = socket_error
        self.option_error = option_error
        self.close_error = close_error
        self.options_failed = False
        self.close_failed = False
        self.stack = ExitStack()

    def open_pipe(self):
        pair = self.pipe()
        self.descriptors.extend(pair)
        return pair

    def open_sockets(self, *args, **kwargs):
        if self.socket_error:
            raise OSError(errno.EMFILE, "fixture socketpair failure")
        reader, writer = self.socketpair(*args, **kwargs)
        self.sockets.extend((reader, writer))
        self.descriptors.extend((reader.fileno(), writer.fileno()))
        if not self.option_error and not self.close_error:
            return reader, writer
        owner = self

        class SocketProxy:
            def __getattr__(self, name):
                return getattr(writer, name)

            def getsockopt(self, *args, **kwargs):
                if owner.option_error:
                    owner.options_failed = True
                    raise OSError(errno.EIO, "fixture getsockopt failure")
                return writer.getsockopt(*args, **kwargs)

            def close(self):
                writer.close()
                if owner.close_error and not owner.close_failed:
                    owner.close_failed = True
                    raise OSError(errno.EIO, "fixture writer close failure after spawn")

        return reader, SocketProxy()

    def __enter__(self):
        self.stack.enter_context(mock.patch.object(subject.os, "pipe", side_effect=self.open_pipe))
        self.stack.enter_context(mock.patch.object(subject.socket, "socketpair",
                                                  side_effect=self.open_sockets))
        return self

    def __exit__(self, *args):
        return self.stack.__exit__(*args)

    def assert_closed(self, test):
        test.assertTrue(self.descriptors, "The fixture must observe an actual acquired descriptor")
        for descriptor in set(self.descriptors):
            with test.subTest(descriptor=descriptor):
                try:
                    os.fstat(descriptor)
                except OSError as error:
                    test.assertEqual(error.errno, errno.EBADF)
                else:
                    test.fail("Capture leaked descriptor " + str(descriptor))
        test.assertTrue(all(sock.fileno() == -1 for sock in self.sockets),
                        "Both report socket objects must be closed")


@unittest.skipUnless(hasattr(os, "waitid") and hasattr(os, "WNOWAIT"),
                     "Requires non-reaping POSIX child status")
class IsolatedLifecycleTests(unittest.TestCase):
    def setUp(self):
        # Composition reuses the fixture without inheriting and duplicating its
        # integration test methods during unittest discovery.
        self.fixture = fixtures.IsolatedIntegrationTests("runTest")
        self.fixture.setUp()

    def tearDown(self):
        self.fixture.tearDown()

    def assert_failed(self, result, error_fragment):
        self.assertFalse(result.receipt["transportComplete"])
        self.assertFalse(result._retention_allowed)
        self.assertTrue(any(error_fragment in error for error in result.receipt["errors"]),
                        result.receipt["errors"])

    def assert_children_accounted(self, result, *, target_started):
        worker = result.receipt["worker"]
        self.assertIsNotNone(worker)
        self.assertTrue(worker["pidLeaseAcquired"])
        self.assertTrue(worker["exitObservedWithoutReap"])
        self.assertTrue(worker["pidLeaseReleased"])
        self.assertFalse(worker["pidLeaseLost"])
        if target_started:
            self.fixture.assert_collected(result)
        else:
            self.assertIsNone(result.receipt["target"])
            self.assertFalse(any(row["name"] == "synthetic-target"
                                 for row in self.fixture.launches))
        self.assertTrue(all(transport.process is None or transport.process.returncode is not None
                            for transport in self.fixture.transports),
                        "No owned process may be left for test teardown to collect")
        for transport in self.fixture.transports:
            self.assertTrue(transport.closed)
            if transport.process is not None:
                self.assertTrue(transport.process.stdout.closed)
                self.assertTrue(transport.process.stderr.closed)

    def assert_setup_failure_before_child(self, error_fragment):
        try:
            result = self.fixture.run_capture("print('must not launch')")
        except OSError as error:
            self.assertIn(error_fragment, str(error))
        else:
            self.assert_failed(result, error_fragment)
        self.assertEqual(self.fixture.transports, [])
        self.assertEqual(self.fixture.launches, [])

    def test_socketpair_failure_closes_request_pipe_before_any_child(self):
        with TrackedChannels(socket_error=True) as channels:
            self.assert_setup_failure_before_child("fixture socketpair failure")
        channels.assert_closed(self)

    def test_socket_option_failure_closes_channels_before_any_child(self):
        with TrackedChannels(option_error=True) as channels:
            self.assert_setup_failure_before_child("fixture getsockopt failure")
        self.assertTrue(channels.options_failed)
        channels.assert_closed(self)

    def test_report_setup_failure_closes_channels_before_any_child(self):
        with TrackedChannels() as channels, mock.patch.object(
                subject, "ReportChannel", side_effect=OSError(errno.EIO, "fixture report setup failure")):
            self.assert_setup_failure_before_child("fixture report setup failure")
        channels.assert_closed(self)

    def test_writer_close_setup_failure_after_spawn_accounts_worker_and_channels(self):
        with TrackedChannels(close_error=True) as channels:
            result = self.fixture.run_capture("print('must not launch')")
        self.assertTrue(channels.close_failed)
        self.assert_failed(result, "fixture writer close failure after spawn")
        self.assert_children_accounted(result, target_started=False)
        channels.assert_closed(self)

    def test_probe_factory_failure_still_accounts_both_children(self):
        failed = False

        def factory(name, argv, **kwargs):
            nonlocal failed
            if argv[0] == "/bin/ps" and not failed:
                failed = True
                raise RuntimeError("fixture first group probe factory failure")
            return self.fixture.factory(name, argv, **kwargs)

        with TrackedChannels() as channels:
            result = self.fixture.run_capture("print('target completed')", factory=factory)
        self.assertTrue(failed)
        self.assert_failed(result, "fixture first group probe factory failure")
        self.assert_children_accounted(result, target_started=True)
        channels.assert_closed(self)

    def test_one_transport_close_error_does_not_skip_remaining_resources(self):
        original_close = subject.progress.OwnedCommand.close
        closed = []

        def close(command):
            original_close(command)
            closed.append(command.name)
            if command.name == "output-observer":
                raise OSError(errno.EIO, "fixture worker close reporting failure")

        with TrackedChannels() as channels, mock.patch.object(
                subject.progress.OwnedCommand, "close", close):
            result = self.fixture.run_capture("print('target completed')")
        self.assert_failed(result, "fixture worker close reporting failure")
        self.assert_children_accounted(result, target_started=True)
        self.assertIn("synthetic-target", closed)
        self.assertTrue(any(name.startswith("groups-") for name in closed))
        channels.assert_closed(self)

    def test_one_supervision_error_keeps_failure_but_still_collects_owned_worker(self):
        original_tick = subject.progress.OwnedCommand.tick
        failed = False

        def tick(command):
            nonlocal failed
            if command.name == "output-observer" and not failed:
                failed = True
                raise RuntimeError("fixture transient supervision error")
            return original_tick(command)

        with TrackedChannels() as channels, mock.patch.object(
                subject.progress.OwnedCommand, "tick", tick):
            result = self.fixture.run_capture("print('must not launch')")
        self.assertTrue(failed)
        self.assert_failed(result, "fixture transient supervision error")
        self.assert_children_accounted(result, target_started=False)
        self.assertTrue(result.receipt["worker"]["cleanupFailed"],
                        "Later collection must not erase the supervision failure")
        channels.assert_closed(self)


if __name__ == "__main__":
    unittest.main()
