"""Compare explicit target AXRaise presence with omission; never change permissions."""
import argparse
import json
from pathlib import Path
import platform
import re
import sys

import compare_native_drag_capture as capture
import compare_native_drag_sources as sources

CASES = sources.ACTIVATION_CASES
POLICY = "ax-only"
RAISE_PHASES = ["focus-finder", "focus-finder", "focus-finder", "focus-native-source"]
WINDOW_EVENTS = sources.ACTIVATION_SOURCE_EVENTS
ACTIVATION_EVENTS = {"activation-start", "activation-ready", "activation-terminating",
    "application-became-active", "application-resigned-active", *WINDOW_EVENTS,
    "target-ax-raise-enter", "target-ax-raise-return", "appkit-defined-enter", "appkit-defined-return",
    "target-mouse-enter", "target-mouse-return"}
STATE_BOOLEANS = ("windowIsKey", "windowIsMain", "windowCanBecomeKey", "windowCanBecomeMain", "windowVisible")


def bindings(case_name):
    return {"sourceCase": case_name, "dragSourceKind": "native-appkit",
            **sources.experiment_bindings(case_name, comparison="activation")}


def evidence_for(stage, case_name):
    return sources.evidence_for(stage, case_name, comparison="activation")


def point_string(value):
    number = r"(-?(?:\d+(?:\.\d*)?|\.\d+))"
    capture.require(isinstance(value, str), "activation-point-geometry")
    match = re.fullmatch(r"\{" + number + r",\s*" + number + r"\}", value)
    capture.require(match is not None, "activation-point-geometry")
    return sources.point(dict(zip(("x", "y"), map(float, match.groups()))), "activation-point-geometry")


def input_signature(case, clock):
    source = case.get("inputSource")
    capture.fields_match(source, {"kind": "shared-hid-keyboard-filter-comparison", "sourceStateID": 1},
                         "activation-input-source")
    sources.finite(source.get("localEventsSuppressionInterval"), "activation-input-suppression")
    for key in ("previousSuppressionIntervalFilter", "previousRemoteMouseDragFilter",
                "suppressionIntervalFilter", "remoteMouseDragFilter"):
        capture.require(type(source.get(key)) is int and source[key] >= 0, "activation-input-filter")
    events = [e for e in case["mouseEvents"] if clock["dragDownBeforePost"] <= e["systemUptimeBeforePost"] <= clock["releaseBeforePost"]]
    capture.require([e["eventType"] for e in events] == [1] + [6] * 55 + [2], "activation-cancel-pointer-protocol")
    signature = []
    for row in events:
        capture.fields_match(row, {"scope": "plain-gesture", "postCalled": True,
                                   "eventTap": "cghidEventTap", "sourceStateID": 1}, "activation-pointer-binding")
        capture.require(type(row.get("postedFlags")) is int and row["postedFlags"] >= 0
                        and row["postedFlags"] & 0x1E0000 == 0, "activation-pointer-modifiers")
        signature.append({"eventType": row["eventType"], "location": sources.point(row.get("location"), "activation-pointer-location"),
                          "postedFlags": row["postedFlags"], "eventTap": row["eventTap"], "sourceStateID": row["sourceStateID"]})
    geometry = case["targetGeometry"]
    anchors = {0: case["sourceGeometry"]["sourcePoint"], 18: point_string(geometry.get("entryInTopPadding")),
               36: point_string(geometry.get("outside")), 54: point_string(geometry.get("entryInTopPadding")),
               55: point_string(geometry.get("escapeMotionPoint")), 56: point_string(geometry.get("releasePoint"))}
    capture.require(all(signature[index]["location"] == location for index, location in anchors.items()),
                    "activation-pointer-geometry-binding")
    return {"inputSource": source, "escapeKeyProtocol": case["escapeKeyProtocol"], "cancelPointerEvents": signature}


def raise_requests(case, case_name, clock, result):
    policy = bindings(case_name)["targetRaisePolicy"]
    requests = case.get("targetRaiseRequests")
    expected_phases = RAISE_PHASES + (["focus-native-source"] if result["axOutcome"] == "captured" else [])
    capture.require(isinstance(requests, list) and len(requests) == len(expected_phases), "target-raise-journal-count")
    previous = -1
    for index, (request, phase) in enumerate(zip(requests, expected_phases)):
        capture.fields_match(request, {"requestIndex": index, "phase": phase, "targetRaisePolicy": policy,
            "performed": policy == "present", "status": 0 if policy == "present" else None,
            "targetPID": case["targetApplicationPID"], "targetWindowTitle": "Native Drag Control", "mouseDownSent": False},
            "target-raise-journal-binding")
        started = sources.finite(request.get("startedSystemUptime"), "target-raise-journal-clock")
        completed = sources.finite(request.get("completedSystemUptime"), "target-raise-journal-clock")
        capture.require(previous <= started <= completed, "target-raise-journal-order")
        previous = completed
        if index < 4:
            capture.require(completed < clock["dragDownBeforePost"], "target-raise-during-cancel-gesture")
        else:
            capture.require(clock["releaseAfterPost"] < started <= completed
                            < result["sourceSession"]["freshSession"]["begin"]["callbackSystemUptime"], "target-raise-fresh-order")
        # The explicit decision receipt and the posted button history must agree.
        held_since = None
        for mouse in case["mouseEvents"]:
            if mouse["eventType"] == 1:
                held_since = mouse["systemUptimeBeforePost"]
            elif mouse["eventType"] == 2 and held_since is not None:
                capture.require(completed < held_since or started > mouse["systemUptimeAfterPost"],
                                "target-raise-overlaps-owned-button")
                held_since = None
    return requests


def event_clock(row):
    value = row.get("callbackSystemUptime", row["systemUptime"])
    value = sources.finite(value, "activation-callback-clock")
    capture.require(value <= row["systemUptime"], "activation-callback-after-emission")
    return value


def window_state(row, label):
    capture.require(type(row.get("applicationActive")) is bool, label + "-active-state")
    for key in ("keyWindowNumber", "mainWindowNumber", "windowNumber"):
        capture.require(key in row and (row[key] is None or type(row[key]) is int and row[key] > 0), label + "-window-number")
    for key in STATE_BOOLEANS:
        capture.require(key in row and (row[key] is None if row["windowNumber"] is None else type(row[key]) is bool),
                        label + "-window-state")
    sources.point(row.get("observedCursorScreen"), label + "-cursor")
    capture.fields_match(row, {"cursorCoordinateSpace": "AppKit-screen-bottom-left"}, label + "-coordinate-space")
    return {"systemUptime": event_clock(row), "event": row["event"],
            "observedCursorScreen": row["observedCursorScreen"], "cursorCoordinateSpace": row["cursorCoordinateSpace"],
            **{key: row[key] for key in ("applicationActive", "keyWindowNumber", "mainWindowNumber", "windowNumber", *STATE_BOOLEANS)}}


def paired_events(rows, requests, clock):
    open_pairs, completed, used = {}, [], set()
    for row in rows:
        family = next((name for name in ("target-ax-raise", "appkit-defined", "target-mouse")
                       if row["event"] in (name + "-enter", name + "-return")), None)
        if family is None:
            continue
        key_name = "raiseIndex" if family == "target-ax-raise" else "dispatchIndex"
        index = row.get(key_name)
        capture.require(type(index) is int and 0 <= index < 16_384, "activation-pair-index")
        key = ("raise" if family == "target-ax-raise" else "dispatch", index)
        capture.require("callbackSystemUptime" in row, "activation-pair-callback-clock")
        if family != "target-ax-raise":
            capture.require(type(row.get("eventWindowNumber")) is int and row["eventWindowNumber"] >= 0,
                            "activation-dispatch-window")
            sources.finite(row.get("eventTimestamp"), "activation-dispatch-timestamp")
            if family == "appkit-defined":
                capture.fields_match(row, {"eventType": 13}, "activation-appkit-event-type")
                capture.require(type(row.get("eventSubtype")) is int, "activation-appkit-subtype")
            else:
                capture.require(type(row.get("eventType")) is int and row["eventType"] in (1, 2, 6), "activation-mouse-type")
                capture.require(type(row.get("modifierFlags")) is int and row["modifierFlags"] >= 0, "activation-mouse-flags")
                sources.point(row.get("locationInWindow"), "activation-mouse-location")
        if row["event"].endswith("-enter"):
            capture.require(key not in used, "activation-pair-reused")
            used.add(key)
            open_pairs[key] = (family, row)
        else:
            capture.require(key in open_pairs, "activation-pair-return-without-entry")
            entered_family, entered = open_pairs.pop(key)
            capture.require(entered_family == family and event_clock(entered) <= event_clock(row), "activation-pair-order")
            if family == "target-ax-raise":
                capture.require(type(row.get("actionTriggered")) is bool, "activation-raise-return-value")
            else:
                fields = ("eventType", "eventTimestamp", "eventWindowNumber")
                fields += ("eventSubtype",) if family == "appkit-defined" else ("modifierFlags", "locationInWindow")
                capture.require(all(entered[k] == row[k] for k in fields), "activation-pair-event-changed")
            overlaps = [r["requestIndex"] for r in requests if r["performed"]
                        and r["startedSystemUptime"] <= event_clock(entered) <= r["completedSystemUptime"]]
            completed.append({"kind": family, "index": index, "enter": entered, "return": row,
                "overlappingObserverRequestIndices": overlaps if family == "target-ax-raise" else [],
                "enteredDuringCancelDrag": clock["dragDownBeforePost"] <= event_clock(entered) <= clock["releaseAfterPost"]})
    capture.require(not open_pairs, "activation-pair-incomplete")
    return completed


def state_at(states, clock):
    before = [r for r in states if r["systemUptime"] <= clock]
    return max(before, key=lambda r: r["systemUptime"]) if before else None


def activation_analysis(stage, context, case_name, case, result, requests):
    directory = evidence_for(stage, case_name) / "orchard"
    rows = sources.read_trace(directory / "activation.jsonl", "activation", case["targetApplicationPID"])
    expected = bindings(case_name)
    for row in rows:
        capture.fields_match(row, expected, "activation-trace-binding")
        capture.require(row["event"] in ACTIVATION_EVENTS, "activation-trace-event")
        event_clock(row)
    starts = [r for r in rows if r["event"] == "activation-start"]
    ready = [r for r in rows if r["event"] == "activation-ready"]
    ends = [r for r in rows if r["event"] == "activation-terminating"]
    capture.require(len(starts) == len(ready) == len(ends) == 1 and rows[0] == starts[0] and rows[-1] == ends[0],
                    "activation-trace-lifecycle")
    source_keys = ("nativeDragControlSourceSHA256", "controlGUI_SHA256", "observerExperimentCommit", "observerExperimentTree",
                   "sourceCommit", "sourceTree", "architecture")
    capture.fields_match(starts[0], {**{k: context["provenance"][k] for k in source_keys},
        "bundleIdentifier": "app.lemulip.NativeDragControl", "executableName": "NativeDragControl", "bundleName": "Native Drag Control.app",
        "targetBundlePath": str(stage / "Native Drag Control.app"), "stagingRoot": str(stage),
        "originalSHA256": context["fixtures"]}, "activation-start-identity")
    capture.fields_match(ready[0], {"windowTitle": "Native Drag Control", "normalNSWindow": True,
                                   "windowClass": "NSWindow"}, "activation-window-kind")
    capture.fields_match(ready[0], {"targetAXRaiseOverrideInstalled": False,
        "targetRaiseObservation": "observer-request-ledger-only"}, "activation-raise-observation-policy")
    capture.require(not any(row["event"] in ("target-ax-raise-enter", "target-ax-raise-return") for row in rows),
                    "activation-raise-hook-contradiction")
    capture.require(type(ready[0].get("styleMask")) is int and ready[0]["styleMask"] >= 0
                    and type(ready[0].get("windowLevel")) is int, "activation-window-policy")
    clock = result["escapePostTiming"]
    capture.require(event_clock(ready[0]) < clock["dragDownBeforePost"], "activation-ready-after-input")
    capture.fields_match(ends[0], {"originalBytesUnchanged": True, "fixtureFileSetUnchanged": True}, "activation-termination-originals")
    target_states = [window_state(row, "activation") for row in rows]
    capture.require(type(ready[0]["windowNumber"]) is int and ready[0]["windowVisible"] is True, "activation-ready-window")
    target_number = ready[0]["windowNumber"]
    capture.require(all(r["windowNumber"] in (None, target_number) for r in rows), "activation-window-identity-changed")
    for row in rows:
        for key in ("originalBytesUnchanged", "fixtureFileSetUnchanged"):
            if key in row:
                capture.require(row[key] is True, "activation-originals-changed")
        if row["event"] in WINDOW_EVENTS | {"application-became-active", "application-resigned-active"}:
            capture.require("callbackSystemUptime" in row, "activation-lifecycle-callback-clock")
    pairs = paired_events(rows, requests, clock)
    source_rows = sources.read_trace(directory / "source.jsonl", "activation-source", case["sourceApplicationPID"])
    source_ready = next(r for r in source_rows if r["event"] == "source-ready")
    source_number = source_ready.get("windowNumber")
    capture.require(type(source_number) is int and source_number > 0, "activation-source-own-window")
    initial = result["sourceSession"]["cancelSession"]["begin"]
    capture.fields_match(initial, {"applicationActive": True, "keyWindowNumber": source_number,
                                  "windowNumber": source_number, "windowIsKey": True}, "activation-source-not-initially-focused")
    source_states = []
    state_events = sources.CALLBACKS | WINDOW_EVENTS | {"source-ready", "application-became-active", "application-resigned-active"}
    for row in source_rows:
        if row["event"] in state_events:
            source_states.append(window_state(row, "activation-source"))
            if row["event"] in WINDOW_EVENTS | {"application-became-active", "application-resigned-active"}:
                capture.require("callbackSystemUptime" in row, "activation-source-lifecycle-clock")
    source_before = state_at(source_states, clock["downStartedSystemUptime"])
    target_before = state_at(target_states, clock["downStartedSystemUptime"])
    escape_states = ([source_before] if source_before else []) + [r for r in source_states
        if clock["downStartedSystemUptime"] < r["systemUptime"] <= clock["upCompletedSystemUptime"]]
    source_retained = bool(escape_states) and all(r["applicationActive"] and r["keyWindowNumber"] == source_number
                                                 and r["windowIsKey"] for r in escape_states)
    held_active = [r for r in target_states if r["applicationActive"]
                   and clock["dragDownBeforePost"] <= r["systemUptime"] <= clock["releaseAfterPost"]]
    became_active = [r for r in held_active if r["event"] == "application-became-active"]
    source_lost = [r for r in source_states if r["event"] in ("application-resigned-active", "window-resigned-key")
                   and clock["dragDownBeforePost"] <= r["systemUptime"] <= clock["releaseAfterPost"]]
    raises = [p for p in pairs if p["kind"] == "target-ax-raise"]
    omitted = expected["targetRaisePolicy"] == "omitted"
    return {"activationSHA256": capture.sha256(directory / "activation.jsonl"), "traceComplete": True,
        "recordCount": len(rows), "targetWindowClass": ready[0]["windowClass"], "targetWindowNumber": target_number,
        "targetWindowPolicy": {key: ready[0][key] for key in
            ("windowClass", "normalNSWindow", "styleMask", "windowLevel", "windowCanBecomeKey", "windowCanBecomeMain",
             "targetAXRaiseOverrideInstalled", "targetRaiseObservation")},
        "initialSourceActiveAndKey": True, "sourceWindowNumber": source_number,
        "intentionalOmissionVerified": omitted, "observerTargetRaiseDispatchCount": sum(r["performed"] for r in requests),
        "targetAXRaiseCallbackCount": len(raises), "targetAXHookCoverage": "not-installed",
        "targetRaiseReceiptInOmittedCase": omitted and bool(raises), "pairs": pairs,
        "targetStateBeforeEscape": target_before, "sourceStateBeforeEscape": source_before,
        "sourceActiveKeyReceiptsThroughEscape": source_retained, "targetActiveReceiptsDuringHeldDrag": held_active,
        "targetBecameActiveDuringHeldDrag": became_active, "sourceResignOrKeyLossDuringHeldDrag": source_lost,
        "sourceStateReceipts": source_states, "targetStateReceipts": target_states,
        "interpretation": "The target is a plain NSWindow without an AXRaise override. The observer journal records its own intentional AXRaise dispatch or omission; status 0 does not prove action completion. Target AXRaise callbacks are not instrumented, and no claim is made about every raising/activation path. An active snapshot before dispatch can precede deactivation and is not by itself a new activation. Process-local transition/key receipts and strict drag outcomes remain separate."}


def retain_invalid_evidence(result, error, scope):
    reason = str(error) if isinstance(error, capture.ComparisonError) else type(error).__name__
    result.setdefault("strictNativeOutcome", {"outcome": result["outcome"], "passed": result["passed"],
                                             "axOutcome": result["axOutcome"], "returnCode": result["returnCode"]})
    result.update(outcome="not-comparable", passed=False, mayContinue=False, reasonCode=reason,
                  evidenceIssueScope=scope, passiveEvidenceInvalid=scope == "passive-activation")
    return result


def classify(stage, context, case_name, returncode):
    result = sources.classify(stage, context, case_name, returncode, comparison="activation")
    scope = "observer-protocol"
    try:
        case = capture.read_json(evidence_for(stage, case_name) / "orchard/report.json")
        clock = result["escapePostTiming"]
        requests = raise_requests(case, case_name, clock, result)
        result.update(targetRaiseRequests=requests, inputProtocolSignature=input_signature(case, clock))
        scope = "passive-activation"
        result["activationEvidence"] = activation_analysis(stage, context, case_name, case, result, requests)
    except Exception as error:
        return retain_invalid_evidence(result, error, scope)
    return result


def comparison_observations(results, complete):
    observed = [r for r in results if "activationEvidence" in r]
    raised = [r for r in observed if r["targetRaisePolicy"] == "present"]
    omitted = [r for r in observed if r["targetRaisePolicy"] == "omitted"]
    unexpected = [r["activationCase"] for r in omitted if r["activationEvidence"]["targetRaiseReceiptInOmittedCase"]]
    contrast = complete and not unexpected and all(r["activationEvidence"]["targetBecameActiveDuringHeldDrag"] for r in raised) \
        and all(not r["activationEvidence"]["targetBecameActiveDuringHeldDrag"]
                and r["activationEvidence"]["sourceActiveKeyReceiptsThroughEscape"] for r in omitted)
    return {"activationContrastObserved": contrast, "omittedCasesWithTargetRaiseReceipts": unexpected,
        "functionalOutcomesByPolicy": {policy: [{"case": r["activationCase"], "axOutcome": r["axOutcome"],
            "sourceClassification": r["sourceSession"]["classification"]} for r in observed if r["targetRaisePolicy"] == policy]
            for policy in ("present", "omitted")},
        "causalConclusion": "not-established",
        "interpretation": "This fixed four-case comparison tests observer-owned target AXRaise necessity. The reported activation contrast requires target became-active transitions during the held drag in both present cases, no such transition and retained source active/key receipts through Escape in both omitted cases. Initial target startup/open activation remains in both arms. A safe native outcome is retained even when activation or AX hook evidence does not establish the intended contrast; intermittent outcomes do not prove a causal repair."}


def compare(stage, output, context, runner=capture.run_observer):
    capture.require(not output.exists() and not output.is_symlink(), "output-already-exists")
    capture.require(all(not evidence_for(stage, name).exists() and not evidence_for(stage, name).is_symlink() for name in CASES),
                    "evidence-already-exists")
    output.mkdir(parents=False, exist_ok=False)
    capture.write_json(output / "inputs-before.json", context["inputs"])
    results, stopped, shared = [], None, None
    for case_name in CASES:
        identity = {"target": "control", **bindings(case_name), "observerLifecycle": "appkit", "captureComparison": POLICY}
        if stopped:
            results.append({**identity, "outcome": "not-run", "reasonCode": stopped})
            continue
        returncode, result = None, None
        try:
            capture.require(sources.input_snapshot(stage) == context["inputs"], "inputs-changed-before-case")
            command = [str(stage / "NativeDragReviewAppKit"), str(stage), "--control", "--compare-capture", POLICY,
                       "--compare-activation", case_name]
            returncode = runner(command, output / (case_name + ".log"))
            capture.require(sources.input_snapshot(stage) == context["inputs"], "inputs-changed-after-case")
            result = classify(stage, context, case_name, returncode)
            result["inputsUnchanged"] = True
            if result["mayContinue"] is not True:
                results.append(result)
                stopped = result["reasonCode"]
                continue
            signature = {"geometry": result["geometrySignature"], "input": result["inputProtocolSignature"],
                         "sourceGeometry": result["sourceGeometry"],
                         "windowPolicy": result["activationEvidence"]["targetWindowPolicy"]}
            if shared is None:
                shared = signature
            capture.require(signature == shared, "activation-shared-protocol-changed")
            results.append(result)
        except Exception as error:
            stopped = str(error) if isinstance(error, capture.ComparisonError) else type(error).__name__
            if result is not None:
                results.append(retain_invalid_evidence(result, error, "shared-protocol"))
            else:
                results.append({**identity, "outcome": "not-comparable", "returnCode": returncode,
                                "reasonCode": stopped, "mayContinue": False})
    try:
        after = sources.input_snapshot(stage)
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
        "dragSourceKind": "native-appkit", "provenance": context["provenance"], "fixtureHashes": context["fixtures"], "cases": results,
        "activationComparison": comparison_observations(results, complete),
        "scope": "Four serial Orchard control cases with one fixed native source and unchanged NSWindow destination; only explicit observer target AXRaise calls are present or deliberately omitted. C12 is built for staging, without production input."}
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
    report = compare(stage, args.output.absolute(), sources.context_for(stage, args.experiment_commit))
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0 if report["allCasesPassed"] else 1


if __name__ == "__main__":
    sys.exit(main())
