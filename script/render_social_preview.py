#!/usr/bin/env python3
"""Render a share-card layout using only the reviewed repository artwork.

This exports a marketing composition, not a new native-app capture. Playwright
is a review/build tool and is never included in the site or app download.
"""
import argparse
import hashlib
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import subprocess
import threading

from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parent.parent
ASSETS = (
    'script/social_preview.html',
    'Resources/AppIcon.png',
    'site/assets/app-workspace.webp',
    'site/assets/lemulip-wordmark.svg',
)
ALT = ('Lemulip Workspace with selected files and tools, beside the words '
       'File tools, right where you drag.')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def render(destination):
    destination.mkdir(parents=True, exist_ok=False)
    before = {name: digest(ROOT / name) for name in ASSETS}

    class Handler(SimpleHTTPRequestHandler):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, directory=str(ROOT), **kwargs)

        def do_GET(self):
            if self.path.lstrip('/') not in ASSETS:
                self.send_error(404)
                return
            super().do_GET()

        def do_HEAD(self):
            self.send_error(405)

        def log_message(self, *_):
            pass

    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    base = f'http://127.0.0.1:{server.server_port}'
    try:
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch()
            context = browser.new_context(viewport={'width': 1200, 'height': 630},
                                          device_scale_factor=1)
            blocked = []

            def local_assets_only(route):
                if route.request.url in {base + '/' + name for name in ASSETS}:
                    route.continue_()
                else:
                    blocked.append(route.request.url)
                    route.abort()

            context.route('**/*', local_assets_only)
            page = context.new_page()
            page.goto(base + '/script/social_preview.html', wait_until='load')
            page.evaluate('async () => { await document.fonts.ready; '
                          'await Promise.all([...document.images].map(image => image.decode())); }')
            geometry = page.evaluate('''() => ({
                document: [document.documentElement.scrollWidth, document.documentElement.scrollHeight],
                workspace: (() => { const image = document.querySelector('.workspace');
                    const rect = image.getBoundingClientRect();
                    return {source: [image.naturalWidth, image.naturalHeight],
                            displayed: [rect.width, rect.height]}; })(),
                boxes: [...document.querySelectorAll('.brand, h1, .description, .workspace, .caption, .availability')]
                    .map(element => { const rect = element.getBoundingClientRect();
                        return {name: element.className || element.tagName,
                            x: rect.x, y: rect.y, right: rect.right, bottom: rect.bottom}; })
            })''')
            if geometry['document'] != [1200, 630]:
                raise RuntimeError('Share layout exceeds its 1200 by 630 canvas')
            if geometry['workspace'] != {'source': [1020, 683], 'displayed': [510, 341.5]}:
                raise RuntimeError('The approved native screenshot must keep its aspect and half-size presentation')
            for box in geometry['boxes']:
                if min(box['x'], box['y']) < 0 or box['right'] > 1200 or box['bottom'] > 630:
                    raise RuntimeError('Share-card content extends beyond the canvas')
            if blocked:
                raise RuntimeError('Share-card layout attempted an unapproved resource request')
            image = destination / 'social-preview.png'
            page.screenshot(path=str(image), type='png', animations='disabled')
            # A smaller rendering is review evidence only; the original remains the export.
            page.add_style_tag(content='html, body { width: 600px; height: 315px; } '
                               '.preview { transform: scale(.5); transform-origin: top left; }')
            page.set_viewport_size({'width': 600, 'height': 315})
            page.screenshot(path=str(destination / 'social-preview-small.png'), type='png')
            manifest = {
                'file': image.name, 'width': 1200, 'height': 630,
                'sha256': digest(image), 'alt': ALT,
                'kind': 'Marketing composition using an existing native app capture',
                'renderSourceCommit': subprocess.check_output(
                    ['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                'renderer': {'name': 'Chromium', 'version': browser.version,
                             'deviceScaleFactor': 1, 'canvas': [1200, 630]},
                'sources': [{'file': name, 'sha256': value} for name, value in before.items()],
                'nativeCaptureRecord': 'site/assets/screenshots.json',
                'processing': 'Original native screenshot placed at 510 by 341.5 pixels; '
                              'no generated, repainted, sharpened or enlarged product controls. '
                              'This is not a fresh Retina capture of the pending release.',
            }
            (destination / 'social-preview.json').write_text(json.dumps(manifest, indent=2) + '\n')
            (destination / 'layout-review.json').write_text(json.dumps(geometry, indent=2) + '\n')
            context.close()
            browser.close()
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)
    if before != {name: digest(ROOT / name) for name in ASSETS}:
        raise RuntimeError('A source image or template changed during rendering')
    print(json.dumps({'file': image.name, 'bytes': image.stat().st_size,
                      'sha256': digest(image), 'sourcesUnchanged': True}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    render(parser.parse_args().output.resolve())
