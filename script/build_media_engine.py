#!/usr/bin/env python3
"""Build an auditable, relocatable FFmpeg helper pack on a native Mac.

The result includes original source archives, full upstream notices and the
recipe. No application release is created or replaced. Build tools may be
installed separately; no Homebrew runtime library is copied into the pack.
"""
from __future__ import annotations
import argparse
import difflib
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import re
import shutil
import subprocess
import tarfile
import tempfile
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parent.parent
NAMES = {'libogg', 'libvorbis', 'opus', 'lame', 'libvpx', 'x264', 'ffmpeg'}
ARCHES = {'arm64', 'x86_64'}
ENCODERS = {'libx264', 'aac', 'libmp3lame', 'libopus', 'libvorbis', 'libvpx-vp9',
            'pcm_s16le', 'pcm_s16be', 'flac', 'gif'}


def load_lock(path: Path) -> dict:
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result: raise ValueError('Duplicate source-lock key')
            result[key] = value
        return result
    lock = json.loads(path.read_text(), object_pairs_hook=unique)
    if not isinstance(lock, dict) or type(lock.get('schema')) is not int or lock.get('schema') != 1 or lock.get('minimumMacOS') != '13.0':
        raise ValueError('Unsupported source-lock format or platform')
    components = lock.get('components')
    if not isinstance(components, list) or len(components) != len(NAMES):
        raise ValueError('Incomplete or duplicate source list')
    seen = set()
    for c in components:
        if not isinstance(c, dict) or c.get('name') not in NAMES or c['name'] in seen:
            raise ValueError('Unknown or duplicate component')
        seen.add(c['name'])
        if not isinstance(c.get('version'), str) or not re.fullmatch(r'[A-Za-z0-9.+_-]{1,80}', c['version']):
            raise ValueError('Invalid pinned version')
        url = urlsplit(c.get('url', ''))
        if url.scheme != 'https' or not url.hostname or url.username or url.password or url.fragment:
            raise ValueError('Sources must use credential-free HTTPS')
        if c.get('license') not in {'BSD-3-Clause', 'LGPL-2.0-or-later', 'GPL-2.0-or-later'}:
            raise ValueError('Unreviewed license selection')
        kind = c.get('kind')
        if kind == 'archive':
            if not re.fullmatch(r'[a-f0-9]{64}', c.get('sha256', '')): raise ValueError('Source archive is not pinned')
        elif kind == 'git':
            if not re.fullmatch(r'[a-f0-9]{40}', c.get('revision', '')): raise ValueError('Source commit is not pinned')
        else: raise ValueError('Unknown source transport')
    if seen != NAMES or components[-1]['name'] != 'ffmpeg':
        raise ValueError('Invalid dependency order')
    return lock


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''): h.update(block)
    return h.hexdigest()


def verify_digest(path: Path, expected: str) -> str:
    actual = sha256(path)
    if actual != expected: raise ValueError('Source checksum mismatch: ' + path.name)
    return actual


def extract_source(archive: Path, destination: Path, maximum_bytes: int = 1_000_000_000) -> Path:
    """Validate the entire archive before writing; never follow archive links."""
    if destination.exists() or destination.is_symlink(): raise ValueError('Source directory already exists')
    with tarfile.open(archive, 'r:*') as tar:
        members = tar.getmembers()
        if not 1 <= len(members) <= 100_000: raise ValueError('Source file count exceeded')
        names, total, roots = set(), 0, set()
        for item in members:
            name = item.name.rstrip('/')
            parts = name.split('/')
            if not name or name.startswith('/') or '\\' in name or any(p in {'', '.', '..'} for p in parts):
                raise ValueError('Noncanonical source path')
            if any(ord(c) < 32 or ord(c) == 127 for c in name) or name in names:
                raise ValueError('Duplicate or invalid source path')
            if not item.isfile() and not item.isdir(): raise ValueError('Source links and special files are refused')
            if item.size < 0: raise ValueError('Negative source size')
            names.add(name); roots.add(parts[0]); total += item.size
            if total > maximum_bytes: raise ValueError('Source expansion budget exceeded')
        if len(roots) != 1: raise ValueError('Expected one source root')
        # Reject a file being used as another entry's parent.
        files = {m.name.rstrip('/') for m in members if m.isfile()}
        for name in names:
            if any(str(p) in files for p in PurePosixPath(name).parents if str(p) != '.'):
                raise ValueError('Source parent is not a directory')
        destination.mkdir(parents=True)
        try:
            for item in members:
                target = destination / item.name.rstrip('/')
                if item.isdir(): target.mkdir(parents=True, exist_ok=True); continue
                target.parent.mkdir(parents=True, exist_ok=True)
                with tar.extractfile(item) as source, target.open('xb') as output:
                    shutil.copyfileobj(source, output)
                target.chmod(0o755 if item.mode & 0o111 else 0o644)
        except Exception:
            shutil.rmtree(destination)
            raise
    return destination / next(iter(roots))


def prepare_source(name: str, source: Path, sources: Path) -> Path | None:
    # Vorbis 1.3.7 injects an obsolete PowerPC-era linker flag on every Darwin
    # host. Keep the original archive and a reproducible patch beside it.
    if name != 'libvorbis': return None
    configure = source / 'configure'
    original = configure.read_text()
    obsolete = ' -force_cpusubtype_ALL'
    if original.count(obsolete) != 3:
        raise ValueError('Unexpected Vorbis configure script; review the source before patching')
    corrected = original.replace(obsolete, '')
    patch = sources / 'libvorbis-darwin-linker.patch'
    patch.write_text(''.join(difflib.unified_diff(original.splitlines(keepends=True),
        corrected.splitlines(keepends=True), fromfile='a/configure', tofile='b/configure')))
    configure.write_text(corrected)
    return patch


def assert_host(system: str, host: str, requested: str) -> None:
    if system != 'Darwin' or requested not in ARCHES or host != requested:
        raise ValueError('Build each architecture on its native macOS runner')


def configure_arguments(name: str, prefix: Path, arch: str) -> list[str]:
    if name not in NAMES or arch not in ARCHES: raise ValueError('Unknown component or architecture')
    common = ['--prefix=' + str(prefix), '--disable-shared', '--enable-static']
    if name in {'libogg', 'libvorbis'}: return common + ['--disable-dependency-tracking']
    if name == 'opus': return common + ['--disable-extra-programs', '--disable-doc']
    if name == 'lame': return common + ['--disable-frontend', '--disable-decoder', '--disable-nasm']
    if name == 'libvpx':
        return common + ['--disable-examples', '--disable-tools', '--disable-unit-tests', '--disable-docs',
                         '--enable-pic', '--enable-vp9-highbitdepth']
    if name == 'x264':
        return ['--prefix=' + str(prefix), '--enable-static', '--enable-pic', '--disable-cli', '--disable-opencl']
    return common + ['--disable-autodetect', '--disable-nonfree', '--disable-network', '--disable-debug',
        '--disable-doc', '--disable-ffplay', '--enable-gpl', '--enable-libx264', '--enable-libmp3lame',
        '--enable-libopus', '--enable-libvorbis', '--enable-libvpx', '--enable-zlib', '--enable-bzlib',
        '--enable-videotoolbox', '--enable-audiotoolbox', '--pkg-config-flags=--static', '--cc=clang',
        '--cxx=clang++', '--target-os=darwin', '--arch=' + arch,
        '--extra-cflags=-I' + str(prefix / 'include') + ' -mmacosx-version-min=13.0',
        '--extra-ldflags=-L' + str(prefix / 'lib') + ' -mmacosx-version-min=13.0']


def run(argv: list[str], cwd: Path, environment: dict, record: list[dict]) -> None:
    print('+ ' + ' '.join(argv), flush=True)
    record.append({'directory': cwd.name, 'arguments': argv})
    subprocess.run(argv, cwd=cwd, env=environment, check=True, timeout=2400)


def fetch_source(component: dict, work: Path, sources: Path, environment: dict, record: list[dict]) -> tuple[Path, Path]:
    name = component['name']
    if component['kind'] == 'archive':
        filename = Path(urlsplit(component['url']).path).name
        archive = sources / filename
        run(['/usr/bin/curl', '--fail', '--location', '--proto', '=https', '--proto-redir', '=https',
             '--retry', '2', '--max-time', '240', '--max-filesize', '200000000',
             '--output', str(archive), component['url']], work, environment, record)
        verify_digest(archive, component['sha256'])
    else:
        checkout = work / (name + '-git'); checkout.mkdir()
        revision = component['revision']
        run(['/usr/bin/git', 'init', '--quiet'], checkout, environment, record)
        run(['/usr/bin/git', '-c', 'core.hooksPath=/dev/null', '-c', 'protocol.file.allow=never',
             'fetch', '--no-tags', '--depth=1', component['url'], revision], checkout, environment, record)
        actual = subprocess.check_output(['/usr/bin/git', 'rev-parse', 'FETCH_HEAD'], cwd=checkout, env=environment, text=True).strip()
        if actual != revision: raise ValueError('Source commit mismatch')
        archive = sources / (name + '-' + revision + '.tar')
        run(['/usr/bin/git', 'archive', '--format=tar', '--prefix=' + name + '/',
             '--output=' + str(archive), revision], checkout, environment, record)
    return extract_source(archive, work / (name + '-source')), archive


def smoke_test(pack: Path, work: Path, environment: dict, record: list[dict]) -> None:
    ffmpeg, ffprobe = [str(pack / 'bin' / n) for n in ('ffmpeg', 'ffprobe')]
    encoders = subprocess.check_output([ffmpeg, '-hide_banner', '-encoders'], env=environment, text=True)
    available = {r.split()[1] for r in encoders.splitlines() if len(r.split()) >= 2 and len(r.split()[0]) == 6}
    if not ENCODERS <= available: raise ValueError('Missing Lemulip encoders: ' + ', '.join(sorted(ENCODERS - available)))
    protocols = subprocess.check_output([ffmpeg, '-hide_banner', '-protocols'], env=environment, text=True)
    if any(p in protocols.split() for p in ('http', 'https', 'tcp', 'udp', 'ftp')):
        raise ValueError('Unexpected network protocol in offline engine')
    test = work / 'smoke'; test.mkdir()
    original = test / 'original.mkv'
    run([ffmpeg, '-v', 'error', '-f', 'lavfi', '-i', 'testsrc2=size=128x96:rate=10:duration=0.5',
         '-f', 'lavfi', '-i', 'sine=frequency=440:duration=0.5', '-c:v', 'ffv1', '-c:a', 'pcm_s16le',
         str(original)], test, environment, record)
    before = sha256(original)
    cases = {'mp4': ['-c:v', 'libx264', '-c:a', 'aac'],
             'webm': ['-c:v', 'libvpx-vp9', '-c:a', 'libopus'],
             'avi': ['-c:v', 'mpeg4', '-c:a', 'libmp3lame'],
             'mp3': ['-vn', '-c:a', 'libmp3lame'], 'ogg': ['-vn', '-c:a', 'libvorbis'],
             'opus': ['-vn', '-c:a', 'libopus'], 'flac': ['-vn', '-c:a', 'flac'],
             'wav': ['-vn', '-c:a', 'pcm_s16le'], 'aiff': ['-vn', '-c:a', 'pcm_s16be'],
             'gif': ['-an', '-vf', 'fps=5,scale=64:-1', '-c:v', 'gif']}
    for ext, flags in cases.items():
        output = test / ('converted.' + ext)
        run([ffmpeg, '-v', 'error', '-i', str(original), *flags, str(output)], test, environment, record)
        if output.stat().st_size < 1: raise ValueError('Empty conversion output')
        probe = json.loads(subprocess.check_output([ffprobe, '-v', 'error', '-show_streams', '-of', 'json', str(output)], env=environment))
        if not probe.get('streams'): raise ValueError('Converted file has no streams')
        run([ffmpeg, '-v', 'error', '-i', str(output), '-f', 'null', '-'], test, environment, record)
    if sha256(original) != before: raise ValueError('Original input changed')


def build(output: Path, work: Path, architecture: str) -> None:
    assert_host(platform.system(), platform.machine(), architecture)
    if output.exists() or output.is_symlink(): raise ValueError('Refusing to replace an existing pack')
    if work.exists() or work.is_symlink(): raise ValueError('Build work directory must be new')
    lock_path = ROOT / 'script/media-engine-sources.json'
    lock = load_lock(lock_path)
    work.mkdir(parents=True)
    prefix = work / 'prefix'; prefix.mkdir()
    stage = work / 'pack'; (stage / 'sources').mkdir(parents=True)
    (stage / 'licenses').mkdir(); (stage / 'bin').mkdir()
    record = []
    # Keep tool paths, but never consume the runner's package discovery paths,
    # injected compiler flags, Git configuration or credentials.
    environment = {k: os.environ[k] for k in ('PATH', 'HOME', 'TMPDIR', 'DEVELOPER_DIR') if k in os.environ}
    environment.update({'MACOSX_DEPLOYMENT_TARGET': '13.0', 'CC': 'clang', 'CXX': 'clang++',
        'CFLAGS': '-O2 -mmacosx-version-min=13.0 -std=gnu17', 'CXXFLAGS': '-O2 -mmacosx-version-min=13.0',
        'CPPFLAGS': '-I' + str(prefix / 'include'), 'LDFLAGS': '-L' + str(prefix / 'lib') + ' -mmacosx-version-min=13.0',
        'PKG_CONFIG_PATH': '', 'PKG_CONFIG_LIBDIR': str(prefix / 'lib/pkgconfig'),
        'GIT_CONFIG_GLOBAL': '/dev/null', 'GIT_CONFIG_NOSYSTEM': '1', 'GIT_TERMINAL_PROMPT': '0',
        'LC_ALL': 'C', 'ac_cv_prog_cc_c23': 'no'})
    for tool in ('clang', 'make', 'pkg-config', 'nasm'):
        if not shutil.which(tool, path=environment.get('PATH')): raise ValueError('Missing build-only tool: ' + tool)
    components, ffmpeg_flags = [], []
    for component in lock['components']:
        name = component['name']
        source, archive = fetch_source(component, work, stage / 'sources', environment, record)
        notices = []
        for pattern in ('COPYING*', 'LICENSE*', 'NOTICE*', 'PATENTS*', 'AUTHORS*'):
            notices.extend(p for p in source.glob(pattern) if p.is_file())
        if not notices: raise ValueError('Missing upstream notices: ' + name)
        notice = stage / 'licenses' / (name + '.txt')
        with notice.open('wb') as destination:
            destination.write((name + ' ' + component['version'] + '\n' + component['url'] + '\n\n').encode())
            for p in sorted(set(notices)):
                destination.write(('\n===== ' + p.name + ' =====\n').encode()); destination.write(p.read_bytes())
            if name == 'ffmpeg':
                destination.write(b'\nThis software is based in part on the work of the Independent JPEG Group.\nNo changes were made to the IJG-derived FFmpeg source files.\n')
        prepare_source(name, source, stage / 'sources')
        flags = configure_arguments(name, prefix, architecture)
        if name == 'ffmpeg': ffmpeg_flags = flags
        run(['./configure', *flags], source, environment, record)
        run(['make', '-j', str(min(os.cpu_count() or 2, 8))], source, environment, record)
        run(['make', 'install'], source, environment, record)
        components.append({'name': name, 'license': component['license'], 'notice': 'licenses/' + notice.name,
                           'source': 'sources/' + archive.name, 'buildInstructions': 'sources/BUILD.txt'})
    for name in ('ffmpeg', 'ffprobe'):
        shutil.copy2(prefix / 'bin' / name, stage / 'bin' / name)
    for path in ('build_media_engine.py', 'bundle_engines.py', 'media-engine-sources.json'):
        shutil.copy2(ROOT / 'script' / path, stage / 'sources' / path)
    (stage / 'sources/BUILD.txt').write_text(
        'Lemulip media helper source build\n'
        'Build on macOS with Xcode Command Line Tools, Python 3.11+, make, pkg-config and nasm.\n'
        'Use script/build_media_engine.py and the included media-engine-sources.json from the matching Lemulip checkout.\n'
        'Run: python3 script/build_media_engine.py --output <new-pack-directory> --work <new-work-directory> --arch ' + architecture + '\n'
        'The source archives here are the complete unmodified inputs. Git inputs are verified by the pinned commit before export.\n'
        'The full command sequence is in build-record.json. The recipe applies libvorbis-darwin-linker.patch to the original Vorbis configure script.\n'
        'The helper executables are separate from the MIT application.\n')
    smoke_test(stage, work, environment, record)
    (stage / 'sources/build-record.json').write_text(json.dumps({'architecture': architecture, 'minimumMacOS': '13.0',
        'compiler': subprocess.check_output(['clang', '--version'], env=environment, text=True),
        'commands': record}, indent=2) + '\n')
    manifest = {'schema': 1, 'engine': 'ffmpeg', 'version': lock['components'][-1]['version'],
        'architectures': [architecture], 'minimumMacOS': '13.0', 'executables': ['bin/ffmpeg', 'bin/ffprobe'],
        'buildFlags': ffmpeg_flags, 'components': components,
        'files': {p.relative_to(stage).as_posix(): sha256(p) for p in sorted(stage.rglob('*')) if p.is_file()}}
    (stage / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    import bundle_engines
    bundle_engines.validate_pack(stage, {architecture})
    native = bundle_engines.verify_macho(stage, manifest, {architecture})
    if len(native) != 2: raise ValueError('Unexpected native runtime dependency')
    # The actual final path is deliberately different from the build prefix.
    output.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(stage, output)
    bundle_engines.validate_pack(output, {architecture})
    bundle_engines.verify_macho(output, manifest, {architecture})
    prefix.rename(work / 'unused-build-prefix')
    relocated_work = work / 'relocated-check'; relocated_work.mkdir()
    smoke_test(output, relocated_work, environment, [])
    print('Verified pack: ' + str(output), flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--arch', choices=sorted(ARCHES), required=True)
    args = parser.parse_args()
    build(args.output.absolute(), args.work.absolute(), args.arch)

if __name__ == '__main__': main()
