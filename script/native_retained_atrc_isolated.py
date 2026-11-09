#!/usr/bin/env python3
"""D29 isolated census protocol and owned-command supervision.

This is a separately callable diagnostic adapter. The D27 collector and its
workflow continue to use their frozen synchronous path.
"""
from __future__ import annotations

from collections import deque
from dataclasses import dataclass
import json
import math
import os
from pathlib import Path
import re
import selectors
import signal
import socket
import stat
import subprocess
import sys
import time
import uuid

import native_retained_atrc_output as legacy
import run_native_recorder_progress_observation as progress

FRAME_BYTES = 4096
BUFFER_BYTES = 65536
MESSAGES_PER_TICK = 16
DIAGNOSTIC_BYTES = 8 * 1024 * 1024
DIAGNOSTIC_RECEIPT_RESERVE = 3 * 1024 * 1024
STARTUP_SECONDS = 2.0
CLEANUP_SECONDS = 2.0
SCAN_NS = 250_000_000
COMMON = {"schema", "nonce", "seq", "kind", "scan", "clockNS"}
EXTRA = {
    "ready": {"pid", "rootIdentity", "limits"},
    "scan_started": set(),
    "op_started": {"op", "category", "path"},
    "op_finished": {"op", "category", "path", "elapsedNS", "outcome"},
    "scan_completed": {"totals", "highWater", "elapsedNS", "operationCount", "rootIdentity"},
    "scan_failed": {"error", "highWater", "elapsedNS", "operationCount"},
    "stopped": set(),
}
COUNTERS = {"entries", "depth", "logicalBytes", "allocatedBytes"}


class ProtocolError(ValueError):
    pass


def integer(value, *, minimum=0):
    return type(value) is int and minimum <= value <= 2**63 - 1


def _pairs(items):
    result = {}
    for key, value in items:
        if key in result:
            raise ProtocolError("Duplicate JSON key")
        result[key] = value
    return result


def decode_report(raw):
    if not isinstance(raw, bytes) or not raw or len(raw) + 1 > FRAME_BYTES:
        raise ProtocolError("Report frame byte limit")
    try:
        result = json.loads(raw.decode("utf-8"), object_pairs_hook=_pairs,
                            parse_constant=lambda _: (_ for _ in ()).throw(ProtocolError("Nonfinite JSON")))
    except (UnicodeError, ValueError, RecursionError) as error:
        raise ProtocolError("Invalid report JSON: " + type(error).__name__) from error
    if not isinstance(result, dict):
        raise ProtocolError("Report must be an object")
    stack = [(result, 0)]
    while stack:
        value, depth = stack.pop()
        if depth > 8:
            raise ProtocolError("Report nesting limit")
        if type(value) is float and not math.isfinite(value):
            raise ProtocolError("Nonfinite report value")
        if isinstance(value, dict):
            stack.extend((item, depth + 1) for item in value.values())
        elif isinstance(value, list):
            stack.extend((item, depth + 1) for item in value)
    return result


class History:
    """First/tail retention with completed and failed omission populations."""
    def __init__(self):
        self.first, self.tail = [], deque(maxlen=128)
        self.tail_sizes = deque(maxlen=128)
        self.retained_bytes = 0
        self.complete_count = self.failed_count = 0

    def add(self, row):
        size = len(json.dumps(row, ensure_ascii=False).encode())
        if row["completed"]:
            self.complete_count += 1
        else:
            self.failed_count += 1
        if len(self.first) < 128:
            self.first.append(row)
        else:
            if len(self.tail) == 128:
                self.retained_bytes -= self.tail_sizes[0]
            self.tail.append(row)
            self.tail_sizes.append(size)
        self.retained_bytes += size

    def summary(self):
        rows = self.first + list(self.tail)
        complete = sum(row["completed"] is True for row in rows)
        return {"records": rows, "completedCount": self.complete_count,
                "failedCount": self.failed_count,
                "omittedCompletedCount": self.complete_count - complete,
                "omittedFailedCount": self.failed_count - (len(rows) - complete)}


class ObserverState:
    def __init__(self, nonce, root_identity, limits, worker_pid):
        if not isinstance(nonce, str) or not re.fullmatch(r"[0-9a-f]{32}", nonce):
            raise ProtocolError("Invalid session nonce")
        if (not isinstance(root_identity, list) or len(root_identity) != 3
                or not all(integer(v) for v in root_identity)
                or not stat.S_ISDIR(root_identity[2]) or stat.S_IMODE(root_identity[2]) != 0o700):
            raise ProtocolError("Invalid root identity")
        if (not isinstance(limits, dict) or set(limits) != set(legacy.LIMITS)
                or not all(integer(v, minimum=1) and v <= legacy.LIMITS[k] for k, v in limits.items())
                or (worker_pid is not None and not integer(worker_pid, minimum=1))):
            raise ProtocolError("Invalid worker identity or limits")
        self.nonce, self.root_identity, self.limits = nonce, root_identity, dict(limits)
        self.worker_pid = worker_pid
        self.ready = self.stopped = self.stop_requested = False
        self.failure = self.pending = self.pending_operation = None
        self.sequence = self.generation = self.completed_scan = 0
        self.last_clock = 0
        self.last_completed = None
        self.operations = History()
        self.scans = History()
        self.high_water = dict.fromkeys(COUNTERS, 0)

    def fail(self, message, now_ns):
        if self.failure is None:
            self.failure = {"code": "isolated-observation-failed", "error": str(message)[:512],
                            "parentClockNS": now_ns,
                            "pendingScan": dict(self.pending) if self.pending else None,
                            "pendingOperation": dict(self.pending_operation) if self.pending_operation else None}
        return False

    def reject(self, message, now_ns):
        self.fail(message, now_ns)
        raise ProtocolError(message)

    def check_deadline(self, now_ns):
        if self.pending and now_ns >= self.pending["deadlineNS"]:
            self.reject("Census completion not observed within parent dispatch budget", now_ns)

    def dispatch(self, now_ns):
        if self.failure or not self.ready or self.pending or self.stop_requested or self.stopped:
            self.reject("Cannot dispatch in current observer state", now_ns)
        self.generation += 1
        self.pending = {"scan": self.generation, "dispatchedNS": now_ns,
                        "deadlineNS": now_ns + SCAN_NS, "started": False,
                        "lastOperation": 0}
        return {"schema": 1, "nonce": self.nonce, "kind": "scan",
                "scan": self.generation, "deadlineNS": now_ns + SCAN_NS}

    def _counter_values(self, row, *, complete):
        if not isinstance(row, dict) or set(row) != COUNTERS:
            raise ProtocolError("Invalid census counters")
        if not all(integer(value) for value in row.values()):
            raise ProtocolError("Census counters must be finite nonnegative integers")
        if complete and (row["entries"] < 1 or any(row[k] > self.limits[k] for k in COUNTERS)):
            raise ProtocolError("Completed census exceeded output bounds")

    def accept(self, message, received_ns):
        try:
            if self.failure is not None:
                raise ProtocolError("Observation already failed")
            self.check_deadline(received_ns)
            if not isinstance(message, dict) or message.get("kind") not in EXTRA:
                raise ProtocolError("Unknown report kind")
            kind = message["kind"]
            if set(message) != COMMON | EXTRA[kind]:
                raise ProtocolError("Unexpected report fields")
            if (type(message["schema"]) is not int or message["schema"] != 1
                    or message["nonce"] != self.nonce
                    or not integer(message["seq"], minimum=1) or message["seq"] != self.sequence + 1
                    or not integer(message["scan"]) or not integer(message["clockNS"])
                    or message["clockNS"] < self.last_clock or message["clockNS"] > received_ns):
                raise ProtocolError("Report identity, sequence or clock mismatch")
            if kind == "ready":
                if (self.ready or self.sequence or message["scan"] != 0
                        or type(message["pid"]) is not int or message["pid"] != self.worker_pid
                        or message["rootIdentity"] != self.root_identity
                        or not isinstance(message["rootIdentity"], list)
                        or not all(integer(v) for v in message["rootIdentity"])
                        or message["limits"] != self.limits
                        or not all(type(v) is int for v in message["limits"].values())):
                    raise ProtocolError("Ready receipt does not bind owned worker and root")
                self.ready = True
            elif kind == "stopped":
                if not self.stop_requested or self.pending or self.stopped or message["scan"] != 0:
                    raise ProtocolError("Unexpected worker stop")
                self.stopped = True
            else:
                if (not self.ready or self.stopped or self.pending is None
                        or message["scan"] != self.pending["scan"]):
                    raise ProtocolError("Report does not match pending generation")
                if kind == "scan_started":
                    if self.pending["started"] or message["clockNS"] < self.pending["dispatchedNS"]:
                        raise ProtocolError("Duplicate scan start")
                    self.pending["started"] = True
                    self.pending["workerStartedNS"] = message["clockNS"]
                elif not self.pending["started"]:
                    raise ProtocolError("Scan report before scan start")
                elif kind in ("op_started", "op_finished"):
                    from native_retained_atrc_worker import CATEGORIES
                    if (not integer(message["op"], minimum=1) or message["category"] not in CATEGORIES
                            or not isinstance(message["path"], str)):
                        raise ProtocolError("Invalid operation witness")
                    path = message["path"]
                    if len(path.encode("utf-8")) > self.limits["pathBytes"]:
                        raise ProtocolError("Operation path exceeds bound")
                    if path != ".":
                        for part in path.split("/"):
                            legacy._component(part)
                    if kind == "op_started":
                        if self.pending_operation or message["op"] != self.pending["lastOperation"] + 1:
                            raise ProtocolError("Overlapping or unsequenced operation")
                        self.pending_operation = dict(message)
                        self.pending["lastOperation"] = message["op"]
                    else:
                        start = self.pending_operation
                        if (not start or any(message[k] != start[k] for k in ("scan", "op", "category", "path"))
                                or not integer(message["elapsedNS"])
                                or message["elapsedNS"] != message["clockNS"] - start["clockNS"]
                                or message["outcome"] not in ("ok", "error", "eof")):
                            raise ProtocolError("Unmatched operation completion")
                        self.operations.add({"completed": message["outcome"] != "error",
                                             "started": start, "ended": dict(message)})
                        if message["outcome"] == "error":
                            self.pending["operationFailed"] = True
                        self.pending_operation = None
                else:
                    if (not integer(message["elapsedNS"]) or not integer(message["operationCount"])
                            or message["elapsedNS"] != message["clockNS"] - self.pending["workerStartedNS"]
                            or message["operationCount"] != self.pending["lastOperation"]):
                        raise ProtocolError("Scan operation accounting mismatch")
                    self._counter_values(message["highWater"], complete=False)
                    if any(message["highWater"][k] < self.high_water[k] for k in COUNTERS):
                        raise ProtocolError("High-water counters regressed")
                    self.high_water = dict(message["highWater"])
                    if kind == "scan_completed":
                        if self.pending_operation or self.pending.get("operationFailed"):
                            raise ProtocolError("Scan completed with pending or failed operation")
                        if (message["rootIdentity"] != self.root_identity
                                or not isinstance(message["rootIdentity"], list)
                                or not all(integer(v) for v in message["rootIdentity"])):
                            raise ProtocolError("Completed scan root mismatch")
                        self._counter_values(message["totals"], complete=True)
                        self._counter_values(message["highWater"], complete=True)
                        if any(message["highWater"][k] < message["totals"][k] for k in COUNTERS):
                            raise ProtocolError("High-water counters omit completed totals")
                        self.completed_scan = message["scan"]
                        self.last_completed = dict(message)
                        self.scans.add({"completed": True, "request": dict(self.pending),
                                        "report": dict(message), "receivedNS": received_ns})
                        self.pending = None
                    else:
                        if not isinstance(message["error"], str) or not message["error"] or len(message["error"]) > 512:
                            raise ProtocolError("Invalid scan error")
                        self.scans.add({"completed": False, "request": dict(self.pending),
                                        "report": dict(message), "receivedNS": received_ns})
                        self.fail(message["error"], received_ns)
            self.sequence = message["seq"]
            self.last_clock = message["clockNS"]
            # Incremental accounting avoids serializing the entire bounded
            # history for every operation report inside the supervision tick.
            if self.operations.retained_bytes + self.scans.retained_bytes + DIAGNOSTIC_RECEIPT_RESERVE > DIAGNOSTIC_BYTES:
                raise ProtocolError("Worker diagnostic retention limit exceeded")
        except (ProtocolError, ValueError, TypeError, KeyError, UnicodeError, RecursionError) as error:
            self.fail(str(error), received_ns)
            if isinstance(error, ProtocolError):
                raise
            raise ProtocolError("Invalid report semantics") from error

    def summary(self):
        return {"schema": 1, "ready": self.ready, "stopped": self.stopped,
                "sequence": self.sequence, "generation": self.generation,
                "lastCompletedScan": self.completed_scan, "lastCompleteCensus": self.last_completed,
                "rootIdentity": self.root_identity, "workerPID": self.worker_pid,
                "failure": self.failure, "pendingScan": self.pending,
                "pendingOperation": self.pending_operation, "highWaterObserved": self.high_water,
                "scanHistory": self.scans.summary(), "operationHistory": self.operations.summary(),
                "maximumRetainedDiagnosticBytes": DIAGNOSTIC_BYTES}


class ReportChannel:
    def __init__(self, descriptor):
        self.fd = descriptor
        os.set_blocking(descriptor, False)
        self.buffer = bytearray()
        self.eof = False
        self.observed_bytes = self.messages = 0
        self.maximum_buffer = self.maximum_tick_bytes = self.maximum_tick_messages = 0

    def drain(self, state):
        """At most one capped read and 16 parsed frames per supervisor tick."""
        read_bytes = processed = 0
        if not self.eof and len(self.buffer) < BUFFER_BYTES:
            try:
                chunk = os.read(self.fd, BUFFER_BYTES - len(self.buffer))
            except BlockingIOError:
                chunk = None
            if chunk is not None:
                if not chunk:
                    self.eof = True
                else:
                    read_bytes = len(chunk)
                    self.buffer.extend(chunk)
                    self.observed_bytes += read_bytes
        self.maximum_tick_bytes = max(self.maximum_tick_bytes, read_bytes)
        self.maximum_buffer = max(self.maximum_buffer, len(self.buffer))
        while processed < MESSAGES_PER_TICK:
            delimiter = self.buffer.find(b"\n")
            if delimiter < 0:
                break
            if delimiter + 1 > FRAME_BYTES:
                raise ProtocolError("Oversized report frame")
            raw = bytes(self.buffer[:delimiter])
            del self.buffer[:delimiter + 1]
            processed += 1
            self.messages += 1
            self.maximum_tick_messages = max(self.maximum_tick_messages, processed)
            message = decode_report(raw)
            state.accept(message, time.monotonic_ns())
        if b"\n" not in self.buffer and len(self.buffer) >= FRAME_BYTES:
            raise ProtocolError("Unterminated oversized report frame")
        if self.eof and self.buffer and b"\n" not in self.buffer:
            raise ProtocolError("Truncated report at EOF")
        return bool(read_bytes or processed or b"\n" in self.buffer)

    def summary(self):
        return {"observedBytes": self.observed_bytes, "parsedMessages": self.messages,
                "maximumUndecodedBytes": self.maximum_buffer,
                "maximumReadBytesPerTick": self.maximum_tick_bytes,
                "maximumMessagesParsedPerTick": self.maximum_tick_messages,
                "EOF": self.eof, "undecodedBytes": len(self.buffer)}


class DescriptorTransport(progress.startup.MonitoredCommand):
    """Use the existing stream/signal machinery with explicitly inherited FDs."""
    def __init__(self, argv, *, cwd, env, limit, inherited):
        self.started = time.monotonic()
        self.streams = {"stdout": bytearray(), "stderr": bytearray()}
        self.selector = selectors.DefaultSelector()
        self.process = None
        self.reap_deferred = False
        self.closed = self.selector_failed = False
        self.receipt = {"argv": list(argv), "pid": None, "status": "running", "exitCode": None,
                        "maximumCombinedBytes": limit, "observedBytes": 0, "retainedBytes": 0,
                        "stopReason": None, "signals": [], "signalErrors": [],
                        "streamErrors": [], "cleanupFailed": False}
        try:
            self.process = subprocess.Popen(argv, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                            start_new_session=True, pass_fds=tuple(inherited))
        except (OSError, ValueError) as error:
            self.receipt.update(status="spawn-error", error=str(error))
            return
        self.receipt["pid"] = self.process.pid
        try:
            for name, pipe in (("stdout", self.process.stdout), ("stderr", self.process.stderr)):
                os.set_blocking(pipe.fileno(), False)
                self.selector.register(pipe, selectors.EVENT_READ, name)
        except Exception as error:
            self.stream_error("setup", error)


@dataclass
class IsolatedResult:
    receipt: dict
    streams: dict
    cleanup_records: list
    _guard: legacy.OutputGuard
    _retention_allowed: bool

    def finalize(self, archive_path):
        """Eligibility comes from both owned children, never a caller's bool."""
        return self._guard.finalize(Path(archive_path), safe_to_read=self._retention_allowed)


def worker_evidence_bytes(receipt, cleanup_records):
    """Canonical UTF-8 metadata plus raw retained worker/probe stream bytes.

    Include the worker receipt in both places in which the result exposes it;
    target evidence has its separate inherited command/stream limits.
    """
    metadata = {key: receipt[key] for key in
                ("observer", "worker", "channel", "channelKernelBuffers", "errors", "finalOwnedGroups")}
    metadata["cleanupRecords"] = [
        {"name": item["name"], "receipt": item["receipt"],
         "streamBytes": {key: len(value) for key, value in item["streams"].items()}}
        for item in cleanup_records]
    return (len(json.dumps(metadata, ensure_ascii=False, allow_nan=False,
                           separators=(",", ":")).encode("utf-8"))
            + sum(len(value) for item in cleanup_records for value in item["streams"].values()))


def capture_isolated(name, argv, *, cwd, env, guard, test_factory=None,
                     test_budget=None, test_reserve=None, test_worker_script=None):
    """Run one command with a separately owned output observer.

    Test worker scripts and shortened command budgets require an explicit
    test factory; this adapter is not wired into D27's native collector.
    """
    progress.require(isinstance(guard, legacy.OutputGuard) and not guard.closed
                     and not guard.capture_started, "Require a fresh owned output guard")
    progress.require(test_factory is not None or
                     (test_budget is None and test_reserve is None and test_worker_script is None
                      and not guard.synthetic_limits), "Test controls cannot be native evidence")
    budget = legacy.TOTAL_SECONDS if test_budget is None else test_budget
    reserve = legacy.TOTAL_SECONDS - legacy.NORMAL_SECONDS if test_reserve is None else test_reserve
    progress.require(all(type(v) in (float, int) and math.isfinite(v) for v in (budget, reserve))
                     and 0 < reserve < budget <= legacy.TOTAL_SECONDS, "Invalid command budget")
    argv = tuple(argv)
    progress.require(isinstance(name, str) and 0 < len(name) <= 100 and argv
                     and all(isinstance(a, str) and a and "\0" not in a for a in argv), "Invalid command")
    cwd = Path(cwd).resolve(strict=True)
    progress.require(cwd.is_dir(), "Invalid command directory")
    worker_script = (Path(test_worker_script).resolve(strict=True) if test_worker_script
                     else Path(__file__).with_name("native_retained_atrc_worker.py").resolve(strict=True))
    guard.capture_started = True
    nonce = uuid.uuid4().hex
    identity = list(legacy._anchor_identity(guard.initial_root))
    # Do all fallible descriptor/protocol setup before a child can exist. A
    # setup exception still closes every descriptor acquired so far.
    request_read = request_write = reports = writer = None
    def close_channel_resources():
        nonlocal request_read, request_write, reports, writer
        failures = []
        for descriptor in (request_read, request_write):
            if descriptor is not None:
                try:
                    os.close(descriptor)
                except OSError as caught:
                    failures.append(str(caught))
        for endpoint in (reports, writer):
            if endpoint is not None:
                try:
                    endpoint.close()
                except OSError as caught:
                    failures.append(str(caught))
        request_read = request_write = reports = writer = None
        return failures
    try:
        request_read, request_write = os.pipe()
        reports, writer = socket.socketpair()
        os.set_blocking(request_write, False)
        reports.setblocking(False)
        writer.setblocking(False)
        request_buffer_sizes = {"reportSendBufferBytes": writer.getsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF),
                                "reportReceiveBufferBytes": reports.getsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF)}
        channel = ReportChannel(reports.fileno())
        state = ObserverState(nonce, identity, guard.limits, None)
    except BaseException:
        close_channel_resources()
        guard._fail(legacy.OutputError("Observer channel setup failed"), code="isolated-observation-failed")
        raise
    worker_argv = (sys.executable, "-u", str(worker_script), "--root", str(guard.root),
                   "--root-fd", str(guard.fd), "--request-fd", str(request_read),
                   "--report-fd", str(writer.fileno()), "--nonce", nonce,
                   "--identity", json.dumps(identity), "--limits", json.dumps(guard.limits))
    inherited = (guard.fd, request_read, writer.fileno())
    def worker_factory(_name, command, **options):
        return DescriptorTransport(command, inherited=inherited, **options)
    # Worker lifetime has its own outer ceiling; its startup/scan/cleanup
    # phases below have smaller independent deadlines.
    outer_worker_budget = STARTUP_SECONDS + legacy.TOTAL_SECONDS + 2 * legacy.GROUP_BUDGET + CLEANUP_SECONDS + 1
    commands, probes = [], []
    worker = target = None
    errors, tick_failures = [], set()
    final_groups = {}
    cleanup_started = None
    stop_sent = False
    initial_scan = final_scan = None
    final_scan_complete = False
    cleanup_overrun = False
    worker_accounted_at = None
    all_tick_count = 0
    maximum_tick_gap = 0.0
    previous_tick = None
    started = time.monotonic()
    startup_complete = False

    def error(message):
        if message not in errors:
            errors.append(message[:512])

    def fail(message):
        state.fail(message, time.monotonic_ns())
        error(message)

    def send(message):
        raw = json.dumps(message, separators=(",", ":"), ensure_ascii=False).encode() + b"\n"
        if len(raw) > FRAME_BYTES:
            raise ProtocolError("Oversized parent request")
        try:
            count = os.write(request_write, raw)
        except (BlockingIOError, BrokenPipeError, OSError) as caught:
            raise ProtocolError("Nonblocking request write failed") from caught
        if count != len(raw):
            raise ProtocolError("Partial parent request write")

    def request_scan():
        message = state.dispatch(time.monotonic_ns())
        send(message)
        return message["scan"]

    def stop_worker(*, failed):
        nonlocal cleanup_started, stop_sent
        if worker is None:
            return
        if cleanup_started is None:
            cleanup_started = time.monotonic()
            state.stop_requested = True
            if not failed and not state.pending:
                try:
                    send({"schema": 1, "nonce": nonce, "kind": "stop"})
                    stop_sent = True
                except ProtocolError as caught:
                    fail(str(caught))
                    failed = True
        if failed:
            worker.stop("observation-failed")

    def tick():
        nonlocal all_tick_count, maximum_tick_gap, previous_tick, cleanup_overrun
        now = time.monotonic()
        if previous_tick is not None:
            maximum_tick_gap = max(maximum_tick_gap, now - previous_tick)
        previous_tick = now
        all_tick_count += 1
        progress_seen = False
        # The target is serviced first, before bounded worker/report work.
        ordered = ([target] if target is not None else []) + ([worker] if worker is not None else []) + probes
        for command in ordered:
            if command.name in tick_failures and command.pid_actions_revoked:
                continue
            old = (command.last_bytes, command.terminal, command.operation_done)
            try:
                command.tick()
            except (progress.EvidenceError, OSError, ValueError, RuntimeError) as caught:
                tick_failures.add(command.name)
                command.receipt["cleanupFailed"] = True
                fail(command.name + ": supervision failed: " + str(caught))
            progress_seen |= old != (command.last_bytes, command.terminal, command.operation_done)
        if state.failure is None and worker is not None:
            try:
                state.check_deadline(time.monotonic_ns())
                progress_seen |= channel.drain(state)
                if channel.eof and not channel.buffer and not state.stopped:
                    fail("Worker report channel closed before acknowledged stop")
                if worker.pid_actions_revoked and not worker.collected:
                    fail("Worker PID lease lost")
                if worker.terminal and not state.stop_requested:
                    fail("Worker exited before observation shutdown")
                if worker.transport.streams["stderr"] or worker.receipt["streamErrors"]:
                    fail("Worker diagnostic stream error")
            except (ProtocolError, OSError, ValueError, RuntimeError) as caught:
                fail(str(caught))
        if state.failure:
            if target is not None:
                target.stop("isolated-observation-failed")
            stop_worker(failed=True)
        if cleanup_started is not None:
            elapsed = time.monotonic() - cleanup_started
            if elapsed >= legacy.TERM_GRACE and not worker.terminal:
                worker.stop("observer-shutdown")
            if elapsed >= CLEANUP_SECONDS and not worker.collected:
                if not worker.terminal or worker.transport.selector.get_map():
                    cleanup_overrun = True
                    fail("Observer cleanup deadline exceeded")
                    if not worker.kill_sent:
                        worker.signal(signal.SIGKILL, group=True)
                        worker.kill_sent = True
        return progress_seen or (state.failure is None and b"\n" in channel.buffer)

    def wait_until(predicate, deadline, *, abort_failure=False):
        while not predicate() and time.monotonic() < deadline:
            busy = tick()
            if abort_failure and state.failure:
                break
            if not predicate() and not busy:
                time.sleep(min(legacy.POLL_SECONDS, max(0, deadline - time.monotonic())))
        tick()

    def probe_groups(suffix, owners):
        eligible = [c for c in owners if c.pid is not None and not c.pid_actions_revoked and not c.collected]
        if not eligible:
            return {}
        try:
            command = progress.OwnedCommand("groups-" + suffix,
                      ("/bin/ps", "-A", "-o", "pid=,pgid=,stat="), cwd=cwd, env=env,
                      budget=legacy.GROUP_BUDGET, reserve=.5, limit=legacy.GROUP_LIMIT,
                      term_grace=legacy.TERM_GRACE, factory=test_factory)
        except (progress.EvidenceError, OSError, ValueError, RuntimeError) as caught:
            fail("Owned-group probe setup failed: " + str(caught))
            return {}
        probes.append(command)
        commands.append(command)
        wait_until(lambda: command.operation_done or command.name in tick_failures, command.deadline)
        try:
            return progress.group_inventory(command, eligible)
        except (progress.EvidenceError, ValueError, UnicodeError, OSError) as caught:
            fail("Owned-group evidence failed: " + str(caught))
            return {}

    def group_safe(command):
        row = final_groups.get(command.name, {})
        return row.get("pidLeaseHeldAtSnapshot") is True and row.get("noLiveMembersObserved") is True

    try:
        worker = progress.OwnedCommand("output-observer", worker_argv, cwd=cwd, env=env,
                                      budget=outer_worker_budget, reserve=CLEANUP_SECONDS,
                                      limit=legacy.GROUP_LIMIT, term_grace=legacy.TERM_GRACE,
                                      factory=worker_factory)
        commands.append(worker)
        state.worker_pid = worker.pid
        startup_deadline = worker.started + STARTUP_SECONDS
        os.close(request_read)
        request_read = None
        writer.close()
        writer = None
        if worker.pid is None:
            fail("Observer process did not start")
        wait_until(lambda: state.ready or state.failure, startup_deadline, abort_failure=True)
        if state.failure is None and state.ready:
            initial_scan = request_scan()
            wait_until(lambda: state.completed_scan == initial_scan or state.failure,
                       min(startup_deadline, time.monotonic() + legacy.SCAN_SECONDS), abort_failure=True)
        if (state.failure is None and state.completed_scan == initial_scan
                and initial_scan is not None and time.monotonic() < startup_deadline):
            totals = state.last_completed["totals"]
            if totals["entries"] != 1 or totals["logicalBytes"] != 0:
                fail("Output parent not empty before target launch")
            else:
                startup_complete = True
        if not startup_complete:
            fail("Observer startup or empty-census gate failed")
        else:
            target = progress.OwnedCommand(name, argv, cwd=cwd, env=env, budget=budget,
                                            reserve=reserve, limit=legacy.MAX_STREAM_BYTES,
                                            term_grace=legacy.TERM_GRACE, factory=test_factory)
            commands.append(target)
            last_dispatch = time.monotonic()
            while not target.operation_done and target.name not in tick_failures and time.monotonic() < target.deadline:
                busy = tick()
                if state.failure is None and state.pending is None and time.monotonic() - last_dispatch >= legacy.SAMPLE_INTERVAL_SECONDS:
                    request_scan()
                    last_dispatch = time.monotonic()
                    busy = True
                if not busy and not target.operation_done:
                    time.sleep(legacy.POLL_SECONDS)
            tick()
            # Finish any earlier generation, then require a NEW post-operation
            # census. Pending pre-exit results cannot satisfy this barrier.
            if state.failure is None and state.pending:
                wait_until(lambda: state.pending is None or state.failure,
                           state.pending["deadlineNS"] / 1e9, abort_failure=True)
            if state.failure is None:
                final_scan = request_scan()
                wait_until(lambda: state.completed_scan == final_scan or state.failure,
                           state.pending["deadlineNS"] / 1e9, abort_failure=True)
                final_scan_complete = state.failure is None and state.completed_scan == final_scan
        stop_worker(failed=state.failure is not None)
        wait_until(lambda: worker.operation_done or worker.name in tick_failures,
                   cleanup_started + CLEANUP_SECONDS)
        owners = ([worker] if worker is not None else []) + ([target] if target is not None else [])
        final_groups.update(probe_groups("initial", owners))
        unsafe = [c for c in owners if not group_safe(c) and c.pid is not None
                  and not c.pid_actions_revoked and not c.collected]
        if unsafe:
            fail("Original cleanup did not establish both owned groups")
            for command in unsafe:
                command.stop("unaccounted-owned-group")
            wait_until(lambda: all(c.kill_sent for c in unsafe),
                       time.monotonic() + legacy.TERM_GRACE + legacy.POLL_SECONDS)
            for command in unsafe:
                if not command.kill_sent:
                    command.signal(signal.SIGKILL, group=True)
                    command.kill_sent = True
            tick()
            final_groups.update(probe_groups("after-stop", unsafe))
    except (ProtocolError, progress.EvidenceError, OSError, ValueError, RuntimeError) as caught:
        fail(type(caught).__name__ + ": " + str(caught))
    finally:
        # Every error path still ticks and stops only directly owned leases.
        owners = ([worker] if worker is not None else []) + ([target] if target is not None else [])
        try:
            stop_worker(failed=state.failure is not None)
            for command in owners:
                if not command.terminal:
                    command.stop("session-finalization")
            end = (cleanup_started if cleanup_started is not None else time.monotonic()) + CLEANUP_SECONDS
            wait_until(lambda: all(c.terminal and not c.transport.selector.get_map()
                                  for c in owners if not c.pid_actions_revoked), end)
            if any(not group_safe(c) for c in owners if c.pid is not None and not c.pid_actions_revoked):
                final_groups.update(probe_groups("final", owners))
            for command in [*probes, *owners]:
                if (command.pid is not None and command.terminal and not command.transport.selector.get_map()
                        and not command.pid_actions_revoked and not command.collected
                        and (command in probes or group_safe(command))):
                    try:
                        command.collect()
                        if command is worker:
                            worker_accounted_at = time.monotonic()
                    except (progress.EvidenceError, OSError, ValueError, RuntimeError) as caught:
                        fail("Collection failed: " + str(caught))
                        command.receipt["cleanupFailed"] = True
                elif command.pid is not None and not command.collected:
                    command.receipt["cleanupFailed"] = True
                    fail(command.name + ": missing terminal/stream/group collection evidence")
                    if not command.kill_sent:
                        command.signal(signal.SIGKILL, group=True)
                        command.kill_sent = True
        except (progress.EvidenceError, OSError, ValueError, RuntimeError) as caught:
            fail("Session finalization failed: " + str(caught))
            for command in commands:
                if not command.collected:
                    command.receipt["cleanupFailed"] = True
                    if not command.kill_sent:
                        command.signal(signal.SIGKILL, group=True)
                        command.kill_sent = True
        finally:
            # Closing one resource must never skip the remaining resources.
            for command in commands:
                try:
                    command.close()
                except (OSError, ValueError, RuntimeError) as caught:
                    command.receipt["cleanupFailed"] = True
                    fail(command.name + ": close failed: " + str(caught))
            for message in close_channel_resources():
                fail("Channel close failed: " + message)
    if worker is None:
        guard._fail(legacy.OutputError(state.failure["error"]), code="isolated-observation-failed")
        raise legacy.OutputError("Observer setup failed before owned command initialization")
    worker_cleanup_elapsed = ((worker_accounted_at if worker_accounted_at is not None else time.monotonic())
                              - cleanup_started)
    if worker_accounted_at is None or worker_cleanup_elapsed > CLEANUP_SECONDS:
        cleanup_overrun = True
        fail("Observer not positively accounted for within cleanup budget")
    if not progress.successful(worker):
        fail("Observer did not exit successfully after acknowledged shutdown")
    def clean(command):
        return bool(command is not None and command.collected and group_safe(command)
                    and command.receipt["pidLeaseReleased"] and not command.receipt["pidLeaseLost"]
                    and not command.receipt["cleanupFailed"] and not command.receipt["streamErrors"])
    target_clean, worker_clean = clean(target), clean(worker)
    probes_clean = all(p.collected and not p.receipt["cleanupFailed"] and not p.receipt["streamErrors"] for p in probes)
    cleanup_complete = target_clean and worker_clean and probes_clean and not cleanup_overrun
    observation_complete = bool(startup_complete and final_scan_complete and state.failure is None
                                and state.stopped and channel.eof and not channel.buffer
                                and progress.successful(worker))
    transport_complete = bool(cleanup_complete and observation_complete and target is not None
                              and target.operation_done and target.receipt["stopReason"] is None
                              and target.receipt.get("completionObservedWithinTotalBudget") is True
                              and all(progress.successful(p) for p in probes) and not errors)
    if state.failure:
        guard._fail(legacy.OutputError(state.failure["error"]), code="isolated-observation-failed")
    # Do not let a target-only read permit bypass either child or an unfinished
    # observation. The combined gate is captured privately in IsolatedResult.
    retain = cleanup_complete and observation_complete
    result = {"schema": 1, "adapter": "D29-isolated-atrc-observer",
              "testControlsUsed": test_factory is not None,
              "startupComplete": startup_complete, "initialScanGeneration": initial_scan,
              "finalScanGeneration": final_scan, "finalFreshScanComplete": final_scan_complete,
              "observationComplete": observation_complete,
              "cleanupComplete": cleanup_complete, "transportComplete": transport_complete,
              "targetCleanupComplete": target_clean, "workerCleanupComplete": worker_clean,
              "workerCleanupDeadlineExceeded": cleanup_overrun,
              "workerCleanupBudgetSeconds": CLEANUP_SECONDS,
              "workerCleanupElapsedSeconds": worker_cleanup_elapsed,
              "workerCleanupDeadlineOvershootSeconds": max(0, worker_cleanup_elapsed - CLEANUP_SECONDS),
              "target": target.receipt if target else None, "worker": worker.receipt,
              "finalOwnedGroups": final_groups, "observer": state.summary(), "channel": channel.summary(),
              "channelKernelBuffers": request_buffer_sizes,
              "errors": errors, "supervisionTicks": all_tick_count,
              "maximumObservedSupervisionTickGapSeconds": maximum_tick_gap,
              "elapsedSeconds": time.monotonic() - started,
              "parentCensusDuringCommandSupervision": False,
              "synchronousFilesystemCallsHaveHardDeadline": False,
              "schedulerHasHardDeadline": False,
              "nativeTraceSemanticsEstablished": False}
    streams = {key: bytes(value) for key, value in target.transport.streams.items()} if target else {"stdout": b"", "stderr": b""}
    cleanup_records = [{"name": c.name, "receipt": c.receipt,
                        "streams": {k: bytes(v) for k, v in c.transport.streams.items()}} for c in [worker, *probes]]
    # State histories reserve 3 MiB for fixed receipts while commands run.
    # Enforce the whole serialized worker/probe evidence allocation as well;
    # 4 KiB is reserved for this accounting receipt itself. A cap failure may
    # omit history rows, but never the first failure, pending operation, owned
    # cleanup receipts or raw bounded cleanup streams.
    omitted = 0
    if worker_evidence_bytes(result, cleanup_records) + FRAME_BYTES > DIAGNOSTIC_BYTES:
        fail("Combined worker diagnostic retention limit exceeded")
        guard._fail(legacy.OutputError(state.failure["error"]), code="isolated-observation-failed")
        result.update(observationComplete=False, transportComplete=False, observer=state.summary())
        retain = False
        histories = [result["observer"][key] for key in ("operationHistory", "scanHistory")]
        while worker_evidence_bytes(result, cleanup_records) + FRAME_BYTES > DIAGNOSTIC_BYTES:
            available = next((history for history in histories if history["records"]), None)
            if available is None:
                # Fixed receipts are bounded by the fixed command count,
                # single signal escalation and 64 KiB stream limits. Never
                # return an oversized result if that invariant is violated.
                raise legacy.OutputError("Fixed worker receipts exceed diagnostic allocation")
            index = 128 if len(available["records"]) > 128 else -1
            removed = available["records"].pop(index)
            available["omittedCompletedCount" if removed["completed"] else "omittedFailedCount"] += 1
            omitted += 1
    result["workerEvidence"] = {"maximumBytes": DIAGNOSTIC_BYTES,
                                "retainedPayloadBytes": worker_evidence_bytes(result, cleanup_records),
                                "accountingReceiptReserveBytes": FRAME_BYTES,
                                "historyReceiptReserveBytes": DIAGNOSTIC_RECEIPT_RESERVE,
                                "historyRowsOmittedForByteLimit": omitted,
                                "accounting": "compact UTF-8 metadata plus raw worker/probe streams"}
    return IsolatedResult(result, streams, cleanup_records, guard, retain)
