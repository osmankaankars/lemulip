#!/usr/bin/env python3
"""Source-backed checks for the product page; no network or extra packages."""
import json, re, unittest
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit
ROOT=Path(__file__).resolve().parent.parent
class Tags(HTMLParser):
    def __init__(self): super().__init__(); self.ids=[]; self.assets=[]
    def handle_starttag(self,tag,attrs):
        a=dict(attrs)
        if 'id' in a:self.ids.append(a['id'])
        if tag in ('img','script') and 'src' in a:self.assets.append(a['src'])
        if tag=='link' and a.get('rel')=='stylesheet':self.assets.append(a['href'])
class SiteTests(unittest.TestCase):
    def test_assets_and_unique_ids(self):
        parser=Tags();parser.feed((ROOT/'site/index.html').read_text())
        self.assertEqual(len(parser.ids),len(set(parser.ids)))
        for asset in parser.assets:
            if not asset.startswith(('http','data:')):self.assertTrue((ROOT/'site'/urlsplit(asset).path).is_file(),asset)
    def test_desktop_demo_has_nine_samples_and_real_controls(self):
        page=(ROOT/'site/index.html').read_text()
        for name in ('desktop-demo','sample-type','origin-desktop','origin-finder','tour-toggle','next-step','wheel-svg','sample-file'):
            self.assertIn('id="'+name+'"',page)
        for name in ('images','pdf','audio','video','documents','spreadsheets','presentations','subtitles','archives'):
            self.assertIn('data-feature="'+name+'"',page)
        self.assertIn('<button id="run-example"',page)
        self.assertNotIn('class="copy-label"',page)
    def test_counts_come_from_native_catalog_not_format_pairs(self):
        source=(ROOT/'Sources/LemulipCore/Catalog.swift').read_text()
        formats=sorted(set(x for a in re.findall(r'extensions = \[([^\]]+)\]',source) for x in re.findall(r'"([^"]+)"',a)))
        ids=set(re.findall(r'op\("([^"]+)"',source))
        data=json.loads((ROOT/'site/catalog.js').read_text().split(' = ',1)[1].strip().removesuffix(';'))
        self.assertEqual(formats,data['conversionFormats'])
        self.assertEqual(26,len(ids-{x for x in ids if x.startswith('action.')}))
        self.assertEqual(35,data['counts']['formats']);self.assertEqual(26,data['counts']['tools']);self.assertEqual(6,data['counts']['actions'])
        self.assertEqual(9,len(data['samples']))
        self.assertEqual(ids,set(data['operationIDs']))
    def test_product_preview_is_compact_and_not_a_site_snapshot(self):
        page=(ROOT/'README.md').read_text()
        self.assertIn('width="720"',page)
        self.assertIn('docs/assets/demo-preview.png',page)
        self.assertIn('Illustrated product preview',page)
        self.assertNotIn('Lemulip website showing',page)
    def test_documentation_does_not_expose_removed_roadmap_gates(self):
        roadmap=(ROOT/'docs/ROADMAP.md').read_text()
        for removed in ('Office Review','Mac Interaction and Accessibility','Lightweight Performance','Signed Distribution'):
            self.assertNotIn(removed,roadmap)
        for p in [ROOT/'README.md',*(ROOT/'docs').glob('*.md')]:
            self.assertNotRegex(p.read_text(),r'(?i)developer id|notariz|ad hoc sign',str(p))
    def test_motion_and_stale_assets_are_explicit(self):
        page=(ROOT/'site/index.html').read_text(); js=(ROOT/'site/product.js').read_text()
        self.assertIn('data-site-version="20261021.2"',page)
        self.assertIn('product.js?v=20261021.2',page)
        for event in ('visibilitychange','prefers-reduced-motion','pointercancel'):self.assertIn(event,js)
        self.assertIn('Browser simulation',page)
        self.assertNotRegex(js,r'\b(FileReader|XMLHttpRequest)\s*\(')
    def test_no_temporary_import_workflows(self):
        self.assertFalse((ROOT/'.github/workflows/inspect-live-site.yml').exists())
        self.assertFalse((ROOT/'.github/refresh-payload').exists())
if __name__=='__main__':unittest.main()
