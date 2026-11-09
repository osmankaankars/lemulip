#!/usr/bin/env python3
"""D27 sampled output bounds and stable retention for one derived import.

The observer is a sampled stop policy, not a filesystem quota or a guarantee
about writes outside its newly owned directory. It never follows a link.
"""
from __future__ import annotations

from collections import deque
import errno
import hashlib
import json
import math
import os
from pathlib import Path
import signal
import stat
import tempfile
import time
import zipfile

import run_native_recorder_progress_observation as progress


MAX_STREAM_BYTES = 8 * 1024 * 1024
GROUP_BUDGET = 2.0
GROUP_LIMIT = 65536
TERM_GRACE = .25
POLL_SECONDS = .005
NORMAL_SECONDS = 90.0
TOTAL_SECONDS = 95.0
SAMPLE_INTERVAL_SECONDS = .05
SCAN_SECONDS = .25
RETENTION_SECONDS = 30.0
CHUNK_BYTES = 65536
LIMITS = {"logicalBytes": 512 * 1024 * 1024,
          "allocatedBytes": 512 * 1024 * 1024,
          "entries": 16384, "depth": 32, "pathBytes": 1024}


class OutputError(ValueError):
    pass


def _identity(info):
    return (info.st_dev, info.st_ino, info.st_mode, info.st_size,
            info.st_mtime_ns, info.st_ctime_ns, info.st_nlink)


def _anchor_identity(info):
    return info.st_dev, info.st_ino, info.st_mode


def _clock_check(deadline):
    if time.monotonic() >= deadline:
        raise OutputError("Output observation or retention deadline exceeded")


def _component(name):
    if (not isinstance(name, str) or name in ("", ".", "..")
            or any(c in name for c in ("/", "\\", ":", "\0"))
            or any(ord(c) < 32 or ord(c) == 127 for c in name)):
        raise OutputError("Output entry name is unsafe")
    try:
        raw = name.encode("utf-8", errors="strict")
    except UnicodeError as error:
        raise OutputError("Output entry name is not strict UTF-8") from error
    if len(raw) > 255:
        raise OutputError("Output component byte bound exceeded")


class _ArchiveIO:
    """Bound every archive read/write, including zipfile's central directory."""
    def __init__(self, raw, deadline, maximum, maximum_read):
        self.raw = raw
        self.deadline = deadline
        self.maximum = maximum
        self.maximum_read = maximum_read
        self.read_bytes = 0

    def __getattr__(self, name):
        return getattr(self.raw, name)

    def read(self, size=-1):
        _clock_check(self.deadline)
        if size < 0:
            size = self.maximum - self.raw.tell() + 1
        if size > self.maximum:
            raise OutputError("Archive read request exceeds its bound")
        result = self.raw.read(size)
        self.read_bytes += len(result)
        if self.read_bytes > self.maximum_read:
            raise OutputError("Aggregate archive read bound exceeded")
        _clock_check(self.deadline)
        return result

    def write(self, data):
        _clock_check(self.deadline)
        if self.raw.tell() + len(data) > self.maximum:
            raise OutputError("Archive byte bound exceeded")
        written = self.raw.write(data)
        _clock_check(self.deadline)
        return written

    def seek(self, offset, whence=0):
        _clock_check(self.deadline)
        result = self.raw.seek(offset, whence)
        if result < 0 or result > self.maximum:
            raise OutputError("Archive seek exceeds its bound")
        return result

    def tell(self):
        _clock_check(self.deadline)
        return self.raw.tell()

    def flush(self):
        _clock_check(self.deadline)
        return self.raw.flush()


class OutputGuard:
    def __init__(self, root: Path, intended_name="derived.trace", *, test_limits=None):
        root = Path(root)
        progress.require(root.is_absolute() and root.name not in ("", ".", ".."),
                         "Require a new absolute derived-output parent")
        _component(root.name)
        _component(intended_name)
        progress.require(intended_name.endswith(".trace"), "Require a .trace target name")
        self.root = root.parent.resolve(strict=True) / root.name
        self.target = self.root / intended_name
        self.intended_name = intended_name
        self.limits = dict(LIMITS)
        self.synthetic_limits = test_limits is not None
        for key, value in (test_limits or {}).items():
            progress.require(key in LIMITS and type(value) is int and 0 < value <= LIMITS[key],
                             "Synthetic output bounds may only tighten declared bounds")
            self.limits[key] = value
        os.mkdir(self.root, 0o700)
        self.fd = os.open(self.root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        self.initial_root = os.fstat(self.fd)
        progress.require(stat.S_IMODE(self.initial_root.st_mode) == 0o700,
                         "Require an exclusive0700 output parent")
        self.closed = False
        self.capture_started = False
        self.finalized = False
        self.failure = None
        self.scan_count = 0
        self.last_scan_started = None
        self.last_scan = None
        self.max_scan_seconds = 0.0
        self.max_sample_gap = 0.0
        self.high_water = {"logicalBytes": 0, "allocatedBytes": 0, "entries": 0, "depth": 0}
        self.first_observations = []
        self.last_observations = deque(maxlen=128)
        self.sample(force=True)
        if self.failure is not None:
            self.close()
            raise OutputError(self.failure["error"])

    def _anchor(self):
        if self.closed:
            raise OutputError("Derived-output descriptor was closed")
        opened = os.fstat(self.fd)
        current = os.stat(self.root, follow_symlinks=False)
        if (_anchor_identity(opened) != _anchor_identity(self.initial_root)
                or _anchor_identity(current) != _anchor_identity(opened)):
            raise OutputError("Derived-output root identity or mode changed")

    def _scan(self, deadline, *, stable=False):
        self._anchor()
        rows = []
        totals = {"logicalBytes": 0, "allocatedBytes": 0, "entries": 0, "depth": 0}
        device = self.initial_root.st_dev

        def walk(fd, relative, depth):
            _clock_check(deadline)
            before = os.fstat(fd)
            add(before, relative, depth, "directory")
            with os.scandir(fd) as children:
                for entry in children:
                    _clock_check(deadline)
                    _component(entry.name)
                    child = entry.name if relative == "." else relative + "/" + entry.name
                    if len(child.encode("utf-8")) > self.limits["pathBytes"]:
                        raise OutputError("Output relative-path byte bound exceeded")
                    metadata = os.stat(entry.name, dir_fd=fd, follow_symlinks=False)
                    if stat.S_ISDIR(metadata.st_mode):
                        nested = os.open(entry.name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                                         dir_fd=fd)
                        try:
                            if _anchor_identity(metadata) != _anchor_identity(os.fstat(nested)):
                                raise OutputError("Output directory changed before opening")
                            walk(nested, child, depth + 1)
                        finally:
                            os.close(nested)
                    elif stat.S_ISREG(metadata.st_mode):
                        if metadata.st_nlink != 1:
                            raise OutputError("Output regular file has more than one link")
                        add(metadata, child, depth + 1, "file")
                    else:
                        raise OutputError("Output contains a symlink or special file")
            if stable and _identity(before) != _identity(os.fstat(fd)):
                raise OutputError("Output directory changed during stable inventory")

        def add(info, relative, depth, kind):
            _clock_check(deadline)
            if info.st_dev != device:
                raise OutputError("Output crossed a filesystem device")
            if depth > self.limits["depth"]:
                raise OutputError("Output depth bound exceeded")
            if not hasattr(info, "st_blocks") or info.st_blocks < 0 or info.st_size < 0:
                raise OutputError("Output allocation accounting is unavailable")
            totals["entries"] += 1
            totals["depth"] = max(totals["depth"], depth)
            totals["logicalBytes"] += info.st_size if kind == "file" else 0
            totals["allocatedBytes"] += info.st_blocks * 512
            for key in ("entries", "logicalBytes", "allocatedBytes"):
                self.high_water[key] = max(self.high_water[key], totals[key])
                if totals[key] > self.limits[key]:
                    raise OutputError("Output " + key + " bound exceeded")
            self.high_water["depth"] = max(self.high_water["depth"], depth)
            rows.append({"path": relative, "kind": kind,
                         "mode": stat.S_IMODE(info.st_mode),
                         "bytes": info.st_size if kind == "file" else 0,
                         "allocatedBytes": info.st_blocks * 512,
                         "device": info.st_dev, "inode": info.st_ino,
                         "mtimeNs": info.st_mtime_ns, "ctimeNs": info.st_ctime_ns,
                         "links": info.st_nlink, "_identity": _identity(info)})

        walk(self.fd, ".", 0)
        self._anchor()
        _clock_check(deadline)
        rows.sort(key=lambda item: item["path"])
        _clock_check(deadline)
        return {"totals": totals, "entries": rows}

    def _fail(self, error, *, code="derived-output-observation-failed"):
        if self.failure is None:
            self.failure = {"code": code, "error": type(error).__name__ + ": " + str(error),
                            "clock": progress.clock()}

    def sample(self, *, force=False):
        if self.failure is not None:
            return False
        started = time.monotonic()
        if not force and self.last_scan_started is not None and started - self.last_scan_started < SAMPLE_INTERVAL_SECONDS:
            return True
        if self.last_scan_started is not None:
            self.max_sample_gap = max(self.max_sample_gap, started - self.last_scan_started)
        self.last_scan_started = started
        observed = {"startedClock": progress.clock()}
        try:
            snapshot = self._scan(started + SCAN_SECONDS)
            observed.update(snapshot["totals"])
            self.last_scan = snapshot
            self.scan_count += 1
        except (OSError, ValueError, RuntimeError) as error:
            self._fail(error)
        finally:
            elapsed = time.monotonic() - started
            self.max_scan_seconds = max(self.max_scan_seconds, elapsed)
            observed.update(elapsedSeconds=elapsed, completed=self.failure is None,
                            endedClock=progress.clock(),
                            scanDeadlineOvershootSeconds=max(0.0, elapsed-SCAN_SECONDS))
            if len(self.first_observations) < 128:
                self.first_observations.append(observed)
            else:
                self.last_observations.append(observed)
        return self.failure is None

    def begin_capture(self, *, synthetic=False):
        progress.require(not self.capture_started, "An OutputGuard cannot run a second import")
        progress.require(synthetic or not self.synthetic_limits, "Synthetic bounds are not native evidence")
        self.capture_started = True
        self.last_scan_started = None
        self.max_sample_gap = 0.0
        progress.require(self.sample(force=True), "Initial derived-output observation failed")
        progress.require(self.last_scan["totals"]["entries"] == 1,
                         "Derived-output parent must still be empty before import")

    def summary(self):
        observations = self.first_observations + list(self.last_observations)
        retained_completed = sum(row["completed"] for row in observations)
        return {"schema": 1, "root": str(self.root), "target": str(self.target),
                "limits": dict(self.limits), "syntheticLimitsUsed": self.synthetic_limits,
                "sampleIntervalSeconds": SAMPLE_INTERVAL_SECONDS,
                "perScanBudgetSeconds": SCAN_SECONDS, "completedScanCount": self.scan_count,
                "sampleGapScope": "Capture start onward; excludes time between guard creation and capture",
                "maximumObservedScanSeconds": self.max_scan_seconds,
                "maximumObservedSampleStartGapSeconds": self.max_sample_gap,
                "highWaterObserved": dict(self.high_water), "failure": self.failure,
                "boundsPassed": self.failure is None and self.scan_count > 0,
                "hardFilesystemQuotaEnforced": False,
                "unobservedTransientOrOffRootGrowthExcluded": False,
                "observations": observations,
                "omittedCompletedObservationCount": max(0, self.scan_count-retained_completed)}

    def _open_file(self, row, catalog, deadline):
        parts = row["path"].split("/")
        parent = os.dup(self.fd)
        try:
            for index, part in enumerate(parts[:-1], 1):
                _clock_check(deadline)
                nested = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
                os.close(parent)
                parent = nested
                expected = catalog["/".join(parts[:index])]
                if _identity(os.fstat(parent)) != expected["_identity"]:
                    raise OutputError("Output ancestor changed before file read")
            fd = os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=parent)
            if _identity(os.fstat(fd)) != row["_identity"]:
                os.close(fd)
                raise OutputError("Output file changed before retention")
            return fd, parent
        except BaseException:
            os.close(parent)
            raise

    def finalize(self, archive_path: Path, *, safe_to_read):
        progress.require(not self.finalized, "Output retention cannot be repeated")
        self.finalized = True
        started = time.monotonic()
        deadline = started + RETENTION_SECONDS
        result = {"status": "retention-incomplete", "retentionComplete": False,
                  "inventoryComplete": False, "newAnalysisDocumentObserved": False,
                  "outputBoundsPass": self.failure is None,
                  "archive": None, "inventory": None, "errors": [],
                  "retentionBudgetSeconds": RETENTION_SECONDS,
                  "semanticAnalysisValidityEstablished": False,
                  "archiveRootPrefix": "derived-output/"}
        staging = None
        staging_file = None
        published = False
        stage = "preflight"
        archive_path = Path(archive_path)
        try:
            if safe_to_read is not True:
                result["status"] = "skipped-cleanup-incomplete"
                return result
            if self.failure is not None:
                result["status"] = "skipped-output-observation-failed"
                result["errors"].append(self.failure["error"])
                return result
            stage = "initial-census"
            snapshot = self._scan(min(deadline, time.monotonic()+SCAN_SECONDS), stable=True)
            rows = snapshot["entries"]
            result["inventory"] = {"totals": snapshot["totals"], "entries": [
                {k: v for k, v in row.items() if k != "_identity"} for row in rows]}
            result["inventoryComplete"] = True
            if len(rows) == 1:
                result.update(status="no-output", retentionComplete=True,
                              emptyOutputReason="The exclusive derived-output parent remained empty")
                return result
            stage = "archive"
            progress.require(archive_path.is_absolute(), "Require an absolute retention archive path")
            _component(archive_path.name)
            archive_path = archive_path.parent.resolve(strict=True) / archive_path.name
            progress.require(not archive_path.is_relative_to(self.root), "Archive must be outside observed output")
            progress.require(not os.path.lexists(archive_path), "Retention archive already exists")
            # Partial archives stay outside both the observed directory and the
            # uploaded evidence directory, including on a cleanup failure.
            staging = Path(tempfile.mkdtemp(prefix=".d27-retention-", dir=archive_path.parent.parent))
            progress.require(not staging.is_relative_to(self.root), "Archive staging overlaps output")
            staging_file = staging / "archive.pending"
            archive_limit = self.limits["logicalBytes"] + self.limits["entries"] * (2*self.limits["pathBytes"]+512) + 65536
            catalog = {row["path"]: row for row in rows}
            expected_zip = {}
            file_read_bytes = verified_bytes = 0
            with staging_file.open("x+b", buffering=0) as raw:
                bounded = _ArchiveIO(raw, deadline, archive_limit, 3*archive_limit)
                with zipfile.ZipFile(bounded, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
                    for row in rows:
                        _clock_check(deadline)
                        name = "derived-output/" + ("" if row["path"] == "." else row["path"])
                        kind = row["kind"]
                        if kind == "directory":
                            if not name.endswith("/"):
                                name += "/"
                            info = zipfile.ZipInfo(name)
                            info.external_attr = (stat.S_IFDIR | row["mode"]) << 16
                            archive.writestr(info, b"")
                            expected_zip[name] = {"bytes": 0, "sha256": hashlib.sha256(b"").hexdigest(), "crc32": 0}
                            continue
                        info = zipfile.ZipInfo(name)
                        info.compress_type = zipfile.ZIP_DEFLATED
                        info.external_attr = (stat.S_IFREG | row["mode"]) << 16
                        fd, parent = self._open_file(row, catalog, deadline)
                        digest = hashlib.sha256()
                        count = 0
                        try:
                            with archive.open(info, "w") as destination:
                                while True:
                                    _clock_check(deadline)
                                    chunk = os.read(fd, min(CHUNK_BYTES, row["bytes"]-count+1))
                                    if not chunk:
                                        break
                                    count += len(chunk)
                                    file_read_bytes += len(chunk)
                                    if count > row["bytes"] or file_read_bytes > self.limits["logicalBytes"]:
                                        raise OutputError("Output grew while retaining bytes")
                                    destination.write(chunk)
                                    digest.update(chunk)
                            if (count != row["bytes"] or _identity(os.fstat(fd)) != row["_identity"]
                                    or _identity(os.stat(row["path"].split("/")[-1], dir_fd=parent,
                                                         follow_symlinks=False)) != row["_identity"]):
                                raise OutputError("Output file changed during retention")
                        finally:
                            os.close(fd)
                            os.close(parent)
                        expected_zip[name] = {"bytes": count, "sha256": digest.hexdigest(),
                                              "crc32": archive.getinfo(name).CRC}
                        row["sha256"] = digest.hexdigest()
                        row["crc32"] = archive.getinfo(name).CRC
                stage = "final-census"
                after = self._scan(min(deadline, time.monotonic()+SCAN_SECONDS), stable=True)
                fingerprint = lambda items: [(row["path"], row["_identity"]) for row in items]
                if fingerprint(rows) != fingerprint(after["entries"]):
                    raise OutputError("Output inventory changed during retention")
                stage = "archive-verification"
                bounded.flush()
                bounded.seek(0)
                with zipfile.ZipFile(bounded) as archive:
                    infos = archive.infolist()
                    if len(infos) != len(expected_zip) or {i.filename for i in infos} != set(expected_zip):
                        raise OutputError("Retained archive inventory differs")
                    for info in infos:
                        _clock_check(deadline)
                        expected = expected_zip[info.filename]
                        if info.file_size != expected["bytes"] or info.CRC != expected["crc32"]:
                            raise OutputError("Retained archive metadata differs")
                        digest = hashlib.sha256()
                        count = 0
                        with archive.open(info) as source:
                            while True:
                                _clock_check(deadline)
                                chunk = source.read(min(CHUNK_BYTES, expected["bytes"]-count+1))
                                if not chunk:
                                    break
                                count += len(chunk)
                                verified_bytes += len(chunk)
                                if count > expected["bytes"] or verified_bytes > self.limits["logicalBytes"]:
                                    raise OutputError("Archive verification expanded-byte bound exceeded")
                                digest.update(chunk)
                        if count != expected["bytes"] or digest.hexdigest() != expected["sha256"]:
                            raise OutputError("Retained archive payload differs")
                bounded.seek(0)
                digest = hashlib.sha256()
                size = 0
                while True:
                    chunk = bounded.read(CHUNK_BYTES)
                    if not chunk:
                        break
                    size += len(chunk)
                    digest.update(chunk)
                _clock_check(deadline)
                if size != os.fstat(raw.fileno()).st_size:
                    raise OutputError("Archive length changed while hashing")
                result["retentionIO"] = {"sourceReadBytes": file_read_bytes,
                                         "verifiedExpandedBytes": verified_bytes,
                                         "archiveReadBytes": bounded.read_bytes,
                                         "maximumArchiveBytes": archive_limit,
                                         "maximumArchiveReadBytes": 3*archive_limit}
            _clock_check(deadline)
            os.link(staging_file, archive_path, follow_symlinks=False)
            published = True
            result["archive"] = {"name": archive_path.name, "bytes": size,
                                 "sha256": digest.hexdigest(), "entryCount": len(rows),
                                 "expandedBytes": file_read_bytes, "crcAndSHA256Verified": True}
            result["inventory"]["entries"] = [{k: v for k, v in row.items() if k != "_identity"} for row in rows]
            top = [row for row in rows if row["path"] != "." and "/" not in row["path"]]
            new_document = (len(top) == 1 and top[0]["path"] == self.intended_name
                            and top[0]["kind"] == "directory"
                            and any(row["kind"] == "file" and row["bytes"] > 0
                                    and row["path"].startswith(self.intended_name+"/") for row in rows))
            result.update(status="output-retained", retentionComplete=True,
                          newAnalysisDocumentObserved=new_document)
            return result
        except (OSError, ValueError, RuntimeError, zipfile.BadZipFile) as error:
            if stage in ("initial-census", "final-census"):
                self._fail(error, code="derived-output-final-observation-failed")
            result["errors"].append(type(error).__name__ + ": " + str(error))
            result["status"] = "retention-failed"
            return result
        finally:
            if staging_file is not None:
                try:
                    staging_file.unlink(missing_ok=True)
                except OSError as error:
                    result["errors"].append("Staging cleanup: " + str(error))
                    result["retentionComplete"] = False
            if staging is not None:
                try:
                    staging.rmdir()
                except OSError as error:
                    result["errors"].append("Staging cleanup: " + str(error))
                    result["retentionComplete"] = False
            elapsed = time.monotonic()-started
            result.update(retentionElapsedSeconds=elapsed,
                          retentionDeadlineOvershootSeconds=max(0.0, elapsed-RETENTION_SECONDS),
                          outputBoundsPass=self.failure is None)
            if elapsed >= RETENTION_SECONDS:
                result["retentionComplete"] = False
                result["newAnalysisDocumentObserved"] = False
                result["errors"].append("Retention completed after its declared deadline")
            if not result["retentionComplete"]:
                result["newAnalysisDocumentObserved"] = False
                if published:
                    try:
                        archive_path.unlink()
                        result["archive"] = None
                    except OSError as error:
                        result["errors"].append("Final archive cleanup: " + str(error))

    def close(self):
        if not self.closed:
            os.close(self.fd)
            self.closed = True


def capture_import(name, argv, *, cwd: Path, env: dict, guard: OutputGuard,
                   test_factory=None, test_budget=None, test_reserve=None):
    """Return ``(receipt, streams, cleanup_records)`` for one finite command.

    All streams are bytes. Cleanup records contain ``name``, ``receipt`` and
    ``streams`` and must be retained by the caller. A natural nonzero exit can
    complete this transport; timeout, truncated output or emergency cleanup
    cannot. No stderr-content policy is imposed on the target command.
    """
    budget = TOTAL_SECONDS if test_budget is None else test_budget
    reserve = TOTAL_SECONDS - NORMAL_SECONDS if test_reserve is None else test_reserve
    limit = MAX_STREAM_BYTES
    progress.require(test_factory is not None or (test_budget is None and test_reserve is None),
                     "Native import budgets are fixed")
    progress.require(isinstance(guard, OutputGuard), "Require the owned output observer")
    guard.begin_capture(synthetic=test_factory is not None)
    progress.require(isinstance(name, str) and name and len(name) <= 100,
                     "Command name is missing or oversized")
    argv = tuple(argv)
    progress.require(argv and all(isinstance(item, str) and item and "\0" not in item for item in argv),
                     "Command arguments are invalid")
    progress.require(all(type(value) in (int, float) and math.isfinite(value)
                         for value in (budget, reserve))
                     and 0 < reserve < budget <= TOTAL_SECONDS,
                     "Command budget must be finite and at most 95 seconds")
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

    def observe_output(*, force=False):
        if not guard.sample(force=force):
            error("Derived-output observation failed: " + guard.failure["error"])
            if target.pid is not None and not target.collected and not target.pid_actions_revoked:
                target.stop(guard.failure["code"])

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
        observe_output()

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
            observe_output(force=True)
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

        # Observe once more while the target lease is still held. A live
        # writer left after operation completion cannot silently pass here.
        observe_output(force=True)
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
        adapter="D27-retained-atrc-output-owned-command", testFactoryUsed=test_factory is not None,
        outputBoundsPass=guard.summary()["boundsPassed"], outputGuard=guard.summary(),
        transportComplete=transport_complete, cleanupComplete=cleanup_complete,
        adapterErrors=errors, ownedGroupsBeforeEmergencyCleanup=initial_groups if emergency else None,
        finalOwnedGroups=final_groups, emergencyCleanupRequired=emergency,
        groupProbeTotalBudgetSeconds=GROUP_BUDGET,
        emergencyTERMGraceSeconds=TERM_GRACE,
        nominalAdapterWallBudgetSeconds=budget + 2 * GROUP_BUDGET + TERM_GRACE,
        perOutputScanWorkBudgetSeconds=SCAN_SECONDS,
        synchronousFilesystemCallsHaveHardDeadline=False,
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
