# Native activation entry calibration

## Question and status

D18 is a **startup-only prerequisite measurement** for the missing request-side evidence in [D17](NATIVE_DRAG_ACTIVATION_REQUEST_LOG_DIAGNOSTIC.md). It asks whether the existing startup of each owned native source/control application actually crosses an observable binding to either public C function `SetFrontProcess` or `SetFrontProcessWithOptions`, on the existing ARM64 and Intel CI runners.

**R1 stopped at compilation before calibration; the SDK-header correction is prepared for R2.** The protocol below fixed the scope and stop conditions before execution. D18 does not perform a drag, post mouse/keyboard input, query accessibility, or test cancellation. A successful calibration would justify considering a narrowly scoped request-entry trace; it would not identify the D17 requester or complete task 07.

## Why this is the next evidence boundary

D17 retained five `launchservicesd SETFRONT` transitions after receiver entry and before Escape in five failing gestures. The daemon record precedes the target activation dispatch by approximately 5–42 ms. The corresponding source key-resignation callbacks also follow the daemon record, by approximately 4.6–24.7 ms. Further endpoint callback stacks would therefore not automatically identify the earlier request.

The retained records have zero activity/parent-activity identifiers, null `source`, and one frame at the daemon logging location. A repeated daemon thread is not a requester token: Intel thread 32764 appears in source startup, held target activation, and a later Finder transition. `oldFrontPid` names the previous foreground process. Neither these fields nor D14's AppKit window-order message formats name the upstream public selector or client.

The owned code's explicit activation calls are startup/setup calls. This source inspection does not rule out later framework requests within the same process. A real intercepted request entry could add a submitting process, target arguments, and a synchronous caller stack. Before collecting any held-drag input with that approach, this experiment checks that a natural AppKit startup path actually reaches the selected wrappers.

## Mechanism and limits

The probe is an ordinary, ad-hoc-signed diagnostic dylib linked into the two isolated native test applications. It is not loaded into the production candidate, a system daemon, Finder, or the observer. The original source/control Swift files, input producers, comparators, C12 production source, and staging helper remain byte-identical to parent `9a3916f806e860b4f7181d26379c0d1711fceea5`.

Apple's [interposition header](https://github.com/apple-oss-distributions/dyld/blob/dyld-1285.19/include/mach-o/dyld-interposing.h), [runtime table builder](https://github.com/apple-oss-distributions/dyld/blob/dyld-1285.19/dyld/DyldRuntimeState.cpp), and [shared-cache patching implementation](https://github.com/apple-oss-distributions/dyld/blob/dyld-1285.19/dyld/Loader.cpp) support this mechanism for launch-loaded dylibs and recorded patchable symbol bindings. The table builder can refuse interposition under its security policy; it does not treat a main-executable interpose section as a launch-loaded interposing dylib. These inspected sources are implementation evidence, not a claim that their version exactly matches this runner's dyld build.

The [prebuilt-loader policy](https://github.com/apple-oss-distributions/dyld/blob/dyld-1285.19/doc/PrebuiltLoaderSet_Policy.md) also records that linking an interposing dylib changes loading behavior. Instrumentation is not timing-neutral. Direct/internal branches, inlining, private entry points, or requests in other processes are not certified by these hooks. A `SETFRONT` log label is not proof of a call through a similarly named exported C function.

The C ABI is checked against the actual SDK declarations at compilation: `SetFrontProcess` returns `OSErr`, whereas `SetFrontProcessWithOptions` returns `OSStatus` and takes `OptionBits`. Each wrapper forwards the original arguments exactly once and returns the original result. It records a bounded stack and raw process-serial-number words without issuing any activation or identity lookup of its own. PSNs are retained as opaque API arguments; they are not assumed to be D17 ASNs.

## Fixed execution

Each architecture runs exactly one startup of the original control and one startup of the original source. The unchanged applications execute their existing `makeKeyAndOrderFront` and `NSApp.activate(ignoringOtherApps: true)` startup code. The helper supplies the existing fixed `quartz-first` configuration and screen-valid source geometry, waits for existing ready records and the affected application's active-state witness, and requests normal termination of only those owned processes.

There is no synthetic direct `SetFrontProcess` calibration call. Such a call would verify only its own binding, not an AppKit route. The helper introduces no `activate` call. Its launch/readiness/cleanup operations have finite deadlines and no launch retry. Forced termination, a missing final journal, a malformed identity, an unfinished record, or overflow is incomplete evidence.

The library records at most 128 calls with at most 48 raw stack frames per call. It retains call identity, process/thread identity, original target words/options, Mach timestamps around capture and original invocation, and original return values. It writes and resolves image information only at termination. A valid loaded-library receipt is required even when the call count is zero. Empty or missing files are not equivalent to a zero-call receipt.

The workflow checks native architecture, exact commit/tree/source identities, ordinary library load commands, interpose-section presence, and binary UUIDs/hashes. It preserves the exact helper, source/control executables, and dylib bytes. Immutable staged inputs are inventoried before and after; the single explicitly named evidence directory is the only task-output exclusion.

The complete staged tree, including empty directories, is retained in a nested ZIP with its own size, SHA-256, entry count, expanded-byte count, and CRC check. Its bounds are 16,384 entries, 64 MiB per file, and 256 MiB expanded. Debug symbols stay outside app bundles before signing. This permits later read-only replay against actual retained input bytes; it does not require running archived executables.

## Predeclared outcomes

| Observation | Allowed result |
| --- | --- |
| Complete normal startup/termination and at least one valid pre-ready intercepted entry with an AppKit frame in **each** process | `startup-route-calibrated`; report which function and actual startup path were observed. This is not full activation coverage. |
| Complete startup evidence and valid loaded-library receipts, but at least one process has no qualifying natural entry | `coverage-unproven`; stop without a held-drag run. Do not claim the application made no activation request. |
| Missing/contradictory identities, bad timestamps, overflow/incomplete buffers, failed startup or abnormal cleanup | `evidence-incomplete`; retain the available bytes and stop. |

The analyzer's nonzero exit for either nonpositive outcome is a calibration gate, not a newly observed cancellation failure. An original C error return remains an observed call, not proof that activation succeeded. Actual active-state witnesses are reported separately. Even a later pre-transition call naming the target would establish a real client-side request, not a unique IPC transaction pairing based solely on time proximity.

## Pre-run validation

Twenty-two focused portable tests passed. They cover complete zero-call receipts, positive startup witnesses, malformed identity and clock data, incomplete/overflow capture, misleading symbol text, calls after native readiness but before a later poll, and a full artifact-loader/CLI replay with ARM's fractional timebase. The YAML, ten shell blocks, and embedded Python parse. Original production/native source, gesture, comparator, and staging paths have an empty diff against the parent. Independent code review checked the probe ABI/forwarding, bounded launch/cleanup, final-file publication, and post-signing identities. Actual SDK compilation, natural entry coverage, and native lifecycle behavior remain unrun at this point.

## R1: compile-only failure and narrow correction

[Run 42419305466](https://github.com/osmankaankars/lemulip/actions/runs/42419305466), attempt 1, executed commit `181b3db6f0438762ebbefbee0bfbc2b503356c2d`, tree `241d5f538b7cabbdd0b8f8813208fbb54e0791a1`. Both architectures passed the 22 portable tests, C12 build, and original staging. Both then stopped at the probe's include of `mach-o/dyld-interposing.h`: that header is present in Apple's published dyld source but absent from these installed SDKs. No source/control calibration startup ran, so R1 has no natural-call coverage result. The output directory was empty and artifact upload also failed; the CI job logs remain the evidence for this build-only result.

R2 removes only that unavailable include and expresses the same two-pointer Mach-O interposition-table layout locally, with two entries for the existing wrapper/original pairs and a table-layout assertion. Actual ApplicationServices SDK declarations still enforce both function signatures and return/argument widths. Forwarding, capture, helper behavior, input scope, and classification remain unchanged. A pre-build commit marker also ensures a compile-stopped run has an artifact to retain. This is a build correction, not a rerun of a previously completed calibration or a changed behavioral hypothesis.

## Disposition

PR #45 remains draft/unmerged and C12 remains HOLD. Task 07's original Finder enter/exit/reenter → Escape → release → distinct fresh-drop gate across three themes and two architectures is unchanged. Task 08's source and screenshot review remains complete, with final acceptance waiting on 07. The owner's physical check and v4 automatic results are complete and are not requested again.

No focus repair, directed Escape, security/preference change, protected-process attachment, timing sweep, or repeated gesture is part of D18. Results will be appended against the exact executed commit and artifact identities.
