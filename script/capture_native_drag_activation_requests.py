"""Collect one bounded, post-input front-process log query without changing native verdicts.

An emitting process and a boot-scoped ASN association are evidence about a log
record, not proof of the original requester or general activation-path coverage.
"""
import argparse
from datetime import datetime, timezone
from fractions import Fraction
import hashlib
import json
import math
from pathlib import Path
import re
import sys

import capture_native_drag_system_log as bounded_log
import compare_native_drag_mouse_driver as mouse

capture = mouse.capture
TIMEOUT_SECONDS = 20
BYTE_LIMIT = 10 * 1024 * 1024
MOUSE_SHA256 = "44839f19f4eff2b23246bd3919658d8880d234db1c9c31629503ed586b2ebabc"
BOUNDED_LOG_SHA256 = "ccc23050210516a9a8ed2d5074af656f0306f318bab720e6144878ca6f921827"
FRONT_SUBSYSTEM = "com.apple.processmanager"
FRONT_CATEGORY = "front-35286506"
CLOCK_SUBSYSTEM = "app.lemulip.NativeTraceClock"
CLOCK_CATEGORY = "calibration"
CLOCK_SOURCE = Path(__file__).parent / "native_ui/NativeTraceClock.swift"
PROTOCOL = {"schema": 1, "protocolBaseCommit": "d69f6b344a0dc069027f04061686a308dae79ba4",
    "inputProtocol": "D13-R3-unchanged", "caseOrder": list(mouse.CASES),
    "queryScope": "front-subsystem-category-across-emitters-plus-session-clock-markers",
    "timeoutSeconds": TIMEOUT_SECONDS, "byteLimit": BYTE_LIMIT, "nativeVerdictPolicy": "unchanged"}
UUID = re.compile(r"[0-9A-F]{8}(?:-[0-9A-F]{4}){3}-[0-9A-F]{12}")
ASN = r"(0x[0-9a-fA-F]+-0x[0-9a-fA-F]+)"
BRING = re.compile(r"BringFrontModifier: pid=(\d+) asn=" + ASN +
    r" Modifier (-?\d+) hideAfter=(\d+) hideOthers=(\d+) dontMakeFrontmost=(\d+)"
    r" mouseDown=(\d+)/(\d+) seed=(\d+)/(\d+)")
SET = re.compile(r"SetFrontProcess: asn=" + ASN + r" options=([0-9a-fA-F]+)")
TICK_FIELDS = tuple(family + suffix for family in ("absolute", "continuous") for suffix in
    ("BeforeUptime", "AfterUptime", "BeforeLog", "AfterLog"))
FLOAT_FIELDS = ("systemUptimeSample", "systemUptimeBeforeLog", "systemUptimeAfterLog",
                "wallBeforeLogUnixSeconds", "wallAfterLogUnixSeconds")
CLOCK_FIELDS = {"schema", "phase", "nonce", "pid", "executablePath", "bootUUID",
    "machTimebaseNumer", "machTimebaseDenom", *TICK_FIELDS, *FLOAT_FIELDS}
CONFIG_FIELDS = {"schema", "nonce", "executablePath", "sourceSHA256", "executableSHA256",
                 "experimentCommit", "experimentTree", "architecture"}
EXECUTION_FIELDS = {"schema", "phase", "returncode", "timedOut", "stdoutSHA256", "stderrSHA256"}


def diagnostic_metadata():
    return {"activationRequestLogDiagnostic": PROTOCOL,
            "activationRequestLogCollectorSourceSHA256": capture.sha256(Path(__file__))}


def require(condition, reason):
    capture.require(condition, "activation-request-" + reason)


def positive(value, label):
    require(type(value) in (int, float) and math.isfinite(value) and value > 0, label)
    return value


def unsigned(value, label, bits=64):
    require(type(value) is int and 0 < value < 2 ** bits, label)
    return value


def wall(value):
    require(isinstance(value, str), "wall-string")
    result = datetime.fromisoformat(value.replace("Z", "+00:00"))
    require(result.tzinfo is not None, "wall-timezone")
    return result.timestamp()


def read_trace(path, pid, name):
    require(path.is_file() and not path.is_symlink() and path.stat().st_size <= BYTE_LIMIT, "trace-file")
    rows = [mouse.decoded_json(line, "activation-request-trace") for line in path.read_bytes().splitlines()]
    require(rows, "trace-empty")
    previous = 0
    for index, row in enumerate(rows):
        require(isinstance(row, dict) and type(row.get("pid")) is int and row["pid"] == pid
                and type(row.get("recordIndex")) is int and row["recordIndex"] == index
                and row.get("mouseDriverCase") == name, "trace-identity")
        current = positive(row.get("systemUptime"), "trace-clock")
        require(current >= previous, "trace-clock-order")
        previous = current
    return rows


def validate_environment(environment, architecture):
    require(isinstance(environment, dict) and set(environment) ==
            {"schema", "hostArchitecture", "helperArchitectures", "translationProbe"}, "clock-environment-schema")
    require(type(environment["schema"]) is int and environment["schema"] == 1 and environment["hostArchitecture"] == architecture
            and environment["helperArchitectures"] == [architecture], "clock-environment-architecture")
    probe = environment["translationProbe"]
    require(isinstance(probe, dict) and type(probe.get("returnCode")) is int and type(probe.get("errno")) is int
            and (probe.get("value") is None or type(probe.get("value")) is int) and probe in (
        {"returnCode": 0, "errno": 0, "value": 0, "status": "native"},
        {"returnCode": -1, "errno": 2, "value": None, "status": "not-exposed"}), "clock-environment-translation")


def validate_snapshot(row, config, phase):
    require(set(row) == CLOCK_FIELDS and type(row.get("schema")) is int and row["schema"] == 1, "clock-schema")
    require(row["phase"] == phase and row["nonce"] == config["nonce"]
            and row["executablePath"] == config["executablePath"], "clock-identity")
    unsigned(row["pid"], "clock-pid", 32)
    require(isinstance(row["bootUUID"], str) and UUID.fullmatch(row["bootUUID"]) is not None, "clock-boot")
    unsigned(row["machTimebaseNumer"], "clock-timebase", 32)
    unsigned(row["machTimebaseDenom"], "clock-timebase", 32)
    for field in TICK_FIELDS:
        unsigned(row[field], "clock-tick")
    for field in FLOAT_FIELDS:
        positive(row[field], "clock-time")
    for family in ("absolute", "continuous"):
        values = [row[family + suffix] for suffix in ("BeforeUptime", "AfterUptime", "BeforeLog", "AfterLog")]
        require(values == sorted(values), "clock-tick-order")
    require(row["systemUptimeSample"] <= row["systemUptimeBeforeLog"] <= row["systemUptimeAfterLog"]
            and row["wallBeforeLogUnixSeconds"] <= row["wallAfterLogUnixSeconds"], "clock-sample-order")


def load_clock(clock_dir, provenance, experiment_commit):
    config_path = clock_dir / "clock-config.json"
    config = mouse.read_json(config_path, "activation-request-clock-config")
    require(set(config) == CONFIG_FIELDS and type(config.get("schema")) is int and config["schema"] == 1,
            "clock-config-schema")
    require(isinstance(config["nonce"], str) and re.fullmatch(r"[0-9a-f]{32}", config["nonce"]), "clock-nonce")
    executable = clock_dir / "NativeTraceClock"
    require(config["executablePath"] == str(executable) and not executable.is_symlink()
            and executable.is_file(), "clock-executable-path")
    require(config["sourceSHA256"] == capture.sha256(CLOCK_SOURCE)
            and config["executableSHA256"] == capture.sha256(executable), "clock-build-hash")
    require(config["experimentCommit"] == experiment_commit
            and config["experimentTree"] == provenance["observerExperimentTree"]
            and config["architecture"] == provenance["architecture"] in ("arm64", "x86_64"), "clock-build-provenance")
    require(provenance.get("activationRequestClockBuild") == config
            and provenance.get("activationRequestClockConfigSHA256") == capture.sha256(config_path), "clock-config-binding")
    validate_environment(provenance.get("activationRequestClockEnvironment"), config["architecture"])
    result = {"config": config, "configSHA256": capture.sha256(config_path),
        "environment": provenance["activationRequestClockEnvironment"], "snapshots": {}, "execution": {}, "errors": []}
    for phase in ("before", "after"):
        try:
            receipt = mouse.read_json(clock_dir / (phase + "-execution.json"), "activation-request-clock-execution")
            require(set(receipt) == EXECUTION_FIELDS and type(receipt.get("schema")) is int
                    and receipt["schema"] == 1 and receipt["phase"] == phase, "clock-execution-schema")
            stdout, stderr = clock_dir / (phase + ".json"), clock_dir / (phase + ".stderr")
            require(stdout.is_file() and not stdout.is_symlink() and stderr.is_file() and not stderr.is_symlink()
                    and stdout.stat().st_size <= 65536 and stderr.stat().st_size <= 65536, "clock-execution-files")
            require(receipt["stdoutSHA256"] == capture.sha256(stdout)
                    and receipt["stderrSHA256"] == capture.sha256(stderr), "clock-execution-hash")
            result["execution"][phase] = receipt
            require(type(receipt["returncode"]) is int and receipt["returncode"] == 0
                    and receipt["timedOut"] is False, "clock-execution-incomplete")
            row = mouse.read_json(stdout, "activation-request-clock")
            validate_snapshot(row, config, phase)
            result["snapshots"][phase] = row
        except Exception as error:
            result["errors"].append({"phase": phase, "reasonCode": error_reason(error)})
    return result


def load_context(stage, comparison_dir, clock_dir, experiment_commit):
    require(re.fullmatch(r"[0-9a-f]{40}", experiment_commit or "") is not None, "experiment-commit")
    require(capture.sha256(Path(mouse.__file__)) == MOUSE_SHA256
            and capture.sha256(Path(bounded_log.__file__)) == BOUNDED_LOG_SHA256, "frozen-source-hash")
    provenance_path, comparison_path = stage / "provenance.json", comparison_dir / "comparison.json"
    provenance = mouse.read_json(provenance_path)
    comparison = mouse.read_json(comparison_path)
    require(provenance.get("observerExperimentCommit") == experiment_commit
            and comparison.get("provenance") == provenance, "comparison-provenance")
    capture.fields_match(provenance, diagnostic_metadata(), "activation-request-diagnostic-provenance")
    require(provenance.get("mouseDriverComparatorSourceSHA256") == MOUSE_SHA256, "mouse-provenance")
    require(comparison.get("schema") == 1 and comparison.get("caseOrder") == list(mouse.CASES)
            and [r.get("mouseDriverCase") for r in comparison.get("cases", [])] == list(mouse.CASES), "case-plan")
    require(comparison.get("diagnosticOnly") is True and comparison.get("releaseReady") is False
            and comparison.get("inputsUnchanged") is True and comparison.get("sameStagedPaths") is True,
            "comparison-scope")
    clock = load_clock(clock_dir, provenance, experiment_commit)
    context = {"schema": 1, "experimentCommit": experiment_commit,
        "experimentTree": provenance["observerExperimentTree"], "architecture": provenance["architecture"],
        "comparisonSHA256": capture.sha256(comparison_path), "provenanceSHA256": capture.sha256(provenance_path),
        "nativeResults": [], "cases": [], "excludedCases": []}
    wall_bounds = []
    for classified in comparison["cases"]:
        name = classified["mouseDriverCase"]
        context["nativeResults"].append({"case": name, **{key: classified.get(key) for key in
            ("outcome", "passed", "comparability", "strictNativeOutcome", "mayContinue")}})
        if classified.get("comparability") != "comparable" or classified.get("mayContinue") is not True:
            context["excludedCases"].append({"case": name, "reasonCode": "native-case-not-comparable"})
            continue
        directory = mouse.evidence_for(stage, name) / "orchard"
        report_path = directory / "report.json"
        report = mouse.read_json(report_path)
        require(classified.get("caseSHA256") == capture.sha256(report_path), "case-hash")
        passed = classified.get("passed")
        require(type(passed) is bool and report.get("status") == ("captured" if passed else "failed")
                and classified.get("cleanupComplete") is True and mouse.cleanup_complete(report.get("cleanup")),
                "case-native-binding")
        native = {"passed": passed, "outcome": "captured" if passed else "escape-cancellation-failed",
            "axOutcome": "captured" if passed else "escape-cancellation-failed", "returnCode": 0 if passed else 1}
        require(classified.get("strictNativeOutcome") == native and classified.get("outcome") == native["outcome"],
                "case-native-verdict")
        for key, value in mouse.bindings(name).items():
            require(report.get(key) == value and classified.get(key) == value, "case-identity")
        driver = report.get("mouseControlDriver", {})
        pids = {"observer": report.get("observerProcessID"), "target": report.get("targetApplicationPID"),
                "source": report.get("sourceApplicationPID"), "runner": driver.get("runnerPID")}
        require(all(type(v) is int and v > 0 for v in pids.values()) and len(set(pids.values())) == 4, "owned-pids")
        paths = {"observer": str(stage / mouse.OBSERVER),
            "target": str(stage / "Native Drag Control.app/Contents/MacOS/NativeDragControl"),
            "source": str(stage / "Native Drag Source.app/Contents/MacOS/NativeDragSource"),
            "runner": str(stage / mouse.RUNNER_RELATIVE / "Contents/MacOS/QualityReview-Runner")}
        require(report.get("applicationPath") == str(stage / "Native Drag Control.app")
                and report.get("sourceApplicationPath") == str(stage / "Native Drag Source.app")
                and driver.get("runnerExecutablePath") == paths["runner"], "owned-paths")
        traces, hashes = {}, {"report.json": capture.sha256(report_path)}
        for filename, role, section, hash_key in (
                ("receiver.jsonl", "target", "receiver", "receiverSHA256"),
                ("activation.jsonl", "target", "activation", "activationSHA256"),
                ("source.jsonl", "source", "sourceSession", "sourceSHA256")):
            path = directory / filename
            hashes[filename] = capture.sha256(path)
            require(classified.get(section, {}).get(hash_key) == hashes[filename], "trace-hash")
            traces[filename] = read_trace(path, pids[role], name)
        receiver = traces["receiver.jsonl"]
        times = [wall(r.get("time")) for r in receiver]
        start, end = min(times) - 1, max(times) + 1
        require(0 < end - start <= 302, "case-wall-span")
        gestures = report.get("mouseDriverGestures")
        require(gestures == classified.get("gestures") and isinstance(gestures, list)
                and [g.get("phase") for g in gestures] == (["cancel", "fresh"] if passed else ["cancel"]), "gesture-binding")
        timing = report.get("escapePostTiming", {})
        life = {"target": [min(r["systemUptime"] for r in receiver + traces["activation.jsonl"]),
                           max(r["systemUptime"] for r in receiver + traces["activation.jsonl"])],
                "source": [traces["source.jsonl"][0]["systemUptime"], traces["source.jsonl"][-1]["systemUptime"]]}
        cancel = gestures[0]
        boundaries = [min(v[0] for v in life.values()), cancel.get("startedSystemUptime"),
            cancel.get("entryObservation", {}).get("receiverEntrySystemUptime"), timing.get("downStartedSystemUptime"),
            timing.get("upCompletedSystemUptime"), cancel.get("releaseObservedSystemUptime")]
        labels = ["setup-observed", "cancel-before-entry", "cancel-entered-before-escape",
                  "escape-posting", "cancel-after-escape-before-release-observation"]
        if passed:
            boundaries += [gestures[1].get("startedSystemUptime"), gestures[1].get("releaseObservedSystemUptime")]
            labels += ["between-gestures", "fresh-call-interval"]
        boundaries += [max(v[1] for v in life.values())]
        labels += ["cleanup-observed"]
        require(all(type(v) in (float, int) and math.isfinite(v) and v > 0 for v in boundaries)
                and all(a < b for a, b in zip(boundaries, boundaries[1:])), "phase-boundaries")
        context["cases"].append({"case": name, "nativeOutcome": native, "ownedPIDs": pids,
            "ownedExecutablePaths": paths, "inputHashes": hashes,
            "wallStartUnixSeconds": start, "wallEndUnixSeconds": end, "wallPrecisionSeconds": 1,
            "observedLifetimes": life, "phases": [{"phase": label, "start": a, "end": b}
                for label, a, b in zip(labels, boundaries, boundaries[1:])]})
        wall_bounds.extend((start, end))
    require(context["cases"], "no-comparable-cases")
    for snapshot in clock["snapshots"].values():
        wall_bounds.extend((snapshot["wallBeforeLogUnixSeconds"] - 1, snapshot["wallAfterLogUnixSeconds"] + 1))
    start, end = math.floor(min(wall_bounds)), math.ceil(max(wall_bounds))
    require(0 < end - start <= 1200, "query-time-span")
    context.update(queryStartUnixSeconds=start, queryEndUnixSeconds=end, clockConfig=clock["config"])
    return context, clock


def command_for(context):
    nonce = context["clockConfig"]["nonce"]
    markers = ["LEMULIP_NATIVE_TRACE_CLOCK " + nonce + " " + phase for phase in ("before", "after")]
    predicate = (f'(subsystem == "{FRONT_SUBSYSTEM}" AND category == "{FRONT_CATEGORY}") OR '
                 f'(subsystem == "{CLOCK_SUBSYSTEM}" AND category == "{CLOCK_CATEGORY}" AND (' +
                 " OR ".join("eventMessage == " + json.dumps(m) for m in markers) + "))")
    def date(value):
        return datetime.fromtimestamp(value, timezone.utc).strftime("%Y-%m-%d %H:%M:%S%z")
    return ["/usr/bin/log", "show", "--style", "json", "--timezone", "UTC", "--info", "--debug",
            "--start", date(context["queryStartUnixSeconds"]), "--end", date(context["queryEndUnixSeconds"]),
            "--predicate", predicate]


def offset_interval(sample, before_tick, after_tick, scale):
    # Subtraction may cancel almost all significant digits. Keep both the
    # reported Double and the integer tick/timebase conversion exact here.
    return [Fraction(sample) - after_tick * scale, Fraction(sample) - before_tick * scale]


def directed_float(value, upper):
    converted = float(value)
    if (upper and Fraction(converted) < value) or (not upper and Fraction(converted) > value):
        converted = math.nextafter(converted, math.inf if upper else -math.inf)
    return converted


def intersection(intervals):
    lo, hi = max(i[0] for i in intervals), min(i[1] for i in intervals)
    return [lo, hi] if lo <= hi else None


def align_clocks(records, clock):
    result = {"status": "unresolved", "reasonCode": None, "bootUUID": None,
              "models": [], "markers": {}, "snapshotErrors": clock["errors"]}
    snapshots = clock["snapshots"]
    if clock["errors"] or set(snapshots) != {"before", "after"}:
        result["reasonCode"] = "clock-snapshots-incomplete"
        return result
    before, after = snapshots["before"], snapshots["after"]
    if any(before[k] != after[k] for k in ("bootUUID", "machTimebaseNumer", "machTimebaseDenom")):
        result["reasonCode"] = "clock-boot-or-timebase-changed"
        return result
    result["bootUUID"] = before["bootUUID"]
    if (before["systemUptimeAfterLog"] >= after["systemUptimeSample"]
            or before["wallAfterLogUnixSeconds"] >= after["wallBeforeLogUnixSeconds"]
            or any(before[f + "AfterLog"] >= after[f + "BeforeUptime"] for f in ("absolute", "continuous"))):
        result["reasonCode"] = "clock-before-after-order"
        return result
    for phase, snapshot in snapshots.items():
        message = "LEMULIP_NATIVE_TRACE_CLOCK " + clock["config"]["nonce"] + " " + phase
        candidates = [(index, row) for index, row in enumerate(records)
            if row.get("subsystem") == CLOCK_SUBSYSTEM and row.get("category") == CLOCK_CATEGORY
            and row.get("eventMessage") == message]
        matches = [(index, row) for index, row in candidates
            if row.get("processID") == snapshot["pid"]
            and type(row.get("processID")) is int
            and row.get("processImagePath") == snapshot["executablePath"]
            and row.get("bootUUID") == snapshot["bootUUID"]]
        result["markers"][phase] = {"candidateRecordIndices": [i for i, _ in candidates],
                                    "identityMatchedRecordIndices": [i for i, _ in matches]}
        if len(candidates) != 1 or len(matches) != 1:
            result["reasonCode"] = "clock-marker-missing-or-ambiguous"
            return result
        index, row = matches[0]
        tick = row.get("machTimestamp")
        if type(tick) is not int or not 0 < tick < 2 ** 64:
            result["reasonCode"] = "clock-marker-mach-timestamp"
            return result
        result["markers"][phase].update(sourceRecordIndex=index, machTimestamp=tick)
    scale = Fraction(before["machTimebaseNumer"], before["machTimebaseDenom"] * 1_000_000_000)
    for family in ("absolute", "continuous"):
        intervals, supported = [], True
        for phase, snapshot in snapshots.items():
            tick = result["markers"][phase]["machTimestamp"]
            if not snapshot[family + "BeforeLog"] <= tick <= snapshot[family + "AfterLog"]:
                supported = False
                break
            intervals.append(offset_interval(snapshot["systemUptimeSample"],
                snapshot[family + "BeforeUptime"], snapshot[family + "AfterUptime"], scale))
            intervals.append([Fraction(snapshot["systemUptimeBeforeLog"]) - tick * scale,
                              Fraction(snapshot["systemUptimeAfterLog"]) - tick * scale])
        overlap = intersection(intervals) if supported else None
        if overlap is not None:
            result["models"].append({"clockKind": family, "secondsPerTick": float(scale),
                "machTimebaseNumer": before["machTimebaseNumer"], "machTimebaseDenom": before["machTimebaseDenom"],
                "offsetIntervalSeconds": [directed_float(overlap[0], False), directed_float(overlap[1], True)]})
    if not result["models"]:
        result["reasonCode"] = "clock-no-stable-bracketed-model"
        return result
    result.update(status="aligned", reasonCode=None,
        clockKindAmbiguous=len(result["models"]) > 1,
        modelPolicy="Union of compatible model intervals; no nearest-model selection or extrapolation.")
    return result


def uptime_interval(row, alignment):
    if alignment["status"] != "aligned":
        return {"status": "unresolved", "reasonCode": "clock-alignment-unresolved"}
    tick = row.get("machTimestamp")
    if row.get("bootUUID") != alignment["bootUUID"] or type(tick) is not int or not 0 < tick < 2 ** 64:
        return {"status": "unresolved", "reasonCode": "event-boot-or-mach-timestamp"}
    if not alignment["markers"]["before"]["machTimestamp"] <= tick <= alignment["markers"]["after"]["machTimestamp"]:
        return {"status": "unresolved", "reasonCode": "outside-calibrated-interval"}
    intervals = []
    for model in alignment["models"]:
        seconds = Fraction(tick * model["machTimebaseNumer"], model["machTimebaseDenom"] * 1_000_000_000)
        intervals.append([directed_float(seconds + Fraction(model["offsetIntervalSeconds"][0]), False),
                          directed_float(seconds + Fraction(model["offsetIntervalSeconds"][1]), True)])
    return {"status": "bounded", "lower": min(v[0] for v in intervals), "upper": max(v[1] for v in intervals)}


def normalized_asn(value):
    return "-".join("0x" + format(int(part, 16), "x") for part in value.split("-"))


def wall_case_matches(entry, context):
    try:
        when = wall(entry.get("timestamp"))
    except (ValueError, TypeError, capture.ComparisonError):
        return []
    return [c for c in context["cases"] if c["wallStartUnixSeconds"] <= when < c["wallEndUnixSeconds"]]


def owned_emitter_matches(entry, context):
    matches = wall_case_matches(entry, context)
    if len(matches) != 1:
        return []
    return [{"case": case["case"], "role": role, "pid": pid}
            for case in matches for role, pid in case["ownedPIDs"].items()
            if type(entry.get("processID")) is int and entry["processID"] == pid
            and entry.get("processImagePath") == case["ownedExecutablePaths"][role]]


def phase_for(bound, case, role):
    if bound["status"] != "bounded":
        return {"status": "unresolved", "reasonCode": bound["reasonCode"]}
    lifetime = case["observedLifetimes"].get(role)
    if lifetime is None or not lifetime[0] < bound["lower"] <= bound["upper"] < lifetime[1]:
        return {"status": "unresolved", "reasonCode": "outside-or-crossing-observed-lifetime"}
    matches = [p["phase"] for p in case["phases"] if p["start"] < bound["lower"] <= bound["upper"] < p["end"]]
    if len(matches) != 1:
        return {"status": "unresolved", "reasonCode": "phase-boundary-crossing"}
    result = {"status": "resolved", "phase": matches[0]}
    if matches[0] == "cancel-after-escape-before-release-observation":
        result["heldButtonClaimSupported"] = False
    return result


def analyze_records(records, context, clock):
    """Pure replay surface; all inputs are serialized retained evidence, no I/O."""
    require(isinstance(records, list) and all(isinstance(row, dict) for row in records), "log-json-array")
    alignment = align_clocks(records, clock)
    if alignment["status"] == "aligned" and (
            clock["snapshots"]["before"]["systemUptimeAfterLog"] >= min(c["phases"][0]["start"] for c in context["cases"])
            or clock["snapshots"]["after"]["systemUptimeSample"] <= max(c["phases"][-1]["end"] for c in context["cases"])):
        alignment.update(status="unresolved", reasonCode="clock-not-outside-observed-case-lifetimes", models=[])
    front, anchors, by_asn, by_pid, self_paths = [], [], {}, {}, {}
    cases = {case["case"]: case for case in context["cases"]}
    for index, entry in enumerate(records):
        if entry.get("subsystem") != FRONT_SUBSYSTEM or entry.get("category") != FRONT_CATEGORY:
            continue
        message = entry.get("eventMessage")
        message = message if isinstance(message, str) else ""
        bring, setting = BRING.fullmatch(message), SET.fullmatch(message)
        row = {"sourceRecordIndex": index, "entry": entry, "emittingPID": entry.get("processID"),
            "ownedEmitterMatches": owned_emitter_matches(entry, context),
            "uptimeInterval": uptime_interval(entry, alignment), "kind": "unrecognized-front-format"}
        boot = entry.get("bootUUID")
        valid_boot = isinstance(boot, str) and UUID.fullmatch(boot) is not None
        if bring:
            pid, asn = int(bring[1]), normalized_asn(bring[2])
            row.update(kind="bring-front-modifier", messagePID=pid, asn=asn, ownedAnchorMatches=[])
            if valid_boot and 0 < pid < 2 ** 31:
                by_asn.setdefault((boot, asn), set()).add(pid)
                by_pid.setdefault((boot, pid), set()).add(asn)
                if type(entry.get("processID")) is int and entry["processID"] == pid:
                    self_paths.setdefault((boot, asn, pid), set()).add(entry.get("processImagePath")
                        if isinstance(entry.get("processImagePath"), str) else None)
                if boot == alignment.get("bootUUID"):
                    row["ownedAnchorMatches"] = [m for m in row["ownedEmitterMatches"] if m["pid"] == pid]
            anchors.append(row)
        elif setting:
            row.update(kind="set-front-process", asn=normalized_asn(setting[1]), optionsHex=setting[2])
        front.append(row)
    conflicts = [{"kind": "asn-multiple-pids", "bootUUID": b, "asn": a, "messagePIDs": sorted(v)}
                 for (b, a), v in sorted(by_asn.items()) if len(v) > 1]
    conflicts += [{"kind": "pid-multiple-asns", "bootUUID": b, "messagePID": p, "asns": sorted(v)}
                  for (b, p), v in sorted(by_pid.items()) if len(v) > 1]
    conflicts += [{"kind": "self-emitter-path-conflict", "bootUUID": b, "asn": a, "messagePID": p,
                   "processImagePaths": sorted(v, key=repr)}
                  for (b, a, p), v in sorted(self_paths.items()) if len(v) > 1]
    for row in front:
        if row["kind"] != "set-front-process":
            continue
        boot, asn = row["entry"].get("bootUUID"), row["asn"]
        matching = [a for a in anchors if a["entry"].get("bootUUID") == boot and a["asn"] == asn]
        row["candidateAnchorIndices"] = [a["sourceRecordIndex"] for a in matching]
        identities = sorted({(m["case"], m["role"], m["pid"]) for a in matching for m in a["ownedAnchorMatches"]})
        mapped_pids = by_asn.get((boot, asn), set())
        conflict = len(mapped_pids) > 1 or any(len(by_pid.get((boot, p), set())) > 1
            or len(self_paths.get((boot, asn, p), set())) > 1 for p in mapped_pids)
        association = {"status": "unresolved", "reasonCode": "owned-asn-anchor-unavailable"}
        phase = {"status": "unresolved", "reasonCode": "target-association-unresolved"}
        if conflict or len(identities) > 1:
            association["reasonCode"] = "conflicting-or-ambiguous-asn-anchors"
        elif len(identities) == 1:
            name, role, pid = identities[0]
            case = cases[name]
            association.update(case=name, role=role, targetPID=pid, asn=asn, bootUUID=boot)
            wall_matches = wall_case_matches(row["entry"], context)
            if len(wall_matches) != 1 or case not in wall_matches:
                association["reasonCode"] = "outside-owned-case-wall-window"
            else:
                association.update(status="candidate-owned-association", reasonCode=None)
                phase = phase_for(row["uptimeInterval"], case, role)
                if phase["status"] == "resolved":
                    association["status"] = "bound-to-owned-observed-lifetime"
        row.update(targetAssociation=association, phase=phase)
    startup = []
    for case in context["cases"]:
        cancel_start = next(p["start"] for p in case["phases"] if p["phase"] == "cancel-before-entry")
        for role in ("source", "target"):
            def before_cancel(row):
                b = row["uptimeInterval"]
                return b["status"] == "bounded" and b["upper"] < cancel_start
            role_anchors = [a for a in anchors if before_cancel(a) and any(
                m["case"] == case["case"] and m["role"] == role for m in a["ownedAnchorMatches"])
                and len(by_asn.get((a["entry"]["bootUUID"], a["asn"]), set())) == 1
                and len(by_pid.get((a["entry"]["bootUUID"], a["messagePID"]), set())) == 1
                and len(self_paths.get((a["entry"]["bootUUID"], a["asn"], a["messagePID"]), set())) == 1]
            role_requests = [r for r in front if r["kind"] == "set-front-process" and before_cancel(r)
                and r["targetAssociation"].get("case") == case["case"] and r["targetAssociation"].get("role") == role
                and r["targetAssociation"]["status"] != "unresolved"]
            startup.append({"case": case["case"], "role": role,
                "mappingRecordIndices": [a["sourceRecordIndex"] for a in role_anchors],
                "setFrontRecordIndices": [r["sourceRecordIndex"] for r in role_requests],
                "status": "observed" if role_anchors and role_requests else "partial" if role_anchors or role_requests else "unresolved",
                "generalHeldPathCoverageEstablished": False})
    return {"schema": 1, "diagnostic": "native-drag-activation-request-log", "status": "analyzed",
        "nativeVerdictsChanged": False, "nativeResults": context["nativeResults"],
        "originAttribution": "not-established", "clockAlignment": alignment,
        "frontRecords": front, "mappingConflicts": conflicts, "startupCalibration": startup,
        "recordCount": len(records), "frontRecordCount": len(front),
        "redactedFrontRecordCount": sum(any(t in str(r["entry"].get("eventMessage", "")).lower()
            for t in ("<private>", "<redacted>")) for r in front),
        "interpretation": "Full records are preserved. Emitting PID is separate from the boot-scoped target ASN association. "
            "Neither identifies the original upstream requester through an intermediary. ActivityIdentifier and traceID "
            "are not used for causal joins. Startup positive calibration does not establish held-path coverage. "
            "The release-observation endpoint is not the physical release; its preceding post-Escape interval "
            "does not establish that the button is still held. "
            "Missing, unrecognized, redacted or unresolved records never establish absence of an activation request."}


def error_reason(error):
    return str(error)[:512] if isinstance(error, capture.ComparisonError) else type(error).__name__


def collect(stage, comparison, clock_dir, output, experiment_commit, runner=bounded_log.run_log):
    require(not output.exists() and not output.is_symlink(), "output-already-exists")
    output.mkdir(parents=False)
    receipt = {"schema": 1, "diagnostic": "native-drag-activation-request-log",
        "experimentCommit": experiment_commit, "status": "error", "collectionCompleted": False,
        "queryCount": 0, "nativeInputExecuted": False, "nativeVerdictsChanged": False,
        "loggingConfigurationChanged": False, "originAttribution": "not-established",
        "timeoutSeconds": TIMEOUT_SECONDS, "byteLimit": BYTE_LIMIT,
        "stdoutFile": "raw.stdout", "stderrFile": "raw.stderr", "recordsFile": None,
        "startedAt": datetime.now(timezone.utc).isoformat()}
    stdout, stderr = b"", b""
    analysis = None
    try:
        context, clock = load_context(stage, comparison, clock_dir, experiment_commit)
        capture.write_json(output / "context.json", context)
        capture.write_json(output / "clock-inputs.json", clock)
        receipt.update(contextSHA256=capture.sha256(output / "context.json"),
            clockInputsSHA256=capture.sha256(output / "clock-inputs.json"), nativeResults=context["nativeResults"],
            comparisonSHA256=context["comparisonSHA256"], provenanceSHA256=context["provenanceSHA256"])
        command = command_for(context)
        receipt.update(command=command, queryCount=1)
        run = runner(command, timeout=TIMEOUT_SECONDS, byte_limit=BYTE_LIMIT)
        raw_stdout, raw_stderr = run["stdout"], run["stderr"]
        require(isinstance(raw_stdout, bytes) and isinstance(raw_stderr, bytes), "query-buffer-contract")
        stdout = raw_stdout[:BYTE_LIMIT]
        stderr = raw_stderr[:BYTE_LIMIT - len(stdout)]
        require(len(raw_stdout) + len(raw_stderr) <= BYTE_LIMIT, "query-buffer-contract")
        receipt.update({key: value for key, value in run.items() if key not in ("stdout", "stderr")})
        receipt["stdoutComplete"] = run["status"] == "completed"
        if run["status"] == "completed":
            require(run["returnCode"] == 0, "log-command-nonzero-exit")
            records = mouse.decoded_json(stdout, "activation-request-log-output")
            require(isinstance(records, list) and all(isinstance(row, dict) for row in records), "log-json-array")
            capture.write_json(output / "records.json", records)
            receipt.update(collectionCompleted=True, recordsFile="records.json",
                recordsSHA256=capture.sha256(output / "records.json"), recordCount=len(records),
                status="completed-records" if records else "completed-empty")
            analysis = analyze_records(records, context, clock)
            capture.write_json(output / "analysis.json", analysis)
            receipt.update(analysisSHA256=capture.sha256(output / "analysis.json"),
                clockAlignmentStatus=analysis["clockAlignment"]["status"])
    except Exception as error:
        receipt.update(status="error", errorCode=error_reason(error))
    finally:
        (output / "raw.stdout").write_bytes(stdout)
        (output / "raw.stderr").write_bytes(stderr)
        receipt.update(stdoutBytes=len(stdout), stderrBytes=len(stderr),
            stdoutSHA256=hashlib.sha256(stdout).hexdigest(), stderrSHA256=hashlib.sha256(stderr).hexdigest(),
            fullRawSHA256=hashlib.sha256(stdout).hexdigest() if receipt.get("stdoutComplete") else None,
            finishedAt=datetime.now(timezone.utc).isoformat())
        capture.write_json(output / "receipt.json", receipt)
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("staged", "comparison", "clock-dir", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--experiment-commit", required=True)
    args = parser.parse_args()
    result = collect(args.staged.resolve(), args.comparison.resolve(), args.clock_dir.resolve(),
                     args.output.absolute(), args.experiment_commit)
    print(json.dumps(result, indent=2, sort_keys=True, allow_nan=False))
    return exit_status(result)


def exit_status(result):
    return 0 if result["collectionCompleted"] and result["status"] in ("completed-records", "completed-empty") else 1


if __name__ == "__main__":
    sys.exit(main())
