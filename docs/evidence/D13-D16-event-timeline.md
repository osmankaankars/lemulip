# Retained drag event timeline: D13 R3 through D16 R1

Read-only extraction from 29 comparable cases (7 PASS, 22 FAIL); three incomplete D14 Intel cases remain excluded. Existing audited native verdicts are retained. All referenced case reports and raw traces match their comparison hashes.

## D16 timeline

All times below are milliseconds relative to gesture API start. `Terminal` is the earliest retained actual cursor observation, not post return. Source begin means the source-will-begin callback clock. A dash denotes no canceled-held activation.

| Arch | Case | Native | Source begin | Receiver entry | Last movement post return | Terminal | First target 6 | Target 13/1 | Escape down start | Escape up complete |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| arm64 | quartz-sync-first | FAIL | 487.470 | 691.635 | 1044.248 | 1048.463 | 995.616 | 1837.520 | 3252.204 | 3564.346 |
| arm64 | quartz-deferred-first | PASS | 479.055 | 752.003 | 999.145 | 999.763 | 1010.745 | — | 3203.697 | 3425.789 |
| arm64 | quartz-deferred-second | FAIL | 336.271 | 631.734 | 956.931 | 960.929 | 1227.120 | 1657.497 | 3171.024 | 3397.165 |
| arm64 | quartz-sync-second | FAIL | 484.689 | 702.104 | 975.433 | 1051.662 | 1060.249 | 1753.678 | 3277.030 | 3499.955 |
| x86_64 | quartz-sync-first | PASS | 420.535 | 726.117 | 1022.971 | 1024.663 | 1027.475 | — | 3224.389 | 3452.381 |
| x86_64 | quartz-deferred-first | PASS | 559.449 | 675.047 | 975.937 | 978.616 | 960.812 | — | 3182.195 | 3429.059 |
| x86_64 | quartz-deferred-second | FAIL | 363.050 | 678.443 | 922.164 | 923.187 | 1179.864 | 1603.014 | 3126.349 | 3455.615 |
| x86_64 | quartz-sync-second | FAIL | 414.754 | 697.971 | 983.729 | 984.501 | 1241.900 | 1661.907 | 3186.917 | 3408.319 |

## All 29 cases: competing timing anchors

Intervals are milliseconds. The source-created→will-begin column uses explicit callback clocks. Actual post envelopes, source movement callbacks, receiver transitions and target dispatch/state rows are in the JSON.

| Diagnostic | Arch | Case | Native | Entry→13 | First 6→13 | Terminal witness→13 | Terminal witness→Escape | Created→will-begin |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| D13-R3 | arm64 | quartz-first | PASS | — | — | — | 2214.848 | 1.076 |
| D13-R3 | arm64 | xctest-first | PASS | — | — | — | 2200.808 | 0.455 |
| D13-R3 | arm64 | xctest-second | FAIL | 982.717 | 412.780 | 671.225 | 2215.825 | 1.002 |
| D13-R3 | arm64 | quartz-second | FAIL | 1012.592 | 429.980 | 687.006 | 2218.167 | 0.918 |
| D13-R3 | x86_64 | quartz-first | FAIL | 1015.398 | 429.339 | 687.195 | 2194.981 | 0.501 |
| D13-R3 | x86_64 | xctest-first | FAIL | 972.440 | 402.758 | 669.193 | 2259.594 | 0.836 |
| D13-R3 | x86_64 | xctest-second | FAIL | 997.232 | 418.706 | 690.924 | 2221.701 | 0.782 |
| D13-R3 | x86_64 | quartz-second | FAIL | 910.686 | 428.400 | 691.510 | 2202.763 | 0.613 |
| D14-R2 | arm64 | quartz-first | FAIL | 1035.890 | 438.218 | 732.054 | 2243.913 | 0.498 |
| D14-R2 | arm64 | xctest-first | FAIL | 1642.080 | 1243.187 | 1243.135 | 2217.672 | 0.402 |
| D14-R2 | arm64 | xctest-second | FAIL | 761.310 | 417.389 | 452.594 | 2197.900 | 0.336 |
| D14-R2 | arm64 | quartz-second | FAIL | 987.447 | 421.897 | 679.130 | 2199.636 | 0.699 |
| D14-R2 | x86_64 | quartz-first | PASS | — | — | — | 2245.515 | 2.105 |
| D15-R1 | arm64 | quartz-first | FAIL | 1073.544 | 809.232 | 702.662 | 2203.738 | 0.994 |
| D15-R1 | arm64 | xctest-first | FAIL | 982.832 | 427.193 | 687.327 | 2250.278 | 0.382 |
| D15-R1 | arm64 | xctest-second | FAIL | 993.892 | 427.292 | 681.544 | 2256.583 | 0.351 |
| D15-R1 | arm64 | quartz-second | FAIL | 1698.374 | 1352.687 | 694.853 | 2291.931 | 0.803 |
| D15-R1 | x86_64 | quartz-first | PASS | — | — | — | 2202.783 | 0.775 |
| D15-R1 | x86_64 | xctest-first | FAIL | 1000.133 | 415.703 | 699.524 | 2246.318 | 0.691 |
| D15-R1 | x86_64 | xctest-second | FAIL | 1007.013 | 415.534 | 702.081 | 2288.441 | 0.723 |
| D15-R1 | x86_64 | quartz-second | FAIL | 967.492 | 428.738 | 688.369 | 2185.551 | 0.508 |
| D16-R1 | arm64 | quartz-sync-first | FAIL | 1145.885 | 841.904 | 789.057 | 2203.741 | 0.981 |
| D16-R1 | arm64 | quartz-deferred-first | PASS | — | — | — | 2203.934 | 0.766 |
| D16-R1 | arm64 | quartz-deferred-second | FAIL | 1025.764 | 430.377 | 696.568 | 2210.094 | 0.444 |
| D16-R1 | arm64 | quartz-sync-second | FAIL | 1051.574 | 693.429 | 702.015 | 2225.367 | 0.386 |
| D16-R1 | x86_64 | quartz-sync-first | PASS | — | — | — | 2199.726 | 0.592 |
| D16-R1 | x86_64 | quartz-deferred-first | PASS | — | — | — | 2203.580 | 0.611 |
| D16-R1 | x86_64 | quartz-deferred-second | FAIL | 924.571 | 423.150 | 679.827 | 2203.163 | 0.551 |
| D16-R1 | x86_64 | quartz-sync-second | FAIL | 963.936 | 420.007 | 677.406 | 2202.416 | 0.367 |

## Findings and counterexamples

All 29 cases contain a first target type-6 dispatch. Seventeen of 22 FAIL cases activate 402.758–438.218 ms later, but five FAIL outliers take 693.429, 809.232, 841.904, 1,243.187 and 1,352.687 ms. First type 6 therefore does not establish an activation deadline or its cause.

Entry→activation ranges 761.310–1,698.374 ms. Terminal-cursor observations give another useful description but not an invariant: D14 ARM XCTest-first activates 1,243.135 ms after the earliest terminal witness; D14 ARM XCTest-second takes 452.594 ms; D16 ARM sync-first takes 789.057 ms. All seven PASS cases observe the terminal cursor about 2.20 seconds before Escape without canceled-held activation. Elapsed dwell alone does not determine the outcome.

There is no nonterminal source-moved callback after the last terminal movement post completes in the 19 comparable Quartz cases. One first target type 6 is nonterminal after that post: D15 ARM quartz-second, matching movement step 16/24 at +50.313 ms. Its observed global cursor is still that same intermediate point, so this is no proof of a stale point delivered after actual terminal arrival. The first actual terminal witness is 708.146 ms after the terminal post. Receiver old-coordinate records occur in both outcomes.

First target type 6 before the first draggingUpdated record is neither sufficient nor necessary: D16 ARM sync-first FAIL precedes it by 1.507 ms; D13 ARM XCTest-first PASS follows it by 193.782 ms. This ordering cannot replace evidence of event acquisition or an activation request.

All 29 source-session-created clocks precede source-will-begin by 0.335–2.105 ms and source-ended by 3.206–6.631 seconds. The source creation call returned before the later tracking callbacks; wrapping that call does not capture a synchronous drag-tracking interval.

All seven PASS cases retain source-active/target-inactive state at Escape; all 22 FAIL cases retain the reverse. Target keyDown/keyUp receipts accompany the failures, while PASS receipts are source-side keyUp only. Missing PASS keyDown receipts do not establish nondelivery. The acquisition and handling of the owned Escape by the source's actual drag-tracking path remains unbound.

The retained event payloads supply no unique upstream event identity: event numbers/flags do not separate outcomes, target CG getter fingerprints are not upstream sender proof, first source mouseDragged payload/deltas are absent, and underlying XCTest posts are absent. No held activation timestamp reuses the initial source drag timestamp. Recreated events with new timestamps cannot be traced to an origin from these fields.

The separately verified private v4 summaries contain no foreground or uptime/delivery trace evidence, and the completed physical owner PASS was uninstrumented. Neither supplies an active-target counterexample or a reason to repeat owner testing.

No new native probe or input parameter change follows from this extraction. The bounded missing evidence is the activation request/timer owner and the actual source tracking event-acquisition/handling path, including reliable hook coverage. More timing correlation or another target dispatch stack would not establish that boundary.

## Competing hypotheses

| Hypothesis | Support | Counterexample or missing boundary |
| --- | --- | --- |
| Receiver entry starts a fixed activation deadline | Entry precedes all 22 held activations. | Entry-to-activation varies 761–1698 ms; all seven PASS cases enter without activating. No timer start/expiry receipt exists. |
| First target type 6 directly determines activation | Seventeen FAIL cases activate 403–438 ms later. | Five large timing outliers and all seven PASS cases also receive type 6. No owned activation request is bound to that event. |
| Terminal dwell alone causes activation | Most FAIL activation clocks cluster after terminal-source observations. | Earliest actual cursor witnesses give 453–1243 ms examples; all PASS cases remain at the terminal cursor for 2200–2246 ms before Escape. |
| A scheduled older drag point is replayed after terminal arrival | Old receiver coordinates can remain after post completion; one target type 6 matches an earlier Quartz point. | In that target case the observed cursor is also intermediate. No nonterminal source-moved callback follows terminal post completion in the 19 Quartz cases. Post completion does not prove arrival. |
| Event number, flags or a stale activation timestamp separates outcomes | Retained payloads expose some source/target numeric fields. | Source mouse-down event number is zero and delivered modifier flags zero across outcomes. First source drag payload/deltas are absent; held activation NSEvent timestamps follow the current source drag timestamp. |
| The source creation API synchronously holds the whole drag loop | beginDraggingSession creates the active session. | Every created receipt precedes will-begin and ended. The later source tracking acquisition path remains unobserved. |
| Foreground ownership determines the observed Escape route | All 29 cases separate by source/target active state; FAIL target sendEvent receives both key edges. | The activation initiator and source tracker retrieval/consumption are unknown. Missing source keyDown receipts do not prove nondelivery, and private local PASS summaries retain no foreground evidence. |

## Definitions and limits

- Primary timeline values are ProcessInfo.systemUptime seconds. Callback-entry clocks are used where explicitly retained; receiver and mouse-down rows otherwise provide record clocks, not callback entry/return.
- NSEvent.timestamp values remain a separate seconds-valued payload series. CGEvent timestamp integers are never converted or used for millisecond alignment.
- Coordinate checks assert equal zero-origin AppKit/Quartz display bounds. Screen-to-Quartz uses y=displayHeight-screenY; target-window points use x=frameX+localX and y=frameY+frameHeight-localY. Point matching permits less than 0.001 point of float precision error.
- Terminal cursor witness is the earliest retained matching observedCursor sample from the source, target, or observer entry sample. It proves observation by that record, not the exact physical arrival time or a timer start.
- Quartz post start/return bounds describe API execution, not completed OS input delivery. An intermediate cursor observed after the last post is not evidence an old point arrived after actual terminal cursor arrival.
- Source-moved callbackPointScreen and receiver draggingLocationInWindow describe framework callback data. Old receiver coordinates can persist after the global cursor moved; they do not bind a new injected event.
- Source-session-created is logged after beginDraggingSession returns in retained source code. Its callback clock precedes will-begin and ended callbacks in all comparable cases.
- Expected nominal schedule, source IDs, event numbers and flags are retained where available. First source mouseDragged payload and deltaX/deltaY are not retained; the XCTest underlying posted event stream is not retained.
- Private local v4 summaries were separately hash-verified and schema-inspected: neither retains foreground/key-window/activation state or uptime/delivery traces. No private paths, names or raw content are included here; physical owner PASS is an uninstrumented user report.
- Missing sendEvent or event-acquisition receipts do not establish nondelivery. These observations identify no activation initiator, timer owner/start/expiry, or complete source tracking retrieval path.

## Excluded cases

- D14-R2 / x86_64 / xctest-first: not-comparable, mouse-cleanup-incomplete.
- D14-R2 / x86_64 / xctest-second: not-run, mouse-cleanup-incomplete.
- D14-R2 / x86_64 / quartz-second: not-run, mouse-cleanup-incomplete.
