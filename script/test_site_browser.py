#!/usr/bin/env python3
"""Test the product page and its deployed URL in Chromium or WebKit.

Playwright is a test dependency only. All file operations on the website are
sample state changes, not file conversions. The separate opt-in player shows an
actual native Mac recording in the same stage.
"""
from __future__ import annotations
import argparse,functools,http.server,json,threading
from pathlib import Path
from playwright.sync_api import sync_playwright
ROOT=Path(__file__).resolve().parent.parent
FAMILIES=('images','pdf','audio','video','documents','spreadsheets','presentations','subtitles','archives')
class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self,*args): pass

def check_presentation(page,output,width,height):
    if page.locator('#tour-toggle').get_attribute('aria-pressed')=='true':
        page.locator('#tour-toggle').click()
    assert page.locator('#sample-type').count()==0
    assert page.locator('#sample-grid [data-sample]').count()==9
    assert page.locator('.header #appearance').count()==1
    assert page.locator('#appearance').is_visible()
    assert page.locator('.header #appearance').bounding_box()['y']<160
    assert page.locator('h1').evaluate('e=>getComputedStyle(e).textTransform')=='capitalize'
    assert page.locator('.file-name').first.evaluate('e=>getComputedStyle(e).textTransform')=='none'
    assert '\u2014' not in page.locator('body').inner_text()
    assert '\u2013' not in page.locator('body').inner_text()
    for origin in ('desktop','finder'):
        page.locator('#origin-'+origin).click()
        desktop=page.locator('#desktop-demo').bounding_box()
        grid=page.locator('#sample-grid').bounding_box();assert grid
        boxes=[]
        for file in page.locator('#sample-grid [data-sample]').all():
            assert file.is_visible()
            box=file.bounding_box();assert box
            assert box['x']>=desktop['x']-1
            assert box['y']>=desktop['y']+27
            assert box['x']+box['width']<=desktop['x']+desktop['width']+1
            within_grid=(box['y']>=grid['y']-1 and box['y']+box['height']<=grid['y']+grid['height']+1)
            if not within_grid:
                page.locator('#try').screenshot(path=str(output/f'clipping-{origin}-{width}.png'))
            assert within_grid,{'origin':origin,'width':width,'file':file.inner_text(),'file_box':box,'grid_box':grid}
            assert box['y']+box['height']<=desktop['y']+desktop['height']+1
            label=file.locator('.file-name').bounding_box();assert label
            assert label['y']+label['height']<=box['y']+box['height']+1
            boxes.append(box)
        for i,a in enumerate(boxes):
            for b in boxes[i+1:]:
                overlap=min(a['x']+a['width'],b['x']+b['width'])-max(a['x'],b['x'])
                vertical=min(a['y']+a['height'],b['y']+b['height'])-max(a['y'],b['y'])
                assert overlap<=1 or vertical<=1,'Overlapping sample files'
        if width in (1440,390,320):
            page.locator('#try').screenshot(path=str(output/f'gallery-{origin}-{width}.png'))
        # In the same screen, the last file can be selected after an output.
        page.locator('[data-sample="video"]').click()
        page.locator('[data-mode="convert"]').click();page.locator('.wheel-choice').first.click()
        page.locator('[data-sample="documents"]').click()
        assert page.locator('#sample-file').get_attribute('data-sample')=='documents'
        page.locator('[data-mode="convert"]').click();page.locator('.wheel-choice').first.click()
        assert page.locator('#output-name').inner_text()=='weekend-notes.pdf'
    for theme in ('pistachio','lemonade','orchard'):
        page.locator('#appearance').select_option(theme)
        assert page.locator('html').get_attribute('data-theme')==theme
        assert page.evaluate('document.documentElement.scrollWidth<=innerWidth')
        if width==1440:
            page.locator('.shortcuts').screenshot(path=str(output/f'shortcuts-{theme}.png'))
    for paragraph in page.locator('.format-engine .engine-note p').all():
        assert paragraph.evaluate('e=>getComputedStyle(e).display')=='block'
    assert page.locator('.format-engine .engine-note').count()>=14
    colors=page.locator('.shortcut-list > div').evaluate_all('es=>es.map(e=>getComputedStyle(e).backgroundColor)')
    assert len(set(colors))==3
    if width in (1440,390):
        page.locator('#formats').screenshot(path=str(output/f'formats-{width}.png'))
    page.locator('#origin-desktop').click();page.locator('[data-sample="images"]').click()
    page.locator('#desktop-demo').focus();page.keyboard.press('Escape')
    page.evaluate('document.documentElement.style.scrollBehavior="auto";scrollTo(0,0)')
    page.screenshot(path=str(output/f'overview-{width}.png'))



GALLERY_SCREENS = ("workspace", "crop-video", "trim-audio", "activity")


def check_native_gallery(page, output: Path, width: int, height: int) -> None:
    """Exercise the actual gallery DOM, including keyboard and demo isolation."""
    if page.locator("#tour-toggle").get_attribute("aria-pressed") == "true":
        page.locator("#tour-toggle").click()
    gallery = page.locator("#app-gallery")
    gallery.scroll_into_view_if_needed()
    frame = gallery.locator(".app-frame")
    original = frame.bounding_box()
    assert original
    formats_y = page.locator("#formats").evaluate("e=>e.getBoundingClientRect().top+scrollY")
    for index, screen in enumerate(GALLERY_SCREENS):
        tab = page.locator("#tab-" + screen)
        tab.click()
        panel = page.locator("#screen-" + screen)
        assert panel.is_visible(), screen
        assert gallery.locator(".app-slide:visible").count() == 1
        assert tab.get_attribute("aria-selected") == "true"
        assert gallery.locator('[role="tab"][tabindex="0"]').count() == 1
        assert page.locator("#gallery-counter").inner_text() == f"{index + 1} / 4"
        assert page.locator("#gallery-caption").inner_text() == tab.inner_text()
        assert panel.locator("img").evaluate("e=>e.complete&&e.naturalWidth>0")
        corners = panel.locator("img").evaluate("""img => {
            const c = document.createElement('canvas');
            c.width = img.naturalWidth; c.height = img.naturalHeight;
            const ctx = c.getContext('2d'); ctx.drawImage(img, 0, 0);
            return [[0,0],[c.width-1,0],[0,c.height-1],[c.width-1,c.height-1]]
                .map(([x,y]) => ctx.getImageData(x,y,1,1).data[3]);
        }""")
        assert corners == [0, 0, 0, 0], "Only the application window belongs in the gallery"
        box = frame.bounding_box()
        assert box and abs(box["width"] - original["width"]) < 1
        assert abs(box["height"] - original["height"]) < 1
        after = page.locator("#formats").evaluate("e=>e.getBoundingClientRect().top+scrollY")
        assert abs(after - formats_y) < 1, "Gallery selection must not reflow the formats section"
        # The active panel is next in tab order; hidden screenshots cannot receive focus.
        tab.focus()
        page.keyboard.press("Tab")
        assert panel.locator("a").evaluate("e=>e===document.activeElement"), screen
        page.keyboard.press("Shift+Tab")
        assert tab.evaluate("e=>e===document.activeElement")
    page.locator("#gallery-next").click()
    assert page.locator("#screen-workspace").is_visible()
    page.locator("#gallery-previous").click()
    assert page.locator("#screen-activity").is_visible()
    page.locator("#tab-activity").focus()
    for key, screen in (("ArrowRight", "workspace"), ("ArrowLeft", "activity"),
                        ("Home", "workspace"), ("End", "activity")):
        page.keyboard.press(key)
        assert page.locator("#screen-" + screen).is_visible()
        assert page.locator("#tab-" + screen).evaluate("e=>e===document.activeElement")
    for theme in ("pistachio", "lemonade", "orchard"):
        page.locator("#appearance").select_option(theme)
        assert page.locator("html").get_attribute("data-theme") == theme
        assert page.evaluate("document.documentElement.scrollWidth<=innerWidth")
        if width in (1440, 390):
            gallery.screenshot(path=str(output / f"native-gallery-{theme}-{width}.png"))
    page.locator("#origin-finder").click()
    page.locator('[data-sample="images"]').click()
    page.locator('[data-mode="convert"]').click()
    page.locator(".wheel-choice").first.click()
    assert page.locator("#output-name").inner_text() == "morning-light.png"
    page.locator("#tab-workspace").click()
    page.locator("#tab-workspace").press("ArrowRight")
    assert page.locator("#output-name").inner_text() == "morning-light.png"
    assert page.locator("#desktop-demo").get_attribute("data-origin") == "finder"
    assert page.locator(".product-demo").count() == 1


def check_gallery_without_javascript(page) -> None:
    assert page.locator("#screen-workspace").is_visible()
    assert page.locator("#gallery-tabs").is_hidden()
    assert page.locator(".gallery-navigation").is_hidden()
    links = page.locator("#app-gallery noscript a")
    assert links.count() == 4
    for link in links.all():
        assert link.is_visible()
        assert link.get_attribute("href").endswith(".webp")


def check_catalog_search(page):
    search=page.locator('#format-search')
    search.fill('crop')
    assert page.locator('.format-row').count()==2
    assert page.locator('.format-row').all_text_contents()[0].startswith('Images')
    assert page.locator('#tool-directory li').count()==2
    assert page.locator('#format-search-status').inner_text()=='2 File Families · 2 Matching Tools'
    search.fill('EXCEL')
    assert 'Spreadsheets' in page.locator('#format-directory').inner_text()
    search.fill('<script>not-a-format</script>')
    assert page.locator('.format-row').count()==0
    assert 'No Matches' in page.locator('#format-search-status').inner_text()
    assert page.locator('.tool-directory').is_hidden()
    page.locator('#format-search-clear').click()
    assert search.evaluate('e=>document.activeElement===e')
    assert page.locator('.format-row').count()==9
    assert page.locator('#tool-directory li').count()==32
    search.fill('trim');search.press('Escape')
    assert search.input_value()==''
    assert page.locator('.format-row').count()==9
    assert page.locator('#sample-grid [data-sample]').count()==9
    assert page.locator('a[href$="Lemulip-0.1.18-macOS-universal.dmg"]').count()==3


def check_native_recording(page,output,width):
    player=page.locator('#native-video')
    assert player.count()==1
    assert player.evaluate('v=>v.paused')
    assert not player.is_visible()
    assert not player.get_attribute('autoplay')
    assert player.get_attribute('preload')=='none'
    before=page.locator('#features').evaluate('e=>e.getBoundingClientRect().top+scrollY')
    page.locator('#watch-native').click()
    assert player.is_visible()
    assert page.locator('#desktop-demo').evaluate('e=>e.inert')
    assert page.locator('#tour-toggle').get_attribute('aria-pressed')=='false'
    page.wait_for_function('document.getElementById("native-video").currentTime > 0.1')
    assert player.evaluate('v=>v.videoWidth > 0 && v.videoHeight > 0')
    assert abs(page.locator('#features').evaluate('e=>e.getBoundingClientRect().top+scrollY')-before)<1
    if width in (1440,390,320):
        page.locator('#try').screenshot(path=str(output/f'native-recording-{width}.png'))
    page.locator('#origin-finder').click()
    assert player.evaluate('v=>v.paused')
    assert not player.is_visible()
    assert page.locator('#sample-grid [data-sample]:visible').count()==9
    assert not page.locator('#desktop-demo').evaluate('e=>e.inert')
    page.locator('#watch-native').focus();page.keyboard.press('Enter')
    assert player.is_visible()
    player.focus();page.keyboard.press('Escape')
    assert not player.is_visible()
    assert page.locator('#watch-native').evaluate('e=>e===document.activeElement')


def exercise(page,output,width,height):
    assert page.locator('html').get_attribute('data-site-version')=='20261028.3'
    assert 'Lemulip' in page.title()
    assert page.locator('#format-count').inner_text()=='35'
    assert page.locator('#tool-count').inner_text()=='26'
    assert page.locator('#action-count').inner_text()=='6'
    if page.locator('#tour-toggle').get_attribute('aria-pressed')=='true':page.locator('#tour-toggle').click()
    # New sample families must change the actual wheel and output, not just a tab.
    expected={'images':'morning-light.png','pdf':'field-notes.png','audio':'voice-note.mp3','video':'morning-walk.mp4','documents':'weekend-notes.pdf','spreadsheets':'inventory.xlsx','presentations':'project-deck.pdf','subtitles':'captions.vtt','archives':'project/'}
    for family in FAMILIES:
        page.locator('[data-sample="'+family+'"]').click()
        page.locator('[data-mode="convert"]').click()
        page.locator('.wheel-choice').first.click()
        assert page.locator('#sample-output').is_visible(),family
        assert page.locator('#output-name').inner_text()==expected[family],family
    page.locator('[data-sample="images"]').click()
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
    # Results never reflow the content below the only demo.
    before=page.locator('#features').evaluate('e=>e.getBoundingClientRect().top+scrollY')
    for family in FAMILIES:
        page.locator('[data-sample="'+family+'"]').click()
        page.locator('[data-mode="convert"]').click()
        page.locator('.wheel-choice').first.click()
        after=page.locator('#features').evaluate('e=>e.getBoundingClientRect().top+scrollY')
        assert abs(after-before)<1,(family,before,after)
    for removed in ('#feature-panel','#run-example','#origin-workspace','.header .github-link'):
        assert page.locator(removed).count()==0,removed
    assert page.locator('.product-demo').count()==1
    check_native_recording(page,output,width)
    for target in ('features','formats'):
        page.locator('.header a[href="#'+target+'"]').click()
        assert page.url.endswith('#'+target)
        assert page.locator('#'+target).is_visible()
    assert 'Not every input' not in page.locator('body').inner_text()
    assert '35 conversion targets' not in page.locator('body').inner_text()
    for theme in ('pistachio','lemonade','orchard'):
        page.locator('#appearance').select_option(theme)
        assert page.locator('html').get_attribute('data-theme')==theme
    page.locator('#features').scroll_into_view_if_needed()
    page.screenshot(path=str(output/f'features-{width}.png'))
    assert page.evaluate('document.documentElement.scrollWidth<=innerWidth'),f'Overflow after navigation {width}'
    assert page.evaluate('Array.from(document.images).every(i=>i.complete&&i.naturalWidth>0)')
    page.locator('#origin-desktop').click();page.evaluate('scrollTo(0,0)')
    if width in (1440,390):page.screenshot(path=str(output/f'page-{width}.png'),full_page=True)

def run(output:Path,engine:str,url:str|None,executable:str|None=None):
    output.mkdir(parents=True,exist_ok=True);results=[];errors=[];failures=[]
    server=None;thread=None
    if not url:
        handler=functools.partial(QuietHandler,directory=str(ROOT))
        server=http.server.ThreadingHTTPServer(('127.0.0.1',0),handler)
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        url=f'http://127.0.0.1:{server.server_port}/site/'
    try:
        with sync_playwright() as p:
            browser=getattr(p,engine).launch(**({'executable_path':executable} if executable else {}))
            try:
                for width,height in ((1440,1000),(1280,900),(768,1024),(390,844),(320,740)):
                    page=browser.new_page(viewport={'width':width,'height':height})
                    page.on('pageerror',lambda e:errors.append(str(e)))
                    page.on('response',lambda r:failures.append([r.status,r.url]) if r.status>=400 else None)
                    page.goto(url,wait_until='networkidle');check_presentation(page,output,width,height);exercise(page,output,width,height);check_native_gallery(page,output,width,height);check_catalog_search(page)
                    results.append({'viewport':f'{width}x{height}','nine_samples':'PASS','wheel':'PASS','single_demo':'PASS','stable_layout':'PASS','keyboard':'PASS','native_gallery_click_keys_focus_wrap':'PASS','themes':'PASS','local_catalog_search':'PASS','reviewed_direct_download':'PASS','overflow':'NONE'})
                    page.close()
                page=browser.new_page(viewport={'width':1440,'height':1000})
                page.goto(url,wait_until='networkidle')
                page.wait_for_function('document.querySelector("#desktop-demo").dataset.step!=="0"')
                page.locator('#tour-toggle').click();before=page.locator('#desktop-demo').get_attribute('data-step');page.wait_for_timeout(2400)
                assert page.locator('#desktop-demo').get_attribute('data-step')==before
                page.locator('#tab-trim-audio').click();page.wait_for_timeout(2600)
                assert page.locator('#screen-trim-audio').is_visible(),'The gallery must never autoplay'
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
                check_gallery_without_javascript(page)
                results.append({'no_javascript_fallback':'PASS','native_gallery_fallback':'PASS'});page.close()
                assert not errors,errors;assert not failures,failures
            finally:browser.close()
    finally:
        if server:server.shutdown();thread.join(timeout=5)
        report={'engine':engine,'url':url,'results':results,'page_errors':errors,'http_failures':failures}
        (output/'browser-results.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output',required=True,type=Path);parser.add_argument('--engine',choices=['chromium','webkit'],default='chromium');parser.add_argument('--url');parser.add_argument('--executable');args=parser.parse_args();run(args.output,args.engine,args.url,args.executable)
