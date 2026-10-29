#!/usr/bin/env python3
"""Reject unsafe staging and incomplete dSYMs without changing build products."""
import json
from pathlib import Path
import shutil
import stat
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import measure_binary_symbols as macho
import prepare_binary_symbols as prepare
from test_measure_binary_symbols import fixture


def dwarf_fixture(*, cpu=0x0100000C, image_uuid=b'0123456789abcdef'):
    data = bytearray(fixture(cpu=cpu, image_uuid=image_uuid, filetype=0xA))
    # First section becomes actual DWARF data; the second remains virtual BSS.
    struct.pack_into('<16s16s', data, 32 + 72, b'__debug_info', b'__DWARF')
    struct.pack_into('<I', data, 32 + 72 + 64, 0x02000000)
    return bytes(data)


class SymbolStagingTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.build = self.root / 'build'
        self.build.mkdir()
        self.staging, self.symbols = self.root / 'staging', self.root / 'symbols'
        self.originals = {}
        for name in prepare.PRODUCTS:
            path = self.build / name
            path.write_bytes(fixture())
            path.chmod(0o755)
            self.originals[name] = (path.read_bytes(), path.stat().st_mtime_ns)
        self.commands = []
        self.dsym_warning = ''
        self.dsym_uuid = b'0123456789abcdef'
        self.corrupt_code = False
        self.mutate_original = False
        self.patches = [patch.object(prepare, 'command', side_effect=self.command),
                        patch.object(macho, 'command', side_effect=self.command)]
        for item in self.patches:
            item.start()
            self.addCleanup(item.stop)

    def command(self, arguments, *, required=True):
        args = [str(value) for value in arguments]
        self.commands.append(args)
        output = error = ''
        if 'dsymutil' in args:
            destination = Path(args[-1]) / 'Contents/Resources/DWARF'
            destination.mkdir(parents=True)
            (destination / Path(args[-3]).name).write_bytes(dwarf_fixture(image_uuid=self.dsym_uuid))
            error = self.dsym_warning
        elif 'dwarfdump' in args:
            pass
        elif args[0] == '/usr/bin/strip':
            self.assertEqual(args[1:3], ['-S', '-x'])
            target = Path(args[-1])
            self.assertNotEqual(target.parent, self.build)
            code = b'\0\2\3\4' if self.corrupt_code else b'\1\2\3\4'
            target.write_bytes(fixture(code=code, symbols=[('_export', 0x0F, 0x100000200), ('_import', 1, 0)]))
            if self.mutate_original:
                (self.build / target.name).write_bytes(b'changed original')
        elif args[:2] == ['/usr/bin/lipo', '-archs']:
            output = 'arm64\n'
        elif args[0] == '/usr/bin/codesign':
            pass
        else:
            raise AssertionError('Unexpected command: ' + str(args))
        return subprocess.CompletedProcess(args, 0, output, error)

    def stage(self):
        return prepare.prepare({'arm64': self.build}, self.staging, self.symbols, self.root)

    def signed_copies(self):
        paths = []
        for name in prepare.PRODUCTS:
            final = self.root / ('signed-' + name)
            shutil.copy2(self.staging / 'arm64' / name, final)
            paths.append(final)
        return paths

    def assert_originals_unchanged(self):
        for name, (data, modified) in self.originals.items():
            path = self.build / name
            self.assertEqual(path.read_bytes(), data)
            self.assertEqual(path.stat().st_mtime_ns, modified)
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o755)

    def test_staging_and_final_verification_keep_originals_and_matching_dsyms(self):
        report = self.stage()
        self.assertEqual(report['result'], 'STAGED')
        self.assertIsNone(report['commit'])
        self.assertEqual(report['sourceKind'], 'exported-source')
        self.assert_originals_unchanged()
        for index, args in enumerate(self.commands):
            if args[0] == '/usr/bin/strip':
                self.assertTrue(any('dwarfdump' in previous for previous in self.commands[:index]))
        gui, cli = self.signed_copies()
        final = prepare.verify_signed(self.symbols, gui, cli, self.root)
        self.assertEqual(final['result'], 'PASS')
        for name, path in zip(prepare.PRODUCTS, [gui, cli]):
            self.assertEqual(final['finalProducts'][name]['SHA256'], macho.digest(path.read_bytes()))
            self.assertEqual(final['finalProducts'][name]['slices']['arm64']['symbols']['local'], 0)
        self.assert_originals_unchanged()

    def test_runtime_change_is_rejected_before_publication(self):
        self.corrupt_code = True
        with self.assertRaisesRegex(ValueError, 'runtimeSectionsSHA256'):
            self.stage()
        self.assertFalse(self.staging.exists())
        self.assertFalse(self.symbols.exists())
        self.assert_originals_unchanged()

    def test_mismatched_dsym_is_rejected_before_strip(self):
        self.dsym_uuid = b'fedcba9876543210'
        with self.assertRaisesRegex(ValueError, 'mismatched dSYM'):
            self.stage()
        self.assertFalse(any(args[0] == '/usr/bin/strip' for args in self.commands))
        self.assert_originals_unchanged()

    def test_incomplete_debug_information_warning_is_a_failure(self):
        self.dsym_warning = 'warning: unable to open object file\n'
        with self.assertRaisesRegex(ValueError, 'generation reported a diagnostic'):
            self.stage()
        self.assertFalse(any(args[0] == '/usr/bin/strip' for args in self.commands))
        self.assert_originals_unchanged()

    def test_accidental_original_mutation_is_detected(self):
        self.mutate_original = True
        with self.assertRaisesRegex(ValueError, 'Original build product changed'):
            self.stage()
        self.assertFalse(self.staging.exists())
        self.assertFalse(self.symbols.exists())

    def test_existing_outputs_and_overlapping_destinations_are_preserved(self):
        self.symbols.mkdir()
        sentinel = self.symbols / 'keep'
        sentinel.write_text('existing evidence')
        with self.assertRaisesRegex(ValueError, 'must be new'):
            self.stage()
        self.assertEqual(sentinel.read_text(), 'existing evidence')
        self.assertFalse(self.staging.exists())
        with self.assertRaisesRegex(ValueError, 'must be separate'):
            prepare.prepare({'arm64': self.build}, self.staging, self.staging / 'nested', self.root)
        self.assert_originals_unchanged()

    def test_changed_retained_dsym_invalidates_final_verification(self):
        report = self.stage()
        gui, cli = self.signed_copies()
        dsym = self.symbols / report['products'][0]['dSYM'] / 'Contents/Resources/DWARF/LemulipApp'
        dsym.write_bytes(dsym.read_bytes() + b'changed')
        with self.assertRaisesRegex(ValueError, 'Retained debug symbols changed'):
            prepare.verify_signed(self.symbols, gui, cli, self.root)
        self.assertNotEqual(json.loads((self.symbols / 'report.json').read_text())['result'], 'PASS')

    def test_changed_final_runtime_cannot_leave_a_stale_pass(self):
        self.stage()
        gui, cli = self.signed_copies()
        prepare.verify_signed(self.symbols, gui, cli, self.root)
        gui.write_bytes(fixture(code=b'\0\2\3\4', symbols=[('_export', 0x0F, 0x100000200), ('_import', 1, 0)]))
        with self.assertRaisesRegex(ValueError, 'runtimeSectionsSHA256'):
            prepare.verify_signed(self.symbols, gui, cli, self.root)
        self.assertNotEqual(json.loads((self.symbols / 'report.json').read_text())['result'], 'PASS')

    def test_original_replacement_after_staging_is_rejected(self):
        self.stage()
        gui, cli = self.signed_copies()
        (self.build / 'LemulipApp').write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'Original build product changed'):
            prepare.verify_signed(self.symbols, gui, cli, self.root)


if __name__ == '__main__':
    unittest.main()
