#!/usr/bin/env python3
"""Exercise real subprocess bounds without macOS applications or trace tools."""

import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest

from collect_native_trace_capabilities import capture


class CaptureTests(unittest.TestCase):
    def run_child(self, source, **options):
        return capture((sys.executable, "-c", source), cwd=Path.cwd(), env=dict(os.environ), **options)

    def test_nonzero_preserves_both_streams(self):
        receipt, streams = self.run_child(
            'import sys; print("out"); print("err", file=sys.stderr); sys.exit(7)', timeout=3)
        self.assertEqual(receipt["status"], "nonzero")
        self.assertEqual(receipt["exitCode"], 7)
        self.assertEqual(streams, {"stdout": b"out\n", "stderr": b"err\n"})

    def test_output_limit_stops_the_owned_process(self):
        receipt, streams = self.run_child('import os; os.write(1,b"x"*2000000)', timeout=3, limit=1024)
        self.assertEqual(receipt["status"], "output-limit")
        self.assertEqual(sum(map(len, streams.values())), 1024)
        self.assertIsNotNone(receipt["exitCode"])
        self.assertTrue(receipt["groupEscalationAttempted"])

    def test_deadline_terminates_the_owned_process(self):
        receipt, _ = self.run_child('import time; time.sleep(30)', timeout=0.2)
        self.assertEqual(receipt["status"], "timeout")
        self.assertLess(receipt["elapsedSeconds"], 5)
        self.assertIsNotNone(receipt["exitCode"])

    @staticmethod
    def owned_child_running(pid, pgid):
        try:
            if os.getpgid(pid) != pgid:
                return False
        except ProcessLookupError:
            return False
        status = subprocess.run(["ps", "-p", str(pid), "-o", "stat="],
                                capture_output=True, text=True, timeout=2)
        # A killed orphan can briefly await the platform's init reaper.
        return status.returncode == 0 and bool(status.stdout.strip()) and not status.stdout.strip().startswith("Z")

    def test_term_exit_of_leader_cannot_leave_a_same_group_child_running(self):
        with tempfile.TemporaryDirectory(prefix="d19-cleanup-") as temporary:
            identity_file = Path(temporary) / "identity.json"
            child = (
                "import os,signal,time,pathlib,json; "
                "signal.signal(signal.SIGTERM,signal.SIG_IGN); "
                f"pathlib.Path({str(identity_file)!r}).write_text(json.dumps({{'pid':os.getpid(),'pgid':os.getpgrp()}})); "
                "time.sleep(30)"
            )
            parent = (
                "import subprocess,sys,time; "
                f"subprocess.Popen([sys.executable,'-c',{child!r}],stdin=subprocess.DEVNULL,"
                "stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL); time.sleep(30)"
            )
            receipt, _ = self.run_child(parent, timeout=1)
            identity = json.loads(identity_file.read_text())
            self.assertEqual(identity["pgid"], receipt["pid"])
            pid, pgid = identity["pid"], identity["pgid"]
            try:
                deadline = time.monotonic() + 2
                while self.owned_child_running(pid, pgid) and time.monotonic() < deadline:
                    time.sleep(0.02)
                self.assertFalse(self.owned_child_running(pid, pgid))
                self.assertEqual(receipt["status"], "timeout")
                self.assertTrue(receipt["groupEscalationAttempted"])
                self.assertIn("SIGKILL", receipt["cleanupSignals"])
            finally:
                if self.owned_child_running(pid, pgid):
                    os.kill(pid, signal.SIGKILL)


if __name__ == "__main__":
    unittest.main()
