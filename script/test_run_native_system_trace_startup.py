#!/usr/bin/env python3
"""Portable D20 transport/parser tests; no native apps, input, or trace tools."""

import copy
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
import zipfile

import run_native_system_trace_startup as subject


class TraceContractTests(unittest.TestCase):
    def test_single_record_command_and_observed_export_selection(self):
        trace = Path("/exclusive/work/recording.trace")
        name = "app.lemulip.d20.recording.00000000-0000-4000-8000-000000000000"
        self.assertEqual(subject.recording_command(trace, name),
                         ("/usr/bin/xcrun", "xctrace", "record", "--template", "System Trace",
                          "--all-processes", "--time-limit", "30s", "--no-prompt",
                          "--notify-tracing-started", name, "--output", str(trace)))
        self.assertEqual(subject.export_command(trace)[-1:], ("--toc",))
        self.assertEqual(subject.export_command(trace, xpath=subject.PROCESSES_XPATH)[-2:],
                         ("--xpath", subject.PROCESSES_XPATH))
        toc = subject.parse_toc(b'<trace-toc><run number="1"><data><table schema="observed-unknown-v37"/></data></run></trace-toc>')
        self.assertEqual(toc["observedTables"], [{"schema": "observed-unknown-v37"}])
        self.assertEqual(toc["tablesXPath"], subject.TABLES_XPATH)
        empty = subject.parse_toc(b'<trace-toc><run number="1"/></trace-toc>')
        self.assertIsNone(empty["tablesXPath"])

    def test_toc_rejects_ambiguous_unsafe_and_incomplete_xml(self):
        for raw in (b'<trace-toc/>', b'<trace-toc><run number="2"/></trace-toc>',
                    b'<trace-toc><run number="1"/><run number="2"/></trace-toc>',
                    b'<trace-toc><run number="1"><data/><data/></run></trace-toc>',
                    b'<trace-toc><run number="1">',
                    b'<!DOCTYPE trace-toc [<!ENTITY x "bad">]><trace-toc><run number="1"/></trace-toc>',
                    '<trace-toc><run number="1"/></trace-toc>'.encode('utf-16')):
            with self.subTest(raw=raw), self.assertRaises(subject.EvidenceError):
                subject.parse_toc(raw)

    def test_query_results_require_requested_entities_and_actual_schemas(self):
        toc = subject.parse_toc(b'<trace-toc><run number="1"><data><table schema="observed-v37"/></data></run></trace-toc>')
        process = ("<trace-query-result><node xpath='/trace-toc/run[@number=\"1\"]/processes'>"
                   "<process name='test-only-transport-fixture'/></node></trace-query-result>").encode()
        table = ("<trace-query-result><node xpath='/trace-toc/run[@number=\"1\"]/data/table[@schema=\"observed-v37\"]'>"
                 "<schema name='observed-v37'/></node></trace-query-result>").encode()
        self.assertEqual(subject.inspect_query_export(process, kind="processes", toc=toc)["processCount"], 1)
        parsed = subject.inspect_query_export(table, kind="tables", toc=toc)
        self.assertEqual(parsed["schemaNames"], ["observed-v37"])
        self.assertFalse(parsed["activationCoverageInferred"])
        # These transport fixtures contain no activation event or stack claim.
        for kind, raw in (("processes", b'<error/>'), ("tables", b'<foo/>'),
                          ("tables", b'<trace-query-result/>'),
                          ("processes", table), ("tables", process),
                          ("tables", table.replace(b"observed-v37", b"invented")),
                          ("processes", process.replace(b"<process name='test-only-transport-fixture'/>", b""))):
            with self.subTest(kind=kind, raw=raw), self.assertRaises(subject.EvidenceError):
                subject.inspect_query_export(raw, kind=kind, toc=toc)

    def test_late_helper_overflow_and_close_errors_invalidate_cached_success(self):
        command = {"status": "completed", "exitCode": 0, "stopReason": None,
                   "streamErrors": [], "cleanupFailed": False}
        for change in ({"stopReason": "output-limit", "status": "output-limit"},
                       {"streamErrors": [{"stage": "close-pipe", "error": "test"}]},
                       {"cleanupFailed": True}, {"exitCode": 1}):
            with self.subTest(change=change):
                report = {"recordingComplete": True, "startupComplete": True,
                          "activationCalibration": "unproven",
                          "commands": {"helper": {**copy.deepcopy(command), **change}, "record": copy.deepcopy(command)}}
                subject.apply_final_transport_gates(report)
                self.assertFalse(report["recordingComplete"])
                self.assertFalse(report["startupComplete"])
                self.assertEqual(report["activationCalibration"], "unproven")

    def test_failed_startup_must_prove_owned_cleanup(self):
        no_launch = {"kind": "native-system-trace-startup", "helperPID": 123, "nonce": "fixture",
                     "startupNeverRan": True, "startupRan": False, "processes": {}}
        self.assertTrue(subject.helper_cleanup_resolved(no_launch, 123, "fixture"))
        self.assertFalse(subject.helper_cleanup_resolved(None, 123, "fixture"))
        for terminated, outstanding in ((False, False), (True, True)):
            record = {**no_launch, "startupNeverRan": False, "startupRan": True,
                      "processes": {"control": {"launchRequested": True,
                                    "cleanup": {"terminated": terminated, "outstandingLaunchCompletion": outstanding}}}}
            self.assertFalse(subject.helper_cleanup_resolved(record, 123, "fixture"))

    def test_trace_archive_is_bounded_verified_and_exclusive(self):
        with tempfile.TemporaryDirectory(prefix="d20-archive-") as temporary:
            root = Path(temporary).resolve()
            work, output = root / "work", root / "evidence"
            work.mkdir(); output.mkdir()
            trace = work / "recording.trace"
            (trace / "empty").mkdir(parents=True)
            (trace / "bytes").write_bytes(b"actual archived bytes")
            result = subject.package_trace(trace, output, work)
            self.assertEqual(result["status"], "packaged")
            self.assertTrue(result["crcVerified"])
            with zipfile.ZipFile(output / "recording.trace.zip") as archive:
                self.assertIsNone(archive.testzip())
                self.assertEqual(archive.read("recording.trace/bytes"), b"actual archived bytes")
                self.assertIn("recording.trace/empty/", archive.namelist())
            original = (output / "recording.trace.zip").read_bytes()
            second = subject.package_trace(trace, output, work)
            self.assertEqual(second["status"], "rejected")
            self.assertEqual((output / "recording.trace.zip").read_bytes(), original)

    def test_trace_archive_rejects_links_and_resource_overflow(self):
        for kind in ("symlink", "size", "entries", "file-root"):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory(prefix="d20-archive-reject-") as temporary:
                root = Path(temporary).resolve()
                work, output = root / "work", root / "evidence"
                work.mkdir(); output.mkdir()
                trace = work / "recording.trace"
                options = {}
                if kind == "file-root":
                    trace.write_bytes(b"not a trace directory")
                else:
                    trace.mkdir()
                    (trace / "data").write_bytes(b"12345678")
                    if kind == "symlink":
                        (root / "outside").write_bytes(b"must not be archived")
                        (trace / "escape").symlink_to(root / "outside")
                    elif kind == "size": options["limit"] = 7
                    else: options["maximum_entries"] = 1
                result = subject.package_trace(trace, output, work, **options)
                self.assertEqual(result["status"], "rejected")
                self.assertFalse((output / "recording.trace.zip").exists())


class ConcurrentTransportTests(unittest.TestCase):
    def finish_owned_test_child(self, command):
        if command.process is not None and command.poll() is None:
            command.signal(signal.SIGTERM)
            try:
                command.process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                command.signal(signal.SIGKILL)
                command.process.wait(timeout=2)
        command.close()

    def test_concurrent_streams_are_capped_without_losing_either_process(self):
        commands = [subject.MonitoredCommand((sys.executable, "-c", source), cwd=Path.cwd(), env=dict(os.environ), limit=1024)
                    for source in ('import os; os.write(1,b"a"*200000); os.write(2,b"b"*200000)',
                                   'import sys; print("other"); print("err",file=sys.stderr)')]
        try:
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                for command in commands: command.drain(); command.poll()
                if all(command.receipt["exitCode"] is not None and not command.selector.get_map() for command in commands): break
                time.sleep(0.005)
            self.assertTrue(all(command.receipt["exitCode"] == 0 for command in commands))
            self.assertEqual(sum(map(len, commands[0].streams.values())), 1024)
            self.assertEqual(commands[0].receipt["stopReason"], "output-limit")
            self.assertEqual(commands[1].streams, {"stdout": b"other\n", "stderr": b"err\n"})
        finally:
            for command in commands: self.finish_owned_test_child(command)

    def test_pipe_setup_and_repeated_read_failure_keep_child_ownership(self):
        with patch.object(subject.os, "set_blocking", side_effect=OSError("injected setup error")):
            command = subject.MonitoredCommand((sys.executable, "-c", "import time; time.sleep(30)"),
                                               cwd=Path.cwd(), env=dict(os.environ))
        try:
            self.assertIsNotNone(command.process)
            self.assertEqual(command.receipt["stopReason"], "stream-error")
            with patch.object(command.selector, "select", side_effect=OSError("injected repeated selector error")):
                command.drain()
                command.drain()
                command.signal(signal.SIGTERM)
                command.process.wait(timeout=2)
                command.close()
            self.assertIsNotNone(command.process.returncode)
            self.assertGreaterEqual(len(command.receipt["streamErrors"]), 2)
        finally:
            self.finish_owned_test_child(command)

    def test_helper_failure_or_early_recorder_exit_never_exports(self):
        # Two tiny Python processes exercise scheduling/cleanup only. No AppKit,
        # source/control application, Darwin notification, or xctrace is invoked.
        for early in (False, True):
            with self.subTest(early=early), tempfile.TemporaryDirectory(prefix="d20-orchestration-") as temporary:
                root = Path(temporary).resolve()
                staged, output = root / "staged", root / "evidence"
                staged.mkdir(); (output / "build").mkdir(parents=True); (output / "sources").mkdir()
                (output / "build/experiment-commit.txt").write_text("a" * 40 + "\n")
                (output / "build/experiment-tree.txt").write_text("b" * 40 + "\n")
                helper = output / "build/test-helper"
                source = '''import hashlib,json,os,pathlib,platform,sys,time
args=dict(zip(sys.argv[1::2],sys.argv[2::2])); out=pathlib.Path(args['--output'])
notification=args['--recording-notification']; nonce=notification.rsplit('.',1)[1]
prepared={'schema':1,'kind':'native-system-trace-startup-prepared','helperPID':os.getpid(),
'helperExecutablePath':sys.argv[0],'helperExecutableSHA256':hashlib.sha256(pathlib.Path(sys.argv[0]).read_bytes()).hexdigest(),
'stagedPath':args['--staged'],'outputPath':str(out),'recordingNotificationName':notification,'nonce':nonce,
'architecture':platform.machine(),'bootUUID':'00000000-0000-4000-8000-000000000001',
'machTimebaseNumer':1,'machTimebaseDenom':1,'preparationComplete':True,'startupRan':False,
'inputGenerated':False,'cooperativeAbortSupported':True,'recordingNotification':{'registered':True,'registrationStatus':0}}
raw=(json.dumps(prepared)+'\\n').encode(); pending=out/'helper-prepared.json.pending'; pending.write_bytes(raw)
os.link(pending,out/'helper-prepared.json'); pending.unlink()
deadline=time.monotonic()+3
while not (out.parent/'work/recording.trace').exists() and time.monotonic()<deadline: time.sleep(.01)
time.sleep(.15)
report=dict(prepared,kind='native-system-trace-startup',status='error',processStartupComplete=False,
startupNeverRan=True,processes={},preparedReceipt={'sha256':hashlib.sha256(raw).hexdigest(),'byteCount':len(raw)})
(out/'startup-run.json').write_text(json.dumps(report)+'\\n')
sys.exit(1)
'''
                helper.write_text("#!" + sys.executable + "\n" + source)
                helper.chmod(0o700)
                recorder_source = ("import pathlib,signal,sys,time; "
                                   "signal.signal(signal.SIGINT,lambda *_:sys.exit(0)); "
                                   "pathlib.Path(sys.argv[1]).mkdir(); " + ("sys.exit(0)" if early else "time.sleep(30)"))
                def command(trace, notification):
                    return (sys.executable, "-c", recorder_source, str(trace))
                with patch.object(subject, "recording_command", side_effect=command) as build, \
                     patch.object(subject, "group_snapshot", return_value={"status":"no-live-group-members-observed","members":[]}), \
                     patch.object(subject, "capture", side_effect=AssertionError("An export must not run")):
                    report = subject.run(staged, output, helper)
                self.assertEqual(build.call_count, 1)
                self.assertEqual(report["status"], "evidence-incomplete")
                self.assertFalse(report["startupComplete"])
                self.assertFalse(report["recordingComplete"])
                self.assertFalse(report["exportsComplete"])
                self.assertEqual(report["activationCalibration"], "unproven")
                self.assertEqual(report["recorderExitedBeforeHelperCompletion"], early)
                self.assertTrue(report["cleanupComplete"])


if __name__ == "__main__":
    unittest.main()
