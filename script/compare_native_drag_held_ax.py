"""Compare held-drag observer AX reads with explicit omissions in fixed slots."""
import argparse
import json
import math
from pathlib import Path
import platform
import sys

import compare_native_drag_activation as activation
import compare_native_drag_capture as capture
import compare_native_drag_sources as sources

CASES = sources.HELD_AX_CASES
POLICY = "ax-only"
SLOT_SECONDS = 0.25
CANCEL_SLOTS = (
    "capture:01-enter-top-padding", "capture:02-leave-file-area",
    "capture:03-reenter-top-padding", "escape-observation:before-key",
    "escape-observation:after-key-held", "capture:diagnostic-after-escape-held",
)
FRESH_SLOT = "capture:05-before-accepted-drop"
HELD_CAPTURES = {name.split(":", 1)[1] for name in (*CANCEL_SLOTS, FRESH_SLOT)
                 if name.startswith("capture:")}


def bindings(case_name):
    capture.require(case_name in CASES, "unknown-held-ax-case")
    return activation.bindings(case_name)


def evidence_for(stage, case_name):
    bindings(case_name)
    return activation.evidence_for(stage, case_name)


def context_for(stage, experiment_commit):
    context = sources.context_for(stage, experiment_commit)
    capture.require(context["provenance"].get("heldAXComparatorSourceSHA256")
                    == capture.sha256(Path(__file__)), "held-ax-comparator-source-link")
    return context


def workspace(value, context, expected, observed=None):
    """Require the full workspace observation, including duplicate-row counts."""
    observed = expected if observed is None else observed
    expected, observed = sorted(expected), sorted(observed)
    capture.fields_match(value, {
        "expectedFilenames": expected, "observedFilenames": observed,
        "matchesExpectedWorkspace": expected == observed,
        "expectedSelectedCountLabel": f"{len(expected)} Selected",
        "expectedSelectedCountMatches": 1 if expected == observed else 0,
        "selectedCountLabels": [f"{len(observed)} Selected"],
        "fixtureRemoveButtonCounts": {name: int(name in observed) for name in context["fixtures"]},
    }, "held-ax-workspace-incomplete")


def observation_clock(row, start_key, end_key):
    started = sources.finite(row.get(start_key), "held-ax-observation-clock")
    completed = sources.finite(row.get(end_key), "held-ax-observation-clock")
    capture.require(started <= completed, "held-ax-observation-order")
    return started, completed


def held_evidence(stage, context, case_name, case, result):
    expected = bindings(case_name)
    policy = expected["heldAXPolicy"]
    capture.fields_match(case, {**expected, "heldAXSlotSeconds": SLOT_SECONDS}, "held-ax-case-binding")
    capture.fields_match(capture.read_json(evidence_for(stage, case_name) / "report.json"),
                         {"heldAXSlotSeconds": SLOT_SECONDS}, "held-ax-aggregate-slot-policy")
    clock = result["escapePostTiming"]
    directory = evidence_for(stage, case_name) / "orchard"
    existing = context["roles"]["Existing"]
    single = context["roles"]["Single"]

    initial = case.get("heldAXInitialWorkspace")
    capture.require(isinstance(initial, dict), "held-ax-initial-workspace-missing")
    initial_started, initial_completed = observation_clock(initial, "startedSystemUptime", "completedSystemUptime")
    capture.require(initial_completed < clock["dragDownBeforePost"], "held-ax-initial-workspace-after-down")
    workspace(initial.get("workspace"), context, [existing])
    workspace(case.get("escapeCancellation"), context, [existing],
              [existing] if result["axOutcome"] == "captured" else [existing, single])

    observations = case.get("escapeObservations")
    capture.require(isinstance(observations, list)
                    and [o.get("phase") for o in observations] == ["before-key", "after-key-held"],
                    "held-ax-key-observation-set")
    observed_clocks = {}
    for row in observations:
        capture.fields_match(row, {"heldAXPolicy": policy,
            "status": "omitted" if policy == "omitted" else "observed"}, "held-ax-key-observation-policy")
        observed_clocks["escape-observation:" + row["phase"]] = observation_clock(
            row, "startedSystemUptime", "completedSystemUptime")
        if policy == "omitted":
            capture.require(not any(key in row for key in ("workspace", "focusedUIElement")),
                            "held-ax-omitted-key-fabricates-observation")
        else:
            workspace(row.get("workspace"), context, [existing])
            capture.require(isinstance(row.get("focusedUIElement"), dict), "held-ax-focus-observation-missing")

    snapshots = [case.get("setupSnapshot", {}), *case.get("stages", []), *case.get("diagnosticSnapshots", [])]
    names = [row.get("stage") for row in snapshots]
    capture.require(len(names) == len(set(names)), "held-ax-duplicate-snapshot")
    first_snapshot = next(row for row in snapshots if row["stage"] == "00-before-drag")
    capture.require(first_snapshot["captureCompletedSystemUptime"] <= initial_started,
                    "held-ax-initial-snapshot-order")
    for row in snapshots:
        name = row["stage"]
        capture.require(isinstance(name, str) and name.replace("-", "").isalnum(), "held-ax-snapshot-name")
        capture.require(capture.read_json(directory / (name + ".json")) == row, "held-ax-snapshot-report-mismatch")
        held = name in HELD_CAPTURES
        capture.fields_match(row, {"mouseDownSent": held}, "held-ax-snapshot-button-state")
        if held:
            capture.fields_match(row, {"leftButtonReportedDown": True}, "held-ax-snapshot-unheld")
            observed_clocks["capture:" + name] = observation_clock(
                row, "captureStartedSystemUptime", "captureCompletedSystemUptime")
            if policy == "omitted":
                capture.require("workspaceAXLabels" not in row, "held-ax-omitted-snapshot-fabricates-labels")
        elif name in ("04-after-escape", "06-after-accepted-drop"):
            capture.require(row["captureStartedSystemUptime"] >= clock["releaseAfterPost"],
                            "held-ax-final-snapshot-before-release")

    slots = case.get("heldAXSlots")
    expected_slots = list(CANCEL_SLOTS) + ([FRESH_SLOT] if result["axOutcome"] == "captured" else [])
    capture.require(isinstance(slots, list) and [r.get("stage") for r in slots] == expected_slots,
                    "held-ax-slot-set")
    previous = -1
    timing = []
    for index, row in enumerate(slots):
        capture.fields_match(row, {"slotIndex": index, "policy": policy, "requestedSeconds": SLOT_SECONDS,
                                   "operationWithinBudget": True}, "held-ax-slot-policy")
        started, completed = observation_clock(row, "startedSystemUptime", "completedSystemUptime")
        operation_end = sources.finite(row.get("operationCompletedSystemUptime"), "held-ax-slot-clock")
        scheduled_end = sources.finite(row.get("scheduledEndSystemUptime"), "held-ax-slot-clock")
        capture.require(previous <= started <= operation_end <= scheduled_end <= completed,
                        "held-ax-slot-order-or-overrun")
        capture.require(math.isclose(scheduled_end - started, SLOT_SECONDS, rel_tol=0, abs_tol=1e-6),
                        "held-ax-slot-duration-changed")
        previous = completed
        observed_start, observed_end = observed_clocks[row["stage"]]
        capture.require(started <= observed_start <= observed_end <= operation_end,
                        "held-ax-slot-observation-unbound")
        if row["stage"] == FRESH_SLOT:
            fresh = result["sourceSession"]["freshSession"]["begin"]["callbackSystemUptime"]
            fresh_release = result["receiver"]["freshDrop"]["releaseBeforePost"]
            capture.require(fresh <= started <= completed <= fresh_release, "held-ax-fresh-slot-outside-gesture")
        else:
            capture.require(clock["dragDownAfterPost"] <= started <= completed <= clock["releaseBeforePost"],
                            "held-ax-slot-outside-gesture")
        if row["stage"] == "escape-observation:before-key":
            capture.require(completed <= clock["downStartedSystemUptime"], "held-ax-before-key-slot-order")
        if row["stage"] == "escape-observation:after-key-held":
            capture.require(clock["upCompletedSystemUptime"] <= started, "held-ax-after-key-slot-order")
        timing.append({"stage": row["stage"], "requestedSeconds": SLOT_SECONDS,
            "operationSeconds": operation_end - started, "actualSlotSeconds": completed - started,
            "wakeOvershootSeconds": completed - scheduled_end})

    reads = case.get("heldAXReads")
    capture.require(isinstance(reads, list) and len(reads) <= 8_192, "held-ax-read-journal-missing-or-bound")
    capture.fields_match(case, {"heldAXReadCount": len(reads), "heldAXReadGuardViolations": []},
                         "held-ax-read-journal-count-or-violation")
    capture.require((not reads) if policy == "omitted" else bool(reads), "held-ax-read-policy-contradiction")
    read_counts = {name: 0 for name in expected_slots}
    previous = -1
    for index, row in enumerate(reads):
        capture.fields_match(row, {"readIndex": index}, "held-ax-read-index")
        capture.require(isinstance(row.get("attribute"), str) and 0 < len(row["attribute"]) <= 128,
                        "held-ax-read-attribute")
        capture.require(type(row.get("status")) is int and row["status"] in (0, -25205, -25212),
                        "held-ax-read-error-in-completed-case")
        started, completed = observation_clock(row, "startedSystemUptime", "completedSystemUptime")
        capture.require(previous <= started, "held-ax-read-order")
        previous = completed
        matched = [slot for slot in slots if slot["startedSystemUptime"] <= started
                   <= completed <= slot["operationCompletedSystemUptime"]]
        capture.require(len(matched) == 1, "held-ax-read-outside-observation-slot")
        read_counts[matched[0]["stage"]] += 1
    if policy == "present":
        capture.require(all(count > 0 for count in read_counts.values()), "held-ax-present-slot-without-reads")
    return {"policy": policy, "readCount": len(reads), "readCountsBySlot": read_counts,
        "guardViolations": [], "slotCount": len(slots), "slots": slots, "slotTimings": timing,
        "cancelSlotSignature": [{"stage": name, "requestedSeconds": SLOT_SECONDS} for name in CANCEL_SLOTS],
        "cancelHeldSeconds": clock["releaseBeforePost"] - clock["dragDownAfterPost"],
        "cancelDownToEscapeSeconds": clock["downStartedSystemUptime"] - clock["dragDownAfterPost"],
        "initialWorkspaceObservedBeforeInput": True, "omissionsExplicit": policy == "omitted",
        "interpretation": "During the experiment body the observer records attempted attribute reads through its guarded read helper. Quiet observations contain no fabricated AX labels or focus data. Fixed 0.25-second slots are nominally identical; actual wake times and durations remain recorded, not claimed identical. This schedule differs from D11. Source/target callback journals and other non-AX work remain common. Incomplete or failed cleanup blocks the case."}


def failure_result(stage, case_name, returncode, error):
    reason = str(error) if isinstance(error, capture.ComparisonError) else type(error).__name__
    result = {"target": "control", **bindings(case_name), "observerLifecycle": "appkit", "captureComparison": POLICY,
        "outcome": "not-comparable", "passed": False, "returnCode": returncode, "reasonCode": reason, "mayContinue": False}
    try:
        raw = capture.read_json(evidence_for(stage, case_name) / "orchard/report.json")
        result["observerFailure"] = {key: raw[key] for key in ("status", "reason", "startupPhase", "cleanup",
            "heldAXSlots", "heldAXReadCount", "heldAXReadGuardViolations") if key in raw}
        # These fields are unvalidated diagnostics, never acceptance evidence.
        # Keep a malformed number legible without making the failure report
        # itself unwritable. The original raw evidence remains untouched.
        result["observerFailure"] = json.loads(json.dumps(result["observerFailure"]),
            parse_constant=lambda value: "invalid-number:" + value)
        result["cleanupComplete"] = capture.cleanup_complete(raw.get("cleanup")) and all(
            raw["cleanup"].get(key) is True for key in ("sourceApplicationStopped", "sourceBundleRegistryEmpty"))
        result["reportRetained"] = True
    except Exception:
        result["reportRetained"] = False
    return result


def classify(stage, context, case_name, returncode):
    bindings(case_name)
    try:
        result = activation.classify(stage, context, case_name, returncode)
    except Exception as error:
        return failure_result(stage, case_name, returncode, error)
    if result.get("mayContinue") is not True:
        return result
    try:
        case = capture.read_json(evidence_for(stage, case_name) / "orchard/report.json")
        result["heldAXEvidence"] = held_evidence(stage, context, case_name, case, result)
    except Exception as error:
        return activation.retain_invalid_evidence(result, error, "held-ax-protocol")
    return result


def comparison_observations(results, complete):
    observed = [r for r in results if r.get("mayContinue") is True and "heldAXEvidence" in r]
    quiet = [r for r in observed if r["heldAXPolicy"] == "omitted"]
    read = [r for r in observed if r["heldAXPolicy"] == "present"]
    quiet_failures = [r for r in quiet if r["axOutcome"] == "escape-cancellation-failed"
                      and r["sourceSession"]["classification"] == "accepted-after-release"]
    activated_failures = [r for r in quiet_failures if r["activationEvidence"]["targetBecameActiveDuringHeldDrag"]]
    contrast = bool(complete and len(quiet) == len(read) == 2
        and all(r["axOutcome"] == "escape-cancellation-failed"
                and r["activationEvidence"]["targetBecameActiveDuringHeldDrag"] for r in read)
        and all(r["passed"] is True and not r["activationEvidence"]["targetBecameActiveDuringHeldDrag"]
                and r["activationEvidence"]["sourceActiveKeyReceiptsThroughEscape"] for r in quiet))
    return {"quietCasesWithCancellationFailure": [r["heldAXCase"] for r in quiet_failures],
        "quietCasesWithActivationAndCancellationFailure": [r["heldAXCase"] for r in activated_failures],
        "observerHeldAXNecessaryForObservedCancellationFailure": False if quiet_failures else None,
        "observerHeldAXNecessaryForObservedActivationAndFailure": False if activated_failures else None,
        "activationAndFunctionalContrastObserved": contrast,
        "causalConclusion": "observer-held-ax-not-necessary" if activated_failures else "not-established",
        "functionalOutcomesByPolicy": {policy: [{"case": r["heldAXCase"], "axOutcome": r["axOutcome"],
            "readCount": r["heldAXEvidence"]["readCount"],
            "sourceClassification": r["sourceSession"]["classification"]}
            for r in observed if r["heldAXPolicy"] == policy] for policy in ("present", "omitted")},
        "interpretation": "A quiet case with zero observer held AX reads, target activation and first-session acceptance falsifies necessity of those reads for that observed failure under this D12 schedule. All-pass or mixed results do not prove a repair or establish behavior at D11 timing. A read-fail/quiet-pass contrast supports sensitivity to the intervention, while actual timing, pre-drag AX, receiver/source instrumentation and other activation paths remain distinct."}


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
            if result.get("mayContinue") is not True:
                results.append(result)
                stopped = result["reasonCode"]
                continue
            signature = {"geometry": result["geometrySignature"], "input": result["inputProtocolSignature"],
                "sourceGeometry": result["sourceGeometry"], "windowPolicy": result["activationEvidence"]["targetWindowPolicy"],
                "cancelSlots": result["heldAXEvidence"]["cancelSlotSignature"]}
            if shared is None:
                shared = signature
            capture.require(signature == shared, "held-ax-shared-protocol-changed")
            results.append(result)
        except Exception as error:
            stopped = str(error) if isinstance(error, capture.ComparisonError) else type(error).__name__
            results.append(activation.retain_invalid_evidence(result, error, "shared-protocol") if result is not None
                           else failure_result(stage, case_name, returncode, error))
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
        "dragSourceKind": "native-appkit", "targetRaisePolicy": "present", "observationSlotSeconds": SLOT_SECONDS,
        "provenance": context["provenance"], "fixtureHashes": context["fixtures"], "cases": results,
        "heldAXComparison": comparison_observations(results, complete),
        "scope": "Four fixed native-source/control cases: held AX read, quiet, quiet, read. Target raises remain present, initial/final AX acceptance and separate fresh drop remain required. Fixed nominal observation slots preserve omitted work time; recorded scheduling differences are not claimed identical."}
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
