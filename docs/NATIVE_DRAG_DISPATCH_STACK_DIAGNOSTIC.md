# Native drag dispatch-stack diagnostic (D15)

## Evidence that motivates this step

[D14 R2](NATIVE_DRAG_EVENT_ORIGIN_DIAGNOSTIC.md) recorded four comparable ARM cancellation failures and one strict Intel diagnostic pass. All five first held target mouse-drag events carried the target PID and CG source-state 0 and were located at the terminal coordinate. Those fields do not distinguish success from failure. The selected system logs identify AppKit window ordering in the target process but do not identify the upstream requester for the held activation.

The next Intel case could not be compared because its helper's identity check ran after FINISHED and observed an already-terminated process. The receipt lacks the current PID, instance equality and URL-presence values needed to reinterpret that historical sample. Its incomplete classification remains unchanged.

D15 makes two bounded diagnostic changes: it corrects that terminal-process observation prospectively, and captures the synchronous caller of the first target mouse-drag dispatch. Neither is a production cancellation fix.

## Fixed input and candidate

- Parent: `9d75fb9ae6a49ef135210c33fbbada974240d084`.
- Branch: `codex/drag-dispatch-stack-07`.
- C12 application: `d821d7343675e2850705d141ef9b3b93a6aee945`.
- C12 tree: `425baa28f00ec24551dd70c0cc874a75fa3be0c1`.
- Gesture baseline: D13 R3 `d69f6b344a0dc069027f04061686a308dae79ba4`.

The same four serial Quartz / XCTest / XCTest / Quartz cases retain the source, literal NSWindow receiver, coordinates, gesture schedule, global Escape and strict native workspace/session checks. This is still the single-entry terminal-hold diagnostic. The original enter, exit, reenter, Escape, release and separate fresh-drop gate remains required for task 07.

## Observe the same finished runner

The helper freezes a positive runner PID only when the live application instance and its paths have been verified. Later checks require both that scalar PID and `NSRunningApplication.isEqual` instance equality. Apple's [processIdentifier documentation](https://developer.apple.com/documentation/appkit/nsrunningapplication/processidentifier) advises comparing application instances rather than relying on PIDs alone. Its [NSRunningApplication documentation](https://developer.apple.com/documentation/appkit/nsrunningapplication) notes that an instance remains valid after exit while properties can lose significance or become unavailable.

Only during the existing bounded stop sequence, after validated FINISHED and with no outstanding input, a unique registry entry for that same instance and positive PID may be observed passively when it is terminated or both identity URLs are unavailable. The receipt distinguishes `terminated` from `identity-urls-unavailable` and records the actual PID, instance match and URL-presence booleans. It never returns that terminal object as a signal target.

Normal cleanup still requires exit 0, an empty registry, no identity/protocol errors, no terminate/force requests and completion within the existing eight-second bound. A different instance/PID, an unavailable PID, an unacknowledged finish or a live mismatched path remains an error. No earlier incomplete run is retroactively accepted.

## One dispatch stack, before CGEvent access

Under `LEMULIP_DISPATCH_STACK_TRACE`, the first target `leftMouseDragged` entry captures the current thread's return addresses before the explicit `NSEvent.cgEvent` getter and before `super.sendEvent`. At most 48 addresses are retained. Capture start/end times, target PID, dispatch index, event timestamp and main-thread state bind the observation to the existing dispatch receipts.

The addresses are buffered until the existing application-termination callback, after held input has ended. Symbol resolution then uses public `backtrace_symbols`; each rendered frame is bounded to 512 characters, with unavailable or truncated results explicit. The observation is attached to the existing `activation-terminating` record. Stack collection has measurable overhead; unchanged gesture scheduling does not mean zero observational disturbance.

Apple documents [Thread.callStackReturnAddresses](https://developer.apple.com/documentation/foundation/thread/callstackreturnaddresses) separately from [callStackSymbols](https://developer.apple.com/documentation/foundation/thread/callstacksymbols). The purpose is to inspect the synchronous caller of this dispatch, not to infer where an asynchronously queued event was created.

## Interpretation and stopping condition

A retained timer or drag-processing caller directly above the target dispatch would identify that synchronous path. It would not, by itself, establish why the event was created, why activation followed or how to repair cancellation.

An ordinary application event-pump stack cannot identify an earlier producer that queued the event. If the stack only shows that path, or symbols are unavailable/truncated at the relevant frames, this observation is inconclusive. It does not justify repeating stack captures with timing variants. The result must remain separate from native acceptance.

## Results

### Reviewed R1 source and run

- Tested commit: [`8d467f0bb64012d1df879083349c7f48aebe1aa1`](https://github.com/osmankaankars/lemulip/commit/8d467f0bb64012d1df879083349c7f48aebe1aa1).
- Tested tree: `bcdee71240090f62164e13850692a4d651639762`.
- Actions run: [`42308788964`](https://github.com/osmankaankars/lemulip/actions/runs/42308788964).
- Attempt 1 started at `2026-11-06T23:00:03Z` and finished at `2026-11-06T23:14:47Z` with an overall failure result.
- Both architectures passed 105 portable checks, all native builds and the event-origin/dispatch-stack analyzer. Both four-case comparisons and their independent retained-evidence audits are complete. Native outcomes and log-collection completeness remain separate below.

| Architecture / retained archive | Artifact ID | ZIP bytes | Files | Expanded bytes | ZIP SHA-256 |
| --- | --- | ---: | ---: | ---: | --- |
| ARM / `D15-R1-arm64.zip` | `13548001797` | 501,417 | 82 | 5,064,244 | `faffc905f90429499c54521838ae9aaf7f1a5875afa43c1a0c1c4a71b6ab3dc5` |
| Intel / `D15-R1-x86_64.zip` | `13547563338` | 340,206 | 83 | 2,316,793 | `4c80ada8696e59d07796599354ee4478fcaa650e374835459329d7ac35831f38` |

The principal receipts in each archive are `drag-mouse-driver-comparison/comparison.json`, `drag-event-origin-analysis/event-origin-analysis.json`, the four case directories under `lemulip-native-ui`, and `drag-event-origin-system-log/receipt.json`. The independent retained-evidence audits are `D15-R1-arm64-audit.json` and `D15-R1-x86_64-audit.json`.

### Native outcomes on both architectures

All eight fixed cases are comparable. ARM fails strict Escape cancellation in all four cases. Intel passes its first Quartz case and fails the other three.

| Fixed case | ARM strict diagnostic outcome | Intel strict diagnostic outcome |
| --- | --- | --- |
| `quartz-first` | FAIL | PASS, including the separate fresh drop |
| `xctest-first` | FAIL | FAIL |
| `xctest-second` | FAIL | FAIL |
| `quartz-second` | FAIL | FAIL |

The Intel pass preserves Existing alone after cancellation, records no target acceptance for the canceled session and ends that source session with operation NONE. A distinct fresh sequence 2 then accepts Single exactly once and ends with source operation COPY. Each of the seven failures instead contains Existing plus Single after the cancellation release and stops before the fresh-drop leg. This one pass is a pass of the single-entry terminal-hold diagnostic, not coverage of the original enter/exit/reentry gate.

Cleanup is normal in every case, with the button released, owned processes stopped, registries empty and no cleanup errors. Each architecture's before/after input inventories are equal. All eight `runnerRetirementObservations` arrays are empty, so neither architecture exercises the new terminal-retirement allowance in this run.

### Stack observation and measured cost

Both `analysisComplete` and `dispatchStackObservationsComplete` are true on both architectures. Each stack is bound to the first held target mouse-drag dispatch, retains all 12 captured frames and has no unresolved rows or truncated symbol text. Within each architecture, all four rendered stacks are identical after replacing hexadecimal load addresses. Across architectures, removing those addresses and architecture-specific symbol offsets leaves the same 12-symbol sequence. That sequence occurs in the Intel PASS and all seven FAIL cases.

The relevant caller sequence is `NSApplication.run` → the observed `-[NSApplication _handleEvent:]` frame → the target's `sendEvent` override → `captureFirstDispatchStack`. The private-looking frame name is retained symbol text; the diagnostic does not call that method or depend on a private API.

| Architecture | Fixed case | Entry capture | Deferred symbol rendering |
| --- | --- | ---: | ---: |
| ARM | `quartz-first` | 0.1121 ms | 13.0597 ms |
| ARM | `xctest-first` | 0.2050 ms | 7.2403 ms |
| ARM | `xctest-second` | 0.0903 ms | 3.2429 ms |
| ARM | `quartz-second` | 0.2507 ms | 3.4288 ms |
| Intel | `quartz-first` | 0.1940 ms | 227.0359 ms |
| Intel | `xctest-first` | 0.2942 ms | 1.4696 ms |
| Intel | `xctest-second` | 0.1376 ms | 1.3668 ms |
| Intel | `quartz-second` | 0.1803 ms | 1.5170 ms |

ARM entry capture took 0.0903–0.2507 ms; deferred rendering took 3.2429–13.0597 ms and began 1.4144–1.6422 seconds after the final observed button release. Intel entry capture took 0.1376–0.2942 ms; deferred rendering took 1.3668–227.0359 ms and began 1.6290–5.1247 seconds after the final observed release, including the fresh leg in its passing case. These are separate measurements: the rendering duration is not the delay between release and termination. No zero-overhead or exact physical release-time claim follows from them.

### Audit scope and decision

Both read-only audits passed. Together they reproduced all eight native classifications field by field and each complete event-origin/dispatch-stack analysis exactly using the published source. Each audit verified 13 retained source copies, equality of the 242-entry before/after input inventories, four immutable case configurations and the recorded links for eight executable hashes. Snapshot equality covers 12 ARM and 13 Intel retained comparisons. Executable and fixture bytes were not archived, so these audits do not reverify those bytes or rerun the live `context_for` checks; `fullContextForRechecked` remains false. Both archives remained unchanged during their audits.

ARM's system-log collector retained 2,429 selected records. Its case/PID/time bindings and selected-record consistency were audited. Raw stdout/stderr and rejected records are not retained, so they cannot be independently reconstructed from this archive. This receipt validation establishes retained-record consistency, not an upstream event producer.

Intel's log query timed out after 20.133974918 seconds, including termination and reap after the fixed 20-second bound. Its receipt reports 3,083,670 incomplete stdout bytes, zero stderr bytes and zero selected records, with `collectionCompleted: false` and `stdoutComplete: false`. The independent audit verified the query context, command and receipt bindings while preserving that TIMEOUT result. **Audit success is not successful log collection:** there is no Intel selected-log analysis, and zero selected records here is not evidence that an activation request was absent. No query or native case was rerun.

The measured entry stacks show the ordinary AppKit event-dispatch path in both the passing case and the failures. No synchronous timer or drag-processing caller appears above this dispatch in the retained stacks; an earlier producer that queued the event cannot be recovered from them. The observation therefore does not distinguish native outcomes or establish the upstream cause. **The declared stopping condition is met on both architectures: no further stack or timing variants are warranted by these results.** This run establishes no production fix and does not satisfy task 07's original enter/exit/reentry cancellation-and-fresh-drop gate. C12/PR45 remains HOLD.

<!-- D15_RESULT -->
