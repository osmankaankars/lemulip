# Native drag mouse driver comparison (D13)

## Question and scope

D13 asks whether the mouse gesture producer is associated with a different Escape-cancellation outcome in the same native AppKit source and plain `NSWindow` receiver. It compares the existing Quartz mouse event path with the public macOS XCTest coordinate drag API. An independent observer posts the same global Quartz Escape in both arms.

This is a diagnostic with a deliberately simpler single-entry gesture. It does not replace the original C12 enter/exit/reentry acceptance gate, establish a particular `CGEvent` field as the cause, or justify promoting PR #45. C12 remains on HOLD until its complete three-leg native acceptance requirement is met. The earlier D11 and D12 records remain historical evidence under their own protocols.

## Pinned inputs

| Input | Pin |
| --- | --- |
| Unchanged C12 application commit | `d821d7343675e2850705d141ef9b3b93a6aee945` |
| Unchanged C12 application tree | `425baa28f00ec24551dd70c0cc874a75fa3be0c1` |
| Diagnostic parent | `0d14c496030d49e6d4943445bad0164ad71c3726` |
| Diagnostic branch | `codex/drag-mouse-driver-07` |
| Runners | `macos-15` / `arm64`; `macos-15-intel` / `x86_64` |
| Xcode | `26.3` |

The application is built once for staging from the pinned C12 commit. Its unchanged full suite is not rerun by this diagnostic. Portable comparison and staging checks remain required, including the unchanged assertion that the production native suite contains exactly 58 cases. The helper XCTest cases belong only to this diagnostic.

## Fixed protocol

Each architecture has four fixed serial cases in one existing CI session, in this order:

1. `quartz-first`
2. `xctest-first`
3. `xctest-second`
4. `quartz-second`

Execution stops at the first incomplete or non-comparable case. Remaining planned cases are reported as not run; they are not silently replaced or retried.

Both arms use the same native AppKit source, plain-window control receiver, fixture set, target point, target-raise policy, and cancellation checks. The mouse producer changes for the complete mouse gesture. XCTest uses Apple's [public coordinate drag API](https://developer.apple.com/documentation/xcuiautomation/xcuicoordinate/click%28forduration%3Athendragto%3Awithvelocity%3Athenholdforduration%3A%29), `XCUICoordinate.click(forDuration:thenDragTo:withVelocity:thenHoldForDuration:)`; Quartz uses the diagnostic's explicit mouse events.

| Parameter | Fixed value or rule |
| --- | --- |
| Initial mouse hold | 0.3 seconds |
| Nominal drag velocity | 400 points per second |
| Cancel gesture destination hold | 5 seconds |
| Separate fresh-drop destination hold | 1 second |
| Escape scheduling | 2 seconds after the observer establishes receiver entry, cursor at the target point, and left button held |
| Escape key-down dwell | 0.15 seconds |
| Escape producer | Independent observer; global Quartz key events in both arms |
| Path | One entry followed by a terminal hold; no exit/reentry or one-point motion |
| Held-drag observation | No observer AX reads or screenshots |
| CI bound | 25 minutes per architecture; one helper build and four fixed cases |

These are nominal protocol timings, not a claim of identical physical event schedules. Quartz begins its terminal hold at observed receiver entry; XCTest begins its hold at native destination arrival. The retained event times and helper outcomes must be considered when interpreting a difference. The observer's AX-read restriction does not establish that the public XCTest implementation performs no internal AX operations. The helper has a bounded stop, and the run does not sweep timing values or retry cases until they pass.

The workflow uses the session's existing permissions. It does not grant permissions, reset TCC, change global preferences, correct focus during the held drag, or target Escape to a process. Pre-drag setup retains the common target-raise policy.

## Required evidence and acceptance

Cancellation is judged after release. The receiver must retain only its pre-existing item, and source and receiver callbacks must bind to the same drag sequence. A source `.none` callback before mouse-up is not required. The retained receipts must establish the actual completion sequence rather than infer it from the order in which files were collected.

A distinct fresh drag must then succeed, with its own source and receiver receipts. Original fixture bytes, the staged input inventory, helper completion, and cleanup are also checked. A missing receipt, unexpected mutation, timeout, malformed helper result, or incomplete fresh-drop check cannot be reported as a successful comparison. Failed cases retain their evidence; a skipped fresh leg remains visible as incomplete acceptance.

The result classifier reports every planned case, including any not-run cases after an incomplete comparison. A failed case is not replaced with a retry, and a diagnostic result does not weaken the existing C12 acceptance conditions.

## Provenance and retained artifacts

`script/compare_native_drag_mouse_driver.py` prepares the mouse helper once before the immutable input inventory is recorded. It creates four distinct nonce-bound configurations at `MouseControl/<case>/configuration.json`, builds the helper once, and generates four case-specific `D13-<case>.xctestrun` manifests from the original build manifest. Runtime evidence remains in each case's own directory.

The provenance record binds the application commit/tree and experiment commit/tree to the relevant Swift and comparator source hashes, compiled observer/source/receiver hashes, helper runner and test executable hashes, per-case configuration hashes, and original plus case-specific test manifests. The new observer is compiled from `NativeDragReview.swift` and `NativeDragMouseDriver.swift` with both `LEMULIP_APPKIT_OBSERVER` and `LEMULIP_MOUSE_DRIVER_OBSERVER`. The two existing observer builds remain available for the inherited staging checks.

The artifact set retains the provenance, comparison JSON/report, available `NativeDragControlEvidence-Capture-ax-only-Lifecycle-appkit-MouseDriver-<case>` evidence directories, per-case `MouseControl` runtime files, helper project/build log, test manifests, and available XCTest results. The built helper is recorded by hashes; the workflow does not upload its compiled app bundle. Inventory and byte-retention checks define what is actually preserved; a manifest or source hash alone does not establish a native outcome.

## Interpretation limits

| Observed complete result | Supported interpretation |
| --- | --- |
| Quartz fails and XCTest passes consistently | A mouse-producer-associated difference exists under this D13 protocol. The result does not isolate one event field or prove the operating system's root cause. |
| Both producers fail | The failure also occurs in this simpler protocol with both producers. This does not identify its cause. |
| Both producers pass | This simpler protocol succeeds. The original C12 acceptance gate is still required. |
| Mixed outcomes or incomplete evidence | Report the case-level observations and limitations. Do not promote them to a general causal claim. |

## R1 observed results

[D13 R1, run 42294823503](https://github.com/osmankaankars/lemulip/actions/runs/42294823503) executed commit `06378f34a1aa8fb0a0389ac1949349b74de53c32`, tree `e95d0844cec87d09da5087849a835c8a242c9c7e`.

| Architecture | Retained result | Interpretation |
| --- | --- | --- |
| ARM | `quartz-first` incomplete; the remaining three cases not run | The immediate button-state sample still reported held, so the observer stopped before postrelease AX collection. This is not a comparable cancellation result. |
| Intel | All four cases comparable; cancellation failed in all four | Both Quartz and XCTest mouse gestures ended in source `COPY` and receiver acceptance. The target received both Escape key-down and key-up while the drag was held. The XCTest arms recorded zero observer pointer-event posts. |

The ARM button-state check occurred just **0.189 ms after the Quartz mouse-up post returned**. The target's mouse-up receipt (`type 2`) followed at **+6.735 ms**, and the source's `COPY` completion at **+119.462 ms**, relative to that return. The later receipts expose a gap between posting release and observing its delivery; they do not supply the missing postrelease AX state. Both architectures retained normal cleanup and unchanged staged inputs.

Intel therefore reproduced the cancellation failure with both mouse producers under D13. The run does not isolate a Quartz-only cause, establish a particular event-field defect, or provide the missing ARM producer comparison.

The downloaded artifact ZIPs were verified against these retained identifiers and SHA-256 digests:

| Architecture | Artifact ID | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| ARM | `13540879050` | 190572 | `f14d25aa09f0e0b6fec4da90b84b9b12b4cf56289758e8910f9059186833ca24` |
| Intel | `13542196335` | 304742 | `aa65f88abfd60fd3ae3d71584ffb275e20213473c004eb9070d372e58f6f1894` |

## R2 release-observation repair

R2 adds a bounded release-acknowledgement check after the Quartz mouse-up post or XCTest mouse API returns: poll button state every **0.025 seconds**, for at most **1 second**. The retained sample sequence must confirm that the button is released. If release is not observed within that window, the case remains incomplete and execution stops under the same rule.

The change addresses the immediate observation race seen in ARM R1. It adds no input event and preserves the held-gesture schedule and strict postrelease acceptance checks. It is a defined measurement change, not a timing sweep or an until-green retry.

## R2 audited results

[D13 R2, run 42296226234](https://github.com/osmankaankars/lemulip/actions/runs/42296226234) executed commit `e47f22d4289352338051027eb810edb9ba69edcb`, tree `1e6ae973e2261823907f2515e98f450ae8fbf02e`.

| Architecture | Fixed-order results | Evidence and limit |
| --- | --- | --- |
| ARM | Quartz `FAIL`; XCTest `PASS`; XCTest `PASS`; Quartz `FAIL` | All four cases comparable, with normal cleanup and unchanged inventories; 14 snapshot records retained. The first Quartz release acknowledgement changed from held to released after 111.694 ms. |
| Intel | First Quartz `NOT COMPARABLE` (`cleanup-incomplete`); remaining three not run | Three snapshot records retained. A helper identity check failed during cleanup; the run does not supply an Intel producer comparison. |

Both ARM XCTest passes satisfy the strict cancellation and fresh-drop requirements: cancellation retained exactly one `Existing` item, source sequence 1 ended with `NONE`, and the receiver accepted nothing from that sequence. A separate sequence 2 then ended with source `COPY` and exactly the expected `Single` result with two receiver items. These are complete D13 passes, not just an absence of an observed drop.

Intel retained the raw `FINISHED` timestamp `515.43169708900007`, an identity-check failure at `515.659576316`, and parsing of `FINISHED` only at `516.094502132`. The failure records false bundle and executable path-match checks without the actual URLs or PID evidence needed to establish why the identity check failed. Exit status 0, an empty runner registry, no held mouse button, and no forced termination were also recorded. Those end-state checks do not resolve the identity gap; the result remains `cleanup-incomplete`.

The ARM contrast is scoped to R2. R1 Intel already contains failures with both XCTest gestures. In R2 ARM's XCTest passes, the source remained active/key through Escape and no target activation was recorded; in R1 Intel's XCTest failures, the target activated about 0.98 seconds after entry and received Escape. These are associations, not a proven activation mechanism. Event number 0, pressure 1, flags 0, and the XCTest HID/session-state mismatch occur in both passing and failing evidence, so none is identified as the causal field.

Both R2 artifacts were independently replayed against their 242-entry input inventories, 11 source hashes, four configurations, five test manifests, and eight binary hash links. Compiled binary bytes are absent from these artifacts; the binary verification establishes retained hash relationships rather than independently rehashing the executables.

| Architecture | Artifact ID | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| ARM | `13541134197` | 316633 | `f9ccd46bb68089c45832913eea649e0fe78d586fc937696f4c3f01724517e119` |
| Intel | `13542771212` | 193947 | `10113e5a239e6b9b5a23d1424516b8782f5402c8d7c6d3e8d68e5554fc05881d` |

## R3 terminal cleanup correction

[D13 R3, run 42298849358](https://github.com/osmankaankars/lemulip/actions/runs/42298849358) tests commit `d69f6b344a0dc069027f04061686a308dae79ba4`, tree `e550037256023b578df06e94ebd6ab4d5fe331b4`.

The stop loop now reads and validates `FINISHED` before checking process identity. Only a previously bound runner PID, with no outstanding gesture and both captured identity URLs nil, can enter the recorded terminal transition. Each observation is tied to the validated `FINISHED` receipt and the existing eight-second stop bound. A retiring process is never returned as a signal target, and no termination or force-termination signal is sent after that transition has been observed. Missing or conflicting identity evidence still fails closed. Normal exit status 0, an empty runner registry, released input and error-free completion remain required.

The patch changes only the helper, classifier and focused tests. It adds no gesture input and does not retroactively normalize R2 Intel's incomplete result. There is no timestamp tolerance change: the differently formatted R2 decimal values represent the same binary64 number. All 82 portable checks passed locally, including 21 mouse-driver checks and the preceding 61 comparison, coverage, release and staging checks.

### R3 audited results

The single run attempt completed on 6 November 2026 at 21:48:53 UTC. Both architectures passed all 82 portable checks and compiled the application, observers, native source/receiver and XCTest helper. Both jobs failed only the final mouse-driver comparison. All eight cases are comparable, with normal cleanup and unchanged inputs.

| Architecture | Quartz first | XCTest first | XCTest second | Quartz second |
| --- | --- | --- | --- | --- |
| ARM | PASS | PASS | FAIL | FAIL |
| Intel | FAIL | FAIL | FAIL | FAIL |

Both ARM passes retain only `Existing` after cancellation, with source sequence 1 ending in `NONE` and no receiver acceptance for that sequence. Each then completes a distinct same-producer sequence 2, accepting `Single` exactly once with source `COPY` and two selected items. Every failed case accepts sequence 1 with source `COPY`; its fresh-drop leg is not run. ARM therefore has mixed results within each producer. Intel again shows failure with both producers. The R2 ARM producer contrast did not repeat, and switching to XCTest is not established as a reliable cancellation repair.

In ARM's two passing cancel legs, the source is foreground at all three Escape observations and the target does not activate during cancellation. In its two failures, the target activates 0.996 and 1.017 seconds after receiver entry, about 1.53 seconds before Escape. Entry-to-Escape intervals remain within 2.521–2.544 seconds. This is an activation association; the initiator of the activation is not established by these receipts.

Intel's four failures also have the target foreground at all three Escape observations, with target activation 0.916–1.019 seconds after entry and 1.504–1.580 seconds before Escape. Its last Quartz release acknowledgement changes from held to released after 81.290 ms; the other three observe released on the first poll.

All eight helpers complete with validated `FINISHED`, exit status 0, empty runner registries, no cleanup errors and no termination signals. All eight retirement arrays are empty, so this run does **not** exercise the missing-URL retirement branch. The portable positive and rejection cases validate its recorded-evidence rules; the native result proves normal cleanup for these eight executions, not reproduction and recovery of the R2 identity failure.

Independent replay against the exact published R3 classifier agrees with all case fields, both aggregate classifications, ARM's 14 snapshots and Intel's 12 snapshots. Both 242-entry input inventories are unchanged. Eleven retained source copies, four configurations, five test manifests and eight binary hash links were verified per architecture. All held observer AX counts are zero; the XCTest arms contain no observer pointer events. As in earlier artifacts, compiled executable and fixture bytes are not archived and cannot be independently rehashed from these downloads.

| Architecture | Artifact ID | ZIP bytes | SHA-256 |
| --- | --- | ---: | --- |
| ARM | `13543451085` | 318399 | `3e4f6738797850cdc9bd9b0c856262a7e683fc9568b8323843479e833ced06cc` |
| Intel | `13544160514` | 306982 | `03dd5a902fed6623f5f0099a0bd0aed65220069b9bfd0d8e45f9b03af567eec0` |

The next unresolved question is which native activation path changes the foreground application during a held drag in failing CI sessions, and why cancellation then differs. A further change needs evidence of that path, followed by the original complete enter/exit/reentry acceptance sequence on the final candidate. The retained physical and local-helper owner passes remain completed evidence; this diagnostic does not reopen them.

The original C12 acceptance gate remains required. These diagnostic results and measurement repairs do not close task 07, the final review in task 08, or PR #45.
