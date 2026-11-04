import json
from pathlib import Path
import tempfile
import threading
import unittest
from unittest.mock import patch
from urllib.request import Request, urlopen
from urllib.error import HTTPError

from native_ax_bridge import SnapshotReader, make_server


class NativeAXBridgeTests(unittest.TestCase):
    def test_server_startup_never_resolves_a_host_name(self):
        # HTTPServer normally reverse-resolves its bind address. Even a local
        # reviewer must not ask macOS to discover names on the user's network.
        with patch('socket.getfqdn', return_value='unexpected.local') as fqdn, \
                patch('socket.gethostbyaddr') as reverse:
            server = make_server(lambda: {'trusted': True}, 'c' * 64)
            try:
                self.assertEqual(server.server_address[0], '127.0.0.1')
                fqdn.assert_not_called()
                reverse.assert_not_called()
                self.assertEqual(server.server_name, '127.0.0.1')
                self.assertEqual(server.server_port, server.server_address[1])
            finally:
                server.server_close()

    def test_reader_requires_trusted_exact_target(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary) / 'Lemulip Native UI Review.app'
            app.mkdir()
            reader = SnapshotReader(Path('/probe'), app)
            record = {'schema': 1, 'trusted': True, 'bundleIdentifier': 'app.lemulip.NativeUIReview',
                      'applicationPath': str(app.resolve()), 'pid': 123, 'nodes': [], 'truncated': False}
            with patch('native_ax_bridge.subprocess.run') as run:
                run.return_value.returncode = 0
                run.return_value.stdout = json.dumps(record)
                self.assertEqual(reader.read(), record)
                run.assert_called_once()
                self.assertEqual(run.call_args.args[0], ['/probe', str(app.resolve())])
                self.assertFalse(run.call_args.kwargs.get('shell', False))
                for key, value in [('trusted', False), ('bundleIdentifier', 'other.app'),
                                   ('applicationPath', '/elsewhere/Other.app'), ('truncated', True)]:
                    bad = dict(record); bad[key] = value
                    run.return_value.stdout = json.dumps(bad)
                    with self.subTest(key=key), self.assertRaises(ValueError): reader.read()

    def test_probe_failure_is_not_a_snapshot(self):
        reader = SnapshotReader(Path('/probe'), Path('/tmp/Lemulip Native UI Review.app'))
        with patch('native_ax_bridge.subprocess.run') as run:
            run.return_value.returncode = 1
            run.return_value.stdout = '{"trusted":false}'
            with self.assertRaises(ValueError): reader.read()

    def test_display_reader_needs_no_running_app_and_rejects_nonboolean_values(self):
        reader = SnapshotReader(Path('/probe'), Path('/absent/Lemulip Native UI Review.app'))
        record = {'schema': 1, 'kind': 'system-display-preferences', 'reader': 'NSWorkspace',
                  'readOnly': True, 'reduceMotion': True, 'reduceTransparency': False}
        with patch('native_ax_bridge.subprocess.run') as run:
            run.return_value.returncode = 0
            run.return_value.stdout = json.dumps(record)
            self.assertEqual(reader.read_display_preferences(), record)
            self.assertEqual(run.call_args.args[0], ['/probe', '--display-preferences'])
            self.assertFalse(run.call_args.kwargs.get('shell', False))
            for key, value in [('reduceMotion', 1), ('reduceTransparency', 'false'),
                               ('reduceTransparency', None), ('readOnly', 1),
                               ('reader', 'defaults'), ('kind', 'other')]:
                bad = dict(record); bad[key] = value
                run.return_value.stdout = json.dumps(bad)
                with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                    reader.read_display_preferences()
            run.return_value.stdout = json.dumps(record)
            run.return_value.returncode = 1
            with self.assertRaises(ValueError): reader.read_display_preferences()

    def test_display_resource_is_authenticated_read_only_and_has_no_query_parameters(self):
        calls = []
        def display_preferences():
            calls.append(1)
            return {'reduceMotion': True, 'reduceTransparency': False}
        server = make_server(lambda: {'trusted': True}, 'd' * 64, display_preferences)
        thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
        base = f'http://127.0.0.1:{server.server_port}'
        authorization = {'Authorization': 'Bearer ' + 'd' * 64}
        try:
            cases = [('/display-preferences', {}, 'GET', 403),
                     ('/display-preferences?reduceMotion=false', authorization, 'GET', 404),
                     ('/display-preferences', authorization, 'POST', 405),
                     ('/display-preferences', dict(authorization, Origin='https://example.invalid'), 'GET', 403),
                     ('/display-preferences', dict(authorization, Host='example.invalid'), 'GET', 403)]
            for path, headers, method, status in cases:
                request = Request(base + path, headers=headers, method=method)
                with self.subTest(path=path, method=method, headers=headers), self.assertRaises(HTTPError) as error:
                    urlopen(request, timeout=3)
                self.assertEqual(error.exception.code, status)
            self.assertEqual(calls, [])
            with urlopen(Request(base + '/display-preferences', headers=authorization), timeout=3) as response:
                self.assertEqual(json.load(response), {'reduceMotion': True, 'reduceTransparency': False})
            self.assertEqual(calls, [1])
        finally:
            server.shutdown(); server.server_close(); thread.join(timeout=3)

    def test_failed_display_reader_is_not_replaced_with_cached_values(self):
        def failed(): raise ValueError('Independent NSWorkspace observation failed')
        server = make_server(lambda: {'trusted': True}, 'e' * 64, failed)
        thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
        try:
            request = Request(f'http://127.0.0.1:{server.server_port}/display-preferences',
                              headers={'Authorization': 'Bearer ' + 'e' * 64})
            with self.assertRaises(HTTPError) as error: urlopen(request, timeout=3)
            self.assertEqual(error.exception.code, 503)
            self.assertFalse(json.load(error.exception)['ok'])
        finally:
            server.shutdown(); server.server_close(); thread.join(timeout=3)

    def test_loopback_is_authenticated_read_only_and_target_fixed(self):
        calls = []
        def snapshot():
            calls.append(1)
            return {'trusted': True, 'nodes': [{'valueDescription': 'Yüzde 82'}]}
        server = make_server(snapshot, 'a' * 64)
        thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
        base = f'http://127.0.0.1:{server.server_port}'
        try:
            for path, token, method, expected in [('/snapshot', '', 'GET', 403),
                    ('/snapshot?pid=12', 'a'*64, 'GET', 404), ('/snapshot', 'a'*64, 'POST', 405)]:
                request = Request(base+path, headers={'Authorization': 'Bearer '+token}, method=method)
                with self.subTest(path=path, method=method), self.assertRaises(HTTPError) as error:
                    urlopen(request, timeout=3)
                self.assertEqual(error.exception.code, expected)
            self.assertEqual(calls, [])
            request = Request(base+'/snapshot', headers={'Authorization': 'Bearer '+'a'*64})
            with urlopen(request, timeout=3) as response: data = json.load(response)
            self.assertEqual(data['nodes'][0]['valueDescription'], 'Yüzde 82')
            self.assertEqual(calls, [1])
        finally:
            server.shutdown(); server.server_close(); thread.join(timeout=3)

    def test_inspection_failure_remains_failed(self):
        def blocked(): raise ValueError('The helper has no Accessibility permission')
        server = make_server(blocked, 'b'*64)
        thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
        try:
            request = Request(f'http://127.0.0.1:{server.server_port}/snapshot',
                              headers={'Authorization': 'Bearer '+'b'*64})
            with self.assertRaises(HTTPError) as error: urlopen(request, timeout=3)
            self.assertEqual(error.exception.code, 503)
            record = json.load(error.exception)
            self.assertFalse(record['ok'])
        finally:
            server.shutdown(); server.server_close(); thread.join(timeout=3)


if __name__ == '__main__': unittest.main()
