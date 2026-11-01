# Native Verification Gate

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


The production-app acceptance suite runs a separately identified copy of Lemulip with its normal macOS event loop. External XCTest input drives the real controls. It is not a website simulation or a direct call to the editor's reorder method. Nothing is installed over a user's application.

## Coverage

The original 17 cases are retained without changing their assertions. Eight additional cases complete the old options matrix and the first-click cancellation requirement:

| Requirement | Real-app coverage |
| --- | --- |
| Quality, both languages | Exact label, numeric 0.82, `82 percent` / `Yüzde 82`, enabled and hittable |
| Maximum dimension, both languages | Exact label and `1920`, enabled and hittable |
| Playback speed, both languages | Exact label, numeric 2.0, `2.00 times` / `2,00 kat`, enabled and hittable |
| Volume, both languages | Exact label, numeric 1.5, `150 percent` / `Yüzde 150`, enabled and hittable |
| PDF page range, both languages | Exact label and `1`, enabled and hittable |
| First-click Cancel while a number draft is active | Both PDF editors; no preliminary Return, Escape or blur; one click closes; no output, unchanged originals and clean reopen |
| Existing PDF interactions | All 13 prior drag, group selection, Undo/Redo, scrolled 18-file/24-page, invalid-number, cancellation and unchanged-number cases |

Media options require a real available FFmpeg. The workflow records its executable path and version, generates a short WAV and decodes it before opening it in the application. Neither engine availability nor spoken slider values are mocked. The read-only accessibility helper rejects untrusted access and targets only the isolated review application.

## Verified Parity Before Migration

On 31 October 2026, [run 41223816503](https://github.com/osmankaankars/lemulip/actions/runs/41223816503) passed **25 of 25 cases on each architecture** before the old acceptance roles were moved. Head `0ba87ce6ed32361c3cb5e66998a92e7eb1657edd` tested merge `a7e0668b7a78d979ad6d22d932b87d6725122a2a`, tree `a10369977333bea3be44386e7e39f5d47a915d74`. The original 17 test cases were retained byte-for-byte, and the eight new cases passed with no changes to production code.

Both downloaded result archives passed advertised-size, SHA-256, ZIP CRC and source-provenance checks. Their logs list all 25 distinct cases as passed, and their six trusted slider snapshots retain the exact English/Turkish descriptions. Combined XCTest source SHA-256: `fa9f2fb058c08360800193e87095fb9b85cb3f2122c9a8d9c11d773e7f1918de`.

| Architecture | Artifact | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| arm64 | `13051336758` | 4,760,182 | `46782d880a063846d67264dce5b80f72269fe19734cbc1a9b22e70dd34cc8121` |
| x86_64 | `13051092903` | 6,465,939 | `5d93b6c0353ae3e53a527c0ffcf0286c091da15098ce39476fedf9538a6c73c8` |

These are test-result archives, not application download-size measurements. The migration commit must itself be checked through the newly required native workflow; this prior parity result is not approval of a new package or release.

## Package Dependency

`build.yml` invokes `native-ui-review.yml` through a local reusable-workflow reference. GitHub uses the same commit for that reference, and the child workflow also checks `git rev-parse HEAD` against `GITHUB_SHA`. Both Apple Silicon and Intel jobs must succeed. The universal package explicitly needs `test`, `native-engines` and `native-ui`; neither a failed nor a skipped native gate is converted into success. No optional `continue-on-error` or test-filter shortcut is used.

The reusable workflow has no duplicate pull-request trigger. Main, tag and PR runs receive the gate from Build and Verify. Its distinct concurrency group cannot cancel the caller, and tag runs are not cancelled by later runs. Existing release coordination, published-asset protection and downloaded-archive verification remain unchanged.

## Legacy Diagnostics

The old `OperationOptionsAccessibilityTests` and four own-window pointer probes remain unchanged in source. They are available through the manual `Legacy Synthetic Native Diagnostics` workflow; an actual failure there still produces a failed diagnostic job and retained evidence. They no longer represent release acceptance after their user-facing requirements have been verified in the normally launched application.

Synthetic-host failures are not being relabelled as successes. The replacement checks real UI semantics, one-click cancellation, actual drag output and original bytes. Internal synthetic-event observations, such as inspecting a delegate's intermediate insertion cue, are not claimed as new external assertions. Visual cue quality remains part of the separate interaction/visual review.

## Remaining Manual And Distribution Checks

These automated cases do not replace listening to VoiceOver, auditioning optional sounds on speakers/headphones with system effects muted, continuous edge-autoscroll review, or authentic Retina captures. Complete those observations and verify the final full-engine universal archives before publishing the combined version. The promotional film remains last.
