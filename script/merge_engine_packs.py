#!/usr/bin/env python3
"""Combine verified native engine packs, preserving both build records."""
from __future__ import annotations
import argparse
import copy
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import bundle_engines as packs

PER_ARCH = {'sources/BUILD.txt', 'sources/build-record.json'}


def merge(arm64: Path, x86_64: Path, output: Path) -> None:
    roots = {'arm64':Path(arm64), 'x86_64':Path(x86_64)}
    output=Path(output)
    if output.exists() or output.is_symlink(): raise ValueError('Refusing to replace an existing universal pack')
    if any(output.resolve().is_relative_to(p.resolve()) for p in roots.values()):
        raise ValueError('Output must be outside both native packs')
    manifests={arch:packs.validate_pack(root,{arch}) for arch,root in roots.items()}
    for arch,root in roots.items():
        if manifests[arch]['architectures'] != [arch]: raise ValueError('Expected one native architecture per input')
        packs.verify_macho(root,manifests[arch],{arch})
    left,right=manifests['arm64'],manifests['x86_64']
    for key in ('engine','version','minimumMacOS','executables','components'):
        if left[key] != right[key]: raise ValueError('Native pack metadata differs: '+key)
    if set(left['files']) != set(right['files']): raise ValueError('Native file inventories differ')
    native=set(left['executables'])
    for name in left['files']:
        if name not in native | PER_ARCH and left['files'][name] != right['files'][name]:
            raise ValueError('Native sources or notices differ: '+name)
    for name in left['files']:
        if name.startswith('sources/native/') or name == 'sources/merge_engine_packs.py':
            raise ValueError('Reserved universal source path')
    output.parent.mkdir(parents=True,exist_ok=True)
    stage=Path(tempfile.mkdtemp(prefix='.merge-engine-',dir=output.parent))
    created=False
    try:
        def checked_copy(source, target, expected):
            target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(source,target)
            if packs.digest(target) != expected: raise ValueError('Native input changed while merging')
        for name,expected in left['files'].items():
            if name in native:
                target=stage/name;target.parent.mkdir(parents=True,exist_ok=True)
                subprocess.run(['/usr/bin/lipo','-create',str(arm64/name),str(x86_64/name),'-output',str(target)],check=True)
                target.chmod(0o755)
            elif name not in PER_ARCH:
                checked_copy(arm64/name,stage/name,expected)
        for arch,root in roots.items():
            for name in sorted(PER_ARCH & set(left['files'])):
                checked_copy(root/name,stage/'sources/native'/arch/name,manifests[arch]['files'][name])
            (stage/'sources/native'/arch).mkdir(parents=True,exist_ok=True)
            shutil.copy2(root/'manifest.json',stage/'sources/native'/arch/'manifest.json')
            if json.loads((stage/'sources/native'/arch/'manifest.json').read_text()) != manifests[arch]:
                raise ValueError('Native manifest changed while merging')
        for arch,root in roots.items():
            for name in native:
                if packs.digest(root/name) != manifests[arch]['files'][name]:
                    raise ValueError('Native executable changed during merging')
        shutil.copy2(Path(__file__),stage/'sources/merge_engine_packs.py')
        (stage/'sources/BUILD.txt').write_text(
            'Universal Lemulip '+left['engine']+' helper\n'
            'Original component archives and full notices are retained alongside this file.\n'
            'Each architecture has its unmodified source manifest, build instructions and command record under sources/native/<arch>/.\n'
            'Rebuild each native pack using its recorded recipe, then combine on macOS:\n'
            'python3 script/merge_engine_packs.py --arm64 <arm-pack> --x86-64 <intel-pack> --output <new-universal-pack>\n'
            'The merge validates both inputs, refuses changed source archives or notices, and retains both build records.\n'
            'The standalone helper can be rebuilt and relinked with modified dependencies.\n')
        manifest=copy.deepcopy(left)
        manifest['architectures']=['arm64','x86_64']
        manifest['buildFlags']=list(dict.fromkeys(left['buildFlags']+right['buildFlags']))
        manifest['nativeManifests']={arch:'sources/native/'+arch+'/manifest.json' for arch in roots}
        manifest['files']={p.relative_to(stage).as_posix():packs.digest(p) for p in sorted(stage.rglob('*')) if p.is_file()}
        (stage/'manifest.json').write_text(json.dumps(manifest,indent=2,sort_keys=True)+'\n')
        packs.validate_pack(stage,{'arm64','x86_64'});packs.verify_macho(stage,manifest,{'arm64','x86_64'})
        # Exclusive reservation; an unrelated existing directory is never replaced.
        output.mkdir();created=True
        shutil.copytree(stage,output,dirs_exist_ok=True)
        packs.validate_pack(output,{'arm64','x86_64'});packs.verify_macho(output,manifest,{'arm64','x86_64'})
    except BaseException:
        if created: shutil.rmtree(output)
        raise
    finally:shutil.rmtree(stage)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--arm64',type=Path,required=True)
    parser.add_argument('--x86-64',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();merge(args.arm64,args.x86_64,args.output)

if __name__=='__main__':main()
