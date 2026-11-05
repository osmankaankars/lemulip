"""Compare Swift async and AppKit observer startup with one fixed AX-only path."""
import argparse
import math
from pathlib import Path
import platform
import stat
import sys

import compare_native_drag_capture as capture

MODES = {
    "swift-async": {"executable": "NativeDragReview", "swiftDefines": []},
    "appkit": {"executable": "NativeDragReviewAppKit", "swiftDefines": ["LEMULIP_APPKIT_OBSERVER"]},
}
CASES = [(target, mode) for target in capture.TARGETS for mode in MODES]
POLICY = "ax-only"


def evidence_for(stage, target, mode):
    suffix = "-Lifecycle-appkit" if mode == "appkit" else ""
    return stage / (capture.TARGETS[target][1] + "-Capture-" + POLICY + suffix)


def input_snapshot(stage):
    result = capture.input_snapshot(stage)
    observer = stage / MODES["appkit"]["executable"]
    result[observer.name] = {"type": "file", "mode": stat.S_IMODE(observer.lstat().st_mode),
                             "sha256": capture.sha256(observer)}
    return result


def context_for(stage, experiment_commit):
    context = capture.context_for(stage, experiment_commit)
    provenance = context["provenance"]
    capture.require(provenance.get("observerAppKitExecutableSHA256") == capture.sha256(stage / "NativeDragReviewAppKit"),
                    "appkit-observer-hash-link")
    capture.require(provenance.get("observerBuildModes") == MODES, "observer-build-modes")
    context["inputs"] = input_snapshot(stage)
    return context


def lifecycle_context(value, mode):
    capture.require(isinstance(value, dict), "lifecycle-context-missing")
    capture.fields_match(value, {"mode": mode, "didFinishLaunching": mode == "appkit",
                                "nsApplicationRunning": mode == "appkit"}, "lifecycle-startup-mismatch")
    capture.require(type(value.get("nsApplicationPresent")) is bool
                    and type(value.get("threadIsMain")) is bool
                    and type(value.get("activationPolicy")) is int
                    and type(value.get("taskPriorityRawValue")) is int, "lifecycle-context-types")
    if mode == "appkit":
        capture.fields_match(value, {"nsApplicationPresent": True, "activationPolicy": 2}, "appkit-startup-policy")
    else:
        policies = (0, 1, 2) if value["nsApplicationPresent"] else (-1,)
        capture.require(value["activationPolicy"] in policies, "baseline-startup-policy")
    # Thread and task priority are observations, not acceptance thresholds.
    return {key: value[key] for key in ("mode", "didFinishLaunching", "nsApplicationPresent",
        "nsApplicationRunning", "activationPolicy", "threadIsMain", "taskPriorityRawValue")}


def classify(stage, context, target, mode, returncode):
    evidence = evidence_for(stage, target, mode)
    aggregate = capture.read_json(evidence / "report.json")
    case = capture.read_json(evidence / "orchard/report.json")
    contexts = {}
    for name, record in (("aggregate", aggregate), ("case", case)):
        capture.fields_match(record, {"observerLifecycle": mode}, "observer-lifecycle-mismatch")
        contexts[name] = lifecycle_context(record.get("observerLifecycleAtStart"), mode)
    suffix = "-Lifecycle-appkit" if mode == "appkit" else ""
    result = capture.classify(stage, context, target, POLICY, returncode, evidence_suffix=suffix)
    hash_key = "observerAppKitExecutableSHA256" if mode == "appkit" else "observerExecutableSHA256"
    result.update(observerLifecycle=mode, observerLifecycleAtStart=contexts,
                  observerExecutable=MODES[mode]["executable"], observerExecutableSHA256=context["provenance"][hash_key])
    timing = case.get("escapePostTiming", {})
    result["escapePostTiming"] = {key: timing[key] for key in ("downStartedSystemUptime", "downCompletedSystemUptime",
        "upStartedSystemUptime", "upCompletedSystemUptime", "heldSeconds") if isinstance(timing, dict)
        and type(timing.get(key)) in (int, float) and math.isfinite(timing[key])}
    pauses = case.get("pauseTimings", [])
    result["pauseTimingCount"] = len(pauses) if isinstance(pauses, list) else 0
    result["pauseTimingLimitReached"] = case.get("pauseTimingLimitReached") is True
    return result


def compare(stage, output, context, runner=capture.run_observer):
    capture.require(not output.exists() and not output.is_symlink(), "output-already-exists")
    capture.require(all(not evidence_for(stage, target, mode).exists()
                        and not evidence_for(stage, target, mode).is_symlink()
                        for target, mode in CASES), "evidence-already-exists")
    output.mkdir(parents=False, exist_ok=False)
    capture.write_json(output / "inputs-before.json", context["inputs"])
    results, stopped = [], None
    for target, mode in CASES:
        identity = {"target": target, "observerLifecycle": mode, "captureComparison": POLICY}
        if stopped:
            results.append({**identity, "outcome": "not-run", "reasonCode": stopped})
            continue
        returncode = None
        try:
            capture.require(input_snapshot(stage) == context["inputs"], "inputs-changed-before-case")
            command = [str(stage / MODES[mode]["executable"]), str(stage)]
            if target == "control":
                command.append("--control")
            command += ["--compare-capture", POLICY]
            returncode = runner(command, output / f"{target}-{mode}.log")
            capture.require(input_snapshot(stage) == context["inputs"], "inputs-changed-after-case")
            result = classify(stage, context, target, mode, returncode)
            result["inputsUnchanged"] = True
            results.append(result)
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
              "C12": "HOLD", "comparisonComplete": complete, "allCasesPassed": passed,
              "inputsUnchanged": unchanged, "sameStagedPaths": True, "captureComparison": POLICY,
              "provenance": context["provenance"], "fixtureHashes": context["fixtures"], "cases": results,
              "scope": "One Orchard lifecycle pair per target in one existing CI session; native acceptance remains separate."}
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
    print(capture.json.dumps(report, indent=2, sort_keys=True))
    return 0 if report["allCasesPassed"] else 1


if __name__ == "__main__":
    sys.exit(main())
