#!/usr/bin/env python3
"""D29 real Python-process integration; never invokes an Apple trace tool.

The delayed metadata fixture waits in a Python callback after the real worker
has emitted its operation-start witness. It models pending work; it does not
claim a kernel stall or reproduce D27's unidentified native delay.

Group-enumeration responses are explicitly synthetic: the fixture lists only
its retained direct children, using their real non-reaping waitid status and
process-group identity. This proves both child leases and collection behavior,
not an OS-wide process-group census. The production /bin/ps gate is unchanged.
"""
from __future__ import annotations

import hashlib
import os
from pathlib import Path
import signal
import sys
import tempfile
import time
import unittest
from unittest import mock
import zipfile

import native_retained_atrc_isolated as subject
import native_retained_atrc_output as legacy


@unittest.skipUnless(hasattr(os, "waitid") and hasattr(os, "WNOWAIT"),
                     "Requires non-reaping POSIX child status")
class IsolatedIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name).resolve(strict=True)
        self.guard = legacy.OutputGuard(self.root / "observed")
        self.transports = []
        self.launches = []
        self.probe_observations = []
        self.descriptor_transport = subject.DescriptorTransport
        self.worker_patch = mock.patch.object(subject, "DescriptorTransport",
                                              side_effect=self.worker_transport)
        self.worker_patch.start()
        self.witness = {"evidenceKind": "real-python-process-synthetic-fixture",
                        "groupEnumeration": "synthetic-direct-owned-child-list",
                        "groupProbeObservations": self.probe_observations}

    def tearDown(self):
        self.worker_patch.stop()
        # Only Popen objects directly created and retained by this fixture are
        # eligible. ECHILD revokes the numeric PID/PGID before any signal.
        for transport in self.transports:
            child = transport.process
            if child is None or child.returncode is not None:
                transport.close()
                continue
            try:
                os.waitid(os.P_PID, child.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)
            except ChildProcessError:
                transport.close()
                continue
            try:
                os.killpg(child.pid, signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                pass
            child.wait(timeout=1)
            transport.close()
        self.guard.close()
        self.temporary.cleanup()

    def worker_transport(self, *args, **kwargs):
        transport = self.descriptor_transport(*args, **kwargs)
        self.transports.append(transport)
        return transport

    def factory(self, name, argv, *, cwd, env, limit):
        self.launches.append({"name": name, "argv": argv})
        if argv[0] == "/bin/ps":
            rows = [(os.getpid(), os.getpgrp(), "S")]
            observed = []
            for previous in self.transports:
                child = previous.process
                if child is None or child.returncode is not None:
                    continue
                status = os.waitid(os.P_PID, child.pid,
                                   os.WEXITED | os.WNOHANG | os.WNOWAIT)
                pgid = os.getpgid(child.pid)
                rows.append((child.pid, pgid, "Z" if status is not None else "S"))
                observed.append({"pid": child.pid, "pgid": pgid,
                                 "waitable": status is not None,
                                 "returncodeBeforeProbe": child.returncode})
            self.probe_observations.append({"name": name, "children": observed})
            inventory = "".join(" ".join(map(str, row)) + "\n" for row in rows)
            argv = (sys.executable, "-c", "import sys;sys.stdout.write(sys.argv[1])", inventory)
        transport = subject.progress.startup.MonitoredCommand(argv, cwd=cwd, env=env, limit=limit)
        self.transports.append(transport)
        return transport

    def worker(self, patch):
        path = self.root / "fixture_worker.py"
        path.write_text("import os, sys, time\nfrom pathlib import Path\n"
                        + "sys.path.insert(0, " + repr(str(Path(__file__).resolve().parent)) + ")\n"
                        + "import native_retained_atrc_worker as worker\n"
                        + patch + "\nraise SystemExit(worker.main())\n")
        return path

    def delayed_worker(self):
        marker = self.root / "metadata-entered"
        script = self.worker(
            "original_stat = worker.REAL_STAT\n"
            "def delayed_stat(path, **kwargs):\n"
            "    if path == 'stall.bin':\n"
            "        Path(" + repr(str(marker)) + ").write_text(str(time.monotonic_ns()))\n"
            "        time.sleep(2)\n"
            "    return original_stat(path, **kwargs)\n"
            "worker.REAL_STAT = delayed_stat\n")
        return script, marker

    def run_capture(self, code, *, worker=None, budget=1.5, reserve=.5, factory=None):
        started = time.monotonic()
        with mock.patch.object(self.guard, "_scan",
                               side_effect=AssertionError("Parent census during capture is forbidden")):
            result = subject.capture_isolated(
                "synthetic-target", (sys.executable, "-u", "-c", code),
                cwd=self.guard.root, env=dict(os.environ), guard=self.guard,
                test_factory=factory or self.factory, test_budget=budget,
                test_reserve=reserve, test_worker_script=worker)
        self.assertLess(time.monotonic() - started, 5,
                        "Each fixture must complete without an unbounded wait")
        self.witness["result"] = result.receipt
        return result

    def assert_collected(self, result):
        for name, receipt in (("synthetic-target", result.receipt["target"]),
                              ("output-observer", result.receipt["worker"])):
            self.assertIsNotNone(receipt)
            self.assertTrue(receipt["pidLeaseAcquired"])
            self.assertTrue(receipt["exitObservedWithoutReap"])
            self.assertTrue(receipt["pidLeaseReleased"])
            self.assertFalse(receipt["pidLeaseLost"])
            group = result.receipt["finalOwnedGroups"][name]
            self.assertTrue(group["pidLeaseHeldAtSnapshot"])
            self.assertTrue(group["noLiveMembersObserved"])
        self.assertTrue(all(t.process is None or t.process.returncode is not None
                            for t in self.transports))
        for receipt in (result.receipt["target"], result.receipt["worker"]):
            self.assertTrue(any(row["pid"] == receipt["pid"] and row["waitable"]
                                and row["returncodeBeforeProbe"] is None
                                for snapshot in self.probe_observations
                                for row in snapshot["children"]),
                            "Both leases must remain unreaped through the group snapshot")

    def test_success_has_fresh_final_generation_both_leases_and_exact_archive(self):
        payload = b"verified synthetic output\n" * 5
        result = self.run_capture(
            "from pathlib import Path; p=Path('derived.trace'); p.mkdir(); "
            "(p/'payload.bin').write_bytes(" + repr(payload) + "); print('finished')")
        self.assertTrue(result.receipt["transportComplete"], result.receipt["errors"])
        self.assertTrue(result.receipt["observationComplete"])
        self.assertTrue(result.receipt["cleanupComplete"])
        self.assertTrue(result.receipt["finalFreshScanComplete"])
        final_generation = result.receipt["finalScanGeneration"]
        self.assertGreater(final_generation, result.receipt["initialScanGeneration"])
        final = next(row for row in result.receipt["observer"]["scanHistory"]["records"]
                     if row["request"]["scan"] == final_generation)
        self.assertGreaterEqual(final["request"]["dispatchedNS"],
                                result.receipt["target"]["operationDoneClock"]["monotonicAfterNS"])
        self.assertEqual(b"finished\n", result.streams["stdout"])
        self.assert_collected(result)
        archive = self.root / "retained.zip"
        retained = result.finalize(archive)
        self.assertTrue(retained["retentionComplete"])
        self.assertTrue(retained["newAnalysisDocumentObserved"])
        self.assertFalse(retained["semanticAnalysisValidityEstablished"])
        with zipfile.ZipFile(archive) as bundle:
            self.assertEqual(payload, bundle.read("derived-output/derived.trace/payload.bin"))
            self.assertIsNone(bundle.testzip())
        self.assertEqual(hashlib.sha256(archive.read_bytes()).hexdigest(), retained["archive"]["sha256"])
        self.assertEqual(payload, (self.guard.target / "payload.bin").read_bytes())

    def test_natural_nonzero_exit_retains_transport_outcome_without_inventing_output(self):
        result = self.run_capture("print('refused'); raise SystemExit(7)")
        self.assertEqual(7, result.receipt["target"]["exitCode"])
        self.assertTrue(result.receipt["transportComplete"], result.receipt["errors"])
        self.assert_collected(result)
        retained = result.finalize(self.root / "absent.zip")
        self.assertEqual("no-output", retained["status"])
        self.assertFalse(retained["newAnalysisDocumentObserved"])

    def test_preexit_census_cannot_replace_a_pending_fresh_final_scan(self):
        live_census = self.root / "live-census-completed"
        final_requested = self.root / "final-scan-requested"
        script = self.worker(
            "original_scan = worker.perform_scan\n"
            "def reported_scan(guard, writer, scan, deadline_ns):\n"
            "    passed = original_scan(guard, writer, scan, deadline_ns)\n"
            "    if passed and scan >= 2:\n"
            "        Path(" + repr(str(live_census)) + ").write_text(str(scan))\n"
            "    return passed\n"
            "worker.perform_scan = reported_scan\n"
            "original_stat = worker.REAL_STAT\n"
            "def pending_final(path, **kwargs):\n"
            "    if path == 'payload.bin' and Path(" + repr(str(final_requested)) + ").exists():\n"
            "        time.sleep(2)\n"
            "    return original_stat(path, **kwargs)\n"
            "worker.REAL_STAT = pending_final\n")
        target_transport = None
        def capture_target(name, argv, **options):
            nonlocal target_transport
            transport = self.factory(name, argv, **options)
            if name == "synthetic-target":
                target_transport = transport
            return transport
        original_dispatch = subject.ObserverState.dispatch
        def mark_postexit_request(state, *args, **kwargs):
            message = original_dispatch(state, *args, **kwargs)
            if target_transport is not None and target_transport.receipt["operationDoneClock"] is not None:
                # Instrument an actual post-operation dispatch, without
                # changing its message, deadline, or parent state transition.
                final_requested.write_text(str(message["scan"]))
            return message
        with mock.patch.object(subject.ObserverState, "dispatch", new=mark_postexit_request):
            result = self.run_capture(
                "from pathlib import Path\nimport time\n"
                "p=Path('derived.trace'); p.mkdir(); (p/'payload.bin').write_bytes(b'present')\n"
                "marker=Path(" + repr(str(live_census)) + ")\n"
                "deadline=time.monotonic()+1\n"
                "while not marker.exists() and time.monotonic()<deadline: time.sleep(.002)\n"
                "assert marker.exists(), 'No completed live census'\n",
                worker=script, factory=capture_target)
        receipt = result.receipt
        self.assertEqual(0, receipt["target"]["exitCode"])
        completed_live = int(live_census.read_text())
        self.assertGreaterEqual(completed_live, 2)
        self.assertGreater(receipt["finalScanGeneration"], completed_live)
        self.assertEqual(receipt["finalScanGeneration"], int(final_requested.read_text()))
        self.assertFalse(receipt["finalFreshScanComplete"])
        pending = receipt["observer"]["failure"]["pendingOperation"]
        self.assertEqual(receipt["finalScanGeneration"], pending["scan"])
        self.assertEqual("derived.trace/payload.bin", pending["path"])
        self.assertFalse(receipt["transportComplete"])
        self.assert_collected(result)
        with mock.patch.object(self.guard, "_scan", side_effect=AssertionError("Final census gate failed")):
            retained = result.finalize(self.root / "not-qualified.zip")
        self.assertFalse(retained["retentionComplete"])
        self.assertFalse((self.root / "not-qualified.zip").exists())

    def test_nonempty_startup_census_prevents_target_launch(self):
        (self.guard.root / "existing.bin").write_bytes(b"preserved")
        result = self.run_capture("raise AssertionError('Target must not launch')")
        self.assertFalse(result.receipt["startupComplete"])
        self.assertIsNone(result.receipt["target"])
        self.assertFalse(any(row["name"] == "synthetic-target" for row in self.launches))
        self.assertIn("not empty", result.receipt["observer"]["failure"]["error"])
        self.assertEqual(b"preserved", (self.guard.root / "existing.bin").read_bytes())

    def test_ready_without_completed_empty_census_does_not_launch_target(self):
        script = self.worker(
            "def pending(guard, writer, scan, deadline_ns):\n"
            "    writer.emit('scan_started', scan)\n"
            "    time.sleep(2)\n"
            "    return False\n"
            "worker.perform_scan = pending\n")
        result = self.run_capture("raise AssertionError('No empty census')", worker=script)
        self.assertTrue(result.receipt["observer"]["ready"])
        self.assertFalse(result.receipt["startupComplete"])
        self.assertIsNone(result.receipt["target"])
        self.assertIn("dispatch budget", result.receipt["observer"]["failure"]["error"])
        self.assertFalse(any(row["name"] == "synthetic-target" for row in self.launches))

    def test_malformed_worker_report_is_retained_as_first_failure(self):
        script = self.worker(
            "def malformed(guard, writer, scan, deadline_ns):\n"
            "    worker.REAL_WRITE(writer.descriptor, b'{\"kind\":\"bad-report\"}\\n')\n"
            "    time.sleep(2)\n"
            "    return False\n"
            "worker.perform_scan = malformed\n")
        result = self.run_capture("raise AssertionError('Malformed observer')", worker=script)
        self.assertFalse(result.receipt["transportComplete"])
        self.assertIsNone(result.receipt["target"])
        first = result.receipt["observer"]["failure"]["error"]
        self.assertIn("Unknown report kind", first)
        self.assertNotIn("startup", first)

    def test_wrong_ready_identity_cannot_authorize_target(self):
        script = self.worker(
            "original_emit = worker.ReportWriter.emit\n"
            "def wrong_root(self, kind, scan, **fields):\n"
            "    if kind == 'ready':\n"
            "        fields['rootIdentity'] = [0, 0, 0]\n"
            "    return original_emit(self, kind, scan, **fields)\n"
            "worker.ReportWriter.emit = wrong_root\n")
        result = self.run_capture("raise AssertionError('Wrong identity')", worker=script)
        self.assertFalse(result.receipt["startupComplete"])
        self.assertIsNone(result.receipt["target"])
        self.assertIn("bind", result.receipt["observer"]["failure"]["error"])

    def test_stalled_metadata_allows_target_stream_and_zero_exit_observation(self):
        script, marker = self.delayed_worker()
        result = self.run_capture(
            "from pathlib import Path\nimport time\n"
            "Path('stall.bin').write_bytes(b'pending')\n"
            "marker=Path(" + repr(str(marker)) + ")\n"
            "deadline=time.monotonic()+1\n"
            "while not marker.exists() and time.monotonic()<deadline: time.sleep(.002)\n"
            "assert marker.exists(), 'Worker never reached metadata operation'\n"
            "print('during-scan', flush=True)\n", worker=script)
        receipt = result.receipt
        pending = receipt["observer"]["failure"]["pendingOperation"]
        self.assertEqual("stat", pending["category"])
        self.assertEqual("stall.bin", pending["path"])
        self.assertEqual(0, receipt["target"]["exitCode"])
        self.assertEqual(b"during-scan\n", result.streams["stdout"])
        failure_ns = receipt["observer"]["failure"]["parentClockNS"]
        observed_ns = receipt["target"]["operationTerminalClock"]["monotonicAfterNS"]
        self.assertGreater(observed_ns, pending["clockNS"])
        self.assertLess(observed_ns, failure_ns)
        self.assertTrue(any(pending["clockNS"] < row["clock"]["monotonicBeforeNS"] < failure_ns
                            for row in receipt["target"]["streamProgress"]))
        self.assertFalse(receipt["observationComplete"])
        self.assertFalse(receipt["transportComplete"])
        self.assert_collected(result)
        with mock.patch.object(self.guard, "_scan", side_effect=AssertionError("Failed gate must not read")):
            retained = result.finalize(self.root / "forbidden.zip")
        self.assertFalse(retained["retentionComplete"])
        self.assertFalse((self.root / "forbidden.zip").exists())

    def test_target_normal_deadline_is_serviced_while_worker_metadata_is_pending(self):
        script, _ = self.delayed_worker()
        result = self.run_capture(
            "from pathlib import Path\nimport time\n"
            "Path('stall.bin').write_bytes(b'pending')\n"
            "print('live', flush=True)\ntime.sleep(2)\n",
            worker=script, budget=.6, reserve=.4)
        receipt = result.receipt
        self.assertEqual("command-budget", receipt["target"]["stopReason"])
        self.assertEqual("SIGTERM", receipt["target"]["signals"][0]["signal"])
        pending = receipt["observer"]["failure"]["pendingOperation"]
        self.assertEqual("stall.bin", pending["path"])
        stop = receipt["target"]["stopRequestedClock"]["monotonicBeforeNS"]
        self.assertGreater(stop, pending["clockNS"])
        self.assertLess(stop, receipt["observer"]["failure"]["parentClockNS"])
        self.assertFalse(receipt["transportComplete"])
        self.assert_collected(result)

    def test_late_collection_does_not_restore_target_total_deadline(self):
        script, _ = self.delayed_worker()
        result = self.run_capture(
            "from pathlib import Path\nimport signal,time\n"
            "signal.signal(signal.SIGTERM, signal.SIG_IGN)\n"
            "Path('stall.bin').write_bytes(b'pending')\n"
            "time.sleep(2)\n", worker=script, budget=.18, reserve=.06)
        receipt = result.receipt
        self.assertEqual("command-budget", receipt["target"]["stopReason"])
        self.assertFalse(receipt["target"]["completionObservedWithinTotalBudget"])
        self.assertGreater(receipt["target"]["totalDeadlineOvershootSeconds"], 0)
        self.assertFalse(receipt["targetCleanupComplete"])
        self.assertFalse(receipt["cleanupComplete"])
        self.assertFalse(receipt["transportComplete"])
        retained = result.finalize(self.root / "late.zip")
        self.assertEqual("skipped-cleanup-incomplete", retained["status"])

    def test_worker_loss_during_pending_operation_preserves_failure_and_cleanup(self):
        script = self.worker(
            "original_stat = worker.REAL_STAT\n"
            "def lost(path, **kwargs):\n"
            "    if path == 'stall.bin': os._exit(9)\n"
            "    return original_stat(path, **kwargs)\n"
            "worker.REAL_STAT = lost\n")
        result = self.run_capture(
            "from pathlib import Path\nimport time\n"
            "Path('stall.bin').write_bytes(b'pending')\ntime.sleep(2)", worker=script)
        self.assertEqual(9, result.receipt["worker"]["exitCode"])
        self.assertIsNotNone(result.receipt["observer"]["failure"])
        self.assertEqual("stall.bin", result.receipt["observer"]["failure"]["pendingOperation"]["path"])
        self.assertFalse(result.receipt["transportComplete"])
        self.assert_collected(result)

    def assert_stopped_worker_cannot_qualify(self, script, *, exit_code, stop_reason):
        result = self.run_capture(
            "from pathlib import Path; p=Path('derived.trace'); p.mkdir(); "
            "(p/'payload.bin').write_bytes(b'complete target output')", worker=script)
        receipt = result.receipt
        self.assertEqual(0, receipt["target"]["exitCode"])
        self.assertTrue(receipt["finalFreshScanComplete"])
        self.assertTrue(receipt["observer"]["stopped"])
        self.assertEqual(exit_code, receipt["worker"]["exitCode"])
        self.assertEqual(stop_reason, receipt["worker"]["stopReason"])
        self.assertTrue(receipt["cleanupComplete"], receipt["errors"])
        self.assert_collected(result)
        self.assertFalse(receipt["observationComplete"],
                         "A stopped report cannot substitute for successful worker termination")
        self.assertFalse(receipt["transportComplete"])
        with mock.patch.object(self.guard, "_scan", side_effect=AssertionError("Worker failed its shutdown gate")):
            retained = result.finalize(self.root / "failed-worker.zip")
        self.witness["retention"] = retained
        self.assertFalse(retained["retentionComplete"])
        self.assertFalse(retained["newAnalysisDocumentObserved"])
        self.assertFalse((self.root / "failed-worker.zip").exists())

    def test_valid_stopped_then_worker_nonzero_exit_cannot_qualify(self):
        script = self.worker(
            "original_main = worker.main\n"
            "def fail_after_acknowledgement():\n"
            "    result = original_main()\n"
            "    return 7 if result == 0 else result\n"
            "worker.main = fail_after_acknowledgement\n")
        self.assert_stopped_worker_cannot_qualify(script, exit_code=7, stop_reason=None)

    def test_valid_stopped_then_worker_requires_term_cannot_qualify(self):
        script = self.worker(
            "original_main = worker.main\n"
            "def wait_after_acknowledgement():\n"
            "    result = original_main()\n"
            "    if result == 0: time.sleep(2)\n"
            "    return result\n"
            "worker.main = wait_after_acknowledgement\n")
        self.assert_stopped_worker_cannot_qualify(
            script, exit_code=-signal.SIGTERM, stop_reason="observer-shutdown")

    def test_unqualified_owned_group_prevents_retention_even_after_exit_zero(self):
        def malformed_probe(name, argv, **options):
            if argv[0] == "/bin/ps":
                argv = (sys.executable, "-c", "print('not a group inventory')")
            return self.factory(name, argv, **options)
        result = self.run_capture("raise SystemExit(0)", factory=malformed_probe)
        self.assertEqual(0, result.receipt["target"]["exitCode"])
        self.assertFalse(result.receipt["cleanupComplete"])
        self.assertFalse(result.receipt["transportComplete"])
        with mock.patch.object(self.guard, "_scan", side_effect=AssertionError("No unsafe final read")):
            retained = result.finalize(self.root / "unsafe.zip")
        self.assertEqual("skipped-cleanup-incomplete", retained["status"])
        self.assertFalse((self.root / "unsafe.zip").exists())

    def test_guard_cannot_start_a_second_observer_or_target(self):
        result = self.run_capture("pass")
        self.assertTrue(result.receipt["transportComplete"], result.receipt["errors"])
        before = len(self.transports)
        with self.assertRaises(subject.progress.EvidenceError):
            self.run_capture("raise AssertionError('Second attempt')")
        self.assertEqual(before, len(self.transports))


if __name__ == "__main__":
    unittest.main()
