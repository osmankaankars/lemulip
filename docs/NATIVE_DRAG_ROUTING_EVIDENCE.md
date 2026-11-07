# Held Drag Cancellation: Evidence and Remaining Boundary

## Decision on 7 November 2026

Task 07 and [PR #45](https://github.com/osmankaankars/lemulip/pull/45) remain
**HOLD**. The cause of the CI cancellation failure is unproven. Task 08's
completed source and twelve-image review remains valid, but its final acceptance
still depends on task 07. This document records a read-only investigation of
existing evidence; it is not a new native run, a production repair, or a gate
exception.

The strongest retained association is that the source remains active before
Escape in every comparable passing case, whereas the receiver has become active
before Escape in every comparable failing case. The missing evidence is the
native requester for that activation and the actual drag-tracking consumer's
handling of the injected Escape. Application activation, ordinary key dispatch,
and drag cancellation are separate boundaries.

Another timing, event-source, keyboard-helper, or receiver-synchronization
variant is not supported by this investigation. A proposed public `nextEvent`
probe was also assessed and not run: it could provide positive retrieval
evidence, but its coverage of AppKit's native tracking path is undocumented and
its absence would not resolve the current uncertainty.

## Symptom and impact

The original C12 [run 41803346911](https://github.com/osmankaankars/lemulip/actions/runs/41803346911)
passed the general tests and all 58 native XCTest cases on both architectures.
The separate held Finder recording step nevertheless failed in all three themes
on both architectures with `Escape did not cancel the actual Finder drag`.
After Escape and release, the receiver accepted the item that should have been
canceled. Successful XCTest results do not replace this separate acceptance
condition.

| Identity | Value |
| --- | --- |
| Candidate commit | `d821d7343675e2850705d141ef9b3b93a6aee945` |
| Candidate tree | `425baa28f00ec24551dd70c0cc874a75fa3be0c1` |
| Main at this investigation | `ade8b1673de0c2dff930430564c17f100f5e807b` |
| Diagnostic baseline for this review | `86794b75fcd146ddcda8a67e798c2e3a58ac0d72` |
| Failure classification | Native automated drag cancellation failure; a product regression or an OS defect has not been established |
| Release impact | Task 07 acceptance and task 08 final sign-off remain blocked |

The completed local physical cancellation/fresh-drop check and local helper
automatic PASS are preserved. They are not being requested again. The local
helper summaries do not retain foreground, key-window, activation, or source
event-delivery fields, so their routing state cannot be reconstructed.

## Existing reproduction and minimization

The failure also occurs with a copy-only native AppKit source and a literal
`NSWindow` receiver. The standard control reproduces the symptom without the
Lemulip production view, Finder as the source, Finder's broader offered operation
mask, or Finder-specific pasteboard types. This narrows the reproduction; it
does not prove that all those environments have the same internal cause.

The latest retained fixed reproduction is the
[D16 workflow](../.github/workflows/native-drag-receiver-sync.yml) at tested
commit `bcb1f00deba2673d3da5b877eab3407f66a4ce22`, tree
`f4d98f133b2ea2df5571f54482aa80722dcb3dc9`, in
[run 42315347973](https://github.com/osmankaankars/lemulip/actions/runs/42315347973).
Its complete source, build, input, comparison, and archive identities are in the
[D16 report](NATIVE_DRAG_RECEIVER_SYNC_DIAGNOSTIC.md).

That workflow stages unchanged C12, builds the source/control/observer and the
existing idle XCTest helper, and invokes `script/compare_native_drag_receiver_sync.py`
with the staged directory and exact experiment commit. Its four cases use one
initial 0.3-second press, one entry at nominal 400 points/second, a 5-second
destination hold, global Escape 2 seconds after observed entry/terminal cursor,
a 0.15-second key dwell, and a distinct fresh drop after a successful cancel.
The original task 07 gate additionally requires exit and reentry; this minimized
protocol does not satisfy that original gate.

Both `macos-15`/arm64 and `macos-15-intel`/x86_64 use the pinned Xcode 26.3 path.
The exact workflow and per-run environment receipts govern reproduction;
runner labels alone do not fix an OS image. D16 produced both PASS and FAIL on
each architecture. The lifecycle-only policy had one pass and one failure on
each. It is already a
completed comparison and is not scheduled for repetition by this document.

## Comparable retained population

Only cases already classified as comparable by their retained strict native
classifier are included. No case has been reclassified to improve the result.
D14's incomplete Intel case and its two unrun cases remain excluded.

| Diagnostic | Run | Comparable PASS | Comparable FAIL | Excluded from the 29-case analysis |
| --- | --- | ---: | ---: | --- |
| D13 R3 | [42298849358](https://github.com/osmankaankars/lemulip/actions/runs/42298849358) | 2 | 6 | None |
| D14 R2 | [42305819111](https://github.com/osmankaankars/lemulip/actions/runs/42305819111) | 1 | 4 | One incomplete cleanup, two unrun cases |
| D15 R1 | [42308788964](https://github.com/osmankaankars/lemulip/actions/runs/42308788964) | 1 | 7 | None |
| D16 R1 | [42315347973](https://github.com/osmankaankars/lemulip/actions/runs/42315347973) | 3 | 5 | None |
| Total | Four different diagnostic runs | 7 | 22 | Three D14 cases |

These are selected historical runs with different instrumentation and, before
D16, different mouse producers. The counts are not an estimate of a general
failure probability and do not constitute a randomized causal comparison.

The [complete 29-case table](evidence/D13-D16-event-timeline.md) and
[machine-readable timeline](evidence/D13-D16-event-timeline.json) retain the
individual boundaries and input hashes. The
[read-only extractor](../script/analyze_retained_drag_event_timeline.py) reads
the eight extracted diagnostic archives under a supplied `--evidence` directory;
it sends no input and imports no native classifier. For example:

```bash
python3 script/analyze_retained_drag_event_timeline.py --evidence /path/to/extracted-evidence --format json
```

An independent [raw-file audit](evidence/D13-D16-event-timeline-independent-audit.json)
recomputed the principal intervals and pre-Escape active/key states directly
from all 29 cases. It checked 124 input-file hashes and verified that all eight
retained ZIP hashes stayed unchanged. All 29 states and intervals matched the
extractor. This is retained-data validation, not a fresh native test or a rerun
of the classifiers.

| Published analysis artifact | SHA-256 |
| --- | --- |
| Extractor | `b1582df19a510e98ba685e3e361a1534542bd2f71443ba241c2efc234adfc6cd` |
| Complete timeline JSON | `847f1cd2b500434d7f70845ff6870985fb65520606fd144b2c8fe425c209f820` |
| Complete timeline Markdown | `bad20d11c99162f1e079558d39f316e094a4351383e1bfdbbcd75a87d6010a3b` |
| Independent raw-file audit | `a3da67c2b8a7015185cbbaa3a2376a2710c4f9bc7c3d21bdcc1e4ffe8a26193e` |

### What the clocks establish

The analysis keeps event timestamps, posting-call clocks, receiver record
clocks, source callback-entry clocks, and observed cursor samples separate.
Posting completion does not establish physical delivery or cursor arrival.
Receiver trace timestamps are not complete callback-duration measurements.

- In all 29 cases, the source's post-`beginDraggingSession` creation record
  precedes `source-will-begin` by approximately 0.336–2.105 ms and precedes `source-ended` by
  3.206–6.631 seconds. The owned `beginDraggingSession` call returned before
  tracking; it is not a synchronous loop containing the later Escape.
- All seven PASS cases retain the source active/key before Escape; all 22 FAIL
  cases retain the receiver active/key. The failure association begins before
  the common Escape injection. That injection cannot cause the already-recorded
  activation, though its later routing remains relevant to cancellation.
- In the 22 FAIL cases, first receiver-entry record to held target
  type-13/subtype-1 dispatch ranges from 761.310 to 1698.374 ms. This does not
  identify an invariant entry-based activation deadline.
- First target type-6 dispatch to activation is 402.758–438.218 ms in 17 of
  those failures. The other five are 693.429, 809.232, 841.904, 1243.187, and
  1352.687 ms. A roughly 0.4-second cluster is therefore not a universal timer
  or a supported timing correction.
- All seven PASS cases have a retained terminal-cursor witness more than two
  seconds before Escape without held target activation. Time spent at the
  endpoint alone does not distinguish the outcomes.

The source-only terminal-cursor witness also has counterexamples: the interval
to activation clusters at 669.193–707.870 ms in 20 failures, but is 787.024 ms
in D16 ARM `quartz-sync-first` and **negative 31.715 ms** in D14 ARM
`xctest-second`. Combining source, target, and observer cursor witnesses changes
these intervals again. None of those samples records the start or expiry of an
identified system timer.

### The apparent stale-event example does not prove stale delivery

In D15 ARM `quartz-second`, the first target type-6 receipt is 50.313 ms after
the terminal movement's posting call completes. Its event position matches
movement step 16 of 24 rather than the endpoint. However, the simultaneously
observed cursor is also at that intermediate point. The earliest retained
terminal-cursor witness follows much later. This demonstrates that posting
completion and observed cursor arrival are different boundaries; it does not
prove that a stale event was delivered after the cursor reached the endpoint.

Across all 19 comparable Quartz cases, no source-moved callback after the
terminal movement posting completes carries a nonterminal callback point.
Receiver callbacks can continue to report earlier positions in both PASS and
FAIL. Such callbacks cannot be counted as distinct injected stale events.

## Code and contract audit

The source and receiver `sendEvent` overrides always forward to `super`.
Source setup activates the source before the gesture. Receiver setup activates
the receiver at launch. The receiver's owned drag callbacks contain no
activation, ordering, or keyboard-forwarding request during the held gesture.
The source guards duplicate session starts and passes the retained original
mouse-down to `beginDraggingSession`, as specified by
[Apple's initiating-event contract](https://developer.apple.com/documentation/appkit/nsview/begindraggingsession(with:event:source:)).

Apple describes [drag-session creation](https://developer.apple.com/documentation/appkit/nsdraggingsession)
as returning before the drag starts on a later run-loop turn. The retained
source chronology agrees with that contract. Neither control view implements
the enabling callbacks described by
[springLoadingEntered](https://developer.apple.com/documentation/appkit/nsspringloadingdestination/springloadingentered(_:)).
An internal window-hover behavior remains possible, but labeling this an owned
spring-loading handler is unsupported.

The observer has one explicit, retained HID `CGEventSource` and does not
release it during the gesture. Earlier failures cover nil sources, HID and
session Escape insertion, retained shared source state, keyboard-through
suppression filters, and preserved pointer flags. The local automatic PASS uses
the later retained-source construction. The current evidence supports no
source-lifetime, input-field, or insertion-tap repair.

D7 already ran public `typeKey(.escape, modifierFlags: [])` on the verified
foreground control; both cancellation cases failed. The
[typeKey contract](https://developer.apple.com/documentation/xcuiautomation/xcuielement/typekey(_:modifierflags:)-6gaoi)
does not certify a process-independent global drag-cancellation path.
Repeating that application-associated operation would not be a new independent
keyboard mechanism.

## Hypotheses already bounded by counterevidence

| Proposed explanation or repair | Retained counterevidence | Remaining limit |
| --- | --- | --- |
| Target AXRaise requests are necessary | D11 fails with all target raises omitted | Other activation paths remain unknown |
| Held observer AX reads are necessary | D12 fails with zero held reads | Other observation and scheduling effects remain possible |
| Replacing Quartz mouse production reliably fixes cancellation | D13 has failures with public XCTest mouse production | Both producers still use the shared Escape route |
| First target CG PID or source-state field identifies the producer | D14 fields match in PASS and FAIL; the getter may create a corresponding CG event | Original upstream producer remains unidentified |
| First target dispatch stack identifies activation | D15 PASS and FAIL show the same ordinary event-pump stack | A queued or asynchronous earlier request is outside that stack |
| Per-record receiver synchronization is necessary | D16 lifecycle-only cases fail with zero per-record synchronizations | Logging can still affect scheduling; no universal zero-effect claim |
| One invariant delay from a retained entry, event, or cursor timestamp explains every failure | The 29-case chronology has explicit counterexamples for those anchors | An unobserved timer with another trigger remains possible |
| An absent source `sendEvent` key-down proves nondelivery | Native tracking can consume events before normal dispatch | Actual tracking-consumer receipt remains unobserved |

## Why the public retrieval probe was not run

Apple's [nextEvent contract](https://developer.apple.com/documentation/appkit/nsapplication/nextevent(matching:until:inmode:dequeue:))
permits event retrieval before normal dispatch. A transparent override could
call `super` once with identical arguments, return the same optional event,
and buffer positive Escape returns. A failed case with a corresponding source
key-down return would challenge a simple “the source never retrieved Escape”
explanation.

That observation would still not identify the caller as the cancellation
consumer, prove that the consumer processed the key, or cover every internal
tracking path. `dequeue == false` would be a peek, not consumption. Absence
would remain inconclusive. A
[local event monitor](https://developer.apple.com/documentation/appkit/nsevent/addlocalmonitorforevents(matching:handler:))
also does not close the gap: Apple excludes events consumed by nested tracking
loops from that monitor's coverage.

The proposed probe therefore does not presently justify another native run.
It is retained as a possible positive-evidence technique for a more specific
future question, not as an implemented fix or a scheduled experiment.

## Concrete technical handoff

The next investigation needs a macOS/AppKit tracing capability that can answer
at least one of these questions in a failing CI session:

1. Which native request or transition activates the receiver while the source
   dragging session is still open? The trace must bind that request to the
   source, receiver, drag sequence, and native monotonic clock before the
   receiver activation callback. Another downstream activation receipt alone
   does not answer it.
2. Does the native source drag-tracking consumer receive the owned Escape
   key-down, and what does it do with it? A positive consumer receipt is useful;
   absence is meaningful only with independently established path coverage.

The existing retained package already supplies exact source/build identities,
strict outcomes, observer post clocks, source lifecycle and callback clocks,
receiver acceptance records, activation journals, cleanup, and fixture
integrity. These should accompany an AppKit/CI-host technical review. This
document does not claim that a specific additional tracing facility is
available or that an upstream platform defect has been proven.

A further experiment should be selected only after its observation boundary,
permissions, overhead, positive evidence, negative-evidence limits, and stopping
condition are concrete. The original constraints remain: no focus correction,
PID-directed Escape, permission/TCC changes, input retry, timing sweep, or
acceptance relaxation.

## Completion criteria and checkpoint

| Work | Status and next required result |
| --- | --- |
| 01–06 | Completed; no work reopened by this investigation |
| 07 | Blocked on a supported cancellation repair and the original Finder enter → exit → reenter → Escape → release → distinct fresh-drop gate on both architectures and all three themes |
| 08 | Source and twelve-image review completed; final review follows task 07 on the exact final candidate and includes any resulting code changes |
| 09 | Not opened without a new brief |

The evidence packet is the completed deliverable of this phase. Production
sources, existing diagnostic inputs, classifiers, and workflows are unchanged.
The investigation has reached a technical escalation point: the available
observations establish association but not the missing native mechanism.
There is no verified narrow fix to ship. No native rerun is claimed, and no
additional owner test is needed to restate the completed local results.
