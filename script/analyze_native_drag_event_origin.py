"""Read retained D13 evidence and describe D14 target mouse-event identities.

Never starts a runner, posts input, changes acceptance, or calls context_for or
input_snapshot.  The existing D13 classifier is replayed only against retained
files; its result must equal the already-recorded comparison case.
"""
import argparse
from datetime import datetime
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
import sys

import compare_native_drag_mouse_driver as mouse

capture, sources, activation = mouse.capture, mouse.sources, mouse.activation
OUTPUT_NAME = "event-origin-analysis.json"
PROTOCOL_BASE_COMMIT = "d69f6b344a0dc069027f04061686a308dae79ba4"
D13_COMPARATOR_SHA256 = "7bab775cdcb4884aba36fae21d1ddcef7635de02b8edf5da54a8ead2fa7b54f4"
DIAGNOSTIC = {"schema": 1, "protocolBaseCommit": PROTOCOL_BASE_COMMIT,
              "inputProtocol": "D13-R3-unchanged", "targetMouseEventIdentitySchema": 1}
CONTROL_BUILD = {"executable": "Native Drag Control.app/Contents/MacOS/NativeDragControl",
                 "swiftDefines": ["LEMULIP_EVENT_ORIGIN_TRACE"]}
CODE_FILES = {
    "eventOriginAnalyzerSourceSHA256": "script/analyze_native_drag_event_origin.py",
    "eventOriginSystemLogCollectorSourceSHA256": "script/capture_native_drag_system_log.py",
}
CG_FIELDS = {"cgSourceStateID", "cgSourcePID", "cgMouseEventNumber", "cgMousePressure", "cgTimestampNanoseconds"}
MOUSE_FIELDS = {"eventType", "eventNumber", "buttonNumber", "clickCount", "pressure", "modifierFlags"}
POINT_TOLERANCE = 1.0
LIMITATIONS = [
    "This analysis does not change the D13 native outcome or verify the original enter/exit/reentry gate.",
    "NSEvent.cgEvent can create a corresponding CG event or be unavailable. Its PID/state fields are observations, not proof of the upstream sender; PID zero does not identify WindowServer.",
    "Matching a coordinate, post interval, or the 0.25-second suppression interval does not establish event identity or causality.",
    "Receiver systemUptime is a retained record clock. Source moved callbacks do not retain the originating NSEvent timestamp; XCTest END and observed release are not exact physical button-up timestamps.",
]


def equal(actual, expected, label):
    encode = lambda value: json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False)
    capture.require(encode(actual) == encode(expected), label)


def integer(value, label, *, minimum=0, maximum=(1 << 63) - 1):
    capture.require(type(value) is int and minimum <= value <= maximum, label)
    return value


def number(value, label):
    capture.require(type(value) in (int, float) and math.isfinite(value), label)
    return value


def digest(value, label):
    capture.require(isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) is not None, label)
    return value


def repository_identity(commit):
    """Bind the running analyzer/collector and unchanged D13 code to Git bytes."""
    capture.require(isinstance(commit, str) and re.fullmatch(r"[0-9a-f]{40}", commit) is not None,
                    "event-origin-experiment-commit")
    def git(*arguments):
        return subprocess.check_output(["git", "-C", str(capture.ROOT), *arguments], timeout=10)
    tree = git("rev-parse", "--verify", commit + "^{tree}").decode().strip()
    capture.require(re.fullmatch(r"[0-9a-f]{40}", tree) is not None, "event-origin-experiment-tree")
    hashes = {}
    for key, relative in {**CODE_FILES, "mouseDriverComparatorSourceSHA256":
                          "script/compare_native_drag_mouse_driver.py"}.items():
        published = hashlib.sha256(git("show", commit + ":" + relative)).hexdigest()
        capture.require(published == capture.sha256(capture.ROOT / relative), "event-origin-running-source-differs")
        hashes[key] = published
    capture.require(hashes["mouseDriverComparatorSourceSHA256"] == D13_COMPARATOR_SHA256,
                    "event-origin-d13-comparator-changed")
    return {"tree": tree, "hashes": hashes}


def context_for_retained(stage, comparison_directory, commit):
    capture.require(stage.name == "lemulip-native-ui" and stage == stage.resolve(), "event-origin-staging-root")
    provenance = mouse.read_json(stage / "provenance.json", "event-origin-provenance")
    comparison = mouse.read_json(comparison_directory / "comparison.json", "event-origin-comparison")
    repository = repository_identity(commit)
    capture.fields_match(provenance, {"sourceCommit": capture.APPLICATION_COMMIT,
        "sourceTree": capture.APPLICATION_TREE, "observerExperimentCommit": commit,
        "observerExperimentTree": repository["tree"], **repository["hashes"]}, "event-origin-provenance-binding")
    capture.require(provenance.get("architecture") in ("arm64", "x86_64"), "event-origin-architecture")
    equal(provenance.get("eventOriginDiagnostic"), DIAGNOSTIC, "event-origin-diagnostic-schema")
    equal(provenance.get("eventOriginControlBuild"), CONTROL_BUILD, "event-origin-control-build")
    equal(comparison.get("provenance"), provenance, "event-origin-comparison-provenance")
    capture.fields_match(comparison, {"schema": 1, "diagnosticOnly": True, "releaseReady": False,
        "C12": "HOLD", "nativeAcceptanceXCTestExecuted": False, "physicalInputVerified": False,
        "captureComparison": "ax-only", "observerLifecycle": "appkit", "caseOrder": list(mouse.CASES),
        "inputsUnchanged": True}, "event-origin-comparison-scope")
    cases = comparison.get("cases")
    capture.require(isinstance(cases, list) and len(cases) == len(mouse.CASES), "event-origin-case-count")
    for name, row in zip(mouse.CASES, cases):
        capture.fields_match(row, mouse.bindings(name), "event-origin-case-order-or-binding")
        capture.require(row.get("comparability") in ("comparable", "not-comparable", "not-run"),
                        "event-origin-comparability")
    capture.require(type(comparison.get("comparisonComplete")) is bool, "event-origin-comparison-complete-type")
    before = mouse.read_json(comparison_directory / "inputs-before.json", "event-origin-inputs-before")
    after = mouse.read_json(comparison_directory / "inputs-after.json", "event-origin-inputs-after")
    capture.require(before and len(before) <= 16_384, "event-origin-input-inventory")
    equal(before, after, "event-origin-inputs-changed")
    capture.require(before.get("provenance.json", {}).get("sha256") == capture.sha256(stage / "provenance.json"),
                    "event-origin-inventory-provenance")
    fixtures = comparison.get("fixtureHashes")
    capture.require(isinstance(fixtures, dict) and len(fixtures) == 4, "event-origin-fixtures")
    roles = {}
    for role in ("Existing", "Single", "Multi-A", "Multi-B"):
        names = [name for name in fixtures if isinstance(name, str)
                 and re.fullmatch(re.escape(role) + r"-[0-9a-f]{32}\.txt", name)]
        capture.require(len(names) == 1, "event-origin-fixture-role")
        roles[role] = names[0]
        digest(fixtures[names[0]], "event-origin-fixture-hash")
    configurations = {name: mouse.configuration_for(stage, name) for name in mouse.CASES}
    equal(provenance.get("mouseConfigurationsSHA256"), {name: capture.sha256(
        stage / "MouseControl" / name / "configuration.json") for name in mouse.CASES}, "event-origin-configuration-hashes")
    capture.require(len({row["nonce"] for row in configurations.values()}) == 4, "event-origin-configuration-nonces")
    return {"provenance": provenance, "fixtures": fixtures, "roles": roles,
            "mouseConfigurations": configurations}, comparison


def delivered_mouse(value, event_type, *, source=False):
    capture.require(isinstance(value, dict), "event-origin-delivered-object")
    if source:
        cg_present = bool(set(value) & CG_FIELDS)
        expected = MOUSE_FIELDS | (CG_FIELDS if cg_present else set())
    else:
        capture.require(type(value.get("cgEventPresent")) is bool, "event-origin-cg-presence")
        cg_present = value["cgEventPresent"]
        expected = MOUSE_FIELDS | {"cgEventPresent"} | (CG_FIELDS if cg_present else set())
    capture.require(set(value) == expected, "event-origin-delivered-fields")
    capture.fields_match(value, {"eventType": event_type, "buttonNumber": 0}, "event-origin-mouse-type-or-button")
    integer(value["eventNumber"], "event-origin-event-number", minimum=-(1 << 63))
    integer(value["modifierFlags"], "event-origin-modifiers", maximum=(1 << 64) - 1)
    if event_type == 6:
        capture.require(value["clickCount"] is None, "event-origin-drag-click-count")
    else:
        integer(value["clickCount"], "event-origin-click-count")
    capture.require(0 <= number(value["pressure"], "event-origin-pressure") <= 1, "event-origin-pressure-range")
    if cg_present:
        integer(value["cgSourceStateID"], "event-origin-cg-state", minimum=-(1 << 63))
        integer(value["cgSourcePID"], "event-origin-cg-pid", maximum=(1 << 31) - 1)
        integer(value["cgMouseEventNumber"], "event-origin-cg-number", minimum=-(1 << 63))
        integer(value["cgTimestampNanoseconds"], "event-origin-cg-time", maximum=(1 << 64) - 1)
        capture.require(0 <= number(value["cgMousePressure"], "event-origin-cg-pressure") <= 1,
                        "event-origin-cg-pressure-range")
    return cg_present


def target_mouse_pairs(rows, case):
    for event in ("activation-start", "activation-ready"):
        markers = [r for r in rows if r["event"] == event]
        capture.require(len(markers) == 1, "event-origin-marker-count")
        capture.fields_match(markers[0], {"targetMouseEventIdentitySchema": 1}, "event-origin-marker-schema")
    pairs = activation.paired_events(rows, case["targetRaiseRequests"], {
        "dragDownBeforePost": case["mouseDriverGestures"][0]["startedSystemUptime"],
        "releaseAfterPost": case["mouseDriverGestures"][0]["releaseObservedSystemUptime"]})
    mouse_pairs = [p for p in pairs if p["kind"] == "target-mouse"]
    capture.require(len(mouse_pairs) <= 64, "event-origin-mouse-pair-bound")
    for pair in mouse_pairs:
        entered, returned = pair["enter"], pair["return"]
        for row in (entered, returned):
            delivered_mouse(row.get("deliveredMouseEvent"), row["eventType"])
            capture.fields_match(row["deliveredMouseEvent"], {"modifierFlags": row["modifierFlags"]},
                                 "event-origin-mouse-flags-binding")
            capture.require(type(row.get("eventMatchesOwnedWindow")) is bool, "event-origin-owned-window-type")
            capture.require(0 <= row["eventTimestamp"] <= activation.event_clock(row) + 1e-6,
                            "event-origin-event-clock")
        equal(entered["deliveredMouseEvent"], returned["deliveredMouseEvent"], "event-origin-pair-identity-changed")
        equal(entered["eventMatchesOwnedWindow"], returned["eventMatchesOwnedWindow"], "event-origin-pair-window-changed")
    return pairs, mouse_pairs


def point_distance(a, b):
    return math.hypot(a["x"] - b["x"], a["y"] - b["y"])


def reference(row, *, callback=False):
    return {"recordIndex": row["recordIndex"], "event": row["event"],
            "systemUptime": activation.event_clock(row) if callback else row["systemUptime"]}


def wall_time_range(rows):
    values = []
    for row in rows:
        value = row.get("time")
        capture.require(isinstance(value, str) and re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ", value) is not None,
                        "event-origin-receiver-wall-time")
        values.append((datetime.fromisoformat(value.replace("Z", "+00:00")), value))
    start, end = min(values), max(values)
    capture.require((end[0] - start[0]).total_seconds() <= 300, "event-origin-receiver-wall-span")
    return {"start": start[1], "end": end[1], "precision": "seconds"}


def quartz_relations(case, gesture, event, point):
    if case["mouseProducer"] != "quartz":
        return {"status": "not-applicable", "reason": "XCTest mouse posts are not recorded by the observer."}
    stamp = event["eventTimestamp"]
    posts = [(index, row) for index, row in enumerate(case["mouseEvents"])
             if row["eventType"] == 6 and gesture["startedSystemUptime"] <= row["systemUptimeBeforePost"]
             <= gesture["releaseObservedSystemUptime"]]
    capture.require(posts and len(posts) <= 255, "event-origin-quartz-post-count")
    matched, intervals = [], []
    for index, row in posts:
        before, after = row["systemUptimeBeforePost"], row["systemUptimeAfterPost"]
        inside = before <= stamp <= after
        if inside:
            intervals.append(index)
        if point_distance(point, row["location"]) <= POINT_TOLERANCE:
            matched.append({"mouseEventIndex": index, "location": row["location"],
                "postStartedSystemUptime": before, "postCompletedSystemUptime": after,
                "timestampInsidePostInterval": inside, "eventTimestampMinusPostCompletedSeconds": stamp - after})
    last_index, last = posts[-1]
    return {"status": "observed", "locationTolerancePoints": POINT_TOLERANCE,
        "matchingLocationPosts": matched, "postIntervalsContainingEventTimestamp": intervals,
        "lastPostedDragIndex": last_index, "lastPostedDragCompletedSystemUptime": last["systemUptimeAfterPost"],
        "eventTimestampMinusLastPostedDragSeconds": stamp - last["systemUptimeAfterPost"]}


def receiver_relation(rows, gesture, event, point):
    sequence = gesture["entryObservation"]["sequenceNumber"]
    relevant = [r for r in rows if r["event"] in ("draggingEntered", "draggingUpdated")
                and r.get("sequenceNumber") == sequence]
    capture.require(relevant, "event-origin-receiver-locations-missing")
    changes, previous = [], None
    for row in relevant:
        location = sources.point(row.get("draggingLocationInWindow"), "event-origin-receiver-location")
        if location != previous:
            changes.append(row)
        previous = location
    before = [r for r in changes if r["systemUptime"] <= event["eventTimestamp"]]
    capture.require(before, "event-origin-no-location-before-event")
    last = before[-1]
    final = next((r for r in relevant if point_distance(r["draggingLocationInWindow"], point) <= POINT_TOLERANCE), None)
    return {"lastDistinctLocationBeforeEvent": {**reference(last), "locationInWindow": last["draggingLocationInWindow"]},
        "eventTimestampMinusLastDistinctLocationSeconds": event["eventTimestamp"] - last["systemUptime"],
        "callbackMinusLastDistinctLocationSeconds": activation.event_clock(event) - last["systemUptime"],
        "distinctLocationsBeforeEvent": len(before),
        "firstReceiverAtEventLocation": reference(final) if final else None,
        "firstReceiverAtEventLocationMinusEventTimestampSeconds": final["systemUptime"] - event["eventTimestamp"] if final else None}


def analyze_case(stage, context, name, recorded):
    directory = mouse.evidence_for(stage, name) / "orchard"
    raw_path = directory / "report.json"
    raw_hash = capture.sha256(raw_path)
    capture.require(raw_hash == digest(recorded.get("caseSHA256"), "event-origin-case-hash-format"), "event-origin-case-hash")
    raw = mouse.read_json(raw_path, "event-origin-raw-case")
    expected = dict(recorded)
    capture.require(expected.pop("inputsUnchanged", None) is True, "event-origin-case-inputs")
    replayed = mouse.classify(stage, context, name, recorded.get("returnCode"))
    equal(replayed, expected, "event-origin-d13-classification-changed")
    capture.require(replayed.get("comparability") == "comparable", "event-origin-d13-case-incomplete")
    pids = {"observer": raw.get("observerProcessID"), "source": raw.get("sourceApplicationPID"),
            "target": raw.get("targetApplicationPID"), "runner": raw.get("mouseControlDriver", {}).get("runnerPID")}
    for value in pids.values():
        integer(value, "event-origin-owned-pid", minimum=1, maximum=(1 << 31) - 1)
    capture.require(len(set(pids.values())) == len(pids), "event-origin-owned-pid-collision")
    rows = {}
    hash_fields = {"activation": (replayed["activation"], "activationSHA256"),
        "receiver": (replayed["receiver"], "receiverSHA256"), "source": (replayed["sourceSession"], "sourceSHA256")}
    hashes = {}
    for kind, (record, key) in hash_fields.items():
        path = directory / (kind + ".jsonl")
        hashes[key] = capture.sha256(path)
        capture.require(hashes[key] == record[key], "event-origin-trace-hash")
        rows[kind] = sources.read_trace(path, "event-origin-" + kind, pids["source" if kind == "source" else "target"])
        for row in rows[kind]:
            capture.fields_match(row, mouse.bindings(name), "event-origin-trace-binding")
    pairs, mouse_pairs = target_mouse_pairs(rows["activation"], raw)
    gesture = raw["mouseDriverGestures"][0]
    held = [p for p in mouse_pairs if p["enter"]["eventType"] == 6 and gesture["startedSystemUptime"]
            <= activation.event_clock(p["enter"]) <= gesture["releaseObservedSystemUptime"]]
    capture.require(held, "event-origin-held-target-drag-missing")
    first = min(held, key=lambda p: activation.event_clock(p["enter"]))
    event, returned = first["enter"], first["return"]
    capture.require(event["eventMatchesOwnedWindow"] is True, "event-origin-target-drag-window")
    initial = [r for r in rows["source"] if r["event"] == "source-mouse-down"
               and gesture["startedSystemUptime"] <= r["systemUptime"] < gesture["entryObservation"]["receiverEntrySystemUptime"]]
    capture.require(len(initial) == 1, "event-origin-source-initial-down")
    down = initial[0]
    source_cg = delivered_mouse(down.get("deliveredMouseEvent"), 1, source=True)
    source_stamp = number(down.get("eventTimestamp"), "event-origin-source-down-clock")
    capture.require(gesture["startedSystemUptime"] <= source_stamp <= down["systemUptime"], "event-origin-source-down-order")
    identity = event["deliveredMouseEvent"]
    cg_pid = identity.get("cgSourcePID")
    relation = next((role for role, pid in pids.items() if pid == cg_pid), "unknown") if identity["cgEventPresent"] else "cg-event-unavailable"
    frame, location = gesture["targetFrame"], event["locationInWindow"]
    point = {"x": frame["x"] + location["x"], "y": frame["y"] + frame["height"] - location["y"]}
    later = [p for p in pairs if p["kind"] == "appkit-defined" and p["enter"].get("eventSubtype") == 1
             and activation.event_clock(event) < activation.event_clock(p["enter"]) <= gesture["releaseObservedSystemUptime"]]
    capture.require(len(later) <= 16, "event-origin-activation-dispatch-bound")
    activations = []
    for pair in later:
        before, after = activation.event_clock(pair["enter"]), activation.event_clock(pair["return"])
        nested = [reference(row, callback=True) for row in rows["activation"]
                  if row["event"] in ("window-became-main", "window-became-key", "application-became-active")
                  and before <= activation.event_clock(row) <= after]
        capture.require(len(nested) <= 16, "event-origin-nested-activation-bound")
        activations.append({"dispatchIndex": pair["index"], "enter": reference(pair["enter"], callback=True),
            "return": reference(pair["return"], callback=True), "eventTimestamp": pair["enter"]["eventTimestamp"],
            "activationTimestampMinusMouseEventTimestampSeconds": pair["enter"]["eventTimestamp"] - event["eventTimestamp"],
            "nestedTargetNotifications": nested})
    source_pid = down["deliveredMouseEvent"].get("cgSourcePID")
    return {"case": name, "status": "analyzed", "mouseProducer": raw["mouseProducer"],
        "nativeComparison": {key: recorded.get(key) for key in ("comparability", "outcome", "passed", "returnCode")},
        "baseClassificationReproduced": True, "caseReportPath": str(raw_path), "caseSHA256": raw_hash,
        **hashes, "ownedPIDs": pids, "wallTimeRange": wall_time_range(rows["receiver"]),
        "targetMousePairsValidated": len(mouse_pairs), "targetMouseEventIdentitySchema": 1,
        "inputSource": {key: raw["inputSource"][key] for key in ("kind", "sourceStateID",
            "localEventsSuppressionInterval", "previousSuppressionIntervalFilter", "previousRemoteMouseDragFilter",
            "suppressionIntervalFilter", "remoteMouseDragFilter")},
        "firstHeldTargetDrag": {"dispatchIndex": first["index"], "enter": reference(event, callback=True),
            "return": reference(returned, callback=True), "eventTimestamp": event["eventTimestamp"],
            "deliveredMouseEvent": identity, "cgSourcePIDRelation": relation,
            "cgSourcePIDMatchesSourceInitialDown": cg_pid == source_pid if identity["cgEventPresent"] and source_cg else None,
            "correspondingCGTimestampMinusNSEventSeconds": identity["cgTimestampNanoseconds"] / 1e9 - event["eventTimestamp"]
                if identity["cgEventPresent"] else None,
            "sourceInitialDown": {**reference(down), "eventTimestamp": source_stamp,
                "deliveredMouseEvent": down["deliveredMouseEvent"], "cgEventFieldsPresent": source_cg},
            "locationInWindow": location, "locationCGFromOwnedWindowFrame": point,
            "distanceFromTerminalPoint": point_distance(point, gesture["targetPoint"]),
            "quartzPostRelations": quartz_relations(raw, gesture, event, point),
            "receiverLocationRelation": receiver_relation(rows["receiver"], gesture, event, location),
            "laterActivationDispatches": activations, "associationOnly": True}}


def error_code(error):
    return str(error)[:240] if isinstance(error, capture.ComparisonError) else type(error).__name__


def native_summary(record):
    values = {}
    for key in ("comparability", "outcome", "passed", "returnCode"):
        value = record.get(key)
        values[key] = value[:128] if isinstance(value, str) else value if type(value) in (bool, int) else None
    return values


def analyze(stage, comparison_directory, commit):
    result = {"schema": 1, "diagnostic": "native-drag-event-origin", "experimentCommit": commit,
        "protocolBaseCommit": PROTOCOL_BASE_COMMIT, "inputProtocol": DIAGNOSTIC["inputProtocol"],
        "acceptanceUnchanged": True, "nativeInputExecuted": False, "analysisComplete": False,
        "comparisonPath": str(comparison_directory / "comparison.json"), "collectorPIDs": [],
        "cases": [], "limitations": LIMITATIONS}
    try:
        context, comparison = context_for_retained(stage, comparison_directory, commit)
        result.update(experimentTree=context["provenance"]["observerExperimentTree"],
            architecture=context["provenance"]["architecture"], provenanceSHA256=capture.sha256(stage / "provenance.json"),
            comparisonSHA256=capture.sha256(comparison_directory / "comparison.json"),
            comparisonComplete=comparison.get("comparisonComplete"))
        for name, recorded in zip(mouse.CASES, comparison["cases"]):
            native = native_summary(recorded)
            try:
                if recorded.get("comparability") == "not-run":
                    capture.require(recorded.get("outcome") == "not-run" and not
                        (mouse.evidence_for(stage, name) / "orchard/report.json").exists(), "event-origin-unexpected-unrun-evidence")
                    row = {"case": name, "status": "not-run", "nativeComparison": native,
                           "reasonCode": str(recorded.get("reasonCode", "not-run"))[:240]}
                elif recorded.get("comparability") != "comparable":
                    row = {"case": name, "status": "incomplete", "nativeComparison": native,
                           "reasonCode": str(recorded.get("reasonCode", "d13-not-comparable"))[:240]}
                else:
                    row = analyze_case(stage, context, name, recorded)
                result["cases"].append(row)
            except Exception as error:
                result["cases"].append({"case": name, "status": "incomplete" if isinstance(error, FileNotFoundError) else "invalid",
                    "nativeComparison": native, "reasonCode": error_code(error)})
        result["collectorPIDs"] = sorted({pid for row in result["cases"] if row["status"] == "analyzed"
                                          for pid in row["ownedPIDs"].values()})
        result["analysisComplete"] = all(row["status"] == "analyzed" for row in result["cases"])
        result["status"] = "complete" if result["analysisComplete"] else (
            "invalid" if any(row["status"] == "invalid" for row in result["cases"]) else "incomplete")
    except Exception as error:
        result["status"] = "incomplete" if isinstance(error, FileNotFoundError) else "invalid"
        result["reasonCode"] = error_code(error)
        result["cases"] = [{"case": name, "status": "incomplete", "reasonCode": "comparison-context-unavailable"}
                           for name in mouse.CASES]
    return result


def write_analysis(output, result):
    capture.require(not output.is_symlink(), "event-origin-output-symlink")
    output.mkdir(parents=True, exist_ok=True)
    data = json.dumps(result, indent=2, sort_keys=True, allow_nan=False) + "\n"
    capture.require(len(data.encode()) <= 1_048_576, "event-origin-output-bound")
    with (output / OUTPUT_NAME).open("x", encoding="utf-8") as stream:
        stream.write(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--staged", type=Path, required=True)
    parser.add_argument("--comparison", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--experiment-commit", required=True)
    args = parser.parse_args()
    result = analyze(args.staged.absolute(), args.comparison.absolute(), args.experiment_commit)
    write_analysis(args.output.absolute(), result)
    print(json.dumps({"status": result["status"], "analysisComplete": result["analysisComplete"],
                      "report": str(args.output.absolute() / OUTPUT_NAME)}, sort_keys=True))
    return 0 if result["analysisComplete"] else 1


if __name__ == "__main__":
    sys.exit(main())
