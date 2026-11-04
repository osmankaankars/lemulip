# Native Verification Gate

## Published Version Evidence — 1 November 2026

PR #33 is merged, including real wheel-selection sound routing. Its 29 real-app
cases passed on Apple Silicon and Intel; old synthetic diagnostic failures below
are historical, not current product failures. A new **seven-case full-app visual
review and genuine 2x capture pass** is recorded in [VISUAL_REVIEW.md](VISUAL_REVIEW.md).

Kaan will assess audible sound/system mute and VoiceOver narration during routine
use and report problems. Those physical observations are not claimed complete and
are not a release blocker by the owner's explicit instruction. Final publication
uses the exact v0.1.20 tagged archive verification; older candidates are not relabelled.
Website delivery is tracked in [ROADMAP.md](ROADMAP.md). The promotional film is last.

## State And Accessibility Review Coverage

The external suite retains the existing 48 cases and adds ten bounded checks:

- Orchard, Pistachio and Lemonade in English and Turkish. Each case confirms the
  selected theme through the real Settings controls, measures the minimum
  workspace, reads the full long-filename recovery message, and exercises
  Command-F and Escape. The PDF, audio and video keyboard checks are distributed
  across the six cases. The 720-by-560 content layout and the outer window with
  its native title bar are recorded separately. Editor sheets retain their actual production sizes;
  a small parent window is not evidence of a small editor.
- Real Finder drops into an already populated workspace in all three themes:
  a new file, the same file again, two selected files, and a rejected drop outside
  the file area. These assert the resulting file rows and unchanged source bytes.
  Their atomic XCTest gestures do not prove the outline's intermediate states.
- Real System Settings changes for Reduce Motion and Reduce Transparency, with
  independent NSWorkspace readback, wheel keyboard use, PDF output validation and usable
  result cards. The original system values are restored in teardown. A still
  screenshot does not establish the first animation frames or fade duration.
  Both the first and reused result card must fit completely inside the display's
  visible area, with every action enabled and reachable above the Dock. Their
  window, action and visible-screen rectangles are retained with the real images.

The isolated application starts with explicit normal theme and saved-frame
preferences to prevent one case from changing another case's starting state.
The existing authenticated, read-only AX helper also reports the actual focused
element in that same application; it does not set focus or grant authorization.
The focused element's AXEnabled read status and Boolean are recorded separately,
so unsupported or absent values cannot be reported as disabled. Interactive audio
and video canvases must be enabled in both the direct AX reading and XCTest.
Each added source fragment and the assembled suite have recorded SHA-256 values.
Audio resume checks retain live AX position samples, then pause before recording
the full AX tree and screenshot so evidence capture leaves time for the next
keyboard resume check. The existing playback and focus assertions are retained.
The same authenticated local reviewer also exposes a separate read-only resource
for two public system display-preference booleans. Each request runs a fresh
NSWorkspace reader outside the XCTest host and works after the review app has
stopped. Both the actual Settings switches and this reader must agree; unchanged
test-host observations are retained only as diagnostics. No defaults or permission
settings are written by either reader.

A separate in-flight Finder observer runs the same held drag in Orchard,
Pistachio and Lemonade: entering, leaving and re-entering the expanded file
target, Escape cancellation and an accepted drop. Each theme has its own
bounded run and evidence folder. The observer confirms that its application
has stopped and its mouse button has been released before the next theme.
Bounded startup waits retry transient AX window/title reads. Only the initial
workspace readiness wait also retries `cannotComplete` on `AXChildren`, retaining
the retry count and last error within its original deadline. The exact application
and fixture windows must still be found before proceeding.
Only the initial Finder icon readiness wait retries `invalidUIElement` across
attributes, including the observed `AXValue` and `AXRole` reads, within the same
bounded deadline. It retains every error's attribute, status and observation time,
the retry count and the last error. PID and identity failures remain fatal. These
startup retries do not apply to later gesture observations.
The startup phase is retained to locate failures in initial workspace content,
Finder icon readiness or target geometry reads without suppressing those failures.
Only those two verified windows are raised, with the fixture window above the
drop target. A setup image, geometry and per-point PID/status records are retained
before hit checks; every pointer target must still belong to its expected process.
The Finder view shortcut carries Command only on key-down and releases it in the
paired key-up. The observer refuses pre-existing Command, Shift, Option or Control
state and uses the existing bounded readiness wait for the shortcut modifiers
to clear. Ordinary pointer events require that clear state and explicitly carry
no modifiers. Input receipts retain constructor, posted and observed modifier
flags, so a modified drag cannot silently stand in for the intended plain drag.
Escape evidence retains the foreground application and actual mouse-button state
before and after key posting and release. At the existing cancellation deadline,
one AX traversal records the expected and observed fixture rows, duplicate Remove
matches and selection-count labels. Its result is fixed before the post-Escape
image is captured, then checked with the same cancellation requirement, so a
failed assertion retains the state that caused it without extending its wait.
The observer's Escape press uses the global user-session event path for a controlled
continued-motion experiment. Two nominal 75 ms waits surround one `leftMouseDragged`
update of +1 point horizontally, only while the probe owns the held mouse button and
both the mouse button and Escape are reported down. Before the gesture, that point
is checked inside the same top padding and review window, outside the fixture Finder
window, and against the target PID. Release uses that verified point. The paired
key-up still runs on an error. The nominal waits total 150 ms; guards, event posting,
sampling and scheduling add to the actual interval. Input records retain the sent
locations, actual key/button states and monotonic observation times. This is an
observer protocol experiment, not a product fix or an Apple timing requirement.
Additional diagnostics record workspace contents and the verified application's
focused element before Escape and again while the mouse is still held afterward.
That held image is stored separately from the seven gesture stages. These AX reads
and the extra image extend the key-to-mouse-release interval; monotonic timestamps
and the measured observation delay retain that distinction. The existing
post-release cancellation requirement still applies.
It checks existing Accessibility, event-posting and screen-capture
authorization without requesting or changing permissions. A `blocked` report
means that observation is unavailable. A `captured` report proves its recorded
gesture outcomes; the combined report requires all three themes to be captured.
The outline still requires inspection of the actual frames.
This diagnostic has no write endpoint. Both data readers remain read-only.
It can retain evidence after a completed, failed XCTest run; that separate result
does not make a failed native gate pass. Cancelled or unbuilt runs do not start it.

A separate macOS diagnostic also runs the fixed Finder observer when its source
or fixture staging changes. It records `diagnosticOnly: true` and
`xctestExecuted: false`, with separate artifacts. This provides earlier observer
evidence on a fresh host; the required complete native suite and its post-suite
observer still run on both architectures. Existing authorization can differ
between the two environments and remains part of each report.

The isolated `--control` diagnostic repeats that exact input sequence against
`app.lemulip.NativeDragControl`, a separate standard AppKit file destination.
It does not alter the production app or its acceptance checks. The control logs
drag-destination callbacks and passively records Escape events passing through
`NSApplication.sendEvent`; it always calls the normal implementation. An absent
`sendEvent` record does not prove that AppKit's tracking loop never received the
key. The three fixture labels are not appearance tests in this control. Its
separate `NativeDragControlEvidence` retains its own executable/source hashes,
screenshots and callback receipts. A failed cancellation remains failed, and the
production observation starts only after every control cleanup is confirmed.
The diagnostic branch runs this comparison without replacing the required native
gate. Comparing these targets can distinguish a product-specific result from a
shared automation result; it does not certify physical keyboard behavior.

Compilation, executed XCTest results, screenshots and any separate live-drag
report must be inspected together for the candidate under review. Source tests
and successful staging alone do not establish runtime success. These checks do
not certify VoiceOver speech or physical audio playback.

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
