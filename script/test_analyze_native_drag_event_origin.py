"""Portable event-identity/entry-stack tests; no native process or input executes."""
import copy
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

import analyze_native_drag_event_origin as origin
import test_compare_native_drag_mouse_driver as d13

mouse, capture = origin.mouse, origin.capture


def identity(kind=6, pid=500, *, present=True, source=False):
    value = {"eventType": kind, "eventNumber": 42, "buttonNumber": 0,
        "clickCount": None if kind == 6 else 1, "pressure": 1., "modifierFlags": 0}
    if not source:
        value["cgEventPresent"] = present
    if present:
        value.update(cgSourceStateID=1, cgSourcePID=pid, cgMouseEventNumber=42,
                     cgMousePressure=1., cgTimestampNanoseconds=10_940_000_000 if kind == 6 else 10_011_000_000)
    return value


def stack_receipt(count=3):
    addresses = [hex(0x1000 + index * 16) for index in range(min(count, 48))]
    return {"schema": 1, "status": "complete", "reasonCode": None, "targetPID": 200,
        "dispatchIndex": 1, "eventType": 6, "eventTimestamp": 10.94, "mainThread": True,
        "captureStartedSystemUptime": 10.95001, "captureCompletedSystemUptime": 10.95002,
        "maximumFrames": 48, "capturedFrameCount": count, "retainedFrameCount": len(addresses),
        "returnAddresses": addresses, "framesTruncated": count > len(addresses),
        "symbolicationMethod": "backtrace_symbols", "maximumSymbolCharacters": 512,
        "symbolicationStartedSystemUptime": 25.041, "symbolicationCompletedSystemUptime": 25.042,
        "symbolicationMainThread": True, "frames": [{"frameIndex": index, "returnAddress": address,
            "symbolStatus": "rendered", "symbol": f"{index} fixture {address} test_frame_{index} + 4",
            "symbolTruncated": False} for index, address in enumerate(addresses)]}


def add_d14(stage, name, *, absent=False, pid=None):
    directory = mouse.evidence_for(stage, name) / "orchard"
    d13.alter_case(stage, name, lambda row: row.update(observerProcessID=500))
    producer_pid = 600 if name.startswith("xctest") else 500
    if pid is None:
        pid = producer_pid
    def activation(rows):
        for row in rows:
            if row["event"] in ("activation-start", "activation-ready"):
                row["targetMouseEventIdentitySchema"] = 1
                row["targetDispatchStackSchema"] = 1
            if row["event"] == "activation-terminating":
                row["callbackSystemUptime"] = 25.04
                row["dispatchStackObservation"] = stack_receipt()
        for event, when in (("target-mouse-enter", 10.95), ("target-mouse-return", 10.96)):
            rows.append({"schema": 1, "pid": 200, **mouse.bindings(name),
                "event": event, "systemUptime": when + .0001, "callbackSystemUptime": when,
                **d13.window_state(False, 7), "dispatchIndex": 1, "eventType": 6, "eventTimestamp": 10.94,
                "eventWindowNumber": 7, "eventMatchesOwnedWindow": True, "modifierFlags": 0,
                "locationInWindow": {"x": 84., "y": 492.}, "deliveredMouseEvent": identity(pid=pid, present=not absent)})
        if any(row["event"] == "application-became-active" for row in rows):
            for event, when, active in (("appkit-defined-enter", 10.99, False), ("appkit-defined-return", 11.02, True)):
                rows.append({"schema": 1, "pid": 200, **mouse.bindings(name),
                    "event": event, "systemUptime": when + .0001, "callbackSystemUptime": when,
                    **d13.window_state(active, 7), "dispatchIndex": 2, "eventType": 13, "eventTimestamp": 10.985,
                    "eventWindowNumber": 0, "eventSubtype": 1, "eventSubtypeName": "applicationActivated"})
        rows.sort(key=lambda row: row["systemUptime"])
    d13.alter_trace(directory / "activation.jsonl", activation)
    def source(rows):
        rows.append({"schema": 1, "pid": 300, **mouse.bindings(name),
            "event": "source-mouse-down", "systemUptime": 10.02, "eventTimestamp": 10.011,
            "sessionIndex": 0, **d13.window_state(True, 4), "deliveredMouseEvent": identity(1, producer_pid, source=True)})
        rows.sort(key=lambda row: row["systemUptime"])
    d13.alter_trace(directory / "source.jsonl", source)
    def receiver(rows):
        for row in rows:
            row["time"] = (datetime(2026, 11, 6, tzinfo=timezone.utc) + timedelta(seconds=row["systemUptime"])).strftime("%Y-%m-%dT%H:%M:%SZ")
            if "sequenceNumber" in row:
                row["draggingLocationInWindow"] = {"x": 84., "y": 492.}
    d13.alter_trace(directory / "receiver.jsonl", receiver)


def fixture(parent, *, passed=("xctest-first",), absent=(), zero=()):
    parent = parent.resolve()
    stage, context = d13.fixture(parent)
    context["provenance"].update(eventOriginDiagnostic=copy.deepcopy(origin.DIAGNOSTIC),
        eventOriginControlBuild=copy.deepcopy(origin.CONTROL_BUILD),
        dispatchStackDiagnostic=copy.deepcopy(origin.DISPATCH_STACK_DIAGNOSTIC),
        runnerRetirementProtocol=origin.RUNNER_RETIREMENT_PROTOCOL,
        **{key: capture.sha256(capture.ROOT / relative) for key, relative in origin.CODE_FILES.items()})
    (stage / "provenance.json").write_text(json.dumps(context["provenance"]))
    context["inputs"] = mouse.input_snapshot(stage)
    comparison = parent / "comparison"
    def runner(command, log):
        name = command[-1]
        code = d13.emit(stage, context, name, passed=name in passed)
        add_d14(stage, name, absent=name in absent, pid=0 if name in zero else None)
        return code
    report = mouse.compare(stage, comparison, context, runner=runner)
    assert report["comparisonComplete"], [(r.get("sourceCase"), r.get("reasonCode")) for r in report["cases"]]
    return stage, comparison, context


def refresh_case(stage, comparison, context, name):
    path = comparison / "comparison.json"
    report = json.loads(path.read_text())
    index = mouse.CASES.index(name)
    row = mouse.classify(stage, context, name, report["cases"][index]["returnCode"])
    assert row["comparability"] == "comparable", row.get("reasonCode")
    row["inputsUnchanged"] = True
    report["cases"][index] = row
    path.write_text(json.dumps(report))


def run_analysis(stage, comparison, context):
    provenance = context["provenance"]
    repository = {"tree": provenance["observerExperimentTree"], "hashes": {
        key: provenance[key] for key in (*origin.CODE_FILES, "mouseDriverComparatorSourceSHA256")}}
    with patch.object(origin, "repository_identity", return_value=repository), \
         patch.object(mouse, "compare", side_effect=AssertionError("No runner orchestration")), \
         patch.object(mouse, "context_for", side_effect=AssertionError("No live context")), \
         patch.object(mouse, "input_snapshot", side_effect=AssertionError("No input inventory execution")):
        return origin.analyze(stage, comparison, provenance["observerExperimentCommit"])


class EventOriginTests(unittest.TestCase):
    def test_fixture_canonicalizes_a_symlinked_temporary_parent(self):
        with tempfile.TemporaryDirectory() as temporary:
            parent = Path(temporary).resolve()
            real = parent / "real"
            real.mkdir()
            alias = parent / "alias"
            alias.symlink_to(real, target_is_directory=True)
            stage, comparison, context = fixture(alias)
            report = run_analysis(stage, comparison, context)
            self.assertEqual(report["status"], "complete", report.get("reasonCode"))
            self.assertEqual(stage, real / "lemulip-native-ui")
            self.assertEqual(comparison, real / "comparison")

    def test_pass_and_fail_remain_native_outcomes_and_pid_roles_are_bounded(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, comparison, context = fixture(Path(temporary))
            report = run_analysis(stage, comparison, context)
            self.assertEqual(report["status"], "complete", report)
            self.assertEqual([r["nativeComparison"]["passed"] for r in report["cases"]], [False, True, False, False])
            self.assertEqual(report["collectorPIDs"], [200, 300, 400, 500])
            self.assertTrue(report["acceptanceUnchanged"])
            self.assertFalse(report["nativeInputExecuted"])
            self.assertTrue(report["dispatchStackObservationsComplete"])
            for row in report["cases"]:
                stack = row["dispatchStackObservation"]
                self.assertTrue(stack["receiptValidated"])
                self.assertEqual(stack["dispatchIndex"], row["firstHeldTargetDrag"]["dispatchIndex"])
                self.assertGreater(stack["symbolicationStartedSystemUptime"], stack["lastGestureReleaseObservedSystemUptime"])
                self.assertGreater(stack["captureDurationSeconds"], 0)
                self.assertFalse(stack["upstreamSenderIdentified"])
            q, x = report["cases"][:2]
            self.assertEqual(q["firstHeldTargetDrag"]["cgSourcePIDRelation"], "observer")
            self.assertEqual(x["firstHeldTargetDrag"]["cgSourcePIDRelation"], "unknown")
            self.assertTrue(x["firstHeldTargetDrag"]["cgSourcePIDMatchesSourceInitialDown"])
            self.assertEqual(q["wallTimeRange"], {"start": "2026-11-06T00:00:02Z", "end": "2026-11-06T00:00:25Z", "precision": "seconds"})
            self.assertEqual(len(q["firstHeldTargetDrag"]["laterActivationDispatches"]), 1)
            self.assertEqual(x["firstHeldTargetDrag"]["laterActivationDispatches"], [])
            self.assertEqual(capture.sha256(Path(mouse.__file__)), origin.COMPARATOR_SOURCE_SHA256)

    def test_timestamp_joins_distinguish_post_overlap_from_later_event(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, comparison, context = fixture(Path(temporary))
            name = "quartz-first"
            def raw(row):
                row["mouseEvents"][20]["systemUptimeAfterPost"] = 10.85
                row["mouseDriverGestures"][0]["lastMovementPostCompletedSystemUptime"] = 10.851
            d13.alter_case(stage, name, raw)
            def pair(rows):
                for row in rows:
                    if row["event"].startswith("target-mouse-"):
                        row["eventTimestamp"] = 10.84
                        row["deliveredMouseEvent"]["cgTimestampNanoseconds"] = 10_840_000_000
                    if row["event"] == "activation-terminating":
                        row["dispatchStackObservation"]["eventTimestamp"] = 10.84
            d13.alter_trace(mouse.evidence_for(stage, name) / "orchard/activation.jsonl", pair)
            refresh_case(stage, comparison, context, name)
            report = run_analysis(stage, comparison, context)
            self.assertTrue(report["analysisComplete"], report)
            first = report["cases"][0]["firstHeldTargetDrag"]["quartzPostRelations"]
            self.assertEqual(first["postIntervalsContainingEventTimestamp"], [20])
            self.assertTrue(first["matchingLocationPosts"][0]["timestampInsidePostInterval"])
            last = report["cases"][-1]["firstHeldTargetDrag"]["quartzPostRelations"]
            self.assertEqual(last["postIntervalsContainingEventTimestamp"], [])
            self.assertGreater(last["eventTimestampMinusLastPostedDragSeconds"], 0)

    def test_nil_corresponding_event_and_pid_zero_make_no_sender_claim(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, comparison, context = fixture(Path(temporary), absent=("quartz-first",), zero=("quartz-second",))
            report = run_analysis(stage, comparison, context)
            self.assertTrue(report["analysisComplete"], report)
            first = report["cases"][0]["firstHeldTargetDrag"]
            self.assertEqual(first["cgSourcePIDRelation"], "cg-event-unavailable")
            self.assertIsNone(first["cgSourcePIDMatchesSourceInitialDown"])
            self.assertEqual(report["cases"][-1]["firstHeldTargetDrag"]["cgSourcePIDRelation"], "unknown")
            self.assertNotIn(0, report["collectorPIDs"])

    def test_delivery_schema_rejects_wrong_types_partial_cg_fields_and_invalid_click_count(self):
        mutations = {
            "partial-cg": lambda row: row.pop("cgSourcePID"),
            "false-with-fields": lambda row: row.update(cgEventPresent=False),
            "nonboolean-presence": lambda row: row.update(cgEventPresent=1),
            "boolean-event-number": lambda row: row.update(eventNumber=True),
            "drag-click-count": lambda row: row.update(clickCount=1),
            "nan-pressure": lambda row: row.update(pressure=float("nan")),
            "negative-pid": lambda row: row.update(cgSourcePID=-1),
            "unknown-field": lambda row: row.update(unknown=True),
        }
        for name, mutate in mutations.items():
            with self.subTest(name=name):
                value = identity()
                mutate(value)
                with self.assertRaises(capture.ComparisonError):
                    origin.delivered_mouse(value, 6)

    def test_marker_pair_and_case_hash_failures_do_not_export_pids(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, comparison, context = fixture(Path(temporary))
            name = "quartz-first"
            directory = mouse.evidence_for(stage, name) / "orchard"
            original_trace = (directory / "activation.jsonl").read_bytes()
            original_case = (directory / "report.json").read_bytes()
            original_comparison = (comparison / "comparison.json").read_bytes()
            def marker(rows):
                next(row for row in rows if row["event"] == "activation-ready").pop("targetMouseEventIdentitySchema")
            def pair(rows):
                next(row for row in rows if row["event"] == "target-mouse-return")["deliveredMouseEvent"]["cgSourcePID"] = 777
            def absent(rows):
                rows[:] = [row for row in rows if not row["event"].startswith("target-mouse-")]
            for label, change in (("missing-marker", marker), ("changed-pair", pair), ("missing-drag", absent), ("raw-hash", None)):
                with self.subTest(label=label):
                    (directory / "activation.jsonl").write_bytes(original_trace)
                    (directory / "report.json").write_bytes(original_case)
                    (comparison / "comparison.json").write_bytes(original_comparison)
                    if change:
                        d13.alter_trace(directory / "activation.jsonl", change)
                        refresh_case(stage, comparison, context, name)
                    else:
                        d13.alter_case(stage, name, lambda row: row.update(observerProcessID=501))
                    report = run_analysis(stage, comparison, context)
                    self.assertEqual(report["cases"][0]["status"], "invalid", report)
                    self.assertNotIn("ownedPIDs", report["cases"][0])

    def test_provenance_build_architecture_and_inventory_changes_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, comparison, context = fixture(Path(temporary))
            path = stage / "provenance.json"
            original = path.read_bytes()
            changes = {
                "protocol": lambda row: row["eventOriginDiagnostic"].update(inputProtocol="changed"),
                "build": lambda row: row["eventOriginControlBuild"].update(swiftDefines=[]),
                "stack-schema": lambda row: row["dispatchStackDiagnostic"].update(maximumFrames=49),
                "retirement-protocol": lambda row: row.update(runnerRetirementProtocol="unbound"),
                "hash": lambda row: row.update(eventOriginAnalyzerSourceSHA256="0" * 64),
                "architecture": lambda row: row.update(architecture="unknown"),
                "commit": lambda row: row.update(observerExperimentCommit="0" * 40),
            }
            for label, change in changes.items():
                with self.subTest(label=label):
                    value = json.loads(original)
                    change(value)
                    path.write_text(json.dumps(value))
                    report = run_analysis(stage, comparison, context)
                    self.assertEqual(report["status"], "invalid", report)
                    self.assertEqual(report["collectorPIDs"], [])
            path.write_bytes(original)
            after = comparison / "inputs-after.json"
            value = json.loads(after.read_text())
            value["provenance.json"]["sha256"] = "0" * 64
            after.write_text(json.dumps(value))
            self.assertEqual(run_analysis(stage, comparison, context)["status"], "invalid")

    def test_missing_or_unbound_stack_is_unavailable_without_changing_native_result(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, comparison, context = fixture(Path(temporary))
            name = "quartz-first"
            path = mouse.evidence_for(stage, name) / "orchard/activation.jsonl"
            original = path.read_bytes()
            baseline = run_analysis(stage, comparison, context)["cases"][0]["nativeComparison"]
            def change_receipt(rows, mutate):
                mutate(next(row for row in rows if row["event"] == "activation-terminating")["dispatchStackObservation"])
            def missing(rows):
                next(row for row in rows if row["event"] == "activation-terminating").pop("dispatchStackObservation")
            def duplicate(rows):
                rows[0]["dispatchStackObservation"] = copy.deepcopy(rows[-1]["dispatchStackObservation"])
            def marker(rows):
                next(row for row in rows if row["event"] == "activation-ready").pop("targetDispatchStackSchema")
            changes = {"missing": missing, "duplicate": duplicate, "marker": marker,
                "wrong-event": lambda rows: change_receipt(rows, lambda r: r.update(dispatchIndex=2)),
                "wrong-pid": lambda rows: change_receipt(rows, lambda r: r.update(targetPID=300)),
                "wrong-event-clock": lambda rows: change_receipt(rows, lambda r: r.update(eventTimestamp=10.93)),
                "capture-before-entry": lambda rows: change_receipt(rows, lambda r: r.update(captureStartedSystemUptime=10.94)),
                "capture-after-record": lambda rows: change_receipt(rows, lambda r: r.update(captureCompletedSystemUptime=10.96)),
                "symbols-during-hold": lambda rows: change_receipt(rows, lambda r: r.update(symbolicationStartedSystemUptime=11.)),
                "symbols-after-record": lambda rows: change_receipt(rows, lambda r: r.update(symbolicationCompletedSystemUptime=25.06))}
            for label, mutate in changes.items():
                with self.subTest(label=label):
                    path.write_bytes(original)
                    d13.alter_trace(path, mutate)
                    refresh_case(stage, comparison, context, name)
                    report = run_analysis(stage, comparison, context)
                    self.assertTrue(report["analysisComplete"], report)
                    self.assertFalse(report["dispatchStackObservationsComplete"])
                    row = report["cases"][0]
                    self.assertEqual(row["nativeComparison"], baseline)
                    self.assertEqual(row["dispatchStackObservation"]["status"], "unavailable")
                    self.assertFalse(row["dispatchStackObservation"]["receiptValidated"])
                    self.assertNotIn("frames", row["dispatchStackObservation"])
                    json.dumps(report, allow_nan=False)

    def test_stack_frame_symbol_and_truncation_bounds(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, comparison, context = fixture(Path(temporary))
            name = "quartz-first"
            path = mouse.evidence_for(stage, name) / "orchard/activation.jsonl"
            rows = d13.read_trace(path)
            event = next(row for row in rows if row["event"] == "target-mouse-enter")
            raw = json.loads((path.parent / "report.json").read_text())
            receipt = stack_receipt(49)
            receipt["frames"][0].update(symbol="x" * 512, symbolTruncated=True)
            rows[-1]["dispatchStackObservation"] = receipt
            valid = origin.dispatch_stack_observation(rows, event, raw["mouseDriverGestures"], 200)
            self.assertEqual(valid["status"], "complete", valid)
            self.assertTrue(valid["framesTruncated"])
            self.assertEqual(len(valid["frames"]), 48)
            changes = {
                "too-many-addresses": lambda r: r["returnAddresses"].append("0x2000"),
                "count-mismatch": lambda r: r.update(retainedFrameCount=47),
                "unbounded-count": lambda r: r.update(capturedFrameCount=4097),
                "boolean-count": lambda r: r.update(capturedFrameCount=True),
                "missing-frame": lambda r: r["frames"].pop(),
                "changed-address": lambda r: r["frames"][0].update(returnAddress="0x1"),
                "oversized-address": lambda r: r["returnAddresses"].__setitem__(0, "0x10000000000000000"),
                "noncanonical-address": lambda r: r["returnAddresses"].__setitem__(0, "0x01000"),
                "oversized-symbol": lambda r: r["frames"][0].update(symbol="x" * 513),
                "embedded-nul": lambda r: r["frames"][0].update(symbol="x\x00y"),
                "missing-truncation": lambda r: r.update(framesTruncated=False),
                "wrong-frame-order": lambda r: r["frames"][0].update(frameIndex=1),
                "unresolved-with-text": lambda r: r["frames"][0].update(symbolStatus="unresolved"),
                "non-main-thread": lambda r: r.update(mainThread=False),
                "nonfinite-clock": lambda r: r.update(captureStartedSystemUptime=float("nan")),
                "unknown-field": lambda r: r.update(unknown=True),
            }
            for label, mutate in changes.items():
                with self.subTest(label=label):
                    changed = copy.deepcopy(receipt)
                    mutate(changed)
                    rows[-1]["dispatchStackObservation"] = changed
                    result = origin.dispatch_stack_observation(rows, event, raw["mouseDriverGestures"], 200)
                    self.assertEqual(result["status"], "unavailable")
                    self.assertFalse(result["receiptValidated"])

    def test_unresolved_symbols_and_empty_capture_remain_explicit(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, comparison, context = fixture(Path(temporary))
            path = mouse.evidence_for(stage, "xctest-first") / "orchard/activation.jsonl"
            rows = d13.read_trace(path)
            event = next(row for row in rows if row["event"] == "target-mouse-enter")
            raw = json.loads((path.parent / "report.json").read_text())
            value = rows[-1]["dispatchStackObservation"]
            value["frames"][1].update(symbolStatus="unresolved", symbol=None)
            value.update(status="unavailable", reasonCode="one-or-more-symbols-unresolved")
            result = origin.dispatch_stack_observation(rows, event, raw["mouseDriverGestures"], 200)
            self.assertEqual(result["status"], "unavailable")
            self.assertTrue(result["receiptValidated"])
            self.assertEqual(result["returnAddresses"], value["returnAddresses"])
            self.assertIsNone(result["frames"][1]["symbol"])
            self.assertGreater(result["lastGestureReleaseObservedSystemUptime"], raw["mouseDriverGestures"][0]["releaseObservedSystemUptime"])
            value = stack_receipt(0)
            value.update(status="unavailable", reasonCode="empty-captured-stack")
            rows[-1]["dispatchStackObservation"] = value
            result = origin.dispatch_stack_observation(rows, event, raw["mouseDriverGestures"], 200)
            self.assertTrue(result["receiptValidated"])
            self.assertEqual(result["status"], "unavailable")
            self.assertEqual(result["returnAddresses"], [])

    def test_partial_notrun_and_missing_comparison_still_write_bounded_reports(self):
        with tempfile.TemporaryDirectory() as temporary:
            parent = Path(temporary)
            stage, comparison, context = fixture(parent)
            path = comparison / "comparison.json"
            value = json.loads(path.read_text())
            value["comparisonComplete"] = False
            value["cases"][0] = {**mouse.bindings(mouse.CASES[0]), "comparability": "not-comparable",
                                  "outcome": "not-comparable", "reasonCode": "mouse-cleanup-incomplete"}
            for index, name in enumerate(mouse.CASES[1:], 1):
                value["cases"][index] = {**mouse.bindings(name), "comparability": "not-run", "outcome": "not-run"}
                shutil.rmtree(mouse.evidence_for(stage, name))
            path.write_text(json.dumps(value))
            report = run_analysis(stage, comparison, context)
            self.assertEqual([row["status"] for row in report["cases"]], ["incomplete", "not-run", "not-run", "not-run"])
            self.assertEqual(report["collectorPIDs"], [])
            origin.write_analysis(parent / "partial", report)
            self.assertLess((parent / "partial" / origin.OUTPUT_NAME).stat().st_size, 1_048_576)
            path.unlink()
            report = run_analysis(stage, comparison, context)
            self.assertEqual(report["status"], "incomplete")
            origin.write_analysis(parent / "missing", report)
            self.assertEqual(len(json.loads((parent / "missing" / origin.OUTPUT_NAME).read_text())["cases"]), 4)

    def test_analysis_preserves_inputs_and_refuses_output_overwrite(self):
        with tempfile.TemporaryDirectory() as temporary:
            parent = Path(temporary)
            stage, comparison, context = fixture(parent)
            before = {str(path): capture.sha256(path) for root in (stage, comparison)
                      for path in root.rglob("*") if path.is_file()}
            report = run_analysis(stage, comparison, context)
            origin.write_analysis(parent / "analysis", report)
            self.assertEqual(before, {path: capture.sha256(Path(path)) for path in before})
            with self.assertRaises(FileExistsError):
                origin.write_analysis(parent / "analysis", report)

    def test_cli_success_requires_complete_native_replay_and_stack_observation(self):
        args = ["analyze", "--staged", "/unused/stage", "--comparison", "/unused/comparison",
                "--output", "/unused/output", "--experiment-commit", "a" * 40]
        for native, stack in ((True, True), (True, False), (False, True), (False, False)):
            with self.subTest(native=native, stack=stack):
                value = {"status": "complete" if native else "incomplete", "analysisComplete": native,
                         "dispatchStackObservationsComplete": stack}
                with patch.object(origin, "analyze", return_value=value), \
                     patch.object(origin, "write_analysis") as write, \
                     patch.object(origin.sys, "argv", args), patch("builtins.print") as printed:
                    self.assertEqual(origin.main(), 0 if native and stack else 1)
                    write.assert_called_once()
                    summary = json.loads(printed.call_args.args[0])
                    self.assertEqual(summary["dispatchStackObservationsComplete"], stack)


if __name__ == "__main__":
    unittest.main()
