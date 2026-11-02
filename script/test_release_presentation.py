#!/usr/bin/env python3
"""The release presentation must describe its actual traceable native screens."""
import json
from pathlib import Path
import re
import unittest
ROOT=Path(__file__).resolve().parent.parent

class ReleasePresentationTests(unittest.TestCase):
    def test_pdf_ordering_has_a_real_screen_not_a_decorative_mockup(self):
        page=(ROOT/'site/index.html').read_text()
        gallery=page.split('id="app-gallery"',1)[1].split('</section>',1)[0]
        self.assertEqual(['workspace','pdf-organize','crop-video','trim-audio'],re.findall(r'data-screen="([^"]+)"',gallery))
        self.assertIn('Drag a page into place',gallery)
        self.assertIn('type its position',gallery)
        self.assertNotIn('app-activity.webp',gallery)

    def test_screen_provenance_records_real_density_without_physical_retina_claim(self):
        rows=json.loads((ROOT/'site/assets/screenshots.json').read_text())
        self.assertEqual({'app-workspace.webp','app-pdf-organize.webp','app-crop-video.webp','app-trim-audio.webp'},{r['file'] for r in rows})
        for row in rows:
            self.assertEqual('0.1.20',row['appVersion'])
            self.assertEqual(23,row['appBuild'])
            self.assertEqual([2,2],row['nativeScale'])
            self.assertFalse(row['upscaled'])
            self.assertFalse(row['retinaCapture'])
            self.assertTrue(row['highDensityRendered'])
            self.assertEqual([1020,700],row['logicalWindowSize'])
            self.assertLessEqual(row['maxDisplayWidth'],row['width']/2)
            self.assertRegex(row['applicationSourceTree'],r'^[0-9a-f]{40}$')

    def test_download_and_capture_story_move_together(self):
        page=(ROOT/'site/index.html').read_text()
        self.assertEqual(3,page.count('releases/download/v0.1.20/Lemulip-0.1.20-macOS-universal.dmg'))
        self.assertNotIn('v0.1.19',page)
        self.assertIn('Lemulip 0.1.20. Select an image',page)
        self.assertIn('data-site-version="20261102.1"',page)
        self.assertIn('Put PDF pages in order.',page)
        self.assertIn('releases/tag/v0.1.20',page)

if __name__=='__main__': unittest.main()
