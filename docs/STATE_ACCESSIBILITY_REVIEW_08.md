# State And Accessibility Final Review: Open

## Evidence reviewed on 6 November 2026 UTC

Task 08 remains open because task 07's held Finder drag cancellation gate has
not passed. This review completes a bounded, independent check of retained C12
visual evidence. It does not approve a merge or release.

The candidate is [PR #45](https://github.com/osmankaankars/lemulip/pull/45), head
`d821d7343675e2850705d141ef9b3b93a6aee945`, tree
`425baa28f00ec24551dd70c0cc874a75fa3be0c1`. The reviewed artifacts come from
[run 41803346911](https://github.com/osmankaankars/lemulip/actions/runs/41803346911).
Their provenance records the CI merge commit
`3736b791f48b5a7bdaa2a752297c9cebeab64cce` and the same candidate tree.
The StateAccessibilityUITests, DisplayAccessibilityUITests and NativeDragReview
source hashes match the pinned C12 source files.

Both downloaded archives passed their advertised byte count, SHA-256 and ZIP
CRC checks. Extraction rejected absolute paths, traversal and symlinks. Each
archive contains 1,599 entries. Each retained XCResult database contains exactly
58 test-case runs, all with result `Success`.

| Architecture | Artifact ID | ZIP bytes | SHA-256 |
| --- | --- | ---: | --- |
| arm64 | 13310237143 | 59,800,674 | `296450189a018761fbd53eb181aedfb3140874d0f609d661f7c31d14946120ca` |
| x86_64 | 13310193645 | 82,837,525 | `f4954bbc586f402b2193226b2535871c951e6ea9aabb693426a01c22b9202c64` |

## Production source review

The C12 production diff against main
`ade8b1673de0c2dff930430564c17f100f5e807b` contains three focused changes:

- The visible result panel is repositioned after content resizing to fit its
  current display's visible area. This path does not activate the application or
  take keyboard focus.
- The interactive audio waveform and video timeline explicitly report their
  enabled state through accessibility.
- Video timeline S/E/P selection commands ignore key-repeat events; arrow-key
  adjustment still repeats.

The independent source review found no additional concrete blocker in that
production diff. It is separate from native execution and from the still-open
drag observer failure. D13 through D17 change only diagnostic infrastructure and leave
these production sources byte-for-byte equal to C12.

## Selected visual observations

The following twelve original PNG attachments were opened individually. The
names and UUIDs were joined through the retained XCResult database, rather
than inferred from the screenshot contents. The images themselves were not
edited or regenerated.

| Architecture | Retained state | Attachment UUID | Observation |
| --- | --- | --- | --- |
| arm64 | Orchard TR minimum workspace | `EF9A37C4-1FE8-4417-A571-34FD68CDF648` | Two selected files, long-name truncation, row actions and workspace controls fit the narrow window. |
| arm64 | Pistachio EN audio keyboard and focus | `0BEEA993-288F-4697-9E68-2BF5D9E77F41` | Waveform focus outline, selected range, time fields and footer actions are visible. |
| arm64 | Lemonade TR video keyboard and focus | `B25FF976-A98D-4244-8E8F-CCA37058D4DD` | Timeline focus outline, selection handles, time fields and primary action are visible above the Dock. |
| arm64 | AccessibilityMotion result card | `10061F34-237B-4657-9D8D-EEF1A2E4174C` | The complete card, wrapped output filename and three output actions fit above the Dock. |
| arm64 | Lemonade EN minimum workspace | `EC728D79-636D-4B08-9CD1-11F829796DF4` | The light theme preserves the same narrow-window file-row controls and long-name truncation. |
| arm64 | Pistachio TR long PDF recovery | `910AC512-482C-46FF-926B-15C2ECB69049` | The full recovery message and long filename wrap within the editor; Cancel remains visible and Create Copy is disabled. |
| arm64 | Orchard TR PDF field Escape restores position | `5B445697-16EA-4E77-ACCA-7AFBB8FEE9A0` | Position 1, selected page, collection focus indication and footer actions are visible. Behavior is established by the corresponding test, not by the still image alone. |
| arm64 | Turkish result card before Finder action | `1D2687A7-C148-46E0-97E8-E42FCB6D1AA4` | Turkish result text, wrapped filename and Finder/Copy/Float actions fit above the Dock. |
| x86_64 | Orchard EN PDF invalid position | `4207539F-E2B6-4018-AF87-63D34888DE5F` | The invalid position value has focus and a warning indicator; Create Copy is disabled and Cancel remains available. |
| x86_64 | Pistachio TR audio keyboard and focus | `0834F69E-7E5A-4593-ABC8-27C8F29C1732` | The Turkish audio editor preserves the focus outline, selected range, time fields and footer controls. |
| x86_64 | Lemonade EN video keyboard and focus | `4DCC0F8D-F2DF-433E-9872-D67E6AABF450` | The English video editor preserves the focused timeline, selection and output controls. |
| x86_64 | AccessibilityTransparency result card | `F07716BF-9FB2-46C4-B83B-6F469CC1EBAF` | The complete result card and output actions remain visible above the Dock at the Intel runner's display size. |

No new blocking visual defect was identified in these selected frames. This is
not an exhaustive review of every retained attachment. The static images do
not establish animation quality, audio playback quality, VoiceOver behavior or
the timing of an in-flight drag.

## Remaining acceptance work

The native drag recording step in the same C12 run failed cancellation in all
three themes on both architectures: `Escape did not cancel the actual Finder
drag`. The 58 successful XCTest cases do not override that separate failure.

The [D12 held AX comparison](NATIVE_DRAG_HELD_AX_DIAGNOSTIC.md),
[D13 mouse producer comparison](NATIVE_DRAG_MOUSE_DRIVER_DIAGNOSTIC.md),
[D14 event-origin observations](NATIVE_DRAG_EVENT_ORIGIN_DIAGNOSTIC.md),
[D15 dispatch-stack observations](NATIVE_DRAG_DISPATCH_STACK_DIAGNOSTIC.md),
[D16 receiver synchronization comparison](NATIVE_DRAG_RECEIVER_SYNC_DIAGNOSTIC.md), and
[D17 activation request log observations](NATIVE_DRAG_ACTIVATION_REQUEST_LOG_DIAGNOSTIC.md) are
diagnostic work. Their scope and results must remain separate from the original
enter, exit, reenter, Escape, release and fresh-drop acceptance sequence.

D14 R2 added no production change. ARM had four comparable cancellation failures;
Intel had one strict diagnostic pass, one incomplete cleanup and two unrun cases.
The added event metadata and selected system logs did not establish the upstream
held-activation request. These results do not close the original gate.

D15 R1 completed all eight comparisons and entry-stack observations. ARM had
four cancellation failures; Intel had one strict diagnostic pass followed by
three cancellation failures. Every case completed normal cleanup with unchanged
inputs. The first-drag stacks follow the ordinary AppKit event-dispatch path in
both successful and failed cases; they do not identify an earlier event producer
or establish a production fix. The Intel post-comparison system-log query timed
out; its absence of selected records is not evidence that no request occurred.
The bounded stack investigation has reached its stated stopping condition.

D16 R1 completed eight comparable cases with valid synchronization measurements
in [run 42315347973](https://github.com/osmankaankars/lemulip/actions/runs/42315347973),
tested commit `bcb1f00deba2673d3da5b877eab3407f66a4ce22`. ARM had one diagnostic
pass and three cancellation failures; Intel had two passes and two failures.
Each architecture's lifecycle-only policy produced one pass and one failure,
with zero per-record synchronizations verified from the retained receipts.
Per-record receiver synchronization was therefore not necessary for those
observed failures, and deferring it did not establish a cancellation repair.
Both reports have complete native and measurement evidence, unchanged inputs,
and normal cleanup. All 121 portable checks and native builds passed on each
architecture; the overall CI result remains failure because the strict native
outcomes did not all pass. D16 ends with mixed results and no production change.

The subsequent [held-drag routing evidence review](NATIVE_DRAG_ROUTING_EVIDENCE.md)
examines 29 retained comparable cases without another native run. Every PASS
retains the source active before Escape and every FAIL retains the receiver
active, but the code, API contracts, and timing counterexamples do not establish
the activation requester or the drag-tracking consumer's handling of Escape.
The investigation now requires evidence across that native boundary; another
timing, synchronization, or application-associated key variant is not a
supported repair. This read-only result adds no production change and does not
close either task.

D17 R1 completed another eight comparable diagnostic cases in
[run 42357652748](https://github.com/osmankaankars/lemulip/actions/runs/42357652748),
tested commit `a17259046aed8ef62c0bd5273e530847b9c78b3c`: ARM PASS/FAIL/FAIL/PASS,
Intel PASS/FAIL/FAIL/FAIL. All 143 portable checks and native builds passed on
each architecture, as did both owned clock markers and each single bounded
system-log query. Native outcomes remained unchanged and were independently
reproduced from the original artifacts.

The new category-wide query recovered `launchservicesd` `SETFRONT` rows that
the old emitter list excluded. All five failing cases contain a source-to-target
front transition after receiver entry and before Escape, approximately 5–42 ms
before the target's activation dispatch callback. These records identify a
server-side transition and its exact source/target context, not the upstream
requester or Escape consumer. This is new diagnostic evidence; production C12
and the original full acceptance requirement remain unchanged.

D18 R2 subsequently completed a startup-only prerequisite measurement in
[run 42419686902](https://github.com/osmankaankars/lemulip/actions/runs/42419686902)
at `80f92e41ccfedb54a15b0a5ef9572a5a57a88c4d`. All four owned app lifecycles
completed normally, with valid loaded-probe receipts and zero captured public C
activation entries. Both architectures correctly returned `coverage-unproven`;
no held-drag experiment followed. All 22 portable checks and native builds passed.
The [D18 result](NATIVE_ACTIVATION_ENTRY_CALIBRATION.md) and
[upstream investigation packet](NATIVE_DRAG_UPSTREAM_INVESTIGATION.md) preserve
that observation and its limits. This adds no acceptance result or product fix;
the completed source/screenshot review and the owner's physical/v4 results remain valid.

D19 R2 completed tool discovery on both architectures in
[run 42565052135](https://github.com/osmankaankars/lemulip/actions/runs/42565052135)
on 9 November 2026 at `daf90a14cbe0e5855e2e4a3e69dc8c170700635d`.
All fifteen read-only inventory commands and six subprocess checks passed per
architecture. The [D19 report](NATIVE_TRACE_CAPABILITIES.md) and
[retained capability evidence](evidence/D19-trace-capabilities.json) establish
the installed System Trace and related CLI contracts. No trace, native app
startup, drag, or keyboard input ran. Recording access, actual export schemas
and causal coverage remained unobserved at D19's completion; the bounded
recording/export prerequisite was separate. This inventory does not close task 07 or change C12,
PR #45's HOLD, or task 08's dependency. The physical/v4 evidence remains complete.

D20 R2 subsequently attempted that prerequisite in
[run 42567849171](https://github.com/osmankaankars/lemulip/actions/runs/42567849171),
on 9 November 2026, 05:31:57–05:35:12 UTC, at
`1462bf597c52727ede7ee20991c65016e8b3086a`, tree
`071467586f6b95d1b5ad5ab57ac5c97349a3526f`. The public-header helper build
correction and all six bounded-command plus ten orchestration tests passed on
each architecture. Both helpers registered their start notification, observed
zero callbacks during the fixed 15-second wait and failed before launching
either source/control app. No native journal, trace package or export was
produced; both recorder streams are empty. Each recorder received only one
direct SIGINT after helper failure and exited -2, with complete cleanup and
124 unchanged staged input entries per architecture.

The [D20 result](NATIVE_SYSTEM_TRACE_STARTUP.md#r2-recording-start-notification-not-observed)
and [retained evidence](evidence/D20-system-trace-startup.json) preserve this
`evidence-incomplete` boundary. They do not explain the recorder's pre-start
silence, demonstrate a permission denial, or calibrate an activation path. A
supported initial tool-start observation is now required before another
qualification can be designed; timeout widening and blind reruns are not
supported by this result. No drag or acceptance case was run. The original
Finder gate, C12/PR #45 HOLD, completed source/screenshot and physical/v4 evidence,
and task 08's dependency on task 07 remain unchanged.

D21 R2 subsequently executed the bounded recorder observation in
[run 42583779680](https://github.com/osmankaankars/lemulip/actions/runs/42583779680)
at `72e59791f59ae0b6e1de367639f43e161303a828` on 9 November 2026.
All 31 portable checks, native builds and 20 installed-manual checks passed per
architecture. Exact-recorder process metadata was retained, but each single
sampler attempt reached its fixed command budget without a report. The
[completed D21 report](NATIVE_RECORDER_STARTUP_OBSERVATION.md) and
[public evidence](evidence/D21-recorder-startup-observation.json) bind the result:
no qualified loaded image/stack, no recording-start callback, no app launch,
trace or export. Both sampler and recorder cleanup resolved and inputs remained
unchanged. Sampler cleanup EPERM is not an inspection-permission denial.

The proposed next prerequisite was a standalone positive calibration of the same bounded
sampler on an owned native child with a known frame. That requires no new
recorder run, timeout widening or held input. D21 supplies no product repair or
original Finder acceptance result. The completed source/twelve-image review,
physical check and v4 evidence remain valid; task 08 still waits on task 07.

[D22 R1](NATIVE_SAMPLER_CALIBRATION.md) subsequently ran that standalone control
in [run 42588874357](https://github.com/osmankaankars/lemulip/actions/runs/42588874357)
at `10ececdd145ca4c857c5844a83cee0b0b3a5d8e2`. Both architectures passed all 43
portable tests, native compilation and provenance checks. One sampler each
completed in about 1.47 seconds and produced the known waiting frame (82/97
samples). CI remained incomplete because the strict image parser rejected
unequal privacy-masked paths; no post-sample identity query followed. Normal
target completion and cleanup passed. These controlled-process observations
are preserved in the [D22 evidence](evidence/D22-native-sampler-calibration.json)
without promoting the full calibration or the product gate.

[D23's offline identity/frame review](NATIVE_SAMPLER_IDENTITY_REVIEW.md) now
accepts both unchanged artifact sets under a separate narrow contract. All 39
portable tests passed and independent reconstruction matched every output value.
The original D22 calibration remains incomplete, with no post-sample identity
snapshot. It adds no native input or original acceptance result. C12, the
completed source/twelve-image review, physical check and v4 result retain their
status; task 08's final closure remains dependent on task 07.

[D24 R2](NATIVE_RECORDER_PROGRESS_OBSERVATION.md) subsequently completed the
bounded recorder/primary/secondary observation in
[run 42609635410](https://github.com/osmankaankars/lemulip/actions/runs/42609635410),
with 81 passing tests per macOS architecture. All four samplers retained only
their 84-byte initial banners, with no report or qualified internal phase.
ARM retained zero callbacks and no trace. Intel retained one late helper-native
callback and a partial trace; recorder output appeared after the sampler window
in the parent clock domain, and recorder exit -11 followed stopping without
normal completion. This adds no original acceptance case or product repair.

[D25 R2](NATIVE_RETAINED_TRACE_EXPORT.md) subsequently completed that retained-input
step in [run 42616711092](https://github.com/osmankaankars/lemulip/actions/runs/42616711092),
attempt 1, with 91 passing tests. Its one read-only export exited 10 after
1.734828604 seconds, with empty stdout and exactly 47 stderr bytes:
`Export failed: Document Missing Template Error` followed by a newline. Input,
source and installed-tool identities remained unchanged. The
[result](evidence/D25-retained-trace-export.json) and
[verification](evidence/D25-verification.json) establish no TOC, usable clock
mapping, event range or original acceptance case.

[D26](NATIVE_RETAINED_ATRC_CONTRACT.md) completed its contract review and the one
missing import-help request, with 45 passing tests. The request exited 0 after
1.290658711 seconds with 1,512 stdout bytes and empty stderr; all 13 source
copies and identities were verified, and source/reader bytes stayed unchanged.
Its [result](evidence/D26-retained-atrc-contract.json) and
[verification](evidence/D26-verification.json) establish generic import grammar
and conditional, release-dependent UTI defaults. The help does not name ATRC
or establish this exact payload's acceptance. D26 performed no import, export
or recording.

[D27 R2](NATIVE_RETAINED_ATRC_IMPORT.md) passed **99 native tests** and made one
import with the same reader, exact protected input and fresh System Trace
availability. Stdout reported import completion and saving. Its output census
took **0.591878661 seconds**, exceeding the **0.25-second** observation budget;
parent TERM/KILL followed, and the importer exited **-9 after 19.594917998
seconds**, before its 90-second deadline. Cleanup completed, input/source/tool
identities stayed unchanged, and all 19 source copies were retained. CI did not pass; the
diagnostic remains `diagnostic-incomplete`, with no qualified derivative/archive. The
[result](evidence/D27-retained-atrc-import.json) and
[verification](evidence/D27-verification.json) supply no unsupported-input,
importer-hang or product-root-cause conclusion. No export or new recording ran.

[D28](NATIVE_RETAINED_ATRC_OBSERVER_REVIEW.md) completed its offline review and
narrow omitted-observation counter fix with 56 passing portable tests. Five
deterministic cases characterize synchronous census/supervision coupling;
exact native per-call timing remains unavailable. A candidate D29 contract
for an isolated observer is defined but unimplemented. No native retry or
threshold increase occurred. PR #45 remains draft/unmerged and C12 remains HOLD. The
original full Finder sequence, completed source/twelve-image review,
physical/v4 evidence and task 08's dependency on task 07 remain unchanged.

To complete task 08, close or explicitly resolve task 07's remaining CI gate on
the final candidate, review any resulting production changes, and retain the
final source/run/artifact identity. The candidate is still on hold.
