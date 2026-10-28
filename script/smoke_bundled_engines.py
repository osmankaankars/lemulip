#!/usr/bin/env python3
"""Exercise the exact downloaded app's engines without package-manager paths."""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
from build_image_engine import synthetic_png
from bundle_engines import digest


def check_health(text: str, app: Path) -> None:
    for engine,helper in [('ffmpeg','ffmpeg'),('imagemagick','magick')]:
        rows=[line for line in text.splitlines() if line.startswith(engine+': ')]
        if len(rows)!=1 or not re.match(re.escape(engine)+r': ready(?: |$)',rows[0]):
            raise ValueError('Bundled engine is not ready: '+engine)
        if rows[0].rsplit(' · ',1)[-1] != str(app/'Contents/Helpers'/helper):
            raise ValueError('Health check resolved an engine outside the release app')


def check(package: Path) -> dict:
    package=package.resolve();app=package/'Lemulip.app';cli=package/'lemulip'
    helpers=app/'Contents/Helpers';ffmpeg=helpers/'ffmpeg';ffprobe=helpers/'ffprobe';magick=helpers/'magick'
    with tempfile.TemporaryDirectory(prefix='Lemulip Engine Release Check ') as tmp:
        root=Path(tmp);home=root/'home';home.mkdir();outputs=root/'outputs';outputs.mkdir()
        env={'PATH':'/usr/bin:/bin:/usr/sbin:/sbin','HOME':str(home),'TMPDIR':str(root),'LC_ALL':'C'}
        def capture(argv):
            return subprocess.check_output([str(x) for x in argv],env=env,cwd=root,text=True,timeout=120).strip()
        health=capture([cli,'engines']);check_health(health,app)
        image=root/'sample image.png';synthetic_png(image);image_hash=digest(image)
        results={}
        for target in ('webp','avif'):
            directory=outputs/target;directory.mkdir()
            capture([cli,'convert',target,image,'--output',directory])
            files=list(directory.iterdir())
            if len(files)!=1 or not files[0].is_file() or files[0].suffix!='.'+target:raise ValueError('Missing image output')
            if capture([magick,'identify','-format','%w %h',files[0]]) != '64 48':raise ValueError('Invalid image result')
            results[target]=digest(files[0])
        media=root/'sample video.mkv'
        capture([ffmpeg,'-v','error','-f','lavfi','-i','testsrc2=size=128x96:rate=10:duration=0.5',
            '-f','lavfi','-i','sine=frequency=440:duration=0.5','-c:v','ffv1','-c:a','pcm_s16le',media])
        media_hash=digest(media)
        for target in ('webm','mp3'):
            directory=outputs/target;directory.mkdir()
            capture([cli,'convert',target,media,'--output',directory])
            files=list(directory.iterdir())
            if len(files)!=1 or not files[0].is_file() or files[0].suffix!='.'+target:raise ValueError('Missing media output')
            streams=json.loads(capture([ffprobe,'-v','error','-show_streams','-of','json',files[0]]))
            if not streams.get('streams'):raise ValueError('Invalid media result')
            capture([ffmpeg,'-v','error','-i',files[0],'-f','null','-'])
            results[target]=digest(files[0])
        if digest(image)!=image_hash or digest(media)!=media_hash:raise ValueError('Original input changed')
        return {'bundledHealth':health,'conversions':results,'originalsPreserved':True,'path':env['PATH']}


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--package',type=Path,required=True)
    args=parser.parse_args();print(json.dumps(check(args.package),indent=2))

if __name__=='__main__':main()
