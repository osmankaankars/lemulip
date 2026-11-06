"""Compare receiver trace synchronization in the fixed Quartz drag protocol.

The native classifier is shared with D13.  Synchronization receipts are an
additional validity gate, never a substitute for native cancellation and a
distinct successful fresh drop.  This diagnostic cannot release C12.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import platform
import stat
import sys

import compare_native_drag_capture as capture
import compare_native_drag_mouse_driver as mouse
import compare_native_drag_sources as sources

CASES = mouse.RECEIVER_SYNC_CASES
PLAN = [{"case": name, "mouseProducer": "quartz",
         "receiverTraceSyncPolicy": mouse.RECEIVER_SYNC_POLICIES[name], "runnerMode": "idle"}
        for name in CASES]
MAXIMUM_RECORD_COUNT = 10_000
MAXIMUM_TRACE_BYTES = 8_388_608


def policy_for(case_name):
    capture.require(case_name in CASES, "receiver-sync-unknown-case")
    return mouse.RECEIVER_SYNC_POLICIES[case_name]


def diagnostic_metadata():
    """One declaration shared by staging, execution and retained-artifact checks."""
    return {"receiverSyncComparatorSourceSHA256": capture.sha256(Path(__file__)),
        "receiverSyncDiagnostic": {"schema": 1, "casePlan": copy.deepcopy(PLAN),
            "receiverCompileDefines": ["LEMULIP_RECEIVER_SYNC_TRACE"],
            "recordWritePolicy": "immediate", "synchronizationAPI": "FileHandle.synchronize",
            "lifecycleSynchronizationPhase": "termination", "perRecordInstrumentation": "buffered-uptime-receipts",
            "heldReceiverFixtureChecks": "unchanged", "dispatchStackCaptureEnabled": False,
            "systemLogCollectionEnabled": False, "productionAcceptanceCoverage": False},
        "receiverSyncControlBuild": {"executable": "Native Drag Control.app/Contents/MacOS/NativeDragControl",
            "swiftDefines": ["LEMULIP_RECEIVER_SYNC_TRACE"]},
        "receiverSyncProtocol": {"parentCommit": "bfd28a169b8c8ee0f2c1a4514526a01cc1572ca8",
            "gestureBaselineCommit": "d69f6b344a0dc069027f04061686a308dae79ba4",
            "inputProtocol": "D13-R3-fixed-Quartz-single-entry-terminal-hold"}}


def prepare_mouse_driver(stage):
    return {**mouse.prepare_mouse_driver(stage, case_plan=CASES), **diagnostic_metadata()}


def input_snapshot(stage):
    directory = stage / "MouseControl"
    capture.require(directory.is_dir() and not directory.is_symlink(), "receiver-sync-control-directory")
    children = list(directory.iterdir())
    capture.require({path.name for path in children} == set(CASES)
                    and all(path.is_dir() and not path.is_symlink() for path in children),
                    "receiver-sync-runtime-case-plan")
    return mouse.input_snapshot(stage, case_plan=CASES)


def context_policy(context):
    provenance = context.get("provenance")
    capture.require(isinstance(provenance, dict), "receiver-sync-provenance")
    # Canonical JSON also rejects booleans substituted for integer schema
    # values, extra nested fields, changed build flags and reordered plans.
    for key, expected in diagnostic_metadata().items():
        actual = provenance.get(key)
        capture.require(json.dumps(actual, sort_keys=True, allow_nan=False)
                        == json.dumps(expected, sort_keys=True, allow_nan=False), "receiver-sync-provenance-" + key)
    capture.require(set(context.get("mouseConfigurations", {})) == set(CASES), "receiver-sync-configuration-case-plan")


def context_for(stage, experiment_commit):
    context = mouse.context_for(stage, experiment_commit, case_plan=CASES)
    context_policy(context)
    context["inputs"] = input_snapshot(stage)
    return context


def exact_fields(value, fields, label):
    capture.require(isinstance(value, dict) and set(value) == set(fields), label + "-fields")


def trace_bytes(path, label, maximum):
    information = path.lstat()
    capture.require(stat.S_ISREG(information.st_mode) and 0 < information.st_size <= maximum, label + "-file")
    data = path.read_bytes()
    capture.require(len(data) == information.st_size and data.endswith(b"\n"), label + "-truncated")
    lines = data.split(b"\n")[:-1]
    capture.require(lines and all(lines), label + "-lines")
    rows = [mouse.decoded_json(line, label) for line in lines]
    capture.require(all(isinstance(row, dict) for row in rows), label + "-records")
    return data, lines, rows


def synchronization_evidence(stage, case_name, native):
    """Validate each successful write and sync against the actual receiver bytes."""
    policy = policy_for(case_name)
    directory = mouse.evidence_for(stage, case_name) / "orchard"
    receiver_data, receiver_lines, receiver = trace_bytes(directory / "receiver.jsonl", "receiver-sync-receiver", MAXIMUM_TRACE_BYTES)
    activation_data, _, activation = trace_bytes(directory / "activation.jsonl", "receiver-sync-activation", 16_777_216)
    receiver_hash, activation_hash = (hashlib.sha256(data).hexdigest() for data in (receiver_data, activation_data))
    capture.require(receiver_hash == native["receiver"]["receiverSHA256"]
                    and activation_hash == native["activation"]["activationSHA256"], "receiver-sync-native-trace-hash")
    capture.require(0 < len(receiver) <= MAXIMUM_RECORD_COUNT, "receiver-sync-record-limit")
    starts = [row for row in activation if row.get("event") == "activation-start"]
    ready = [row for row in activation if row.get("event") == "activation-ready"]
    ends = [row for row in activation if row.get("event") == "activation-terminating"]
    capture.require(len(starts) == len(ready) == len(ends) == 1
                    and activation[0] == starts[0] and activation[-1] == ends[0], "receiver-sync-activation-lifecycle")
    for row in (starts[0], ready[0]):
        capture.require(type(row.get("receiverTraceSynchronizationSchema")) is int
                        and row["receiverTraceSynchronizationSchema"] == 1, "receiver-sync-startup-schema")
    containing = [row for row in activation if "receiverTraceSynchronization" in row]
    capture.require(containing == ends, "receiver-sync-termination-receipt-count")
    end = ends[0]
    receipt = end.get("receiverTraceSynchronization")
    exact_fields(receipt, {"schema", "status", "reasonCode", "receiverSyncCase", "receiverTraceSyncPolicy", "targetPID",
        "traceFileName", "recordWritePolicy", "synchronizationAPI", "maximumRecordCount", "maximumTraceBytes",
        "recordCount", "writtenByteCount", "perRecordSynchronizeCount", "records", "lifecycleSynchronization"},
        "receiver-sync-receipt")
    capture.fields_match(receipt, {"schema": 1, "status": "complete", "reasonCode": None,
        "receiverSyncCase": case_name, "receiverTraceSyncPolicy": policy, "targetPID": native["receiver"]["pid"],
        "traceFileName": "receiver.jsonl", "recordWritePolicy": "immediate", "synchronizationAPI": "FileHandle.synchronize",
        "maximumRecordCount": MAXIMUM_RECORD_COUNT, "maximumTraceBytes": MAXIMUM_TRACE_BYTES,
        "recordCount": len(receiver), "writtenByteCount": len(receiver_data),
        "perRecordSynchronizeCount": len(receiver) if policy == "per-record" else 0}, "receiver-sync-receipt-binding")
    for key in ("schema", "targetPID", "maximumRecordCount", "maximumTraceBytes", "recordCount", "writtenByteCount"):
        mouse.integer(receipt[key], "receiver-sync-receipt-integer-" + key, minimum=1)
    mouse.integer(receipt["perRecordSynchronizeCount"], "receiver-sync-receipt-sync-count")
    records = receipt["records"]
    capture.require(isinstance(records, list) and len(records) == len(receiver), "receiver-sync-write-receipt-count")
    offset, previous_completion = 0, 0.
    for index, (row, line, record) in enumerate(zip(receiver, receiver_lines, records)):
        exact_fields(record, {"recordIndex", "event", "recordSystemUptime", "byteOffset", "byteCount",
            "writeStartedSystemUptime", "writeCompletedSystemUptime", "synchronizeAttempted",
            "synchronizeStartedSystemUptime", "synchronizeCompletedSystemUptime"}, "receiver-sync-write-receipt")
        capture.fields_match(record, {"recordIndex": index, "event": row["event"],
            "recordSystemUptime": row["systemUptime"], "byteOffset": offset, "byteCount": len(line) + 1},
            "receiver-sync-write-byte-binding")
        mouse.integer(record["recordIndex"], "receiver-sync-write-index")
        mouse.integer(record["byteOffset"], "receiver-sync-write-byte-offset")
        mouse.integer(record["byteCount"], "receiver-sync-write-byte-count", minimum=1)
        recorded = sources.finite(record["recordSystemUptime"], "receiver-sync-record-clock")
        started = sources.finite(record["writeStartedSystemUptime"], "receiver-sync-write-start-clock")
        completed = sources.finite(record["writeCompletedSystemUptime"], "receiver-sync-write-complete-clock")
        capture.require(previous_completion <= recorded <= started <= completed, "receiver-sync-write-clock-order")
        if policy == "per-record":
            capture.require(record["synchronizeAttempted"] is True, "receiver-sync-per-record-sync-missing")
            sync_started = sources.finite(record["synchronizeStartedSystemUptime"], "receiver-sync-record-sync-start-clock")
            sync_completed = sources.finite(record["synchronizeCompletedSystemUptime"], "receiver-sync-record-sync-complete-clock")
            capture.require(completed <= sync_started <= sync_completed, "receiver-sync-record-sync-clock-order")
            previous_completion = sync_completed
        else:
            capture.require(record["synchronizeAttempted"] is False
                            and record["synchronizeStartedSystemUptime"] is None
                            and record["synchronizeCompletedSystemUptime"] is None, "receiver-sync-unexpected-per-record-sync")
            previous_completion = completed
        offset += len(line) + 1
    capture.require(offset == len(receiver_data), "receiver-sync-byte-coverage")
    final_sync = receipt["lifecycleSynchronization"]
    exact_fields(final_sync, {"phase", "recordCount", "writtenByteCount", "startedSystemUptime",
        "completedSystemUptime", "succeeded"}, "receiver-sync-lifecycle")
    capture.fields_match(final_sync, {"phase": "termination", "recordCount": len(receiver),
        "writtenByteCount": len(receiver_data), "succeeded": True}, "receiver-sync-lifecycle-binding")
    capture.require(final_sync["succeeded"] is True, "receiver-sync-lifecycle-unsuccessful")
    for key in ("recordCount", "writtenByteCount"):
        mouse.integer(final_sync[key], "receiver-sync-lifecycle-integer-" + key, minimum=1)
    sync_started = sources.finite(final_sync["startedSystemUptime"], "receiver-sync-lifecycle-start-clock")
    sync_completed = sources.finite(final_sync["completedSystemUptime"], "receiver-sync-lifecycle-complete-clock")
    callback = sources.finite(end.get("callbackSystemUptime"), "receiver-sync-termination-callback-clock")
    terminated = sources.finite(end.get("systemUptime"), "receiver-sync-termination-record-clock")
    released = sources.finite(native["gestures"][-1]["releaseObservedSystemUptime"], "receiver-sync-final-release-clock")
    capture.require(receiver[-1]["event"] == "application-terminated"
                    and callback <= records[-1]["recordSystemUptime"]
                    and max(previous_completion, released) <= sync_started <= sync_completed <= terminated,
                    "receiver-sync-lifecycle-clock-order")
    return {"status": "valid", "reasonCode": None, "receiverSyncCase": case_name,
        "receiverTraceSyncPolicy": policy, "receiverSHA256": receiver_hash, "activationSHA256": activation_hash,
        "receipt": receipt,
        "interpretation": "The receipt covers every retained receiver byte and successful FileHandle operation. Record timestamps do not measure callback duration or require an observer read to follow write return or synchronization."}


def error_code(error):
    return str(error) if isinstance(error, capture.ComparisonError) else type(error).__name__


def classify(stage, context, case_name, returncode):
    policy_for(case_name)
    result = mouse.classify(stage, context, case_name, returncode)
    if result.get("comparability") != "comparable":
        result["receiverSyncInstrumentation"] = {"status": "invalid", "reasonCode": "receiver-sync-native-case-incomplete"}
        return result
    try:
        result["receiverSyncInstrumentation"] = synchronization_evidence(stage, case_name, result)
    except Exception as error:
        reason = error_code(error)
        result["receiverSyncInstrumentation"] = {"status": "invalid", "reasonCode": reason}
        result["comparisonStopReasonCode"] = reason
        result["mayContinue"] = False
    return result


def comparison_observations(results, complete):
    valid = [row for row in results if row.get("comparability") == "comparable"
             and row.get("receiverSyncInstrumentation", {}).get("status") == "valid"
             and row.get("inputsUnchanged") is True and row.get("commonInputSignatureMatches") is True]
    by_policy = {policy: [row for row in valid if row["receiverTraceSyncPolicy"] == policy]
                 for policy in ("per-record", "lifecycle")}
    per_record = [row["passed"] for row in by_policy["per-record"]]
    lifecycle = [row["passed"] for row in by_policy["lifecycle"]]
    contrast = complete and len(per_record) == len(lifecycle) == 2 and (
        per_record == [False, False] and lifecycle == [True, True]
        or per_record == [True, True] and lifecycle == [False, False])
    lifecycle_failures = [row["receiverSyncCase"] for row in by_policy["lifecycle"] if row["passed"] is False]
    if not complete:
        conclusion = "incomplete-comparison"
    elif contrast:
        conclusion = "receiver-sync-policy-associated-contrast"
    elif all(row["passed"] for row in valid):
        conclusion = "baseline-failure-not-reproduced"
    elif all(not row["passed"] for row in valid):
        conclusion = "lifecycle-sync-did-not-resolve-failure"
    else:
        conclusion = "mixed-results-no-policy-conclusion"
    direction = None if not contrast else ("lifecycle-passed-per-record-failed" if lifecycle[0]
                                           else "per-record-passed-lifecycle-failed")
    return {"classification": conclusion, "repeatedPolicyContrastObserved": contrast, "contrastDirection": direction,
        "lifecycleFailureCases": lifecycle_failures,
        "perRecordSynchronizationNecessityFalsified": bool(lifecycle_failures),
        "perRecordSynchronizationNecessaryForObservedFailure": False if lifecycle_failures else None,
        "caseOutcomes": {policy: [{"case": row["receiverSyncCase"], "outcome": row["outcome"]}
                                 for row in by_policy[policy]] for policy in by_policy},
        "productionFixEstablished": False, "originalGateCovered": False,
        "interpretation": "A repeated contrast in either direction supports sensitivity to receiver trace synchronization policy in this protocol, not an OS cause or a production fix. A valid lifecycle-policy failure shows per-record synchronization was not necessary for that failure. All-pass and other mixed results establish no fix. The original enter/exit/reentry gate remains uncovered."}


def compare(stage, output, context, runner=capture.run_observer):
    context_policy(context)
    capture.require(not output.exists() and not output.is_symlink(), "output-already-exists")
    capture.require(all(not mouse.evidence_for(stage, name).exists() and not mouse.evidence_for(stage, name).is_symlink()
                        for name in CASES), "evidence-already-exists")
    output.mkdir(parents=False, exist_ok=False)
    capture.write_json(output / "inputs-before.json", context["inputs"])
    results, stopped, signature = [], None, None
    for case_name in CASES:
        identity = {"target": "control", **mouse.bindings(case_name), "observerLifecycle": "appkit", "captureComparison": "ax-only"}
        if stopped:
            results.append({**identity, "outcome": "not-run", "comparability": "not-run", "reasonCode": stopped,
                            "receiverSyncInstrumentation": {"status": "not-run", "reasonCode": stopped}})
            continue
        returncode, result = None, None
        try:
            capture.require(input_snapshot(stage) == context["inputs"], "inputs-changed-before-case")
            capture.require({path.name for path in mouse.runtime_directory(stage, case_name).iterdir()} == {"configuration.json"},
                            "mouse-runtime-not-empty-before-case")
            command = [str(stage / mouse.OBSERVER), str(stage), "--control", "--compare-capture", "ax-only",
                       "--compare-mouse-driver", case_name]
            returncode = runner(command, output / (case_name + ".log"))
            capture.require(input_snapshot(stage) == context["inputs"], "inputs-changed-after-case")
            result = classify(stage, context, case_name, returncode)
            result["inputsUnchanged"] = True
            if result.get("comparability") == "comparable":
                current = result["commonInputSignature"]
                if signature is None:
                    signature = current
                result["commonInputSignatureMatches"] = current == signature
                capture.require(current == signature, "mouse-common-protocol-or-geometry-changed")
            if result.get("mayContinue") is not True:
                stopped = result.get("comparisonStopReasonCode", result.get("reasonCode", "receiver-sync-case-incomplete"))
            results.append(result)
        except Exception as error:
            stopped = error_code(error)
            if result is None:
                result = mouse.failure_result(stage, case_name, returncode, error)
                result["receiverSyncInstrumentation"] = {"status": "invalid", "reasonCode": "receiver-sync-native-case-incomplete"}
            result["comparisonStopReasonCode"] = stopped
            result["mayContinue"] = False
            results.append(result)
    try:
        after = input_snapshot(stage)
        unchanged = after == context["inputs"]
        capture.write_json(output / "inputs-after.json", after)
    except Exception:
        unchanged = False
    native_complete = len(results) == len(CASES) and all(row.get("comparability") == "comparable" for row in results)
    sync_complete = len(results) == len(CASES) and all(row.get("receiverSyncInstrumentation", {}).get("status") == "valid" for row in results)
    complete = native_complete and sync_complete and unchanged and all(row.get("mayContinue") is True for row in results)
    native_passed = native_complete and all(row.get("passed") is True for row in results)
    passed = complete and native_passed
    report = {"schema": 1, "comparisonKind": "receiver-trace-synchronization", "status": "passed" if passed else "failed",
        "diagnosticOnly": True, "releaseReady": False, "nativeAcceptanceXCTestExecuted": False, "physicalInputVerified": False,
        "C12": "HOLD", "comparisonComplete": complete, "nativeComparisonComplete": native_complete,
        "syncInstrumentationComplete": sync_complete, "strictNativeAllCasesPassed": native_passed, "allCasesPassed": passed,
        "inputsUnchanged": unchanged, "sameStagedPaths": True, "captureComparison": "ax-only", "caseOrder": list(CASES),
        "casePlan": copy.deepcopy(PLAN), "observerLifecycle": "appkit", "provenance": context["provenance"],
        "fixtureHashes": context["fixtures"], "cases": results, "receiverSyncComparison": comparison_observations(results, complete),
        "scope": "One fixed per-record/lifecycle/lifecycle/per-record receiver synchronization comparison in Orchard. All four cases use the same Quartz single-entry terminal-hold protocol and an idle XCTest runner. Writes and fixture validation stay in place. Every native pass still requires Existing-only cancellation and a distinct successful fresh drop; the original continuous enter/exit/reentry gate is not covered."}
    capture.write_json(output / "comparison.json", report)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--staged", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--experiment-commit")
    parser.add_argument("--prepare-driver", action="store_true")
    args = parser.parse_args()
    capture.require(platform.system() == "Darwin" and platform.machine() in ("arm64", "x86_64"), "native-mac-required")
    stage = args.staged.absolute()
    if args.prepare_driver:
        capture.require(args.output is None and args.experiment_commit is None, "mouse-prepare-option-conflict")
        print(json.dumps(prepare_mouse_driver(stage), indent=2, sort_keys=True, allow_nan=False))
        return 0
    capture.require(args.output is not None and args.experiment_commit is not None, "mouse-comparison-options-required")
    report = compare(stage, args.output.absolute(), context_for(stage, args.experiment_commit))
    print(json.dumps(report, indent=2, sort_keys=True, allow_nan=False))
    return 0 if report["allCasesPassed"] else 1


if __name__ == "__main__":
    sys.exit(main())
