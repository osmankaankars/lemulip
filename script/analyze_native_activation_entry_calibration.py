"""Classify retained D18 natural-startup calibration; never launch native code.

An observed public C entry in an owned process is a positive route witness only.
It does not establish held-drag coverage, a cross-process requester, or acceptance.
The pure analyzer below deliberately keeps startup completion separate from the
presence of a qualifying, pre-ready AppKit call stack.
"""
from __future__ import annotations

import argparse
from fractions import Fraction
import hashlib
import json
import math
from pathlib import Path, PurePosixPath
import re
import stat
import struct
import sys
import uuid


ROLES = ("control", "source")
APPKIT = "/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit"
LIBRARY_NAME = "libNativeActivationEntryProbe.dylib"
ARCHITECTURES = {0x01000007: "x86_64", 0x0100000C: "arm64"}
CASE = "quartz-first"
MAX_JSON_BYTES = 8 * 1024 * 1024
EVIDENCE_DIRECTORY = "NativeDragControlEvidence-Capture-ax-only-Lifecycle-appkit-MouseDriver-quartz-first/orchard"
INPUT_EVENTS = {"source-mouse-down", "source-mouse-up", "source-session-requested", "source-session-created",
    "source-will-begin", "source-moved", "source-ended", "escape-send-event", "draggingEntered", "draggingUpdated",
    "draggingExited", "draggingEnded", "prepareForDragOperation", "performDragOperation", "concludeDragOperation",
    "target-mouse-enter", "target-mouse-return", "selection-changed", "open-rejected"}
ORIGINAL_SOURCES = {
    "NativeDragControl.swift": "6709c7513559b02020ece0992930e48689f73be875bba3494a8e523359fa02e1",
    "NativeDragSource.swift": "d009e5f20207845cb6b6bdb476d8e511b7e6e146f773b8512b4d1b2045f6dc31",
}
LIMITATIONS = [
    "Calibration observes one natural startup per original owned application; it generates no drag or keyboard input.",
    "A positive result establishes only an observed public C entry with an AppKit frame before native readiness in that process.",
    "A complete zero-call receipt or a call without the required frame/timing leaves route coverage unproven; it is not proof that activation requests were absent.",
    "The PSN arguments are retained opaque public-API values. They are not equated with a log ASN or used to infer a requester.",
    "An entry stack cannot establish the ultimate upstream cross-process requester or guaranteed coverage of private/framework/system paths.",
    "API return status and an independently observed active application are separate observations, not a causal request/transition join.",
    "No outcome changes PR #45, the original Finder drag gate, task 08 acceptance, or the completed physical/v4 checks.",
]


class EvidenceError(ValueError):
    pass


def require(condition, reason):
    if not condition:
        raise EvidenceError(reason)


def integer(value, label, minimum=0, maximum=(1 << 64) - 1):
    require(type(value) is int and minimum <= value <= maximum, label)
    return value


def digest(value, label):
    require(isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) is not None, label)
    return value


def image_uuid(value, label):
    require(isinstance(value, str)
            and re.fullmatch(r"[0-9A-F]{8}(?:-[0-9A-F]{4}){3}-[0-9A-F]{12}", value) is not None
            and value != "00000000-0000-0000-0000-000000000000", label)
    return value


def absolute_path(value, label):
    require(isinstance(value, str) and value.startswith("/") and "\x00" not in value
            and PurePosixPath(value).as_posix() == value and ".." not in PurePosixPath(value).parts, label)
    return value


def address(value, label, *, zero=False):
    require(isinstance(value, str) and re.fullmatch(r"0x[0-9a-fA-F]+", value) is not None, label)
    number = int(value, 16)
    require((0 if zero else 1) <= number < (1 << 64), label)
    return number


def float_interval(value, label):
    require(type(value) in (float, int) and math.isfinite(value) and value >= 0, label)
    value = float(value)
    return (Fraction.from_float(math.nextafter(value, -math.inf)),
            Fraction.from_float(math.nextafter(value, math.inf)))


def validate_clock(clock, label):
    require(isinstance(clock, dict), label)
    for family in ("machAbsolute", "machContinuous"):
        before = integer(clock.get(family + "Before"), label + "-" + family + "-before", 1)
        after = integer(clock.get(family + "After"), label + "-" + family + "-after", 1)
        require(before <= after, label + "-" + family + "-order")
    float_interval(clock.get("systemUptime"), label + "-uptime")
    return clock


def calibrated_offset(clocks, scale):
    bounds = []
    for index, clock in enumerate(clocks):
        validate_clock(clock, "clock-" + str(index))
        low, high = float_interval(clock["systemUptime"], "clock-uptime")
        bounds.append((low - clock["machAbsoluteAfter"] * scale,
                       high - clock["machAbsoluteBefore"] * scale))
    low, high = max(x[0] for x in bounds), min(x[1] for x in bounds)
    require(low <= high, "absolute-to-uptime-calibration-inconsistent")
    return low, high


def macho_identity(data):
    """Read only the native thin Mach-O header and LC_UUID, without executing it."""
    require(isinstance(data, bytes) and len(data) >= 32 and data[:4] == b"\xcf\xfa\xed\xfe", "binary-not-native-thin-macho")
    _, cpu, _, file_type, count, command_bytes, _, _ = struct.unpack_from("<8I", data)
    require(cpu in ARCHITECTURES and file_type in (2, 6), "binary-architecture-or-type")
    require(count <= 65536 and command_bytes <= len(data) - 32, "binary-load-command-extent")
    end, position, identity = 32 + command_bytes, 32, None
    for _ in range(count):
        require(position + 8 <= end, "binary-truncated-load-command")
        command, size = struct.unpack_from("<II", data, position)
        require(size >= 8 and size % 8 == 0 and position + size <= end, "binary-load-command-size")
        if command == 0x1B:
            require(size == 24 and identity is None, "binary-duplicate-or-invalid-uuid")
            identity = str(uuid.UUID(bytes=data[position + 8:position + 24])).upper()
        position += size
    require(position == end and identity is not None, "binary-missing-uuid-or-command-extent")
    image_uuid(identity, "binary-invalid-uuid")
    return {"architecture": ARCHITECTURES[cpu], "fileType": file_type, "imageUUID": identity,
            "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)}


def _frame(frame, executable, library):
    require(isinstance(frame, dict), "frame-object")
    raw_address = address(frame.get("address"), "frame-address")
    path = None if frame.get("imagePath") is None else absolute_path(frame["imagePath"], "frame-image-path")
    identity = None if frame.get("imageUUID") is None else image_uuid(frame["imageUUID"], "frame-image-uuid")
    require((frame.get("imageBase") is None) == (frame.get("imageOffset") is None), "frame-partial-address-mapping")
    base = None if frame.get("imageBase") is None else address(frame["imageBase"], "frame-image-base")
    if base is not None:
        offset = address(frame["imageOffset"], "frame-image-offset", zero=True)
        require(base + offset == raw_address, "frame-address-image-offset-mismatch")
    if path is not None and (path == executable["path"] or PurePosixPath(path).name == PurePosixPath(executable["path"]).name):
        require(path == executable["path"] and (identity is None or identity == executable["imageUUID"]), "frame-owned-executable-identity")
    if path is not None and (path == library["path"] or PurePosixPath(path).name == LIBRARY_NAME):
        require(path == library["path"] and (identity is None or identity == library["imageUUID"]), "frame-probe-library-identity")
    if frame.get("symbolAddress") is not None:
        address(frame["symbolAddress"], "frame-symbol-address")
    if path is None or identity is None or base is None:
        return {"resolved": False, "appKit": False}
    return {"resolved": True, "appKit": path == APPKIT}


def _validate_startup_role(role, process, binaries, receipt, scale, offset):
    require(isinstance(process, dict) and isinstance(binaries, dict), "process-or-binary-missing")
    expected_name = "NativeDrag" + ("Control" if role == "control" else "Source")
    executable, library = binaries["executable"], binaries["library"]
    for value in (executable, library):
        require(isinstance(value, dict), "binary-identity-object")
        require(value.get("architecture") == receipt["architecture"], "binary-architecture-mismatch")
        absolute_path(value.get("path"), "binary-path")
        image_uuid(value.get("imageUUID"), "binary-uuid")
        digest(value.get("sha256"), "binary-sha256")
    pid = integer(process.get("pid"), "process-pid", 1, (1 << 31) - 1)
    require(process.get("role") == role and process.get("bundleIdentifier") == "app.lemulip." + expected_name,
            "process-role-or-bundle")
    require(process.get("executablePath") == executable["path"]
            and process.get("executableSHA256") == executable["sha256"], "process-executable-binding")
    require(process.get("bundlePath") == str(PurePosixPath(executable["path"]).parents[2]), "process-bundle-path")
    require(isinstance(process.get("arguments"), list) and all(isinstance(x, str) for x in process["arguments"]), "process-arguments")
    if role == "control":
        require(process["arguments"] == ["-controlTheme", "orchard", "-controlEvidenceKind", "activation-quartz-first"],
                "control-startup-arguments")
    else:
        flags = ["--case", "--frame-x", "--frame-y", "--frame-width", "--frame-height", "--point-x", "--point-y"]
        require(len(process["arguments"]) == 14 and process["arguments"][::2] == flags
                and process["arguments"][1] == CASE, "source-startup-arguments")
        geometry = [float(value) for value in process["arguments"][3::2]]
        require(all(math.isfinite(value) for value in geometry) and geometry[2:4] == [480, 320]
                and geometry[4] == geometry[0] + 240 and geometry[5] == geometry[1] + 160, "source-startup-geometry")
    require(process.get("environment") == {"LEMULIP_ACTIVATION_PROBE_OUTPUT": process.get("probeOutputPath")}, "process-environment")
    expected_output = receipt["outputPath"] + "/" + role + ".json"
    require(process.get("probeOutputPath") == expected_output, "process-probe-output-path")
    require(process.get("launchRequested") is True and process.get("ready") is True, "process-startup-not-complete")
    launch = validate_clock(process.get("launchRequestedClock"), "launch-requested-clock")
    returned = validate_clock(process.get("launchReturnedClock"), "launch-returned-clock")
    observed = validate_clock(process.get("readyObservedClock"), "ready-observed-clock")
    require(launch["machAbsoluteAfter"] <= returned["machAbsoluteBefore"] <= observed["machAbsoluteAfter"], "startup-clock-order")
    active = process.get("activeWitness")
    require(isinstance(active, dict) and active.get("isActive") is True, "startup-active-witness-missing")
    active_clock = validate_clock(active.get("clock"), "active-witness-clock")
    cleanup = process.get("cleanup")
    require(isinstance(cleanup, dict) and cleanup.get("normalTerminationRequested") is True
            and cleanup.get("terminateReturn") is True and cleanup.get("fallbackUsed") is False
            and cleanup.get("signals") == [] and cleanup.get("terminated") is True
            and cleanup.get("completedNormally") is True and cleanup.get("identityVerified") is True
            and cleanup.get("exitStatusAvailable") is False and cleanup.get("exitStatus") is None,
            "normal-cleanup-incomplete")
    terminated = validate_clock(cleanup.get("terminatedObservedClock"), "terminated-observed-clock")
    require(active_clock["machAbsoluteAfter"] <= terminated["machAbsoluteAfter"], "cleanup-clock-order")
    ready_rows = process.get("readyRecords")
    ready_event = "application-ready" if role == "control" else "source-ready"
    require(isinstance(ready_rows, list), "native-ready-records-missing")
    ready_rows = [row for row in ready_rows if isinstance(row, dict) and row.get("event") == ready_event]
    require(len(ready_rows) == 1 and ready_rows[0].get("pid") == pid, "native-ready-record-identity")
    ready = ready_rows[0]
    log_name = "receiver" if role == "control" else "source"
    final_ready = [row for row in receipt["nativeLogs"][log_name]["records"] if row.get("event") == ready_event]
    require(final_ready == [ready], "native-ready-record-not-in-final-journal")
    ready_low, ready_high = float_interval(ready.get("systemUptime"), "native-ready-uptime")
    require(launch["machAbsoluteAfter"] * scale + offset[0] <= ready_high
            and ready_low <= observed["machAbsoluteAfter"] * scale + offset[1], "native-ready-outside-startup")
    return {"pid": pid, "executable": executable, "library": library, "launch": launch,
            "terminated": terminated, "ready": ready, "readyLow": ready_low, "readyEvent": ready_event}


def _analyze_probe_role(role, probe, startup, receipt, scale, offset):
    require(isinstance(probe, dict), "probe-missing-or-malformed")
    pid, executable, library = startup["pid"], startup["executable"], startup["library"]
    launch, terminated, ready = startup["launch"], startup["terminated"], startup["ready"]
    ready_low, ready_event = startup["readyLow"], startup["readyEvent"]
    require(probe.get("schemaVersion") == 1 and probe.get("probe") == "NativeActivationEntryProbe"
            and probe.get("scope") == "startup-calibration-only", "probe-schema-or-scope")
    require(probe.get("pid") == pid and probe.get("architecture") == receipt["architecture"]
            and probe.get("executablePath") == executable["path"]
            and probe.get("executableImageUUID") == executable["imageUUID"], "probe-process-identity")
    require(probe.get("bootUUID") == receipt["bootUUID"]
            and probe.get("machTimebaseNumer") == receipt["machTimebaseNumer"]
            and probe.get("machTimebaseDenom") == receipt["machTimebaseDenom"], "probe-clock-identity")
    loaded_library = probe.get("library")
    require(isinstance(loaded_library, dict) and loaded_library.get("path") == library["path"]
            and loaded_library.get("imageUUID") == library["imageUUID"], "probe-loaded-library-identity")
    address(loaded_library.get("imageBase"), "probe-library-image-base")
    require(probe.get("initialized") is True and probe.get("initializationError") is None
            and probe.get("warmupCompleted") is True and probe.get("atexitInvoked") is True
            and probe.get("captureClosed") is True and probe.get("countsAsOf") == "capture-close",
            "probe-initialization-or-flush-incomplete")
    require(probe.get("recordCapacity") == 128 and probe.get("frameCapacity") == 48, "probe-capacity")
    for family in ("MachAbsolute", "MachContinuous"):
        constructor = integer(probe.get("constructor" + family), "probe-constructor-clock", 1)
        initialized = integer(probe.get("ready" + family), "probe-ready-clock", 1)
        flushed = integer(probe.get("flush" + family), "probe-flush-clock", 1)
        require(constructor <= initialized <= flushed, "probe-lifecycle-clock-order")
    require(launch["machAbsoluteAfter"] <= probe["constructorMachAbsolute"]
            and probe["flushMachAbsolute"] <= terminated["machAbsoluteAfter"], "probe-outside-owned-lifetime")
    calls, counts = probe.get("calls"), probe.get("counts")
    require(isinstance(calls, list) and len(calls) <= 128 and isinstance(counts, dict), "probe-call-container")
    for name in ("totalCalls", "recordedCalls", "completedCalls", "droppedCalls", "incompleteCalls", "nestedCalls",
                 "overflowCalls", "beforeReadyCalls", "afterCaptureClosedCalls", "activeCallsAtFlush"):
        integer(counts.get(name), "probe-count-" + name)
    require(counts["totalCalls"] == counts["recordedCalls"] == counts["completedCalls"] == len(calls), "probe-count-reconciliation")
    require(all(counts[key] == 0 for key in ("droppedCalls", "incompleteCalls", "overflowCalls", "beforeReadyCalls",
                                           "afterCaptureClosedCalls", "activeCallsAtFlush")), "probe-capture-loss-or-incomplete")
    qualified, observations, nested, unresolved = [], [], 0, 0
    ids = set()
    for call in calls:
        require(isinstance(call, dict), "call-object")
        call_id = integer(call.get("callID"), "call-id", 1, 128)
        require(call_id not in ids, "duplicate-call-id")
        ids.add(call_id)
        require(call.get("pid") == pid, "call-pid-mismatch")
        integer(call.get("threadID"), "call-thread-id", 1)
        require(call.get("threadIDError") == 0, "call-thread-id-unavailable")
        function = call.get("function")
        require(function in ("SetFrontProcess", "SetFrontProcessWithOptions"), "call-function")
        bits = 16 if function == "SetFrontProcess" else 32
        require(call.get("returnType") == ("OSErr" if bits == 16 else "OSStatus") and call.get("resultBits") == bits, "call-result-abi")
        target = call.get("targetPSN")
        require(target is None or isinstance(target, dict) and set(target) == {"high", "low"}, "call-psn-shape")
        if target is not None:
            integer(target["high"], "call-psn-high", 0, (1 << 32) - 1)
            integer(target["low"], "call-psn-low", 0, (1 << 32) - 1)
        if function == "SetFrontProcess":
            require(call.get("options") is None, "call-options-for-non-options-function")
        else:
            integer(call.get("options"), "call-options", 0, (1 << 32) - 1)
        depth = integer(call.get("nestingDepth"), "call-nesting-depth", 1, 128)
        nested += depth > 1
        require(call.get("completed") is True, "call-incomplete")
        integer(call.get("result"), "call-result", -(1 << (bits - 1)), (1 << (bits - 1)) - 1)
        for field in ("entryErrno", "resultErrno"):
            integer(call.get(field), "call-" + field, -(1 << 31), (1 << 31) - 1)
        for family in ("MachAbsolute", "MachContinuous"):
            entry = integer(call.get("entry" + family), "call-entry-clock", 1)
            original = integer(call.get("preOriginal" + family), "call-original-clock", 1)
            after = integer(call.get("afterOriginal" + family), "call-return-clock", 1)
            require(probe["ready" + family] <= entry <= original <= after <= probe["flush" + family], "call-clock-order")
        frames = call.get("frames")
        require(isinstance(frames, list) and 0 < len(frames) <= 48
                and call.get("frameCount") == len(frames), "call-stack-frame-count")
        require(call.get("stackMayBeTruncated") is False, "call-stack-may-be-truncated")
        frame_results = [_frame(frame, executable, library) for frame in frames]
        require(all(frame.get("imagePath") != library["path"] or frame.get("imageBase") == loaded_library["imageBase"]
                    for frame in frames), "frame-probe-library-base-mismatch")
        unresolved += sum(not frame["resolved"] for frame in frame_results)
        appkit_indices = [index for index, frame in enumerate(frame_results) if frame["appKit"]]
        end_upper = call["afterOriginalMachAbsolute"] * scale + offset[1]
        before_ready = end_upper < ready_low
        observation = {"callID": call_id, "function": function, "result": call["result"], "targetPSN": target,
            "options": call.get("options"), "appKitFrameIndices": appkit_indices,
            "completedWhollyBeforeNativeReady": before_ready,
            "qualifiesForStartupRouteCoverage": bool(appkit_indices) and before_ready}
        observations.append(observation)
        if observation["qualifiesForStartupRouteCoverage"]:
            qualified.append(call_id)
    require(counts["nestedCalls"] == nested, "probe-nested-count-reconciliation")
    require(ids == set(range(1, len(calls) + 1)), "probe-call-id-sequence")
    return {"role": role, "status": "startup-route-calibrated" if qualified else "coverage-unproven",
        "startupComplete": True, "evidenceComplete": True, "naturalCEntryObserved": bool(qualified),
        "pid": pid, "nativeReadyEvent": ready_event, "nativeReadySystemUptime": ready["systemUptime"],
        "qualifyingCallIDs": qualified, "callCount": len(calls), "unresolvedFrameCount": unresolved,
        "calls": observations, "heldRouteCoverageEstablished": False, "ultimateRequesterEstablished": False}


def analyze_records(receipt, probes, binary_identities, *, inputs_preserved=False):
    """Pure analysis of parsed receipts and independently read binary identities."""
    result = {"schema": 1, "diagnostic": "native-activation-entry-startup-calibration",
        "scope": "startup-calibration-only", "status": "evidence-incomplete", "calibrationGatePassed": False,
        "startupComplete": False, "heldRouteCoverageEstablished": False, "ultimateRequesterEstablished": False,
        "nativeInputExecuted": False, "releaseReady": False, "C12": "HOLD", "roles": [], "limitations": LIMITATIONS}
    try:
        require(isinstance(receipt, dict), "calibration-receipt-missing")
        require(receipt.get("schema") == 1 and receipt.get("kind") == "native-activation-entry-startup-calibration"
                and receipt.get("caseName") == CASE, "calibration-schema-or-case")
        require(receipt.get("status") == "complete" and receipt.get("processCalibrationComplete") is True, "process-calibration-incomplete")
        require(receipt.get("stagedInputsUnchanged") is True and receipt.get("launchRetryCount") == 0
                and receipt.get("newExplicitActivationCalls") == 0, "calibration-input-scope")
        require(receipt.get("nativeLifecycleRecordsComplete") is True
                and receipt.get("unexpectedNativeInputObserved") is False, "native-lifecycle-or-input-scope")
        absolute_path(receipt.get("stagedPath"), "calibration-staged-path")
        absolute_path(receipt.get("outputPath"), "calibration-output-path")
        for key in ("inputGenerated", "mouseInputGenerated", "keyboardInputGenerated", "accessibilityCallsMade"):
            require(receipt.get(key) is False, "unexpected-input-or-accessibility-activity")
        require(inputs_preserved is True, "immutable-inputs-changed-or-unverified")
        require(receipt.get("architecture") in ("arm64", "x86_64"), "calibration-architecture")
        image_uuid(receipt.get("bootUUID"), "calibration-boot-uuid")
        numerator = integer(receipt.get("machTimebaseNumer"), "mach-timebase-numerator", 1, (1 << 32) - 1)
        denominator = integer(receipt.get("machTimebaseDenom"), "mach-timebase-denominator", 1, (1 << 32) - 1)
        scale = Fraction(numerator, denominator * 1_000_000_000)
        processes = receipt.get("processes")
        require(isinstance(processes, dict) and set(processes) == set(ROLES), "calibration-process-set")
        require(all(isinstance(processes[role], dict) for role in ROLES), "calibration-process-objects")
        require(processes["control"].get("pid") != processes["source"].get("pid"), "process-pid-reused-or-aliased")
        native_logs = receipt.get("nativeLogs")
        require(isinstance(native_logs, dict) and set(native_logs) == {"receiver", "activation", "source"}, "native-journal-set")
        for name, log in native_logs.items():
            role = "source" if name == "source" else "control"
            require(isinstance(log, dict) and log.get("status") == "complete"
                    and isinstance(log.get("records"), list), "native-journal-incomplete")
            require(log.get("path") == receipt["stagedPath"] + "/" + EVIDENCE_DIRECTORY + "/" + name + ".jsonl",
                    "native-journal-path")
            for row in log["records"]:
                require(isinstance(row, dict) and row.get("pid") == processes[role].get("pid"), "native-journal-pid")
                require(row.get("event") not in INPUT_EVENTS and "sequenceNumber" not in row, "unexpected-native-input-event")
        for role, expectations in (("control", [("receiver", "application-ready"), ("receiver", "application-terminated"),
                                                   ("activation", "activation-ready"), ("activation", "activation-terminating")]),
                                    ("source", [("source", "source-ready"), ("source", "application-terminating")])):
            for journal, event in expectations:
                matched = [row for row in native_logs[journal]["records"] if row.get("event") == event]
                require(len(matched) == 1, "native-lifecycle-record-missing-or-duplicate")
                if role == "source" and event == "application-terminating":
                    require(matched[0].get("sessionCount") == 0 and matched[0].get("activeSession") is False, "native-source-session-not-empty")
        require(isinstance(probes, dict) and set(probes) == set(ROLES)
                and isinstance(binary_identities, dict) and set(binary_identities) == set(ROLES), "probe-or-binary-role-set")
        clocks = [receipt.get("runClockBeforeLaunch"), receipt.get("runClockAfterTermination")]
        for role in ROLES:
            process = processes[role]
            require(isinstance(process, dict), "process-object")
            clocks += [process.get("launchRequestedClock"), process.get("launchReturnedClock"), process.get("readyObservedClock")]
            clocks += [(process.get("activeWitness") or {}).get("clock"), (process.get("cleanup") or {}).get("terminatedObservedClock")]
        offset = calibrated_offset(clocks, scale)
        result["absoluteToUptimeOffsetSeconds"] = [float(offset[0]), float(offset[1])]
        result["architecture"] = receipt["architecture"]
        for role in ROLES:
            startup = None
            try:
                startup = _validate_startup_role(role, processes[role], binary_identities[role], receipt, scale, offset)
                row = _analyze_probe_role(role, probes[role], startup, receipt, scale, offset)
            except (EvidenceError, KeyError, TypeError, ValueError, OverflowError) as error:
                row = {"role": role, "status": "evidence-incomplete", "startupComplete": startup is not None,
                       "evidenceComplete": False, "naturalCEntryObserved": False, "reasonCode": str(error)}
            result["roles"].append(row)
        result["startupComplete"] = all(row["startupComplete"] for row in result["roles"])
        statuses = {row["status"] for row in result["roles"]}
        if "evidence-incomplete" not in statuses:
            result["status"] = "coverage-unproven" if "coverage-unproven" in statuses else "startup-route-calibrated"
        result["calibrationGatePassed"] = result["status"] == "startup-route-calibrated"
    except (EvidenceError, KeyError, TypeError, ValueError, OverflowError) as error:
        result["reasonCode"] = str(error)
    return result


def _json_object(pairs):
    value = {}
    for key, item in pairs:
        require(key not in value, "duplicate-json-key")
        value[key] = item
    return value


def parse_json(data):
    def invalid_constant(_):
        raise EvidenceError("non-finite-json-number")
    return json.loads(data, object_pairs_hook=_json_object, parse_constant=invalid_constant)


def read_regular(path, *, maximum=MAX_JSON_BYTES, allow_empty=False):
    path = Path(path)
    require(path.is_absolute() and path.resolve(strict=True) == path, "file-path-symlink-or-not-absolute")
    info = path.lstat()
    require(stat.S_ISREG(info.st_mode) and (0 if allow_empty else 1) <= info.st_size <= maximum,
            "file-not-bounded-regular")
    with path.open("rb") as stream:
        data = stream.read(maximum + 1)
    require(len(data) <= maximum and (allow_empty or data), "file-byte-limit")
    return data


def read_json(path):
    return parse_json(read_regular(path))


def _build_identity(build, data, architecture, expected_path, file_type):
    require(isinstance(build, dict) and build.get("path") == expected_path, "build-record-path")
    actual = macho_identity(data)
    require(build.get("sha256") == actual["sha256"] and actual["architecture"] == architecture
            and build.get("architectures") == [architecture] and actual["fileType"] == file_type,
            "build-record-binary-mismatch")
    output = build.get("uuidOutput")
    require(isinstance(output, str), "build-uuid-output-missing")
    lines = output.strip().splitlines()
    require(len(lines) == 1, "build-uuid-output-count")
    match = re.fullmatch(r"UUID: ([A-Fa-f0-9-]{36}) \((arm64|x86_64)\) (.+)", lines[0])
    require(match is not None and match[1].upper() == actual["imageUUID"]
            and match[2] == architecture and match[3] == expected_path, "build-uuid-output-mismatch")
    return {**actual, "path": expected_path}


def _verify_inputs(staged, output):
    before, after = read_json(output / "inputs-before.json"), read_json(output / "inputs-after.json")
    preservation = read_json(output / "input-preservation.json")
    require(isinstance(before, dict) and before and before == after, "immutable-inventory-mismatch")
    require(preservation == {"schema": 1, "inputsUnchanged": True,
                            "beforeEntries": len(before), "afterEntries": len(after)}, "input-preservation-receipt")
    for name, expected in after.items():
        require(isinstance(name, str) and PurePosixPath(name).as_posix() == name
                and not name.startswith("/") and ".." not in PurePosixPath(name).parts, "inventory-relative-path")
        require(isinstance(expected, dict), "inventory-entry")
        path = staged / name
        require(path.resolve(strict=True) == path, "inventory-symlink")
        if expected.get("kind") == "directory":
            require(expected == {"kind": "directory"} and path.is_dir(), "inventory-directory")
        else:
            require(expected.get("kind") == "file" and set(expected) == {"kind", "bytes", "sha256"}, "inventory-file-entry")
            data = read_regular(path, maximum=256 * 1024 * 1024, allow_empty=True)
            require(len(data) == expected.get("bytes") and hashlib.sha256(data).hexdigest() == expected.get("sha256"), "immutable-input-bytes-changed")
    # Native journals are the only permitted additions inside the staging tree.
    evidence_root = EVIDENCE_DIRECTORY.split("/")[0]
    actual_names = {p.relative_to(staged).as_posix() for p in staged.rglob("*")
                    if p.name != ".DS_Store" and p.relative_to(staged).parts[0] != evidence_root}
    require(actual_names == set(after), "immutable-input-file-set-changed")


def load_evidence(staged, output):
    """Read fixed artifact paths; remap archived roots only for local file reads."""
    staged, output = Path(staged), Path(output)
    for directory in (staged, output):
        require(directory.is_absolute() and directory.resolve(strict=True) == directory and directory.is_dir(),
                "artifact-directory-path")
    receipt = read_json(output / "calibration-run.json")
    provenance = read_json(staged / "provenance.json")
    require(isinstance(receipt, dict) and isinstance(provenance, dict), "artifact-json-objects")
    require(receipt.get("provenance") == provenance, "helper-provenance-binding")
    require(provenance.get("sourceCommit") == "d821d7343675e2850705d141ef9b3b93a6aee945"
            and provenance.get("sourceTree") == "425baa28f00ec24551dd70c0cc874a75fa3be0c1"
            and provenance.get("architecture") == receipt.get("architecture")
            and provenance.get("startupCalibrationOnly") is True and provenance.get("nativeInputExecuted") is False
            and provenance.get("releaseReady") is False, "calibration-provenance-scope")
    original_staged = absolute_path(receipt.get("stagedPath"), "recorded-staging-root")
    original_output = absolute_path(receipt.get("outputPath"), "recorded-output-root")
    require(original_staged != original_output and not original_output.startswith(original_staged + "/")
            and not original_staged.startswith(original_output + "/"), "recorded-roots-overlap")
    _verify_inputs(staged, output)
    source_hashes = provenance.get("retainedDiagnosticSourcesSHA256")
    require(isinstance(source_hashes, dict) and set(ORIGINAL_SOURCES) <= set(source_hashes), "retained-source-inventory")
    for name, expected in source_hashes.items():
        require(isinstance(name, str) and PurePosixPath(name).name == name, "retained-source-name")
        digest(expected, "retained-source-hash")
        require(hashlib.sha256(read_regular(output / "sources" / name)).hexdigest() == expected, "retained-source-bytes-mismatch")
    for name, expected in ORIGINAL_SOURCES.items():
        require(source_hashes[name] == expected, "original-native-startup-source-changed")
    require(provenance.get("nativeDragControlSourceSHA256") == ORIGINAL_SOURCES["NativeDragControl.swift"]
            and provenance.get("nativeDragSourceSourceSHA256") == ORIGINAL_SOURCES["NativeDragSource.swift"],
            "original-native-source-provenance")
    builds = provenance.get("activationEntryCalibrationBuilds")
    require(isinstance(builds, dict) and set(builds) == {"control", "source", "probe", "helper"}, "build-identity-set")
    architecture = receipt["architecture"]
    library_data = read_regular(output / "build" / LIBRARY_NAME, maximum=64 * 1024 * 1024)
    library = _build_identity(builds["probe"], library_data, architecture, original_output + "/build/" + LIBRARY_NAME, 6)
    helper_name = "NativeActivationEntryCalibration"
    _build_identity(builds["helper"], read_regular(output / "build" / helper_name, maximum=64 * 1024 * 1024),
                    architecture, original_output + "/build/" + helper_name, 2)
    require(receipt.get("helperExecutablePath") == builds["helper"]["path"], "helper-executable-path")
    binary_identities, probes = {}, {}
    for role in ROLES:
        capitalized = "Control" if role == "control" else "Source"
        relative = "Native Drag " + capitalized + ".app/Contents/"
        executable_relative = relative + "MacOS/NativeDrag" + capitalized
        executable = _build_identity(builds[role], read_regular(staged / executable_relative, maximum=64 * 1024 * 1024),
                                     architecture, original_staged + "/" + executable_relative, 2)
        require(provenance.get(role + "GUI_SHA256") == executable["sha256"], "owned-executable-provenance")
        loaded_data = read_regular(staged / relative / "Frameworks" / LIBRARY_NAME, maximum=64 * 1024 * 1024)
        require(loaded_data == library_data, "loaded-probe-copy-differs")
        binary_identities[role] = {"executable": executable,
            "library": {**library, "path": original_staged + "/" + relative + "Frameworks/" + LIBRARY_NAME}}
        data = read_regular(output / (role + ".json"))
        process = receipt.get("processes", {}).get(role, {})
        require(process.get("probeReceipt") == {"status": "retained", "path": original_output + "/" + role + ".json",
            "byteCount": len(data), "sha256": hashlib.sha256(data).hexdigest()}, "probe-receipt-byte-binding")
        probes[role] = parse_json(data)
    for name in ("receiver", "activation", "source"):
        log = receipt.get("nativeLogs", {}).get(name)
        require(isinstance(log, dict), "native-log-receipt-missing")
        data = read_regular(staged / EVIDENCE_DIRECTORY / (name + ".jsonl"), allow_empty=True)
        require((not data or data.endswith(b"\n")) and len(data.splitlines()) <= 10000, "native-journal-truncated-or-too-many-records")
        records = [parse_json(line) for line in data.splitlines()]
        require(log.get("status") == "complete" and log.get("byteCount") == len(data)
                and log.get("sha256") == hashlib.sha256(data).hexdigest() and log.get("records") == records,
                "native-journal-byte-binding")
    return receipt, probes, binary_identities


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--staged", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args(argv)
    analysis_path = args.output / "analysis.json"
    try:
        receipt, probes, binaries = load_evidence(args.staged, args.output)
        result = analyze_records(receipt, probes, binaries, inputs_preserved=True)
    except (EvidenceError, OSError, KeyError, TypeError, ValueError, OverflowError) as error:
        result = analyze_records(None, {}, {})
        result["reasonCode"] = str(error)
    # An incomplete receipt still gets a reviewable result. Existing results are
    # never silently replaced, and no native program or system query is invoked.
    try:
        require(args.output.is_absolute() and args.output.resolve(strict=True) == args.output, "analysis-output-directory")
        with analysis_path.open("x", encoding="utf-8") as stream:
            json.dump(result, stream, indent=2, sort_keys=True, allow_nan=False)
            stream.write("\n")
    except (OSError, EvidenceError) as error:
        print(json.dumps({"status": "evidence-incomplete", "reasonCode": str(error)}), file=sys.stderr)
        return 1
    print(json.dumps({"status": result["status"], "calibrationGatePassed": result["calibrationGatePassed"],
                      "analysisPath": str(analysis_path)}, sort_keys=True))
    return 0 if result["calibrationGatePassed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
