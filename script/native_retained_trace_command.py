#!/usr/bin/env python3
"""D25 finite installed-command capture with a retained PID lease.

This adapter reuses D24's transport unchanged. It starts no recording and does
not interpret exported data. Its caller supplies the fixed diagnostic command.
"""
from __future__ import annotations

import errno
import math
from pathlib import Path
import signal
import time

import run_native_recorder_progress_observation as progress


MAX_STREAM_BYTES = 8 * 1024 * 1024
GROUP_BUDGET = 2.0
GROUP_LIMIT = 65536
TERM_GRACE = .25
POLL_SECONDS = .005


def capture_owned(name, argv, *, cwd: Path, env: dict, budget=33.0, reserve=3.0,
                  limit=MAX_STREAM_BYTES, test_factory=None):
    """Return ``(receipt, streams, cleanup_records)`` for one finite command.

    All streams are bytes. Cleanup records contain ``name``, ``receipt`` and
    ``streams`` and must be retained by the caller. A natural nonzero exit can
    complete this transport; timeout, truncated output or emergency cleanup
    cannot. No stderr-content policy is imposed on the target command.
    """
    progress.require(isinstance(name, str) and name and len(name) <= 100,
                     "Command name is missing or oversized")
    argv = tuple(argv)
    progress.require(argv and all(isinstance(item, str) and item and "\0" not in item for item in argv),
                     "Command arguments are invalid")
    progress.require(all(type(value) in (int, float) and math.isfinite(value)
                         for value in (budget, reserve))
                     and 0 < reserve < budget <= 33,
                     "Command budget must be finite and at most 33 seconds")
    progress.require(type(limit) is int and 0 < limit <= MAX_STREAM_BYTES,
                     "Command output bound is invalid")
    cwd = Path(cwd).resolve(strict=True)
    progress.require(cwd.is_dir(), "Command working directory is not a directory")

    target = progress.OwnedCommand(name, argv, cwd=cwd, env=env, budget=budget,
                                   reserve=reserve, limit=limit, term_grace=TERM_GRACE,
                                   factory=test_factory)
    commands = [target]
    probes = []
    errors = []
    tick_failures = set()
    final_groups = None
    initial_groups = None
    emergency = False
    group_safe = False

    def error(message):
        if message not in errors:
            errors.append(message)

    def tick_all():
        for command in commands:
            if command.name in tick_failures:
                continue
            try:
                command.tick()
            except (progress.EvidenceError, OSError, ValueError, RuntimeError) as caught:
                tick_failures.add(command.name)
                command.receipt["cleanupFailed"] = True
                error(command.name + ": tick failed: " + type(caught).__name__ + ": " + str(caught))

    def finish_operation(command):
        while (not command.operation_done and command.name not in tick_failures
               and time.monotonic() < command.deadline):
            tick_all()
            if not command.operation_done:
                time.sleep(POLL_SECONDS)
        # The final tick records actual deadline overshoot; do not relabel a
        # late observation as having completed within the original bound.
        tick_all()

    def probe(suffix):
        progress.require(not target.pid_actions_revoked and not target.collected,
                         "Target PID lease is unavailable for group inspection")
        command = progress.OwnedCommand(
            name + "-" + suffix, ("/bin/ps", "-A", "-o", "pid=,pgid=,stat="),
            cwd=cwd, env=env, budget=GROUP_BUDGET, reserve=.5,
            limit=GROUP_LIMIT, term_grace=TERM_GRACE, factory=test_factory,
        )
        commands.append(command)
        probes.append(command)
        finish_operation(command)
        progress.require(not target.pid_actions_revoked and not target.collected,
                         "Target PID lease was lost during group inspection")
        return progress.group_inventory(command, [target])

    def usable_group(groups):
        return (groups is not None
                and groups.get(name, {}).get("pidLeaseHeldAtSnapshot") is True
                and groups[name].get("noLiveMembersObserved") is True)

    try:
        if target.pid is None:
            error("Target command did not start")
        else:
            finish_operation(target)
            if not target.pid_actions_revoked:
                try:
                    initial_groups = final_groups = probe("owned-groups")
                    group_safe = usable_group(final_groups)
                except (progress.EvidenceError, OSError, ValueError, UnicodeError, RuntimeError) as caught:
                    error("Initial owned-group inventory failed: " + str(caught))
                if not group_safe and not target.pid_actions_revoked:
                    # An exited leader with closed streams can leave a silent
                    # descendant. Cleanup never turns this original miss into
                    # a successful operation or an extended operation budget.
                    emergency = True
                    error("Original operation did not establish a clean owned group")
                    target.receipt["emergencyGroupCleanup"] = True
                    target.signal(signal.SIGTERM, group=True)
                    force_at = time.monotonic() + TERM_GRACE
                    while time.monotonic() < force_at:
                        tick_all()
                        time.sleep(POLL_SECONDS)
                    target.signal(signal.SIGKILL, group=True)
                    target.kill_sent = True
                    tick_all()
                    try:
                        final_groups = probe("owned-groups-after-cleanup")
                        group_safe = usable_group(final_groups)
                    except (progress.EvidenceError, OSError, ValueError, UnicodeError, RuntimeError) as caught:
                        error("Final owned-group inventory failed: " + str(caught))
            else:
                error("Target PID lease was lost; no further PID-directed actions are allowed")
    finally:
        # Normally all operations ended within their independent bounds. If an
        # inventory probe itself failed, one final nonblocking tick and signal
        # attempt may stop its still-owned child; no unbounded wait is allowed.
        for command in commands:
            if command.pid is None or command.collected or command.pid_actions_revoked:
                continue
            if not command.terminal or command.transport.selector.get_map():
                command.signal(signal.SIGKILL, group=True)
                command.kill_sent = True
        tick_all()

        target_terminal = bool(target.terminal and not target.transport.selector.get_map())
        failures = target.receipt["signalErrors"]
        if (group_safe and target_terminal and failures
                and all(item.get("errno") == errno.EPERM and item.get("target") == "owned-group"
                        for item in failures)
                and not target.receipt["cleanupFailureReasons"] and not tick_failures):
            target.receipt["cleanupFailed"] = False
            target.receipt["signalFailureResolvedByNoLiveOwnedGroup"] = True

        # A trusted /bin/ps probe has no numeric-PID dependents. Its final
        # collection is separate from the target's positive group evidence.
        for command in [*probes, target]:
            if command.pid is None:
                continue
            can_collect = (command.terminal and not command.transport.selector.get_map()
                           and not command.pid_actions_revoked and not command.collected
                           and (command is not target or group_safe))
            if can_collect:
                try:
                    command.collect()
                except (progress.EvidenceError, OSError, ValueError, RuntimeError) as caught:
                    error(command.name + ": collection failed: " + str(caught))
                    command.receipt["cleanupFailed"] = True
            else:
                error(command.name + ": collection lacks terminal/closed-stream/owned-group evidence")
                command.receipt["cleanupFailed"] = True
        for command in commands:
            try:
                command.close()
            except (progress.EvidenceError, OSError, ValueError, RuntimeError) as caught:
                error(command.name + ": close failed: " + str(caught))
                command.receipt["cleanupFailed"] = True

    cleanup_complete = bool(target.pid is not None and group_safe
                            and all(command.collected and command.receipt["pidLeaseReleased"]
                                    and not command.receipt["pidLeaseLost"]
                                    and not command.receipt["streamErrors"]
                                    and not command.receipt["cleanupFailed"]
                                    for command in commands))
    transport_complete = bool(cleanup_complete and not emergency and not errors
                              and target.operation_done and target.terminal
                              and target.receipt["stopReason"] is None
                              and target.receipt.get("completionObservedWithinTotalBudget") is True
                              and all(progress.successful(probe) for probe in probes))
    target.receipt.update(
        adapter="D25-retained-trace-owned-command", testFactoryUsed=test_factory is not None,
        transportComplete=transport_complete, cleanupComplete=cleanup_complete,
        adapterErrors=errors, ownedGroupsBeforeEmergencyCleanup=initial_groups if emergency else None,
        finalOwnedGroups=final_groups, emergencyCleanupRequired=emergency,
        groupProbeTotalBudgetSeconds=GROUP_BUDGET,
        emergencyTERMGraceSeconds=TERM_GRACE,
        maximumAdapterWallBudgetSeconds=budget + 2 * GROUP_BUDGET + TERM_GRACE,
        adapterElapsedSeconds=time.monotonic() - target.started,
        descendantExitTimesWithinOperationBudgetEstablished=False,
        groupSnapshotMeaning="No live members at the snapshot; no retrospective descendant-exit timestamp.",
    )
    cleanup_records = [
        {"name": command.name, "receipt": command.receipt,
         "streams": {key: bytes(value) for key, value in command.transport.streams.items()}}
        for command in probes
    ]
    return target.receipt, {key: bytes(value) for key, value in target.transport.streams.items()}, cleanup_records
