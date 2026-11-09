#!/usr/bin/env python3
"""Portable D22 contract/lifecycle tests; no Apple sample or native app execution.

Native receipts, ps rows and sample reports below are explicit synthetic parser
fixtures. The subprocesses, pipe ownership, EOF, signals and cleanup are real.
These tests do not establish native sampling or an Apple executable identity.
"""

import copy
import hashlib
import json
import os
from pathlib import Path
import platform
import signal
import sys
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import run_native_sampler_calibration as subject


UUID = "11111111-2222-3333-4444-555555555555"
BOOT = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
NONCE = "12345678-1234-1234-1234-123456789ABC"


def native_clock(tick):
    return {"machAbsoluteBefore": tick, "machAbsoluteAfter": tick + 1,
            "machContinuousBefore": tick, "machContinuousAfter": tick + 1,
            "systemUptime": tick / 1e9, "wallTimeUnixNS": tick + 1000000000000000000}


def sample_report(helper, pid, architecture="arm64", code_type=None):
    code_type = code_type or ("ARM64" if architecture == "arm64" else "X86-64")
    return (f"Process: NativeSamplerCalibration [{pid}]\nPath: {helper}\nCode Type: {code_type}\n"
            "Call graph:\n"
            "    10 Thread_1\n"
            f"    + 10 {subject.EXPECTED_FRAME} (in {helper.name}) + 32 [0x100001020]\n"
            "    +   10 poll (in libsystem_kernel.dylib) + 8\n"
            "Total number in stack (recursive counted multiple, when >=5):\n"
            "    10 poll (in libsystem_kernel.dylib) + 8\n"
            f"Binary Images:\n0x100000000 - 0x100003fff {helper.name} <{UUID}> {helper}\n").encode()


def wait_for_file(path, timeout=3):
    deadline = time.monotonic() + timeout
    while not path.exists() and time.monotonic() < deadline:
        time.sleep(.005)
    if not path.is_file():
        raise AssertionError("Fixture child did not publish its bounded ready marker")


def dispose(target):
    """Test teardown only, after assertions about production lease state."""
    if target.process is not None:
        target.reap_deferred = False
        if target.process.poll() is None:
            target.signal(signal.SIGKILL)
            target.process.wait(timeout=2)
        if target.process.stdin is not None:
            try:
                target.process.stdin.close()
            except OSError:
                target.process.stdin.close()
    target.close()


class SampleContracts(unittest.TestCase):
    def test_native_architecture_and_counted_target_frame_are_required(self):
        helper = Path("/fixture/NativeSamplerCalibration")
        for architecture, spelling in (("arm64", "ARM64"), ("arm64", "ARM64 (Native)"),
                                       ("arm64", "ARM-64 (Native)"), ("x86_64", "X86-64 (Native)")):
            with self.subTest(architecture=architecture, spelling=spelling):
                result = subject.qualify_sample(sample_report(helper, 123, architecture, spelling), pid=123,
                                                helper=helper, expected_uuid=UUID, architecture=architecture)
                self.assertTrue(result["qualified"])
                self.assertEqual(result["countedFrameWitnesses"][0]["sampleCount"], 10)
                self.assertFalse(result["recorderImageOrStackQualified"])
                self.assertFalse(result["activationRouteCoverageEstablished"])

    def test_identity_and_call_tree_false_positives_are_rejected(self):
        helper = Path("/fixture/NativeSamplerCalibration")
        raw = sample_report(helper, 123)
        frame = f"    + 10 {subject.EXPECTED_FRAME} (in {helper.name}) + 32 [0x100001020]\n".encode()
        header, graph_and_images = raw.split(b"Call graph:\n", 1)
        graph, images = graph_and_images.split(b"Binary Images:\n", 1)
        invalid = {
            "foreign-pid": raw.replace(b"[123]", b"[124]"),
            "foreign-uuid": raw.replace(UUID.encode(), b"99999999-2222-3333-4444-555555555555"),
            "foreign-path": raw.replace(str(helper).encode(), b"/elsewhere/NativeSamplerCalibration"),
            "translated": raw.replace(b"Code Type: ARM64", b"Code Type: X86-64 (Translated)"),
            "zero-count": raw.replace(frame, frame.replace(b"+ 10", b"+ 0")),
            "symbol-prefix": raw.replace(subject.EXPECTED_FRAME.encode(), (subject.EXPECTED_FRAME + "_other").encode()),
            "foreign-frame-image": raw.replace(frame, frame.replace(b"(in NativeSamplerCalibration)", b"(in Other)")),
            "summary-only": raw.replace(frame, b"").replace(b"    10 poll", frame + b"    10 poll"),
            "indented-summary-only": raw.replace(frame, b"").replace(b"Total number in stack", b"    Total number in stack").replace(b"    10 poll", frame + b"    10 poll"),
            "graph-after-images": header + b"Binary Images:\n" + images + b"Call graph:\n" + graph,
            "duplicate-pid-header": raw + b"Process: NativeSamplerCalibration [123]\n",
            "duplicate-image-header": raw + b"Binary Images:\n",
            "duplicate-call-graph": raw + b"Call graph:\n",
        }
        for name, body in invalid.items():
            with self.subTest(name=name), self.assertRaises((ValueError, TypeError)):
                subject.qualify_sample(body, pid=123, helper=helper, expected_uuid=UUID, architecture="arm64")

    def receipt_fixture(self, complete=False):
        helper = Path("/fixture/NativeSamplerCalibration")
        provenance = {"helper": {"sha256": "a" * 64, "uuid": UUID}, "architecture": "arm64",
                      "sourceSHA256": "b" * 64, "experimentCommit": "c" * 40, "experimentTree": "d" * 40}
        target = SimpleNamespace(process=SimpleNamespace(pid=1234))
        value = {"schema": 1, "kind": "d22-sampler-calibration-complete" if complete else "d22-sampler-calibration-ready",
                 "pid": 1234, "ppid": os.getpid(), "pgid": 1234, "euid": os.geteuid(), "nonce": NONCE,
                 "executablePath": str(helper), "executableSHA256": "a" * 64, "machOUUID": UUID,
                 "architecture": "arm64", "sourceSHA256": "b" * 64, "experimentCommit": "c" * 40,
                 "experimentTree": "d" * 40, "expectedFrame": subject.EXPECTED_FRAME, "safetyTimeoutSeconds": 15,
                 "identityValidated": True, "nativeInputExecuted": False, "settingsChanged": False,
                 "applicationLaunchRequested": False, "recordingRequested": False, "bootUUID": BOOT,
                 "machTimebaseNumer": 1, "machTimebaseDenom": 1,
                 "translationProbe": {"returnCode": 0, "errno": 0, "value": 0},
                 "nativeStartClock": native_clock(1000000000), "readinessClock": native_clock(2000000000),
                 "expectedFrameEntered": True, "receivedInputBytes": 0}
        if complete:
            value.update(releaseClock=native_clock(3000000000), completionClock=native_clock(4000000000),
                         elapsedSeconds=3.000000001)
        return value, {"kind": value["kind"], "target": target, "helper": helper, "provenance": provenance, "nonce": NONCE}

    def test_native_receipt_identity_and_clock_failures_do_not_qualify(self):
        value, kwargs = self.receipt_fixture()
        subject.validate_native_receipt(value, **kwargs)
        changes = ({"pid": 1235}, {"ppid": os.getpid() + 1}, {"pgid": 1235}, {"euid": os.geteuid() + 1},
                   {"nonce": UUID}, {"machOUUID": BOOT}, {"sourceSHA256": "f" * 64},
                   {"expectedFrameEntered": False}, {"receivedInputBytes": 1}, {"receivedInputBytes": False},
                   {"safetyTimeoutSeconds": 16}, {"machTimebaseDenom": 0},
                   {"translationProbe": {"returnCode": 0, "errno": 0, "value": 1}})
        for change in changes:
            with self.subTest(change=change), self.assertRaises(ValueError):
                subject.validate_native_receipt({**value, **change}, **kwargs)
        complete, kwargs = self.receipt_fixture(complete=True)
        subject.validate_native_receipt(complete, **kwargs)
        for name in ("reversed-bracket", "reversed-lifecycle", "nan-uptime", "elapsed-mismatch", "expired"):
            candidate = copy.deepcopy(complete)
            if name == "reversed-bracket": candidate["readinessClock"]["machAbsoluteAfter"] = 1
            elif name == "reversed-lifecycle": candidate["releaseClock"] = native_clock(100)
            elif name == "nan-uptime": candidate["completionClock"]["systemUptime"] = float("nan")
            elif name == "elapsed-mismatch": candidate["elapsedSeconds"] = .5
            else: candidate["elapsedSeconds"] = 15
            with self.subTest(name=name), self.assertRaises(ValueError):
                subject.validate_native_receipt(candidate, **kwargs)


class TargetLifecycle(unittest.TestCase):
    def test_exited_target_pid_is_reserved_until_observer_release(self):
        with tempfile.TemporaryDirectory(prefix="d22-pin-") as temporary:
            target = subject.OwnedTarget((sys.executable, "-c", "pass"), cwd=Path(temporary), env=os.environ.copy())
            try:
                deadline = time.monotonic() + 3
                while target.selector.get_map() and time.monotonic() < deadline:
                    target.drain()
                    self.assertIsNone(target.poll())
                    time.sleep(.005)
                self.assertFalse(target.selector.get_map())
                self.assertIsNone(target.process.returncode)
                self.assertTrue(target.reap_deferred)
                os.kill(target.process.pid, 0)
                subject.cleanup_target(target, observer_groups_resolved=True)
                self.assertEqual(target.process.returncode, 0)
                self.assertFalse(target.receipt["forcedCleanupUsed"])
            finally:
                dispose(target)

    def test_eof_and_forced_cleanup_are_distinct(self):
        for force in (False, True):
            with self.subTest(force=force), tempfile.TemporaryDirectory(prefix="d22-stop-") as temporary:
                root = Path(temporary); ready = root / "ready"
                action = "time.sleep(30)" if force else "sys.stdin.buffer.read()"
                code = ("import pathlib,signal,sys,time;signal.signal(signal.SIGTERM,signal.SIG_IGN);"
                        "pathlib.Path(sys.argv[1]).touch();" + action)
                target = subject.OwnedTarget((sys.executable, "-c", code, str(ready)), cwd=root, env=os.environ.copy())
                try:
                    wait_for_file(ready)
                    subject.cleanup_target(target, observer_groups_resolved=True)
                    self.assertEqual(target.receipt["forcedCleanupUsed"], force)
                    self.assertEqual(target.process.returncode, -signal.SIGKILL if force else 0)
                    self.assertTrue(target.stdin_closed)
                    self.assertFalse(target.selector.get_map())
                finally:
                    dispose(target)

    def test_unresolved_observer_keeps_target_reserved_during_forced_cleanup(self):
        with tempfile.TemporaryDirectory(prefix="d22-unresolved-") as temporary:
            target = subject.OwnedTarget((sys.executable, "-c", "import sys;sys.stdin.buffer.read()"),
                                         cwd=Path(temporary), env=os.environ.copy())
            try:
                subject.cleanup_target(target, observer_groups_resolved=False)
                self.assertTrue(target.reap_deferred)
                self.assertIsNone(target.process.returncode)
                self.assertFalse(target.receipt["stdinEOFRequested"])
                self.assertTrue(target.receipt["forcedCleanupUsed"])
                self.assertTrue(target.receipt["cleanupFailed"])
            finally:
                dispose(target)


# Explicit synthetic native receipt producer, never a substitute for the C
# program/native CI. Clock fields use Python nanoseconds solely as parser data.
TARGET_SOURCE = r'''import hashlib,json,os,pathlib,sys,time
args=dict(zip(sys.argv[1::2],sys.argv[2::2])); mode=CASE_MODE
def clock():
 before=time.monotonic_ns();wall=time.time_ns();after=time.monotonic_ns()
 return {'machAbsoluteBefore':before,'machAbsoluteAfter':after,'machContinuousBefore':before,'machContinuousAfter':after,'systemUptime':before/1e9,'wallTimeUnixNS':wall}
def publish(path,value):
 raw=(json.dumps(value)+'\n').encode();pending=pathlib.Path(str(path)+'.pending')
 with pending.open('xb') as handle:handle.write(raw)
 os.link(pending,path);pending.unlink();return raw
start=clock();ready_clock=clock()
value={'schema':1,'kind':'d22-sampler-calibration-ready','pid':os.getpid(),'ppid':os.getppid(),'pgid':os.getpgrp(),'euid':os.geteuid(),
'nonce':args['--nonce'],'executablePath':args['--expected-executable'],'executableSHA256':args['--expected-sha256'],'machOUUID':args['--expected-uuid'],
'architecture':args['--expected-architecture'],'sourceSHA256':args['--source-sha256'],'experimentCommit':args['--experiment-commit'],'experimentTree':args['--experiment-tree'],
'expectedFrame':'lemulip_d22_wait_for_release','safetyTimeoutSeconds':15,'identityValidated':True,'nativeInputExecuted':False,'settingsChanged':False,
'applicationLaunchRequested':False,'recordingRequested':False,'bootUUID':'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE','machTimebaseNumer':1,'machTimebaseDenom':1,
'translationProbe':{'returnCode':0,'errno':0,'value':0},'nativeStartClock':start,'readinessClock':ready_clock,'expectedFrameEntered':True,'receivedInputBytes':0}
raw=publish(pathlib.Path(args['--ready']),value)
if mode=='early-completion':
 publish(pathlib.Path(args['--completion']),{'kind':'synthetic-early-completion'});sys.exit(2)
received=sys.stdin.buffer.read();release=clock();completion=clock()
value.update(kind='d22-sampler-calibration-complete',reason='stdin-eof',cooperativeEOFObserved=True,safetyTimeoutExpired=False,finalIdentityMatches=True,
exitCode=0,receivedInputBytes=len(received),readyReceiptSHA256=hashlib.sha256(raw).hexdigest(),readyReceiptBytes=len(raw),releaseClock=release,completionClock=completion,
elapsedSeconds=(completion['machContinuousAfter']-start['machContinuousBefore'])/1e9)
if mode=='changed-readiness':
 value['readinessClock']=dict(value['readinessClock']);value['readinessClock']['wallTimeUnixNS']+=1
publish(pathlib.Path(args['--completion']),value)
'''


class RunFixture:
    def __init__(self, root, *, target_mode="normal", fault=None):
        self.root, self.fault = root, fault
        self.output = root / "evidence"; (self.output / "build").mkdir(parents=True)
        self.helper = self.output / "build/NativeSamplerCalibration"
        self.helper.write_text("#!" + sys.executable + "\n" + TARGET_SOURCE.replace("CASE_MODE", repr(target_mode)))
        self.helper.chmod(0o700)
        self.architecture = platform.machine()
        self.provenance = {"schema": 1, "diagnostic": "D22-native-sampler-calibration", "architecture": self.architecture,
                           "experimentCommit": "c" * 40, "experimentTree": "d" * 40, "sourceSHA256": "b" * 64,
                           "expectedFrame": subject.EXPECTED_FRAME,
                           "helper": {"path": str(self.helper), "architecture": self.architecture, "uuid": UUID,
                                      "sha256": hashlib.sha256(self.helper.read_bytes()).hexdigest()}}
        self.provenance_path = self.output / "build-provenance.json"
        self.provenance_path.write_text(json.dumps(self.provenance))
        self.targets, self.commands, self.original_argv = [], [], []
        self.ps_count, self.group_count = 0, 0
        self.target_class, self.command_class = subject.OwnedTarget, subject.observation.ObservationCommand
        self.stdin_underlying = None

    def target(self, argv, **kwargs):
        target = self.target_class(argv, **kwargs)
        self.targets.append(target)
        wait_for_file(self.output / "target-ready.json")
        # Test-only observation clock starts after fixture readiness so a
        # shortened trigger never depends on interpreter startup speed. No
        # native timing conclusion is drawn from these synthetic run receipts.
        target.started = time.monotonic()
        if self.fault == "target-drain":
            target.drain = lambda: (_ for _ in ()).throw(OSError("injected persistent target drain failure"))
        if self.fault == "stdin-close":
            underlying = target.process.stdin
            self.stdin_underlying = underlying
            class FailOnce:
                def __init__(self): self.calls = 0
                @property
                def closed(self): return underlying.closed
                def close(self):
                    self.calls += 1
                    if self.calls == 1: raise OSError("injected stdin close failure before FD close")
                    return underlying.close()
            target.process.stdin = FailOnce()
        return target

    def command(self, argv, **kwargs):
        argv = tuple(argv); self.original_argv.append(argv)
        target = self.targets[-1]
        fault = False
        if argv[0] == "/bin/ps" and "-p" in argv:
            self.ps_count += 1
            assert target.reap_deferred and target.process.returncode is None
            assert int(argv[argv.index("-p") + 1]) == target.process.pid
            row = f"{target.process.pid} {os.getpid()} {target.process.pid} {os.geteuid()} Mon Nov 9 12:00:00 2026 S fixture fixture"
            if self.ps_count == 2 and self.fault == "report-mutation":
                sample = self.root / "work/controlled-sample.txt"
                sample.write_bytes(sample.read_bytes() + b"retention mutation\n")
            argv = (sys.executable, "-c", "import sys;print(sys.argv[1])", row)
        elif argv[0] == "/usr/bin/sample":
            assert target.reap_deferred and target.process.returncode is None
            assert argv[1:6] == (str(target.process.pid), "1", "10", "-mayDie", "-file")
            if self.fault in ("sample-tick", "sample-budget"):
                fault = self.fault == "sample-tick"
                marker = self.root / "sample-ready"
                argv = (sys.executable, "-c", "import pathlib,signal,sys,time;signal.signal(signal.SIGTERM,signal.SIG_IGN);pathlib.Path(sys.argv[1]).touch();time.sleep(30)", str(marker))
            else:
                body = sample_report(self.helper, target.process.pid, self.architecture).decode()
                argv = (sys.executable, "-c", "import pathlib,sys;pathlib.Path(sys.argv[1]).write_text(sys.argv[2])", argv[-1], body)
        elif argv[:2] == ("/bin/ps", "-A"):
            self.group_count += 1
            if self.group_count == 1:
                assert target.reap_deferred and target.process.returncode is None
            fault = self.fault == ("observer-checker-tick" if self.group_count == 1 else "target-checker-tick")
            if fault:
                marker = self.root / ("checker-ready-" + str(self.group_count))
                argv = (sys.executable, "-c", "import pathlib,signal,sys,time;signal.signal(signal.SIGTERM,signal.SIG_IGN);pathlib.Path(sys.argv[1]).touch();time.sleep(30)", str(marker))
            else:
                argv = (sys.executable, "-c", "print('1 1 S')")
        else:
            raise AssertionError("Unexpected command in fixed calibration: " + repr(argv))
        command = self.command_class(argv, **kwargs)
        self.commands.append(command)
        if fault or self.fault == "sample-budget" and self.original_argv[-1][0] == "/usr/bin/sample":
            wait_for_file(marker)
        if fault:
            command.tick = lambda: (_ for _ in ()).throw(RuntimeError("injected persistent owned checker/sample tick failure"))
        return command

    def run(self, **extra_patches):
        from contextlib import ExitStack
        with ExitStack() as stack:
            stack.enter_context(patch.object(subject, "TRIGGER_SECONDS", .05))
            stack.enter_context(patch.object(subject, "OwnedTarget", side_effect=self.target))
            stack.enter_context(patch.object(subject.observation, "ObservationCommand", side_effect=self.command))
            stack.enter_context(patch.object(subject.observation, "preflight", return_value={"passed": True}))
            for key, value in extra_patches.items(): stack.enter_context(patch.object(subject, key, value))
            return subject.run(self.helper, self.output, self.provenance_path)

    def close(self):
        for command in self.commands:
            dispose(command.transport)
        for target in self.targets:
            dispose(target)


class CalibrationLifecycle(unittest.TestCase):
    def test_one_positive_control_keeps_original_recorder_and_acceptance_unqualified(self):
        with tempfile.TemporaryDirectory(prefix="d22-qualified-") as temporary:
            fixture = RunFixture(Path(temporary))
            try:
                result = fixture.run()
                self.assertTrue(result["controlledSamplerCalibrationComplete"], result["errors"])
                self.assertEqual(result["sampleInvocationCount"], 1)
                self.assertEqual(result["sampleReport"], result["qualifiedSampleReport"])
                self.assertEqual(result["target"]["exitCode"], 0)
                self.assertFalse(result["target"]["forcedCleanupUsed"])
                self.assertEqual(result["C12"], "HOLD")
                for key in ("releaseReady", "recordingExecuted", "nativeInputExecuted", "recorderImageOrStackQualified", "activationRouteCoverageEstablished"):
                    self.assertFalse(result[key])
                self.assertTrue(all(command.transport.closed for command in fixture.commands))
                self.assertTrue(fixture.targets[0].closed)
            finally:
                fixture.close()

    def test_completion_binding_and_retained_sample_mutation_cannot_pass(self):
        for mode, fault in (("changed-readiness", None), ("normal", "report-mutation")):
            with self.subTest(mode=mode, fault=fault), tempfile.TemporaryDirectory(prefix="d22-binding-") as temporary:
                fixture = RunFixture(Path(temporary), target_mode=mode, fault=fault)
                try:
                    result = fixture.run()
                    self.assertFalse(result["controlledSamplerCalibrationComplete"])
                    self.assertEqual(result["sampleInvocationCount"], 1)
                    self.assertTrue(result["errors"])
                    if fault:
                        self.assertNotEqual(result["sampleReport"], result["qualifiedSampleReport"])
                finally:
                    fixture.close()

    def test_completed_target_or_closed_cutoff_cannot_start_sampling(self):
        for mode, cutoff in (("early-completion", 14.0), ("normal", .06)):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory(prefix="d22-stop-gate-") as temporary:
                fixture = RunFixture(Path(temporary), target_mode=mode)
                try:
                    result = fixture.run(CUTOFF_SECONDS=cutoff)
                    self.assertFalse(result["controlledSamplerCalibrationComplete"])
                    self.assertEqual(result["sampleInvocationCount"], 0)
                    self.assertFalse(any(argv[0] == "/usr/bin/sample" for argv in fixture.original_argv))
                finally:
                    fixture.close()

    def test_sampler_budget_is_one_attempt_and_cannot_be_promoted_by_cleanup(self):
        with tempfile.TemporaryDirectory(prefix="d22-budget-") as temporary:
            fixture = RunFixture(Path(temporary), fault="sample-budget")
            try:
                result = fixture.run()
                self.assertFalse(result["controlledSamplerCalibrationComplete"])
                self.assertEqual(result["sampleInvocationCount"], 1)
                self.assertEqual(sum(argv[0] == "/usr/bin/sample" for argv in fixture.original_argv), 1)
                self.assertEqual(result["commands"]["sample"]["stopReason"], "command-budget")
                self.assertTrue(fixture.commands[1].transport.closed)
            finally:
                fixture.close()

    def test_owned_sample_and_late_cleanup_checker_tick_faults_cannot_leak_children(self):
        for fault in ("sample-tick", "observer-checker-tick", "target-checker-tick"):
            with self.subTest(fault=fault), tempfile.TemporaryDirectory(prefix="d22-tick-fault-") as temporary:
                fixture = RunFixture(Path(temporary), fault=fault)
                try:
                    result = fixture.run()
                    self.assertFalse(result["controlledSamplerCalibrationComplete"])
                    self.assertTrue(result["errors"])
                    for command in fixture.commands:
                        self.assertIsNotNone(command.transport.process.returncode, command.transport.receipt)
                        self.assertTrue(command.transport.closed)
                    self.assertTrue(fixture.targets[0].closed)
                finally:
                    fixture.close()

    def test_target_drain_and_stdin_close_faults_preserve_bounded_cleanup(self):
        for fault in ("target-drain", "stdin-close"):
            with self.subTest(fault=fault), tempfile.TemporaryDirectory(prefix="d22-target-fault-") as temporary:
                fixture = RunFixture(Path(temporary), fault=fault)
                try:
                    result = fixture.run()
                    self.assertFalse(result["controlledSamplerCalibrationComplete"])
                    self.assertTrue(result["target"]["streamErrors"])
                    self.assertTrue(fixture.targets[0].closed)
                    if fixture.stdin_underlying is not None:
                        self.assertTrue(fixture.stdin_underlying.closed)
                    self.assertTrue(all(command.transport.closed for command in fixture.commands))
                finally:
                    fixture.close()


if __name__ == "__main__":
    unittest.main()
