#!/usr/bin/env python3
"""D30 classifier tests over explicitly synthetic retained receipt fixtures.

No subprocess, Apple tool, process-group query or OS signal is executed here.
The independent rows encode the claimed event order and raw ps evidence; the
classifier must reject contradictory or missing witnesses.
"""
from __future__ import annotations

import json
import unittest

import isolated_atrc_macos_fixture as fixture
import run_isolated_atrc_macos_qualification as subject

BASE = 1_000_000_000
TARGET = 101
WORKER = 102
CHILD = 104
ROOT_IDENTITY = [27, 1000, 16832]


def clock(offset):
    return {"monotonicBeforeNS": BASE + offset,
            "wallTimeNS": 1_800_000_000_000_000_000 + offset,
            "monotonicAfterNS": BASE + offset + 10}


def command(pid, *, code=0, done=180_000_000, collected=210_000_000):
    return {
        "pid": pid, "status": "exited", "exitCode": code, "stopReason": None,
        "pidLeaseAcquired": True, "pidLeaseReleased": True, "pidLeaseLost": False,
        "pidDirectedActionsRevoked": True, "exitObservedWithoutReap": True,
        "inheritedStreamsStillOpen": False, "streamErrors": [], "signalErrors": [],
        "cleanupFailed": False, "cleanupFailureReasons": [],
        "signals": [], "operationTerminalClock": clock(done - 100),
        "operationDoneClock": clock(done), "collectedClock": clock(collected),
        "collectionStartedClock": clock(collected - 100),
        "clockBeforeSpawn": clock(2_990_000), "clockAtSpawn": clock(3_000_000),
        "completionObservedWithinTotalBudget": True,
        "normalOperationBudgetSeconds": 3.0, "totalBudgetSeconds": 5.0,
        "normalDeadlineOvershootSeconds": 0.0, "totalDeadlineOvershootSeconds": 0.0,
        "streamProgress": [], "observedBytes": 0, "retainedBytes": 0,
        "argv": ["python3", "fixed-fixture.py"], "intendedArgv": ["python3", "fixed-fixture.py"],
    }


def scan(generation, dispatch, completion, *, entries=7, logical=None):
    if logical is None:
        logical = sum(map(len, fixture.EXPECTED_FILES.values()))
    totals = {"entries": entries, "depth": 2 if entries > 1 else 0,
              "logicalBytes": logical, "allocatedBytes": 28672 if entries > 1 else 4096}
    return {"completed": True,
            "request": {"scan": generation, "dispatchedNS": BASE + dispatch,
                        "deadlineNS": BASE + dispatch + 250_000_000, "started": True,
                        "workerStartedNS": BASE + dispatch + 100,
                        "lastOperation": 7},
            "report": {"schema": 1, "nonce": "0" * 32, "kind": "scan_completed",
                       "scan": generation, "seq": generation * 20,
                       "clockNS": BASE + completion,
                       "elapsedNS": completion - dispatch - 100, "operationCount": 7,
                       "totals": totals, "highWater": totals,
                       "rootIdentity": ROOT_IDENTITY},
            "receivedNS": BASE + completion + 20}


def group(pid, *, state="Z"):
    return {"pgid": pid, "pidLeaseHeldAtSnapshot": True,
            "members": [{"pid": pid, "pgid": pid, "state": state}],
            "noLiveMembersObserved": state.startswith("Z")}


def signal_row(name, pid, after):
    return {"signal": name, "target": "owned-group",
            "afterSeconds": after}


def probe(name, pid, rows, at=190_000_000):
    receipt = command(pid, done=at + 1_000_000, collected=at + 5_000_000)
    receipt["clockBeforeSpawn"] = clock(at - 1000)
    receipt["clockAtSpawn"] = clock(at + 1000)
    receipt["argv"] = receipt["intendedArgv"] = ["/bin/ps", "-A", "-o", "pid=,pgid=,stat="]
    raw = "".join(f"{p} {pg} {state}\n" for p, pg, state in rows).encode("ascii")
    receipt["observedBytes"] = receipt["retainedBytes"] = len(raw)
    return {"name": name, "receipt": receipt,
            "streams": {"stdout": raw, "stderr": b""}}


def probe_observation(name, at=190_000_000):
    return {"probeName": name,
            "children": [{"role": role, "pid": pid, "pgid": pid, "waitable": True,
                          "returncodeBeforeProbe": None, "observedClockNS": BASE + at}
                         for role, pid in (("target", TARGET), ("worker", WORKER))]}


def successful_fixture():
    target = command(TARGET, done=160_000_000)
    worker = command(WORKER, done=180_000_000)
    worker["clockBeforeSpawn"] = clock(0)
    worker["clockAtSpawn"] = clock(10)
    target["streamProgress"] = [{"clock": clock(159_000_000),
                                 "observedBytes": len(fixture.SUCCESS_STDOUT),
                                 "stdoutBytes": len(fixture.SUCCESS_STDOUT), "stderrBytes": 0}]
    target["observedBytes"] = target["retainedBytes"] = len(fixture.SUCCESS_STDOUT)
    scans = [scan(1, 1_000_000, 2_000_000, entries=1, logical=0),
             scan(2, 50_000_000, 51_000_000),
             scan(3, 165_000_000, 166_000_000)]
    operation_rows = []
    for index, category in enumerate(
            ("stat", "fstat", "open", "close", "scandir", "scandir_next", "scandir_close"), 1):
        start = {"schema": 1, "nonce": "0" * 32, "kind": "op_started",
                 "seq": index * 2, "scan": 2, "op": index, "category": category,
                 "path": ".", "clockNS": BASE + 50_100_000 + index * 100}
        end = dict(start, kind="op_finished", seq=index * 2 + 1,
                   clockNS=start["clockNS"] + 10, elapsedNS=10, outcome="ok")
        operation_rows.append({"completed": True, "started": start, "ended": end})
    receipt = {
        "schema": 1, "adapter": "D29-isolated-atrc-observer", "testControlsUsed": True,
        "startupComplete": True, "initialScanGeneration": 1, "finalScanGeneration": 3,
        "finalFreshScanComplete": True, "observationComplete": True,
        "cleanupComplete": True, "transportComplete": True,
        "targetCleanupComplete": True, "workerCleanupComplete": True,
        "workerCleanupDeadlineExceeded": False,
        "workerCleanupBudgetSeconds": 2.0, "workerCleanupElapsedSeconds": 0.03,
        "workerCleanupDeadlineOvershootSeconds": 0.0,
        "target": target, "worker": worker,
        "finalOwnedGroups": {"target": group(TARGET), "output-observer": group(WORKER)},
        "observer": {"schema": 1, "ready": True, "stopped": True,
                     "sequence": 60, "generation": 3, "lastCompletedScan": 3,
                     "lastCompleteCensus": scans[-1]["report"], "rootIdentity": ROOT_IDENTITY,
                     "workerPID": WORKER, "failure": None, "pendingScan": None,
                     "pendingOperation": None, "highWaterObserved": scans[-1]["report"]["highWater"],
                     "scanHistory": {"records": scans, "completedCount": 3, "failedCount": 0,
                                     "omittedCompletedCount": 0, "omittedFailedCount": 0},
                     "operationHistory": {"records": operation_rows, "completedCount": 7,
                                          "failedCount": 0, "omittedCompletedCount": 0,
                                          "omittedFailedCount": 0}},
        "channel": {"EOF": True, "undecodedBytes": 0},
        "channelKernelBuffers": {"reportSendBufferBytes": 16384, "reportReceiveBufferBytes": 16384},
        "workerEvidence": {"maximumBytes": 8388608, "retainedPayloadBytes": 25000,
                           "accountingReceiptReserveBytes": 4096,
                           "historyRowsOmittedForByteLimit": 0},
        "errors": [], "parentCensusDuringCommandSupervision": False,
        "nativeTraceSemanticsEstablished": False,
    }
    records = [{"name": "output-observer", "receipt": worker,
                "streams": {"stdout": b"", "stderr": b""}},
               probe("groups-initial", 103, [(1, 1, "S"), (TARGET, TARGET, "Z"),
                                              (WORKER, WORKER, "Z")])]
    controls = {"probeLeaseObservations": [probe_observation("groups-initial")]}
    retention = {
        "status": "output-retained", "retentionComplete": True, "inventoryComplete": True,
        "newAnalysisDocumentObserved": True, "semanticAnalysisValidityEstablished": False,
        "archive": {"sha256": "a" * 64, "crcAndSHA256Verified": True},
        "payloadVerification": {"exactPayloads": True, "crcValid": True,
                                "sha256Matches": True, "originalsPreserved": True},
    }
    return receipt, {"stdout": fixture.SUCCESS_STDOUT, "stderr": b""}, records, controls, retention


def denied_retention():
    return {"status": "skipped-output-observation-failed", "retentionComplete": False,
            "newAnalysisDocumentObserved": False, "semanticAnalysisValidityEstablished": False,
            "archive": None}


def pending_fixture(*, deadline=False):
    receipt, streams, records, controls, _ = successful_fixture()
    pending_scan = {"scan": 3, "dispatchedNS": BASE + 55_000_000,
                    "deadlineNS": BASE + 305_000_000, "started": True}
    pending_op = {"schema": 1, "nonce": "0" * 32, "seq": 21, "kind": "op_started",
                  "scan": 3, "op": 1, "category": "stat", "path": "stall.bin",
                  "clockNS": BASE + 60_000_000}
    failure = {"code": "isolated-observation-failed",
               "error": "Census completion not observed within parent dispatch budget",
               "parentClockNS": BASE + 305_100_000,
               "pendingScan": pending_scan, "pendingOperation": pending_op}
    receipt.update(finalScanGeneration=None, finalFreshScanComplete=False,
                   observationComplete=False, transportComplete=False,
                   errors=[failure["error"]], workerCleanupElapsedSeconds=0.295)
    receipt["observer"].update(stopped=False, failure=failure, pendingScan=pending_scan,
                               pendingOperation=pending_op, generation=3, lastCompletedScan=2)
    receipt["worker"].update(exitCode=-15, stopReason="observation-failed",
                             operationTerminalClock=clock(307_000_000),
                             operationDoneClock=clock(556_000_000),
                             collectionStartedClock=clock(599_999_900),
                             collectedClock=clock(600_000_000))
    receipt["worker"]["signals"] = [signal_row("SIGTERM", WORKER, .306),
                                      signal_row("SIGKILL", WORKER, .556)]
    target = receipt["target"]
    target.update(operationTerminalClock=clock(70_000_000), operationDoneClock=clock(70_100_000),
                  collectionStartedClock=clock(599_999_900),
                  collectedClock=clock(600_000_000))
    target["streamProgress"] = [{"clock": clock(65_000_000),
                                 "observedBytes": len(fixture.PENDING_EXIT_STDOUT),
                                 "stdoutBytes": len(fixture.PENDING_EXIT_STDOUT), "stderrBytes": 0}]
    target["observedBytes"] = target["retainedBytes"] = len(fixture.PENDING_EXIT_STDOUT)
    controls["workerMarker"] = {"pid": WORKER, "monotonicNS": BASE + 61_000_000}
    records[-1] = probe("groups-initial", 103, [(1, 1, "S"), (TARGET, TARGET, "Z"),
                                               (WORKER, WORKER, "Z")], at=580_000_000)
    controls["probeLeaseObservations"] = [probe_observation("groups-initial", at=580_000_000)]
    if deadline:
        target.update(exitCode=-15, stopReason="command-budget",
                      stopRequestedClock=clock(154_000_000),
                      operationTerminalClock=clock(155_000_000),
                      operationDoneClock=clock(404_000_000),
                      normalOperationBudgetSeconds=.15, totalBudgetSeconds=.5)
        target["signals"] = [signal_row("SIGTERM", TARGET, .151),
                              signal_row("SIGKILL", TARGET, .401)]
        target["streamProgress"] = []
        target["observedBytes"] = target["retainedBytes"] = 0
        streams = {"stdout": b"", "stderr": b""}
    else:
        streams = {"stdout": fixture.PENDING_EXIT_STDOUT, "stderr": b""}
    return receipt, streams, records, controls, denied_retention()


def stopped_worker_fixture():
    receipt, streams, records, controls, _ = successful_fixture()
    receipt["worker"]["exitCode"] = 7
    receipt.update(observationComplete=False, transportComplete=False,
                   errors=["Observer did not exit successfully after acknowledged shutdown"])
    receipt["observer"]["failure"] = {
        "code": "isolated-observation-failed",
        "error": "Observer did not exit successfully after acknowledged shutdown",
        "parentClockNS": BASE + 220_000_000, "pendingScan": None, "pendingOperation": None}
    return receipt, streams, records, controls, denied_retention()


def descendant_fixture():
    receipt, _, records, controls, _ = successful_fixture()
    target = receipt["target"]
    target.update(stopReason="unaccounted-owned-group", stopRequestedClock=clock(250_000_000),
                  collectionStartedClock=clock(599_999_900),
                  collectedClock=clock(600_000_000))
    target["signals"] = [signal_row("SIGTERM", TARGET, .247),
                          signal_row("SIGKILL", TARGET, .497)]
    receipt["worker"]["collectedClock"] = clock(600_000_000)
    receipt["worker"]["collectionStartedClock"] = clock(599_999_900)
    receipt["worker"]["stopReason"] = "observation-failed"
    receipt["worker"]["signals"] = [signal_row("SIGTERM", WORKER, .250)]
    receipt.update(observationComplete=False, transportComplete=False,
                   errors=["Original cleanup did not establish both owned groups"])
    receipt["observer"]["failure"] = {
        "code": "isolated-observation-failed",
        "error": "Original cleanup did not establish both owned groups",
        "parentClockNS": BASE + 240_000_000, "pendingScan": None, "pendingOperation": None}
    initial = probe("groups-initial", 103,
                    [(1, 1, "S"), (TARGET, TARGET, "Z"), (WORKER, WORKER, "Z"),
                     (CHILD, TARGET, "S")], at=230_000_000)
    final = probe("groups-after-stop", 105,
                  [(1, 1, "S"), (TARGET, TARGET, "Z"), (WORKER, WORKER, "Z")],
                  at=580_000_000)
    records[:] = [records[0], initial, final]
    controls["probeLeaseObservations"] = [
        probe_observation("groups-initial", at=230_000_000),
        probe_observation("groups-after-stop", at=580_000_000)]
    controls["descendant"] = {"pid": CHILD, "pgid": TARGET, "readyNS": BASE + 150_000_000,
                               "ready": True, "leaderPID": TARGET, "termIgnored": True}
    output = json.dumps({"schema": 1, "kind": "descendant-ready", "pid": CHILD,
                         "pgid": TARGET, "monotonicNS": BASE + 155_000_000}).encode() + b"\n"
    target["streamProgress"] = [{"clock": clock(155_000_000), "observedBytes": len(output),
                                 "stdoutBytes": len(output), "stderrBytes": 0}]
    target["observedBytes"] = target["retainedBytes"] = len(output)
    return receipt, {"stdout": output, "stderr": b""}, records, controls, denied_retention()


class OwnedAccountingTests(unittest.TestCase):
    def test_positive_raw_groups_and_released_leases_are_accounted(self):
        receipt, _, records, _, _ = successful_fixture()
        self.assertTrue(subject.owned_children_accounted(receipt, records))

    def test_outer_cleanup_flag_cannot_replace_owned_child_evidence(self):
        for field, value in (("pidLeaseReleased", False), ("pidLeaseLost", True),
                             ("exitObservedWithoutReap", False), ("inheritedStreamsStillOpen", True),
                             ("cleanupFailed", True), ("streamErrors", ["lost stream"])):
            for role in ("target", "worker"):
                with self.subTest(role=role, field=field):
                    receipt, _, records, _, _ = successful_fixture()
                    receipt[role][field] = value
                    self.assertFalse(subject.owned_children_accounted(receipt, records))

    def test_empty_duplicate_live_or_foreign_final_leader_is_rejected(self):
        mutations = ([], [{"pid": TARGET, "pgid": TARGET, "state": "Z"}] * 2,
                     [{"pid": TARGET, "pgid": TARGET, "state": "S"}],
                     [{"pid": TARGET + 20, "pgid": TARGET, "state": "Z"}])
        for members in mutations:
            with self.subTest(members=members):
                receipt, _, records, _, _ = successful_fixture()
                receipt["finalOwnedGroups"]["target"]["members"] = members
                self.assertFalse(subject.owned_children_accounted(receipt, records))

    def test_summary_group_without_successful_matching_raw_ps_is_rejected(self):
        variants = (b"", b"1 1 S\n", b"101 101 S\n102 102 Z\n", b"not-ps\n")
        for raw in variants:
            with self.subTest(raw=raw):
                receipt, _, records, _, _ = successful_fixture()
                records[-1]["streams"]["stdout"] = raw
                self.assertFalse(subject.owned_children_accounted(receipt, records))
        receipt, _, records, _, _ = successful_fixture()
        records[-1]["receipt"]["exitCode"] = 1
        self.assertFalse(subject.owned_children_accounted(receipt, records))

    def test_probe_lease_release_and_clean_streams_are_required(self):
        for field, value in (("pidLeaseReleased", False), ("pidLeaseLost", True),
                             ("cleanupFailed", True), ("stopReason", "command-budget")):
            with self.subTest(field=field):
                receipt, _, records, _, _ = successful_fixture()
                records[-1]["receipt"][field] = value
                self.assertFalse(subject.owned_children_accounted(receipt, records))
        receipt, _, records, _, _ = successful_fixture()
        records[-1]["streams"]["stderr"] = b"ps failed\n"
        self.assertFalse(subject.owned_children_accounted(receipt, records))

    def test_later_live_group_snapshot_cannot_be_hidden_by_earlier_safe_inventory(self):
        receipt, _, records, _, _ = successful_fixture()
        records.append(probe("groups-final", 105,
                             [(1, 1, "S"), (TARGET, TARGET, "Z"),
                              (WORKER, WORKER, "Z"), (CHILD, TARGET, "S")],
                             at=200_000_000))
        self.assertFalse(subject.owned_children_accounted(receipt, records))

    def test_false_outer_cleanup_can_still_preserve_positive_child_accounting(self):
        receipt, _, records, _, _ = successful_fixture()
        receipt["cleanupComplete"] = False
        self.assertTrue(subject.owned_children_accounted(receipt, records))


class ClassificationTests(unittest.TestCase):
    def classify(self, name, data):
        receipt, streams, records, controls, retained = data
        return subject.classify_case(name, receipt, streams, records, controls, retention=retained)

    def assert_rejected(self, name, data):
        result = self.classify(name, data)
        self.assertFalse(result["passed"], result)
        self.assertTrue(result["errors"], result)

    def test_success_requires_complete_event_and_payload_evidence(self):
        result = self.classify("success", successful_fixture())
        self.assertTrue(result["passed"], result)

    def test_missing_target_never_qualifies_a_case(self):
        data = successful_fixture()
        data[0]["target"] = None
        self.assert_rejected("success", data)

    def test_false_final_gate_or_stale_post_operation_generation_is_rejected(self):
        data = successful_fixture()
        data[0]["finalFreshScanComplete"] = False
        self.assert_rejected("success", data)
        data = successful_fixture()
        data[0]["observer"]["scanHistory"]["records"][-1]["request"]["dispatchedNS"] = BASE + 100_000_000
        self.assert_rejected("success", data)

    def test_no_completed_live_census_cannot_substitute_for_live_observation(self):
        data = successful_fixture()
        data[0]["observer"]["scanHistory"]["records"].pop(1)
        self.assert_rejected("success", data)

    def test_aggregate_retention_true_cannot_hide_missing_exact_payload_checks(self):
        for field in ("exactPayloads", "crcValid", "sha256Matches", "originalsPreserved"):
            with self.subTest(field=field):
                data = successful_fixture()
                data[4]["payloadVerification"][field] = False
                self.assert_rejected("success", data)
        data = successful_fixture()
        data[4]["semanticAnalysisValidityEstablished"] = True
        self.assert_rejected("success", data)

    def test_success_rejects_nonzero_or_forced_worker_after_stopped_message(self):
        for field, value in (("exitCode", 7), ("stopReason", "observer-shutdown")):
            with self.subTest(field=field):
                data = successful_fixture()
                data[0]["worker"][field] = value
                self.assert_rejected("success", data)

    def test_probe_launch_witness_must_show_unreaped_owned_child(self):
        for field, value in (("returncodeBeforeProbe", 0), ("waitable", False),
                             ("pgid", TARGET + 99), ("pid", TARGET + 99)):
            with self.subTest(field=field):
                data = successful_fixture()
                data[3]["probeLeaseObservations"][0]["children"][0][field] = value
                self.assert_rejected("success", data)

    def test_probe_launch_witness_is_bound_to_actual_probe_and_precollection_clock(self):
        for mutation in ("probe-name", "post-collection-clock"):
            with self.subTest(mutation=mutation):
                data = successful_fixture()
                if mutation == "probe-name":
                    data[3]["probeLeaseObservations"][0]["probeName"] = "unrelated-probe"
                else:
                    data[3]["probeLeaseObservations"][0]["children"][0]["observedClockNS"] = BASE + 220_000_000
                self.assert_rejected("success", data)

    def test_pending_metadata_case_accepts_expected_failure_with_positive_cleanup(self):
        result = self.classify("pending-exit", pending_fixture())
        self.assertTrue(result["passed"], result)

    def test_pending_progress_and_exit_must_be_observed_inside_pending_interval(self):
        for offset in (50_000_000, 305_000_001):
            for target_field in ("streamProgress", "operationTerminalClock"):
                with self.subTest(offset=offset, target_field=target_field):
                    data = pending_fixture()
                    if target_field == "streamProgress":
                        data[0]["target"]["streamProgress"][0]["clock"] = clock(offset)
                    else:
                        data[0]["target"][target_field] = clock(offset)
                    self.assert_rejected("pending-exit", data)

    def test_pending_case_rejects_missing_output_marker_or_pending_operation(self):
        data = pending_fixture()
        data[1]["stdout"] = b""
        self.assert_rejected("pending-exit", data)
        data = pending_fixture()
        data[3]["workerMarker"]["pid"] += 1
        self.assert_rejected("pending-exit", data)
        data = pending_fixture()
        data[0]["observer"]["failure"]["pendingOperation"] = None
        self.assert_rejected("pending-exit", data)

    def test_pending_failure_cannot_be_relabelled_as_successful_retention(self):
        data = pending_fixture()
        data[4]["retentionComplete"] = True
        self.assert_rejected("pending-exit", data)
        data = pending_fixture()
        data[0]["observationComplete"] = True
        self.assert_rejected("pending-exit", data)

    def test_pending_cases_require_expected_worker_exit_and_matching_owned_signal(self):
        for name in ("pending-exit", "deadline"):
            for code in (0, 7, -11):
                with self.subTest(name=name, workerExitCode=code):
                    data = pending_fixture(deadline=name == "deadline")
                    data[0]["worker"]["exitCode"] = code
                    self.assert_rejected(name, data)
            data = pending_fixture(deadline=name == "deadline")
            data[0]["worker"]["signals"] = []
            self.assert_rejected(name, data)

    def test_deadline_stop_occurs_inside_pending_metadata_interval(self):
        result = self.classify("deadline", pending_fixture(deadline=True))
        self.assertTrue(result["passed"], result)

    def test_wrong_reason_or_stop_outside_pending_interval_does_not_prove_deadline_service(self):
        data = pending_fixture(deadline=True)
        data[0]["target"]["stopReason"] = "isolated-observation-failed"
        self.assert_rejected("deadline", data)
        for offset in (50_000_000, 305_000_001):
            with self.subTest(offset=offset):
                data = pending_fixture(deadline=True)
                data[0]["target"]["stopRequestedClock"] = clock(offset)
                self.assert_rejected("deadline", data)

    def test_acknowledged_worker_exit_seven_is_expected_negative(self):
        result = self.classify("exit-seven", stopped_worker_fixture())
        self.assertTrue(result["passed"], result)

    def test_exit_seven_case_requires_exact_worker_outcome_and_fresh_final_scan(self):
        for mutate in ("code", "stopped", "final"):
            with self.subTest(mutate=mutate):
                data = stopped_worker_fixture()
                if mutate == "code":
                    data[0]["worker"]["exitCode"] = 0
                elif mutate == "stopped":
                    data[0]["observer"]["stopped"] = False
                else:
                    data[0]["finalFreshScanComplete"] = False
                self.assert_rejected("exit-seven", data)

    def test_live_same_group_descendant_cleanup_is_expected_negative(self):
        result = self.classify("descendant", descendant_fixture())
        self.assertTrue(result["passed"], result)

    def test_descendant_case_rejects_unrelated_worker_failure(self):
        for code in (7, -11):
            with self.subTest(workerExitCode=code):
                data = descendant_fixture()
                data[0]["worker"]["exitCode"] = code
                self.assert_rejected("descendant", data)

    def test_descendant_requires_initial_live_member_in_original_owned_group(self):
        for raw in (b"101 101 Z\n102 102 Z\n",
                    b"101 101 Z\n102 102 Z\n104 999 S\n",
                    b"101 101 Z\n102 102 Z\n104 101 Z\n"):
            with self.subTest(raw=raw):
                data = descendant_fixture()
                data[2][1]["streams"]["stdout"] = raw
                self.assert_rejected("descendant", data)

    def test_descendant_requires_kill_and_no_live_member_after_cleanup(self):
        data = descendant_fixture()
        data[0]["target"]["signals"] = [signal_row("SIGTERM", TARGET, .247)]
        self.assert_rejected("descendant", data)
        data = descendant_fixture()
        data[2][-1]["streams"]["stdout"] += b"104 101 S\n"
        self.assert_rejected("descendant", data)

    def test_test_controls_and_unknown_case_cannot_be_mislabelled_as_qualification(self):
        data = successful_fixture()
        data[0]["testControlsUsed"] = False
        self.assert_rejected("success", data)
        self.assert_rejected("unrecognized", successful_fixture())


if __name__ == "__main__":
    unittest.main()
