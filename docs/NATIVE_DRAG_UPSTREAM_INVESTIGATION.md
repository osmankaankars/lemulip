# Held-drag activation: platform investigation packet

## Issue card

**Status, 9 November 2026 Europe/Istanbul:** automated drag cancellation remains unresolved. PR #45 is open, draft and unmerged; C12 and task 07 remain HOLD. D20 received no recording-start notification and D21 produced no bounded recorder stack report. D22 has now produced real controlled-child reports within the unchanged budget: 82 ARM and 97 Intel samples of the known waiting frame, with matching UUID/address witnesses. Its strict parser rejected unequal privacy-masked paths before the post-sample identity query, so the original full calibration remains incomplete. Recorder startup and D21 sampler noncompletion remain unexplained. D23 has completed that separate offline identity/frame review on both unchanged archives: 39 portable tests passed and independent reconstruction matched every output value. The original exact-path and post-sample omissions remain explicit.

[D24 R2](NATIVE_RECORDER_PROGRESS_OBSERVATION.md) completed its bounded recorder/primary/secondary observation on both architectures. All four samplers retained only their initial 84-byte banners, with no report or qualified internal phase. ARM retained zero callbacks and no trace; Intel retained one late helper-native callback and a partial trace, with no normal recorder completion. [D25 R2](NATIVE_RETAINED_TRACE_EXPORT.md) subsequently made one bounded read-only TOC export of the exact retained Intel package. It exited 10 with `Document Missing Template Error`; no TOC, clock mapping or event coverage was established. [D26](NATIVE_RETAINED_ATRC_CONTRACT.md) completed its contract review and one missing import-help request. The installed help defines generic import/selector behavior and conditional UTI defaults, but does not establish exact ATRC acceptance. D27 is proposed as one separately bounded derived-import hypothesis test, with fresh selection evidence and no automatic export or original-package repair; it has not run. No new held gesture, production repair, product-acceptance exception or external bug report is established.

**Expected behavior:** Escape cancels the first held drag, release leaves only Existing in the destination, and a distinct fresh drag accepts Single exactly once. **Observed failure:** after injected Escape and release, the destination accepts Single from the first session and the native source ends that session with COPY. The original product candidate passed its general/native XCTest suite but failed the separate held-Finder acceptance step. The [routing report](NATIVE_DRAG_ROUTING_EVIDENCE.md#symptom-and-impact) preserves that distinction.

**Strongest positive evidence:** five D17 failures retain a `launchservicesd SETFRONT` transition from the owned source to the owned target after receiver entry and before Escape. The daemon record precedes the target's activation dispatch by approximately 5–42 ms. **Missing evidence:** the earlier request/client context, or the actual source drag-tracking consumer's receipt and disposition of Escape. An OS/AppKit defect, a CI-host defect, and a Lemulip product regression have not been established.

| Identity | Exact value |
| --- | --- |
| Repository / PR | [osmankaankars/lemulip, PR #45](https://github.com/osmankaankars/lemulip/pull/45) |
| C12 candidate | `d821d7343675e2850705d141ef9b3b93a6aee945` |
| C12 tree | `425baa28f00ec24551dd70c0cc874a75fa3be0c1` |
| Main | `ade8b1673de0c2dff930430564c17f100f5e807b` |
| D17 executed code / tree | `a17259046aed8ef62c0bd5273e530847b9c78b3c` / `460878bd1e11b3c17c830b9c34d767add856fa5c` |
| D17 run / jobs | [42357652748](https://github.com/osmankaankars/lemulip/actions/runs/42357652748), attempt 1; ARM `128359171366`, Intel `128359171490` |
| D18 executed code / tree | `80f92e41ccfedb54a15b0a5ef9572a5a57a88c4d` / `e159ad30d8ad0ef0443a0ee04dc74b515f739ddb` |
| D18 run / jobs | [42419686902](https://github.com/osmankaankars/lemulip/actions/runs/42419686902), attempt 1; ARM `128545233709`, Intel `128545233926` |
| D19 executed code / tree | `daf90a14cbe0e5855e2e4a3e69dc8c170700635d` / `7b3cf73162aff5612fa7f5b97bf2729df6f68d55` |
| D19 run / jobs | [42565052135](https://github.com/osmankaankars/lemulip/actions/runs/42565052135); ARM `128989654018`, Intel `128989654392` |
| D20 R2 executed code / tree | `1462bf597c52727ede7ee20991c65016e8b3086a` / `071467586f6b95d1b5ad5ab57ac5c97349a3526f` |
| D20 R2 run / jobs | [42567849171](https://github.com/osmankaankars/lemulip/actions/runs/42567849171), attempt 1; ARM `128998197463`, Intel `128998197228` |
| D24 R2 executed code / tree | `73464e30f278203cbd129025f1db814b6c549b2b` / `0d0b8c476fb052cd7b3a5b7ac98d0c6977069bf5` |
| D24 R2 run | [42609635410](https://github.com/osmankaankars/lemulip/actions/runs/42609635410) |
| D25 R2 executed code / tree | `e537fb774768747c144ba7c57c1d8d4a097683e9` / `8b073dc3cafb004d4fe4dc8dd99e5fdd9ce42e04` |
| D25 R2 run / attempt | [42616711092](https://github.com/osmankaankars/lemulip/actions/runs/42616711092) / 1 |
| D26 executed code / tree | `e8e0cbe351c82f3804a8f5bfa2c0b22ab54f69b4` / `9b9ffd59df1bb7848e24ecbe82d252c0b47a1d72` |
| D26 run / attempt | [42629940773](https://github.com/osmankaankars/lemulip/actions/runs/42629940773) / 1 |

The [integrity manifest](evidence/D17-D18-investigation-manifest.json) gives immutable Git URLs and SHA-256 values for **all 36 D17 and eight D18 retained source copies**, as well as both runs' archive identities and verification limits. It includes the original source/control, complete build/staging workflow, observers/input producers, classifiers, tests, and candidate staging sources. An investigator does not need the original chat to identify the executed code.

The separate [D19 capability projection](evidence/D19-trace-capabilities.json) indexes all 54 archive files and four exact retained source copies per architecture. It preserves both complete capability objects and selected exact help/list/host output, with every omitted file body declared.

The [D20 evidence projection](evidence/D20-system-trace-startup.json) binds the subsequent recording prerequisite and its failure before source/control startup. The [D20 protocol and results](NATIVE_SYSTEM_TRACE_STARTUP.md) retain the earlier header-import build failure separately from R2's observed notification timeout.

## Recorded reproduction

The failure was minimized to an owned native AppKit source and a receiver with an actual plain `NSWindow`. The source offers one exact file URL using `beginDraggingSession`, copy only, and normal cancellation animation. The destination uses normal dragging callbacks. Neither contains a custom Escape repair. The C12 product is built for staging, but D17 does not send the test input to its production view. This minimization narrows the failure surface; it does not establish that every source/environment has an identical internal cause.

Use the immutable [D17 workflow](https://github.com/osmankaankars/lemulip/blob/a17259046aed8ef62c0bd5273e530847b9c78b3c/.github/workflows/native-drag-activation-request-log.yml) as the complete recorded build/staging recipe. It pins C12, builds the original AppKit source/control and observers, prepares the public XCTest mouse runner, records provenance, and invokes the strict comparator. The [source manifest](evidence/D17-D18-investigation-manifest.json) resolves every retained dependency to its tested revision; the two application source snippets alone are not a complete reproduction environment.

The fixed four-case order is **Quartz, XCTest, XCTest, Quartz**. The diagnostic schedule is an initial 0.3-second press, one entry at nominal 400 points/second, a five-second terminal hold, globally posted Escape two seconds after observed entry/terminal cursor, 0.15-second key dwell, release, and—only after a successful cancel—a distinct fresh drop. Fresh-drop hold is one second. No held AX reads or screenshots are taken. Failed cancellation does not proceed to fresh drop. Non-comparable evidence halts remaining input rather than being retried.

The recorded comparator invocation is:

```bash
python3 script/compare_native_drag_mouse_driver.py \
  --staged "$RUNNER_TEMP/lemulip-native-ui" \
  --output "$RUNNER_TEMP/drag-mouse-driver-comparison" \
  --experiment-commit "$GITHUB_SHA"
```

This command belongs after the exact workflow's preparation/provenance steps in a fresh isolated workspace. It is supplied as a recipe reference, not as an instruction to overwrite retained evidence or rerun without a new measurement question. The experiment is nondeterministic: the completed D17 run had both PASS and FAIL. A new run is not promised to reproduce every individual outcome.

| D17 case | ARM64 | Intel |
| --- | --- | --- |
| `quartz-first` | PASS | PASS |
| `xctest-first` | FAIL | FAIL |
| `xctest-second` | FAIL | FAIL |
| `quartz-second` | PASS | FAIL |

All eight cases were comparable, inputs were unchanged, and cleanup completed normally. These are diagnostic results. The original acceptance gate additionally requires exit and reentry and covers all three themes; a diagnostic single-entry PASS cannot satisfy it.

## Navigate the evidence

### D17: positive system transition

Start with the [completed D17 report](NATIVE_DRAG_ACTIVATION_REQUEST_LOG_DIAGNOSTIC.md#r1-completed-run-and-new-server-side-transition-evidence) and [39 retained transition records](evidence/D17-front-transitions.json). The five held failure rows are:

| Architecture / case | Raw record index | Source PID → target PID |
| --- | ---: | --- |
| ARM `xctest-first` | 132 | 7967 → 7959 |
| ARM `xctest-second` | 187 | 8617 → 8514 |
| Intel `xctest-first` | 131 | 10538 → 10522 |
| Intel `xctest-second` | 186 | 10949 → 10783 |
| Intel `quartz-second` | 241 | 11215 → 11199 |

In each downloaded D17 artifact, retain together:

- `drag-activation-request-log/`: complete raw query bytes, full parsed records, context, clock inputs, analysis and query receipt.
- `drag-activation-request-clock/`: before/after owned markers, execution receipts, clock configuration and clock executable.
- `drag-mouse-driver-comparison/`: immutable-input inventories, reports and strict native results.
- `lemulip-native-ui/NativeDragControlEvidence-Capture-ax-only-Lifecycle-appkit-MouseDriver-*/orchard/`: source, receiver, activation and observer evidence for each case.
- `lemulip-native-ui/provenance.json` and `DiagnosticSources/`: exact build and source bindings.

The complete log category, rather than an emitter allowlist, exposed the daemon transition. The old collector included `lsd` but excluded `launchservicesd`. Correcting that demonstrated selection gap produced new evidence; simply repeating the old query would not.

Clock comparisons use the empirical marker calibration and callback-entry uptime, retaining complete uncertainty intervals. `NSEvent.timestamp` is not substituted for a calibrated clock. `oldFrontPid` names the previous foreground application, not the requesting client. The zero activity identifiers, null `source`, repeated daemon thread/trace fields, and single logging frame do not supply a request chain. Source resignation callbacks also follow the daemon transition; they do not provide an earlier requesting stack.

### D18: a tested observation boundary that did not calibrate

The [completed D18 report](NATIVE_ACTIVATION_ENTRY_CALIBRATION.md#r2-completed-startup-calibration) and [projected evidence](evidence/D18-startup-calibration.json) establish four normal startup/termination lifecycles with **four valid zero-call probe receipts**. Both analyses are `coverage-unproven`. No held-drag input followed.

D18 artifacts contain `calibration-run.json`, `control.json`, `source.json`, both inventories, `analysis.json`, exact helper/library/app build material, and eight retained sources. `staged-evidence.zip` plus `staged-archive.json` retain the complete staged tree, native journals and original empty directories. Validate the outer archive and nested ZIP before extracting into a new directory. The exact analyzer can replay the extracted data without launching any native program; its CLI writes a new result exclusively, so use its pure `load_evidence` / `analyze_records` functions to compare against an already present `analysis.json`.

The library loaded and contains the expected two-entry table and imports. This does not establish dyld's runtime patching decision, AMFI policy, or traversal of those exports by natural activation. An extra synthetic direct-C call would test its own binding. D18 supplies no basis for extending this selected mechanism into the held gesture.

### D19: installed tool contracts established, recording still unqualified

The [completed D19 inventory](NATIVE_TRACE_CAPABILITIES.md#r2-completed-tool-inventory) ran on 9 November 2026, 05:03:00–05:03:38 UTC. All fifteen read-only commands and six subprocess checks passed on each architecture. Both results are `inventory-complete`; neither ran a trace, launched the native source/control apps, sent input, or changed settings.

Both Xcode 26.3 (`17C529`) installations list System Trace, Thread State Trace and System Call Trace, and document bounded recording with `--no-prompt` plus `--toc` / `--xpath` export. Their help does not advertise the recording-options CLI added in Xcode 27. The ARM host reports `VirtualMac2,1` / Apple M1 (Virtual), macOS 15.8.2 (`24H232`); Intel reports `Macmini6,2` / Core i7-8700B with virtualization, macOS 15.7.9 (`24G830`). Processor Trace is listed, but neither reported CPU meets Apple's documented M4-or-later Mac requirement. The [D19 report](NATIVE_TRACE_CAPABILITIES.md) links the primary contracts and exact retained output.

Enabled developer-tools status does not establish per-tool recording authorization. A listed instrument does not establish an exported schema, event-specific stack, or request relationship. D19 did not execute the separate input-free System Trace recording/export prerequisite. D20's subsequent attempt is recorded below. A successful qualification would still need a positive natural-path witness before supporting a held-drag extension or identifying the requester/consumer.

### D20: start notification absent; natural startup did not run

[D20 R2](NATIVE_SYSTEM_TRACE_STARTUP.md#r2-recording-start-notification-not-observed) ran on 9 November 2026, 05:31:57–05:35:12 UTC. The public SDK header correction built successfully on both architectures; all six bounded-command and ten orchestration tests passed per architecture. Each helper registered its unique notification successfully and published a prepared receipt before the single recorder command was invoked.

Both helpers observed zero callbacks in the fixed 15-second wait, cancelled their registrations successfully and returned `recording-notification-timeout`. Neither source nor control was launched: all launch-request flags are false, all app PIDs are null, and native journals are absent. Each recorder retained zero stdout/stderr bytes and produced no trace package. After the helper failed, the orchestrator sent only one direct SIGINT to the owned recorder; it exited -2, with complete cleanup and an empty final process-group snapshot. Both 124-entry immutable-input inventories remained unchanged. No export ran and activation calibration remains unproven.

This result does not establish a permission denial or explain why the recorder was silent. Recording access, actual exported fields and caller/consumer coverage remain unqualified. The missing initial tool-start observation is now the prerequisite: identify a supported way to distinguish recorder start progress and notification delivery before designing another attempt. Widening the timeout, blindly repeating the command or changing permissions is not supported by the retained evidence. No held gesture follows from this result.

### D21: exact recorder metadata; bounded sampler produced no report

[D21 R2](NATIVE_RECORDER_STARTUP_OBSERVATION.md#r2-process-metadata-retained-bounded-sample-did-not-complete) ran on 9 November 2026, 08:08:17–08:12:10 UTC, in [run 42583779680](https://github.com/osmankaankars/lemulip/actions/runs/42583779680), at `72e59791f59ae0b6e1de367639f43e161303a828`, tree `338e5dd9aabbe9c861c4dba49b2b7cdbb6fe4671`. All 31 portable tests, builds, source gates and 20 installed-manual checks passed per architecture. R1 had stopped before runtime because its parser did not recognise the installed sample manual's ARGUMENTS section; the narrow R2 correction changed only that recognition.

Each R2 observer validated one exact owned recorder PID/parent/group/effective-UID snapshot. The advisory arguments describe `xctrace`; the raw process states are ARM `U<s` and Intel `R<s`. These snapshots do not qualify the loaded image or a common waiting call. Each one-second/ten-millisecond sampler attempt produced only an 84-byte announcement, then reached the unchanged 3.5-second operation allowance inside its four-second total budget. Both exited -15 after TERM; no report or post-sample identity was retained.

The later sampler-group KILL EPERM errors concern cleanup, not target inspection. Positive final group snapshots, exited children and closed streams resolved cleanup while preserving the original failure. Both PID reservations were released before the conservative cutoff. The original helper's 15-second wait still received zero callbacks, no apps launched, recorder streams remained empty and no trace/export followed. Inputs and C12 remain unchanged. The [public evidence projection](evidence/D21-recorder-startup-observation.json) binds all four R1/R2 artifacts and actual receipt values, with enumerated omissions.

The proposed next discriminating prerequisite was one standalone sampler calibration per architecture on a small owned native child, with the same timing, arguments and total budget. It must produce a complete PID/path/binary-identity-bound report containing a known waiting frame with a positive sample count. Failure ends that attempt and leaves the method unqualified; success qualifies only that control path and still requires a new recorder-specific evidence proposal. This needs no new `xctrace record`, longer timeout, permission change or held gesture.

### D22: controlled reports produced; original identity gate incomplete

[D22 R1](NATIVE_SAMPLER_CALIBRATION.md#r1-reports-produced-strict-path-identity-remained-incomplete) ran on 9 November 2026, 08:50:34–08:51:39 UTC, in [run 42588874357](https://github.com/osmankaankars/lemulip/actions/runs/42588874357), at `10ececdd145ca4c857c5844a83cee0b0b3a5d8e2`, tree `6219e264ff2df60c16b1be5063643808569a09eb`. Both architectures passed 43 portable tests, native C compilation, source/build provenance and twenty installed-manual checks. There was one controlled-child sample each and no recorder or application launch.

Both samplers exited zero in approximately 1.47 seconds without interruption. The retained reports contain 82 ARM and 97 Intel samples of `lemulip_d22_wait_for_release`, above `poll` in the actual call graph. Each reported image UUID matches the executable, dSYM and native receipts; its range contains the frame PC and starts at the report's main load address. These are limited positive observations. Header and Binary Images paths use different privacy masks, so the executed exact-path gate failed before an after-identity snapshot. Full calibration remains incomplete; no missing observation is inferred.

Both native targets completed through stdin EOF with matching ready-byte, identity and lifecycle-clock evidence. Observer and target cleanup completed, all 51 input entries per architecture stayed unchanged, and no native retry followed. The [public D22 projection](evidence/D22-native-sampler-calibration.json) binds all 156 artifact files, 24 retained source copies, command receipts, reports and separately labelled offline analysis.

### D23: retained identity/frame witness verified offline

[D23](NATIVE_SAMPLER_IDENTITY_REVIEW.md) completed the separate offline contract at source `088180b54eb2095f9a634ad0c83f7911821a095f`, tree `c56a7151beb84f7644107720032707a7180d0e3d`. Both original ZIPs passed the fixed-manifest verifier; all 39 portable tests passed, and an independent reconstruction matched every derived output value. The actual call-graph PCs bind to unique expected-UUID images and the retained wait-function symbols, displacements and function extents. Native/build/source identities, command streams, normal EOF and lifecycle order agree. The original archive bytes remained unchanged.

The [derived review](evidence/D23-native-sampler-identity-review.json) and [verification receipt](evidence/D23-verification.json) explicitly preserve `originalD22Complete=false`, `exactReportPathMatched=false` and `postSamplePSAvailable=false`. Display paths remain verbatim advisory text. A narrowly tested publication-scanner correction recognizes only the exact anonymous path token in explicitly listed D23 files; real paths and all other privacy rules remain active.

D23 adds no recorder stack or new native observation. The next concrete question is which startup stage prevents the recording-start notification and whether bounded sampling stalls before capture or during report/symbol processing. D21's initial banner cannot distinguish those stages; the original recorder, activation and product-acceptance questions remain open.

### D24: nested observation remained unqualified; Intel retained a partial trace

[D24 R2](NATIVE_RECORDER_PROGRESS_OBSERVATION.md) passed all 81 tests on each macOS architecture and completed the specified bounded observation and cleanup. Each primary and secondary sampler retained one exact 84-byte initial banner, with no completion/report-written marker, report or primary-after snapshot. The primary-before metadata shows a sleeping owned process on both architectures; it does not identify an internal sampler phase, wait subsystem or authorization cause.

ARM received zero callbacks and produced no trace. Intel received one callback at helper-native +14.109752 seconds. In the separate parent clock domain, its first recorder output appeared at recorder-relative +11.31 seconds, after both samplers had ended by about +6.81 seconds. Intel's recorder exited -11 after stopping/escalation; normal recording completion is not established. Its partial package contains 115,835,304 expanded bytes. The read-only byte audit found one literal issue, `Data stream: Time Mapping`; the issue semantics and trace-time coverage remain unknown.

D24 proposed a bounded read-only installed `xctrace export --input … --toc` against an exact retained copy as the next finite evidence step. D24 did not change D23's historical identity/frame result, the original full acceptance sequence or task 08's dependency.

### D25: exact retained input refused by the reader

[D25 R2](NATIVE_RETAINED_TRACE_EXPORT.md) passed all 91 tests and made one export in [run 42616711092](https://github.com/osmankaankars/lemulip/actions/runs/42616711092), attempt 1. It exited 10 after 1.734828604 seconds, with empty stdout and exactly 47 stderr bytes: `Export failed: Document Missing Template Error` followed by a newline. Input, source and installed-tool identities remained unchanged. The [result projection](evidence/D25-retained-trace-export.json) and [verification record](evidence/D25-verification.json) retain this finite refusal; no TOC, usable clock mapping, event range or sampler-window coverage was obtained.

D25 proposed an offline contract review before any further native or derived-data work. The error text alone did not identify a missing document member or establish a repair route.

### D26: native import grammar and remaining acceptance question

[D26](NATIVE_RETAINED_ATRC_CONTRACT.md) identified import-specific help as the concrete missing artifact and collected it once. All 45 tests passed. The help request exited 0 after 1.290658711 seconds with 1,512 stdout bytes and empty stderr; all 13 source copies and identities were verified, and source/reader bytes stayed unchanged. The [result](evidence/D26-retained-atrc-contract.json) and [verification](evidence/D26-verification.json) preserve that help-only outcome.

The help documents conditional default templates by input UTI, warns that defaults can change across releases, and gives an explicit System Trace selection for a ktrace example. It does not name ATRC or identify this payload's accepted type, default template or validity. D26 stopped without import, export or recording.

The proposed D27 is one bounded derived-import compatibility test. General Apple Trace family evidence and actual 26.3 grammar justify a hypothesis; they do not prove exact payload acceptance in advance. Its protocol must preserve the original and an exact read-only input copy, bind the same reader, require fresh observed System Trace availability, and create a separate exclusive output under fixed transport/output/cleanup bounds. There is no automatic export, repair or recording retry. D27 has not run. C12/07/PR #45 HOLD and task 08's original dependency remain unchanged.

### Retention and verification scope

The manifest identifies D17 artifacts `13568960184` / `13568149451` and D18 artifacts `13592893180` / `13592938122`, with their advertised sizes and checked SHA-256 digests. The workflow artifact retention is 14 days; preserve required archives before expiration. Canonical reports, source revisions, public evidence projections and the integrity index remain in Git.

The [D19 evidence](evidence/D19-trace-capabilities.json) separately binds artifacts `13651171058` / `13650748741` to their verified ZIP digests. All 54 files per architecture match the archive bytes, and all four source copies per architecture match the executed Git revision. Its public projection includes no runner-home paths. Complete original command receipts and the manual's terminal-formatted bytes remain in the archives; their public identities and body omissions are explicit.

D17's source/control/observer executable bytes were not archived; their provenance links are not fresh binary rehashes. Its clock executable was retained. D18 archives the exact executables and loaded library bytes, and all 128 immutable input entries were rechecked. These verification scopes must remain distinct. Archived executables need not be run to validate either packet.

## Questions already investigated

| Question | Decisive retained result / implication |
| --- | --- |
| Is Finder-specific source code necessary? | [D10 retained result](NATIVE_DRAG_ACTIVATION_DIAGNOSTIC.md#evidence-and-hypothesis) reproduced first-session acceptance with an owned copy-only AppKit source. Its [recorded protocol](NATIVE_VERIFICATION.md#instrumented-drag-source-comparison) does not establish identical internal causes across sources. |
| Is observer target AXRaise necessary? | [D11](NATIVE_DRAG_ACTIVATION_DIAGNOSTIC.md) retained an Intel failure with zero such requests. Removing them did not establish a fix. |
| Are held AX reads necessary? | [D12](NATIVE_DRAG_HELD_AX_DIAGNOSTIC.md) retained failures with those reads omitted. |
| Does changing the mouse producer reliably fix cancellation? | [D17](NATIVE_DRAG_ACTIVATION_REQUEST_LOG_DIAGNOSTIC.md) retained failures with both producers; Quartz passed and failed on Intel. |
| Does the first target event stack identify the initiator? | [D15](NATIVE_DRAG_DISPATCH_STACK_DIAGNOSTIC.md) showed ordinary downstream AppKit dispatch in PASS and FAIL. |
| Is per-record receiver synchronization necessary? | [D16](NATIVE_DRAG_RECEIVER_SYNC_DIAGNOSTIC.md) retained a PASS and FAIL per architecture under lifecycle-only synchronization. |
| Does a public retrieval/responder hook certify the Escape consumer? | [Routing review](NATIVE_DRAG_ROUTING_EVIDENCE.md) found no supported coverage contract; the proposed `nextEvent` probe was not run. |
| Do the selected public C wrappers observe a natural startup request? | [D18](NATIVE_ACTIVATION_ENTRY_CALIBRATION.md) returned four complete zero-call receipts, so the prerequisite coverage gate remained closed. |
| Which tracing tools and CLI contracts are installed? | [D19](NATIVE_TRACE_CAPABILITIES.md) completed both inventories. System Trace and the relevant instruments are listed, but recording access, actual export schemas and causal coverage remain unobserved. |
| Did the bounded System Trace prerequisite observe natural startup? | [D20 R2](NATIVE_SYSTEM_TRACE_STARTUP.md#r2-recording-start-notification-not-observed) retained successful registration but zero callbacks, no app launches, empty recorder streams and no trace. The missing initial tool-start state remains unexplained; no export or activation calibration followed. |
| Did a bounded recorder sample identify its initial stack? | [D21 R2](NATIVE_RECORDER_STARTUP_OBSERVATION.md) retained exact-process metadata, but both sampler commands hit their fixed budget without a report. Recorder image/stack and the noncompletion cause remain unqualified. |
| Did the same bounded sampler produce a controlled report? | [D22 R1](NATIVE_SAMPLER_CALIBRATION.md) produced counted known-frame reports in about 1.47 seconds on both architectures. The strict path gate stopped before the after-identity snapshot, so full calibration stays incomplete; [D23's separate offline identity/frame review](NATIVE_SAMPLER_IDENTITY_REVIEW.md) now verifies the narrow witness on both unchanged archives, with all original omissions preserved. |
| Did sampling the sampler identify the recorder/sample startup phase? | [D24 R2](NATIVE_RECORDER_PROGRESS_OBSERVATION.md) retained four initial 84-byte banners, no reports and no qualified phase. Bounded execution/cleanup and 81 passing tests per architecture do not establish a stack or authorization cause. |
| Is the retained Intel partial trace exportable with known time coverage? | [D25 R2](NATIVE_RETAINED_TRACE_EXPORT.md) made one bounded read-only export; exit 10 and `Document Missing Template Error`, with unchanged input/source/tool identities. No TOC or time coverage was established. D26's subsequent help-only result leaves that refusal unchanged. |
| Does the raw payload have a qualified derived-import route? | [D26](NATIVE_RETAINED_ATRC_CONTRACT.md) collected the actual 26.3 import grammar and conditional UTI defaults; exact ATRC acceptance remains unestablished. One separately bounded D27 compatibility hypothesis test is proposed, with fresh System Trace availability, exact read-only input and exclusive output; no automatic export or original repair. It has not run. |

## Automatic window behavior: a documented question, not a traced cause

Apple's [historical AppKit release notes](https://developer.apple.com/library/archive/releasenotes/AppKit/RN-AppKitOlderNotes/), under **OS X 10.10.3 → Spring Loaded Drag & Drop**, describe automatic window spring-forward during a hover, separately from optional spring-loaded controls. The owned views' lack of enabling `NSSpringLoadingDestination` callbacks therefore does not exclude automatic framework/window behavior. Those notes warn that later releases may supersede earlier behavior; they do not identify the current macOS requester, activation API, IPC transaction, or cancellation consumer. Nor does window ordering alone prove the global foreground request recorded in D17.

The platform question is now more specific: on the recorded macOS builds, which component makes that window decision while an `NSDraggingSession` is still open, and which supported observation connects its request, target and drag/client context to the subsequent `SETFRONT`? Across that transition, what positively identifies the same Escape's disposition in the source's native cancellation consumer? Historical behavior and temporal association do not answer those request/consumer questions.

## Concrete question for a platform investigator

Identify a supported observation mechanism that reaches at least one of the following boundaries in a comparable failing session:

1. **Earlier activation request/client context:** the submitting process, requested target, and synchronous caller or documented initiating transition before the daemon foreground change. Retain a real request/IPC relationship when available; time proximity alone is not a unique transaction match.
2. **Actual source drag-tracking consumer:** positive evidence binding the posted Escape key-down to cancellation handling for that session, with the handler's disposition. Ordinary key dispatch, a generic responder action, or event retrieval is not automatically this consumer.

Before further native input, specify the exact boundary, positive natural-path witness or documented coverage contract, process/target identity binding, clock relationship, access requirements, measurement cost, missing-data interpretation and stopping condition. A verified earlier observation can support a bounded new experiment. The present evidence does not support another downstream callback stack, a guessed selector/symbol, a timing adjustment, a focus repair or directed Escape.

This packet does not assert that standard runners are impossible to debug. It asks for an observation with a demonstrable relationship to the failing path. No external communication has been sent.

## Acceptance and remaining work

Task 07 still requires the original **Finder enter → exit → reenter → Escape → release → distinct fresh drop**, for Orchard, Pistachio and Lemonade on ARM64 and Intel, against the final candidate. A supported repair or an explicit resolution of that remaining CI gate is required before final acceptance. Task 08's C12 source and twelve-screenshot review is complete; its final acceptance waits on 07 and any resulting production change review. The owner's physical check and v4 automatic results are completed evidence and are not requested again. PR #45 remains draft/unmerged; no release is authorized by these diagnostics.
