#!/usr/bin/env python3
"""Strip staged GUI/CLI copies and retain verified debug symbols separately."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import platform
import re
import shutil
import stat
import tempfile

from measure_binary_symbols import (ARCHITECTURES, command, digest, inspect_macho,
                                    retain_dsym, signature, verify_preservation)

ROOT = Path(__file__).resolve().parent.parent
PRODUCTS = ('LemulipApp', 'lemulip')
STRIP_FLAGS = ['-S', '-x']


def source_identity(root: Path) -> dict:
    # Public Source ZIPs intentionally contain no Git history or invented commit.
    if not (root / '.git').exists():
        return {'commit': None, 'sourceKind': 'exported-source', 'worktreeClean': None}
    commit = command(['git', '-C', root, 'rev-parse', 'HEAD']).stdout.strip()
    if not re.fullmatch(r'[0-9a-f]{40,64}', commit):
        raise ValueError('Invalid source commit')
    status = command(['git', '-C', root, 'status', '--porcelain', '--untracked-files=normal']).stdout
    return {'commit': commit, 'sourceKind': 'git', 'worktreeClean': not status.strip()}


def unchanged_original(product: dict, root: Path) -> None:
    source = root / product['originalSource']
    current = source.stat()
    if (digest(source.read_bytes()) != product['originalSHA256']
            or stat.S_IMODE(current.st_mode) != product['originalMode']
            or current.st_mtime_ns != product['originalMtimeNS']):
        raise ValueError('Original build product changed: ' + product['originalSource'])


def prepare(builds: dict[str, Path], staging: Path, symbols: Path, root: Path = ROOT) -> dict:
    """Create fresh thin copies; callers publish them only after verify_signed."""
    if not builds or not set(builds) <= set(ARCHITECTURES.values()):
        raise ValueError('Expected arm64 and/or x86_64 build directories')
    if staging.exists() or symbols.exists() or staging.is_symlink() or symbols.is_symlink():
        raise ValueError('Staging and debug-symbol outputs must be new')
    if (staging.resolve() == symbols.resolve() or staging.resolve() in symbols.resolve().parents
            or symbols.resolve() in staging.resolve().parents):
        raise ValueError('Staging and debug-symbol outputs must be separate')
    root = root.resolve()
    originals = []
    for architecture, directory in sorted(builds.items()):
        for name in PRODUCTS:
            source = (directory / name).resolve(strict=True)
            data = source.read_bytes()
            original = inspect_macho(data)
            if original['architecture'] != architecture or original['fileType'] != 2:
                raise ValueError('Expected a thin executable for ' + architecture)
            information = source.stat()
            originals.append({'architecture': architecture, 'product': name,
                'originalSource': source.relative_to(root).as_posix(),
                'originalSHA256': digest(data), 'original': original,
                'originalMode': stat.S_IMODE(information.st_mode),
                'originalMtimeNS': information.st_mtime_ns})

    report = {'schema': 1, **source_identity(root), 'stripFlags': STRIP_FLAGS,
              'architectures': sorted(builds), 'products': originals, 'result': 'STAGED'}
    staging.mkdir(parents=True)
    try:
        symbols.mkdir(parents=True)
        for product in originals:
            source = root / product['originalSource']
            architecture, name = product['architecture'], product['product']
            dsym = symbols / 'dSYMs' / architecture / (name + '.dSYM')
            product.update(retain_dsym(source, dsym, product['original']))
            product['dSYM'] = dsym.relative_to(symbols).as_posix()
            target = staging / architecture / name
            target.parent.mkdir(exist_ok=True)
            shutil.copy2(source, target)
            command(['/usr/bin/strip', *STRIP_FLAGS, target])
            data = target.read_bytes()
            product['staged'] = inspect_macho(data)
            product['stagedSHA256'] = digest(data)
            verify_preservation(product['original'], product['staged'])
            if product['staged']['symbols']['local'] != 0:
                raise ValueError('Staged executable still contains local symbols')
            unchanged_original(product, root)
        (symbols / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    except Exception:
        shutil.rmtree(staging)
        if symbols.exists():
            shutil.rmtree(symbols)
        raise
    return report


def verify_signed(symbols: Path, gui: Path, cli: Path, root: Path = ROOT) -> dict:
    """Verify final signed native/fat products against every original thin build."""
    report_path = symbols / 'report.json'
    report = json.loads(report_path.read_text())
    expected_arches = report['architectures']
    expected = {(arch, name) for arch in expected_arches for name in PRODUCTS}
    actual = [(p['architecture'], p['product']) for p in report['products']]
    if (report['schema'] != 1 or report['stripFlags'] != STRIP_FLAGS
            or not expected_arches or not set(expected_arches) <= set(ARCHITECTURES.values())
            or set(actual) != expected or len(actual) != len(expected)):
        raise ValueError('Incomplete symbol-preparation report')
    # A failed recheck must not leave a stale PASS receipt beside changed files.
    report['result'] = 'VERIFYING'
    report['finalProducts'] = {}
    report_path.write_text(json.dumps(report, indent=2) + '\n')
    for name, final in [('LemulipApp', gui), ('lemulip', cli)]:
        arches = command(['/usr/bin/lipo', '-archs', final]).stdout.split()
        if sorted(arches) != expected_arches:
            raise ValueError('Final executable has unexpected architectures')
        signed = signature(final)
        if not signed['valid']:
            raise ValueError('Final executable has an invalid signature')
        final_data = final.read_bytes()
        final_record = {'SHA256': digest(final_data), 'bytes': len(final_data),
                        'signature': signed, 'slices': {}}
        for product in (p for p in report['products'] if p['product'] == name):
            architecture = product['architecture']
            unchanged_original(product, root)
            dsym = symbols / product['dSYM']
            files = {p.relative_to(dsym).as_posix(): digest(p.read_bytes())
                     for p in dsym.rglob('*') if p.is_file() and not p.is_symlink()}
            if files != product['dSYMFiles'] or any(p.is_symlink() for p in dsym.rglob('*')):
                raise ValueError('Retained debug symbols changed')
            if final_data[:4] == b'\xcf\xfa\xed\xfe':
                measured = inspect_macho(final_data)
            else:
                with tempfile.TemporaryDirectory(prefix='lemulip-symbol-slice-') as temporary:
                    thin = Path(temporary) / name
                    command(['/usr/bin/lipo', final, '-thin', architecture, '-output', thin])
                    measured = inspect_macho(thin.read_bytes())
            verify_preservation(product['original'], measured)
            if measured['symbols'] != product['staged']['symbols']:
                raise ValueError('Final executable changed the staged symbol set')
            final_record['slices'][architecture] = measured
        report['finalProducts'][name] = final_record
    report['result'] = 'PASS'
    report_path.write_text(json.dumps(report, indent=2) + '\n')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='operation', required=True)
    stage = commands.add_parser('prepare')
    stage.add_argument('--build', action='append', required=True, metavar='ARCH=DIRECTORY')
    stage.add_argument('--staging', type=Path, required=True)
    stage.add_argument('--symbols', type=Path, required=True)
    verify = commands.add_parser('verify')
    verify.add_argument('--symbols', type=Path, required=True)
    verify.add_argument('--gui', type=Path, required=True)
    verify.add_argument('--cli', type=Path, required=True)
    args = parser.parse_args()
    if platform.system() != 'Darwin':
        parser.error('Release symbol preparation requires macOS')
    if args.operation == 'prepare':
        builds = {}
        for value in args.build:
            architecture, separator, directory = value.partition('=')
            if not separator or not directory or architecture in builds:
                parser.error('Each architecture requires one build directory')
            builds[architecture] = Path(directory)
        report = prepare(builds, args.staging, args.symbols)
    else:
        report = verify_signed(args.symbols, args.gui, args.cli)
    print('GUI/CLI symbol preparation: ' + report['result'])


if __name__ == '__main__':
    main()
