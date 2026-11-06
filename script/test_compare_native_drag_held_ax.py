"""Portable D12 evidence tests; none of these records drives native input."""
import copy
import json
from pathlib import Path
import tempfile
import unittest

import compare_native_drag_activation as activation
import compare_native_drag_capture as capture
import compare_native_drag_held_ax as held_ax
import compare_native_drag_sources as sources
from test_compare_native_drag_activation import emit as emit_activation, save_rows
from test_compare_native_drag_sources import fixture as source_fixture, read_trace


def fixture(parent):
    stage, context = source_fixture(parent)
    context["provenance"]["heldAXComparatorSourceSHA256"] = capture.sha256(Path(held_ax.__file__))
    (stage / "provenance.json").write_text(json.dumps(context["provenance"]))
    context["inputs"] = sources.input_snapshot(stage)
    return stage, context


def emit(stage, context, case_name, passed=False, target_activates=None):
    """Reuse native-shaped D11 trace contracts, inserting declared D12 slots."""
    code = emit_activation(stage, context, case_name, passed=passed, target_activates=target_activates)
    folder = held_ax.evidence_for(stage, case_name)
    directory = folder / "orchard"
    report = capture.read_json(directory / "report.json")
    policy = held_ax.bindings(case_name)["heldAXPolicy"]
    thresholds = (6.12, 7.12, 8.12, 8.25, 9.35, 9.50) + ((13.25,) if passed else ())
    duration = .25  # Fixed requirement, independent of the classifier constant.

    def mapped(clock):
        return clock + duration * sum(threshold < clock for threshold in thresholds)

    def remap(value):
        if isinstance(value, list):
            return [remap(row) for row in value]
        if isinstance(value, dict):
            return {key: mapped(item) if (key.endswith("SystemUptime") or key.startswith("systemUptime") or key == "eventTimestamp")
                    and type(item) in (int, float) else remap(item) for key, item in value.items()}
        return value

    report = remap(report)
    for name in ("source.jsonl", "receiver.jsonl", "activation.jsonl"):
        save_rows(directory / name, remap(read_trace(directory / name)))

    existing, single = context["roles"]["Existing"], context["roles"]["Single"]

    def workspace(expected, observed=None):
        observed = expected if observed is None else observed
        return {"expectedFilenames": sorted(expected), "observedFilenames": sorted(observed),
            "matchesExpectedWorkspace": set(expected) == set(observed),
            "expectedSelectedCountLabel": f"{len(expected)} Selected",
            "expectedSelectedCountMatches": int(set(expected) == set(observed)),
            "selectedCountLabels": [f"{len(observed)} Selected"],
            "fixtureRemoveButtonCounts": {name: int(name in observed) for name in context["fixtures"]}}

    report["heldAXInitialWorkspace"] = {"startedSystemUptime": 4.8, "completedSystemUptime": 4.82,
                                         "workspace": workspace([existing])}
    report["escapeCancellation"] = workspace([existing], [existing] if passed else [existing, single])
    slot_names = list(held_ax.CANCEL_SLOTS) + ([held_ax.FRESH_SLOT] if passed else [])
    slots = []
    reads = []
    for index, (name, threshold) in enumerate(zip(slot_names, thresholds)):
        start = mapped(threshold)
        slots.append({"slotIndex": index, "stage": name, "policy": policy, "startedSystemUptime": start,
            "operationCompletedSystemUptime": start + .05, "scheduledEndSystemUptime": start + duration,
            "completedSystemUptime": start + duration, "requestedSeconds": duration, "operationWithinBudget": True})
        if policy == "present":
            for offset, attribute in ((.005, "AXChildren"), (.015, "AXRole")):
                reads.append({"readIndex": len(reads), "attribute": attribute,
                    "startedSystemUptime": start + offset, "completedSystemUptime": start + offset + .002, "status": 0})
    report.update(heldAXSlots=slots, heldAXReads=reads, heldAXReadCount=len(reads), heldAXReadGuardViolations=[],
                  heldAXSlotSeconds=duration)
    aggregate = capture.read_json(folder / "report.json")
    aggregate["heldAXSlotSeconds"] = duration
    (folder / "report.json").write_text(json.dumps(aggregate))
    by_slot = {row["stage"]: row for row in slots}
    snapshots = [report["setupSnapshot"], *report["stages"], *report["diagnosticSnapshots"]]
    unheld_times = {"setup-before-hit-checks": 2.45, "00-before-drag": 4.7,
                   "04-after-escape": mapped(10.8), "06-after-accepted-drop": mapped(14.5)}
    for row in snapshots:
        name = row["stage"]
        held = name in held_ax.HELD_CAPTURES
        start = by_slot["capture:" + name]["startedSystemUptime"] + .001 if held else unheld_times[name]
        row.update(captureStartedSystemUptime=start, captureCompletedSystemUptime=start + .03,
                   mouseDownSent=held, leftButtonReportedDown=held,
                   captureKind="held-ax-omitted" if held and policy == "omitted" else "target-ax-only")
        if held and policy == "omitted":
            row.pop("workspaceAXLabels", None)
        else:
            names = [existing, single] if name == "06-after-accepted-drop" or name == "04-after-escape" and not passed else [existing]
            row["workspaceAXLabels"] = [f"{len(names)} Selected"] + ["Remove " + n for n in names]
        (directory / (name + ".json")).write_text(json.dumps(row))
    observations = []
    for phase in ("before-key", "after-key-held"):
        start = by_slot["escape-observation:" + phase]["startedSystemUptime"] + .001
        row = {"phase": phase, "heldAXPolicy": policy, "startedSystemUptime": start,
               "completedSystemUptime": start + .03, "status": "omitted" if policy == "omitted" else "observed"}
        if policy == "present":
            row.update(workspace=workspace([existing]), focusedUIElement={"status": "partial", "role": "AXWindow"})
        observations.append(row)
    report["escapeObservations"] = observations
    (directory / "report.json").write_text(json.dumps(report))
    return code


def alter_report(directory, action, *, update_snapshots=False):
    path = directory / "report.json"
    record = capture.read_json(path)
    action(record)
    path.write_text(json.dumps(record))
    if update_snapshots:
        for row in [record["setupSnapshot"], *record["stages"], *record["diagnosticSnapshots"]]:
            (directory / (row["stage"] + ".json")).write_text(json.dumps(row))


class HeldAXComparisonTests(unittest.TestCase):
    def run_cases(self, stage, context, output, pass_for=None, change=None, target_activates=None):
        commands = []
        def runner(command, log):
            case_name = held_ax.CASES[len(commands)]
            commands.append(command)
            passed = bool(pass_for and pass_for(case_name))
            activates = target_activates(case_name) if target_activates else not passed
            code = emit(stage, context, case_name, passed=passed, target_activates=activates)
            if change:
                change(case_name, held_ax.evidence_for(stage, case_name) / "orchard")
            return code
        return held_ax.compare(stage, output, context, runner), commands

    def test_quiet_activation_failure_falsifies_necessity_without_making_ci_pass(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            report, commands = self.run_cases(stage, context, Path(temporary) / "out")
            self.assertEqual(report["caseOrder"], ["ax-read-first", "ax-quiet-first", "ax-quiet-second", "ax-read-second"])
            self.assertTrue(report["comparisonComplete"], report["cases"])
            self.assertFalse(report["allCasesPassed"])
            self.assertEqual(report["heldAXComparison"]["causalConclusion"], "observer-held-ax-not-necessary")
            self.assertEqual(report["heldAXComparison"]["quietCasesWithActivationAndCancellationFailure"],
                             ["ax-quiet-first", "ax-quiet-second"])
            self.assertEqual(report["observationSlotSeconds"], .25)
            for command, name, case in zip(commands, held_ax.CASES, report["cases"]):
                self.assertEqual(command, [str(stage / "NativeDragReviewAppKit"), str(stage), "--control",
                    "--compare-capture", "ax-only", "--compare-activation", name])
                self.assertEqual(case["sourceSession"]["classification"], "accepted-after-release")
                self.assertTrue(all(r["performed"] for r in case["targetRaiseRequests"]))
                self.assertEqual(case["heldAXEvidence"]["readCount"], 0 if name.startswith("ax-quiet") else 12)

    def test_quiet_pass_needs_fresh_drop_and_keeps_intervention_conclusion_limited(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            report, commands = self.run_cases(stage, context, Path(temporary) / "out",
                pass_for=lambda name: name.startswith("ax-quiet"))
            self.assertEqual(len(commands), 4)
            self.assertTrue(report["comparisonComplete"], report["cases"])
            self.assertTrue(report["heldAXComparison"]["activationAndFunctionalContrastObserved"])
            self.assertEqual(report["heldAXComparison"]["causalConclusion"], "not-established")
            for case in report["cases"][1:3]:
                self.assertTrue(case["passed"])
                self.assertEqual(case["heldAXEvidence"]["slotCount"], 7)
                self.assertEqual(case["sourceSession"]["freshSession"]["end"]["operationRawValue"], 1)

    def test_all_pass_cannot_close_production_hold_or_claim_a_causal_fix(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            report, _ = self.run_cases(stage, context, Path(temporary) / "out", pass_for=lambda _: True)
            self.assertTrue(report["allCasesPassed"], report["cases"])
            self.assertEqual(report["C12"], "HOLD")
            self.assertEqual(report["heldAXComparison"]["causalConclusion"], "not-established")
            self.assertIsNone(report["heldAXComparison"]["observerHeldAXNecessaryForObservedActivationAndFailure"])
            for field in ("releaseReady", "nativeAcceptanceXCTestExecuted", "physicalInputVerified"):
                self.assertFalse(report[field])

    def test_quiet_read_or_fabricated_observation_stops_further_input(self):
        mutations = {
            "read": lambda r: r.update(heldAXReads=[{"readIndex": 0}], heldAXReadCount=1),
            "guard": lambda r: r.update(heldAXReadGuardViolations=[{"attribute": "AXChildren", "systemUptime": 7.}]),
            "count": lambda r: r.update(heldAXReadCount=1),
            "key-workspace": lambda r: r["escapeObservations"][0].update(workspace={}),
            "key-focus": lambda r: r["escapeObservations"][1].update(focusedUIElement={}),
            "snapshot-label": lambda r: r["stages"][1].update(workspaceAXLabels=["1 Selected"]),
            "false-observed": lambda r: r["stages"][2].update(captureKind="target-ax-only"),
        }
        for label, mutation in mutations.items():
            with self.subTest(label=label), tempfile.TemporaryDirectory() as temporary:
                stage, context = fixture(Path(temporary))
                def change(name, directory):
                    if name == "ax-quiet-first":
                        alter_report(directory, mutation, update_snapshots=True)
                report, commands = self.run_cases(stage, context, Path(temporary) / "out", change=change)
                self.assertEqual(len(commands), 2)
                self.assertFalse(report["comparisonComplete"])
                self.assertEqual(report["cases"][1]["outcome"], "not-comparable")
                self.assertEqual([r["outcome"] for r in report["cases"]][2:], ["not-run", "not-run"])

    def test_slot_and_read_tampering_cannot_promote_native_results(self):
        mutations = {
            "missing-slot": lambda r: r["heldAXSlots"].pop(),
            "wrong-duration": lambda r: r["heldAXSlots"][0].update(requestedSeconds=.1),
            "overrun": lambda r: r["heldAXSlots"][0].update(operationCompletedSystemUptime=r["heldAXSlots"][0]["scheduledEndSystemUptime"] + .01),
            "overrun-flag": lambda r: r["heldAXSlots"][0].update(operationWithinBudget=False),
            "early-finish": lambda r: r["heldAXSlots"][0].update(completedSystemUptime=r["heldAXSlots"][0]["scheduledEndSystemUptime"] - .01),
            "wrong-end": lambda r: r["heldAXSlots"][0].update(scheduledEndSystemUptime=r["heldAXSlots"][0]["scheduledEndSystemUptime"] - .01),
            "out-of-slot-read": lambda r: r["heldAXReads"][0].update(startedSystemUptime=5.5, completedSystemUptime=5.51),
            "missing-reads": lambda r: r.update(heldAXReads=[], heldAXReadCount=0),
            "bad-status": lambda r: r["heldAXReads"][0].update(status=-25204),
            "duplicate-read-index": lambda r: r["heldAXReads"][1].update(readIndex=0),
            "missing-operation-reads": lambda r: r["heldAXReads"][-1].update(startedSystemUptime=20., completedSystemUptime=20.01),
            "unknown-read-attribute": lambda r: r["heldAXReads"][0].update(attribute=None),
            "nan-clock": lambda r: r["heldAXSlots"][0].update(completedSystemUptime=float("nan")),
        }
        for label, mutation in mutations.items():
            with self.subTest(label=label), tempfile.TemporaryDirectory() as temporary:
                stage, context = fixture(Path(temporary))
                def change(name, directory):
                    if name == "ax-read-first":
                        alter_report(directory, mutation)
                report, commands = self.run_cases(stage, context, Path(temporary) / "out", change=change)
                self.assertEqual(len(commands), 1)
                invalid = report["cases"][0]
                self.assertFalse(invalid["mayContinue"])
                self.assertEqual(invalid["strictNativeOutcome"]["outcome"], "escape-cancellation-failed")

    def test_initial_workspace_is_observed_before_input_with_exact_counts(self):
        mutations = {
            "missing": lambda r: r.pop("heldAXInitialWorkspace"),
            "too-late": lambda r: r["heldAXInitialWorkspace"].update(completedSystemUptime=5.1),
            "duplicate-existing": lambda r: r["heldAXInitialWorkspace"]["workspace"]["fixtureRemoveButtonCounts"].update(
                {next(k for k in r["originalSHA256"] if k.startswith("Existing")): 2}),
            "not-observed": lambda r: r["heldAXInitialWorkspace"].pop("workspace"),
        }
        for label, mutation in mutations.items():
            with self.subTest(label=label), tempfile.TemporaryDirectory() as temporary:
                stage, context = fixture(Path(temporary))
                report, commands = self.run_cases(stage, context, Path(temporary) / "out",
                    change=lambda _n, d: alter_report(d, mutation))
                self.assertEqual(len(commands), 1)
                self.assertFalse(report["comparisonComplete"])

    def test_standalone_snapshot_must_equal_its_embedded_record(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            def change(_name, directory):
                path = directory / "00-before-drag.json"
                value = json.loads(path.read_text())
                value["workspaceAXLabels"] = ["2 Selected"]
                path.write_text(json.dumps(value))
            report, commands = self.run_cases(stage, context, Path(temporary) / "out", change=change)
            self.assertEqual(len(commands), 1)
            self.assertEqual(report["cases"][0]["reasonCode"], "held-ax-snapshot-report-mismatch")

    def test_unknown_native_error_is_retained_with_cleanup_and_stops(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            error = "The fixed held AX operation exceeded its observation slot"
            def change(_name, directory):
                alter_report(directory, lambda r: r.update(reason=error, startupPhase="complete"))
            report, commands = self.run_cases(stage, context, Path(temporary) / "out", change=change)
            self.assertEqual(len(commands), 1)
            self.assertEqual(report["cases"][0]["observerFailure"]["reason"], error)
            self.assertTrue(report["cases"][0]["cleanupComplete"])
            self.assertFalse(report["cases"][0]["mayContinue"])

    def test_fresh_drop_receipt_remains_required_for_quiet_pass(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            def change(name, directory):
                if name == "ax-quiet-first":
                    rows = read_trace(directory / "source.jsonl")
                    rows = [r for r in rows if not (r["event"] == "source-ended" and r.get("sessionIndex") == 2)]
                    save_rows(directory / "source.jsonl", rows)
            report, commands = self.run_cases(stage, context, Path(temporary) / "out",
                pass_for=lambda n: n.startswith("ax-quiet"), change=change)
            self.assertEqual(len(commands), 2)
            self.assertEqual(report["cases"][1]["reasonCode"], "source-session-end-unobserved")

    def test_nonfinite_early_failure_still_retains_a_valid_failure_report(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            output = Path(temporary) / "out"
            def change(_name, directory):
                def corrupt(record):
                    record["reason"] = "Malformed native evidence"
                    record["heldAXSlots"][0]["completedSystemUptime"] = float("nan")
                alter_report(directory, corrupt)
            report, commands = self.run_cases(stage, context, output, change=change)
            self.assertEqual(len(commands), 1)
            self.assertFalse(report["comparisonComplete"])
            self.assertFalse(report["cases"][0]["mayContinue"])
            self.assertTrue(report["cases"][0]["reportRetained"])
            json.loads((output / "comparison.json").read_text(),
                       parse_constant=lambda value: self.fail("Nonfinite failure output: " + value))

    def test_previous_d11_case_set_and_default_path_remain_unchanged(self):
        self.assertEqual(activation.CASES, ("raise-first", "no-raise-first", "no-raise-second", "raise-second"))
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            code = emit_activation(stage, context, "raise-first", passed=False)
            result = activation.classify(stage, context, "raise-first", code)
            self.assertEqual(result["outcome"], "escape-cancellation-failed")
            self.assertNotIn("heldAXPolicy", result)


if __name__ == "__main__":
    unittest.main()
