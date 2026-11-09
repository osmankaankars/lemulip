#!/usr/bin/env python3
"""D29 descriptor-bound census worker, used by the offline observer adapter.

The worker performs no import, recording, export or final output retention.
It reuses D27's no-follow census in its own process. Required reports are
nonblocking and never retried: a missing report invalidates the observation.
Operation intervals include start-report emission and scheduling, not only
time spent inside the filesystem implementation.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import select
import stat
import sys
import time

import native_retained_atrc_output as base


FRAME_BYTES = 4096
SCAN_NS = 250_000_000
CATEGORIES = frozenset({'stat', 'fstat', 'open', 'close', 'scandir',
                        'scandir_next', 'scandir_close'})
REAL_WRITE = os.write
REAL_STAT = os.stat
REAL_FSTAT = os.fstat
REAL_OPEN = os.open
REAL_CLOSE = os.close
REAL_SCANDIR = os.scandir


class WorkerError(ValueError):
    pass


def _require(value, message):
    if not value:
        raise WorkerError(message)


def _integer(value, *, minimum=0):
    return type(value) is int and minimum <= value < 2 ** 63


def _nonce(value):
    return isinstance(value, str) and re.fullmatch(r'[0-9a-f]{32}', value) is not None


def encode_frame(message):
    """One compact UTF-8 JSON object and newline, bounded in encoded bytes."""
    _require(isinstance(message, dict), 'A frame must be an object')
    try:
        raw = (json.dumps(message, ensure_ascii=False, allow_nan=False,
                          sort_keys=True, separators=(',', ':')) + '\n').encode('utf-8', 'strict')
    except (TypeError, ValueError, UnicodeError) as error:
        raise WorkerError('Frame is not strict finite UTF-8 JSON') from error
    _require(len(raw) <= FRAME_BYTES, 'Frame byte limit exceeded')
    return raw


def _pairs(pairs):
    value = {}
    for key, item in pairs:
        _require(key not in value, 'Duplicate JSON key')
        value[key] = item
    return value


def _nonfinite(value):
    raise WorkerError('Non-finite JSON value')


def decode_request(raw, nonce, last_scan):
    _require(type(raw) is bytes and 0 < len(raw) <= FRAME_BYTES
             and raw.endswith(b'\n') and raw.count(b'\n') == 1,
             'Request must be one bounded newline frame')
    _require(_nonce(nonce) and _integer(last_scan), 'Invalid request context')
    try:
        request = json.loads(raw.decode('utf-8', 'strict'), object_pairs_hook=_pairs,
                             parse_constant=_nonfinite)
    except (UnicodeError, json.JSONDecodeError) as error:
        raise WorkerError('Invalid request JSON') from error
    _require(isinstance(request, dict), 'Request must be an object')
    _require(type(request.get('schema')) is int and request['schema'] == 1,
             'Unsupported request schema')
    _require(request.get('nonce') == nonce, 'Request nonce mismatch')
    if request.get('kind') == 'stop':
        _require(set(request) == {'schema', 'nonce', 'kind'}, 'Unexpected stop fields')
    elif request.get('kind') == 'scan':
        _require(set(request) == {'schema', 'nonce', 'kind', 'scan', 'deadlineNS'},
                 'Unexpected scan fields')
        _require(_integer(request['scan'], minimum=1) and request['scan'] == last_scan + 1,
                 'Stale, duplicate or out-of-order scan')
        _require(_integer(request['deadlineNS'], minimum=1), 'Invalid scan deadline')
    else:
        raise WorkerError('Unknown request kind')
    return request


class ReportWriter:
    """Do not continue after a partial, blocked or failed required write."""
    def __init__(self, descriptor, nonce):
        _require(_integer(descriptor) and _nonce(nonce), 'Invalid report channel')
        self.descriptor = descriptor
        self.nonce = nonce
        self.sequence = 0
        self.failure = None

    def emit(self, kind, scan, *, clock_ns=None, **fields):
        if self.failure is not None:
            raise self.failure
        _require(_integer(scan), 'Invalid report scan')
        sampled = time.monotonic_ns() if clock_ns is None else clock_ns
        _require(_integer(sampled), 'Invalid report clock')
        self.sequence += 1
        value = {'schema': 1, 'nonce': self.nonce, 'seq': self.sequence,
                 'kind': kind, 'scan': scan, 'clockNS': sampled}
        _require(not set(fields).intersection(value), 'Report fields replace envelope')
        value.update(fields)
        try:
            raw = encode_frame(value)
            written = REAL_WRITE(self.descriptor, raw)
            if written != len(raw):
                raise WorkerError('Required report write was partial')
        except (OSError, WorkerError) as error:
            self.failure = WorkerError('Required report unavailable: ' + type(error).__name__)
            raise self.failure from error
        return value


class BorrowedGuard(base.OutputGuard):
    """Reuse only the census; the inherited descriptor belongs to this worker."""
    def __init__(self, root, root_fd, identity, limits):
        root = Path(root)
        _require(root.is_absolute() and root.name not in ('', '.', '..'), 'Invalid output root')
        base._component(root.name)
        _require(root == root.parent.resolve(strict=True) / root.name,
                 'Output root parent is not canonical')
        _require(_integer(root_fd), 'Invalid output descriptor')
        _require(type(identity) is list and len(identity) == 3
                 and all(_integer(value) for value in identity), 'Invalid root identity')
        _require(isinstance(limits, dict) and set(limits) == set(base.LIMITS),
                 'Output limits must name the complete fixed contract')
        _require(all(type(value) is int and 0 < value <= base.LIMITS[key]
                     for key, value in limits.items()), 'Output limits may only tighten')
        info = REAL_FSTAT(root_fd)
        path_info = REAL_STAT(root, follow_symlinks=False)
        _require(stat.S_ISDIR(info.st_mode) and stat.S_IMODE(info.st_mode) == 0o700,
                 'Output root must be an exclusive0700 directory')
        _require(list(base._anchor_identity(info)) == identity
                 and base._anchor_identity(path_info) == base._anchor_identity(info),
                 'Inherited output root identity or path mismatch')
        self.root = root
        self.fd = root_fd
        self.initial_root = info
        self.closed = False
        self.limits = dict(limits)
        self.high_water = {'logicalBytes': 0, 'allocatedBytes': 0, 'entries': 0, 'depth': 0}


class TimedOS:
    """A module-local proxy; real IPC and other modules never use this proxy."""
    def __init__(self, guard, writer, scan):
        self.guard = guard
        self.writer = writer
        self.scan = scan
        self.operation_count = 0
        self.paths = {guard.fd: '.'}

    def __getattr__(self, name):
        return getattr(os, name)

    def _path(self, path, dir_fd=None):
        if path == self.guard.root:
            return '.'
        _require(type(path) is str and dir_fd in self.paths, 'Unbound census path')
        base._component(path)
        prefix = self.paths[dir_fd]
        relative = path if prefix == '.' else prefix + '/' + path
        _require(len(relative.encode('utf-8')) <= self.guard.limits['pathBytes'],
                 'Census relative-path bound exceeded')
        return relative

    def _operation(self, category, path, callback):
        if self.writer.failure is not None:
            raise self.writer.failure
        self.operation_count += 1
        operation = self.operation_count
        started = time.monotonic_ns()
        fields = {'op': operation, 'category': category, 'path': path}
        self.writer.emit('op_started', self.scan, clock_ns=started, **fields)
        outcome = 'ok'
        try:
            return callback()
        except StopIteration:
            outcome = 'eof'
            raise
        except BaseException:
            outcome = 'error'
            raise
        finally:
            ended = time.monotonic_ns()
            self.writer.emit('op_finished', self.scan, clock_ns=ended,
                             elapsedNS=ended - started, outcome=outcome, **fields)

    def stat(self, path, *, dir_fd=None, follow_symlinks=True):
        relative = self._path(path, dir_fd)
        return self._operation('stat', relative,
                               lambda: REAL_STAT(path, dir_fd=dir_fd, follow_symlinks=follow_symlinks))

    def fstat(self, descriptor):
        _require(descriptor in self.paths, 'Unbound census descriptor')
        return self._operation('fstat', self.paths[descriptor], lambda: REAL_FSTAT(descriptor))

    def open(self, path, flags, *, dir_fd=None):
        relative = self._path(path, dir_fd)
        descriptor = self._operation('open', relative, lambda: REAL_OPEN(path, flags, dir_fd=dir_fd))
        self.paths[descriptor] = relative
        return descriptor

    def close(self, descriptor):
        _require(descriptor in self.paths, 'Unbound census descriptor')
        try:
            if self.writer.failure is not None:
                return REAL_CLOSE(descriptor)
            return self._operation('close', self.paths[descriptor], lambda: REAL_CLOSE(descriptor))
        finally:
            self.paths.pop(descriptor, None)

    def scandir(self, descriptor):
        _require(descriptor in self.paths, 'Unbound census descriptor')
        path = self.paths[descriptor]
        iterator = self._operation('scandir', path, lambda: REAL_SCANDIR(descriptor))
        return _TimedIterator(self, iterator, path)


class _TimedIterator:
    def __init__(self, proxy, iterator, path):
        self.proxy, self.iterator, self.path = proxy, iterator, path
        self.closed = False

    def __enter__(self):
        return self

    def __exit__(self, *unused):
        self.close()

    def __iter__(self):
        return self

    def __next__(self):
        return self.proxy._operation('scandir_next', self.path, lambda: next(self.iterator))

    def close(self):
        if self.closed:
            return
        self.closed = True
        if self.proxy.writer.failure is not None:
            self.iterator.close()
        else:
            self.proxy._operation('scandir_close', self.path, self.iterator.close)


def perform_scan(guard, writer, scan, deadline_ns):
    """One census against the parent's deadline; no retained payload is sent."""
    _require(isinstance(guard, BorrowedGuard) and isinstance(writer, ReportWriter),
             'Invalid scan collaborators')
    _require(_integer(scan, minimum=1) and _integer(deadline_ns, minimum=1),
             'Invalid scan request')
    started = time.monotonic_ns()
    _require(deadline_ns <= started + SCAN_NS, 'Scan deadline attempts to extend the fixed budget')
    writer.emit('scan_started', scan, clock_ns=started)
    proxy = TimedOS(guard, writer, scan)
    original_os = base.os
    failure = None
    snapshot = None
    try:
        base.os = proxy
        base._clock_check(deadline_ns / 1_000_000_000)
        snapshot = guard._scan(deadline_ns / 1_000_000_000)
    except (OSError, ValueError, RuntimeError) as error:
        if writer.failure is not None:
            raise writer.failure
        failure = type(error).__name__ + ': ' + str(error)
    finally:
        base.os = original_os
    ended = time.monotonic_ns()
    fields = {'highWater': dict(guard.high_water), 'elapsedNS': ended - started,
              'operationCount': proxy.operation_count}
    if failure is not None:
        writer.emit('scan_failed', scan, clock_ns=ended, error=failure[:512], **fields)
        return False
    writer.emit('scan_completed', scan, clock_ns=ended, totals=snapshot['totals'],
                 rootIdentity=list(base._anchor_identity(guard.initial_root)), **fields)
    return True


def run_worker(*, root, root_fd, request_fd, report_fd, nonce, identity, limits):
    """Run an exclusively owned worker over inherited request/report FDs."""
    descriptors = (root_fd, request_fd, report_fd)
    _require(all(_integer(fd) for fd in descriptors) and len(set(descriptors)) == 3,
             'Require three distinct inherited descriptors')
    _require(_nonce(nonce), 'Invalid worker nonce')
    try:
        os.set_blocking(request_fd, False)
        os.set_blocking(report_fd, False)
        guard = BorrowedGuard(root, root_fd, identity, limits)
        writer = ReportWriter(report_fd, nonce)
        writer.emit('ready', 0, pid=os.getpid(), rootIdentity=list(base._anchor_identity(guard.initial_root)),
                    limits=dict(guard.limits))
        buffer = bytearray()
        last_scan = 0
        while True:
            if b'\n' not in buffer:
                readable, _, _ = select.select([request_fd], [], [], .05)
                if not readable:
                    continue
                try:
                    chunk = os.read(request_fd, FRAME_BYTES + 1 - len(buffer))
                except BlockingIOError:
                    continue
                _require(bool(chunk), 'Request channel closed without stop')
                buffer.extend(chunk)
                _require(len(buffer) <= FRAME_BYTES, 'Request buffer exceeds one frame')
                _require(buffer.count(b'\n') <= 1, 'Pipelined worker requests are not permitted')
                continue
            raw, _, remaining = buffer.partition(b'\n')
            _require(not remaining, 'A request is already pending')
            buffer.clear()
            request = decode_request(bytes(raw) + b'\n', nonce, last_scan)
            if request['kind'] == 'stop':
                writer.emit('stopped', 0)
                return 0
            last_scan = request['scan']
            if not perform_scan(guard, writer, last_scan, request['deadlineNS']):
                return 2
    finally:
        for descriptor in descriptors:
            try:
                REAL_CLOSE(descriptor)
            except OSError:
                pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', required=True, type=Path)
    parser.add_argument('--root-fd', required=True, type=int)
    parser.add_argument('--request-fd', required=True, type=int)
    parser.add_argument('--report-fd', required=True, type=int)
    parser.add_argument('--nonce', required=True)
    parser.add_argument('--identity', required=True)
    parser.add_argument('--limits', required=True)
    args = parser.parse_args()
    try:
        identity = json.loads(args.identity, object_pairs_hook=_pairs, parse_constant=_nonfinite)
        limits = json.loads(args.limits, object_pairs_hook=_pairs, parse_constant=_nonfinite)
        return run_worker(root=args.root, root_fd=args.root_fd, request_fd=args.request_fd,
                          report_fd=args.report_fd, nonce=args.nonce, identity=identity, limits=limits)
    except (OSError, ValueError, RuntimeError) as error:
        # One bounded diagnostic, not an alternate protocol or retry path.
        print('Observer worker failed: ' + (type(error).__name__ + ': ' + str(error))[:768], file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
