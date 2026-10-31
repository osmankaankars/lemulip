#!/usr/bin/env python3
"""Export four reviewed native captures without resizing or repainting UI pixels."""
from collections import deque
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
CAPTURE_COMMIT = 'a45a19cf48310a8d5a3b87ad78d6b7253b3e6213'
BUILD_COMMIT = 'eaa783c949a1814130a6618395269ba17c1baa6f'
CAPTURE_RUN = 41252452759
ARTIFACT_ID = 13061981222
ARTIFACT_SHA256 = 'ab58b67460ee90521a53d43cdb9175469188da8305aaa763163b65c5b704a0b8'
APPROVED = {
    'app-workspace.webp': ('workspace-orchard', '4a7d27a265c6bbd960c7297e3a58f3635b00b30937052fd3487c9757e8dd3470'),
    'app-pdf-organize.webp': ('pdf-organize', '06663d6647ff07c66ff78a4ec6918c4cc6e7d5b6ae305f9fb3d1795e73ef4ad2'),
    'app-crop-video.webp': ('crop-video', '634caac376f3ec603b129145c84b4ab3ebdd3ce20636f92a9d61a2fe4551a6e6'),
    'app-trim-audio.webp': ('trim-audio', 'f4a8593d7ffe9343c3800bcebe25180895fdffbf19bed5e985684f72678042c0'),
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def remove_corner_padding(image):
    """Remove only border-connected black padding in 14px exterior corner boxes."""
    result = image.convert('RGBA')
    pixels = result.load()
    w, h = result.size
    queue = deque([(0, 0), (w-1, 0), (0, h-1), (w-1, h-1)])
    visited = set()
    while queue:
        x, y = queue.popleft()
        if (x, y) in visited or not (0 <= x < w and 0 <= y < h):
            continue
        if pixels[x, y] != (0, 0, 0, 255):
            continue
        if min(x, w-1-x) >= 14 or min(y, h-1-y) >= 14:
            raise ValueError('Black padding extends beyond the approved exterior corners')
        visited.add((x, y))
        queue.extend(((x-1,y),(x+1,y),(x,y-1),(x,y+1)))
    if len(visited) != 290:
        raise ValueError('Unexpected native corner geometry')
    for x, y in visited:
        pixels[x, y] = (0, 0, 0, 0)
    return result, len(visited)


def export(artifact, destination):
    provenance = json.loads((artifact/'provenance.json').read_text())
    if provenance.get('harnessCommit') != CAPTURE_COMMIT or provenance.get('applicationBuildCommit') != BUILD_COMMIT:
        raise ValueError('Unreviewed capture or application source')
    if not provenance.get('bundledEngines') or not provenance.get('originalBundleUnchanged'):
        raise ValueError('Expected the preserved complete application')
    log = (artifact/'xcodebuild.log').read_text()
    if 'Executed 7 tests, with 0 failures' not in log or '** TEST SUCCEEDED **' not in log:
        raise ValueError('Actual visual-state tests did not pass')
    display = json.loads((artifact/'virtual-display.json').read_text())
    if display.get('status') != 'native-2x-mode' or display.get('logicalSize') != [1280,900] or display.get('pixelSize') != [2560,1800]:
        raise ValueError('Native high-density rendering not established')
    source_tree = (artifact/'application-source-tree.txt').read_text().strip()
    if len(source_tree) != 40:
        raise ValueError('Missing application source identity')
    files = {digest(p):p for p in (artifact/'Attachments').rglob('*.png')}
    records = {}
    for p in (artifact/'Attachments').rglob('*.json'):
        try:
            record = json.loads(p.read_text())
        except (ValueError, UnicodeError):
            continue
        if isinstance(record,dict) and 'id' in record and 'logicalWidth' in record:
            records[record['id']] = record
    destination.mkdir(parents=True,exist_ok=True)
    manifest = []
    for name,(screen,expected) in APPROVED.items():
        record = records[screen]
        if record['sha256'] != expected or expected not in files:
            raise ValueError('Bytes differ from reviewed original: '+screen)
        if tuple(record[k] for k in ('width','height','logicalWidth','logicalHeight','scaleX','scaleY')) != (2040,1400,1020,700,2,2):
            raise ValueError('Unexpected native geometry')
        with Image.open(files[expected]) as source:
            image,padding = remove_corner_padding(source)
            if image.size != (2040,1400):
                raise ValueError('The capture must not be resampled')
            target = destination/name
            image.save(target,'WEBP',quality=96,method=6,exact=True)
        manifest.append({
            'file':name,'sha256':digest(target),'width':2040,'height':1400,
            'sourceSize':[2040,1400],'cropBox':[0,0,2040,1400],
            'origin':'Native app window capture','capture':'Window capture without desktop or shadow',
            'captureMethod':record['capture'],'sourceCommit':CAPTURE_COMMIT,
            'sourceWorkflowRun':CAPTURE_RUN,'sourceArtifact':ARTIFACT_ID,
            'sourceArtifactSHA256':ARTIFACT_SHA256,'sourcePNG_SHA256':expected,
            'applicationBuildCommit':BUILD_COMMIT,'applicationSourceTree':source_tree,
            'applicationArchiveSHA256':provenance['applicationArchiveSHA256'],
            'appVersion':'0.1.20','appBuild':23,'bundledEngines':True,
            'logicalWindowSize':[1020,700],'nativeScale':[2,2],
            'upscaled':False,'retinaCapture':False,'highDensityRendered':True,
            'display':'Temporary macOS virtual HiDPI test display; not a physical Retina panel',
            'maxDisplayWidth':510,'syntheticInput':True,
            'processing':f'Window-only crop at original dimensions. Remove {padding} border-connected pure-black exterior corner-padding pixels only; preserve all UI pixels before metadata-free WebP encoding (quality 96). No resize, sharpening, repainting or generated controls.'})
    (destination/'screenshots.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(json.dumps(manifest,indent=2))


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--artifact',type=Path,required=True)
    parser.add_argument('--output',type=Path,default=ROOT/'site/assets')
    args=parser.parse_args()
    export(args.artifact.resolve(),args.output.resolve())
