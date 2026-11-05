"""Compare Finder and an instrumented AppKit source; never grant permissions."""
import argparse
import json
import math
from pathlib import Path
import platform
import re
import stat
import sys

import compare_native_drag_capture as capture
import compare_native_drag_lifecycle as lifecycle

CASES = ("finder-first", "appkit-first", "appkit-second", "finder-second")
POLICY = "ax-only"
SOURCE_BUNDLE = "Native Drag Source.app"
SOURCE_ID = "app.lemulip.NativeDragSource"
SOURCE_EXECUTABLE = "NativeDragSource"
SOURCE_KEYS = ("nativeDragSourceSourceSHA256", "sourceGUI_SHA256")
CALLBACKS = {"source-will-begin", "source-moved", "source-ended"}
RECEIVER_CALLBACKS = {"draggingEntered", "draggingUpdated", "draggingExited", "draggingEnded",
                      "prepareForDragOperation", "performDragOperation", "concludeDragOperation"}
SOURCE_EVENTS = CALLBACKS | {"source-ready", "source-mouse-down", "source-mouse-up",
    "source-session-requested", "source-session-created", "escape-send-event",
    "application-became-active", "application-resigned-active", "application-terminating"}
ERROR_EVENTS = {"trace-limit", "source-failed", "watchdog-timeout", "application-timeout", "open-rejected"}


def source_kind(case_name):
    capture.require(case_name in CASES, "unknown-source-case")
    return "native-appkit" if case_name.startswith("appkit-") else "finder"


def evidence_for(stage, case_name):
    source_kind(case_name)
    return stage / ("NativeDragControlEvidence-Capture-ax-only-Lifecycle-appkit-Source-" + case_name)


def input_snapshot(stage):
    result = lifecycle.input_snapshot(stage)
    bundle = stage / SOURCE_BUNDLE
    capture.require(bundle.is_dir() and not bundle.is_symlink(), "missing-or-symlinked-source-bundle")
    paths = [bundle, *sorted(bundle.rglob("*"))]
    capture.require(len(paths) <= 16_384, "source-inventory-bound")
    for path in paths:
        info = path.lstat()
        capture.require(stat.S_ISDIR(info.st_mode) or stat.S_ISREG(info.st_mode), "source-input-file-type")
        entry = {"mode": stat.S_IMODE(info.st_mode), "type": "directory" if path.is_dir() else "file"}
        if entry["type"] == "file":
            entry["sha256"] = capture.sha256(path)
        result[path.relative_to(stage).as_posix()] = entry
    return result


def context_for(stage, experiment_commit):
    context = lifecycle.context_for(stage, experiment_commit)
    links = {"nativeDragSourceSourceSHA256": capture.ROOT / "script/native_ui/NativeDragSource.swift",
             "sourceGUI_SHA256": stage / SOURCE_BUNDLE / "Contents/MacOS" / SOURCE_EXECUTABLE}
    capture.require(all(context["provenance"].get(key) == capture.sha256(path) for key, path in links.items()),
                    "native-source-hash-link")
    context["inputs"] = input_snapshot(stage)
    return context


def finite(value, code):
    capture.require(type(value) in (int, float) and math.isfinite(value) and value >= 0, code)
    return value


def point(value, code):
    capture.require(isinstance(value, dict) and set(value) == {"x", "y"}, code)
    capture.require(all(type(v) in (int, float) and math.isfinite(v) for v in value.values()), code)
    return value


def rect_string(value, code):
    capture.require(isinstance(value, str), code)
    number = r"(-?(?:\d+(?:\.\d*)?|\.\d+))"
    match = re.fullmatch(r"\{\{" + number + r",\s*" + number + r"\},\s*\{" + number + r",\s*" + number + r"\}\}", value)
    capture.require(match is not None, code)
    result = dict(zip(("x", "y", "width", "height"), map(float, match.groups())))
    capture.require(all(math.isfinite(v) for v in result.values()) and result["width"] > 0 and result["height"] > 0, code)
    return result


def geometry_signature(case, kind):
    geometry, target = case.get("sourceGeometry"), case.get("targetGeometry")
    capture.require(isinstance(geometry, dict) and isinstance(target, dict) and target, "geometry-missing")
    capture.fields_match(geometry, {"coordinateSpace": "quartz-global-top-left"}, "source-coordinate-space")
    for key in ("finderWindow", "finderIcon"):
        rect_string(geometry.get(key), "source-geometry-" + key)
    point(geometry.get("sourcePoint"), "source-point")
    if kind == "native-appkit":
        for key in ("nativeWindow", "nativeIcon"):
            rect_string(geometry.get(key), "source-geometry-" + key)
    else:
        capture.require(geometry.get("nativeWindow") is None and geometry.get("nativeIcon") is None,
                        "finder-native-geometry")
    # Native-only rectangles are independently bound to source-ready. Shared
    # geometry is an exact four-case invariant, including the first cancel path.
    return {"targetGeometry": target, "sourceGeometry": {key: geometry[key]
        for key in ("coordinateSpace", "finderWindow", "finderIcon", "sourcePoint")}}


def read_trace(path, label, expected_pid=None):
    info = path.lstat()
    capture.require(stat.S_ISREG(info.st_mode) and 0 < info.st_size <= 16_777_216, label + "-trace-file")
    data = path.read_bytes()
    capture.require(len(data) == info.st_size and data.endswith(b"\n"), label + "-trace-truncated")
    lines = data.splitlines()
    capture.require(0 < len(lines) <= 16_384, label + "-trace-count")

    def object_pairs(pairs):
        result = {}
        for key, value in pairs:
            capture.require(key not in result, label + "-trace-duplicate-key")
            result[key] = value
        return result

    def bad_constant(_):
        raise capture.ComparisonError(label + "-trace-nonfinite")

    records, previous = [], -1
    for index, line in enumerate(lines):
        row = json.loads(line, object_pairs_hook=object_pairs, parse_constant=bad_constant)
        capture.fields_match(row, {"schema": 1, "recordIndex": index}, label + "-trace-index")
        pid = row.get("pid")
        capture.require(type(pid) is int and pid > 0, label + "-trace-pid")
        if expected_pid is None:
            expected_pid = pid
        capture.require(pid == expected_pid, label + "-trace-pid")
        clock = finite(row.get("systemUptime"), label + "-trace-clock")
        capture.require(clock >= previous, label + "-trace-clock-order")
        previous = clock
        capture.require(isinstance(row.get("event"), str) and 0 < len(row["event"]) <= 128,
                        label + "-trace-event")
        capture.require(row["event"] not in ERROR_EVENTS, label + "-trace-error")
        records.append(row)
    return records


def gesture_clock(case):
    timing = case.get("escapePostTiming")
    capture.require(isinstance(timing, dict), "escape-timing-missing")
    keys = ("downStartedSystemUptime", "downCompletedSystemUptime", "upStartedSystemUptime", "upCompletedSystemUptime")
    clocks = [finite(timing.get(key), "escape-timing-clock") for key in keys]
    capture.require(clocks == sorted(clocks), "escape-timing-order")
    finite(timing.get("heldSeconds"), "escape-held-seconds")
    events = case.get("mouseEvents")
    capture.require(isinstance(events, list) and 0 < len(events) <= 4096, "mouse-events-missing")
    previous = -1
    for event in events:
        capture.require(isinstance(event, dict), "mouse-event-type")
        capture.fields_match(event, {"postCalled": True, "eventTap": "cghidEventTap", "sourceStateID": 1},
                             "mouse-input-protocol")
        capture.require(type(event.get("eventType")) is int, "mouse-event-type")
        before = finite(event.get("systemUptimeBeforePost"), "mouse-post-clock")
        after = finite(event.get("systemUptimeAfterPost"), "mouse-post-clock")
        capture.require(previous <= before <= after, "mouse-post-order")
        previous = after
    downs = [e for e in events if e["eventType"] == 1 and e["systemUptimeAfterPost"] <= clocks[0]]
    capture.require(downs, "cancel-mousedown-missing")
    down = downs[-1]
    ups = [e for e in events if e["eventType"] == 2 and e["systemUptimeBeforePost"] >= clocks[3]]
    capture.require(ups, "cancel-release-missing")
    release = ups[0]
    capture.require(not any(e["eventType"] == 2 and down["systemUptimeAfterPost"] < e["systemUptimeBeforePost"] < clocks[0]
                            for e in events), "cancel-drag-released-before-key")
    capture.require(not any(e["eventType"] == 1 and clocks[0] < e["systemUptimeBeforePost"] < release["systemUptimeBeforePost"]
                            for e in events), "cancel-drag-restarted")
    return {**{key: timing[key] for key in (*keys, "heldSeconds")},
            "dragDownBeforePost": down["systemUptimeBeforePost"], "dragDownAfterPost": down["systemUptimeAfterPost"],
            "releaseBeforePost": release["systemUptimeBeforePost"], "releaseAfterPost": release["systemUptimeAfterPost"]}


def receiver_analysis(path, stage, context, case_name, case, clock, passed):
    pid = case.get("targetApplicationPID")
    capture.require(type(pid) is int and pid > 0, "target-application-pid")
    rows = read_trace(path, "receiver", pid)
    starts = [r for r in rows if r["event"] == "application-start"]
    ends = [r for r in rows if r["event"] == "application-terminated"]
    capture.require(len(starts) == len(ends) == 1 and rows[0] == starts[0] and rows[-1] == ends[0],
                    "receiver-lifecycle-trace")
    capture.fields_match(starts[0], {"bundleIdentifier": "app.lemulip.NativeDragControl", "theme": "orchard",
        "originalSHA256": context["fixtures"], "fixtureFilenames": sorted(context["fixtures"]),
        "sourceCase": case_name, "dragSourceKind": source_kind(case_name), "stagingRoot": str(stage),
        "bundlePath": str(stage / "Native Drag Control.app"),
        "executablePath": str(stage / "Native Drag Control.app/Contents/MacOS/NativeDragControl")}, "receiver-start-binding")
    for row in rows:
        capture.fields_match(row, {"sourceCase": case_name, "dragSourceKind": source_kind(case_name)}, "receiver-case-binding")
        for key in ("originalBytesUnchanged", "fixtureFileSetUnchanged"):
            if key in row:
                capture.require(row[key] is True, "receiver-originals-changed")
    callbacks = [r for r in rows if r["event"] in RECEIVER_CALLBACKS]
    capture.require(callbacks, "receiver-drag-missing")
    for row in callbacks:
        capture.require(type(row.get("sequenceNumber")) is int and row["sequenceNumber"] >= 0, "receiver-sequence")
        capture.fields_match(row, {"originalBytesUnchanged": True, "fixtureFileSetUnchanged": True}, "receiver-originals-receipt")
        capture.require(type(row.get("sourceAllowedOperationMask")) is int and row["sourceAllowedOperationMask"] >= 0,
                        "receiver-operation-mask")
        capture.require(isinstance(row.get("pasteboardTypes"), list) and row["pasteboardTypes"]
                        and all(isinstance(v, str) for v in row["pasteboardTypes"]), "receiver-pasteboard-types")
        if source_kind(case_name) == "native-appkit":
            capture.require(row["sourceAllowedOperationMask"] == 1, "native-offered-mask-changed")
    before_key = [r for r in callbacks if clock["dragDownBeforePost"] <= r["systemUptime"] < clock["downStartedSystemUptime"]]
    entered = [r for r in before_key if r["event"] == "draggingEntered" and r.get("returnedCopy") is True]
    capture.require(entered, "receiver-initial-entry-missing")
    sequence = entered[0]["sequenceNumber"]
    capture.require(all(r["sequenceNumber"] == sequence for r in before_key), "receiver-cancel-sequence-changed")
    exited = [r for r in before_key if r["event"] == "draggingExited" and r["recordIndex"] > entered[0]["recordIndex"]]
    capture.require(exited, "receiver-exit-missing")
    reentered = [r for r in before_key if r["event"] in ("draggingEntered", "draggingUpdated")
                 and r["recordIndex"] > exited[0]["recordIndex"] and r.get("returnedCopy") is True]
    capture.require(reentered, "receiver-reentry-before-escape-missing")
    existing, single = context["roles"]["Existing"], context["roles"]["Single"]
    first = [r for r in callbacks if r["sequenceNumber"] == sequence]
    accepted = [r for r in first if r["event"] == "performDragOperation" and r.get("accepted") is True]
    if passed:
        capture.require(not accepted, "cancelled-sequence-was-accepted")
    else:
        capture.require(len(accepted) == 1 and accepted[0]["systemUptime"] >= clock["releaseBeforePost"],
                        "failed-cancel-acceptance-not-bound")
        capture.require(sorted(accepted[0].get("selectedFilenames", [])) == sorted([existing, single]),
                        "failed-cancel-selected-files")
    fresh = None
    sequences = {r["sequenceNumber"] for r in callbacks}
    if passed:
        capture.require(len(sequences) == 2, "fresh-drop-sequence-missing")
        fresh_sequence = next(iter(sequences - {sequence}))
        fresh_rows = [r for r in callbacks if r["sequenceNumber"] == fresh_sequence]
        fresh_entries = [r for r in fresh_rows if r["event"] == "draggingEntered" and r.get("returnedCopy") is True]
        fresh_perform = [r for r in fresh_rows if r["event"] == "performDragOperation" and r.get("accepted") is True]
        capture.require(fresh_entries and len(fresh_perform) == 1
                        and fresh_entries[0]["systemUptime"] > clock["releaseAfterPost"], "fresh-drop-receiver-order")
        releases = [r for r in case["mouseEvents"] if r["eventType"] == 2
                    and r["systemUptimeBeforePost"] > fresh_entries[0]["systemUptime"]]
        capture.require(releases and releases[0]["systemUptimeBeforePost"] <= fresh_perform[0]["systemUptime"],
                        "fresh-drop-release-missing")
        capture.require(sorted(fresh_perform[0].get("selectedFilenames", [])) == sorted([existing, single]),
                        "fresh-drop-selected-files")
        fresh = {"sequenceNumber": fresh_sequence, "entrySystemUptime": fresh_entries[0]["systemUptime"],
                 "releaseBeforePost": releases[0]["systemUptimeBeforePost"],
                 "acceptedSystemUptime": fresh_perform[0]["systemUptime"]}
    else:
        capture.require(sequences == {sequence}, "unexpected-extra-drag-sequence")
    return {"pid": starts[0]["pid"], "cancelSequenceNumber": sequence,
            "entrySystemUptime": entered[0]["systemUptime"], "exitSystemUptime": exited[0]["systemUptime"],
            "reentrySystemUptime": reentered[0]["systemUptime"],
            "acceptedCancelSystemUptimes": [r["systemUptime"] for r in accepted], "freshDrop": fresh,
            "sourceAllowedOperationMasks": sorted({r["sourceAllowedOperationMask"] for r in callbacks}),
            "pasteboardTypes": sorted({v for r in callbacks for v in r["pasteboardTypes"]}),
            "escapeSendEventReceipts": [r for r in rows if r["event"] == "escape-send-event"],
            "activationReceipts": [r for r in rows if r["event"] in ("application-became-active", "application-resigned-active")]}


def source_analysis(path, stage, context, case_name, case, clock, receiver, passed):
    pid = case.get("sourceApplicationPID")
    capture.require(type(pid) is int and pid > 0 and pid != receiver["pid"], "source-application-pid")
    capture.require(case.get("sourceApplicationPath") == str(stage / SOURCE_BUNDLE), "source-application-path")
    rows = read_trace(path, "source", pid)
    for row in rows:
        capture.fields_match(row, {"sourceCase": case_name, "dragSourceKind": "native-appkit"}, "source-trace-case-binding")
        capture.require(row["event"] in SOURCE_EVENTS, "source-trace-event-unknown")
        for key in ("originalBytesUnchanged", "fixtureFileSetUnchanged"):
            if key in row:
                capture.require(row[key] is True, "source-originals-changed")
    ready = [r for r in rows if r["event"] == "source-ready"]
    terminated = [r for r in rows if r["event"] == "application-terminating"]
    capture.require(len(ready) == len(terminated) == 1 and rows[-1] == terminated[0], "source-lifecycle-trace")
    bindings = {k: context["provenance"][k] for k in (*SOURCE_KEYS, "observerExperimentCommit", "observerExperimentTree",
                "sourceCommit", "sourceTree", "architecture")}
    capture.fields_match(ready[0], {**bindings, "bundleIdentifier": SOURCE_ID, "executableName": SOURCE_EXECUTABLE,
        "bundleName": SOURCE_BUNDLE, "stagingRoot": str(stage), "sourceBundlePath": str(stage / SOURCE_BUNDLE),
        "geometryCoordinateSpace": "Quartz-global-top-left", "originalSHA256": context["fixtures"]}, "source-ready-binding")
    capture.fields_match(terminated[0], {"originalBytesUnchanged": True, "fixtureFileSetUnchanged": True,
        "sessionCount": 2 if passed else 1}, "source-termination-state")
    capture.require(type(terminated[0].get("activeSession")) is bool, "source-termination-session-state")
    capture.require(ready[0]["systemUptime"] < clock["dragDownBeforePost"], "source-ready-after-input")
    geometry = case["sourceGeometry"]
    for key in ("requestedSourcePointCG", "sourcePointCG"):
        capture.require(point(ready[0].get(key), "source-ready-point") == geometry["sourcePoint"], "source-ready-point-binding")
    for key, observer_key in (("actualWindowFrameCG", "nativeWindow"), ("imageFrameCG", "nativeIcon")):
        capture.require(ready[0].get(key) == rect_string(geometry[observer_key], "source-ready-rectangle"),
                        "source-ready-geometry-binding")
    callbacks = [r for r in rows if r["event"] in CALLBACKS]
    capture.require(callbacks, "source-session-missing")
    for row in callbacks:
        capture.require(type(row.get("sessionIndex")) is int and row["sessionIndex"] in (1, 2)
                        and type(row.get("sequenceNumber")) is int and row["sequenceNumber"] >= 0, "source-session-identity")
        capture.fields_match(row, {"filename": context["roles"]["Single"], "offeredOperationMask": 1,
            "callbackPointCoordinateSpace": "AppKit-screen-bottom-left"}, "source-session-fixture")
        capture.require(type(row.get("applicationActive")) is bool
                        and (row.get("keyWindowNumber") is None or type(row["keyWindowNumber"]) is int), "source-session-foreground")
        capture.require(type(row.get("animatesToStartingPositionsOnCancelOrFail")) is bool,
                        "source-session-animation-receipt")
        capture.require(isinstance(row.get("pasteboardTypes"), list) and row["pasteboardTypes"]
                        and all(isinstance(v, str) for v in row["pasteboardTypes"]), "source-session-pasteboard-types")
        callback_clock = finite(row.get("callbackSystemUptime"), "source-callback-clock")
        capture.require(callback_clock <= row["systemUptime"], "source-callback-after-emission")
        point(row.get("callbackPointScreen"), "source-callback-point")
        point(row.get("observedCursorCG"), "source-observed-cursor")
        if row["event"] in ("source-will-begin", "source-ended"):
            capture.fields_match(row, {"originalBytesUnchanged": True, "fixtureFileSetUnchanged": True},
                                 "source-originals-changed")
    capture.require({r["sessionIndex"] for r in callbacks} == ({1, 2} if passed else {1}), "source-session-count")
    sessions = {}
    for index in sorted({r["sessionIndex"] for r in callbacks}):
        session = [r for r in callbacks if r["sessionIndex"] == index]
        begins = [r for r in session if r["event"] == "source-will-begin"]
        ends = [r for r in session if r["event"] == "source-ended"]
        capture.require(len(begins) == 1 and len(ends) <= 1 and session[0] == begins[0], "source-session-lifecycle")
        sequence = begins[0]["sequenceNumber"]
        capture.require(all(r["sequenceNumber"] == sequence for r in session), "source-session-sequence-changed")
        clocks = [r["callbackSystemUptime"] for r in session]
        capture.require(clocks == sorted(clocks) and (not ends or session[-1] == ends[0]), "source-session-callback-order")
        if ends:
            capture.require(type(ends[0].get("operationRawValue")) is int and ends[0]["operationRawValue"] in (0, 1),
                            "source-ended-operation")
        sessions[index] = {"begin": begins[0], "end": ends[0] if ends else None}
    first = sessions[1]
    capture.require(first["begin"]["sequenceNumber"] == receiver["cancelSequenceNumber"], "source-receiver-sequence-mismatch")
    capture.require(clock["dragDownBeforePost"] <= first["begin"]["callbackSystemUptime"]
                    <= receiver["entrySystemUptime"] < clock["downStartedSystemUptime"], "source-cancel-begin-order")
    end, classification = first["end"], "session-end-unobserved"
    if end:
        ended = end["callbackSystemUptime"]
        if end["operationRawValue"] == 1:
            capture.require(ended >= clock["releaseBeforePost"] and receiver["acceptedCancelSystemUptimes"],
                            "source-copy-without-target-acceptance")
            classification = "accepted-after-release"
        else:
            capture.require(not receiver["acceptedCancelSystemUptimes"], "source-none-with-target-acceptance")
            if ended < clock["downStartedSystemUptime"]:
                classification = "indeterminate-end-before-escape"
            elif ended < clock["downCompletedSystemUptime"]:
                classification = "indeterminate-end-during-key-post"
            elif ended < clock["releaseBeforePost"]:
                classification = "cancelled-before-release" if passed else "indeterminate-end-before-release"
            else:
                classification = "indeterminate-end-after-release"
    fresh_complete = True
    if passed:
        fresh = sessions[2]
        fresh_receiver = receiver["freshDrop"]
        capture.require(fresh["begin"]["sequenceNumber"] == fresh_receiver["sequenceNumber"]
                        and fresh["begin"]["sequenceNumber"] != first["begin"]["sequenceNumber"], "source-fresh-sequence-mismatch")
        capture.require(clock["releaseAfterPost"] < fresh["begin"]["callbackSystemUptime"]
                        <= fresh_receiver["entrySystemUptime"], "source-fresh-begin-order")
        if end:
            capture.require(end["callbackSystemUptime"] <= fresh["begin"]["callbackSystemUptime"],
                            "source-sessions-overlap")
        fresh_complete = fresh["end"] is not None
        if fresh_complete:
            capture.require(fresh["end"]["operationRawValue"] == 1
                            and fresh["end"]["callbackSystemUptime"] >= fresh_receiver["acceptedSystemUptime"],
                            "source-fresh-copy-not-proven")
    if end is not None and fresh_complete:
        capture.require(terminated[0]["activeSession"] is False, "source-termination-still-dragging")
    return {"classification": classification, "traceComplete": end is not None and fresh_complete,
            "sourceSHA256": capture.sha256(path), "pid": pid,
            "cancelSession": first, "freshSession": sessions.get(2),
            "escapeSendEventReceipts": [r for r in rows if r["event"] == "escape-send-event"],
            "activationReceipts": [r for r in rows if r["event"] in ("application-became-active", "application-resigned-active")],
            "interpretation": "A NONE callback after release is indeterminate; missing sendEvent receipts do not prove nondelivery."}


def classify(stage, context, case_name, returncode):
    kind = source_kind(case_name)
    evidence = evidence_for(stage, case_name)
    aggregate = capture.read_json(evidence / "report.json")
    case = capture.read_json(evidence / "orchard/report.json")
    startup = {}
    expected = {"sourceCase": case_name, "dragSourceKind": kind, "observerLifecycle": "appkit",
                **{k: context["provenance"][k] for k in SOURCE_KEYS}}
    for label, record in (("aggregate", aggregate), ("case", case)):
        capture.fields_match(record, expected, "source-comparison-binding")
        startup[label] = lifecycle.lifecycle_context(record.get("observerLifecycleAtStart"), "appkit")
    result = capture.classify(stage, context, "control", POLICY, returncode,
                             evidence_suffix="-Lifecycle-appkit-Source-" + case_name)
    capture.fields_match(case["cleanup"], {"sourceApplicationStopped": True, "sourceBundleRegistryEmpty": True},
                         "source-cleanup-incomplete")
    signature = geometry_signature(case, kind)
    geometries = case.get("sourceGeometries")
    capture.require(isinstance(geometries, dict) and geometries.get("cancel-source") == case["sourceGeometry"],
                    "cancel-source-geometry-missing")
    if result["passed"]:
        capture.require(geometries.get("drop-source") == case["sourceGeometry"], "fresh-source-geometry-changed")
    clock = gesture_clock(case)
    receiver = receiver_analysis(evidence / "orchard/receiver.jsonl", stage, context, case_name, case, clock, result["passed"])
    if kind == "native-appkit":
        source = source_analysis(evidence / "orchard/source.jsonl", stage, context, case_name, case, clock, receiver, result["passed"])
    else:
        capture.require(not (evidence / "orchard/source.jsonl").exists(), "finder-source-trace-unexpected")
        source = {"classification": "source-session-unobserved", "traceComplete": None,
                  "interpretation": "Finder supplies no instrumented source callback; destination outcome remains the AX observation."}
    foreground = []
    for row in case.get("escapeInputStates", []):
        if isinstance(row, dict):
            foreground.append({key: row.get(key) for key in ("phase", "systemUptime", "foregroundBundleIdentifier", "foregroundPID",
                "mouseDownSent", "leftButtonReportedDown", "hidLeftButtonReportedDown", "escapeKeyReportedDown", "hidEscapeKeyReportedDown")})
    result.update(**expected, observerLifecycleAtStart=startup,
        observerExecutable="NativeDragReviewAppKit", observerExecutableSHA256=context["provenance"]["observerAppKitExecutableSHA256"],
        geometrySignature=signature, sourceGeometry=case["sourceGeometry"], sourceGeometries=geometries, escapePostTiming=clock,
        receiver=receiver, sourceSession=source, foreground=foreground, axOutcome=result["outcome"])
    if source["traceComplete"] is False:
        result.update(outcome="not-comparable", passed=False, mayContinue=False, reasonCode="source-session-end-unobserved")
    elif source["classification"] == "indeterminate-end-before-escape":
        result.update(outcome="not-comparable", passed=False, mayContinue=False, reasonCode="source-session-ended-before-escape")
    return result


def compare(stage, output, context, runner=capture.run_observer):
    capture.require(not output.exists() and not output.is_symlink(), "output-already-exists")
    capture.require(all(not evidence_for(stage, name).exists() and not evidence_for(stage, name).is_symlink() for name in CASES),
                    "evidence-already-exists")
    output.mkdir(parents=False, exist_ok=False)
    capture.write_json(output / "inputs-before.json", context["inputs"])
    results, stopped, geometry = [], None, None
    for case_name in CASES:
        identity = {"target": "control", "sourceCase": case_name, "dragSourceKind": source_kind(case_name),
                    "observerLifecycle": "appkit", "captureComparison": POLICY}
        if stopped:
            results.append({**identity, "outcome": "not-run", "reasonCode": stopped})
            continue
        returncode = None
        try:
            capture.require(input_snapshot(stage) == context["inputs"], "inputs-changed-before-case")
            command = [str(stage / "NativeDragReviewAppKit"), str(stage), "--control", "--compare-capture", POLICY,
                       "--compare-source", case_name]
            returncode = runner(command, output / (case_name + ".log"))
            capture.require(input_snapshot(stage) == context["inputs"], "inputs-changed-after-case")
            result = classify(stage, context, case_name, returncode)
            if geometry is None:
                geometry = result["geometrySignature"]
            capture.require(result["geometrySignature"] == geometry, "geometry-changed-between-cases")
            result["inputsUnchanged"] = True
            results.append(result)
            if result["mayContinue"] is not True:
                stopped = result["reasonCode"]
        except Exception as error:
            stopped = str(error) if isinstance(error, capture.ComparisonError) else type(error).__name__
            results.append({**identity, "outcome": "not-comparable", "returnCode": returncode,
                            "reasonCode": stopped, "mayContinue": False})
    try:
        after = input_snapshot(stage)
        unchanged = after == context["inputs"]
        capture.write_json(output / "inputs-after.json", after)
    except Exception:
        unchanged = False
    complete = len(results) == len(CASES) and all(r.get("mayContinue") is True for r in results)
    passed = complete and unchanged and all(r.get("passed") is True for r in results)
    report = {"schema": 1, "status": "passed" if passed else "failed", "diagnosticOnly": True,
        "releaseReady": False, "nativeAcceptanceXCTestExecuted": False, "physicalInputVerified": False,
        "C12": "HOLD", "comparisonComplete": complete, "allCasesPassed": passed, "caseOrder": list(CASES),
        "inputsUnchanged": unchanged, "sameStagedPaths": True, "captureComparison": POLICY, "observerLifecycle": "appkit",
        "provenance": context["provenance"], "fixtureHashes": context["fixtures"], "cases": results,
        "scope": "Four serial Orchard control cases in one existing CI session. C12 is built only for staging; no production-target input.",
        "interpretation": "Finder and the copy-only native source differ in source implementation and offered pasteboard/operation semantics. This comparison does not isolate hardware, spring-loading, or App Nap; source callbacks cannot substitute for strict AX cancellation and fresh-drop outcomes."}
    capture.write_json(output / "comparison.json", report)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--staged", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--experiment-commit", required=True)
    args = parser.parse_args()
    capture.require(platform.system() == "Darwin" and platform.machine() in ("arm64", "x86_64"), "native-mac-required")
    stage = args.staged.absolute()
    report = compare(stage, args.output.absolute(), context_for(stage, args.experiment_commit))
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0 if report["allCasesPassed"] else 1


if __name__ == "__main__":
    sys.exit(main())
