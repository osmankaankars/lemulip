#!/usr/bin/env python3
"""Independent D29 protocol contracts; no subprocess or native command.

Reports are hand-built from the agreed wire contract. Test clocks are integer
nanoseconds; expected deadlines, populations and limits are not computed by
the implementation under test.
"""
from __future__ import annotations

import copy
import json
import stat
import unittest

import native_retained_atrc_isolated as subject


NONCE = "7c8a6d0c1e494f89b9b5e6e4c8f2d3a0"
ROOT = [1, 10001, stat.S_IFDIR | 0o700]
PID = 42001
LIMITS = {"logicalBytes": 536870912, "allocatedBytes": 536870912,
          "entries": 16384, "depth": 32, "pathBytes": 1024}
EMPTY = {"logicalBytes": 0, "allocatedBytes": 4096, "entries": 1, "depth": 0}


class DecodeReportTests(unittest.TestCase):
    def test_object_round_trip_preserves_integer_nanoseconds(self):
        value = {"schema": 1, "nonce": NONCE, "seq": 1, "kind": "stopped",
                 "scan": 0, "clockNS": 1794236351870770000}
        self.assertEqual(value, subject.decode_report(json.dumps(value).encode()))

    def test_duplicate_top_level_and_nested_keys_are_rejected(self):
        for raw in (b'{"seq":1,"seq":2}', b'{"totals":{"entries":1,"entries":2}}'):
            with self.subTest(raw=raw), self.assertRaises(subject.ProtocolError):
                subject.decode_report(raw)

    def test_invalid_utf8_is_rejected(self):
        with self.assertRaises(subject.ProtocolError):
            subject.decode_report(b'{"error":"\xff"}')

    def test_nonfinite_json_constants_are_rejected(self):
        for token in (b"NaN", b"Infinity", b"-Infinity", b"1e9999"):
            with self.subTest(token=token), self.assertRaises(subject.ProtocolError):
                subject.decode_report(b'{"clockNS":' + token + b'}')

    def test_scalar_array_and_trailing_json_are_rejected(self):
        for raw in (b"null", b"true", b"1", b'"report"', b"[]", b"{}{}"):
            with self.subTest(raw=raw), self.assertRaises(subject.ProtocolError):
                subject.decode_report(raw)

    def test_oversized_frame_is_rejected(self):
        with self.assertRaises(subject.ProtocolError):
            subject.decode_report(b'{"error":"' + b"x" * 4096 + b'"}')

    def test_deeply_nested_frame_is_rejected_with_protocol_error(self):
        raw = b'{"payload":' + b"[" * 100 + b"0" + b"]" * 100 + b"}"
        self.assertLess(len(raw), 4096)
        with self.assertRaises(subject.ProtocolError):
            subject.decode_report(raw)


class ObserverStateTests(unittest.TestCase):
    def setUp(self):
        self.reset()

    def reset(self):
        self.state = subject.ObserverState(NONCE, list(ROOT), dict(LIMITS), PID)
        self.seq = 0
        self.now = 1_000_000_000
        self.generation = 0
        self.started_ns = None
        self.op_started_ns = None

    def report(self, kind, *, scan=None, clock=None, **fields):
        self.seq += 1
        self.now += 1000
        result = {"schema": 1, "nonce": NONCE, "seq": self.seq, "kind": kind,
                  "scan": self.generation if scan is None else scan,
                  "clockNS": self.now if clock is None else clock}
        result.update(fields)
        return result

    def send(self, kind, *, received=None, **fields):
        report = self.report(kind, **fields)
        self.state.accept(report, report["clockNS"] + 1 if received is None else received)
        return report

    def ready(self):
        return self.send("ready", scan=0, pid=PID, rootIdentity=list(ROOT), limits=dict(LIMITS))

    def dispatch(self):
        self.now += 60_000_000
        self.generation += 1
        request = self.state.dispatch(self.now)
        self.assertIsNotNone(self.state.pending)
        return request

    def start(self):
        report = self.send("scan_started")
        self.started_ns = report["clockNS"]
        return report

    def start_op(self, *, op=1, category="stat", path="."):
        report = self.send("op_started", op=op, category=category, path=path)
        self.op_started_ns = report["clockNS"]
        return report

    def finish_op(self, *, op=1, category="stat", path=".", outcome="ok"):
        return self.send("op_finished", op=op, category=category, path=path,
                         elapsedNS=self.now + 1000 - self.op_started_ns, outcome=outcome)

    def completed_report(self, *, totals=None, high=None, operations=1):
        totals = dict(EMPTY if totals is None else totals)
        return self.report("scan_completed", totals=totals,
                           highWater=dict(totals if high is None else high),
                           elapsedNS=self.now + 1000 - self.started_ns,
                           operationCount=operations, rootIdentity=list(ROOT))

    def complete(self, *, totals=None, high=None, operations=1):
        report = self.completed_report(totals=totals, high=high, operations=operations)
        self.state.accept(report, report["clockNS"] + 1)
        return report

    def scan(self, *, totals=None, high=None):
        self.dispatch()
        self.start()
        self.start_op()
        self.finish_op()
        return self.complete(totals=totals, high=high)

    def rejected(self, function):
        with self.assertRaises(subject.ProtocolError):
            function()
        self.assertIsNotNone(self.state.failure)

    def latch(self, function):
        # A valid terminal failure may be returned or raised by the adapter;
        # either route must latch the same first failure for the parent.
        try:
            function()
        except subject.ProtocolError:
            pass
        self.assertIsNotNone(self.state.failure)

    def test_ready_binds_child_and_root_then_one_scan_and_stop_complete(self):
        self.assertFalse(self.state.ready)
        self.ready()
        self.assertTrue(self.state.ready)
        self.scan()
        self.assertEqual(1, self.state.completed_scan)
        self.assertIsNone(self.state.pending)
        self.assertIsNone(self.state.pending_operation)
        self.assertIsNone(self.state.failure)
        # The parent arms this only after sending its explicit stop request.
        self.state.stop_requested = True
        self.send("stopped", scan=0)
        self.assertTrue(self.state.stopped)

    def test_dispatch_before_ready_is_rejected_and_latched(self):
        self.rejected(lambda: self.state.dispatch(self.now))

    def test_ready_rejects_foreign_pid_root_limits_and_boolean_identity(self):
        variants = ({"pid": PID + 1}, {"pid": True}, {"rootIdentity": [1, 10002, ROOT[2]]},
                    {"rootIdentity": [True, ROOT[1], ROOT[2]]},
                    {"limits": {**LIMITS, "entries": 16385}},
                    {"limits": {**LIMITS, "depth": True}})
        for changed in variants:
            with self.subTest(changed=changed):
                self.reset()
                report = self.report("ready", scan=0, pid=PID, rootIdentity=list(ROOT), limits=dict(LIMITS))
                report.update(changed)
                self.rejected(lambda: self.state.accept(report, self.now + 1))
                self.assertFalse(self.state.ready)

    def test_duplicate_ready_is_rejected(self):
        self.ready()
        self.rejected(self.ready)

    def test_unknown_nonce_schema_kind_and_extra_keys_are_rejected(self):
        for changed in ({"nonce": "foreign"}, {"schema": 2}, {"schema": True},
                        {"kind": "unrecognized"}, {"unexpected": 1}):
            with self.subTest(changed=changed):
                self.reset()
                report = self.report("ready", scan=0, pid=PID, rootIdentity=list(ROOT), limits=dict(LIMITS))
                report.update(changed)
                self.rejected(lambda: self.state.accept(report, self.now + 1))

    def test_sequence_gap_duplicate_and_boolean_are_rejected(self):
        for seq in (1, 3, True):
            with self.subTest(seq=seq):
                self.reset()
                self.ready()
                self.dispatch()
                report = self.report("scan_started")
                report["seq"] = seq
                self.rejected(lambda: self.state.accept(report, self.now + 1))

    def test_second_pending_dispatch_is_rejected(self):
        self.ready()
        self.dispatch()
        first = copy.deepcopy(self.state.pending)
        self.rejected(lambda: self.state.dispatch(self.now + 1))
        self.assertEqual(first, self.state.pending)

    def test_scan_generation_must_match_dispatch_and_be_integer(self):
        for scan in (0, 2, True):
            with self.subTest(scan=scan):
                self.reset()
                self.ready()
                self.dispatch()
                report = self.report("scan_started", scan=scan)
                self.rejected(lambda: self.state.accept(report, self.now + 1))

    def test_completion_requires_scan_started(self):
        self.ready()
        self.dispatch()
        self.started_ns = self.now
        report = self.completed_report(operations=0)
        self.rejected(lambda: self.state.accept(report, self.now + 1))

    def test_completion_cannot_hide_pending_operation(self):
        self.ready()
        self.dispatch()
        self.start()
        self.start_op()
        pending = copy.deepcopy(self.state.pending_operation)
        report = self.completed_report()
        self.rejected(lambda: self.state.accept(report, self.now + 1))
        self.assertEqual(pending, self.state.pending_operation)
        self.assertEqual(0, self.state.completed_scan)

    def test_operation_end_requires_matching_start_identity(self):
        for changed in ({"op": 2}, {"category": "fstat"}, {"path": "other"},
                        {"op": True}, {"outcome": "assumed-ok"}):
            with self.subTest(changed=changed):
                self.reset()
                self.ready()
                self.dispatch()
                self.start()
                self.start_op()
                report = self.report("op_finished", op=1, category="stat", path=".",
                                     elapsedNS=1000, outcome="ok")
                report.update(changed)
                self.rejected(lambda: self.state.accept(report, self.now + 1))

    def test_operation_finish_without_start_and_second_start_are_rejected(self):
        for second_start in (False, True):
            with self.subTest(second_start=second_start):
                self.reset()
                self.ready()
                self.dispatch()
                self.start()
                if second_start:
                    self.start_op()
                    self.rejected(lambda: self.start_op(op=2))
                else:
                    report = self.report("op_finished", op=1, category="stat", path=".",
                                         elapsedNS=1, outcome="ok")
                    self.rejected(lambda: self.state.accept(report, self.now + 1))

    def test_operation_category_and_relative_paths_are_bounded(self):
        variants = ({"category": "read-private-file"}, {"path": "/absolute"},
                    {"path": "../escape"}, {"path": "a/../escape"}, {"path": "a\\b"},
                    {"path": "a\0b"}, {"path": "x" * 1025})
        for changed in variants:
            with self.subTest(changed=changed):
                self.reset()
                self.ready()
                self.dispatch()
                self.start()
                report = self.report("op_started", op=1, category="stat", path=".")
                report.update(changed)
                self.rejected(lambda: self.state.accept(report, self.now + 1))

    def test_report_clock_rejects_boolean_negative_future_and_backward_values(self):
        for clock in (True, -1, 9_000_000_000, 0):
            with self.subTest(clock=clock):
                self.reset()
                self.ready()
                self.dispatch()
                report = self.report("scan_started", clock=clock)
                self.rejected(lambda: self.state.accept(report, self.now + 1))

    def test_operation_elapsed_must_match_start_end_clocks(self):
        for elapsed in (True, -1, 0, 1001):
            with self.subTest(elapsed=elapsed):
                self.reset()
                self.ready()
                self.dispatch()
                self.start()
                self.start_op()
                report = self.report("op_finished", op=1, category="stat", path=".",
                                     elapsedNS=elapsed, outcome="ok")
                self.rejected(lambda: self.state.accept(report, self.now + 1))

    def test_scan_elapsed_and_operation_count_must_match_observed_lifecycle(self):
        for changed in ({"elapsedNS": True}, {"elapsedNS": 0}, {"operationCount": True},
                        {"operationCount": 0}, {"operationCount": 2}):
            with self.subTest(changed=changed):
                self.reset()
                self.ready()
                self.dispatch()
                self.start()
                self.start_op()
                self.finish_op()
                report = self.completed_report()
                report.update(changed)
                self.rejected(lambda: self.state.accept(report, self.now + 1))

    def test_completed_totals_reject_boolean_negative_and_exceeded_limits(self):
        variants = ({"entries": True}, {"entries": 0}, {"entries": 16385}, {"depth": 33},
                    {"logicalBytes": -1}, {"logicalBytes": 536870913},
                    {"allocatedBytes": 536870913})
        for changed in variants:
            with self.subTest(changed=changed):
                self.reset()
                self.ready()
                self.dispatch()
                self.start()
                self.start_op()
                self.finish_op()
                report = self.completed_report(totals={**EMPTY, **changed})
                self.rejected(lambda: self.state.accept(report, self.now + 1))

    def test_completion_binds_root_identity_again(self):
        self.ready()
        self.dispatch()
        self.start()
        self.start_op()
        self.finish_op()
        report = self.completed_report()
        report["rootIdentity"] = [1, 10002, ROOT[2]]
        self.rejected(lambda: self.state.accept(report, self.now + 1))

    def test_high_water_cannot_fall_below_totals_or_previous_high_water(self):
        for previous in (False, True):
            with self.subTest(previous=previous):
                self.reset()
                self.ready()
                larger = {**EMPTY, "logicalBytes": 10, "entries": 2, "depth": 1}
                if previous:
                    self.scan(totals=larger)
                self.dispatch()
                self.start()
                self.start_op()
                self.finish_op()
                report = self.completed_report(totals=EMPTY if previous else larger, high=EMPTY)
                self.rejected(lambda: self.state.accept(report, self.now + 1))

    def test_completed_scan_cannot_report_out_of_bounds_high_water(self):
        for changed in ({"entries": 16385}, {"depth": 33}, {"logicalBytes": 536870913},
                        {"allocatedBytes": 536870913}):
            with self.subTest(changed=changed):
                self.reset()
                self.ready()
                self.dispatch()
                self.start()
                self.start_op()
                self.finish_op()
                report = self.completed_report(high={**EMPTY, **changed})
                self.rejected(lambda: self.state.accept(report, self.now + 1))

    def test_completed_scan_cannot_erase_a_reported_operation_error(self):
        self.ready()
        self.dispatch()
        self.start()
        self.start_op()
        try:
            self.finish_op(outcome="error")
        except subject.ProtocolError:
            pass
        report = self.completed_report()
        self.rejected(lambda: self.state.accept(report, self.now + 1))
        self.assertEqual(0, self.state.completed_scan)
        self.assertEqual(1, self.state.summary()["operationHistory"]["failedCount"])

    def test_smaller_second_inventory_may_preserve_prior_high_water(self):
        self.ready()
        larger = {**EMPTY, "logicalBytes": 10, "entries": 2, "depth": 1}
        self.scan(totals=larger)
        self.scan(totals=EMPTY, high=larger)
        self.assertEqual(2, self.state.completed_scan)
        self.assertIsNone(self.state.failure)

    def test_pending_deadline_is_250_milliseconds_and_not_reset_by_progress(self):
        self.ready()
        self.dispatch()
        dispatched = self.now
        self.start()
        self.start_op()
        self.state.check_deadline(dispatched + 249_999_999)
        self.assertIsNone(self.state.failure)
        self.rejected(lambda: self.state.check_deadline(dispatched + 250_000_000))
        self.assertIsNotNone(self.state.pending_operation)

    def test_queued_completion_received_late_cannot_restore_success(self):
        self.ready()
        self.dispatch()
        dispatched = self.now
        self.start()
        self.start_op()
        self.finish_op()
        report = self.completed_report()
        self.assertLess(report["clockNS"], dispatched + 250_000_000)
        self.rejected(lambda: self.state.accept(report, dispatched + 250_000_001))
        self.assertEqual(0, self.state.completed_scan)

    def test_no_pending_scan_has_no_fabricated_deadline_failure(self):
        self.ready()
        self.state.check_deadline(self.now + 10_000_000_000)
        self.assertIsNone(self.state.failure)

    def test_first_failure_and_pending_operation_survive_later_failures(self):
        self.ready()
        self.dispatch()
        self.start()
        self.start_op()
        pending = copy.deepcopy(self.state.pending_operation)
        self.latch(lambda: self.state.fail("first controlled failure", self.now + 1))
        failure = copy.deepcopy(self.state.failure)
        self.latch(lambda: self.state.fail("later failure", self.now + 2))
        self.assertEqual(failure, self.state.failure)
        self.assertEqual(pending, self.state.pending_operation)
        self.rejected(lambda: self.state.dispatch(self.now + 3))
        self.assertEqual(failure, self.state.failure)

    def test_stopped_message_cannot_clear_pending_scan_or_failure(self):
        self.ready()
        self.dispatch()
        report = self.report("stopped", scan=0)
        self.rejected(lambda: self.state.accept(report, self.now + 1))
        failure = copy.deepcopy(self.state.failure)
        self.latch(lambda: self.state.fail("worker exited zero afterward", self.now + 2))
        self.assertEqual(failure, self.state.failure)

    def test_bounded_scan_and_operation_histories_count_completed_and_failed_separately(self):
        self.ready()
        for _ in range(324):
            self.scan()
        self.dispatch()
        self.start()
        failed = self.report("scan_failed", error="controlled final scan failure", highWater=dict(EMPTY),
                             elapsedNS=1000, operationCount=0)
        self.latch(lambda: self.state.accept(failed, self.now + 1))
        summary = self.state.summary()
        scans, operations = summary["scanHistory"], summary["operationHistory"]
        self.assertEqual(324, scans["completedCount"])
        self.assertEqual(1, scans["failedCount"])
        self.assertEqual(256, len(scans["records"]))
        self.assertEqual(69, scans["omittedCompletedCount"])
        self.assertEqual(0, scans["omittedFailedCount"])
        self.assertEqual(324, operations["completedCount"])
        self.assertEqual(0, operations["failedCount"])
        self.assertEqual(256, len(operations["records"]))
        self.assertEqual(68, operations["omittedCompletedCount"])
        self.assertEqual(0, operations["omittedFailedCount"])
        self.assertLessEqual(len(json.dumps(summary).encode()), 8388608)
        self.assertEqual(324, self.state.completed_scan)


if __name__ == "__main__":
    unittest.main()
