import AppKit
import CryptoKit
import Darwin
import Foundation

// Startup-only driver for the unchanged native source and control. The linked
// observation library decides which public C entries it saw; successful process
// startup is deliberately not a claim that any activation route was calibrated.
private enum CalibrationIssue: Error, CustomStringConvertible {
    case invalid(String)
    var description: String { switch self { case .invalid(let message): return message } }
}

private func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw CalibrationIssue.invalid(message) }
}

private func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func rectJSON(_ rect: CGRect) -> [String: Double] {
    ["x": Double(rect.minX), "y": Double(rect.minY), "width": Double(rect.width), "height": Double(rect.height)]
}

private func pathExists(_ url: URL) -> Bool {
    var info = stat()
    return Darwin.lstat(url.path, &info) == 0 || errno != ENOENT
}

private func clockSample() -> [String: Any] {
    let absoluteBefore = mach_absolute_time()
    let continuousBefore = mach_continuous_time()
    let uptime = ProcessInfo.processInfo.systemUptime
    let continuousAfter = mach_continuous_time()
    let absoluteAfter = mach_absolute_time()
    return ["machAbsoluteBefore": absoluteBefore, "machContinuousBefore": continuousBefore,
            "systemUptime": uptime, "machContinuousAfter": continuousAfter,
            "machAbsoluteAfter": absoluteAfter,
            "wallTimeUTC": ISO8601DateFormatter().string(from: Date())]
}

private func bootUUID() throws -> String {
    var bytes = [CChar](repeating: 0, count: 128)
    var count = bytes.count
    let result = bytes.withUnsafeMutableBufferPointer { buffer in
        sysctlbyname("kern.bootsessionuuid", buffer.baseAddress, &count, nil, 0)
    }
    try require(result == 0 && count > 1 && count <= bytes.count && bytes.prefix(count).contains(0),
                "The boot-session UUID is unavailable")
    let value = bytes.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    try require(UUID(uuidString: value) != nil, "The boot-session UUID is malformed")
    return UUID(uuidString: value)!.uuidString
}

private func safeDirectory(_ url: URL) throws {
    try require(url.isFileURL && url.path.hasPrefix("/")
                && url.standardizedFileURL.path == url.path
                && url.resolvingSymlinksInPath().path == url.path,
                "Require an absolute directory without symlinks: \(url.path)")
    let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    try require(values.isDirectory == true && values.isSymbolicLink == false,
                "The fixed directory is unavailable: \(url.path)")
}

private func regularData(_ url: URL, maximumBytes: Int, allowEmpty: Bool = false) throws -> Data {
    try require(url.standardizedFileURL.path == url.path
                && url.resolvingSymlinksInPath().path == url.path,
                "Symlinked files are not allowed: \(url.path)")
    let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    try require(descriptor >= 0, "Could not open the fixed file: \(url.path)")
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    defer { try? handle.close() }
    var info = stat()
    try require(Darwin.fstat(descriptor, &info) == 0
                && info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG)
                && info.st_size >= (allowEmpty ? 0 : 1) && info.st_size <= maximumBytes,
                "Require a bounded regular file: \(url.path)")
    var data = Data()
    while data.count <= maximumBytes {
        let next = try handle.read(upToCount: min(65_536, maximumBytes + 1 - data.count)) ?? Data()
        if next.isEmpty { break }
        data.append(next)
    }
    try require(data.count <= maximumBytes && (allowEmpty || !data.isEmpty),
                "The file exceeded its read bound: \(url.path)")
    return data
}

private func jsonRecords(_ data: Data, final: Bool) throws -> [[String: Any]] {
    if final { try require(data.isEmpty || data.last == 10, "A final native journal has an incomplete last line") }
    let pieces = data.split(separator: 10, omittingEmptySubsequences: false)
    // A trailing empty component follows a newline. Otherwise the final
    // component is an in-flight partial record and is not ready to decode.
    let complete = pieces.dropLast()
    try require(complete.count <= 10_000, "A native journal exceeded its record bound")
    return try complete.map { piece in
        try require(!piece.isEmpty, "A native journal contains an empty record")
        guard let object = try JSONSerialization.jsonObject(with: Data(piece)) as? [String: Any] else {
            throw CalibrationIssue.invalid("A native journal record is not an object")
        }
        return object
    }
}

private struct Arguments {
    let staged: URL
    let output: URL

    init() throws {
        let values = Array(CommandLine.arguments.dropFirst())
        try require(values.count == 4, "Usage: NativeActivationEntryCalibration --staged ABS --output ABS")
        var parsed: [String: String] = [:]
        for index in stride(from: 0, to: values.count, by: 2) {
            let key = values[index]
            try require(["--staged", "--output"].contains(key) && parsed[key] == nil,
                        "Require each fixed startup-calibration argument exactly once")
            try require(values[index + 1].hasPrefix("/"), "Calibration paths must be absolute")
            parsed[key] = values[index + 1]
        }
        guard let stagedPath = parsed["--staged"], let outputPath = parsed["--output"] else {
            throw CalibrationIssue.invalid("Both fixed calibration paths are required")
        }
        staged = URL(fileURLWithPath: stagedPath, isDirectory: true).standardizedFileURL
        output = URL(fileURLWithPath: outputPath, isDirectory: true).standardizedFileURL
        try safeDirectory(output)
        try require(output.path != staged.path && !output.path.hasPrefix(staged.path + "/")
                    && !staged.path.hasPrefix(output.path + "/"),
                    "Calibration output and the staged input tree must be separate directories")
        for name in ["calibration-run.json", "control.json", "source.json", "control.json.pending", "source.json.pending"] {
            try require(!pathExists(output.appendingPathComponent(name)),
                        "Refusing to overwrite a previous calibration result: \(name)")
        }
    }
}

// NSWorkspace may invoke its completion on a different queue. The main thread
// only reads the result while pumping its run loop within the fixed deadline.
private final class LaunchOutcome: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private var application: NSRunningApplication?
    private var errorMessage: String?

    func finish(_ application: NSRunningApplication?, _ error: Error?) {
        lock.lock()
        defer { lock.unlock() }
        self.application = application
        errorMessage = error.map { String(describing: $0) }
        finished = true
    }

    func snapshot() -> (Bool, NSRunningApplication?, String?) {
        lock.lock()
        defer { lock.unlock() }
        return (finished, application, errorMessage)
    }
}

@MainActor
private final class OwnedProcess {
    let role: String
    let bundle: URL
    let executable: URL
    let identifier: String
    let probeOutput: URL
    let arguments: [String]
    let outcome = LaunchOutcome()
    var application: NSRunningApplication?
    var pid: pid_t?
    var launchDate: Date?
    var fields: [String: Any]

    init(role: String, staged: URL, output: URL, arguments: [String]) {
        self.role = role
        let capitalized = role == "source" ? "Source" : "Control"
        bundle = staged.appendingPathComponent("Native Drag \(capitalized).app", isDirectory: true)
        executable = bundle.appendingPathComponent("Contents/MacOS/NativeDrag\(capitalized)")
        identifier = "app.lemulip.NativeDrag\(capitalized)"
        probeOutput = output.appendingPathComponent(role + ".json")
        self.arguments = arguments
        fields = ["role": role, "bundleIdentifier": identifier, "bundlePath": bundle.path,
                  "executablePath": executable.path, "arguments": arguments,
                  "environment": ["LEMULIP_ACTIVATION_PROBE_OUTPUT": probeOutput.path],
                  "probeOutputPath": probeOutput.path, "launchRequested": false, "ready": false,
                  "pid": NSNull(), "readyRecords": [], "cleanup": ["terminated": false]]
    }

    func validateIdentity(_ app: NSRunningApplication) throws {
        try require(app.processIdentifier > 0 && app.bundleIdentifier == identifier
                    && app.bundleURL?.standardizedFileURL.path == bundle.path
                    && app.bundleURL?.resolvingSymlinksInPath().path == bundle.path
                    && app.executableURL?.standardizedFileURL.path == executable.path
                    && app.executableURL?.resolvingSymlinksInPath().path == executable.path,
                    "The launched \(role) application has an unexpected identity")
        if let pid { try require(app.processIdentifier == pid, "The owned \(role) PID changed") }
        if let launchDate { try require(app.launchDate == launchDate, "The owned \(role) process instance changed") }
    }

    func adoptCompletedLaunch() throws {
        guard application == nil else { return }
        let (_, app, _) = outcome.snapshot()
        guard let app else { return }
        try validateIdentity(app)
        application = app
        pid = app.processIdentifier
        launchDate = app.launchDate
        fields["pid"] = Int(app.processIdentifier)
        fields["launchDate"] = app.launchDate.map { ISO8601DateFormatter().string(from: $0) as Any } ?? NSNull()
        fields["launchReturnedClock"] = clockSample()
    }
}

@MainActor
private final class StartupCalibration {
    private let arguments: Arguments
    private let started = ProcessInfo.processInfo.systemUptime
    private let evidenceName = "NativeDragControlEvidence-Capture-ax-only-Lifecycle-appkit-MouseDriver-quartz-first"
    private var processes: [OwnedProcess] = []
    private var originalHashes: [String: String] = [:]
    private var errors: [String] = []
    private var report: [String: Any] = [
        "schema": 1, "kind": "native-activation-entry-startup-calibration", "caseName": "quartz-first",
        "status": "error", "processCalibrationComplete": false, "hookCalibrationDetermined": false,
        "inputGenerated": false, "mouseInputGenerated": false, "keyboardInputGenerated": false,
        "accessibilityCallsMade": false, "newExplicitActivationCalls": 0,
        "readinessTimeoutSeconds": 8, "normalTerminationTimeoutSeconds": 8,
        "pendingLaunchCleanupWaitSeconds": 8, "signalFallbackWaitSeconds": 2, "launchRetryCount": 0,
        "scope": "Natural startup of the original owned source/control; no gesture or cancellation test."
    ]

    init(arguments: Arguments) {
        self.arguments = arguments
        report["commandArguments"] = CommandLine.arguments
        report["stagedPath"] = arguments.staged.path
        report["outputPath"] = arguments.output.path
        report["helperPID"] = Int(ProcessInfo.processInfo.processIdentifier)
        report["helperExecutablePath"] = CommandLine.arguments.first ?? ""
        report["osVersion"] = ProcessInfo.processInfo.operatingSystemVersionString
    }

    private var evidence: URL {
        arguments.staged.appendingPathComponent(evidenceName + "/orchard", isDirectory: true)
    }

    private func pump(until deadline: TimeInterval) {
        let remaining = deadline - ProcessInfo.processInfo.systemUptime
        if remaining > 0 { _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: min(0.02, remaining))) }
    }

    private func remember(_ url: URL, maximumBytes: Int) throws -> Data {
        let data = try regularData(url, maximumBytes: maximumBytes)
        originalHashes[url.path] = digest(data)
        return data
    }

    private func prepare() throws {
        try safeDirectory(arguments.staged)
        try require(arguments.staged.lastPathComponent == "lemulip-native-ui", "Require the original staging directory name")
        try require(!ProcessInfo.processInfo.environment.keys.contains(where: { $0.hasPrefix("DYLD_") }),
                    "DYLD environment injection is outside this startup calibration")
        report["bootUUID"] = try bootUUID()
        var timebase = mach_timebase_info_data_t()
        try require(mach_timebase_info(&timebase) == KERN_SUCCESS && timebase.numer > 0 && timebase.denom > 0,
                    "The native mach timebase is unavailable")
        report["machTimebaseNumer"] = timebase.numer
        report["machTimebaseDenom"] = timebase.denom
        #if arch(arm64)
        let architecture = "arm64"
        #elseif arch(x86_64)
        let architecture = "x86_64"
        #else
        let architecture = "unsupported"
        #endif
        report["architecture"] = architecture
        try require(architecture != "unsupported", "Require an ARM or Intel native calibration")
        let helper = NSApplication.shared
        let initialPolicy = helper.activationPolicy()
        let attempted = initialPolicy != .prohibited
        let accepted: Bool? = attempted ? helper.setActivationPolicy(.prohibited) : nil
        let finalPolicy = helper.activationPolicy()
        report["helperActivationPolicySetup"] = ["initialPolicy": initialPolicy.rawValue,
            "setAttempted": attempted, "setAccepted": accepted.map { $0 as Any } ?? NSNull(),
            "finalPolicy": finalPolicy.rawValue]
        try require((!attempted || accepted == true) && finalPolicy == .prohibited,
                    "Could not establish the helper's own prohibited activation policy")

        let provenanceData = try remember(arguments.staged.appendingPathComponent("provenance.json"), maximumBytes: 262_144)
        guard let provenance = try JSONSerialization.jsonObject(with: provenanceData) as? [String: Any] else {
            throw CalibrationIssue.invalid("The fixed staged provenance is not an object")
        }
        try require(provenance["architecture"] as? String == architecture
                    && provenance["sourceCommit"] as? String == "d821d7343675e2850705d141ef9b3b93a6aee945"
                    && provenance["sourceTree"] as? String == "425baa28f00ec24551dd70c0cc874a75fa3be0c1",
                    "The native architecture or pinned C12 provenance does not match")
        report["provenance"] = provenance

        let fixtureFolder = arguments.staged.appendingPathComponent("Fixtures/FinderDrop/orchard", isDirectory: true)
        try safeDirectory(fixtureFolder)
        let fixtures = try FileManager.default.contentsOfDirectory(at: fixtureFolder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent != ".DS_Store" }
        try require(fixtures.count == 4, "Require exactly four original Orchard fixtures")
        for role in ["Existing", "Single", "Multi-A", "Multi-B"] {
            let pattern = "^" + role + "-[a-f0-9]{32}\\.txt$"
            let matches = fixtures.filter { $0.lastPathComponent.range(of: pattern, options: .regularExpression) != nil }
            try require(matches.count == 1, "A required Orchard fixture is missing or ambiguous")
            _ = try remember(matches[0], maximumBytes: 65_535)
        }
        report["fixturePaths"] = fixtures.map(\.path).sorted()

        let display = CGMainDisplayID()
        guard let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display
        }) else { throw CalibrationIssue.invalid("The primary AppKit screen is unavailable") }
        let cg = CGDisplayBounds(display)
        let appKit = screen.frame
        try require(abs(appKit.width - cg.width) < 0.5 && abs(appKit.height - cg.height) < 0.5
                    && cg.width >= 900 && cg.height >= 700,
                    "Require a primary display with matching logical coordinate dimensions")
        let frame = CGRect(x: cg.minX + 48, y: cg.minY + 72, width: 480, height: 320)
        let point = CGPoint(x: frame.midX, y: frame.midY)
        try require(cg.contains(frame), "The fixed source window must fit on the primary display")
        let geometry: [String: Any] = ["coordinateSpace": "Quartz-global-top-left", "frame": rectJSON(frame),
            "point": ["x": Double(point.x), "y": Double(point.y)],
            "quartzDisplayBounds": rectJSON(cg), "appKitDisplayFrame": rectJSON(appKit)]
        report["sourceGeometry"] = geometry
        let sourceArguments = ["--case", "quartz-first", "--frame-x", String(Double(frame.minX)),
            "--frame-y", String(Double(frame.minY)), "--frame-width", String(Double(frame.width)),
            "--frame-height", String(Double(frame.height)), "--point-x", String(Double(point.x)),
            "--point-y", String(Double(point.y))]
        processes = [OwnedProcess(role: "control", staged: arguments.staged, output: arguments.output,
                                  arguments: ["-controlTheme", "orchard", "-controlEvidenceKind", "activation-quartz-first"]),
                     OwnedProcess(role: "source", staged: arguments.staged, output: arguments.output,
                                  arguments: sourceArguments)]
        for owned in processes {
            try safeDirectory(owned.bundle)
            let infoData = try remember(owned.bundle.appendingPathComponent("Contents/Info.plist"), maximumBytes: 262_144)
            guard let info = try PropertyListSerialization.propertyList(from: infoData, options: [], format: nil) as? [String: Any] else {
                throw CalibrationIssue.invalid("The fixed \(owned.role) Info.plist is invalid")
            }
            let executableName = owned.executable.lastPathComponent
            try require(info["CFBundleIdentifier"] as? String == owned.identifier
                        && info["CFBundleExecutable"] as? String == executableName
                        && info["CFBundlePackageType"] as? String == "APPL"
                        && info["NSPrincipalClass"] as? String == executableName + "Application",
                        "The fixed \(owned.role) bundle identity does not match")
            let executableData = try remember(owned.executable, maximumBytes: 134_217_728)
            let executableSHA = digest(executableData)
            try require(provenance[owned.role + "GUI_SHA256"] as? String == executableSHA,
                        "The \(owned.role) executable differs from its staged provenance")
            owned.fields["executableSHA256"] = executableSHA
            let library = owned.bundle.appendingPathComponent("Contents/Frameworks/libNativeActivationEntryProbe.dylib")
            owned.fields["probeLibraryPath"] = library.path
            owned.fields["probeLibrarySHA256"] = digest(try remember(library, maximumBytes: 16_777_216))
            try require(NSRunningApplication.runningApplications(withBundleIdentifier: owned.identifier).isEmpty,
                        "A \(owned.role) instance was already running; no instance will be reused")
        }

        let parent = evidence.deletingLastPathComponent()
        for directory in [parent, evidence] {
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            }
            try safeDirectory(directory)
        }
        try require(try FileManager.default.contentsOfDirectory(at: evidence, includingPropertiesForKeys: nil).isEmpty,
                    "The fixed native evidence directory must be empty before this single launch")
        report["nativeEvidencePath"] = evidence.path
        report["inputFileSHA256Before"] = originalHashes
        report["preparationComplete"] = true
    }

    private func launchAndObserve(_ owned: OwnedProcess) throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = owned.arguments
        configuration.environment = ["LEMULIP_ACTIVATION_PROBE_OUTPUT": owned.probeOutput.path]
        configuration.addsToRecentItems = false
        let deadline = ProcessInfo.processInfo.systemUptime + 8
        owned.fields["launchRequestedClock"] = clockSample()
        owned.fields["launchRequested"] = true
        let outcome = owned.outcome
        NSWorkspace.shared.openApplication(at: owned.bundle, configuration: configuration) { app, error in
            outcome.finish(app, error)
        }
        while !outcome.snapshot().0 && ProcessInfo.processInfo.systemUptime < deadline { pump(until: deadline) }
        try owned.adoptCompletedLaunch()
        let (finished, _, launchError) = outcome.snapshot()
        if let launchError { throw CalibrationIssue.invalid("The \(owned.role) launch failed: \(launchError)") }
        try require(finished, "The \(owned.role) launch completion exceeded its readiness deadline")
        guard let app = owned.application else { throw CalibrationIssue.invalid("The \(owned.role) launch returned no owned process") }
        let journal = evidence.appendingPathComponent(owned.role == "source" ? "source.jsonl" : "receiver.jsonl")
        let readyEvent = owned.role == "source" ? "source-ready" : "application-ready"
        while ProcessInfo.processInfo.systemUptime < deadline {
            try owned.validateIdentity(app)
            try require(!app.isTerminated, "The \(owned.role) process exited before startup readiness")
            if FileManager.default.fileExists(atPath: journal.path) {
                let data = try regularData(journal, maximumBytes: 8_388_608, allowEmpty: true)
                let records = try jsonRecords(data, final: false)
                let ready = records.filter { $0["event"] as? String == readyEvent }
                try require(ready.count <= 1, "The \(owned.role) emitted duplicate startup-ready records")
                if let record = ready.first, app.isActive {
                    try require((record["pid"] as? NSNumber)?.int32Value == app.processIdentifier
                                && (record["systemUptime"] as? NSNumber)?.doubleValue.isFinite == true,
                                "The \(owned.role) ready record has no valid owned PID and native time")
                    owned.fields["readyRecords"] = [record]
                    owned.fields["readyJournalPath"] = journal.path
                    owned.fields["readyObservedClock"] = clockSample()
                    owned.fields["activeWitness"] = ["isActive": true, "isTerminated": false, "clock": clockSample()]
                    owned.fields["ready"] = true
                    return
                }
            }
            pump(until: deadline)
        }
        throw CalibrationIssue.invalid("The \(owned.role) did not publish native readiness and become active within eight seconds")
    }

    private func stop(_ owned: OwnedProcess) {
        var receipt: [String: Any] = ["startedClock": clockSample(), "normalTerminationRequested": false,
            "normalTerminationSeconds": 8, "fallbackUsed": false, "signals": [], "terminated": false,
            "completedNormally": false, "exitStatus": NSNull(), "exitStatusAvailable": false,
            "exitStatusReason": "NSWorkspace launched the process; NSRunningApplication does not expose its wait status."]
        // A timed-out launch request has not been cancelled by NSWorkspace.
        // Allow its one existing completion a bounded cleanup-only window so
        // a late returned owned PID can still be terminated normally.
        let pending = owned.application == nil && !owned.outcome.snapshot().0
        receipt["pendingLaunchCleanupWaitUsed"] = pending
        if pending {
            let deadline = ProcessInfo.processInfo.systemUptime + 8
            while !owned.outcome.snapshot().0 && ProcessInfo.processInfo.systemUptime < deadline { pump(until: deadline) }
            receipt["pendingLaunchCleanupWaitCompletedClock"] = clockSample()
        }
        do { try owned.adoptCompletedLaunch() }
        catch { errors.append(String(describing: error)) }
        receipt["outstandingLaunchCompletion"] = !owned.outcome.snapshot().0
        guard let app = owned.application, let pid = owned.pid else {
            receipt["reason"] = "No identity-verified launched process was returned"
            receipt["launchCompletionReceived"] = owned.outcome.snapshot().0
            receipt["completedClock"] = clockSample()
            if !owned.outcome.snapshot().0 {
                errors.append("The \(owned.role) launch completion remains outstanding after bounded cleanup")
            }
            owned.fields["cleanup"] = receipt
            return
        }
        do {
            try owned.validateIdentity(app)
            receipt["identityVerified"] = true
            receipt["identityObservedClock"] = clockSample()
            try require(!app.isTerminated, "The \(owned.role) exited before the helper requested normal termination")
            receipt["terminationRequestedClock"] = clockSample()
            receipt["normalTerminationRequested"] = true
            receipt["terminateReturn"] = app.terminate()
            let normalDeadline = ProcessInfo.processInfo.systemUptime + 8
            while !app.isTerminated && ProcessInfo.processInfo.systemUptime < normalDeadline { pump(until: normalDeadline) }
            var signals: [[String: Any]] = []
            if !app.isTerminated {
                receipt["fallbackUsed"] = true
                for signal in [Int32(SIGTERM), Int32(SIGKILL)] {
                    if app.isTerminated { break }
                    // Recheck the exact instance immediately before a numeric-PID
                    // fallback. No bundle-wide or name-based termination exists.
                    guard let fresh = NSRunningApplication(processIdentifier: pid), let launched = owned.launchDate else {
                        throw CalibrationIssue.invalid("Cannot safely bind the \(owned.role) PID for signal fallback")
                    }
                    try owned.validateIdentity(fresh)
                    try require(fresh.launchDate == launched && !fresh.isTerminated,
                                "The \(owned.role) process instance changed before signal fallback")
                    let sentAt = clockSample()
                    let result = Darwin.kill(pid, signal)
                    let signalErrno = result == 0 ? 0 : errno
                    signals.append(["signal": signal, "pid": Int(pid), "requestedClock": sentAt,
                                    "returnValue": result, "errno": signalErrno])
                    receipt["signals"] = signals
                    let deadline = ProcessInfo.processInfo.systemUptime + 2
                    while !app.isTerminated && ProcessInfo.processInfo.systemUptime < deadline { pump(until: deadline) }
                }
            }
            receipt["signals"] = signals
            receipt["terminated"] = app.isTerminated
            if app.isTerminated { receipt["terminatedObservedClock"] = clockSample() }
            let normal = app.isTerminated && (receipt["fallbackUsed"] as? Bool) == false
                && (receipt["terminateReturn"] as? Bool) == true && (receipt["identityVerified"] as? Bool) == true
            receipt["completedNormally"] = normal
            if !normal { errors.append("The \(owned.role) did not complete normal bounded termination") }
        } catch {
            receipt["error"] = String(describing: error)
            receipt["terminated"] = app.isTerminated
            if app.isTerminated { receipt["terminatedObservedClock"] = clockSample() }
            errors.append(String(describing: error))
        }
        receipt["completedClock"] = clockSample()
        owned.fields["cleanup"] = receipt
    }

    private func collectFinalEvidence() {
        var logs: [String: Any] = [:]
        var decoded: [String: [[String: Any]]] = [:]
        var unexpectedInputObserved = false
        for name in ["receiver", "activation", "source"] {
            let url = evidence.appendingPathComponent(name + ".jsonl")
            guard FileManager.default.fileExists(atPath: url.path) else {
                logs[name] = ["path": url.path, "status": "absent"]
                continue
            }
            do {
                let data = try regularData(url, maximumBytes: 8_388_608, allowEmpty: true)
                let records = try jsonRecords(data, final: true)
                decoded[name] = records
                logs[name] = ["path": url.path, "status": "complete", "sha256": digest(data),
                              "byteCount": data.count, "records": records]
                let inputEvents: Set<String> = ["source-mouse-down", "source-mouse-up", "source-session-requested",
                    "source-session-created", "source-will-begin", "source-moved", "source-ended", "escape-send-event",
                    "draggingEntered", "draggingUpdated", "draggingExited", "draggingEnded", "prepareForDragOperation",
                    "performDragOperation", "concludeDragOperation", "target-mouse-enter", "target-mouse-return",
                    "selection-changed", "open-rejected"]
                if records.contains(where: { inputEvents.contains($0["event"] as? String ?? "") || $0["sequenceNumber"] != nil }) {
                    unexpectedInputObserved = true
                    errors.append("Unexpected native input or dragging activity occurred in \(name).jsonl")
                }
            } catch {
                logs[name] = ["path": url.path, "status": "error", "error": String(describing: error)]
                errors.append(String(describing: error))
            }
        }
        report["nativeLogs"] = logs
        report["unexpectedNativeInputObserved"] = unexpectedInputObserved
        if processes.count == 2 && processes.allSatisfy({ $0.fields["ready"] as? Bool == true }) {
            do {
                for owned in processes {
                    guard let pid = owned.pid else { throw CalibrationIssue.invalid("A ready process lost its PID binding") }
                    let expectations: [(String, String)] = owned.role == "source"
                        ? [("source", "source-ready"), ("source", "application-terminating")]
                        : [("receiver", "application-ready"), ("receiver", "application-terminated"),
                           ("activation", "activation-ready"), ("activation", "activation-terminating")]
                    for (journal, event) in expectations {
                        let matches = (decoded[journal] ?? []).filter { $0["event"] as? String == event }
                        try require(matches.count == 1 && (matches[0]["pid"] as? NSNumber)?.int32Value == pid,
                                    "The final \(journal) journal lacks one owned \(event) record")
                        if owned.role == "source" && event == "application-terminating" {
                            try require((matches[0]["sessionCount"] as? NSNumber)?.intValue == 0
                                        && (matches[0]["activeSession"] as? Bool) == false,
                                        "The startup-only source unexpectedly entered a dragging session")
                        }
                    }
                }
                report["nativeLifecycleRecordsComplete"] = true
            } catch {
                report["nativeLifecycleRecordsComplete"] = false
                errors.append(String(describing: error))
            }
        } else { report["nativeLifecycleRecordsComplete"] = false }
        for owned in processes {
            do {
                if FileManager.default.fileExists(atPath: owned.probeOutput.path) {
                    let data = try regularData(owned.probeOutput, maximumBytes: 16_777_216)
                    owned.fields["probeReceipt"] = ["status": "retained", "path": owned.probeOutput.path,
                                                     "byteCount": data.count, "sha256": digest(data)]
                } else {
                    owned.fields["probeReceipt"] = ["status": "absent", "path": owned.probeOutput.path]
                }
            } catch {
                owned.fields["probeReceipt"] = ["status": "error", "path": owned.probeOutput.path,
                                                 "error": String(describing: error)]
            }
        }
        do {
            for (path, expected) in originalHashes {
                let actual = digest(try regularData(URL(fileURLWithPath: path), maximumBytes: 134_217_728))
                try require(actual == expected, "A staged input changed during startup calibration: \(path)")
            }
            if let before = report["fixturePaths"] as? [String] {
                let folder = arguments.staged.appendingPathComponent("Fixtures/FinderDrop/orchard", isDirectory: true)
                let after = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                    .filter { $0.lastPathComponent != ".DS_Store" }.map(\.path).sorted()
                try require(after == before, "The original Orchard fixture set changed")
            }
            report["stagedInputsUnchanged"] = report["preparationComplete"] as? Bool == true
        } catch {
            report["stagedInputsUnchanged"] = false
            errors.append(String(describing: error))
        }
    }

    func execute() -> Bool {
        do {
            try prepare()
            report["runClockBeforeLaunch"] = clockSample()
            for owned in processes { try launchAndObserve(owned) }
            for owned in processes {
                guard let app = owned.application else { throw CalibrationIssue.invalid("An owned startup process is missing") }
                try owned.validateIdentity(app)
                try require(!app.isTerminated, "Both owned processes must remain alive until both startups are observed")
            }
            report["bothStartupsObservedClock"] = clockSample()
        } catch { errors.append(String(describing: error)) }
        // Source first, then control. A source-launch failure still cleans up the
        // already-observed control, without asking either process to activate.
        for owned in processes.reversed() where owned.fields["launchRequested"] as? Bool == true { stop(owned) }
        report["runClockAfterTermination"] = clockSample()
        collectFinalEvidence()
        let lifecycleComplete = processes.count == 2 && processes.allSatisfy {
            $0.fields["ready"] as? Bool == true
                && (($0.fields["cleanup"] as? [String: Any])?["completedNormally"] as? Bool) == true
        }
        report["processCalibrationComplete"] = lifecycleComplete && errors.isEmpty
        report["status"] = lifecycleComplete && errors.isEmpty ? "complete" : "error"
        report["errors"] = errors
        report["elapsedSeconds"] = ProcessInfo.processInfo.systemUptime - started
        report["processes"] = Dictionary(uniqueKeysWithValues: processes.map { ($0.role, $0.fields) })
        do {
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            let output = arguments.output.appendingPathComponent("calibration-run.json")
            let descriptor = Darwin.open(output.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
            try require(descriptor >= 0, "Could not exclusively create calibration-run.json")
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            defer { try? handle.close() }
            try handle.write(contentsOf: data)
            try handle.write(contentsOf: Data([10]))
            try handle.synchronize()
            let summary: [String: Any] = ["status": report["status"] ?? "error", "reportPath": output.path,
                                          "processCalibrationComplete": report["processCalibrationComplete"] ?? false]
            FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: summary, options: [.sortedKeys]))
            FileHandle.standardOutput.write(Data([10]))
        } catch {
            FileHandle.standardError.write(Data(("Startup calibration report failed: \(error)\n").utf8))
            return false
        }
        return lifecycleComplete && errors.isEmpty
    }
}

@main
private enum NativeActivationEntryCalibration {
    @MainActor
    static func main() {
        do {
            let arguments = try Arguments()
            let succeeded = StartupCalibration(arguments: arguments).execute()
            Darwin.exit(succeeded ? 0 : 1)
        } catch {
            FileHandle.standardError.write(Data(("Startup calibration configuration failed: \(error)\n").utf8))
            Darwin.exit(2)
        }
    }
}
