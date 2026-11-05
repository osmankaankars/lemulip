"""Portable D11 falsification tests; no native process or input is executed."""
import copy
import json
from pathlib import Path
import tempfile
import unittest

import compare_native_drag_activation as activation
import compare_native_drag_capture as capture
import compare_native_drag_sources as sources
from test_compare_native_drag_sources import fixture, emit as emit_source, read_trace, rewrite_trace


def save_rows(path, rows):
    rows.sort(key=lambda r: r["systemUptime"])
    for index, row in enumerate(rows):
        row["recordIndex"] = index
    path.write_text("".join(json.dumps(row) + "\n" for row in rows))


def state(active, number=7, key=None):
    if key is None:
        key = number if active else None
    return {"applicationActive": active, "keyWindowNumber": key, "mainWindowNumber": key,
        "windowNumber": number, "windowIsKey": active if number is not None else None,
        "windowIsMain": active if number is not None else None, "windowCanBecomeKey": True if number is not None else None,
        "windowCanBecomeMain": True if number is not None else None, "windowVisible": True if number is not None else None,
        "observedCursorScreen": {"x": 474.5, "y": 745}, "cursorCoordinateSpace": "AppKit-screen-bottom-left"}


def emit(stage, context, case_name, passed=False, hooks=True, target_activates=None):
    # Retain the D10 fixture's strict native records, then explicitly bind them
    # to D11's separate namespace. This is test data, not a runtime alias route.
    code = emit_source(stage, context, "appkit-first", passed=passed)
    folder = activation.evidence_for(stage, case_name)
    sources.evidence_for(stage, "appkit-first").rename(folder)
    directory = folder / "orchard"
    binding = activation.bindings(case_name)
    present = binding["targetRaisePolicy"] == "present"
    if target_activates is None:
        target_activates = present
    report = capture.read_json(directory / "report.json")
    aggregate = capture.read_json(folder / "report.json")
    for record in (report, aggregate):
        record.update(binding)
    report["targetGeometry"]["escapeMotionPoint"] = report["targetGeometry"]["releasePoint"]
    report["inputSource"] = {"kind": "shared-hid-keyboard-filter-comparison", "sourceStateID": 1,
        "localEventsSuppressionInterval": .25, "previousSuppressionIntervalFilter": 7,
        "previousRemoteMouseDragFilter": 7, "suppressionIntervalFilter": 7, "remoteMouseDragFilter": 7,
        "scope": "Portable native-shaped input receipt; never execute."}
    origin = report["sourceGeometry"]["sourcePoint"]
    entry, outside, escape = {"x": 473.5, "y": 155}, {"x": 473.5, "y": 135}, {"x": 474.5, "y": 155}

    def mouse(kind, clock, point):
        return {"scope": "plain-gesture", "eventType": kind, "eventTap": "cghidEventTap", "sourceStateID": 1,
            "mouseEventNumber": 0, "timestampNanoseconds": 0, "location": point,
            "constructorFlags": 536870912, "postedFlags": 536870912, "sessionFlagsBeforePost": 536870912,
            "systemUptimeBeforePost": clock, "systemUptimeAfterPost": clock + .001, "postCalled": True,
            "mouseEnteredSystemUptime": clock - .001, "guardsAndConstructionCompletedSystemUptime": clock}

    mouse_events = [mouse(5, 2.9, origin), mouse(1, 3., origin), mouse(2, 3.1, origin), mouse(1, 5., origin)]
    previous = origin
    for start_time, destination in ((5.2, entry), (6.2, outside), (7.2, entry)):
        for step in range(1, 19):
            location = {axis: previous[axis] + (destination[axis] - previous[axis]) * step / 18 for axis in ("x", "y")}
            mouse_events.append(mouse(6, start_time + step * .04, location))
        previous = destination
    mouse_events += [mouse(6, 9.1, escape), mouse(2, 10., escape)]
    if passed:
        mouse_events += [mouse(1, 11.2, origin), mouse(2, 11.3, origin), mouse(1, 12., origin)]
        for step in range(1, 19):
            mouse_events.append(mouse(6, 12.2 + step * .04,
                {axis: origin[axis] + (entry[axis] - origin[axis]) * step / 18 for axis in ("x", "y")}))
        mouse_events += [mouse(2, 14., entry)]
    report["mouseEvents"] = mouse_events
    requests = []
    for index, phase in enumerate(activation.RAISE_PHASES + (["focus-native-source"] if passed else [])):
        started = (2.1, 2.2, 2.3, 2.7, 11.)[index]
        requests.append({"requestIndex": index, "phase": phase, "targetRaisePolicy": binding["targetRaisePolicy"],
            "performed": present, "status": 0 if present else None, "startedSystemUptime": started,
            "completedSystemUptime": started + .01, "targetPID": 200,
            "targetWindowTitle": "Native Drag Control", "mouseDownSent": False})
    report["targetRaiseRequests"] = requests
    (directory / "report.json").write_text(json.dumps(report))
    (folder / "report.json").write_text(json.dumps(aggregate))
    for name in ("receiver.jsonl", "source.jsonl"):
        rows = read_trace(directory / name)
        for row in rows:
            row.update(binding)
        if name == "source.jsonl":
            for row in rows:
                clock = row.get("callbackSystemUptime", row["systemUptime"])
                row.update(state(not target_activates or clock < 8.5, number=4))
            if target_activates:
                for event, clock in (("window-resigned-key", 8.5), ("application-resigned-active", 8.51)):
                    rows.append({"schema": 1, "pid": 300, **binding, "event": event,
                        "callbackSystemUptime": clock, "systemUptime": clock + .001, **state(False, number=4)})
        save_rows(directory / name, rows)
    provenance_keys = ("nativeDragControlSourceSHA256", "controlGUI_SHA256", "observerExperimentCommit", "observerExperimentTree",
                       "sourceCommit", "sourceTree", "architecture")

    def row(event, clock, active=False, number=7, **fields):
        return {"schema": 1, "pid": 200, **binding, "event": event, "systemUptime": clock + .0001,
                "callbackSystemUptime": clock, **state(active, number), **fields}

    rows = [row("activation-start", 1., number=None,
        **{key: context["provenance"][key] for key in provenance_keys},
        bundleIdentifier="app.lemulip.NativeDragControl", executableName="NativeDragControl", bundleName="Native Drag Control.app",
        targetBundlePath=str(stage / "Native Drag Control.app"), stagingRoot=str(stage), originalSHA256=context["fixtures"]),
        row("activation-ready", 2., active=True, windowTitle="Native Drag Control", normalNSWindow=True,
            windowClass="NativeDragActivationWindow", styleMask=15, windowLevel=0),
        row("application-resigned-active", 2.55)]
    if hooks and present:
        for request in requests:
            started = request["startedSystemUptime"]
            rows += [row("target-ax-raise-enter", started + .001, raiseIndex=request["requestIndex"]),
                     row("target-ax-raise-return", started + .005, raiseIndex=request["requestIndex"], actionTriggered=True)]
    if target_activates:
        rows += [row("appkit-defined-enter", 8.48, dispatchIndex=0, eventType=13, eventSubtype=1, eventTimestamp=8.47, eventWindowNumber=7),
                 row("appkit-defined-return", 8.49, active=True, dispatchIndex=0, eventType=13, eventSubtype=1,
                     eventTimestamp=8.47, eventWindowNumber=7),
                 row("application-became-active", 8.5, active=True), row("window-became-key", 8.51, active=True)]
    rows.append(row("activation-terminating", 17., active=target_activates, originalBytesUnchanged=True, fixtureFileSetUnchanged=True))
    save_rows(directory / "activation.jsonl", rows)
    return code


def alter_report(directory, action):
    path = directory / "report.json"
    record = capture.read_json(path)
    action(record)
    path.write_text(json.dumps(record))


class ActivationComparisonTests(unittest.TestCase):
    def run_cases(self, stage, context, output, pass_for=None, change=None, hooks=True):
        commands = []
        def runner(command, log):
            name = activation.CASES[len(commands)]
            commands.append(command)
            code = emit(stage, context, name, passed=bool(pass_for and pass_for(name)), hooks=hooks)
            if change:
                change(name, activation.evidence_for(stage, name) / "orchard")
            return code
        return activation.compare(stage, output, context, runner), commands

    def test_fixed_abba_keeps_all_expected_failures_without_claiming_cause_or_release(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            report, commands = self.run_cases(stage, context, Path(temporary) / "out")
            self.assertTrue(report["comparisonComplete"])
            self.assertFalse(report["allCasesPassed"])
            self.assertEqual(report["C12"], "HOLD")
            self.assertFalse(report["releaseReady"])
            self.assertFalse(report["nativeAcceptanceXCTestExecuted"])
            self.assertEqual(report["activationComparison"]["causalConclusion"], "not-established")
            for command, name, case in zip(commands, activation.CASES, report["cases"]):
                self.assertEqual(command, [str(stage / "NativeDragReviewAppKit"), str(stage), "--control",
                    "--compare-capture", "ax-only", "--compare-activation", name])
                self.assertEqual(case["outcome"], "escape-cancellation-failed")
                self.assertEqual(case["sourceSession"]["classification"], "accepted-after-release")
                self.assertEqual(len(case["targetRaiseRequests"]), 4)

    def test_no_raise_pass_requires_fresh_drop_and_is_separate_from_activation_contrast(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            report, commands = self.run_cases(stage, context, Path(temporary) / "out", pass_for=lambda name: name.startswith("no-raise"))
            self.assertEqual(len(commands), 4)
            self.assertTrue(report["comparisonComplete"])
            self.assertFalse(report["allCasesPassed"])
            self.assertTrue(report["activationComparison"]["activationContrastObserved"])
            for case in report["cases"][1:3]:
                self.assertTrue(case["passed"])
                self.assertEqual(len(case["targetRaiseRequests"]), 5)
                self.assertEqual(case["sourceSession"]["freshSession"]["end"]["operationRawValue"], 1)
                self.assertEqual(case["activationEvidence"]["sourceStateReceipts"][0]["cursorCoordinateSpace"],
                                 "AppKit-screen-bottom-left")
                self.assertIn("observedCursorScreen", case["activationEvidence"]["targetStateBeforeEscape"])

    def test_unobserved_raise_hook_or_unexpected_omitted_hook_does_not_discard_safe_outcome(self):
        for unexpected in (False, True):
            with self.subTest(unexpected=unexpected), tempfile.TemporaryDirectory() as temporary:
                stage, context = fixture(Path(temporary))
                def change(name, directory):
                    if unexpected and name == "no-raise-first":
                        rows = read_trace(directory / "activation.jsonl")
                        for event, clock in (("target-ax-raise-enter", 2.71), ("target-ax-raise-return", 2.72)):
                            rows.append({**copy.deepcopy(rows[1]), "event": event, "raiseIndex": 0,
                                "callbackSystemUptime": clock, "systemUptime": clock + .001, "actionTriggered": True})
                        save_rows(directory / "activation.jsonl", rows)
                report, commands = self.run_cases(stage, context, Path(temporary) / "out", hooks=False,
                    pass_for=lambda name: name.startswith("no-raise"), change=change)
                self.assertEqual(len(commands), 4)
                self.assertTrue(report["comparisonComplete"])
                self.assertEqual(report["cases"][0]["activationEvidence"]["targetAXHookCoverage"], "unobserved")
                if unexpected:
                    self.assertTrue(report["cases"][1]["passed"])
                    self.assertFalse(report["activationComparison"]["activationContrastObserved"])
                    self.assertEqual(report["activationComparison"]["omittedCasesWithTargetRaiseReceipts"], ["no-raise-first"])

    def test_every_raise_site_needs_an_explicit_correct_unheld_decision(self):
        changes = {
            "missing-site": lambda c: c["targetRaiseRequests"].pop(1),
            "wrong-site-order": lambda c: c["targetRaiseRequests"][0].update(phase="focus-native-source"),
            "false-omission": lambda c: c["targetRaiseRequests"][0].update(performed=True, status=0),
            "claimed-held": lambda c: c["targetRaiseRequests"][0].update(mouseDownSent=True),
            "wrong-pid": lambda c: c["targetRaiseRequests"][0].update(targetPID=201),
            "wrong-policy": lambda c: c["targetRaiseRequests"][0].update(targetRaisePolicy="present"),
            "during-click": lambda c: c["targetRaiseRequests"][3].update(startedSystemUptime=3.02, completedSystemUptime=3.04),
            "during-drag": lambda c: c["targetRaiseRequests"][3].update(startedSystemUptime=7., completedSystemUptime=7.1),
        }
        for label, mutation in changes.items():
            with self.subTest(label=label), tempfile.TemporaryDirectory() as temporary:
                stage, context = fixture(Path(temporary))
                def change(name, directory):
                    if name == "no-raise-first":
                        alter_report(directory, mutation)
                report, commands = self.run_cases(stage, context, Path(temporary) / "out", change=change)
                self.assertEqual(len(commands), 2)
                self.assertEqual(report["cases"][1]["outcome"], "not-comparable")
                self.assertEqual([r["outcome"] for r in report["cases"]][2:], ["not-run", "not-run"])

    def test_bad_activation_identity_missing_lifecycle_or_unpaired_dispatch_stops(self):
        mutations = {
            "missing": lambda p: p.unlink(),
            "truncated": lambda p: p.write_bytes(p.read_bytes()[:-1]),
            "wrong-case": lambda p: rewrite_trace(p, lambda rows: rows[0].update(activationCase="raise-second")),
            "wrong-pid": lambda p: rewrite_trace(p, lambda rows: rows[0].update(pid=201)),
            "wrong-provenance": lambda p: rewrite_trace(p, lambda rows: rows[0].update(controlGUI_SHA256="f" * 64)),
            "missing-ready": lambda p: rewrite_trace(p, lambda rows: rows[1].update(event="application-became-active")),
            "missing-termination": lambda p: rewrite_trace(p, lambda rows: rows.pop()),
            "missing-return": lambda p: rewrite_trace(p, lambda rows: next(r for r in rows if r["event"] == "target-ax-raise-return").update(event="application-became-active")),
            "return-index": lambda p: rewrite_trace(p, lambda rows: next(r for r in rows if r["event"] == "appkit-defined-return").update(dispatchIndex=99)),
            "window-changed": lambda p: rewrite_trace(p, lambda rows: rows[-1].update(windowNumber=99)),
        }
        for label, mutation in mutations.items():
            with self.subTest(label=label), tempfile.TemporaryDirectory() as temporary:
                stage, context = fixture(Path(temporary))
                def change(name, directory):
                    if name == "raise-first":
                        mutation(directory / "activation.jsonl")
                report, commands = self.run_cases(stage, context, Path(temporary) / "out", change=change)
                self.assertEqual(len(commands), 1)
                self.assertFalse(report["comparisonComplete"])
                self.assertTrue(report["cases"][0]["passiveEvidenceInvalid"])
                self.assertEqual(report["cases"][0]["axOutcome"], "escape-cancellation-failed")
                self.assertEqual(report["cases"][0]["strictNativeOutcome"]["outcome"], "escape-cancellation-failed")

    def test_initial_source_focus_is_process_local_not_observer_cached_foreground(self):
        for field, value in (("applicationActive", False), ("keyWindowNumber", 99), ("windowIsKey", False)):
            with self.subTest(field=field), tempfile.TemporaryDirectory() as temporary:
                stage, context = fixture(Path(temporary))
                def change(name, directory):
                    if name == "no-raise-first":
                        rewrite_trace(directory / "source.jsonl", lambda rows:
                            next(r for r in rows if r["event"] == "source-will-begin").update({field: value}))
                report, commands = self.run_cases(stage, context, Path(temporary) / "out", change=change)
                self.assertEqual(len(commands), 2)
                self.assertEqual(report["cases"][1]["reasonCode"], "activation-source-not-initially-focused")

    def test_missing_first_drag_or_fresh_drop_cannot_become_omission_success(self):
        changes = {
            "missing-entry": lambda d: rewrite_trace(d / "receiver.jsonl", lambda rows:
                next(r for r in rows if r["event"] == "draggingEntered").update(event="draggingUpdated")),
            "wrong-source-sequence": lambda d: rewrite_trace(d / "source.jsonl", lambda rows:
                [r.update(sequenceNumber=99) for r in rows if r.get("sessionIndex") == 1]),
            "missing-fresh-stage": lambda d: alter_report(d, lambda c: c.update(stages=[r for r in c["stages"] if r["stage"] != "06-after-accepted-drop"])),
            "missing-fresh-copy": lambda d: rewrite_trace(d / "source.jsonl", lambda rows:
                [r.update(operationRawValue=0) for r in rows if r.get("sessionIndex") == 2 and r["event"] == "source-ended"]),
            "missing-fresh-decision": lambda d: alter_report(d, lambda c: c["targetRaiseRequests"].pop()),
        }
        for label, mutation in changes.items():
            with self.subTest(label=label), tempfile.TemporaryDirectory() as temporary:
                stage, context = fixture(Path(temporary))
                def change(name, directory):
                    if name == "no-raise-first":
                        mutation(directory)
                report, commands = self.run_cases(stage, context, Path(temporary) / "out", pass_for=lambda n: n.startswith("no-raise"), change=change)
                self.assertEqual(len(commands), 2)
                self.assertFalse(report["allCasesPassed"])

    def test_changed_pointer_input_or_cleanup_stops_and_late_none_stays_indeterminate(self):
        changes = {
            "pointer": lambda c: c["mouseEvents"][15]["location"].update(x=600),
            "input-source": lambda c: c["inputSource"].update(localEventsSuppressionInterval=.5),
            "cleanup": lambda c: c["cleanup"].update(sourceBundleRegistryEmpty=False),
        }
        for label, mutation in changes.items():
            with self.subTest(label=label), tempfile.TemporaryDirectory() as temporary:
                stage, context = fixture(Path(temporary))
                def change(name, directory):
                    if name == "no-raise-first":
                        alter_report(directory, mutation)
                report, commands = self.run_cases(stage, context, Path(temporary) / "out", change=change)
                self.assertEqual(len(commands), 2)
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            code = emit(stage, context, "no-raise-first", passed=True)
            path = activation.evidence_for(stage, "no-raise-first") / "orchard/source.jsonl"
            rows = read_trace(path)
            next(r for r in rows if r["event"] == "source-ended" and r["sessionIndex"] == 1).update(
                callbackSystemUptime=10.5, systemUptime=10.501)
            save_rows(path, rows)
            result = activation.classify(stage, context, "no-raise-first", code)
            self.assertTrue(result["passed"])
            self.assertEqual(result["sourceSession"]["classification"], "indeterminate-end-after-release")

    def test_changed_inputs_stop_and_unexpected_safe_baseline_pass_does_not_retry(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            def change(name, directory):
                (stage / "NativeDragReviewAppKit").write_bytes(b"Changed executable")
            report, commands = self.run_cases(stage, context, Path(temporary) / "out", change=change)
            self.assertEqual(len(commands), 1)
            self.assertFalse(report["inputsUnchanged"])
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            report, commands = self.run_cases(stage, context, Path(temporary) / "out", pass_for=lambda n: True)
            self.assertEqual(len(commands), 4)
            self.assertTrue(report["allCasesPassed"])
            self.assertEqual(report["activationComparison"]["causalConclusion"], "not-established")
            self.assertFalse(report["releaseReady"])
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            def change(name, directory):
                if name == "no-raise-first":
                    rewrite_trace(directory / "activation.jsonl", lambda rows:
                        next(r for r in rows if r["event"] == "activation-ready").update(windowLevel=1))
            report, commands = self.run_cases(stage, context, Path(temporary) / "out", change=change)
            self.assertEqual(len(commands), 2)
            self.assertEqual(report["cases"][1]["reasonCode"], "activation-shared-protocol-changed")
            self.assertEqual(report["cases"][1]["strictNativeOutcome"]["outcome"], "escape-cancellation-failed")

    def test_d10_contract_does_not_implicitly_accept_activation_cases(self):
        self.assertEqual(sources.CASES, ("finder-first", "appkit-first", "appkit-second", "finder-second"))
        for name in activation.CASES:
            with self.subTest(name=name), self.assertRaisesRegex(capture.ComparisonError, "unknown-source-case"):
                sources.source_kind(name)
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            emit_source(stage, context, "appkit-first")
            result = sources.classify(stage, context, "appkit-first", 1)
            self.assertNotIn("activationCase", result)
            self.assertEqual(result["outcome"], "escape-cancellation-failed")
            evidence = activation.evidence_for(stage, "raise-second")
            evidence.mkdir()
            with self.assertRaisesRegex(capture.ComparisonError, "evidence-already-exists"):
                activation.compare(stage, Path(temporary) / "out", context, lambda *_: self.fail("unexpected input"))


if __name__ == "__main__":
    unittest.main()
