#!/usr/bin/env python3
"""Regression tests for bounded, pinned media-engine source builds."""
import gzip
import hashlib
import importlib.util
import io
import json
import lzma
import os
from pathlib import Path
import stat
import tarfile
import tempfile
import unittest
from unittest.mock import patch
import subprocess

ROOT = Path(__file__).resolve().parent.parent

class MediaBuildTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        path = ROOT / 'script/build_media_engine.py'
        assert path.is_file(), 'Native media source builder is not implemented'
        spec = importlib.util.spec_from_file_location('build_media_engine', path)
        cls.m = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.m)

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def archive(self, entries):
        target = self.root / 'fixture.tar'
        with tarfile.open(target, 'w') as tar:
            for name, kind in entries:
                item = tarfile.TarInfo(name)
                item.mode = 0o755
                if kind == 'file':
                    item.size = 4
                    tar.addfile(item, io.BytesIO(b'data'))
                else:
                    item.type = kind
                    item.linkname = 'target'
                    tar.addfile(item)
        return target

    def test_lock_covers_exact_selected_codecs_with_immutable_pins(self):
        lock = self.m.load_lock(ROOT / 'script/media-engine-sources.json')
        self.assertEqual({'ffmpeg', 'x264', 'libvpx', 'lame', 'opus', 'libogg', 'libvorbis'}, {c['name'] for c in lock['components']})
        for c in lock['components']:
            if c['kind'] == 'archive':
                self.assertRegex(c['sha256'], r'^[a-f0-9]{64}$')
            else:
                self.assertRegex(c['revision'], r'^[a-f0-9]{40}$')
        self.assertEqual('13.0', lock['minimumMacOS'])

    def test_mutable_revision_and_http_are_rejected(self):
        source = json.loads((ROOT / 'script/media-engine-sources.json').read_text())
        for change in ({'url': 'http://example.invalid/a.tar'}, {'revision': 'main', 'kind': 'git'}):
            changed = json.loads(json.dumps(source))
            changed['components'][0].update(change)
            p = self.root / 'lock.json'; p.write_text(json.dumps(changed))
            with self.assertRaises(ValueError): self.m.load_lock(p)

    def test_digest_mismatch_fails_before_extraction(self):
        p = self.archive([('source/configure', 'file')])
        with self.assertRaises(ValueError): self.m.verify_digest(p, '0' * 64)
        self.assertEqual(hashlib.sha256(p.read_bytes()).hexdigest(), self.m.verify_digest(p, hashlib.sha256(p.read_bytes()).hexdigest()))

    def source_download_fixture(self):
        payload = self.archive([('source/configure', 'file')]).read_bytes()
        work = self.root / 'download-work'; work.mkdir()
        sources = self.root / 'sources'; sources.mkdir()
        component = {'name': 'ffmpeg', 'kind': 'archive',
                     'url': 'https://example.invalid/ffmpeg.tar',
                     'sha256': hashlib.sha256(payload).hexdigest()}
        return payload, work, sources, component

    def test_source_download_retries_connection_resets_with_bounded_https(self):
        payload, work, sources, component = self.source_download_fixture()
        calls = []
        def transfer(argv, **kwargs):
            calls.append(argv)
            self.assertTrue(kwargs['check'])
            Path(argv[argv.index('--output') + 1]).write_bytes(payload)
        with patch.object(self.m.subprocess, 'run', side_effect=transfer):
            extracted, archive = self.m.fetch_source(component, work, sources, {}, [])
        self.assertEqual(b'data', (extracted / 'configure').read_bytes())
        self.assertEqual(component['sha256'], self.m.sha256(archive))
        self.assertEqual(1, len(calls))
        args = calls[0]
        self.assertIn('--retry-all-errors', args)
        for flag, value in {'--retry': '2', '--connect-timeout': '30',
                            '--retry-max-time': '480', '--max-time': '240',
                            '--max-filesize': '200000000', '--proto': '=https',
                            '--proto-redir': '=https'}.items():
            self.assertEqual(value, args[args.index(flag) + 1])
        self.assertNotIn('--insecure', args)
        self.assertNotIn('-k', args)
        self.assertEqual(component['url'], args[-1])

    def test_exhausted_transfer_never_extracts_partial_source(self):
        _, work, sources, component = self.source_download_fixture()
        def interrupted(argv, **kwargs):
            Path(argv[argv.index('--output') + 1]).write_bytes(b'partial transfer')
            raise subprocess.CalledProcessError(35, argv)
        with patch.object(self.m.subprocess, 'run', side_effect=interrupted):
            with self.assertRaises(subprocess.CalledProcessError):
                self.m.fetch_source(component, work, sources, {}, [])
        self.assertFalse((work / 'ffmpeg-source').exists())

    def test_successful_transfer_with_wrong_digest_is_not_extracted(self):
        payload, work, sources, component = self.source_download_fixture()
        component['sha256'] = '0' * 64
        def transfer(argv, **kwargs):
            Path(argv[argv.index('--output') + 1]).write_bytes(payload)
        with patch.object(self.m.subprocess, 'run', side_effect=transfer):
            with self.assertRaisesRegex(ValueError, 'checksum mismatch'):
                self.m.fetch_source(component, work, sources, {}, [])
        self.assertFalse((work / 'ffmpeg-source').exists())

    def git_source_fixture(self, name='x264'):
        checkout = self.root / 'local-git'; checkout.mkdir()
        (checkout / 'configure').write_bytes(b'#!/bin/sh\necho fixture\n')
        (checkout / 'configure').chmod(0o755)
        (checkout / 'LICENSE').write_bytes(b'Complete fixture license\n')
        (checkout / 'src').mkdir()
        (checkout / 'src/main.c').write_bytes(b'int fixture(void) { return 0; }\n' * 100)
        environment = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
        environment.update(GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM='1',
            GIT_AUTHOR_NAME='Source fixture', GIT_AUTHOR_EMAIL='contributors@lemulip.invalid',
            GIT_COMMITTER_NAME='Source fixture', GIT_COMMITTER_EMAIL='contributors@lemulip.invalid',
            GIT_AUTHOR_DATE='2023-11-14T22:13:20Z', GIT_COMMITTER_DATE='2023-11-14T22:13:20Z')
        def git(*args):
            return subprocess.check_output(['/usr/bin/git', '-c', 'core.hooksPath=' + os.devnull,
                *args], cwd=checkout, env=environment, stderr=subprocess.PIPE, timeout=10)
        git('init', '--quiet')
        git('add', 'configure', 'LICENSE', 'src/main.c')
        git('commit', '--quiet', '-m', 'Source fixture')
        revision = git('rev-parse', 'HEAD').decode().strip()
        payload = git('archive', '--format=tar', '--prefix=' + name + '/', revision)
        return {'name': name, 'kind': 'git', 'revision': revision,
                'url': 'https://example.invalid/' + name + '.git'}, payload

    def fetch_git_fixture(self, component, payload, folder='fetch', sources=None, revision=None):
        work = self.root / folder; work.mkdir()
        if sources is None:
            sources = work / 'sources'; sources.mkdir()
        def exported(argv, cwd, environment, record):
            record.append({'directory': cwd.name, 'arguments': argv})
            if 'archive' in argv:
                target = next(arg.removeprefix('--output=') for arg in argv if arg.startswith('--output='))
                Path(target).write_bytes(payload)
        with patch.object(self.m, 'run', side_effect=exported), patch.object(
                self.m.subprocess, 'check_output', return_value=(revision or component['revision']) + '\n'):
            return self.m.fetch_source(component, work, sources, {}, [])

    def test_git_source_archive_is_lossless_xz_with_original_member_metadata(self):
        component, payload = self.git_source_fixture()
        extracted, archive = self.fetch_git_fixture(component, payload)
        self.assertEqual('x264-' + component['revision'] + '.tar.xz', archive.name)
        self.assertFalse(archive.with_suffix('').exists())
        self.assertLess(archive.stat().st_size, len(payload))
        decoder = lzma.LZMADecompressor(format=lzma.FORMAT_XZ)
        self.assertEqual(payload, decoder.decompress(archive.read_bytes()))
        self.assertTrue(decoder.eof)
        self.assertEqual(lzma.CHECK_CRC64, decoder.check)
        with tarfile.open(fileobj=io.BytesIO(payload)) as original:
            for member in original.getmembers():
                if not member.isfile():
                    continue
                path = extracted.parent / member.name
                self.assertEqual(original.extractfile(member).read(), path.read_bytes())
                self.assertEqual(member.mtime, path.stat().st_mtime)
                self.assertEqual(0o755 if member.mode & 0o111 else 0o644, stat.S_IMODE(path.stat().st_mode))

    def test_git_archive_compression_is_identical_for_separate_build_directories(self):
        component, payload = self.git_source_fixture()
        _, first = self.fetch_git_fixture(component, payload, folder='arm-build')
        _, second = self.fetch_git_fixture(component, payload, folder='intel-build')
        self.assertEqual('.xz', first.suffix)
        self.assertEqual(first.read_bytes(), second.read_bytes())

    def test_compressed_git_source_is_accepted_by_engine_pack_manifest(self):
        import bundle_engines
        component, payload = self.git_source_fixture(name='imagemagick')
        pack = self.root / 'pack'; sources = pack / 'sources'; sources.mkdir(parents=True)
        _, archive = self.fetch_git_fixture(component, payload, sources=sources)
        self.assertEqual('.xz', archive.suffix)
        for name, data in {'bin/magick': b'helper fixture', 'licenses/imagemagick.txt': b'license',
                           'sources/BUILD.txt': b'complete source fixture recipe'}.items():
            path = pack / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(data)
        manifest = {'schema': 1, 'engine': 'imagemagick', 'version': '7.1.2-34',
            'architectures': ['arm64'], 'minimumMacOS': '13.0', 'buildFlags': [],
            'executables': ['bin/magick'], 'components': [{'name': 'imagemagick',
                'license': 'ImageMagick', 'notice': 'licenses/imagemagick.txt',
                'source': 'sources/' + archive.name, 'buildInstructions': 'sources/BUILD.txt'}],
            'files': {p.relative_to(pack).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                      for p in pack.rglob('*') if p.is_file()}}
        (pack / 'manifest.json').write_text(json.dumps(manifest))
        self.assertEqual(manifest, bundle_engines.validate_pack(pack, {'arm64'}))
        self.assertEqual(payload, lzma.decompress(archive.read_bytes()))

    def test_downloaded_source_archives_are_preserved_byte_for_byte(self):
        original = self.archive([('source/configure', 'file')]).read_bytes()
        cases = {'gz': gzip.compress(original, mtime=0), 'xz': lzma.compress(original,
                 format=lzma.FORMAT_XZ, check=lzma.CHECK_CRC64, preset=0)}
        for suffix, payload in cases.items():
            with self.subTest(suffix=suffix):
                work = self.root / ('download-' + suffix); work.mkdir()
                sources = work / 'sources'; sources.mkdir()
                component = {'name': 'ffmpeg', 'kind': 'archive',
                    'url': 'https://example.invalid/ffmpeg.tar.' + suffix,
                    'sha256': hashlib.sha256(payload).hexdigest()}
                def transfer(argv, **kwargs):
                    Path(argv[argv.index('--output') + 1]).write_bytes(payload)
                with patch.object(self.m.subprocess, 'run', side_effect=transfer):
                    extracted, archive = self.m.fetch_source(component, work, sources, {}, [])
                self.assertEqual('ffmpeg.tar.' + suffix, archive.name)
                self.assertEqual(payload, archive.read_bytes())
                self.assertEqual(b'data', (extracted / 'configure').read_bytes())

    def test_git_revision_mismatch_is_rejected_before_export(self):
        component, payload = self.git_source_fixture()
        with self.assertRaisesRegex(ValueError, 'Source commit mismatch'):
            self.fetch_git_fixture(component, payload, revision='0' * 40)
        self.assertEqual([], list((self.root / 'fetch/sources').iterdir()))
        self.assertFalse((self.root / 'fetch/x264-source').exists())

    def test_failed_git_compression_keeps_original_and_removes_partial_xz(self):
        component, payload = self.git_source_fixture()
        def interrupted(source, output, length):
            output.write(source.read(1024))
            raise OSError('Interrupted fixture write')
        with patch.object(self.m.shutil, 'copyfileobj', side_effect=interrupted):
            with self.assertRaisesRegex(OSError, 'Interrupted fixture write'):
                self.fetch_git_fixture(component, payload)
        archive = self.root / 'fetch/sources' / ('x264-' + component['revision'] + '.tar')
        self.assertEqual(payload, archive.read_bytes())
        self.assertFalse(archive.with_suffix('.tar.xz').exists())
        self.assertFalse((self.root / 'fetch/x264-source').exists())

    def test_git_compression_roundtrip_mismatch_keeps_original(self):
        component, payload = self.git_source_fixture()
        open_xz = lzma.open
        def altered(filename, mode, **kwargs):
            if mode == 'rb':
                Path(filename).write_bytes(lzma.compress(b'X' + payload[1:], format=lzma.FORMAT_XZ))
            return open_xz(filename, mode, **kwargs)
        with patch.object(self.m.lzma, 'open', side_effect=altered):
            with self.assertRaisesRegex(ValueError, 'differs from its original export'):
                self.fetch_git_fixture(component, payload)
        archive = self.root / 'fetch/sources' / ('x264-' + component['revision'] + '.tar')
        self.assertEqual(payload, archive.read_bytes())
        self.assertFalse(archive.with_suffix('.tar.xz').exists())
        self.assertFalse((self.root / 'fetch/x264-source').exists())

    def test_git_compression_never_replaces_an_existing_xz_file(self):
        component, payload = self.git_source_fixture()
        sources = self.root / 'sources'; sources.mkdir()
        existing = sources / ('x264-' + component['revision'] + '.tar.xz')
        existing.write_bytes(b'preserve existing file')
        with self.assertRaises(FileExistsError):
            self.fetch_git_fixture(component, payload, sources=sources)
        self.assertEqual(b'preserve existing file', existing.read_bytes())
        self.assertEqual(payload, existing.with_suffix('').read_bytes())
        self.assertFalse((self.root / 'fetch/x264-source').exists())

    def test_compressed_git_sources_keep_existing_extraction_guards(self):
        component, _ = self.git_source_fixture()
        payload = self.archive([('source/../../escape', 'file')]).read_bytes()
        with self.assertRaisesRegex(ValueError, 'Noncanonical source path'):
            self.fetch_git_fixture(component, payload)
        self.assertFalse((self.root / 'fetch/x264-source').exists())
        self.assertFalse((self.root / 'escape').exists())

    def test_regular_sources_preserve_executable_mode(self):
        p = self.archive([('source/configure', 'file'), ('source/src/main.c', 'file')])
        root = self.m.extract_source(p, self.root / 'output')
        self.assertEqual(b'data', (root / 'configure').read_bytes())
        self.assertTrue((root / 'configure').stat().st_mode & 0o111)

    def test_source_timestamps_do_not_force_unplanned_autotools_regeneration(self):
        archive=self.root/'timestamps.tar'
        with tarfile.open(archive,'w') as tar:
            for index,name in enumerate(('configure.ac','aclocal.m4','Makefile.in','configure')):
                item=tarfile.TarInfo('source/'+name);item.size=4;item.mtime=1700000000+index
                tar.addfile(item,io.BytesIO(b'data'))
        output=self.m.extract_source(archive,self.root/'preserved')
        for index,name in enumerate(('configure.ac','aclocal.m4','Makefile.in','configure')):
            self.assertEqual(1700000000+index,(output/name).stat().st_mtime)

    def test_traversal_links_devices_and_duplicate_paths_are_rejected(self):
        cases = [[('../escape', 'file')], [('/absolute', 'file')], [('source/link', tarfile.SYMTYPE)],
                 [('source/link', tarfile.LNKTYPE)], [('source/device', tarfile.CHRTYPE)],
                 [('source/x', 'file'), ('source/x', 'file')], [('source/a/../b', 'file')]]
        for i, entries in enumerate(cases):
            with self.subTest(entries=entries):
                p = self.archive(entries)
                with self.assertRaises(ValueError): self.m.extract_source(p, self.root / f'bad-{i}')
                self.assertFalse((self.root / f'bad-{i}').exists())

    def test_source_budget_is_enforced(self):
        p = self.archive([('source/configure', 'file')])
        with self.assertRaises(ValueError): self.m.extract_source(p, self.root / 'small', maximum_bytes=3)

    def test_build_flags_keep_codec_coverage_without_network_or_nonfree(self):
        flags = self.m.configure_arguments('ffmpeg', self.root / 'prefix', 'arm64')
        for name in ['libx264', 'libmp3lame', 'libopus', 'libvorbis', 'libvpx']:
            self.assertIn('--enable-' + name, flags)
        for flag in ['--disable-autodetect', '--disable-network', '--disable-shared', '--enable-static', '--enable-gpl']:
            self.assertIn(flag, flags)
        self.assertNotIn('--enable-nonfree', flags)
        self.assertNotIn('--enable-openssl', flags)
        self.assertTrue(any(f.startswith('--extra-cflags=-I') for f in flags))
        self.assertTrue(any(f.startswith('--extra-ldflags=-L') for f in flags))

    def test_vorbis_obsolete_linker_flag_is_removed_and_patch_is_retained(self):
        source = self.root / 'vorbis'; source.mkdir()
        sources = self.root / 'sources'; sources.mkdir()
        original = '#!/bin/sh\n' + 'CFLAGS="-DDARWIN -force_cpusubtype_ALL -O3"\n' * 3
        (source / 'configure').write_text(original)
        (source / 'configure').chmod(0o755)
        patch = self.m.prepare_source('libvorbis', source, sources)
        self.assertNotIn(' -force_cpusubtype_ALL', (source / 'configure').read_text())
        self.assertTrue((source / 'configure').stat().st_mode & 0o111)
        self.assertTrue(patch.is_file())
        self.assertIn('-CFLAGS="-DDARWIN -force_cpusubtype_ALL -O3"', patch.read_text())
        self.assertIn('+CFLAGS="-DDARWIN -O3"', patch.read_text())

    def test_vorbis_patch_refuses_unexpected_upstream_source(self):
        source = self.root / 'vorbis'; source.mkdir()
        sources = self.root / 'sources'; sources.mkdir()
        (source / 'configure').write_text('#!/bin/sh\necho unexpected\n')
        with self.assertRaises(ValueError): self.m.prepare_source('libvorbis', source, sources)
        self.assertEqual('#!/bin/sh\necho unexpected\n', (source / 'configure').read_text())

    def test_architecture_and_platform_mismatch_fail(self):
        for system, host, requested in [('Linux','arm64','arm64'), ('Darwin','x86_64','arm64'), ('Darwin','arm64','unknown')]:
            with self.assertRaises(ValueError): self.m.assert_host(system, host, requested)
        self.m.assert_host('Darwin', 'arm64', 'arm64')

    def test_unknown_component_cannot_run_arbitrary_configure(self):
        with self.assertRaises(ValueError): self.m.configure_arguments('surprise', self.root, 'arm64')

    def test_source_lock_rejects_extra_or_duplicate_components(self):
        source = json.loads((ROOT / 'script/media-engine-sources.json').read_text())
        source['components'].append(source['components'][0])
        p = self.root / 'lock.json'; p.write_text(json.dumps(source))
        with self.assertRaises(ValueError): self.m.load_lock(p)

if __name__ == '__main__': unittest.main()
