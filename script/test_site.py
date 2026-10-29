#!/usr/bin/env python3
"""Source-backed checks for the product page; no network or extra packages."""
import json, re, unittest, subprocess, tempfile
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit
ROOT=Path(__file__).resolve().parent.parent
# Advance only after verifying the new public release and both Mac downloads.
# Never derive this from the pending application's Resources/Info.plist.
PUBLISHED_VERSION='0.1.19'
class Tags(HTMLParser):
    def __init__(self): super().__init__(); self.ids=[]; self.assets=[]
    def handle_starttag(self,tag,attrs):
        a=dict(attrs)
        if 'id' in a:self.ids.append(a['id'])
        if tag in ('img','script','source') and 'src' in a:self.assets.append(a['src'])
        if tag=='link' and a.get('rel')=='stylesheet':self.assets.append(a['href'])
        if tag=='video' and 'poster' in a:self.assets.append(a['poster'])
class SiteTests(unittest.TestCase):
    def test_assets_and_unique_ids(self):
        parser=Tags();parser.feed((ROOT/'site/index.html').read_text())
        self.assertEqual(len(parser.ids),len(set(parser.ids)))
        for asset in parser.assets:
            if not asset.startswith(('http','data:')):self.assertTrue((ROOT/'site'/urlsplit(asset).path).is_file(),asset)
    def test_desktop_demo_has_nine_samples_and_real_controls(self):
        page=(ROOT/'site/index.html').read_text()
        for name in ('desktop-demo','sample-grid','origin-desktop','origin-finder','tour-toggle','next-step','wheel-svg','sample-file'):
            self.assertIn('id="'+name+'"',page)
        for name in ('images','pdf','audio','video','documents','spreadsheets','presentations','subtitles','archives'):
            self.assertIn('data-sample="'+name+'"',page)
        self.assertNotIn('id="run-example"',page)
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
    def test_format_search_is_local_accessible_and_clearable(self):
        page=(ROOT/'site/index.html').read_text()
        for marker in ('id="format-search"','id="format-search-clear"','id="format-search-status"','aria-controls="format-directory tool-directory"'):
            self.assertIn(marker,page)
        self.assertTrue((ROOT/'site/catalog-search.js').is_file())
        js=(ROOT/'site/catalog-search.js').read_text()
        self.assertNotRegex(js,r'fetch\s*\(|XMLHttpRequest|FileReader|localStorage')
        subprocess.run(['node',str(ROOT/'script/test_catalog_search.js')],check=True,cwd=ROOT)

    def test_primary_downloads_use_reviewed_release_not_release_listing(self):
        page=(ROOT/'site/index.html').read_text()
        expected=f'https://github.com/osmankaankars/lemulip/releases/download/v{PUBLISHED_VERSION}/Lemulip-{PUBLISHED_VERSION}-macOS-universal.dmg'
        self.assertEqual(3,page.count('href="'+expected+'"'))
        self.assertIn('Release Notes',page)
        self.assertIn('Apple Silicon &amp; Intel · v'+PUBLISHED_VERSION,page)
        self.assertNotIn('v0.1.17',page)
        self.assertIn('data-step=',page)

    def test_release_metadata_changes_run_website_checks(self):
        workflow=(ROOT/'.github/workflows/site-review.yml').read_text()
        # Both push and pull_request filters must cover staged releases.
        filters=re.findall(r'^    paths: (.+)$',workflow,re.M)
        self.assertEqual(2,len(filters))
        for paths in filters:
            self.assertIn("'Resources/Info.plist'",paths)
            self.assertIn("'docs/RELEASE_NOTES.md'",paths)

    def test_native_recording_shares_the_single_stage_and_requires_a_click(self):
        page=(ROOT/'site/index.html').read_text()
        for marker in ('id="watch-native"', 'id="demo-stage"', 'id="native-recording"',
                       'id="native-video"', 'id="demo-controls"', 'id="demo-source"'):
            self.assertIn(marker,page)
        self.assertEqual(1,page.count('<video '))
        video=page.split('<video ',1)[1].split('>',1)[0]
        self.assertIn('controls',video)
        self.assertIn('playsinline',video)
        self.assertIn('preload="none"',video)
        self.assertNotRegex(video,r'\bautoplay\b|\bloop\b')
        self.assertIn('lemulip:watch-native',(ROOT/'site/product.js').read_text())
        self.assertEqual(1,page.count('class="product-demo"'))
        subprocess.run(['node',str(ROOT/'script/test_demo_view.js')],check=True,cwd=ROOT)

    def test_product_preview_is_compact_and_not_a_site_snapshot(self):
        page=(ROOT/'README.md').read_text()
        self.assertIn('width="720"',page)
        self.assertIn('site/assets/app-workspace.webp',page)
        self.assertIn('Native macOS app',page)
        self.assertNotIn('Illustrated product preview',page)
        self.assertNotIn('Lemulip website showing',page)
    def test_native_gallery_order_structure_and_no_autoplay(self):
        page=(ROOT/'site/index.html').read_text()
        self.assertIn('id="app-gallery"',page)
        self.assertLess(page.index('id="features"'),page.index('id="app-gallery"'))
        self.assertLess(page.index('id="app-gallery"'),page.index('id="formats"'))
        gallery=page.split('id="app-gallery"',1)[1].split('</section>',1)[0]
        self.assertEqual(['workspace','crop-video','trim-audio','activity'],re.findall(r'data-screen="([^"]+)"',gallery))
        self.assertEqual(4,gallery.count('role="tabpanel"'))
        self.assertEqual(4,gallery.count('role="tab"'))
        self.assertIn('<noscript>',gallery)
        js=(ROOT/'site/gallery.js').read_text()
        self.assertNotRegex(js,r'setInterval|setTimeout|requestAnimationFrame')
        self.assertNotRegex(js,r'fetch\s*\(|XMLHttpRequest|FileReader')
        for key in ('ArrowRight','ArrowLeft','Home','End'):self.assertIn(key,js)
        self.assertEqual(1,page.count('class="product-demo"'))
    def test_native_gallery_assets_have_reviewed_hashes(self):
        import hashlib,struct
        manifest=ROOT/'site/assets/screenshots.json'
        self.assertTrue(manifest.is_file(),'Missing native screenshot inventory')
        records=json.loads(manifest.read_text())
        self.assertEqual(4,len(records))
        for row in records:
            data=(ROOT/'site/assets'/row['file']).read_bytes()
            self.assertEqual(row['sha256'],hashlib.sha256(data).hexdigest())
            self.assertEqual(b'RIFF',data[:4]);self.assertEqual(b'WEBP',data[8:12])
            self.assertEqual(len(data),struct.unpack('<I',data[4:8])[0]+8)
            self.assertIn(row['origin'], ('User-provided native app screenshot', 'Native app window capture'))
            if row['origin'] == 'Native app window capture':
                self.assertRegex(row['sourceCommit'], r'^[0-9a-f]{40}$')
                self.assertGreater(row['sourceWorkflowRun'], 0)
                self.assertEqual('Window capture without desktop or shadow', row['capture'])
            self.assertNotIn(b'EXIF',data);self.assertNotIn(b'XMP ',data)
    def test_documentation_does_not_expose_removed_roadmap_gates(self):
        roadmap=(ROOT/'docs/ROADMAP.md').read_text()
        for removed in ('Office Review','Mac Interaction and Accessibility','Lightweight Performance','Signed Distribution'):
            self.assertNotIn(removed,roadmap)
        for p in [ROOT/'README.md',*(ROOT/'docs').glob('*.md')]:
            self.assertNotRegex(p.read_text(),r'(?i)developer id|notariz|ad hoc sign',str(p))
    def test_motion_and_stale_assets_are_explicit(self):
        page=(ROOT/'site/index.html').read_text(); js=(ROOT/'site/product.js').read_text()
        self.assertIn('data-site-version="20261029.1"',page)
        self.assertIn('product.js?v=20261029.1',page)
        for event in ('visibilitychange','prefers-reduced-motion','pointercancel'):self.assertIn(event,js)
        self.assertIn('Browser Simulation',page)
        self.assertNotRegex(js,r'\b(FileReader|XMLHttpRequest)\s*\(')
    def test_no_temporary_import_workflows(self):
        self.assertFalse((ROOT/'.github/workflows/inspect-live-site.yml').exists())
        self.assertFalse((ROOT/'.github/refresh-payload').exists())
    def test_single_demo_and_navigation(self):
        page=(ROOT/'site/index.html').read_text()
        js=(ROOT/'site/product.js').read_text()
        for removed in ('feature-panel','run-example','origin-workspace','workspace-window','sample-video'):
            self.assertNotIn(removed,page)
        for removed in ('workspace-status','const features=','AudioContext','sample-video'):
            self.assertNotIn(removed,js)
        header=page.split('<header',1)[1].split('</header>',1)[0]
        self.assertIn('id="appearance"',header)
        self.assertIn('href="#features"',header);self.assertIn('href="#formats"',header)
        self.assertNotIn('class="github-link"',header)
        self.assertIn('id="features"',page)
        self.assertNotIn('35 conversion targets',page)
        self.assertNotIn('Not every input',page)
        self.assertFalse((ROOT/'site/assets/sample-walk.mp4').exists())
        self.assertFalse((ROOT/'site/presentation.css').exists())
    def test_copy_and_format_notes(self):
        page=(ROOT/'site/index.html').read_text();js=(ROOT/'site/product.js').read_text()
        for text in (page,js):self.assertNotRegex(text,r'[\u2013\u2014]')
        for name in ('shortcut-convert','shortcut-tools','shortcut-actions'):self.assertIn(name,page)
        self.assertIn('class="engine-note"',js)
        self.assertIn('ImageMagick',js)
        self.assertEqual(9,len(re.findall(r'data-sample="',page)))
    def test_published_media_and_image_engines_are_included(self):
        data=json.loads((ROOT/'site/catalog.js').read_text().split(' = ',1)[1].strip().removesuffix(';'))
        self.assertEqual(PUBLISHED_VERSION,data['version'])
        js=(ROOT/'site/product.js').read_text()
        for sample in ('images','audio','video'):
            line=next(line for line in js.splitlines() if line.strip().startswith(sample+':['))
            self.assertIn("['Included',",line)
            self.assertNotIn("['Optional',",line)
        for sample in ('documents','spreadsheets','presentations'):
            line=next(line for line in js.splitlines() if line.strip().startswith(sample+':['))
            self.assertIn("['Optional',",line)

    def test_readme_is_one_product_summary(self):
        readme=(ROOT/'README.md').read_text()
        self.assertLess(len(readme.split()),450)
        self.assertEqual(1,len(re.findall(r'https://osmankaankars\.github\.io/lemulip/[^)"\s]*',readme)))
        self.assertEqual(1,readme.lower().count('open-source'))
        for required in ('THIRD_PARTY_NOTICES.md','LICENSE','SECURITY.md','FFmpeg','LibreOffice','Pandoc','ImageMagick'):
            self.assertIn(required,readme)
    def test_document_links_and_fragments_resolve(self):
        for source in [*ROOT.glob('*.md'),*(ROOT/'docs').glob('*.md')]:
            text=source.read_text()
            for href in re.findall(r'\[[^\]]*\]\(([^)]+)\)',text):
                parts=urlsplit(href.split(' "',1)[0])
                if parts.scheme or parts.netloc:continue
                target=(source.parent/parts.path).resolve() if parts.path else source
                self.assertTrue(target.exists(),f'{source.name}: {href}')
                if parts.fragment and target.suffix=='.md':
                    headings=re.findall(r'^#{1,6}\s+(.+)$',target.read_text(),re.M)
                    slugs={re.sub(r'[^\w\- ]','',h.lower()).replace(' ','-') for h in headings}
                    self.assertIn(parts.fragment,slugs,f'{source.name}: {href}')
    def test_packaged_guides_match_current_tree(self):
        script=(ROOT/'script/package_release.sh').read_text()
        functions=script[script.index('copy_public_guides()'):script.index('if [[ "${1:-}" == --verify')]
        with tempfile.TemporaryDirectory(prefix='lemulip-guides-') as folder:
            run=subprocess.run(['bash','-s','--',folder],input='set -eu\n'+functions+'\ncopy_public_guides "$1"\nverify_public_guides "$1"\n',cwd=ROOT,text=True,capture_output=True)
            self.assertEqual(0,run.returncode,run.stderr)
            readme=(Path(folder)/'README.md').read_text()
            for href in re.findall(r'\[[^\]]*\]\(([^)]+)\)',readme):
                self.assertTrue((Path(folder)/href).exists(),href)
            for name in ('LICENSE','THIRD_PARTY_NOTICES.md','SECURITY.md'):
                self.assertEqual((ROOT/name).read_bytes(),(Path(folder)/name).read_bytes())
if __name__=='__main__':unittest.main()
