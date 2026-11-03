# Product Quality Roadmap

Updated **2 November 2026 (Europe/Istanbul)**.

## Current Delivery

**0.1.20 / build 23 is published.** The exact tagged source is
`eaa783c949a1814130a6618395269ba17c1baa6f`. The website presentation was merged in
PR #34 after the public release assets were verified. Website refinements in
[PR #36](https://github.com/osmankaankars/lemulip/pull/36) and
[PR #37](https://github.com/osmankaankars/lemulip/pull/37) shipped on 2 November;
they do not change the published application. See
[the delivery record](RELEASE_DELIVERY_0.1.20.md) for hashes and final live checks.

| Work | Delivery status |
| --- | --- |
| P1/P2: PDF ordering | Released: incoming/natural/reverse order, handle and thumbnail dragging, numeric positions, grouped selection, Undo/Redo, first-click Cancel and long-list fixes. |
| A1: Optional sound | Released: changed wheel choices and accepted actions use the shared cue. Default off; repeats, centre, opening/reset and cancellation remain quiet. |
| Q1: Native finish | Completed for this pass: 29 real-app cases per architecture and seven full-app visual scenarios. Findings and coverage limits are in [VISUAL_REVIEW.md](VISUAL_REVIEW.md). No new blocking visual defect was observed; no speculative UI rewrite was added. |
| B1/B2: Smaller payload | Released with both architectures and bundled engines/source/license files retained. Final ZIP: 144,331,845 bytes; DMG: 149,992,570 bytes; logical app files: 237,418,447 bytes. |
| W1/W2/W4: Product page | Shipped in #36/#37: direct task-led copy, compact key guide and catalog, selected-example playback that stops at the result, visible replay framing and native page scrolling. Three themes, nine sample families and verified 0.1.20 downloads retained. [Live Chromium/WebKit checks](https://github.com/osmankaankars/lemulip/actions/runs/41465598855) passed at five viewport sizes. |
| W3: Fresh captures | Four real 2040 x 1400 captures of 1020 x 700 native windows. Temporary macOS HiDPI display, no enlarged 1x images or repainted controls; not a physical Retina-panel claim. |
| M1: Release presentation | Current Workspace/PDF Pages/Crop Video/Trim Audio images, task-led copy and refreshed 1200 x 630 sharing card. See delivery evidence for actual deployed browser checks. |
| Daily-use feedback, including sound / VoiceOver follow-up | Completed by owner acceptance on 1 November 2026: Kaan reported no issues and explicitly requested closing this stage. This is user acceptance, not an automated acoustic or VoiceOver narration certification. |
| V1: Promotional film | The separate 25-second illustrated film and its final voice/music direction were approved by the owner. Keep it distinct from the site's real Finder recording. This records creative approval; it does not claim the final MP4 is archived in this repository. |

## Product Direction and Guardrails

Keep Lemulip a precise, lively Mac utility: drag a file, choose an operation,
inspect the result. Preserve its icon, three themes, operation wheel and local
processing. Lead with concrete jobs; keep the larger catalog available on demand.
Use [DESIGN.md](DESIGN.md) for motion/type decisions and
[MARKETING.md](MARKETING.md) for the current product story. The website's protected
choices and reference roles are recorded in [WEBSITE.md](WEBSITE.md).

Conversion creates a new copy without replacing the original. Explicit Move is a
separate file action. Every public feature and size claim must match the adjacent
released download. Real captures must retain commit, geometry and hash provenance;
a simulated browser interaction is not a native app recording.

## Later Work, Not Required to Finish 0.1.20

Further distribution changes, such as shared engine libraries or architecture-
specific downloads, need separate measurement and evaluation. Candidate features
remain: editable DOCX from PDF, slide-to-image export, Finder-compatible paste
references, additional shelf work, photo adjustments, metadata editing,
canvas/collage tools and richer media editing. These are not promised features or
dates, and do not displace issue reports from actual use.

## Historical Decisions and Evidence

The complete previous roadmap, including original decisions, acceptance criteria,
reference research and candidate measurements, is preserved **byte-for-byte** in
[the pre-delivery record](ROADMAP_HISTORY_20261101.md).
Its older PR/download states are historical, not current blockers. PR #33 merged
the native work; superseded PRs #20/#23/#25/#26/#30 retain their commits and reviews.
