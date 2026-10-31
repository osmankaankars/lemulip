#!/usr/bin/env python3
"""Package and verify an unreleased UI review copy; never publish a release."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import plistlib
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import zipfile

from prepare_binary_symbols import source_identity, verify_signed

ROOT = Path(__file__).resolve().parent.parent
FOLDER = 'Lemulip-UI-Review'
ARCHIVE = FOLDER + '.zip'
APP = 'Lemulip UI Review.app'
ARCHES = ['arm64', 'x86_64']
OVERRIDES = {'CFBundleIdentifier': 'app.freewheel.Freewheel.UIReview',
             'CFBundleName': 'Lemulip Review', 'CFBundleDisplayName': 'Lemulip UI Review'}
STATUS = 'UNRELEASED UI REVIEW'


def run(*arguments, env=None):
    try:
        result = subprocess.run([str(a) for a in arguments], check=True, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, timeout=180)
    except subprocess.CalledProcessError as error:
        print(error.stdout, end='', file=sys.stderr)
        print(error.stderr, end='', file=sys.stderr)
        raise
    return result.stdout.strip()


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def file_hashes(directory: Path) -> dict[str, str]:
    result = {}
    for path in sorted(directory.rglob('*')):
        if path.is_symlink() or not (path.is_file() or path.is_dir()):
            raise ValueError('Review payload must contain only regular files and directories')
        if path.is_file():
            result[path.relative_to(directory).as_posix()] = sha256(path)
    return result


def checked_source(expected: str) -> dict:
    identity = source_identity(ROOT)
    if (not re.fullmatch(r'[0-9a-f]{40}', expected) or identity['commit'] != expected
            or identity['worktreeClean'] is not True):
        raise ValueError('Review packaging requires the exact clean source commit')
    return {**identity, 'tree': run('git', '-C', ROOT, 'rev-parse', 'HEAD^{tree}')}


def review_plist(original: dict) -> tuple[dict, dict]:
    if original.get('CFBundleIdentifier') != 'app.freewheel.Freewheel':
        raise ValueError('Unexpected source application identity')
    if original.get('CFBundleExecutable') != 'Lemulip':
        raise ValueError('Unexpected source executable')
    changed = {key: {'original': original.get(key), 'review': value}
               for key, value in OVERRIDES.items()}
    return {**original, **OVERRIDES}, changed


def verify_bundle(app: Path, cli: Path) -> None:
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if any(info.get(key) != value for key, value in OVERRIDES.items()):
        raise ValueError('Review identity is missing')
    if (app / 'Contents/Helpers').exists() or (app / 'Contents/Resources/EngineSupport').exists():
        raise ValueError('UI review must not bundle third-party engines')
    if list(app.rglob('*.dSYM')):
        raise ValueError('Debug symbols must remain outside the review download')
    for signed, binary in [(app, app / 'Contents/MacOS/Lemulip'), (cli, cli)]:
        run('/usr/bin/codesign', '--verify', '--all-architectures', '--strict', signed)
        if sorted(run('/usr/bin/lipo', '-archs', binary).split()) != ARCHES:
            raise ValueError('Review executables must contain exactly arm64 and x86_64')


def stage(output: Path, expected: str) -> None:
    identity = checked_source(expected)
    original = ROOT / 'dist/Lemulip.app'
    original_hashes = file_hashes(original)
    source_plist = ROOT / 'Resources/Info.plist'
    source_plist_hash = sha256(source_plist)
    info = plistlib.loads((original / 'Contents/Info.plist').read_bytes())
    if info != plistlib.loads(source_plist.read_bytes()):
        raise ValueError('Built application metadata differs from source')
    review_info, changes = review_plist(info)
    if output.exists():
        raise ValueError('Review output directory must be new')
    output.mkdir(parents=True)
    with tempfile.TemporaryDirectory(prefix='ui-review-', dir=ROOT / '.build') as temporary:
        payload = Path(temporary) / FOLDER
        payload.mkdir()
        app = payload / APP
        shutil.copytree(original, app, symlinks=True)
        (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(review_info))
        run('/usr/bin/codesign', '--force', '--sign', '-', '--identifier',
            OVERRIDES['CFBundleIdentifier'], app)
        tools = payload / 'Tools'
        tools.mkdir()
        cli = tools / 'lemulip'
        shutil.copy2(ROOT / 'dist/lemulip', cli)
        verify_bundle(app, cli)
        symbols = ROOT / 'dist/Lemulip-Debug-Symbols'
        report = verify_signed(symbols, app / 'Contents/MacOS/Lemulip', cli, root=ROOT)
        if (report['result'] != 'PASS' or report['commit'] != expected
                or report['worktreeClean'] is not True or report['architectures'] != ARCHES):
            raise ValueError('Missing matching clean-source universal debug-symbol evidence')
        staged_hashes = file_hashes(app)
        permitted_changes = {'Contents/Info.plist', 'Contents/MacOS/Lemulip',
                             'Contents/_CodeSignature/CodeResources'}
        if (staged_hashes.keys() != original_hashes.keys()
                or any(staged_hashes[name] != value and name not in permitted_changes
                       for name, value in original_hashes.items())):
            raise ValueError('Review staging changed more than identity and signing bytes')
        run('/usr/bin/xcrun', '--sdk', 'macosx', 'swift', ROOT / 'script/ui_review_fixtures.swift',
            'make', payload / 'Fixtures')
        shutil.copy2(ROOT / 'docs/UI_REVIEW.md', payload / 'READ-ME-EN-TR.md')
        metadata = {'schema': 1, 'status': STATUS, 'releaseReady': False, 'source': identity,
                    'metadataOverrides': changes, 'sourceInfoPlistSHA256': source_plist_hash,
                    'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'],
                    'architectures': ARCHES, 'bundledEngines': [],
                    'originalSignedGUI_SHA256': original_hashes['Contents/MacOS/Lemulip'],
                    'reviewSignedGUI_SHA256': staged_hashes['Contents/MacOS/Lemulip'],
                    'CLI_SHA256': sha256(cli), 'matchingDebugSymbolsRetainedSeparately': True,
                    'nativeVerification': 'See native-arm64.json and native-x86_64.json beside this ZIP.',
                    'physicalInteractionAndRetinaReview': 'NOT ESTABLISHED BY CI',
                    'toolchain': run('/usr/bin/xcrun', '--sdk', 'macosx', 'swift', '--version')}
        (payload / 'REVIEW-INFO.json').write_text(json.dumps(metadata, indent=2) + '\n')
        hashes = file_hashes(payload)
        (payload / 'SHA256SUMS.txt').write_text(''.join(f'{value}  {name}\n' for name, value in hashes.items()))
        if file_hashes(original) != original_hashes or sha256(source_plist) != source_plist_hash:
            raise ValueError('Original app or source metadata changed')
        checked_source(expected)
        archive = output / ARCHIVE
        run('/usr/bin/ditto', '-c', '-k', '--norsrc', '--noextattr', '--keepParent', payload, archive)
        (output / (ARCHIVE + '.sha256')).write_text(f'{sha256(archive)}  {ARCHIVE}\n')
    print(STATUS + ': staged ' + str(output / ARCHIVE))


def checked_archive(directory: Path) -> str:
    archive = directory / ARCHIVE
    digest = sha256(archive)
    if (directory / (ARCHIVE + '.sha256')).read_text() != f'{digest}  {ARCHIVE}\n':
        raise ValueError('Review ZIP checksum mismatch')
    with zipfile.ZipFile(archive) as zipped:
        names = set()
        for entry in zipped.infolist():
            path = PurePosixPath(entry.filename)
            mode = entry.external_attr >> 16
            if (path.is_absolute() or not path.parts or path.parts[0] != FOLDER
                    or '..' in path.parts or '\\' in entry.filename
                    or any(ord(c) < 32 for c in entry.filename) or entry.filename in names
                    or stat.S_ISLNK(mode)):
                raise ValueError('Unexpected review ZIP entry')
            names.add(entry.filename)
        if not names or zipped.testzip() is not None:
            raise ValueError('Review ZIP is empty or has a CRC failure')
    return digest


def verify_contents(payload: Path) -> dict:
    expected = {}
    for line in (payload / 'SHA256SUMS.txt').read_text().splitlines():
        digest, separator, name = line.partition('  ')
        if not separator or not re.fullmatch(r'[0-9a-f]{64}', digest) or name in expected:
            raise ValueError('Invalid review content checksum record')
        expected[name] = digest
    actual = file_hashes(payload)
    actual.pop('SHA256SUMS.txt')
    if actual != expected:
        raise ValueError('Review content checksum mismatch')
    metadata = json.loads((payload / 'REVIEW-INFO.json').read_text())
    if (metadata['status'] != STATUS or metadata['releaseReady'] is not False
            or metadata['bundledEngines'] != []):
        raise ValueError('Review-only metadata is missing')
    return metadata


def smoke(payload: Path, destination: Path) -> dict:
    cli = payload / 'Tools/lemulip'
    fixtures = payload / 'Fixtures'
    original_hashes = file_hashes(fixtures)
    environment = {**os.environ, 'PATH': '/usr/bin:/bin:/usr/sbin:/sbin'}

    def convert(name, *arguments):
        output = destination / name
        output.mkdir()
        run(cli, *arguments, '--output', output, env=environment)
        files = list(output.iterdir())
        if len(files) != 1 or not files[0].is_file() or files[0].is_symlink():
            raise ValueError('Expected exactly one built-in smoke output')
        return files[0]

    def labels(path):
        return json.loads(run('/usr/bin/xcrun', '--sdk', 'macosx', 'swift',
                              ROOT / 'script/ui_review_fixtures.swift', 'inspect', path))

    merged = convert('merge', 'run', 'pdf.merge', fixtures / 'Merge/03-Notes.pdf',
                     fixtures / 'Merge/01-Cover.pdf', fixtures / 'Merge/02-Report.pdf')
    merged_labels = labels(merged)
    if merged_labels != ['03 - Notes', '01 - Cover', '02.1 - Report', '02.2 - Report']:
        raise ValueError('Built-in PDF merge did not preserve the requested document/page order')
    extracted = convert('extract', 'run', 'pdf.extract', fixtures / 'Organize/Page-Order.pdf', '--pages', '2,4')
    extracted_labels = labels(extracted)
    if extracted_labels != ['PAGE 2', 'PAGE 4']:
        raise ValueError('Built-in PDF extraction produced unexpected pages')
    vtt = convert('subtitle', 'convert', 'vtt', fixtures / 'Subtitle.srt')
    text = vtt.read_text()
    if not text.startswith('WEBVTT\n') or '00:00:00.000 --> 00:00:01.000' not in text or 'UI review subtitle' not in text:
        raise ValueError('Built-in SRT to VTT conversion failed')
    if file_hashes(fixtures) != original_hashes:
        raise ValueError('A smoke operation changed an original fixture')
    return {'PDFMergePageLabels': merged_labels, 'PDFExtractPageLabels': extracted_labels,
            'SRTtoVTT': 'PASS', 'originalsPreserved': True, 'PATH': environment['PATH']}


def verify(directory: Path, expected: str, architecture: str, report_path: Path) -> None:
    report = {'status': STATUS, 'result': 'FAIL', 'commit': expected, 'architecture': architecture}
    try:
        if platform.machine() != architecture or architecture not in ARCHES:
            raise ValueError('Expected a native verification runner for ' + architecture)
        checked_source(expected)
        report['archiveSHA256'] = checked_archive(directory)
        with tempfile.TemporaryDirectory(prefix='lemulip-ui-review-') as temporary:
            working = Path(temporary)
            run('/usr/bin/ditto', '-x', '-k', directory / ARCHIVE, working)
            payload = working / FOLDER
            metadata = verify_contents(payload)
            if metadata['source'] != checked_source(expected):
                raise ValueError('Review archive source identity differs from this verification checkout')
            verify_bundle(payload / APP, payload / 'Tools/lemulip')
            report['signaturesAndUniversalArchitectures'] = 'PASS'
            report['nativeLaunch'] = run(ROOT / 'script/build_and_run.sh', '--verify-bundle', payload / APP)
            report['builtInSmoke'] = smoke(payload, working)
            verify_contents(payload)
            report['packagedFilesPreserved'] = True
        report['result'] = 'PASS'
    except Exception as error:
        report['error'] = str(error)
        raise
    finally:
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(report, indent=2) + '\n')


def evidence(directory: Path, expected: str) -> None:
    digest = checked_archive(directory)
    for architecture in ARCHES:
        report = json.loads((directory / ('native-' + architecture + '.json')).read_text())
        if (report['status'] != STATUS or report['result'] != 'PASS' or report['commit'] != expected
                or report['architecture'] != architecture or report['archiveSHA256'] != digest):
            raise ValueError('Both native receipts must pass for the exact same source and review ZIP')
    print(STATUS + ': both native receipts match the unchanged ZIP; physical review is still required.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=['stage', 'verify', 'evidence'])
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--expected-commit', required=True)
    parser.add_argument('--architecture', choices=ARCHES)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    if args.operation != 'evidence' and platform.system() != 'Darwin':
        parser.error('Review app packaging and native verification require macOS')
    if args.operation == 'stage':
        stage(args.directory.resolve(), args.expected_commit)
    elif args.operation == 'verify':
        if not args.architecture or not args.report:
            parser.error('verify requires --architecture and --report')
        verify(args.directory.resolve(), args.expected_commit, args.architecture, args.report)
    else:
        evidence(args.directory.resolve(), args.expected_commit)


if __name__ == '__main__':
    main()
