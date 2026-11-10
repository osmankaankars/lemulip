#!/usr/bin/env python3
"""D30 real worker/socket backpressure qualification over disposable output.

The live API never substitutes process-group evidence or filesystem/report
operations. Its pass-through factory supplies inherited descriptors to the
frozen D29 worker and executes the actual /bin/ps command for owned cleanup.
The report channel is deliberately not consumed after one census dispatch.
"""
from __future__ import annotations

import errno
import json
import os
from pathlib import Path
import signal
import socket
import sys
import time
import uuid

import native_retained_atrc_isolated as isolated
import native_retained_atrc_output as output
import native_retained_atrc_worker as worker
import native_retained_trace_command as command
import run_native_recorder_progress_observation as progress


NAME = "pressure-worker"
FILE_COUNT = 128
SOCKET_SEND_REQUEST = 4096
SOCKET_SEND_MAXIMUM = 65536
REPORT_BYTES = 65536
STARTUP_SECONDS = 2.0
TOTAL_SECONDS = 5.0
RESERVE_SECONDS = 2.0
PS_ARGV = ("/bin/ps", "-A", "-o", "pid=,pgid=,stat=")


def _leader_visible(receipt):
    """Absence alone cannot establish the retained zombie-leader contract."""
    group = (receipt.get("finalOwnedGroups") or {}).get(NAME, {})
    pid = receipt.get("pid")
    leaders = [row for row in group.get("members", []) if row.get("pid") == pid]
    return bool(type(pid) is int and group.get("pidLeaseHeldAtSnapshot") is True
                and group.get("noLiveMembersObserved") is True and len(leaders) == 1
                and leaders[0].get("pgid") == pid
                and isinstance(leaders[0].get("state"), str)
                and leaders[0]["state"].startswith("Z"))


def _prefix(raw, *, nonce, identity, limits, pid, ready_received_ns, dispatched_ns):
    """Check retained syntax/lifecycle, without inventing live receive clocks."""
    rows, errors = [], []
    parts = raw.split(b"\n")
    tail = parts.pop()
    state = isolated.ObserverState(nonce, identity, limits, pid)
    request = None
    for index, part in enumerate(parts):
        try:
            row = isolated.decode_report(part)
            # Postmortem scan reports were intentionally withheld. Worker
            # clock samples validate ordering only, never timely receipt.
            received = ready_received_ns if index == 0 else row["clockNS"]
            state.accept(row, received)
            rows.append(row)
            if index == 0:
                if row["kind"] != "ready" or dispatched_ns is None:
                    raise isolated.ProtocolError("Missing bound ready/dispatch")
                request = state.dispatch(dispatched_ns)
        except (ValueError, KeyError, TypeError, OSError) as caught:
            errors.append(type(caught).__name__ + ": " + str(caught)[:512])
            break
    if len(tail) >= worker.FRAME_BYTES:
        errors.append("Trailing partial frame exceeds frame limit")
    return {"records": rows, "completeFrameCount": len(parts),
            "trailingPartialBytes": len(tail), "errors": errors,
            "orderedBoundPrefix": not errors and bool(rows) and len(rows) == len(parts),
            "scanStarted": any(row["kind"] == "scan_started" for row in rows),
            "operationStarted": any(row["kind"] == "op_started" for row in rows),
            "completedScanCount": sum(row["kind"] == "scan_completed" for row in rows),
            "pendingOperation": state.pending_operation,
            "request": request,
            "receiveTimeDeadlineValidationClaimed": False,
            "meaning": "Postmortem report identity, sequence and operation ordering only; scan reports were deliberately not received live."}


def _recover_exception(transport, *, cwd, env, errors):
    """Bound cleanup after an unexpected adapter exception, under the held lease.

    This path never qualifies the pressure case. A lost lease forbids later
    PID actions; collection still requires a real no-live group snapshot.
    """
    receipts = []
    child = transport.process
    receipt = transport.receipt
    if child is None or child.returncode is not None or receipt.get("pidDirectedActionsRevoked"):
        return receipts
    try:
        os.waitid(os.P_PID, child.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)
    except (OSError, AttributeError) as caught:
        if isinstance(caught, ChildProcessError) or getattr(caught, "errno", None) == errno.ECHILD:
            receipt.update(pidLeaseLost=True, pidDirectedActionsRevoked=True)
        errors.append("Recovery lease probe failed: " + type(caught).__name__)
        return receipts
    transport.signal(signal.SIGKILL, group=True)
    terminal = None
    until = time.monotonic() + 2.0
    try:
        while time.monotonic() < until:
            transport.drain()
            terminal = os.waitid(os.P_PID, child.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)
            if terminal is not None and not transport.selector.get_map():
                break
            time.sleep(.005)
        if terminal is None or transport.selector.get_map():
            errors.append("Recovery child/streams remain unaccounted")
            return receipts
        if terminal.si_pid != child.pid or terminal.si_code not in (os.CLD_EXITED, os.CLD_KILLED, os.CLD_DUMPED):
            errors.append("Recovery terminal event does not bind the owned child")
            return receipts
        expected_code = terminal.si_status if terminal.si_code == os.CLD_EXITED else -terminal.si_status
        group_receipt, streams, cleanup = command.capture_owned(
            "pressure-recovery-ps", PS_ARGV, cwd=cwd, env=env,
            budget=2.0, reserve=.5, limit=65536)
        receipts.append({"name": "pressure-recovery-ps", "receipt": group_receipt, "streams": streams})
        receipts.extend(cleanup)
        rows = [line.split() for line in streams["stdout"].decode("ascii").splitlines() if line.strip()]
        if not (group_receipt.get("transportComplete") and group_receipt.get("exitCode") == 0
                and not streams["stderr"] and rows
                and all(len(row) == 3 and row[0].isdigit() and row[1].isdigit() for row in rows)):
            errors.append("Recovery group probe lacks complete valid evidence")
            return receipts
        members = [row for row in rows if int(row[1]) == child.pid]
        if not (any(int(row[0]) == child.pid for row in members)
                and all(row[2].startswith("Z") for row in members)):
            errors.append("Recovery group does not show held zombie leader and no live members")
            return receipts
        receipt.update(pidDirectedActionsRevoked=True, recoveryCollection=True,
                       recoveryGroupMembers=members)
        transport.reap_deferred = False
        code = transport.poll()
        receipt.update(pidLeaseReleased=code is not None, exitCode=code,
                       recoveryCollectedExitMatchesPeek=code == expected_code,
                       recoveryCollectedClock=progress.clock())
        if code != expected_code:
            receipt["pidLeaseLost"] = True
            errors.append("Recovery collected exit differs from non-reaping terminal witness")
    except (OSError, ValueError, RuntimeError, AttributeError) as caught:
        if isinstance(caught, ChildProcessError) or getattr(caught, "errno", None) == errno.ECHILD:
            receipt.update(pidLeaseLost=True, pidDirectedActionsRevoked=True)
        errors.append("Recovery failed: " + type(caught).__name__ + ": " + str(caught)[:256])
    return receipts


def run_pressure_case(case_root: Path, env: dict) -> dict:
    """Run one real worker; return failed evidence rather than retrying a case.

    ``case_root`` must exist; ``observed`` must not. The return contains
    ``receipt``, byte-valued ``streams``, ``cleanup_records``, JSON-serializable
    ``details``, and bounded byte-valued ``report_raw``.
    """
    case_root = Path(case_root).resolve(strict=True)
    progress.require(case_root.is_dir(), "Pressure case directory is missing")
    progress.require(isinstance(env, dict) and all(isinstance(k, str) and isinstance(v, str)
                     for k, v in env.items()), "Pressure environment must be a string mapping")
    guard = None
    request_read = request_write = reader = writer = None
    target_transport = None
    primary_count = 0
    receipt, streams, cleanup_records = {}, {"stdout": b"", "stderr": b""}, []
    errors, lease_snapshots = [], []
    raw = bytearray()
    ready_buffer = bytearray()
    report_eof = False
    ready_received_ns = dispatched_ns = None
    ready_bound = False
    request_attempts = 0
    request_sent = False
    report_reads_after_dispatch = 0
    report_limit_exceeded = False
    state = None
    nonce = uuid.uuid4().hex
    buffers = {}

    def note(message):
        text = str(message)[:512]
        if text not in errors:
            errors.append(text)

    def close_child_ends():
        nonlocal request_read, writer
        if request_read is not None:
            descriptor, request_read = request_read, None
            try:
                os.close(descriptor)
            except OSError as caught:
                note("Parent request-read close failed: " + str(caught))
        if writer is not None:
            endpoint, writer = writer, None
            try:
                endpoint.close()
            except OSError as caught:
                note("Parent report-writer close failed: " + str(caught))

    def handshake_tick():
        nonlocal state, ready_bound, ready_received_ns, dispatched_ns
        nonlocal request_attempts, request_sent
        nonlocal report_reads_after_dispatch
        close_child_ends()
        if request_attempts or errors:
            return
        transport = target_transport
        if not (transport.reap_deferred and transport.receipt.get("pidLeaseAcquired") is True
                and transport.process is not None and transport.process.returncode is None):
            note("Ready handling attempted without retained child lease")
            return
        if time.monotonic() >= transport.started + STARTUP_SECONDS:
            note("Pressure worker ready deadline exceeded")
            return
        try:
            if dispatched_ns is not None:
                report_reads_after_dispatch += 1
            chunk = reader.recv(worker.FRAME_BYTES + 1 - len(ready_buffer))
        except BlockingIOError:
            return
        if not chunk:
            note("Report EOF before bound ready")
            return
        raw.extend(chunk)
        ready_buffer.extend(chunk)
        if len(ready_buffer) > worker.FRAME_BYTES:
            note("Oversized ready frame")
            return
        if b"\n" not in ready_buffer:
            return
        line, _, remaining = ready_buffer.partition(b"\n")
        if remaining:
            note("Unexpected report before census dispatch")
            return
        ready_received_ns = time.monotonic_ns()
        message = isolated.decode_report(bytes(line))
        state = isolated.ObserverState(nonce, identity, guard.limits, transport.process.pid)
        state.accept(message, ready_received_ns)
        if not state.ready:
            note("First report is not a bound ready message")
            return
        ready_bound = True
        dispatched_ns = time.monotonic_ns()
        request = worker.encode_frame(state.dispatch(dispatched_ns))
        request_attempts += 1
        count = os.write(request_write, request)
        if count != len(request):
            note("Pressure scan request write was partial")
            return
        request_sent = True

    def factory(name, argv, *, cwd, env, limit):
        nonlocal target_transport, primary_count
        if name == NAME:
            primary_count += 1
            progress.require(primary_count == 1, "Pressure worker cannot be relaunched")
            target_transport = isolated.DescriptorTransport(argv, cwd=cwd, env=env,
                                                            limit=limit, inherited=inherited)
            original_drain = target_transport.drain
            def drain():
                original_drain()
                try:
                    handshake_tick()
                except (OSError, ValueError, RuntimeError) as caught:
                    note("Pressure ready/dispatch failed: " + type(caught).__name__ + ": " + str(caught))
            target_transport.drain = drain
            return target_transport
        progress.require(tuple(argv) == PS_ARGV, "Pressure group probe argv changed")
        child = target_transport.process
        witness = {"probe": name, "pid": child.pid if child else None,
                   "returncodeBeforeProbe": child.returncode if child else None,
                   "pidLeaseAcquired": target_transport.receipt.get("pidLeaseAcquired"),
                   "pidDirectedActionsRevoked": target_transport.receipt.get("pidDirectedActionsRevoked")}
        if child is not None and not witness["pidDirectedActionsRevoked"]:
            try:
                observed = os.waitid(os.P_PID, child.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)
                witness["waitable"] = observed is not None
                witness["pgid"] = os.getpgid(child.pid)
            except (OSError, AttributeError) as caught:
                witness["error"] = type(caught).__name__
                note("Pressure group lease witness failed: " + type(caught).__name__)
        lease_snapshots.append(witness)
        return progress.startup.MonitoredCommand(argv, cwd=cwd, env=env, limit=limit)

    try:
        guard = output.OutputGuard(case_root / "observed")
        identity = list(output._anchor_identity(guard.initial_root))
        for index in range(FILE_COUNT):
            (guard.root / ("item-%03d.bin" % index)).write_bytes(b"x")
        request_read, request_write = os.pipe()
        reader, writer = socket.socketpair()
        os.set_blocking(request_write, False)
        reader.setblocking(False)
        writer.setblocking(False)
        writer.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, SOCKET_SEND_REQUEST)
        buffers = {"requestedSendBytes": SOCKET_SEND_REQUEST,
                   "actualSendBytes": writer.getsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF),
                   "actualReceiveBytes": reader.getsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF)}
        progress.require(0 < buffers["actualSendBytes"] <= SOCKET_SEND_MAXIMUM,
                         "Pressure send buffer exceeds fixed qualification bound")
        inherited = (guard.fd, request_read, writer.fileno())
        argv = (sys.executable, "-u", str(Path(worker.__file__).resolve(strict=True)),
                "--root", str(guard.root), "--root-fd", str(guard.fd),
                "--request-fd", str(request_read), "--report-fd", str(writer.fileno()),
                "--nonce", nonce, "--identity", json.dumps(identity),
                "--limits", json.dumps(guard.limits))
        receipt, streams, cleanup_records = command.capture_owned(
            NAME, argv, cwd=case_root, env=env, budget=TOTAL_SECONDS,
            reserve=RESERVE_SECONDS, limit=65536, test_factory=factory)
        # All capture-owned phases are over before the first post-dispatch
        # report read. Retain a bounded prefix even if qualification failed.
        while len(raw) <= REPORT_BYTES:
            try:
                chunk = reader.recv(REPORT_BYTES + 1 - len(raw))
            except BlockingIOError:
                break
            if not chunk:
                report_eof = True
                break
            raw.extend(chunk)
            if len(raw) > REPORT_BYTES:
                report_limit_exceeded = True
                del raw[REPORT_BYTES:]
                break
    except Exception as caught:
        if target_transport is None or target_transport.process is None:
            raise
        note("Pressure capture failed: " + type(caught).__name__ + ": " + str(caught))
        receipt = target_transport.receipt
        receipt["cleanupComplete"] = False
        receipt["transportComplete"] = False
        cleanup_records.extend(_recover_exception(target_transport, cwd=case_root, env=env, errors=errors))
        streams = {key: bytes(value) for key, value in target_transport.streams.items()}
    finally:
        close_child_ends()
        if request_write is not None:
            try:
                os.close(request_write)
            except OSError as caught:
                note("Request writer close failed: " + str(caught))
        if reader is not None:
            try:
                reader.close()
            except OSError as caught:
                note("Report reader close failed: " + str(caught))
        if target_transport is not None:
            try:
                target_transport.close()
            except (OSError, ValueError, RuntimeError) as caught:
                note("Pressure transport close failed: " + str(caught))
        if guard is not None:
            try:
                guard.close()
            except (OSError, ValueError, RuntimeError) as caught:
                note("Pressure root descriptor close failed: " + str(caught))

    prefix = {"records": [], "orderedBoundPrefix": False, "scanStarted": False,
              "operationStarted": False, "completedScanCount": 0,
              "errors": ["Ready and dispatch were not established"]}
    if ready_bound and dispatched_ns is not None:
        prefix = _prefix(bytes(raw), nonce=nonce, identity=identity, limits=guard.limits,
                         pid=receipt.get("pid"), ready_received_ns=ready_received_ns,
                         dispatched_ns=dispatched_ns)
    stderr = streams["stderr"]
    failure_prefix = b"Observer worker failed: WorkerError: Required report unavailable: "
    required_failure = stderr.strip() in (failure_prefix + b"BlockingIOError", failure_prefix + b"WorkerError")
    checks = {
        "ready_bound": ready_bound,
        "request_sent_once": request_sent and request_attempts == 1,
        "report_reads_withheld": request_sent and report_reads_after_dispatch == 0,
        "natural_worker_exit_2": receipt.get("exitCode") == 2 and receipt.get("stopReason") is None,
        "worker_stdout_empty": streams["stdout"] == b"",
        "required_report_write_failed": required_failure,
        "ordered_bound_prefix": prefix["orderedBoundPrefix"],
        "scan_operation_started": prefix["scanStarted"] and prefix["operationStarted"],
        "no_completed_scan": prefix["completedScanCount"] == 0,
        "report_eof": report_eof,
        "report_within_limit": not report_limit_exceeded and len(raw) <= REPORT_BYTES,
        "leader_visible_while_leased": _leader_visible(receipt),
        "lease_witnesses_valid": bool(lease_snapshots) and all(
            row.get("pidLeaseAcquired") is True and row.get("pidDirectedActionsRevoked") is False
            and row.get("returncodeBeforeProbe") is None and row.get("waitable") is True
            and row.get("pid") == row.get("pgid") and not row.get("error") for row in lease_snapshots),
        "cleanup_complete": receipt.get("cleanupComplete") is True,
        "transport_complete": receipt.get("transportComplete") is True,
        "no_harness_errors": not errors,
    }
    details = {"case": "real-worker-report-backpressure", "passed": all(checks.values()),
               "checks": checks, "errors": errors, "socketBuffers": buffers,
               "syntheticWorkload": True, "groupEnumeration": "real-bin-ps",
               "fileCount": FILE_COUNT, "logicalInputBytes": FILE_COUNT,
               "normalBudgetSeconds": TOTAL_SECONDS - RESERVE_SECONDS,
               "totalBudgetSeconds": TOTAL_SECONDS, "startupBudgetSeconds": STARTUP_SECONDS,
               "readyReceivedNS": ready_received_ns, "scanDispatchedNS": dispatched_ns,
               "scanDeadlineNS": dispatched_ns + worker.SCAN_NS if dispatched_ns else None,
               "scanRequestAttempts": request_attempts, "postDispatchLiveReportReads": report_reads_after_dispatch,
               "reportBytes": len(raw), "maximumReportBytes": REPORT_BYTES,
               "reportEOF": report_eof, "reportLimitExceeded": report_limit_exceeded,
               "leaseSnapshots": lease_snapshots, "prefixLifecycle": prefix,
               "noRetryMeaning": "One census request; the frozen worker exits after its first unavailable required report. No second worker or scan is launched.",
               "nativeTraceSemanticsEstablished": False}
    return {"receipt": receipt, "streams": streams, "cleanup_records": cleanup_records,
            "details": details, "report_raw": bytes(raw)}
