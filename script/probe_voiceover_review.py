#!/usr/bin/env python3
"""Attempt VoiceOver startup on an ephemeral Mac CI host; never certify narration."""
from __future__ import annotations
import argparse
import json
import platform
import subprocess
import time
from pathlib import Path


def attempt(directory: Path) -> dict:
    record = {"schema": 1, "narrationVerified": False, "audioAuditionVerified": False,
              "scope": "Runtime availability probe only; human speech/audio review remains open"}
    if platform.system() != "Darwin":
        return dict(record, status="unavailable", reason="VoiceOver requires macOS")
    app = directory / "Lemulip Native UI Review.app"
    if not app.is_dir():
        return dict(record, status="unavailable", reason="Isolated review application was not staged")
    try:
        check = ["/usr/bin/xcrun", "swift", "-e", "import AppKit; print(NSWorkspace.shared.isVoiceOverEnabled)"]
        before = subprocess.run(check, capture_output=True, text=True, timeout=30)
        if before.returncode or before.stdout.strip() not in {"true", "false"}:
            return dict(record, status="unavailable", reason="Could not read VoiceOver runtime state",
                        diagnostic=before.stderr[-2000:])
        record["enabledBefore"] = before.stdout.strip() == "true"
        # Do not interfere with a pre-existing accessibility session.
        if record["enabledBefore"]:
            return dict(record, status="already-running", enabledAfter=True)
        launched = subprocess.run(["/usr/bin/open", "-n", str(app)], capture_output=True, text=True, timeout=10)
        voice = subprocess.run(["/usr/bin/open", "-a", "VoiceOver"], capture_output=True, text=True, timeout=10)
        record.update(appLaunchExit=launched.returncode, voiceOverLaunchExit=voice.returncode,
                      diagnostic=voice.stderr[-2000:])
        time.sleep(2)
        after = subprocess.run(check, capture_output=True, text=True, timeout=30)
        record["enabledAfter"] = after.returncode == 0 and after.stdout.strip() == "true"
        record["status"] = "runtime-started" if record["enabledAfter"] else "startup-not-confirmed"
        record["humanReviewNeeded"] = "Verify spoken focus, selected operation, units and cancellation on a Mac"
        # This diagnostic runs after all interaction tests, on an ephemeral CI
        # machine. No TCC changes, global key injection, audio-volume override or
        # simulated spoken result is used. The runner tears down after collection.
        capture = subprocess.run(["/usr/sbin/screencapture", "-x", str(directory / "VoiceOver-attempt.png")],
                                 capture_output=True, text=True, timeout=10)
        record["screenshotExit"] = capture.returncode
    except (OSError, subprocess.SubprocessError) as error:
        record.update(status="unavailable", reason=str(error))
    return record


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, required=True)
    args = parser.parse_args()
    record = attempt(args.directory)
    args.directory.mkdir(parents=True, exist_ok=True)
    (args.directory / "voiceover-attempt.json").write_text(json.dumps(record, indent=2) + "\n")
    print(json.dumps(record, indent=2))
