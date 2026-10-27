#!/usr/bin/env python3
"""Reject unaudited or non-portable engine packs before modifying an app."""
import hashlib, json, pathlib, tempfile, unittest
import importlib.util
from types import SimpleNamespace
from unittest.mock import patch
ROOT = pathlib.Path(__file__).resolve().parent.parent

class EnginePackTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location('bundle_engines', ROOT/'script/bundle_engines.py')
        self.assertTrue((ROOT/'script/bundle_engines.py').is_file(), 'engine pack validation is not implemented')
        self.module = importlib.util.module_from_spec(spec); spec.loader.exec_module(self.module)
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root = pathlib.Path(self.tmp.name); self.pack = self.root/'pandoc'; self.pack.mkdir()
        content = {'bin/pandoc': b'fixture only', 'licenses/COPYING': b'GPL-2.0-or-later license fixture',
                   'sources/pandoc.tar': b'corresponding source fixture', 'sources/build.txt': b'build steps fixture'}
        for name, data in content.items():
            p=self.pack/name; p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data)
        self.manifest={'schema':1,'engine':'pandoc','version':'3.12.1','architectures':['arm64','x86_64'],
            'minimumMacOS':'13.0','executables':['bin/pandoc'],'buildFlags':[],
            'components':[{'name':'pandoc','license':'GPL-2.0-or-later','notice':'licenses/COPYING',
                           'source':'sources/pandoc.tar','buildInstructions':'sources/build.txt'}],
            'files':{name:hashlib.sha256(data).hexdigest() for name,data in content.items()}}
        self.save()
    def save(self): (self.pack/'manifest.json').write_text(json.dumps(self.manifest))
    def validate(self): return self.module.validate_pack(self.pack, required_architectures={'arm64','x86_64'})
    def test_manifest_returns_exact_inventory(self):
        self.assertEqual('pandoc', self.validate()['engine'])
    def test_tamper_is_rejected(self):
        (self.pack/'bin/pandoc').write_bytes(b'changed')
        with self.assertRaises(ValueError): self.validate()
    def test_unlisted_files_and_symlinks_are_rejected(self):
        extra=self.pack/'unlisted'; extra.write_bytes(b'x')
        with self.assertRaises(ValueError): self.validate()
        extra.unlink(); extra.symlink_to(self.pack/'bin/pandoc')
        with self.assertRaises(ValueError): self.validate()
    def test_traversal_and_noncanonical_paths_are_rejected(self):
        for path in ['../outside','/absolute','bin/../pandoc','bin//pandoc','bin/./pandoc','bin\\pandoc']:
            with self.subTest(path=path):
                old=self.manifest['files'];self.manifest['files']={path:'a'*64};self.save()
                with self.assertRaises(ValueError): self.validate()
                self.manifest['files']=old
    def test_license_source_and_build_instructions_are_mandatory(self):
        for key in ['notice','source','buildInstructions']:
            with self.subTest(key=key):
                saved=self.manifest['components'][0].pop(key);self.save()
                with self.assertRaises(ValueError):self.validate()
                self.manifest['components'][0][key]=saved
    def test_nonfree_and_incompatible_architectures_are_rejected(self):
        self.manifest['buildFlags']=['--enable-nonfree'];self.save()
        with self.assertRaises(ValueError):self.validate()
        self.manifest['buildFlags']=[];self.manifest['architectures']=['arm64'];self.save()
        with self.assertRaises(ValueError):self.validate()
    def test_newer_minimum_macos_and_unknown_engine_are_rejected(self):
        self.manifest['minimumMacOS']='15.0';self.save()
        with self.assertRaises(ValueError):self.validate()
        self.manifest['minimumMacOS']='13.0';self.manifest['engine']='../../evil';self.save()
        with self.assertRaises(ValueError):self.validate()
    def test_empty_components_and_missing_helpers_are_rejected(self):
        self.manifest['components']=[];self.save()
        with self.assertRaises(ValueError):self.validate()
    def test_non_macho_fixture_is_not_distribution_ready(self):
        with self.assertRaises(ValueError):self.module.verify_macho(self.pack, self.validate(), {'arm64','x86_64'})
    def test_disabled_nonfree_is_allowed_but_malformed_manifest_types_are_rejected(self):
        self.manifest['buildFlags']=['--disable-nonfree'];self.save()
        self.assertEqual('pandoc',self.validate()['engine'])
        for key,value in [('engine',[]),('schema',True),('architectures',['arm64',[]])]:
            old=self.manifest[key];self.manifest[key]=value;self.save()
            with self.assertRaises(ValueError):self.validate()
            self.manifest[key]=old
    def native_fixture(self, load):
        binary = self.pack / 'bin/pandoc'
        binary.write_bytes(b'\xcf\xfa\xed\xfe' + b'fixture')
        def output(argv, **kwargs):
            if '-l' in argv: return load
            if '-L' in argv: return str(binary) + ':\n\t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1351.0.0)\n'
            raise AssertionError(argv)
        with patch.object(self.module.os, 'uname', return_value=SimpleNamespace(sysname='Darwin')), \
             patch.object(self.module.subprocess, 'run', return_value=SimpleNamespace(stdout='arm64\n')), \
             patch.object(self.module.subprocess, 'check_output', side_effect=output):
            return self.module.verify_macho(self.pack, self.manifest, {'arm64'})

    def test_modern_macos_target_does_not_include_linker_or_sdk_version(self):
        load = 'Load command 8\n      cmd LC_BUILD_VERSION\n  cmdsize 32\n platform 1\n    minos 13.0\n      sdk 26.3\n   ntools 1\n     tool 3\n  version 1230.1\n'
        try:
            result = self.native_fixture(load)
        except ValueError as error:
            self.fail('A valid macOS target was rejected because tool/SDK versions leaked into it: ' + str(error))
        self.assertEqual([self.pack/'bin/pandoc'], result)

    def test_native_verifier_rejects_newer_macos_and_other_platforms(self):
        for platform, minimum in [('1', '14.0'), ('IOS', '13.0'), ('2', '13.0'), ('MACCATALYST', '13.0')]:
            with self.subTest(platform=platform, minimum=minimum):
                load = f'Load command 8\n cmd LC_BUILD_VERSION\n platform {platform}\n minos {minimum}\n sdk 26.3\n ntools 0\n'
                with self.assertRaises(ValueError): self.native_fixture(load)

    def test_legacy_macos_target_is_supported_but_missing_target_is_not(self):
        load = 'Load command 5\n cmd LC_VERSION_MIN_MACOSX\n cmdsize 16\n version 10.15\n sdk 15.0\n'
        self.assertEqual([self.pack/'bin/pandoc'], self.native_fixture(load))
        for load in ['Load command 5\n cmd LC_SOURCE_VERSION\n version 13.0\n',
                     'Load command 5\n cmd LC_BUILD_VERSION\n platform 1\n sdk 13.0\n ntools 0\n']:
            with self.assertRaises(ValueError): self.native_fixture(load)

    def test_existing_bundle_is_never_overwritten(self):
        target=self.root/'App.app'; (target/'Contents/Helpers/Engines').mkdir(parents=True)
        sentinel=target/'Contents/Helpers/Engines/keep';sentinel.write_text('preserve')
        with self.assertRaises(ValueError):self.module.stage_packs(self.root, target, {'arm64','x86_64'})
        self.assertEqual('preserve',sentinel.read_text())
if __name__=='__main__':unittest.main()
