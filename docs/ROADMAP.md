# Product Quality Roadmap

Updated 29 October 2026. This plan turns the product review into small, verifiable changes. A prepared change is not a shipped feature: the website can improve independently, while app changes need native checks and a new verified release. The current public download remains **0.1.19 / build 22**.

## Direction

Lemulip should feel like a precise, lively Mac utility. Its identity is the drag, modifier key, operation wheel, and local result. The website should make that sequence clear, then let people inspect the real app and its capabilities without scrolling through a manual.

Keep the existing icon, orchard/pistachio/lemonade themes, the interactive wheel, the real Finder recording, and the catalog-backed counts. The next pass adds a more fluid, tactile presentation around that identity: natural typography, a deliberate wheel entrance, clear selection feedback and smooth changes between real screens. See [the design direction](DESIGN.md) for the shared decisions and motion budget.

## Order of Work

| Priority | Work | Decision | Completion evidence |
| --- | --- | --- | --- |
| 1 | W1: Native screenshot presentation | Compact, authentic screenshots with a useful explanation for each screen | Desktop and mobile browser captures, original image hashes unchanged, no layout shift while switching |
| 1 | W2: Format directory | Closed by default; navigation reveals it; search stays inside | Mouse/keyboard, direct-link, query preservation, no-JavaScript and narrow-width checks |
| 1 | P1: PDF input order | Preserve incoming order; offer explicit filename, reverse, and incoming-order commands | Real PDF fixtures, export order and undo/redo checks |
| 1 | P2: PDF rearrangement | Separate drag handle and editable output position | Native build, provider/drop and selection tests, then a real Mac interaction review |
| 2 | B1: Smaller source payload | Losslessly compress raw Git source TARs using XZ | Exact decompressed hashes, extraction/manifest checks, native package verification, fresh size comparison |
| 2 | A1: Optional selection sound | One subtle cue for a committed operation choice; default off with preview | Native volume/mute, rapid-selection, cancellation, persistence and accessibility review |
| 3 | W3: Fresh high-density captures | Capture the running app at 2x after editor changes stabilize | Recorded commit, dimensions, hashes and native capture provenance |
| 3 | Q1: Consistent editor finish | Review spacing, selection, empty/loading/error states, keyboard focus and motion together | A short scenario matrix and actual Mac screenshots, with specific defects resolved |
| 3 | W4: Fluid product presentation | Sentence-case typography, a distinct wheel entrance, result feedback and manual screen transitions | Both browser engines, keyboard continuity, interruption, reduced motion, five viewport sizes and all themes |
| Later | B2: Further binary reduction | Measure symbol stripping before touching engine architecture | Real stripped build comparison and native regressions; no estimated savings presented as delivered |
| 4 | M1: Marketing readiness | Current native visuals, accurate feature story, verified download and first-run guidance | Every public claim and asset maps to a released feature and recorded source |
| Last | V1: Promotional film | Plan and record the final product experience after the preceding work ships | Real released workflows, a reviewed storyboard and accurate output examples |

W1/W2 are live through PR #19. P1/P2 are prepared in PR #20 and have passed real PDF export tests on both native architectures; the actual editor interaction review remains separate. B1 is under full native packaging verification in PR #21. A1 implementation has started with a default-off preference. Website presentation can be reviewed while native packages build, but it must not advertise those app changes as released. The promotional film remains last.

## W1 — Give Real Screenshots an Appropriate Scale

**Observed problem.** The four native WebP captures are 1020 pixels wide. The current gallery stretches them to 1060 CSS pixels. At that width even a 1x display enlarges the source; a 2x display needs roughly twice as many pixels. In the measured 1363-pixel browser viewport the image frame alone was 1060 × 728 CSS pixels. The gallery repeated the selected name below the tabs and added previous/next arrows and a counter for only four views.

**Decision.** Keep the real captures at a maximum of **510 CSS pixels** for the current assets. Place a short explanation beside the image on desktop and above it on small screens. Keep four manual tabs: Workspace, Crop Video, Trim Audio, Activity. Remove the redundant arrow controls and counter. The image remains a link to the original for closer inspection.

Each screen should communicate a particular task:

- Workspace: choose files, search for a tool or format, pin frequent choices.
- Crop Video: set the retained region, aspect ratio, and output size.
- Trim Audio: choose a range on the waveform and preview it.
- Activity: inspect completed conversions and find their output.

**Acceptance.** No image exceeds half its source width; the surrounding section fits comfortably in a desktop view; changing tabs does not move the next section; keyboard arrows/Home/End and focus work; all three themes remain readable at 320, 390, 768, 1280 and 1440 pixels. Images and their provenance remain unchanged. No generated interface, artificial sharpening, second autoplay sequence, parallax, or decorative mock device is needed.

**Next capture pass (W3).** Once the native changes are ready, capture actual app windows at 2x with a useful file and visible result. Do not enlarge a 1x capture and label it Retina. Include a purposeful PDF ordering example if it explains the new workflow better than an existing view. Reassess the display width from the new source dimensions rather than expanding the gallery automatically.

## W2 — Open the Catalog When Someone Needs It

**Observed problem.** The format section occupied about **1618 CSS pixels** in the same desktop inspection. Most of that detail is irrelevant until a visitor has a particular format or tool in mind.

**Decision.** Put the search, format families, engine notes, and nested tools/actions list inside one native disclosure. The closed row says “Formats & tools” and explains what can be found. The navigation and count-section links open it, including a fresh visit to `#formats`. Keep the current search semantics and clear/Escape behavior. Closing the directory must not discard a query.

**Acceptance.** Closed on a normal first visit; opens with click, Enter and Space; direct links reveal the search; search results and counts remain accurate; no-result feedback is announced; clearing restores the user's prior tools-list state; static format information and the full guide remain accessible without JavaScript. Mobile search text is at least 16 pixels. Do not remove supported formats or hide engine requirements to make the page appear simpler.

**Follow-up copy pass.** Review repeated explanations and capitalization across the whole page as one editorial change. Preserve product names, format abbreviations, filenames and macOS spelling. Remove genuinely duplicated information after checking what each section teaches. This is not a reason to rewrite every sentence in the first layout fix.

## P1 — Make the PDF Order Explicit

**Diagnosis.** The inspected path preserves the URLs received from the pasteboard or file picker through opening and export. No unconditional app-side reversal was found. A file provider's delivered order is not reliable evidence of the user's click chronology. Silently reversing or alphabetizing every import would replace one surprising behavior with another.

**Decision.** Keep incoming order as the default. Add explicit Merge ordering commands:

1. Filename order using natural numeric comparison (`page-1`, `page-2`, `page-10`).
2. Reverse the current order.
3. Restore incoming order for the remaining items.

Commands act on the current document set, preserve selection identities, and create one undo step. They must not resurrect removed files, silently change a pending export, or sort by an internal UUID. Show the resulting list before the user commits the merge.

**Acceptance.** Real multi-page PDF fixtures establish that incoming document order and each document's page order survive through the export plan. Natural sort, duplicate-name stability, reverse, restored order, removal, selection, undo and redo have explicit coverage. The UI makes the order control discoverable without requiring users to know why Finder supplied a particular sequence.

## P2 — Rearrange by Dragging or Typing a Position

**Diagnosis.** Both editors already contain drag/drop hooks, so adding another nominal “drag support” flag would not solve the experience. The current drop resolver rejects every target inside the dragged selection, including valid insertion boundaries for noncontiguous selections. Selection buttons also need a clearly separate grab surface and must not contain an editable field.

**Decision.** Add a visible drag handle and insertion cue. Resolve drops by insertion boundary, keeping selected items in their relative order. Accept only the current editor's valid drag payload; an intervening edit invalidates a stale drag. Retain keyboard movement as an alternative.

Make the visible output position editable in Merge and Organize. Enter moves the edited item to that final position; Escape or leaving the field cancels. If other selected items move with it, their relative order stays intact and the valid destination range is shown. Reject invalid input instead of silently moving to a different position. A completed move is one undo action.

**Acceptance.** Cover first/last positions, multi-selection, selected-target drops, no-op drops, malformed or foreign providers, stale drag tokens, bounds, removal, undo/redo, and export order. While a position is being edited, editor-level Delete/Select All/move shortcuts must not override text editing. On a Mac, verify pointer drag across the list/grid, scrolling, visible insertion markers, cancel outside the editor, and the number field with keyboard navigation. Unit tests and successful compilation alone do not establish physical drag usability.

## B1 — Reduce the Installed Payload Without Removing Capability

The audit used the public **0.1.19 universal ZIP**. Sizes below use decimal MB and logical file sizes, not filesystem allocation or runtime memory.

| Item | Measured size |
| --- | ---: |
| App ZIP download | 153.240 MB |
| DMG download | 164.820 MB |
| Files inside `Lemulip.app` | 349.100 MB |
| Engine support/source materials | 173.555 MB |
| `ffmpeg` | 59.890 MB |
| `ffprobe` | 59.502 MB |
| `magick` | 39.119 MB |

The website media are not inside the app. Removing screenshots from the website would not reduce the installed application.

**Measured candidate.** Four raw Git-export TAR archives (ImageMagick, AOM, libvpx, x264) total **123,371,520 bytes**. XZ preset 6 produced **20,267,932 bytes**. Decompressing each result reproduced its original SHA-256 exactly.

That is **103,103,588 bytes** of potential installed-file savings: approximately **29.5%** of this app's logical size, from 349.100 MB to about 245.997 MB. The existing ZIP already compresses the TARs, so the expected download improvement is much smaller: approximately **7.707 MB / 5.0%**, to about 145.534 MB. These are candidate estimates until a new package is built. The new DMG size has not been measured.

**Decision.** Compress only raw Git-export TARs in the shared source-fetch helper, before manifests are generated. Keep all matching source, notices, patches and build instructions. Preserve upstream archive downloads and pinned source revisions. Existing extraction supports standard compressed TARs. Do not remove codecs, runtime helpers, architectures, or sources in this slice.

**Acceptance.** Local fixtures prove deterministic output, byte-identical decompression, preserved members/permissions/timestamps and normal extraction. Both native engine builds must consume the archives, their universal merge must validate, and the packaged binaries must pass the existing conversion/relocation checks. Record actual app/ZIP/DMG sizes only from those new packages. Never replace 0.1.19 assets to deliver a size change.

**Later possibilities.** Native symbol stripping may reduce GUI/CLI binaries but needs a real build measurement and crash-diagnosis plan. Shared engine libraries and architecture-specific downloads change distribution complexity and need separate evaluation. The small repository-only Source ZIP is not a substitute for matching engine source material.

## A1 — Add a Quiet, Optional Selection Cue

**Decision.** A very short, soft selection sound belongs to the native app's operation choice. Begin with one committed-choice cue, not a sound on every pointer movement, file in a batch, progress update, or canceled action. Keep visual selection feedback complete on its own.

Add one setting, **Selection sounds**, default **off**, with an explicit preview control. Persist it across launches. Respect system output volume and the macOS UI-sound policy. Avoid interrupting music or installing an audio engine dependency for a tiny cue. Do not add website click sounds or autoplay audio.

**Sound direction.** A restrained, original tick with a rounded attack and a short tail, approximately 40–80 ms as a starting audition range. No bright notification bell, game reward chime, or long flourish. Choose the final timbre by listening on Mac speakers and headphones, not by treating a duration or waveform as proof of quality.

**Acceptance.** Exactly one cue for an eligible choice; none when disabled, canceled, unavailable, or repeatedly receiving the same event. Rapid choices cannot create an overlapping wall of sound. The setting and preview are keyboard-accessible and clearly labeled in English and Turkish. Test persistence, rapid inputs, active media playback, system volume/mute and VoiceOver. Start with this one cue; completion and error sounds are separate decisions after listening to the first.

## Research and What We Take From It

References were reviewed on 29 October 2026. Official product pages and their image assets informed the decisions; this is not a claim that every reference was tested interactively.

- [CleanShot](https://cleanshot.com/): concrete tasks and focused native examples, with deeper feature pages available separately. Take the specificity and hierarchy, not its testimonials or visual brand.
- [Dropover](https://dropoverapp.com/): show the defining gesture first, then explain file actions and advanced controls. This is especially relevant to Lemulip's drag-based entry point.
- [Screen Studio](https://screen.studio/): separate the result/recording from the editing interface and group detailed controls. Lemulip keeps its existing single demo stage and uses the gallery for actual app screens.
- [Raycast](https://www.raycast.com/): selected capabilities can lead to a deeper catalog without putting every option in the main narrative.
- [Hand Mirror](https://handmirror.app/): a small utility can feel specific and personable through an immediately understandable use case rather than a large collection of decorative sections.
- [Alcove](https://tryalcove.com/): its interactive product introduction makes the characteristic interaction something a visitor can try. Lemulip's wheel gets that focus; its own brand and file workflow remain the source of the design.
- [NotchNook](https://getnotchnook.com/): real product demonstrations connect a compact native surface with concrete tasks. Use this as a reference for purposeful product framing, not as evidence for any Lemulip feature, customer count or review.
- [Apple HIG: motion](https://developer.apple.com/design/human-interface-guidelines/motion): feedback should follow input, remain brief and be interruptible. The website uses a bounded wheel entrance and stable manual screen transitions; the native app keeps frequent actions immediate and observes Reduce Motion.
- [Apple Preview: add, delete or move PDF pages](https://support.apple.com/guide/preview/add-delete-or-move-pdf-pages-prvw11793/mac): dragging thumbnails is a familiar Mac interaction. Numeric placement adds a precise alternative for longer lists.
- [Apple HIG: playing audio](https://developer.apple.com/design/human-interface-guidelines/playing-audio), [accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), and [UI sound property](https://developer.apple.com/documentation/audiotoolbox/kaudioservicespropertyisuisound): sound should work with platform controls and visual feedback. Default-off and the proposed cue character are Lemulip product decisions, not a claim that Apple mandates them.

## Future Ideas Kept Separate

Editable DOCX from PDFs; slide-to-image export; Finder-compatible file references for paste; further floating-shelf work; photo adjustments; metadata editing; canvas/collage tools; and richer media editing remain candidates. They do not displace the quality work above, and they are not current features or promised release dates.
