#!/usr/bin/env python3
"""Check that the native experiment rejects runtime changes, not symbol removal."""
import struct
import unittest

import measure_binary_symbols as m


def fixture(*, symbols=None, code=b'\x01\x02\x03\x04', cpu=0x0100000C,
            image_uuid=b'0123456789abcdef', library=b'/usr/lib/libSystem.B.dylib',
            dyld=b'\0\0', filetype=2, virtual_text_size=None):
    if symbols is None:
        symbols = [('_debug', 0x64, 0), ('_local', 0x0E, 0x100000200),
                   ('_export', 0x0F, 0x100000200), ('_import', 0x01, 0)]
    strings = bytearray(b'\0')
    records = bytearray()
    for name, kind, value in symbols:
        string_index = len(strings)
        strings.extend(name.encode() + b'\0')
        records.extend(struct.pack('<IBBHQ', string_index, kind, 1 if kind & 0x0E else 0, 0, value))
    symoff = 520
    stroff = symoff + len(records)
    dyldoff = stroff + len(strings)
    segment = struct.pack('<II16sQQQQiiII', 0x19, 232, b'__TEXT', 0x100000000,
                          4096, 0, 516, 7, 5, 2, 0)
    segment += struct.pack('<16s16sQQIIIIIIII', b'__text', b'__TEXT', 0x100000200,
                           len(code) if virtual_text_size is None else virtual_text_size,
                           512 if virtual_text_size is None else 0, 2, 0, 0, 0x80000400, 0, 0, 0)
    segment += struct.pack('<16s16sQQIIIIIIII', b'__bss', b'__DATA', 0x100001000,
                           8192, 0, 2, 0, 0, 1, 0, 0, 0)
    library_size = (24 + len(library) + 1 + 7) // 8 * 8
    dependency = struct.pack('<6I', 0xC, library_size, 24, 0, 0, 0) + library + b'\0'
    dependency += b'\0' * (library_size - len(dependency))
    commands = (segment + struct.pack('<II16s', 0x1B, 24, image_uuid)
                + struct.pack('<6I', 2, 24, symoff, len(symbols), stroff, len(strings))
                + dependency + struct.pack('<4I', 0x80000033, 16, dyldoff, len(dyld)))
    header = struct.pack('<8I', 0xFEEDFACF, cpu, 0, filetype, 5, len(commands), 0, 0)
    data = bytearray(header + commands)
    assert len(data) <= 512
    data += b'\0' * (512 - len(data)) + code
    data += b'\0' * (symoff - len(data)) + records + strings + dyld
    return bytes(data)


class SymbolMeasurementTests(unittest.TestCase):
    def test_local_and_debug_removal_preserves_runtime_and_linkage(self):
        original = m.inspect_macho(fixture())
        reduced = m.inspect_macho(fixture(symbols=[('_export', 0x0F, 0x100000200), ('_import', 0x01, 0)]))
        m.verify_preservation(original, reduced)
        self.assertLess(reduced['bytes'], original['bytes'])
        self.assertEqual(original['symbols'], {'debug': 1, 'local': 1, 'imports': 1, 'exports': 1})
        self.assertEqual(reduced['symbols']['debug'], 0)
        self.assertEqual(reduced['symbols']['local'], 0)
        self.assertEqual(original['runtimeSectionCount'], 2)

    def test_runtime_code_change_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'runtimeSectionsSHA256'):
            m.verify_preservation(m.inspect_macho(fixture()), m.inspect_macho(fixture(code=b'\0\2\3\4')))

    def test_changed_import_is_rejected(self):
        changed = fixture(symbols=[('_export', 0x0F, 0x100000200), ('_different_import', 1, 0)])
        with self.assertRaisesRegex(ValueError, 'importsSHA256'):
            m.verify_preservation(m.inspect_macho(fixture()), m.inspect_macho(changed))

    def test_changed_export_address_is_rejected(self):
        changed = fixture(symbols=[('_export', 0x0F, 0x100000204), ('_import', 1, 0)])
        with self.assertRaisesRegex(ValueError, 'exportsSHA256'):
            m.verify_preservation(m.inspect_macho(fixture()), m.inspect_macho(changed))

    def test_changed_architecture_uuid_and_dependencies_are_rejected(self):
        for kwargs, key in [({'cpu': 0x01000007}, 'architecture'),
                            ({'image_uuid': b'fedcba9876543210'}, 'uuid'),
                            ({'library': b'/usr/lib/different.dylib'}, 'dependenciesSHA256'),
                            ({'dyld': b'\1\0'}, 'dyldPayloadsSHA256')]:
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, key):
                m.verify_preservation(m.inspect_macho(fixture()), m.inspect_macho(fixture(**kwargs)))

    def test_zero_fill_is_not_read_as_file_bytes(self):
        # The 8 KiB zero-fill section is larger than the entire fixture file.
        self.assertEqual(m.inspect_macho(fixture())['runtimeSectionCount'], 2)

    def test_dsym_virtual_runtime_sections_do_not_require_stored_code(self):
        info = m.inspect_macho(fixture(filetype=0xA, virtual_text_size=5_000_000))
        self.assertEqual(info['fileType'], 0xA)
        self.assertEqual(info['runtimeSectionCount'], 0)

    def test_truncated_symbol_payload_and_invalid_headers_are_rejected(self):
        for data in [b'not macho', fixture()[:28], fixture()[:-10]]:
            with self.subTest(size=len(data)), self.assertRaises(ValueError):
                m.inspect_macho(data)


if __name__ == '__main__':
    unittest.main()
