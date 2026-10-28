#!/usr/bin/env python3
"""Universal pack merging and installed release integrity contracts."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import bundle_engines as packs

ROOT = Path(__file__).resolve().parent.parent

class PresenceTests(unittest.TestCase):
    def test_release_tools_are_present(self):
        for name in ('merge_engine_packs.py', 'verify_bundled_engines.py', 'smoke_bundled_engines.py'):
            self.assertTrue((ROOT/'script'/name).is_file(), name+' is missing')

@unittest.skipUnless((ROOT/'script/merge_engine_packs.py').is_file(), 'Merger not implemented')
class MergeTests(unittest.TestCase):
    def setUp(self):
        import merge_engine_packs
        self.m = merge_engine_packs
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.arm = self.make_pack('arm64'); self.intel = self.make_pack('x86_64')
        self.output = self.root/'universal'

    def make_pack(self, arch):
        root=self.root/arch; root.mkdir()
        content={'bin/magick':b'fixture-'+arch.encode(), 'sources/original.tar':b'identical source archive',
                 'sources/BUILD.txt':('native build '+arch).encode(),
                 'sources/build-record.json':json.dumps({'arch':arch}).encode(), 'licenses/imagemagick.txt':b'license fixture'}
        for name,data in content.items():
            path=root/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
        manifest={'schema':1,'engine':'imagemagick','version':'7.1.2-34','architectures':[arch],
            'minimumMacOS':'13.0','executables':['bin/magick'],'buildFlags':['--disable-shared'],
            'components':[{'name':'imagemagick','license':'ImageMagick','notice':'licenses/imagemagick.txt',
                           'source':'sources/original.tar','buildInstructions':'sources/BUILD.txt'}],
            'files':{name:packs.digest(root/name) for name in content}}
        (root/'manifest.json').write_text(json.dumps(manifest))
        return root

    def change(self, root, name, data):
        p=root/name;p.write_bytes(data)
        m=json.loads((root/'manifest.json').read_text());m['files'][name]=packs.digest(p)
        (root/'manifest.json').write_text(json.dumps(m))

    def merge(self, fail=False):
        def lipo(argv, **kw):
            self.assertEqual('/usr/bin/lipo',argv[0]); self.assertIn('-create',argv)
            if fail: raise OSError('lipo fixture failure')
            Path(argv[-1]).write_bytes(b'universal-fixture')
        with patch.object(self.m.packs,'verify_macho',return_value=[]), patch.object(self.m.subprocess,'run',side_effect=lipo):
            self.m.merge(self.arm,self.intel,self.output)

    def test_both_native_records_and_complete_sources_survive(self):
        self.merge()
        m=packs.validate_pack(self.output,{'arm64','x86_64'})
        self.assertEqual(['arm64','x86_64'],m['architectures'])
        self.assertEqual(b'identical source archive',(self.output/'sources/original.tar').read_bytes())
        for arch,source in [('arm64',self.arm),('x86_64',self.intel)]:
            for name in ('manifest.json','sources/BUILD.txt','sources/build-record.json'):
                self.assertEqual((source/name).read_bytes(),(self.output/'sources/native'/arch/name).read_bytes())
        self.assertEqual(b'universal-fixture',(self.output/'bin/magick').read_bytes())
        self.assertIn('merge_engine_packs.py', (self.output/'sources/BUILD.txt').read_text())
        self.assertEqual(b'fixture-arm64',(self.arm/'bin/magick').read_bytes())

    def test_changed_source_or_notice_is_not_silently_selected(self):
        for name in ('sources/original.tar','licenses/imagemagick.txt'):
            before=(self.intel/name).read_bytes()
            self.change(self.intel,name,b'different')
            with self.assertRaises(ValueError):self.merge()
            self.assertFalse(self.output.exists())
            self.change(self.intel,name,before)

    def test_mismatched_versions_architectures_and_components_fail(self):
        path=self.intel/'manifest.json';original=json.loads(path.read_text())
        for field,value in [('version','other'),('architectures',['arm64']),('minimumMacOS','14.0')]:
            m=dict(original);m[field]=value;path.write_text(json.dumps(m))
            with self.subTest(field=field),self.assertRaises(ValueError):self.merge()
            self.assertFalse(self.output.exists())
        path.write_text(json.dumps(original))

    def test_existing_output_and_failed_merge_preserve_sources(self):
        self.output.mkdir();sentinel=self.output/'keep';sentinel.write_text('keep')
        with self.assertRaises(ValueError):self.merge()
        self.assertEqual('keep',sentinel.read_text());sentinel.unlink();self.output.rmdir()
        with self.assertRaises(OSError):self.merge(fail=True)
        self.assertFalse(self.output.exists())
        self.assertFalse(list(self.root.glob('.merge-engine-*')))

    def test_unlisted_file_and_nested_output_are_refused(self):
        extra=self.arm/'extra';extra.write_text('unlisted')
        with self.assertRaises(ValueError):self.merge()
        extra.unlink();self.output=self.arm/'nested'
        with self.assertRaises(ValueError):self.merge()

@unittest.skipUnless((ROOT/'script/verify_bundled_engines.py').is_file(), 'Verifier not implemented')
class InstalledTests(unittest.TestCase):
    def setUp(self):
        import verify_bundled_engines
        self.v=verify_bundled_engines
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name);self.app=self.root/'Lemulip.app'
        (self.app/'Contents/Resources').mkdir(parents=True)
        self.packs=self.root/'packs';self.packs.mkdir()
        for engine,executables in [('ffmpeg',['ffmpeg','ffprobe']),('imagemagick',['magick'])]:
            root=self.packs/engine;root.mkdir()
            content={**{'bin/'+name:b'native-fixture' for name in executables},
                     'sources/original.tar':b'source','sources/BUILD.txt':b'build','licenses/notice.txt':b'notice'}
            for name,data in content.items():
                p=root/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data)
            m={'schema':1,'engine':engine,'version':'1.0','architectures':['arm64','x86_64'],'minimumMacOS':'13.0',
               'executables':['bin/'+e for e in executables],'buildFlags':[],
               'components':[{'name':engine,'license':'MIT','notice':'licenses/notice.txt','source':'sources/original.tar','buildInstructions':'sources/BUILD.txt'}],
               'files':{name:packs.digest(root/name) for name in content}}
            (root/'manifest.json').write_text(json.dumps(m))
        with patch.object(packs,'verify_macho',side_effect=lambda root,m,arches:[root/e for e in m['executables']]), \
             patch.object(packs.subprocess,'run'):
            packs.stage_packs(self.packs,self.app,{'arm64','x86_64'})

    def verify(self):
        with patch.object(self.v.packs,'verify_macho',return_value=[]),patch.object(self.v.subprocess,'run'):
            return self.v.verify(self.app,{'arm64','x86_64'})

    def test_both_release_engines_are_required_and_verified(self):
        result=self.verify()
        self.assertEqual({'ffmpeg','imagemagick'},set(result))
        self.assertEqual(2,result['ffmpeg']['executables'])

    def test_missing_notice_or_changed_helper_fails(self):
        for relative in ('Contents/Helpers/ffmpeg','Contents/Resources/EngineSupport/imagemagick/licenses/notice.txt'):
            p=self.app/relative;old=p.read_bytes();p.write_bytes(b'changed')
            with self.subTest(path=relative),self.assertRaises(ValueError):self.verify()
            p.write_bytes(old)

    def test_mapping_cannot_escape_or_redirect_to_another_engine(self):
        p=self.app/'Contents/Resources/EngineSupport/ffmpeg/installed-manifest.json';old=p.read_text()
        for redirect in ('../outside','Contents/Helpers/magick'):
            m=json.loads(old);m['sourceToBundle']['bin/ffmpeg']=redirect;p.write_text(json.dumps(m))
            with self.assertRaises(ValueError):self.verify()
        p.write_text(old)

    def test_unlisted_resource_is_rejected(self):
        (self.app/'Contents/Resources/EngineSupport/ffmpeg/extra').write_text('unexpected')
        with self.assertRaises(ValueError):self.verify()

    def test_updated_installed_hash_cannot_hide_changed_license(self):
        resource=self.app/'Contents/Resources/EngineSupport/ffmpeg/licenses/notice.txt';resource.write_text('rewritten')
        p=self.app/'Contents/Resources/EngineSupport/ffmpeg/installed-manifest.json';m=json.loads(p.read_text())
        m['files'][resource.relative_to(self.app).as_posix()]=packs.digest(resource);p.write_text(json.dumps(m))
        with self.assertRaises(ValueError):self.verify()

class ReleaseWiringTests(unittest.TestCase):
    def test_release_requires_native_packs_and_verifies_the_downloaded_app(self):
        workflow=(ROOT/'.github/workflows/build.yml').read_text()
        self.assertIn('  native-engines:',workflow)
        self.assertIn('needs: [test, native-engines]',workflow)
        self.assertIn('from merge_engine_packs import merge',workflow)
        self.assertIn("merge(sources['arm64',engine],sources['x86_64',engine]",workflow)
        self.assertIn('LEMULIP_ENGINE_PACKS:',workflow)
        script=(ROOT/'script/package_release.sh').read_text()
        self.assertIn('script/verify_bundled_engines.py',script)
        self.assertIn('script/smoke_bundled_engines.py',script)

@unittest.skipUnless((ROOT/'script/smoke_bundled_engines.py').is_file(), 'Smoke checks not implemented')
class SmokeContracts(unittest.TestCase):
    def test_health_requires_ready_state_and_the_actual_bundle_path(self):
        import smoke_bundled_engines as m
        app=Path('/package/Lemulip.app')
        good='ffmpeg: ready 8.1.2 · '+str(app/'Contents/Helpers/ffmpeg')+'\nimagemagick: ready 7.1.2 · '+str(app/'Contents/Helpers/magick')
        m.check_health(good,app)
        for bad in (good.replace('ffmpeg: ready','ffmpeg: limited'), good.replace(str(app/'Contents/Helpers/ffmpeg'),'/usr/local/bin/ffmpeg')):
            with self.assertRaises(ValueError):m.check_health(bad,app)

if __name__=='__main__':unittest.main()
