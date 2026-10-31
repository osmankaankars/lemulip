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

### Current evidence

| Work | Current state |
| --- | --- |
| W1/W2/W4 | Live through PRs #19 and #22. Chromium and WebKit passed before and after deployment. |
| M1 | First-use links and guidance are live through PR #27. The current sharing-card and installation-order repair is recorded below. Download remains 0.1.19; new native visuals and the final release story are pending. |
| P1/P2 | PR #20 preserves tested export order and adds explicit order commands, position entry and drag handles. The focus-reset correction passed actual keyboard scenarios on both architectures. A later actual pointer check found that Cancel needed two clicks during a number edit; the correction now passes both first-click cases on Apple silicon in [run 40902646884](https://github.com/osmankaankars/lemulip/actions/runs/40902646884). Physical dragging remains unproved. |
| B1/B2 | PRs #21 and #28 are merged. Both hosts verified the exact combined universal package from main; measured app payload is 237,113,725 bytes. No smaller public release has been published. |
| A1 | PR #23 passes all 11 automated sound tests on both architectures. The exact generated sound is retained for audition; listening, system mute and the complete native settings review remain pending. |
| Q1 continuity | PR #25 passed the real crop keyboard path and final output-pixel assertions on both architectures at `7c0ac41` (186 ordinary tests plus 15 feedback/continuity tests on each). |
| Q1 feedback/accessibility | PR #26 includes bounded panel motion and localized control names/units. Hosted panel tests pass. Own-process accessibility inspection still does not expose the SwiftUI semantic nodes after a verified launch/key-window lifecycle; VoiceOver success is not claimed. |
| W3 | Bitmap and explicit-display-scale probes did not produce sharp complete SwiftUI captures. The native PDF probe omitted SwiftUI geometry and its actual raster transform remained 1×. All three routes are closed for marketing assets; real Retina captures are still required. |
| V1 | Last, after the verified app, accurate website story and final native visuals. |

The isolated [UI review copy](https://github.com/osmankaankars/lemulip/blob/f402dabbdbd34ba9ea80ac38495caffb2bdf29d1/docs/UI_REVIEW.md) combines the native feature branches with 0.1.20/build 23 preparation. Its distinct bundle identity separates preferences. A dedicated workflow retains a review ZIP only after both native hosts verify that same ZIP, but its engine-free payload and those checks do not establish release readiness or physical interaction quality. The [retained review build](https://github.com/osmankaankars/lemulip/actions/runs/40903073501) passed both native checks of the same ZIP. The combined normal [Build](https://github.com/osmankaankars/lemulip/actions/runs/40903073393) passed 200 ordinary tests, two actual PDF keyboard scenarios and 15 sound/continuity tests per architecture, but still fails the exact accessibility lookup in its own-process host. Physical dragging, audible/muted playback, VoiceOver narration and final Retina captures remain open. Normal build and release gates remain in place.

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

**Measured source payload.** Four raw Git-export TAR archives (ImageMagick, AOM, libvpx, x264) total **123,371,520 bytes**. XZ preset 6 produced **20,267,932 bytes**. Decompressing each result reproduced its original SHA-256 exactly.

**Built universal candidate.** [Build run 40872540142](https://github.com/osmankaankars/lemulip/actions/runs/40872540142) produced the actual app, ZIP and DMG from source-compression head `c5ccf51cdfb35da2dce831ffb5bb47968777d4fa`. Archive hashes, CRCs, 65 installed receipt hashes, all 18 matching source/license components and the compressed source round trips were checked.

| Item | Public 0.1.19 | Built B1 candidate | Reduction |
| --- | ---: | ---: | ---: |
| Logical files inside the app | 349,100,211 B | 245,999,805 B | 103,100,406 B / 29.53% |
| App ZIP | 153,240,283 B | 145,534,426 B | 7,705,857 B / 5.03% |
| DMG | 164,820,266 B | 151,979,361 B | 12,840,905 B / 7.79% |

The smaller download improvement is expected because the old ZIP already compresses the raw TAR files. These are measured candidate sizes, **not a new public download**. Both final native checks passed against the exact same universal archives before PR #21 was merged. Rebuilt executable files need not have identical bytes; the audit establishes matching source, recipes and licenses, then relies on the native package checks for behavior.

**Decision.** Compress only raw Git-export TARs in the shared source-fetch helper, before manifests are generated. Keep all matching source, notices, patches and build instructions. Preserve upstream archive downloads and pinned source revisions. Existing extraction supports standard compressed TARs. Do not remove codecs, runtime helpers, architectures, or sources in this slice.

**Acceptance.** Local fixtures prove deterministic output, byte-identical decompression, preserved members/permissions/timestamps and normal extraction. Both native engine builds must consume the archives, their universal merge must validate, and the packaged binaries must pass the existing conversion/relocation checks. Record actual app/ZIP/DMG sizes only from those new packages. Never replace 0.1.19 assets to deliver a size change.

**Further work.** GUI/CLI symbol reduction is covered by B2 below. Shared engine libraries and architecture-specific downloads change distribution complexity and need separate evaluation. The small repository-only Source ZIP is not a substitute for matching engine source material.

## A1 — Add a Quiet, Optional Selection Cue

**Decision.** A very short, soft selection sound belongs to the native app's operation choice. Begin with one committed-choice cue, not a sound on every pointer movement, file in a batch, progress update, or canceled action. Keep visual selection feedback complete on its own.

Add one setting, **Selection sounds**, default **off**, with an explicit preview control. Persist it across launches. Respect system output volume and the macOS UI-sound policy. Avoid interrupting music or installing an audio engine dependency for a tiny cue. Do not add website click sounds or autoplay audio.

**Sound direction.** A restrained, original tick with a rounded attack and a short tail, approximately 40–80 ms as a starting audition range. No bright notification bell, game reward chime, or long flourish. Choose the final timbre by listening on Mac speakers and headphones, not by treating a duration or waveform as proof of quality.

**Acceptance.** Exactly one cue for an eligible choice; none when disabled, canceled, unavailable, or repeatedly receiving the same event. Rapid choices cannot create an overlapping wall of sound. The setting and preview are keyboard-accessible and clearly labeled in English and Turkish. Test persistence, rapid inputs, active media playback, system volume/mute and VoiceOver. Start with this one cue; completion and error sounds are separate decisions after listening to the first.

## Q1 — Finish Native Interactions Together

[PR #25](https://github.com/osmankaankars/lemulip/pull/25) fixes a concrete interruption: canceling the destination chooser previously cleared the pending edit and closed several editor sessions. The change retains the arrangement, crop or trim until an output destination is accepted, and rejects duplicate or stale submission.

[PR #26](https://github.com/osmankaankars/lemulip/pull/26) adds brief native panel entry (90 ms for the wheel, 140 ms for the result card), immediate input eligibility and dismissal, live reduced-motion/transparency handling, and explicit localized option-control names and values. Its [editor review matrix](https://github.com/osmankaankars/lemulip/blob/758e07a4d056d1485ba6354b9079b7d2631b6001/docs/EDITOR_REVIEW.md) tracks scenarios and the distinction between rendered views, model tests and actual input delivery.

**PDF extraction input follow-up.** The options form previously accepted any nonempty
page-range text. A malformed entry such as `1,,2` or `3-1` closed the form and
created a failed job; Retry repeated the same invalid request. The shared page-range
parser now lets the form show a specific English/Turkish syntax error, disable its
default action and retain the text for correction. A corrected `3,1-2,3` still
exports pages `3,1,2`, preserving first-occurrence order and the original document.

The bounded parser checks syntax without expanding ranges while someone types.
Document-specific page-count checks remain in the converter. The native regression
uses the production options view, own-window AppKit key events and real PDF output
on both architectures; the build retains its captures and observations separately
from physical keyboard and VoiceOver review. This change does not alter the frozen
`f402dabb` UI review copy or complete the other native release gates.

## B2 — Measure and Retain Matching Symbols

[The two-architecture experiment](https://github.com/osmankaankars/lemulip/actions/runs/40879083064) at `43d441911b311b29960aa7f01738a88e3b59b16a` measured copies of the GUI and CLI using the same signing treatment for the baseline and variants. Removing debug and local symbol entries (`strip -S -x`) preserved UUIDs, runtime section bytes, dependencies, imports, exports and dynamic-loader payloads. Matching dSYMs were produced and verified before stripping.

| Architecture | Product | Signed baseline | Signed stripped copy |
| --- | --- | ---: | ---: |
| Apple silicon | GUI | 7,400,192 B | 2,954,736 B |
| Apple silicon | CLI | 1,867,440 B | 1,244,672 B |
| Intel | GUI | 7,598,336 B | 3,149,840 B |
| Intel | CLI | 1,961,104 B | 1,335,856 B |

The experiment above changed no production package and measured no ZIP or DMG. [PR #28](https://github.com/osmankaankars/lemulip/pull/28) subsequently adopted the verified process in production: it stages only Release GUI/CLI copies, retains matching symbols and commit/UUID/hash records outside the shipped app, and keeps original build products intact. Debug builds and bundled engines remain outside this change.

[The exact implementation's native checks](https://github.com/osmankaankars/lemulip/actions/runs/40884107022) passed on Apple silicon and Intel, including actual GUI launch, a subtitle conversion, retained Debug binaries, and matching dSYM UUID/architecture/DWARF validation. The ordinary build and CodeQL checks also passed before merging. Required CI symbol artifacts are retained for 90 days.

**Combined package measured.** [Main run 40888274702](https://github.com/osmankaankars/lemulip/actions/runs/40888274702), at `5d86c6bf76a09653ae8b0c14f68efb8f0aff9e56`, built B1 and B2 together. Both native hosts verified the same universal artifact `12907867184` (SHA-256 `20aca7ba1301d765cecd14848547544655e61b571ba6a4f93caa683a48883d32`). This candidate still carries 0.1.19/build 22 metadata and is not a replacement public download.

| Item | Public 0.1.19 | Combined B1+B2 candidate | Reduction |
| --- | ---: | ---: | ---: |
| Logical files inside the app | 349,100,211 B | 237,113,725 B | 111,986,486 B / 32.08% |
| App ZIP | 153,240,283 B | 144,203,490 B | 9,036,793 B / 5.90% |
| DMG | 164,820,266 B | 149,920,290 B | 14,899,976 B / 9.04% |

The Source ZIP grew from 2,426,675 to 2,461,318 bytes as source code and checks were added. The application measurement uses logical file payload sizes, not filesystem allocation. The standalone CLI contributes to the ZIP, but not to the app or DMG totals.

The downloaded candidate passed all 65 installed receipt hashes, retained all 18 source/license components, preserved 14 upstream archives byte-for-byte and reproduced the four original Git TARs exactly after decompression. Its actual universal GUI/CLI hashes and four architecture UUIDs match the separately retained dSYMs. Both native archive checks passed signature, relocation, built-in and bundled conversions, original preservation, DMG validation and GUI launch. Independently rebuilt engine executables are not claimed to be byte-identical across builds.

The feature-inclusive 0.1.20 app, ZIP and DMG still need their own complete release build and both native checks. No existing public release asset is replaced, and a lightweight UI review package must not be compared with these complete-engine distribution sizes.

## M1 — Repair the Current Sharing and First-use Path

**Observed problem.** The public share metadata still selected an obsolete browser
simulation with the retired headline and controls. The “Install & first steps”
link jumped past installation and first-launch instructions to a step that assumed
the app was already open.

**Decision.** Use a 1200 × 630 composition with the current Lemulip identity and the
existing genuine Workspace capture. Its native image stays at 510 × 341.5 pixels;
its source bytes and capture provenance remain unchanged. This repairs the current
0.1.19 presentation. It does not complete W3 or imply a new native capture.

Start the installation link at the guide's beginning and order the material as
release installation, first launch, then the built-in sample. Keep source-build
instructions later and retain the existing deep links.

**Acceptance.** Inspect the full-size and smaller card, retain source/output hashes,
and verify the actual prepared and deployed canonical/Open Graph/Twitter metadata,
image decoding and checksum in both browser engines. Production must use its actual
Pages URL. A pull-request fixture URL must never imply public deployment. Keep the
verified 0.1.19 download and all native release gates unchanged.

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
