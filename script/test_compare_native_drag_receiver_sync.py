"""Portable D16 tests. Synthetic receipts never launch native input."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import compare_native_drag_capture as capture
import compare_native_drag_mouse_driver as mouse
import compare_native_drag_receiver_sync as sync
import compare_native_drag_sources as sources
import test_compare_native_drag_mouse_driver as fixture_mouse


def fixture(parent):
    stage, context = fixture_mouse.fixture(parent, case_plan=sync.CASES)
    context["provenance"].update(sync.diagnostic_metadata())
    (stage / "provenance.json").write_text(json.dumps(context["provenance"]))
    context["inputs"] = sync.input_snapshot(stage)
    return stage, context


def attach_receipt(stage, case_name):
    directory = mouse.evidence_for(stage, case_name) / "orchard"
    data = (directory / "receiver.jsonl").read_bytes()
    receiver = fixture_mouse.read_trace(directory / "receiver.jsonl")
    records, offset = [], 0
    per_record = sync.policy_for(case_name) == "per-record"
    for index, (row, line) in enumerate(zip(receiver, data.split(b"\n")[:-1])):
        when = row["systemUptime"]
        records.append({"recordIndex": index, "event": row["event"], "recordSystemUptime": when,
            "byteOffset": offset, "byteCount": len(line) + 1,
            "writeStartedSystemUptime": when + .0001, "writeCompletedSystemUptime": when + .0002,
            "synchronizeAttempted": per_record, "synchronizeStartedSystemUptime": when + .0003 if per_record else None,
            "synchronizeCompletedSystemUptime": when + .0004 if per_record else None})
        offset += len(line) + 1
    final = receiver[-1]["systemUptime"]
    receipt = {"schema": 1, "status": "complete", "reasonCode": None, "receiverSyncCase": case_name,
        "receiverTraceSyncPolicy": sync.policy_for(case_name), "targetPID": 200, "traceFileName": "receiver.jsonl",
        "recordWritePolicy": "immediate", "synchronizationAPI": "FileHandle.synchronize",
        "maximumRecordCount": 10_000, "maximumTraceBytes": 8_388_608, "recordCount": len(receiver),
        "writtenByteCount": len(data), "perRecordSynchronizeCount": len(receiver) if per_record else 0,
        "records": records, "lifecycleSynchronization": {"phase": "termination", "recordCount": len(receiver),
            "writtenByteCount": len(data), "startedSystemUptime": final + .0005,
            "completedSystemUptime": final + .0006, "succeeded": True}}
    def update(rows):
        for row in rows:
            if row["event"] in ("activation-start", "activation-ready"):
                row["receiverTraceSynchronizationSchema"] = 1
        rows[-1].update(callbackSystemUptime=final - .001, systemUptime=final + .02,
                        receiverTraceSynchronization=receipt)
    fixture_mouse.alter_trace(directory / "activation.jsonl", update)


def alter_receipt(stage, case_name, action):
    path = mouse.evidence_for(stage, case_name) / "orchard/activation.jsonl"
    fixture_mouse.alter_trace(path, lambda rows: action(rows[-1]["receiverTraceSynchronization"]))


class ReceiverSyncComparisonTests(unittest.TestCase):
    def run_cases(self, stage, context, output, *, pass_for=None, change=None, none_after_release=False):
        commands = []
        def runner(command, log):
            name = sync.CASES[len(commands)]
            commands.append(command)
            code = fixture_mouse.emit(stage, context, name, passed=bool(pass_for and pass_for(name)),
                                      none_after_release=none_after_release)
            attach_receipt(stage, name)
            if change:
                change(stage, name)
            return code
        return sync.compare(stage, output, context, runner), commands

    def test_complete_failures_keep_native_verdict_and_falsify_sync_necessity(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            report, commands = self.run_cases(stage, context, Path(temporary) / "out")
            self.assertEqual(len(commands), 4)
            self.assertTrue(report["comparisonComplete"], report["cases"])
            self.assertTrue(report["nativeComparisonComplete"])
            self.assertTrue(report["syncInstrumentationComplete"])
            self.assertFalse(report["allCasesPassed"])
            self.assertEqual(report["caseOrder"], list(sync.CASES))
            self.assertEqual(report["casePlan"], sync.PLAN)
            self.assertEqual(report["receiverSyncComparison"]["classification"], "lifecycle-sync-did-not-resolve-failure")
            self.assertEqual(report["receiverSyncComparison"]["lifecycleFailureCases"], list(sync.CASES[1:3]))
            self.assertTrue(report["receiverSyncComparison"]["perRecordSynchronizationNecessityFalsified"])
            for command, name, row in zip(commands, sync.CASES, report["cases"]):
                self.assertEqual(command[-2:], ["--compare-mouse-driver", name])
                self.assertEqual(row["mouseProducer"], "quartz")
                self.assertEqual(row["mouseControlDriver"]["requestCount"], 0)
                self.assertEqual(row["comparability"], "comparable")
                self.assertEqual(row["outcome"], "escape-cancellation-failed")
                self.assertFalse(row["strictNativeOutcome"]["passed"])
                receipt = row["receiverSyncInstrumentation"]["receipt"]
                self.assertEqual(receipt["perRecordSynchronizeCount"], receipt["recordCount"] if sync.policy_for(name) == "per-record" else 0)
                self.assertTrue(row["inputsUnchanged"] and row["commonInputSignatureMatches"])

    def test_repeated_contrast_in_either_direction_is_only_policy_sensitivity(self):
        for passing_policy in ("per-record", "lifecycle"):
            with self.subTest(passing_policy=passing_policy), tempfile.TemporaryDirectory() as temporary:
                stage, context = fixture(Path(temporary))
                report, _ = self.run_cases(stage, context, Path(temporary) / "out",
                    pass_for=lambda name: sync.policy_for(name) == passing_policy)
                self.assertTrue(report["comparisonComplete"], report["cases"])
                observation = report["receiverSyncComparison"]
                self.assertEqual(observation["classification"], "receiver-sync-policy-associated-contrast")
                self.assertTrue(observation["repeatedPolicyContrastObserved"])
                self.assertEqual(observation["contrastDirection"], passing_policy + "-passed-"
                                 + ("lifecycle" if passing_policy == "per-record" else "per-record") + "-failed")
                self.assertEqual(observation["perRecordSynchronizationNecessityFalsified"], passing_policy == "per-record")
                self.assertFalse(observation["productionFixEstablished"] or observation["originalGateCovered"])
                self.assertEqual(report["C12"], "HOLD")

    def test_normal_cancellation_after_release_requires_distinct_fresh_drop(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            report, _ = self.run_cases(stage, context, Path(temporary) / "out", pass_for=lambda _: True, none_after_release=True)
            self.assertTrue(report["allCasesPassed"], report["cases"])
            self.assertTrue(report["strictNativeAllCasesPassed"])
            self.assertEqual(report["receiverSyncComparison"]["classification"], "baseline-failure-not-reproduced")
            for row in report["cases"]:
                sessions = row["sourceSession"]["sessions"]
                self.assertTrue(sessions["cancel"]["noneCallbackAfterObservedRelease"])
                self.assertEqual(sessions["cancel"]["end"]["operationRawValue"], 0)
                self.assertEqual(sessions["fresh"]["end"]["operationRawValue"], 1)
            self.assertFalse(report["releaseReady"] or report["nativeAcceptanceXCTestExecuted"] or report["physicalInputVerified"])

    def test_other_mixed_outcomes_establish_no_fix(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            report, _ = self.run_cases(stage, context, Path(temporary) / "out", pass_for=lambda name: name == sync.CASES[1])
            self.assertTrue(report["comparisonComplete"], report["cases"])
            self.assertEqual(report["receiverSyncComparison"]["classification"], "mixed-results-no-policy-conclusion")
            self.assertFalse(report["receiverSyncComparison"]["repeatedPolicyContrastObserved"])

    def test_malformed_receipts_stop_next_input_without_rewriting_native_fail(self):
        mutations = {
            "wrong-policy": lambda r: r.update(receiverTraceSyncPolicy="lifecycle"),
            "wrong-case": lambda r: r.update(receiverSyncCase=sync.CASES[3]),
            "wrong-pid": lambda r: r.update(targetPID=300),
            "unknown-field": lambda r: r.update(unmeasured=True),
            "bool-schema": lambda r: r.update(schema=True),
            "incomplete-watchdog": lambda r: r.update(status="incomplete", reasonCode="watchdog-termination"),
            "missing-write": lambda r: r["records"].pop(),
            "wrong-count": lambda r: r.update(recordCount=r["recordCount"] + 1),
            "wrong-bytes": lambda r: r.update(writtenByteCount=r["writtenByteCount"] - 1),
            "wrong-offset": lambda r: r["records"][1].update(byteOffset=0),
            "wrong-size": lambda r: r["records"][0].update(byteCount=r["records"][0]["byteCount"] - 1),
            "wrong-event": lambda r: r["records"][0].update(event="other-event"),
            "wrong-record-clock": lambda r: r["records"][0].update(recordSystemUptime=1.),
            "reversed-write": lambda r: r["records"][0].update(writeCompletedSystemUptime=1.),
            "overlapping-records": lambda r: r["records"][0].update(synchronizeCompletedSystemUptime=3.),
            "no-record-sync": lambda r: r["records"][0].update(synchronizeAttempted=False),
            "missing-sync-clock": lambda r: r["records"][0].update(synchronizeCompletedSystemUptime=None),
            "sync-before-write-return": lambda r: r["records"][0].update(synchronizeStartedSystemUptime=1.),
            "sync-count": lambda r: r.update(perRecordSynchronizeCount=0),
            "incomplete-lifecycle": lambda r: r["lifecycleSynchronization"].update(succeeded=False),
            "bool-lifecycle-count": lambda r: r["lifecycleSynchronization"].update(recordCount=True),
            "wrong-lifecycle-phase": lambda r: r["lifecycleSynchronization"].update(phase="watchdog"),
            "lifecycle-before-final-write": lambda r: r["lifecycleSynchronization"].update(startedSystemUptime=20.),
            "lifecycle-after-termination": lambda r: r["lifecycleSynchronization"].update(completedSystemUptime=26.),
        }
        for label, mutation in mutations.items():
            with self.subTest(mutation=label), tempfile.TemporaryDirectory() as temporary:
                stage, context = fixture(Path(temporary))
                report, commands = self.run_cases(stage, context, Path(temporary) / "out",
                    change=lambda root, name: alter_receipt(root, name, mutation))
                self.assertEqual(len(commands), 1)
                first = report["cases"][0]
                self.assertEqual(first["comparability"], "comparable", first)
                self.assertEqual(first["outcome"], "escape-cancellation-failed")
                self.assertEqual(first["receiverSyncInstrumentation"]["status"], "invalid")
                self.assertFalse(first["mayContinue"])
                self.assertEqual([row["outcome"] for row in report["cases"][1:]], ["not-run"] * 3)
                self.assertFalse(report["comparisonComplete"])

    def test_lifecycle_arm_rejects_hidden_or_claimed_per_record_synchronization(self):
        mutations = [lambda r: r["records"][0].update(synchronizeAttempted=True),
                     lambda r: r["records"][0].update(synchronizeStartedSystemUptime=2.0003),
                     lambda r: r["records"][0].update(synchronizeCompletedSystemUptime=2.0004),
                     lambda r: r.update(perRecordSynchronizeCount=1)]
        for mutation in mutations:
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as temporary:
                stage, context = fixture(Path(temporary))
                def change(root, name):
                    if name == sync.CASES[1]:
                        alter_receipt(root, name, mutation)
                report, commands = self.run_cases(stage, context, Path(temporary) / "out", change=change)
                self.assertEqual(len(commands), 2)
                self.assertEqual(report["cases"][1]["receiverSyncInstrumentation"]["status"], "invalid")
                self.assertFalse(report["receiverSyncComparison"]["perRecordSynchronizationNecessityFalsified"])

    def test_invalid_final_receipt_preserves_four_native_passes(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            def change(root, name):
                if name == sync.CASES[-1]:
                    alter_receipt(root, name, lambda r: r["records"].pop())
            report, commands = self.run_cases(stage, context, Path(temporary) / "out", pass_for=lambda _: True, change=change)
            self.assertEqual(len(commands), 4)
            self.assertTrue(report["nativeComparisonComplete"] and report["strictNativeAllCasesPassed"])
            self.assertFalse(report["syncInstrumentationComplete"] or report["comparisonComplete"] or report["allCasesPassed"])
            self.assertTrue(all(row["passed"] and row["comparability"] == "comparable" for row in report["cases"]))
            self.assertEqual(report["cases"][-1]["outcome"], "captured")

    def test_missing_startup_termination_or_callback_envelope_receipt_is_invalid(self):
        mutations = [lambda rows: rows[0].pop("receiverTraceSynchronizationSchema"),
                     lambda rows: rows[1].update(receiverTraceSynchronizationSchema=True),
                     lambda rows: rows[-1].pop("receiverTraceSynchronization"),
                     lambda rows: rows[-1].pop("callbackSystemUptime"),
                     lambda rows: rows[-1].update(callbackSystemUptime=25.11),
                     lambda rows: rows[1].update(receiverTraceSynchronization=rows[-1]["receiverTraceSynchronization"])]
        for mutation in mutations:
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as temporary:
                stage, context = fixture(Path(temporary))
                def change(root, name):
                    fixture_mouse.alter_trace(mouse.evidence_for(root, name) / "orchard/activation.jsonl", mutation)
                report, commands = self.run_cases(stage, context, Path(temporary) / "out", change=change)
                self.assertEqual(len(commands), 1)
                self.assertEqual(report["cases"][0]["receiverSyncInstrumentation"]["status"], "invalid")

    def test_complete_raw_byte_coverage_detects_reformat_and_uncovered_rows(self):
        for extra_row in (False, True):
            with self.subTest(extra_row=extra_row), tempfile.TemporaryDirectory() as temporary:
                stage, context = fixture(Path(temporary))
                def change(root, name):
                    path = mouse.evidence_for(root, name) / "orchard/receiver.jsonl"
                    if extra_row:
                        def insert(rows):
                            rows.insert(-1, {**rows[-1], "event": "late-receiver-observation", "systemUptime": 24.9})
                        fixture_mouse.alter_trace(path, insert)
                    else:
                        path.write_bytes(b" " + path.read_bytes())
                report, commands = self.run_cases(stage, context, Path(temporary) / "out", change=change)
                self.assertEqual(len(commands), 1)
                self.assertEqual(report["cases"][0]["comparability"], "comparable", report["cases"][0])
                self.assertEqual(report["cases"][0]["receiverSyncInstrumentation"]["status"], "invalid")

    def test_observer_may_read_entry_before_write_returns_or_synchronization_finishes(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            def change(root, name):
                def delay(receipt):
                    row = receipt["records"][2]
                    row["writeCompletedSystemUptime"] = 11.
                    if sync.policy_for(name) == "per-record":
                        row.update(synchronizeStartedSystemUptime=11.01, synchronizeCompletedSystemUptime=11.02)
                alter_receipt(root, name, delay)
            report, _ = self.run_cases(stage, context, Path(temporary) / "out", change=change)
            self.assertTrue(report["comparisonComplete"], report["cases"])

    def test_lifecycle_sync_must_follow_the_last_observed_mouse_release(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            def change(root, name):
                directory = mouse.evidence_for(root, name) / "orchard"
                case = json.loads((directory / "report.json").read_text())
                released = case["mouseDriverGestures"][-1]["releaseObservedSystemUptime"]
                fixture_mouse.alter_trace(directory / "receiver.jsonl",
                    lambda rows: rows[-1].update(systemUptime=released - .005))
                attach_receipt(root, name)
            report, commands = self.run_cases(stage, context, Path(temporary) / "out", change=change)
            self.assertEqual(len(commands), 1)
            first = report["cases"][0]
            self.assertEqual(first["comparability"], "comparable", first)
            self.assertEqual(first["outcome"], "escape-cancellation-failed")
            self.assertEqual(first["receiverSyncInstrumentation"]["reasonCode"], "receiver-sync-lifecycle-clock-order")

    def test_cleanup_failure_is_native_incomplete_and_stops_next_case(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            def change(root, name):
                fixture_mouse.alter_case(root, name, lambda row: row["mouseControlDriver"]["cleanup"].update(normalCompletion=False))
            report, commands = self.run_cases(stage, context, Path(temporary) / "out", change=change)
            self.assertEqual(len(commands), 1)
            self.assertEqual(report["cases"][0]["comparability"], "not-comparable")
            self.assertNotIn("strictNativeOutcome", report["cases"][0])
            self.assertFalse(report["nativeComparisonComplete"])

    def test_changed_common_gesture_signature_stops_with_native_result_preserved(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            def change(root, name):
                if name == sync.CASES[1]:
                    fixture_mouse.alter_case(root, name, lambda row: row["inputSource"].update(localEventsSuppressionInterval=.9))
            report, commands = self.run_cases(stage, context, Path(temporary) / "out", change=change)
            self.assertEqual(len(commands), 2)
            second = report["cases"][1]
            self.assertEqual(second["comparability"], "comparable", second)
            self.assertEqual(second["comparisonStopReasonCode"], "mouse-common-protocol-or-geometry-changed")
            self.assertFalse(second["commonInputSignatureMatches"] or second["mayContinue"])

    def test_immutable_inputs_and_existing_runtime_are_checked_before_more_input(self):
        for existing in (False, True):
            with self.subTest(existing=existing), tempfile.TemporaryDirectory() as temporary:
                stage, context = fixture(Path(temporary))
                if existing:
                    (stage / "MouseControl" / sync.CASES[0] / "xcodebuild.log").write_text("retained\n")
                def change(root, name):
                    (root / mouse.OBSERVER).write_bytes(b"changed observer\n")
                report, commands = self.run_cases(stage, context, Path(temporary) / "out", change=change)
                self.assertEqual(len(commands), 0 if existing else 1)
                self.assertFalse(report["comparisonComplete"])

    def test_exact_case_plan_metadata_and_code_provenance_are_required(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            with patch.object(sources, "context_for", return_value=copy.deepcopy(context)):
                self.assertEqual(sync.context_for(stage, "b" * 40)["inputs"], context["inputs"])
            mutations = [lambda value: value["receiverSyncDiagnostic"]["casePlan"].reverse(),
                         lambda value: value["receiverSyncDiagnostic"]["casePlan"].pop(),
                         lambda value: value["receiverSyncDiagnostic"]["casePlan"][0].update(case="quartz-first"),
                         lambda value: value["receiverSyncDiagnostic"]["casePlan"][1].update(receiverTraceSyncPolicy="per-record"),
                         lambda value: value["receiverSyncDiagnostic"].update(schema=True),
                         lambda value: value["receiverSyncControlBuild"]["swiftDefines"].append("LEMULIP_DISPATCH_STACK_TRACE"),
                         lambda value: value["receiverSyncProtocol"].update(inputProtocol="different"),
                         lambda value: value.update(receiverSyncComparatorSourceSHA256="0" * 64)]
            for mutate in mutations:
                broken = copy.deepcopy(context)
                mutate(broken["provenance"])
                with self.subTest(mutation=mutate), self.assertRaises(capture.ComparisonError):
                    sync.context_policy(broken)
            (stage / "MouseControl" / "quartz-first").mkdir()
            with self.assertRaisesRegex(capture.ComparisonError, "receiver-sync-runtime-case-plan"):
                sync.input_snapshot(stage)

    def test_only_exact_complete_plans_are_accepted_and_legacy_default_is_unchanged(self):
        self.assertEqual(mouse.CASES, ("quartz-first", "xctest-first", "xctest-second", "quartz-second"))
        for bad in ((), sync.CASES[:3], tuple(reversed(sync.CASES)), (mouse.CASES[0], *sync.CASES[1:]), "quartz-sync-first"):
            with self.subTest(plan=bad), self.assertRaises(capture.ComparisonError):
                mouse.fixed_case_plan(bad)
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            self.assertEqual(mouse.manifest_metadata(stage, case_plan=sync.CASES)["mouseXCTestRunSHA256"],
                             context["provenance"]["mouseXCTestRunSHA256"])
            with self.assertRaises(Exception):
                mouse.manifest_metadata(stage)
            with patch.object(mouse, "prepare_mouse_driver", return_value={"built": True}) as prepare:
                metadata = sync.prepare_mouse_driver(stage)
                prepare.assert_called_once_with(stage, case_plan=sync.CASES)
                self.assertTrue(metadata["built"])
                self.assertEqual(metadata["receiverSyncDiagnostic"]["casePlan"], sync.PLAN)


if __name__ == "__main__":
    unittest.main()
