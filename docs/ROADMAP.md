# Roadmap

Freewheel should make everyday file work feel easy: see what will change, make
one clear decision, and save a new copy. The next milestones focus on visual
editing, a warmer native interface, and a small resource footprint.

This is a working plan. Items below are planned unless explicitly marked as
implemented. They are not promises of a release date or evidence that a feature
already ships. The app and repository keep the Freewheel name while the next
visual identity is explored.

## Current Product

The app has a drag wheel, a workspace, a session queue, a floating file shelf,
and native conversion tools with optional external engines. Its current image
crop asks for centered dimensions. Media trimming asks for start and end times.
Neither dialog provides an image selection canvas or an audio waveform.

The [browser walkthrough](https://osmankaankars.github.io/freewheel/) demonstrates
the wheel with sample files. It is a simulation and does not convert files.
Read [Formats](FORMATS.md) for the actual conversion routes and their limits.

## 0. Reliable Builds and Clear Installation

Make the first downloadable preview dependable before expanding the feature
list.

- Resolve the case-insensitive collision between the GUI and CLI build products.
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
satisfy this gate. The current result is visible in [Build and Verify](https://github.com/osmankaankars/freewheel/actions/workflows/build.yml).

## 1. Visual Image Crop

Show the actual image and make the selected output area obvious.

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

**Ready when:** the chosen rectangle matches the output for landscape, portrait,
rotated, transparent, and large images; keyboard and pointer controls agree;
cancellation produces no output; and the original file remains unchanged.

## 2. Audio Waveform Trim

Let users hear and see the range they are keeping.

- Decode a bounded waveform summary in the background and show a loading state
  immediately. Allow cancellation while the waveform is prepared.
- Provide start and end handles, editable timestamps, a visible selected duration,
  and a playhead that follows playback.
- Add Play Selection, Pause, Reset, and Create Copy. Stop playback when the editor
  closes and keep selection changes synchronized with the numeric fields.
- Describe unsupported codecs or a required engine before export starts.
- Use native decoding and export for supported media; retain FFmpeg as an optional
  route for additional formats. State when export re-encodes the selected audio.
- Add silence detection only after manual selection and playback are reliable.

**Ready when:** preview playback uses the selected range, exported audio matches
the documented timestamp precision, playback and export cancel cleanly, and
long recordings do not require keeping the entire decoded file in memory.

## 3. Video and PDF Previews

Build on the editor behavior established by image crop and audio trim.

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

Explore a pistachio-and-cream direction alongside a lemonade palette. Use warm
neutral surfaces, dark readable text, and color for selection, focus, and the
primary action. Let users' photos, pages, and waveforms remain the main content.

- Design an original icon and wordmark that also work in the menu bar and Finder.
- Choose a short, pronounceable name after checking existing apps, projects,
  domains, and relevant trademarks. Candidate names are not approved identities.
- Share color, spacing, typography, focus, and control states across the wheel,
  workspace, editors, website, and documentation.
- Support system light and dark appearance, reduced motion, and keyboard access.
- Use Title Case for English headings and actions; keep explanatory text direct.
- Replace promotional concepts with actual app screenshots as each editor ships.
  Label any interactive simulation clearly.

**Ready when:** the identity works at icon size, text and controls meet their
contrast requirements, and the same editing task feels consistent across the
app and its product pages. A rename needs its own migration plan for preferences,
bundle identity, repository links, and existing downloads.

## 5. Additional Tools

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

Measure the first passing universal build before making public size or speed
claims. These are **initial engineering targets, not measured results**:

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

## Design Benchmark

The October 2026 review covered Tangerine's [homepage](https://tangerineformac.com/),
[tool details](https://tangerineformac.com/tools), [press kit](https://tangerineformac.com/press),
and [privacy page](https://tangerineformac.com/privacy), including its public
editor screenshots and videos. The visual crop canvas, audio waveform selection,
video timeline, and PDF thumbnails provide useful reference points for editing
clarity. This was a review of public materials, not a hands-on performance test.

Freewheel will use its own code, artwork, and product identity. Feature names
and conversion counts alone do not establish comparable quality; the editor
behavior and exported result must earn that comparison.
