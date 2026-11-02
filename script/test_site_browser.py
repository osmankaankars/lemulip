#!/usr/bin/env python3
"""Test the product page and its deployed URL in Chromium or WebKit.

Playwright is a test dependency only. All file operations on the website are
sample state changes, not file conversions. The separate opt-in player shows an
actual native Mac recording in the same stage.
"""
from __future__ import annotations
import argparse,functools,hashlib,http.server,json,tempfile,threading
from pathlib import Path
from urllib.parse import urljoin
from playwright.sync_api import sync_playwright
from prepare_site import prepare_site, SHARE_ALT, SHARE_FILE
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
    assert page.locator('h1').evaluate('e=>getComputedStyle(e).textTransform')=='none'
    assert page.locator('.file-name').first.evaluate('e=>getComputedStyle(e).textTransform')=='none'
    assert '\u2014' not in page.locator('body').inner_text()
    assert '\u2013' not in page.locator('body').inner_text()
    for origin in ('desktop','finder'):
        page.locator('#origin-'+origin).click()
        # Smooth scrolling can change viewport offsets between separate calls.
        # Take the container, file and label bounds from the same rendered frame.
        geometry=page.locator('#desktop-demo').evaluate('''desktop => {
            const rect=e=>{const {x,y,width,height}=e.getBoundingClientRect();return {x,y,width,height}};
            const grid=desktop.querySelector('#sample-grid');
            return {desktop:rect(desktop),grid:rect(grid),files:[...grid.querySelectorAll('[data-sample]')].map(file=>({
                text:file.innerText,box:rect(file),label:rect(file.querySelector('.file-name')),
                visibility:getComputedStyle(file).visibility
            }))};
        }''')
        desktop=geometry['desktop'];grid=geometry['grid']
        boxes=[]
        for file in geometry['files']:
            box=file['box'];assert box['width']>0 and box['height']>0
            assert file['visibility']=='visible'
            assert box['x']>=desktop['x']-1
            assert box['y']>=desktop['y']+27
            assert box['x']+box['width']<=desktop['x']+desktop['width']+1
            within_grid=(box['y']>=grid['y']-1 and box['y']+box['height']<=grid['y']+grid['height']+1)
            if not within_grid:
                page.locator('#try').screenshot(path=str(output/f'clipping-{origin}-{width}.png'))
            assert within_grid,{'origin':origin,'width':width,'file':file['text'],'file_box':box,'grid_box':grid}
            assert box['y']+box['height']<=desktop['y']+desktop['height']+1
            label=file['label'];assert label['width']>0 and label['height']>0
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
    colors=page.locator('.shortcut-list kbd').evaluate_all('es=>es.map(e=>getComputedStyle(e).backgroundColor)')
    assert len(colors)==3
    assert len(set(colors))==3
    if width in (1440,390):
        page.locator('#formats').screenshot(path=str(output/f'formats-{width}.png'))
    page.locator('#origin-desktop').click();page.locator('[data-sample="images"]').click()
    page.locator('#desktop-demo').focus();page.keyboard.press('Escape')
    page.evaluate('document.documentElement.style.scrollBehavior="auto";scrollTo(0,0)')
    page.screenshot(path=str(output/f'overview-{width}.png'))



GALLERY_SCREENS = ("workspace", "pdf-organize", "crop-video", "trim-audio")


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
        assert page.locator("#gallery-caption-title").inner_text() == tab.get_attribute("data-title")
        assert page.locator("#gallery-description").inner_text() == tab.get_attribute("data-description")
        assert panel.locator("img").evaluate("e=>e.complete&&e.naturalWidth>0")
        assert panel.locator("img").evaluate("e=>e.getBoundingClientRect().width<=e.naturalWidth/2+1"), "Native captures need at least 2 source pixels per CSS pixel"
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
    page.locator("#tab-trim-audio").focus()
    for key, screen in (("ArrowRight", "workspace"), ("ArrowLeft", "trim-audio"),
                        ("Home", "workspace"), ("End", "trim-audio")):
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


def check_wheel_keyboard_feedback(page) -> None:
    """Redrawing a wheel must preserve the focused choice, including wrapping."""
    page.locator('#origin-desktop').click()
    page.locator('[data-sample="images"]').click()
    page.locator('[data-mode="convert"]').click()
    active = page.locator('.wheel-choice[tabindex="0"]')
    assert active.count() == 1
    active.focus()
    page.keyboard.press('ArrowRight')
    active = page.locator('.wheel-choice[tabindex="0"]')
    assert active.get_attribute('data-index') == '1'
    assert active.get_attribute('aria-pressed') == 'true'
    assert active.evaluate('e=>e===document.activeElement')
    assert page.locator('#tour-toggle').get_attribute('aria-pressed') == 'false'
    # Keyboard mode switches replace the SVG nodes just like arrow movement.
    page.keyboard.press('Control')
    assert page.locator('[data-mode="actions"]').get_attribute('aria-pressed') == 'true'
    assert page.locator('.wheel-choice[tabindex="0"]').evaluate('e=>e===document.activeElement')
    page.keyboard.press('Shift')
    assert page.locator('[data-mode="convert"]').get_attribute('aria-pressed') == 'true'
    assert page.locator('.wheel-choice[tabindex="0"]').evaluate('e=>e===document.activeElement')
    page.keyboard.press('Shift+Tab')
    assert page.evaluate('document.activeElement!==document.body'), 'Backward Tab must not lose focus during modifier handling'
    page.locator('.wheel-choice[tabindex="0"]').focus()
    page.keyboard.press('ArrowRight')
    page.keyboard.press('Enter')
    assert page.locator('#output-name').inner_text() == 'morning-light.jpg'
    assert page.locator('#sample-file').evaluate('e=>e===document.activeElement')
    page.locator('[data-mode="convert"]').click()
    page.locator('.wheel-choice[tabindex="0"]').focus()
    page.keyboard.press('ArrowLeft')
    active = page.locator('.wheel-choice[tabindex="0"]')
    assert active.text_content() == 'PDF'
    assert active.evaluate('e=>e===document.activeElement')
    page.keyboard.press('Escape')
    assert page.locator('#floating-wheel').is_hidden()
    assert page.locator('#sample-file').evaluate('e=>e===document.activeElement')


REPLAY_STAGE_FRAMED = '''() => {
    const r = document.getElementById('desktop-demo').getBoundingClientRect();
    return Math.min(innerHeight, r.bottom) - Math.max(0, r.top) >= Math.min(r.height, innerHeight) / 2;
}'''


def click_visible_play(page) -> None:
    """Use the real pointer without allowing locator.click() to scroll the page."""
    point = page.locator('#tour-toggle').evaluate('''button => {
        const r = button.getBoundingClientRect(), x = r.left + r.width / 2, y = r.top + r.height / 2;
        return {x, y, clickable: r.top >= 0 && r.bottom <= innerHeight && r.left >= 0 &&
            r.right <= innerWidth && button.contains(document.elementFromPoint(x, y))};
    }''')
    assert point['clickable'], point
    page.mouse.click(point['x'], point['y'])


def check_retained_mode_replay(page) -> None:
    """A replay keeps its operation and explains the corresponding shortcut."""
    for family, hint in (('images', 'Sample copy'), ('archives', 'Sample extracted folder')):
        page.locator('[data-sample="'+family+'"]').click()
        page.locator('[data-mode="convert"]').click()
        page.locator('.wheel-choice').first.click()
        assert page.locator('#demo-hint').inner_text() == hint
    page.locator('[data-sample="images"]').click()
    for mode, key, operation in (('tools', 'Command', 'Crop'), ('actions', 'Control', 'Move To…')):
        page.locator('[data-mode="'+mode+'"]').click()
        page.locator('#wheel-svg').get_by_role('button', name=operation, exact=True).click()
        assert page.locator('#demo-hint').inner_text() == 'Sample result'
        # Step one lasts 1.7 seconds. Observe it before the input command so a
        # slow driver round trip cannot miss a correctly displayed instruction.
        page.evaluate('''() => {
            const desktop = document.getElementById('desktop-demo'), play = document.getElementById('tour-toggle');
            const frame = () => { const r = desktop.getBoundingClientRect(); return {y: scrollY, top: r.top, bottom: r.bottom}; };
            const frames = window.__replayFrames = {manualResult: frame()};
            document.getElementById('try').scrollIntoView({block: 'center', inline: 'nearest', behavior: 'instant'});
            window.__replayClickCapture = () => {
                frames.click = frame();
                requestAnimationFrame(() => { frames.nextFrame = frame(); });
            };
            play.addEventListener('click', window.__replayClickCapture, {capture: true, once: true});
            window.__replayStepOne = null;
            const observer = new MutationObserver(() => {
                if (document.getElementById('desktop-demo').dataset.step !== '1') return;
                window.__replayStepOne = {
                    instruction: document.getElementById('demo-instruction').textContent,
                    hint: document.getElementById('demo-hint').textContent
                };
                observer.disconnect();
            });
            observer.observe(document.getElementById('desktop-demo'), {
                attributes: true, attributeFilter: ['data-step']
            });
            window.__replayObserver = observer;
        }''')
        failed = False
        try:
            assert page.evaluate(REPLAY_STAGE_FRAMED), 'The shortcut-label fixture requires the stage in view'
            click_visible_play(page)
            displayed = page.wait_for_function('window.__replayStepOne').json_value()
            assert displayed['instruction'] == 'Tap '+key+' for '+mode+'.', (mode, displayed)
            assert displayed['hint'] == 'Tap '+key, (mode, displayed)
            page.wait_for_function('document.querySelector("#desktop-demo").dataset.step==="3"')
            assert page.locator('[data-mode="'+mode+'"]').get_attribute('aria-pressed') == 'true'
            assert page.locator('#output-name').inner_text() == operation
            assert page.locator('#demo-hint').inner_text() == 'Sample result'
            assert page.locator('#tour-toggle').get_attribute('aria-pressed') == 'false'
        except Exception:
            failed = True
            try:
                state = page.evaluate('''() => {
                    const desktop = document.getElementById('desktop-demo');
                    const active = document.activeElement;
                    return {
                        mode: document.querySelector('[data-mode][aria-pressed="true"]')?.dataset.mode,
                        step: desktop?.dataset.step, autoplay: desktop?.dataset.autoplay,
                        hidden: document.hidden, scrollY, frames: window.__replayFrames,
                        activeElement: active && {tag: active.tagName, id: active.id,
                            label: active.getAttribute('aria-label')},
                        rect: desktop?.getBoundingClientRect().toJSON()
                    };
                }''')
            except Exception as snapshot_error:
                state = {'snapshot_error': str(snapshot_error)}
            print(json.dumps({'retained_mode_replay_failure': {'expected_mode': mode, **state}}), flush=True)
            raise
        finally:
            try:
                page.evaluate('''() => {
                    window.__replayObserver?.disconnect();
                    document.getElementById('tour-toggle').removeEventListener('click', window.__replayClickCapture, true);
                }''')
            except Exception:
                if not failed:
                    raise


def install_visibility_batch_probe(page) -> None:
    """Keep native observation, with a way to deliver a controlled queued batch."""
    page.add_init_script('''(() => {
        const NativeObserver = window.IntersectionObserver;
        window.IntersectionObserver = class extends NativeObserver {
            constructor(callback, options) {
                super(callback, options);
                this.testCallback = callback;
            }
            observe(target) {
                super.observe(target);
                if (target.id !== 'desktop-demo') return;
                window.__deliverDemoVisibility = states => {
                    // After native setup, isolate this target's controlled queue
                    // from live entries that could overwrite the test stimulus.
                    this.disconnect();
                    this.takeRecords();
                    const now = performance.now();
                    this.testCallback(states.map((visible, index) => ({
                        target, time: now - states.length + index + 1,
                        isIntersecting: visible, intersectionRatio: visible ? 1 : 0
                    })), this);
                };
            }
        };
    })();''')


def check_queued_visibility_replay(page) -> None:
    """The latest queued visibility controls a requested replay, never starts one."""
    page.wait_for_function('typeof window.__deliverDemoVisibility === "function"')
    desktop = page.locator('#desktop-demo')
    tour = page.locator('#tour-toggle')
    page.evaluate('window.__deliverDemoVisibility([false, true])')
    page.wait_for_timeout(2400)
    assert desktop.get_attribute('data-step') == '0'
    assert tour.get_attribute('aria-pressed') == 'false', 'Visibility alone must not start playback'

    page.locator('[data-mode="tools"]').click()
    page.locator('#wheel-svg').get_by_role('button', name='Crop', exact=True).click()
    page.evaluate('window.__deliverDemoVisibility([false, true])')
    tour.click()
    assert tour.get_attribute('aria-pressed') == 'true', 'Play must start a new replay from the manual result'
    page.wait_for_function('document.getElementById("desktop-demo").dataset.step==="3"')
    assert page.locator('#output-name').inner_text() == 'Crop'
    assert page.locator('[data-mode="tools"]').get_attribute('aria-pressed') == 'true'
    assert tour.get_attribute('aria-pressed') == 'false'

    page.evaluate('window.__deliverDemoVisibility([true, false])')
    tour.click()
    page.wait_for_timeout(2400)
    assert desktop.get_attribute('data-step') == '0', 'A later hidden entry must suspend the requested replay'
    assert tour.get_attribute('aria-pressed') == 'true', 'Visibility suspension must retain the playback request'
    assert page.locator('#sample-output').is_hidden()
    page.evaluate('window.__deliverDemoVisibility([true])')
    page.wait_for_function('document.getElementById("desktop-demo").dataset.step==="3"')
    assert page.locator('#output-name').inner_text() == 'Crop'
    assert page.locator('#sample-file').get_attribute('data-sample') == 'images'
    assert tour.get_attribute('aria-pressed') == 'false'
    page.wait_for_timeout(2400)
    assert desktop.get_attribute('data-step') == '3', 'A resumed replay must stop at its result'

    page.evaluate('window.__deliverDemoVisibility([true, false])')
    tour.click()
    desktop.focus()
    assert tour.get_attribute('aria-pressed') == 'false', 'Keyboard entry must cancel the suspended replay'
    page.evaluate('window.__deliverDemoVisibility([true])')
    page.wait_for_timeout(2400)
    assert desktop.get_attribute('data-step') == '0'
    assert tour.get_attribute('aria-pressed') == 'false', 'Visibility must not resume a cancelled replay'


def check_replay_frames_selected_example(page) -> None:
    """Play frames a clipped stage and leaves an already framed replay in place."""
    desktop = page.locator('#desktop-demo')
    play = page.locator('#tour-toggle')
    sample = page.locator('#sample-file').get_attribute('data-sample')
    page.locator('[data-mode="actions"]').click()
    page.locator('#wheel-svg').get_by_role('button', name='Move To…', exact=True).click()
    assert page.locator('#output-name').inner_text() == 'Move To…'

    edge = desktop.evaluate('''e => {
        window.scrollTo({top: scrollY + e.getBoundingClientRect().bottom - 18, behavior: 'instant'});
        const {top, bottom} = e.getBoundingClientRect();
        return {top, bottom};
    }''')
    assert edge['top'] < 0 and 17 <= edge['bottom'] <= 19, edge
    for case in ('clipped', 'already-framed', 'default-scroll-at-click'):
        if case == 'default-scroll-at-click':
            desktop.evaluate('''e => {
                window.scrollTo({top: 0, behavior: 'instant'});
                const edge = scrollY + e.getBoundingClientRect().bottom - 18;
                // Exercise a default scroll initiated before the Play handler.
                // Nothing scrolls the page from the test after activation.
                document.getElementById('tour-toggle').addEventListener('click',
                    () => window.scrollTo({top: edge}), {capture: true, once: true});
            }''')
        if case != 'clipped':
            assert page.evaluate(REPLAY_STAGE_FRAMED), case
        start_y = page.evaluate('scrollY')
        click_visible_play(page)
        page.wait_for_function('() => document.getElementById("desktop-demo").dataset.autoplay === "true" && ('
                               + REPLAY_STAGE_FRAMED + ')()', timeout=5000)
        page.wait_for_function('''() => {
            const desktop = document.getElementById('desktop-demo');
            return desktop.dataset.step === '3' && desktop.dataset.autoplay === 'false';
        }''')
        assert page.locator('[data-mode="actions"]').get_attribute('aria-pressed') == 'true'
        assert page.locator('#output-name').inner_text() == 'Move To…'
        assert page.locator('#sample-file').get_attribute('data-sample') == sample
        assert play.get_attribute('aria-pressed') == 'false'
        assert page.evaluate(REPLAY_STAGE_FRAMED), ('The completed result should remain in view', case)
        if case == 'already-framed':
            assert abs(page.evaluate('scrollY') - start_y) <= 1, 'An already framed replay must leave the page in place'


def check_gallery_without_javascript(page) -> None:
    assert page.locator("#screen-workspace").is_visible()
    assert page.locator("#gallery-tabs").is_hidden()
    assert page.locator(".gallery-navigation").count() == 0
    links = page.locator("#app-gallery noscript a")
    assert links.count() == 4
    for link in links.all():
        assert link.is_visible()
        assert link.get_attribute("href").endswith(".webp")
    assert page.locator('#format-directory').is_hidden()
    page.locator('#format-details > summary').click()
    assert page.locator('#format-directory').is_visible()
    assert 'AVIF' in page.locator('#format-directory').inner_text()


def check_catalog_search(page):
    details=page.locator('#format-details')
    summary=page.locator('#format-details > summary')
    # Navigation in exercise() has already opened the directory.
    assert details.evaluate('e=>e.open')
    summary.click()
    assert page.locator('#format-search').is_hidden()
    summary.focus();summary.press('Enter')
    assert details.evaluate('e=>e.open')
    search=page.locator('#format-search')
    assert search.evaluate('e=>parseFloat(getComputedStyle(e).fontSize)>=16'), 'Search must remain readable without mobile auto-zoom'
    search.fill('crop')
    assert page.locator('.format-row').count()==2
    assert page.locator('.format-row').all_text_contents()[0].startswith('Images')
    assert page.locator('#tool-directory li').count()==2
    assert page.locator('#format-search-status').inner_text()=='2 file families · 2 matching tools'
    summary.click()
    assert search.is_hidden()
    page.locator('.header a[href="#formats"]').click()
    assert search.is_visible() and search.input_value()=='crop'
    search.fill('EXCEL')
    assert 'Spreadsheets' in page.locator('#format-directory').inner_text()
    search.fill('<script>not-a-format</script>')
    assert page.locator('.format-row').count()==0
    assert 'No matches' in page.locator('#format-search-status').inner_text()
    assert page.locator('.tool-directory').is_hidden()
    page.locator('#format-search-clear').click()
    assert search.evaluate('e=>document.activeElement===e')
    assert page.locator('.format-row').count()==9
    assert page.locator('#tool-directory li').count()==32
    search.fill('trim');search.press('Escape')
    assert search.input_value()==''
    assert page.locator('.format-row').count()==9
    assert page.locator('#sample-grid [data-sample]').count()==9
    assert page.locator('a[href$="Lemulip-0.1.20-macOS-universal.dmg"]').count()==3
    summary.click()
    summary.press('Space')
    assert details.evaluate('e=>e.open')


def check_native_recording(page,output,width):
    player=page.locator('#native-video')
    assert player.count()==1
    assert player.evaluate('v=>v.paused')
    assert not player.is_visible()
    assert not player.get_attribute('autoplay')
    assert player.get_attribute('preload')=='none'
    assert page.locator('#watch-native').inner_text()=='Watch Mac recording'
    before=page.locator('#features').evaluate('e=>e.getBoundingClientRect().top+scrollY')
    page.locator('#watch-native').click()
    assert player.is_visible()
    assert page.locator('#desktop-demo').evaluate('e=>e.inert')
    assert page.locator('#tour-toggle').get_attribute('aria-pressed')=='false'
    assert page.locator('#watch-native').inner_text()=='Back to the wheel'
    assert page.locator('#demo-source').inner_text()=='Actual Mac recording. A JPG copy appears beside the original.'
    assert page.locator('#demo-instruction').is_hidden()
    assert page.locator('#demo-instruction').get_attribute('aria-hidden')=='true'
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
    assert page.locator('#watch-native').inner_text()=='Watch Mac recording'
    assert page.locator('#demo-source').inner_text()=='Interactive example. Nothing is uploaded.'
    assert page.locator('#demo-instruction').is_visible()
    assert page.locator('#demo-instruction').get_attribute('aria-hidden')=='false'
    page.locator('#watch-native').focus();page.keyboard.press('Enter')
    assert player.is_visible()
    player.focus();page.keyboard.press('Escape')
    assert not player.is_visible()
    assert page.locator('#watch-native').evaluate('e=>e===document.activeElement')


def check_entry_and_sharing(page, canonical):
    """Check prepared/deployed tags and decode the exact public image bytes."""
    def one(selector, attribute, expected):
        control=page.locator(selector)
        assert control.count()==1, selector
        assert control.get_attribute(attribute)==expected, selector
    one('link[rel="canonical"]','href',canonical)
    expected={
        'og:url':canonical,'og:image':canonical+'assets/'+SHARE_FILE,
        'og:image:type':'image/png','og:image:width':'1200','og:image:height':'630',
        'og:image:alt':SHARE_ALT,'twitter:card':'summary_large_image',
        'twitter:image':canonical+'assets/'+SHARE_FILE,'twitter:image:alt':SHARE_ALT,
        'twitter:title':page.locator('meta[property="og:title"]').get_attribute('content'),
        'twitter:description':page.locator('meta[property="og:description"]').get_attribute('content'),
    }
    for key,value in expected.items():
        attribute='property' if key.startswith('og:') else 'name'
        one(f'meta[{attribute}="{key}"]','content',value)
    manifest=json.loads((ROOT/'site/assets/social-preview.json').read_text())
    # Local checks use the fixture canonical but fetch the locally prepared asset.
    resource=urljoin(page.url,'assets/'+SHARE_FILE)
    response=page.request.get(resource)
    assert response.ok and response.headers.get('content-type','').split(';')[0]=='image/png'
    assert hashlib.sha256(response.body()).hexdigest()==manifest['sha256']
    size=page.evaluate('''url=>new Promise((resolve,reject)=>{
        const image=new Image();
        image.onload=()=>resolve([image.naturalWidth,image.naturalHeight]);
        image.onerror=()=>reject(new Error('The public social preview could not decode'));
        image.src=url;
    })''',resource)
    assert size==[1200,630],size
    one('.release-links a:has-text("Install & first steps")','href',
        'https://github.com/osmankaankars/lemulip/blob/main/docs/INSTALL.md')


def exercise(page,output,width,height):
    assert page.locator('html').get_attribute('data-site-version')=='20261102.2'
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
    server=None;thread=None;prepared=None
    try:
        if not url:
            prepared=tempfile.TemporaryDirectory(prefix='lemulip-site-browser-')
            canonical='https://preview.example.invalid/lemulip/'
            prepare_site(ROOT,Path(prepared.name)/'lemulip','osmankaankars/lemulip',canonical)
            handler=functools.partial(QuietHandler,directory=prepared.name)
            server=http.server.ThreadingHTTPServer(('127.0.0.1',0),handler)
            thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
            url=f'http://127.0.0.1:{server.server_port}/lemulip/'
        else:
            canonical=url.split('#',1)[0].rstrip('/')+'/'
        with sync_playwright() as p:
            browser=getattr(p,engine).launch(**({'executable_path':executable} if executable else {}))
            try:
                page=browser.new_page()
                page.goto(url,wait_until='networkidle')
                check_entry_and_sharing(page,canonical)
                results.append({'prepared_share_metadata_image_and_first_use_link':'PASS'});page.close()
                for width,height in ((1440,1000),(1280,900),(768,1024),(390,844),(320,740)):
                    page=browser.new_page(viewport={'width':width,'height':height})
                    page.on('pageerror',lambda e:errors.append(str(e)))
                    page.on('response',lambda r:failures.append([r.status,r.url]) if r.status>=400 else None)
                    page.goto(url,wait_until='networkidle')
                    assert not page.locator('#format-details').evaluate('e=>e.open'), 'The long directory starts closed'
                    assert page.locator('#formats').bounding_box()['height'] <= 240, 'Closed directory should remain compact'
                    if width in (1440,390):
                        # Async native captures can otherwise be missing from an offscreen
                        # full-page screenshot even though they render on first scroll.
                        initial_image=page.locator('#screen-workspace img')
                        initial_image.scroll_into_view_if_needed()
                        initial_image.evaluate('image=>image.decode()')
                        page.locator('.header').scroll_into_view_if_needed()
                        page.screenshot(path=str(output/f'overview-collapsed-{width}.png'),full_page=True)
                    check_presentation(page,output,width,height);exercise(page,output,width,height);check_native_gallery(page,output,width,height);check_catalog_search(page);check_wheel_keyboard_feedback(page)
                    results.append({'viewport':f'{width}x{height}','nine_samples':'PASS','wheel':'PASS','single_demo':'PASS','stable_layout':'PASS','keyboard':'PASS','native_gallery_click_keys_focus_wrap':'PASS','themes':'PASS','local_catalog_search':'PASS','reviewed_direct_download':'PASS','overflow':'NONE'})
                    page.close()
                page=browser.new_page(viewport={'width':1440,'height':1000})
                page.goto(url,wait_until='networkidle')
                tour=page.locator('#tour-toggle');desktop=page.locator('#desktop-demo')
                assert desktop.get_attribute('data-step')=='0'
                assert tour.get_attribute('aria-pressed')=='false'
                assert tour.get_attribute('aria-label')=='Play example'
                initial_sample=page.locator('#sample-file').get_attribute('data-sample')
                page.wait_for_timeout(2400)
                assert desktop.get_attribute('data-step')=='0','The example must remain idle before Play'
                assert page.locator('#sample-file').get_attribute('data-sample')==initial_sample
                # Play demonstrates the selected file, not an automatic carousel of samples.
                page.locator('[data-sample="documents"]').click()
                page.locator('#origin-desktop').click()
                tour.click()
                assert tour.get_attribute('aria-pressed')=='true'
                assert tour.get_attribute('aria-label')=='Pause example'
                page.wait_for_function('document.querySelector("#desktop-demo").dataset.step==="1"')
                tour.click();before=desktop.get_attribute('data-step');page.wait_for_timeout(2400)
                assert tour.get_attribute('aria-pressed')=='false'
                assert tour.get_attribute('aria-label')=='Play example'
                assert page.locator('#desktop-demo').get_attribute('data-step')==before
                page.locator('#tab-trim-audio').click();page.wait_for_timeout(2600)
                assert page.locator('#screen-trim-audio').is_visible(),'The gallery must never autoplay'
                page.locator('#next-step').click();assert page.locator('#desktop-demo').get_attribute('data-step')!=before
                assert tour.get_attribute('aria-pressed')=='false','Manual Next must not start a tour'
                tour.click()
                page.wait_for_function('document.querySelector("#desktop-demo").dataset.step==="3"')
                assert tour.get_attribute('aria-pressed')=='false','The example stops at its result'
                assert page.locator('#sample-file').get_attribute('data-sample')=='documents'
                assert page.locator('#output-name').inner_text()=='weekend-notes.pdf'
                assert page.locator('#next-step').get_attribute('aria-label')=='Replay example'
                page.locator('#next-step').click()
                assert desktop.get_attribute('data-step')=='0'
                assert tour.get_attribute('aria-pressed')=='false'
                assert page.locator('#sample-file').get_attribute('data-sample')=='documents'
                tour.click()
                page.wait_for_function('document.querySelector("#desktop-demo").dataset.step==="3"')
                assert tour.get_attribute('aria-pressed')=='false'
                assert tour.get_attribute('aria-label')=='Play example'
                page.wait_for_timeout(2400)
                assert desktop.get_attribute('data-step')=='3','A completed replay must remain on its result'
                assert page.locator('#sample-file').get_attribute('data-sample')=='documents'
                assert page.locator('#output-name').inner_text()=='weekend-notes.pdf'
                check_retained_mode_replay(page)
                # A genuine pointer drag and modifier key must submit only on a wheel drop.
                page.locator('[data-sample="images"]').click()
                page.locator('#origin-desktop').click();box=page.locator('#sample-file').bounding_box();assert box
                page.mouse.move(box['x']+box['width']/2,box['y']+box['height']/2);page.mouse.down()
                page.mouse.move(box['x']+box['width']/2+25,box['y']+box['height']/2+10,steps=4)
                page.keyboard.press('Shift')
                target=page.locator('.wheel-choice').first.bounding_box();assert target
                page.mouse.move(target['x']+target['width']/2,target['y']+target['height']/4,steps=8);page.mouse.up()
                assert page.locator('#sample-output').is_visible()
                assert page.locator('#output-name').inner_text()=='morning-light.png'
                results.append({'user_started_example_idle_pause_replay_and_stop':'PASS','retained_mode_replay_and_result_feedback':'PASS','pointer_drag_shift_and_drop':'PASS'});page.close()
                page=browser.new_page(viewport={'width':1440,'height':1000})
                page.on('pageerror',lambda e:errors.append(str(e)))
                install_visibility_batch_probe(page)
                page.goto(url,wait_until='networkidle')
                check_queued_visibility_replay(page)
                results.append({'queued_visibility_order_idle_resume_keyboard_and_result':'PASS'});page.close()
                page=browser.new_page(viewport={'width':1440,'height':1000})
                page.on('pageerror',lambda e:errors.append(str(e)))
                page.goto(url,wait_until='networkidle')
                check_replay_frames_selected_example(page)
                results.append({'clipped_replay_framed_and_framed_replay_stays_put':'PASS'});page.close()
                page=browser.new_page();page.goto(url,wait_until='networkidle')
                page.locator('#tour-toggle').click()
                assert page.locator('#tour-toggle').get_attribute('aria-pressed')=='true'
                page.locator('#desktop-demo').focus()
                assert page.locator('#tour-toggle').get_attribute('aria-pressed')=='false', 'Keyboard entry owns the demo; the running example must stop'
                results.append({'keyboard_entry_pauses_tour':'PASS'});page.close()
                page=browser.new_page(viewport={'width':390,'height':844},reduced_motion='reduce');page.goto(url,wait_until='networkidle')
                assert page.locator('#tour-toggle').get_attribute('aria-pressed')=='false'
                page.locator('#next-step').click();page.locator('#next-step').click()
                assert page.locator('#floating-wheel').is_visible()
                assert page.locator('#floating-wheel').evaluate('e=>getComputedStyle(e).animationName')=='none'
                check_wheel_keyboard_feedback(page)
                page.locator('#tab-trim-audio').click()
                assert page.locator('#screen-trim-audio').evaluate('e=>getComputedStyle(e).animationName')=='none'
                results.append({'reduced_motion_manual_controls':'PASS'});page.close()
                page=browser.new_page();page.goto(url.split('#')[0]+'#formats',wait_until='networkidle')
                assert page.locator('#format-details').evaluate('e=>e.open')
                assert page.locator('#format-search').is_visible()
                results.append({'catalog_direct_link_opens_directory':'PASS'});page.close()
                page=browser.new_page(java_script_enabled=False);page.goto(url,wait_until='networkidle')
                assert page.locator('h1').is_visible();assert page.locator('.hero-copy .button').is_visible()
                check_gallery_without_javascript(page)
                results.append({'no_javascript_fallback':'PASS','native_gallery_fallback':'PASS'});page.close()
                assert not errors,errors;assert not failures,failures
            finally:browser.close()
    finally:
        if server:server.shutdown();thread.join(timeout=5)
        if prepared:prepared.cleanup()
        report={'engine':engine,'url':url,'results':results,'page_errors':errors,'http_failures':failures}
        (output/'browser-results.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output',required=True,type=Path);parser.add_argument('--engine',choices=['chromium','webkit'],default='chromium');parser.add_argument('--url');parser.add_argument('--executable');args=parser.parse_args();run(args.output,args.engine,args.url,args.executable)
