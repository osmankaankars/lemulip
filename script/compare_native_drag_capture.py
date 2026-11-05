"""Run one same-path, Orchard-only capture comparison; never grant permissions."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import platform
import re
import stat
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
APPLICATION_COMMIT = "d821d7343675e2850705d141ef9b3b93a6aee945"
APPLICATION_TREE = "425baa28f00ec24551dd70c0cc874a75fa3be0c1"
ESCAPE_FAILURE = "Escape did not cancel the actual Finder drag"
TARGETS = {
    "control": ("Native Drag Control.app", "NativeDragControlEvidence", "standard-appkit-control"),
    "production": ("Lemulip Native UI Review.app", "NativeDragEvidence", "production"),
}
CASES = [(target, policy) for target in TARGETS for policy in ("screenshots", "ax-only")]


class ComparisonError(ValueError):
    pass


def require(condition, code):
    if not condition:
        raise ComparisonError(code)


def sha256(path):
    information = path.lstat()
    require(stat.S_ISREG(information.st_mode) and information.st_size <= 268_435_456, "nonregular-or-oversized-input")
    digest, count = hashlib.sha256(), 0
    with path.open("rb") as stream:
        while chunk := stream.read(1_048_576):
            count += len(chunk)
            require(count <= information.st_size, "input-size-changed")
            digest.update(chunk)
    require(count == information.st_size, "input-size-changed")
    return digest.hexdigest()


def read_json(path):
    information = path.lstat()
    require(stat.S_ISREG(information.st_mode) and information.st_size <= 8_388_608, "invalid-report-file")
    with path.open("rb") as stream:
        data = stream.read(8_388_609)
    require(len(data) == information.st_size, "report-size-changed")
    value = json.loads(data)
    require(isinstance(value, dict), "report-is-not-a-dictionary")
    return value


def write_json(path, value):
    with path.open("x") as stream:
        json.dump(value, stream, indent=2, sort_keys=True, allow_nan=False)
        stream.write("\n")


def input_snapshot(stage):
    """Exclude only Finder view metadata; every app/fixture/observer byte is fixed."""
    result = {}
    for name in ("Lemulip Native UI Review.app", "Native Drag Control.app", "Fixtures", "NativeDragReview", "provenance.json"):
        root = stage / name
        require(root.exists() and not root.is_symlink(), "missing-or-symlinked-input")
        paths = [root, *sorted(root.rglob("*"))] if root.is_dir() else [root]
        require(len(paths) <= 16_384, "input-inventory-bound")
        for path in paths:
            if name == "Fixtures" and path.name == ".DS_Store":
                continue
            info = path.lstat()
            require(stat.S_ISDIR(info.st_mode) or stat.S_ISREG(info.st_mode), "input-file-type")
            relative = path.relative_to(stage).as_posix()
            entry = {"mode": stat.S_IMODE(info.st_mode), "type": "directory" if path.is_dir() else "file"}
            if entry["type"] == "file":
                entry["sha256"] = sha256(path)
            result[relative] = entry
    return result


def context_for(stage, experiment_commit):
    require(stage.name == "lemulip-native-ui" and stage == stage.resolve(), "staging-root")
    provenance = read_json(stage / "provenance.json")
    require(provenance.get("sourceCommit") == APPLICATION_COMMIT
            and provenance.get("sourceTree") == APPLICATION_TREE, "application-source-pins")
    git = lambda value: subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", value], text=True).strip()
    require(re.fullmatch(r"[0-9a-f]{40}", experiment_commit) is not None
            and git("HEAD") == experiment_commit == provenance.get("observerExperimentCommit")
            and git("HEAD^{tree}") == provenance.get("observerExperimentTree"), "observer-source-pins")
    require(provenance.get("architecture") == platform.machine(), "architecture-mismatch")
    require(provenance.get("diagnosticOnly") is True
            and provenance.get("nativeAcceptanceXCTestExecuted") is False, "diagnostic-scope")
    links = {
        "nativeDragReviewSourceSHA256": ROOT / "script/native_ui/NativeDragReview.swift",
        "nativeDragControlSourceSHA256": ROOT / "script/native_ui/NativeDragControl.swift",
        "observerExecutableSHA256": stage / "NativeDragReview",
        "stagedGUI_SHA256": stage / "Lemulip Native UI Review.app/Contents/MacOS/Lemulip",
        "controlGUI_SHA256": stage / "Native Drag Control.app/Contents/MacOS/NativeDragControl",
    }
    require(all(provenance.get(key) == sha256(path) for key, path in links.items()), "source-binary-hash-link")
    folder = stage / "Fixtures/FinderDrop/orchard"
    fixtures = {p.name: sha256(p) for p in folder.iterdir() if p.name != ".DS_Store"}
    require(len(fixtures) == 4, "fixture-count")
    roles = {}
    for role in ("Existing", "Single", "Multi-A", "Multi-B"):
        names = [name for name in fixtures if re.fullmatch(re.escape(role) + r"-[0-9a-f]{32}\.txt", name)]
        require(len(names) == 1, "fixture-role")
        require((folder / names[0]).read_bytes() == f"Synthetic Finder input: orchard, {role}. Preserve these bytes.\n".encode(), "fixture-contents")
        roles[role] = names[0]
    return {"provenance": provenance, "fixtures": fixtures, "roles": roles, "inputs": input_snapshot(stage)}


def fields_match(actual, expected, code):
    require(isinstance(actual, dict), code)
    require(all(type(actual.get(k)) is type(v) and actual.get(k) == v for k, v in expected.items()), code)


def cleanup_complete(cleanup):
    return (isinstance(cleanup, dict) and cleanup.get("completed") is True
        and cleanup.get("leftButtonReportedDown") is False and cleanup.get("errors") == []
        and all(cleanup.get(k) is True for k in ("applicationStopped", "fixtureFinderWindowClosed", "fixedBundleRegistryEmpty")))


def classify(stage, context, target, policy, returncode, evidence_suffix=""):
    bundle, evidence_name, kind = TARGETS[target]
    require(evidence_suffix in ("", "-Lifecycle-appkit",
        "-Lifecycle-appkit-Source-finder-first", "-Lifecycle-appkit-Source-appkit-first",
        "-Lifecycle-appkit-Source-appkit-second", "-Lifecycle-appkit-Source-finder-second",
        "-Lifecycle-appkit-Activation-raise-first", "-Lifecycle-appkit-Activation-no-raise-first",
        "-Lifecycle-appkit-Activation-no-raise-second", "-Lifecycle-appkit-Activation-raise-second"),
        "unknown-evidence-suffix")
    evidence = stage / (evidence_name + "-Capture-" + policy + evidence_suffix)
    aggregate = read_json(evidence / "report.json")
    case_path = evidence / "orchard/report.json"
    case = read_json(case_path)
    provenance = context["provenance"]
    source_keys = ["sourceCommit", "sourceTree", "architecture", "observerExperimentCommit",
                   "observerExperimentTree", "nativeDragReviewSourceSHA256"]
    source_keys += (["stagedGUI_SHA256"] if target == "production" else ["controlGUI_SHA256", "nativeDragControlSourceSHA256"])
    expected = {k: provenance[k] for k in source_keys}
    expected.update(targetKind=kind, inputDriver="CGEvent", permissionRequested=False,
                    captureComparison=policy, diagnosticOnly=True, nativeAcceptanceXCTestExecuted=False,
                    imageCaptureEnabled=policy == "screenshots")
    fields_match(aggregate, {**expected, "schema": 2, "expectedThemes": ["orchard"]}, "aggregate-identity")
    fields_match(case, {**expected, "schema": 1, "theme": "orchard"}, "case-identity")
    require(case.get("applicationPath") == str(stage / bundle)
            and case.get("fixtureFolder") == str(stage / "Fixtures/FinderDrop/orchard"), "staged-path-changed")
    require(case.get("originalSHA256") == context["fixtures"], "reported-fixture-hashes")
    fields_match(case.get("preflight"), {"accessibility": True, "postEvents": True, "screenCapture": True}, "existing-permission-unavailable")
    require(set(case["preflight"]) == {"accessibility", "postEvents", "screenCapture"}, "permission-policy-changed")
    themes = aggregate.get("themes", [])
    require(len(themes) == 1, "theme-count")
    theme = themes[0]
    fields_match(theme, {"theme": "orchard", "report": "orchard/report.json", "reportRetained": True}, "case-report-not-retained")
    require(cleanup_complete(case.get("cleanup")) and theme.get("cleanup") == case["cleanup"], "cleanup-incomplete")
    existing, single = context["roles"]["Existing"], context["roles"]["Single"]
    observations = [o.get("workspace", {}) for o in case.get("escapeObservations", []) if o.get("phase") == "before-key"]
    require(len(observations) == 1, "initial-workspace-missing")
    fields_match(observations[0], {"matchesExpectedWorkspace": True, "expectedFilenames": [existing],
        "observedFilenames": [existing], "selectedCountLabels": ["1 Selected"]}, "initial-workspace-incorrect")
    protocol = case.get("escapeKeyProtocol", {})
    fields_match(protocol, {"keyCode": 53, "eventTap": "cghidEventTap", "keyDownDwellSeconds": 0.15,
        "downSourceStateID": 1, "upSourceStateID": 1, "downFlags": 0, "upFlags": 0,
        "continuedMotionDelta": {"x": 1, "y": 0}}, "escape-protocol-changed")
    cancellation = case.get("escapeCancellation", {})
    require(cancellation.get("expectedFilenames") == [existing], "cancellation-observation-missing")
    passed = case.get("status") == "captured"
    if passed:
        fields_match(case, {"gestureOutcomesVerified": True, "originalBytesUnchanged": True,
                           "userFileSetUnchanged": True}, "incomplete-success")
        fields_match(cancellation, {"matchesExpectedWorkspace": True, "observedFilenames": [existing],
                                   "selectedCountLabels": ["1 Selected"]}, "cancellation-not-proven")
    else:
        fields_match(case, {"status": "failed", "reason": ESCAPE_FAILURE, "gestureOutcomesVerified": False}, "unknown-or-blocked-failure")
        fields_match(theme, {"reason": ESCAPE_FAILURE}, "failure-summary-mismatch")
        fields_match(cancellation, {"matchesExpectedWorkspace": False, "observedFilenames": sorted([existing, single]),
                                   "selectedCountLabels": ["2 Selected"]}, "unexpected-cancellation-failure")
    status = "captured" if passed else "failed"
    fields_match(aggregate, {"status": status, "allThemesCaptured": passed, "gestureOutcomesVerified": passed}, "aggregate-status-mismatch")
    fields_match(theme, {"status": status, "gestureOutcomesVerified": passed}, "theme-status-mismatch")
    require(returncode == (0 if passed else 1), "observer-exit-mismatch")
    fields_match(case, {"imagesCaptured": policy == "screenshots"}, "case-image-receipt")
    fields_match(aggregate, {"imagesCaptured": policy == "screenshots"}, "aggregate-image-receipt")
    stages = case.get("stages", [])
    required_stages = {"00-before-drag", "01-enter-top-padding", "02-leave-file-area", "03-reenter-top-padding", "04-after-escape"}
    if passed:
        required_stages |= {"05-before-accepted-drop", "06-after-accepted-drop"}
    require({s.get("stage") for s in stages} == required_stages, "incomplete-stages")
    captures = [case.get("setupSnapshot", {}), *stages, *case.get("diagnosticSnapshots", [])]
    require(any(c.get("stage") == "diagnostic-after-escape-held" for c in captures), "held-observation-missing")
    durations = {}
    for capture in captures:
        fields_match(capture, {"captureKind": "screen-and-target-ax" if policy == "screenshots" else "target-ax-only",
                              "imagesCaptured": policy == "screenshots"}, "capture-policy-mismatch")
        started, finished = capture.get("captureStartedSystemUptime"), capture.get("captureCompletedSystemUptime")
        require(type(started) in (int, float) and type(finished) in (int, float)
                and math.isfinite(started) and math.isfinite(finished) and finished >= started, "capture-clock")
        durations[capture["stage"]] = finished - started
        if policy == "screenshots":
            image = capture.get("image", "")
            require(isinstance(image, str) and Path(image).name == image and image.endswith(".png"), "image-name")
            require(sha256(evidence / "orchard" / image) == capture.get("imageSHA256"), "image-hash")
        else:
            require(not any(k in capture for k in ("image", "imageSHA256", "pixelWidth", "pixelHeight")), "unexpected-image-fields")
    if policy == "ax-only":
        require(not any(evidence.rglob("*.png")), "unexpected-image-file")
    result = {"target": target, "captureComparison": policy, "passed": passed,
              "outcome": "captured" if passed else "escape-cancellation-failed", "mayContinue": True,
              "returnCode": returncode, "reportRetained": True, "cleanupComplete": True,
              "sourceBindings": expected, "caseSHA256": sha256(case_path),
              "captureSeconds": durations, "heldObservation": case.get("escapeHeldDiagnostic", {}),
              "targetGeometry": case.get("targetGeometry", {})}
    if target == "control":
        result["receiverSHA256"] = sha256(evidence / "orchard/receiver.jsonl")
    return result


def run_observer(command, log):
    # The observer owns its 110-second clock and paired cleanup. Do not kill it
    # with an outer subprocess timeout while it may own mouse/key state.
    with log.open("xb") as stream:
        return subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, check=False).returncode


def compare(stage, output, context, runner=run_observer):
    require(not output.exists() and not output.is_symlink(), "output-already-exists")
    require(all(not (stage / (TARGETS[t][1] + "-Capture-" + p)).exists() for t, p in CASES), "evidence-already-exists")
    output.mkdir(parents=False, exist_ok=False)
    write_json(output / "inputs-before.json", context["inputs"])
    results, stopped = [], None
    for target, policy in CASES:
        if stopped:
            results.append({"target": target, "captureComparison": policy, "outcome": "not-run", "reasonCode": stopped})
            continue
        returncode = None
        try:
            require(input_snapshot(stage) == context["inputs"], "inputs-changed-before-case")
            command = [str(stage / "NativeDragReview"), str(stage)]
            if target == "control":
                command.append("--control")
            command += ["--compare-capture", policy]
            returncode = runner(command, output / f"{target}-{policy}.log")
            require(input_snapshot(stage) == context["inputs"], "inputs-changed-after-case")
            result = classify(stage, context, target, policy, returncode)
            result["inputsUnchanged"] = True
            results.append(result)
        except Exception as error:
            stopped = str(error) if isinstance(error, ComparisonError) else type(error).__name__
            results.append({"target": target, "captureComparison": policy, "outcome": "not-comparable",
                            "returnCode": returncode, "reasonCode": stopped, "mayContinue": False})
    try:
        after = input_snapshot(stage)
        unchanged = after == context["inputs"]
        write_json(output / "inputs-after.json", after)
    except Exception:
        unchanged = False
    complete = len(results) == 4 and all(r.get("mayContinue") is True for r in results)
    passed = complete and unchanged and all(r.get("passed") is True for r in results)
    report = {"schema": 1, "status": "passed" if passed else "failed", "diagnosticOnly": True,
              "releaseReady": False, "nativeAcceptanceXCTestExecuted": False, "physicalInputVerified": False,
              "C12": "HOLD", "comparisonComplete": complete, "allCasesPassed": passed,
              "inputsUnchanged": unchanged, "sameStagedPaths": True, "provenance": context["provenance"],
              "fixtureHashes": context["fixtures"], "cases": results,
              "scope": "One Orchard capture-only pair per target in one existing CI session; native acceptance remains separate."}
    write_json(output / "comparison.json", report)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--staged", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--experiment-commit", required=True)
    args = parser.parse_args()
    require(platform.system() == "Darwin" and platform.machine() in ("arm64", "x86_64"), "native-mac-required")
    stage = args.staged.absolute()
    report = compare(stage, args.output.absolute(), context_for(stage, args.experiment_commit))
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0 if report["allCasesPassed"] else 1


if __name__ == "__main__":
    sys.exit(main())
