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
and native conversion tools with optional external engines. Source 0.1.3 added
three saved appearances and a native visual image crop editor. Source 0.1.4 adds
an audio waveform editor with range selection and playback. Video trimming
still asks for numeric start and end times. Native UI acceptance for each new
editor remains part of its release gate.

The [browser walkthrough](https://osmankaankars.github.io/lemulip/) demonstrates
the wheel with sample files. It is a simulation and does not convert files.
Read [Formats](FORMATS.md) for the actual conversion routes and their limits.

## 0. Reliable Builds and Clear Installation

Make the first downloadable preview dependable before expanding the feature
list.

**Verified baseline:** the Lemulip naming and universal packaging update at
`46cb4dc` passed [both Mac test jobs and exact downloaded-package checks](https://github.com/osmankaankars/lemulip/actions/runs/39127334291),
[CodeQL](https://github.com/osmankaankars/lemulip/actions/runs/39127334294), and
[Pages deployment](https://github.com/osmankaankars/lemulip/actions/runs/39127338673)
on October 18, 2026. Both Mac runners launched the downloaded app briefly and
verified the packaged CLI. New source changes must pass these gates again;
the baseline does not verify the new themes or crop editor.

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

**Implemented in source 0.1.3; Mac acceptance pending.** The editor, crop geometry,
bounded image preview, original-resolution export, and regression cases are now
in place. Complete the exact-commit Mac build and hands-on pointer, keyboard,
orientation, and cancellation checks before marking this milestone ready.

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

**Implemented in source 0.1.4; Mac acceptance pending.** The native editor,
bounded waveform summary, range controls, selection playback, and export route
are in place. Exact-commit Mac builds and hands-on playback, seeking, keyboard,
and cancellation checks are still required. The browser's silent waveform
concept does not run the native editor.

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

**Next feature milestone after the image and audio editors pass their Mac
acceptance checks.** These previews remain planned.

| Editor | Planned Experience |
| --- | --- |
| Trim Video | Native video preview, a bounded thumbnail timeline, range handles, selected duration, and playback of the chosen range |
| Crop Video | The same crop controls over the video preview, with export dimensions and aspect ratio visible |
| Organize PDF | Page thumbnails with explicit reorder, rotate, remove, and extract actions |
| Merge PDF | A visible ordered list with page counts and a clear output summary |

**Ready when:** previews and final output agree, ordering is explicit, empty or
invalid selections cannot be submitted, and long documents or clips load only
the preview data needed for the visible editor.

## 4. Warm Visual Identity

The first visual foundation is implemented in source: **Lemulip** branding,
**Orchard Night** as the default, **Vivid Pistachio** and **Lemon Drop** as saved
appearance choices, a dimensional folded-ribbon icon,
and navigation materials with an older-system fallback. The wheel stands on its
own without an enclosing rectangular panel or repeated footer instruction. See the shared
[Design guide](DESIGN.md). Native build and appearance verification are still
required before a release claim.

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

The first passing universal build provides a size baseline. The exact CI
archives from `46cb4dc` contained:

| Artifact | Measured Payload |
| --- | --- |
| Installed app files | 7,532,916 bytes, about 7.53 MB |
| Universal download ZIP, including CLI and notices | 4,317,627 bytes, about 4.32 MB |
| Universal DMG | 4,023,401 bytes, about 4.02 MB |

Sizes were calculated from the verified archives in the
[baseline build](https://github.com/osmankaankars/lemulip/actions/runs/39127334291).
The app payload is the sum of its files, not allocated filesystem blocks. These
measurements precede the theme and crop changes. Record the new release's sizes
after packaging. Memory, CPU, and launch-time budgets below are still
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
