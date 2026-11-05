"""Portable lifecycle routing and stop rules; these tests never send input."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import compare_native_drag_capture as capture
import compare_native_drag_lifecycle as lifecycle
from test_compare_native_drag_capture import fixture as capture_fixture, emit_case


def fixture(parent):
    stage, context = capture_fixture(parent)
    (stage / "NativeDragReviewAppKit").write_bytes(b"Portable AppKit observer fixture; never execute.\n")
    context["provenance"].update(observerBuildModes=copy.deepcopy(lifecycle.MODES),
        observerExecutableSHA256=capture.sha256(stage / "NativeDragReview"),
        observerAppKitExecutableSHA256=capture.sha256(stage / "NativeDragReviewAppKit"))
    (stage / "provenance.json").write_text(json.dumps(context["provenance"]))
    context["inputs"] = lifecycle.input_snapshot(stage)
    return stage, context


def emit(stage, context, target, mode, passed=False, mutate=None):
    def add_lifecycle(aggregate, case):
        for record in (aggregate, case):
            record.update(captureComparison="ax-only", observerLifecycle=mode,
                observerLifecycleAtStart={"mode": mode, "didFinishLaunching": mode == "appkit",
                    "nsApplicationPresent": mode == "appkit", "nsApplicationRunning": mode == "appkit",
                    "activationPolicy": 2 if mode == "appkit" else -1,
                    "threadIsMain": True, "taskPriorityRawValue": 21})
        if mutate:
            mutate(aggregate, case)
    # Reuse the native-shaped D8 records, with only the new evidence suffix and
    # startup receipts changed. The original staged app and fixture paths stay fixed.
    policy = "ax-only" + ("-Lifecycle-appkit" if mode == "appkit" else "")
    return emit_case(stage, context, target, policy, passed, add_lifecycle)


class LifecycleComparisonTests(unittest.TestCase):
    def test_known_failures_retain_all_four_cases_without_becoming_success(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            commands = []
            def runner(command, log):
                target, mode = lifecycle.CASES[len(commands)]
                commands.append(command)
                return emit(stage, context, target, mode)
            report = lifecycle.compare(stage, Path(temporary) / "output", context, runner)
            self.assertTrue(report["comparisonComplete"])
            self.assertTrue(report["inputsUnchanged"])
            self.assertFalse(report["allCasesPassed"])
            self.assertEqual(report["status"], "failed")
            for command, result, (target, mode) in zip(commands, report["cases"], lifecycle.CASES):
                self.assertEqual(command, [str(stage / lifecycle.MODES[mode]["executable"]), str(stage)]
                    + (["--control"] if target == "control" else []) + ["--compare-capture", "ax-only"])
                self.assertEqual(result["observerLifecycle"], mode)
                self.assertEqual(result["observerExecutableSHA256"], capture.sha256(Path(command[0])))
                self.assertEqual(result["outcome"], "escape-cancellation-failed")

    def test_complete_success_still_requires_fresh_drop_and_keeps_hold(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            sequence = iter(lifecycle.CASES)
            def runner(command, log):
                target, mode = next(sequence)
                return emit(stage, context, target, mode, passed=True)
            report = lifecycle.compare(stage, Path(temporary) / "output", context, runner)
            self.assertTrue(report["allCasesPassed"])
            self.assertEqual(report["C12"], "HOLD")
            self.assertFalse(report["nativeAcceptanceXCTestExecuted"])
            self.assertFalse(report["physicalInputVerified"])

    def test_missing_unknown_blocked_or_unsafe_first_case_stops_later_input(self):
        mutations = {
            "missing-context": lambda a, c: c.pop("observerLifecycleAtStart"),
            "wrong-mode": lambda a, c: a.update(observerLifecycle="appkit"),
            "unknown": lambda a, c: c.update(reason="Unrelated startup failure"),
            "blocked": lambda a, c: c.update(status="blocked"),
            "cleanup": lambda a, c: c["cleanup"].update(completed=1),
            "permission": lambda a, c: c["preflight"].update(postEvents=False),
            "capture-policy": lambda a, c: c.update(captureComparison="screenshots"),
            "report": lambda a, c: a["themes"][0].update(reportRetained=False),
        }
        for name, mutation in mutations.items():
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                stage, context = fixture(Path(temporary))
                calls = []
                def runner(command, log):
                    calls.append(command)
                    emit(stage, context, "control", "swift-async", mutate=mutation)
                    return 0 if name == "blocked" else 1
                report = lifecycle.compare(stage, Path(temporary) / "output", context, runner)
                self.assertEqual(len(calls), 1)
                self.assertFalse(report["comparisonComplete"])
                self.assertEqual([r["outcome"] for r in report["cases"]][1:], ["not-run"] * 3)

    def test_missing_native_report_is_retained_as_stop(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            calls = []
            def runner(command, log):
                calls.append(command)
                return 1
            report = lifecycle.compare(stage, Path(temporary) / "output", context, runner)
            self.assertEqual(len(calls), 1)
            self.assertEqual(report["cases"][0]["reasonCode"], "FileNotFoundError")
            self.assertEqual(report["cases"][1]["outcome"], "not-run")

    def test_appkit_requires_running_nonactivating_finished_startup(self):
        mutations = [{"didFinishLaunching": False}, {"nsApplicationPresent": False},
                     {"nsApplicationRunning": False}, {"activationPolicy": 0}, {"activationPolicy": True}]
        for mutation in mutations:
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as temporary:
                stage, context = fixture(Path(temporary))
                calls = []
                def runner(command, log):
                    target, mode = lifecycle.CASES[len(calls)]
                    calls.append(command)
                    def change(a, c):
                        if mode == "appkit":
                            c["observerLifecycleAtStart"].update(mutation)
                    return emit(stage, context, target, mode, mutate=change)
                report = lifecycle.compare(stage, Path(temporary) / "output", context, runner)
                self.assertEqual(len(calls), 2)
                self.assertFalse(report["comparisonComplete"])
                self.assertEqual(report["cases"][2]["outcome"], "not-run")

    def test_both_observers_are_inventory_pinned_before_every_case(self):
        for name in ("NativeDragReview", "NativeDragReviewAppKit"):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                stage, context = fixture(Path(temporary))
                calls = []
                def runner(command, log):
                    calls.append(command)
                    result = emit(stage, context, "control", "swift-async")
                    (stage / name).write_bytes(b"changed after first case")
                    return result
                report = lifecycle.compare(stage, Path(temporary) / "output", context, runner)
                self.assertEqual(len(calls), 1)
                self.assertFalse(report["inputsUnchanged"])
                self.assertEqual(report["cases"][0]["reasonCode"], "inputs-changed-after-case")

    def test_appkit_source_binding_and_build_metadata_are_checked(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            with patch.object(capture, "context_for", return_value=context):
                self.assertEqual(lifecycle.context_for(stage, "unused")["inputs"], lifecycle.input_snapshot(stage))
                context["provenance"]["observerBuildModes"]["appkit"]["swiftDefines"] = []
                with self.assertRaisesRegex(capture.ComparisonError, "observer-build-modes"):
                    lifecycle.context_for(stage, "unused")
                context["provenance"]["observerBuildModes"] = copy.deepcopy(lifecycle.MODES)
                context["provenance"]["observerAppKitExecutableSHA256"] = "0" * 64
                with self.assertRaisesRegex(capture.ComparisonError, "appkit-observer-hash-link"):
                    lifecycle.context_for(stage, "unused")

    def test_existing_appkit_evidence_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            evidence = lifecycle.evidence_for(stage, "production", "appkit")
            evidence.mkdir()
            with self.assertRaisesRegex(capture.ComparisonError, "evidence-already-exists"):
                lifecycle.compare(stage, Path(temporary) / "output", context, lambda *_: self.fail("unexpected input"))


if __name__ == "__main__":
    unittest.main()
