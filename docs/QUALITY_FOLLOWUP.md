# 0.1.20 Quality Roadmap Follow-Up

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


Updated 31 October 2026. This supplements [the product roadmap](ROADMAP.md). The candidate is **not a published download**. Public downloads remain **0.1.19 / build 22**. The promotional film remains last.

## Source and Integration

[PR #33](https://github.com/osmankaankars/lemulip/pull/33) preserves frozen review `f402dabbdbd34ba9ea80ac38495caffb2bdf29d1` and main `4d97ea785ddd2920532587444c94a19a35563191` as parents. The original review branch and its artifact remain unchanged. Installation/sharing work and PDF page-range validation from #31 and #32 are included alongside PDF ordering, optional sound, editor continuity and panel feedback.

The options form retains both localized names/units and guarded PDF range submission. Native suites run in separate processes after compilation so a failed sibling no longer hides later results. Every failed check still fails its job. No assertion is disabled and no failed check is converted into a pass.

## P2: Actual Pointer Reordering Now Verified

Two concrete production corrections are in the candidate:

1. Declare the existing opaque `app.lemulip.pdf-merge-document` and `app.lemulip.pdf-organizer-page` payloads in `UTExportedTypeDeclarations`, conforming to `public.data`. No filename extension is claimed. Own-process payload visibility, token matching, stale-generation protection and ordering logic are unchanged. The new declaration contract failed for both missing types before the change and passes afterward.
2. Attach the Organizer thumbnail's existing drag modifier to its visible Button label content rather than the outer Button. Selection actions, accessible names, keyboard alternatives, drop resolution and export remain unchanged.

### Regression Evidence

- [Baseline run 41189883290](https://github.com/osmankaankars/lemulip/actions/runs/41189883290), head `5708e123`: the external test reaches actual production windows, but both Merge and Organizer reorder assertions fail.
- [Run 41193058639](https://github.com/osmankaankars/lemulip/actions/runs/41193058639), head `44d0632`: after the type declarations, Merge dragging, actual output order and original-byte assertions pass on **both architectures**. Organizer thumbnail dragging still fails.
- [Run 41193692948](https://github.com/osmankaankars/lemulip/actions/runs/41193692948), head `23db1fb8`: an independent Organizer handle test passes on **both architectures**, including actual output and unchanged original bytes. The original thumbnail scenario is retained and still fails, isolating the remaining problem to that drag surface.
- [Run 41194218970](https://github.com/osmankaankars/lemulip/actions/runs/41194218970), head `8c9e1ddf81ef380141c0dead74ee82aae70813c3`: after the one-modifier move, **Merge handle, Organizer thumbnail and Organizer handle all pass on Apple Silicon and Intel**. The test source is unchanged from the preceding red thumbnail run.

The final native run tested merge `6b13851759114bc2b9e58e672468c28f321f2cbf`, source tree `ea4ebea70f6cd372930bd3bcadf5cc7b43441ca6`. Both retained provenance records identify that tree and test-source SHA-256 `f3774570c38fb5695ab602ba2054183ccbc8954be0e63d2def05b469437f3c4c`.

| External production-app scenario | Apple Silicon | Intel |
| --- | --- | --- |
| English maximum-dimension field: exact name, value, enabled/hittable state | Pass | Pass |
| Turkish maximum-dimension field: exact name, value, enabled/hittable state | Pass | Pass |
| Merge handle drag, displayed positions, exported PDF, unchanged originals | Pass | Pass |
| Organizer thumbnail drag, displayed positions, exported PDF, unchanged original | Pass | Pass |
| Organizer handle drag, displayed positions, exported PDF, unchanged original | Pass | Pass |
| English Quality spoken-value description | Blocked: runner AX permission | Blocked: runner AX permission |
| Turkish Quality spoken-value description | Blocked: runner AX permission | Blocked: runner AX permission |

The tests launch a separately identified copy of the real app with its normal event loop. They open synthetic files through the app, search for the operation, use external XCTest pointer input, inspect updated position fields and click the production Create Copy control. Merge output is Report page 1, Report page 2, Notes, Cover. Organizer output is pages **2, 1, 3, 4**. Original input bytes are compared after export.

These are actual automated native interactions, not a web simulation or direct calls to the editor's reorder method. They establish the listed scenarios, not every long-list, scroll, multiselection, undo or physical-device interaction.

### Retained Artifact Audit

The final artifacts were downloaded and checked against advertised sizes, SHA-256 and ZIP CRCs. Logs and provenance were read, not inferred from an overall workflow badge.

| Architecture | Artifact | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| arm64 | `13039413886` | 95,356,307 | `e857351fb85acb0114351884aa369393911713c04f583db4100ed61dfa1e8a34` |
| x86_64 | `13040375176` | 56,547,561 | `7c031971f68dea0302c7402ed1f613092186558af7264efab431c7b2c0c32ddb` |

`provenance.json` is a staging receipt and deliberately says `testStatus: NOT RUN`; test outcomes come from the subsequent XCTest log/result bundle. It is not a pass receipt or release approval.

## Q1: Accessibility Findings and Honest Test Status

XCUIAutomation exposes the Quality slider's numeric value as `NSNumber(0.82)`, not the human-readable spoken string. The external test now verifies the raw number and separately requests the exact localized `AXValueDescription`; it does not drop the localized-unit requirement. Exact Quality/Kalite labels and numeric-value assertions are reached successfully.

Both CI runners lack direct accessibility permission for the test process. The public `AXIsProcessTrusted()` check therefore fails before the spoken-description query. **No TCC database edit, permission bypass, fallback value, skipped assertion or VoiceOver pass is introduced.** Each final external suite has seven tests: **five pass, two fail on that permission gate**. Its overall result remains failed.

[Normal Build 41194219054](https://github.com/osmankaankars/lemulip/actions/runs/41194219054) compiles on both architectures and passes general/model tests, PDF keyboard interaction, feedback/continuity and PDF-range correction. Its older own-process accessibility lookup still fails on both hosts; its ARM own-window synthetic pointer review also fails. Those distinct hosts are not substituted for the external real-app results, nor silently removed. Engine integrations and normal release packaging did not run after those failed gates. The entire build is not green.

Local Linux checks: **174 Python helper tests passed**, staged privacy checks passed for 200 public source files, and whitespace checks passed. The full `swift test --jobs 2` run executed 150 tests and failed three Pandoc integrations:

- `EngineIntegrationTests.testAdvancedMarkdownWordFallbackNormalizesUTF16WithoutChangingInputs`
- `EngineIntegrationTests.testAdvancedMarkdownWordUsesPandocForTheWholeBatch`
- `EngineIntegrationTests.testPandocMarkdownHTMLAndEPUBRoundTrip`

The installed Linux Pandoc lacks the embedded-template/sandbox behavior required by those tests. These failures are recorded rather than represented as a green full suite; Linux checks do not verify SwiftUI behavior.

## Remaining Order of Work

1. Complete the broader PDF native review: noncontiguous/multiple selection with pointer movement, scrolling, undo/redo and cancellation. Preserve the three passing external drag/export regressions.
2. Resolve the remaining accessibility verification path using appropriately authorized native review, including actual VoiceOver narration. Keep unresolved hosted-test results visible and reconcile the test hosts before merging; do not weaken the checks to manufacture green status.
3. Review the optional cue on Mac speakers/headphones, system volume/mute and concurrent media playback. Source/waveform tests alone are not a listening review.
4. Verify the final combined full-engine universal ZIP/DMG on both architectures, then publish a new version without replacing 0.1.19 assets.
5. Capture genuine high-density images from the final native app and update the public feature story. Do not upscale 1x test captures or claim the candidate is already downloadable.
6. Produce the promotional film last.

This follow-up advances P2 and distinguishes the remaining Q1 test-host limitations. It does not close every native quality gate, merge the candidate, modify public downloads or publish 0.1.20.
