#!/usr/bin/env python3
"""Extract hash-bound D13-R3 through D16-R1 event timelines without replay.

Only retained files are read. No native tool, classifier, log query or repository
code is imported. ProcessInfo uptime and NSEvent timestamps stay separate;
CG timestamp integers are preserved as payload data and never converted.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path

PINS = {
    "D13-R3": ("d69f6b344a0dc069027f04061686a308dae79ba4", "42298849358"),
    "D14-R2": ("97bbb565019eac697c3445fd184aa627d04b5a5b", "42305819111"),
    "D15-R1": ("8d467f0bb64012d1df879083349c7f48aebe1aa1", "42308788964"),
    "D16-R1": ("bcb1f00deba2673d3da5b877eab3407f66a4ce22", "42315347973"),
}
def sha(data):
    return hashlib.sha256(data).hexdigest()


def read(path, expected=None, trace=False):
    data = path.read_bytes()
    if expected is not None:
        assert sha(data) == expected, (path, "SHA mismatch")
    rows = [json.loads(line) for line in data.splitlines()] if trace else json.loads(data)
    if trace:
        assert [row["recordIndex"] for row in rows] == list(range(len(rows)))
    return rows


def clock(row):
    return row.get("callbackSystemUptime", row["systemUptime"])


def close(left, right):
    return math.hypot(left["x"] - right["x"], left["y"] - right["y"]) < .001


def ms(after, before):
    return None if after is None or before is None else 1000 * (after - before)


def first(rows):
    return rows[0] if rows else None


def extract(evidence, diagnostic, architecture, case):
    archive = evidence / (diagnostic + "-" + architecture)
    directory = archive / "lemulip-native-ui" / (
        "NativeDragControlEvidence-Capture-ax-only-Lifecycle-appkit-MouseDriver-" + case["mouseDriverCase"]) / "orchard"
    hashes = {"report.json": case["caseSHA256"], "source.jsonl": case["sourceSession"]["sourceSHA256"],
        "receiver.jsonl": case["receiver"]["receiverSHA256"], "activation.jsonl": case["activation"]["activationSHA256"]}
    raw = read(directory / "report.json", hashes["report.json"])
    source, receiver, activation = [read(directory / (name + ".jsonl"), hashes[name + ".jsonl"], True)
                                    for name in ("source", "receiver", "activation")]
    g = raw["mouseDriverGestures"][0]
    assert g["phase"] == "cancel"
    begin, release = g["startedSystemUptime"], g["releaseObservedSystemUptime"]
    entry = g["entryObservation"]["receiverEntrySystemUptime"]
    seq = g["entryObservation"]["sequenceNumber"]
    target, frame = g["targetPoint"], g["targetFrame"]
    ready = next(row for row in source if row["event"] == "source-ready")
    display = ready["appKitDisplayFrame"]
    assert display["x"] == display["y"] == 0 and ready["quartzDisplayBounds"]["x"] == ready["quartzDisplayBounds"]["y"] == 0
    assert all(display[key] == ready["quartzDisplayBounds"][key] for key in ("width", "height"))
    target_screen = {"x": target["x"], "y": display["height"] - target["y"]}
    target_local = {"x": target["x"] - frame["x"], "y": frame["height"] - (target["y"] - frame["y"])}
    moved = [row for row in source if row["event"] == "source-moved" and row.get("sequenceNumber") == seq]
    received = [row for row in receiver if row["event"] in ("draggingEntered", "draggingUpdated") and row.get("sequenceNumber") == seq]
    transitions = []
    for row in received:
        if not transitions or row["draggingLocationInWindow"] != transitions[-1]["draggingLocationInWindow"]:
            transitions.append(row)
    created = next(row for row in source if row["event"] == "source-session-created" and row.get("sequenceNumber") == seq)
    will_begin = next(row for row in source if row["event"] == "source-will-begin" and row.get("sequenceNumber") == seq)
    ended = next(row for row in source if row["event"] == "source-ended" and row.get("sequenceNumber") == seq)
    down = next(row for row in source if row["event"] == "source-mouse-down" and begin <= row["systemUptime"] <= clock(will_begin))
    requested = next(row for row in source if row["event"] == "source-session-requested" and row["sessionIndex"] == 1)
    mouse = [row for row in activation if row["event"] == "target-mouse-enter" and row.get("eventType") == 6
             and begin <= clock(row) < release]
    activated = [row for row in activation if row["event"] == "appkit-defined-enter" and row.get("eventType") == 13
                 and row.get("eventSubtype") == 1 and begin <= clock(row) < release]
    assert len(mouse) >= 1 and len(activated) <= 1
    type6, type13 = mouse[0], first(activated)
    escape = raw["escapePostTiming"]
    times = {
        "gestureStart": begin, "sourceMouseDownRecord": down["systemUptime"],
        "sourceSessionRequestedRecord": requested["systemUptime"], "sourceSessionCreatedCallback": clock(created),
        "sourceWillBeginCallback": clock(will_begin), "receiverFirstEntryRecord": entry,
        "receiverFirstUpdateRecord": next(row["systemUptime"] for row in received if row["event"] == "draggingUpdated"),
        "receiverLastDistinctPointRecord": transitions[-1]["systemUptime"],
        "observerEntryObservation": g["entryObservation"]["observedSystemUptime"],
        "firstTargetType6Callback": clock(type6), "heldType13Callback": clock(type13) if type13 else None,
        "escapeDownPostStarted": escape["downStartedSystemUptime"], "escapeDownPostCompleted": escape["downCompletedSystemUptime"],
        "escapeUpPostStarted": escape["upStartedSystemUptime"], "escapeUpPostCompleted": escape["upCompletedSystemUptime"],
        "releaseObserved": release, "sourceEndedCallback": clock(ended),
    }
    for label, rows, event in (("sourceResignedKey", source, "window-resigned-key"),
                              ("sourceResignedActive", source, "application-resigned-active"),
                              ("targetBecameKey", activation, "window-became-key"),
                              ("targetBecameActive", activation, "application-became-active")):
        found = first([row for row in rows if row["event"] == event and begin <= clock(row) < release])
        times[label] = clock(found) if found else None
    witnesses = []
    for origin, rows in (("source", source), ("target", activation)):
        for row in rows:
            if not begin <= row["systemUptime"] < release:
                continue
            if ("observedCursorCG" in row and close(row["observedCursorCG"], target)) or (
                    "observedCursorScreen" in row and close(row["observedCursorScreen"], target_screen)):
                witnesses.append({"systemUptime": row["systemUptime"], "origin": origin, "event": row["event"], "recordIndex": row["recordIndex"]})
    if close(g["entryObservation"]["cursorCG"], target):
        witnesses.append({"systemUptime": times["observerEntryObservation"], "origin": "observer", "event": "entryObservation"})
    witnesses.sort(key=lambda value: value["systemUptime"])
    times["firstRetainedTerminalCursorObservation"] = witnesses[0]["systemUptime"]
    source_terminal = next(row for row in source if row.get("sequenceNumber") == seq and "observedCursorCG" in row
                           and close(row["observedCursorCG"], target))
    times["firstSourceSessionTerminalCursorObservation"] = source_terminal["systemUptime"]
    posts = []
    stale = {"quartzPostStreamRetained": bool(raw["mouseEvents"])}
    if raw["mouseEvents"]:
        events = raw["mouseEvents"]
        events = events[:next(i for i, row in enumerate(events) if row["eventType"] == 2) + 1]
        assert [row["eventType"] for row in events] == [1] + [6] * 24 + [2]
        posts = [{"index": i, **row} for i, row in enumerate(events)]
        times.update(mouseDownPostBefore=events[0]["systemUptimeBeforePost"], mouseDownPostAfter=events[0]["systemUptimeAfterPost"],
            firstMovementPostBefore=events[1]["systemUptimeBeforePost"], lastMovementPostBefore=events[-2]["systemUptimeBeforePost"],
            lastMovementPostAfter=events[-2]["systemUptimeAfterPost"], mouseUpPostBefore=events[-1]["systemUptimeBeforePost"], mouseUpPostAfter=events[-1]["systemUptimeAfterPost"])
        cutoff = times["lastMovementPostAfter"]
        stale.update(nonterminalSourceMovedAfterTerminalPost=[row["recordIndex"] for row in moved
            if clock(row) > cutoff and not close(row["callbackPointScreen"], target_screen)],
            nonterminalReceiverRecordAfterTerminalPost=[row["recordIndex"] for row in received
                if row["systemUptime"] > cutoff and not close(row["draggingLocationInWindow"], target_local)],
            nonterminalTargetType6AfterTerminalPost=[row["recordIndex"] for row in mouse
                if clock(row) > cutoff and not close(row["locationInWindow"], target_local)])
    first6_cg = {"x": frame["x"] + type6["locationInWindow"]["x"], "y": frame["y"] + frame["height"] - type6["locationInWindow"]["y"]}
    first6_cursor_cg = {"x": type6["observedCursorScreen"]["x"], "y": display["height"] - type6["observedCursorScreen"]["y"]}
    matched = [row for row in posts if row["eventType"] == 6 and close(row["location"], first6_cg)]
    stale.update(firstTargetType6PointCG=first6_cg, observedCursorAtFirstTargetType6CG=first6_cursor_cg,
                 firstTargetType6PointMatchesObservedCursor=close(first6_cg, first6_cursor_cg),
                 firstTargetType6MatchedMovementSteps=[row["index"] for row in matched])
    if matched:
        assert len(matched) == 1
        stale["firstTargetType6AfterMatchedPostStartMilliseconds"] = ms(clock(type6), matched[0]["systemUptimeBeforePost"])
        stale["firstTargetType6AfterMatchedPostEndMilliseconds"] = ms(clock(type6), matched[0]["systemUptimeAfterPost"])
    def state_before(rows):
        row = [row for row in rows if "applicationActive" in row and clock(row) <= escape["downStartedSystemUptime"]][-1]
        return {key: row[key] for key in ("event", "recordIndex", "systemUptime", "applicationActive", "windowIsKey", "keyWindowNumber", "windowNumber")}
    intervals = {
        "entryToActivation": ms(times["heldType13Callback"], entry),
        "firstTarget6ToActivation": ms(times["heldType13Callback"], times["firstTargetType6Callback"]),
        "firstActualTerminalWitnessToActivation": ms(times["heldType13Callback"], times["firstRetainedTerminalCursorObservation"]),
        "firstSourceTerminalWitnessToActivation": ms(times["heldType13Callback"], times["firstSourceSessionTerminalCursorObservation"]),
        "terminalWitnessToEscape": ms(times["escapeDownPostStarted"], times["firstRetainedTerminalCursorObservation"]),
        "firstReceiverUpdateToFirstTarget6": ms(times["firstTargetType6Callback"], times["receiverFirstUpdateRecord"]),
        "createdToWillBegin": ms(clock(will_begin), clock(created)), "createdToSourceEnd": ms(clock(ended), clock(created)),
        "terminalPostEndToFirstTarget6": ms(times["firstTargetType6Callback"], times.get("lastMovementPostAfter")),
        "terminalPostEndToTerminalWitness": ms(times["firstRetainedTerminalCursorObservation"], times.get("lastMovementPostAfter")),
    }
    event_keys = ("recordIndex", "event", "eventType", "eventSubtype", "eventTimestamp", "callbackSystemUptime", "systemUptime", "eventWindowNumber",
        "eventMatchesOwnedWindow", "locationInWindow", "observedCursorScreen", "observedCursorCG", "applicationActive", "windowIsKey", "deliveredMouseEvent", "modifierFlags", "keyCode")
    selected_activation = [{key: row[key] for key in event_keys if key in row} for row in activation if begin <= clock(row) <= release]
    source_motion = [{key: row[key] for key in ("recordIndex", "callbackSystemUptime", "systemUptime", "callbackPointScreen", "observedCursorCG")} for row in moved]
    escape_receipts = {name: [{key: row[key] for key in event_keys if key in row} for row in rows
        if row["event"] == "escape-send-event" and begin <= row["systemUptime"] < release] for name, rows in (("source", source), ("target", receiver))}
    return {"diagnostic": diagnostic, "architecture": architecture, "case": case["mouseDriverCase"], "producer": case["mouseProducer"],
        "outcome": "PASS" if case["passed"] else "FAIL", "retainedComparability": case["comparability"],
        "rawDirectoryRelativeToEvidence": directory.relative_to(evidence).as_posix(), "rawFileSHA256": hashes,
        "timesSystemUptimeSeconds": times, "millisecondsRelativeToGestureStart": {k: ms(v, begin) for k, v in times.items()},
        "intervalsMilliseconds": intervals, "terminalCursorWitnesses": witnesses,
        "beforeEscape": {"source": state_before(source), "target": state_before(activation)},
        "escapeReceipts": escape_receipts, "targetDispatchAndStateEvents": selected_activation,
        "sourceMovementCallbacks": source_motion, "receiverLocationTransitions": [{"recordIndex": row["recordIndex"],
            "systemUptime": row["systemUptime"], "event": row["event"], "draggingLocationInWindow": row["draggingLocationInWindow"]} for row in transitions],
        "quartzEventPosts": posts, "stalePointChecks": stale,
        "NSEventTimestampsSeconds": {"sourceMouseDown": down["eventTimestamp"], "sessionOriginalMouseDown": requested["originalMouseDownTimestamp"],
            "sessionFirstMouseDragged": requested["firstMouseDraggedTimestamp"], "targetFirstType6": type6["eventTimestamp"],
            "targetHeldType13": type13["eventTimestamp"] if type13 else None},
        "sourceMouseDownPayload": down["deliveredMouseEvent"], "firstSourceMouseDraggedPayloadRetained": False,
        "sourceAndPostedDeltaXYRetained": any("deltaX" in row or "deltaY" in row for row in [down["deliveredMouseEvent"], *posts]),
        "heldActivationNSEventTimestampAfterCurrentSourceDragTimestamp": type13["eventTimestamp"] > requested["firstMouseDraggedTimestamp"] if type13 else None}


def analyze(evidence):
    cases, comparisons, excluded = [], [], []
    for diagnostic, (commit, run) in PINS.items():
        for architecture in ("arm64", "x86_64"):
            path = evidence / (diagnostic + "-" + architecture) / (
                "drag-receiver-sync-comparison" if diagnostic == "D16-R1" else "drag-mouse-driver-comparison") / "comparison.json"
            comparison = read(path)
            assert comparison["provenance"]["observerExperimentCommit"] == commit, diagnostic
            assert comparison["provenance"]["architecture"] == architecture
            comparisons.append({"path": path.relative_to(evidence).as_posix(), "sha256": sha(path.read_bytes()), "commit": commit, "runID": run})
            for case in comparison["cases"]:
                if case.get("comparability") != "comparable":
                    excluded.append({"diagnostic": diagnostic, "architecture": architecture, "case": case["mouseDriverCase"],
                                     "outcome": case["outcome"], "comparability": case["comparability"], "reasonCode": case.get("reasonCode")})
                else:
                    cases.append(extract(evidence, diagnostic, architecture, case))
    assert len(cases) == 29 and len(excluded) == 3
    failed = [case for case in cases if case["outcome"] == "FAIL"]
    passed = [case for case in cases if case["outcome"] == "PASS"]
    quartz = [case for case in cases if case["producer"] == "quartz"]
    def compact(case):
        return {key: case[key] for key in ("diagnostic", "architecture", "case", "outcome", "intervalsMilliseconds")}
    return {"schema": 1, "analysis": "retained-native-drag-event-timeline", "nativeExecuted": False, "classifierExecuted": False,
        "logQueryExecuted": False, "originalEvidenceModified": False, "comparisons": comparisons, "excluded": excluded,
        "cases": cases, "summary": {"comparable": len(cases), "passed": len(passed), "failed": len(failed),
            "first6To13Under500Milliseconds": sum(case["intervalsMilliseconds"]["firstTarget6ToActivation"] < 500 for case in failed),
            "first6To13Outliers": [compact(case) for case in failed if case["intervalsMilliseconds"]["firstTarget6ToActivation"] >= 500],
            "sourceCreatedBeforeWillBeginCount": sum(case["intervalsMilliseconds"]["createdToWillBegin"] > 0 for case in cases),
            "sourceCreatedBeforeSourceEndCount": sum(case["intervalsMilliseconds"]["createdToSourceEnd"] > 0 for case in cases),
            "foregroundOutcomeCounterexamples": [compact(case) for case in cases
                if case["beforeEscape"]["source"]["applicationActive"] != (case["outcome"] == "PASS")
                or case["beforeEscape"]["target"]["applicationActive"] == (case["outcome"] == "PASS")],
            "quartzNonterminalSourceMoveAfterTerminalPostCases": [compact(case) for case in quartz if case["stalePointChecks"]["nonterminalSourceMovedAfterTerminalPost"]],
            "quartzNonterminalTarget6AfterTerminalPostCases": [compact(case) for case in quartz if case["stalePointChecks"]["nonterminalTargetType6AfterTerminalPost"]]},
        "definitions": ["Primary timeline values are ProcessInfo.systemUptime seconds. Callback-entry clocks are used where explicitly retained; receiver and mouse-down rows otherwise provide record clocks, not callback entry/return.",
            "NSEvent.timestamp values remain a separate seconds-valued payload series. CGEvent timestamp integers are never converted or used for millisecond alignment.",
            "Coordinate checks assert equal zero-origin AppKit/Quartz display bounds. Screen-to-Quartz uses y=displayHeight-screenY; target-window points use x=frameX+localX and y=frameY+frameHeight-localY. Point matching permits less than 0.001 point of float precision error.",
            "Terminal cursor witness is the earliest retained matching observedCursor sample from the source, target, or observer entry sample. It proves observation by that record, not the exact physical arrival time or a timer start.",
            "Quartz post start/return bounds describe API execution, not completed OS input delivery. An intermediate cursor observed after the last post is not evidence an old point arrived after actual terminal cursor arrival.",
            "Source-moved callbackPointScreen and receiver draggingLocationInWindow describe framework callback data. Old receiver coordinates can persist after the global cursor moved; they do not bind a new injected event.",
            "Source-session-created is logged after beginDraggingSession returns in retained source code. Its callback clock precedes will-begin and ended callbacks in all comparable cases.",
            "Expected nominal schedule, source IDs, event numbers and flags are retained where available. First source mouseDragged payload and deltaX/deltaY are not retained; the XCTest underlying posted event stream is not retained.",
            "Private local v4 summaries were separately hash-verified and schema-inspected: neither retains foreground/key-window/activation state or uptime/delivery traces. No private paths, names or raw content are included here; physical owner PASS is an uninstrumented user report.",
            "Missing sendEvent or event-acquisition receipts do not establish nondelivery. These observations identify no activation initiator, timer owner/start/expiry, or complete source tracking retrieval path."]}


def markdown(report):
    lines = ["# Retained drag event timeline: D13 R3 through D16 R1", "", "Read-only extraction from 29 comparable cases (7 PASS, 22 FAIL); three incomplete D14 Intel cases remain excluded. Existing audited native verdicts are retained. All referenced case reports and raw traces match their comparison hashes.", "", "## D16 timeline", "", "All times below are milliseconds relative to gesture API start. `Terminal` is the earliest retained actual cursor observation, not post return. Source begin means the source-will-begin callback clock. A dash denotes no canceled-held activation.", "", "| Arch | Case | Native | Source begin | Receiver entry | Last movement post return | Terminal | First target 6 | Target 13/1 | Escape down start | Escape up complete |", "| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"]
    def show(value):
        return "—" if value is None else f"{value:.3f}"
    for case in report["cases"]:
        if case["diagnostic"] != "D16-R1":
            continue
        t = case["millisecondsRelativeToGestureStart"]
        vals = [t.get(key) for key in ("sourceWillBeginCallback", "receiverFirstEntryRecord", "lastMovementPostAfter", "firstRetainedTerminalCursorObservation", "firstTargetType6Callback", "heldType13Callback", "escapeDownPostStarted", "escapeUpPostCompleted")]
        lines.append(f"| {case['architecture']} | {case['case']} | {case['outcome']} | " + " | ".join(show(v) for v in vals) + " |")
    lines += ["", "## All 29 cases: competing timing anchors", "", "Intervals are milliseconds. The source-created→will-begin column uses explicit callback clocks. Actual post envelopes, source movement callbacks, receiver transitions and target dispatch/state rows are in the JSON.", "", "| Diagnostic | Arch | Case | Native | Entry→13 | First 6→13 | Terminal witness→13 | Terminal witness→Escape | Created→will-begin |", "| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |"]
    for case in report["cases"]:
        i = case["intervalsMilliseconds"]
        vals = [i[key] for key in ("entryToActivation", "firstTarget6ToActivation", "firstActualTerminalWitnessToActivation", "terminalWitnessToEscape", "createdToWillBegin")]
        lines.append(f"| {case['diagnostic']} | {case['architecture']} | {case['case']} | {case['outcome']} | " + " | ".join(show(v) for v in vals) + " |")
    lines += ["", "## Findings and counterexamples", "",
        "All 29 cases contain a first target type-6 dispatch. Seventeen of 22 FAIL cases activate 402.758–438.218 ms later, but five FAIL outliers take 693.429, 809.232, 841.904, 1,243.187 and 1,352.687 ms. First type 6 therefore does not establish an activation deadline or its cause.", "",
        "Entry→activation ranges 761.310–1,698.374 ms. Terminal-cursor observations give another useful description but not an invariant: D14 ARM XCTest-first activates 1,243.135 ms after the earliest terminal witness; D14 ARM XCTest-second takes 452.594 ms; D16 ARM sync-first takes 789.057 ms. All seven PASS cases observe the terminal cursor about 2.20 seconds before Escape without canceled-held activation. Elapsed dwell alone does not determine the outcome.", "",
        "There is no nonterminal source-moved callback after the last terminal movement post completes in the 19 comparable Quartz cases. One first target type 6 is nonterminal after that post: D15 ARM quartz-second, matching movement step 16/24 at +50.313 ms. Its observed global cursor is still that same intermediate point, so this is no proof of a stale point delivered after actual terminal arrival. The first actual terminal witness is 708.146 ms after the terminal post. Receiver old-coordinate records occur in both outcomes.", "",
        "First target type 6 before the first draggingUpdated record is neither sufficient nor necessary: D16 ARM sync-first FAIL precedes it by 1.507 ms; D13 ARM XCTest-first PASS follows it by 193.782 ms. This ordering cannot replace evidence of event acquisition or an activation request.", "",
        "All 29 source-session-created clocks precede source-will-begin by 0.335–2.105 ms and source-ended by 3.206–6.631 seconds. The source creation call returned before the later tracking callbacks; wrapping that call does not capture a synchronous drag-tracking interval.", "",
        "All seven PASS cases retain source-active/target-inactive state at Escape; all 22 FAIL cases retain the reverse. Target keyDown/keyUp receipts accompany the failures, while PASS receipts are source-side keyUp only. Missing PASS keyDown receipts do not establish nondelivery. The acquisition and handling of the owned Escape by the source's actual drag-tracking path remains unbound.", "",
        "The retained event payloads supply no unique upstream event identity: event numbers/flags do not separate outcomes, target CG getter fingerprints are not upstream sender proof, first source mouseDragged payload/deltas are absent, and underlying XCTest posts are absent. No held activation timestamp reuses the initial source drag timestamp. Recreated events with new timestamps cannot be traced to an origin from these fields.", "",
        "The separately verified private v4 summaries contain no foreground or uptime/delivery trace evidence, and the completed physical owner PASS was uninstrumented. Neither supplies an active-target counterexample or a reason to repeat owner testing.", "",
        "No new native probe or input parameter change follows from this extraction. The bounded missing evidence is the activation request/timer owner and the actual source tracking event-acquisition/handling path, including reliable hook coverage. More timing correlation or another target dispatch stack would not establish that boundary.", "", "## Competing hypotheses", "",
        "| Hypothesis | Support | Counterexample or missing boundary |",
        "| --- | --- | --- |",
        "| Receiver entry starts a fixed activation deadline | Entry precedes all 22 held activations. | Entry-to-activation varies 761–1698 ms; all seven PASS cases enter without activating. No timer start/expiry receipt exists. |",
        "| First target type 6 directly determines activation | Seventeen FAIL cases activate 403–438 ms later. | Five large timing outliers and all seven PASS cases also receive type 6. No owned activation request is bound to that event. |",
        "| Terminal dwell alone causes activation | Most FAIL activation clocks cluster after terminal-source observations. | Earliest actual cursor witnesses give 453–1243 ms examples; all PASS cases remain at the terminal cursor for 2200–2246 ms before Escape. |",
        "| A scheduled older drag point is replayed after terminal arrival | Old receiver coordinates can remain after post completion; one target type 6 matches an earlier Quartz point. | In that target case the observed cursor is also intermediate. No nonterminal source-moved callback follows terminal post completion in the 19 Quartz cases. Post completion does not prove arrival. |",
        "| Event number, flags or a stale activation timestamp separates outcomes | Retained payloads expose some source/target numeric fields. | Source mouse-down event number is zero and delivered modifier flags zero across outcomes. First source drag payload/deltas are absent; held activation NSEvent timestamps follow the current source drag timestamp. |",
        "| The source creation API synchronously holds the whole drag loop | beginDraggingSession creates the active session. | Every created receipt precedes will-begin and ended. The later source tracking acquisition path remains unobserved. |",
        "| Foreground ownership determines the observed Escape route | All 29 cases separate by source/target active state; FAIL target sendEvent receives both key edges. | The activation initiator and source tracker retrieval/consumption are unknown. Missing source keyDown receipts do not prove nondelivery, and private local PASS summaries retain no foreground evidence. |",
        "", "## Definitions and limits", ""]
    lines.extend("- " + definition for definition in report["definitions"])
    lines += ["", "## Excluded cases", ""]
    for case in report["excluded"]:
        lines.append(f"- {case['diagnostic']} / {case['architecture']} / {case['case']}: {case['comparability']}, {case['reasonCode']}.")
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--format", choices=("json", "markdown"), default="json")
    args = parser.parse_args()
    report = analyze(args.evidence)
    print(json.dumps(report, indent=2, sort_keys=True, allow_nan=False) if args.format == "json" else markdown(report), end="\n" if args.format == "json" else "")
