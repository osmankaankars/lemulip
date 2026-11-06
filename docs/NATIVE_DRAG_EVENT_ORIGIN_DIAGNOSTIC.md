# Native drag event-origin diagnostic (D14)

## Question and retained evidence

D14 asks what the existing event metadata and system logs can establish about the mouse event delivered to the inactive target before its later activation. It adds passive observations to the D13 protocol. It does not change the gesture or attempt an activation fix.

In [D13 R3](https://github.com/osmankaankars/lemulip/actions/runs/42298849358), the first target `leftMouseDragged` receipt (`type 6`) followed the last distinct receiver point by about **254–265 ms**. That first target event was at an intermediate path point in the two passing cases and at the endpoint in the six failing cases. In the ARM Quartz pass, mouse-post record `[20]` lasted **169.339 ms**, and the target event timestamp lay inside that posting interval. In the ARM Quartz failure, the corresponding target event timestamp was **266.196 ms after the final mouse post**.

These are associations between retained timing and location records. They do not establish that the event initiated activation, that a posting delay caused cancellation to succeed, or that a particular event field is defective. The source's recorded **0.25-second local-event suppression interval stays fixed**; proximity to that value is not causal proof.

## Pinned scope

| Input | Pin |
| --- | --- |
| D13 R3 native baseline | `d69f6b344a0dc069027f04061686a308dae79ba4` |
| D14 parent | `8e26736c8c0d5b5d61de0d02ef72f2b1578dac53` |
| D14 branch | `codex/drag-event-origin-07` |
| D14 R1 code | `a1f1bfa4fce5cd6e7e28ce55271861e3db05df90` |
| D14 R1 tree | `10051223884f3e01be0c79b9ac7523c8f64c5c1d` |
| D14 R2 code | `97bbb565019eac697c3445fd184aa627d04b5a5b` |
| D14 R2 tree | `e3c326ce8b0eda2e89aa8ce20864ff94e2a5bca5` |
| Unchanged C12 application | `d821d7343675e2850705d141ef9b3b93a6aee945` |
| Unchanged C12 tree | `425baa28f00ec24551dd70c0cc874a75fa3be0c1` |

Both architectures retain the D13 R3 case order: **Quartz / XCTest / XCTest / Quartz**, with the same source, receiver, fixtures, coordinates and input schedule. This remains the single-entry terminal-hold diagnostic: 0.3-second initial hold, nominal velocity 400 points/second, 5-second cancellation hold, independent global Quartz Escape 2 seconds after verified entry, 0.15-second Escape dwell, and a separate fresh drop with a 1-second hold. The existing release-acknowledgement and cleanup rules remain in force.

The [D13 protocol and audited results](NATIVE_DRAG_MOUSE_DRIVER_DIAGNOSTIC.md) define those conditions and their timing limits. The strict base classifier still requires postrelease `Existing`-only cancellation, same-sequence source/receiver receipts, a distinct successful fresh drop, unchanged originals and inventory, and normal cleanup. An incomplete case still stops the remaining cases. Supplementary origin evidence cannot turn a failed or incomplete native result into a pass.

## Passive event metadata

Under `LEMULIP_EVENT_ORIGIN_TRACE`, the existing `ControlApplication.sendEvent` observation records the event's public Core Graphics PID, source-state and timestamp fields alongside its existing dispatch receipts. The observer's `observerProcessID` is retained with the case provenance so a reported PID can be compared with the known observer, source, receiver and helper identities.

The receiver remains a literal `NSWindow`. The existing event dispatcher still calls `super` normally. D14 adds no activation override, stack capture, private API, new input event, focus correction, timing adjustment or held observer AX read. The observations describe delivered metadata; a PID or state field alone does not establish the reason for an activation request. Missing metadata stays unavailable.

Apple documents [`NSEvent.cgEvent`](https://developer.apple.com/documentation/appkit/nsevent/cgevent) as the corresponding Core Graphics event, which may be unavailable, and [`eventSourceUnixProcessID`](https://developer.apple.com/documentation/coregraphics/cgeventfield/eventsourceunixprocessid) as its source PID field. Zero or an unknown PID is not attribution to WindowServer. [`clickCount`](https://developer.apple.com/documentation/appkit/nsevent/clickcount) is meaningful only for mouse-down/up, so D14 records it as null for mouse-dragged events.

## Bounded system-log collection

After the native comparison, a read-only analyzer validates the retained event receipts. A separate collector then reads and filters bounded output from `/usr/bin/log show`. Collection uses `--style json`, `--timezone UTC`, explicit `--start` and `--end` bounds, and `--info --debug` to select existing records. An invocation is limited to **20 seconds and 10 MiB**.

The permitted scope is the owned process IDs and, only with an explicit owned-bundle or labeled owned-PID binding, records from `WindowServer`, `lsd`, `runningboardd` or `loginwindow`. A coincidental numeric substring is not ownership evidence. This scope does not authorize unrelated application logs.

Collection does not change logging configuration, start a live stream, enable private logging or use `sudo`. Apple's [WWDC22 Core Data and CloudKit session](https://developer.apple.com/videos/play/wwdc2022/10119/) illustrates bounded historical queries; it does not promise a particular activation-origin message or complete coverage on these runners.

Empty, redacted, unavailable, truncated or timed-out log output is inconclusive. A state-transition message establishes only the state it reports unless it explicitly identifies and binds an activation request. The collector reports availability and ownership bindings, without automatically assigning an activation cause. Interpretation of the retained records must distinguish unavailable coverage, a recorded state change, and supported origin evidence. These findings remain separate from native acceptance.

## Interpretation and next gate

An explicit, correctly bound request record could narrow the activation path. Matching event metadata could connect a delivered event to a known producer. Either finding would still require a causal test before selecting a repair. Shared fields, timing proximity and absence of log messages do not establish a cause or rule out an unobserved system path.

D11 already tested observer target AXRaise omission; D12 tested held observer AX-read omission; D13 produced both passing and failing results with both mouse producers. D14 preserves those limits and does not repeat those interventions.

The original complete C12 enter/exit/reentry acceptance gate remains required on the final candidate. Tasks 07 and 08 remain open. The owner's completed physical and v4 helper passes are preserved, and the approved film and music remain outside this diagnostic's scope.

## Results

### R1: test-fixture path error before native execution

[Run 42305546780](https://github.com/osmankaankars/lemulip/actions/runs/42305546780) stopped during the new analyzer's portable tests on both architectures. macOS exposed the temporary fixture through `/var/folders`, while its resolved path used `/private/var/folders`; the analyzer correctly rejected the noncanonical staging root. Application build, staging and native gestures were skipped. The supplementary reports recorded missing context, and no system-log query ran. This is not a native PASS or FAIL result.

R2 resolves the fixture parent before constructing its files. A focused symlink-parent regression reproduced `event-origin-staging-root` before the fix and passed afterward; all nine analyzer tests passed locally. Only the test file changed between R1 and R2. The analyzer guard, collector, native source and input protocol are unchanged. Together with the eight collector checks and the existing 82 checks, the local validation total is 99.

### R2: native event-identity comparison

[Run 42305819111](https://github.com/osmankaankars/lemulip/actions/runs/42305819111), attempt 1, completed on 6 November 2026 at 22:41:44 UTC with an overall failure. Both architectures passed all 99 portable checks and compiled C12, the observers, source, control and public XCTest runner. ARM completed all four comparisons and both supplementary readers. Intel stopped after the second case's cleanup error; its analyzer preserved that incomplete result, and its collector admitted only the first, fully analyzed case.

| Architecture | Quartz first | XCTest first | XCTest second | Quartz second |
| --- | --- | --- | --- | --- |
| arm64 | Comparable FAIL | Comparable FAIL | Comparable FAIL | Comparable FAIL |
| x86_64 | Comparable PASS | NOT COMPARABLE: cleanup incomplete | NOT RUN | NOT RUN |

The ARM failures each accepted sequence 1 and ended the source session with COPY. They did not run a fresh-drop leg. Each had normal cleanup, no held observer AX reads and unchanged input inventories. In Intel's first Quartz case, cancellation left only Existing, source sequence 1 ended with NONE and no receiver acceptance, and the distinct sequence 2 fresh drop added Single exactly once and ended with COPY. That case also had normal cleanup. It remains a single-entry diagnostic pass, not the original full acceptance gate.

#### Intel cleanup remains incomplete

The Intel first XCTest case observed FINISHED at uptime `675.912578741`; a process-identity check at `676.005582538` then recorded `processNotTerminated=false` and all four path-match checks false. The later helper exit status was 0 and the registry was empty, but the identity error remained. The existing retirement branch recorded no observation. Its predicate required the previously bound PID and both identity URLs to be nil; the failing receipt does not retain the actual current PID or URL-presence values, so those predicates cannot be reconstructed afterward. The case stays NOT COMPARABLE and the last two cases stay NOT RUN.

This identifies a further terminal-process observation boundary to address prospectively. It does not retroactively validate cleanup or establish that the existing nil-URL retirement branch was exercised.

#### Delivered event identity

All **five fully analyzed cases**, including Intel's strict pass, reported the target's PID, CG source-state `0`, event number `0`, pressure `1` and no modifiers for their first held target type-6 event. The corresponding CG and NSEvent timestamps matched. Each initial source mouse-down instead retained a different producer PID. The event-source metadata therefore does not distinguish cancellation success from failure. Because `NSEvent.cgEvent` may create a corresponding event, the target PID alone is not proof that the target produced the original upstream input.

All five first target events were at the terminal coordinate. Intel's passing case therefore also shows that the D13 R3 intermediate-versus-terminal location association is not a sufficient success/failure rule. In the two ARM XCTest failures, the receiver first recorded that endpoint after the target event, by about 544.501 and 450.646 ms, even though the event itself was already at the endpoint.

In ARM, the target event followed the last distinct receiver location by 253.324–255.797 ms. Intel's passing event followed it by 725.256 ms and preceded the receiver's first endpoint record by 25.149 ms. These are retained clock/location relationships, not a reason to change the fixed suppression interval or gesture schedule.

ARM's later activation callbacks still occur inside a separate type-13 application-activated dispatch, outside the first type-6 dispatch. The elapsed times from type-6 return to type-13 entry were 437.696 / 1242.913 / 417.062 / 421.400 ms. Intel's passing cancellation leg has no such later held activation dispatch.

#### Existing system logs

Both bounded queries completed without changing logging configuration. ARM retained 2,451 of 2,547 query records in 11.703 seconds; Intel retained 627 of 627 in 4.768 seconds. Their stdout sizes were 3,874,862 and 937,645 bytes, respectively; neither query produced stderr. The Intel query covers only its fully analyzed Quartz-first case.

For ARM, retained raw-record indices **343/344/347, 1046/1047/1048, 1681/1682/1683 and 2323/2324/2325** bind AppKit's window-order messages to the respective owned target PIDs **4459, 5328, 5789 and 6313**. They report an inactive target window being ordered forward. They do not retain a caller stack, hover/timer reason or requestor PID. Their activity identifier is zero, and the trace identifiers repeat by message format across separate targets; those fields do not link a unique activation request.

Explicit LaunchServices front requests and runningboardd launch assertions are present during application startup. They do not identify the later held activation request. No correctly bound upstream requester for that held activation was established. No WindowServer record was retained in the ARM selected set; the bounded predicate and available persisted logs do not establish complete coverage. Although the collector recognized no `<private>` or `<redacted>` token, 306 retained ARM messages contain the abbreviation marker `<…>`.

The artifact does not retain a verified Mach timebase. No exact millisecond ordering between system-log `machTimestamp` and the native uptime clocks is asserted by assuming an ARM frequency. Native trace intervals above use their own recorded clock domain.

#### Artifact verification and limits

| Architecture | Artifact ID | ZIP bytes | ZIP SHA-256 |
| --- | --- | ---: | --- |
| arm64 | 13546861566 | 496,090 | `6a6593ebeeb072400434ad9401586e708c674d048818c1628ea520822e766720` |
| x86_64 | 13547145073 | 294,066 | `114f7878ed674a10517586bfbf778c96d11c81a7e5f7431eb60e22ccf65a193a` |

Both ZIPs passed advertised size/SHA-256, CRC and safe-path checks. Their 82 / 60 extracted files, totaling 5,109,772 / 2,212,332 bytes, remained unchanged during audit. Exact published-code replay reproduced all available native case and aggregate fields, including Intel's incomplete result, and the full supplementary analysis JSON. ARM's 12 and Intel's seven snapshots matched their raw files. Each architecture's 242-entry inventories, 13 retained source copies, four configurations, five manifests and eight recorded binary hash links were verified.

The log receipt's context and command were independently rebuilt, and all 2,451 / 627 retained record bindings were revalidated. Compiled binary/fixture bytes and the full raw log streams were not archived; their bytes and omitted records cannot be independently reconstructed from these artifacts. Successful replay is evidence consistency, not native acceptance or proof of activation origin.

Task 07 and final task 08 acceptance remain open. The next concrete work is the Intel terminal-process observation race, followed by a discriminating observation of the held activation path. C12 and main remain unchanged; PR #45 remains draft/HOLD. The completed owner checks are not reopened.

<!-- D14_RESULT -->
