"""Portable D18 evidence-gate tests. No native program, input, or log query runs."""
import copy
import hashlib
import json
from pathlib import Path
import struct
import tempfile
import unittest
import uuid
from unittest.mock import patch

import analyze_native_activation_entry_calibration as calibration


BOOT = "12345678-1234-1234-1234-123456789ABC"
EXE_UUIDS = {"control": "11111111-1111-1111-1111-111111111111", "source": "22222222-2222-2222-2222-222222222222"}
LIB_UUID = "33333333-3333-3333-3333-333333333333"
APPKIT_UUID = "44444444-4444-4444-4444-444444444444"
STAGED = "/recorded/lemulip-native-ui"
OUTPUT = "/recorded/drag-activation-entry-calibration"


def clock(seconds):
    tick = round(seconds * 1_000_000_000)
    return {"machAbsoluteBefore": tick - 10, "machAbsoluteAfter": tick + 10,
            "machContinuousBefore": tick + 5_000_000_000 - 5,
            "machContinuousAfter": tick + 5_000_000_000 + 5,
            "systemUptime": seconds, "wallTimeUTC": "2026-11-08T00:00:00Z"}


def frame(path, identity, base, offset=512):
    return {"address": hex(base + offset), "imagePath": path, "imageUUID": identity,
            "imageBase": hex(base), "imageOffset": hex(offset), "symbol": "not-used-as-evidence", "symbolAddress": None}


def fixture():
    receipt = {"schema": 1, "kind": "native-activation-entry-startup-calibration", "caseName": "quartz-first",
        "status": "complete", "processCalibrationComplete": True, "stagedInputsUnchanged": True,
        "inputGenerated": False, "mouseInputGenerated": False, "keyboardInputGenerated": False,
        "accessibilityCallsMade": False, "newExplicitActivationCalls": 0, "launchRetryCount": 0,
        "stagedPath": STAGED, "outputPath": OUTPUT, "architecture": "x86_64", "bootUUID": BOOT,
        "machTimebaseNumer": 1, "machTimebaseDenom": 1,
        "runClockBeforeLaunch": clock(.5), "runClockAfterTermination": clock(8), "processes": {}, "nativeLogs": {},
        "nativeLifecycleRecordsComplete": True, "unexpectedNativeInputObserved": False}
    probes, binaries = {}, {}
    for role, pid, start, ready_time, flush in (("control", 101, 1, 2, 7), ("source", 102, 3, 4, 6)):
        capitalized = "Control" if role == "control" else "Source"
        bundle = STAGED + "/Native Drag " + capitalized + ".app"
        executable = bundle + "/Contents/MacOS/NativeDrag" + capitalized
        library_path = bundle + "/Contents/Frameworks/" + calibration.LIBRARY_NAME
        ready = {"pid": pid, "event": "application-ready" if role == "control" else "source-ready",
                 "systemUptime": ready_time}
        receipt["processes"][role] = {"role": role, "pid": pid, "bundleIdentifier": "app.lemulip.NativeDrag" + capitalized,
            "bundlePath": bundle, "executablePath": executable, "executableSHA256": "a" * 64,
            "arguments": ["-controlTheme", "orchard", "-controlEvidenceKind", "activation-quartz-first"] if role == "control"
                else ["--case", "quartz-first", "--frame-x", "48.0", "--frame-y", "72.0", "--frame-width", "480.0",
                      "--frame-height", "320.0", "--point-x", "288.0", "--point-y", "232.0"],
            "environment": {"LEMULIP_ACTIVATION_PROBE_OUTPUT": OUTPUT + "/" + role + ".json"},
            "probeOutputPath": OUTPUT + "/" + role + ".json", "launchRequested": True, "ready": True,
            "launchRequestedClock": clock(start), "launchReturnedClock": clock(start + .2),
            "readyObservedClock": clock(ready_time + .1), "readyRecords": [ready],
            "activeWitness": {"isActive": True, "clock": clock(ready_time + .2)},
            "cleanup": {"normalTerminationRequested": True, "terminateReturn": True, "fallbackUsed": False,
                "signals": [], "terminated": True, "completedNormally": True, "identityVerified": True,
                "exitStatus": None, "exitStatusAvailable": False, "terminatedObservedClock": clock(flush + .1)}}
        binaries[role] = {"executable": {"path": executable, "sha256": "a" * 64,
                            "architecture": "x86_64", "imageUUID": EXE_UUIDS[role]},
                          "library": {"path": library_path, "sha256": "b" * 64,
                            "architecture": "x86_64", "imageUUID": LIB_UUID}}
        call = {"callID": 1, "pid": pid, "threadID": 501, "threadIDError": 0,
                "function": "SetFrontProcess", "returnType": "OSErr", "resultBits": 16,
                "targetPSN": {"high": 0, "low": 98765}, "options": None, "nestingDepth": 1,
                "completed": True, "result": 0, "entryErrno": 0, "resultErrno": 0,
                "frameCount": 2, "stackMayBeTruncated": False,
                "frames": [frame(library_path, LIB_UUID, 0x110000000), frame(calibration.APPKIT, APPKIT_UUID, 0x100000000)]}
        for family, extra in (("MachAbsolute", 0), ("MachContinuous", 5_000_000_000)):
            for field, seconds in (("entry", start + .3), ("preOriginal", start + .31), ("afterOriginal", start + .32)):
                call[field + family] = round(seconds * 1_000_000_000) + extra
        probe = {"schemaVersion": 1, "probe": "NativeActivationEntryProbe", "scope": "startup-calibration-only",
            "architecture": "x86_64", "pid": pid, "executablePath": executable, "executableImageUUID": EXE_UUIDS[role],
            "library": {"path": library_path, "imageUUID": LIB_UUID, "imageBase": "0x110000000"},
            "bootUUID": BOOT, "machTimebaseNumer": 1, "machTimebaseDenom": 1,
            "initialized": True, "initializationError": None, "warmupCompleted": True,
            "atexitInvoked": True, "captureClosed": True, "countsAsOf": "capture-close", "recordCapacity": 128, "frameCapacity": 48,
            "counts": {"totalCalls": 1, "recordedCalls": 1, "completedCalls": 1, "droppedCalls": 0,
                "incompleteCalls": 0, "nestedCalls": 0, "overflowCalls": 0, "beforeReadyCalls": 0,
                "afterCaptureClosedCalls": 0, "activeCallsAtFlush": 0}, "calls": [call]}
        for family, extra in (("MachAbsolute", 0), ("MachContinuous", 5_000_000_000)):
            for field, seconds in (("constructor", start + .1), ("ready", start + .11), ("flush", flush)):
                probe[field + family] = round(seconds * 1_000_000_000) + extra
        probes[role] = probe
        log_name = "receiver" if role == "control" else "source"
        terminating = {"pid": pid, "event": "application-terminated" if role == "control" else "application-terminating",
                       "systemUptime": flush - .1}
        if role == "source":
            terminating.update(sessionCount=0, activeSession=False)
        receipt["nativeLogs"][log_name] = {"status": "complete", "path": STAGED + "/" + calibration.EVIDENCE_DIRECTORY + "/" + log_name + ".jsonl", "records": [ready, terminating]}
    receipt["nativeLogs"]["activation"] = {"status": "complete", "path": STAGED + "/" + calibration.EVIDENCE_DIRECTORY + "/activation.jsonl",
        "records": [{"pid": 101, "event": "activation-ready", "systemUptime": 2.01},
                    {"pid": 101, "event": "activation-terminating", "systemUptime": 6.9}]}
    return receipt, probes, binaries


def analyze(receipt, probes, binaries, **kwargs):
    return calibration.analyze_records(receipt, probes, binaries, inputs_preserved=True, **kwargs)


class CalibrationGateTests(unittest.TestCase):
    def setUp(self):
        self.receipt, self.probes, self.binaries = fixture()

    def run_analysis(self):
        return analyze(self.receipt, self.probes, self.binaries)

    def test_positive_entries_only_calibrate_startup(self):
        result = self.run_analysis()
        self.assertEqual(result["status"], "startup-route-calibrated", result)
        self.assertTrue(result["startupComplete"])
        self.assertTrue(result["calibrationGatePassed"])
        self.assertFalse(result["heldRouteCoverageEstablished"])
        self.assertFalse(result["ultimateRequesterEstablished"])
        self.assertFalse(result["releaseReady"])
        self.assertEqual(result["C12"], "HOLD")

    def test_arm_fractional_timebase_uses_native_ticks_without_float_guess(self):
        self.receipt.update(architecture="arm64", machTimebaseNumer=125, machTimebaseDenom=3)
        def convert(value):
            if isinstance(value, dict):
                for key, item in value.items():
                    if ("MachAbsolute" in key or "MachContinuous" in key or key.startswith("machAbsolute")
                            or key.startswith("machContinuous")) and type(item) is int:
                        value[key] = (item * 3 + (124 if key.endswith("After") else 0)) // 125
                    else:
                        convert(item)
            elif isinstance(value, list):
                for item in value:
                    convert(item)
        convert(self.receipt)
        for role in calibration.ROLES:
            self.probes[role].update(architecture="arm64", machTimebaseNumer=125, machTimebaseDenom=3)
            convert(self.probes[role])
            for binary in self.binaries[role].values():
                binary["architecture"] = "arm64"
        result = self.run_analysis()
        self.assertEqual(result["status"], "startup-route-calibrated", result)

    def test_complete_zero_calls_is_unproven_not_incomplete_or_absent_requests(self):
        for probe in self.probes.values():
            probe["calls"] = []
            probe["counts"].update(totalCalls=0, recordedCalls=0, completedCalls=0)
        result = self.run_analysis()
        self.assertEqual(result["status"], "coverage-unproven")
        self.assertTrue(result["startupComplete"])
        self.assertFalse(result["calibrationGatePassed"])
        self.assertTrue(all(row["evidenceComplete"] for row in result["roles"]))

    def test_one_unproven_role_holds_overall_gate(self):
        self.probes["source"]["calls"] = []
        self.probes["source"]["counts"].update(totalCalls=0, recordedCalls=0, completedCalls=0)
        result = self.run_analysis()
        self.assertEqual(result["status"], "coverage-unproven")
        self.assertEqual(result["roles"][0]["qualifyingCallIDs"], [1])

    def test_symbol_text_cannot_substitute_for_raw_appkit_image(self):
        frame = self.probes["control"]["calls"][0]["frames"][1]
        frame.update(imagePath="/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation", symbol="-[NSApplication activateIgnoringOtherApps:]")
        self.assertEqual(self.run_analysis()["status"], "coverage-unproven")

    def test_after_native_ready_before_poll_is_not_pre_ready(self):
        call = self.probes["control"]["calls"][0]
        for family, extra in (("MachAbsolute", 0), ("MachContinuous", 5_000_000_000)):
            for field, seconds in (("entry", 2.02), ("preOriginal", 2.03), ("afterOriginal", 2.04)):
                call[field + family] = round(seconds * 1_000_000_000) + extra
        result = self.run_analysis()
        self.assertEqual(result["status"], "coverage-unproven")
        self.assertFalse(result["roles"][0]["calls"][0]["completedWhollyBeforeNativeReady"])

    def test_uncertain_boundary_is_not_rounded_into_pre_ready(self):
        call = self.probes["control"]["calls"][0]
        call["afterOriginalMachAbsolute"] = 2_000_000_000
        call["afterOriginalMachContinuous"] = 7_000_000_000
        self.assertEqual(self.run_analysis()["status"], "coverage-unproven")

    def test_original_error_and_null_psn_are_observations_not_activation_cause(self):
        call = self.probes["control"]["calls"][0]
        call.update(result=-50, targetPSN=None)
        result = self.run_analysis()
        self.assertEqual(result["status"], "startup-route-calibrated")
        self.assertEqual(result["roles"][0]["calls"][0]["result"], -50)
        self.assertIsNone(result["roles"][0]["calls"][0]["targetPSN"])

    def test_with_options_uses_32_bit_signed_result(self):
        call = self.probes["control"]["calls"][0]
        call.update(function="SetFrontProcessWithOptions", returnType="OSStatus", resultBits=32, options=0xFFFFFFFF, result=-65536)
        self.assertEqual(self.run_analysis()["status"], "startup-route-calibrated")
        call.update(function="SetFrontProcess", returnType="OSErr", resultBits=16, options=None)
        self.assertEqual(self.run_analysis()["status"], "evidence-incomplete")

    def test_missing_probe_keeps_independent_completed_startup(self):
        self.probes["control"] = None
        result = self.run_analysis()
        self.assertEqual(result["status"], "evidence-incomplete")
        self.assertTrue(result["startupComplete"])
        self.assertFalse(result["roles"][0]["evidenceComplete"])

    def test_identity_and_capture_errors_close_gate(self):
        cases = {
            "wrong pid": lambda p: p.update(pid=777),
            "wrong executable": lambda p: p.update(executablePath="/another/NativeDragControl"),
            "wrong executable UUID": lambda p: p.update(executableImageUUID=LIB_UUID),
            "wrong boot": lambda p: p.update(bootUUID=LIB_UUID),
            "wrong timebase": lambda p: p.update(machTimebaseNumer=125),
            "not initialized": lambda p: p.update(initialized=False),
            "not final": lambda p: p.update(atexitInvoked=False),
            "overflow": lambda p: p["counts"].update(overflowCalls=1),
            "inflight": lambda p: p["counts"].update(activeCallsAtFlush=1),
            "lost call": lambda p: p["counts"].update(totalCalls=2, droppedCalls=1),
            "truncated stack": lambda p: p["calls"][0].update(stackMayBeTruncated=True),
            "unfinished original": lambda p: p["calls"][0].update(completed=False, result=None),
            "wrong call pid": lambda p: p["calls"][0].update(pid=777),
            "wrong frame UUID": lambda p: p["calls"][0]["frames"][0].update(imageUUID=APPKIT_UUID),
            "bad frame address": lambda p: p["calls"][0]["frames"][1].update(address="0x999"),
            "frame UUID malformed": lambda p: p["calls"][0]["frames"][1].update(imageUUID="unknown"),
        }
        for name, mutate in cases.items():
            with self.subTest(name=name):
                receipt, probes, binaries = fixture()
                mutate(probes["control"])
                result = analyze(receipt, probes, binaries)
                self.assertEqual(result["status"], "evidence-incomplete", result)
                self.assertFalse(result["calibrationGatePassed"])

    def test_honest_unresolved_frame_does_not_claim_appkit(self):
        self.probes["control"]["calls"][0]["frames"][1].update(imageUUID=None)
        result = self.run_analysis()
        self.assertEqual(result["status"], "coverage-unproven")
        self.assertEqual(result["roles"][0]["unresolvedFrameCount"], 1)

    def test_one_unresolved_other_frame_does_not_discard_real_appkit_witness(self):
        call = self.probes["control"]["calls"][0]
        call["frames"].append({"address": "0x123456", "imagePath": None, "imageUUID": None, "imageBase": None, "imageOffset": None})
        call["frameCount"] += 1
        self.assertEqual(self.run_analysis()["status"], "startup-route-calibrated")

    def test_nested_counter_uses_depth_above_one(self):
        probe = self.probes["control"]
        call = copy.deepcopy(probe["calls"][0])
        call.update(callID=2, nestingDepth=2)
        probe["calls"].append(call)
        probe["counts"].update(totalCalls=2, recordedCalls=2, completedCalls=2, nestedCalls=1)
        self.assertEqual(self.run_analysis()["status"], "startup-route-calibrated")

    def test_input_fallback_and_clock_disagreement_close_gate(self):
        cases = {
            "input flag": lambda r: r.update(inputGenerated=True),
            "AX flag": lambda r: r.update(accessibilityCallsMade=True),
            "retry": lambda r: r.update(launchRetryCount=1),
            "fallback": lambda r: r["processes"]["source"]["cleanup"].update(fallbackUsed=True),
            "not active": lambda r: r["processes"]["source"]["activeWitness"].update(isActive=False),
            "native input": lambda r: r["nativeLogs"]["source"]["records"].append({"pid": 102, "event": "source-session-requested"}),
            "clock drift": lambda r: r["runClockAfterTermination"].update(systemUptime=9),
            "boolean clock": lambda r: r["runClockAfterTermination"].update(machAbsoluteAfter=True),
            "ready not retained": lambda r: r["nativeLogs"]["receiver"].update(records=[]),
        }
        for name, mutate in cases.items():
            with self.subTest(name=name):
                receipt, probes, binaries = fixture()
                mutate(receipt)
                self.assertEqual(analyze(receipt, probes, binaries)["status"], "evidence-incomplete")

    def test_input_preservation_requires_explicit_verified_context(self):
        result = calibration.analyze_records(self.receipt, self.probes, self.binaries)
        self.assertEqual(result["status"], "evidence-incomplete")

    def test_bad_json_duplicate_and_nonfinite_values_are_rejected(self):
        for raw in (b'{"pid":1,"pid":2}', b'{"clock":NaN}', b'{"clock":Infinity}', b'{"bad":'):
            with self.subTest(raw=raw), self.assertRaises(ValueError):
                calibration.parse_json(raw)


def macho(identity, *, cpu=0x01000007, file_type=2):
    return struct.pack("<8I", 0xFEEDFACF, cpu, 3, file_type, 1, 24, 0, 0) + struct.pack("<2I", 0x1B, 24) + uuid.UUID(identity).bytes


def artifact_fixture(root):
    staged, output = root / "lemulip-native-ui", root / "out"
    staged.mkdir()
    (output / "build").mkdir(parents=True)
    (output / "sources").mkdir()
    receipt, probes, _ = fixture()
    builds = {}
    probe_data = macho(LIB_UUID, file_type=6)
    for role in ("control", "source", "probe", "helper"):
        if role in calibration.ROLES:
            original = receipt["processes"][role]["executablePath"]
            path = staged / original.removeprefix(STAGED + "/")
            data = macho(EXE_UUIDS[role])
            library = path.parent.parent / "Frameworks" / calibration.LIBRARY_NAME
            library.parent.mkdir(parents=True)
            library.write_bytes(probe_data)
        else:
            filename = calibration.LIBRARY_NAME if role == "probe" else "NativeActivationEntryCalibration"
            path = output / "build" / filename
            original = OUTPUT + "/build/" + filename
            data = probe_data if role == "probe" else macho("55555555-5555-5555-5555-555555555555")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        identity = calibration.macho_identity(data)
        builds[role] = {"path": original, "sha256": identity["sha256"], "architectures": ["x86_64"],
                        "uuidOutput": "UUID: " + identity["imageUUID"] + " (x86_64) " + original + "\n"}
        if role in calibration.ROLES:
            receipt["processes"][role]["executableSHA256"] = identity["sha256"]
    source_hashes = {}
    for name in calibration.ORIGINAL_SOURCES:
        data = (Path(__file__).parent / "native_ui" / name).read_bytes()
        (output / "sources" / name).write_bytes(data)
        source_hashes[name] = hashlib.sha256(data).hexdigest()
    provenance = {"sourceCommit": "d821d7343675e2850705d141ef9b3b93a6aee945",
        "sourceTree": "425baa28f00ec24551dd70c0cc874a75fa3be0c1", "architecture": "x86_64",
        "startupCalibrationOnly": True, "nativeInputExecuted": False, "releaseReady": False,
        "activationEntryCalibrationBuilds": builds, "retainedDiagnosticSourcesSHA256": source_hashes,
        "nativeDragControlSourceSHA256": source_hashes["NativeDragControl.swift"],
        "nativeDragSourceSourceSHA256": source_hashes["NativeDragSource.swift"],
        "controlGUI_SHA256": builds["control"]["sha256"], "sourceGUI_SHA256": builds["source"]["sha256"]}
    receipt["provenance"] = provenance
    receipt["helperExecutablePath"] = builds["helper"]["path"]
    (staged / "provenance.json").write_text(json.dumps(provenance))
    inventory = {}
    for path in staged.rglob("*"):
        inventory[path.relative_to(staged).as_posix()] = {"kind": "directory"} if path.is_dir() else {
            "kind": "file", "bytes": path.stat().st_size, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
    for name in ("inputs-before.json", "inputs-after.json"):
        (output / name).write_text(json.dumps(inventory))
    (output / "input-preservation.json").write_text(json.dumps({"schema": 1, "inputsUnchanged": True,
        "beforeEntries": len(inventory), "afterEntries": len(inventory)}))
    for role, probe in probes.items():
        data = (json.dumps(probe) + "\n").encode()
        (output / (role + ".json")).write_bytes(data)
        receipt["processes"][role]["probeReceipt"] = {"status": "retained", "path": OUTPUT + "/" + role + ".json",
            "byteCount": len(data), "sha256": hashlib.sha256(data).hexdigest()}
    journals = staged / calibration.EVIDENCE_DIRECTORY
    journals.mkdir(parents=True)
    for name, log in receipt["nativeLogs"].items():
        data = b"".join((json.dumps(row) + "\n").encode() for row in log["records"])
        (journals / (name + ".jsonl")).write_bytes(data)
        log.update(byteCount=len(data), sha256=hashlib.sha256(data).hexdigest())
    (output / "calibration-run.json").write_text(json.dumps(receipt))
    return staged, output


class ArtifactBindingTests(unittest.TestCase):
    def test_full_archived_artifact_replay_and_cli(self):
        with tempfile.TemporaryDirectory() as directory:
            staged, output = artifact_fixture(Path(directory).resolve())
            receipt, probes, binaries = calibration.load_evidence(staged, output)
            result = analyze(receipt, probes, binaries)
            self.assertEqual(result["status"], "startup-route-calibrated", result)
            with patch("builtins.print"):
                code = calibration.main(["--staged", str(staged), "--output", str(output)])
            self.assertEqual(code, 0)
            self.assertEqual(json.loads((output / "analysis.json").read_text())["status"], "startup-route-calibrated")

    def test_artifact_byte_and_inventory_mismatch_are_incomplete(self):
        mutations = {
            "executable": lambda staged, output: (staged / "Native Drag Control.app/Contents/MacOS/NativeDragControl").write_bytes(b"changed"),
            "loaded dylib": lambda staged, output: (staged / "Native Drag Source.app/Contents/Frameworks" / calibration.LIBRARY_NAME).write_bytes(b"changed"),
            "extra immutable file": lambda staged, output: (staged / "unplanned.txt").write_text("changed"),
            "probe JSON changed": lambda staged, output: (output / "control.json").write_text("{}"),
            "native journal changed": lambda staged, output: (staged / calibration.EVIDENCE_DIRECTORY / "source.jsonl").write_text("{}\n"),
            "input receipt disagrees": lambda staged, output: (output / "inputs-after.json").write_text("{}"),
            "original source changed": lambda staged, output: (output / "sources/NativeDragSource.swift").write_text("changed"),
        }
        for name, mutate in mutations.items():
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                staged, output = artifact_fixture(Path(directory).resolve())
                mutate(staged, output)
                with patch("builtins.print"):
                    self.assertEqual(calibration.main(["--staged", str(staged), "--output", str(output)]), 1)
                self.assertEqual(json.loads((output / "analysis.json").read_text())["status"], "evidence-incomplete")

    def test_macho_native_uuid_arch_and_digest(self):
        data = macho(EXE_UUIDS["control"])
        value = calibration.macho_identity(data)
        self.assertEqual(value["imageUUID"], EXE_UUIDS["control"])
        self.assertEqual(value["architecture"], "x86_64")
        self.assertEqual(value["sha256"], hashlib.sha256(data).hexdigest())
        self.assertEqual(calibration.macho_identity(macho(EXE_UUIDS["source"], cpu=0x0100000C))["architecture"], "arm64")

    def test_macho_invalid_and_duplicate_uuid_are_not_identity(self):
        data = macho(EXE_UUIDS["control"])
        duplicate = struct.pack("<8I", 0xFEEDFACF, 0x01000007, 3, 2, 2, 48, 0, 0) + data[32:] * 2
        for bad in (b"not Mach-O", data[:-1], macho(EXE_UUIDS["control"], cpu=7), duplicate):
            with self.subTest(size=len(bad)), self.assertRaises(calibration.EvidenceError):
                calibration.macho_identity(bad)

    def test_missing_final_receipt_is_incomplete_and_analysis_is_exclusive(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            staged, output = root / "lemulip-native-ui", root / "out"
            staged.mkdir()
            output.mkdir()
            (output / "control.json.pending").write_text('{"valid-looking":"pending only"}')
            with patch("builtins.print"):
                self.assertEqual(calibration.main(["--staged", str(staged), "--output", str(output)]), 1)
            before = (output / "analysis.json").read_bytes()
            self.assertEqual(json.loads(before)["status"], "evidence-incomplete")
            with patch("builtins.print"):
                self.assertEqual(calibration.main(["--staged", str(staged), "--output", str(output)]), 1)
            self.assertEqual((output / "analysis.json").read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
