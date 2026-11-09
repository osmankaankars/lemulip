#!/usr/bin/env python3
"""Synthetic portable tests of D25 adapter policy, not native trace evidence."""
from __future__ import annotations

import errno
import json
import os
from pathlib import Path
import signal
import sys
import tempfile
import time
import unittest

import native_retained_trace_command as subject
import run_native_system_trace_startup as startup


@unittest.skipUnless(hasattr(os, "waitid") and hasattr(os, "WNOWAIT"), "Requires POSIX non-reaping child status")
class RetainedCommandPolicyTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name).resolve(strict=True)
        self.transports = []
        self.snapshots_while_leased = []
        self.descendant_ready = self.root / "descendant-ready"
        self.descendant_exit = self.root / "descendant-exit"
        self.descendant_stop = self.root / "descendant-stop"

    def tearDown(self):
        self.descendant_stop.touch()
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
        self.temporary.cleanup()

    def factory(self, name, argv, *, cwd, env, limit):
        if name != "synthetic-target" and self.transports:
            target = self.transports[0].process
            witness = os.waitid(os.P_PID, target.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)
            self.snapshots_while_leased.append({"returncode": target.returncode,
                                                "waitable": witness is not None})
            if argv[0] == "/bin/ps":
                # This executor's /proc is outside its PID namespace. As in
                # D24, explicitly synthetic ps rows reflect actual waitid
                # states; native production still invokes installed /bin/ps.
                rows = [(os.getpid(), os.getpgrp(), "S")]
                for previous in self.transports:
                    child = previous.process
                    if child is None or child.returncode is not None:
                        continue
                    observed = os.waitid(os.P_PID, child.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)
                    rows.append((child.pid, child.pid, "Z" if observed is not None else "S"))
                if self.descendant_ready.exists():
                    leaf = json.loads(self.descendant_ready.read_text())
                    rows.append((leaf["pid"], leaf["pgid"], "Z" if self.descendant_exit.exists() else "S"))
                text = "".join(" ".join(map(str, row)) + "\n" for row in rows)
                argv = (sys.executable, "-c", "import sys; sys.stdout.write(sys.argv[1])", text)
        transport = startup.MonitoredCommand(argv, cwd=cwd, env=env, limit=limit)
        self.transports.append(transport)
        return transport

    def capture(self, code, *, factory=None, budget=1.4, reserve=.5, limit=65536):
        return subject.capture_owned(
            "synthetic-target", (sys.executable, "-u", "-c", code),
            cwd=self.root, env=dict(os.environ), budget=budget, reserve=reserve,
            limit=limit, test_factory=factory or self.factory,
        )

    def test_successful_stdout_and_stderr_keep_lease_until_group_inventory(self):
        receipt, streams, cleanup = self.capture("import sys; print('toc'); print('warning', file=sys.stderr)")
        self.assertTrue(receipt["transportComplete"])
        self.assertTrue(receipt["cleanupComplete"])
        self.assertEqual(streams, {"stdout": b"toc\n", "stderr": b"warning\n"})
        self.assertEqual(self.snapshots_while_leased, [{"returncode": None, "waitable": True}])
        self.assertTrue(receipt["pidLeaseReleased"])
        self.assertEqual(len(cleanup), 1)
        self.assertIsInstance(cleanup[0]["streams"]["stdout"], bytes)
        self.assertTrue(receipt["finalOwnedGroups"]["synthetic-target"]["pidLeaseHeldAtSnapshot"])
        self.assertFalse(receipt["descendantExitTimesWithinOperationBudgetEstablished"])

    def test_natural_nonzero_refusal_is_completed_transport(self):
        receipt, streams, cleanup = self.capture(
            "import sys; print('synthetic unreadable input', file=sys.stderr); raise SystemExit(2)")
        self.assertEqual(receipt["exitCode"], 2)
        self.assertIsNone(receipt["stopReason"])
        self.assertTrue(receipt["transportComplete"])
        self.assertTrue(receipt["cleanupComplete"])
        self.assertIn(b"unreadable", streams["stderr"])
        self.assertEqual(len(cleanup), 1)

    def test_timeout_preserves_failure_even_after_clean_collection(self):
        receipt, _, _ = self.capture("import time; print('waiting',flush=True); time.sleep(5)",
                                     budget=1.1, reserve=.5)
        self.assertEqual(receipt["stopReason"], "command-budget")
        self.assertFalse(receipt["transportComplete"])
        self.assertTrue(receipt["cleanupComplete"])
        self.assertTrue(receipt["pidLeaseReleased"])
        self.assertLess(receipt["operationElapsedSeconds"], 1.1)

    def test_output_limit_cannot_be_promoted_to_complete(self):
        receipt, streams, _ = self.capture("import time; print('x'*8192,flush=True); time.sleep(5)", limit=128)
        self.assertEqual(receipt["stopReason"], "output-limit")
        self.assertLessEqual(sum(map(len, streams.values())), 128)
        self.assertFalse(receipt["transportComplete"])
        self.assertTrue(receipt["cleanupComplete"])

    def test_silent_descendant_is_cleaned_without_extending_original_success(self):
        ready = self.descendant_ready
        leaf = ("import json,os,pathlib,signal,time\nstopped=False\n"
                "def stop(sig, frame):\n global stopped\n stopped=True\n"
                "signal.signal(signal.SIGTERM,stop)\n"
                f"pathlib.Path({str(ready)!r}).write_text(json.dumps({{'pid':os.getpid(),'pgid':os.getpgrp()}}))\n"
                "deadline=time.monotonic()+5\n"
                f"while not stopped and not pathlib.Path({str(self.descendant_stop)!r}).exists() and time.monotonic()<deadline: time.sleep(.002)\n"
                f"pathlib.Path({str(self.descendant_exit)!r}).write_text('completed')\n")
        leader = ("import pathlib,subprocess,sys,time; "
                  f"subprocess.Popen([sys.executable,'-u','-c',{leaf!r}],stdin=subprocess.DEVNULL,"
                  "stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL); "
                  f"ready=pathlib.Path({str(ready)!r}); deadline=time.monotonic()+1; "
                  "\nwhile not ready.exists() and time.monotonic()<deadline: time.sleep(.002)\n"
                  "assert ready.exists(); print('leader exits',flush=True)")
        receipt, _, cleanup = self.capture(leader)
        self.assertEqual(receipt["exitCode"], 0)
        self.assertTrue(receipt["emergencyCleanupRequired"])
        self.assertFalse(receipt["transportComplete"])
        self.assertTrue(receipt["cleanupComplete"])
        self.assertEqual(len(cleanup), 2)
        self.assertFalse(receipt["ownedGroupsBeforeEmergencyCleanup"]["synthetic-target"]["noLiveMembersObserved"])
        self.assertTrue(receipt["finalOwnedGroups"]["synthetic-target"]["noLiveMembersObserved"])
        self.assertTrue(all(row["returncode"] is None for row in self.snapshots_while_leased))

    def test_zombie_group_eperm_is_resolved_only_by_positive_inventory(self):
        def factory(name, argv, **kwargs):
            transport = self.factory(name, argv, **kwargs)
            if name == "synthetic-target":
                original = transport.signal

                def signal_group(sig, *, group=False):
                    if sig == signal.SIGKILL and group:
                        transport.receipt["signalErrors"].append(
                            {"signal": "SIGKILL", "target": "owned-group", "errno": errno.EPERM})
                        transport.receipt["cleanupFailed"] = True
                        return False
                    return original(sig, group=group)

                transport.signal = signal_group
            return transport

        receipt, _, _ = self.capture("import time; time.sleep(5)", factory=factory,
                                     budget=1.1, reserve=.5)
        self.assertTrue(receipt["signalFailureResolvedByNoLiveOwnedGroup"])
        self.assertTrue(receipt["cleanupComplete"])
        self.assertFalse(receipt["transportComplete"])
        self.assertEqual(receipt["stopReason"], "command-budget")

    def test_late_close_error_invalidates_final_qualification(self):
        def factory(name, argv, **kwargs):
            transport = self.factory(name, argv, **kwargs)
            if name == "synthetic-target":
                original = transport.close

                def close():
                    was_closed = transport.closed
                    original()
                    if not was_closed:
                        transport.receipt["streamErrors"].append(
                            {"stage": "close", "error": "Synthetic close failure"})

                transport.close = close
            return transport

        receipt, _, _ = self.capture("print('synthetic toc')", factory=factory)
        self.assertFalse(receipt["transportComplete"])
        self.assertFalse(receipt["cleanupComplete"])
        self.assertTrue(receipt["pidLeaseReleased"])
        self.assertEqual(receipt["streamErrors"][0]["stage"], "close")

    def test_external_reap_revokes_signals_and_prevents_group_probe(self):
        def factory(name, argv, **kwargs):
            transport = self.factory(name, argv, **kwargs)
            if name == "synthetic-target":
                transport.process.wait(timeout=1)

                def forbidden_signal(*args, **kwargs):
                    self.fail("A signal was attempted after PID ownership loss")

                transport.signal = forbidden_signal
            return transport

        receipt, _, cleanup = self.capture("raise SystemExit(0)", factory=factory)
        self.assertTrue(receipt["pidLeaseLost"])
        self.assertTrue(receipt["pidDirectedActionsRevoked"])
        self.assertFalse(receipt["transportComplete"])
        self.assertFalse(receipt["cleanupComplete"])
        self.assertEqual(cleanup, [])
        self.assertEqual(receipt["signals"], [])

    def test_invalid_first_inventory_remains_failure_after_emergency_cleanup(self):
        def factory(name, argv, **kwargs):
            if name.endswith("-owned-groups"):
                argv = (sys.executable, "-c", "print('synthetic malformed inventory')")
            return self.factory(name, argv, **kwargs)

        receipt, _, cleanup = self.capture("print('done')", factory=factory)
        self.assertFalse(receipt["transportComplete"])
        self.assertTrue(receipt["cleanupComplete"])
        self.assertTrue(receipt["emergencyCleanupRequired"])
        self.assertEqual(len(cleanup), 2)
        self.assertTrue(any("Initial owned-group inventory failed" in error for error in receipt["adapterErrors"]))


if __name__ == "__main__":
    unittest.main()
