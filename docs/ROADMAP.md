# Roadmap

Lemulip should make everyday file work feel easy: see what will change, make
one clear decision, and save a new copy. The next milestones focus on visual
editing, a warmer native interface, and a small resource footprint.

This is a working plan. Items below are planned unless explicitly marked as
implemented. They are not promises of a release date or evidence that a feature
already ships. **Lemulip** is the selected product name and **Orchard Night** is
the default appearance.

## Current Product

The app has a drag wheel, a workspace, a session queue, a floating file shelf,
and native conversion tools with optional external engines. The published
[0.1.4 preview](https://github.com/osmankaankars/lemulip/releases/tag/v0.1.4)
includes three saved appearances, a native visual image crop editor, and an
audio waveform editor with range selection and playback. Source **0.1.5** adds
native video trim; source **0.1.6** adds visual video crop, source **0.1.7**
adds a PDF page organizer, and source **0.1.8** adds PDF merge preview. Each version's own
[Mac checks](https://github.com/osmankaankars/lemulip/actions/workflows/build.yml)
and [release assets](https://github.com/osmankaankars/lemulip/releases) determine
availability. Hands-on acceptance of editor interactions remains separate from
automated CI.

The [browser walkthrough](https://osmankaankars.github.io/lemulip/) demonstrates
the wheel with sample files. It is a simulation and does not convert files.
Read [Formats](FORMATS.md) for the actual conversion routes and their limits.

## 0. Reliable Builds and Clear Installation

Make the first downloadable preview dependable before expanding the feature
list.

**Verified baseline:** version **0.1.4**, build **7**, at `17bb81a` passed
[the source build](https://github.com/osmankaankars/lemulip/actions/runs/39139842826),
[CodeQL](https://github.com/osmankaankars/lemulip/actions/runs/39139842808), and
[the tagged build and downloaded-package checks](https://github.com/osmankaankars/lemulip/actions/runs/39141454481)
on October 18, 2026. Each Mac architecture passed 77 core and native tests;
Apple silicon also passed five optional-engine integration tests. Both runners
verified the downloaded universal app and CLI. The DMG, app ZIP, source ZIP,
and checksums are published under `v0.1.4`.

Source **0.1.5** at `26ac82d` passed its
[Mac build and package checks](https://github.com/osmankaankars/lemulip/actions/runs/39146365216):
85 core and native tests on each architecture, plus five optional-engine
integration tests on Apple silicon. Its
[website deployment](https://github.com/osmankaankars/lemulip/actions/runs/39146365294)
also passed. Release availability remains recorded in
[Releases](https://github.com/osmankaankars/lemulip/releases).

Every new app version must pass its own Mac and security checks. These results
do not establish a newer version's result or complete hands-on editor acceptance.

- Keep the GUI and CLI build product names distinct on case-insensitive disks.
- Correct PDF raster dimensions and rendering of annotations on rotated crops.
- Keep strict native regression checks, including all four quarter-turn rotations.
- Pass macOS tests on Apple silicon and Intel, then verify the exact universal
  archives downloaded from CI.
- Publish a new version and tag for verified fixes; preserve existing tags.
- Describe signing and first-launch behavior accurately. Add Developer ID
  signing and notarization when a signing identity is available.
- Keep public instructions portable and English headings in Title Case.

**Ready when:** both Mac jobs and downloaded-package checks pass for the exact
release commit, and a clean Mac can install and launch the downloaded app using
the documented steps. Local source inspection and a working website do not
satisfy this gate. The current result is visible in [Build and Verify](https://github.com/osmankaankars/lemulip/actions/workflows/build.yml).

## 1. Visual Image Crop

Show the actual image and make the selected output area obvious.

**Published in 0.1.4; automated Mac checks passed.** The editor, crop geometry,
bounded image preview, original-resolution export, and regression cases are in
the verified release. Hands-on pointer, keyboard, orientation, and cancellation
checks are still needed before marking interactive acceptance complete.

- Open a downsampled preview with a movable crop rectangle, eight resize handles,
  a dimmed outer area, and an optional thirds grid.
- Offer Free, Original, 1:1, 4:3, 3:4, 16:9, and 9:16 ratios. Keep pixel width and
  height available for precise work.
- Support keyboard movement, visible focus, Reset, Cancel, and Create Copy.
- Keep all selections within the image and explain invalid dimensions inline.
- Apply image orientation consistently to both the preview and exported pixels.
- Convert the selected preview rectangle back to full-resolution coordinates;
  cropping must preserve detail from the original, not export the preview bitmap.
- Start with one image at a time. For a multiple-file selection, explain that
  interactive cropping requires a single image instead of silently choosing one.

The first implementation supports a single still raster image that macOS can
decode and write. It caps the preview at 1,600 pixels on its longest edge and
the original at 40 megapixels / 16,384 pixels per side. SVG, multi-frame images,
and unavailable codecs receive an explicit explanation. The command-line crop
keeps its centered width/height behavior.

**Ready when:** the chosen rectangle matches the output for landscape, portrait,
rotated, transparent, and large images; keyboard and pointer controls agree;
cancellation produces no output; and the original file remains unchanged.

## 2. Audio Waveform Trim

Let users hear and see the range they are keeping.

**Published in 0.1.4; automated Mac checks passed.** The native editor,
bounded waveform summary, range controls, selection playback, and export route
are in the verified release. Hands-on playback, seeking, keyboard, and
cancellation acceptance is still pending. The browser walkthrough does not
run the native editor.

- Decode a bounded waveform summary in the background and show a loading state
  immediately. Allow cancellation while the waveform is prepared.
- Provide start and end handles, editable timestamps, a visible selected duration,
  and a playhead that follows playback.
- Add Play Selection, Pause, Reset, and Create Copy. Stop playback when the editor
  closes and keep selection changes synchronized with the numeric fields.
- Describe unsupported codecs or a required engine before export starts.
- Use native decoding and export for supported media; retain FFmpeg as an optional
  route for additional formats. State when export re-encodes the selected audio.
- Keep silence detection as later work, after manual selection and playback
  are verified.

**Ready when:** preview playback uses the selected range, exported audio matches
the documented timestamp precision, playback and export cancel cleanly, and
long recordings do not require keeping the entire decoded file in memory.

## 3. Video and PDF Previews

Build on the editor behavior established by image crop and audio trim.

**All four editor implementations are complete in source:** Trim Video in
0.1.5, Crop Video in 0.1.6, Organize PDF in 0.1.7, and Merge PDF preview in
0.1.8. Mac verification is reported by each commit's Actions run. Hands-on
acceptance of these editors remains open. **Warm Visual Identity is the next
development milestone.**

| Editor | Experience and Status |
| --- | --- |
| Trim Video | Source 0.1.5: native video preview, a bounded thumbnail strip, range handles, timestamps, selected duration, and selection playback; MP4/MOV copy export |
| Crop Video | Source 0.1.6: a movable crop over the native preview, aspect ratios, output dimensions, and full-duration MP4/MOV copy export |
| Organize PDF | Source 0.1.7: page thumbnails, reorder, selected-page rotation, removal with undo, and extraction to a new PDF |
| Merge PDF | Source 0.1.8: first-page previews, document reordering and removal with undo, page counts, and output page ranges before creating a copy |

The first video trim editor uses native macOS playback and export without new
dependencies. It requests 12 thumbnails, each at most 192 pixels on its longest
edge; the engine caps a request at 24 thumbnails. It supports one local,
native-decodable video track with at most one audio track. MP4 and MOV exports
re-encode the selected source range; frame and audio-codec boundaries can affect
the exact duration. Unsupported inputs receive an explanation before editing.
The original remains unchanged. See [Visual Video Trim](USER_GUIDE.md#visual-video-trim).

Video crop applies one spatial selection to the full clip and keeps its audio.
The crop overlays native playback, with a single upright still frame capped at
1,280 pixels on its longest edge while playback prepares. Output dimensions are
even numbers for the native video encoder; the
chosen rectangle remains within the source. MP4 and MOV output re-encodes the
video, using the source frames rather than the preview image. Trim and Crop
remain separate operations. See [Visual Video Crop](USER_GUIDE.md#visual-video-crop).

PDF organization shows one document as page thumbnails, with dragging and
explicit controls for ordering, rotation, removal, and selected-page extraction.
It copies original pages to keep text and vector content, and verifies that the
source still matches the preview before export. Preview storage and edit history
are bounded; the editor releases its temporary source copy on close. See
[Organize PDF](USER_GUIDE.md#organize-pdf) for supported documents and controls.

PDF merge preview arranges whole documents in an ordered list. Each row shows
the first page, document page count, and resulting page range; the total updates
as files move or leave the arrangement. Export copies the original PDF pages
and validates their source fingerprints. The preview shares bounded rendering
and temporary-file handling with the organizer. See
[Merge PDF](USER_GUIDE.md#merge-pdf).

**Ready when:** previews and final output agree, ordering is explicit, empty or
invalid selections cannot be submitted, and long documents or clips load only
the preview data needed for the visible editor.

## 4. Warm Visual Identity

**Next development milestone.** Refine the established identity across the app
and its product pages, starting with the icon at everyday sizes and a Lemulip
wordmark.

The first visual foundation is implemented in source: **Lemulip** branding,
**Orchard Night** as the default, **Vivid Pistachio** and **Lemon Drop** as saved
appearance choices, a dimensional folded-ribbon icon,
and navigation materials with an older-system fallback. The wheel stands on its
own without an enclosing rectangular panel or repeated footer instruction. See the shared
[Design guide](DESIGN.md). These foundations are included in the verified 0.1.4
build; hands-on appearance and accessibility review remains open.

Use deep green surfaces, warm readable text, and concentrated color for selection,
focus, and the primary action. Let users' photos, pages, and waveforms remain the
main content.

- Refine the approved icon at Finder and Dock sizes; add a Lemulip wordmark and
  a layered Icon Composer variant.
- Share color, spacing, typography, focus, and control states across the wheel,
  workspace, editors, website, and documentation.
- Keep the three appearances consistent across windows and editors. The saved
  appearance preference is implemented; preserve reduced motion, transparency
  options, contrast, and keyboard access as more editors are added.
- Use Title Case for English headings and actions; keep explanatory text direct.
- Replace promotional concepts with actual app screenshots as each editor ships.
  Label any interactive simulation clearly.

**Ready when:** the identity works at icon size, text and controls meet their
contrast requirements, and the same editing task feels consistent across the
app and its product pages. Verify the name transition on an existing installation
and keep historical tags and downloads intact.

## 5. Easier Office Conversion

The current implementation offers DOCX, XLSX, and PPTX output through optional
local engines. Make common routes easier to use while preserving a small app.

- Keep format names clear: Microsoft Word Document, Excel Workbook, and
  PowerPoint Presentation. Explain an engine requirement before a job starts.
- Evaluate built-in export for basic DOCX documents and single-sheet CSV/TSV to
  XLSX. Define the supported formatting and data types before expanding scope.
- Keep an optional local engine for complex Office documents and verify font,
  table, formula, and slide behavior with representative files.
- Develop PDF-to-editable-DOCX as a separate layout-reconstruction feature.
  Follow with spreadsheet and slide export only when their outputs are usable.
- Add slide-to-image export with explicit page selection and image dimensions.

**Ready when:** supported routes produce files that open correctly in their
target applications, layout and data limitations are clear, and optional engine
installation is required only where the documented route needs it.

## 6. Additional Tools

After the core editors are reliable, prioritize tools by repeated real tasks:
photo adjustments with before/after comparison, metadata inspection and editing,
canvas backgrounds, collages, and more capable PDF organization. Research richer
audio tools and media redaction separately; these need clear scope and export
behavior rather than placeholder menu entries.

Review file actions as part of this work. The current **Copy To…** chooses a
destination. Copying file references for Finder paste is a distinct planned
action. The existing floating shelf also needs a usability review before adding
edge pinning or more persistent state.

## Keep It Lightweight

The desktop app stays native with AppKit and SwiftUI. It currently has no
third-party Swift package dependencies. Optional conversion engines remain
separate installations, so users choose the capabilities and disk cost they need.
The website and test sources are not bundled into the installed app.

The published **0.1.4**, build **7**, provides a measured size baseline. Its exact
release archives contain:

| Artifact | Measured Payload |
| --- | --- |
| Installed app files | 9,484,180 bytes, about 9.48 MB |
| Universal download ZIP, including CLI and notices | 4,916,705 bytes, about 4.92 MB |
| Universal DMG | 4,610,647 bytes, about 4.61 MB |

Sizes were calculated from the verified archives in the
[tagged build](https://github.com/osmankaankars/lemulip/actions/runs/39141454481)
and checked against the published checksums. The app payload is the sum of its
files, not allocated filesystem blocks. These measurements include the themes,
visual crop, and audio waveform editor. Record each newer version's sizes after
verified packaging. Memory, CPU, and launch-time budgets below are still
**engineering targets, not measured results**:

| Metric | Initial Target | Measurement |
| --- | --- | --- |
| Universal app download | At most 30 MB compressed; 60 MB installed | App-only archive and installed bundle, excluding separately installed engines |
| Idle memory | At most 100 MB resident memory | No jobs or editors, after a 60-second settling period |
| Idle CPU | Below 0.5% of one logical CPU on average | 60 seconds with the wheel enabled and no drag session; also record wakeups |
| Warm launch | Interactive workspace within 1 second | Median of 10 launches on an Apple silicon baseline; record OS and hardware model |

Publish the actual measurement method and results, then adjust targets only
with an explained tradeoff. Compare Intel separately instead of assuming the
same result. A smaller source repository is not a measurement of app memory.

The current drag monitor polls every 40 ms. Measure its idle cost and investigate
event-driven activation or adaptive polling without losing Finder compatibility.
This interval alone does not establish CPU usage.

Create preview workers only when an editor opens. Downsample image previews,
bound waveform and thumbnail caches, cancel obsolete requests, and release their
buffers on close. Full-resolution export should use the original file through
the existing safe output pipeline. Heavy work must not block the main thread.
