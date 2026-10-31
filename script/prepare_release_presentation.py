#!/usr/bin/env python3
"""One-time, branch-only preparation of the reviewed 0.1.20 presentation."""
from pathlib import Path
import re
ROOT=Path(__file__).resolve().parent.parent

def change(name,transform):
    path=ROOT/name;old=path.read_text();new=transform(old)
    if old==new: raise ValueError('Expected an unapplied presentation input: '+name)
    path.write_text(new)

def page(s):
    assert s.count('data-screen="activity"')==1 and s.count('data-screen="workspace"')==1
    s=s.replace('20261029.5','20261101.1').replace('0.1.19','0.1.20')
    s=s.replace('A workspace for your files.<br>Room for the details.','A few everyday jobs.<br>A closer look at the tools.')
    s=s.replace('Choose your files, find a format or tool, and pin the ones you use most.','Find the format you need, keep your favourite tools close, and work with a new copy.')
    s=s.replace('Select a screen. Open the image for a closer look.','Captured in Lemulip 0.1.20. Open an image for a closer look.')
    s=s.replace('<p class="intro">Convert, crop, trim, and arrange.<br>All on your Mac.</p>','<p class="intro">Convert an image. Trim a clip.<br>Put your PDF pages in order.</p>')
    s=s.replace('    <p class="requirements">Free &amp; open source','    <p class="release-highlight">New: PDF page ordering &amp; optional wheel sounds.</p>\n    <p class="requirements">Free &amp; open source',1)
    activity=re.search(r'      <button id="tab-activity"[^\n]+\n',s).group(0)
    tab='      <button id="tab-pdf-organize" type="button" role="tab" data-screen="pdf-organize" data-title="Every page, in its place." data-description="Drag pages into place or type a page number. Keep the order you want, then create a new PDF." aria-controls="screen-pdf-organize" aria-selected="false" tabindex="-1">PDF Pages</button>\n'
    s=s.replace(activity,'').replace('      <button id="tab-crop-video"',tab+'      <button id="tab-crop-video"')
    activity=re.search(r'    <figure class="app-slide" id="screen-activity".*?</figure>\n',s,re.S).group(0)
    figure='''    <figure class="app-slide" id="screen-pdf-organize" role="tabpanel" aria-labelledby="tab-pdf-organize" hidden>
      <a href="./assets/app-pdf-organize.webp" target="_blank" rel="noopener" aria-label="Open PDF Pages screenshot">
        <img src="./assets/app-pdf-organize.webp" width="2040" height="1400" alt="The native PDF editor with four pages, an edited page position and the preserved original order" decoding="async">
      </a>
    </figure>
'''
    s=s.replace(activity,'').replace('    <figure class="app-slide" id="screen-crop-video"',figure+'    <figure class="app-slide" id="screen-crop-video"')
    s=s.replace('height="683"','height="1400"').replace('height="670"','height="1400"').replace('width="1020"','width="2040"')
    s=s.replace('<a href="./assets/app-activity.webp">Activity</a>','<a href="./assets/app-pdf-organize.webp">PDF Pages</a>')
    return s.replace('The Lemulip Workspace with selected files, search and pinned tools','The native Lemulip Workspace with a selected image and conversion tools')

change('site/index.html',page)
change('site/catalog.js',lambda s:s.replace('0.1.19','0.1.20'))
change('site/gallery.css',lambda s:s.replace('1020 / 683','1020 / 700').replace('for a sharp 2x overview','for two source pixels per CSS pixel'))
change('site/product.css',lambda s:s+'\n/* A single release detail, not another feature section. */\n.release-highlight { max-width:32ch; margin:18px 0 0; color:var(--muted); font-size:13px; line-height:1.6; }\n')
for name in ['script/test_site.py','script/test_site_browser.py']:
    def tests(s):
        return (s.replace('0.1.19','0.1.20').replace('20261029.5','20261101.1')
            .replace("['workspace','crop-video','trim-audio','activity']","['workspace','pdf-organize','crop-video','trim-audio']")
            .replace('("workspace", "crop-video", "trim-audio", "activity")','("workspace", "pdf-organize", "crop-video", "trim-audio")')
            .replace('#tab-activity','#tab-trim-audio').replace('#screen-activity','#screen-trim-audio')
            .replace('("ArrowLeft", "activity")','("ArrowLeft", "trim-audio")').replace('("End", "activity")','("End", "trim-audio")'))
    change(name,tests)
change('script/social_preview.html',lambda s:s.replace('height: 341.5px','height: auto').replace('width="1020" height="683"','width="2040" height="1400"'))
change('script/render_social_preview.py',lambda s:s.replace("{'source': [1020, 683], 'displayed': [510, 341.5]}","{'source': [2040, 1400], 'displayed': [510, 350]}")
    .replace('half-size presentation','four-source-pixels-per-CSS-pixel presentation').replace('510 by 341.5','510 by 350')
    .replace('existing native app capture','fresh native app capture')
    .replace('This is not a fresh Retina capture of the pending release.','The source is a genuine 2x native render of 0.1.20 on a virtual HiDPI Mac display, not a physical Retina panel; no screenshot enlargement.'))

status='''

## Current Status — 1 November 2026

PR #33 is merged, including real wheel-selection sound routing. Its 29 real-app
cases passed on Apple Silicon and Intel; old synthetic diagnostic failures below
are historical, not current product failures. A new **seven-case full-app visual
review and genuine 2x capture pass** is recorded in [VISUAL_REVIEW.md](VISUAL_REVIEW.md).

Kaan will assess audible sound/system mute and VoiceOver narration during routine
use and report problems. Those physical observations are not claimed complete and
are not a release blocker by the owner's explicit instruction. Final publication
uses the exact v0.1.20 tagged archive verification; older candidates are not relabelled.
Website delivery is tracked in [ROADMAP.md](ROADMAP.md). The promotional film is last.

## Historical Evidence

'''
for name in ['QUALITY_FOLLOWUP.md','NATIVE_VERIFICATION.md','EDITOR_REVIEW.md']:
    change('docs/'+name,lambda s:s.split('\n',1)[0]+status+s.split('\n',1)[1])
change('docs/ROADMAP.md',lambda s:'''# Product Quality Roadmap

Updated **1 November 2026 (Europe/Istanbul)**. This section is current; dated
investigations below are retained as history, not as still-open PR statuses.

## Current Delivery

Release target: **0.1.20 / build 23**, source `eaa783c949a1814130a6618395269ba17c1baa6f`.
PR #33 is merged. Superseded #20/#23/#25/#26/#30 are closed with history retained.
This presentation must not replace the live download before the exact v0.1.20
archives are published and verified. Older candidates are never relabelled.

| Work | Current state |
| --- | --- |
| P1/P2: PDF ordering | Main includes explicit sort commands, dragging, numeric moves, groups, Undo/Redo, first-click Cancel and long-list fixes. Two-architecture real-app tests passed. |
| A1: Optional sound | Changed wheel selections and accepted actions use the shared optional cue. Default off; repeats, centre, opening/reset and cancellation stay quiet. Kaan owns ongoing acoustic/system-mute review and will report issues. |
| Q1: Native finish | 29 real-app cases per Mac architecture plus seven full-app visual scenarios. See [VISUAL_REVIEW.md](VISUAL_REVIEW.md) for actual findings and limits. |
| B1/B2: Smaller payload | Lossless source compression and retained GUI/CLI symbols are in main. Architectures, required engines and license/source files remain. Public size claims must use final released files. |
| W1/W2/W4: Product page | Compact gallery, closed catalog, manual keyboard-accessible tabs, bounded motion and themes are retained. PDF Pages replaces Activity instead of adding another large section. |
| W3: Fresh captures | Completed: real 2040 x 1400 images of 1020 x 700 windows rendered natively at 2x on a temporary macOS HiDPI display. No enlargement or repainted controls; not a physical Retina-panel claim. |
| M1: Release presentation | Current native gallery, sharing card, clear feature copy and 0.1.20 download transition are grouped in one changeset. Exact release verification and deployed browser checks remain delivery gates. |
| VoiceOver / listening | Owner follow-up during normal use, explicitly not a release blocker. Automated semantics are verified; audible narration is not claimed. |
| V1: Film | Last. Discuss together after this release and website delivery. |

Further binary architecture changes and new editing tools remain later work; no
new feature scope is being added to finish this release.

## Historical Investigation — 29 October 2026

The old PR/download states below explain the original work and are superseded by
the current table. Candidate measurements are not current public-release claims.

'''+s.split('\n',1)[1])
change('docs/MARKETING.md',lambda s:'''# Lemulip Product Story

Updated 1 November 2026 for **0.1.20 / build 23**. PR #33 is merged. Download
links switch only after the exact tagged release archives have been verified.
This is the product-story reference, not a promotional-film storyboard.

## The Main Idea

**File tools, right where you drag.**

Drag a local file, tap a key, and choose what happens next. Convert an image,
trim a clip or put PDF pages in order. Workspace offers another way to select
files and tools. Lemulip is free and open source, without an account or subscription.

**Dosyanın olduğu yerde, ihtiyacın olan araç.**

Dosyanı sürükle, bir tuşa dokun, yapmak istediğin işlemi seç. Görselleri dönüştür,
video ve ses dosyalarını düzenle, PDF sayfalarını sırala. Çalışma Alanı aynı
araçlara ulaşmanın başka bir yolu. Ücretsiz ve açık kaynaklı; hesap gerektirmez.

## Four Specific Product Moments

| Screen | Useful story |
| --- | --- |
| Workspace | Find a format, choose a tool, keep the original and work with a new copy. |
| PDF Pages | Drag thumbnails/handles or type a position, inspect the order and create the arranged PDF. Natural filename, reverse and incoming-order commands are also available in Merge. |
| Crop Video | See the retained area, aspect ratio and exact output dimensions before creating the copy. |
| Trim Audio | Inspect the waveform and selected time range before exporting. |

The existing Finder conversion recording remains a real recording, separately
identified from the interactive browser simulation. Conversion preserves originals;
**Move To…** is an explicit file action that relocates the selected original.

## Public Facts and Boundaries

- macOS 13+, Apple Silicon and Intel; the download is a public preview.
- 35 conversion output formats, 26 tools and six file actions, generated from the
  native catalog. Not every input converts to every output.
- Local processing. Optional engine installation needs the internet; AirDrop sends
  only when chosen. FFmpeg/ImageMagick are included; Pandoc/LibreOffice are optional.
- Optional selection sound now acknowledges changed wheel choices as well as
  accepted operations. Default off, independent preview, persisted preference.
- Only use the exact published package sizes beside its matching download link.
  Do not claim universal losslessness, instantaneous processing or invented usage.

## Actual Visual Assets

The gallery uses the complete 0.1.20 app. The screenshot inventory records original
PNG hashes, logical/pixel geometry, capture workflow and exact application archive.
A temporary macOS HiDPI test display renders **1020 x 700 windows at 2040 x 1400**.
These are real native 2x renders, not physical-panel photography or enlarged 1x images.

Keep the gallery at **510 CSS pixels maximum**. Four meaningful screens are enough;
the catalog stays available on demand. Only 290 pure-black pixels outside the
rounded window corners become transparent before metadata-free WebP encoding.
Product text and controls are neither repainted nor sharpened. Test documents and
media are synthetic; application interactions and outputs are real.

The 1200 x 630 sharing card is a marketing composition of the current Workspace,
approved icon/wordmark and headline. Its manifest records the sources and renderer.
No invented ratings, customer logos or fake product capabilities.

## From Download to First Result

The main button selects the verified release DMG. **Install & first steps** opens
installation, first launch and the built-in sample in that order. Workspace is the
alternative when the source application does not provide a compatible local drag.
Activity and the user guide explain completed outputs and errors.

## Final Owner Review and Film

Kaan will assess sound on speakers/headphones, system mute and VoiceOver narration
while using the app and report issues. That agreement is not an acoustic test pass,
and does not stall publication. The 29-case native regression gates and bounded
visual review are separate. After exact release and deployed website verification,
discuss the promotional film together. Record only the experience people can download.
''')
print('Prepared presentation text and tracking; no product source changed.')
