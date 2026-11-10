#!/usr/bin/env python3
"""D30 fixed disposable workloads; no Apple tools, GUI input or arbitrary command.

The descendant mode creates exactly one same-group child with a finite lifetime.
Only the surrounding owned-command supervisor may signal that process group.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import json
import os
from pathlib import Path
import signal
import stat
import sys
import time

MODES = ("success", "pending-exit", "deadline", "descendant")
EXPECTED_FILES = {
    "derived.trace/metadata.json": b'{"schema":1,"kind":"D30-synthetic-output"}\n',
    "derived.trace/payload.bin": bytes(range(64)),
    "derived.trace/notes.txt": b"Disposable observer qualification; no native trace data.\n",
    "derived.trace/nested/sample.dat": b"fixed sample\x00\x01\x02\n" * 4,
}
SUCCESS_STDOUT = b"D30 fixture success\n"
PENDING_EXIT_STDOUT = b"D30 pending progress\n"
SUCCESS_LIVE_SECONDS = 0.15
WORKER_MARKER_WAIT_SECONDS = 1.5
DESCENDANT_READY_SECONDS = 1.0
FINITE_WAIT_SECONDS = 3.0
POLL_SECONDS = 0.005
MARKER_BYTES = 4096


class FixtureError(ValueError):
    pass


def require(value, message):
    if not value:
        raise FixtureError(message)


def integer(value, *, minimum=0):
    return type(value) is int and minimum <= value < 2**63


def canonical_directory(value):
    path = Path(value)
    require(path.is_absolute(), "Fixture directory must be absolute")
    info = path.lstat()
    require(stat.S_ISDIR(info.st_mode) and not stat.S_ISLNK(info.st_mode),
            "Fixture directory must be a real directory")
    require(path == path.resolve(strict=True), "Fixture directory must be canonical")
    return path


@dataclass(frozen=True)
class FixtureContext:
    output_root: Path
    control_dir: Path


def validate_context(control_dir, output_root=None):
    control = canonical_directory(control_dir)
    root = canonical_directory(Path.cwd() if output_root is None else output_root)
    require(root.parent == control, "Observed root must be a direct child of its case directory")
    require(stat.S_IMODE(root.lstat().st_mode) == 0o700, "Observed root must have mode 0700")
    return FixtureContext(root, control)


def publish_marker(directory, name, value):
    require(name in ("worker-operation.json", "descendant.json"), "Unknown fixture marker")
    raw = json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8") + b"\n"
    require(len(raw) <= MARKER_BYTES, "Fixture marker exceeds byte limit")
    temporary = directory / (name + ".pending")
    final = directory / name
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    try:
        require(os.write(descriptor, raw) == len(raw), "Partial fixture marker write")
    finally:
        os.close(descriptor)
    try:
        # Publish a complete file without overwriting an earlier marker.
        os.link(temporary, final, follow_symlinks=False)
    finally:
        temporary.unlink()


def read_marker(directory, name):
    require(name in ("worker-operation.json", "descendant.json"), "Unknown fixture marker")
    descriptor = os.open(directory / name, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
    try:
        before = os.fstat(descriptor)
        require(stat.S_ISREG(before.st_mode) and 0 < before.st_size <= MARKER_BYTES,
                "Fixture marker must be a bounded regular file")
        raw = os.read(descriptor, MARKER_BYTES + 1)
        after = os.fstat(descriptor)
        require(len(raw) == before.st_size and len(raw) <= MARKER_BYTES
                and (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns)
                == (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns),
                "Fixture marker changed while reading")
    finally:
        os.close(descriptor)
    value = json.loads(raw.decode("utf-8"))
    require(isinstance(value, dict), "Fixture marker must be an object")
    return value


def wait_marker(directory, name, timeout):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            return read_marker(directory, name)
        except FileNotFoundError:
            time.sleep(min(POLL_SECONDS, max(0, deadline - time.monotonic())))
    raise FixtureError("Fixture readiness deadline exceeded: " + name)


def write_stall_file(context):
    with (context.output_root / "stall.bin").open("xb") as stream:
        stream.write(b"D30 pending metadata fixture\n")


def run_success(context):
    (context.output_root / "derived.trace").mkdir(mode=0o700)
    (context.output_root / "derived.trace/nested").mkdir(mode=0o700)
    for relative, payload in EXPECTED_FILES.items():
        with (context.output_root / relative).open("xb") as stream:
            stream.write(payload)
    time.sleep(SUCCESS_LIVE_SECONDS)
    print(SUCCESS_STDOUT.decode("ascii"), end="", flush=True)
    return 0


def run_pending_exit(context):
    started = time.monotonic_ns()
    write_stall_file(context)
    marker = wait_marker(context.control_dir, "worker-operation.json", WORKER_MARKER_WAIT_SECONDS)
    require(marker.get("schema") == 1 and type(marker.get("schema")) is int
            and marker.get("mode") == "delay-stat" and marker.get("operation") == "stat"
            and marker.get("relativePath") == "stall.bin"
            and integer(marker.get("pid"), minimum=1) and integer(marker.get("pgid"), minimum=1)
            and integer(marker.get("monotonicNS"), minimum=1)
            and started <= marker["monotonicNS"] <= time.monotonic_ns(),
            "Worker-operation marker does not describe this fixture interval")
    print(PENDING_EXIT_STDOUT.decode("ascii"), end="", flush=True)
    return 0


def run_deadline(context):
    write_stall_file(context)
    # Default TERM handling is deliberately retained. If supervision fails,
    # this fixed synthetic target still returns naturally after three seconds.
    time.sleep(FINITE_WAIT_SECONDS)
    print("D30 deadline target reached its finite natural end", flush=True)
    return 0


def run_descendant(context):
    require(hasattr(os, "fork"), "Descendant fixture requires fork")
    leader_pid, group = os.getpid(), os.getpgrp()
    require(leader_pid == group, "Descendant fixture must start as its own process-group leader")
    descendant_pid = os.fork()
    if descendant_pid == 0:
        code = 2
        try:
            signal.signal(signal.SIGTERM, signal.SIG_IGN)
            os.close(1)
            os.close(2)
            started = time.monotonic_ns()
            deadline_ns = started + int(FINITE_WAIT_SECONDS * 1e9)
            publish_marker(context.control_dir, "descendant.json",
                           {"schema": 1, "ready": True, "role": "same-group-descendant",
                            "pid": os.getpid(), "parentPID": os.getppid(), "leaderPID": leader_pid,
                            "pgid": os.getpgrp(), "monotonicNS": started, "readyNS": started,
                            "naturalDeadlineNS": deadline_ns,
                            "termIgnored": True})
            deadline = deadline_ns / 1e9
            while time.monotonic() < deadline:
                time.sleep(min(0.02, max(0, deadline - time.monotonic())))
            code = 0
        finally:
            os._exit(code)
    marker = wait_marker(context.control_dir, "descendant.json", DESCENDANT_READY_SECONDS)
    require(marker.get("schema") == 1 and type(marker.get("schema")) is int
            and marker.get("ready") is True and marker.get("termIgnored") is True
            and marker.get("role") == "same-group-descendant"
            and marker.get("pid") == descendant_pid and marker.get("leaderPID") == leader_pid
            and marker.get("parentPID") == leader_pid and marker.get("pgid") == group,
            "Descendant readiness marker does not match the owned group")
    print(json.dumps({"schema": 1, "kind": "descendant-ready", "pid": descendant_pid,
                      "pgid": group, "monotonicNS": time.monotonic_ns()},
                     sort_keys=True, separators=(",", ":")), flush=True)
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=MODES)
    parser.add_argument("--control-dir", required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        context = validate_context(args.control_dir)
        return {"success": run_success, "pending-exit": run_pending_exit,
                "deadline": run_deadline, "descendant": run_descendant}[args.mode](context)
    except (OSError, ValueError, RuntimeError) as error:
        print("D30 target fixture failed: " + (type(error).__name__ + ": " + str(error))[:512],
              file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
