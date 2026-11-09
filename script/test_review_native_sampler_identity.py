#!/usr/bin/env python3
"""Portable D23 behavior tests using generated, explicitly synthetic evidence."""
from __future__ import annotations

import copy
import io
import json
from pathlib import Path
import stat
import struct
import subprocess
import sys
import tempfile
import unittest
import warnings
import zipfile

import review_native_sampler_identity as review
from native_sampler_identity_fixture import (
    BINARY, DSYM, EXE, FRAME, Fixture, clock, identity, native_clock,
)


class IdentityReviewTests(unittest.TestCase):
    def rejected(self, fixture, pattern=None):
        # These mutations deliberately repair the trusted member hashes. A pass
        # cannot be avoided merely because an outer digest stopped the parser.
        for name, expected in fixture.trust['architectures'][fixture.architecture]['members'].items():
            self.assertEqual(identity(fixture.files[name]), expected, name)
        with self.assertRaises(review.EvidenceError) as caught:
            review.validate_evidence(fixture.files, fixture.architecture, fixture.trust)
        message = str(caught.exception)
        self.assertNotRegex(message.lower(), r'archive (hash|digest|bytes)|member (hash|digest|bytes)')
        if pattern:
            self.assertRegex(message.lower(), pattern)
        return message

    def test_synthetic_baselines_are_semantic_only_on_both_architectures(self):
        for architecture in ('arm64', 'x86_64'):
            with self.subTest(architecture=architecture):
                fixture = Fixture(architecture)
                before = copy.deepcopy(fixture.files)
                result = review.validate_evidence(fixture.files, architecture, fixture.trust)
                self.assertFalse(result['archiveBytesVerified'])
                self.assertEqual(result['evidenceRole'], 'semantic-validation-only')
                for flag in ('originalD22Complete', 'exactReportPathMatched', 'postSamplePSAvailable'):
                    self.assertIs(result[flag], False)
                self.assertEqual(fixture.files, before)
                serialized = json.dumps(result)
                self.assertIn('/Users/USER/*/NativeSamplerCalibration', serialized)
                self.assertIn('/Users/*/NativeSamplerCalibration', serialized)
                self.assertNotIn(EXE, serialized)

    def test_wrong_swapped_and_duplicate_image_uuids_are_rejected(self):
        original = '11111111-1111-4111-8111-111111111111'
        other = '22222222-2222-4222-8222-222222222222'
        for case in ('wrong', 'swapped', 'duplicate-main', 'duplicate-foreign'):
            with self.subTest(case=case):
                f = Fixture()
                text = f.files['controlled-sample.txt'].decode()
                main = next(line for line in text.splitlines() if '<' + original + '>' in line)
                if case == 'wrong':
                    text = text.replace(original, other)
                elif case == 'swapped':
                    text = text.replace(original, other).replace(
                        '55555555-5555-4555-8555-555555555555', original)
                elif case == 'duplicate-main':
                    text += main + '\n'
                else:
                    text += main.replace('+NativeSamplerCalibration (0)', 'Foreign (0)') + '\n'
                f.files['controlled-sample.txt'] = text.encode()
                f.bind()
                self.rejected(f, r'uuid|image')

    def test_foreign_report_pid_parent_and_process_name_are_rejected(self):
        for old, new in [('[1234]', '[9999]'), ('(pid 1234)', '(pid 9999)'),
                         ('Python [1200]', 'Python [9999]'),
                         ('Process:         NativeSamplerCalibration', 'Process:         Other')]:
            with self.subTest(new=new):
                f = Fixture()
                f.replace_report(old, new)
                self.rejected(f, r'pid|parent|process|analysis|header')

    def test_wrong_or_translated_report_architecture_is_rejected(self):
        for architecture, code in [('arm64', 'X86-64'), ('x86_64', 'ARM64'),
                                   ('arm64', 'ARM64 (Translated)')]:
            with self.subTest(architecture=architecture, code=code):
                f = Fixture(architecture)
                f.replace_report('Code Type:       ' + ('ARM64' if architecture == 'arm64' else 'X86-64'),
                                 'Code Type:       ' + code)
                self.rejected(f, r'code|architecture|native')

    def test_wrong_image_name_and_main_load_are_rejected(self):
        for old, new in [('+NativeSamplerCalibration (0)', '+Other (0)'),
                         ('Load Address:    0x102c90000', 'Load Address:    0x102c90001'),
                         ('0x102c90000 - 0x102c90fff', '0x102c90001 - 0x102c90fff'),
                         ('0x102c90000 - 0x102c90fff', '0x102c90000 - 0x102c80000')]:
            with self.subTest(new=new):
                f = Fixture()
                f.replace_report(old, new)
                self.rejected(f, r'image|load|range|address')

    def test_named_frame_must_be_counted_in_call_graph_and_correct_image(self):
        for case in ('summary-only', 'zero-count', 'wrong-image', 'name-suffix', 'no-frame'):
            with self.subTest(case=case):
                f = Fixture()
                text = f.files['controlled-sample.txt'].decode()
                frame = next(line for line in text.splitlines() if '7 ' + FRAME in line)
                if case == 'summary-only':
                    text = text.replace(frame + '\n', '').replace(
                        'Sort by top of stack, same collapsed (when >= 5):',
                        'Sort by top of stack, same collapsed (when >= 5):\n' + frame)
                elif case == 'zero-count':
                    text = text.replace('7 ' + FRAME, '0 ' + FRAME)
                elif case == 'wrong-image':
                    text = text.replace(frame, frame.replace('(in NativeSamplerCalibration)', '(in Other)'))
                elif case == 'name-suffix':
                    text = text.replace(FRAME, FRAME + '_not_the_function')
                else:
                    text = text.replace(frame + '\n', '')
                f.files['controlled-sample.txt'] = text.encode()
                f.bind()
                self.rejected(f, r'frame|graph|symbol|sample count')

    def test_sampled_pc_and_reported_displacement_must_match_symbol(self):
        for old, new in [('0x102c90674', '0x999999999'),
                         ('0x102c90674', '0x102c90675'),
                         (') + 452 ', ') + 453 '), (') + 452 ', ') + 999999 ' )]:
            with self.subTest(new=new):
                f = Fixture()
                f.replace_report(old, new)
                self.rejected(f, r'pc|frame|offset|displacement|range|symbol')

    def test_arithmetic_match_cannot_label_pc_outside_known_wait_function(self):
        f = Fixture()
        f.replace_report(') + 452  [0x102c90674]', ') + 928  [0x102c90850]')
        self.rejected(f, r'function|symbol|extent|frame')

    def test_sample_pc_cannot_belong_to_overlapping_foreign_image(self):
        f = Fixture()
        f.files['controlled-sample.txt'] += (
            b'0x102c90000 - 0x102c90fff ForeignImage (0) '
            b'<AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA> /synthetic/foreign\n')
        f.bind()
        self.rejected(f, r'overlap|ambig|image|owner')

    def test_duplicate_headers_sections_and_ambiguous_frames_fail_closed(self):
        for line in ['Process:         NativeSamplerCalibration [1234]',
                     'Path:            /Users/USER/*/NativeSamplerCalibration',
                     'Code Type:       ARM64', 'Load Address:    0x102c90000',
                     'Parent Process:  Python [1200]', 'Call graph:', 'Binary Images:']:
            with self.subTest(line=line):
                f = Fixture()
                f.replace_report(line, line + '\n' + line)
                self.rejected(f, r'duplicate|ambig|one|exact|single|header|section|graph|image')

    def test_nm_header_and_frame_addresses_are_cross_checked(self):
        for old, new in [('00000001000004b0', '00000001000004b1'),
                         ('0000000100000000', '0000000100000001'),
                         (' T _' + FRAME, ' U _' + FRAME)]:
            with self.subTest(new=new):
                f = Fixture()
                f.files['build/helper-symbols.txt'] = f.files['build/helper-symbols.txt'].replace(old.encode(), new.encode())
                f.bind()
                self.rejected(f, r'nm|symbol|header')

    def test_macho_symbols_are_real_defined_unique_text_symbols(self):
        # Baseline contains an N_FUN/STABS duplicate, which is not a second
        # external symbol. Converting it to N_SECT must become ambiguous.
        for case in ('duplicate-external', 'undefined', 'wrong-section', 'wrong-value',
                     'wrong-header', 'bad-string-index', 'unbounded-strings', 'bad-load-size'):
            with self.subTest(case=case):
                f = Fixture()
                raw = bytearray(f.files[BINARY])
                if case == 'duplicate-external':
                    raw[0x924] = 0x0F
                elif case == 'undefined':
                    raw[0x914] = 0x01
                elif case == 'wrong-section':
                    raw[0x915] = 2
                elif case == 'wrong-value':
                    struct.pack_into('<Q', raw, 0x918, 0x1000004B1)
                elif case == 'wrong-header':
                    struct.pack_into('<Q', raw, 0x908, 0x100000001)
                elif case == 'bad-string-index':
                    struct.pack_into('<I', raw, 0x910, 999999)
                elif case == 'unbounded-strings':
                    # LC_SYMTAB starts after header + UUID + segment/section.
                    struct.pack_into('<I', raw, 32 + 24 + 152 + 20, 0xFFFFFFFF)
                else:
                    struct.pack_into('<I', raw, 36, 0xFFFFFFF8)
                f.files[BINARY] = bytes(raw)
                f.bind(binary=True)
                self.rejected(f, r'symbol|section|text|mach|load|bound|string|header|nm')

    def test_binary_dsym_and_native_uuid_cpu_bindings(self):
        for name, field in [(BINARY, 'uuid'), (DSYM, 'uuid'), (BINARY, 'cpu'), (DSYM, 'cpu')]:
            with self.subTest(name=name, field=field):
                f = Fixture()
                raw = bytearray(f.files[name])
                if field == 'uuid':
                    raw[40] ^= 0x80
                else:
                    struct.pack_into('<I', raw, 4, 0x1000007)
                f.files[name] = bytes(raw)
                f.bind(binary=name == BINARY)
                self.rejected(f, r'uuid|architecture|cpu|mach|identity mismatch')

    def test_mixed_native_receipt_identity_is_rejected(self):
        changes = {'pid': 9999, 'ppid': 9999, 'pgid': 9999, 'euid': 9999,
            'nonce': '99999999-9999-4999-8999-999999999999',
            'bootUUID': '99999999-9999-4999-8999-999999999999',
            'architecture': 'x86_64', 'machOUUID': '99999999-9999-4999-8999-999999999999',
            'sourceSHA256': 'f' * 64, 'experimentCommit': 'f' * 40,
            'experimentTree': 'f' * 40, 'executableSHA256': 'f' * 64,
            'executablePath': '/synthetic/foreign/binary', 'expectedFrame': FRAME + '_other',
            'identityValidated': False}
        for field, value in changes.items():
            with self.subTest(field=field):
                f = Fixture()
                f.edit('target-completion.json', lambda d: d.__setitem__(field, value))
                self.rejected(f)

    def test_native_translation_and_invalid_scalar_types_are_rejected(self):
        for field, value in [('translationProbe', {'returnCode': 0, 'errno': 0, 'value': 1}),
                             ('pid', True), ('euid', True), ('machTimebaseNumer', 0),
                             ('machTimebaseDenom', -1), ('safetyTimeoutSeconds', True),
                             ('receivedInputBytes', 1)]:
            with self.subTest(field=field):
                f = Fixture()
                f.edit('target-ready.json', lambda d: d.__setitem__(field, value))
                self.rejected(f)

    def test_native_lifecycle_and_cross_receipt_clock_order(self):
        changes = [('releaseClock', native_clock(103.0)),
                   ('completionClock', native_clock(99.0)),
                   ('nativeStartClock', native_clock(100.1)),
                   ('readinessClock', native_clock(103.4)),
                   ('elapsedSeconds', 999.0)]
        for field, value in changes:
            with self.subTest(field=field):
                f = Fixture()
                f.edit('target-completion.json', lambda d: d.__setitem__(field, value))
                self.rejected(f, r'clock|elapsed|read|start|time|order')

    def test_parent_observer_eof_and_reap_clock_order(self):
        for file, field, value in [('target.json', 'stdinEOFClock', clock(104.2)),
            ('target.json', 'clockAfterCleanup', clock(104.2)),
            ('sample.json', 'clockAtSpawn', clock(103.0)),
            ('target-groups.json', 'clockAtSpawn', clock(104.0)),
            ('sampler-calibration.json', 'pidLeaseClock', clock(103.5))]:
            with self.subTest(file=file, field=field):
                f = Fixture()
                f.edit(file, lambda d: d.__setitem__(field, value))
                self.rejected(f, r'clock|lease|order|spawn|eof|time|completion')

    def test_clock_durations_and_spawn_anchors_cannot_contradict_recorded_clocks(self):
        f = Fixture()
        report = f.get('sampler-calibration.json')
        report.update(targetMonotonicStart=99.0, triggerMonotonic=102.0)
        f.put('sampler-calibration.json', report)
        f.bind()
        self.rejected(f, r'clock|spawn|anchor|order|window')
        f = Fixture()
        command = f.get('sample.json')
        command.update(elapsedSeconds=0.001, exitObservedAfterSeconds=0.0005)
        f.put('sample.json', command)
        f.bind()
        self.rejected(f, r'clock|elapsed|duration|time')

    def test_json_overflow_and_contradictory_macho_segment_are_rejected(self):
        for number in ('1e999', '-1e999'):
            with self.subTest(number=number):
                with self.assertRaises(review.EvidenceError):
                    review.json_bytes(('{"value":' + number + '}').encode(), 'synthetic JSON')
        f = Fixture()
        raw = bytearray(f.files[BINARY])
        # Add an enclosing __OTHER segment whose section falsely claims __TEXT.
        # The frame points at that second section, while the legitimate header
        # remains in section 1. Old name-only checks could accept this mismatch.
        second = bytearray(raw[56:208])
        second[8:24] = b'__OTHER' + b'\0' * 9
        commands = raw[32:208] + second + raw[208:232]
        raw[32:32 + len(commands)] = commands
        struct.pack_into('<II', raw, 16, 4, len(commands))
        raw[0x915] = 2
        f.files[BINARY] = bytes(raw)
        f.bind(binary=True)
        self.rejected(f, r'segment|section')

    def test_pid_lease_normal_eof_and_group_cleanup_are_required(self):
        for file, field, value in [('sampler-calibration.json', 'pidLeaseAcquired', False),
            ('target.json', 'pidLeaseReleased', False),
            ('target.json', 'stdinEOFDelivered', False),
            ('target.json', 'stdinClosed', False),
            ('target.json', 'stdinBytesSent', 1),
            ('target.json', 'forcedCleanupUsed', True),
            ('target-completion.json', 'reason', 'safety-timeout'),
            ('target-completion.json', 'cooperativeEOFObserved', False),
            ('target-completion.json', 'finalIdentityMatches', False),
            ('sample.json', 'signals', [{'signal': 15}]),
            ('sample.json', 'inheritedStreamsStillOpen', True),
            ('sample.json', 'stopReason', 'timeout')]:
            with self.subTest(file=file, field=field):
                f = Fixture()
                f.edit(file, lambda d: d.__setitem__(field, value))
                self.rejected(f)
        for name, line in [('observer-groups', '1241 1241 S\n'),
                           ('target-groups', '1234 1234 S\n')]:
            with self.subTest(live_group=name):
                f = Fixture()
                f.files[name + '.stdout.txt'] += line.encode()
                f.bind()
                self.rejected(f, r'group|live|member')

    def test_before_ps_snapshot_binds_pid_parent_group_uid_and_liveness(self):
        for old, new in [('1234 1200 1234 501', '9999 1200 1234 501'),
                         ('1234 1200 1234 501', '1234 9999 1234 501'),
                         ('1234 1200 1234 501', '1234 1200 9999 501'),
                         ('1234 1200 1234 501', '1234 1200 1234 999'),
                         (' S<s ', ' Z ' )]:
            with self.subTest(new=new):
                f = Fixture()
                f.files['identity-before.stdout.txt'] = f.files['identity-before.stdout.txt'].replace(old.encode(), new.encode())
                f.bind()
                self.rejected(f, r'identity|pid|ps|state|snapshot|live')

    def test_hashes_sources_and_input_inventory_are_independently_bound(self):
        f = Fixture()
        f.files['sources/NativeSamplerCalibration.c'] += b'changed\n'
        f.bind()
        self.rejected(f, r'source|hash|identity')
        f = Fixture()
        f.edit('target-completion.json', lambda d: d.__setitem__('readyReceiptSHA256', '0' * 64), ready=False)
        self.rejected(f, r'ready|hash|identity|receipt')
        f = Fixture()
        f.edit('inputs-after.json', lambda d: d[BINARY].__setitem__('sha256', '0' * 64), inputs=False)
        self.rejected(f, r'input|hash|unchanged')
        f = Fixture()
        f.edit('build-provenance.json', lambda d: d.__setitem__('experimentTree', 'f' * 40))
        self.rejected(f, r'tree|provenance|source|commit|identity')

    def test_command_stream_hash_cannot_be_rebound_by_aggregate_only(self):
        f = Fixture()
        sample = f.get('sample.json')
        sample['files']['stderr']['sha256'] = '0' * 64
        f.put('sample.json', sample)
        report = f.get('sampler-calibration.json')
        report['commands']['sample'] = sample
        f.put('sampler-calibration.json', report)
        f.rebind_members()
        self.rejected(f, r'stream|hash|identity|stderr')

    def test_manifest_rejects_byte_changes_missing_and_extra_files(self):
        for case in ('byte-change', 'missing', 'extra'):
            with self.subTest(case=case):
                f = Fixture()
                if case == 'byte-change':
                    f.files['controlled-sample.txt'] += b'changed'
                elif case == 'missing':
                    del f.files['target-ready.json']
                else:
                    f.files['unretained.txt'] = b'extra'
                with self.assertRaises(review.EvidenceError):
                    review.validate_evidence(f.files, f.architecture, f.trust)

    def test_duplicate_json_keys_nonfinite_values_are_rejected(self):
        for old, new in [(b'"pid": 1234', b'"pid": 1234, "pid": 1234'),
                         (b'"elapsedSeconds": 4.35800001', b'"elapsedSeconds": NaN')]:
            with self.subTest(new=new):
                f = Fixture()
                name = 'target-ready.json' if b'pid' in old else 'target-completion.json'
                self.assertIn(old, f.files[name])
                f.files[name] = f.files[name].replace(old, new)
                # Preserve raw invalid JSON and update only aggregate byte bindings.
                report = f.get('sampler-calibration.json')
                key = 'readyReceipt' if name == 'target-ready.json' else 'completionReceipt'
                report[key] = {'name': name, **identity(f.files[name])}
                f.put('sampler-calibration.json', report)
                f.rebind_members()
                self.rejected(f, r'duplicate|json|finite|nan')

    def test_original_incomplete_decision_and_missing_after_ps_cannot_be_promoted(self):
        for field, value in [('controlledSamplerCalibrationComplete', True),
                             ('status', 'controlled-sampler-qualified'),
                             ('errors', []), ('afterIdentity', {'pid': 1234}),
                             ('sampleQualification', {'qualified': True}),
                             ('releaseReady', True), ('C12', 'PASS')]:
            with self.subTest(field=field):
                f = Fixture()
                f.edit('sampler-calibration.json', lambda d: d.__setitem__(field, value))
                self.rejected(f)
        f = Fixture()
        f.files['identity-after.json'] = b'{}\n'
        f.rebind_members()
        self.rejected(f, r'after|original|missing|absent')


class ArchiveBoundaryTests(unittest.TestCase):
    @staticmethod
    def archive(entries):
        output = io.BytesIO()
        with warnings.catch_warnings():
            warnings.simplefilter('ignore', UserWarning)
            with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_STORED) as archive:
                for name, data in entries:
                    archive.writestr(name, data)
        return output.getvalue()

    def test_archive_reader_returns_bytes_without_extracting(self):
        data = self.archive([('nested/report.txt', b'report'), ('second.json', b'{}')])
        self.assertEqual(review.read_zip_bytes(data), {'nested/report.txt': b'report', 'second.json': b'{}'})

    def test_archive_duplicate_and_unsafe_names_are_rejected(self):
        for name in ('.', '../escape', '/absolute', 'one/../../escape', r'one\escape', 'one/./two', 'one//two'):
            with self.subTest(name=name):
                with self.assertRaises(review.EvidenceError):
                    review.read_zip_bytes(self.archive([(name, b'bad')]))
        with self.assertRaises(review.EvidenceError):
            review.read_zip_bytes(self.archive([('duplicate', b'one'), ('duplicate', b'two')]))

    def test_archive_symlink_crc_and_oversized_declared_member_are_rejected(self):
        entry = zipfile.ZipInfo('link')
        entry.create_system = 3
        entry.external_attr = (stat.S_IFLNK | 0o777) << 16
        with self.assertRaises(review.EvidenceError):
            review.read_zip_bytes(self.archive([(entry, b'/target')]))
        data = bytearray(self.archive([('report', b'unique-payload')]))
        data[data.index(b'unique-payload')] ^= 1
        with self.assertRaises(review.EvidenceError):
            review.read_zip_bytes(bytes(data))
        data = bytearray(self.archive([('report', b'data')]))
        central = data.index(b'PK\x01\x02')
        struct.pack_into('<I', data, central + 24, 0x7FFFFFFF)
        with self.assertRaises(review.EvidenceError):
            review.read_zip_bytes(bytes(data))

    def test_archive_hidden_nul_and_file_directory_collision_are_rejected(self):
        data = self.archive([('badX', b'data')]).replace(b'badX', b'bad\0')
        with self.assertRaises(review.EvidenceError):
            review.read_zip_bytes(data)
        with self.assertRaises(review.EvidenceError):
            review.read_zip_bytes(self.archive([('parent', b'file'), ('parent/child', b'child')]))

    def test_public_wrapper_never_accepts_synthetic_archive_as_original(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'synthetic.zip'
            data = self.archive(list(Fixture().files.items()))
            path.write_bytes(data)
            with self.assertRaises(review.EvidenceError):
                review.verify_archive(path, 'arm64')
            self.assertEqual(path.read_bytes(), data)
            with self.assertRaises(review.EvidenceError):
                review.verify_archive(path, 'foreign-architecture')

    def test_cli_has_no_hash_bypass_and_does_not_write_success_on_invalid_input(self):
        script = str(Path(review.__file__).resolve())
        with tempfile.TemporaryDirectory() as folder:
            archive = Path(folder) / 'synthetic.zip'
            archive.write_bytes(self.archive([('report', b'synthetic')]))
            output = Path(folder) / 'result.json'
            command = [sys.executable, script, '--arm64', str(archive), '--x86-64', str(archive),
                       '--output', str(output)]
            result = subprocess.run(command, capture_output=True, text=True, timeout=10)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(output.exists())
            bypass = subprocess.run(command + ['--skip-hash'], capture_output=True, text=True, timeout=10)
            self.assertEqual(bypass.returncode, 2)
            self.assertIn('unrecognized arguments', bypass.stderr)


if __name__ == '__main__':
    unittest.main()
