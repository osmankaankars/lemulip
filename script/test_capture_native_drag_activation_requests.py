"""Portable request-log checks. Synthetic fixtures never execute native input or log show."""
import copy
from datetime import datetime, timezone
from fractions import Fraction
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

import capture_native_drag_activation_requests as logs
from test_compare_native_drag_mouse_driver import fixture, emit, read_trace

BOOT = "12345678-1234-1234-1234-123456789ABC"
OTHER_BOOT = "87654321-4321-4321-4321-CBA987654321"
BASE = datetime(2026, 11, 7, tzinfo=timezone.utc).timestamp()


def write(path, value):
    path.write_text(json.dumps(value, sort_keys=True) + "\n")


def wall(when):
    return datetime.fromtimestamp(BASE + when, timezone.utc).isoformat()


class ActivationRequestTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.stage, self.native_context = fixture(self.root)
        self.comparison = self.root / "comparison"
        self.comparison.mkdir()
        self.clock_dir = self.root / "clock"
        self.clock_dir.mkdir()
        executable = self.clock_dir / "NativeTraceClock"
        executable.write_bytes(b"Portable clock fixture; do not execute.\n")
        self.commit = self.native_context["provenance"]["observerExperimentCommit"]
        self.config = {"schema": 1, "nonce": "e" * 32, "executablePath": str(executable),
            "sourceSHA256": logs.capture.sha256(logs.CLOCK_SOURCE), "executableSHA256": logs.capture.sha256(executable),
            "experimentCommit": self.commit, "experimentTree": self.native_context["provenance"]["observerExperimentTree"],
            "architecture": self.native_context["provenance"]["architecture"]}
        write(self.clock_dir / "clock-config.json", self.config)
        provenance = self.native_context["provenance"]
        provenance.update(logs.diagnostic_metadata(), activationRequestClockBuild=self.config,
            activationRequestClockConfigSHA256=logs.capture.sha256(self.clock_dir / "clock-config.json"),
            activationRequestClockEnvironment={"schema": 1, "hostArchitecture": self.config["architecture"],
                "helperArchitectures": [self.config["architecture"]],
                "translationProbe": {"returnCode": 0, "errno": 0, "value": 0, "status": "native"}})
        write(self.stage / "provenance.json", provenance)
        self.snapshots = {phase: self.snapshot(phase, when, pid) for phase, when, pid in
                          (("before", 1., 700), ("after", 30., 701))}
        for phase, snapshot in self.snapshots.items():
            self.save_snapshot(phase, snapshot)
        self.case_name = logs.mouse.CASES[0]
        self.directory = logs.mouse.evidence_for(self.stage, self.case_name) / "orchard"
        self.make_comparison(passed=True)
        self.calls, self.outputs = [], 0

    def snapshot(self, phase, when, pid):
        tick = lambda value: round(value * 1_000_000_000)
        row = {"schema": 1, "phase": phase, "nonce": self.config["nonce"], "pid": pid,
            "executablePath": self.config["executablePath"], "bootUUID": BOOT,
            "machTimebaseNumer": 1, "machTimebaseDenom": 1, "systemUptimeSample": when,
            "systemUptimeBeforeLog": when + .001, "systemUptimeAfterLog": when + .0012,
            "wallBeforeLogUnixSeconds": BASE + when + .001, "wallAfterLogUnixSeconds": BASE + when + .0012}
        for family, offset in (("absolute", 0), ("continuous", 100)):
            for suffix, delta in (("BeforeUptime", -.0001), ("AfterUptime", .0001),
                                  ("BeforeLog", .001), ("AfterLog", .0012)):
                row[family + suffix] = tick(when + offset + delta)
        return row

    def save_snapshot(self, phase, row, returncode=0, timed_out=False):
        write(self.clock_dir / (phase + ".json"), row)
        (self.clock_dir / (phase + ".stderr")).write_bytes(b"")
        write(self.clock_dir / (phase + "-execution.json"), {"schema": 1, "phase": phase,
            "returncode": returncode, "timedOut": timed_out,
            "stdoutSHA256": logs.capture.sha256(self.clock_dir / (phase + ".json")),
            "stderrSHA256": logs.capture.sha256(self.clock_dir / (phase + ".stderr"))})

    def make_comparison(self, passed):
        if self.directory.exists():
            # Existing fixture emitter only creates its owned directory once.
            import shutil
            shutil.rmtree(self.directory.parent)
        code = emit(self.stage, self.native_context, self.case_name, passed=passed)
        report_path = self.directory / "report.json"
        report = json.loads(report_path.read_text())
        report["observerProcessID"] = 100
        write(report_path, report)
        receiver = read_trace(self.directory / "receiver.jsonl")
        for row in receiver:
            row["time"] = datetime.fromtimestamp(BASE + int(row["systemUptime"]), timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        (self.directory / "receiver.jsonl").write_text("".join(json.dumps(r) + "\n" for r in receiver))
        classified = logs.mouse.classify(self.stage, self.native_context, self.case_name, code)
        self.assertEqual(classified["comparability"], "comparable", classified)
        self.native_comparison = {"schema": 1, "diagnosticOnly": True, "releaseReady": False,
            "inputsUnchanged": True, "sameStagedPaths": True, "caseOrder": list(logs.mouse.CASES),
            "provenance": self.native_context["provenance"], "cases": [classified] + [
                {**logs.mouse.bindings(name), "outcome": "not-run", "comparability": "not-comparable",
                 "passed": False, "mayContinue": False} for name in logs.mouse.CASES[1:]]}
        write(self.comparison / "comparison.json", self.native_comparison)

    def context(self):
        return logs.load_context(self.stage, self.comparison, self.clock_dir, self.commit)

    def entry(self, message, when, pid=200, path=None, boot=BOOT, **extra):
        return {"timestamp": wall(when), "machTimestamp": round(when * 1_000_000_000), "bootUUID": boot,
            "processID": pid, "processImagePath": path or str(self.stage / "Native Drag Control.app/Contents/MacOS/NativeDragControl"),
            "senderImagePath": "/System/Library/Frameworks/ApplicationServices.framework/HIServices",
            "subsystem": logs.FRONT_SUBSYSTEM, "category": logs.FRONT_CATEGORY,
            "eventMessage": message, "eventType": "logEvent", "messageType": "Default",
            "activityIdentifier": 0, "traceID": 12345, **extra}

    def marker(self, phase):
        snapshot = self.snapshots[phase]
        return self.entry("LEMULIP_NATIVE_TRACE_CLOCK " + self.config["nonce"] + " " + phase,
            snapshot["systemUptimeSample"] + .0011, pid=snapshot["pid"], path=self.config["executablePath"],
            subsystem=logs.CLOCK_SUBSYSTEM, category=logs.CLOCK_CATEGORY)

    def anchor(self, when=2.2, pid=200, asn="0x0-0x29029", emitter=None, path=None, **extra):
        return self.entry(f"BringFrontModifier: pid={pid} asn={asn} Modifier 0 hideAfter=0 hideOthers=0 "
            "dontMakeFrontmost=0 mouseDown=0/0 seed=0/0", when, pid=pid if emitter is None else emitter, path=path, **extra)

    def request(self, when=11.5, asn="0x0-0x29029", **extra):
        return self.entry(f"SetFrontProcess: asn={asn} options=0", when, pid=99,
                          path="/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer", **extra)

    def records(self):
        source = str(self.stage / "Native Drag Source.app/Contents/MacOS/NativeDragSource")
        return [self.marker("before"), self.anchor(), self.request(when=2.3),
            self.anchor(when=3.1, pid=300, asn="0x0-0x2c02c", path=source),
            self.request(when=3.2, asn="0x0-0x2c02c"), self.request(), self.marker("after")]

    def analyze(self, records=None, context=None, clock=None):
        loaded_context, loaded_clock = self.context()
        return logs.analyze_records(records if records is not None else self.records(),
            context if context is not None else loaded_context, clock if clock is not None else loaded_clock)

    def collect(self, entries=None, result=None):
        self.outputs += 1
        output = self.root / ("output-" + str(self.outputs))
        data = json.dumps(self.records() if entries is None else entries).encode()
        supplied = result if result is not None else {"status": "completed", "returnCode": 0,
            "stdout": data, "stderr": b"", "bytesObserved": len(data), "elapsedSeconds": .01}
        def runner(command, **limits):
            self.calls.append((command, limits))
            return copy.deepcopy(supplied)
        receipt = logs.collect(self.stage, self.comparison, self.clock_dir, output, self.commit, runner)
        self.assertEqual(receipt, json.loads((output / "receipt.json").read_text()))
        return receipt, output

    def test_asn_only_shared_request_survives_query_and_target_is_not_emitter(self):
        receipt, output = self.collect()
        self.assertTrue(receipt["collectionCompleted"], receipt)
        self.assertEqual(len(self.calls), 1)
        command, limits = self.calls[0]
        self.assertEqual(limits, {"timeout": 20, "byte_limit": 10 * 1024 * 1024})
        self.assertNotIn("processID", command[-1])
        self.assertNotIn("MATCHES", command[-1])
        self.assertNotIn("CONTAINS", command[-1])
        self.assertIn('subsystem == "com.apple.processmanager"', command[-1])
        self.assertIn(self.config["nonce"], command[-1])
        self.assertEqual(command[command.index("--start") + 1], "2026-11-07 00:00:00+0000")
        self.assertEqual(command[command.index("--end") + 1], "2026-11-07 00:00:32+0000")
        analysis = json.loads((output / "analysis.json").read_text())
        request = next(r for r in analysis["frontRecords"] if r["sourceRecordIndex"] == 5)
        self.assertEqual(request["emittingPID"], 99)
        self.assertEqual(request["targetAssociation"]["targetPID"], 200)
        self.assertEqual(request["targetAssociation"]["status"], "bound-to-owned-observed-lifetime")
        self.assertEqual(request["phase"], {"status": "resolved", "phase": "cancel-entered-before-escape"})
        self.assertEqual(analysis["originAttribution"], "not-established")
        self.assertTrue(all(r["status"] == "observed" for r in analysis["startupCalibration"]))
        self.assertFalse(any(r["generalHeldPathCoverageEstablished"] for r in analysis["startupCalibration"]))
        self.assertEqual(logs.analyze_records(json.loads((output / "records.json").read_text()),
            json.loads((output / "context.json").read_text()), json.loads((output / "clock-inputs.json").read_text())), analysis)

    def test_every_raw_field_is_retained_and_zero_activity_trace_ids_do_not_join(self):
        records = self.records()
        records[5].update(parentActivityIdentifier=456, senderProgramCounter=789, backtrace={"frames": [1, 2]},
                          inventedFutureField={"preserved": True})
        records.append(self.request(asn="0x0-0xdead"))
        receipt, output = self.collect(entries=records)
        retained = json.loads((output / "records.json").read_text())
        self.assertEqual(retained, records)
        self.assertEqual(json.loads((output / "raw.stdout").read_bytes()), records)
        self.assertEqual(receipt["recordCount"], 8)
        analysis = json.loads((output / "analysis.json").read_text())
        foreign = next(r for r in analysis["frontRecords"] if r["sourceRecordIndex"] == 7)
        self.assertEqual(foreign["targetAssociation"]["status"], "unresolved")
        self.assertNotIn("targetPID", foreign["targetAssociation"])

    def test_conflicting_asn_or_pid_anchor_anywhere_in_query_is_ambiguous(self):
        for extra in (self.anchor(when=24, pid=999), self.anchor(when=24, asn="0x0-0x999")):
            with self.subTest(extra=extra):
                analysis = self.analyze(self.records() + [extra])
                self.assertTrue(analysis["mappingConflicts"])
                row = next(r for r in analysis["frontRecords"] if r["sourceRecordIndex"] == 5)
                self.assertEqual(row["targetAssociation"]["reasonCode"], "conflicting-or-ambiguous-asn-anchors")

    def test_self_emitter_path_conflict_is_not_a_shared_emitter_reference(self):
        bad = self.anchor(when=24, path="/reused/pid/OtherExecutable")
        analysis = self.analyze(self.records() + [bad])
        self.assertIn("self-emitter-path-conflict", {r["kind"] for r in analysis["mappingConflicts"]})
        row = next(r for r in analysis["frontRecords"] if r["sourceRecordIndex"] == 5)
        self.assertEqual(row["targetAssociation"]["status"], "unresolved")
        shared = self.anchor(when=24, emitter=99, path="/System/WindowServer")
        analysis = self.analyze(self.records() + [shared])
        self.assertFalse(analysis["mappingConflicts"])
        row = next(r for r in analysis["frontRecords"] if r["sourceRecordIndex"] == 5)
        self.assertEqual(row["targetAssociation"]["status"], "bound-to-owned-observed-lifetime")

    def test_other_boot_wrong_path_and_outside_pid_window_do_not_bind(self):
        for records in (
                [self.marker("before"), self.anchor(boot=OTHER_BOOT), self.request(), self.marker("after")],
                [self.marker("before"), self.anchor(path="/foreign/NativeDragControl"), self.request(), self.marker("after")],
                [self.marker("before"), self.anchor(), self.request(when=28), self.marker("after")]):
            analysis = self.analyze(records)
            row = next(r for r in analysis["frontRecords"] if r["kind"] == "set-front-process")
            self.assertEqual(row["targetAssociation"]["status"], "unresolved")
            self.assertEqual(row["phase"]["status"], "unresolved")

    def test_overlapping_case_windows_make_identity_unresolved(self):
        context, clock = self.context()
        extra = copy.deepcopy(context["cases"][0])
        extra["case"] = "xctest-first"
        extra["ownedPIDs"] = {k: v + 1000 for k, v in extra["ownedPIDs"].items()}
        context["cases"].append(extra)
        analysis = logs.analyze_records(self.records(), context, clock)
        row = next(r for r in analysis["frontRecords"] if r["sourceRecordIndex"] == 5)
        self.assertEqual(row["targetAssociation"]["status"], "unresolved")

    def test_missing_duplicate_foreign_and_wrong_nonce_markers_never_calibrate(self):
        original = self.records()
        foreign = self.marker("before")
        foreign["processID"] = 999
        wrong_nonce = self.marker("before")
        wrong_nonce["eventMessage"] = wrong_nonce["eventMessage"].replace("e" * 32, "f" * 32)
        for records in (original[1:], original + [copy.deepcopy(original[0])], original + [foreign],
                        [foreign] + original[1:], [wrong_nonce] + original[1:]):
            with self.subTest(records=records):
                analysis = self.analyze(records)
                self.assertEqual(analysis["clockAlignment"]["status"], "unresolved")
                self.assertTrue(all(r["uptimeInterval"]["status"] == "unresolved" for r in analysis["frontRecords"]))

    def test_incorrect_timebase_or_disjoint_offsets_cannot_create_phase_order(self):
        for change in ("scale", "offset", "boot"):
            context, clock = self.context()
            if change == "scale":
                for snapshot in clock["snapshots"].values():
                    snapshot["machTimebaseNumer"] = 125
                    snapshot["machTimebaseDenom"] = 3
            elif change == "offset":
                for key in ("systemUptimeSample", "systemUptimeBeforeLog", "systemUptimeAfterLog"):
                    clock["snapshots"]["after"][key] += .01
            else:
                clock["snapshots"]["after"]["bootUUID"] = OTHER_BOOT
            analysis = logs.analyze_records(self.records(), context, clock)
            self.assertEqual(analysis["clockAlignment"]["status"], "unresolved", change)

    def test_compatible_clock_kind_ambiguity_uses_union_and_boundary_is_unresolved(self):
        context, clock = self.context()
        for snapshot in clock["snapshots"].values():
            for suffix in ("BeforeUptime", "AfterUptime", "BeforeLog", "AfterLog"):
                snapshot["continuous" + suffix] = snapshot["absolute" + suffix]
        records = self.records() + [self.request(when=12.91)]
        analysis = logs.analyze_records(records, context, clock)
        self.assertEqual(analysis["clockAlignment"]["status"], "aligned")
        self.assertTrue(analysis["clockAlignment"]["clockKindAmbiguous"])
        row = next(r for r in analysis["frontRecords"] if r["sourceRecordIndex"] == 7)
        self.assertEqual(row["phase"], {"status": "unresolved", "reasonCode": "phase-boundary-crossing"})

    def test_exact_arm_timebase_cancellation_bounds_are_outward(self):
        tick = 7_200_000_001
        expected = Fraction(-1, 24_000_000)
        interval = logs.offset_interval(300., tick, tick, Fraction(125, 3_000_000_000))
        self.assertEqual(interval, [expected, expected])
        low, high = logs.directed_float(interval[0], False), logs.directed_float(interval[1], True)
        self.assertLessEqual(Fraction(low), expected)
        self.assertGreaterEqual(Fraction(high), expected)
        alignment = {"status": "aligned", "bootUUID": BOOT,
            "markers": {"before": {"machTimestamp": tick - 10}, "after": {"machTimestamp": tick + 10}},
            "models": [{"machTimebaseNumer": 125, "machTimebaseDenom": 3, "offsetIntervalSeconds": [low, high]}]}
        bound = logs.uptime_interval({"bootUUID": BOOT, "machTimestamp": tick}, alignment)
        self.assertLessEqual(bound["lower"], 300.)
        self.assertGreaterEqual(bound["upper"], 300.)

    def test_release_observation_interval_does_not_claim_button_still_held(self):
        # Fixture Quartz mouse-up is posted at15.91, observation at15.94.
        # A request after the post must never become a held-button proof.
        analysis = self.analyze(self.records() + [self.request(when=15.93)])
        row = next(r for r in analysis["frontRecords"] if r["sourceRecordIndex"] == 7)
        self.assertEqual(row["phase"], {"status": "resolved",
            "phase": "cancel-after-escape-before-release-observation", "heldButtonClaimSupported": False})

    def test_clock_marker_inside_observed_case_is_unresolved(self):
        context, clock = self.context()
        context["cases"][0]["phases"][0]["start"] = .5
        analysis = logs.analyze_records(self.records(), context, clock)
        self.assertEqual(analysis["clockAlignment"]["reasonCode"], "clock-not-outside-observed-case-lifetimes")
        self.assertTrue(all(r["uptimeInterval"]["status"] == "unresolved" for r in analysis["frontRecords"]))

    def test_startup_pre_trace_is_only_candidate_and_not_precise_lifetime(self):
        records = self.records()
        records[1] = self.anchor(when=1.8)
        records[2] = self.request(when=1.9)
        analysis = self.analyze(records)
        row = next(r for r in analysis["frontRecords"] if r["sourceRecordIndex"] == 2)
        self.assertEqual(row["targetAssociation"]["status"], "candidate-owned-association")
        self.assertEqual(row["phase"]["status"], "unresolved")
        target = next(r for r in analysis["startupCalibration"] if r["role"] == "target")
        self.assertEqual(target["status"], "observed")
        self.assertFalse(target["generalHeldPathCoverageEstablished"])

    def test_post_log_helper_failure_invalidates_marker_but_not_native_pass(self):
        self.save_snapshot("after", self.snapshots["after"], returncode=2)
        receipt, output = self.collect()
        self.assertTrue(receipt["collectionCompleted"], receipt)
        analysis = json.loads((output / "analysis.json").read_text())
        self.assertEqual(analysis["clockAlignment"]["status"], "unresolved")
        self.assertTrue(analysis["nativeResults"][0]["strictNativeOutcome"]["passed"])
        self.assertEqual(analysis["nativeResults"][0]["outcome"], "captured")
        self.assertFalse(analysis["nativeVerdictsChanged"])

    def test_native_fail_is_preserved_with_zero_records_and_no_absence_claim(self):
        self.make_comparison(passed=False)
        receipt, output = self.collect(entries=[])
        self.assertEqual(receipt["status"], "completed-empty")
        analysis = json.loads((output / "analysis.json").read_text())
        self.assertFalse(analysis["nativeResults"][0]["strictNativeOutcome"]["passed"])
        self.assertEqual(analysis["nativeResults"][0]["outcome"], "escape-cancellation-failed")
        self.assertEqual(analysis["originAttribution"], "not-established")

    def test_changed_hash_or_case_plan_blocks_query(self):
        (self.directory / "source.jsonl").write_bytes((self.directory / "source.jsonl").read_bytes() + b"\n")
        receipt, output = self.collect()
        self.assertEqual(receipt["queryCount"], 0)
        self.assertEqual(receipt["errorCode"], "activation-request-trace-hash")
        self.assertEqual((output / "raw.stdout").read_bytes(), b"")
        comparison = copy.deepcopy(self.native_comparison)
        comparison["caseOrder"] = list(reversed(logs.mouse.CASES))
        write(self.comparison / "comparison.json", comparison)
        receipt, _ = self.collect()
        self.assertEqual(receipt["queryCount"], 0)
        self.assertEqual(receipt["errorCode"], "activation-request-case-plan")
        self.assertFalse(self.calls)

    def test_incomplete_native_cleanup_blocks_supplement_query(self):
        path = self.directory / "report.json"
        report = json.loads(path.read_text())
        report["cleanup"]["applicationStopped"] = False
        write(path, report)
        self.native_comparison["cases"][0]["caseSHA256"] = logs.capture.sha256(path)
        write(self.comparison / "comparison.json", self.native_comparison)
        receipt, _ = self.collect()
        self.assertEqual(receipt["queryCount"], 0)
        self.assertEqual(receipt["errorCode"], "activation-request-case-native-binding")
        self.assertFalse(self.calls)

    def test_missing_execution_receipt_or_snapshot_hash_is_unresolved(self):
        (self.clock_dir / "before-execution.json").unlink()
        receipt, output = self.collect()
        self.assertTrue(receipt["collectionCompleted"])
        analysis = json.loads((output / "analysis.json").read_text())
        self.assertEqual(analysis["clockAlignment"]["status"], "unresolved")
        self.save_snapshot("before", self.snapshots["before"])
        (self.clock_dir / "before.json").write_bytes((self.clock_dir / "before.json").read_bytes() + b"\n")
        receipt, output = self.collect()
        analysis = json.loads((output / "analysis.json").read_text())
        self.assertEqual(analysis["clockAlignment"]["snapshotErrors"][0]["reasonCode"], "activation-request-clock-execution-hash")

    def test_bad_architecture_or_translation_is_not_a_clock_provenance_match(self):
        for probe in ({"returnCode": 0, "errno": 0, "value": 1, "status": "native"},
                      {"returnCode": False, "errno": 0, "value": 0, "status": "native"}):
            environment = copy.deepcopy(self.native_context["provenance"]["activationRequestClockEnvironment"])
            environment["translationProbe"] = probe
            with self.assertRaises(logs.capture.ComparisonError):
                logs.validate_environment(environment, self.config["architecture"])
        environment["translationProbe"] = {"returnCode": -1, "errno": 2, "value": None, "status": "not-exposed"}
        logs.validate_environment(environment, self.config["architecture"])

    def test_timeout_and_byte_cap_preserve_both_captured_pipes(self):
        for status in ("timeout", "truncated"):
            supplied = {"status": status, "returnCode": -9, "stdout": b'[partial', "stderr": b'bounded diagnostic',
                "bytesObserved": 100, "elapsedSeconds": 20.1}
            receipt, output = self.collect(result=supplied)
            self.assertEqual(receipt["status"], status)
            self.assertFalse(receipt["collectionCompleted"])
            self.assertFalse(receipt["stdoutComplete"])
            self.assertIsNone(receipt["fullRawSHA256"])
            self.assertEqual((output / "raw.stdout").read_bytes(), supplied["stdout"])
            self.assertEqual((output / "raw.stderr").read_bytes(), supplied["stderr"])
            self.assertFalse((output / "records.json").exists())
            self.assertEqual(receipt["stdoutSHA256"], hashlib.sha256(supplied["stdout"]).hexdigest())
        result = logs.bounded_log.run_log([sys.executable, "-c", "import os; os.write(2,b'e'*2048); os.write(1,b'o'*2048)"],
                                           timeout=2, byte_limit=1024)
        self.assertEqual(result["status"], "truncated")
        self.assertLessEqual(len(result["stdout"]) + len(result["stderr"]), 1024)

    def test_malformed_and_nonzero_results_preserve_exact_raw_bytes(self):
        for data, code in ((b'[{"a":1,"a":2}]', 0), (b'[NaN]', 0), (b'{}', 0), (b'not JSON', 0), (b'[]', 77)):
            supplied = {"status": "completed", "returnCode": code, "stdout": data, "stderr": b'error detail',
                "bytesObserved": len(data) + 12, "elapsedSeconds": .01}
            receipt, output = self.collect(result=supplied)
            self.assertEqual(receipt["status"], "error")
            self.assertFalse(receipt["collectionCompleted"])
            self.assertEqual((output / "raw.stdout").read_bytes(), data)
            self.assertEqual((output / "raw.stderr").read_bytes(), b'error detail')
            self.assertFalse((output / "records.json").exists())

    def test_analysis_exception_preserves_collected_bytes_and_fails_cli(self):
        with patch.object(logs, "analyze_records", side_effect=RuntimeError("fixture failure")):
            receipt, output = self.collect()
        self.assertTrue(receipt["collectionCompleted"])
        self.assertEqual(receipt["status"], "error")
        self.assertEqual(logs.exit_status(receipt), 1)
        self.assertEqual(json.loads((output / "records.json").read_text()), self.records())
        self.assertEqual(json.loads((output / "raw.stdout").read_bytes()), self.records())
        self.assertTrue(receipt["nativeResults"][0]["strictNativeOutcome"]["passed"])


if __name__ == "__main__":
    unittest.main()
