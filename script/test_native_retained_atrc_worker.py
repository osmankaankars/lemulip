#!/usr/bin/env python3
"""Portable D29 worker contracts. All trees and processes are disposable."""
from contextlib import contextmanager
import json
import os
from pathlib import Path
import select
import signal
import socket
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

import native_retained_atrc_output as base
import native_retained_atrc_worker as subject


NONCE = '0123456789abcdef0123456789abcdef'


class ProtocolTests(unittest.TestCase):
    def scan(self, **changes):
        value = {'schema': 1, 'nonce': NONCE, 'kind': 'scan', 'scan': 1,
                 'deadlineNS': time.monotonic_ns() + 250_000_000}
        value.update(changes)
        return value

    def test_strict_request_round_trip_and_stop(self):
        request = self.scan()
        self.assertEqual(request, subject.decode_request(subject.encode_frame(request), NONCE, 0))
        stop = {'schema': 1, 'nonce': NONCE, 'kind': 'stop'}
        self.assertEqual(stop, subject.decode_request(subject.encode_frame(stop), NONCE, 7))

    def test_rejects_duplicate_json_keys_nonfinite_and_boolean_integers(self):
        encoded = subject.encode_frame(self.scan())
        bad = [encoded.replace(b'"schema":1', b'"schema":1,"schema":1'),
               encoded.replace(b'"schema":1', b'"schema":NaN'),
               subject.encode_frame(self.scan(schema=True)),
               subject.encode_frame(self.scan(scan=True)),
               subject.encode_frame(self.scan(deadlineNS=True))]
        for raw in bad:
            with self.subTest(raw=raw):
                with self.assertRaises(subject.WorkerError):
                    subject.decode_request(raw, NONCE, 0)

    def test_rejects_stale_missing_extra_wrong_nonce_and_unframed_requests(self):
        request = self.scan()
        bad = [subject.encode_frame(self.scan(scan=2)),
               subject.encode_frame(self.scan(nonce='f' * 32)),
               subject.encode_frame(self.scan(extra=1)),
               subject.encode_frame({k: v for k, v in request.items() if k != 'deadlineNS'}),
               subject.encode_frame(request)[:-1],
               b'[]\n', b'\xff\n', b'{}\n{}\n',
               subject.encode_frame(self.scan(deadlineNS=-1)),
               subject.encode_frame(self.scan(deadlineNS=2 ** 63))]
        for raw in bad:
            with self.subTest(raw=raw):
                with self.assertRaises(subject.WorkerError):
                    subject.decode_request(raw, NONCE, 0)
        with self.assertRaises(subject.WorkerError):
            subject.decode_request(subject.encode_frame(request), NONCE, 1)

    def test_frame_limit_counts_utf8_bytes_and_rejects_nonfinite(self):
        raw = subject.encode_frame({'path': 'ç' * 30})
        self.assertEqual({'path': 'ç' * 30}, json.loads(raw))
        with self.assertRaises(subject.WorkerError):
            subject.encode_frame({'path': 'ç' * 4096})
        with self.assertRaises(subject.WorkerError):
            subject.encode_frame({'value': float('inf')})

    def test_report_backpressure_is_terminal_and_not_retried(self):
        writer = subject.ReportWriter(91, NONCE)
        with mock.patch.object(subject, 'REAL_WRITE', side_effect=BlockingIOError()) as write:
            with self.assertRaises(subject.WorkerError):
                writer.emit('scan_started', 1)
            with self.assertRaises(subject.WorkerError):
                writer.emit('scan_started', 1)
        self.assertEqual(1, write.call_count)

    def test_partial_report_write_is_terminal_and_not_retried(self):
        writer = subject.ReportWriter(91, NONCE)
        with mock.patch.object(subject, 'REAL_WRITE', return_value=1) as write:
            with self.assertRaises(subject.WorkerError):
                writer.emit('scan_started', 1)
            with self.assertRaises(subject.WorkerError):
                writer.emit('scan_started', 1)
        self.assertEqual(1, write.call_count)


class ScanTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name).resolve() / 'owned'
        self.root.mkdir(mode=0o700)
        self.fd = os.open(self.root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        info = os.fstat(self.fd)
        self.identity = list(base._anchor_identity(info))
        self.frames = []

    def tearDown(self):
        os.close(self.fd)
        self.temp.cleanup()

    def capture_write(self, fd, raw):
        self.frames.append(json.loads(raw))
        return len(raw)

    def scanner(self, limits=None):
        return subject.BorrowedGuard(self.root, self.fd, self.identity, limits or dict(base.LIMITS))

    def scan(self, guard=None):
        guard = guard or self.scanner()
        writer = subject.ReportWriter(91, NONCE)
        with mock.patch.object(subject, 'REAL_WRITE', side_effect=self.capture_write):
            good = subject.perform_scan(guard, writer, 1, time.monotonic_ns() + 250_000_000)
        return good, guard

    def test_real_tree_totals_and_ordered_relative_operation_pairs(self):
        (self.root / 'a').write_bytes(b'abcd')
        (self.root / 'directory').mkdir()
        (self.root / 'directory' / 'ü.txt').write_bytes(b'1234567')
        good, guard = self.scan()
        self.assertTrue(good)
        self.assertEqual('scan_started', self.frames[0]['kind'])
        self.assertEqual('scan_completed', self.frames[-1]['kind'])
        final = self.frames[-1]
        self.assertEqual(4, final['totals']['entries'])
        self.assertEqual(11, final['totals']['logicalBytes'])
        self.assertEqual(2, final['totals']['depth'])
        self.assertEqual(self.identity, final['rootIdentity'])
        self.assertEqual(list(range(1, len(self.frames) + 1)), [r['seq'] for r in self.frames])
        pending = None
        starts = []
        for row in self.frames:
            if row['kind'] == 'op_started':
                self.assertIsNone(pending)
                pending = row
                starts.append(row)
                self.assertIn(row['category'], subject.CATEGORIES)
                self.assertFalse(row['path'].startswith('/'))
                self.assertNotIn('..', row['path'].split('/'))
            elif row['kind'] == 'op_finished':
                self.assertIsNotNone(pending)
                for key in ('op', 'category', 'path', 'scan'):
                    self.assertEqual(pending[key], row[key])
                self.assertEqual(row['clockNS'] - pending['clockNS'], row['elapsedNS'])
                pending = None
        self.assertIsNone(pending)
        self.assertEqual(final['operationCount'], len(starts))
        self.assertTrue({'stat', 'fstat', 'open', 'close', 'scandir', 'scandir_next', 'scandir_close'}
                        .issubset({r['category'] for r in starts}))
        self.assertTrue(any(r['kind'] == 'op_finished' and r['category'] == 'scandir_next'
                            and r['outcome'] == 'eof' for r in self.frames))
        self.assertTrue(any(r.get('path') == 'directory/ü.txt' for r in self.frames))
        self.assertIs(base.os, os)

    def test_symlink_and_hardlink_are_rejected_without_payload_reads(self):
        for kind in ('symlink', 'hardlink'):
            with self.subTest(kind=kind):
                source = self.root.parent / 'original'
                source.write_bytes(b'private bytes')
                destination = self.root / 'unsafe'
                if kind == 'symlink':
                    destination.symlink_to(source)
                else:
                    os.link(source, destination)
                self.frames = []
                good, _ = self.scan()
                self.assertFalse(good)
                self.assertEqual('scan_failed', self.frames[-1]['kind'])
                self.assertNotIn(b'private bytes', json.dumps(self.frames).encode())
                destination.unlink()
                source.unlink()

    def test_replaced_root_is_rejected_against_inherited_descriptor(self):
        guard = self.scanner()
        self.root.rename(self.root.with_name('old'))
        self.root.mkdir(mode=0o700)
        good, _ = self.scan(guard)
        self.assertFalse(good)
        self.assertIn('identity', self.frames[-1]['error'])

    def test_ready_preconditions_reject_foreign_identity_and_wrong_root_mode(self):
        with self.assertRaises(subject.WorkerError):
            subject.BorrowedGuard(self.root, self.fd,
                                  [self.identity[0], self.identity[1] + 1, self.identity[2]],
                                  dict(base.LIMITS))
        with self.assertRaises(subject.WorkerError):
            subject.BorrowedGuard(self.root, self.fd, [True, *self.identity[1:]], dict(base.LIMITS))
        self.root.chmod(0o755)
        with self.assertRaises(subject.WorkerError):
            self.scanner()

    def test_required_start_report_failure_prevents_unwitnessed_filesystem_call(self):
        guard = self.scanner()
        writer = subject.ReportWriter(91, NONCE)
        writes = 0

        def fail_operation_start(fd, raw):
            nonlocal writes
            writes += 1
            if writes == 2:
                raise BlockingIOError()
            return self.capture_write(fd, raw)

        with mock.patch.object(subject, 'REAL_WRITE', side_effect=fail_operation_start), \
                mock.patch.object(subject, 'REAL_FSTAT', side_effect=AssertionError('Unwitnessed call')):
            with self.assertRaises(subject.WorkerError):
                subject.perform_scan(guard, writer, 1, time.monotonic_ns() + 250_000_000)
        self.assertEqual(2, writes)
        self.assertEqual(['scan_started'], [r['kind'] for r in self.frames])
        self.assertIs(base.os, os)

    def test_output_limits_only_tighten_and_fail_with_partial_high_water(self):
        with self.assertRaises(subject.WorkerError):
            self.scanner({**base.LIMITS, 'entries': base.LIMITS['entries'] + 1})
        with self.assertRaises(subject.WorkerError):
            self.scanner({**base.LIMITS, 'depth': True})
        (self.root / 'large').write_bytes(b'12345')
        guard = self.scanner({**base.LIMITS, 'logicalBytes': 4})
        good, _ = self.scan(guard)
        self.assertFalse(good)
        self.assertGreater(self.frames[-1]['highWater']['logicalBytes'], 4)
        self.assertNotIn('totals', self.frames[-1])

    def test_operation_start_precedes_call_and_late_return_fails_scan(self):
        (self.root / 'slow').write_bytes(b'123')
        real_stat = subject.REAL_STAT
        virtual = time.monotonic_ns()
        observed_pending = []

        def clock():
            return virtual

        def delayed_stat(*args, **kwargs):
            nonlocal virtual
            if args[0] == 'slow':
                observed_pending.append(dict(self.frames[-1]))
                virtual += 600_000_000
            return real_stat(*args, **kwargs)

        writer = subject.ReportWriter(91, NONCE)
        guard = self.scanner()
        with mock.patch.object(subject, 'REAL_WRITE', side_effect=self.capture_write), \
                mock.patch.object(subject, 'REAL_STAT', side_effect=delayed_stat), \
                mock.patch.object(subject.time, 'monotonic_ns', side_effect=clock), \
                mock.patch.object(base.time, 'monotonic', side_effect=lambda: virtual / 1e9):
            good = subject.perform_scan(guard, writer, 1, virtual + 250_000_000)
        self.assertFalse(good)
        self.assertEqual('op_started', observed_pending[0]['kind'])
        self.assertEqual('slow', observed_pending[0]['path'])
        finished = next(r for r in self.frames if r['kind'] == 'op_finished' and r['path'] == 'slow')
        self.assertEqual(600_000_000, finished['elapsedNS'])
        self.assertEqual('scan_failed', self.frames[-1]['kind'])
        self.assertEqual(600_000_000, self.frames[-1]['elapsedNS'])

    def test_expired_request_emits_failure_without_filesystem_operations(self):
        writer = subject.ReportWriter(91, NONCE)
        guard = self.scanner()
        with mock.patch.object(subject, 'REAL_WRITE', side_effect=self.capture_write):
            self.assertFalse(subject.perform_scan(guard, writer, 1, time.monotonic_ns() - 1))
        self.assertEqual(['scan_started', 'scan_failed'], [r['kind'] for r in self.frames])
        self.assertEqual(0, self.frames[-1]['operationCount'])

    def test_future_deadline_is_not_silently_accepted_or_reset(self):
        writer = subject.ReportWriter(91, NONCE)
        guard = self.scanner()
        with mock.patch.object(subject, 'REAL_WRITE', side_effect=self.capture_write):
            with self.assertRaises(subject.WorkerError):
                subject.perform_scan(guard, writer, 1, time.monotonic_ns() + 2_000_000_000)
        self.assertEqual([], self.frames)


@unittest.skipUnless(hasattr(os, 'O_NOFOLLOW'), 'Requires POSIX descriptors')
class ProcessTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name).resolve() / 'owned'
        self.root.mkdir(mode=0o700)
        self.root_fd = os.open(self.root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        self.identity = list(base._anchor_identity(os.fstat(self.root_fd)))
        self.request_r, self.request_w = os.pipe()
        self.report_parent, self.report_child = socket.socketpair()
        self.report_parent.setblocking(False)
        self.buffer = bytearray()
        self.child = None

    def tearDown(self):
        if self.child is not None:
            if self.child.poll() is None:
                self.child.kill()
            self.child.wait(timeout=2)
            self.child.stderr.close()
        for fd in (self.root_fd, self.request_r, self.request_w):
            try:
                os.close(fd)
            except OSError:
                pass
        self.report_parent.close()
        self.report_child.close()
        self.temp.cleanup()

    def launch(self):
        command = [sys.executable, str(Path(subject.__file__)), '--root', str(self.root),
                   '--root-fd', str(self.root_fd), '--request-fd', str(self.request_r),
                   '--report-fd', str(self.report_child.fileno()), '--nonce', NONCE,
                   '--identity', json.dumps(self.identity), '--limits', json.dumps(base.LIMITS)]
        self.child = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                      stderr=subprocess.PIPE, start_new_session=True,
                                      pass_fds=(self.root_fd, self.request_r, self.report_child.fileno()))
        self.report_child.close()
        os.close(self.request_r)
        self.request_r = -1
        return self.until('ready')[0]

    def until(self, kind):
        result = []
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            while b'\n' in self.buffer:
                raw, _, rest = self.buffer.partition(b'\n')
                self.buffer = bytearray(rest)
                row = json.loads(raw)
                result.append(row)
                if row['kind'] == kind:
                    return result
            ready, _, _ = select.select([self.report_parent], [], [], .02)
            if ready:
                raw = self.report_parent.recv(65536)
                if not raw:
                    self.fail('Worker report EOF before ' + kind)
                self.buffer.extend(raw)
        self.fail('Worker report deadline before ' + kind)

    def send(self, value):
        os.write(self.request_w, subject.encode_frame(value))

    def test_real_child_ready_binds_pid_root_and_preserves_sequence_across_scans(self):
        ready = self.launch()
        self.assertEqual(self.child.pid, ready['pid'])
        self.assertEqual(self.identity, ready['rootIdentity'])
        self.assertEqual(dict(base.LIMITS), ready['limits'])
        rows = [ready]
        for scan in (1, 2):
            (self.root / 'item').write_bytes(b'123' * scan)
            self.send({'schema': 1, 'nonce': NONCE, 'kind': 'scan', 'scan': scan,
                       'deadlineNS': time.monotonic_ns() + 250_000_000})
            records = self.until('scan_completed')
            self.assertEqual(3 * scan, records[-1]['totals']['logicalBytes'])
            rows.extend(records)
        self.send({'schema': 1, 'nonce': NONCE, 'kind': 'stop'})
        rows.extend(self.until('stopped'))
        self.assertEqual(0, self.child.wait(timeout=2))
        self.assertEqual(list(range(1, len(rows) + 1)), [r['seq'] for r in rows])
        self.assertEqual(b'', self.child.stderr.read())

    def test_malformed_command_and_closed_request_channel_exit_without_scan(self):
        self.launch()
        os.write(self.request_w, b'{"schema":1,"schema":1}\n')
        self.assertNotEqual(0, self.child.wait(timeout=2))
        self.assertIn(b'worker', self.child.stderr.read().lower())

    def test_request_eof_exits_and_cannot_leave_worker_running(self):
        self.launch()
        os.close(self.request_w)
        self.request_w = -1
        self.assertNotEqual(0, self.child.wait(timeout=2))


if __name__ == '__main__':
    unittest.main()
