#!/usr/bin/env python3
"""D30 fixed worker faults over the unchanged D29 worker command line."""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import sys
import time

import isolated_atrc_macos_fixture as fixture
import native_retained_atrc_worker as worker

WORKER_MODES = ("delay-stat", "exit-seven")
DELAY_SECONDS = 2.0


def environment_context(environment, argv):
    mode = environment.get("D30_WORKER_MODE")
    fixture.require(mode in WORKER_MODES, "Require one fixed D30 worker mode")
    raw_control = environment.get("D30_CONTROL_DIR")
    fixture.require(isinstance(raw_control, str) and bool(raw_control), "Require D30 control directory")
    # The real worker remains responsible for parsing the unchanged full CLI.
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--root", required=True, type=Path)
    known, _ = parser.parse_known_args(argv)
    context = fixture.validate_context(raw_control, known.root)
    return mode, context


def run(mode, context):
    fixture.require(mode in WORKER_MODES, "Unknown fixed worker mode")
    original_stat = worker.REAL_STAT

    def delayed_stat(path, **kwargs):
        if path == "stall.bin":
            # TimedOS emits op_started immediately before invoking REAL_STAT.
            # This marker therefore witnesses entry after that real report.
            fixture.publish_marker(context.control_dir, "worker-operation.json",
                                   {"schema": 1, "mode": "delay-stat", "operation": "stat",
                                    "relativePath": "stall.bin", "pid": os.getpid(),
                                    "pgid": os.getpgrp(), "monotonicNS": time.monotonic_ns()})
            time.sleep(DELAY_SECONDS)
        return original_stat(path, **kwargs)

    try:
        if mode == "delay-stat":
            worker.REAL_STAT = delayed_stat
        status = worker.main()
        return 7 if mode == "exit-seven" and status == 0 else status
    finally:
        worker.REAL_STAT = original_stat


def main():
    try:
        mode, context = environment_context(os.environ, sys.argv[1:])
        return run(mode, context)
    except (OSError, ValueError, RuntimeError) as error:
        print("D30 worker fixture failed: " + (type(error).__name__ + ": " + str(error))[:512],
              file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
