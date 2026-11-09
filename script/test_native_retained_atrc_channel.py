#!/usr/bin/env python3
"""Bounded nonblocking report-channel tests, separate from report semantics."""
import json
import os
import socket
import unittest

import native_retained_atrc_isolated as subject


class Sink:
    def __init__(self):
        self.received = []

    def accept(self, value, now_ns):
        self.received.append((value, now_ns))


class ReportChannelTests(unittest.TestCase):
    def setUp(self):
        self.reader, self.writer = socket.socketpair()
        self.writer.setblocking(False)
        self.channel = subject.ReportChannel(self.reader.fileno())
        self.sink = Sink()

    def tearDown(self):
        self.reader.close()
        self.writer.close()

    def send(self, raw):
        self.assertEqual(len(raw), self.writer.send(raw))

    def test_no_available_bytes_returns_without_read_or_parse(self):
        self.assertFalse(self.channel.drain(self.sink))
        self.assertEqual([], self.sink.received)
        self.assertFalse(self.channel.eof)

    def test_fragmented_utf8_frame_is_not_parsed_before_newline(self):
        raw = json.dumps({"path": "örnek"}, ensure_ascii=False).encode() + b"\n"
        self.send(raw[:11])
        self.channel.drain(self.sink)
        self.assertEqual([], self.sink.received)
        self.send(raw[11:])
        self.channel.drain(self.sink)
        self.assertEqual([{"path": "örnek"}], [v for v, _ in self.sink.received])

    def test_backlog_yields_after_sixteen_messages_and_retains_remaining_frames(self):
        self.send(b"".join(json.dumps({"sequence": n}).encode() + b"\n" for n in range(40)))
        self.assertTrue(self.channel.drain(self.sink))
        self.assertEqual(16, len(self.sink.received))
        self.assertTrue(self.channel.buffer)
        self.channel.drain(self.sink)
        self.assertEqual(32, len(self.sink.received))
        self.channel.drain(self.sink)
        self.assertEqual(list(range(40)), [v["sequence"] for v, _ in self.sink.received])
        self.assertEqual(16, self.channel.maximum_tick_messages)
        self.assertLessEqual(self.channel.maximum_tick_bytes, 65536)
        self.assertLessEqual(self.channel.maximum_buffer, 65536)

    def test_maximum_sized_frame_passes_and_one_byte_larger_fails(self):
        raw = b'{"x":"' + b"x" * (4096 - len(b'{"x":""}\n')) + b'"}\n'
        self.assertEqual(4096, len(raw))
        self.send(raw)
        self.channel.drain(self.sink)
        self.assertEqual(1, len(self.sink.received))
        self.send(raw[:-2] + b'x}\n')
        with self.assertRaises(subject.ProtocolError):
            self.channel.drain(self.sink)
        self.assertEqual(4097, self.channel.maximum_tick_bytes)

    def test_unterminated_frame_cannot_expand_to_buffer_cap(self):
        self.send(b"x" * 4096)
        with self.assertRaises(subject.ProtocolError):
            self.channel.drain(self.sink)
        self.assertEqual([], self.sink.received)
        self.assertLessEqual(len(self.channel.buffer), subject.BUFFER_BYTES)

    def test_truncated_eof_is_rejected(self):
        self.send(b'{"partial":1')
        self.writer.shutdown(socket.SHUT_WR)
        self.channel.drain(self.sink)
        with self.assertRaises(subject.ProtocolError):
            self.channel.drain(self.sink)

    def test_complete_backlog_at_eof_is_processed_in_separate_bounded_ticks(self):
        self.send(b'{"sequence":1}\n' * 40)
        self.writer.shutdown(socket.SHUT_WR)
        for _ in range(4):
            self.channel.drain(self.sink)
        self.assertEqual(40, len(self.sink.received))
        self.assertTrue(self.channel.eof)
        self.assertFalse(self.channel.buffer)
        self.assertEqual(16, self.channel.maximum_tick_messages)

    def test_invalid_utf8_and_duplicate_key_frames_are_not_applied(self):
        for raw in (b'{"v":"\xff"}\n', b'{"v":1,"v":2}\n'):
            self.send(raw)
            with self.assertRaises(subject.ProtocolError):
                self.channel.drain(self.sink)
            self.assertFalse(self.sink.received)
            self.assertEqual(1, self.channel.maximum_tick_messages)
            self.assertGreaterEqual(self.channel.maximum_tick_bytes, len(raw))


if __name__ == "__main__":
    unittest.main()
