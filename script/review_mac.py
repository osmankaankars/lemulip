#!/usr/bin/env python3
"""Collect local Mac readiness and optional idle measurements, without publishing."""
from __future__ import annotations

import argparse
import ctypes
import datetime
import functools
import json
import math
import os
from pathlib import Path
import platform
import plistlib
import re
import stat
import statistics
import struct
import subprocess
import sys
import time
from xml.parsers.expat import ExpatError

ROOT = Path(__file__).resolve().parent.parent
BUNDLE_ID = "app.freewheel.Freewheel"
REPORT_NAMES = ("Lemulip-Mac-Review.json", "Lemulip-Mac-Review.md")
SETTLE_SECONDS = 60
SAMPLE_SECONDS = 60


class RUsageInfoV0(ctypes.Structure):
    # Apple XNU's fixed V0 layout; do not use a newer flavor with this buffer.
    # https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/sys/resource.h
    _fields_ = [
        ("ri_uuid", ctypes.c_uint8 * 16),
        ("ri_user_time", ctypes.c_uint64),
        ("ri_system_time", ctypes.c_uint64),
        ("ri_pkg_idle_wkups", ctypes.c_uint64),
        ("ri_interrupt_wkups", ctypes.c_uint64),
        ("ri_pageins", ctypes.c_uint64),
        ("ri_wired_size", ctypes.c_uint64),
        ("ri_resident_size", ctypes.c_uint64),
        ("ri_phys_footprint", ctypes.c_uint64),
        ("ri_proc_start_abstime", ctypes.c_uint64),
        ("ri_proc_exit_abstime", ctypes.c_uint64),
    ]


class ReviewError(Exception):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ReviewError(message)


def command(arguments: list[str], timeout: int = 5):
    """Capture locally; callers return only allowlisted values, never raw output."""
    environment = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C"}
    try:
        return subprocess.run(arguments, capture_output=True, text=True,
                              errors="replace", timeout=timeout, env=environment)
    except (OSError, subprocess.TimeoutExpired):
        return None


def scalar(arguments: list[str], pattern: str):
    result = command(arguments)
    if result is not None and result.returncode == 0:
        value = result.stdout.strip()
        if re.fullmatch(pattern, value):
            return value
    return None


def system_summary() -> dict:
    memory = scalar(["/usr/sbin/sysctl", "-n", "hw.memsize"], r"[0-9]{1,16}")
    arm64 = scalar(["/usr/sbin/sysctl", "-n", "hw.optional.arm64"], r"[01]")
    architecture = platform.machine()
    return {
        "model": scalar(["/usr/sbin/sysctl", "-n", "hw.model"], r"[A-Za-z]+[0-9]+,[0-9]+"),
        "macos_version": scalar(["/usr/bin/sw_vers", "-productVersion"], r"[0-9]+(?:\.[0-9]+){1,2}"),
        "macos_build": scalar(["/usr/bin/sw_vers", "-buildVersion"], r"[0-9]{1,3}[A-Z][0-9]{1,6}[a-z]?"),
        "architecture": "arm64" if arm64 == "1" else architecture if architecture in {"arm64", "x86_64"} else None,
        "physical_memory_bytes": int(memory) if memory else None,
    }


def architectures(executable: Path) -> list[str]:
    """Read Mach-O CPU types without requiring Xcode or invoking a tool stub."""
    with executable.open("rb") as stream:
        header = stream.read(8)
        require(len(header) == 8, "The app executable has an invalid header.")
        magic = header[:4]
        thin = {b"\xcf\xfa\xed\xfe": "<", b"\xfe\xed\xfa\xcf": ">"}
        fat = {b"\xca\xfe\xba\xbe": (">", 20), b"\xbe\xba\xfe\xca": ("<", 20),
               b"\xca\xfe\xba\xbf": (">", 32), b"\xbf\xba\xfe\xca": ("<", 32)}
        if magic in thin:
            types = [struct.unpack(thin[magic] + "I", header[4:])[0]]
        else:
            require(magic in fat, "The app executable is not a supported Mach-O binary.")
            endian, record_size = fat[magic]
            count = struct.unpack(endian + "I", header[4:])[0]
            require(1 <= count <= 8, "The app executable has an invalid architecture count.")
            records = stream.read(count * record_size)
            require(len(records) == count * record_size, "The app executable has a truncated header.")
            types = [struct.unpack_from(endian + "I", records, i * record_size)[0] for i in range(count)]
    names = {0x0100000C: "arm64", 0x01000007: "x86_64"}
    require(all(value in names for value in types), "The app contains an unexpected architecture.")
    return sorted({names[value] for value in types})


def inspect_bundle(app: Path) -> tuple[dict, Path]:
    require(app.is_dir() and app.suffix == ".app", "Select an existing Lemulip app bundle.")
    info_path = app / "Contents" / "Info.plist"
    require(not info_path.is_symlink() and info_path.is_file() and info_path.stat().st_size <= 65536
            and info_path.resolve().is_relative_to(app),
            "The app bundle has no valid Info.plist.")
    try:
        info = plistlib.loads(info_path.read_bytes())
    except (ValueError, TypeError, plistlib.InvalidFileException, ExpatError):
        raise ReviewError("The app bundle has an invalid Info.plist.") from None
    require(isinstance(info, dict) and info.get("CFBundleIdentifier") == BUNDLE_ID
            and info.get("CFBundleExecutable") == "Lemulip", "The selected bundle is not Lemulip.")
    version, build = info.get("CFBundleShortVersionString"), info.get("CFBundleVersion")
    require(isinstance(version, str) and re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version)
            and isinstance(build, str) and re.fullmatch(r"[0-9]{1,10}", build),
            "The app bundle has an invalid version or build number.")
    executable = app / "Contents" / "MacOS" / "Lemulip"
    require(executable.is_file() and not executable.is_symlink()
            and executable.resolve().is_relative_to(app), "The app executable is missing or outside its bundle.")
    logical = 0
    count = 0
    def unreadable(_error):
        raise ReviewError("Some app bundle files could not be read.")

    for directory, folders, files in os.walk(app, followlinks=False, onerror=unreadable):
        for name in folders + files:
            item = Path(directory) / name
            metadata = item.lstat()
            require(stat.S_ISREG(metadata.st_mode) or stat.S_ISDIR(metadata.st_mode)
                    or stat.S_ISLNK(metadata.st_mode), "The app contains an unexpected file type.")
            count += 1
            require(count <= 100000, "The app contains too many entries for this review.")
            if stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
                logical += metadata.st_size
    allocated = command(["/usr/bin/du", "-sk", str(app)])
    allocated_bytes = None
    if allocated is not None and allocated.returncode == 0:
        match = re.match(r"^([0-9]+)\s", allocated.stdout)
        if match:
            allocated_bytes = int(match[1]) * 1024
    return {"version": version, "build": build, "architectures": architectures(executable),
            "logical_bundle_bytes": logical, "allocated_bundle_bytes": allocated_bytes}, executable


def signature_summary(app: Path) -> dict:
    verified = command(["/usr/bin/codesign", "--verify", "--all-architectures", "--strict", str(app)])
    details = command(["/usr/bin/codesign", "--display", "--verbose=4", str(app)])
    kind, runtime = "Not Available", None
    if details is not None and details.returncode == 0:
        content = details.stdout + "\n" + details.stderr
        if re.search(r"^Signature=adhoc\s*$", content, re.MULTILINE):
            kind = "Ad Hoc"
        elif re.search(r"^Authority=Developer ID Application:", content, re.MULTILINE):
            kind = "Developer ID Application"
        else:
            kind = "Other Signature"
        flags = re.search(r"\bflags=0x([0-9a-fA-F]+)\b", content)
        if flags:
            runtime = bool(int(flags[1], 16) & 0x10000)
    print("Checking Local Gatekeeper Assessment...", flush=True)
    assessment = command(["/usr/sbin/spctl", "--assess", "--type", "execute", "--verbose=2", str(app)], timeout=25)
    gatekeeper = "Not Available"
    if assessment is not None:
        if assessment.returncode == 0:
            gatekeeper = "Accepted"
        elif re.search(r"(?:^|:\s*)rejected\b", assessment.stdout + "\n" + assessment.stderr, re.MULTILINE):
            gatekeeper = "Rejected"
    return {"kind": kind, "integrity_verified": verified.returncode == 0 if verified else None,
            "hardened_runtime": runtime, "local_gatekeeper_assessment": gatekeeper,
            "notarization": "Not Verified", "downloaded_first_launch": "Not Reviewed"}


def signing_identity_count():
    result = command(["/usr/bin/security", "find-identity", "-v", "-p", "codesigning"])
    if result is None or result.returncode != 0:
        return None
    rows = re.findall(r'^\s*[0-9]+\)\s+[0-9A-Fa-f]{40}\s+"([^"\r\n]+)"\s*$', result.stdout, re.MULTILINE)
    total = re.search(r"\b([0-9]+) valid identities found\b", result.stdout)
    if total is None or int(total[1]) != len(rows):
        return None
    return sum(name.startswith("Developer ID Application: ") for name in rows)


def cpu_seconds(value: str) -> float:
    require(bool(re.fullmatch(r"(?:[0-9]+-)?[0-9]+(?::[0-9]+){1,2}(?:\.[0-9]+)?", value)),
            "The process CPU time could not be read.")
    day_text, remainder = value.split("-", 1) if "-" in value else ("0", value)
    parts = remainder.split(":")
    hours, minutes, seconds = ("0", *parts) if len(parts) == 2 else parts
    require(float(seconds) < 60 and (len(parts) == 2 or int(minutes) < 60),
            "The process CPU time has an unexpected format.")
    return int(day_text) * 86400 + int(hours) * 3600 + int(minutes) * 60 + float(seconds)


@functools.lru_cache(maxsize=1)
def process_library():
    library = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
    library.proc_pidpath.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
    library.proc_pidpath.restype = ctypes.c_int
    return library


def process_path(pid: int) -> Path:
    buffer = ctypes.create_string_buffer(4096)
    require(process_library().proc_pidpath(pid, buffer, len(buffer)) > 0,
            "The selected process executable could not be verified.")
    return Path(os.fsdecode(buffer.value)).resolve()


@functools.lru_cache(maxsize=1)
def wakeup_function():
    function = process_library().proc_pid_rusage
    function.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]
    function.restype = ctypes.c_int
    return function


def wakeup_snapshot(pid: int) -> dict:
    """Read optional counters without weakening process checks or requiring sudo."""
    if (ctypes.sizeof(ctypes.c_void_p) != 8 or ctypes.sizeof(RUsageInfoV0) != 96
            or RUsageInfoV0.ri_pkg_idle_wkups.offset != 32
            or RUsageInfoV0.ri_interrupt_wkups.offset != 40
            or RUsageInfoV0.ri_proc_start_abstime.offset != 80
            or RUsageInfoV0.ri_proc_exit_abstime.offset != 88):
        return {"status": "Not Measured", "reason": "Native Wakeup Counter Layout Unsupported"}
    try:
        function = wakeup_function()
        usage = RUsageInfoV0()
        before = time.monotonic()
        result = function(pid, 0, ctypes.byref(usage))
        after = time.monotonic()
    except (AttributeError, OSError, TypeError, ValueError, ctypes.ArgumentError):
        return {"status": "Not Measured", "reason": "Native Wakeup Counters Unavailable"}
    if result != 0:
        return {"status": "Not Measured", "reason": "Native Wakeup Counters Unavailable"}
    if not 0 <= after - before <= 1:
        return {"status": "Not Measured", "reason": "Native Wakeup Read Interrupted"}
    if usage.ri_proc_start_abstime == 0:
        return {"status": "Not Measured", "reason": "Native Wakeup Process Identity Unavailable"}
    if usage.ri_proc_exit_abstime != 0:
        return {"status": "Not Measured", "reason": "App Process Exited During Wakeup Measurement"}
    return {"status": "Measured", "time": before + (after - before) / 2,
            "process_start": usage.ri_proc_start_abstime,
            "interrupt": usage.ri_interrupt_wkups, "platform_idle": usage.ri_pkg_idle_wkups}


def wakeup_measurement(start: dict, end: dict) -> dict:
    """Return interval counts only; timestamps and process identifiers stay local."""
    for snapshot in (start, end):
        if snapshot["status"] != "Measured":
            return {"status": "Not Measured", "reason": snapshot["reason"]}
    if start["process_start"] != end["process_start"]:
        return {"status": "Not Measured", "reason": "App Process Changed During Wakeup Measurement"}
    if any(end[key] < start[key] for key in ("interrupt", "platform_idle")):
        return {"status": "Not Measured", "reason": "Native Wakeup Counters Decreased"}
    elapsed = end["time"] - start["time"]
    if not math.isfinite(elapsed) or elapsed <= 0:
        return {"status": "Not Measured", "reason": "Wakeup Observation Interval Invalid"}
    # XNU maps these to interrupt and platform-idle task ledgers. They overlap;
    # neither their sum nor the app's timer interval measures total wakeups/energy.
    # https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/osfmk/kern/bsd_kern.c
    interrupt = end["interrupt"] - start["interrupt"]
    platform_idle = end["platform_idle"] - start["platform_idle"]
    return {"status": "Measured", "source": "proc_pid_rusage (RUSAGE_INFO_V0)",
            "scope": "Main App Process Only", "observation_seconds": round(elapsed, 3),
            "interrupt_wakeups": interrupt, "interrupt_wakeups_per_second": round(interrupt / elapsed, 4),
            "platform_idle_wakeups": platform_idle,
            "platform_idle_wakeups_per_second": round(platform_idle / elapsed, 4)}


def process_snapshot(pid: int, executable: Path) -> dict:
    result = command(["/bin/ps", "-p", str(pid), "-o", "uid=", "-o", "lstart=", "-o", "rss=", "-o", "time="])
    require(result is not None and result.returncode == 0, "The selected app process is no longer available.")
    fields = result.stdout.split()
    require(len(fields) == 8 and fields[0].isdigit() and fields[6].isdigit(),
            "The app process counters could not be read.")
    require(int(fields[0]) == os.getuid() and process_path(pid) == executable.resolve(),
            "The process does not belong to the current user and selected Lemulip app.")
    metadata = executable.stat()
    return {"identity": (pid, tuple(fields[1:6]), metadata.st_dev, metadata.st_ino,
                         metadata.st_size, metadata.st_mtime_ns),
            "rss_bytes": int(fields[6]) * 1024, "cpu_seconds": cpu_seconds(fields[7]),
            "time": time.monotonic()}


def choose_process(pid, executable: Path) -> tuple[int, dict]:
    if pid is None:
        found = command(["/usr/bin/pgrep", "-U", str(os.getuid()), "-x", "Lemulip"])
        require(found is not None and found.returncode in {0, 1}, "The running app could not be located.")
        candidates = found.stdout.split()
        require(all(value.isdigit() and 0 < int(value) <= 2147483647 for value in candidates),
                "The running app process list could not be read.")
        require(bool(candidates),
                "No Lemulip process is running for the current user. Open the selected app, wait for its workspace, then retry.")
        matching = []
        for candidate in sorted({int(value) for value in candidates}):
            try:
                actual = process_path(candidate)
            except (ReviewError, OSError):
                raise ReviewError("A running Lemulip process could not be verified. Wait for the app to finish opening and retry, or use --pid for the selected instance.") from None
            if actual == executable.resolve():
                matching.append(candidate)
        require(bool(matching),
                "Lemulip is running from a different app bundle. Open the selected app, or use --app to select the running bundle.")
        require(len(matching) == 1,
                "Multiple instances of the selected app are running. Finish any work and quit the other instances, or use --pid to select one.")
        pid = matching[0]
    return pid, process_snapshot(pid, executable)


def measure_idle(executable: Path, pid=None) -> dict:
    require(sys.stdin.isatty(), "Idle measurement requires an interactive Terminal for confirmation.")
    pid, initial = choose_process(pid, executable)
    print("Keep the workspace visible and the drag wheel enabled. Close editors and finish all jobs and playback.")
    print("Do not use Lemulip or drag files during the next two minutes. The app will stay open.")
    try:
        answer = input("Type IDLE to confirm these conditions, or press Return to skip: ").strip()
    except EOFError:
        answer = ""
    if answer != "IDLE":
        return {"status": "Not Measured", "reason": "Idle Conditions Not Confirmed",
                "wakeups": "Not Measured", "warm_interactive_launch": "Not Measured"}
    current = process_snapshot(pid, executable)
    require(current["identity"] == initial["identity"], "The app process or executable changed before measurement.")
    print(f"Settling: {SETTLE_SECONDS} Seconds", flush=True)
    settle_start = time.monotonic()
    for second in range(1, SETTLE_SECONDS + 1):
        time.sleep(max(0, settle_start + second - time.monotonic()))
        current = process_snapshot(pid, executable)
        require(current["identity"] == initial["identity"], "The app process or executable changed during measurement.")
        if second % 30 == 0:
            print(f"Settling: {second} / {SETTLE_SECONDS} Seconds", flush=True)
    start = process_snapshot(pid, executable)
    require(start["identity"] == initial["identity"], "The app process or executable changed during measurement.")
    wakeup_start = wakeup_snapshot(pid)
    samples = [start]
    print(f"Measuring: {SAMPLE_SECONDS} Seconds", flush=True)
    for second in range(1, SAMPLE_SECONDS + 1):
        time.sleep(max(0, start["time"] + second - time.monotonic()))
        current = process_snapshot(pid, executable)
        require(current["identity"] == initial["identity"], "The app process or executable changed during measurement.")
        require(0 < current["time"] - samples[-1]["time"] <= 5,
                "Sampling was interrupted. Keep the Mac awake and repeat the measurement.")
        require(current["cpu_seconds"] >= samples[-1]["cpu_seconds"], "The app CPU counter changed unexpectedly.")
        samples.append(current)
        if second % 30 == 0:
            print(f"Measuring: {second} / {SAMPLE_SECONDS} Seconds", flush=True)
    wakeup_end = wakeup_snapshot(pid) if wakeup_start["status"] == "Measured" else wakeup_start
    wakeups = wakeup_measurement(wakeup_start, wakeup_end)
    elapsed = samples[-1]["time"] - start["time"]
    return {
        "status": "Measured", "conditions": "Operator Confirmed: Workspace Visible, Wheel Enabled, No Jobs, Editors, Playback or Dragging",
        "scope": "Main App Process Only", "settling_seconds": round(start["time"] - settle_start, 3),
        "observation_seconds": round(elapsed, 3), "rss_sample_count": len(samples),
        "mean_rss_bytes": round(statistics.mean(sample["rss_bytes"] for sample in samples)),
        "peak_sampled_rss_bytes": max(sample["rss_bytes"] for sample in samples),
        "mean_cpu_percent_one_core": round(100 * (samples[-1]["cpu_seconds"] - start["cpu_seconds"]) / elapsed, 4),
        "wakeups": wakeups["status"], "wakeup_measurement": wakeups,
        "warm_interactive_launch": "Not Measured",
    }


def prepare_output(directory: Path) -> Path:
    directory = directory.expanduser().resolve()
    require(not directory.is_relative_to(ROOT), "Choose an output directory outside the source or review-kit folder.")
    for parent in [directory, *directory.parents]:
        require(not os.path.lexists(parent / ".git"), "Choose an output directory outside a Git checkout.")
    require(not directory.exists() or directory.is_dir(), "The report output must be a directory.")
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    require(all(not os.path.lexists(directory / name) for name in REPORT_NAMES),
            "A report already exists in this directory. Choose a new output directory; existing reports are preserved.")
    return directory


def markdown_report(report: dict) -> str:
    def value(item):
        if item is None:
            return "Not Available"
        if isinstance(item, bool):
            return "Yes" if item else "No"
        if isinstance(item, list):
            return ", ".join(item)
        return str(item)

    def size(item):
        return "Not Available" if item is None else f"{item / 1_000_000:.2f} MB ({item:,} bytes)"

    app, system, signature, idle = (report[key] for key in ("app", "system", "signature", "idle"))
    rows = [
        ("Lemulip", f"{app['version']} (Build {app['build']})"),
        ("Mac Model", system["model"]), ("Hardware Architecture", system["architecture"]),
        ("macOS", system["macos_version"]), ("macOS Build", system["macos_build"]),
        ("Physical Memory", size(system["physical_memory_bytes"])),
        ("App Architectures", app["architectures"]),
        ("Logical Bundle Size", size(app["logical_bundle_bytes"])),
        ("Allocated Bundle Size", size(app["allocated_bundle_bytes"])),
        ("Signature", signature["kind"]), ("Signature Integrity Verified", signature["integrity_verified"]),
        ("Hardened Runtime", signature["hardened_runtime"]),
        ("Local Gatekeeper Assessment", signature["local_gatekeeper_assessment"]),
        ("Available Developer ID Application Identities", report["developer_id_identity_count"]),
        ("Apple Notarization", "Not Verified"), ("Downloaded First Launch", "Not Reviewed"),
    ]
    lines = ["# Lemulip Mac Review", "", f"Collected: {report['collected_utc']}", "",
             "This local readiness report does not complete any hands-on roadmap acceptance gate.", "",
             "## Readiness", "", "| Check | Result |", "| --- | --- |"]
    lines += [f"| {title} | {value(result)} |" for title, result in rows]
    lines += ["", "## Idle Measurements", "", f"Status: **{idle['status']}**", ""]
    if idle["status"] == "Measured":
        lines += ["| Metric | Result |", "| --- | --- |",
                  f"| Settling Period (Seconds) | {idle['settling_seconds']} |",
                  f"| Observation Period (Seconds) | {idle['observation_seconds']} |",
                  f"| RSS Samples | {idle['rss_sample_count']} |",
                  f"| Mean Resident Memory | {size(idle['mean_rss_bytes'])} |",
                  f"| Peak Sampled Resident Memory | {size(idle['peak_sampled_rss_bytes'])} |",
                  f"| Mean CPU (% of One Logical CPU) | {idle['mean_cpu_percent_one_core']} |", "",
                  idle["conditions"] + ".", ""]
    elif "reason" in idle:
        lines += [idle["reason"] + ".", ""]
    wakeups = idle.get("wakeup_measurement")
    measured_wakeups = isinstance(wakeups, dict) and wakeups.get("status") == "Measured"
    if measured_wakeups:
        lines += ["Wakeups: **Measured**.", "", "| Metric | Result |", "| --- | --- |",
                  f"| Wakeup Observation Period (Seconds) | {wakeups['observation_seconds']} |",
                  f"| Interrupt Wakeups | {wakeups['interrupt_wakeups']} |",
                  f"| Interrupt Wakeups per Second | {wakeups['interrupt_wakeups_per_second']} |",
                  f"| Platform Idle Wakeups | {wakeups['platform_idle_wakeups']} |",
                  f"| Platform Idle Wakeups per Second | {wakeups['platform_idle_wakeups_per_second']} |", "",
                  "Warm Interactive Launch: **Not Measured**.", ""]
    else:
        lines += ["Wakeups: **Not Measured**. Warm Interactive Launch: **Not Measured**.", ""]
        if isinstance(wakeups, dict) and "reason" in wakeups:
            lines += [wakeups["reason"] + ".", ""]
    lines += [
        "## Measurement Limits", "",
        "- MB uses decimal units: 1 MB = 1,000,000 bytes. Exact byte counts are retained in both reports.",
        "- Logical size sums file bytes and symlink lengths. Allocated size comes from `du`; filesystem allocation can differ. Optional engines are excluded.",
        "- RSS samples cover the main app process. They are not total system memory, physical footprint, or the maximum between samples.",
        "- CPU uses the difference in cumulative process CPU time over monotonic elapsed time. Its source has centisecond precision; this is not an instantaneous CPU sample.",
    ]
    if isinstance(wakeups, dict):
        lines += [
            "- Wakeups use two `proc_pid_rusage` V0 counter readings and their own monotonic interval. The app process must retain the same start identifier; decreasing or unavailable counters are not reported as zero.",
            "- Interrupt and platform-idle wakeups are separate kernel attributions for the main app process. They can overlap and must not be added; they do not measure all thread wakeups, system sleep/wake events, or total energy use.",
        ]
    lines += [
        "- A local Gatekeeper assessment can reflect existing approvals. It does not verify notarization or the first launch of a fresh quarantined download.",
        "- Available signing identities do not prove notarization access. Identity names, certificate data, paths, usernames, hostnames, and serial numbers are omitted.",
        ("- Office appearance, Finder interactions, editors, VoiceOver, multiple displays, and ten interactive warm launches require separate review."
         if measured_wakeups else
         "- Office appearance, Finder interactions, editors, VoiceOver, multiple displays, wakeups, and ten interactive warm launches require separate review."),
        "", "This report stays local. Nothing is uploaded or installed, and no application is launched or quit.", "",
    ]
    return "\n".join(lines)


def write_reports(directory: Path, report: dict) -> None:
    contents = (json.dumps(report, indent=2, ensure_ascii=True) + "\n", markdown_report(report))
    for name, content in zip(REPORT_NAMES, contents):
        descriptor = os.open(directory / name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            stream.write(content)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, default=Path("/Applications/Lemulip.app"), help="Installed app to inspect (default: /Applications/Lemulip.app).")
    parser.add_argument("--output", type=Path, required=True, help="Report directory outside a Git checkout; existing reports are never overwritten.")
    parser.add_argument("--measure-idle", action="store_true", help="Confirm idle conditions, settle for 60 seconds, and observe the running app for 60 seconds.")
    parser.add_argument("--pid", type=int, help="PID of the already running selected app, used only with --measure-idle.")
    arguments = parser.parse_args()
    require(platform.system() == "Darwin", "This review requires a real Mac. No measurements were made.")
    require(arguments.pid is None or arguments.measure_idle, "--pid requires --measure-idle.")
    require(arguments.pid is None or 0 < arguments.pid <= 2147483647, "Specify a valid positive PID.")
    app = arguments.app.expanduser().resolve()
    directory = prepare_output(arguments.output)
    print("Checking Lemulip and Installed Size...", flush=True)
    app_summary, executable = inspect_bundle(app)
    print(f"Selected App: Lemulip {app_summary['version']} (Build {app_summary['build']})", flush=True)
    print("Checking the Mac Baseline...", flush=True)
    baseline = system_summary()
    print("Checking Local Signing Readiness...", flush=True)
    signature = signature_summary(app)
    print("Counting Available Developer ID Application Identities...", flush=True)
    report = {"schema_version": 1,
              "collected_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
              "app": app_summary, "system": baseline, "signature": signature,
              "developer_id_identity_count": signing_identity_count(),
              "idle": {"status": "Not Measured", "wakeups": "Not Measured", "warm_interactive_launch": "Not Measured"}}
    exit_status = 0
    if arguments.measure_idle:
        try:
            report["idle"] = measure_idle(executable, arguments.pid)
        except ReviewError as error:
            report["idle"]["reason"] = "Idle Measurement Could Not Be Completed"
            print(f"Lemulip: {error}", file=sys.stderr)
            exit_status = 1
        except KeyboardInterrupt:
            report["idle"]["reason"] = "Idle Measurement Stopped by Operator"
            print("Lemulip: Idle measurement stopped. The running app was left untouched.", file=sys.stderr)
            exit_status = 130
        except (OSError, ValueError, TypeError):
            report["idle"]["reason"] = "Idle Process Data Unavailable"
            print("Lemulip: Idle process data could not be collected. The running app was left untouched.", file=sys.stderr)
            exit_status = 1
        print("Idle Measurement: " + report["idle"]["status"], flush=True)
        print("Idle Wakeups: " + report["idle"]["wakeups"], flush=True)
    write_reports(directory, report)
    print("Saved: " + " and ".join(REPORT_NAMES))
    print("Readiness was recorded. Hands-on acceptance and warm launch remain unverified."
          + (" Wakeups were not measured." if report["idle"]["wakeups"] != "Measured" else ""))
    return exit_status


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ReviewError as error:
        print(f"Lemulip: {error}", file=sys.stderr)
        raise SystemExit(1)
    except KeyboardInterrupt:
        print("Lemulip: Review stopped. The running app was left untouched.", file=sys.stderr)
        raise SystemExit(130)
    except (OSError, ValueError, TypeError):
        print("Lemulip: The local review could not be completed. No system settings were changed.", file=sys.stderr)
        raise SystemExit(1)
