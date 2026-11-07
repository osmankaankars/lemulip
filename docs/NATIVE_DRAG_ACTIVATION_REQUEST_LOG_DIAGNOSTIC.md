# Native drag activation request log diagnostic

## Question and status

D17 asks one new evidence question: **does a front-process log record referring to an owned target's application serial number appear during the canceled gesture when the same record class is collected across all emitting processes?** It repairs a demonstrated selection gap in the previous diagnostic collector. It does not repair application behavior or replace the native acceptance gate.

This initial protocol is written before native execution. Results must identify the exact tested commit and tree, CI attempt, raw collection status, clock calibration status, identity ambiguities, and unchanged native outcomes. No native success is asserted here.

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

The workflow's shell blocks and embedded Python parsed successfully. A read-only schema smoke check used the original eight D15 reports/traces with only path and D17 metadata substitutions in memory; both PASS and FAIL context shapes loaded correctly. It did not establish new provenance or execute native input, inventory collection, or a system-log query. The native input and classifier diff against the parent is empty. Native Swift compilation, clock-marker availability, empirical calibration, and real log coverage remain unrun until the identified CI attempt.
