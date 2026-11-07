# Native activation entry calibration

## Question and status

D18 is a **startup-only prerequisite measurement** for the missing request-side evidence in [D17](NATIVE_DRAG_ACTIVATION_REQUEST_LOG_DIAGNOSTIC.md). It asks whether the existing startup of each owned native source/control application actually crosses an observable binding to either public C function `SetFrontProcess` or `SetFrontProcessWithOptions`, on the existing ARM64 and Intel CI runners.

**R2 is complete: both architectures produced `coverage-unproven`.** All four native startup lifecycles completed normally and all four loaded probes published valid zero-call receipts. The selected C-entry route therefore has no natural-path calibration witness and is not extended into a held drag. R1 had stopped at a missing SDK header before calibration. The protocol below fixed the scope and stop conditions before execution. D18 performed no drag, posted no mouse/keyboard input, queried no accessibility, and did not test cancellation.

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

R2 removed only that unavailable include and expressed the same two-pointer Mach-O interposition-table layout locally, with two entries for the existing wrapper/original pairs and a table-layout assertion. Actual ApplicationServices SDK declarations still enforce both function signatures and return/argument widths. Forwarding, capture, helper behavior, input scope, and classification remained unchanged. A pre-build commit marker also ensures a compile-stopped run has an artifact to retain. This was a build correction, not a rerun of a previously completed calibration or a changed behavioral hypothesis.

## R2: completed startup calibration

[Run 42419686902](https://github.com/osmankaankars/lemulip/actions/runs/42419686902), attempt 1, executed commit **`80f92e41ccfedb54a15b0a5ef9572a5a57a88c4d`**, tree **`e159ad30d8ad0ef0443a0ee04dc74b515f739ddb`**. It ran on 7 November 2026 at 22:14:41–22:16:40 UTC, or **8 November 01:14:41–01:16:40 Europe/Istanbul**. ARM job `128545233709` and Intel job `128545233926` passed all 22 portable checks, the C ABI assertions, native builds, identity/input preparation, startup/cleanup, and complete evidence retention. Each job failed only the deliberately nonpositive coverage gate.

| Architecture / process | PID | Native ready and active witness | Captured C entries | Cleanup |
| --- | ---: | --- | ---: | --- |
| ARM control | 3878 | Complete | 0 | Normal, no fallback |
| ARM source | 3890 | Complete | 0 | Normal, no fallback |
| Intel control | 5267 | Complete | 0 | Normal, no fallback |
| Intel source | 5274 | Complete | 0 | Normal, no fallback |

ARM ran macOS 15.8.2 build `24H232`; Intel ran macOS 15.7.9 build `24G830`, using the pinned Xcode 26.3 developer directory. The startup helper elapsed times were 2.023760 and 2.103771 seconds, respectively. Both helpers already had prohibited activation policy and did not change it. Both sources terminated with zero sessions and no active drag. No input, accessibility call, launch retry, signal fallback, outstanding launch completion, or helper error was recorded.

Each C receipt records successful initialization and warmup, matching executable/library/boot identities, `atexitInvoked=true`, and closed capture. All ten counters are zero, including dropped, unfinished, overflow, before-ready, and active-at-flush counts. All four `calls` arrays are empty. Final receipts exist and no `.pending` files remain. These are complete zero-call observations, not empty or missing output interpreted as zero. The [machine-readable evidence](evidence/D18-startup-calibration.json) retains both complete analyses, all probe fields except two explicitly identified local paths, lifecycle projections, and the unmodified original-file hashes.

Normal termination is supported by accepted termination requests, verified process identities, observed termination, original lifecycle records, and probe `atexit`. The helper did not receive a child wait status from NSWorkspace; **no child exit-code-zero claim is made**.

### Static binary inspection

Independent read-only inspection found the expected 32-byte, two-pair `__interpose` table in both retained dylibs. Chained fixups bind the two own replacement functions to strong `SetFrontProcess` and `SetFrontProcessWithOptions` imports from ApplicationServices. All four apps have the ordinary library dependency and expected relative Frameworks search path. Loaded library copies, UUIDs, executable hashes, and receipt identities agree.

The linker placed the table in `__DATA_CONST` with section flags zero. Apple's inspected [section-discovery implementation](https://github.com/apple-oss-distributions/dyld/blob/dyld-1285.19/mach_o/Header.cpp) also recognizes the section name in `__DATA`-prefixed segments, so this is not an identified construction defect. Stored CodeDirectory flags are ad hoc (`0x2`), without the hardened-runtime/library-validation bits. These static observations **do not show dyld's runtime patching decision or AMFI's `allowInterposing` value**.

### Integrity and exact replay

| Architecture | Outer artifact ID | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| ARM64 | `13592893180` | 8,183,349 | `b8ca44b0dcfb8335e729fc5b8bcc5a61530454fd7b2e4bff0b8f5408a293e87d` |
| Intel | `13592938122` | 8,259,242 | `5c856aabac18829b43d5fe313db9bc32d0065bdd57f4f93463349285bd631df7` |

Outer archives each contain 43 files. The nested staged archives each contain 134 entries: 80 files and 54 directories, including the original empty directories. Nested SHA-256 values are ARM `b1f7444f82ec1047e14dc3e20e099df938fb521c40ee60b4c9a8d9791b264969` (5,815,712 bytes) and Intel `89bd4ff2147bb8c927f373edce7ec5696cc23f8b36e3e372f57e74579a4938f9` (5,877,246 bytes). Size, hash, CRC, path/type and expansion bounds passed, and every extracted file equals its archived bytes.

Each architecture preserves **128 unchanged input entries: 77 files and 51 directories**. All eight retained source copies match the exact executed Git blobs. The read-only loader rehashed the staged inputs and exact native executables/libraries/helper, parsed their Mach-O identities, and bound the native journal bytes to helper receipts. The pure analyzer then reproduced each CI `analysis.json` field-for-field, independently twice, without new native input, system queries, or artifact writes. ARM analysis SHA-256 is `73c21421928131881cf9662e42715d3f052e208387b2b12998132a8f43437929`; Intel is `ddc3df162c86e5739213b8ba3761268a411dc943bde963b70f92147159338c8d`.

### Decision and remaining boundary

The installed library contains the intended table and completed its lifecycle, but the natural startup path produced no positive C-entry witness. **Close this proposed tracing route as uncalibrated.** Do not interpret the result as no activation request, as proof that either public API was unused, or as proof that AMFI blocked the hook. D18 does not identify the D17 requester or an OS defect.

No held-drag extension, synthetic direct-C calibration, selector expansion, or parameter sweep follows from this result. The [platform investigation packet](NATIVE_DRAG_UPSTREAM_INVESTIGATION.md) and its [44-source integrity index](evidence/D17-D18-investigation-manifest.json) collect the actual earlier positive evidence, this coverage result, the exact recorded reproduction, and the question a verified upstream tracing mechanism must answer. No external submission has been made.

## Disposition

PR #45 remains draft/unmerged and C12 remains HOLD. Task 07's original Finder enter/exit/reenter → Escape → release → distinct fresh-drop gate across three themes and two architectures is unchanged. Task 08's source and screenshot review remains complete, with final acceptance waiting on 07. The owner's physical check and v4 automatic results are complete and are not requested again.

No focus repair, directed Escape, security/preference change, protected-process attachment, timing sweep, or repeated gesture is part of D18. The completed results above are bound to the exact executed commit and artifact identities.
