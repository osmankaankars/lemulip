#!/usr/bin/env python3
"""Browser regressions and review images for the illustrative product website.

Requires Playwright and its Chromium browser; neither is an app dependency.
Usage: python3 script/test_site_browser.py --output <temporary-review-folder>
"""
from __future__ import annotations
import argparse
import functools
import http.server
import json
import threading
from pathlib import Path
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parent.parent
FEATURES = ('images', 'pdf', 'audio', 'video', 'documents', 'archives')

class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

def run(output: Path) -> None:
    output.mkdir(parents=True, exist_ok=True)
    errors: list[str] = []
    results: list[dict] = []
    handler = functools.partial(QuietHandler, directory=str(ROOT))
    with http.server.ThreadingHTTPServer(('127.0.0.1', 0), handler) as server:
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        url = f'http://127.0.0.1:{server.server_port}/site/'
        try:
            with sync_playwright() as playwright:
                browser = playwright.chromium.launch()
                try:
                    for width, height in ((1536,1024), (1280,900), (768,1024), (390,844), (320,740)):
                        page = browser.new_page(viewport={'width':width,'height':height}, device_scale_factor=1)
                        page.on('pageerror', lambda error: errors.append(str(error)))
                        page.goto(url, wait_until='networkidle')
                        assert 'Lemulip' in page.title()
                        assert page.locator('h1').inner_text() == 'Less File Work.\nMore Flow.'
                        # Freeze only illustrations to capture an inspectable, repeatable state.
                        page.evaluate('document.documentElement.dataset.staticPreview="true"')
                        page.screenshot(path=str(output/f'home-{width}.png'))
                        assert page.evaluate('document.documentElement.scrollWidth <= innerWidth'), f'Overflow: {width}'
                        page.locator('#features').scroll_into_view_if_needed()
                        for feature in FEATURES:
                            tab = page.locator(f'[data-feature="{feature}"]')
                            tab.click()
                            assert tab.get_attribute('aria-selected') == 'true'
                            assert page.locator('#feature-canvas').get_attribute('data-scene') == feature
                            assert page.locator('#feature-panel').get_attribute('aria-labelledby') == tab.get_attribute('id')
                            if width in (1536,390):
                                page.locator('#feature-panel').screenshot(path=str(output/f'{feature}-{width}.png'))
                        page.locator('[data-feature="images"]').click()
                        page.locator('#features').scroll_into_view_if_needed()
                        page.screenshot(path=str(output/f'features-{width}.png'))
                        page.locator('#tab-images').focus()
                        page.keyboard.press('ArrowRight')
                        assert page.locator('#tab-pdf').get_attribute('aria-selected') == 'true'
                        page.keyboard.press('End')
                        assert page.locator('#tab-archives').get_attribute('aria-selected') == 'true'
                        page.locator('#feature-toggle').click()
                        assert page.locator('html').get_attribute('data-motion') == 'paused'
                        page.locator('#feature-toggle').click()
                        assert page.locator('html').get_attribute('data-motion') == 'playing'
                        for _ in range(3):
                            page.locator('#next-step').click()
                        page.wait_for_function('document.querySelector("#demo").dataset.phase === "done"')
                        assert page.locator('#result-filename').inner_text() == 'morning-light.png'
                        page.locator('#appearance').select_option('pistachio')
                        assert page.locator('html').get_attribute('data-theme') == 'pistachio'
                        page.locator('#appearance').select_option('orchard')
                        assert page.evaluate('Array.from(document.images).every(i=>i.complete && i.naturalWidth>0)')
                        results.append({'viewport':f'{width}x{height}', 'tabs':'PASS', 'keyboard':'PASS', 'pause':'PASS', 'wheel':'PASS', 'theme':'PASS', 'overflow':'NONE'})
                        page.close()
                    page = browser.new_page(viewport={'width':1280,'height':900}, reduced_motion='reduce')
                    page.goto(url, wait_until='networkidle')
                    assert page.locator('html').get_attribute('data-motion') == 'paused'
                    assert page.locator('#showcase-toggle').is_disabled()
                    assert page.locator('.flow-input').evaluate('e=>getComputedStyle(e).animationName') == 'none'
                    results.append({'reduced_motion':'PASS'})
                    page.close()
                    page = browser.new_page(viewport={'width':1280,'height':900}, java_script_enabled=False)
                    page.goto(url, wait_until='networkidle')
                    assert page.locator('h1').is_visible()
                    assert page.locator('.showcase-actions a').first.is_visible()
                    results.append({'no_javascript_fallback':'PASS'})
                    page.close()
                    # Prove motion runs, and pause actually freezes it (not just its label).
                    page = browser.new_page(viewport={'width':1536,'height':1024})
                    page.goto(url, wait_until='networkidle')
                    page.wait_for_function('document.querySelector("#flow-demo").classList.contains("is-visible")')
                    assert page.locator('.flow-input').evaluate('e=>getComputedStyle(e).animationName') != 'none'
                    before = page.locator('.flow-input').evaluate('e=>e.getAnimations()[0].currentTime')
                    page.wait_for_timeout(350)
                    after = page.locator('.flow-input').evaluate('e=>e.getAnimations()[0].currentTime')
                    assert after > before
                    page.locator('#showcase-toggle').click()
                    page.wait_for_timeout(100)
                    before = page.locator('.flow-input').evaluate('e=>e.getAnimations()[0].currentTime')
                    page.wait_for_timeout(250)
                    after = page.locator('.flow-input').evaluate('e=>e.getAnimations()[0].currentTime')
                    assert abs(after-before) < 2
                    results.append({'animation_runs_and_freezes':'PASS'})
                    page.close()
                    assert not errors, errors
                finally:
                    browser.close()
        finally:
            server.shutdown()
            thread.join(timeout=5)
            report = {'results':results, 'page_errors':errors}
            (output/'browser-results.json').write_text(json.dumps(report, indent=2)+'\n')
            print(json.dumps(report, indent=2))

if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    run(parser.parse_args().output)
