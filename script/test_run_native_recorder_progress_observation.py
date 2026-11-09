#!/usr/bin/env python3
"""D24 portable behavior tests; every reported native observation is synthetic."""
from __future__ import annotations

import copy
import hashlib
import json
import os
from pathlib import Path
import platform
import signal
import struct
import subprocess
import sys
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest import mock
import uuid

import native_sampler_tool_identity as tool_identity
import run_native_recorder_progress_observation as progress


def until(predicate, *, tick=lambda: None, timeout=3.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        tick()
        if predicate():
            return
        time.sleep(.005)
    raise AssertionError("Synthetic child did not reach its expected bounded state")


class OwnedCommandTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.children = []

    def command(self, code, *, budget=1.0, reserve=.2, limit=65536, factory=None):
        command = progress.OwnedCommand(
            "synthetic-owned-child", (sys.executable, "-u", "-c", code),
            cwd=self.root, env=dict(os.environ), budget=budget, limit=limit,
            reserve=reserve, term_grace=.04, factory=factory,
        )
        self.children.append(command)
        return command

    def tearDown(self):
        # A failed assertion cannot leave a still-owned test process running.
        # waitid verifies child ownership without collecting before a signal.
        for command in self.children:
            process = command.transport.process
            if process is None or process.returncode is not None:
                command.close()
                continue
            try:
                os.waitid(os.P_PID, process.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)
            except ChildProcessError:
                command.close()
                continue
            try:
                command.transport.signal(signal.SIGKILL, group=True)
                deadline = time.monotonic() + 1.0
                while time.monotonic() < deadline:
                    command.transport.drain()
                    if command.peek() is not None and not command.transport.selector.get_map():
                        command.collect()
                        break
                    time.sleep(.005)
            finally:
                command.close()
        self.directory.cleanup()

    def test_exit_peek_keeps_pid_reserved_until_explicit_collection(self):
        command = self.command("print('synthetic exit', flush=True)")
        until(lambda: command.operation_done, tick=command.tick)
        self.assertTrue(command.terminal)
        self.assertEqual(command.peek(), 0)
        self.assertIsNone(command.transport.process.returncode)
        self.assertFalse(command.collected)
        for _ in range(3):
            witness = os.waitid(os.P_PID, command.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)
            self.assertEqual(witness.si_pid, command.pid)
            command.tick()
            self.assertIsNone(command.transport.process.returncode)
        command.collect()
        self.assertTrue(command.collected)
        self.assertEqual(command.transport.process.returncode, 0)
        with self.assertRaises(ChildProcessError):
            os.waitid(os.P_PID, command.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)

    def test_live_child_cannot_be_collected(self):
        command = self.command("import time; print('ready', flush=True); time.sleep(30)")
        until(lambda: b"ready" in command.transport.streams["stdout"], tick=command.tick)
        with self.assertRaises(progress.EvidenceError):
            command.collect()
        self.assertIsNone(command.transport.process.returncode)
        self.assertFalse(command.collected)

    def test_closed_streams_do_not_make_a_live_leader_terminal(self):
        command = self.command("import os,time; os.close(1); os.close(2); time.sleep(30)",
                               budget=.6, reserve=.2)
        until(lambda: not command.transport.selector.get_map(), tick=command.tick)
        self.assertIsNone(command.peek())
        self.assertFalse(command.terminal)
        self.assertFalse(command.operation_done)
        self.assertIsNone(command.transport.process.returncode)
        until(lambda: command.operation_done, tick=command.tick)
        self.assertEqual(command.receipt["stopReason"], "command-budget")
        command.collect()

    def test_normal_budget_interrupts_even_while_pid_collection_is_deferred(self):
        code = "import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); print('ready',flush=True); time.sleep(30)"
        command = self.command(code, budget=.8, reserve=.2)
        until(lambda: command.operation_done, tick=command.tick)
        self.assertEqual(command.receipt["stopReason"], "command-budget")
        signals = command.receipt["signals"]
        self.assertEqual([entry["signal"] for entry in signals], ["SIGTERM", "SIGKILL"])
        self.assertGreaterEqual(signals[0]["afterSeconds"], .6)
        self.assertLess(signals[0]["afterSeconds"], .8)
        self.assertEqual(command.peek(), -signal.SIGKILL)
        self.assertIsNone(command.transport.process.returncode)
        command.collect()
        self.assertTrue(command.collected)

    def test_exited_leader_does_not_hide_live_descendant_with_inherited_streams(self):
        code = ("import subprocess,sys; "
                "subprocess.Popen([sys.executable,'-u','-c','import time; print(\"descendant\",flush=True); time.sleep(30)']); "
                "print('leader exited',flush=True)")
        command = self.command(code, budget=.8, reserve=.2)
        until(lambda: command.terminal, tick=command.tick)
        self.assertFalse(command.operation_done)
        self.assertTrue(command.transport.selector.get_map())
        self.assertIsNone(command.transport.process.returncode)
        with self.assertRaises(progress.EvidenceError):
            command.collect()
        until(lambda: command.operation_done, tick=command.tick)
        self.assertEqual(command.receipt["stopReason"], "command-budget")
        self.assertFalse(command.transport.selector.get_map())
        command.collect()
        self.assertEqual(command.transport.process.returncode, 0)

    def test_output_limit_is_a_failure_and_retention_is_bounded(self):
        command = self.command("import time; print('x'*8192,flush=True); time.sleep(30)", limit=128)
        until(lambda: command.operation_done, tick=command.tick)
        self.assertEqual(command.receipt["stopReason"], "output-limit")
        self.assertLessEqual(sum(len(value) for value in command.transport.streams.values()), 128)
        self.assertIsNone(command.transport.process.returncode)
        command.collect()

    def test_repeated_stop_and_tick_never_signal_after_collection(self):
        command = self.command("print('done',flush=True)")
        until(lambda: command.operation_done, tick=command.tick)
        command.collect()
        with mock.patch.object(command.transport, "signal", side_effect=AssertionError("Signal after collection")):
            command.stop("late cancellation")
            command.tick()
            command.close()

    def test_natural_exit_first_observed_after_total_deadline_does_not_pass_the_bound(self):
        command = self.command("raise SystemExit(0)", budget=.2, reserve=.05)
        time.sleep(.23)
        command.tick()
        self.assertTrue(command.terminal)
        self.assertTrue(command.receipt["cleanupFailed"])
        self.assertIn("completion-not-observed-within-total-budget", command.receipt["cleanupFailureReasons"])
        self.assertIsNone(command.transport.process.returncode)
        command.collect()

    def test_post_reap_status_mismatch_revokes_all_future_pid_directed_actions(self):
        command = self.command("print('done',flush=True)")
        until(lambda: command.operation_done, tick=command.tick)
        real_poll = command.transport.poll

        def reap_then_misreport():
            return real_poll() + 1

        with mock.patch.object(command.transport, "poll", side_effect=reap_then_misreport):
            with self.assertRaises(progress.EvidenceError):
                command.collect()
        self.assertEqual(command.transport.process.returncode, 0)
        self.assertTrue(command.collected)
        self.assertTrue(command.receipt["pidDirectedActionsRevoked"])
        with mock.patch.object(command.transport, "signal", side_effect=AssertionError("Signal after reap")):
            command.stop("late cleanup after mismatch")
            command.tick()
            command.close()

    def test_echild_after_external_reap_revokes_every_later_pid_and_group_signal(self):
        command = self.command("raise SystemExit(0)")
        # Model the concrete invalid-ownership case using an actual reap,
        # before OwnedCommand has observed terminal status with WNOWAIT.
        self.assertEqual(command.transport.process.wait(timeout=1), 0)
        with self.assertRaises(progress.EvidenceError):
            command.peek()
        self.assertTrue(command.receipt["pidLeaseLost"])
        self.assertTrue(command.receipt["pidDirectedActionsRevoked"])
        self.assertTrue(command.receipt["cleanupFailed"])
        with mock.patch.object(command.transport, "signal", side_effect=AssertionError("Signal after ECHILD")):
            command.stop("late cancellation after ownership loss")
            command.tick()
            self.assertFalse(command.signal(signal.SIGTERM))
            self.assertFalse(command.signal(signal.SIGKILL, group=True))
            with self.assertRaises(progress.EvidenceError):
                command.collect()
            command.close()

    def test_term_escalates_after_leader_exit_and_eof_while_descendant_ignores_term(self):
        ready = self.root / "silent-descendant-ready"
        leaf = ("import os,pathlib,signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); "
                f"pathlib.Path({str(ready)!r}).write_text(str(os.getpid())); time.sleep(30)")
        code = ("import pathlib,subprocess,sys,time; "
                f"subprocess.Popen([sys.executable,'-u','-c',{leaf!r}],stdin=subprocess.DEVNULL,"
                "stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL); "
                f"ready=pathlib.Path({str(ready)!r}); "
                "\nwhile not ready.exists(): time.sleep(.002)\n"
                "print('leader and silent descendant ready',flush=True); time.sleep(30)")
        command = self.command(code, budget=.8, reserve=.2)
        until(lambda: b"descendant ready" in command.transport.streams["stdout"], tick=command.tick)
        until(lambda: command.operation_done, tick=command.tick)
        self.assertEqual([entry["signal"] for entry in command.receipt["signals"]], ["SIGTERM", "SIGKILL"])
        self.assertEqual(command.peek(), -signal.SIGTERM)
        self.assertFalse(command.transport.selector.get_map())
        self.assertIsNone(command.transport.process.returncode)
        command.collect()
        try:
            os.waitpid(int(ready.read_text()), os.WNOHANG)
        except ChildProcessError:
            pass


class SamplerProgressTextTests(unittest.TestCase):
    BANNER = b"Sampling process 1234 for 1 second with 10 milliseconds of run time between samples\n"
    COMPLETE = b"Sampling completed, processing symbols...\n"
    WRITTEN = b"Sample analysis of process 1234 written to file /synthetic/primary.txt\n"

    def classify(self, raw):
        return progress.classify_sample_stderr(raw, target_pid=1234)

    def test_only_a_complete_expected_pid_banner_opens_the_observation_gate(self):
        for end in range(len(self.BANNER)):
            with self.subTest(end=end):
                self.assertFalse(self.classify(self.BANNER[:end])["expectedBannerObserved"])
        result = self.classify(self.BANNER)
        self.assertTrue(result["expectedBannerObserved"])
        self.assertEqual(result["expectedBannerCount"], 1)
        self.assertFalse(result["ambiguous"])
        self.assertFalse(result["samplingCompletedMarkerObserved"])
        self.assertFalse(result["reportWrittenMarkerObserved"])

    def test_foreign_pid_duplicate_and_malformed_banners_never_qualify(self):
        cases = [self.BANNER.replace(b"1234", b"9999"), self.BANNER + self.BANNER,
                 self.BANNER.replace(b"1 second", b"2 seconds"),
                 self.BANNER.replace(b"10 milliseconds", b"1 millisecond"),
                 b"prefix " + self.BANNER]
        for raw in cases:
            with self.subTest(raw=raw):
                result = self.classify(raw)
                self.assertFalse(result["expectedBannerObserved"] and not result["ambiguous"])

    def test_progress_markers_are_observed_text_without_internal_phase_inference(self):
        result = self.classify(self.BANNER + self.COMPLETE + self.WRITTEN)
        self.assertTrue(result["expectedBannerObserved"])
        self.assertTrue(result["samplingCompletedMarkerObserved"])
        self.assertTrue(result["reportWrittenMarkerObserved"])
        self.assertFalse(result["ambiguous"])
        banner_only = self.classify(self.BANNER)
        self.assertIsNot(banner_only.get("earlySymbolDiscoveryExcluded"), True)
        self.assertIsNot(banner_only.get("samplingNeverStarted"), True)
        self.assertIsNot(banner_only.get("permissionDenied"), True)

    def test_nul_or_oversized_stream_cannot_produce_a_gate(self):
        for raw in (self.BANNER + b"\0", self.BANNER + b"x" * progress.STREAM_LIMIT):
            with self.subTest(length=len(raw)), self.assertRaises(progress.EvidenceError):
                self.classify(raw)


class NonreapingCapabilityTests(unittest.TestCase):
    def test_positive_capability_is_demonstrated_by_a_real_owned_child(self):
        result = progress.waitid_preflight()
        self.assertTrue(result["available"])
        self.assertTrue(result["peekDidNotReap"])
        self.assertEqual(result["exitCode"], 23)

    def test_failed_capability_probe_still_collects_its_owned_child(self):
        processes = []
        popen = subprocess.Popen

        def record_process(*args, **kwargs):
            child = popen(*args, **kwargs)
            processes.append(child)
            return child

        with mock.patch.object(progress.subprocess, "Popen", side_effect=record_process):
            with mock.patch.object(progress.os, "waitid", side_effect=OSError("synthetic unsupported waitid")):
                with self.assertRaises(progress.EvidenceError):
                    progress.waitid_preflight()
        self.assertEqual(len(processes), 1)
        self.assertIsNotNone(processes[0].returncode)


class BoundedFileTests(unittest.TestCase):
    def test_fifo_is_rejected_without_waiting_for_a_writer(self):
        with tempfile.TemporaryDirectory(prefix="d24-fifo-") as temporary:
            fifo = Path(temporary) / "untrusted-report"
            os.mkfifo(fifo, 0o600)
            code = ("import sys; import run_native_recorder_progress_observation as p\n"
                    "try:\n    p.read_regular(sys.argv[1], 32768)\n"
                    "except (p.EvidenceError, OSError):\n    print('nonregular-rejected')\n"
                    "else:\n    raise SystemExit('FIFO incorrectly accepted')\n")
            # A regression to a blocking open still cannot hang this test run.
            result = subprocess.run((sys.executable, "-u", "-c", code, str(fifo)),
                                    env=dict(os.environ, PYTHONPATH=str(Path(__file__).resolve().parent)),
                                    capture_output=True, timeout=2)
            self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
            self.assertEqual(result.stdout, b"nonregular-rejected\n")


SAMPLE_UUID = "12345678-1234-1234-1234-123456789ABC"
SECOND_UUID = "22345678-1234-1234-1234-123456789ABC"
KERNEL_UUID = "32345678-1234-1234-1234-123456789ABC"


def synthetic_report(*, pid=1234, parent=4321, code_type="ARM64E (Native)",
                     sample_uuid=SAMPLE_UUID, header_path="/usr/bin/sample",
                     image_path="/usr/bin/sample"):
    """Made-up report bytes for parser behavior, never retained native evidence."""
    return (f"""Analysis of sampling sample (pid {pid}) every 10 milliseconds
Process:         sample [{pid}]
Path:            {header_path}
Load Address:    0x1000
Code Type:       {code_type}
Platform:        macOS
Parent Process:  Python [{parent}]
Target Type:     live task
Report Version:  7
Analysis Tool:   /usr/bin/sample

Call graph:
    40 Thread_1: synthetic thread
    + 40 synthetic_sampler_wait (in sample) + 4 [0x1004]
    +   40 synthetic_mach_msg (in libsystem_kernel.dylib) + 8 [0x5008]

Total number in stack (recursive counted multiple, when >=5):
        40 synthetic_sampler_wait (in sample) + 4 [0x1004]

Sort by top of stack, same collapsed (when >= 5):
        synthetic_sampler_wait (in sample)        40

Binary Images:
       0x1000 - 0x1fff  sample (1 - 1) <{sample_uuid}> {image_path}
       0x5000 - 0x5fff  libsystem_kernel.dylib (1 - 1) <{KERNEL_UUID}> /usr/lib/system/libsystem_kernel.dylib
""").encode()


class SamplerReportIdentityTests(unittest.TestCase):
    def inspect(self, raw, *, architecture="arm64", native_uuids=None):
        return progress.inspect_sampler_report(
            raw, target_pid=1234, target_parent=4321, architecture=architecture,
            tool_identity={"architecture": architecture,
                           "nativeUUIDs": native_uuids or [SAMPLE_UUID]},
        )

    def test_native_family_accepts_arm64e_without_claiming_a_known_helper_frame(self):
        for code in ("ARM64", "ARM64 (Native)", "ARM-64 (Native)",
                     "ARM64E", "ARM64E (Native)", "ARM-64E (Native)"):
            with self.subTest(code=code):
                result = self.inspect(synthetic_report(code_type=code))
                self.assertEqual(result["mainImageUUID"], SAMPLE_UUID)
                self.assertEqual(result["countedFrames"][0]["sampleCount"], 40)
                self.assertEqual(result["countedFrames"][0]["pc"], 0x1004)
                self.assertFalse(result["establishesD23KnownFrameContract"])
                self.assertFalse(result["establishesUnperturbedRecorderState"])

    def test_native_x86_report_uses_the_uuid_of_a_supported_native_slice(self):
        result = self.inspect(synthetic_report(code_type="X86-64 (Native)", sample_uuid=SECOND_UUID),
                              architecture="x86_64", native_uuids=[SAMPLE_UUID, SECOND_UUID])
        self.assertEqual(result["mainImageUUID"], SECOND_UUID)

    def test_report_paths_are_preserved_as_advisory_without_matching_globs(self):
        result = self.inspect(synthetic_report(header_path="/private/*/different-name",
                                               image_path="/masked/sample-copy"))
        self.assertEqual(result["observedHeaderPath"], "/private/*/different-name")
        self.assertEqual(result["observedMainImagePath"], "/masked/sample-copy")
        self.assertTrue(result["pathsAreAdvisory"])
        self.assertFalse(result["pathsWereGlobMatched"])

    def test_foreign_or_translated_code_type_cannot_prove_native_identity(self):
        for code in ("X86-64 (Native)", "X86-64 (Translated)", "ARM64 (Translated)", "ARM", "unknown"):
            with self.subTest(code=code), self.assertRaises(progress.EvidenceError):
                self.inspect(synthetic_report(code_type=code))

    def test_pid_parent_uuid_and_load_address_must_each_bind_to_the_owned_sampler(self):
        valid = synthetic_report(code_type="ARM64")
        cases = [synthetic_report(pid=1235, code_type="ARM64"),
                 synthetic_report(parent=4322, code_type="ARM64"),
                 synthetic_report(sample_uuid=SECOND_UUID, code_type="ARM64"),
                 valid.replace(b"Load Address:    0x1000", b"Load Address:    0x1001"),
                 valid.replace(b"Process:         sample", b"Process:         other"),
                 valid.replace(b"Platform:        macOS", b"Platform:        other")]
        for raw in cases:
            with self.subTest(raw=raw[:180]), self.assertRaises(progress.EvidenceError):
                self.inspect(raw)

    def test_duplicate_identity_fields_or_main_image_are_rejected(self):
        valid = synthetic_report(code_type="ARM64")
        cases = [valid.replace(b"Call graph:", b"Process: sample [1234]\nCall graph:"),
                 valid + (f"0x9000 - 0x9fff sample (1 - 1) <{SECOND_UUID}> /synthetic/sample\n").encode(),
                 valid + (f"0x9000 - 0x9fff other (1 - 1) <{SAMPLE_UUID}> /synthetic/other\n").encode(),
                 valid.replace(b"Binary Images:", b"Call graph:\nBinary Images:")]
        for raw in cases:
            with self.subTest(raw=raw[-160:]), self.assertRaises(progress.EvidenceError):
                self.inspect(raw)

    def test_counted_main_frame_is_required_in_call_graph_not_just_summary(self):
        valid = synthetic_report(code_type="ARM64")
        raw = valid.replace(b"    + 40 synthetic_sampler_wait (in sample) + 4 [0x1004]\n", b"")
        with self.assertRaises(progress.EvidenceError):
            self.inspect(raw)

    def test_frame_addresses_cannot_claim_overlapping_or_wrong_images(self):
        valid = synthetic_report(code_type="ARM64")
        cases = [valid.replace(b"[0x1004]", b"[0x9004]"),
                 valid.replace(b"[0x1004]", b"[0x5004]"),
                 valid.replace(b"0x5000 - 0x5fff", b"0x1000 - 0x5fff"),
                 valid.replace(b"+ 40 synthetic_sampler_wait", b"+ 0 synthetic_sampler_wait"),
                 valid.replace(b"0x1000 - 0x1fff", b"0x1fff - 0x1000")]
        for raw in cases:
            with self.subTest(raw=raw[-220:]), self.assertRaises(progress.EvidenceError):
                self.inspect(raw)

    def test_binary_and_oversized_reports_are_rejected_before_parsing(self):
        for raw in (b"", b"\xff", b"\0", b"x" * (progress.REPORT_LIMIT + 1)):
            with self.subTest(length=len(raw)), self.assertRaises(progress.EvidenceError):
                self.inspect(raw)


def synthetic_macho(*, cpu=0x0100000C, subtype=2, image_uuid=SAMPLE_UUID,
                    endian="<", commands=None, filetype=2):
    if commands is None:
        commands = [struct.pack(endian + "II", 0x1B, 24) + uuid.UUID(image_uuid).bytes]
    body = b"".join(commands)
    return struct.pack(endian + "8I", 0xFEEDFACF, cpu, subtype, filetype,
                       len(commands), len(body), 0, 0) + body


def synthetic_fat(slices, *, wide=False, endian=">"):
    """Construct a data-only FAT fixture from explicit CPU, subtype, slice bytes."""
    width = 32 if wide else 20
    offset = 8 + len(slices) * width
    table, bodies = [], []
    for cpu, subtype, body in slices:
        if wide:
            table.append(struct.pack(endian + "IIQQII", cpu, subtype, offset, len(body), 0, 0))
        else:
            table.append(struct.pack(endian + "5I", cpu, subtype, offset, len(body), 0))
        bodies.append(body)
        offset += len(body)
    return (struct.pack(endian + "II", 0xCAFEBABF if wide else 0xCAFEBABE, len(slices))
            + b"".join(table) + b"".join(bodies))


class InstalledToolIdentityTests(unittest.TestCase):
    def test_thin_native_subtypes_and_endianness_preserve_byte_identity(self):
        for family, cpu, subtype in (("arm64", 0x0100000C, 2),
                                     ("arm64", 0x0100000C, 0x80000002),
                                     ("x86_64", 0x01000007, 8),
                                     ("x86_64", 0x01000007, 0x80000008)):
            for endian in ("<", ">"):
                with self.subTest(family=family, endian=endian):
                    raw = synthetic_macho(cpu=cpu, subtype=subtype, endian=endian)
                    result = tool_identity.inspect_tool(raw, family)
                    self.assertEqual(result["nativeUUIDs"], [SAMPLE_UUID])
                    self.assertEqual(result["nativeSlices"][0]["cpuSubtype"], subtype)
                    self.assertEqual(result["sha256"], hashlib.sha256(raw).hexdigest())
                    self.assertEqual(result["nativeSlices"][0]["sha256"], result["sha256"])
                    self.assertEqual(result["nativeSlices"][0]["offset"], 0)

    def test_fat_and_fat64_select_all_host_family_subtypes_without_translation(self):
        slices = [(0x0100000C, 0, synthetic_macho(subtype=0)),
                  (0x0100000C, 2, synthetic_macho(subtype=2, image_uuid=SECOND_UUID)),
                  (0x01000007, 8, synthetic_macho(cpu=0x01000007, subtype=8,
                                                image_uuid=KERNEL_UUID))]
        for wide in (False, True):
            for endian in ("<", ">"):
                with self.subTest(wide=wide, endian=endian):
                    raw = synthetic_fat(slices, wide=wide, endian=endian)
                    arm = tool_identity.inspect_tool(raw, "arm64")
                    intel = tool_identity.inspect_tool(raw, "x86_64")
                    self.assertEqual(arm["nativeUUIDs"], [SAMPLE_UUID, SECOND_UUID])
                    self.assertEqual(intel["nativeUUIDs"], [KERNEL_UUID])
                    for entry in arm["slices"]:
                        section = raw[entry["offset"]:entry["offset"] + entry["bytes"]]
                        self.assertEqual(entry["sha256"], hashlib.sha256(section).hexdigest())
                    self.assertEqual(arm["sha256"], hashlib.sha256(raw).hexdigest())

    def test_wrong_host_family_and_nonexecutable_images_are_rejected(self):
        cases = [(synthetic_macho(), "x86_64"),
                 (synthetic_macho(), "aarch64"),
                 (synthetic_macho(filetype=6), "arm64"),
                 (synthetic_macho(cpu=12), "arm64")]
        for raw, family in cases:
            with self.subTest(family=family, prefix=raw[:16]), self.assertRaises(tool_identity.IdentityError):
                tool_identity.inspect_tool(raw, family)

    def test_missing_zero_duplicate_uuid_and_invalid_load_commands_are_rejected(self):
        duplicate = [struct.pack("<II", 0x1B, 24) + uuid.UUID(SAMPLE_UUID).bytes] * 2
        cases = [synthetic_macho(image_uuid=str(uuid.UUID(int=0))),
                 synthetic_macho(commands=[]),
                 synthetic_macho(commands=duplicate),
                 synthetic_macho(commands=[struct.pack("<II", 0x1B, 8)]),
                 synthetic_macho(commands=[struct.pack("<II", 0x1B, 40) + uuid.UUID(SAMPLE_UUID).bytes]),
                 synthetic_macho()[:-1]]
        for raw in cases:
            with self.subTest(length=len(raw), prefix=raw[:32]), self.assertRaises(tool_identity.IdentityError):
                tool_identity.inspect_tool(raw, "arm64")

    def test_fat_table_must_match_nonoverlapping_bounded_unique_slices(self):
        slices = [(0x0100000C, 0, synthetic_macho(subtype=0)),
                  (0x0100000C, 2, synthetic_macho(image_uuid=SECOND_UUID))]
        valid = synthetic_fat(slices)
        cases = []
        for location, replacement in ((16, struct.pack(">I", len(valid) + 100)),
                                      (20, struct.pack(">I", len(valid))),
                                      (24, struct.pack(">I", 32)),
                                      (36, struct.pack(">I", 48)),
                                      (12, struct.pack(">I", 2))):
            mutated = bytearray(valid)
            mutated[location:location + len(replacement)] = replacement
            cases.append(bytes(mutated))
        cases.append(synthetic_fat([(0x0100000C, 0, synthetic_macho(subtype=0)),
                                    (0x0100000C, 0, synthetic_macho(subtype=0, image_uuid=SECOND_UUID))]))
        cases.append(synthetic_fat([(0x0100000C, 0, synthetic_macho(subtype=0)),
                                    (0x0100000C, 2, synthetic_macho(subtype=2))]))
        for raw in cases:
            with self.subTest(table=raw[:48]), self.assertRaises(tool_identity.IdentityError):
                tool_identity.inspect_tool(raw, "arm64")


def synthetic_native_clock():
    before, wall, after = time.monotonic_ns(), time.time_ns(), time.monotonic_ns()
    return {"machAbsoluteBefore": before, "machAbsoluteAfter": after,
            "machContinuousBefore": before, "machContinuousAfter": after,
            "systemUptime": before / 1e9, "wallTimeUnixNS": wall}


def fixture_publish(path, value):
    raw = (json.dumps(value, sort_keys=True) + "\n").encode()
    with Path(path).open("xb") as handle:
        handle.write(raw)
    return raw


def fixture_event(name, **fields):
    path = os.environ.get("LEMULIP_D24_SYNTHETIC_EVENTS")
    if path:
        entry = {"event": name, "pid": os.getpid(), "monotonic": time.monotonic(), **fields}
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
        try:
            os.write(descriptor, (json.dumps(entry, sort_keys=True) + "\n").encode())
        finally:
            os.close(descriptor)


def synthetic_helper(argv, scenario, scale):
    options = dict(zip(argv[1::2], argv[2::2]))
    abort = False

    def request_abort(_signum, _frame):
        nonlocal abort
        abort = True

    signal.signal(signal.SIGTERM, request_abort)
    start = synthetic_native_clock()
    before_registration = synthetic_native_clock()
    callback = synthetic_native_clock() if scenario == "early-callback" else None
    after_registration = synthetic_native_clock()
    ready_clock = synthetic_native_clock()
    notification = {"name": options["--recording-notification"], "registered": True,
                    "registrationStatus": 0, "token": 17,
                    "registrationBeforeClock": before_registration,
                    "registrationAfterClock": after_registration}
    ready = {"schema": 1, "kind": "d24-recorder-progress-ready", "pid": os.getpid(),
             "ppid": os.getppid(), "pgid": os.getpgrp(), "euid": os.geteuid(),
             "executablePath": options["--expected-executable"],
             "executableSHA256": options["--expected-sha256"],
             "machOUUID": options["--expected-uuid"],
             "architecture": options["--expected-architecture"], "nonce": options["--nonce"],
             "sourceSHA256": options["--source-sha256"],
             "experimentCommit": options["--experiment-commit"],
             "experimentTree": options["--experiment-tree"],
             "bootUUID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
             "identityValidated": True, "nativeInputExecuted": False, "settingsChanged": False,
             "applicationLaunchRequested": False, "recordingRequested": False,
             "windowSeconds": 15 * scale, "machTimebaseNumer": 1, "machTimebaseDenom": 1,
             "translationProbe": {"returnCode": 0, "errno": 0, "value": 0},
             "nativeStartClock": start, "readinessClock": ready_clock, "notification": notification}
    if scenario == "helper-invalid-ready":
        ready["pid"] += 1
    ready_raw = fixture_publish(options["--ready"], ready)
    fixture_event("helper-ready")
    if scenario == "helper-exit-early":
        time.sleep(.2 * scale)
        return 9
    deadline = start["machContinuousBefore"] / 1e9 + 15 * scale
    while not abort and time.monotonic() < deadline:
        time.sleep(.005)
    closed = synthetic_native_clock()
    completed = synthetic_native_clock()
    final = copy.deepcopy(ready)
    final.update(kind="d24-recorder-progress-complete", completionClock=completed,
                 readyReceiptSHA256=hashlib.sha256(ready_raw).hexdigest(),
                 readyReceiptBytes=len(ready_raw), reason="cooperative-abort" if abort else "window-complete",
                 normalWindowCompleted=not abort, cooperativeAbortObserved=abort,
                 finalIdentityMatches=True, exitCode=143 if abort else 0,
                 elapsedSeconds=(completed["machContinuousAfter"] - start["machContinuousBefore"]) / 1e9)
    final["notification"].update(receivedCount=1 if callback else 0,
                                  firstReceivedToken=17 if callback else None,
                                  firstReceivedClock=callback, countOverflow=False,
                                  callbackClockFailed=False, cancelStatus=0, cancelled=True,
                                  closedClock=closed)
    fixture_publish(options["--completion"], final)
    fixture_event("helper-complete", aborted=abort)
    return 143 if abort else 0


def synthetic_child(role, argv):
    """Run only test fixture roles; this dispatcher cannot invoke Apple tools."""
    scenario = os.environ.get("LEMULIP_D24_SYNTHETIC_SCENARIO", "normal")
    scale = float(os.environ["LEMULIP_D24_TEST_SCALE"])
    fixture_event("child-start", role=role)
    if role == "owned-group-snapshot":
        for row in json.loads(os.environ["LEMULIP_D24_SYNTHETIC_GROUP_ROWS"]):
            print(" ".join(map(str, row)), flush=True)
        return 0
    if role == "closed-stream-descendant":
        stopped = False

        def stop_descendant(_signum, _frame):
            nonlocal stopped
            stopped = True

        signal.signal(signal.SIGTERM, stop_descendant)
        fixture_publish(os.environ["LEMULIP_D24_SYNTHETIC_DESCENDANT_READY"],
                        {"pid": os.getpid(), "pgid": os.getpgrp()})
        hard_end = time.monotonic() + 10
        while (not stopped and not Path(os.environ["LEMULIP_D24_SYNTHETIC_DESCENDANT_STOP"]).exists()
               and time.monotonic() < hard_end):
            time.sleep(.005)
        fixture_publish(os.environ["LEMULIP_D24_SYNTHETIC_DESCENDANT_EXIT"],
                        {"pid": os.getpid(), "termObserved": stopped})
        return 0
    if role == "helper":
        return synthetic_helper(argv, scenario, scale)
    if role == "record":
        while True:
            time.sleep(1)
    if role in ("primary-sample", "secondary-sample"):
        target = int(argv[1])
        report_path = Path(argv[argv.index("-file") + 1])
        banner = (f"Sampling process {target} for 1 second with 10 milliseconds of run time between samples\n").encode()
        if role == "primary-sample":
            if scenario == "closed-stream-descendant":
                subprocess.Popen((sys.executable, "-u", str(Path(__file__).resolve()),
                                  "--synthetic-child", "closed-stream-descendant", "[]"),
                                 stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                 stderr=subprocess.DEVNULL)
                until(lambda: Path(os.environ["LEMULIP_D24_SYNTHETIC_DESCENDANT_READY"]).exists())
                return 0
            if scenario == "wrong-banner":
                banner = banner.replace(str(target).encode(), str(target + 1000000).encode(), 1)
            if scenario == "duplicate-banner":
                banner += banner
            if scenario == "chunked-banner":
                os.write(2, banner[:-1])
                fixture_event("primary-incomplete-banner")
                time.sleep(.7 * scale)
                fixture_event("primary-complete-banner")
                os.write(2, banner[-1:])
            elif scenario != "no-banner":
                fixture_event("primary-complete-banner")
                os.write(2, banner)
            if scenario == "primary-exit-early":
                return 0
            if scenario == "primary-file-too-large":
                with report_path.open("xb") as handle:
                    handle.truncate(progress.REPORT_LIMIT + 1)
            if scenario == "primary-file-symlink":
                report_path.symlink_to(Path(os.environ["LEMULIP_D24_SYNTHETIC_PROVENANCE"]))
            while True:
                time.sleep(1)
        if scenario == "secondary-hangs":
            signal.signal(signal.SIGTERM, signal.SIG_IGN)
            os.write(2, banner)
            while True:
                time.sleep(1)
        architecture = os.environ["LEMULIP_D24_SYNTHETIC_ARCHITECTURE"]
        raw = synthetic_report(pid=target, parent=int(os.environ["LEMULIP_D24_SYNTHETIC_PARENT"]),
                               code_type="ARM64E (Native)" if architecture == "arm64" else "X86-64 (Native)")
        if scenario == "secondary-bad-report":
            raw = raw.replace(SAMPLE_UUID.encode(), SECOND_UUID.encode())
        with report_path.open("xb") as handle:
            handle.write(raw)
        os.write(2, banner + b"Sampling completed, processing symbols...\n"
                 + f"Sample analysis of process {target} written to file {report_path}\n".encode())
        fixture_event("secondary-report-written")
        return 0
    if role in ("recorder-before", "primary-before", "primary-after"):
        # Metadata rows are explicit synthetic data about real owned child PIDs.
        target = int(argv[argv.index("-p") + 1])
        parent = int(os.environ["LEMULIP_D24_SYNTHETIC_PARENT"])
        if scenario == "primary-before-foreign-parent" and role == "primary-before":
            parent += 1000000
        start = "Mon Nov  9 12:00:00 2026"
        if scenario == "primary-after-mixed-instance" and role == "primary-after":
            start = "Mon Nov  9 12:00:01 2026"
        print(f"{target} {parent} {target} {os.geteuid()} {start} S synthetic-fixture synthetic-argv", flush=True)
        if scenario == "primary-exit-during-before" and role == "primary-before":
            os.kill(target, signal.SIGTERM)
        return 0
    raise ValueError("Unknown synthetic fixture role: " + role)


class SyntheticOrchestrationTests(unittest.TestCase):
    """Real processes and cleanup with clearly synthetic native/report fields."""
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="d24-portable-")
        self.root = Path(self.directory.name).resolve(strict=True)
        self.output = self.root / "output"
        self.sources = self.output / "sources"
        self.sources.mkdir(parents=True)
        self.helper = self.root / "SyntheticNotifyHelper"
        self.helper.write_bytes(b"Explicit synthetic helper identity bytes, not executable native code.\n")
        self.helper.chmod(0o700)
        self.sample_tool = self.root / "SyntheticSampleTool"
        self.architecture = "arm64" if platform.machine() in ("arm64", "aarch64") else "x86_64"
        cpu, subtype = (0x0100000C, 2) if self.architecture == "arm64" else (0x01000007, 8)
        self.sample_tool.write_bytes(synthetic_macho(cpu=cpu, subtype=subtype))
        source = Path(__file__).parent / "native_ui" / "NativeRecorderProgressNotify.c"
        source_raw = source.read_bytes()
        (self.sources / source.name).write_bytes(source_raw)
        source_hash = hashlib.sha256(source_raw).hexdigest()
        helper_raw = self.helper.read_bytes()
        self.provenance_value = {
            "schema": 1, "diagnostic": "D24-recorder-progress-observation",
            "experimentCommit": "a" * 40, "experimentTree": "b" * 40,
            "architecture": self.architecture, "sourceSHA256": source_hash,
            "frozenCandidate": {"commit": "d821d7343675e2850705d141ef9b3b93a6aee945",
                                "tree": "425baa28f00ec24551dd70c0cc874a75fa3be0c1"},
            "dependencyBase": "c1844a1ecb1650336d2cd584d23e2c3c6ed33a29",
            "helper": {"path": str(self.helper), "bytes": len(helper_raw),
                       "sha256": hashlib.sha256(helper_raw).hexdigest(), "uuid": SECOND_UUID,
                       "architecture": self.architecture, "architectures": [self.architecture]},
            "sampleTool": {"path": str(self.sample_tool),
                           **tool_identity.inspect_tool(self.sample_tool.read_bytes(), self.architecture)},
            "retainedDiagnosticSourcesSHA256": {source.name: source_hash},
        }
        self.provenance = self.root / "synthetic-provenance.json"
        fixture_publish(self.provenance, self.provenance_value)
        self.events_path = self.root / "events.jsonl"
        self.descendant_ready = self.root / "descendant-ready.json"
        self.descendant_exit = self.root / "descendant-exit.json"
        self.descendant_stop = self.root / "descendant-stop"
        self.children = []
        self.launches = []
        self.scenario = "normal"
        self.scale = .2
        self.fail_factory_name = None

    def factory(self, name, argv, *, cwd, env, limit):
        self.launches.append({"name": name, "argv": tuple(argv), "monotonic": time.monotonic(),
                              "uncollectedRoles": [role for role, transport in self.children
                                                   if transport.process is not None
                                                   and transport.process.returncode is None]})
        if name == self.fail_factory_name:
            raise RuntimeError("Injected synthetic late observer factory failure")
        env = dict(env)
        env.update(LEMULIP_D24_SYNTHETIC_SCENARIO=self.scenario,
                   LEMULIP_D24_SYNTHETIC_EVENTS=str(self.events_path),
                   LEMULIP_D24_SYNTHETIC_PROVENANCE=str(self.provenance),
                   LEMULIP_D24_SYNTHETIC_ARCHITECTURE=self.architecture,
                   LEMULIP_D24_SYNTHETIC_PARENT=str(os.getpid()),
                   LEMULIP_D24_SYNTHETIC_DESCENDANT_READY=str(self.descendant_ready),
                   LEMULIP_D24_SYNTHETIC_DESCENDANT_EXIT=str(self.descendant_exit),
                   LEMULIP_D24_SYNTHETIC_DESCENDANT_STOP=str(self.descendant_stop))
        if name in ("owned-groups", "owned-groups-after-cleanup"):
            # This executor's /proc is outside its PID namespace, so native ps
            # cannot enumerate it. These explicitly synthetic ps rows reflect
            # real non-reaping waitid states of this test's actual children.
            rows = [(os.getpid(), os.getpgrp(), "S")]
            for _role, previous in self.children:
                child = previous.process
                if child is None or child.returncode is not None:
                    continue
                observed = os.waitid(os.P_PID, child.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)
                rows.append((child.pid, child.pid, "Z" if observed is not None else "S"))
            if self.descendant_ready.exists():
                descendant = json.loads(self.descendant_ready.read_text())
                rows.append((descendant["pid"], descendant["pgid"],
                             "Z" if self.descendant_exit.exists() else "S"))
            env["LEMULIP_D24_SYNTHETIC_GROUP_ROWS"] = json.dumps(rows)
            actual = (sys.executable, "-u", str(Path(__file__).resolve()),
                      "--synthetic-child", "owned-group-snapshot", json.dumps(argv))
        elif name in ("recorder-before", "primary-before", "primary-after"):
            # A short row writer avoids charging test-module import time to the
            # original half-second ps normal budget when it is scaled down.
            target = int(argv[argv.index("-p") + 1])
            parent = os.getpid() + (1000000 if self.scenario == "primary-before-foreign-parent"
                                   and name == "primary-before" else 0)
            start = ("Mon Nov  9 12:00:01 2026" if self.scenario == "primary-after-mixed-instance"
                     and name == "primary-after" else "Mon Nov  9 12:00:00 2026")
            row = f"{target} {parent} {target} {os.geteuid()} {start} S synthetic-fixture synthetic-argv\n"
            code = "import os,signal,sys; sys.stdout.write(sys.argv[1]); sys.stdout.flush()"
            if self.scenario == "primary-exit-during-before" and name == "primary-before":
                code += "; os.kill(int(sys.argv[2]),signal.SIGTERM)"
            actual = (sys.executable, "-u", "-c", code, row, str(target))
        else:
            actual = (sys.executable, "-u", str(Path(__file__).resolve()),
                      "--synthetic-child", name, json.dumps(argv))
        transport = progress.startup.MonitoredCommand(actual, cwd=cwd, env=env, limit=limit)
        self.children.append((name, transport))
        if name == "primary-sample" and self.scenario == "primary-exit-early":
            # Deliver the still-buffered banner only after the real kernel has
            # observed exit, so this tests a known exit rather than a race with
            # interpreter shutdown after stderr.write(). WNOWAIT retains PID.
            until(lambda: os.waitid(os.P_PID, transport.process.pid,
                                   os.WEXITED | os.WNOHANG | os.WNOWAIT) is not None)
        return transport

    def tearDown(self):
        # The grandchild has a cooperative test-only marker as a fallback, so
        # even a broken implementation/assertion cannot leak it or signal a
        # potentially reused PID after its parent lease has been released.
        self.descendant_stop.touch()
        for _name, transport in self.children:
            child = transport.process
            if child is not None and child.returncode is None:
                try:
                    os.waitid(os.P_PID, child.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)
                except ChildProcessError:
                    pass
                else:
                    try:
                        os.killpg(child.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    child.wait(timeout=2)
            transport.close()
        if self.descendant_ready.exists():
            until(lambda: self.descendant_exit.exists(), timeout=1)
            descendant = json.loads(self.descendant_ready.read_text())
            try:
                os.waitpid(descendant["pid"], os.WNOHANG)
            except ChildProcessError:
                pass
        self.directory.cleanup()

    def execute(self, scenario="normal"):
        self.scenario = scenario
        before = time.monotonic()
        returned = progress.run(self.helper, self.output, self.provenance,
                                test_hooks=progress.TestHooks(factory=self.factory, scale=self.scale))
        self.elapsed = time.monotonic() - before
        self.result = json.loads((self.output / "recorder-progress-observation.json").read_text())
        self.returned = returned
        return self.result

    def names(self):
        return [entry["name"] for entry in self.launches]

    def command(self, name):
        matching = [transport for role, transport in self.children if role == name]
        self.assertEqual(len(matching), 1, name)
        return matching[0]

    def assert_children_collected(self):
        self.assertTrue(self.children)
        for name, transport in self.children:
            with self.subTest(child=name):
                self.assertIsNotNone(transport.process.returncode)
                self.assertTrue(transport.closed)
                with self.assertRaises(ChildProcessError):
                    os.waitid(os.P_PID, transport.process.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)

    def test_one_nested_observation_preserves_real_pid_leases_and_fixed_argv(self):
        result = self.execute()
        self.assertEqual(result["evidenceKind"], "synthetic-portable-test")
        self.assertTrue(result["samplerStackQualified"], result.get("errors"))
        self.assertTrue(result["diagnosticExecutionComplete"], result.get("errors"))
        self.assertTrue(result["cleanupComplete"], result.get("errors"))
        roles = self.names()
        for name in ("helper", "record", "recorder-before", "primary-sample", "primary-before",
                     "secondary-sample", "primary-after"):
            self.assertEqual(roles.count(name), 1, roles)
        for target_role, sample_role in (("record", "primary-sample"),
                                         ("primary-sample", "secondary-sample")):
            launch = next(entry for entry in self.launches if entry["name"] == sample_role)
            self.assertEqual(launch["argv"][:6],
                             ("/usr/bin/sample", str(self.command(target_role).process.pid),
                              "1", "10", "-mayDie", "-file"))
            self.assertIn(target_role, launch["uncollectedRoles"])
        for role in ("primary-before", "primary-after"):
            launch = next(entry for entry in self.launches if entry["name"] == role)
            self.assertIn("primary-sample", launch["uncollectedRoles"])
        primary = self.command("primary-sample")
        self.assertEqual(primary.receipt["normalOperationBudgetSeconds"], 3.5 * self.scale)
        self.assertEqual(primary.receipt["totalBudgetSeconds"], 4 * self.scale)
        self.assertGreaterEqual(primary.receipt["signals"][0]["afterSeconds"], 3.5 * self.scale)
        self.assertLess(primary.receipt["signals"][0]["afterSeconds"], 4 * self.scale)
        ready_raw = (self.output / "helper-ready.json").read_bytes()
        ready, completion = json.loads(ready_raw), json.loads((self.output / "helper-completion.json").read_text())
        invalid = copy.deepcopy(completion)
        closed = invalid["notification"]["closedClock"]
        shift = int(7 * self.scale * 1e9)
        for key in ("machAbsoluteBefore", "machAbsoluteAfter", "machContinuousBefore", "machContinuousAfter"):
            closed[key] -= shift
        closed["systemUptime"] -= shift / 1e9
        helper = self.command("helper")
        with self.assertRaises(progress.EvidenceError):
            progress.validate_completion(invalid, ready=ready, ready_raw=ready_raw,
                command=SimpleNamespace(pid=helper.process.pid, terminal=True, receipt=helper.receipt),
                provenance=self.provenance_value, nonce=result["nonce"], window=15 * self.scale)
        self.assert_children_collected()

    def test_incomplete_banner_cannot_launch_metadata_until_newline_arrives(self):
        result = self.execute("chunked-banner")
        self.assertTrue(result["samplerStackQualified"], result.get("errors"))
        events = [json.loads(line) for line in self.events_path.read_text().splitlines()]
        incomplete = next(event["monotonic"] for event in events if event["event"] == "primary-incomplete-banner")
        complete = next(event["monotonic"] for event in events if event["event"] == "primary-complete-banner")
        before = next(entry["monotonic"] for entry in self.launches if entry["name"] == "primary-before")
        self.assertGreater(complete, incomplete)
        self.assertGreaterEqual(before, complete)
        self.assertEqual(self.names().count("secondary-sample"), 1)
        self.assert_children_collected()

    def test_foreign_banner_never_opens_the_nested_observation_gate(self):
        result = self.execute("wrong-banner")
        self.assertNotIn("primary-before", self.names())
        self.assertNotIn("secondary-sample", self.names())
        self.assertFalse(result["samplerStackQualified"])
        self.assert_children_collected()

    def test_primary_exit_at_banner_does_not_launch_a_pid_directed_observer(self):
        result = self.execute("primary-exit-early")
        self.assertNotIn("primary-before", self.names())
        self.assertNotIn("secondary-sample", self.names())
        self.assertNotIn("primary-after", self.names())
        self.assertFalse(result["samplerStackQualified"])
        self.assert_children_collected()

    def test_target_exit_during_before_snapshot_prevents_secondary_launch(self):
        result = self.execute("primary-exit-during-before")
        self.assertIn("primary-before", self.names())
        self.assertNotIn("secondary-sample", self.names())
        self.assertNotIn("primary-after", self.names())
        self.assertFalse(result["samplerStackQualified"])
        self.assert_children_collected()

    def test_secondary_is_cancelled_by_the_primary_boundary_without_extending_it(self):
        result = self.execute("secondary-hangs")
        self.assertFalse(result["samplerStackQualified"])
        primary, secondary = self.command("primary-sample"), self.command("secondary-sample")
        primary_term = primary.started + primary.receipt["signals"][0]["afterSeconds"]
        secondary_term = secondary.started + secondary.receipt["signals"][0]["afterSeconds"]
        self.assertLessEqual(abs(secondary_term - primary_term), .1)
        self.assertLess(primary.receipt["signals"][0]["afterSeconds"], 4 * self.scale)
        self.assertEqual([entry["signal"] for entry in secondary.receipt["signals"]], ["SIGTERM", "SIGKILL"])
        self.assertEqual(self.names().count("secondary-sample"), 1)
        self.assertNotIn("primary-after", self.names())
        self.assert_children_collected()

    def test_after_snapshot_from_another_instance_rejects_the_stack(self):
        result = self.execute("primary-after-mixed-instance")
        self.assertEqual(self.names().count("primary-after"), 1)
        self.assertFalse(result["samplerStackQualified"])
        self.assert_children_collected()

    def test_bad_before_identity_prevents_secondary_launch(self):
        result = self.execute("primary-before-foreign-parent")
        self.assertNotIn("secondary-sample", self.names())
        self.assertFalse(result["samplerStackQualified"])
        self.assert_children_collected()

    def test_early_helper_exit_stops_the_unit_before_any_sampler(self):
        result = self.execute("helper-exit-early")
        self.assertNotIn("primary-sample", self.names())
        self.assertNotIn("secondary-sample", self.names())
        self.assertFalse(result["diagnosticExecutionComplete"])
        self.assert_children_collected()

    def test_invalid_helper_ready_identity_prevents_recorder_launch(self):
        result = self.execute("helper-invalid-ready")
        self.assertNotIn("record", self.names())
        self.assertNotIn("primary-sample", self.names())
        self.assertFalse(result["diagnosticExecutionComplete"])
        self.assert_children_collected()

    def test_late_observer_exception_cleans_existing_children_and_late_group_checker(self):
        self.fail_factory_name = "primary-after"
        result = self.execute()
        self.assertIn("secondary-sample", self.names())
        self.assertIn("owned-groups", self.names())
        self.assertFalse(result["diagnosticExecutionComplete"])
        self.assertEqual(self.command("helper").process.returncode, 143)
        complete = json.loads((self.output / "helper-completion.json").read_text())
        self.assertTrue(complete["cooperativeAbortObserved"])
        self.assertFalse(complete["normalWindowCompleted"])
        self.assert_children_collected()

    def test_failed_nonreaping_capability_starts_no_native_role(self):
        with mock.patch.object(progress, "waitid_preflight", side_effect=progress.EvidenceError("synthetic failed capability")):
            try:
                self.execute()
            except progress.EvidenceError:
                pass
        self.assertEqual(self.launches, [])

    def test_early_notification_callback_does_not_shorten_the_helper_window(self):
        result = self.execute("early-callback")
        self.assertTrue(result["diagnosticExecutionComplete"], result.get("errors"))
        final = json.loads((self.output / "helper-completion.json").read_text())
        self.assertEqual(final["notification"]["receivedCount"], 1)
        self.assertLess(final["notification"]["firstReceivedClock"]["machContinuousAfter"],
                        final["notification"]["registrationAfterClock"]["machContinuousBefore"])
        self.assertTrue(final["normalWindowCompleted"])
        self.assertGreaterEqual(final["elapsedSeconds"], 15 * self.scale)
        self.assertEqual(self.names().count("primary-sample"), 1)
        self.assertEqual(self.names().count("secondary-sample"), 1)
        self.assert_children_collected()

    def test_oversized_primary_file_stops_the_observation_with_bounded_retention(self):
        result = self.execute("primary-file-too-large")
        self.assertFalse(result["diagnosticExecutionComplete"])
        self.assertFalse(result["samplerStackQualified"])
        self.assert_children_collected()

    def test_primary_file_symlink_cannot_be_read_as_a_sampler_report(self):
        result = self.execute("primary-file-symlink")
        self.assertFalse(result["diagnosticExecutionComplete"])
        self.assertFalse(result["samplerStackQualified"])
        self.assert_children_collected()

    def test_closed_stream_descendant_is_stopped_before_primary_pid_collection(self):
        result = self.execute("closed-stream-descendant")
        first = next(entry for entry in self.launches if entry["name"] == "owned-groups")
        self.assertIn("primary-sample", first["uncollectedRoles"])
        self.assertTrue(self.descendant_ready.exists())
        self.assertTrue(self.descendant_exit.exists(), result.get("errors"))
        self.assertTrue(json.loads(self.descendant_exit.read_text())["termObserved"])
        self.assertIn("owned-groups-after-cleanup", self.names())
        final = next(entry for entry in self.launches if entry["name"] == "owned-groups-after-cleanup")
        self.assertIn("primary-sample", final["uncollectedRoles"])
        self.assertTrue(result["cleanupComplete"], result.get("errors"))
        self.assertFalse(result["diagnosticExecutionComplete"])
        self.assertTrue(result["errors"])
        self.assert_children_collected()

    def test_one_collection_exception_does_not_skip_other_children_or_summary(self):
        real_collect = progress.OwnedCommand.collect
        injected = []

        def collect_then_fail(command):
            code = real_collect(command)
            if command.name == "secondary-sample":
                injected.append(command.name)
                raise progress.EvidenceError("synthetic exception after actual child collection")
            return code

        with mock.patch.object(progress.OwnedCommand, "collect", new=collect_then_fail):
            result = self.execute()
        self.assertEqual(injected, ["secondary-sample"])
        self.assertFalse(result["cleanupComplete"])
        self.assertFalse(result["diagnosticExecutionComplete"])
        self.assertTrue(any("secondary-sample: child collection failed" in value for value in result["errors"]))
        self.assertEqual(set(result["commands"]), set(self.names()))
        self.assert_children_collected()


class FixturePathIdentityTests(unittest.TestCase):
    def test_symlinked_temporary_parent_uses_canonical_paths_before_provenance(self):
        real_temporary_directory = tempfile.TemporaryDirectory
        with real_temporary_directory(prefix="d24-path-alias-") as temporary:
            parent = Path(temporary).resolve(strict=True)
            actual = parent / "real-parent"
            actual.mkdir()
            alias = parent / "linked-parent"
            alias.symlink_to(actual, target_is_directory=True)

            def through_alias(*args, **kwargs):
                return real_temporary_directory(*args, dir=alias, **kwargs)

            fixture = SyntheticOrchestrationTests()
            with mock.patch.object(tempfile, "TemporaryDirectory", side_effect=through_alias):
                fixture.setUp()
            try:
                self.assertNotEqual(Path(fixture.directory.name), fixture.root)
                provenance, _ = progress.validate_inputs(
                    fixture.helper.resolve(strict=True), fixture.output.resolve(strict=True),
                    fixture.provenance.resolve(strict=True), synthetic=True)
                self.assertEqual(provenance["helper"]["path"], str(fixture.helper.resolve(strict=True)))
                self.assertEqual(provenance["sampleTool"]["path"], str(fixture.sample_tool.resolve(strict=True)))
                self.assertEqual(fixture.launches, [])
            finally:
                fixture.tearDown()


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "--synthetic-child":
        raise SystemExit(synthetic_child(sys.argv[2], json.loads(sys.argv[3])))
    unittest.main()
