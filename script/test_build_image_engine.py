#!/usr/bin/env python3
"""Image pack contract and safety regressions, independent of native CI."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent

class ImplementationTest(unittest.TestCase):
    def test_builder_is_present(self):
        self.assertTrue((ROOT / 'script/build_image_engine.py').is_file(), 'Native image builder is missing')

@unittest.skipUnless((ROOT / 'script/build_image_engine.py').is_file(), 'Implementation not present yet')
class ImagePackTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        path = ROOT / 'script/build_image_engine.py'
        assert path.is_file(), 'Native ImageMagick source builder is not implemented'
        spec = importlib.util.spec_from_file_location('build_image_engine', path)
        cls.m = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.m)

    def test_complete_immutable_dependency_lock(self):
        lock = self.m.load_lock(ROOT / 'script/image-engine-sources.json')
        self.assertEqual(self.m.NAMES, {c['name'] for c in lock['components']})
        self.assertEqual('imagemagick', lock['components'][-1]['name'])
        self.assertEqual('13.0', lock['minimumMacOS'])
        for c in lock['components']:
            self.assertRegex(c.get('sha256', c.get('revision')), r'^(?:[a-f0-9]{40}|[a-f0-9]{64})$')

    def test_lock_refuses_duplicates_missing_unpinned_and_insecure_sources(self):
        source = json.loads((ROOT / 'script/image-engine-sources.json').read_text())
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / 'lock.json'
            for kind in ('duplicate', 'missing', 'unpinned', 'http', 'credentials', 'unknown-license'):
                s = json.loads(json.dumps(source))
                if kind == 'duplicate': s['components'].append(s['components'][0])
                elif kind == 'missing': s['components'].pop(0)
                elif kind == 'unpinned': s['components'][0]['sha256'] = 'latest'
                elif kind == 'http': s['components'][0]['url'] = 'http://example.invalid/a'
                elif kind == 'credentials': s['components'][0]['url'] = 'https://' + ':'.join(('user','pass')) + '@' + 'example.invalid/a'
                else: s['components'][0]['license'] = 'unreviewed'
                p.write_text(json.dumps(s))
                with self.subTest(kind=kind), self.assertRaises(ValueError): self.m.load_lock(p)

    def test_portable_static_magick_flags_disable_external_delegates(self):
        flags = self.m.configure_arguments('imagemagick', Path('/build/prefix'))
        for f in ('--disable-shared','--enable-static','--disable-installed','--without-modules','--without-perl','--without-x','--without-gslib','--without-rsvg','--without-magick-plus-plus','--disable-openmp','--disable-opencl'):
            self.assertIn(f, flags)
        for f in ('--with-heic=yes','--with-webp=yes','--with-jpeg=yes','--with-png=yes','--with-tiff=yes','--with-xml=yes','--with-lcms=yes'):
            self.assertIn(f, flags)
        self.assertNotIn('--enable-zero-configuration', flags)

    def test_heif_uses_reviewed_static_codecs_not_loadable_plugins(self):
        args = self.m.cmake_options('libheif')
        for f in ('-DENABLE_PLUGIN_LOADING=OFF','-DWITH_KVAZAAR=ON','-DWITH_LIBDE265=ON','-DWITH_AOM_ENCODER=ON','-DWITH_AOM_DECODER=ON','-DWITH_X265=OFF','-DWITH_X264=OFF','-DWITH_OpenH264_DECODER=OFF','-DWITH_DAV1D=OFF','-DWITH_RAV1E=OFF','-DWITH_FFMPEG_DECODER=OFF'):
            self.assertIn(f,args)

    def test_all_expected_coders_are_required(self):
        self.assertEqual({'PNG','JPEG','WEBP','AVIF','HEIC','TIFF','BMP','GIF','ICO','MSVG'},self.m.REQUIRED_READ)
        self.assertEqual(self.m.REQUIRED_READ-{'MSVG'}, self.m.REQUIRED_WRITE)
        listing='\n'.join(f'  {name}* {name} rw- sample' for name in self.m.REQUIRED_READ)
        self.m.check_formats(listing)
        with self.assertRaises(ValueError): self.m.check_formats(listing.replace('AVIF* AVIF rw-', 'AVIF* AVIF r--'))
        with self.assertRaises(ValueError): self.m.check_formats('PNG* PNG rw- only')

    def test_policy_disables_network_delegates_filters_and_indirect_reads(self):
        import xml.etree.ElementTree as ET
        rules = ET.fromstring(self.m.POLICY).findall('policy')
        for domain, pattern in [('delegate','*'),('filter','*'),('path','@*'),('coder','*')]:
            self.assertTrue(any(r.get('domain')==domain and r.get('pattern')==pattern and r.get('rights')=='none' for r in rules))
        self.assertTrue(any(r.get('name')=='memory' and r.get('value')=='256MiB' for r in rules))
        allow=next(r for r in rules if r.get('domain')=='coder' and r.get('rights')=='read|write')
        self.assertNotIn('HTTP', allow.get('pattern'))
        self.assertNotIn('MVG', allow.get('pattern'))

    def test_xml_build_disables_network_and_python(self):
        self.assertIn('--without-http',self.m.configure_arguments('libxml2',Path('/prefix')))
        self.assertIn('--without-python',self.m.configure_arguments('libxml2',Path('/prefix')))

    def test_unknown_dependencies_fail_closed(self):
        with self.assertRaises(ValueError): self.m.cmake_options('unknown')
        with self.assertRaises(ValueError): self.m.configure_arguments('unknown',Path('/prefix'))

    def test_static_format_listing_without_module_column_is_supported(self):
        listing='\n'.join(f'  {name}* rw+ sample' for name in self.m.REQUIRED_READ)
        self.m.check_formats(listing)

    def test_system_zlib_metadata_uses_sdk_version_and_no_extra_library_path(self):
        self.assertTrue(hasattr(self.m,'sdk_zlib_metadata'), 'SDK zlib metadata is missing')
        text=self.m.sdk_zlib_metadata('#define ZLIB_VERSION "1.2.12"\n')
        self.assertIn('Version: 1.2.12',text)
        self.assertIn('Libs: -lz',text)
        self.assertNotIn('-L',text)
        with self.assertRaises(ValueError):self.m.sdk_zlib_metadata('#define ZLIB_VERSION "unknown"')

    def test_upstream_copyright_filename_is_kept_as_a_license(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            for name in ('Copyright','COPYING.LESSER','LICENSE.md','PATENTS','README.ijg','unrelated.c'):
                (root/name).write_text(name)
            self.assertTrue(hasattr(self.m, 'source_notices'), 'libxml2 Copyright notice is not collected')
            names={p.name for p in self.m.source_notices(root)}
            self.assertEqual({'Copyright','COPYING.LESSER','LICENSE.md','PATENTS','README.ijg'}, names)

    def test_internal_svg_drawing_permission_is_bounded_to_private_work(self):
        self.assertTrue(hasattr(self.m,'scoped_svg_policy'))
        import xml.etree.ElementTree as ET
        rules=ET.fromstring(self.m.scoped_svg_policy(Path('/tmp/private-job'))).findall('policy')
        self.assertTrue(any(r.get('domain')=='path' and r.get('pattern')=='*' and r.get('rights')=='none' for r in rules))
        self.assertTrue(any(r.get('domain')=='path' and r.get('pattern')=='/tmp/private-job/*' and r.get('rights')=='read|write' for r in rules))
        self.assertTrue(any(r.get('domain')=='coder' and r.get('pattern')=='MVG' and r.get('rights')=='read' for r in rules))
        default=ET.fromstring(self.m.POLICY).findall('policy')
        self.assertFalse(any(r.get('pattern')=='MVG' and r.get('rights')=='read' for r in default))
        with self.assertRaises(ValueError): self.m.scoped_svg_policy(Path('/tmp/invalid&path'))

    def test_source_helpers_are_shared_not_reimplemented(self):
        self.assertEqual('build_media_engine',self.m.fetch_source.__module__)
        self.assertEqual('build_media_engine',self.m.sha256.__module__)

if __name__=='__main__': unittest.main()
