#!/usr/bin/env python3
"""D19: read-only installed tracing-tool inventory; never starts a recording."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import selectors
import signal
import subprocess
import time


COMMANDS = (
    ("os-version", ("/usr/bin/sw_vers",), True),
    ("kernel-version", ("/usr/sbin/sysctl", "-n", "kern.version"), True),
    ("hardware-model", ("/usr/sbin/sysctl", "-n", "hw.model"), True),
    ("cpu-brand", ("/usr/sbin/sysctl", "-n", "machdep.cpu.brand_string"), False),
    ("virtual-machine", ("/usr/sbin/sysctl", "-n", "kern.hv_vmm_present"), False),
    ("developer-tools-status", ("/usr/sbin/DevToolsSecurity", "-status"), False),
    ("xcode-version", ("/usr/bin/xcodebuild", "-version"), True),
    ("xctrace-path", ("/usr/bin/xcrun", "--find", "xctrace"), True),
    ("xctrace-help", ("/usr/bin/xcrun", "xctrace", "help"), True),
    ("xctrace-record-help", ("/usr/bin/xcrun", "xctrace", "help", "record"), True),
    ("xctrace-export-help", ("/usr/bin/xcrun", "xctrace", "help", "export"), True),
    ("xctrace-list-help", ("/usr/bin/xcrun", "xctrace", "help", "list"), True),
    ("xctrace-templates", ("/usr/bin/xcrun", "xctrace", "list", "templates"), True),
    ("xctrace-instruments", ("/usr/bin/xcrun", "xctrace", "list", "instruments"), True),
    ("xctrace-manual", ("/usr/bin/xcrun", "man", "xctrace"), False),
)
TIMEOUT_SECONDS = 20.0
MAX_COMBINED_BYTES = 2 * 1024 * 1024


def write_json(path: Path, value: object) -> None:
    with path.open("x", encoding="utf-8") as output:
        json.dump(value, output, indent=2, sort_keys=True, allow_nan=False)
        output.write("\n")


def capture(argv: tuple[str, ...], *, cwd: Path, env: dict[str, str],
            timeout: float = TIMEOUT_SECONDS, limit: int = MAX_COMBINED_BYTES) -> tuple[dict, dict[str, bytes]]:
    """Bound both time and combined output; terminate only our new process group."""
    started = time.monotonic()
    streams = {"stdout": bytearray(), "stderr": bytearray()}
    result = {"argv": list(argv), "timeoutSeconds": timeout, "maximumCombinedBytes": limit,
              "status": "not-started", "exitCode": None, "cleanupSignals": [],
              "groupEscalationAttempted": False,
              "observedBytes": 0, "retainedBytes": 0}
    try:
        process = subprocess.Popen(argv, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
    except OSError as error:
        result.update(status="spawn-error", error=str(error), elapsedSeconds=time.monotonic() - started)
        return result, {key: bytes(value) for key, value in streams.items()}
    result["pid"] = process.pid
    deadline = started + timeout
    stopped = None

    def stop(reason: str) -> None:
        nonlocal stopped
        if stopped is not None:
            return
        stopped = time.monotonic()
        result["status"] = reason
        try:
            os.killpg(process.pid, signal.SIGTERM)
            result["cleanupSignals"].append("SIGTERM")
        except ProcessLookupError:
            pass

    with selectors.DefaultSelector() as selector:
        for name, pipe in (("stdout", process.stdout), ("stderr", process.stderr)):
            os.set_blocking(pipe.fileno(), False)
            selector.register(pipe, selectors.EVENT_READ, name)
        try:
            while selector.get_map():
                now = time.monotonic()
                if now >= deadline:
                    stop("timeout")
                if stopped is not None and now - stopped >= 2:
                    break
                for key, _ in selector.select(0.1):
                    chunk = os.read(key.fileobj.fileno(), 65536)
                    if not chunk:
                        selector.unregister(key.fileobj)
                        continue
                    result["observedBytes"] += len(chunk)
                    remaining = max(0, limit - result["retainedBytes"])
                    kept = chunk[:remaining]
                    streams[key.data].extend(kept)
                    result["retainedBytes"] += len(kept)
                    if len(kept) != len(chunk):
                        stop("output-limit")
            if stopped is None:
                try:
                    process.wait(timeout=max(0.01, deadline - time.monotonic()))
                except subprocess.TimeoutExpired:
                    stop("timeout")
            if stopped is not None:
                # The leader can exit and close both pipes while a same-group
                # descendant ignores TERM. Escalate the group before waiting
                # on/reaping only the leader, irrespective of pipe/leader state.
                result["groupEscalationAttempted"] = True
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                    result["cleanupSignals"].append("SIGKILL")
                except ProcessLookupError:
                    pass
            if process.poll() is None:
                try:
                    process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                        result["cleanupSignals"].append("SIGKILL")
                    except ProcessLookupError:
                        pass
                    process.wait(timeout=2)
        finally:
            for pipe in (process.stdout, process.stderr):
                pipe.close()
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=2)
    if stopped is None:
        result["status"] = "completed" if process.returncode == 0 else "nonzero"
    result.update(exitCode=process.returncode, elapsedSeconds=time.monotonic() - started)
    return result, {key: bytes(value) for key, value in streams.items()}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--experiment-commit", required=True)
    parser.add_argument("--architecture", required=True, choices=("arm64", "x86_64"))
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9a-f]{40}", args.experiment_commit):
        parser.error("Require a complete immutable commit SHA")
    if platform.system() != "Darwin" or platform.machine() != args.architecture:
        parser.error("Require the named native macOS architecture")
    if not args.output.is_absolute() or not args.output.parent.is_dir():
        parser.error("Output must be a new absolute child of an existing directory")
    repo = Path(__file__).resolve().parent.parent
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()
    if commit != args.experiment_commit:
        parser.error("The checked-out experiment commit differs")
    tree = subprocess.check_output(["git", "rev-parse", "HEAD^{tree}"], cwd=repo, text=True).strip()
    args.output.mkdir(exist_ok=False)
    sources = args.output / "sources"
    sources.mkdir()
    identities = {}
    for relative in ("script/collect_native_trace_capabilities.py",
                     "script/test_collect_native_trace_capabilities.py",
                     ".github/workflows/native-trace-capabilities.yml",
                     "docs/NATIVE_TRACE_CAPABILITIES.md"):
        data = (repo / relative).read_bytes()
        target = sources / Path(relative).name
        with target.open("xb") as output:
            output.write(data)
        identities[relative] = {"sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)}
    report = {"schema": 1, "diagnostic": "D19-trace-tool-capabilities", "architecture": args.architecture,
              "experimentCommit": commit, "experimentTree": tree, "sourceIdentities": identities,
              "developerDirectory": os.environ.get("DEVELOPER_DIR"), "commands": [],
              "traceRecordingExecuted": False, "nativeApplicationsLaunched": False,
              "nativeInputExecuted": False, "settingsChanged": False,
              "activationRouteCoverageEstablished": False, "ipcRequestChainEstablished": False,
              "C12": "HOLD", "releaseReady": False,
              "limitations": ["Inventory completion is not tracing permission or path coverage.",
                              "DevToolsSecurity status is not per-tool TCC authorization.",
                              "A listed template is not proof its recording/export succeeds.",
                              "Kernel version identifies the runner build, not an unverified XNU source match."]}
    write_json(args.output / "scope.json", {key: value for key, value in report.items() if key != "commands"})
    env = dict(os.environ, PAGER="cat", MANPAGER="cat", MANWIDTH="120", TERM="dumb")
    for name, argv, required in COMMANDS:
        receipt, streams = capture(argv, cwd=repo, env=env)
        receipt.update(name=name, required=required, files={})
        for stream, data in streams.items():
            filename = name + "." + stream + ".txt"
            with (args.output / filename).open("xb") as output:
                output.write(data)
            receipt["files"][stream] = {"name": filename, "bytes": len(data),
                                         "sha256": hashlib.sha256(data).hexdigest()}
        write_json(args.output / (name + ".json"), receipt)
        report["commands"].append(receipt)
        print(name + ": " + receipt["status"], flush=True)
    report["inventoryComplete"] = all(not row["required"] or row["status"] == "completed"
                                      for row in report["commands"])
    report["status"] = "inventory-complete" if report["inventoryComplete"] else "inventory-incomplete"
    write_json(args.output / "capabilities.json", report)
    print(report["status"], flush=True)
    return 0 if report["inventoryComplete"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
