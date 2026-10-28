#!/usr/bin/env python3
"""Verify installed engine inventories, native slices and source material."""
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

REQUIRED = {'ffmpeg','imagemagick'}


def read_json(path):
    if path.stat().st_size > 2_000_000: raise ValueError('Oversized engine manifest')
    def unique(pairs):
        result={}
        for k,v in pairs:
            if k in result:raise ValueError('Duplicate engine manifest key')
            result[k]=v
        return result
    value=json.loads(path.read_text(),object_pairs_hook=unique)
    if not isinstance(value,dict):raise ValueError('Invalid engine manifest')
    return value


def regular(root: Path, relative: str) -> Path:
    packs.relative_path(relative)
    p=root
    for part in relative.split('/'):
        p=p/part
        if p.is_symlink():raise ValueError('Symbolic link in installed engine')
    if not p.is_file():raise ValueError('Missing installed engine file: '+relative)
    return p


def verify(app: Path, architectures: set[str], required: set[str] = REQUIRED) -> dict:
    app=Path(app)
    if app.is_symlink() or not app.is_dir():raise ValueError('Invalid application directory')
    if not required or not required <= packs.ENGINES.keys():raise ValueError('Unknown required engine')
    result={}
    for engine in sorted(required):
        base='Contents/Resources/EngineSupport/'+engine+'/'
        original=regular(app,base+'manifest.json')
        manifest=read_json(original)
        installed=read_json(regular(app,base+'installed-manifest.json'))
        if (type(installed.get('schema')) is not int or installed['schema'] != 2 or installed.get('engine') != engine
            or manifest.get('engine') != engine or installed.get('sourceManifestSHA256') != packs.digest(original)):
            raise ValueError('Installed engine manifest mismatch')
        if not isinstance(manifest.get('files'),dict):raise ValueError('Missing original inventory')
        if installed.get('architectures') != sorted(architectures):raise ValueError('Installed architecture mismatch')
        executables=packs.ENGINES[engine]
        expected={name:('Contents/Helpers/'+Path(name).name if name in executables else base+name)
                  for name in [*manifest['files'],'manifest.json']}
        if installed.get('sourceToBundle') != expected or not isinstance(installed.get('files'),dict) or set(installed['files']) != set(expected.values()):
            raise ValueError('Unexpected installed engine path mapping')
        actual=set()
        for p in (app/base).rglob('*'):
            if p.is_symlink():raise ValueError('Symbolic link in engine resources')
            if p.is_file():actual.add(p.relative_to(app).as_posix())
            elif not p.is_dir():raise ValueError('Special engine resource')
        if actual != {path for path in expected.values() if path.startswith(base)} | {base+'installed-manifest.json'}:
            raise ValueError('Unlisted or missing installed engine resources')
        # Reconstruct a read-only validation view. Only executable digests may
        # differ from the source pack, because bundle signing changes those bytes.
        with tempfile.TemporaryDirectory(prefix='lemulip-engine-check-') as tmp:
            root=Path(tmp);prepared=copy.deepcopy(manifest)
            for name,path in expected.items():
                source=regular(app,path);digest=packs.digest(source)
                if installed['files'][path] != digest:raise ValueError('Installed engine digest mismatch: '+path)
                if name=='manifest.json':continue
                if name not in executables and manifest['files'][name] != digest:
                    raise ValueError('Original source or notice changed: '+name)
                if name in executables:prepared['files'][name]=digest
                target=root/name;target.parent.mkdir(parents=True,exist_ok=True)
                try:os.link(source,target)
                except OSError:shutil.copy2(source,target)
            (root/'manifest.json').write_text(json.dumps(prepared))
            packs.validate_pack(root,architectures);packs.verify_macho(root,prepared,architectures)
        for name in sorted(executables):
            subprocess.run(['/usr/bin/codesign','--verify','--all-architectures','--strict',str(app/expected[name])],check=True)
        result[engine]={'version':manifest['version'],'architectures':sorted(architectures),
                        'executables':len(executables),'files':len(expected),'components':len(manifest['components'])}
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app',type=Path,required=True)
    parser.add_argument('--architectures',choices=sorted(packs.ARCHITECTURES),nargs='+',required=True)
    args=parser.parse_args();print(json.dumps(verify(args.app,set(args.architectures)),indent=2))

if __name__=='__main__':main()
