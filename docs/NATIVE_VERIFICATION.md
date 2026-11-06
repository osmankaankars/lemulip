# Native Verification Gate

## Current Improvement Cycle — 6 November 2026 UTC

The current candidate's source identity, retained C12 visual review and open
acceptance gate are recorded in [the task 08 review](STATE_ACCESSIBILITY_REVIEW_08.md).
PR #45 remains on hold for the held-drag Escape failure. Its successful 58-case
native suite and the separate diagnostic comparisons do not close that gate.

## Published Version Evidence — 1 November 2026

PR #33 is merged, including real wheel-selection sound routing. Its 29 real-app
cases passed on Apple Silicon and Intel; old synthetic diagnostic failures below
are historical, not current product failures. A new **seven-case full-app visual
review and genuine 2x capture pass** is recorded in [VISUAL_REVIEW.md](VISUAL_REVIEW.md).

The daily-use follow-up was subsequently closed by the owner's 1 November
acceptance, as recorded in [RELEASE_DELIVERY_0.1.20.md](RELEASE_DELIVERY_0.1.20.md#owner-acceptance).
That acceptance does not claim separate automated acoustic, mute or VoiceOver
certification. Final publication used the exact v0.1.20 tagged archive; older
candidates are not relabelled. The older work-order and manual-check lists below
are historical. Film work is outside the current task 07/08 acceptance scope.

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
none of those four modifiers. Input receipts retain constructor, posted and observed modifier
flags, so a modified drag cannot silently stand in for the intended plain drag.

The D7 diagnostic comparison preserves ordinary pointer-event constructor flags
except Command, Shift, Option and Control, while retaining the refusal to post
when any of those modifiers is held. D6 receipts include constructor bit
`0x20000000`; its meaning has not been established. Keyboard events, the HID
event source, suppression filters and interval, configured timing, cleanup,
production code and acceptance gate criteria remain unchanged. Existing
constructor and posted flag receipts record the difference; this is an input
experiment, not a verified cancellation fix.

Escape evidence retains the foreground application and actual mouse-button state
before and after key posting and release. At the existing cancellation deadline,
one AX traversal records the expected and observed fixture rows, duplicate Remove
matches and selection-count labels. Its result is fixed before the post-Escape
image is captured, then checked with the same cancellation requirement, so a
failed assertion retains the state that caused it without extending its wait.
The observer's Escape press uses the HID event entry point for a controlled
continued-motion comparison after the shortcut modifier fix. Earlier HID trials
predated that fix and do not establish this combination's outcome. This comparison
changes only the Escape posting location from the prior Quartz protocol; it does
not claim physical input. The public [event-tap locations](https://developer.apple.com/documentation/coregraphics/cgeventtaplocation)
identify different insertion points in the event stream, not cancellation guarantees.
Two nominal 75 ms waits surround one `leftMouseDragged`
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
`nativeAcceptanceXCTestExecuted: false`, with separate artifacts. This provides earlier observer
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

After both three-theme observations have confirmed cleanup, a separate
`--keyboard-control` comparison may run against the same standard AppKit target
for Orchard only. It uses a separately built XCTest runner and one public
`XCUIApplication.typeKey(.escape, modifierFlags: [])` call. This runner is not
part of the 58 production acceptance tests. Its nonce-bound, expiring request
requires the exact control app path and PID, that app in the foreground, the
observer's held mouse button, clear modifiers and Escape released. The driver
does not explicitly launch or activate the target. Public XCTest may still
perform its own activation or idle waits; passive application-activity receipts
and actual key events must be inspected before interpreting the outcome.
The comparison omits the CG Escape dwell and one-point motion, retains the
existing cancellation assertion and fresh accepted drop, and records separate
`NativeDragKeyboardEvidence`, runner/source hashes and protocol logs. Successful
keyboard injection alone does not satisfy cancellation. READY, request and
completion waits are bounded within the observer's theme deadline. Cleanup
stops only its own driver process and exact identified runner before proceeding;
an unconfirmed stop prevents further optional input. A blocked or failed driver
does not establish a product defect or physical-keyboard behavior.

Compilation, executed XCTest results, screenshots and any separate live-drag
report must be inspected together for the candidate under review. Source tests
and successful staging alone do not establish runtime success. These checks do
not certify VoiceOver speech or physical audio playback.

### Capture-Only Observer Comparison

The separate `Native Finder Capture Comparison` workflow isolates the image
capture path from the existing standalone observer. It builds the pinned C12
application once, then uses the same staged application, fixtures, observer and
host for four serial Orchard cases: standard AppKit control with screenshots,
control with AX-only observation, production with screenshots, and production
with AX-only observation. ARM64 and Intel run independently. The diagnostic CLI
is `NativeDragReview <review-directory> [--control] --compare-capture screenshots|ax-only`.
Without that explicit option, the original three-theme and keyboard paths remain
unchanged.

Only the capture method changes between paired conditions. AX labels and input
state are still collected at every original stage. AX-only capture omits the
`screencapture` subprocess and PNG decoding/hashing; it does not compensate for
the omitted time. Both conditions require the same existing Accessibility,
event-posting and screen-capture grants. They keep the same event source, flags,
keyboard pass-through, fixed pauses, geometry, identity checks, Existing-only
cancellation assertion, fresh accepted drop and original-byte checks.

Fixed `-Capture-screenshots` and `-Capture-ax-only` evidence roots prevent one
condition from overwriting another. The control's extra argument selects only
one of these fixed trace destinations. Configuration records
`imageCaptureEnabled`; actual successful image capture records `imagesCaptured`.
The workflow retains the precise source and executable hashes. It continues
after a captured case or the exact cancellation failure only when the report
was retained, owned cleanup completed, the app registry is empty and the button
is released. A blocked permission check, unknown failure, missing report or
incomplete cleanup stops subsequent input. Any failed case keeps the overall
comparison failed, even when a later case passes.

A screenshots FAIL followed by AX-only PASS would identify sensitivity to the
image-capture path, including its timing cost; it would not distinguish the
subprocess, PNG work or elapsed time as the precise cause. Matching outcomes do
not support a capture-only explanation. This comparison is diagnostic-only,
runs no native acceptance XCTest suite, and cannot satisfy the three-theme
visual review or replace the existing full native gate. Private owner reports
and local user paths are not included in its source.

On 5 November 2026, [run 42035806356](https://github.com/osmankaankars/lemulip/actions/runs/42035806356)
completed this comparison at observer `4a19cc538c7f342b9a74ac3fbf005a41d0f0ff49`
against unchanged C12 `d821d7343675e2850705d141ef9b3b93a6aee945`.
All eight cases, four on each architecture, failed the exact cancellation
assertion: Existing alone before Escape and while still held, then Existing plus
Single after release. Each retained all three successful permission preflights,
complete owned cleanup and identical before/after input inventories. Both control
receivers recorded unmodified Escape down/up before accepting the same drag.
Neither mode reached the later fresh-drop check. Removing image capture shortened
observation time but did not resolve cancellation in these samples. C12 remains
HOLD; this result does not establish a product defect or exclude other timing and
host differences.

### Explicit AppKit Lifecycle Comparison

The separate `Native Finder Lifecycle Comparison` workflow asks whether explicit
AppKit startup changes the standalone observer's result. It builds two observer
executables from the same source and compiler invocation; only the second adds
`-D LEMULIP_APPKIT_OBSERVER`. The baseline keeps the existing Swift async main.
The alternative uses a synchronous main, creates a windowless `NSApplication`,
reads `.prohibited` activation policy and schedules the same async core once
from `applicationDidFinishLaunching`. Its core additionally checks the launch
notification, running application loop and activation policy before input.
An already-prohibited process keeps that policy without calling the setter.
Otherwise the policy change must succeed and its readback must be prohibited.
Initial policy, attempted change, setter result and final policy are logged
before input; failure never falls back to a different activation policy.
The baseline's passive metadata reads the existing `NSApp` global without
creating an application. See Apple's [run()](https://developer.apple.com/documentation/appkit/nsapplication/run())
and [prohibited](https://developer.apple.com/documentation/appkit/nsapplication/activationpolicy-swift.enum/prohibited)
contracts. Swift async main may itself run a Core Foundation loop; this is an
AppKit startup/lifecycle comparison, not a claim that the baseline lacks a runloop.

Both executables are started directly by the same orchestration process. There
is no helper app package, alternative authorization route or permission request.
Both use the fixed Orchard AX-only capture option, while retaining the original
AX, event-posting and screen-capture checks. Standard control and production each
run baseline then AppKit, serially, against the same C12 staging and fixture paths.
The AppKit evidence root adds `-Lifecycle-appkit`; control receiver routing only
adds that corresponding fixed destination. Both observer binaries, target bundles,
fixtures and provenance are hashed before and after each case.

Shared passive records include actual pause start/return times, pointer guard and
construction time, Escape post start/return times, task priority, main-thread
status and existing AppKit lifecycle state. They do not change requested waits,
deadlines, scheduling priority, input source, suppression, flags or geometry.
The original cancellation assertion, later fresh drop, owned cleanup and stop-on-
unsafe-transition policy remain intact. Timing receipts are observations, not
new timing thresholds or application-delivery acknowledgements.

In comparison mode only, the final fresh-drop workspace wait may retry an
AX read that returns `invalidUIElement` while rows are being replaced. This
node-validity error was observed on both `AXRole` and `AXChildren`; it is not
specific to the attribute being read.
Each retry revalidates the exact target identities and rebuilds the AX tree;
the original eight-second wait and overall run deadline remain fixed. The
required Existing-plus-Single workspace must still match. A separate readiness
receipt distinguishes an unmatched/retrying wait from a completed wait before
the final capture. Other AX errors, the cancellation assertion and capture
failures retain their existing failure behavior. The control receiver accepted
the fresh drop; the subsequent AX error is consistent with row replacement
invalidating an in-progress snapshot, rather than proof of the exact AX node.

A baseline FAIL/AppKit PASS would identify sensitivity to the AppKit startup and
lifecycle configuration in that CI session. It would not distinguish WindowServer
setup, event dispatch or task scheduling as the precise cause, and would not by
itself reproduce the interactive owner's host. Two failures would show that
explicit AppKit lifecycle alone did not resolve the tested failure. Every failure
remains a failure in the retained comparison. This diagnostic does not run the
native acceptance XCTest suite and cannot change the C12 HOLD or release gate.

## Instrumented drag-source comparison

`script/compare_native_drag_sources.py` runs four fixed, serial Orchard cases:
Finder, native AppKit source, native AppKit source, then Finder. Each uses the
same standard AppKit control destination, windowless AppKit observer, AX-only
capture, staged paths, fixture bytes and synthetic input protocol. This is an
isolated diagnostic. It does not run production acceptance, resolve the C12
HOLD or authorize promotion of the lifecycle experiment.

The native source is a separate, fixed `Native Drag Source.app`. It uses the
normal `NSView.mouseDragged` and `beginDraggingSession` path to offer the exact
Single fixture as a file URL. Its source operation mask permits copying only.
It has no custom Escape or cancellation handler and keeps AppKit's default
cancellation animation. Finder's offered operations and pasteboard types can
differ; both are retained in the receiver trace. Results therefore compare two
source implementations, rather than claiming their protocols are identical.

Before input, the observer measures the real Finder icon center and window
frame. The native window and its single accessible image must reproduce those
coordinates. Each case retains the source and target geometry. The comparator
requires the shared geometry to match across all four cases, along with the
observer, destination, source bundle, fixture and provenance inventories. Each
case has its own evidence root ending in `-Source-<case>`, and existing evidence
is never replaced. Application activation and window raising happen only during
initial selection or preparation for the later fresh drag, never while a drag
is held. No PID-directed Escape, authorization request or preference change is
introduced.

The source records the native session's `willBegin`, movement and end callbacks,
the dragging sequence number, offered operations, and the final operation.
Callback entry uptime is captured before validation. The destination's matching
sequence receipts, observer key-post and mouse-release times, and exact workspace
contents are joined after cleanup. A `willBegin` receipt is required; merely
requesting a session is insufficient. Source receipts are bounded and buffered
in memory during interaction, then flushed on termination, failure or watchdog
expiry. The startup binding is flushed before any input. The observer does not
read the trace while dragging.

A source end with operation `none` after the Escape post and before mouse release,
with accepted entry/re-entry and no accepted destination drop, can establish that
the native source session ended before release. An end with `none` only after
release remains indeterminate: the normal cancellation animation can delay the
callback. An accepted destination drop joined to a source end with copy is
reported as a completed drop. Absence from `NSApplication.sendEvent` alone does
not prove that AppKit never received Escape. A successful native-source case
does not establish Finder success or identify the precise OS dispatch mechanism.

The existing cancellation assertion, later fresh-drop assertion, original bytes,
fixture file set and eight-second cleanup deadline remain required. Cleanup also
checks normal termination and an empty registry for the owned source bundle;
it never terminates an unowned application. Missing or malformed source receipts,
identity drift, missing session completion, changed inputs, or incomplete cleanup
stop later input. A recognized cancellation failure may be followed by the next
predeclared case only after verified cleanup. Every failed case stays failed in
the overall diagnostic; there is no retry-until-success policy.

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

## Historical Manual And Distribution Checklist

This pre-delivery checklist is retained as historical scope, not a reopened owner follow-up.

These automated cases do not replace listening to VoiceOver, auditioning optional sounds on speakers/headphones with system effects muted, continuous edge-autoscroll review, or authentic Retina captures. Complete those observations and verify the final full-engine universal archives before publishing the combined version. The promotional film remains last.
