#!/usr/bin/env python3
"""D28 deterministic observer-boundary tests; no native commands or real sleeps.

The filesystem is real and disposable. Only elapsed time, the transport factory,
and waitid's process boundary are synthetic. OutputGuard, capture_import,
OwnedCommand, and group-inventory parsing remain the production implementation.
"""
from __future__ import annotations

from contextlib import ExitStack
from pathlib import Path
import os
import signal
from types import SimpleNamespace
import tempfile
import unittest
from unittest import mock

import native_retained_atrc_output as subject


class VirtualClock:
    def __init__(self):
        self.nanoseconds = 0
        self.events = []

    def monotonic(self):
        return self.nanoseconds / 1_000_000_000

    def sleep(self, seconds):
        self.nanoseconds += round(seconds * 1_000_000_000)

    def snapshot(self):
        return {"monotonicBeforeNS": self.nanoseconds,
                "wallTimeNS": 1_700_000_000_000_000_000 + self.nanoseconds,
                "monotonicAfterNS": self.nanoseconds}

    def event(self, kind, pid=None):
        self.events.append({"kind": kind, "time": self.monotonic(), "pid": pid})


class SyntheticTransport:
    """Transport seam only: TERM is ignored; KILL terminates a still-live child."""
    def __init__(self, clock, pid, argv, limit, *, output=b"", output_at=0,
                 exit_at=None, exit_code=0):
        self.clock, self.started = clock, clock.monotonic()
        self.process = SimpleNamespace(pid=pid, returncode=None)
        self.pending, self.output_at = output, output_at
        self.exit_at, self.exit_code, self.forced_exit = exit_at, exit_code, None
        self.streams = {"stdout": bytearray(), "stderr": bytearray()}
        self.streams_open, self.closed, self.reap_deferred = True, False, False
        self.selector = SimpleNamespace(get_map=lambda: {"stdout": True} if self.streams_open else {})
        self.receipt = {"argv": list(argv), "pid": pid, "status": "running", "exitCode": None,
                        "maximumCombinedBytes": limit, "observedBytes": 0, "retainedBytes": 0,
                        "stopReason": None, "signals": [], "signalErrors": [],
                        "streamErrors": [], "cleanupFailed": False}

    def state(self):
        if self.forced_exit is not None:
            return self.forced_exit
        return self.exit_code if self.exit_at is not None and self.clock.monotonic() >= self.exit_at else None

    def drain(self):
        self.clock.event("drain", self.process.pid)
        if self.pending and self.clock.monotonic() >= self.output_at:
            self.streams["stdout"].extend(self.pending)
            self.receipt["observedBytes"] += len(self.pending)
            self.receipt["retainedBytes"] += len(self.pending)
            self.pending = b""
        if self.state() is not None:
            self.streams_open = False

    def signal(self, sig, *, group=False):
        assert group and self.process.returncode is None, "Signal requires an unreaped synthetic owner"
        self.clock.event(sig.name, self.process.pid)
        self.receipt["signals"].append({"signal": sig.name, "target": "owned-group",
                                        "afterSeconds": self.clock.monotonic() - self.started})
        if sig == signal.SIGKILL and self.state() is None:
            self.forced_exit = -signal.SIGKILL
        return True

    def poll(self):
        assert not self.reap_deferred
        self.clock.event("collect", self.process.pid)
        self.process.returncode = self.state()
        return self.process.returncode

    def close(self):
        self.closed = True
        self.receipt["elapsedSeconds"] = self.clock.monotonic() - self.started


class ObserverBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name).resolve(strict=True)
        self.clock = VirtualClock()
        self.patches = ExitStack()
        self.patches.enter_context(mock.patch.object(subject, "time", self.clock))
        self.patches.enter_context(mock.patch.object(subject.progress, "time", self.clock))
        self.patches.enter_context(mock.patch.object(subject.progress, "clock", self.clock.snapshot))
        self.guards, self.transports = [], []
        self.witness = {"evidenceKind": "deterministic-synthetic-observer-test"}

    def tearDown(self):
        self.patches.close()
        for guard in self.guards:
            guard.close()
        self.temporary.cleanup()

    def guard(self):
        guard = subject.OutputGuard(self.root / ("output-" + str(len(self.guards))))
        self.guards.append(guard)
        return guard

    def scan_witness(self, guard):
        summary = guard.summary()
        return {"observation": summary["observations"][-1],
                "failure": summary["failure"], "completedScanCount": summary["completedScanCount"],
                "highWaterObserved": summary["highWaterObserved"]}

    def test_late_metadata_return_preserves_partial_high_water_and_skips_retention(self):
        guard = self.guard()
        (guard.root / "payload.bin").write_bytes(b"payload")
        previous = guard.last_scan
        original_stat, calls = subject.os.stat, 0

        def delayed_final_anchor(*args, **kwargs):
            nonlocal calls
            if args[0] == guard.root:
                calls += 1
                if calls == 2:
                    self.clock.sleep(.6)
            return original_stat(*args, **kwargs)

        with mock.patch.object(subject.os, "stat", side_effect=delayed_final_anchor):
            self.assertFalse(guard.sample(force=True))
        latest = guard.summary()["observations"][-1]
        self.assertEqual(2, calls)
        self.assertAlmostEqual(.6, latest["elapsedSeconds"])
        self.assertAlmostEqual(.35, latest["scanDeadlineOvershootSeconds"])
        self.assertFalse(latest["completed"])
        self.assertNotIn("entries", latest)
        self.assertNotIn("logicalBytes", latest)
        self.assertIs(previous, guard.last_scan)
        self.assertEqual(1, guard.scan_count)
        self.assertEqual(2, guard.high_water["entries"])
        self.assertEqual(7, guard.high_water["logicalBytes"])
        observed_count = len(guard.summary()["observations"])
        with mock.patch.object(guard, "_scan", side_effect=AssertionError("Failed observer must not read again")):
            self.assertFalse(guard.sample(force=True))
            retained = guard.finalize(self.root / "output.zip", safe_to_read=True)
        self.assertEqual(observed_count, len(guard.summary()["observations"]))
        self.assertEqual("skipped-output-observation-failed", retained["status"])
        self.assertEqual(0, retained["retentionElapsedSeconds"])
        self.assertFalse(retained["retentionComplete"])
        self.assertFalse((self.root / "output.zip").exists())
        self.witness.update(self.scan_witness(guard), retentionStatus=retained["status"],
                            retentionElapsedSeconds=retained["retentionElapsedSeconds"])

    def test_metadata_delay_and_between_call_pause_have_identical_aggregate_scan_timing(self):
        outcomes = []
        for boundary in ("metadata-call", "between-calls"):
            with self.subTest(boundary=boundary):
                self.clock.nanoseconds = 0
                guard = self.guard()
                original_stat, original_check = subject.os.stat, subject._clock_check
                delayed = False

                def stat(*args, **kwargs):
                    nonlocal delayed
                    if args[0] == guard.root and not delayed:
                        delayed = True
                        self.clock.sleep(.6)
                    return original_stat(*args, **kwargs)

                def scheduled_check(deadline):
                    nonlocal delayed
                    if not delayed:
                        delayed = True
                        self.clock.sleep(.6)
                    return original_check(deadline)

                patch = (mock.patch.object(subject.os, "stat", side_effect=stat)
                         if boundary == "metadata-call" else
                         mock.patch.object(subject, "_clock_check", side_effect=scheduled_check))
                with patch:
                    self.assertFalse(guard.sample(force=True))
                self.assertTrue(delayed)
                outcomes.append(self.scan_witness(guard))
        self.assertEqual(outcomes[0], outcomes[1])
        self.witness.update(indistinguishableAggregateWitness=outcomes[0],
                            injectedBoundaries=["metadata-call", "between-calls"],
                            actualNativeDelayAttributed=False)

    def capture_delayed(self, *, budget=2.0, reserve=.5, exit_at=None):
        guard = self.guard()
        original_stat = subject.os.stat
        delay = {}

        def factory(name, argv, *, cwd, env, limit):
            pid = 42000 + len(self.transports)
            if not self.transports:
                (guard.root / "pending.bin").write_bytes(b"synthetic")
                transport = SyntheticTransport(self.clock, pid, argv, limit, output=b"ready\n",
                                               output_at=.1, exit_at=exit_at)
            else:
                target = self.transports[0]
                self.assertIsNone(target.process.returncode)
                self.clock.event("group-snapshot", target.process.pid)
                state = "Z" if target.state() is not None else "S"
                row = f"{target.process.pid} {target.process.pid} {state}\n".encode("ascii")
                transport = SyntheticTransport(self.clock, pid, argv, limit, output=row,
                                               exit_at=self.clock.monotonic())
            self.transports.append(transport)
            return transport

        def waitid(kind, pid, flags):
            self.assertEqual(os.P_PID, kind)
            self.assertEqual(os.WEXITED | os.WNOHANG | os.WNOWAIT, flags)
            transport = next(item for item in self.transports if item.process.pid == pid)
            self.assertIsNone(transport.process.returncode)
            self.clock.event("peek", pid)
            code = transport.state()
            if code is None:
                return None
            return SimpleNamespace(si_pid=pid, si_code=os.CLD_EXITED if code >= 0 else os.CLD_KILLED,
                                   si_status=code if code >= 0 else -code)

        def delayed_stat(*args, **kwargs):
            if args[0] == "pending.bin" and kwargs.get("dir_fd") == guard.fd and not delay:
                delay["begin"] = self.clock.monotonic()
                self.clock.event("metadata-enter")
                self.clock.sleep(.6)
                delay["end"] = self.clock.monotonic()
                self.clock.event("metadata-return")
            return original_stat(*args, **kwargs)

        with mock.patch.object(subject.os, "stat", side_effect=delayed_stat), \
                mock.patch.object(subject.progress.os, "waitid", side_effect=waitid):
            receipt, streams, probes = subject.capture_import(
                "synthetic-import", ("synthetic-import",), cwd=self.root, env={}, guard=guard,
                test_factory=factory, test_budget=budget, test_reserve=reserve)
        self.assertEqual(.05, delay["begin"])
        self.assertAlmostEqual(.65, delay["end"])
        target_pid = self.transports[0].process.pid
        supervision = [event for event in self.clock.events
                       if event["pid"] == target_pid and event["kind"] in ("drain", "peek")]
        self.assertFalse([event for event in supervision if delay["begin"] < event["time"] <= delay["end"]])
        after = next(event for event in supervision if event["time"] > delay["end"])
        self.assertEqual("drain", after["kind"])
        self.assertAlmostEqual(.655, after["time"])
        self.assertEqual(b"ready\n", streams["stdout"])
        self.assertFalse(receipt["transportComplete"])
        self.assertEqual("derived-output-observation-failed", receipt["stopReason"])
        self.assertFalse(receipt["synchronousFilesystemCallsHaveHardDeadline"])
        self.assertTrue(receipt["pidLeaseReleased"])
        self.assertTrue(all(item.process.returncode is not None for item in self.transports))
        self.witness.update(delay=delay, firstResumedSupervision=after,
                            signals=receipt["signals"], stopReason=receipt["stopReason"],
                            exitCode=receipt["exitCode"], cleanupComplete=receipt["cleanupComplete"],
                            transportComplete=receipt["transportComplete"],
                            normalDeadlineOvershootSeconds=receipt["normalDeadlineOvershootSeconds"],
                            totalDeadlineOvershootSeconds=receipt["totalDeadlineOvershootSeconds"],
                            operationElapsedSeconds=receipt["operationElapsedSeconds"],
                            completionObservedWithinTotalBudget=receipt["completionObservedWithinTotalBudget"],
                            lifecycleEvents=[event for event in self.clock.events
                                             if event["kind"] not in ("drain", "peek")],
                            observation=guard.summary()["observations"][-1])
        return receipt, probes

    def test_synchronous_scan_defers_supervision_then_preserves_owned_cleanup(self):
        receipt, probes = self.capture_delayed()
        self.assertTrue(receipt["cleanupComplete"])
        self.assertEqual(-9, receipt["exitCode"])
        self.assertEqual(["SIGTERM", "SIGKILL"], [item["signal"] for item in receipt["signals"]])
        term, kill = (item["afterSeconds"] for item in receipt["signals"])
        self.assertAlmostEqual(.65, term)
        self.assertGreaterEqual(kill - term, subject.TERM_GRACE)
        self.assertTrue(receipt["completionObservedWithinTotalBudget"])
        self.assertFalse(receipt["emergencyCleanupRequired"])
        self.assertEqual(1, len(probes))
        self.assertTrue(receipt["finalOwnedGroups"]["synthetic-import"]["pidLeaseHeldAtSnapshot"])

    def test_scan_crossing_total_deadline_cannot_pass_after_late_collection(self):
        receipt, probes = self.capture_delayed(budget=.5, reserve=.1)
        self.assertFalse(receipt["cleanupComplete"])
        self.assertFalse(receipt["completionObservedWithinTotalBudget"])
        self.assertAlmostEqual(.25, receipt["normalDeadlineOvershootSeconds"])
        self.assertAlmostEqual(.155, receipt["totalDeadlineOvershootSeconds"])
        self.assertTrue(receipt["emergencyCleanupRequired"])
        self.assertIn("completion-not-observed-within-total-budget", receipt["cleanupFailureReasons"])
        self.assertEqual(2, len(probes))

    def test_exit_zero_during_scan_does_not_erase_observer_failure(self):
        receipt, _ = self.capture_delayed(exit_at=.1)
        self.assertEqual(0, receipt["exitCode"])
        self.assertTrue(receipt["cleanupComplete"])
        self.assertAlmostEqual(.655, receipt["exitObservedAfterSeconds"])
        self.assertFalse(receipt["outputBoundsPass"])
        self.witness.update(syntheticNaturalExitAt=.1,
                            exitObservedAfterSeconds=receipt["exitObservedAfterSeconds"])


if __name__ == "__main__":
    unittest.main()
