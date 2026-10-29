#!/usr/bin/env python3
"""Measure Apple strip on temporary release GUI/CLI copies, never release files.

Mach-O layouts and strip semantics follow Apple's cctools headers and manual:
https://github.com/apple-oss-distributions/cctools/tree/main/include/mach-o
https://github.com/apple-oss-distributions/cctools/blob/main/man/strip.1
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import platform
import re
import shutil
import struct
import subprocess
import tempfile
import uuid

ARCHITECTURES = {0x01000007: 'x86_64', 0x0100000C: 'arm64'}
VARIANTS = {'baseline': [], 'debug': ['-S'], 'debug-and-local': ['-S', '-x']}
INVARIANTS = ('architecture', 'fileType', 'uuid', 'runtimeSectionsSHA256',
              'dependenciesSHA256', 'dyldPayloadsSHA256', 'importsSHA256', 'exportsSHA256')


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def record_digest(value) -> str:
    return digest(json.dumps(value, sort_keys=True, separators=(',', ':')).encode())


def inspect_macho(data: bytes) -> dict:
    """Describe one native 64-bit Mach-O without relying on mutable file offsets."""
    if len(data) < 32 or data[:4] != b'\xcf\xfa\xed\xfe':
        raise ValueError('Expected a native little-endian 64-bit Mach-O')
    _, cpu, _, filetype, count, command_bytes, _, _ = struct.unpack_from('<8I', data)
    if cpu not in ARCHITECTURES or 32 + command_bytes > len(data):
        raise ValueError('Unsupported architecture or truncated load commands')

    def read(offset, size):
        if offset < 0 or size < 0 or offset + size > len(data):
            raise ValueError('Mach-O payload extends past the file')
        return data[offset:offset + size]

    def name(value):
        return value.split(b'\0', 1)[0].decode('utf-8', 'surrogateescape')

    sections, dependencies, dyld = [], [], []
    debug_sections, symtab, image_uuid = 0, None, None
    position = 32
    for _ in range(count):
        command, size = struct.unpack('<II', read(position, 8))
        if size < 8 or position + size > 32 + command_bytes:
            raise ValueError('Invalid Mach-O load command size')
        body = read(position, size)
        if command == 0x19:  # LC_SEGMENT_64
            if size < 72:
                raise ValueError('Truncated segment command')
            segment = struct.unpack_from('<II16sQQQQiiII', body)
            if size != 72 + 80 * segment[9]:
                raise ValueError('Invalid section count')
            for index in range(segment[9]):
                section = struct.unpack_from('<16s16sQQIIIIIIII', body, 72 + 80 * index)
                sectname, segname = name(section[0]), name(section[1])
                address, length, offset, flags = section[2], section[3], section[4], section[8]
                if segname == '__DWARF' or flags & 0x02000000:  # S_ATTR_DEBUG
                    debug_sections += length
                    continue
                # dSYM files describe original virtual sections without storing
                # their runtime bytes; only their DWARF and UUID are inspected.
                if filetype == 0xA:
                    continue
                # Zero-fill sections describe memory, not bytes at file offset 0.
                zero_fill = (flags & 0xFF) in {0x1, 0xC, 0x12}
                payload = None if zero_fill else digest(read(offset, length))
                sections.append((segname, sectname, address, length, flags, payload))
        elif command == 0x1B:  # LC_UUID
            if size != 24 or image_uuid is not None:
                raise ValueError('Invalid or duplicate LC_UUID')
            image_uuid = str(uuid.UUID(bytes=body[8:24])).upper()
        elif command == 0x2:  # LC_SYMTAB
            if size != 24 or symtab is not None:
                raise ValueError('Invalid or duplicate LC_SYMTAB')
            symtab = struct.unpack_from('<4I', body, 8)
        elif command in {0xC, 0x18 | 0x80000000, 0x1F | 0x80000000,
                         0x23 | 0x80000000, 0x1C | 0x80000000, 0x32, 0x28 | 0x80000000}:
            # Dependencies/rpaths, target OS and entry point must not change.
            dependencies.append((command, body.hex()))
        elif command in {0x33 | 0x80000000, 0x34 | 0x80000000, 0x26, 0x29}:
            # Export trie, chained fixups, function starts and data-in-code.
            if size != 16:
                raise ValueError('Invalid linkedit data command')
            offset, length = struct.unpack_from('<II', body, 8)
            dyld.append((command, digest(read(offset, length))))
        elif command in {0x22, 0x22 | 0x80000000}:  # LC_DYLD_INFO[_ONLY]
            if size != 48:
                raise ValueError('Invalid dyld info command')
            for part in range(5):
                offset, length = struct.unpack_from('<II', body, 8 + 8 * part)
                dyld.append((command, part, digest(read(offset, length))))
        position += size
    if position != 32 + command_bytes or image_uuid is None:
        raise ValueError('Invalid command extent or missing UUID')

    imports, exports = [], []
    counts = {'debug': 0, 'local': 0, 'imports': 0, 'exports': 0}
    symbol_bytes = string_bytes = 0
    if symtab:
        offset, number, string_offset, string_bytes = symtab
        symbols, strings = read(offset, 16 * number), read(string_offset, string_bytes)
        symbol_bytes = len(symbols)

        def symbol_name(index):
            end = strings.find(b'\0', index)
            if index >= len(strings) or end < 0:
                raise ValueError('Invalid symbol string index')
            return strings[index:end].decode('utf-8', 'surrogateescape')

        for index in range(number):
            string_index, kind, section, description, value = struct.unpack_from('<IBBHQ', symbols, 16 * index)
            if kind & 0xE0:  # N_STAB
                counts['debug'] += 1
            elif not kind & 1:  # N_EXT
                counts['local'] += 1
            else:
                # N_INDR stores a string-table index, not a runtime address.
                logical_value = symbol_name(value) if (kind & 0x0E) == 0x0A else value
                record = (symbol_name(string_index), kind, section, description, logical_value)
                target = imports if (kind & 0x0E) == 0 else exports
                target.append(record)
        counts['imports'], counts['exports'] = len(imports), len(exports)
    return {'architecture': ARCHITECTURES[cpu], 'fileType': filetype, 'uuid': image_uuid,
            'bytes': len(data), 'debugSectionBytes': debug_sections,
            'runtimeSectionCount': len(sections), 'runtimeSectionsSHA256': record_digest(sorted(sections)),
            'dependenciesSHA256': record_digest(dependencies), 'dyldPayloadsSHA256': record_digest(dyld),
            'importsSHA256': record_digest(sorted(imports)), 'exportsSHA256': record_digest(sorted(exports)),
            'symbols': counts, 'symbolTableBytes': symbol_bytes, 'stringTableBytes': string_bytes}


def verify_preservation(original: dict, modified: dict) -> None:
    for key in INVARIANTS:
        if original[key] != modified[key]:
            raise ValueError('Modified binary changed ' + key)


def command(arguments, *, required=True):
    result = subprocess.run([str(x) for x in arguments], capture_output=True, text=True)
    if required and result.returncode:
        raise RuntimeError('Command failed: ' + ' '.join(str(x) for x in arguments)
                           + '\n' + (result.stdout + result.stderr)[-8000:])
    return result


def signature(path):
    result = command(['/usr/bin/codesign', '--verify', '--all-architectures', '--strict', path], required=False)
    return {'valid': result.returncode == 0, 'exitCode': result.returncode,
            'diagnostic': (result.stdout + result.stderr).strip()[-1000:]}


def retain_dsym(source: Path, dsym: Path, original: dict) -> dict:
    """Keep complete matching debug information before stripping a copy."""
    if dsym.exists():
        raise ValueError('Debug-symbol output already exists')
    dsym.parent.mkdir(parents=True, exist_ok=True)
    dsym_result = command(['/usr/bin/xcrun', '--sdk', 'macosx', 'dsymutil', source, '-o', dsym])
    diagnostic = (dsym_result.stdout + dsym_result.stderr).strip()
    # A missing object can produce a matching but incomplete dSYM with exit 0.
    if re.search(r'\b(?:warning|error):', diagnostic, re.IGNORECASE):
        raise ValueError('Debug-symbol generation reported a diagnostic: ' + diagnostic[-2000:])
    dwarf_files = list((dsym / 'Contents/Resources/DWARF').iterdir())
    if len(dwarf_files) != 1:
        raise ValueError('Expected one native DWARF file')
    dwarf = inspect_macho(dwarf_files[0].read_bytes())
    if (dwarf['uuid'] != original['uuid'] or dwarf['architecture'] != original['architecture']
            or dwarf['fileType'] != 0xA or dwarf['debugSectionBytes'] == 0):
        raise ValueError('Missing DWARF content or mismatched dSYM')
    command(['/usr/bin/xcrun', '--sdk', 'macosx', 'dwarfdump', '--verify', dsym])
    files = {}
    for path in sorted(dsym.rglob('*')):
        if path.is_symlink():
            raise ValueError('Unexpected symlink in debug-symbol output')
        if path.is_file():
            files[path.relative_to(dsym).as_posix()] = digest(path.read_bytes())
    return {'dSYMUUID': dwarf['uuid'], 'dSYMDWARFBytes': dwarf['debugSectionBytes'],
            'dSYMDiagnostic': diagnostic[-2000:], 'dSYMFiles': files}


def measure_binary(source: Path, label: str, output: Path, architecture: str) -> dict:
    original_bytes = source.read_bytes()
    original = inspect_macho(original_bytes)
    if original['architecture'] != architecture or original['fileType'] != 2:
        raise ValueError('Expected a native MH_EXECUTE for ' + architecture)
    dsym = output / 'dSYMs' / (label + '.dSYM')
    debug = retain_dsym(source, dsym, original)
    report = {'product': label, 'originalSHA256': digest(original_bytes), 'original': original,
              'originalSignature': signature(source), 'dSYM': str(dsym.relative_to(output)),
              **debug, 'variants': {}}
    with tempfile.TemporaryDirectory(prefix='symbol-measure-') as temporary:
        for variant, flags in VARIANTS.items():
            target = Path(temporary) / variant / source.name
            target.parent.mkdir()
            shutil.copy2(source, target)
            if flags:
                command(['/usr/bin/strip', *flags, target])
            before_signing = signature(target)
            command(['/usr/bin/codesign', '--force', '--sign', '-', target])
            signed = signature(target)
            if not signed['valid']:
                raise ValueError('Temporary binary failed signature verification: ' + variant)
            data = target.read_bytes()
            measured = inspect_macho(data)
            verify_preservation(original, measured)
            report['variants'][variant] = {'stripFlags': flags, 'SHA256': digest(data),
                'signatureBeforeSigning': before_signing, 'signatureAfterSigning': signed,
                'runtimePreserved': True, 'measurement': measured}
    if source.read_bytes() != original_bytes:
        raise ValueError('Original build product changed during measurement')
    baseline = report['variants']['baseline']['measurement']['bytes']
    for variant in report['variants'].values():
        variant['bytesSavedFromSignedBaseline'] = baseline - variant['measurement']['bytes']
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--gui', required=True, type=Path)
    parser.add_argument('--cli', required=True, type=Path)
    parser.add_argument('--architecture', required=True, choices=ARCHITECTURES.values())
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    if platform.system() != 'Darwin' or platform.machine() != args.architecture:
        parser.error('Run on the requested native macOS architecture')
    if args.output.exists():
        parser.error('Output directory must not already exist')
    args.output.mkdir(parents=True)
    report = {'schema': 1, 'commit': command(['git', 'rev-parse', 'HEAD']).stdout.strip(),
              'architecture': args.architecture, 'scope': 'native GUI and CLI copies only',
              'toolchain': command(['/usr/bin/xcrun', '--sdk', 'macosx', 'swift', '--version']).stdout.strip(),
              'macOS': platform.mac_ver()[0],
              'packagedArchivesMeasured': False, 'productionFilesModified': False, 'products': []}
    try:
        for label, source in [('LemulipApp', args.gui), ('lemulip', args.cli)]:
            report['products'].append(measure_binary(source.resolve(strict=True), label, args.output, args.architecture))
        report['result'] = 'PASS'
    except Exception as error:
        report['result'] = 'FAIL'
        report['error'] = str(error)
        raise
    finally:
        (args.output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
        lines = ['# Native binary symbol measurement', '', 'Result: ' + report.get('result', 'FAIL'),
                 'Commit: ' + report['commit'], 'Architecture: ' + args.architecture, '',
                 'Production files and bundled engines are unchanged. ZIP/DMG sizes were not measured.', '',
                 '| Product | Signed baseline | `-S` | `-S -x` |', '|---|---:|---:|---:|']
        for product in report['products']:
            sizes = [str(product['variants'][v]['measurement']['bytes']) for v in VARIANTS]
            lines.append('| ' + product['product'] + ' | ' + ' | '.join(sizes) + ' |')
        if report.get('error'):
            lines += ['', 'Failure: ' + report['error']]
        (args.output / 'report.md').write_text('\n'.join(lines) + '\n')


if __name__ == '__main__':
    main()
