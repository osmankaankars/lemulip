#!/usr/bin/env python3
"""Offline structural checks for the marketing site, without new dependencies."""
import re
import unittest
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
class Tags(HTMLParser):
    def __init__(self):
        super().__init__(); self.ids = []; self.assets = []; self.scripts = []
    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if 'id' in a: self.ids.append(a['id'])
        if tag in ('script', 'img') and 'src' in a: self.assets.append(a['src'])
        if tag == 'link' and a.get('rel') == 'stylesheet': self.assets.append(a['href'])

class SiteTests(unittest.TestCase):
    def test_all_local_assets_exist_and_ids_are_unique(self):
        parser = Tags(); parser.feed((ROOT/'site/index.html').read_text())
        self.assertEqual(len(parser.ids), len(set(parser.ids)))
        for asset in parser.assets:
            if not asset.startswith(('https:', 'data:')):
                self.assertTrue((ROOT/'site'/asset).is_file(), asset)
    def test_hero_and_six_feature_previews_are_present(self):
        page=(ROOT/'site/index.html').read_text()
        self.assertIn('Less File Work.', page)
        self.assertIn('More Flow.', page)
        for name in ('images','pdf','audio','video','documents','archives'):
            self.assertIn('data-feature="'+name+'"', page)
        self.assertIn('id="features"',page)
        self.assertIn('id="showcase-toggle"',page)
    def test_existing_wheel_and_theme_controls_survive(self):
        page=(ROOT/'site/index.html').read_text()
        for name in ('try','demo','wheel-svg','appearance','next-step','announcer'):
            self.assertIn('id="'+name+'"', page)
    def test_motion_can_be_paused_and_reduced(self):
        css=(ROOT/'site/showcase.css').read_text()
        js=(ROOT/'site/showcase.js').read_text()
        self.assertIn('prefers-reduced-motion',css)
        self.assertIn('prefers-reduced-motion',js)
        self.assertIn('visibilitychange',js)
        self.assertIn('IntersectionObserver',js)
        self.assertIn('aria-selected',js)
    def test_simulations_are_labelled_without_uploads(self):
        page=(ROOT/'site/index.html').read_text()
        self.assertIn('Illustrated Demo',page)
        self.assertIn('No Files Uploaded',page)
        self.assertIn('not a recording',page)
        js=(ROOT/'site/showcase.js').read_text()
        self.assertNotRegex(js,r'\b(fetch|XMLHttpRequest|FileReader)\s*\(')
    def test_no_temporary_transfer_files_ship(self):
        self.assertFalse((ROOT/'.github/refresh-payload').exists())
        self.assertFalse((ROOT/'.github/workflows/repository-refresh.yml').exists())
        self.assertFalse((ROOT/'script/migrate_branding.py').exists())

if __name__=='__main__': unittest.main()
