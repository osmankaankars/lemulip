#!/usr/bin/env python3
"""D21 portable ownership/transport tests; no Apple sample, native input or apps."""

import copy
import errno
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import run_native_recorder_startup_observation as subject
import run_native_system_trace_startup as startup


# Synthetic manual/parser transport fixtures, not claimed installed manuals.
SAMPLE_MANUAL = b"""SYNOPSIS
sample process duration interval
DESCRIPTION
The process argument is a process ID. duration specifies seconds. interval specifies milliseconds.
-mayDie Collect symbolic information before sampling.
-file filename Specifies output written to the named file.
"""
PS_MANUAL = b"""DESCRIPTION
-p pid Select processes with matching process IDs.
-A Display all processes.
-w Display wide output; more than once removes the width restriction.
-o format A space or comma list of keywords with optional = header text. All headers empty suppress display of the header.
KEYWORDS
pid process ID ppid parent process ID pgid process group number uid effective user ID
lstart time started state symbolic process state (alias stat) comm command args command and arguments
"""


def complete(command, timeout=3):
    deadline = time.monotonic() + timeout
    while not command.done and time.monotonic() < deadline:
        command.tick()
        time.sleep(.005)
    if not command.done:
        raise AssertionError("bounded observer child did not finish")


class ObserverContracts(unittest.TestCase):
    def test_manual_gate_requires_semantics_and_preserves_normalized_overstrikes(self):
        self.assertTrue(subject.validate_manuals(SAMPLE_MANUAL, PS_MANUAL)["passed"])
        self.assertEqual(subject.manual_text(b"s\bsa\bam\bme\bep\bpl\ble\be"), "sameple")
        for sample in (SAMPLE_MANUAL.replace(b"seconds", b"units"),
                       SAMPLE_MANUAL.replace(b"milliseconds", b"units"),
                       SAMPLE_MANUAL.replace(b"-file filename Specifies output written to the named file.", b"-file"),
                       SAMPLE_MANUAL.replace(b"before sampling", b"after sampling"),
                       SAMPLE_MANUAL.replace(b"sample process duration interval", b"sample process interval duration"),
                       SAMPLE_MANUAL.replace(b"duration specifies seconds", b"duration specifies milliseconds"),
                       SAMPLE_MANUAL.replace(b"interval specifies milliseconds", b"interval specifies seconds")):
            with self.subTest(sample=sample):
                self.assertFalse(subject.validate_manuals(sample, PS_MANUAL)["passed"])
        self.assertFalse(subject.validate_manuals(SAMPLE_MANUAL, PS_MANUAL.replace(b"effective user ID", b"user"))["passed"])
        self.assertFalse(subject.validate_manuals(SAMPLE_MANUAL, PS_MANUAL.replace(b"-A Display all processes.", b""))["passed"])
        self.assertFalse(subject.validate_manuals(SAMPLE_MANUAL, PS_MANUAL.replace(b"All headers empty suppress display of the header.", b""))["passed"])

    def test_metadata_binds_instance_and_rejects_zombie_or_ambiguous_rows(self):
        raw = b" 123 10 123 501 Mon Nov  9 12:10:02 2026 S /path with spaces/tool process args\n"
        parsed = subject.parse_identity(raw, pid=123, ppid=10, pgid=123, uid=501)
        self.assertEqual(parsed["startTime"], "Mon Nov 9 12:10:02 2026")
        self.assertEqual(parsed["advisoryCommandAndArguments"], "/path with spaces/tool process args")
        self.assertFalse(parsed["commandTextProvesImage"])
        for bad in (raw + raw, raw.replace(b"2026 S", b"2026 Z"), raw.replace(b"123 10", b"124 10"), raw.replace(b"501", b"502")):
            with self.subTest(bad=bad), self.assertRaises(startup.EvidenceError):
                subject.parse_identity(bad, pid=123, ppid=10, pgid=123, uid=501)

    def test_sample_identity_requires_owned_pid_path_and_binary_images(self):
        raw = b"Process: transport-fixture [123]\nPath: /fixture/image\nBinary Images:\n0x1 - 0x2 fixture /fixture/image\n"
        parsed = subject.inspect_sample(raw, pid=123)
        self.assertEqual(parsed["observedPath"], "/fixture/image")
        self.assertFalse(parsed["sampledImageProvesUnperturbedD20Image"])
        for bad in (raw.replace(b"[123]", b"[124]"), raw.replace(b"/fixture/image", b"relative"), raw.split(b"Binary Images:")[0]):
            with self.subTest(bad=bad), self.assertRaises(startup.EvidenceError):
                subject.inspect_sample(bad, pid=123)

    def test_exact_owned_pid_stays_reserved_until_lease_release(self):
        with tempfile.TemporaryDirectory(prefix="d21-lease-") as temporary:
            command = startup.MonitoredCommand((sys.executable, "-c", "pass"),
                                               cwd=Path(temporary), env=os.environ.copy())
            command.reap_deferred = True
            try:
                deadline = time.monotonic() + 3
                while command.selector.get_map() and time.monotonic() < deadline:
                    command.drain()
                    self.assertIsNone(command.poll())
                    time.sleep(.005)
                self.assertFalse(command.selector.get_map())
                self.assertIsNone(command.process.returncode)
                os.kill(command.process.pid, 0)  # The unreaped child still reserves this PID.
                command.reap_deferred = False
                deadline = time.monotonic() + 2
                while command.poll() is None and time.monotonic() < deadline:
                    time.sleep(.005)
                self.assertEqual(command.process.returncode, 0)
            finally:
                command.reap_deferred = False
                if command.poll() is None:
                    command.signal(signal.SIGKILL)
                    command.process.wait(timeout=2)
                command.close()

    def test_nonblocking_deadline_escalates_owned_descendant_before_reaping(self):
        with tempfile.TemporaryDirectory(prefix="d21-deadline-") as temporary:
            root = Path(temporary)
            code = """import os,signal,time,pathlib
child=os.fork()
if child==0:
 signal.signal(signal.SIGTERM,signal.SIG_IGN)
 os.close(1);os.close(2)
 while True:
  with pathlib.Path('heartbeat').open('ab') as output: output.write(b'.')
  time.sleep(.01)
else:
 pathlib.Path('descendant.txt').write_text(str(child))
 time.sleep(30)
"""
            command = subject.ObservationCommand((sys.executable, "-c", code), cwd=root,
                                                 env=os.environ.copy(), budget=1.0, limit=65536)
            elapsed = []
            while not command.done:
                before = time.monotonic(); command.tick(); elapsed.append(time.monotonic() - before)
                time.sleep(.005)
            self.assertLess(max(elapsed), .1)
            self.assertIn("SIGKILL", [item["signal"] for item in command.transport.receipt["signals"]])
            self.assertEqual(command.transport.receipt["stopReason"], "command-budget")
            heartbeat = (root / "heartbeat").read_bytes()
            self.assertTrue(heartbeat)
            time.sleep(.06)
            self.assertEqual((root / "heartbeat").read_bytes(), heartbeat)

    def test_output_limit_cancels_once_without_retaining_unbounded_bytes(self):
        with tempfile.TemporaryDirectory(prefix="d21-output-") as temporary:
            command = subject.ObservationCommand((sys.executable, "-c", "import os,time;os.write(1,b'x'*65536);time.sleep(30)"),
                                                 cwd=Path(temporary), env=os.environ.copy(), budget=1, limit=100)
            complete(command)
            self.assertEqual(command.transport.receipt["stopReason"], "output-limit")
            self.assertEqual(command.transport.receipt["retainedBytes"], 100)
            self.assertEqual(sum(s["signal"] == "SIGTERM" for s in command.transport.receipt["signals"]), 1)

    def test_leader_exit_with_inherited_pipe_does_not_escape_group_cleanup(self):
        with tempfile.TemporaryDirectory(prefix="d21-inherited-pipe-") as temporary:
            code = "import os,signal,time;child=os.fork();(os._exit(0) if child else None);signal.signal(signal.SIGTERM,signal.SIG_IGN);time.sleep(30)"
            command = subject.ObservationCommand((sys.executable, "-c", code), cwd=Path(temporary),
                                                 env=os.environ.copy(), budget=1, limit=65536)
            complete(command)
            self.assertIn("SIGKILL", [row["signal"] for row in command.transport.receipt["signals"]])
            self.assertEqual(command.transport.receipt["stopReason"], "command-budget")
            self.assertFalse(command.transport.receipt["inheritedStreamsStillOpen"])
            self.assertEqual(command.transport.process.returncode, 0)

    def test_report_reader_rejects_symlink_and_oversize(self):
        with tempfile.TemporaryDirectory(prefix="d21-report-") as temporary:
            root = Path(temporary); report = root / "report"
            report.write_bytes(b"123456")
            with self.assertRaises(startup.EvidenceError): startup.read_regular(report, 5)
            alias = root / "alias"; alias.symlink_to(report)
            with self.assertRaises(OSError): startup.read_regular(alias, 10)

    def test_persistent_report_error_cannot_prevent_sampler_kill_and_close(self):
        with tempfile.TemporaryDirectory(prefix="d21-report-error-") as temporary:
            root = Path(temporary)
            recorder = startup.MonitoredCommand((sys.executable, "-c", "import time;time.sleep(30)"),
                                                cwd=root, env=os.environ.copy())
            observer = subject.RecorderObservation(root)
            observer.attach(recorder, helper_started=time.monotonic(),
                            prepared={"bootUUID": "fixture", "nonce": "fixture", "recordingNotificationName": "fixture"},
                            cwd=root, env=os.environ.copy())
            recorder.reap_deferred = True
            observer.report["pidLeaseAcquired"] = True
            observer.state = "sample"
            ready = root / "sampler-ready"
            code = ("import pathlib,signal,sys,time;signal.signal(signal.SIGTERM,signal.SIG_IGN);"
                    "pathlib.Path(sys.argv[1]).touch();time.sleep(30)")
            observer.launch("observer-sample", (sys.executable, "-c", code, str(ready)), 4)
            sample = observer.commands["observer-sample"]
            launch, lstat = observer.launch, Path.lstat
            def launch_fixture(name, argv, budget, limit=subject.PS_STREAM_LIMIT):
                # Explicit synthetic cleanup metadata; the sampler/recorder
                # and their TERM/KILL lifecycle remain real child processes.
                if name == "observer-groups":
                    argv = (sys.executable, "-c", "print('1 1 S')")
                launch(name, argv, budget, limit)
            def fail_report(path, *args, **kwargs):
                if path == observer.report_path:
                    raise PermissionError(errno.EACCES, "persistent test report access failure")
                return lstat(path, *args, **kwargs)
            try:
                deadline = time.monotonic() + 3
                while not ready.exists() and time.monotonic() < deadline:
                    time.sleep(.005)
                self.assertTrue(ready.exists())
                with patch.object(observer, "launch", side_effect=launch_fixture), \
                     patch.object(Path, "lstat", new=fail_report):
                    deadline = time.monotonic() + 3
                    while not observer.done and time.monotonic() < deadline:
                        observer.tick(helper_running=True, recorder_stopping=False)
                        time.sleep(.005)
                self.assertTrue(observer.done)
                self.assertEqual(sample.transport.process.returncode, -signal.SIGKILL)
                self.assertEqual([row["signal"] for row in sample.transport.receipt["signals"]],
                                 ["SIGTERM", "SIGKILL"])
                self.assertTrue(sample.transport.closed)
                self.assertTrue(observer.report["pidLeaseReleased"])
                self.assertEqual(observer.report["status"], "observation-incomplete")
                self.assertTrue(any("persistent test report access failure" in row for row in observer.report["errors"]))
                observer.finish()
            finally:
                for command in observer.commands.values():
                    if command.transport.process is not None and command.transport.process.poll() is None:
                        command.transport.signal(signal.SIGKILL)
                        command.transport.process.wait(timeout=2)
                    command.transport.close()
                recorder.reap_deferred = False
                if recorder.poll() is None:
                    recorder.signal(signal.SIGKILL)
                    recorder.process.wait(timeout=2)
                recorder.close()

    def test_dead_group_eperm_requires_positive_snapshot_and_no_other_cleanup_fault(self):
        with tempfile.TemporaryDirectory(prefix="d21-eperm-") as temporary:
            root = Path(temporary)
            ready = root / "ready"
            command = subject.ObservationCommand(
                (sys.executable, "-c", "import pathlib,sys,time;pathlib.Path(sys.argv[1]).touch();time.sleep(30)", str(ready)),
                cwd=root, env=os.environ.copy(), budget=4, limit=65536)
            snapshot = None
            killpg = os.killpg
            def zombie_only_eperm(pgid, sig):
                if pgid == command.transport.process.pid and sig == signal.SIGKILL:
                    raise PermissionError(errno.EPERM, "simulated Darwin zombie-only group")
                return killpg(pgid, sig)
            try:
                deadline = time.monotonic() + 3
                while not ready.exists() and time.monotonic() < deadline:
                    time.sleep(.005)
                self.assertTrue(ready.exists())
                with patch.object(startup.os, "killpg", side_effect=zombie_only_eperm):
                    command.stop("helper-finished-or-recorder-stopping")
                    complete(command)
                self.assertEqual(command.transport.process.returncode, -signal.SIGTERM)
                original = copy.deepcopy(command.transport.receipt)
                self.assertTrue(original["cleanupFailed"])
                self.assertEqual(original["signalErrors"][0]["errno"], errno.EPERM)
                # Synthetic positive/negative snapshots test classification;
                # they do not stand in for the native workflow's real ps gate.
                snapshot = subject.ObservationCommand((sys.executable, "-c", "print('1 1 S')"),
                                                       cwd=root, env=os.environ.copy(), budget=2, limit=65536)
                complete(snapshot)
                for scenario in ("resolved", "live-member", "unrelated-fault"):
                    with self.subTest(scenario=scenario):
                        command.transport.receipt = copy.deepcopy(original)
                        snapshot.transport.streams["stdout"] = bytearray(b"1 1 S\n")
                        if scenario == "live-member":
                            pid = command.transport.process.pid
                            snapshot.transport.streams["stdout"].extend(f"{pid + 1000000} {pid} S\n".encode())
                        if scenario == "unrelated-fault":
                            command.transport.receipt["cleanupFailureReasons"] = ["inherited-streams-still-open"]
                        observer = subject.RecorderObservation(root)
                        observer.recorder = SimpleNamespace(reap_deferred=True, receipt={"cleanupFailed": False})
                        observer.commands = {"observer-sample": command, "observer-groups": snapshot}
                        observer.cancel_reason = "helper-finished-or-recorder-stopping"
                        observer.resolve_groups(snapshot)
                        resolved = scenario == "resolved"
                        self.assertEqual(observer.report["cleanupComplete"], resolved)
                        self.assertEqual(observer.report["pidLeaseReleased"], resolved)
                        self.assertEqual(observer.recorder.reap_deferred, not resolved)
                        self.assertEqual(command.transport.receipt["signalErrors"], original["signalErrors"])
                        self.assertEqual(command.transport.receipt["stopReason"], original["stopReason"])
                        self.assertEqual(observer.report["status"], "observation-incomplete")
                        if resolved:
                            self.assertEqual(command.transport.receipt["status"], original["stopReason"])
                            self.assertTrue(command.transport.receipt["cleanupResolvedByGroupSnapshot"])
            finally:
                for owned in (command, snapshot):
                    if owned is None:
                        continue
                    if owned.transport.process is not None and owned.transport.process.poll() is None:
                        owned.transport.signal(signal.SIGKILL)
                        owned.transport.process.wait(timeout=2)
                    owned.transport.close()

    def test_insufficient_original_window_never_acquires_lease_or_samples(self):
        with tempfile.TemporaryDirectory(prefix="d21-window-") as temporary:
            root = Path(temporary)
            recorder = startup.MonitoredCommand((sys.executable, "-c", "import time;time.sleep(30)"), cwd=root, env=os.environ.copy())
            observation = subject.RecorderObservation(root)
            observation.attach(recorder, helper_started=time.monotonic() - 13, prepared={"bootUUID":"fixture", "nonce":"fixture", "recordingNotificationName":"fixture"}, cwd=root, env=os.environ.copy())
            observation.trigger = time.monotonic() - 1
            observation.tick(helper_running=True, recorder_stopping=False)
            self.assertTrue(observation.done)
            self.assertFalse(recorder.reap_deferred)
            self.assertEqual(observation.report["sampleInvocationCount"], 0)
            self.assertEqual(observation.report["status"], "skipped-insufficient-original-window")
            recorder.signal(signal.SIGTERM); recorder.process.wait(timeout=2); recorder.close()


class ObserverIntegration(unittest.TestCase):
    def portable_command(self, observer, name, argv):
        # The executor's /bin/ps cannot see child rows. Explicit synthetic
        # metadata exercises the parser/lease plumbing around real subprocesses;
        # these fixtures establish no macOS observation or native success.
        if name.startswith("observer-identity-"):
            row = f"{observer.recorder.process.pid} {os.getpid()} {observer.recorder.process.pid} {os.geteuid()} Mon Nov  9 12:10:02 2026 S fixture fixture"
            return (sys.executable, "-c", "import sys;print(sys.argv[1])", row)
        if name == "observer-groups":
            return (sys.executable, "-c", "print('1 1 S')")
        return argv

    def fixture(self, root, helper_seconds, wait_marker=None):
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
WAIT_FOR_TEST_BOUNDARY
report=dict(prepared,kind='native-system-trace-startup',status='error',processStartupComplete=False,
startupNeverRan=True,processes={},preparedReceipt={'sha256':hashlib.sha256(raw).hexdigest(),'byteCount':len(raw)})
(out/'startup-run.json').write_text(json.dumps(report)+'\\n')
sys.exit(1)
'''
        wait_code = "time.sleep(" + repr(helper_seconds) + ")"
        if wait_marker is not None:
            wait_code = ("deadline=time.monotonic()+5\n"
                         "while not (out/" + repr(wait_marker) + ").exists() and time.monotonic()<deadline: time.sleep(.01)\n"
                         "if not (out/" + repr(wait_marker) + ").exists(): sys.exit(2)")
        source = source.replace("WAIT_FOR_TEST_BOUNDARY", wait_code)
        helper.write_text("#!" + sys.executable + "\n" + source); helper.chmod(0o700)
        recorder_code = ("import pathlib,signal,sys,time; "
                         "signal.signal(signal.SIGINT,lambda *_:sys.exit(0)); "
                         "pathlib.Path(sys.argv[1]).mkdir(); time.sleep(30)")
        return staged, output, helper, lambda trace, notification: (sys.executable, "-c", recorder_code, str(trace))

    def test_one_observation_can_finish_without_promoting_failed_startup(self):
        with tempfile.TemporaryDirectory(prefix="d21-integration-") as temporary:
            staged, output, helper, recording = self.fixture(Path(temporary), 0, "observation-done")
            observer = subject.RecorderObservation(output)
            launch = observer.launch
            def launch_fixture(name, argv, budget, limit=subject.PS_STREAM_LIMIT):
                if name == "observer-sample":
                    code = "import pathlib,sys;pathlib.Path(sys.argv[2]).write_text('Process: transport-fixture ['+sys.argv[1]+']\\nPath: /fixture/image\\nBinary Images:\\n0x1 - 0x2 fixture /fixture/image\\n')"
                    argv = (sys.executable, "-c", code, argv[1], argv[-1])
                argv = self.portable_command(observer, name, argv)
                launch(name, argv, budget, limit)
            tick = observer.tick
            def tick_fixture(**kwargs):
                tick(**kwargs)
                if observer.done: (output / "observation-done").touch()
            with patch.object(subject, "OBSERVE_AFTER_SECONDS", .05), \
                 patch.object(observer, "launch", side_effect=launch_fixture), \
                 patch.object(observer, "tick", side_effect=tick_fixture), \
                 patch.object(startup, "recording_command", side_effect=recording), \
                 patch.object(startup, "capture", side_effect=AssertionError("No export allowed")), \
                 patch.object(startup, "group_snapshot", return_value={"status":"no-live-group-members-observed","members":[]}):
                report = startup.run(staged, output, helper, observer=observer)
            self.assertEqual(observer.report["sampleInvocationCount"], 1)
            self.assertTrue(observer.report["pidLeaseReleased"])
            self.assertEqual(observer.report["status"], "observed-image-and-process-instance")
            self.assertFalse(report["recordingComplete"])
            self.assertFalse(report["startupComplete"])
            self.assertEqual(report["activationCalibration"], "unproven")

    def test_helper_finish_interrupts_recorder_without_waiting_for_sampler(self):
        with tempfile.TemporaryDirectory(prefix="d21-cancel-") as temporary:
            staged, output, helper, recording = self.fixture(Path(temporary), 0, "sampler-ready")
            observer = subject.RecorderObservation(output)
            launch = observer.launch
            def launch_fixture(name, argv, budget, limit=subject.PS_STREAM_LIMIT):
                if name == "observer-sample":
                    argv = (sys.executable, "-c", "import pathlib,sys,time;pathlib.Path(sys.argv[1]).touch();time.sleep(30)", str(output / "sampler-ready"))
                argv = self.portable_command(observer, name, argv)
                launch(name, argv, budget, limit)
            with patch.object(subject, "OBSERVE_AFTER_SECONDS", .05), \
                 patch.object(observer, "launch", side_effect=launch_fixture), \
                 patch.object(startup, "recording_command", side_effect=recording), \
                 patch.object(startup, "capture", side_effect=AssertionError("No export allowed")), \
                 patch.object(startup, "group_snapshot", return_value={"status":"no-live-group-members-observed","members":[]}):
                report = startup.run(staged, output, helper, observer=observer)
            self.assertEqual(observer.report["sampleInvocationCount"], 1)
            sample = observer.report["commands"]["observer-sample"]
            self.assertEqual(sample["stopReason"], "helper-finished-or-recorder-stopping")
            self.assertTrue(observer.report["pidLeaseReleased"])
            self.assertFalse(observer.report["observedImageBound"])
            interrupt = report["commands"]["record"]["signals"][0]
            self.assertEqual(interrupt["signal"], "SIGINT")
            helper_exit = observer.report["helperMonotonicStart"] + report["commands"]["helper"]["exitObservedAfterSeconds"]
            recorder_interrupt = observer.report["recorderMonotonicStart"] + interrupt["afterSeconds"]
            self.assertGreaterEqual(recorder_interrupt, helper_exit)
            self.assertLess(recorder_interrupt - helper_exit, .25)
            self.assertFalse(report["recordingComplete"])

    def test_observer_exceptions_cannot_bypass_owned_cleanup_and_transport_close(self):
        class BrokenObserver:
            done = False
            def attach(self, recorder, **kwargs): self.recorder = recorder
            def tick(self, **kwargs):
                if hasattr(self, "recorder"): raise RuntimeError("injected tick failure")
            def cancel(self, reason): raise RuntimeError("injected cancel failure")
            def finish(self): raise RuntimeError("injected finish failure")
        with tempfile.TemporaryDirectory(prefix="d21-errors-") as temporary:
            staged, output, helper, recording = self.fixture(Path(temporary), .4)
            observer = BrokenObserver()
            with patch.object(startup, "recording_command", side_effect=recording), \
                 patch.object(startup, "capture", side_effect=AssertionError("No export allowed")):
                report = startup.run(staged, output, helper, observer=observer)
            self.assertTrue(observer.recorder.closed)
            self.assertIsNotNone(observer.recorder.process.returncode)
            self.assertFalse(report["cleanupComplete"])
            self.assertTrue((output / "record.json").is_file())
            self.assertTrue(any("injected cancel failure" in error for error in report["errors"]))
            self.assertTrue(any("injected finish failure" in error for error in report["errors"]))


if __name__ == "__main__":
    unittest.main()
