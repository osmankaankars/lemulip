#!/usr/bin/env python3
"""Run native UI tests with an authenticated, fixed-target, read-only AX reader.

The helper uses the launcher's existing macOS Accessibility authorization. No
TCC database, permission setting, sandbox, or app behavior is changed. Missing
permission remains a failed test. This does not verify VoiceOver narration.
"""
from __future__ import annotations

import argparse
import hmac
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
from pathlib import Path
import secrets
import subprocess
import threading
from collections.abc import Callable


class SnapshotReader:
    def __init__(self, executable: Path, app: Path):
        self.executable = executable.resolve()
        self.app = app.resolve()

    def read(self) -> dict:
        result = subprocess.run([str(self.executable), str(self.app)], capture_output=True,
                                text=True, timeout=8, check=False)
        if len(result.stdout) > 1024 * 1024:
            raise ValueError('AX helper output exceeds the review limit')
        try:
            record = json.loads(result.stdout)
        except (ValueError, TypeError) as error:
            raise ValueError('AX helper did not return a complete JSON snapshot') from error
        if result.returncode != 0:
            raise ValueError(str(record.get('error', 'AX helper failed'))[:2048])
        if (record.get('schema') != 1 or record.get('trusted') is not True
                or record.get('bundleIdentifier') != 'app.lemulip.NativeUIReview'
                or record.get('applicationPath') != str(self.app)
                or record.get('truncated') is not False
                or not isinstance(record.get('pid'), int) or record['pid'] <= 0
                or not isinstance(record.get('nodes'), list)):
            raise ValueError('AX snapshot is untrusted, incomplete or from a different application')
        return record


def make_server(snapshot: Callable[[], dict], token: str) -> HTTPServer:
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass  # Never record authentication headers or request data.

        def respond(self, status: int, record: dict) -> None:
            data = json.dumps(record, ensure_ascii=False).encode('utf-8')
            self.send_response(status)
            self.send_header('Content-Type', 'application/json; charset=utf-8')
            self.send_header('Content-Length', str(len(data)))
            self.send_header('Cache-Control', 'no-store')
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self) -> None:
            if (self.headers.get('Origin') is not None
                    or self.headers.get('Host') != f'127.0.0.1:{self.server.server_port}'
                    or not hmac.compare_digest(self.headers.get('Authorization', '').encode('utf-8'),
                                               ('Bearer ' + token).encode('ascii'))):
                self.respond(403, {'ok': False, 'error': 'Unauthorized review client'}); return
            if self.path != '/snapshot':
                self.respond(404, {'ok': False, 'error': 'Only the fixed snapshot resource is available'}); return
            try:
                self.respond(200, snapshot())
            except (ValueError, OSError, subprocess.SubprocessError) as error:
                self.respond(503, {'ok': False, 'error': str(error)[:2048]})

        def do_POST(self) -> None:
            self.respond(405, {'ok': False, 'error': 'Read-only review endpoint'})

    server = HTTPServer(('127.0.0.1', 0), Handler)
    server.timeout = 1
    return server


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--helper', type=Path, required=True)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command:
        parser.error('An XCTest command is required after --')
    directory = args.directory.resolve(strict=True)
    reader = SnapshotReader(args.helper.resolve(strict=True), directory / 'Lemulip Native UI Review.app')
    token = secrets.token_hex(32)
    evidence = directory / 'AccessibilitySnapshots'
    evidence.mkdir(exist_ok=False)
    counter = 0
    def snapshot() -> dict:
        nonlocal counter
        record = reader.read()
        counter += 1
        with (evidence / f'snapshot-{counter:03d}.json').open('x') as output:
            json.dump(record, output, ensure_ascii=False, indent=2)
        return record
    server = make_server(snapshot, token)
    endpoint = directory / 'accessibility-endpoint.json'
    fd = os.open(endpoint, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as output:
        json.dump({'url': f'http://127.0.0.1:{server.server_port}/snapshot', 'token': token}, output)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        return subprocess.run(command, check=False).returncode
    finally:
        server.shutdown(); server.server_close(); thread.join(timeout=10)
        endpoint.unlink(missing_ok=True)


if __name__ == '__main__':
    raise SystemExit(main())
