"""Layout evidence for the compact gallery, workspace, themes, and format notes."""
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
    for origin in ('desktop','finder','workspace'):
        page.locator('#origin-'+origin).click()
        desktop=page.locator('#desktop-demo').bounding_box()
        boxes=[]
        for file in page.locator('#sample-grid [data-sample]').all():
            assert file.is_visible()
            box=file.bounding_box();assert box
            assert box['x']>=desktop['x']-1
            assert box['y']>=desktop['y']+27
            assert box['x']+box['width']<=desktop['x']+desktop['width']+1
            assert box['y']+box['height']<=desktop['y']+desktop['height']+1
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
    page.evaluate('scrollTo(0,0)')
