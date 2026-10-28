#!/usr/bin/env python3
"""Regression tests for bounded, pinned media-engine source builds."""
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest

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
