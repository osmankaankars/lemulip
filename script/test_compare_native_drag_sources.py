"""Portable evidence/stop tests. Synthetic records never execute GUI input."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import compare_native_drag_capture as capture
import compare_native_drag_lifecycle as lifecycle
import compare_native_drag_sources as sources
from test_compare_native_drag_capture import emit_case
from test_compare_native_drag_lifecycle import fixture as lifecycle_fixture


def fixture(parent):
    stage, context = lifecycle_fixture(parent)
    binary = stage / sources.SOURCE_BUNDLE / "Contents/MacOS" / sources.SOURCE_EXECUTABLE
    binary.parent.mkdir(parents=True)
    binary.write_bytes(b"Portable native source fixture; never execute.\n")
    (binary.parent.parent / "Info.plist").write_bytes(b"Portable nonexecutable bundle metadata.\n")
    context["provenance"].update(sourceGUI_SHA256=capture.sha256(binary),
        nativeDragSourceSourceSHA256=capture.sha256(capture.ROOT / "script/native_ui/NativeDragSource.swift"))
    (stage / "provenance.json").write_text(json.dumps(context["provenance"]))
    context["inputs"] = sources.input_snapshot(stage)
    return stage, context


def write_trace(path, records, case_name, pid):
    rows = []
    for index, row in enumerate(sorted(records, key=lambda r: r["systemUptime"])):
        rows.append({"schema": 1, "recordIndex": index, "pid": pid,
                     "sourceCase": case_name, "dragSourceKind": sources.source_kind(case_name), **row})
    path.write_text("".join(json.dumps(r) + "\n" for r in rows))


def read_trace(path):
    return [json.loads(line) for line in path.read_text().splitlines()]


def rewrite_trace(path, mutate):
    rows = read_trace(path)
    mutate(rows)
    path.write_text("".join(json.dumps(row) + "\n" for row in rows))


def emit(stage, context, case_name, passed=False, end_time=None, mutate=None):
    kind = sources.source_kind(case_name)
    existing, single = context["roles"]["Existing"], context["roles"]["Single"]
    geometry = {"coordinateSpace": "quartz-global-top-left", "finderWindow": "{{8, 281}, {920, 360}}",
                "finderIcon": "{{500, 350}, {32, 32}}", "sourcePoint": {"x": 516, "y": 366},
                "nativeWindow": "{{8, 281}, {920, 360}}" if kind == "native-appkit" else None,
                "nativeIcon": "{{500, 350}, {32, 32}}" if kind == "native-appkit" else None}

    def mouse(event_type, clock):
        return {"eventType": event_type, "scope": "plain-gesture", "sourceStateID": 1,
                "eventTap": "cghidEventTap", "postCalled": True,
                "systemUptimeBeforePost": clock, "systemUptimeAfterPost": clock + .01}

    def add_source(aggregate, case):
        for record in (aggregate, case):
            record.update(captureComparison="ax-only", observerLifecycle="appkit", sourceCase=case_name, dragSourceKind=kind,
                observerLifecycleAtStart={"mode": "appkit", "didFinishLaunching": True,
                    "nsApplicationPresent": True, "nsApplicationRunning": True,
                    "activationPolicy": 2, "threadIsMain": True, "taskPriorityRawValue": 21})
        case.update(targetApplicationPID=200,
            targetGeometry={"reviewWindow": "{{16, 32}, {920, 560}}", "entryInTopPadding": "{473.5, 155}",
                            "outside": "{473.5, 135}", "releasePoint": "{474.5, 155}"}, sourceGeometry=geometry,
            escapePostTiming={"downStartedSystemUptime": 9., "downCompletedSystemUptime": 9.01,
                "upStartedSystemUptime": 9.16, "upCompletedSystemUptime": 9.17, "heldSeconds": .16},
            mouseEvents=[mouse(1, 3), mouse(2, 3.1), mouse(1, 5), mouse(6, 6), mouse(6, 7), mouse(6, 8),
                         mouse(6, 9.1), mouse(2, 10)],
            escapeInputStates=[{"phase": "before-key-post", "systemUptime": 8.99,
                "foregroundBundleIdentifier": sources.SOURCE_ID if kind == "native-appkit" else "com.apple.finder",
                "foregroundPID": 300 if kind == "native-appkit" else 400, "mouseDownSent": True}])
        if passed:
            case["mouseEvents"] += [mouse(1, 12), mouse(6, 13), mouse(2, 14)]
        case["sourceGeometries"] = {"cancel-source": copy.deepcopy(geometry)}
        if passed:
            case["sourceGeometries"]["drop-source"] = copy.deepcopy(geometry)
        for cleanup in (case["cleanup"], aggregate["themes"][0]["cleanup"]):
            cleanup.update(sourceApplicationStopped=True, sourceBundleRegistryEmpty=True)
        if kind == "native-appkit":
            case.update(sourceApplicationPath=str(stage / sources.SOURCE_BUNDLE), sourceApplicationPID=300)
        if mutate:
            mutate(aggregate, case)

    code = emit_case(stage, context, "control", "ax-only-Lifecycle-appkit-Source-" + case_name, passed, add_source)
    folder = sources.evidence_for(stage, case_name) / "orchard"
    unchanged = {"originalBytesUnchanged": True, "fixtureFileSetUnchanged": True}
    receiver = [{"event": "application-start", "systemUptime": 1., "bundleIdentifier": "app.lemulip.NativeDragControl",
        "theme": "orchard", "originalSHA256": context["fixtures"], "fixtureFilenames": sorted(context["fixtures"]),
        "stagingRoot": str(stage), "bundlePath": str(stage / "Native Drag Control.app"),
        "executablePath": str(stage / "Native Drag Control.app/Contents/MacOS/NativeDragControl")},
        {"event": "application-ready", "systemUptime": 2.}]

    def received(event, clock, sequence=11, **extra):
        return {"event": event, "systemUptime": clock, "sequenceNumber": sequence, **unchanged,
                "sourceAllowedOperationMask": 1 if kind == "native-appkit" else 55,
                "pasteboardTypes": ["public.file-url"], "applicationActive": False,
                "selectedFilenames": [existing], **extra}

    receiver += [received("draggingEntered", 6.1, returnedCopy=True), received("draggingExited", 7.1),
                 received("draggingEntered", 8.1, returnedCopy=True)]
    if not passed:
        receiver += [received("performDragOperation", 10.2, accepted=True, selectedFilenames=[existing, single])]
    if passed:
        receiver += [received("draggingEnded", 9.3), received("draggingEntered", 13.1, sequence=12, returnedCopy=True),
            received("performDragOperation", 14.2, sequence=12, accepted=True, selectedFilenames=[existing, single])]
    receiver += [{"event": "application-terminated", "systemUptime": 17., **unchanged}]
    write_trace(folder / "receiver.jsonl", receiver, case_name, 200)
    if kind == "native-appkit":
        ready = {"event": "source-ready", "systemUptime": 2.5, "bundleIdentifier": sources.SOURCE_ID,
            "executableName": sources.SOURCE_EXECUTABLE, "bundleName": sources.SOURCE_BUNDLE,
            "stagingRoot": str(stage), "sourceBundlePath": str(stage / sources.SOURCE_BUNDLE),
            "geometryCoordinateSpace": "Quartz-global-top-left", "originalSHA256": context["fixtures"],
            "requestedWindowFrameCG": {"x": 8, "y": 281, "width": 920, "height": 360},
            "actualWindowFrameCG": {"x": 8, "y": 281, "width": 920, "height": 360},
            "imageFrameCG": {"x": 500, "y": 350, "width": 32, "height": 32},
            "sourcePointCG": geometry["sourcePoint"], "requestedSourcePointCG": geometry["sourcePoint"],
            **{k: context["provenance"][k] for k in (*sources.SOURCE_KEYS, "sourceCommit", "sourceTree",
                "observerExperimentCommit", "observerExperimentTree", "architecture")}}

        def callback(event, clock, index=1, **extra):
            return {"event": event, "systemUptime": clock + .001, "callbackSystemUptime": clock,
                    "sessionIndex": index, "sequenceNumber": 10 + index, "filename": single, **unchanged,
                    "callbackPointScreen": {"x": 474.5, "y": 745}, "callbackPointCoordinateSpace": "AppKit-screen-bottom-left",
                    "observedCursorCG": {"x": 474.5, "y": 155},
                    "applicationActive": True, "keyWindowNumber": 4, "offeredOperationMask": 1,
                    "pasteboardTypes": ["public.file-url"], "animatesToStartingPositionsOnCancelOrFail": True, **extra}

        records = [ready, callback("source-will-begin", 5.1), callback("source-moved", 6.05),
                   callback("source-moved", 8.05), callback("source-ended", end_time if end_time is not None else (9.25 if passed else 10.3),
                            operationRawValue=0 if passed else 1)]
        if passed:
            records += [callback("source-will-begin", 12.1, index=2), callback("source-moved", 13.05, index=2),
                        callback("source-ended", 14.3, index=2, operationRawValue=1)]
        records += [{"event": "application-terminating", "systemUptime": 18., **unchanged,
                     "activeSession": False, "sessionCount": 2 if passed else 1}]
        write_trace(folder / "source.jsonl", records, case_name, 300)
    return code


class SourceComparisonTests(unittest.TestCase):
    def run_comparison(self, stage, context, output, passed=False, change=None):
        commands = []
        def runner(command, log):
            name = sources.CASES[len(commands)]
            commands.append(command)
            code = emit(stage, context, name, passed)
            if change:
                change(name, sources.evidence_for(stage, name) / "orchard", stage)
            return code
        return sources.compare(stage, output, context, runner), commands

    def test_fixed_four_case_order_continues_expected_failures_without_reruns(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            report, commands = self.run_comparison(stage, context, Path(temporary) / "out")
            self.assertTrue(report["comparisonComplete"])
            self.assertFalse(report["allCasesPassed"])
            self.assertEqual(report["caseOrder"], list(sources.CASES))
            self.assertEqual(len(commands), 4)
            for command, name, result in zip(commands, sources.CASES, report["cases"]):
                self.assertEqual(command, [str(stage / "NativeDragReviewAppKit"), str(stage), "--control",
                    "--compare-capture", "ax-only", "--compare-source", name])
                self.assertEqual(result["outcome"], "escape-cancellation-failed")
                if name.startswith("appkit"):
                    self.assertEqual(result["sourceSession"]["classification"], "accepted-after-release")
                else:
                    self.assertEqual(result["sourceSession"]["classification"], "source-session-unobserved")

    def test_complete_success_keeps_diagnostic_hold_and_separate_source_evidence(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            report, commands = self.run_comparison(stage, context, Path(temporary) / "out", passed=True)
            self.assertEqual(len(commands), 4)
            self.assertTrue(report["allCasesPassed"])
            self.assertEqual(report["C12"], "HOLD")
            self.assertFalse(report["releaseReady"])
            self.assertFalse(report["nativeAcceptanceXCTestExecuted"])
            self.assertFalse(report["physicalInputVerified"])
            for result in report["cases"][1:3]:
                self.assertEqual(result["sourceSession"]["classification"], "cancelled-before-release")
                self.assertEqual(result["sourceSession"]["freshSession"]["end"]["operationRawValue"], 1)

    def test_none_after_release_is_not_escape_cancellation_proof(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            code = emit(stage, context, "appkit-first", passed=True, end_time=10.5)
            result = sources.classify(stage, context, "appkit-first", code)
            self.assertTrue(result["passed"])
            self.assertEqual(result["axOutcome"], "captured")
            self.assertEqual(result["sourceSession"]["classification"], "indeterminate-end-after-release")

    def test_ending_before_escape_cannot_count_as_escape_success(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            code = emit(stage, context, "appkit-first", passed=True, end_time=8.5)
            result = sources.classify(stage, context, "appkit-first", code)
            self.assertFalse(result["passed"])
            self.assertFalse(result["mayContinue"])
            self.assertEqual(result["axOutcome"], "captured")
            self.assertEqual(result["sourceSession"]["classification"], "indeterminate-end-before-escape")

    def test_wrong_bindings_permissions_cleanup_or_geometry_stop_next_input(self):
        mutations = {
            "wrong-case": lambda a, c: c.update(sourceCase="appkit-second"),
            "wrong-kind": lambda a, c: a.update(dragSourceKind="finder"),
            "wrong-source-hash": lambda a, c: c.update(sourceGUI_SHA256="0" * 64),
            "wrong-path": lambda a, c: c.update(sourceApplicationPath="/elsewhere/Native Drag Source.app"),
            "wrong-target-pid": lambda a, c: c.update(targetApplicationPID=999),
            "permission": lambda a, c: c["preflight"].update(postEvents=False),
            "source-still-running": lambda a, c: c["cleanup"].update(sourceApplicationStopped=False),
            "source-registry": lambda a, c: c["cleanup"].update(sourceBundleRegistryEmpty=False),
            "unknown-error": lambda a, c: c.update(reason="Unexpected startup failure"),
            "geometry": lambda a, c: c["targetGeometry"].update(outside="{473.5, 134}"),
        }
        for name, mutation in mutations.items():
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                stage, context = fixture(Path(temporary))
                calls = []
                def runner(command, log):
                    case_name = sources.CASES[len(calls)]
                    calls.append(command)
                    return emit(stage, context, case_name, mutate=mutation if case_name == "appkit-first" else None)
                report = sources.compare(stage, Path(temporary) / "out", context, runner)
                self.assertEqual(len(calls), 2)
                self.assertEqual(report["cases"][1]["outcome"], "not-comparable")
                self.assertEqual([r["outcome"] for r in report["cases"]][2:], ["not-run", "not-run"])

    def test_missing_bad_or_unbound_source_trace_stops_later_cases(self):
        def only(name, action):
            def change(case_name, directory, stage):
                if case_name == "appkit-first":
                    action(directory / name)
            return change
        mutations = {
            "missing": lambda p: p.unlink(),
            "truncated": lambda p: p.write_bytes(p.read_bytes()[:-1]),
            "malformed": lambda p: p.write_text("{not json}\n"),
            "wrong-pid": lambda p: rewrite_trace(p, lambda rows: rows[1].update(pid=301)),
            "wrong-index": lambda p: rewrite_trace(p, lambda rows: rows[1].update(recordIndex=9)),
            "wrong-source-ready": lambda p: rewrite_trace(p, lambda rows: rows[0].update(sourceGUI_SHA256="f" * 64)),
            "wrong-fixture": lambda p: rewrite_trace(p, lambda rows: rows[1].update(filename="Different.txt")),
            "wrong-sequence": lambda p: rewrite_trace(p, lambda rows: [r.update(sequenceNumber=88) for r in rows if "sequenceNumber" in r]),
            "missing-end": lambda p: rewrite_trace(p, lambda rows: rows.__setitem__(slice(None), [r for r in rows if r["event"] != "source-ended"])),
            "missing-termination": lambda p: rewrite_trace(p, lambda rows: rows.pop()),
            "source-mutated-original": lambda p: rewrite_trace(p, lambda rows: rows[1].update(originalBytesUnchanged=False)),
            "source-error": lambda p: rewrite_trace(p, lambda rows: rows[1].update(event="source-failed")),
        }
        for name, mutation in mutations.items():
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                stage, context = fixture(Path(temporary))
                report, commands = self.run_comparison(stage, context, Path(temporary) / "out", change=only("source.jsonl", mutation))
                self.assertEqual(len(commands), 2)
                self.assertEqual(report["cases"][1]["outcome"], "not-comparable")
                self.assertFalse(report["comparisonComplete"])

    def test_existing_only_ax_cannot_hide_missing_first_drag_or_wrong_fresh_drop(self):
        mutations = {
            "first-never-began": lambda d: rewrite_trace(d / "source.jsonl", lambda rows:
                rows[1].update(event="source-moved")),
            "no-target-entry": lambda d: rewrite_trace(d / "receiver.jsonl", lambda rows:
                rows[2].update(event="draggingUpdated")),
            "no-target-exit": lambda d: rewrite_trace(d / "receiver.jsonl", lambda rows:
                rows[3].update(event="draggingUpdated")),
            "no-target-reentry": lambda d: rewrite_trace(d / "receiver.jsonl", lambda rows:
                rows[4].update(returnedCopy=False)),
            "fresh-reuses-sequence": lambda d: rewrite_trace(d / "source.jsonl", lambda rows:
                [r.update(sequenceNumber=11) for r in rows if r.get("sessionIndex") == 2]),
            "fresh-no-copy-end": lambda d: rewrite_trace(d / "source.jsonl", lambda rows:
                [r.update(operationRawValue=0) for r in rows if r.get("sessionIndex") == 2 and r["event"] == "source-ended"]),
            "fresh-no-accepted-perform": lambda d: rewrite_trace(d / "receiver.jsonl", lambda rows:
                [r.update(accepted=False) for r in rows if r["event"] == "performDragOperation"]),
        }
        for name, mutation in mutations.items():
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                stage, context = fixture(Path(temporary))
                def change(case_name, directory, stage):
                    if case_name == "appkit-first":
                        mutation(directory)
                report, commands = self.run_comparison(stage, context, Path(temporary) / "out", passed=True, change=change)
                self.assertEqual(len(commands), 2)
                self.assertFalse(report["allCasesPassed"])
                self.assertEqual(report["cases"][2]["outcome"], "not-run")

    def test_source_none_never_overrides_target_accepted_drop(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            code = emit(stage, context, "appkit-first")
            path = sources.evidence_for(stage, "appkit-first") / "orchard/source.jsonl"
            rewrite_trace(path, lambda rows: [r.update(operationRawValue=0) for r in rows if r["event"] == "source-ended"])
            with self.assertRaisesRegex(capture.ComparisonError, "source-none-with-target-acceptance"):
                sources.classify(stage, context, "appkit-first", code)

    def test_missing_end_retains_ax_result_but_stops_and_never_means_ignored_escape(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            def change(case_name, directory, stage):
                if case_name == "appkit-first":
                    path = directory / "source.jsonl"
                    rows = [r for r in read_trace(path) if r["event"] != "source-ended"]
                    for index, row in enumerate(rows):
                        row["recordIndex"] = index
                    path.write_text("".join(json.dumps(r) + "\n" for r in rows))
            report, commands = self.run_comparison(stage, context, Path(temporary) / "out", change=change)
            self.assertEqual(len(commands), 2)
            result = report["cases"][1]
            self.assertEqual(result["axOutcome"], "escape-cancellation-failed")
            self.assertEqual(result["sourceSession"]["classification"], "session-end-unobserved")
            self.assertEqual(result["reasonCode"], "source-session-end-unobserved")

    def test_finder_source_cleanup_and_fresh_geometry_must_also_be_verified(self):
        for change in (lambda c: c["cleanup"].update(sourceBundleRegistryEmpty=False),
                       lambda c: c["sourceGeometries"]["drop-source"].update(finderIcon="{{501, 350}, {32, 32}}")):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as temporary:
                stage, context = fixture(Path(temporary))
                calls = []
                def runner(command, log):
                    calls.append(command)
                    return emit(stage, context, "finder-first", passed=True, mutate=lambda a, c: change(c))
                report = sources.compare(stage, Path(temporary) / "out", context, runner)
                self.assertEqual(len(calls), 1)
                self.assertFalse(report["comparisonComplete"])

    def test_all_source_bundle_bytes_and_both_observers_are_pinned(self):
        names = ["NativeDragReview", "NativeDragReviewAppKit", "Native Drag Source.app/Contents/Info.plist",
                 "Native Drag Source.app/Contents/MacOS/NativeDragSource", "Native Drag Control.app/Contents/MacOS/NativeDragControl"]
        for name in names:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                stage, context = fixture(Path(temporary))
                def change(case_name, directory, stage):
                    (stage / name).write_bytes(b"Changed input must stop the sequence.")
                report, commands = self.run_comparison(stage, context, Path(temporary) / "out", change=change)
                self.assertEqual(len(commands), 1)
                self.assertFalse(report["inputsUnchanged"])
                self.assertEqual(report["cases"][0]["reasonCode"], "inputs-changed-after-case")

    def test_fresh_drop_stage_and_source_bindings_remain_mandatory(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            def mutate(a, c):
                c["stages"] = [s for s in c["stages"] if s["stage"] != "06-after-accepted-drop"]
            code = emit(stage, context, "appkit-first", passed=True, mutate=mutate)
            with self.assertRaisesRegex(capture.ComparisonError, "incomplete-stages"):
                sources.classify(stage, context, "appkit-first", code)
            with patch.object(lifecycle, "context_for", return_value=context):
                self.assertEqual(sources.context_for(stage, "unused")["inputs"], sources.input_snapshot(stage))
                context["provenance"]["sourceGUI_SHA256"] = "0" * 64
                with self.assertRaisesRegex(capture.ComparisonError, "native-source-hash-link"):
                    sources.context_for(stage, "unused")

    def test_existing_evidence_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            evidence = sources.evidence_for(stage, "appkit-second")
            evidence.mkdir()
            with self.assertRaisesRegex(capture.ComparisonError, "evidence-already-exists"):
                sources.compare(stage, Path(temporary) / "out", context, lambda *_: self.fail("unexpected input"))


if __name__ == "__main__":
    unittest.main()
