# Native drag activation request log diagnostic

## Question and status

D17 asks one new evidence question: **does a front-process log record referring to an owned target's application serial number appear during the canceled gesture when the same record class is collected across all emitting processes?** It repairs a demonstrated selection gap in the previous diagnostic collector. It does not repair application behavior or replace the native acceptance gate.

**R1 is complete: three comparable native PASS cases and five FAIL cases.** Both bounded queries and clock calibrations completed. Newly retained `launchservicesd` transition rows precede Escape in all five failures; their upstream requester remains unknown. See [the completed results](#r1-completed-run-and-new-server-side-transition-evidence) below. The following protocol was retained in the tested commit before execution and does not treat diagnostic success as acceptance of PR #45.

The branch is `codex/drag-activation-request-log-07`, based on retained-evidence commit `3cb160df4b029005f59cc0d1e0eb46cb574612df`, tree `763e08da65bf2fc93ecee4856245fe9879c852a6`. C12 remains `d821d7343675e2850705d141ef9b3b93a6aee945`, tree `425baa28f00ec24551dd70c0cc874a75fa3be0c1`. PR #45 remains draft and HOLD; task 08's final acceptance still depends on task 07. Completed owner physical/v4 checks remain completed.

## The demonstrated selection gap

The preceding [retained routing evidence](NATIVE_DRAG_ROUTING_EVIDENCE.md) established a held target activation and Escape routing association, without identifying its upstream requester. D15's first target dispatch stack and D16's receiver synchronization comparison did not provide a reliable repair. Neither question is reopened here.

The old `capture_native_drag_system_log.py`, SHA-256 `ccc23050210516a9a8ed2d5074af656f0306f318bab720e6144878ca6f921827`, selected owned emitting processes, or a short list of shared processes whose message contained an owned PID or bundle reference, and then required an activation/front/focus/drag keyword. It retained a reduced field set rather than the exact query stdout.

Actual retained records contain subsystem `com.apple.processmanager`, category `front-35286506`, with these observed formats:

```text
BringFrontModifier: pid=%ld asn=0x%x-0x%x Modifier %ld hideAfter=%d hideOthers=%d dontMakeFrontmost=%d mouseDown=%d/%d seed=%ld/%ld
SetFrontProcess: asn=0x%x-0x%x options=%lx
```

The second format contains an ASN, but no PID or bundle reference. The retained D14/D15 collections contain 18 such rows: eight D14 ARM, two D14 Intel, and eight D15 ARM. Each was retained through its owned emitter identity. Replaying the actual old selector with the same messages assigned to each of its four shared emitter names rejects all 72 hypothetical rows. This establishes a selection blind spot; it does not establish that any excluded requester record actually existed.

All 18 observed rows precede the first receiver-entry wall-second in their bound case. Their placement is startup-associated, not proof of an exact pre-mouse-down boundary. Their `activityIdentifier` is zero and their format-specific `traceID` repeats across cases; neither is a unique request transaction key. None of these old rows supplies a cross-process requester link.

The read-only coverage analysis, SHA-256 `d327a7711ad33ac39f0aa164aee5368176c000bb1413c5551a8a62b1bd459a74`, binds the original log receipts, selected records, provenance, and receiver traces. It does not reconstruct discarded stdout. In particular, D15 Intel's 20-second timeout retained a byte count and hash of partial stdout, but not those bytes; its empty selected output cannot be reinterpreted as absence of a request.

## Fixed native experiment

One workflow attempt runs on the existing `macos-15` ARM and `macos-15-intel` runners with the pinned Xcode path. Each architecture executes exactly the existing four-case order:

| Case | Mouse producer |
| --- | --- |
| `quartz-first` | Quartz |
| `xctest-first` | XCTest |
| `xctest-second` | XCTest |
| `quartz-second` | Quartz |

The inherited D13-R3 gesture has one receiver entry, a terminal hold, global CG Escape, release, and the conditional distinct fresh drag. Its timing, geometry, event payloads, no-held-AX policy, fixture bytes, owned helper retirement, and strict classifier remain unchanged. Native source, receiver, observers, mouse helpers, and classifier sources are byte-identical to the branch parent. The workflow verifies that diff before building.

The receiver is compiled without D14 event-origin, D15 dispatch-stack, or D16 synchronization instrumentation defines. Its default behavior is unchanged. The C12 application is built and staged from its exact commit/tree. The new clock helper is compiled into a separate directory outside the staged immutable input inventory.

After cancellation and release, strict success still requires Existing alone, source operation NONE for the canceled sequence, and no receiver acceptance of that sequence. A distinct fresh sequence must subsequently accept Single once with source operation COPY. Fixture preservation, normal helper completion, and clean teardown remain required. Failed cancellation retains FAIL and an unexecuted fresh leg. Incomplete native evidence retains its inherited non-comparable classification and stops further input. Comparable failures may proceed through the predeclared remaining cases.

This diagnostic's single-entry result cannot satisfy the original Finder enter/exit/reenter, Escape, release, and distinct fresh-drop gate across three themes and both architectures.

## One bounded query after input

The new collector is separate from the old one. After validating its retained native context, it makes exactly one `/usr/bin/log show` query after native input, with the existing **20-second** timeout and **10 MiB shared stdout/stderr** limit. A pre-query validation failure records zero queries; it does not trigger a fallback. There is no retry or larger query. It selects the complete observed front-process category across emitters, plus this diagnostic's exact clock markers:

```text
(subsystem == "com.apple.processmanager" AND category == "front-35286506")
OR (the owned clock subsystem, category, and session nonce)
```

No PID, bundle, emitter-name, or activation-keyword condition is added to the front-category arm. The query requests JSON, UTC timestamps, and available info/debug entries. These flags select existing records; the workflow does not change logging configuration. Query bounds include both clock markers and case wall windows, with one second of padding.

The collector retains exact bounded `raw.stdout` and `raw.stderr` even on timeout, nonzero exit, malformed JSON, or truncation. A complete exit-zero JSON array additionally produces full-field `records.json`. Derived rows reference their original array indices and preserve the complete original entry. Collection receipts distinguish complete data from partial evidence, and retain command, bounds, byte counts, hashes, and status. An unexpected analysis error returns nonzero while preserving any completed collection; an explicitly unresolved calibration is a documented analysis result. Missing records never become an absence-of-request conclusion.

## Identity binding and requester limits

An ASN is an opaque observed pair of hexadecimal values. It is not derived from a PID. The collector only binds an ASN to an owned role through an explicit `BringFrontModifier` record whose message PID, emitting PID, full executable path, nonempty boot UUID, and unambiguous case window agree with retained native evidence.

All anchors for a boot/ASN are considered. Conflicting identities, wrong executable paths, reused PIDs, overlapping case windows, missing metadata, and redacted or unrecognized messages remain ambiguous or unresolved. Selecting the first or closest anchor is not allowed. Startup rows may precede the first instrumentation record, so startup association is scoped to the unique case wall window and exact emitter identity; it is not an invented process-birth timestamp. A held-phase claim additionally requires a calibrated interval wholly inside the owned process's observed trace lifetime.

A matching `SetFrontProcess` row supports an **observed emitting process context, an owned ASN reference, and bounded timing**. It does not establish the ultimate upstream requester. An internal subsystem may emit on behalf of another process, and the observed message format is not a documented universal coverage guarantee. Other category rows are retained even when they do not match these two formats.

Source and target startup anchors and startup `SetFrontProcess` witnesses are reported separately. They positively show that the query can retain this message path at startup. They do not prove that every held activation uses it, that all records persisted, or that redacted/unlogged paths are absent.

## Empirical clock calibration

`NativeTraceClock` is a synchronous Foundation/OSLog/Darwin command-line helper. It performs no AppKit initialization or input. It reads the boot UUID and Mach timebase, brackets a `ProcessInfo.systemUptime` sample with both absolute and continuous Mach clocks, then brackets one public notice log marker with clocks and wall time. It writes one bounded JSON line and exits. Invalid metadata, clock order, or output produces a failure receipt, which cannot establish calibration even if a marker was emitted before the failure.

The helper runs once before all four native cases and once after their completion or failure. The exact marker is:

```text
LEMULIP_NATIVE_TRACE_CLOCK <session nonce> before|after
```

Its subsystem is `app.lemulip.NativeTraceClock`; category is `calibration`. Provenance binds the source and executable hashes, absolute helper path, session nonce, experiment commit/tree, architecture, and exact configuration bytes. The workflow verifies native helper architecture and reads `sysctl.proc_translated`; only an explicit native value or the documented unavailable-key result is allowed. This environment observation is retained separately from the frozen native input protocol.

The collector requires successful, hash-bound helper execution receipts and unique log markers matching nonce, phase, PID, executable path, and boot UUID. A candidate clock family is compatible only if each marker's actual `machTimestamp` falls inside the corresponding captured logging bracket. The captured `mach_timebase_info` fraction converts ticks to seconds; raw ticks are never assumed to be nanoseconds.

For each candidate clock family, the uptime sample and its enclosing Mach samples establish an offset interval. Exact rational arithmetic preserves tick/timebase bounds before outward conversion for reporting. Before and after intervals must intersect; incompatible offsets are unresolved, without averaging or widening tolerance. If both clock families remain compatible, timing conclusions use the union of their possible mapped intervals. A record receives a phase only if its whole interval lies within the same retained phase and observed lifetime. Boundary overlap, out-of-span values, missing markers, duplicate markers, or inconsistent clocks remain unresolved.

An observed release timestamp is later than the release it observes. The phase after Escape therefore ends at **release observation**, not at an asserted exact button-release instant, and carries `heldButtonClaimSupported=false`. A row in that interval must not be described as definitely occurring while the button remained held. API-call and fresh-drag observation intervals have the same distinction; their labels do not establish exact physical button boundaries.

Apple documents that [system uptime](https://developer.apple.com/documentation/foundation/processinfo/systemuptime) measures awake time, [Mach clocks](https://developer.apple.com/documentation/driverkit/c-runtime-support) differ in sleep handling, and [architecture differences](https://developer.apple.com/documentation/apple-silicon/addressing-architectural-differences-in-your-macos-code) affect Mach values and translation. This experiment empirically calibrates the observed `log show` JSON field for its own boot and time span. It does not assert a public, cross-version contract for that undocumented field. Wall time supplies query bounds and coarse checks, not fine-grained event ordering.

## Interpretation and stopping condition

| Observation | Supported result |
| --- | --- |
| A uniquely bound target ASN record is wholly inside a held phase | A retained front-process message referring to that owned target occurred in that phase; report its emitter and full context. Upstream causation remains a separate question. |
| New cross-emitter records are retained but identity or time is ambiguous | The old selection gap is demonstrated in this run; the specific requester or phase remains unresolved. |
| Only startup witnesses appear | This message path is observable at startup; no held-path coverage or absence claim follows. |
| Query times out, truncates, fails, or has malformed JSON | Preserve partial raw bytes and status. Do not retry, parse a partial prefix into complete evidence, or change native verdicts. |
| Clock markers or identity anchors are missing/inconsistent | Preserve complete collection if available; timing or attribution remains unresolved. |

The comparison ends after the fixed four cases or the inherited first non-comparable case. The log query then ends at its existing bound. Supplemental collection and calibration status remain separate from native PASS/FAIL. This is not a permission change, focus repair, PID-directed Escape, timing sweep, synchronization variant, or retry-until-green procedure.

The workflow retains full native reports and traces, comparison inventories, helper receipts and configuration, the clock executable, raw query bytes, complete parsed records when available, derived analysis, provenance, and exact diagnostic sources. Other compiled application/helper binaries and fixture bytes are not archived; their recorded hash links must not be described as independent rehashes of absent bytes.

Further action must follow the actual retained result. A production repair still requires a supported mechanism and verification with PR #45's original gate. D17 alone does not authorize merge or release.

## Pre-run validation

All **143 portable tests** passed locally: 121 inherited checks and 22 focused collector tests. The new tests exercise ASN-only cross-emitter retention, boot/PID/path and case-window conflicts, marker identity and execution failures, exact clock bounds and ambiguous models, release-observation semantics, unchanged native verdicts, and raw retention on unsuccessful collection or analysis. An independent review reran the 22 focused tests and found no remaining material correction.

The workflow's shell blocks and embedded Python parsed successfully. A read-only schema smoke check used the original eight D15 reports/traces with only path and D17 metadata substitutions in memory; both PASS and FAIL context shapes loaded correctly. It did not establish new provenance or execute native input, inventory collection, or a system-log query. The native input and classifier diff against the parent is empty. Native Swift compilation, clock-marker availability, empirical calibration, and real log coverage were unrun at that pre-run stage; their completed R1 observations follow.

## R1: completed run and new server-side transition evidence

Tested commit: `a17259046aed8ef62c0bd5273e530847b9c78b3c`; tree: `460878bd1e11b3c17c830b9c34d767add856fa5c`. [Run 42357652748](https://github.com/osmankaankars/lemulip/actions/runs/42357652748), attempt 1, ran from **7 November 2026 08:57:37 UTC** to **09:04:30 UTC**. Overall result: **failure**. Both architectures passed all **143 portable tests**, built unchanged C12 and all native helpers, completed both clock markers, and completed their single bounded query. The failing step is the unchanged strict native comparison.

The initial protocol above belongs to that exact tested source. This results update and its retained-data projection do not change the collector, native input, or classifier, and do not trigger another native run.

### Native results

| Architecture | `quartz-first` | `xctest-first` | `xctest-second` | `quartz-second` |
| --- | --- | --- | --- | --- |
| arm64 | Comparable PASS | Comparable FAIL | Comparable FAIL | Comparable PASS |
| x86_64 | Comparable PASS | Comparable FAIL | Comparable FAIL | Comparable FAIL |

All eight cases are comparable and both comparisons are complete. The three PASS cases retain Existing alone after cancellation, source operation NONE, no receiver acceptance of the canceled sequence, and the distinct fresh Single/COPY sequence. The five FAIL cases accept the canceled Single sequence and retain their failure; the fresh leg is not run. All cases complete normal cleanup with the left button up, source/target/runner stopped, and expected registries empty. Held observer AX reads remain zero, guard violations remain empty, and each architecture's 242-entry immutable input inventory is unchanged.

These counts are observations of this fixed diagnostic run, not a mouse-producer reliability estimate. They do not satisfy the original exit/reentry gate or establish a repair.

### Complete query and empirical calibration

| Observation | arm64 | x86_64 |
| --- | ---: | ---: |
| Query count | 1 | 1 |
| Query elapsed seconds | 1.427270166 | 2.175731394 |
| Exact stdout bytes | 302,113 | 301,573 |
| Stderr bytes | 0 | 0 |
| Complete JSON records | 251 | 250 |
| Front-category records | 249 | 248 |
| Owned clock markers | 2 | 2 |
| `BringFrontModifier` rows | 8 | 8 |
| Mixed-case `SetFrontProcess` rows | 8 | 8 |
| Other front-format rows, retained in full | 233 | 232 |
| Uppercase `SETFRONT` rows within those other formats | 20 | 19 |
| Owned role startup anchor/request pairs | 8 | 8 |
| ASN mapping conflicts | 0 | 0 |

Both collections are `completed-records`; there is no timeout, truncation, malformed output, or retry. The exact raw JSON arrays equal the complete parsed records field for field. Every derived front entry preserves its original full entry, including fields the old collector dropped.

Both marker pairs validate against helper execution receipts, exact nonce, boot, PID, path, and captured clock brackets. ARM's captured Mach timebase is 125/3 nanoseconds per tick; Intel's is 1/1. Both absolute and continuous models remain compatible, so the clock family is explicitly ambiguous. The union of compatible model intervals is used throughout. Its resulting time widths are approximately **3.083 microseconds on ARM** and **3.243 microseconds on Intel**. These are empirical conversion bounds, not a measurement of total instrumentation uncertainty or log completeness.

All sixteen mixed-case `SetFrontProcess` messages remain startup observations. The new positive canceled-gesture evidence comes from another retained format: uppercase `SETFRONT`. The frozen CI analyzer correctly leaves this format unrecognized while preserving it in full. The following interpretation is a separate read-only analysis of those retained bytes, not a modified CI result.

### Five retained source-to-target transitions before Escape

The observed uppercase format is:

```text
SETFRONT: pid=%d asn=0x-0x%x foreground=%d oldFrontPid=%d oldFrontASN=0x-0x%u
```

All 39 rows of this format are emitted by `/System/Library/CoreServices/launchservicesd`: PID 122 on ARM and PID 124 on Intel. In every one of the five FAIL cases, one row names the owned target as `pid`, the owned source as `oldFrontPid`, and `foreground=1`. Its entire calibrated interval lies after receiver entry and before Escape, inside both owned processes' observed trace lifetimes.

| Architecture / case | Raw array index | Previous source PID → new target PID | Log → target dispatch callback | Log → target active callback | Log → Escape start |
| --- | ---: | --- | ---: | ---: | ---: |
| ARM `xctest-first` | 132 | 7967 → 7959 | ≈42.38 ms | ≈57.35 ms | ≈1.52386 s |
| ARM `xctest-second` | 187 | 8617 → 8514 | ≈18.62 ms | ≈22.82 ms | ≈1.59693 s |
| Intel `xctest-first` | 131 | 10538 → 10522 | ≈12.24 ms | ≈15.72 ms | ≈1.56798 s |
| Intel `xctest-second` | 186 | 10949 → 10783 | ≈7.39 ms | ≈11.97 ms | ≈1.59881 s |
| Intel `quartz-second` | 241 | 11215 → 11199 | ≈5.12 ms | ≈11.36 ms | ≈1.45538 s |

The dispatch observation is `appkit-defined-enter`, event type 13/subtype 1; the active observation is `application-became-active`. These deltas use **`callbackSystemUptime`**, not the later JSON journal timestamp. Both clocks and the full bounded delta intervals are retained in the [machine-readable transition evidence](evidence/D17-front-transitions.json). `NSEvent.eventTimestamp` is not used for calibration or these deltas.

The ASN components require the retained format string: the new component uses hexadecimal `%x`, while the previous component uses decimal `%u` despite its literal `0x` prefix. For example, ARM index 132's previous suffix `245820` is decimal and corroborates the source anchor's hexadecimal low component `0x3c03c`. Parsing that suffix as hexadecimal would create a false mismatch. All five positive rows corroborate their same-boot target/source startup anchors. The omitted high component is not reconstructed from the uppercase message; identity uses the explicit PID and its separately verified full anchor.

The only front-category rows retained inside any canceled-gesture phase are these five transitions. No matching row is retained in the three PASS cancellation intervals. This is retained-data coverage, not proof that no other request occurred. The two ARM PASS cases have positive matching transitions during their distinct fresh-call intervals, at indices 77 and 242. Intel's PASS case has no retained matching fresh transition; that absence is not converted into a claim that successful drops need no activation.

### The actual old-collector exclusion

Replaying the unchanged old local selector against all 39 uppercase rows rejects all 39. For the five positive canceled-gesture rows, the owned-PID message-reference condition **does** match. The rejecting condition is the emitter allowlist: it includes `lsd`, but not `launchservicesd`. The daemon is also not one of the owned case processes.

This is an actual demonstrated process-selection blind spot in the retained R1 data. It is distinct from the earlier hypothetical shared-emitter exclusion of ASN-only mixed-case `SetFrontProcess` messages. Collecting the full category across emitters recovered useful server-side transition evidence without a new input or timing variant.

### What the new record establishes

The evidence now connects a system-daemon front-transition record to each failed case's exact source/target identities and to the subsequent owned activation callbacks, before Escape is posted. The observation precedes target dispatch callbacks by roughly 5–42 milliseconds and is therefore stronger than the earlier target-only endpoint observation.

It still does **not** identify the original activation requester or prove that `launchservicesd` initiated the transition. `oldFrontPid` identifies the previous foreground process, not the caller. The retained `activityIdentifier` and `parentActivityIdentifier` are zero; `source` is null. Each of the five rows has one backtrace frame in `launchservicesd`, whose offset equals `senderProgramCounter`: 155508 on ARM and 145594 on Intel. The image UUID, trace ID, and logging offset repeat within each architecture. They identify a logging location, not a cross-process request chain or upstream stack.

The next evidence boundary is the request/client context that precedes this server transition, or positive evidence from the actual source drag-tracking consumer of Escape. D17 does not support a production focus change, directed Escape, permission change, or another parameter sweep. Its fixed run is complete; the new retained data should be used before considering any further native experiment.

### Artifact identities and independent verification

| Architecture | Artifact ID | ZIP bytes | Extracted files / bytes | ZIP SHA-256 |
| --- | --- | ---: | ---: | --- |
| arm64 | 13568960184 | 544,892 | 119 / 3,902,341 | `e2c44b86be6515c4a23b9e0c526a959330f6cc6649575a233286bff3e404f343` |
| x86_64 | 13568149451 | 545,049 | 118 / 3,887,604 | `4267aed58c11dc0d64ff27e3d8de10ddbd89f2318d1d3d4f87a2b649c7d30e7e` |

Both archives passed their advertised size and SHA-256, ZIP CRC, path/type checks, and entry/expansion bounds. They remained unchanged throughout the read-only audits.

A separate native/provenance audit reproduced all eight classifications and both aggregates field for field. Per architecture, it verified 36 retained diagnostic/candidate source copies against published Git blobs and their manifest, rehashed 14 archived immutable input files, and verified the recorded inventory links for eight native executables and four fixtures. Those other executable/fixture bytes are absent and were not independently rehashed. The archived clock binaries were independently hashed and parsed as native thin Mach-O executables: ARM 147,520 bytes, SHA-256 `6385bdcf38a3a4f5d906e1a8f81339850e834c4e8d33b87e72b6b3299dc40d1f`; Intel 113,696 bytes, SHA-256 `48d954a216d91ab608ef879668cd70ce0e56b4cab26b357eba8debbe4bbe607d`.

An independent front-log audit reconstructed rational clock intersections and phase boundaries from the original traces, verified marker/configuration/executable hashes and all ASN bindings, checked full-field raw/parsed/derived equality, and reproduced `analyze_records` exactly. Its supplementary uppercase analysis checked all 39 records and the five positive canceled-gesture transitions. The public JSON preserves all 39 original system-daemon entries, exact indices, bounds, callback observations, archive identities, and input hashes; only local archive locations and derived owned-process executable paths are omitted.

The native audit JSON hashes are `37ff90282d6c83150b66d646a87bfdfd63d342f8bc5d70dbffc65b7f20a92a48` (ARM) and `402ab687f696bc71c803073ae1771e080b8badea1f22caf69eca06dcec309ae1` (Intel). The front audit hashes are `364fc92f777b19052c4efb7e64d8a5f750f8d3f745b077953cf33e147f465c0b` and `119853ae4806e702a7719112a8cd912ee03a8a280fe5a832f2c816c208c828cc`. The full supplementary uppercase analysis hash is `ec7e5635c7f9dd2a9227189ea1102f2a585c553f21ca746de64e655bef4da7e5`.

PR #45 remains open, draft and unmerged at C12. Task 07 and task 08 final acceptance remain open. The completed owner physical/v4 results and C12 source/twelve-frame review remain completed evidence.
