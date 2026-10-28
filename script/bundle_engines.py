#!/usr/bin/env python3
"""Stage maintainer-reviewed, self-contained engines before the app is signed.

No downloads or package-manager execution. A manifest is an inventory, not proof
of license compliance: the distributor must review the corresponding sources.
"""
from __future__ import annotations
import argparse, hashlib, json, os, pathlib, re, shutil, subprocess, tempfile

ENGINES = {'ffmpeg': {'bin/ffmpeg', 'bin/ffprobe'}, 'imagemagick': {'bin/magick'}, 'pandoc': {'bin/pandoc'}}
ARCHITECTURES = {'arm64', 'x86_64'}
MAX_FILES, MAX_BYTES = 20_000, 2_000_000_000
MACHO = {b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xfe\xed\xfa\xce',
         b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca', b'\xca\xfe\xba\xbf', b'\xbf\xba\xfe\xca'}

def relative_path(value: object) -> str:
    if not isinstance(value, str) or not value or len(value) > 1024 or '\\' in value or any(ord(c)<32 for c in value):
        raise ValueError('Invalid pack path')
    parts=value.split('/')
    if any(p in {'', '.', '..'} for p in parts) or value.startswith('/'):
        raise ValueError('Pack paths must be canonical and relative')
    return value

def version(value: object) -> tuple[int, int]:
    if not isinstance(value,str) or not re.fullmatch(r'\d+\.\d+(?:\.\d+)?',value):
        raise ValueError('Invalid macOS deployment target')
    return tuple(int(x) for x in value.split('.')[:2])

def digest(path: pathlib.Path) -> str:
    h=hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1_048_576), b''): h.update(block)
    return h.hexdigest()

def validate_pack(root: pathlib.Path, required_architectures: set[str]) -> dict:
    root=pathlib.Path(root)
    if not required_architectures or not required_architectures <= ARCHITECTURES:
        raise ValueError('Unknown build architecture')
    if root.is_symlink() or not root.is_dir(): raise ValueError('Engine pack must be a real directory')
    manifest_path=root/'manifest.json'
    if manifest_path.is_symlink() or not manifest_path.is_file() or manifest_path.stat().st_size>2_000_000:
        raise ValueError('Missing or oversized pack manifest')
    def unique_keys(pairs):
        result={}
        for key,value in pairs:
            if key in result: raise ValueError('Duplicate manifest key')
            result[key]=value
        return result
    m=json.loads(manifest_path.read_text(),object_pairs_hook=unique_keys)
    if not isinstance(m,dict) or type(m.get('schema')) is not int or m.get('schema')!=1 or not isinstance(m.get('engine'),str) or m['engine'] not in ENGINES:
        raise ValueError('Unsupported engine pack')
    if not isinstance(m.get('version'),str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9.+_-]{0,79}',m['version']):
        raise ValueError('Missing engine version')
    arches=m.get('architectures')
    if not isinstance(arches,list) or any(not isinstance(a,str) for a in arches) or not required_architectures<=set(arches)<=ARCHITECTURES:
        raise ValueError('Pack does not support every requested architecture')
    if version(m.get('minimumMacOS'))>(13,0):raise ValueError('Engine requires newer macOS than Lemulip')
    flags=m.get('buildFlags')
    if not isinstance(flags,list) or any(not isinstance(f,str) for f in flags) or any('nonfree' in f.lower() and f.lower() != '--disable-nonfree' for f in flags):
        raise ValueError('Unreviewed or non-redistributable build configuration')
    files=m.get('files')
    if not isinstance(files,dict) or not 1<=len(files)<=MAX_FILES:raise ValueError('Missing file inventory')
    for name,sha in files.items():
        relative_path(name)
        if name=='manifest.json' or not isinstance(sha,str) or not re.fullmatch('[0-9a-f]{64}',sha):raise ValueError('Invalid file digest')
    inventory=set();size=0
    for p in root.rglob('*'):
        if p.is_symlink():raise ValueError('Symlinks are not allowed in prepared engine packs')
        if p.is_dir():continue
        if not p.is_file():raise ValueError('Pack contains a special file')
        name=p.relative_to(root).as_posix()
        if name=='manifest.json':continue
        inventory.add(name);size+=p.stat().st_size
        if len(inventory)>MAX_FILES or size>MAX_BYTES:raise ValueError('Engine pack exceeds its size budget')
        if files.get(name)!=digest(p):raise ValueError('Unlisted or changed pack file: '+name)
    if inventory!=set(files):raise ValueError('Pack is missing declared files')
    executable=m.get('executables')
    if not isinstance(executable,list) or any(not isinstance(e,str) for e in executable) or set(executable)!=ENGINES[m['engine']]:
        raise ValueError('Required engine helper is missing or unexpected')
    if not set(executable)<=inventory:raise ValueError('Engine executables are missing')
    components=m.get('components')
    if not isinstance(components,list) or not components:raise ValueError('Component and license inventory is required')
    seen=set()
    for c in components:
        if not isinstance(c,dict) or not isinstance(c.get('name'),str) or not c['name'] or c['name'] in seen:
            raise ValueError('Invalid or duplicate component')
        seen.add(c['name'])
        license_id=c.get('license')
        if not isinstance(license_id,str) or not license_id.strip() or any(x in license_id.lower() for x in ('unknown','nonfree','proprietary')):
            raise ValueError('Unreviewed license')
        # Require exact source archives and build instructions for every bundled
        # component, not just those whose license name we happen to recognize.
        for key, prefix in [('notice','licenses/'),('source','sources/'),('buildInstructions','sources/')]:
            name=relative_path(c.get(key))
            if name not in inventory or not name.startswith(prefix) or (root/name).stat().st_size==0:
                raise ValueError('Missing component '+key)
    if m['engine'] not in seen:raise ValueError('Main engine is absent from the component inventory')
    return m

def verify_macho(root: pathlib.Path, manifest: dict, required_architectures: set[str]) -> list[pathlib.Path]:
    """Verify real executable/library bytes, slices and local dependency closure."""
    native=[]
    for name in manifest['files']:
        p=root/name
        with p.open('rb') as stream: magic=stream.read(4)
        if magic in MACHO: native.append(p)
        elif name in manifest['executables'] or name.endswith(('.dylib','.so')):
            raise ValueError('Engine code is not Mach-O: '+name)
    for p in native:
        if os.uname().sysname!='Darwin':raise ValueError('Native pack verification requires macOS')
        result=subprocess.run(['/usr/bin/lipo','-archs',str(p)],capture_output=True,text=True,check=True)
        if not required_architectures<=set(result.stdout.split()):raise ValueError('Missing binary architecture: '+p.name)
        for arch in sorted(required_architectures):
            load=subprocess.check_output(['/usr/bin/otool','-arch',arch,'-l',str(p)],text=True)
            # LC_BUILD_VERSION also contains the linker's "version". Only its
            # "minos" field is the deployment target; SDK/tool versions are not.
            commands=re.split(r'Load command \d+',load)
            deployment=[]
            for command in commands:
                kind=re.search(r'^[ \t]*cmd[ \t]+(LC_\w+)[ \t]*$',command,re.M)
                if not kind:continue
                if kind[1]=='LC_BUILD_VERSION':
                    platforms=re.findall(r'^[ \t]*platform[ \t]+(\w+)[ \t]*$',command,re.M)
                    if len(platforms)!=1 or platforms[0] not in {'1','MACOS'}:
                        raise ValueError('Engine binary is not a macOS target: '+p.name)
                    field='minos'
                elif kind[1]=='LC_VERSION_MIN_MACOSX':field='version'
                elif kind[1].startswith('LC_VERSION_MIN_'):
                    raise ValueError('Engine binary is not a macOS target: '+p.name)
                else:continue
                values=re.findall(r'^[ \t]*'+field+r'[ \t]+(\d+\.\d+(?:\.\d+)?)[ \t]*$',command,re.M)
                if len(values)!=1:raise ValueError('Missing or ambiguous binary deployment target: '+p.name)
                deployment.extend(values)
            if len(deployment)!=1 or any(version(v)>(13,0) for v in deployment):
                raise ValueError('Unsupported binary deployment target: '+p.name+' '+repr(deployment))
            linked=subprocess.check_output(['/usr/bin/otool','-arch',arch,'-L',str(p)],text=True)
            for line in linked.splitlines():
                if not line.startswith((' ','\t')):continue
                dependency=line.strip().split(' (',1)[0]
                if dependency.startswith(('/System/Library/','/usr/lib/')):continue
                if dependency.startswith('@loader_path/'):
                    target=(p.parent/dependency[len('@loader_path/'):]).resolve()
                elif dependency.startswith('@executable_path/') and p.relative_to(root).as_posix() in manifest['executables']:
                    target=(p.parent/dependency[len('@executable_path/'):]).resolve()
                else:raise ValueError('Non-portable engine dependency: '+dependency)
                if not target.is_relative_to(root.resolve()) or not target.is_file():raise ValueError('Dependency escapes or is missing from the pack')
                if target.relative_to(root.resolve()).as_posix() not in manifest['files']:raise ValueError('Undeclared dependency')
    return native

def stage_packs(packs: pathlib.Path, app: pathlib.Path, architectures: set[str]) -> None:
    """Install flat signed helpers and resource-only support into a staging app.

    The enclosing build publishes the entire application after signing it. This
    function never overwrites existing helpers and rolls back its own additions
    on failure. Source packs remain unchanged.
    """
    helpers=app/'Contents/Helpers'
    support=app/'Contents/Resources/EngineSupport'
    directories=[app,app/'Contents',app/'Contents/Resources',helpers,support]
    for directory in directories:
        if directory.is_symlink() or (directory.exists() and not directory.is_dir()):
            raise ValueError('Bundle directories must be real directories')
    if not app.is_dir() or not (app/'Contents').is_dir():raise ValueError('Missing staging application')
    if (helpers/'Engines').exists() or (helpers/'Engines').is_symlink():
        raise ValueError('Refusing to replace an existing engine bundle')
    roots=sorted(p for p in packs.iterdir() if p.is_dir())
    if not roots:raise ValueError('No prepared engine packs were supplied')
    manifests=[];seen=set();helper_names=set()
    for root in roots:
        manifest=validate_pack(root,architectures)
        engine=manifest['engine']
        if engine in seen:raise ValueError('Duplicate engine pack')
        seen.add(engine)
        target=support/engine
        if target.exists() or target.is_symlink():raise ValueError('Refusing to replace existing engine resources')
        if 'installed-manifest.json' in manifest['files']:raise ValueError('Reserved installed manifest path')
        native=verify_macho(root,manifest,architectures)
        if {p.relative_to(root).as_posix() for p in native}!=set(manifest['executables']):
            raise ValueError('Only self-contained executable packs support this bundle layout')
        for executable in manifest['executables']:
            name=pathlib.PurePosixPath(executable).name
            if name in helper_names or (helpers/name).exists() or (helpers/name).is_symlink():
                raise ValueError('Refusing to replace an existing helper: '+name)
            helper_names.add(name)
        manifests.append((root,manifest))
    # Never put temporary data in Helpers: macOS treats that directory as code.
    stage=pathlib.Path(tempfile.mkdtemp(prefix='.engine-stage-',dir=app.parent))
    created_files=[];created_support=[];created_directories=[]
    try:
        for root,m in manifests:
            copy=stage/'packs'/m['engine'];shutil.copytree(root,copy,symlinks=True)
            if validate_pack(copy,architectures)!=m:raise ValueError('Pack manifest changed during staging')
            for p in verify_macho(copy,m,architectures):
                p.chmod(0o755)
                subprocess.run(['/usr/bin/codesign','--force','--sign','-',str(p)],check=True)
                subprocess.run(['/usr/bin/codesign','--verify','--strict',str(p)],check=True)
            mapping={}
            for name in [*m['files'],'manifest.json']:
                if name in m['executables']:
                    relative='Contents/Helpers/'+pathlib.PurePosixPath(name).name
                else:relative='Contents/Resources/EngineSupport/'+m['engine']+'/'+name
                mapping[name]=relative
                target=stage/'layout'/relative;target.parent.mkdir(parents=True,exist_ok=True)
                shutil.copy2(copy/name,target)
                target.chmod(0o755 if name in m['executables'] else 0o644)
            installed={'schema':2,'engine':m['engine'],'sourceManifestSHA256':digest(copy/'manifest.json'),
                       'architectures':sorted(architectures),'sourceToBundle':mapping,
                       'files':{target:digest(stage/'layout'/target) for target in mapping.values()}}
            (stage/'layout/Contents/Resources/EngineSupport'/m['engine']/'installed-manifest.json').write_text(
                json.dumps(installed,indent=2,sort_keys=True)+'\n')
        # All native validation and signing finish before touching the app.
        for directory in [app/'Contents/Resources',helpers,support]:
            if directory.is_symlink():raise ValueError('Bundle directory changed during staging')
            if not directory.exists():directory.mkdir();created_directories.append(directory)
        for name in sorted(helper_names):
            target=helpers/name
            # Exclusive publication: unlike rename, link never replaces a file
            # that appeared after the collision checks. Staging is on this volume.
            os.link(stage/'layout/Contents/Helpers'/name,target)
            created_files.append(target)
        for _,m in manifests:
            target=support/m['engine']
            target.mkdir();created_support.append(target)
            shutil.copytree(stage/'layout/Contents/Resources/EngineSupport'/m['engine'],target,dirs_exist_ok=True)
    except BaseException:
        for target in reversed(created_support):shutil.rmtree(target)
        for target in reversed(created_files):target.unlink()
        for directory in reversed(created_directories):directory.rmdir()
        raise
    finally:
        shutil.rmtree(stage)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--packs',type=pathlib.Path,required=True)
    parser.add_argument('--app',type=pathlib.Path,required=True)
    parser.add_argument('--architectures',nargs='+',choices=sorted(ARCHITECTURES),required=True)
    args=parser.parse_args()
    stage_packs(args.packs,args.app,set(args.architectures))
if __name__=='__main__':main()
