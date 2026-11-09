#!/usr/bin/env python3
"""D29 deterministic cleanup scheduling and retained-diagnostic bounds.

The real adapter and OwnedCommand run over virtual time and fake transports.
No child, process-group command, signal, or native trace tool is executed.
The worker models an owned child that remains unaccounted for after KILL.
"""
from __future__ import annotations

from contextlib import ExitStack
import json
import os
from pathlib import Path
import signal
from types import SimpleNamespace
import tempfile
import unittest
from unittest import mock

import native_retained_atrc_isolated as subject
import native_retained_atrc_output as legacy


class VirtualClock:
    def __init__(self):
        self.now = 10.0
        self.sleeps = []

    def monotonic(self):
        return self.now

    def monotonic_ns(self):
        return int(self.now * 1_000_000_000)

    def advance(self, seconds):
        self.now += seconds

    def sleep(self, seconds):
        self.sleeps.append(seconds)
        self.advance(seconds)

    def receipt(self):
        return {"monotonicNS": self.monotonic_ns(), "wallUTC": "synthetic"}


class VirtualSelector:
    def __init__(self):
        self.open = True

    def get_map(self):
        return {"synthetic-stream": None} if self.open else {}


class VirtualTransport:
    """A non-exiting worker or a short, successful group-probe transport."""
    def __init__(self, fixture, argv, *, limit, worker):
        self.fixture, self.worker = fixture, worker
        self.started = fixture.clock.monotonic()
        self.process = SimpleNamespace(pid=42001 + len(fixture.transports), returncode=None)
        self.selector = VirtualSelector()
        self.closed = self.reap_deferred = self.done = False
        self.streams = {"stdout": bytearray(), "stderr": bytearray()}
        self.receipt = {"argv": list(argv), "pid": self.process.pid,
                        "status": "running", "exitCode": None,
                        "maximumCombinedBytes": limit, "observedBytes": 0,
                        "retainedBytes": 0, "stopReason": None, "signals": [],
                        "signalErrors": [], "streamErrors": [], "cleanupFailed": False}
        fixture.transports.append(self)

    def drain(self):
        # Work still consumes time when the adapter incorrectly reports busy.
        # A virtual millisecond makes the regression terminate deterministically.
        self.fixture.clock.advance(.001)
        if not self.worker:
            if not self.streams["stdout"]:
                raw = b"42001 42001 S\n"
                self.streams["stdout"].extend(raw)
                self.receipt.update(observedBytes=len(raw), retainedBytes=len(raw))
            if self.fixture.clock.monotonic() - self.started >= .05:
                self.done = True
                self.selector.open = False

    def signal(self, sig, *, group=False):
        self.receipt["signals"].append({"signal": sig.name,
                                        "target": "owned-group" if group else "owned-process",
                                        "afterSeconds": self.fixture.clock.monotonic() - self.started})
        return True

    def poll(self):
        if self.reap_deferred or not self.done:
            return self.process.returncode
        self.process.returncode = 0
        return 0

    def close(self):
        self.closed = True
        self.selector.open = False
        self.receipt["elapsedSeconds"] = self.fixture.clock.monotonic() - self.started
        self.receipt["status"] = "cleanup-incomplete" if self.receipt["cleanupFailed"] else "completed"


class FailedReportChannel:
    def __init__(self, descriptor, *, history_rows=0):
        self.fd = descriptor
        self.buffer = bytearray(b'{"queued":"unusable after first failure"}\n')
        self.eof = False
        self.calls = 0
        self.history_rows = history_rows

    def drain(self, state):
        self.calls += 1
        # Seed bounded history storage directly for the separate final-allocation
        # test. Report semantics are covered by the protocol suite. The alternating
        # populations make removal accounting observable for both result kinds.
        for index in range(self.history_rows):
            state.operations.add({"completed": index % 2 == 0,
                                  "started": {"op": index + 1, "path": "x" * 900},
                                  "ended": {"op": index + 1, "path": "x" * 900}})
        if self.history_rows:
            state.pending = {"scan": 1, "dispatchedNS": 10_000_000_000,
                             "deadlineNS": 10_250_000_000, "started": True,
                             "lastOperation": self.history_rows + 1}
            state.pending_operation = {"scan": 1, "op": self.history_rows + 1,
                                       "category": "stat", "path": "pending.bin"}
        raise subject.ProtocolError("fixture first report failure")

    def summary(self):
        return {"observedBytes": len(self.buffer), "parsedMessages": 0,
                "maximumUndecodedBytes": len(self.buffer),
                "maximumReadBytesPerTick": len(self.buffer),
                "maximumMessagesParsedPerTick": 0,
                "EOF": False, "undecodedBytes": len(self.buffer)}


class CleanupFixture:
    def __init__(self, *, history_rows=0):
        self.clock = VirtualClock()
        self.transports = []
        self.channel = None
        self.history_rows = history_rows

    def worker(self, argv, *, cwd, env, limit, inherited):
        return VirtualTransport(self, argv, limit=limit, worker=True)

    def probe(self, name, argv, *, cwd, env, limit):
        if argv[:2] != ("/bin/ps", "-A"):
            raise AssertionError("A failed startup must not launch the target")
        return VirtualTransport(self, argv, limit=limit, worker=False)

    def reports(self, descriptor):
        self.channel = FailedReportChannel(descriptor, history_rows=self.history_rows)
        return self.channel

    def waitid(self, kind, pid, options):
        matches = [transport for transport in self.transports if transport.process.pid == pid]
        if len(matches) != 1:
            raise AssertionError("Foreign synthetic PID inspected")
        transport = matches[0]
        if transport.process.returncode is not None:
            raise ChildProcessError("Synthetic child already collected")
        if not transport.done:
            return None
        return SimpleNamespace(si_pid=pid, si_code=os.CLD_EXITED, si_status=0)

    def capture(self, root, guard):
        with ExitStack() as stack:
            stack.enter_context(mock.patch.object(subject, "time", self.clock))
            stack.enter_context(mock.patch.object(subject.progress, "time", self.clock))
            stack.enter_context(mock.patch.object(subject.progress, "clock", self.clock.receipt))
            stack.enter_context(mock.patch.object(subject.progress.os, "waitid", self.waitid))
            stack.enter_context(mock.patch.object(subject, "DescriptorTransport", self.worker))
            stack.enter_context(mock.patch.object(subject, "ReportChannel", self.reports))
            stack.enter_context(mock.patch.object(guard, "_scan", side_effect=AssertionError(
                "No parent census may occur during capture")))
            return subject.capture_isolated(
                "synthetic-target", ("synthetic-command",), cwd=root, env={}, guard=guard,
                test_factory=self.probe, test_budget=1.5, test_reserve=.5,
                test_worker_script=Path(__file__).with_name("native_retained_atrc_worker.py"))


class CleanupBoundsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name).resolve(strict=True)
        self.guard = legacy.OutputGuard(self.root / "observed")
        self.fixture = CleanupFixture()

    def tearDown(self):
        self.guard.close()
        self.temporary.cleanup()

    def capture(self):
        result = self.fixture.capture(self.root, self.guard)
        self.assertFalse(result.receipt["cleanupComplete"])
        self.assertFalse(result.receipt["transportComplete"])
        self.assertFalse(result._retention_allowed)
        self.assertTrue(result.receipt["workerCleanupDeadlineExceeded"])
        self.assertEqual("fixture first report failure", result.receipt["observer"]["failure"]["error"])
        self.assertIsNone(result.receipt["target"])
        self.assertEqual(1, self.fixture.channel.calls)
        self.assertTrue(self.fixture.channel.buffer)
        self.assertTrue(all(transport.closed for transport in self.fixture.transports))
        return result

    def test_failed_report_backlog_does_not_disable_cleanup_poll_sleeps(self):
        self.capture()
        self.assertGreater(sum(self.fixture.clock.sleeps), 1.5,
                           "Rejected report backlog must not keep cleanup marked busy")
        self.assertLess(len(self.fixture.clock.sleeps), 600)

    def test_unaccounted_worker_cannot_append_kill_receipt_on_every_tick(self):
        result = self.capture()
        kills = [row for row in result.receipt["worker"]["signals"]
                 if row["signal"] == signal.SIGKILL.name]
        self.assertGreaterEqual(len(kills), 1, "Owned escalation must still occur")
        self.assertEqual(len(kills), 1,
                             "Cleanup deadline/probe ticks must not append unbounded signals")

    def test_final_evidence_reports_explicit_combined_allocation(self):
        result = self.capture()
        allocation = result.receipt["workerEvidence"]
        self.assertEqual(8 * 1024 * 1024, allocation["maximumBytes"])
        self.assertEqual(4096, allocation["accountingReceiptReserveBytes"])
        self.assertEqual(subject.worker_evidence_bytes(result.receipt, result.cleanup_records),
                         allocation["retainedPayloadBytes"])
        self.assertLessEqual(allocation["retainedPayloadBytes"]
                             + allocation["accountingReceiptReserveBytes"],
                             allocation["maximumBytes"])
        self.assertEqual(0, allocation["historyRowsOmittedForByteLimit"])
        self.assertGreaterEqual(allocation["historyReceiptReserveBytes"], 1024 * 1024)

    def test_total_cap_prunes_history_but_preserves_first_failure_pending_and_cleanup(self):
        self.fixture = CleanupFixture(history_rows=64)
        with mock.patch.object(subject, "DIAGNOSTIC_BYTES", 32768):
            result = self.capture()
        allocation = result.receipt["workerEvidence"]
        self.assertEqual(32768, allocation["maximumBytes"])
        self.assertLessEqual(allocation["retainedPayloadBytes"]
                             + allocation["accountingReceiptReserveBytes"], 32768)
        self.assertGreater(allocation["historyRowsOmittedForByteLimit"], 0)
        observer = result.receipt["observer"]
        self.assertEqual("pending.bin", observer["pendingOperation"]["path"])
        self.assertEqual(observer["pendingOperation"], observer["failure"]["pendingOperation"])
        self.assertEqual(observer["pendingScan"], observer["failure"]["pendingScan"])
        history = observer["operationHistory"]
        retained_completed = sum(row["completed"] is True for row in history["records"])
        retained_failed = sum(row["completed"] is False for row in history["records"])
        self.assertEqual(32, history["completedCount"])
        self.assertEqual(32, history["failedCount"])
        self.assertEqual(32 - retained_completed, history["omittedCompletedCount"])
        self.assertEqual(32 - retained_failed, history["omittedFailedCount"])
        self.assertEqual(allocation["historyRowsOmittedForByteLimit"], 64 - len(history["records"]))
        self.assertEqual(len(self.fixture.transports), len(result.cleanup_records))
        for transport, record in zip(self.fixture.transports, result.cleanup_records):
            self.assertEqual(transport.receipt, record["receipt"])
            self.assertEqual({key: bytes(value) for key, value in transport.streams.items()},
                             record["streams"])
        self.assertIn("Combined worker diagnostic retention limit exceeded", result.receipt["errors"])

    def test_unrepresentable_fixed_receipts_fail_after_cleanup_without_returning_oversized_evidence(self):
        with mock.patch.object(subject, "DIAGNOSTIC_BYTES", 128):
            with self.assertRaisesRegex(legacy.OutputError, "Fixed worker receipts exceed"):
                self.fixture.capture(self.root, self.guard)
        self.assertIn("fixture first report failure", self.guard.failure["error"])
        self.assertTrue(self.fixture.transports)
        self.assertTrue(all(transport.closed for transport in self.fixture.transports))


class DiagnosticAccountingTests(unittest.TestCase):
    def test_accounting_includes_group_receipts_unicode_and_raw_cleanup_streams(self):
        receipt = {"observer": {}, "worker": {}, "channel": {},
                   "channelKernelBuffers": {}, "errors": [], "finalOwnedGroups": {}}
        baseline = subject.worker_evidence_bytes(receipt, [])
        expected_empty = (b'{"observer":{},"worker":{},"channel":{},'
                          b'"channelKernelBuffers":{},"errors":[],"finalOwnedGroups":{},'
                          b'"cleanupRecords":[]}')
        self.assertEqual(len(expected_empty), baseline)
        receipt["finalOwnedGroups"] = {"output-observer": {"members": [
            {"pid": 42001, "pgid": 42001, "state": "D"}]}}
        group_size = len(json.dumps(receipt["finalOwnedGroups"], separators=(",", ":")).encode())
        with_group = subject.worker_evidence_bytes(receipt, [])
        self.assertEqual(group_size - len(b"{}"), with_group - baseline)
        records = [{"name": "observer", "receipt": {"note": "ö"},
                    "streams": {"stdout": b"\xff" * 128, "stderr": b""}}]
        expected_records = ('[{"name":"observer","receipt":{"note":"ö"},'
                            '"streamBytes":{"stdout":128,"stderr":0}}]').encode("utf-8")
        self.assertEqual(len(expected_records) - len(b"[]") + 128,
                         subject.worker_evidence_bytes(receipt, records) - with_group)


if __name__ == "__main__":
    unittest.main()
