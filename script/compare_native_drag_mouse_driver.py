"""Compare two complete mouse producers in one bounded native AppKit protocol.

This diagnostic uses one entry and a terminal hold.  It does not replace the
continuous enter/exit/reentry acceptance gate and cannot release C12.
"""
import argparse
import copy
import json
import math
from pathlib import Path
import platform
import plistlib
import re
import stat
import subprocess
import sys
import uuid

import compare_native_drag_activation as activation
import compare_native_drag_capture as capture
import compare_native_drag_lifecycle as lifecycle
import compare_native_drag_sources as sources

CASES = ("quartz-first", "xctest-first", "xctest-second", "quartz-second")
OBSERVER = "NativeDragReviewMouseAppKit"
RUNNER_ID = "app.lemulip.NativeDragMouseTests.xctrunner"
RUNNER_RELATIVE = "MouseDerivedData/Build/Products/Debug/QualityReview-Runner.app"
TEST_RELATIVE = "Contents/PlugIns/QualityReview.xctest/Contents/MacOS/QualityReview"
PROJECT_RELATIVE = "MouseRunner/QualityReview.xcodeproj"
INITIAL_HOLD_SECONDS = .3
VELOCITY = 400.
CANCEL_HOLD_SECONDS = 5.
FRESH_HOLD_SECONDS = 1.
ESCAPE_DELAY_SECONDS = 2.
ESCAPE_DWELL_SECONDS = .15
RELEASE_OBSERVATION_TIMEOUT_SECONDS = 1.
RELEASE_OBSERVATION_POLL_SECONDS = .025


def bindings(case_name):
    capture.require(case_name in CASES, "unknown-mouse-driver-case")
    return {"sourceCase": case_name, "dragSourceKind": "native-appkit",
            "activationCase": case_name, "targetRaisePolicy": "present",
            "mouseDriverCase": case_name,
            "mouseProducer": "xctest" if case_name.startswith("xctest-") else "quartz"}


def evidence_for(stage, case_name):
    bindings(case_name)
    return stage / ("NativeDragControlEvidence-Capture-ax-only-Lifecycle-appkit-MouseDriver-" + case_name)


def configuration_for(stage, case_name):
    bindings(case_name)
    config = capture.read_json(stage / "MouseControl" / case_name / "configuration.json")
    capture.fields_match(config, {"schema": 1, "case": case_name}, "mouse-configuration-schema")
    capture.require(set(config) == {"schema", "case", "nonce"}
                    and isinstance(config.get("nonce"), str)
                    and re.fullmatch(r"[0-9a-f]{32}", config["nonce"]) is not None,
                    "mouse-configuration-nonce")
    return config


def xctest_target(manifest):
    """Select the single generated UI target, never an arbitrary nested dict."""
    capture.require(isinstance(manifest, dict), "mouse-xctestrun-root")
    metadata = manifest.get("__xctestrun_metadata__", {})
    capture.require(isinstance(metadata, dict), "mouse-xctestrun-metadata")
    version = metadata.get("FormatVersion", 1)
    capture.require(type(version) is int and version in (1, 2), "mouse-xctestrun-format")
    if version == 1:
        targets = {key: value for key, value in manifest.items() if not key.startswith("__")}
        capture.require(set(targets) == {"QualityReview"}, "mouse-xctestrun-target-count")
        target = targets["QualityReview"]
    else:
        configurations = manifest.get("TestConfigurations")
        capture.require(isinstance(configurations, list) and len(configurations) == 1
                        and isinstance(configurations[0], dict), "mouse-xctestrun-configuration-count")
        targets = configurations[0].get("TestTargets")
        capture.require(isinstance(targets, list) and len(targets) == 1
                        and isinstance(targets[0], dict), "mouse-xctestrun-target-count")
        target = targets[0]
        capture.fields_match(target, {"BlueprintName": "QualityReview"}, "mouse-xctestrun-blueprint")
    capture.require(isinstance(target, dict), "mouse-xctestrun-target")
    capture.fields_match(target, {"IsUITestBundle": True}, "mouse-xctestrun-ui-target")
    bundle = target.get("TestBundlePath")
    capture.require(isinstance(bundle, str) and bundle.endswith("/QualityReview.xctest"), "mouse-xctestrun-test-bundle")
    capture.require("ProductModuleName" not in target or target["ProductModuleName"] == "QualityReview",
                    "mouse-xctestrun-product-module")
    capture.require(isinstance(target.get("EnvironmentVariables", {}), dict), "mouse-xctestrun-environment")
    return target


def manifest_metadata(stage, *, prepare=False):
    products = stage / "MouseDerivedData/Build/Products"
    manifests = sorted(products.glob("*.xctestrun"))
    originals = [path for path in manifests if not path.name.startswith("D13-")]
    capture.require(len(originals) == 1, "mouse-xctestrun-manifest-count")
    original = originals[0]
    capture.require(original.stat().st_size <= 1_048_576, "mouse-xctestrun-size")
    capture.sha256(original)
    template = plistlib.loads(original.read_bytes())
    original_target = xctest_target(template)
    capture.require("LEMULIP_MOUSE_DRIVER_CASE" not in original_target.get("EnvironmentVariables", {}),
                    "mouse-xctestrun-preexisting-case")
    hashes = {}
    for name in CASES:
        destination = products / ("D13-" + name + ".xctestrun")
        expected = copy.deepcopy(template)
        target = xctest_target(expected)
        target["EnvironmentVariables"] = {**target.get("EnvironmentVariables", {}), "LEMULIP_MOUSE_DRIVER_CASE": name}
        if prepare:
            with destination.open("xb") as stream:
                plistlib.dump(expected, stream, sort_keys=True)
        capture.require(destination.stat().st_size <= 1_048_576, "mouse-xctestrun-size")
        hashes[name] = capture.sha256(destination)
        capture.require(plistlib.loads(destination.read_bytes()) == expected, "mouse-xctestrun-case-binding")
    capture.require({path.name for path in products.glob("*.xctestrun")}
                    == {original.name, *("D13-" + name + ".xctestrun" for name in CASES)},
                    "mouse-xctestrun-unexpected-manifest")
    return {"mouseXCTestRunSHA256": hashes, "mouseOriginalXCTestRunPath": str(original),
            "mouseOriginalXCTestRunSHA256": capture.sha256(original)}


def runner_metadata(stage):
    runner = stage / RUNNER_RELATIVE
    info_path = runner / "Contents/Info.plist"
    capture.sha256(info_path)  # Enforce a bounded, regular file before parsing.
    capture.require(info_path.stat().st_size <= 262_144, "mouse-runner-info-size")
    info = plistlib.loads(info_path.read_bytes())
    capture.fields_match(info, {"CFBundleIdentifier": RUNNER_ID,
        "CFBundleExecutable": "QualityReview-Runner"}, "mouse-runner-identity")
    executable = runner / "Contents/MacOS/QualityReview-Runner"
    test_executable = runner / TEST_RELATIVE
    capture.require(executable.stat().st_size > 0 and test_executable.stat().st_size > 0,
                    "mouse-runner-empty-binary")
    return {"mouseRunnerInfoSHA256": capture.sha256(info_path),
            "mouseRunnerExecutableSHA256": capture.sha256(executable),
            "mouseTestsExecutableSHA256": capture.sha256(test_executable),
            "mouseRunnerBuilt": True, "mouseRunnerBundleIdentifier": RUNNER_ID,
            "mouseRunnerApplicationPath": str(runner),
            "mouseRunnerExecutablePath": str(executable),
            "mouseTestsExecutablePath": str(test_executable)}


def prepare_mouse_driver(stage):
    """Build once, before any native input; return provenance additions.

    The caller writes these additions into its staged provenance receipt before
    context_for captures the immutable inventory.  This helper never launches
    the runner or grants permissions.
    """
    import prepare_native_ui as staging
    capture.require(platform.system() == "Darwin", "native-mac-required")
    capture.require(stage.name == "lemulip-native-ui" and stage == stage.resolve(), "staging-root")
    for name in ("MouseControl", "MouseRunner", "MouseDerivedData", "mouse-build.log"):
        capture.require(not (stage / name).exists() and not (stage / name).is_symlink(),
                        "mouse-build-output-already-exists")
    source = capture.ROOT / "script/native_ui/NativeDragMouseTests.swift"
    project = staging.write_project(stage / "MouseRunner", source,
                                    stage / "Native Drag Control.app", stage / "Fixtures")
    project_file = project / "project.pbxproj"
    original = project_file.read_text()
    capture.require(original.count("app.lemulip.NativeQualityUITests") == 1,
                    "mouse-generated-project-identity")
    project_file.write_text(original.replace("app.lemulip.NativeQualityUITests", "app.lemulip.NativeDragMouseTests"))
    control = stage / "MouseControl"
    control.mkdir(mode=0o700, exist_ok=False)
    for name in CASES:
        directory = control / name
        directory.mkdir(mode=0o700, exist_ok=False)
        capture.write_json(directory / "configuration.json", {"schema": 1, "case": name, "nonce": uuid.uuid4().hex})
    command = ["xcrun", "xcodebuild", "build-for-testing", "-project", str(project),
               "-scheme", "QualityReview", "-derivedDataPath", str(stage / "MouseDerivedData"),
               "-destination", "platform=macOS", "-parallel-testing-enabled", "NO"]
    with (stage / "mouse-build.log").open("xb") as log:
        completed = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=False)
    capture.require(completed.returncode == 0, "mouse-runner-build-failed")
    return {**runner_metadata(stage), **manifest_metadata(stage, prepare=True),
        "nativeDragMouseTestsSourceSHA256": capture.sha256(source),
        "nativeDragMouseDriverSourceSHA256": capture.sha256(capture.ROOT / "script/native_ui/NativeDragMouseDriver.swift"),
        "mouseDriverComparatorSourceSHA256": capture.sha256(Path(__file__)),
        "mouseConfigurationsSHA256": {name: capture.sha256(control / name / "configuration.json") for name in CASES},
        "mouseComparisonScope": "One entry and a terminal hold in the standard AppKit receiver; diagnostic only, distinct from the original enter/exit/reentry gate."}


def inventory_tree(stage, root, output):
    """Inventory immutable runner inputs, including bounded internal aliases."""
    capture.require(root.exists() and not root.is_symlink(), "mouse-input-root")
    paths = [root, *sorted(root.rglob("*"))] if root.is_dir() else [root]
    capture.require(len(paths) <= 16_384, "mouse-input-inventory-bound")
    for path in paths:
        information = path.lstat()
        entry = {"mode": stat.S_IMODE(information.st_mode)}
        if stat.S_ISREG(information.st_mode):
            entry.update(type="file", sha256=capture.sha256(path))
        elif stat.S_ISDIR(information.st_mode):
            entry.update(type="directory")
        elif stat.S_ISLNK(information.st_mode):
            # Framework version aliases may be legitimate build products.  An
            # alias must remain inside this inventoried tree; external links
            # would make the staged-byte claim incomplete.
            capture.require(root.is_dir() and path.resolve().is_relative_to(root.resolve())
                            and path.resolve().exists(), "mouse-input-external-symlink")
            entry.update(type="symlink", target=path.readlink().as_posix())
        else:
            raise capture.ComparisonError("mouse-input-file-type")
        output[path.relative_to(stage).as_posix()] = entry


def input_snapshot(stage):
    result = sources.input_snapshot(stage)
    for name in (OBSERVER, "MouseRunner", RUNNER_RELATIVE):
        inventory_tree(stage, stage / name, result)
    for name in CASES:
        inventory_tree(stage, stage / "MouseControl" / name / "configuration.json", result)
    products = stage / "MouseDerivedData/Build/Products"
    manifests = sorted(products.glob("*.xctestrun"))
    capture.require(len(manifests) == 5, "mouse-xctestrun-manifest-count")
    for path in manifests:
        inventory_tree(stage, path, result)
    return result


def context_for(stage, experiment_commit):
    context = sources.context_for(stage, experiment_commit)
    provenance = context["provenance"]
    links = {
        "observerMouseAppKitExecutableSHA256": stage / OBSERVER,
        "nativeDragMouseTestsSourceSHA256": capture.ROOT / "script/native_ui/NativeDragMouseTests.swift",
        "nativeDragMouseDriverSourceSHA256": capture.ROOT / "script/native_ui/NativeDragMouseDriver.swift",
        "mouseDriverComparatorSourceSHA256": Path(__file__),
    }
    capture.require(all(provenance.get(key) == capture.sha256(path) for key, path in links.items()),
                    "mouse-source-binary-hash-link")
    capture.fields_match(provenance, runner_metadata(stage), "mouse-runner-provenance")
    capture.fields_match(provenance, manifest_metadata(stage), "mouse-xctestrun-provenance")
    capture.fields_match(provenance, {"mouseConfigurationsSHA256": {name:
        capture.sha256(stage / "MouseControl" / name / "configuration.json") for name in CASES}}, "mouse-configuration-provenance")
    context["mouseConfigurations"] = {name: configuration_for(stage, name) for name in CASES}
    capture.require(len({value["nonce"] for value in context["mouseConfigurations"].values()}) == 4,
                    "mouse-configuration-nonces-not-unique")
    context["inputs"] = input_snapshot(stage)
    return context


def runtime_directory(stage, case_name):
    bindings(case_name)
    return stage / "MouseControl" / case_name


def cleanup_complete(value):
    return capture.cleanup_complete(value) and all(value.get(key) is True for key in
        ("sourceApplicationStopped", "sourceBundleRegistryEmpty", "mouseDriverStopped", "mouseDriverNormal"))


def decoded_json(data, label):
    def pairs(items):
        result = {}
        for key, value in items:
            capture.require(key not in result, label + "-duplicate-key")
            result[key] = value
        return result
    def invalid(_):
        raise capture.ComparisonError(label + "-nonfinite")
    return json.loads(data, object_pairs_hook=pairs, parse_constant=invalid)


def read_json(path, label="mouse-json"):
    information = path.lstat()
    capture.require(stat.S_ISREG(information.st_mode) and information.st_size <= 8_388_608, label + "-file")
    data = path.read_bytes()
    capture.require(len(data) == information.st_size, label + "-size-changed")
    result = decoded_json(data, label)
    capture.require(isinstance(result, dict), label + "-object")
    return result


def clock(row, key):
    capture.require(isinstance(row, dict), "mouse-clock-record")
    return sources.finite(row.get(key), "mouse-clock-" + key)


def interval(row, start="startedSystemUptime", end="completedSystemUptime"):
    before, after = clock(row, start), clock(row, end)
    capture.require(before <= after, "mouse-clock-order")
    return before, after


def integer(value, label, *, minimum=0):
    capture.require(type(value) is int and value >= minimum, label)
    return value


def rectangle(value, label):
    capture.require(isinstance(value, dict) and set(value) == {"x", "y", "width", "height"}
                    and all(type(v) in (int, float) and math.isfinite(v) for v in value.values())
                    and value["width"] > 0 and value["height"] > 0, label)
    return value


def workspace(value, context, expected, observed=None):
    expected = sorted(expected)
    observed = expected if observed is None else sorted(observed)
    capture.fields_match(value, {"expectedFilenames": expected, "observedFilenames": observed,
        "matchesExpectedWorkspace": expected == observed,
        "expectedSelectedCountLabel": f"{len(expected)} Selected",
        "expectedSelectedCountMatches": 1 if expected == observed else 0,
        "selectedCountLabels": [f"{len(observed)} Selected"],
        "fixtureRemoveButtonCounts": {name: int(name in observed) for name in context["fixtures"]}},
        "mouse-workspace-incomplete")


def protocol_for(case_name):
    return {"schema": 1, "case": case_name, "mouseProducer": bindings(case_name)["mouseProducer"],
        "path": "single-entry-terminal-hold", "initialHoldSeconds": INITIAL_HOLD_SECONDS,
        "nominalVelocityPointsPerSecond": VELOCITY, "cancelDestinationHoldSeconds": CANCEL_HOLD_SECONDS,
        "freshDestinationHoldSeconds": FRESH_HOLD_SECONDS, "escapeOffsetSeconds": ESCAPE_DELAY_SECONDS,
        "escapeDwellSeconds": ESCAPE_DWELL_SECONDS, "heldObserverAXPolicy": "omitted",
        "releaseObservationTimeoutSeconds": RELEASE_OBSERVATION_TIMEOUT_SECONDS,
        "releaseObservationPollSeconds": RELEASE_OBSERVATION_POLL_SECONDS,
        "runnerPresentInBothArms": True, "continuedMouseMotionDuringEscape": False,
        "productionAcceptanceCoverage": False}


def native_outcome(stage, context, case_name, returncode, aggregate, case):
    identity = bindings(case_name)
    source_keys = ("sourceCommit", "sourceTree", "architecture", "observerExperimentCommit",
        "observerExperimentTree", "nativeDragReviewSourceSHA256", "nativeDragControlSourceSHA256", "controlGUI_SHA256")
    expected = {**{key: context["provenance"][key] for key in source_keys}, **identity,
        "targetKind": "standard-appkit-control", "inputDriver": "mouse-" + identity["mouseProducer"] + "-global-cg-escape",
        "permissionRequested": False, "captureComparison": "ax-only", "observerLifecycle": "appkit",
        "diagnosticOnly": True, "nativeAcceptanceXCTestExecuted": False, "imageCaptureEnabled": False,
        "imagesCaptured": False}
    capture.fields_match(aggregate, {**expected, "schema": 2, "expectedThemes": ["orchard"]}, "mouse-aggregate-identity")
    capture.fields_match(case, {**expected, "schema": 1, "theme": "orchard",
        "applicationPath": str(stage / "Native Drag Control.app"),
        "sourceApplicationPath": str(stage / sources.SOURCE_BUNDLE),
        "fixtureFolder": str(stage / "Fixtures/FinderDrop/orchard"), "originalSHA256": context["fixtures"]},
        "mouse-case-identity")
    for value in (aggregate, case):
        lifecycle.lifecycle_context(value.get("observerLifecycleAtStart"), "appkit")
        capture.require(not any(key in value for key in ("heldAXPolicy", "heldAXCase", "heldAXSlots", "heldAXReads")),
                        "mouse-unexpected-held-ax-arm")
    capture.fields_match(case.get("preflight"), {"accessibility": True, "postEvents": True, "screenCapture": True},
                         "mouse-existing-permission-unavailable")
    capture.require(set(case["preflight"]) == {"accessibility", "postEvents", "screenCapture"}, "mouse-permission-policy")
    capture.require(cleanup_complete(case.get("cleanup")), "mouse-cleanup-incomplete")
    themes = aggregate.get("themes")
    capture.require(isinstance(themes, list) and len(themes) == 1, "mouse-theme-count")
    theme = themes[0]
    capture.fields_match(theme, {"theme": "orchard", "report": "orchard/report.json", "reportRetained": True,
                                "cleanup": case["cleanup"]}, "mouse-theme-binding")
    existing, single = context["roles"]["Existing"], context["roles"]["Single"]
    workspace(case.get("mouseDriverInitialWorkspace"), context, [existing])
    passed = case.get("status") == "captured"
    if passed:
        workspace(case.get("escapeCancellation"), context, [existing])
        workspace(case.get("freshDropWorkspace"), context, [existing, single])
    else:
        capture.fields_match(case, {"status": "failed", "reason": "Escape did not cancel the actual native drag"},
                             "mouse-unknown-or-blocked-failure")
        capture.fields_match(theme, {"reason": case["reason"]}, "mouse-failure-summary")
        workspace(case.get("escapeCancellation"), context, [existing], [existing, single])
        capture.require("freshDropWorkspace" not in case and "freshDropObservationTiming" not in case,
                        "mouse-fresh-after-failed-cancellation")
    capture.fields_match(case, {"mouseDriverCancellationObserved": True, "gestureOutcomesVerified": passed,
        "originalBytesUnchanged": True, "userFileSetUnchanged": True}, "mouse-native-result-incomplete")
    status = "captured" if passed else "failed"
    capture.fields_match(aggregate, {"status": status, "allThemesCaptured": passed, "gestureOutcomesVerified": passed},
                         "mouse-aggregate-status")
    capture.fields_match(theme, {"status": status, "gestureOutcomesVerified": passed}, "mouse-theme-status")
    capture.require(type(returncode) is int and returncode == (0 if passed else 1), "mouse-observer-exit")
    return {"outcome": "captured" if passed else "escape-cancellation-failed", "passed": passed,
            "axOutcome": "captured" if passed else "escape-cancellation-failed", "returnCode": returncode}


def gesture_evidence(case, case_name, passed):
    expected = protocol_for(case_name)
    # Swift's JSON number spelling may be integral for a Double with no fraction.
    protocol = case.get("mouseDriverProtocol")
    capture.require(isinstance(protocol, dict) and set(protocol) == set(expected), "mouse-protocol-fields")
    for key, value in expected.items():
        if type(value) is float:
            capture.require(type(protocol[key]) in (int, float) and protocol[key] == value, "mouse-protocol-constant")
        else:
            capture.fields_match(protocol, {key: value}, "mouse-protocol-constant")
    capture.fields_match(case, {"mouseDriverAXGuardViolations": [], "heldObserverAXReadCount": 0}, "mouse-held-ax-guard")
    capture.require(case.get("escapeObservations", []) == [] and case.get("diagnosticSnapshots", []) == [],
                    "mouse-held-ax-observation-present")
    gestures = case.get("mouseDriverGestures")
    phases = ["cancel", "fresh"] if passed else ["cancel"]
    capture.require(isinstance(gestures, list) and [g.get("phase") for g in gestures] == phases,
                    "mouse-gesture-count")
    producer = bindings(case_name)["mouseProducer"]
    source_pid = integer(case.get("sourceApplicationPID"), "mouse-source-pid", minimum=1)
    target_pid = integer(case.get("targetApplicationPID"), "mouse-target-pid", minimum=1)
    capture.require(source_pid != target_pid, "mouse-source-target-pid-collision")
    geometry = sources.geometry_signature(case, "native-appkit")
    geometries = case.get("sourceGeometries")
    capture.require(isinstance(geometries, dict) and set(geometries) ==
                    ({"cancel-source", "drop-source"} if passed else {"cancel-source"}), "mouse-source-geometry-set")
    capture.require(all(value == case["sourceGeometry"] for value in geometries.values()), "mouse-source-geometry-changed")
    selections = case.get("mouseDriverSourceSelectionBeforeGesture")
    capture.require(isinstance(selections, dict) and set(selections) == set(geometries), "mouse-source-selection-set")
    previous_release, signatures = -1, []
    for gesture in gestures:
        phase = gesture["phase"]
        capture.fields_match(gesture, {"mouseProducer": producer, "completed": True, "releaseButtonState": False,
            "releaseMethod": "xctest-gesture-return" if producer == "xctest" else "quartz-mouse-up"}, "mouse-gesture-completion")
        hold = CANCEL_HOLD_SECONDS if phase == "cancel" else FRESH_HOLD_SECONDS
        capture.require(type(gesture.get("destinationHoldSeconds")) in (int, float)
                        and gesture["destinationHoldSeconds"] == hold, "mouse-destination-hold")
        started, released = interval(gesture, "startedSystemUptime", "releaseObservedSystemUptime")
        capture.require(started > previous_release, "mouse-gestures-overlap")
        previous_release = released
        requested = clock(gesture, "releaseRequestCompletedSystemUptime")
        acknowledgement = gesture.get("releaseAcknowledgement")
        capture.require(isinstance(acknowledgement, dict) and set(acknowledgement) ==
                        {"timeoutSeconds", "pollIntervalSeconds", "states"}, "mouse-release-acknowledgement-fields")
        for key, value in (("timeoutSeconds", RELEASE_OBSERVATION_TIMEOUT_SECONDS),
                           ("pollIntervalSeconds", RELEASE_OBSERVATION_POLL_SECONDS)):
            capture.require(type(acknowledgement[key]) in (int, float) and acknowledgement[key] == value,
                            "mouse-release-observation-protocol")
        release_states = acknowledgement["states"]
        maximum_states = math.floor(RELEASE_OBSERVATION_TIMEOUT_SECONDS / RELEASE_OBSERVATION_POLL_SECONDS) + 1
        capture.require(isinstance(release_states, list) and 1 <= len(release_states) <= maximum_states,
                        "mouse-release-observation-count")
        previous_state = None
        for index, state in enumerate(release_states):
            capture.require(isinstance(state, dict) and set(state) == {"systemUptime", "leftButtonReportedDown"},
                            "mouse-release-observation-fields")
            when = clock(state, "systemUptime")
            capture.require(requested <= when <= requested + RELEASE_OBSERVATION_TIMEOUT_SECONDS,
                            "mouse-release-observation-deadline")
            if previous_state is not None:
                capture.require(when > previous_state
                                and when - previous_state >= RELEASE_OBSERVATION_POLL_SECONDS - 1e-6,
                                "mouse-release-observation-poll-order")
            capture.fields_match(state, {"leftButtonReportedDown": index < len(release_states) - 1},
                                 "mouse-release-observation-input-state")
            previous_state = when
        capture.require(started < requested <= released and released == previous_state,
                        "mouse-release-observation-binding")
        source = sources.point(gesture.get("sourcePoint"), "mouse-gesture-source-point")
        target = sources.point(gesture.get("targetPoint"), "mouse-gesture-target-point")
        capture.require(source == case["sourceGeometry"]["sourcePoint"]
                        and target == activation.point_string(case["targetGeometry"].get("entryInTopPadding")),
                        "mouse-gesture-point-binding")
        source_frame = rectangle(gesture.get("sourceFrame"), "mouse-source-frame")
        target_frame = rectangle(gesture.get("targetFrame"), "mouse-target-frame")
        for point_value, frame_value in ((source, source_frame), (target, target_frame)):
            capture.require(frame_value["x"] <= point_value["x"] < frame_value["x"] + frame_value["width"]
                            and frame_value["y"] <= point_value["y"] < frame_value["y"] + frame_value["height"],
                            "mouse-point-outside-frame")
        capture.require(source_frame == sources.rect_string(case["sourceGeometry"]["nativeWindow"], "mouse-native-window")
                        and target_frame == sources.rect_string(case["targetGeometry"].get("reviewWindow"), "mouse-target-window"),
                        "mouse-gesture-frame-binding")
        entry = gesture.get("entryObservation")
        capture.fields_match(entry, {"leftButtonReportedDown": True, "sourcePID": source_pid, "targetPID": target_pid},
                             "mouse-entry-held-and-owned")
        entry_time = clock(entry, "receiverEntrySystemUptime")
        observed = clock(entry, "observedSystemUptime")
        capture.require(started <= entry_time <= observed < requested, "mouse-entry-order")
        integer(entry.get("sequenceNumber"), "mouse-entry-sequence")
        integer(entry.get("receiverRecordIndex"), "mouse-entry-record-index")
        cursor = sources.point(entry.get("cursorCG"), "mouse-entry-cursor")
        capture.require(math.hypot(cursor["x"] - target["x"], cursor["y"] - target["y"]) <= 1,
                        "mouse-entry-not-at-destination")
        selection = selections["cancel-source" if phase == "cancel" else "drop-source"]
        capture.fields_match(selection, {"selectionClickPosted": False}, "mouse-setup-selection-click")
        capture.require(type(selection.get("selected")) is bool
                        and clock(selection, "systemUptime") < started, "mouse-source-selection-observation")
        if producer == "quartz":
            scheduled = clock(gesture, "releaseScheduledSystemUptime")
            capture.require(math.isclose(scheduled, observed + hold, rel_tol=0, abs_tol=1e-6)
                            and scheduled <= released, "mouse-quartz-release-schedule")
            capture.require(started < clock(gesture, "lastMovementPostCompletedSystemUptime") <= observed,
                            "mouse-quartz-movement-order")
        else:
            capture.require(started <= clock(gesture, "requestPublishedSystemUptime") <= observed,
                            "mouse-xctest-publication-order")
        signatures.append({"phase": phase, "sourcePoint": source, "targetPoint": target,
                           "sourceFrame": source_frame, "targetFrame": target_frame, "destinationHoldSeconds": hold})
    cancel = gestures[0]
    timing = case.get("escapePostTiming")
    keys = ("downStartedSystemUptime", "downCompletedSystemUptime", "upStartedSystemUptime", "upCompletedSystemUptime")
    times = [clock(timing, key) for key in keys]
    capture.require(times == sorted(times) and times[2] >= times[1] + ESCAPE_DWELL_SECONDS - 1e-6,
                    "mouse-escape-order-or-dwell")
    capture.require(math.isclose(clock(timing, "heldSeconds"), times[2] - times[0], rel_tol=0, abs_tol=1e-6),
                    "mouse-escape-dwell-receipt")
    scheduled = clock(cancel, "escapeScheduledSystemUptime")
    capture.require(math.isclose(scheduled, cancel["entryObservation"]["observedSystemUptime"] + ESCAPE_DELAY_SECONDS,
                                rel_tol=0, abs_tol=1e-6) and scheduled <= times[0]
                    and times[-1] < cancel["releaseObservedSystemUptime"], "mouse-escape-schedule")
    capture.fields_match(cancel, {"escapeBeforeReleaseVerified": True}, "mouse-escape-not-held")
    capture.fields_match(case.get("escapeKeyProtocol"), {"kind": "d13-global-escape-no-pointer-motion", "keyCode": 53,
        "eventTap": "cghidEventTap", "keyDownDwellSeconds": ESCAPE_DWELL_SECONDS, "downSourceStateID": 1,
        "upSourceStateID": 1, "downFlags": 0, "upFlags": 0, "continuedMotion": False}, "mouse-escape-protocol")
    states = case.get("escapeInputStates")
    capture.require(isinstance(states, list) and [r.get("phase") for r in states] ==
                    ["d13-before-key-post", "d13-before-key-up", "d13-after-key-up"], "mouse-escape-input-states")
    previous = -1
    for index, row in enumerate(states):
        observed = clock(row, "systemUptime")
        capture.require(previous <= observed < cancel["releaseObservedSystemUptime"], "mouse-escape-state-clock")
        previous = observed
        capture.fields_match(row, {"mouseDownSent": producer == "quartz", "leftButtonReportedDown": True,
                                   "escapeKeyDownSent": index == 1}, "mouse-escape-input-held")
        capture.require(type(row.get("foregroundPID")) is int and row["foregroundPID"] in (source_pid, target_pid),
                        "mouse-escape-foreground-pid")
        expected_bundle = sources.SOURCE_ID if row["foregroundPID"] == source_pid else "app.lemulip.NativeDragControl"
        capture.require(row.get("foregroundBundleIdentifier") == expected_bundle, "mouse-escape-foreground-bundle")
        capture.require(type(row.get("hidLeftButtonReportedDown")) is bool
                        and type(row.get("escapeKeyReportedDown")) is bool
                        and type(row.get("hidEscapeKeyReportedDown")) is bool, "mouse-input-observation-types")
        modifiers = row.get("modifiers")
        capture.fields_match(modifiers, {"relevantFlags": 0, "command": False, "shift": False,
                                         "option": False, "control": False}, "mouse-escape-held-modifier")
        capture.require(integer(modifiers.get("sessionFlags"), "mouse-escape-session-flags") & 0x1E0000 == 0,
                        "mouse-escape-session-modifiers")
        if index == 0:
            capture.require(observed <= times[0] and row["escapeKeyReportedDown"] is False,
                            "mouse-before-key-state")
        elif index == 1:
            capture.require(times[1] <= observed <= times[2], "mouse-before-key-up-state")
        else:
            capture.require(times[3] <= observed, "mouse-after-key-up-state")
    return gestures, {"protocol": {key: value for key, value in protocol.items() if key not in ("case", "mouseProducer")},
                      "sourceGeometry": case["sourceGeometry"], "targetGeometry": geometry["targetGeometry"],
                      "cancelGeometry": signatures[0]}, timing


def pointer_evidence(case, gestures, producer):
    events = case.get("mouseEvents")
    capture.require(isinstance(events, list) and len(events) <= 256, "mouse-pointer-journal")
    if producer == "xctest":
        capture.require(events == [], "mouse-observer-posted-pointer-in-xctest-case")
        return {"observerPointerPostCount": 0, "gestureReleases": {}}
    previous, used, releases = -1, [], {}
    for row in events:
        capture.fields_match(row, {"scope": "plain-gesture", "postCalled": True, "eventTap": "cghidEventTap",
                                  "sourceStateID": 1}, "mouse-quartz-pointer-binding")
        before, after = interval(row, "systemUptimeBeforePost", "systemUptimeAfterPost")
        capture.require(before >= previous, "mouse-quartz-post-order")
        previous = after
        flags = integer(row.get("postedFlags"), "mouse-pointer-flags")
        capture.require(flags & 0x1E0000 == 0, "mouse-pointer-modifiers")
        sources.point(row.get("location"), "mouse-pointer-location")
    for gesture in gestures:
        start, end = gesture["startedSystemUptime"], gesture["releaseObservedSystemUptime"]
        rows = [row for row in events if start <= row["systemUptimeBeforePost"] <= row["systemUptimeAfterPost"] <= end]
        source, target = gesture["sourcePoint"], gesture["targetPoint"]
        distance = math.hypot(target["x"] - source["x"], target["y"] - source["y"])
        steps = max(1, math.ceil(distance / 10))
        capture.require(steps <= 100 and [r.get("eventType") for r in rows] == [1] + [6] * steps + [2],
                        "mouse-quartz-pointer-sequence")
        capture.require(rows[0]["location"] == source and rows[-1]["location"] == target, "mouse-quartz-pointer-endpoints")
        for index, row in enumerate(rows[1:-1], 1):
            fraction = index / steps
            expected = {axis: source[axis] + (target[axis] - source[axis]) * fraction for axis in ("x", "y")}
            capture.require(all(math.isclose(row["location"][axis], expected[axis], rel_tol=0, abs_tol=1e-6)
                                for axis in expected), "mouse-quartz-path-not-straight")
        capture.require(rows[1]["systemUptimeBeforePost"] >= rows[0]["systemUptimeAfterPost"] + INITIAL_HOLD_SECONDS - 1e-6,
                        "mouse-quartz-initial-hold")
        capture.require(rows[-2]["systemUptimeAfterPost"] <= gesture["lastMovementPostCompletedSystemUptime"]
                        <= gesture["entryObservation"]["observedSystemUptime"], "mouse-quartz-motion-after-entry")
        capture.require(rows[-1]["systemUptimeBeforePost"] >= gesture["releaseScheduledSystemUptime"],
                        "mouse-quartz-release-too-early")
        capture.require(rows[-1]["systemUptimeAfterPost"] <= gesture["releaseRequestCompletedSystemUptime"],
                        "mouse-quartz-release-request-before-post-completed")
        releases[gesture["phase"]] = {"before": rows[-1]["systemUptimeBeforePost"], "after": rows[-1]["systemUptimeAfterPost"]}
        used.extend(rows)
    capture.require(used == events, "mouse-quartz-extra-pointer-posts")
    capture.require(case["escapePostTiming"]["upCompletedSystemUptime"] < releases["cancel"]["before"],
                    "mouse-quartz-released-before-escape")
    return {"observerPointerPostCount": len(events), "gestureReleases": releases}


def snapshot_evidence(stage, context, case_name, case, gestures, passed):
    initial_start, initial_end = interval(case.get("mouseDriverInitialWorkspaceTiming"))
    capture.require(initial_end < gestures[0]["startedSystemUptime"], "mouse-initial-workspace-after-input")
    cancel_start, cancel_end = interval(case.get("escapeCancellationObservationTiming"))
    capture.require(cancel_start >= gestures[0]["releaseObservedSystemUptime"], "mouse-cancellation-observed-before-release")
    timing = {"initial": [initial_start, initial_end], "cancel": [cancel_start, cancel_end]}
    if passed:
        fresh_start, fresh_end = interval(case.get("freshDropObservationTiming"))
        capture.require(cancel_end < gestures[1]["startedSystemUptime"]
                        and fresh_start >= gestures[1]["releaseObservedSystemUptime"], "mouse-fresh-workspace-order")
        timing["fresh"] = [fresh_start, fresh_end]
    stages = case.get("stages")
    expected = ["00-before-drag", "d13-cancel-after-release"] + (["d13-fresh-after-release"] if passed else [])
    capture.require(isinstance(stages, list) and [row.get("stage") for row in stages] == expected, "mouse-snapshot-stage-set")
    snapshots = [case.get("setupSnapshot", {}), *stages]
    capture.require(snapshots[0].get("stage") == "setup-before-hit-checks", "mouse-setup-snapshot")
    directory = evidence_for(stage, case_name) / "orchard"
    previous, durations = -1, {}
    for row in snapshots:
        capture.fields_match(row, {"captureKind": "target-ax-only", "imagesCaptured": False,
                                  "mouseDownSent": False, "leftButtonReportedDown": False}, "mouse-snapshot-policy")
        capture.require(isinstance(row.get("workspaceAXLabels"), list)
                        and all(isinstance(v, str) for v in row["workspaceAXLabels"]), "mouse-snapshot-labels")
        capture.require(not any(key in row for key in ("image", "imageSHA256", "pixelWidth", "pixelHeight")),
                        "mouse-snapshot-unexpected-image")
        before, after = interval(row, "captureStartedSystemUptime", "captureCompletedSystemUptime")
        capture.require(previous <= before, "mouse-snapshot-clock-order")
        previous = after
        capture.require(all(after <= g["startedSystemUptime"] or before >= g["releaseObservedSystemUptime"] for g in gestures),
                        "mouse-snapshot-during-gesture")
        name = row["stage"]
        capture.require(read_json(directory / (name + ".json"), "mouse-snapshot") == row, "mouse-snapshot-report-mismatch")
        if name == "00-before-drag":
            capture.require(after <= initial_start, "mouse-initial-snapshot-order")
        if name == "d13-cancel-after-release":
            capture.require(before >= cancel_end, "mouse-cancel-snapshot-order")
        if name == "d13-fresh-after-release":
            capture.require(before >= timing["fresh"][1], "mouse-fresh-snapshot-order")
        durations[name] = after - before
    capture.require(not any(evidence_for(stage, case_name).rglob("*.png")), "mouse-unexpected-image-file")
    return {"workspaceObservationTimings": timing, "snapshotSeconds": durations, "snapshotCount": len(snapshots)}


def driver_evidence(stage, context, case_name, case, gestures, passed):
    driver = case.get("mouseControlDriver")
    config = context["mouseConfigurations"][case_name]
    provenance = context["provenance"]
    producer = bindings(case_name)["mouseProducer"]
    count = (2 if passed else 1) if producer == "xctest" else 0
    directory = runtime_directory(stage, case_name)
    runner = stage / RUNNER_RELATIVE
    expected = {"inputDriver": "XCTest", "status": "completed", "case": case_name, "nonce": config["nonce"],
        "runnerBundleIdentifier": RUNNER_ID, "runnerApplicationPath": str(runner),
        "runnerExecutablePath": str(runner / "Contents/MacOS/QualityReview-Runner"),
        "mouseTestsExecutablePath": str(runner / TEST_RELATIVE), "projectPath": str(stage / PROJECT_RELATIVE),
        "mouseConfigurationPath": str(directory / "configuration.json"),
        "mouseXCTestRunPath": str(stage / "MouseDerivedData/Build/Products" / ("D13-" + case_name + ".xctestrun")),
        "mouseConfigurationSHA256": provenance["mouseConfigurationsSHA256"][case_name],
        "mouseXCTestRunSHA256": provenance["mouseXCTestRunSHA256"][case_name],
        "readyTimeoutSeconds": 60, "gestureTimeoutSeconds": 20, "lifetimeSeconds": 150, "stopTimeoutSeconds": 8,
        "publishedRequestCount": count, "completedRequestCount": count, "processExitStatus": 0,
        **{key: provenance[key] for key in ("mouseRunnerInfoSHA256", "mouseRunnerExecutableSHA256", "mouseTestsExecutableSHA256")}}
    capture.fields_match(driver, expected, "mouse-driver-identity-or-completion")
    runner_pid = integer(driver.get("runnerPID"), "mouse-runner-pid", minimum=1)
    process_pid = integer(driver.get("processPID"), "mouse-process-pid", minimum=1)
    capture.require(len({runner_pid, process_pid, case["sourceApplicationPID"], case["targetApplicationPID"]}) == 4,
                    "mouse-driver-pid-collision")
    started, expires = interval(driver, "startedSystemUptime", "expiresSystemUptime")
    capture.require(expires - started <= 150 + 1e-6, "mouse-runner-lifetime")
    retirements = driver.get("runnerRetirementObservations")
    capture.require(isinstance(retirements, list) and len(retirements) <= 161, "mouse-runner-retirement-count")
    capture.fields_match(driver.get("cleanup"), {"stopConfirmed": True, "processStopped": True,
        "runnerRegistryEmpty": True, "finishedPublished": True, "finishedAcknowledged": True,
        "normalCompletion": True, "terminationRequested": False, "forceTerminationRequested": False,
        "gestureOutstanding": False, "runnerRetirementObserved": bool(retirements), "timeoutSeconds": 8,
        "errors": []}, "mouse-runner-cleanup")
    cleanup_elapsed = clock(driver["cleanup"], "elapsedSeconds")
    requests = driver.get("requests")
    publications = driver.get("requestPublications", [])
    capture.require(isinstance(requests, list) and len(requests) == count
                    and isinstance(publications, list) and len(publications) == count, "mouse-request-count")
    request_fields = {"schema", "case", "nonce", "action", "theme", "requestIndex", "phase", "runnerPID",
        "sourceBundleIdentifier", "sourceApplicationPath", "sourceExecutablePath", "sourceWindowTitle", "sourcePID",
        "targetBundleIdentifier", "targetApplicationPath", "targetExecutablePath", "targetWindowTitle", "targetPID",
        "coordinateSpace", "sourcePoint", "targetPoint", "sourceFrame", "targetFrame", "initialHoldSeconds",
        "velocityPointsPerSecond", "destinationHoldSeconds", "createdSystemUptime", "expiresSystemUptime"}
    for index, request in enumerate(requests, 1):
        gesture = gestures[index - 1]
        capture.require(isinstance(request, dict) and set(request) == request_fields, "mouse-request-fields")
        for key in ("sourcePoint", "targetPoint"):
            sources.point(request.get(key), "mouse-request-point")
        for key in ("sourceFrame", "targetFrame"):
            rectangle(request.get(key), "mouse-request-frame")
        capture.fields_match(request, {"schema": 1, "case": case_name, "nonce": config["nonce"],
            "action": "click-drag-hold", "theme": "orchard", "requestIndex": index, "phase": gesture["phase"],
            "runnerPID": runner_pid, "sourceBundleIdentifier": sources.SOURCE_ID,
            "sourceApplicationPath": str(stage / sources.SOURCE_BUNDLE),
            "sourceExecutablePath": str(stage / sources.SOURCE_BUNDLE / "Contents/MacOS/NativeDragSource"),
            "sourceWindowTitle": "Native Drag Source", "sourcePID": case["sourceApplicationPID"],
            "targetBundleIdentifier": "app.lemulip.NativeDragControl", "targetApplicationPath": str(stage / "Native Drag Control.app"),
            "targetExecutablePath": str(stage / "Native Drag Control.app/Contents/MacOS/NativeDragControl"),
            "targetWindowTitle": "Native Drag Control", "targetPID": case["targetApplicationPID"],
            "coordinateSpace": "quartz-global-top-left", "initialHoldSeconds": INITIAL_HOLD_SECONDS,
            **{key: gesture[key] for key in ("sourcePoint", "targetPoint", "sourceFrame", "targetFrame")}}, "mouse-request-binding")
        capture.require(type(request["velocityPointsPerSecond"]) in (int, float) and request["velocityPointsPerSecond"] == VELOCITY
                        and type(request["destinationHoldSeconds"]) in (int, float)
                        and request["destinationHoldSeconds"] == gesture["destinationHoldSeconds"], "mouse-request-schedule")
        created, deadline = interval(request, "createdSystemUptime", "expiresSystemUptime")
        capture.require(gesture["startedSystemUptime"] <= created < deadline <= expires
                        and deadline - created <= 20 + 1e-6, "mouse-request-deadline")
        capture.fields_match(publications[index - 1], {"requestIndex": index}, "mouse-request-publication-index")
        published = clock(publications[index - 1], "systemUptime")
        capture.require(created <= published <= gesture["requestPublishedSystemUptime"], "mouse-request-publication-clock")
        capture.require(read_json(directory / f"request-{index}.json", "mouse-request") == request, "mouse-request-file-mismatch")
    finish = driver.get("finished")
    capture.require(isinstance(finish, dict) and set(finish) ==
        {"schema", "case", "nonce", "action", "requestCount", "createdSystemUptime"}, "mouse-finished-fields")
    capture.fields_match(finish, {"schema": 1, "case": case_name, "nonce": config["nonce"],
                                "action": "finished", "requestCount": count}, "mouse-finished-binding")
    finish_time = clock(finish, "createdSystemUptime")
    capture.require(finish_time >= gestures[-1]["releaseObservedSystemUptime"], "mouse-finished-before-release")
    capture.require(read_json(directory / "finished.json", "mouse-finished") == finish, "mouse-finished-file-mismatch")
    capture.require({path.name for path in directory.iterdir()} == {"configuration.json", "xcodebuild.log", "finished.json",
                    *(f"request-{index}.json" for index in range(1, count + 1))}, "mouse-runtime-file-set")
    log = directory / "xcodebuild.log"
    information = log.lstat()
    capture.require(stat.S_ISREG(information.st_mode) and 0 < information.st_size <= 8_388_608, "mouse-runner-log-file")
    data = log.read_bytes()
    capture.require(len(data) == information.st_size and data.endswith(b"\n"), "mouse-runner-log-truncated")
    lines = [line for line in data.decode("utf-8").splitlines() if line.startswith("LEMULIP_MOUSE_")]
    expected_markers = ["READY"] + [marker for _ in requests for marker in ("BEGIN", "END")] + ["FINISHED"]
    receipts = driver.get("markerReceipts")
    capture.require(isinstance(receipts, list) and len(receipts) == len(expected_markers) == len(lines), "mouse-marker-count")
    base = {"schema", "case", "nonce", "systemUptime", "runnerPID", "leftButtonReportedDown", "hidLeftButtonReportedDown",
            "rightButtonReportedDown", "centerButtonReportedDown", "escapeKeyReportedDown", "hidEscapeKeyReportedDown",
            "modifierFlags", "hidModifierFlags"}
    previous, boundaries = started, {}
    for line, marker, receipt in zip(lines, expected_markers, receipts):
        prefix, separator, payload = line.partition(" ")
        capture.require(separator == " " and prefix == "LEMULIP_MOUSE_" + marker, "mouse-marker-order")
        witness = decoded_json(payload, "mouse-marker")
        fields = base | ({"requestIndex", "phase", "sourcePID", "targetPID"} if marker in ("BEGIN", "END") else set())
        if marker == "BEGIN":
            fields |= {"sourceWindowFrame", "targetWindowFrame", "sourceScreenPoint", "targetScreenPoint"}
        elif marker == "FINISHED":
            fields.add("requestCount")
        capture.require(isinstance(witness, dict) and set(witness) == fields, "mouse-marker-fields")
        capture.fields_match(witness, {"schema": 1, "case": case_name, "nonce": config["nonce"], "runnerPID": runner_pid},
                             "mouse-marker-identity")
        capture.fields_match(receipt, {"marker": marker, "line": line, "witness": witness}, "mouse-marker-receipt-mismatch")
        observed = clock(receipt, "observedSystemUptime")
        when = clock(witness, "systemUptime")
        capture.require(previous <= when <= observed, "mouse-marker-clock")
        previous = when
        for key in ("leftButtonReportedDown", "hidLeftButtonReportedDown", "rightButtonReportedDown", "centerButtonReportedDown",
                    "escapeKeyReportedDown", "hidEscapeKeyReportedDown"):
            capture.fields_match(witness, {key: False}, "mouse-marker-held-input")
        for key in ("modifierFlags", "hidModifierFlags"):
            flags = integer(witness.get(key), "mouse-marker-modifier-flags")
            capture.require(flags <= 0xFFFFFFFF and flags & 0x1E0000 == 0, "mouse-marker-held-modifier")
        if marker == "READY":
            capture.require(when <= gestures[0]["startedSystemUptime"] and observed <= gestures[0]["startedSystemUptime"],
                            "mouse-runner-not-ready-before-gesture")
        elif marker in ("BEGIN", "END"):
            index = integer(witness.get("requestIndex"), "mouse-marker-request-index", minimum=1)
            capture.require(index <= count, "mouse-marker-unrequested-gesture")
            request, gesture = requests[index - 1], gestures[index - 1]
            capture.fields_match(witness, {"phase": request["phase"], "sourcePID": case["sourceApplicationPID"],
                                         "targetPID": case["targetApplicationPID"]}, "mouse-marker-request-binding")
            capture.require(request["createdSystemUptime"] <= when <= request["expiresSystemUptime"], "mouse-marker-request-expired")
            boundary = boundaries.setdefault(request["phase"], {})
            capture.require(marker not in boundary, "mouse-marker-duplicate-boundary")
            boundary[marker] = when
            if marker == "BEGIN":
                capture.require(when <= gesture["entryObservation"]["receiverEntrySystemUptime"], "mouse-entry-before-public-api")
                for actual_key, expected_key in (("sourceWindowFrame", "sourceFrame"), ("targetWindowFrame", "targetFrame"),
                    ("sourceScreenPoint", "sourcePoint"), ("targetScreenPoint", "targetPoint")):
                    actual = rectangle(witness.get(actual_key), "mouse-marker-frame") if actual_key.endswith("Frame") \
                        else sources.point(witness.get(actual_key), "mouse-marker-point")
                    capture.require(all(abs(actual[key] - request[expected_key][key]) <= 1 for key in actual), "mouse-marker-geometry")
            else:
                capture.require(boundary.get("BEGIN", math.inf) < when <= observed
                                <= gesture["releaseRequestCompletedSystemUptime"],
                                "mouse-public-api-end-order")
                if request["phase"] == "cancel":
                    capture.require(when >= case["escapePostTiming"]["upCompletedSystemUptime"], "mouse-public-api-ended-before-escape")
        else:
            capture.fields_match(witness, {"requestCount": count}, "mouse-finished-witness-count")
            capture.require(when >= finish_time, "mouse-finished-before-request")
    finished_observed = clock(receipts[-1], "observedSystemUptime")
    previous_retirement = finished_observed
    retirement_fields = {"runnerPID", "observedSystemUptime", "finishedObservedSystemUptime", "registryCount",
        "boundRunnerPIDMatches", "bundleURLMissing", "executableURLMissing", "finishedAcknowledged",
        "finishedPublished", "gestureOutstanding", "processNotTerminated"}
    for retirement in retirements:
        capture.require(isinstance(retirement, dict) and set(retirement) == retirement_fields,
                        "mouse-runner-retirement-fields")
        capture.fields_match(retirement, {"runnerPID": runner_pid, "registryCount": 1,
            "boundRunnerPIDMatches": True, "bundleURLMissing": True, "executableURLMissing": True,
            "finishedAcknowledged": True, "finishedPublished": True, "gestureOutstanding": False},
            "mouse-runner-retirement-identity")
        capture.require(type(retirement["processNotTerminated"]) is bool, "mouse-runner-retirement-process-state")
        capture.require(clock(retirement, "finishedObservedSystemUptime") == finished_observed,
                        "mouse-runner-retirement-finished-binding")
        when = clock(retirement, "observedSystemUptime")
        capture.require(previous_retirement < when <= finish_time + min(8, cleanup_elapsed),
                        "mouse-runner-retirement-order-or-bound")
        previous_retirement = when
    return {"runnerPID": runner_pid, "processPID": process_pid, "requestCount": count,
        "idleRunnerVerified": producer == "quartz", "normalCompletion": True, "boundaries": boundaries,
        "runnerRetirementObservations": retirements,
        "logSHA256": capture.sha256(log), "markerReceipts": receipts,
        "requestSHA256": {str(index): capture.sha256(directory / f"request-{index}.json") for index in range(1, count + 1)},
        "finishedSHA256": capture.sha256(directory / "finished.json")}


def receiver_evidence(stage, context, case_name, case, gestures, pointer, passed):
    path = evidence_for(stage, case_name) / "orchard/receiver.jsonl"
    rows = sources.read_trace(path, "mouse-receiver", case["targetApplicationPID"])
    starts = [row for row in rows if row["event"] == "application-start"]
    ends = [row for row in rows if row["event"] == "application-terminated"]
    capture.require(len(starts) == len(ends) == 1 and rows[0] == starts[0] and rows[-1] == ends[0], "mouse-receiver-lifecycle")
    capture.fields_match(starts[0], {"bundleIdentifier": "app.lemulip.NativeDragControl", "theme": "orchard",
        "originalSHA256": context["fixtures"], "fixtureFilenames": sorted(context["fixtures"]),
        "stagingRoot": str(stage), "bundlePath": str(stage / "Native Drag Control.app"),
        "executablePath": str(stage / "Native Drag Control.app/Contents/MacOS/NativeDragControl")}, "mouse-receiver-start")
    for row in rows:
        capture.fields_match(row, bindings(case_name), "mouse-receiver-case-binding")
        for key in ("originalBytesUnchanged", "fixtureFileSetUnchanged"):
            if key in row:
                capture.require(row[key] is True, "mouse-receiver-originals-changed")
    capture.fields_match(ends[0], {"originalBytesUnchanged": True, "fixtureFileSetUnchanged": True}, "mouse-receiver-termination-originals")
    callbacks = [row for row in rows if row["event"] in sources.RECEIVER_CALLBACKS]
    capture.require(callbacks, "mouse-receiver-callbacks-missing")
    for row in callbacks:
        integer(row.get("sequenceNumber"), "mouse-receiver-sequence")
        capture.fields_match(row, {"originalBytesUnchanged": True, "fixtureFileSetUnchanged": True,
                                  "sourceAllowedOperationMask": 1}, "mouse-receiver-copy-offer")
        capture.require(isinstance(row.get("pasteboardTypes"), list) and "public.file-url" in row["pasteboardTypes"]
                        and all(isinstance(v, str) for v in row["pasteboardTypes"]), "mouse-receiver-pasteboard")
    sequences = {g["entryObservation"]["sequenceNumber"] for g in gestures}
    capture.require(len(sequences) == len(gestures) and {r["sequenceNumber"] for r in callbacks} == sequences,
                    "mouse-receiver-extra-or-reused-sequence")
    phases = {}
    existing, single = context["roles"]["Existing"], context["roles"]["Single"]
    for gesture in gestures:
        phase, entry = gesture["phase"], gesture["entryObservation"]
        group = [r for r in callbacks if r["sequenceNumber"] == entry["sequenceNumber"]]
        entries = [r for r in group if r["event"] == "draggingEntered" and r.get("returnedCopy") is True]
        matching = [r for r in entries if r["recordIndex"] == entry["receiverRecordIndex"]
                    and r["systemUptime"] == entry["receiverEntrySystemUptime"]]
        capture.require(len(matching) == 1 and matching[0] == entries[0]
                        and gesture["startedSystemUptime"] <= entries[0]["systemUptime"], "mouse-live-entry-unbound")
        accepted = [r for r in group if r["event"] == "performDragOperation" and r.get("accepted") is True]
        should_accept = phase == "fresh" or not passed
        if should_accept:
            capture.require(len(accepted) == 1, "mouse-drop-acceptance-count")
            capture.require(accepted[0].get("selectedFilenames") == sorted([existing, single]), "mouse-drop-selected-files")
            capture.require(accepted[0]["systemUptime"] > entry["receiverEntrySystemUptime"], "mouse-drop-before-entry")
            if phase in pointer["gestureReleases"]:
                capture.require(accepted[0]["systemUptime"] >= pointer["gestureReleases"][phase]["before"],
                                "mouse-quartz-acceptance-before-release")
        else:
            capture.require(not accepted, "mouse-cancelled-sequence-accepted")
        if phase == "cancel":
            before_key = [r for r in group if r["systemUptime"] < case["escapePostTiming"]["downStartedSystemUptime"]]
            capture.require(entries[0] in before_key and not any(r["event"] == "draggingExited" for r in before_key),
                            "mouse-cancel-not-single-entry")
            capture.require(not any(r["event"] == "performDragOperation" for r in before_key), "mouse-drop-before-escape")
            if accepted:
                capture.require(accepted[0]["systemUptime"] >= case["escapePostTiming"]["upCompletedSystemUptime"],
                                "mouse-cancel-acceptance-before-escape-completed")
        phases[phase] = {"sequenceNumber": entry["sequenceNumber"], "entry": matching[0],
                         "accepted": accepted[0] if accepted else None}
    return {"receiverSHA256": capture.sha256(path), "pid": case["targetApplicationPID"], "phases": phases,
        "escapeSendEventReceipts": [r for r in rows if r["event"] == "escape-send-event"]}


def source_evidence(stage, context, case_name, case, gestures, receiver, driver, passed):
    path = evidence_for(stage, case_name) / "orchard/source.jsonl"
    rows = sources.read_trace(path, "mouse-source", case["sourceApplicationPID"])
    for row in rows:
        capture.fields_match(row, bindings(case_name), "mouse-source-case-binding")
        capture.require(row["event"] in sources.SOURCE_EVENTS | sources.ACTIVATION_SOURCE_EVENTS, "mouse-source-event")
        for key in ("originalBytesUnchanged", "fixtureFileSetUnchanged"):
            if key in row:
                capture.require(row[key] is True, "mouse-source-originals-changed")
    ready = [r for r in rows if r["event"] == "source-ready"]
    ends = [r for r in rows if r["event"] == "application-terminating"]
    capture.require(len(ready) == len(ends) == 1 and rows[-1] == ends[0], "mouse-source-lifecycle")
    source_keys = (*sources.SOURCE_KEYS, "sourceCommit", "sourceTree", "architecture", "observerExperimentCommit", "observerExperimentTree")
    capture.fields_match(ready[0], {**{key: context["provenance"][key] for key in source_keys},
        "bundleIdentifier": sources.SOURCE_ID, "executableName": sources.SOURCE_EXECUTABLE,
        "bundleName": sources.SOURCE_BUNDLE, "stagingRoot": str(stage), "sourceBundlePath": str(stage / sources.SOURCE_BUNDLE),
        "geometryCoordinateSpace": "Quartz-global-top-left", "originalSHA256": context["fixtures"]}, "mouse-source-ready-binding")
    capture.fields_match(ends[0], {"originalBytesUnchanged": True, "fixtureFileSetUnchanged": True,
                                  "activeSession": False, "sessionCount": len(gestures)}, "mouse-source-termination")
    capture.require(ready[0]["systemUptime"] < gestures[0]["startedSystemUptime"], "mouse-source-ready-after-input")
    for key in ("requestedSourcePointCG", "sourcePointCG"):
        capture.require(sources.point(ready[0].get(key), "mouse-source-ready-point") == gestures[0]["sourcePoint"], "mouse-source-ready-point-binding")
    for key, geometry_key in (("actualWindowFrameCG", "nativeWindow"), ("imageFrameCG", "nativeIcon")):
        capture.require(ready[0].get(key) == sources.rect_string(case["sourceGeometry"][geometry_key], "mouse-source-ready-rectangle"),
                        "mouse-source-ready-frame-binding")
    callbacks = [r for r in rows if r["event"] in sources.CALLBACKS]
    capture.require({r.get("sessionIndex") for r in callbacks} == set(range(1, len(gestures) + 1)), "mouse-source-session-count")
    sessions, previous_end = {}, -1
    for index, gesture in enumerate(gestures, 1):
        group = [r for r in callbacks if r.get("sessionIndex") == index]
        begins = [r for r in group if r["event"] == "source-will-begin"]
        ended = [r for r in group if r["event"] == "source-ended"]
        capture.require(len(begins) == len(ended) == 1 and group[0] == begins[0] and group[-1] == ended[0],
                        "mouse-source-session-lifecycle")
        phase, target = gesture["phase"], receiver["phases"][gesture["phase"]]
        previous = -1
        for row in group:
            capture.fields_match(row, {"sessionIndex": index, "sequenceNumber": target["sequenceNumber"],
                "filename": context["roles"]["Single"], "offeredOperationMask": 1,
                "callbackPointCoordinateSpace": "AppKit-screen-bottom-left"}, "mouse-source-session-binding")
            when = clock(row, "callbackSystemUptime")
            capture.require(previous <= when <= row["systemUptime"], "mouse-source-callback-clock")
            previous = when
            sources.point(row.get("callbackPointScreen"), "mouse-source-callback-point")
            sources.point(row.get("observedCursorCG"), "mouse-source-cursor")
            capture.require(type(row.get("applicationActive")) is bool
                            and type(row.get("animatesToStartingPositionsOnCancelOrFail")) is bool,
                            "mouse-source-state-types")
            capture.require(isinstance(row.get("pasteboardTypes"), list) and "public.file-url" in row["pasteboardTypes"],
                            "mouse-source-pasteboard")
        begin_time, end_time = begins[0]["callbackSystemUptime"], ended[0]["callbackSystemUptime"]
        capture.require(gesture["startedSystemUptime"] <= begin_time <= target["entry"]["systemUptime"]
                        and previous_end < begin_time, "mouse-source-session-order")
        previous_end = end_time
        if phase in driver["boundaries"]:
            capture.require(driver["boundaries"][phase]["BEGIN"] <= begin_time, "mouse-source-begin-before-xctest-call")
        operation = 1 if phase == "fresh" or not passed else 0
        capture.fields_match(ended[0], {"operationRawValue": operation,
            "originalBytesUnchanged": True, "fixtureFileSetUnchanged": True}, "mouse-source-ended-operation")
        capture.fields_match(begins[0], {"originalBytesUnchanged": True, "fixtureFileSetUnchanged": True}, "mouse-source-begin-originals")
        if operation == 1:
            capture.require(target["accepted"] is not None and end_time >= target["accepted"]["systemUptime"], "mouse-source-copy-without-receiver")
        else:
            capture.require(target["accepted"] is None and end_time >= case["escapePostTiming"]["downStartedSystemUptime"],
                            "mouse-source-none-before-escape-or-with-acceptance")
        # NONE after release is valid here: the complete strict final workspace
        # and independent fresh drop decide cancellation, not callback latency.
        sessions[phase] = {"begin": begins[0], "end": ended[0], "noneCallbackAfterObservedRelease":
            operation == 0 and end_time >= gesture["releaseObservedSystemUptime"]}
    return {"sourceSHA256": capture.sha256(path), "pid": case["sourceApplicationPID"], "traceComplete": True,
        "classification": "cancellation-and-fresh-drop-proven" if passed else "copy-with-completed-release",
        "sessions": sessions, "escapeSendEventReceipts": [r for r in rows if r["event"] == "escape-send-event"],
        "interpretation": "A NONE callback may follow observed mouse release. Missing sendEvent receipts do not prove nondelivery. XCTest END is an API return boundary, not the exact physical release timestamp."}


def activation_evidence(stage, context, case_name, case, gestures, source_result, passed):
    requests = case.get("targetRaiseRequests")
    phases = activation.RAISE_PHASES + (["focus-native-source"] if passed else [])
    capture.require(isinstance(requests, list) and len(requests) == len(phases), "mouse-target-raise-count")
    previous = -1
    for index, (row, phase) in enumerate(zip(requests, phases)):
        capture.fields_match(row, {"requestIndex": index, "phase": phase, "targetRaisePolicy": "present",
            "performed": True, "status": 0, "targetPID": case["targetApplicationPID"],
            "targetWindowTitle": "Native Drag Control", "mouseDownSent": False}, "mouse-target-raise-binding")
        before, after = interval(row)
        capture.require(before >= previous, "mouse-target-raise-order")
        previous = after
        if index < 4:
            capture.require(after < gestures[0]["startedSystemUptime"], "mouse-target-raise-during-first-gesture")
        else:
            capture.require(gestures[0]["releaseObservedSystemUptime"] < before <= after < gestures[1]["startedSystemUptime"],
                            "mouse-target-raise-during-fresh-gesture")
    directory = evidence_for(stage, case_name) / "orchard"
    rows = sources.read_trace(directory / "activation.jsonl", "mouse-activation", case["targetApplicationPID"])
    for row in rows:
        capture.fields_match(row, bindings(case_name), "mouse-activation-binding")
        capture.require(row["event"] in activation.ACTIVATION_EVENTS, "mouse-activation-event")
        activation.event_clock(row)
        for key in ("originalBytesUnchanged", "fixtureFileSetUnchanged"):
            if key in row:
                capture.require(row[key] is True, "mouse-activation-originals-changed")
    starts = [r for r in rows if r["event"] == "activation-start"]
    ready = [r for r in rows if r["event"] == "activation-ready"]
    ends = [r for r in rows if r["event"] == "activation-terminating"]
    capture.require(len(starts) == len(ready) == len(ends) == 1 and rows[0] == starts[0] and rows[-1] == ends[0],
                    "mouse-activation-lifecycle")
    keys = ("nativeDragControlSourceSHA256", "controlGUI_SHA256", "sourceCommit", "sourceTree", "architecture",
            "observerExperimentCommit", "observerExperimentTree")
    capture.fields_match(starts[0], {**{key: context["provenance"][key] for key in keys},
        "bundleIdentifier": "app.lemulip.NativeDragControl", "executableName": "NativeDragControl",
        "bundleName": "Native Drag Control.app", "targetBundlePath": str(stage / "Native Drag Control.app"),
        "stagingRoot": str(stage), "originalSHA256": context["fixtures"]}, "mouse-activation-start")
    capture.fields_match(ready[0], {"windowTitle": "Native Drag Control", "normalNSWindow": True,
        "windowClass": "NSWindow", "targetAXRaiseOverrideInstalled": False,
        "targetRaiseObservation": "observer-request-ledger-only"}, "mouse-target-window-policy")
    capture.require(type(ready[0].get("styleMask")) is int and type(ready[0].get("windowLevel")) is int,
                    "mouse-target-window-policy-types")
    capture.require(activation.event_clock(ready[0]) < gestures[0]["startedSystemUptime"], "mouse-target-ready-after-input")
    capture.fields_match(ends[0], {"originalBytesUnchanged": True, "fixtureFileSetUnchanged": True}, "mouse-activation-end-originals")
    capture.require(not any(r["event"].startswith("target-ax-raise-") for r in rows), "mouse-unexpected-target-raise-hook")
    target_states = [activation.window_state(row, "mouse-activation") for row in rows]
    number = integer(ready[0].get("windowNumber"), "mouse-target-window-number", minimum=1)
    capture.require(ready[0]["windowVisible"] is True and all(row["windowNumber"] in (None, number) for row in rows),
                    "mouse-target-window-identity")
    cancel = gestures[0]
    pairs = activation.paired_events(rows, requests, {"dragDownBeforePost": cancel["startedSystemUptime"],
        "releaseAfterPost": cancel["releaseObservedSystemUptime"]})
    for pair in pairs:
        pair["enteredDuringCancelCallInterval"] = pair.pop("enteredDuringCancelDrag")
    source_rows = sources.read_trace(directory / "source.jsonl", "mouse-activation-source", case["sourceApplicationPID"])
    source_ready = next(row for row in source_rows if row["event"] == "source-ready")
    source_number = integer(source_ready.get("windowNumber"), "mouse-source-window-number", minimum=1)
    capture.fields_match(source_result["sessions"]["cancel"]["begin"], {"applicationActive": True,
        "keyWindowNumber": source_number, "windowNumber": source_number, "windowIsKey": True}, "mouse-source-not-initially-key")
    state_events = sources.CALLBACKS | sources.ACTIVATION_SOURCE_EVENTS | {"source-ready", "application-became-active", "application-resigned-active"}
    source_states = [activation.window_state(row, "mouse-activation-source") for row in source_rows if row["event"] in state_events]
    down = case["escapePostTiming"]["downStartedSystemUptime"]
    return {"activationSHA256": capture.sha256(directory / "activation.jsonl"), "traceComplete": True,
        "targetWindowClass": "NSWindow", "initialSourceActiveAndKey": True, "targetRaiseRequests": requests,
        "targetStateBeforeEscape": activation.state_at(target_states, down),
        "sourceStateBeforeEscape": activation.state_at(source_states, down),
        "targetBecameActiveDuringCancelCallInterval": [r for r in target_states
            if r["event"] == "application-became-active" and cancel["startedSystemUptime"] <= r["systemUptime"]
            <= cancel["releaseObservedSystemUptime"]], "pairs": pairs,
        "sourceStateReceipts": source_states, "targetStateReceipts": target_states,
        "interpretation": "Activation receipts describe each process and remain separate from strict workspace outcomes. The cancel-call interval brackets API dispatch and observed release; it does not claim an exact XCTest button-down or button-up timestamp. The target has no AXRaise hook."}


def classify(stage, context, case_name, returncode):
    bindings(case_name)
    native = None
    try:
        directory = evidence_for(stage, case_name)
        aggregate = read_json(directory / "report.json", "mouse-aggregate")
        case = read_json(directory / "orchard/report.json", "mouse-case")
        native = native_outcome(stage, context, case_name, returncode, aggregate, case)
        gestures, signature, timing = gesture_evidence(case, case_name, native["passed"])
        pointer = pointer_evidence(case, gestures, bindings(case_name)["mouseProducer"])
        snapshots = snapshot_evidence(stage, context, case_name, case, gestures, native["passed"])
        driver = driver_evidence(stage, context, case_name, case, gestures, native["passed"])
        receiver = receiver_evidence(stage, context, case_name, case, gestures, pointer, native["passed"])
        source = source_evidence(stage, context, case_name, case, gestures, receiver, driver, native["passed"])
        activation_result = activation_evidence(stage, context, case_name, case, gestures, source, native["passed"])
        input_source = case.get("inputSource")
        capture.fields_match(input_source, {"kind": "shared-hid-keyboard-filter-comparison", "sourceStateID": 1}, "mouse-input-source")
        clock(input_source, "localEventsSuppressionInterval")
        for key in ("previousSuppressionIntervalFilter", "previousRemoteMouseDragFilter", "suppressionIntervalFilter", "remoteMouseDragFilter"):
            integer(input_source.get(key), "mouse-input-filter")
        signature["inputSource"] = input_source
        return {"target": "control", **bindings(case_name), "observerLifecycle": "appkit", "captureComparison": "ax-only",
            **native, "strictNativeOutcome": native, "comparability": "comparable", "mayContinue": True,
            "reportRetained": True, "cleanupComplete": True, "commonInputSignature": signature,
            "caseSHA256": capture.sha256(directory / "orchard/report.json"), "escapePostTiming": timing,
            "gestures": gestures, "snapshots": snapshots, "pointer": pointer, "mouseControlDriver": driver,
            "receiver": receiver, "sourceSession": source, "activation": activation_result}
    except Exception as error:
        return failure_result(stage, case_name, returncode, error, native)


def failure_result(stage, case_name, returncode, error, native=None):
    reason = str(error) if isinstance(error, capture.ComparisonError) else type(error).__name__
    result = {"target": "control", **bindings(case_name), "observerLifecycle": "appkit",
        "captureComparison": "ax-only", "comparability": "not-comparable", "outcome": "not-comparable",
        "passed": False, "returnCode": returncode, "reasonCode": reason, "mayContinue": False}
    if native is not None:
        # Final AX observations may be complete even when driver/source proof
        # is not.  Preserve that narrower result without calling it acceptance.
        result["reportedWorkspaceOutcome"] = native
    try:
        raw = capture.read_json(evidence_for(stage, case_name) / "orchard/report.json")
        result["observerFailure"] = {key: raw[key] for key in
            ("status", "reason", "startupPhase", "cleanup", "mouseDriverGestures", "mouseDriverAXGuardViolations")
            if key in raw}
        result["observerFailure"] = json.loads(json.dumps(result["observerFailure"]),
            parse_constant=lambda value: "invalid-number:" + value)
        result["cleanupComplete"] = cleanup_complete(raw.get("cleanup"))
        result["reportRetained"] = True
    except Exception:
        result["reportRetained"] = False
    return result


def comparison_observations(results, complete):
    observed = [row for row in results if row.get("mayContinue") is True]
    by_driver = {name: [row for row in observed if row["mouseProducer"] == name]
                 for name in ("quartz", "xctest")}
    contrast = complete and all(not row["passed"] for row in by_driver["quartz"]) \
        and all(row["passed"] for row in by_driver["xctest"])
    if not complete:
        conclusion = "incomplete-comparison"
    elif contrast:
        conclusion = "mouse-producer-associated-contrast"
    elif all(row["passed"] for row in observed):
        conclusion = "baseline-failure-not-reproduced"
    elif all(not row["passed"] for row in observed):
        conclusion = "alternative-mouse-producer-did-not-resolve-failure"
    else:
        conclusion = "mixed-results-no-route-conclusion"
    return {"classification": conclusion, "repeatedProducerContrastObserved": contrast,
        "caseOutcomes": {name: [{"case": row["mouseDriverCase"], "outcome": row["outcome"]}
                               for row in by_driver[name]] for name in by_driver},
        "productionFixEstablished": False, "originalGateCovered": False,
        "interpretation": "Both arms use this new single-entry terminal-hold protocol and a global CG Escape. A repeated contrast supports producer sensitivity in this protocol; it does not identify the OS mechanism or verify the original enter/exit/reentry gate. All-pass fails to reproduce the Quartz baseline and is not a causal fix."}


def compare(stage, output, context, runner=capture.run_observer):
    capture.require(not output.exists() and not output.is_symlink(), "output-already-exists")
    capture.require(all(not evidence_for(stage, name).exists() and not evidence_for(stage, name).is_symlink()
                        for name in CASES), "evidence-already-exists")
    output.mkdir(parents=False, exist_ok=False)
    capture.write_json(output / "inputs-before.json", context["inputs"])
    results, stopped, signature = [], None, None
    for case_name in CASES:
        identity = {"target": "control", **bindings(case_name), "observerLifecycle": "appkit",
                    "captureComparison": "ax-only"}
        if stopped:
            results.append({**identity, "outcome": "not-run", "comparability": "not-run", "reasonCode": stopped})
            continue
        returncode, result = None, None
        try:
            capture.require(input_snapshot(stage) == context["inputs"], "inputs-changed-before-case")
            capture.require({path.name for path in runtime_directory(stage, case_name).iterdir()} == {"configuration.json"},
                            "mouse-runtime-not-empty-before-case")
            command = [str(stage / OBSERVER), str(stage), "--control", "--compare-capture", "ax-only",
                       "--compare-mouse-driver", case_name]
            returncode = runner(command, output / (case_name + ".log"))
            capture.require(input_snapshot(stage) == context["inputs"], "inputs-changed-after-case")
            result = classify(stage, context, case_name, returncode)
            result["inputsUnchanged"] = True
            if result.get("mayContinue") is True:
                current = result["commonInputSignature"]
                if signature is None:
                    signature = current
                capture.require(current == signature, "mouse-common-protocol-or-geometry-changed")
            if result.get("mayContinue") is not True:
                stopped = result.get("reasonCode", "mouse-case-incomplete")
            results.append(result)
        except Exception as error:
            result = failure_result(stage, case_name, returncode, error,
                native=result.get("strictNativeOutcome") if result else None)
            stopped = result["reasonCode"]
            results.append(result)
    try:
        after = input_snapshot(stage)
        unchanged = after == context["inputs"]
        capture.write_json(output / "inputs-after.json", after)
    except Exception:
        unchanged = False
    complete = len(results) == len(CASES) and all(row.get("mayContinue") is True for row in results)
    passed = complete and unchanged and all(row.get("passed") is True for row in results)
    report = {"schema": 1, "status": "passed" if passed else "failed", "diagnosticOnly": True,
        "releaseReady": False, "nativeAcceptanceXCTestExecuted": False, "physicalInputVerified": False,
        "C12": "HOLD", "comparisonComplete": complete, "allCasesPassed": passed,
        "inputsUnchanged": unchanged, "sameStagedPaths": True, "captureComparison": "ax-only",
        "caseOrder": list(CASES), "observerLifecycle": "appkit", "provenance": context["provenance"],
        "fixtureHashes": context["fixtures"], "cases": results,
        "mouseDriverComparison": comparison_observations(results, complete),
        "scope": "One fixed Quartz/XCTest/XCTest/Quartz comparison in Orchard with a simple entry and terminal hold. Every completed pass still requires Existing-only cancellation and a separate same-producer fresh drop. This diagnostic does not cover the original continuous enter/exit/reentry gate."}
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
