"""Portable checks for continuing only after a comparable, clean native case."""
import copy
import json
from pathlib import Path
import tempfile
import unittest

from compare_native_drag_capture import (APPLICATION_COMMIT, APPLICATION_TREE, CASES,
    ESCAPE_FAILURE, TARGETS, ComparisonError, classify, compare, input_snapshot, sha256)


def fixture(parent):
    stage = parent / "lemulip-native-ui"
    stage.mkdir(parents=True)
    for bundle, executable in [("Lemulip Native UI Review.app", "Lemulip"), ("Native Drag Control.app", "NativeDragControl")]:
        binary = stage / bundle / "Contents/MacOS" / executable
        binary.parent.mkdir(parents=True)
        binary.write_bytes(b"Portable test input; never execute.\n")
    (stage / "NativeDragReview").write_bytes(b"Portable test observer; never execute.\n")
    folder = stage / "Fixtures/FinderDrop/orchard"
    folder.mkdir(parents=True)
    roles = {}
    for role in ("Existing", "Single", "Multi-A", "Multi-B"):
        name = role + "-" + "a" * 32 + ".txt"
        (folder / name).write_text(f"Synthetic Finder input: orchard, {role}. Preserve these bytes.\n")
        roles[role] = name
    provenance = {"sourceCommit": APPLICATION_COMMIT, "sourceTree": APPLICATION_TREE, "architecture": "arm64",
        "observerExperimentCommit": "b" * 40, "observerExperimentTree": "c" * 40,
        "nativeDragReviewSourceSHA256": "d" * 64, "nativeDragControlSourceSHA256": "e" * 64,
        "stagedGUI_SHA256": "f" * 64, "controlGUI_SHA256": "0" * 64}
    (stage / "provenance.json").write_text(json.dumps(provenance))
    context = {"provenance": provenance, "roles": roles,
               "fixtures": {p.name: sha256(p) for p in folder.iterdir()}, "inputs": input_snapshot(stage)}
    return stage, context


def emit_case(stage, context, target, policy, passed=False, mutate=None):
    bundle, evidence_name, kind = TARGETS[target]
    evidence = stage / (evidence_name + "-Capture-" + policy)
    directory = evidence / "orchard"
    directory.mkdir(parents=True)
    cleanup = {"completed": True, "leftButtonReportedDown": False, "applicationStopped": True,
               "fixtureFinderWindowClosed": True, "fixedBundleRegistryEmpty": True, "errors": []}
    existing, single = context["roles"]["Existing"], context["roles"]["Single"]
    workspace = {"matchesExpectedWorkspace": True, "expectedFilenames": [existing],
                 "observedFilenames": [existing], "selectedCountLabels": ["1 Selected"]}
    case = {**context["provenance"], "schema": 1, "theme": "orchard", "targetKind": kind,
        "inputDriver": "CGEvent", "permissionRequested": False, "captureComparison": policy,
        "diagnosticOnly": True, "nativeAcceptanceXCTestExecuted": False,
        "imageCaptureEnabled": policy == "screenshots", "imagesCaptured": policy == "screenshots",
        "applicationPath": str(stage / bundle), "fixtureFolder": str(stage / "Fixtures/FinderDrop/orchard"),
        "originalSHA256": context["fixtures"], "preflight": {"accessibility": True, "postEvents": True, "screenCapture": True},
        "cleanup": cleanup, "escapeObservations": [{"phase": "before-key", "workspace": workspace}],
        "escapeKeyProtocol": {"keyCode": 53, "eventTap": "cghidEventTap", "keyDownDwellSeconds": 0.15,
            "downSourceStateID": 1, "upSourceStateID": 1, "downFlags": 0, "upFlags": 0,
            "continuedMotionDelta": {"x": 1, "y": 0}},
        "escapeCancellation": copy.deepcopy(workspace), "status": "captured" if passed else "failed",
        "gestureOutcomesVerified": passed, "originalBytesUnchanged": passed, "userFileSetUnchanged": passed}
    if not passed:
        case["reason"] = ESCAPE_FAILURE
        case["escapeCancellation"].update(matchesExpectedWorkspace=False,
            observedFilenames=sorted([existing, single]), selectedCountLabels=["2 Selected"])
    names = ["00-before-drag", "01-enter-top-padding", "02-leave-file-area", "03-reenter-top-padding", "04-after-escape"]
    if passed:
        names += ["05-before-accepted-drop", "06-after-accepted-drop"]

    def capture(name):
        value = {"stage": name, "captureKind": "screen-and-target-ax" if policy == "screenshots" else "target-ax-only",
                 "imagesCaptured": policy == "screenshots", "captureStartedSystemUptime": 1.0, "captureCompletedSystemUptime": 1.2}
        if policy == "screenshots":
            image = directory / (name + ".png")
            image.write_bytes(b"Portable hash fixture, not a native screenshot.\n")
            value.update(image=image.name, imageSHA256=sha256(image))
        return value

    case["stages"] = [capture(name) for name in names]
    case["setupSnapshot"] = capture("setup-before-hit-checks")
    case["diagnosticSnapshots"] = [capture("diagnostic-after-escape-held")]
    theme = {"theme": "orchard", "report": "orchard/report.json", "reportRetained": True,
             "status": case["status"], "gestureOutcomesVerified": passed, "cleanup": copy.deepcopy(cleanup)}
    if not passed:
        theme["reason"] = ESCAPE_FAILURE
    aggregate = {**context["provenance"], "schema": 2, "expectedThemes": ["orchard"], "targetKind": kind,
        "inputDriver": "CGEvent", "permissionRequested": False, "captureComparison": policy,
        "diagnosticOnly": True, "nativeAcceptanceXCTestExecuted": False,
        "imageCaptureEnabled": policy == "screenshots", "imagesCaptured": policy == "screenshots",
        "status": case["status"], "allThemesCaptured": passed, "gestureOutcomesVerified": passed, "themes": [theme]}
    if mutate:
        mutate(aggregate, case)
    (evidence / "report.json").write_text(json.dumps(aggregate))
    (directory / "report.json").write_text(json.dumps(case))
    if target == "control":
        (directory / "receiver.jsonl").write_text('{"schema":1,"event":"application-terminated"}\n')
    return 0 if passed else 1


class CaptureComparisonTests(unittest.TestCase):
    def test_exact_cancellation_failure_continues_but_never_becomes_success(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            commands = []

            def runner(command, log):
                commands.append(command)
                target, policy = CASES[len(commands) - 1]
                return emit_case(stage, context, target, policy)

            report = compare(stage, Path(temporary) / "output", context, runner)
            self.assertEqual(len(commands), 4)
            self.assertTrue(report["comparisonComplete"])
            self.assertFalse(report["allCasesPassed"])
            self.assertEqual(report["status"], "failed")
            for command, (target, policy) in zip(commands, CASES):
                self.assertEqual(command, [str(stage / "NativeDragReview"), str(stage)]
                    + (["--control"] if target == "control" else []) + ["--compare-capture", policy])

    def test_captured_requires_fresh_drop_and_both_capture_policies_work(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            sequence = iter(CASES)
            def runner(command, log):
                target, policy = next(sequence)
                return emit_case(stage, context, target, policy, passed=True)
            report = compare(stage, Path(temporary) / "output", context, runner)
            self.assertTrue(report["allCasesPassed"])
            self.assertEqual(report["status"], "passed")
            self.assertFalse(report["nativeAcceptanceXCTestExecuted"])
            self.assertEqual(report["C12"], "HOLD")

    def test_incomplete_or_unbound_first_case_prevents_all_later_input(self):
        mutations = {
            "cleanup": lambda a, c: c["cleanup"].update(completed=1),
            "permission": lambda a, c: c["preflight"].update(postEvents=False),
            "report": lambda a, c: a["themes"][0].update(reportRetained=False),
            "source": lambda a, c: c.update(observerExperimentCommit="0" * 40),
            "unknown": lambda a, c: c.update(reason="Unrelated startup failure"),
            "policy": lambda a, c: c.update(captureComparison="ax-only"),
            "protocol": lambda a, c: c["escapeKeyProtocol"].update(keyDownDwellSeconds=0.3),
        }
        for name, mutation in mutations.items():
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                stage, context = fixture(Path(temporary))
                calls = []
                def runner(command, log):
                    calls.append(command)
                    return emit_case(stage, context, "control", "screenshots", mutate=mutation)
                report = compare(stage, Path(temporary) / "output", context, runner)
                self.assertEqual(len(calls), 1)
                self.assertFalse(report["comparisonComplete"])
                self.assertEqual([c["outcome"] for c in report["cases"]][1:], ["not-run"] * 3)

    def test_changed_observer_bytes_stop_before_another_case(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            calls = []
            def runner(command, log):
                calls.append(command)
                result = emit_case(stage, context, "control", "screenshots")
                (stage / "NativeDragReview").write_bytes(b"changed after one case")
                return result
            report = compare(stage, Path(temporary) / "output", context, runner)
            self.assertEqual(len(calls), 1)
            self.assertFalse(report["inputsUnchanged"])
            self.assertEqual(report["cases"][0]["reasonCode"], "inputs-changed-after-case")

    def test_existing_evidence_is_never_replaced(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            evidence = stage / "NativeDragControlEvidence-Capture-screenshots"
            evidence.mkdir()
            (evidence / "prior.txt").write_text("retain")
            with self.assertRaisesRegex(ComparisonError, "evidence-already-exists"):
                compare(stage, Path(temporary) / "output", context, lambda *_: self.fail("unexpected input"))
            self.assertEqual((evidence / "prior.txt").read_text(), "retain")

    def test_ax_only_rejects_an_image_and_claimed_success_without_fresh_drop(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            emit_case(stage, context, "production", "ax-only", passed=True)
            directory = stage / "NativeDragEvidence-Capture-ax-only/orchard"
            (directory / "unexpected.png").write_bytes(b"unexpected")
            with self.assertRaisesRegex(ComparisonError, "unexpected-image-file"):
                classify(stage, context, "production", "ax-only", 0)
            (directory / "unexpected.png").unlink()
            report = json.loads((directory / "report.json").read_text())
            report["stages"] = [s for s in report["stages"] if s["stage"] != "06-after-accepted-drop"]
            (directory / "report.json").write_text(json.dumps(report))
            with self.assertRaisesRegex(ComparisonError, "incomplete-stages"):
                classify(stage, context, "production", "ax-only", 0)


if __name__ == "__main__":
    unittest.main()
