#!/usr/bin/env python3
"""Test the product page and its deployed URL in Chromium or WebKit.

Playwright is a test dependency only. All file operations on the website are
sample state changes; media checks exercise the real bundled sample clip.
"""
from __future__ import annotations
import argparse,functools,http.server,io,json,re,threading
from pathlib import Path
from playwright.sync_api import sync_playwright
ROOT=Path(__file__).resolve().parent.parent
FAMILIES=('images','pdf','audio','video','documents','spreadsheets','presentations','subtitles','archives')
class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self,*args): pass
    def send_head(self):
        # Mirror Pages byte-range support: a plain SimpleHTTP server can reset
        # media seeks to zero even though its initial response decodes correctly.
        path=Path(self.translate_path(self.path))
        if path.suffix!='.mp4' or not path.is_file():return super().send_head()
        raw=path.read_bytes();start=0;end=len(raw)-1;status=200
        value=self.headers.get('Range')
        if value:
            match=re.fullmatch(r'bytes=(\d+)-(\d*)',value)
            if not match:
                self.send_error(416,'Only a single byte range is supported');return None
            start=int(match[1]);end=min(int(match[2]) if match[2] else end,end)
            if start>end:
                self.send_response(416);self.send_header('Content-Range',f'bytes */{len(raw)}');self.end_headers();return None
            status=206
        self.send_response(status);self.send_header('Content-Type','video/mp4')
        self.send_header('Accept-Ranges','bytes');self.send_header('Content-Length',str(end-start+1))
        if status==206:self.send_header('Content-Range',f'bytes {start}-{end}/{len(raw)}')
        self.end_headers();return io.BytesIO(raw[start:end+1])

def exercise(page,output,width,height):
    assert page.locator('html').get_attribute('data-site-version')=='20261021.2'
    assert 'Lemulip' in page.title()
    assert page.locator('#format-count').inner_text()=='35'
    assert page.locator('#tool-count').inner_text()=='26'
    assert page.locator('#action-count').inner_text()=='6'
    if page.locator('#tour-toggle').get_attribute('aria-pressed')=='true':page.locator('#tour-toggle').click()
    # New sample families must change the actual wheel and output, not just a tab.
    expected={'images':'morning-light.png','pdf':'field-notes.png','audio':'voice-note.mp3','video':'morning-walk.mp4','documents':'weekend-notes.pdf','spreadsheets':'inventory.xlsx','presentations':'project-deck.pdf','subtitles':'captions.vtt','archives':'project/'}
    for family in FAMILIES:
        page.locator('#sample-type').select_option(family)
        page.locator('[data-mode="convert"]').click()
        page.locator('.wheel-choice').first.click()
        assert page.locator('#sample-output').is_visible(),family
        assert page.locator('#output-name').inner_text()==expected[family],family
    page.locator('#sample-type').select_option('images')
    page.locator('[data-mode="tools"]').click()
    assert 'Crop' in page.locator('#wheel-svg').text_content()
    page.locator('[data-mode="actions"]').click()
    assert page.locator('.wheel-choice').count()==6
    page.locator('.wheel-choice').filter(has_text='Move To').click()
    assert 'moves' not in page.locator('#output-detail').inner_text() or 'Mac app' in page.locator('#output-detail').inner_text()
    for origin in ('finder','desktop'):
        page.locator('#origin-'+origin).click()
        assert page.locator('#desktop-demo').get_attribute('data-origin')==origin
        page.locator('#desktop-demo').focus();page.keyboard.press('Shift')
        assert page.locator('#floating-wheel').is_visible()
        page.keyboard.press('ArrowRight');page.keyboard.press('Enter')
        assert page.locator('#output-name').inner_text()=='morning-light.jpg'
    page.locator('[data-mode="convert"]').click()
    page.evaluate('document.documentElement.style.scrollBehavior="auto";scrollTo(0,0)')
    page.screenshot(path=str(output/f'home-{width}.png'))
    assert page.evaluate('document.documentElement.scrollWidth<=innerWidth'),f'Overflow {width}'
    for family in FAMILIES:
        page.locator('[data-feature="'+family+'"]').click()
        assert page.locator('#sample-workbench').get_attribute('data-family')==family
        assert page.locator('#feature-panel').get_attribute('aria-labelledby')=='tab-'+family
        page.locator('#run-example').click()
        assert page.locator('#example-output').get_attribute('data-result')==family
        assert page.locator('#example-output').is_visible()
        if family=='video':
            page.wait_for_function('document.querySelector("#sample-video").readyState >= 2')
            duration=page.locator('#sample-video').evaluate('v=>v.duration')
            assert 3.9<=duration<=4.1,duration
            page.locator('#sample-video').evaluate("""v=>{
                window.samplePlayback=[];
                for(const event of ['seeking','seeked','playing','pause','error'])
                    v.addEventListener(event,()=>window.samplePlayback.push({event,time:v.currentTime,ready:v.readyState}));
            }""")
            page.locator('#play-video').click()
            try:
                page.wait_for_function("""() => {
                    const v=document.querySelector('#sample-video');
                    return !v.paused && v.currentTime>1.05 &&
                        window.samplePlayback.some(e=>e.event==='seeked' && e.time>=.95);
                }""",timeout=10000)
            except Exception:
                state=page.locator('#sample-video').evaluate("""v=>({time:v.currentTime,ready:v.readyState,paused:v.paused,error:v.error?.message,seekable:Array.from({length:v.seekable.length},(_,i)=>[v.seekable.start(i),v.seekable.end(i)]),events:window.samplePlayback})""")
                (output/f'video-failure-{width}.json').write_text(json.dumps(state,indent=2))
                raise
            page.locator('#sample-video').evaluate('v=>v.pause()')
        if width in (1440,390):page.locator('#feature-panel').screenshot(path=str(output/f'{family}-{width}.png'))
    # Edited state must be reflected in each corresponding sample result.
    page.locator('#tab-pdf').click();page.locator('#swap-pages').click();page.locator('#rotate-page').click();page.locator('#run-example').click()
    assert '2 → 1 → 3' in page.locator('#example-output').inner_text()
    assert '90°' in page.locator('#example-output').inner_text()
    page.locator('#tab-images').click();page.locator('#crop-inset').fill('25');page.locator('#run-example').click()
    assert '25%' in page.locator('#example-output').inner_text()
    page.locator('#tab-documents').click();page.locator('#note-title').fill('A real sample change');page.locator('#run-example').click()
    assert page.locator('#word-preview h4').inner_text()=='A real sample change'
    page.locator('#tab-spreadsheets').click();page.locator('#table-sample').select_option('1');page.locator('#run-example').click()
    assert '=1+1' in page.locator('#sample-workbench table').inner_text()
    page.locator('#tab-subtitles').click();page.locator('#caption-language').select_option('tr');page.locator('#run-example').click()
    assert 'Günaydın.' in page.locator('#sample-workbench').inner_text()
    page.locator('#tab-archives').click()
    for check in page.locator('[data-archive]').all():check.uncheck()
    assert page.locator('#run-example').is_disabled()
    page.locator('[data-archive="0"]').check();page.locator('#run-example').click()
    assert '1 sample file:' in page.locator('#example-output').inner_text()
    page.locator('#tab-images').focus();page.keyboard.press('ArrowRight')
    assert page.locator('#tab-pdf').get_attribute('aria-selected')=='true'
    page.keyboard.press('End');assert page.locator('#tab-archives').get_attribute('aria-selected')=='true'
    for theme in ('pistachio','lemonade','orchard'):
        page.locator('#appearance').select_option(theme)
        assert page.locator('html').get_attribute('data-theme')==theme
    page.locator('#tab-images').click();page.locator('#features').scroll_into_view_if_needed()
    page.screenshot(path=str(output/f'features-{width}.png'))
    assert page.evaluate('document.documentElement.scrollWidth<=innerWidth'),f'Overflow after edits {width}'
    assert page.evaluate('Array.from(document.images).every(i=>i.complete&&i.naturalWidth>0)')

def run(output:Path,engine:str,url:str|None):
    output.mkdir(parents=True,exist_ok=True);results=[];errors=[];failures=[]
    server=None;thread=None
    if not url:
        handler=functools.partial(QuietHandler,directory=str(ROOT))
        server=http.server.ThreadingHTTPServer(('127.0.0.1',0),handler)
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        url=f'http://127.0.0.1:{server.server_port}/site/'
    try:
        with sync_playwright() as p:
            browser=getattr(p,engine).launch()
            try:
                for width,height in ((1440,1000),(1280,900),(768,1024),(390,844),(320,740)):
                    page=browser.new_page(viewport={'width':width,'height':height})
                    page.on('pageerror',lambda e:errors.append(str(e)))
                    page.on('response',lambda r:failures.append([r.status,r.url]) if r.status>=400 else None)
                    page.goto(url,wait_until='networkidle');exercise(page,output,width,height)
                    results.append({'viewport':f'{width}x{height}','nine_samples':'PASS','wheel':'PASS','edit_results':'PASS','video_decode_and_playback':'PASS','keyboard':'PASS','themes':'PASS','overflow':'NONE'})
                    page.close()
                page=browser.new_page(viewport={'width':1440,'height':1000})
                page.goto(url,wait_until='networkidle')
                page.wait_for_function('document.querySelector("#desktop-demo").dataset.step!=="0"')
                page.locator('#tour-toggle').click();before=page.locator('#desktop-demo').get_attribute('data-step');page.wait_for_timeout(2400)
                assert page.locator('#desktop-demo').get_attribute('data-step')==before
                page.locator('#next-step').click();assert page.locator('#desktop-demo').get_attribute('data-step')!=before
                # A genuine pointer drag and modifier key must submit only on a wheel drop.
                page.locator('#origin-desktop').click();box=page.locator('#sample-file').bounding_box();assert box
                page.mouse.move(box['x']+box['width']/2,box['y']+box['height']/2);page.mouse.down()
                page.mouse.move(box['x']+box['width']/2+25,box['y']+box['height']/2+10,steps=4)
                page.keyboard.press('Shift')
                target=page.locator('.wheel-choice').first.bounding_box();assert target
                page.mouse.move(target['x']+target['width']/2,target['y']+target['height']/4,steps=8);page.mouse.up()
                assert page.locator('#sample-output').is_visible()
                results.append({'autoplay_advances_and_pauses':'PASS','pointer_drag_shift_and_drop':'PASS'});page.close()
                page=browser.new_page(viewport={'width':390,'height':844},reduced_motion='reduce');page.goto(url,wait_until='networkidle')
                assert page.locator('#tour-toggle').get_attribute('aria-pressed')=='false'
                page.locator('#next-step').click();page.locator('#next-step').click()
                assert page.locator('#floating-wheel').is_visible()
                results.append({'reduced_motion_manual_controls':'PASS'});page.close()
                page=browser.new_page(java_script_enabled=False);page.goto(url,wait_until='networkidle')
                assert page.locator('h1').is_visible();assert page.locator('.hero-copy .button').is_visible()
                results.append({'no_javascript_fallback':'PASS'});page.close()
                assert not errors,errors;assert not failures,failures
            finally:browser.close()
    finally:
        if server:server.shutdown();thread.join(timeout=5)
        report={'engine':engine,'url':url,'results':results,'page_errors':errors,'http_failures':failures}
        (output/'browser-results.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output',required=True,type=Path);parser.add_argument('--engine',choices=['chromium','webkit'],default='chromium');parser.add_argument('--url');args=parser.parse_args();run(args.output,args.engine,args.url)
