"""Portable checks for D14 log scope, provenance and incomplete collection."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

import capture_native_drag_system_log as logs


class SystemLogTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.stage, self.comparison = self.root / "stage", self.root / "comparison"
        self.stage.mkdir()
        self.comparison.mkdir()
        self.analysis_path = self.root / "event-origin-analysis.json"
        self.commit = "a" * 40
        self.calls, self.outputs = [], 0
        name = logs.mouse.CASES[0]
        self.directory = logs.mouse.evidence_for(self.stage, name) / "orchard"
        self.directory.mkdir(parents=True)
        self.paths = {"observer": str(self.stage / logs.mouse.OBSERVER),
            "source": str(self.stage / "Native Drag Source.app/Contents/MacOS/NativeDragSource"),
            "target": str(self.stage / "Native Drag Control.app/Contents/MacOS/NativeDragControl"),
            "runner": str(self.stage / logs.mouse.RUNNER_RELATIVE / "Contents/MacOS/QualityReview-Runner")}
        self.raw = {"observerProcessID": 111, "sourceApplicationPID": 222, "targetApplicationPID": 333,
            "applicationPath": str(self.stage / "Native Drag Control.app"),
            "sourceApplicationPath": str(self.stage / "Native Drag Source.app"),
            "mouseControlDriver": {"runnerPID": 444, "runnerExecutablePath": self.paths["runner"]}}
        self.write(self.directory / "report.json", self.raw)
        receiver = [{"pid": 333, "mouseDriverCase": name, "time": value} for value in
                    ("2026-11-06T20:00:10Z", "2026-11-06T20:00:20Z")]
        (self.directory / "receiver.jsonl").write_text("\n".join(json.dumps(row) for row in receiver) + "\n")
        provenance = {"observerExperimentCommit": self.commit, "observerExperimentTree": "b" * 40,
            "architecture": "arm64", "eventOriginDiagnostic": logs.PROTOCOL,
            "eventOriginSystemLogCollectorSourceSHA256": logs.capture.sha256(Path(logs.__file__))}
        self.write(self.stage / "provenance.json", provenance)
        case_hash = logs.capture.sha256(self.directory / "report.json")
        receiver_hash = logs.capture.sha256(self.directory / "receiver.jsonl")
        comparison = {"provenance": provenance, "cases": [{"mouseDriverCase": case} for case in logs.mouse.CASES]}
        comparison["cases"][0].update(caseSHA256=case_hash, receiver={"receiverSHA256": receiver_hash})
        self.write(self.comparison / "comparison.json", comparison)
        self.analysis = {"schema": 1, "diagnostic": "native-drag-event-origin", "experimentCommit": self.commit,
            "experimentTree": "b" * 40, "architecture": "arm64", "protocolBaseCommit": logs.PROTOCOL["protocolBaseCommit"],
            "inputProtocol": logs.PROTOCOL["inputProtocol"],
            "provenanceSHA256": logs.capture.sha256(self.stage / "provenance.json"),
            "comparisonSHA256": logs.capture.sha256(self.comparison / "comparison.json"),
            "cases": [{"case": case, "status": "not-run"} for case in logs.mouse.CASES]}
        self.analysis["cases"][0].update(status="analyzed", caseSHA256=case_hash, receiverSHA256=receiver_hash,
            caseReportPath=str(self.directory / "report.json"),
            ownedPIDs={"observer": 111, "source": 222, "target": 333, "runner": 444},
            wallTimeRange={"start": receiver[0]["time"], "end": receiver[1]["time"], "precision": "seconds"})
        self.write(self.analysis_path, self.analysis)

    @staticmethod
    def write(path, value):
        path.write_text(json.dumps(value, sort_keys=True))

    def entry(self, message="activation request", pid=111, image=None, when="2026-11-06 20:00:15.123456+0000"):
        return {"timestamp": when, "processID": pid, "processImagePath": image or self.paths["observer"],
                "eventMessage": message, "eventType": "logEvent", "messageType": "Default"}

    def collect(self, entries=(), result=None):
        self.outputs += 1
        output = self.root / f"output-{self.outputs}"
        raw = json.dumps(list(entries)).encode()
        result = result if result is not None else {"status": "completed", "returnCode": 0,
            "stdout": raw, "stderr": b"", "bytesObserved": len(raw), "elapsedSeconds": .01}
        def runner(command):
            self.calls.append(command)
            return dict(result)
        receipt = logs.collect(self.stage, self.comparison, self.analysis_path, output, self.commit, runner)
        records = [json.loads(line) for line in (output / "records.ndjson").read_text().splitlines()]
        self.assertEqual(receipt, json.loads((output / "receipt.json").read_text()))
        return receipt, records

    def test_only_owned_and_explicitly_bound_timed_records_are_retained(self):
        shared = "/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer"
        entries = [self.entry(), self.entry("activate pid=222", 77, shared),
            self.entry("frontmost app.lemulip.NativeDragControl", 77, shared),
            self.entry("activate pid=2229", 77, shared), self.entry("activate 222 windows", 77, shared),
            self.entry("activate app.lemulip.NativeDragControl.Unrelated", 77, shared),
            self.entry(pid=999), self.entry(image="/unowned/NativeDragReviewMouseAppKit"),
            self.entry(when="2026-11-06 20:00:22.000000+0000"), self.entry("unrelated storage activity")]
        receipt, records = self.collect(entries)
        self.assertEqual(receipt["status"], "completed-records")
        self.assertEqual([row["sourceRecordIndex"] for row in records], [0, 1, 2])
        self.assertEqual(receipt["rejectedRecordCount"], 7)
        command = self.calls[0]
        self.assertEqual(command[:4], ["/usr/bin/log", "show", "--style", "json"])
        self.assertIn("--info", command)
        self.assertIn("--debug", command)
        self.assertEqual(command[command.index("--start") + 1], "2026-11-06 20:00:09+0000")
        self.assertEqual(command[command.index("--end") + 1], "2026-11-06 20:00:21+0000")
        self.assertEqual(len(self.calls), 1)

    def test_changed_raw_hash_and_forged_pid_prevent_any_log_query(self):
        original = (self.directory / "report.json").read_bytes()
        self.raw["observerProcessID"] = 999
        self.write(self.directory / "report.json", self.raw)
        receipt, _ = self.collect()
        self.assertEqual(receipt["errorCode"], "log-case-hash-binding")
        (self.directory / "report.json").write_bytes(original)
        self.analysis["cases"][0]["ownedPIDs"]["observer"] = 999
        self.write(self.analysis_path, self.analysis)
        receipt, _ = self.collect()
        self.assertEqual(receipt["errorCode"], "log-owned-pid-binding")
        self.assertEqual(self.calls, [])

    def test_unanalyzed_cases_do_not_expand_scope_or_become_empty_success(self):
        self.analysis["cases"][1].update(status="invalid", ownedPIDs={"observer": 999})
        self.write(self.analysis_path, self.analysis)
        receipt, records = self.collect([self.entry(pid=999)])
        self.assertEqual(records, [])
        self.assertNotIn("processID == 999", self.calls[0][-1])
        self.analysis["cases"][0]["status"] = "incomplete"
        self.write(self.analysis_path, self.analysis)
        receipt, _ = self.collect()
        self.assertEqual(receipt["status"], "error")
        self.assertEqual(receipt["errorCode"], "log-no-analyzed-cases")
        self.assertEqual(len(self.calls), 1)

    def test_empty_collection_has_no_origin_or_acceptance_claim(self):
        receipt, records = self.collect()
        self.assertEqual(receipt["status"], "completed-empty")
        self.assertTrue(receipt["collectionCompleted"])
        self.assertEqual(receipt["originAttribution"], "not-assessed")
        self.assertFalse(receipt["nativeInputExecuted"])
        self.assertFalse(receipt["loggingConfigurationChanged"])
        self.assertEqual(records, [])

    def test_redacted_records_remain_explicitly_inconclusive(self):
        receipt, records = self.collect([self.entry("activation requester <private>")])
        self.assertEqual(receipt["status"], "redacted")
        self.assertEqual(receipt["redactedRecordCount"], 1)
        self.assertEqual(records[0]["entry"]["eventMessage"], "activation requester <private>")
        self.assertEqual(receipt["originAttribution"], "not-assessed")

    def test_timeout_terminates_only_query_and_retains_incomplete_receipt(self):
        result = logs.run_log([sys.executable, "-c", "import os,time; os.write(1,b'['); time.sleep(5)"], timeout=.1)
        self.assertEqual(result["status"], "timeout")
        self.assertLess(result["elapsedSeconds"], 2)
        receipt, records = self.collect(result=result)
        self.assertEqual(receipt["status"], "timeout")
        self.assertFalse(receipt["collectionCompleted"])
        self.assertFalse(receipt["stdoutComplete"])
        self.assertIsNone(receipt["fullRawSHA256"])
        self.assertEqual(records, [])

    def test_pipe_byte_cap_cannot_be_reported_as_complete(self):
        result = logs.run_log([sys.executable, "-c", "import os; os.write(1,b'x'*131072)"], byte_limit=1024)
        self.assertEqual(result["status"], "truncated")
        self.assertLessEqual(len(result["stdout"]) + len(result["stderr"]), 1024)
        receipt, records = self.collect(result=result)
        self.assertEqual(receipt["status"], "truncated")
        self.assertFalse(receipt["collectionCompleted"])
        self.assertIsNone(receipt["fullRawSHA256"])
        self.assertEqual(receipt["stdoutSHA256"], hashlib.sha256(result["stdout"]).hexdigest())
        self.assertEqual(records, [])

    def test_malformed_or_failed_query_never_looks_like_empty_collection(self):
        for raw, code in ((b"broken", 0), (b"{}", 0), (b'[{"a":1,"a":2}]', 0),
                          (b"[NaN]", 0), (b"[]", 77)):
            with self.subTest(raw=raw, code=code):
                receipt, records = self.collect(result={"status": "completed", "returnCode": code,
                    "stdout": raw, "stderr": b"", "bytesObserved": len(raw), "elapsedSeconds": .01})
                self.assertEqual(receipt["status"], "error")
                self.assertFalse(receipt["collectionCompleted"])
                self.assertEqual(records, [])


if __name__ == "__main__":
    unittest.main()
