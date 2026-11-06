"""Portable D13 evidence tests; synthetic records never execute native input."""
import copy
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

import compare_native_drag_capture as capture
import compare_native_drag_mouse_driver as mouse
import compare_native_drag_sources as sources
from test_compare_native_drag_sources import fixture as source_fixture


def fixture(parent):
    stage, context = source_fixture(parent)
    (stage / mouse.OBSERVER).write_bytes(b"Portable D13 observer fixture; never execute.\n")
    project = stage / mouse.PROJECT_RELATIVE
    project.mkdir(parents=True)
    (project / "project.pbxproj").write_text("Portable generated project fixture.\n")
    for index, name in enumerate(mouse.CASES, 1):
        directory = stage / "MouseControl" / name
        directory.mkdir(parents=True)
        capture.write_json(directory / "configuration.json", {"schema": 1, "case": name, "nonce": f"{index:032x}"})
    runner = stage / mouse.RUNNER_RELATIVE
    (runner / "Contents/MacOS").mkdir(parents=True)
    (runner / "Contents/MacOS/QualityReview-Runner").write_bytes(b"Portable runner; never execute.\n")
    executable = runner / mouse.TEST_RELATIVE
    executable.parent.mkdir(parents=True)
    executable.write_bytes(b"Portable test bundle; never execute.\n")
    (runner / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": mouse.RUNNER_ID,
                                                              "CFBundleExecutable": "QualityReview-Runner"}))
    products = stage / "MouseDerivedData/Build/Products"
    manifest = {"__xctestrun_metadata__": {"FormatVersion": 2}, "TestConfigurations": [{"Name": "Default",
        "TestTargets": [{"BlueprintName": "QualityReview", "IsUITestBundle": True, "ProductModuleName": "QualityReview",
            "TestBundlePath": "__TESTROOT__/Debug/QualityReview-Runner.app/Contents/PlugIns/QualityReview.xctest",
            "EnvironmentVariables": {"EXISTING_ENV": "preserved"}}]}]}
    (products / "QualityReview_macosx.xctestrun").write_bytes(plistlib.dumps(manifest))
    provenance = context["provenance"]
    provenance.update(mouse.runner_metadata(stage), **mouse.manifest_metadata(stage, prepare=True),
        mouseConfigurationsSHA256={name: capture.sha256(stage / "MouseControl" / name / "configuration.json") for name in mouse.CASES})
    for key, path in {"observerMouseAppKitExecutableSHA256": stage / mouse.OBSERVER,
        "nativeDragMouseTestsSourceSHA256": capture.ROOT / "script/native_ui/NativeDragMouseTests.swift",
        "nativeDragMouseDriverSourceSHA256": capture.ROOT / "script/native_ui/NativeDragMouseDriver.swift",
        "mouseDriverComparatorSourceSHA256": Path(mouse.__file__)}.items():
        provenance[key] = capture.sha256(path)
    (stage / "provenance.json").write_text(json.dumps(provenance))
    context["mouseConfigurations"] = {name: mouse.configuration_for(stage, name) for name in mouse.CASES}
    context["inputs"] = mouse.input_snapshot(stage)
    return stage, context


def workspace(context, expected, observed=None):
    expected = sorted(expected)
    observed = expected if observed is None else sorted(observed)
    return {"expectedFilenames": expected, "observedFilenames": observed,
        "matchesExpectedWorkspace": expected == observed, "expectedSelectedCountLabel": f"{len(expected)} Selected",
        "expectedSelectedCountMatches": int(expected == observed), "selectedCountLabels": [f"{len(observed)} Selected"],
        "fixtureRemoveButtonCounts": {name: int(name in observed) for name in context["fixtures"]}}


def window_state(active, number):
    return {"applicationActive": active, "windowNumber": number, "keyWindowNumber": number if active else None,
        "mainWindowNumber": number if active else None, "windowIsKey": active, "windowIsMain": active,
        "windowCanBecomeKey": True, "windowCanBecomeMain": True, "windowVisible": True,
        "observedCursorScreen": {"x": 100., "y": 800.}, "cursorCoordinateSpace": "AppKit-screen-bottom-left"}


def save_trace(path, rows, case_name, pid):
    values = [{"schema": 1, "recordIndex": index, "pid": pid, **mouse.bindings(case_name), **row}
              for index, row in enumerate(sorted(rows, key=lambda r: r["systemUptime"]))]
    path.write_text("".join(json.dumps(row) + "\n" for row in values))
    return values


def read_trace(path):
    return [json.loads(line) for line in path.read_text().splitlines()]


def alter_trace(path, action):
    rows = read_trace(path)
    action(rows)
    for index, row in enumerate(rows):
        row["recordIndex"] = index
    path.write_text("".join(json.dumps(row) + "\n" for row in rows))


def emit(stage, context, case_name, *, passed=False, none_after_release=False):
    identity = mouse.bindings(case_name)
    producer = identity["mouseProducer"]
    evidence = mouse.evidence_for(stage, case_name)
    directory = evidence / "orchard"
    directory.mkdir(parents=True)
    existing, single = context["roles"]["Existing"], context["roles"]["Single"]
    source_point, target_point = {"x": 100., "y": 300.}, {"x": 100., "y": 100.}
    source_frame, target_frame = {"x": 8., "y": 281., "width": 920., "height": 360.}, {"x": 16., "y": 32., "width": 920., "height": 560.}
    source_geometry = {"coordinateSpace": "quartz-global-top-left", "finderWindow": "{{8, 281}, {920, 360}}",
        "finderIcon": "{{84, 284}, {32, 32}}", "sourcePoint": source_point,
        "nativeWindow": "{{8, 281}, {920, 360}}", "nativeIcon": "{{84, 284}, {32, 32}}"}
    cleanup = {"completed": True, "leftButtonReportedDown": False, "applicationStopped": True,
        "fixtureFinderWindowClosed": True, "fixedBundleRegistryEmpty": True, "sourceApplicationStopped": True,
        "sourceBundleRegistryEmpty": True, "mouseDriverStopped": True, "mouseDriverNormal": True, "errors": []}
    lifecycle = {"mode": "appkit", "didFinishLaunching": True, "nsApplicationPresent": True,
        "nsApplicationRunning": True, "activationPolicy": 2, "threadIsMain": True, "taskPriorityRawValue": 21}
    common = {**context["provenance"], **identity, "targetKind": "standard-appkit-control",
        "inputDriver": "mouse-" + producer + "-global-cg-escape", "permissionRequested": False,
        "captureComparison": "ax-only", "observerLifecycle": "appkit", "observerLifecycleAtStart": lifecycle,
        "diagnosticOnly": True, "nativeAcceptanceXCTestExecuted": False, "imageCaptureEnabled": False,
        "imagesCaptured": False, "gestureOutcomesVerified": passed, "status": "captured" if passed else "failed"}
    case = {**common, "schema": 1, "theme": "orchard", "applicationPath": str(stage / "Native Drag Control.app"),
        "sourceApplicationPath": str(stage / sources.SOURCE_BUNDLE), "sourceApplicationPID": 300,
        "targetApplicationPID": 200, "fixtureFolder": str(stage / "Fixtures/FinderDrop/orchard"),
        "originalSHA256": context["fixtures"], "originalBytesUnchanged": True, "userFileSetUnchanged": True,
        "preflight": {"accessibility": True, "postEvents": True, "screenCapture": True}, "cleanup": cleanup,
        "mouseDriverProtocol": mouse.protocol_for(case_name), "mouseDriverAXGuardViolations": [], "heldObserverAXReadCount": 0,
        "mouseDriverInitialWorkspace": workspace(context, [existing]), "mouseDriverInitialWorkspaceTiming": {
            "startedSystemUptime": 5.2, "completedSystemUptime": 5.3}, "mouseDriverCancellationObserved": True,
        "escapeCancellation": workspace(context, [existing], [existing] if passed else [existing, single]),
        "escapeCancellationObservationTiming": {"startedSystemUptime": 16.7, "completedSystemUptime": 16.72},
        "sourceGeometry": source_geometry, "sourceGeometries": {"cancel-source": copy.deepcopy(source_geometry)},
        "targetGeometry": {"reviewWindow": "{{16, 32}, {920, 560}}", "entryInTopPadding": "{100, 100}"},
        "mouseDriverSourceSelectionBeforeGesture": {"cancel-source": {"selected": False, "selectionClickPosted": False, "systemUptime": 3.8}},
        "escapePostTiming": {"downStartedSystemUptime": 12.91, "downCompletedSystemUptime": 12.911,
            "upStartedSystemUptime": 13.071, "upCompletedSystemUptime": 13.072, "heldSeconds": .161},
        "escapeKeyProtocol": {"kind": "d13-global-escape-no-pointer-motion", "keyCode": 53, "eventTap": "cghidEventTap",
            "keyDownDwellSeconds": .15, "downSourceStateID": 1, "upSourceStateID": 1, "downFlags": 0, "upFlags": 0,
            "continuedMotion": False}, "inputSource": {"kind": "shared-hid-keyboard-filter-comparison", "sourceStateID": 1,
                "localEventsSuppressionInterval": .25, "previousSuppressionIntervalFilter": 0, "previousRemoteMouseDragFilter": 0,
                "suppressionIntervalFilter": 2, "remoteMouseDragFilter": 2}, "mouseEvents": [], "diagnosticSnapshots": [],
        "targetRaiseRequests": []}
    if not passed:
        case["reason"] = "Escape did not cancel the actual native drag"
    else:
        case.update(freshDropWorkspace=workspace(context, [existing, single]),
                    freshDropObservationTiming={"startedSystemUptime": 22.7, "completedSystemUptime": 22.72})
        case["sourceGeometries"]["drop-source"] = copy.deepcopy(source_geometry)
        case["mouseDriverSourceSelectionBeforeGesture"]["drop-source"] = {
            "selected": True, "selectionClickPosted": False, "systemUptime": 18.2}
    for index, (phase, when) in enumerate(zip(mouse.activation.RAISE_PHASES + (["focus-native-source"] if passed else []),
                                            [2.2, 2.4, 2.6, 3.5, 18.])):
        case["targetRaiseRequests"].append({"requestIndex": index, "phase": phase, "targetRaisePolicy": "present", "performed": True,
            "status": 0, "targetPID": 200, "targetWindowTitle": "Native Drag Control", "mouseDownSent": False,
            "startedSystemUptime": when, "completedSystemUptime": when + .01})
    foreground = (300, sources.SOURCE_ID) if passed else (200, "app.lemulip.NativeDragControl")
    case["escapeInputStates"] = [{"phase": phase, "systemUptime": when, "mouseDownSent": producer == "quartz",
        "leftButtonReportedDown": True, "hidLeftButtonReportedDown": True, "escapeKeyDownSent": index == 1,
        "escapeKeyReportedDown": index == 1, "hidEscapeKeyReportedDown": index == 1,
        "modifiers": {"sessionFlags": 0x20000000, "relevantFlags": 0, "command": False,
                      "shift": False, "option": False, "control": False},
        "foregroundPID": foreground[0], "foregroundBundleIdentifier": foreground[1]}
        for index, (phase, when) in enumerate(zip(
            ["d13-before-key-post", "d13-before-key-up", "d13-after-key-up"], [12.90, 13.07, 13.073]))]
    gestures = []
    for phase, start, sequence, record_index in [("cancel", 10., 11, 2)] + ([("fresh", 20., 12, 4)] if passed else []):
        hold = 5. if phase == "cancel" else 1.
        release = start + .9 + hold
        request_completed = release + (.04 if producer == "xctest" else .012)
        release_observed = release + (.05 if producer == "xctest" else .04)
        release_states = ([] if producer == "xctest" else
            [{"systemUptime": release + .015, "leftButtonReportedDown": True}])
        release_states.append({"systemUptime": release_observed, "leftButtonReportedDown": False})
        gesture = {"phase": phase, "mouseProducer": producer, "startedSystemUptime": start,
            "sourcePoint": source_point, "targetPoint": target_point, "sourceFrame": source_frame, "targetFrame": target_frame,
            "destinationHoldSeconds": hold, "completed": True, "releaseButtonState": False,
            "releaseRequestCompletedSystemUptime": request_completed,
            "releaseObservedSystemUptime": release_observed,
            "releaseAcknowledgement": {"timeoutSeconds": 1., "pollIntervalSeconds": .025, "states": release_states},
            "releaseMethod": "xctest-gesture-return" if producer == "xctest" else "quartz-mouse-up",
            "entryObservation": {"observedSystemUptime": start + .9, "receiverEntrySystemUptime": start + .82,
                "sequenceNumber": sequence, "receiverRecordIndex": record_index, "cursorCG": target_point,
                "leftButtonReportedDown": True, "sourcePID": 300, "targetPID": 200}}
        if phase == "cancel":
            gesture.update(escapeScheduledSystemUptime=12.9, escapeBeforeReleaseVerified=True)
        if producer == "xctest":
            gesture["requestPublishedSystemUptime"] = start + .03
        else:
            gesture.update(releaseScheduledSystemUptime=release, lastMovementPostCompletedSystemUptime=start + .812)
            def posted(kind, when, point):
                return {"eventType": kind, "scope": "plain-gesture", "postCalled": True,
                    "eventTap": "cghidEventTap", "sourceStateID": 1, "postedFlags": 0x20000000,
                    "systemUptimeBeforePost": when, "systemUptimeAfterPost": when + .001, "location": point}
            case["mouseEvents"].append(posted(1, start + .01, source_point))
            case["mouseEvents"] += [posted(6, start + .31 + .025 * step,
                {"x": 100., "y": 300. - step * 10}) for step in range(1, 21)]
            case["mouseEvents"].append(posted(2, release + .01, target_point))
        gestures.append(gesture)
    case["mouseDriverGestures"] = gestures
    names = [("setup-before-hit-checks", 4.), ("00-before-drag", 5.), ("d13-cancel-after-release", 16.74)]
    if passed:
        names.append(("d13-fresh-after-release", 22.74))
    snapshots = [{"stage": name, "captureKind": "target-ax-only", "imagesCaptured": False,
        "mouseDownSent": False, "leftButtonReportedDown": False, "workspaceAXLabels": ["1 Selected", "Remove " + existing],
        "captureStartedSystemUptime": when, "captureCompletedSystemUptime": when + .02} for name, when in names]
    case["setupSnapshot"], case["stages"] = snapshots[0], snapshots[1:]
    for row in snapshots:
        (directory / (row["stage"] + ".json")).write_text(json.dumps(row))

    unchanged = {"originalBytesUnchanged": True, "fixtureFileSetUnchanged": True}
    receiver = [{"event": "application-start", "systemUptime": 2., "bundleIdentifier": "app.lemulip.NativeDragControl",
        "theme": "orchard", "originalSHA256": context["fixtures"], "fixtureFilenames": sorted(context["fixtures"]),
        "stagingRoot": str(stage), "bundlePath": str(stage / "Native Drag Control.app"),
        "executablePath": str(stage / "Native Drag Control.app/Contents/MacOS/NativeDragControl")},
        {"event": "application-ready", "systemUptime": 2.1}]
    def received(event, when, sequence=11, **extra):
        return {"event": event, "systemUptime": when, "sequenceNumber": sequence, **unchanged,
            "sourceAllowedOperationMask": 1, "pasteboardTypes": ["public.file-url"], "selectedFilenames": [existing], **extra}
    receiver.append(received("draggingEntered", 10.82, returnedCopy=True))
    if passed:
        receiver += [received("draggingEnded", 13.2), received("draggingEntered", 20.82, sequence=12, returnedCopy=True),
            received("performDragOperation", 21.93, sequence=12, accepted=True, selectedFilenames=sorted([existing, single]))]
    else:
        receiver.append(received("performDragOperation", 15.93, accepted=True, selectedFilenames=sorted([existing, single])))
    receiver.append({"event": "application-terminated", "systemUptime": 25.1, **unchanged})
    save_trace(directory / "receiver.jsonl", receiver, case_name, 200)
    ready = {"event": "source-ready", "systemUptime": 3., **window_state(True, 4),
        "bundleIdentifier": sources.SOURCE_ID, "executableName": sources.SOURCE_EXECUTABLE, "bundleName": sources.SOURCE_BUNDLE,
        "stagingRoot": str(stage), "sourceBundlePath": str(stage / sources.SOURCE_BUNDLE),
        "geometryCoordinateSpace": "Quartz-global-top-left", "originalSHA256": context["fixtures"],
        "actualWindowFrameCG": source_frame, "imageFrameCG": {"x": 84., "y": 284., "width": 32., "height": 32.},
        "requestedSourcePointCG": source_point, "sourcePointCG": source_point,
        **{key: context["provenance"][key] for key in (*sources.SOURCE_KEYS, "sourceCommit", "sourceTree", "architecture",
                                                      "observerExperimentCommit", "observerExperimentTree")}}
    def callback(event, when, index=1, **extra):
        return {"event": event, "systemUptime": when + .001, "callbackSystemUptime": when, **window_state(True, 4),
            "sessionIndex": index, "sequenceNumber": 10 + index, "filename": single, "offeredOperationMask": 1,
            "callbackPointCoordinateSpace": "AppKit-screen-bottom-left", "callbackPointScreen": {"x": 100., "y": 800.},
            "observedCursorCG": target_point, "animatesToStartingPositionsOnCancelOrFail": True,
            "pasteboardTypes": ["public.file-url"], **unchanged, **extra}
    end = 16.0 if passed and none_after_release else 13.21 if passed else (15.94 if producer == "xctest" else 15.96)
    source = [ready, callback("source-will-begin", 10.4), callback("source-moved", 10.8),
              callback("source-ended", end, operationRawValue=0 if passed else 1)]
    if passed:
        source += [callback("source-will-begin", 20.4, index=2), callback("source-moved", 20.8, index=2),
                   callback("source-ended", 22.0, index=2, operationRawValue=1)]
    source.append({"event": "application-terminating", "systemUptime": 25., **unchanged, "activeSession": False,
                   "sessionCount": 2 if passed else 1})
    save_trace(directory / "source.jsonl", source, case_name, 300)
    activation = [{"event": "activation-start", "systemUptime": 2., **window_state(False, 7),
        "bundleIdentifier": "app.lemulip.NativeDragControl", "executableName": "NativeDragControl", "bundleName": "Native Drag Control.app",
        "targetBundlePath": str(stage / "Native Drag Control.app"), "stagingRoot": str(stage), "originalSHA256": context["fixtures"],
        **{key: context["provenance"][key] for key in ("nativeDragControlSourceSHA256", "controlGUI_SHA256", "sourceCommit",
            "sourceTree", "architecture", "observerExperimentCommit", "observerExperimentTree")}},
        {"event": "activation-ready", "systemUptime": 2.1, **window_state(False, 7), "windowTitle": "Native Drag Control",
            "normalNSWindow": True, "windowClass": "NSWindow", "targetAXRaiseOverrideInstalled": False,
            "targetRaiseObservation": "observer-request-ledger-only", "styleMask": 15, "windowLevel": 0}]
    if not passed:
        activation.append({"event": "application-became-active", "systemUptime": 11.001,
                           "callbackSystemUptime": 11., **window_state(True, 7)})
    activation.append({"event": "activation-terminating", "systemUptime": 25.05, **window_state(not passed, 7), **unchanged})
    save_trace(directory / "activation.jsonl", activation, case_name, 200)

    config = context["mouseConfigurations"][case_name]
    runtime = mouse.runtime_directory(stage, case_name)
    runner = stage / mouse.RUNNER_RELATIVE
    provenance = context["provenance"]
    driver = {"inputDriver": "XCTest", "status": "completed", "case": case_name, "nonce": config["nonce"],
        "runnerBundleIdentifier": mouse.RUNNER_ID, "runnerApplicationPath": str(runner),
        "runnerExecutablePath": str(runner / "Contents/MacOS/QualityReview-Runner"), "mouseTestsExecutablePath": str(runner / mouse.TEST_RELATIVE),
        "projectPath": str(stage / mouse.PROJECT_RELATIVE), "mouseConfigurationPath": str(runtime / "configuration.json"),
        "mouseXCTestRunPath": str(stage / "MouseDerivedData/Build/Products" / ("D13-" + case_name + ".xctestrun")),
        "mouseConfigurationSHA256": provenance["mouseConfigurationsSHA256"][case_name],
        "mouseXCTestRunSHA256": provenance["mouseXCTestRunSHA256"][case_name],
        **{key: provenance[key] for key in ("mouseRunnerInfoSHA256", "mouseRunnerExecutableSHA256", "mouseTestsExecutableSHA256")},
        "readyTimeoutSeconds": 60, "gestureTimeoutSeconds": 20, "lifetimeSeconds": 150, "stopTimeoutSeconds": 8,
        "runnerPID": 400, "processPID": 401, "startedSystemUptime": 1., "expiresSystemUptime": 110., "processExitStatus": 0,
        "cleanup": {"stopConfirmed": True, "processStopped": True, "runnerRegistryEmpty": True,
            "finishedPublished": True, "finishedAcknowledged": True, "normalCompletion": True, "terminationRequested": False,
            "forceTerminationRequested": False, "gestureOutstanding": False, "timeoutSeconds": 8, "elapsedSeconds": .2, "errors": []},
        "requests": [], "requestPublications": [], "markerReceipts": []}
    if producer == "xctest":
        for index, gesture in enumerate(gestures, 1):
            request = {"schema": 1, "case": case_name, "nonce": config["nonce"], "action": "click-drag-hold", "theme": "orchard",
                "requestIndex": index, "phase": gesture["phase"], "runnerPID": 400,
                "sourceBundleIdentifier": sources.SOURCE_ID, "sourceApplicationPath": str(stage / sources.SOURCE_BUNDLE),
                "sourceExecutablePath": str(stage / sources.SOURCE_BUNDLE / "Contents/MacOS/NativeDragSource"),
                "sourceWindowTitle": "Native Drag Source", "sourcePID": 300, "targetBundleIdentifier": "app.lemulip.NativeDragControl",
                "targetApplicationPath": str(stage / "Native Drag Control.app"),
                "targetExecutablePath": str(stage / "Native Drag Control.app/Contents/MacOS/NativeDragControl"),
                "targetWindowTitle": "Native Drag Control", "targetPID": 200, "coordinateSpace": "quartz-global-top-left",
                **{key: gesture[key] for key in ("sourcePoint", "targetPoint", "sourceFrame", "targetFrame")},
                "initialHoldSeconds": .3, "velocityPointsPerSecond": 400, "destinationHoldSeconds": gesture["destinationHoldSeconds"],
                "createdSystemUptime": gesture["startedSystemUptime"] + .01, "expiresSystemUptime": gesture["startedSystemUptime"] + 20}
            driver["requests"].append(request)
            driver["requestPublications"].append({"requestIndex": index, "systemUptime": gesture["startedSystemUptime"] + .02})
            (runtime / f"request-{index}.json").write_text(json.dumps(request))
    count = len(driver["requests"])
    driver.update(publishedRequestCount=count, completedRequestCount=count)
    driver["finished"] = {"schema": 1, "case": case_name, "nonce": config["nonce"], "action": "finished",
                          "requestCount": count, "createdSystemUptime": 24.}
    (runtime / "finished.json").write_text(json.dumps(driver["finished"]))
    def marker(name, when, extra=None):
        witness = {"schema": 1, "case": case_name, "nonce": config["nonce"], "systemUptime": when, "runnerPID": 400,
            "leftButtonReportedDown": False, "hidLeftButtonReportedDown": False, "rightButtonReportedDown": False,
            "centerButtonReportedDown": False, "escapeKeyReportedDown": False, "hidEscapeKeyReportedDown": False,
            "modifierFlags": 0x20000000, "hidModifierFlags": 0x20000000, **(extra or {})}
        line = "LEMULIP_MOUSE_" + name + " " + json.dumps(witness, separators=(",", ":"))
        driver["markerReceipts"].append({"marker": name, "line": line, "witness": witness, "observedSystemUptime": when + .01})
    marker("READY", 1.2)
    for index, request in enumerate(driver["requests"], 1):
        extra = {"requestIndex": index, "phase": request["phase"], "sourcePID": 300, "targetPID": 200}
        marker("BEGIN", gestures[index - 1]["startedSystemUptime"] + .1, {**extra,
            "sourceWindowFrame": source_frame, "targetWindowFrame": target_frame,
            "sourceScreenPoint": source_point, "targetScreenPoint": target_point})
        marker("END", gestures[index - 1]["releaseRequestCompletedSystemUptime"] - .02, extra)
    marker("FINISHED", 24.1, {"requestCount": count})
    (runtime / "xcodebuild.log").write_text("Portable diagnostic log\n" + "".join(r["line"] + "\n" for r in driver["markerReceipts"]))
    case["mouseControlDriver"] = driver
    theme = {"theme": "orchard", "report": "orchard/report.json", "reportRetained": True,
             "status": case["status"], "gestureOutcomesVerified": passed, "cleanup": copy.deepcopy(cleanup)}
    if not passed:
        theme["reason"] = case["reason"]
    aggregate = {**common, "schema": 2, "expectedThemes": ["orchard"], "allThemesCaptured": passed, "themes": [theme]}
    (evidence / "report.json").write_text(json.dumps(aggregate))
    (directory / "report.json").write_text(json.dumps(case))
    return 0 if passed else 1


def alter_case(stage, name, action, *, snapshots=False):
    directory = mouse.evidence_for(stage, name) / "orchard"
    path = directory / "report.json"
    record = json.loads(path.read_text())
    action(record)
    path.write_text(json.dumps(record))
    if snapshots:
        for snapshot in [record["setupSnapshot"], *record["stages"]]:
            (directory / (snapshot["stage"] + ".json")).write_text(json.dumps(snapshot))


class MouseDriverComparisonTests(unittest.TestCase):
    def run_cases(self, stage, context, output, pass_for=None, change=None, none_after_release=False):
        commands = []
        def runner(command, log):
            name = mouse.CASES[len(commands)]
            commands.append(command)
            code = emit(stage, context, name, passed=bool(pass_for and pass_for(name)), none_after_release=none_after_release)
            if change:
                change(stage, name)
            return code
        return mouse.compare(stage, output, context, runner), commands

    def test_fixed_order_failure_is_comparable_but_never_a_pass(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            report, commands = self.run_cases(stage, context, Path(temporary) / "out")
            self.assertTrue(report["comparisonComplete"], report["cases"])
            self.assertFalse(report["allCasesPassed"])
            self.assertTrue(report["inputsUnchanged"])
            self.assertEqual(report["caseOrder"], ["quartz-first", "xctest-first", "xctest-second", "quartz-second"])
            self.assertEqual(report["mouseDriverComparison"]["classification"], "alternative-mouse-producer-did-not-resolve-failure")
            for command, name, result in zip(commands, mouse.CASES, report["cases"]):
                self.assertEqual(command, [str(stage / mouse.OBSERVER), str(stage), "--control", "--compare-capture", "ax-only",
                                           "--compare-mouse-driver", name])
                self.assertEqual(result["outcome"], "escape-cancellation-failed")
                self.assertEqual(result["mouseControlDriver"]["requestCount"], 1 if name.startswith("xctest") else 0)
                self.assertTrue((mouse.runtime_directory(stage, name) / "xcodebuild.log").exists())

    def test_repeated_route_contrast_requires_two_fresh_drop_passes(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            report, commands = self.run_cases(stage, context, Path(temporary) / "out", lambda n: n.startswith("xctest"))
            self.assertEqual(len(commands), 4)
            self.assertTrue(report["comparisonComplete"], report["cases"])
            self.assertTrue(report["mouseDriverComparison"]["repeatedProducerContrastObserved"])
            self.assertFalse(report["mouseDriverComparison"]["originalGateCovered"])
            self.assertEqual([r["passed"] for r in report["cases"]], [False, True, True, False])
            self.assertEqual(report["C12"], "HOLD")

    def test_none_after_release_is_allowed_when_final_cancel_and_fresh_drop_pass(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            report, _ = self.run_cases(stage, context, Path(temporary) / "out", lambda _: True, none_after_release=True)
            self.assertTrue(report["allCasesPassed"], report["cases"])
            self.assertEqual(report["mouseDriverComparison"]["classification"], "baseline-failure-not-reproduced")
            self.assertTrue(all(r["sourceSession"]["sessions"]["cancel"]["noneCallbackAfterObservedRelease"] for r in report["cases"]))
            for key in ("releaseReady", "nativeAcceptanceXCTestExecuted", "physicalInputVerified"):
                self.assertFalse(report[key])

    def test_async_release_acknowledgement_preserves_failed_cancellation(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            report, commands = self.run_cases(stage, context, Path(temporary) / "out")
            self.assertEqual(len(commands), 4)
            self.assertTrue(report["comparisonComplete"], report["cases"])
            self.assertFalse(report["allCasesPassed"])
            for result in report["cases"]:
                self.assertEqual(result["outcome"], "escape-cancellation-failed")
                gesture = result["gestures"][0]
                states = gesture["releaseAcknowledgement"]["states"]
                expected = [True, False] if result["mouseProducer"] == "quartz" else [False]
                self.assertEqual([state["leftButtonReportedDown"] for state in states], expected)
                self.assertEqual(gesture["releaseObservedSystemUptime"], states[-1]["systemUptime"])
                self.assertFalse(gesture["releaseButtonState"])
                self.assertEqual(result["pointer"]["observerPointerPostCount"], 22 if expected[0] else 0)

    def test_release_acknowledgement_requires_bounded_ordered_up_observation(self):
        def replace_states(record, states):
            gesture = record["mouseDriverGestures"][0]
            gesture["releaseAcknowledgement"]["states"] = states
            if states:
                gesture["releaseObservedSystemUptime"] = states[-1]["systemUptime"]

        self.assert_stopped_mutations({
            "missing-ack": lambda r: r["mouseDriverGestures"][0].pop("releaseAcknowledgement"),
            "missing-request-clock": lambda r: r["mouseDriverGestures"][0].pop("releaseRequestCompletedSystemUptime"),
            "empty-observations": lambda r: replace_states(r, []),
            "still-held": lambda r: r["mouseDriverGestures"][0]["releaseAcknowledgement"]["states"][-1].update(
                leftButtonReportedDown=True),
            "nonboolean-state": lambda r: r["mouseDriverGestures"][0]["releaseAcknowledgement"]["states"][-1].update(
                leftButtonReportedDown=0),
            "continued-after-first-up": lambda r: r["mouseDriverGestures"][0]["releaseAcknowledgement"]["states"][0].update(
                leftButtonReportedDown=False),
            "before-request": lambda r: r["mouseDriverGestures"][0]["releaseAcknowledgement"]["states"][0].update(
                systemUptime=r["mouseDriverGestures"][0]["releaseRequestCompletedSystemUptime"] - .001),
            "after-deadline": lambda r: replace_states(r, [{"systemUptime":
                r["mouseDriverGestures"][0]["releaseRequestCompletedSystemUptime"] + 1.001, "leftButtonReportedDown": False}]),
            "repeated-clock": lambda r: r["mouseDriverGestures"][0]["releaseAcknowledgement"]["states"][0].update(
                systemUptime=r["mouseDriverGestures"][0]["releaseObservedSystemUptime"]),
            "shortened-poll": lambda r: r["mouseDriverGestures"][0]["releaseAcknowledgement"]["states"][0].update(
                systemUptime=r["mouseDriverGestures"][0]["releaseObservedSystemUptime"] - .001),
            "unbound-final-clock": lambda r: r["mouseDriverGestures"][0].update(releaseObservedSystemUptime=16.0),
            "changed-timeout": lambda r: r["mouseDriverGestures"][0]["releaseAcknowledgement"].update(timeoutSeconds=2.),
            "changed-poll": lambda r: r["mouseDriverGestures"][0]["releaseAcknowledgement"].update(pollIntervalSeconds=.01),
            "changed-protocol": lambda r: r["mouseDriverProtocol"].update(releaseObservationTimeoutSeconds=2.),
        })
        self.assert_stopped_mutations({
            "xctest-missing-ack": lambda r: r["mouseDriverGestures"][0].pop("releaseAcknowledgement"),
            "fresh-still-held": lambda r: r["mouseDriverGestures"][1]["releaseAcknowledgement"]["states"][-1].update(
                leftButtonReportedDown=True),
        }, passed=True, at="xctest-first")

    def test_release_request_clock_must_follow_its_producer_completion(self):
        self.assert_stopped_mutations({
            "before-quartz-post-return": lambda r: r["mouseDriverGestures"][0].update(
                releaseRequestCompletedSystemUptime=r["mouseEvents"][-1]["systemUptimeBeforePost"]),
        })
        self.assert_stopped_mutations({
            "before-xctest-end-observed": lambda r: r["mouseDriverGestures"][0].update(
                releaseRequestCompletedSystemUptime=r["mouseControlDriver"]["markerReceipts"][2]["observedSystemUptime"] - .001),
        }, at="xctest-first")

    def assert_stopped_mutations(self, mutations, *, passed=False, at="quartz-first", snapshots=False):
        for label, mutation in mutations.items():
            with self.subTest(label=label), tempfile.TemporaryDirectory() as temporary:
                stage, context = fixture(Path(temporary))
                def change(stage, name):
                    if name == at:
                        alter_case(stage, name, mutation, snapshots=snapshots)
                report, commands = self.run_cases(stage, context, Path(temporary) / "out", lambda _: passed, change)
                expected_count = mouse.CASES.index(at) + 1
                self.assertEqual(len(commands), expected_count, report["cases"])
                result = report["cases"][expected_count - 1]
                self.assertEqual(result["comparability"], "not-comparable", result)
                self.assertFalse(result["mayContinue"])
                self.assertFalse(report["comparisonComplete"])
                self.assertTrue(all(r["outcome"] == "not-run" for r in report["cases"][expected_count:]))

    def test_missing_ownership_geometry_or_schedule_stops(self):
        self.assert_stopped_mutations({
            "unheld-entry": lambda r: r["mouseDriverGestures"][0]["entryObservation"].update(leftButtonReportedDown=False),
            "wrong-live-index": lambda r: r["mouseDriverGestures"][0]["entryObservation"].update(receiverRecordIndex=1),
            "wrong-live-sequence": lambda r: r["mouseDriverGestures"][0]["entryObservation"].update(sequenceNumber=44),
            "wrong-cursor": lambda r: r["mouseDriverGestures"][0]["entryObservation"].update(cursorCG={"x": 900., "y": 900.}),
            "early-key": lambda r: r["escapePostTiming"].update(downStartedSystemUptime=11.0),
            "unheld-before-up": lambda r: r["escapeInputStates"][1].update(leftButtonReportedDown=False),
            "pid-key": lambda r: r["escapeKeyProtocol"].update(eventTap="postToPid"),
            "pointer-motion": lambda r: r["escapeKeyProtocol"].update(continuedMotion=True),
            "owning-foreign-button": lambda r: r["escapeInputStates"][0].update(mouseDownSent=False),
            "foreground-missing": lambda r: r["escapeInputStates"][0].update(foregroundPID=None),
            "modifier-held": lambda r: r["escapeInputStates"][1]["modifiers"].update(command=True),
            "setup-click": lambda r: r["mouseDriverSourceSelectionBeforeGesture"]["cancel-source"].update(selectionClickPosted=True),
            "release-still-held": lambda r: r["mouseDriverGestures"][0].update(releaseButtonState=True),
        })

    def test_held_ax_and_final_observation_tampering_stops(self):
        self.assert_stopped_mutations({
            "held-read": lambda r: r.update(heldObserverAXReadCount=1),
            "guard": lambda r: r.update(mouseDriverAXGuardViolations=[{"attribute": "AXChildren"}]),
            "held-ax-arm": lambda r: r.update(heldAXPolicy="omitted"),
            "fabricated-held-observation": lambda r: r.update(escapeObservations=[{"phase": "before-key", "workspace": {}}]),
            "late-initial": lambda r: r["mouseDriverInitialWorkspaceTiming"].update(completedSystemUptime=11.),
            "early-final": lambda r: r["escapeCancellationObservationTiming"].update(startedSystemUptime=14.),
            "duplicate-row": lambda r: r["escapeCancellation"]["fixtureRemoveButtonCounts"].update(
                {next(k for k in r["originalSHA256"] if k.startswith("Single")): 2}),
            "originals-changed": lambda r: r.update(originalBytesUnchanged=False),
            "no-fresh": lambda r: r.pop("freshDropWorkspace", None),
        }, passed=True)

    def test_pointer_extra_events_or_wrong_path_fail_closed(self):
        self.assert_stopped_mutations({
            "extra-up": lambda r: r["mouseEvents"].insert(3, copy.deepcopy(r["mouseEvents"][-1])),
            "bent-path": lambda r: r["mouseEvents"][3]["location"].update(x=111.),
            "modified-input": lambda r: r["mouseEvents"][2].update(postedFlags=0x100000),
            "wrong-source": lambda r: r["mouseEvents"][2].update(sourceStateID=0),
        })
        self.assert_stopped_mutations({"observer-mouse": lambda r: r["mouseEvents"].append({"eventType": 1})}, at="xctest-first")

    def test_driver_incomplete_cleanup_or_unbound_receipt_stops(self):
        self.assert_stopped_mutations({
            "status": lambda r: r["mouseControlDriver"].update(status="stopped"),
            "test-binary": lambda r: r["mouseControlDriver"].update(mouseTestsExecutableSHA256="f" * 64),
            "exit": lambda r: r["mouseControlDriver"].update(processExitStatus=1),
            "force": lambda r: r["mouseControlDriver"]["cleanup"].update(forceTerminationRequested=True),
            "finished-not-acknowledged": lambda r: r["mouseControlDriver"]["cleanup"].update(finishedAcknowledged=False),
            "wrong-case": lambda r: r["mouseControlDriver"].update(case="quartz-first"),
            "wrong-nonce": lambda r: r["mouseControlDriver"].update(nonce="f" * 32),
            "missing-marker": lambda r: r["mouseControlDriver"]["markerReceipts"].pop(),
            "receipt-diverges": lambda r: r["mouseControlDriver"]["markerReceipts"][1]["witness"].update(leftButtonReportedDown=True),
            "request-geometry": lambda r: r["mouseControlDriver"]["requests"][0]["targetPoint"].update(x=400.),
            "request-deadline": lambda r: r["mouseControlDriver"]["requests"][0].update(expiresSystemUptime=200.),
        }, at="xctest-first")

    def test_raw_markers_are_validated_even_when_embedded_receipts_match(self):
        for label, mutate in {
            "held-at-begin": lambda witness: witness.update(leftButtonReportedDown=True),
            "wrong-marker-nonce": lambda witness: witness.update(nonce="f" * 32),
            "unrequested-index": lambda witness: witness.update(requestIndex=2),
        }.items():
            with self.subTest(label=label), tempfile.TemporaryDirectory() as temporary:
                stage, context = fixture(Path(temporary))
                def change(stage, name):
                    if name != "xctest-first":
                        return
                    path = mouse.evidence_for(stage, name) / "orchard/report.json"
                    record = json.loads(path.read_text())
                    receipt = record["mouseControlDriver"]["markerReceipts"][1]
                    mutate(receipt["witness"])
                    receipt["line"] = "LEMULIP_MOUSE_BEGIN " + json.dumps(receipt["witness"], separators=(",", ":"))
                    path.write_text(json.dumps(record))
                    (mouse.runtime_directory(stage, name) / "xcodebuild.log").write_text("".join(
                        row["line"] + "\n" for row in record["mouseControlDriver"]["markerReceipts"]))
                report, commands = self.run_cases(stage, context, Path(temporary) / "out", change=change)
                self.assertEqual(len(commands), 2, report["cases"])
                self.assertEqual(report["cases"][1]["outcome"], "not-comparable")

    def test_source_and_receiver_tampering_cannot_promote_a_pass(self):
        mutations = {
            "wrong-source-operation": ("source", lambda rows: next(r for r in rows if r["event"] == "source-ended").update(operationRawValue=1)),
            "missing-source-end": ("source", lambda rows: rows.remove(next(r for r in rows if r["event"] == "source-ended"))),
            "none-before-escape": ("source", lambda rows: next(r for r in rows if r["event"] == "source-ended").update(
                systemUptime=11.001, callbackSystemUptime=11.0)),
            "sequence": ("source", lambda rows: next(r for r in rows if r["event"] == "source-will-begin").update(sequenceNumber=99)),
            "originals": ("source", lambda rows: rows[-1].update(originalBytesUnchanged=False)),
            "fresh-reused": ("receiver", lambda rows: next(r for r in rows if r["event"] == "performDragOperation").update(sequenceNumber=11)),
            "double-fresh": ("receiver", lambda rows: rows.insert(-1, copy.deepcopy(next(r for r in rows if r["event"] == "performDragOperation")))),
            "live-entry": ("receiver", lambda rows: next(r for r in rows if r["event"] == "draggingEntered").update(returnedCopy=False)),
        }
        for label, (trace, mutation) in mutations.items():
            with self.subTest(label=label), tempfile.TemporaryDirectory() as temporary:
                stage, context = fixture(Path(temporary))
                def change(stage, name):
                    if name == "quartz-first":
                        alter_trace(mouse.evidence_for(stage, name) / "orchard" / (trace + ".jsonl"), mutation)
                report, commands = self.run_cases(stage, context, Path(temporary) / "out", lambda _: True, change)
                self.assertEqual(len(commands), 1, report["cases"])
                self.assertEqual(report["cases"][0]["outcome"], "not-comparable")
                self.assertTrue(report["cases"][0]["reportedWorkspaceOutcome"]["passed"])
                self.assertNotIn("strictNativeOutcome", report["cases"][0])

    def test_snapshot_files_must_equal_embedded_observation_and_be_post_release(self):
        self.assert_stopped_mutations({
            "held-snapshot": lambda r: r["stages"][1].update(captureStartedSystemUptime=14., captureCompletedSystemUptime=14.1),
            "fake-label-omission": lambda r: r["stages"][1].pop("workspaceAXLabels"),
            "image": lambda r: r["stages"][1].update(image="unexpected.png"),
        }, snapshots=True)
        self.assert_stopped_mutations({"embedded-divergence": lambda r: r["stages"][1].update(workspaceAXLabels=["9 Selected"])})

    def test_failed_cleanup_and_malformed_numbers_are_retained_and_stop(self):
        self.assert_stopped_mutations({
            "native-cleanup": lambda r: r["cleanup"].update(mouseDriverNormal=False),
            "nan": lambda r: r["mouseDriverGestures"][0].update(releaseObservedSystemUptime=float("nan")),
            "unknown-failure": lambda r: r.update(reason="startup incomplete"),
        })

    def test_input_mutation_stops_before_a_second_case(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            def change(stage, name):
                (stage / mouse.RUNNER_RELATIVE / mouse.TEST_RELATIVE).write_bytes(b"Changed native test binary")
            report, commands = self.run_cases(stage, context, Path(temporary) / "out", change=change)
            self.assertEqual(len(commands), 1)
            self.assertFalse(report["inputsUnchanged"])
            self.assertEqual(report["cases"][0]["reasonCode"], "inputs-changed-after-case")

    def test_existing_runtime_output_prevents_input_without_erasing_evidence(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            path = mouse.runtime_directory(stage, "quartz-first") / "xcodebuild.log"
            path.write_text("Existing evidence\n")
            report, commands = self.run_cases(stage, context, Path(temporary) / "out")
            self.assertEqual(commands, [])
            self.assertEqual(path.read_text(), "Existing evidence\n")
            self.assertFalse(report["comparisonComplete"])

    def test_context_binds_runner_test_code_configs_and_manifests(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            with patch.object(sources, "context_for", return_value=copy.deepcopy(context)):
                self.assertEqual(mouse.context_for(stage, "b" * 40)["inputs"], context["inputs"])
                path = stage / mouse.RUNNER_RELATIVE / mouse.TEST_RELATIVE
                path.write_bytes(b"Changed test code")
                with self.assertRaisesRegex(capture.ComparisonError, "mouse-runner-provenance"):
                    mouse.context_for(stage, "b" * 40)

    def test_case_manifests_preserve_original_and_inject_only_selected_target(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage, context = fixture(Path(temporary))
            for name in mouse.CASES:
                path = stage / "MouseDerivedData/Build/Products" / ("D13-" + name + ".xctestrun")
                value = plistlib.loads(path.read_bytes())
                self.assertEqual(mouse.xctest_target(value)["EnvironmentVariables"],
                                 {"EXISTING_ENV": "preserved", "LEMULIP_MOUSE_DRIVER_CASE": name})
            self.assertEqual(mouse.manifest_metadata(stage)["mouseXCTestRunSHA256"], context["provenance"]["mouseXCTestRunSHA256"])
            path.write_bytes(plistlib.dumps({"QualityReview": {"IsUITestBundle": True, "TestBundlePath": "bad"}}))
            with self.assertRaises(capture.ComparisonError):
                mouse.manifest_metadata(stage)

    def test_manifest_ambiguous_targets_and_non_ui_tests_are_rejected(self):
        target = {"BlueprintName": "QualityReview", "IsUITestBundle": True, "TestBundlePath": "__TESTROOT__/QualityReview.xctest"}
        mutations = [
            {"__xctestrun_metadata__": {"FormatVersion": 2}, "TestConfigurations": [{"TestTargets": [target, target]}]},
            {"QualityReview": {**target, "IsUITestBundle": False}},
            {"Other": target},
            {"__xctestrun_metadata__": {"FormatVersion": 3}, "QualityReview": target},
        ]
        for value in mutations:
            with self.subTest(value=value), self.assertRaises(capture.ComparisonError):
                mouse.xctest_target(value)
        self.assertIs(mouse.xctest_target({"QualityReview": target}), target)


if __name__ == "__main__":
    unittest.main()
