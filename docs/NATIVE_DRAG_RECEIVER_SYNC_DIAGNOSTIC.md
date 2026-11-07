# Native drag receiver synchronization diagnostic (D16)

## Question and motivating evidence

D16 asks whether changing the receiver trace's explicit storage synchronization policy changes the strict cancellation outcome under one fixed native drag protocol. The control currently writes each record and then synchronizes its file handle, including records produced by `draggingUpdated`. The source trace and activation journal already defer their file writes. This is a concrete difference in observation cost; it is not an identified activation mechanism or a production cancellation fix.

The retained comparable cancellation cases from [D13 R3](NATIVE_DRAG_MOUSE_DRIVER_DIAGNOSTIC.md), [D14 R2](NATIVE_DRAG_EVENT_ORIGIN_DIAGNOSTIC.md), and [D15 R1](NATIVE_DRAG_DISPATCH_STACK_DIAGNOSTIC.md) contain the following association:

| Retained strict outcome | Comparable cases | Distinct receiver positions during cancellation |
| --- | ---: | --- |
| PASS | 4 | 2 in each case |
| FAIL | 17 | 5–20 per case |

These 21 cases do not isolate trace synchronization. Each PASS also has only one source-moved callback after first receiver entry, while each FAIL has 5–20. All 21 declared common gesture signatures match, as do all 11 Quartz payload sequences, but actual posting durations vary. The series also includes different mouse producers, runner sessions, architectures, and diagnostic instrumentation. Receiver callback counts or positions can be consequences of event delivery as well as contributors to observer cost. The association motivates only a weak, bounded test of the concrete per-record flush. It does not predict an improvement from removing that flush or establish that it initiates target activation.

D15's first target dispatch stacks showed the ordinary AppKit event-pump path in both PASS and FAIL. Their stopping condition remains in force: D16 adds neither another first-event stack variant nor a timing sweep.

## Pinned inputs and scope

| Input | Pin |
| --- | --- |
| Diagnostic parent | `bfd28a169b8c8ee0f2c1a4514526a01cc1572ca8` |
| Diagnostic branch | `codex/drag-receiver-sync-07` |
| Unchanged C12 application commit | `d821d7343675e2850705d141ef9b3b93a6aee945` |
| Unchanged C12 application tree | `425baa28f00ec24551dd70c0cc874a75fa3be0c1` |
| Gesture schedule baseline | D13 R3, `d69f6b344a0dc069027f04061686a308dae79ba4` |
| Runners | `macos-15` / `arm64`; `macos-15-intel` / `x86_64` |
| Xcode | `26.3` |

The application is built once for staging from the pinned C12 source. Each architecture uses the same native AppKit source, literal `NSWindow` control, fixture bytes, observer build, geometry, and global Quartz mouse and Escape producers in all four cases. The public XCTest helper is built once and remains present, idle with respect to mouse production, in every case. Its existing identity, completion, and cleanup requirements still apply.

The receiver is compiled with `LEMULIP_RECEIVER_SYNC_TRACE` only. The D14 event-origin and D15 dispatch-stack compilation flags are absent. Their portable tests remain available in CI, but neither the D14 analyzer nor the system-log collector runs on D16 native output. This keeps their extra observation work outside the D16 native experiment.

Both policies use the same D16 measurement implementation. The intended comparison is the policy difference within D16; the historical suites supply context and are not treated as an otherwise identical control arm.

This is the single-entry terminal-hold diagnostic. Task 07 and PR #45 still require the original complete enter, exit, reenter, Escape, release, and distinct fresh-drop gate. The retained physical and local-helper owner passes remain completed evidence; D16 does not request another owner test.

## Four fixed serial cases

| Order | Case | Mouse producer | Receiver trace synchronization |
| ---: | --- | --- | --- |
| 1 | `quartz-sync-first` | Quartz | `per-record` |
| 2 | `quartz-deferred-first` | Quartz | `lifecycle` |
| 3 | `quartz-deferred-second` | Quartz | `lifecycle` |
| 4 | `quartz-sync-second` | Quartz | `per-record` |

Both policies write each complete trace record immediately through `FileHandle.write(contentsOf:)`. The experimental variable is the explicit `FileHandle.synchronize()` policy for the whole receiver trace, not just `draggingUpdated`. Fixture hashing, fixture-set validation, JSON record construction, and live receiver-entry checks remain enabled in both policies.

The `per-record` arm retains a synchronization after each record. Both policies perform a final synchronization after the last receiver `application-terminated` row and before the activation journal's `activation-terminating` record. The `lifecycle` arm performs only this final synchronization; it has no startup flush. The retained policy and completion evidence must establish which behavior actually executed; a policy label alone is insufficient.

| Gesture parameter | Fixed value or rule |
| --- | --- |
| Initial mouse hold | 0.3 seconds |
| Nominal drag velocity | 400 points per second |
| Cancellation destination hold | 5 seconds |
| Separate fresh-drop destination hold | 1 second |
| Escape schedule | 2 seconds after the observer establishes receiver entry, terminal cursor position, and held left button |
| Escape key-down dwell | 0.15 seconds |
| Release observation | Existing bounded check: at most 1 second, polling every 0.025 seconds |
| Path | One entry followed by a terminal hold |
| Held observation | No observer AX reads or screenshots; no additional pointer motion |
| Execution bound | Four cases, serially, within the existing 25-minute job bound |

These are unchanged nominal protocol values, not a guarantee of identical event-delivery timing. A change in callback duration or dispatch scheduling is part of what the experiment may reveal. There is no case retry, timing sweep, extra focus correction, PID-directed Escape, permission request, TCC change, or global preference change.

## Why immediate writes and storage synchronization are separate

Apple documents [FileHandle.write(contentsOf:)](https://developer.apple.com/documentation/foundation/filehandle/write%28contentsof%3A%29) as a synchronous write to the file handle. Its separate [FileHandle.synchronize()](https://developer.apple.com/documentation/foundation/filehandle/synchronize%28%29) method flushes in-memory file data and attributes toward storage and waits for that flush to complete. Apple's [WWDC19 storage discussion](https://developer.apple.com/videos/play/wwdc2019/419/) distinguishes fast logical I/O through the OS cache from explicit disk synchronization and describes the cost of excessive synchronization.

D16 therefore keeps the immediate writes that the same-host observer uses to establish receiver entry. The existing live-entry evidence checks remain the validation of that witness. It does not replace those writes with an in-memory-only journal or infer entry from a policy setting.

Deferring explicit synchronization changes intermediate crash durability: recent records may not have reached persistent storage if the machine or process fails before the lifecycle flush. A completed write and a later synchronization also do not create a transaction with an independently racing reader. Existing record framing, parse checks, write errors, lifecycle completion, and trace completeness requirements remain material. The experiment does not claim a universal visibility or crash-recovery guarantee for every filesystem.

## Evidence, provenance, and classification

The D16 comparator prepares four distinct nonce-bound helper configurations and case-specific test manifests before recording the immutable input inventory. Provenance binds the exact experiment commit/tree, parent and gesture baseline, four-case plan, policy mapping, receiver build define, candidate commit/tree, relevant Swift/Python source hashes, executable hashes, helper identity, and configuration/manifest hashes.

Every receiver and activation row carries `receiverSyncCase` and `receiverTraceSyncPolicy`. The activation start and ready markers identify synchronization schema 1. Bounded write-duration and conditional synchronization-duration measurements are retained in memory during input; the final `receiverTraceSynchronization` receipt is attached to `activation-terminating` only after a successful final flush. This preserves the immediate receiver-entry witness without writing each measurement as another trace record. Watchdog, fatal, and trace-limit paths cannot produce a successful complete receipt. These supplemental measurement checks remain separate from the inherited strict native outcome.

The retained artifacts include the exact diagnostic Swift and Python sources, workflow and protocol, staged provenance, helper build receipt and project, original and per-case manifests, all available case traces and reports, helper runtime receipts and logs, XCTest results, and before/after input inventories. Executable hashes are retained; this workflow does not archive the compiled application and helper bundles. Retained hashes must not be described as independent rehashing of executable bytes that are absent from the archive.

The strict outcome remains unchanged. After cancellation and release, only Existing may remain, the canceled source sequence must end with operation NONE, and the receiver must not accept that sequence. A distinct fresh drag must then succeed once with the expected Single item and source operation COPY. Original fixture bytes, source/receiver sequence binding, normal helper completion, and clean teardown remain required. Failed cancellation cases retain their failed outcome and the unexecuted fresh leg.

Missing or malformed native evidence, a helper protocol error, or incomplete cleanup retains the inherited non-comparable classification. The additional synchronization validator has a separate result: a policy mismatch or incomplete write/flush receipt stops the comparison without replacing an independently valid native PASS or FAIL, its `passed` field, or its native comparability. The report distinguishes native comparison completeness, synchronization measurement completeness, and overall comparison completeness.

Input mutation, a changed common protocol signature, any non-comparable native case, or invalid supplementary measurement stops further input. The remaining fixed cases are reported as not run. Comparable failures with valid measurements may proceed to the next predeclared case. Nothing is retried or silently replaced.

## Interpretation and stopping condition

| Complete observation | Supported interpretation |
| --- | --- |
| The two `per-record` cases fail and both `lifecycle` cases pass | A repeated association with receiver synchronization policy exists in this protocol. It establishes sensitivity, not the activation mechanism or a production fix. |
| The two `per-record` cases pass and both `lifecycle` cases fail | The reverse repeated association also establishes sensitivity to the policy under this protocol. It is not discarded because it opposes an improvement hypothesis. |
| All four fail | This bounded policy change did not restore cancellation in these cases. It does not prove logging has no effect on delivery or identify the underlying cause. |
| All four pass | The failure was not reproduced in this four-case run. The result does not demonstrate that the deferred policy repaired it. |
| Mixed outcomes within a policy or incomplete evidence | Report each case and its limits. Do not generalize a causal effect or replace the missing comparison with another run. |

The order balances two observations of each policy but supplies neither randomization nor a statistical causal estimate. Even a repeated contrast in either direction leaves possible history and session effects. The diagnostic ends after the fixed cases or its first non-comparable case. Further work requires a new evidence-backed question, not repetition until a desired result appears.

No D16 result alone establishes an upstream activation requester, makes C12 release-ready, or satisfies PR #45's original full gate. C12/PR45 remains HOLD.

## Pre-run checks

The protocol retained in the tested commit marked native execution unrun. The completed R1 results below belong to that exact tested source; this results update is documentation only.

Local portable validation passed all **121 tests**: 105 inherited checks and 16 D16 tests. The initial combined run identified one stale exact source hash in the inherited D14 analyzer after the shared comparator gained explicit case-plan support. That pin was updated to the reviewed shared comparator hash, `44839f19f4eff2b23246bd3919658d8880d234db1c9c31629503ed586b2ebabc`; all 13 analyzer and 8 dependent collector tests then passed. The exact hash gate remains required. Neither native postprocessor is executed by D16.

The workflow requires all existing portable comparator tests, the D14 analyzer and collector unit tests, release/coverage/staging checks, and the new D16 tests before native builds and execution. Portable test success is not a native cancellation result.

## R1: completed comparison and retained-evidence audit

Tested commit: `bcb1f00deba2673d3da5b877eab3407f66a4ce22`; tree: `f4d98f133b2ea2df5571f54482aa80722dcb3dc9`. [Run 42315347973](https://github.com/osmankaankars/lemulip/actions/runs/42315347973), attempt 1, ran from **6 November 2026 23:58:52 UTC** to **7 November 2026 00:05:34 UTC**. Its overall result is **failure**. Both architectures passed all **121 portable tests**, built the unchanged C12 application and diagnostic native executables, and reached the four-case comparison. There was no rerun.

| Architecture | `quartz-sync-first` | `quartz-deferred-first` | `quartz-deferred-second` | `quartz-sync-second` |
| --- | --- | --- | --- | --- |
| arm64 | Comparable FAIL | Comparable PASS | Comparable FAIL | Comparable FAIL |
| x86_64 | Comparable PASS | Comparable PASS | Comparable FAIL | Comparable FAIL |

**All eight native cases are comparable and all eight synchronization measurements are valid.** Both reports have `nativeComparisonComplete=true`, `syncInstrumentationComplete=true`, and `comparisonComplete=true`; neither has `allCasesPassed=true`. The three PASS cases retained Existing alone after cancellation, ended canceled source sequence 1 with operation NONE and no receiver acceptance, then accepted Single exactly once in distinct sequence 2 with source operation COPY. The five FAIL cases accepted Single from canceled sequence 1 and ended it with COPY; their fresh-drop leg was not run. These are the unchanged strict diagnostic outcomes, not the original full PR45 gate.

All eight helpers remained idle as mouse producers and completed normally. Button release, owned application shutdown, empty source/target registries, fixture preservation, and cleanup passed. Each architecture's 242-entry input inventories were unchanged, and all four cases shared the required common input signature. Held observer AX reads and screenshots remained disabled. No native D14 analysis, system-log collection, D15 stack capture, input retry, or parameter sweep was performed.

### Measured receiver policy

The following counts cover the whole receiver trace, including setup and termination. Successful cases additionally contain their separate fresh drag, so whole-trace totals are not directly comparable performance workloads. Every receiver write was bound to the exact retained newline-framed bytes, and every case completed one final lifecycle synchronization after its final observed release.

| Architecture | Case | Native result | Receiver writes | Per-record synchronizations | Final lifecycle synchronization (ms) |
| --- | --- | --- | ---: | ---: | ---: |
| arm64 | `quartz-sync-first` | FAIL | 132 | 132 | 0.002833 |
| arm64 | `quartz-deferred-first` | PASS | 111 | 0 | 0.573875 |
| arm64 | `quartz-deferred-second` | FAIL | 139 | 0 | 0.127375 |
| arm64 | `quartz-sync-second` | FAIL | 137 | 137 | 0.009083 |
| x86_64 | `quartz-sync-first` | PASS | 122 | 122 | 0.003486 |
| x86_64 | `quartz-deferred-first` | PASS | 123 | 0 | 0.462410 |
| x86_64 | `quartz-deferred-second` | FAIL | 138 | 0 | 0.506083 |
| x86_64 | `quartz-sync-second` | FAIL | 139 | 139 | 0.003845 |

Within the canceled gesture's API-start/observed-release interval, the four per-record cases contained respectively **121, 126, 63, and 128** synchronized receiver records (ARM first/second, then Intel first/second). Their summed explicit synchronization intervals were **99.338, 75.591, 83.869, and 138.890 ms**. The four lifecycle cases had **zero** per-record synchronizations. Final synchronization began 1.4527–1.8020 seconds after each case's final observed release. These measurements establish that the policy difference executed. They do not measure complete callback duration, exact physical button boundaries, an upstream requester, or a causal timing threshold.

### Retained movement and activation observations

The three D16 PASS cases each contain two distinct receiver positions in canceled sequence 1 and one source-moved callback at or after the first receiver-entry record timestamp. The five FAIL cases contain 4–8 receiver positions and 4–8 such source callbacks. The association is still present in both streams after changing synchronization policy; it does not isolate receiver processing or establish a cause. The new four-position FAIL also means the earlier 21-case FAIL range of 5–20 must not be reused as a general lower bound.

All eight retained common-input signatures and 26-event Quartz cancellation payloads match, including across architectures. Actual posting and delivery times differ. Each of the five FAIL traces records a type-13/subtype-1 target activation dispatch during the canceled gesture interval and target Escape key-down/key-up receipts; the retained pre-Escape target state is active and key. The three PASS traces contain no such activation dispatch in that interval; their retained pre-Escape source state is active and key, with a source Escape key-up receipt and no target Escape receipt. Absence of a recorded source key-down does not establish nondelivery, and these receipts do not identify the upstream activation requester.

### Artifact identities and replay

| Architecture | Artifact ID | ZIP bytes | Extracted files / bytes | ZIP SHA-256 |
| --- | --- | ---: | ---: | --- |
| arm64 | 13549949717 | 467,743 | 98 / 2,969,931 | `a5c28d9d5c849631af2a043d2d9fb14cc4933ecaa550e578a0e80f4aecf3ad0b` |
| x86_64 | 13550916186 | 477,454 | 99 / 3,083,918 | `6c33fa80f1a6c2f41c668645fd1a19aaeced17fda2367d81fc1602ca1c30bd2b` |

Both archives passed their advertised size and SHA-256, ZIP CRC, path, file-type, entry-count and expansion bounds. A separate read-only audit pinned the tested commit/tree, the inherited strict classifier sources, and the reviewed D16 sources. It reproduced all eight case classifications field for field and both aggregate policy conclusions from the original retained files. It also verified every synchronization receipt against its receiver bytes and termination journal. No native input, live `context_for`, inventory recollection, or system-log query ran during this replay; the archives remained unchanged.

Per architecture, the audit verified **33 retained source copies** against their exact published Git blobs (including the workflow, initial protocol, and three C12 preparation sources), **14 retained immutable input files**, four distinct case configurations, the original plus four case-specific manifests, and eight binary-hash links in the inventory/provenance. ARM's 13 snapshots (3/4/3/3) and Intel's 14 snapshots (4/4/3/3) matched the embedded reports exactly. Compiled executable and fixture bytes are not in these archives; their recorded hash links are not independent rehashes of absent bytes.

The retained `comparison.json` SHA-256 values are `b0a055129c0988cc01328d6dc1c90201da7bee35ef12d94fcaaac666aea23f73` (ARM) and `56dd7b014c5452078136640148f183fb88ee2375a3398ba53e895d0236b6677c` (Intel). The separate auditor's SHA-256 is `52743335c25018c178d3351a62113a56b940052d0120ec9c4685d12e1868ff7e`.

### Conclusion and next boundary

Both architectures report `mixed-results-no-policy-conclusion`. Each lifecycle policy produced one PASS and one FAIL; Intel also produced a PASS and a FAIL under per-record synchronization. **Per-record receiver synchronization was not necessary for the observed lifecycle-arm failures, and deferring it did not establish a reliable cancellation repair.** This does not prove that logging has no effect on event delivery. The fixed order and small sample do not supply a statistical causal estimate, and the matching first/second lifecycle pattern is not a new history-effect conclusion.

The planned comparison is complete. Its mixed result does not justify another synchronization variant or a timing sweep. The open task remains to explain the held target activation and Escape routing well enough to support a concrete repair or an explicit resolution of the CI gate, then verify the final candidate with the original enter/exit/reentry, Escape, release, and distinct fresh-drop sequence. No production change follows from D16 alone.

PR #45 remains open, draft and unmerged at C12 `d821d7343675e2850705d141ef9b3b93a6aee945`; main remains `ade8b1673de0c2dff930430564c17f100f5e807b`. Task 07 and final task 08 acceptance remain open. Completed owner physical/v4 checks and the retained C12 source/twelve-frame review remain completed evidence.
