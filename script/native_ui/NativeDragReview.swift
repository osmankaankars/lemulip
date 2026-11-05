import AppKit
import ApplicationServices
import CryptoKit
import Darwin
import Foundation

// A separate, explicitly interactive evidence probe. ReadOnlyAXSnapshot stays
// read-only. This executable never requests or changes any macOS permission.
// Usage: NativeDragReview <the prepare_native_ui.py review directory> [--control | --keyboard-control]
enum DragReviewIssue: Error, CustomStringConvertible {
    case blocked(String)
    case failed(String)
    var description: String {
        switch self { case .blocked(let text), .failed(let text): return text }
    }
}

private struct AXReadFailure: Error, CustomStringConvertible {
    let attribute: String
    let status: Int32
    var description: String { "AX read failed for \(attribute): \(status)" }
}

enum DragReviewTheme: String, CaseIterable {
    case orchard, pistachio, lemonade
}

enum DragReviewTarget {
    case production, control, keyboardControl

    var identifier: String {
        self == .production ? "app.lemulip.NativeUIReview" : "app.lemulip.NativeDragControl"
    }
    var bundleName: String {
        self == .production ? "Lemulip Native UI Review.app" : "Native Drag Control.app"
    }
    var executable: String { self == .production ? "Lemulip" : "NativeDragControl" }
    var windowTitle: String { self == .production ? "Lemulip" : "Native Drag Control" }
    var evidenceName: String {
        switch self {
        case .production: return "NativeDragEvidence"
        case .control: return "NativeDragControlEvidence"
        case .keyboardControl: return "NativeDragKeyboardEvidence"
        }
    }
    var themes: [DragReviewTheme] { self == .keyboardControl ? [.orchard] : DragReviewTheme.allCases }
    var inputDriver: String { self == .keyboardControl ? "XCTest" : "CGEvent" }
}

enum SameHostEscapeInput: String {
    case automatic, external
}

struct SameHostDragOptions {
    var escapeInput: SameHostEscapeInput = .automatic
    var leadInSeconds: Double = 0
    var dwellSeconds: Double = 0.15
    var externalDownTimeoutSeconds: Double = 12
    var externalUpTimeoutSeconds: Double = 4
    var onPrompt: (@MainActor (String) -> Void)? = nil
}

// Owns only the prebuilt, fixed one-test keyboard runner. This helper never
// posts input, activates an app or builds a new target during the held drag.
@MainActor
private final class KeyboardControlDriver {
    private let directory: URL
    private let control: URL
    private let project: URL
    private let derivedData: URL
    private let runnerBundle: URL
    private let runnerExecutable: URL
    private let runnerIdentifier = "app.lemulip.NativeDragKeyboardTests.xctrunner"
    private let process = Process()
    private var logHandle: FileHandle?
    private var started = false
    private var runner: NSRunningApplication?
    private var nonce = ""
    private var requested = false
    private var requestCreated: Double?
    private var requestExpires: Double?
    private var markers: [String] = []
    private(set) var ended = false
    private(set) var completedNormally = false
    private(set) var evidence: [String: Any] = ["inputDriver": "XCTest", "status": "not-started"]

    init(directory: URL) throws {
        self.directory = directory
        control = directory.appendingPathComponent("KeyboardControl", isDirectory: true)
        project = directory.appendingPathComponent("KeyboardRunner/QualityReview.xcodeproj", isDirectory: true)
        derivedData = directory.appendingPathComponent("KeyboardDerivedData", isDirectory: true)
        runnerBundle = derivedData.appendingPathComponent("Build/Products/Debug/QualityReview-Runner.app", isDirectory: true)
        runnerExecutable = runnerBundle.appendingPathComponent("Contents/MacOS/QualityReview-Runner")
        try require(directory.lastPathComponent == "lemulip-native-ui", "Require the fixed keyboard staging root")
        for url in [directory, control, project, derivedData, runnerBundle] { try checkPath(url, directory: true) }
        let configurationData = try readBounded(control.appendingPathComponent("configuration.json"), maximum: 4_096)
        guard let configuration = try JSONSerialization.jsonObject(with: configurationData) as? [String: Any],
              let schema = configuration["schema"] as? NSNumber,
              CFGetTypeID(schema) != CFBooleanGetTypeID(), schema.doubleValue == 1,
              let value = configuration["nonce"] as? String,
              value.count == 32, value.allSatisfy({ "0123456789abcdef".contains($0) }) else {
            throw DragReviewIssue.failed("The keyboard configuration has an invalid schema or nonce")
        }
        nonce = value
        let infoData = try readBounded(runnerBundle.appendingPathComponent("Contents/Info.plist"), maximum: 262_144)
        let info = try PropertyListSerialization.propertyList(from: infoData, options: [], format: nil) as? [String: Any]
        try require(info?["CFBundleIdentifier"] as? String == runnerIdentifier
                    && info?["CFBundleExecutable"] as? String == "QualityReview-Runner",
                    "The keyboard runner does not match its fixed prebuilt identity")
        let executableData = try readBounded(runnerExecutable, maximum: 268_435_456)
        try require(!executableData.isEmpty, "The prebuilt keyboard runner executable is empty")
        try require(NSRunningApplication.runningApplications(withBundleIdentifier: runnerIdentifier).isEmpty,
                    "The fixed keyboard runner must be stopped before this comparison")
        for name in ["xcodebuild.log", "request.json", "request.json.pending", "finished.json", "finished.json.pending"] {
            var attributes = stat()
            try require(lstat(control.appendingPathComponent(name).path, &attributes) != 0 && errno == ENOENT,
                        "Refusing an existing keyboard protocol output")
        }
        evidence = ["inputDriver": "XCTest", "status": "validated", "nonce": nonce,
                    "runnerBundleIdentifier": runnerIdentifier, "runnerApplicationPath": runnerBundle.path,
                    "runnerExecutablePath": runnerExecutable.path, "projectPath": project.path,
                    "keyboardRunnerInfoSHA256": SHA256.hash(data: infoData).map { String(format: "%02x", $0) }.joined(),
                    "keyboardRunnerExecutableSHA256": SHA256.hash(data: executableData).map { String(format: "%02x", $0) }.joined(),
                    "readyTimeoutSeconds": 60, "escapeTimeoutSeconds": 20, "stopTimeoutSeconds": 8]
    }

    private func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw DragReviewIssue.failed(message) }
    }

    private func checkPath(_ url: URL, directory: Bool) throws {
        try require(url.standardizedFileURL.path == url.resolvingSymlinksInPath().path,
                    "Symlinked keyboard driver paths are not allowed")
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
        try require(values.isSymbolicLink == false && (directory ? values.isDirectory == true : values.isRegularFile == true),
                    "A fixed keyboard driver path has the wrong file type")
    }

    private func readBounded(_ url: URL, maximum: Int) throws -> Data {
        try checkPath(url, directory: false)
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        try require(descriptor >= 0, "Could not open the fixed keyboard driver file")
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximum + 1) ?? Data()
        try require(data.count <= maximum, "A keyboard driver file exceeded its size bound")
        return data
    }

    private func publish(_ name: String, object: [String: Any]) throws {
        try require(["request.json", "finished.json"].contains(name), "Only fixed keyboard protocol outputs may be written")
        try checkPath(control, directory: true)
        let temporary = control.appendingPathComponent(name + ".pending")
        let destination = control.appendingPathComponent(name)
        let descriptor = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                                     S_IRUSR | S_IWUSR)
        try require(descriptor >= 0, "Could not exclusively create a keyboard protocol file")
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close(); Darwin.unlink(temporary.path) }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try require(data.count <= 4_096, "The keyboard request exceeds its size bound")
        try handle.write(contentsOf: data)
        try handle.synchronize()
        // Linking a completed file publishes it atomically without replacement.
        try require(Darwin.link(temporary.path, destination.path) == 0,
                    "Could not publish the exclusive keyboard protocol file")
    }

    private func currentRunner() throws -> NSRunningApplication? {
        let matches = NSRunningApplication.runningApplications(withBundleIdentifier: runnerIdentifier)
        try require(matches.count <= 1, "The fixed keyboard runner is ambiguous")
        guard let current = matches.first else { return nil }
        try require(started && !current.isTerminated
                    && current.bundleURL?.resolvingSymlinksInPath().path == runnerBundle.path
                    && current.executableURL?.resolvingSymlinksInPath().path == runnerExecutable.path,
                    "The keyboard runner process has an unexpected identity")
        if let runner {
            try require(current.processIdentifier == runner.processIdentifier, "The owned keyboard runner PID changed")
        } else {
            runner = current
            evidence["runnerPID"] = Int(current.processIdentifier)
        }
        return current
    }

    private func refreshMarkers() throws {
        let data = try readBounded(control.appendingPathComponent("xcodebuild.log"), maximum: 8 * 1_024 * 1_024)
        let end = data.lastIndex(of: 0x0a).map { data.index(after: $0) } ?? data.startIndex
        guard let log = String(data: data[..<end], encoding: .utf8) else {
            throw DragReviewIssue.failed("The keyboard driver log is not UTF-8")
        }
        var observed: [String] = []
        for line in log.split(separator: "\n", omittingEmptySubsequences: false).dropLast() {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\r" }).map(String.init)
            guard let prefix = fields.first, prefix.hasPrefix("LEMULIP_KEYBOARD_") else { continue }
            let phase = String(prefix.dropFirst("LEMULIP_KEYBOARD_".count))
            try require(["READY", "BEGIN", "END", "FAILED"].contains(phase) && fields.count >= 2 && fields[1] == nonce,
                        "The keyboard driver marker has an unexpected action or nonce")
            if phase == "READY" { try require(fields.count == 2, "The keyboard READY marker is malformed") }
            else {
                guard fields.count == 3, let time = Double(fields[2]), time.isFinite else {
                    throw DragReviewIssue.failed("The keyboard marker has an invalid monotonic timestamp")
                }
                if phase == "BEGIN" || phase == "END" {
                    try require(requested && time >= (requestCreated ?? .infinity) && time <= (requestExpires ?? -Double.infinity),
                                "The keyboard input marker is outside its one requested action")
                }
            }
            try require(!observed.contains(phase), "The one-shot keyboard driver repeated a marker")
            if phase == "BEGIN" { try require(observed == ["READY"], "The keyboard BEGIN marker is out of order") }
            if phase == "END" { try require(observed == ["READY", "BEGIN"], "The keyboard END marker is out of order") }
            observed.append(phase)
            if !markers.contains(phase) {
                var receipts = evidence["markerReceipts"] as? [[String: Any]] ?? []
                receipts.append(["marker": phase, "line": String(line), "observedSystemUptime": ProcessInfo.processInfo.systemUptime])
                evidence["markerReceipts"] = receipts
            }
        }
        markers = observed
        try require(!markers.contains("FAILED"), "The public XCTest keyboard driver reported failure")
    }

    private func waitFor(_ marker: String, seconds: Double, expiresAt: Double) async throws {
        let deadline = min(expiresAt, ProcessInfo.processInfo.systemUptime + seconds)
        while ProcessInfo.processInfo.systemUptime < deadline {
            try refreshMarkers()
            try require(process.isRunning, "The keyboard driver exited before completing the bounded handshake")
            let activeRunner = try currentRunner()
            if markers.contains(marker) {
                try require(activeRunner != nil, "The keyboard marker has no matching live runner")
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw DragReviewIssue.failed("The keyboard driver did not report \(marker) within its bounded wait")
    }

    func start(expiresAt: Double) async throws {
        try require(!started && ProcessInfo.processInfo.systemUptime < expiresAt,
                    "The keyboard driver must start within this run's bounded lifetime")
        try require(NSRunningApplication.runningApplications(withBundleIdentifier: runnerIdentifier).isEmpty,
                    "The fixed keyboard runner appeared before this probe started it")
        let log = control.appendingPathComponent("xcodebuild.log")
        let descriptor = Darwin.open(log.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        try require(descriptor >= 0, "Could not exclusively create the keyboard driver log")
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        logHandle = handle
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.currentDirectoryURL = directory
        process.arguments = ["xcodebuild", "test-without-building", "-project", project.path, "-scheme", "QualityReview",
                             "-derivedDataPath", derivedData.path, "-destination", "platform=macOS",
                             "-parallel-testing-enabled", "NO", "-test-timeouts-enabled", "YES",
                             "-default-test-execution-time-allowance", "110", "-maximum-test-execution-time-allowance", "110"]
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        started = true
        evidence["processPID"] = Int(process.processIdentifier)
        evidence["startedSystemUptime"] = ProcessInfo.processInfo.systemUptime
        evidence["status"] = "waiting-for-ready"
        try await waitFor("READY", seconds: 60, expiresAt: expiresAt)
        evidence["status"] = "ready"
    }

    func requestEscape(target: NSRunningApplication, application: URL, expiresAt: Double) async throws {
        try require(!requested && process.isRunning && (try currentRunner()) != nil,
                    "Require this run's live, unused keyboard driver")
        let created = ProcessInfo.processInfo.systemUptime
        let expires = min(created + 20, expiresAt)
        try require(expires > created, "No bounded lifetime remains for the keyboard request")
        let request: [String: Any] = ["schema": 1, "nonce": nonce, "action": "escape", "flags": 0, "keyCode": 53,
                                      "theme": "orchard", "targetBundleIdentifier": "app.lemulip.NativeDragControl",
                                      "targetApplicationPath": application.path, "targetPID": Int(target.processIdentifier),
                                      "createdSystemUptime": created, "expiresSystemUptime": expires]
        requestCreated = created
        requestExpires = expires
        requested = true
        evidence["request"] = request
        evidence["status"] = "waiting-for-escape-end"
        defer {
            evidence["escapeRequestFinishedSystemUptime"] = ProcessInfo.processInfo.systemUptime
            evidence["escapeRequestElapsedSeconds"] = ProcessInfo.processInfo.systemUptime - created
        }
        do {
            try publish("request.json", object: request)
            try await waitFor("END", seconds: 20, expiresAt: expires)
            ended = true
            evidence["status"] = "escape-ended"
        } catch {
            evidence["status"] = "escape-failed"
            evidence["reason"] = String(describing: error)
            throw error
        }
    }

    func stop(gracefully: Bool) async -> Bool {
        let began = ProcessInfo.processInfo.systemUptime
        let deadline = began + 8
        var errors: [String] = []
        var finishPublished = false
        if gracefully && ended {
            do {
                try publish("finished.json", object: ["schema": 1, "nonce": nonce, "action": "finished",
                                                      "createdSystemUptime": began])
                finishPublished = true
            } catch { errors.append(String(describing: error)) }
        }
        var terminated = false
        var forced = false
        var stopped = false
        repeat {
            let now = ProcessInfo.processInfo.systemUptime
            var verifiedRunner: NSRunningApplication?
            do { verifiedRunner = try currentRunner() }
            catch { if errors.isEmpty { errors.append(String(describing: error)) } }
            let registryEmpty = NSRunningApplication.runningApplications(withBundleIdentifier: runnerIdentifier).isEmpty
            if !process.isRunning && registryEmpty { stopped = true; break }
            if !terminated && (!finishPublished || now >= began + 6) {
                if process.isRunning { process.terminate() }
                if let verifiedRunner { _ = verifiedRunner.terminate() }
                terminated = true
            }
            if !forced && now >= deadline - 1 {
                if started && process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
                if let verifiedRunner { _ = verifiedRunner.forceTerminate() }
                forced = true
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        } while ProcessInfo.processInfo.systemUptime < deadline
        let processStopped = !process.isRunning
        let registryEmpty = NSRunningApplication.runningApplications(withBundleIdentifier: runnerIdentifier).isEmpty
        stopped = stopped || (processStopped && registryEmpty)
        if started && processStopped { evidence["processExitStatus"] = process.terminationStatus }
        completedNormally = finishPublished && stopped && started && process.terminationStatus == 0 && errors.isEmpty
        evidence["cleanup"] = ["stopConfirmed": stopped, "processStopped": processStopped,
                                "runnerRegistryEmpty": registryEmpty, "finishedPublished": finishPublished,
                                "normalCompletion": completedNormally, "terminationRequested": terminated,
                                "forceTerminationRequested": forced, "timeoutSeconds": 8,
                                "elapsedSeconds": ProcessInfo.processInfo.systemUptime - began, "errors": errors]
        if stopped { try? logHandle?.close(); logHandle = nil }
        return stopped
    }
}

@MainActor
final class DragReview {
    private let target: DragReviewTarget
    private let sameHost: SameHostDragOptions?
    private var identifier: String { target.identifier }
    private let directory: URL
    private let theme: DragReviewTheme
    // Keep related pointer and keyboard events on one source through cleanup.
    // Posting at the HID tap alone does not select the event's source state.
    private let inputSource = CGEventSource(stateID: .hidSystemState)
    private var bundle: URL!
    private var folder: URL!
    private var output: URL?
    private var reviewApp: NSRunningApplication?
    private var finderApp: NSRunningApplication?
    private var reviewWindow: AXUIElement?
    private var finderWindow: AXUIElement?
    private var keyboardDriver: KeyboardControlDriver?
    private var originals: [String: Data] = [:]
    private var inputNames: Set<String> = []
    private var mouseDown = false
    private var escapeKeyDown = false
    private var syntheticEscapePosts = 0
    private var externalEscapePollCount = 0
    private var pointer = CGPoint.zero
    private var events: [[String: Any]] = []
    private var mouseEventRecords: [[String: Any]] = []
    private let relevantModifiers: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
    private var diagnosticSnapshots: [[String: Any]] = []
    private let expiresAt = ProcessInfo.processInfo.systemUptime + 110
    var record: [String: Any] = [
        "schema": 1, "status": "not-run",
        "gestureOutcomesVerified": false, "outlineVisualReviewRequired": true,
        "outlineBehaviorVerified": false, "permissionRequested": false,
        "scope": "Real Finder drag; held entry, exit, re-entry, Escape and drop frames. Visual review is separate."
    ]

    init(directory: URL, theme: DragReviewTheme, target: DragReviewTarget,
         sameHost: SameHostDragOptions? = nil) {
        self.directory = directory.standardizedFileURL.resolvingSymlinksInPath()
        self.theme = theme
        self.target = target
        self.sameHost = sameHost
        record["theme"] = theme.rawValue
        record["targetKind"] = target == .production ? "production" : "standard-appkit-control"
        record["inputDriver"] = target.inputDriver
        if target != .production {
            record["scope"] = "Reference AppKit destination with passive event/callback tracing. Theme names identify fixture sets, not product appearances. No product verification claim."
        }
        if target == .keyboardControl {
            record["scope"] = "One Orchard reference destination using the public XCTest keyboard API for Escape; observer-owned Finder mouse input. No production or physical-keyboard verification claim."
        }
        if let sameHost {
            record["sameHost"] = [
                "imagesCaptured": false, "screenCaptureRequired": false,
                "captureKind": "target-ax-and-input-state",
                "keyboardObservation": "key-53-state-only",
                "sharedFinderPreparation": "paired-Command-1-before-drag",
                "hardwareProvenanceVerified": false
            ]
            record["sameHostEscape"] = [
                "mode": sameHost.escapeInput.rawValue, "status": "not-started",
                "leadInSeconds": sameHost.leadInSeconds.isFinite ? sameHost.leadInSeconds as Any : NSNull(),
                "dwellSeconds": sameHost.dwellSeconds.isFinite ? sameHost.dwellSeconds as Any : NSNull(),
                "externalDownTimeoutSeconds": sameHost.externalDownTimeoutSeconds.isFinite
                    ? sameHost.externalDownTimeoutSeconds as Any : NSNull(),
                "externalUpTimeoutSeconds": sameHost.externalUpTimeoutSeconds.isFinite
                    ? sameHost.externalUpTimeoutSeconds as Any : NSNull(),
                "motionDelayTargetSeconds": 0.075, "pollIntervalSeconds": 0.01,
                "syntheticEscapePosts": 0, "hardwareProvenanceVerified": false,
                "stateObservationIsDeliveryAcknowledgement": false,
                "timingSource": "ProcessInfo.systemUptime",
                "downWaitSeconds": NSNull(), "heldSeconds": NSNull(), "motionDelaySeconds": NSNull()
            ]
        }
    }

    private func updateSameHostEscape(_ fields: [String: Any]) {
        guard sameHost != nil else { return }
        var evidence = record["sameHostEscape"] as? [String: Any] ?? [:]
        evidence.merge(fields) { _, new in new }
        evidence["syntheticEscapePosts"] = syntheticEscapePosts
        record["sameHostEscape"] = evidence
    }

    private func sameHostBlocked(_ status: String, _ message: String) -> DragReviewIssue {
        updateSameHostEscape(["status": status, "reason": message])
        if sameHost != nil {
            record["status"] = "blocked"
            record["reason"] = message
        }
        return .blocked(message)
    }

    private func validateSameHostOptions() throws {
        guard let sameHost else { return }
        guard target != .keyboardControl,
              sameHost.leadInSeconds.isFinite, (0...12).contains(sameHost.leadInSeconds),
              sameHost.dwellSeconds.isFinite, (0.15...4).contains(sameHost.dwellSeconds),
              sameHost.externalDownTimeoutSeconds.isFinite,
              sameHost.externalDownTimeoutSeconds > 0, sameHost.externalDownTimeoutSeconds <= 12,
              sameHost.externalUpTimeoutSeconds.isFinite,
              sameHost.externalUpTimeoutSeconds > 0, sameHost.externalUpTimeoutSeconds <= 4 else {
            throw sameHostBlocked("invalid-configuration", "The same-host Escape options exceed their fixed bounds")
        }
    }

    private var observedDisplayPreferences: [String: Bool] {
        ["reduceMotion": NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
         "reduceTransparency": NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency]
    }

    private func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw DragReviewIssue.failed(message) }
    }

    private func read(_ node: AXUIElement, _ key: String) throws -> CFTypeRef? {
        try require(ProcessInfo.processInfo.systemUptime < expiresAt, "The bounded native drag review timed out")
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(node, key as CFString, &value)
        switch error {
        case .success: return value
        case .attributeUnsupported, .noValue: return nil
        default: throw AXReadFailure(attribute: key, status: error.rawValue)
        }
    }

    private func text(_ node: AXUIElement, _ key: String) throws -> String? {
        try read(node, key) as? String
    }

    private func names(_ node: AXUIElement) throws -> Set<String> {
        Set(try [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXIdentifierAttribute]
            .compactMap { try text(node, $0) })
    }

    private func pid(_ node: AXUIElement) throws -> pid_t {
        var value: pid_t = 0
        try require(AXUIElementGetPid(node, &value) == .success, "Could not identify the AX element's process")
        return value
    }

    private func frame(_ node: AXUIElement) throws -> CGRect {
        guard let position = try read(node, kAXPositionAttribute),
              let size = try read(node, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else {
            throw DragReviewIssue.failed("The real AX element has no position and size")
        }
        var point = CGPoint.zero
        var extent = CGSize.zero
        try require(AXValueGetValue(position as! AXValue, .cgPoint, &point) &&
                    AXValueGetValue(size as! AXValue, .cgSize, &extent), "Could not decode the AX element's frame")
        try require(point.x.isFinite && point.y.isFinite && extent.width.isFinite && extent.height.isFinite &&
                    extent.width > 0 && extent.height > 0,
                    "The AX element has an invalid frame")
        return CGRect(origin: point, size: extent)
    }

    private func nodes(_ root: AXUIElement, owner: pid_t) throws -> [AXUIElement] {
        var pending = [root]
        var result: [AXUIElement] = []
        while let node = pending.popLast() {
            if result.contains(where: { CFEqual($0, node) }) { continue }
            try require(result.count < 768, "The fixed window's AX tree exceeded the bounded review size")
            try require(try pid(node) == owner, "An AX node belongs to a different process")
            try require(AXUIElementSetMessagingTimeout(node, 0.4) == .success, "Could not bound AX messaging")
            result.append(node)
            if let children = try read(node, kAXChildrenAttribute) as? [AXUIElement] { pending += children }
        }
        return result
    }

    private func window(in app: NSRunningApplication, title: String) throws -> AXUIElement? {
        let root = AXUIElementCreateApplication(app.processIdentifier)
        try require(AXUIElementSetMessagingTimeout(root, 0.4) == .success, "Could not bound application AX messaging")
        let windows = try read(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
        let matches = try windows.filter { try text($0, kAXTitleAttribute) == title }
        try require(matches.count <= 1, "The expected window is ambiguous")
        return matches.first
    }

    private func unique(_ list: [AXUIElement], role: String, name: String) throws -> AXUIElement {
        let matches = try list.filter {
            guard try text($0, kAXRoleAttribute) == role else { return false }
            return try names($0).contains(name)
        }
        try require(matches.count == 1, "Expected exactly one \(role) named \(name)")
        return matches[0]
    }

    private func pause(_ seconds: Double) async throws {
        try require(ProcessInfo.processInfo.systemUptime + seconds < expiresAt, "The bounded native drag review timed out")
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func wait(_ message: String, seconds: Double = 8, retryWindowReadiness: Bool = false,
                      retryInitialWorkspaceReadiness: Bool = false,
                      retryFinderIconReadiness: Bool = false,
                      until condition: () throws -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        var lastReadinessFailure: String?
        var initialWorkspaceRetryCount = 0
        if retryInitialWorkspaceReadiness {
            record["initialWorkspaceReadiness"] = ["phase": "initial-workspace", "retryCount": 0,
                                                    "lastError": NSNull(), "timeoutSeconds": seconds]
        }
        var finderIconRetryCount = 0
        var finderIconErrors: [[String: Any]] = []
        if retryFinderIconReadiness {
            record["finderIconReadiness"] = ["phase": "finder-icons", "retryCount": 0,
                                            "lastError": NSNull(), "errors": finderIconErrors, "timeoutSeconds": seconds]
        }
        repeat {
            do { if try condition() { return } }
            catch let error as AXReadFailure where retryWindowReadiness
                && error.status == AXError.cannotComplete.rawValue
                && (error.attribute == kAXWindowsAttribute || error.attribute == kAXTitleAttribute) {
                // A newly launched app may not answer its window lookup yet.
                // Keep this retry inside the existing bounded readiness wait.
                lastReadinessFailure = error.description
            } catch let error as AXReadFailure where retryInitialWorkspaceReadiness
                && error.status == AXError.cannotComplete.rawValue && error.attribute == kAXChildrenAttribute {
                // Only the initial workspace may retry this transient tree read.
                // The original deadline is never extended or restarted.
                initialWorkspaceRetryCount += 1
                lastReadinessFailure = error.description
                record["initialWorkspaceReadiness"] = [
                    "phase": "initial-workspace", "retryCount": initialWorkspaceRetryCount, "timeoutSeconds": seconds,
                    "lastError": ["attribute": error.attribute, "status": error.status, "description": error.description]
                ]
            } catch let error as AXReadFailure where retryFinderIconReadiness
                && error.status == AXError.invalidUIElement.rawValue {
                // Re-read only the initial Finder icon tree within the same deadline.
                finderIconRetryCount += 1
                lastReadinessFailure = error.description
                let failure: [String: Any] = ["attribute": error.attribute, "status": error.status,
                                             "description": error.description, "systemUptime": ProcessInfo.processInfo.systemUptime]
                finderIconErrors.append(failure)
                record["finderIconReadiness"] = [
                    "phase": "finder-icons", "retryCount": finderIconRetryCount, "timeoutSeconds": seconds,
                    "lastError": failure, "errors": finderIconErrors
                ]
            }
            try await pause(0.1)
        } while ProcessInfo.processInfo.systemUptime < deadline
        throw DragReviewIssue.failed(lastReadinessFailure.map { message + "; last readiness error: " + $0 } ?? message)
    }

    private func fixtureSet() throws -> Set<String> {
        let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        return Set(urls.map(\.lastPathComponent).filter { $0 != ".DS_Store" })
    }

    private func fixture(_ prefix: String) throws -> URL {
        let matches = inputNames.filter { $0.hasPrefix(prefix + "-") && $0.hasSuffix(".txt") }
        try require(matches.count == 1, "The input-only fixture prefix is missing or ambiguous: \(prefix)")
        return folder.appendingPathComponent(matches.first!)
    }

    private func validate() throws {
        try require(directory.lastPathComponent == "lemulip-native-ui", "Use the isolated native UI staging directory")
        bundle = directory.appendingPathComponent(target.bundleName, isDirectory: true)
        folder = directory.appendingPathComponent("Fixtures/FinderDrop/" + theme.rawValue, isDirectory: true)
        let evidenceRoot = directory.appendingPathComponent(target.evidenceName, isDirectory: true)
        for url in [bundle!, folder!, evidenceRoot] {
            try require(url.standardizedFileURL.path == url.resolvingSymlinksInPath().path,
                        "Symlinked review targets are not allowed")
        }
        try require(try evidenceRoot.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true,
                    "The fixed evidence root is unavailable")
        let infoData = try Data(contentsOf: bundle.appendingPathComponent("Contents/Info.plist"))
        let info = try PropertyListSerialization.propertyList(from: infoData, options: [], format: nil) as? [String: Any]
        try require(info?["CFBundleIdentifier"] as? String == identifier && info?["CFBundleExecutable"] as? String == target.executable,
                    "The target does not match its fixed staged identity")
        inputNames = try fixtureSet()
        try require(inputNames.count == 4, "Require exactly four staged Finder inputs")
        for prefix in ["Existing", "Single", "Multi-A", "Multi-B"] {
            let input = try fixture(prefix)
            let values = try input.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            try require(values.isRegularFile == true && values.isSymbolicLink == false &&
                        (values.fileSize ?? 0) > 0 && (values.fileSize ?? 0) < 65_536, "Require small, nonempty regular fixture files")
            originals[input.lastPathComponent] = try Data(contentsOf: input)
        }
        let destination = evidenceRoot.appendingPathComponent(theme.rawValue, isDirectory: true)
        try require(!FileManager.default.fileExists(atPath: destination.path), "Refusing to replace existing drag evidence")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        output = destination
        record["fixtureFolder"] = folder.path
        record["applicationPath"] = bundle.path
        record["originalSHA256"] = originals.mapValues { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() }
        if let data = try? Data(contentsOf: directory.appendingPathComponent("provenance.json")),
           let provenance = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let keys = ["sourceCommit", "sourceTree", "architecture", "nativeDragReviewSourceSHA256"]
                + (target == .production ? ["stagedGUI_SHA256", "compiledTestSourceSHA256"]
                   : ["controlGUI_SHA256", "nativeDragControlSourceSHA256"])
                + (target == .keyboardControl ? ["nativeDragKeyboardTestsSourceSHA256", "keyboardRunnerInfoSHA256",
                                                "keyboardRunnerExecutableSHA256"] : [])
            for key in keys {
                if let value = provenance[key] as? String { record[key] = value }
            }
        }
    }

    private func assertTargets() throws {
        guard let app = reviewApp, let finder = finderApp else { throw DragReviewIssue.failed("Review targets are not ready") }
        try require(!app.isTerminated && app.bundleIdentifier == identifier &&
                    app.bundleURL?.resolvingSymlinksInPath().path == bundle.path, "The staged app identity changed")
        try require(!finder.isTerminated && finder.bundleIdentifier == "com.apple.finder" &&
                    finder.bundleURL?.resolvingSymlinksInPath().path == "/System/Library/CoreServices/Finder.app",
                    "The Finder process identity changed")
    }

    private func arrange(_ window: AXUIElement, owner: pid_t, rect: CGRect) throws {
        let windowPID = try pid(window)
        let windowRole = try text(window, kAXRoleAttribute)
        try require(windowPID == owner && windowRole == kAXWindowRole,
                    "Only the verified review/Finder windows may be arranged")
        var point = rect.origin
        var size = rect.size
        guard let position = AXValueCreate(.cgPoint, &point), let extent = AXValueCreate(.cgSize, &size) else {
            throw DragReviewIssue.failed("Could not encode the bounded window frame")
        }
        for (attribute, value) in [(kAXSizeAttribute, extent), (kAXPositionAttribute, position)] {
            var settable = DarwinBoolean(false)
            guard AXUIElementIsAttributeSettable(window, attribute as CFString, &settable) == .success, settable.boolValue else {
                throw DragReviewIssue.blocked("The authorized AX interface cannot arrange the fixture window")
            }
            try require(AXUIElementSetAttributeValue(window, attribute as CFString, value) == .success,
                        "Could not arrange the verified fixture window")
        }
    }

    private func appNodes() throws -> [AXUIElement] {
        guard let window = reviewWindow, let app = reviewApp else { throw DragReviewIssue.failed("No review window") }
        return try nodes(window, owner: app.processIdentifier)
    }

    private func finderNodes() throws -> [AXUIElement] {
        guard let window = finderWindow, let app = finderApp else { throw DragReviewIssue.failed("No fixture Finder window") }
        return try nodes(window, owner: app.processIdentifier)
    }

    private func workspaceContains(_ expected: Set<String>) throws -> Bool {
        try workspaceObservation(expected).matches
    }

    private func workspaceObservation(_ expected: Set<String>) throws -> (matches: Bool, evidence: [String: Any]) {
        let list = try appNodes()
        var removeButtonCounts = Dictionary(uniqueKeysWithValues: inputNames.map { ($0, 0) })
        let expectedCountLabel = "\(expected.count) Selected"
        var expectedCountMatches = 0
        var selectedCountLabels: [String] = []
        for node in list {
            let role = try text(node, kAXRoleAttribute)
            guard role == kAXButtonRole || role == kAXStaticTextRole else { continue }
            let labels = try names(node)
            if role == kAXButtonRole {
                for name in inputNames where labels.contains("Remove " + name) {
                    removeButtonCounts[name, default: 0] += 1
                }
            } else {
                if labels.contains(expectedCountLabel) { expectedCountMatches += 1 }
                selectedCountLabels += labels.filter {
                    $0.range(of: #"^[0-9]+ Selected$"#, options: .regularExpression) != nil
                }.sorted()
            }
        }
        let observed = Set(removeButtonCounts.filter { $0.value > 0 }.map { $0.key })
        let matches = removeButtonCounts.values.allSatisfy { $0 <= 1 }
            && observed == expected && expectedCountMatches == 1
        return (matches, [
            "matchesExpectedWorkspace": matches, "expectedFilenames": expected.sorted(),
            "observedFilenames": observed.sorted(), "fixtureRemoveButtonCounts": removeButtonCounts,
            "expectedSelectedCountLabel": expectedCountLabel, "expectedSelectedCountMatches": expectedCountMatches,
            "selectedCountLabels": selectedCountLabels.sorted(),
            "time": ISO8601DateFormatter().string(from: Date())
        ])
    }

    private func focusedReviewElementObservation() throws -> [String: Any] {
        try assertTargets()
        guard let app = reviewApp else { throw DragReviewIssue.failed("No verified review application") }
        let owner = app.processIdentifier
        let root = AXUIElementCreateApplication(owner)
        try require(AXUIElementSetMessagingTimeout(root, 0.4) == .success, "Could not bound the review focus lookup")
        try require(try pid(root) == owner, "The review focus root belongs to another process")
        var observation: [String: Any] = [
            "status": "unavailable", "applicationPID": Int(owner),
            "scope": "verified-staged-application-only", "focusedPID": NSNull(),
            "role": NSNull(), "identifier": NSNull(), "description": NSNull()
        ]
        do {
            guard let value = try read(root, kAXFocusedUIElementAttribute) else {
                observation["reason"] = "The staged application exposed no focused UI element"
                return observation
            }
            guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
                observation["reason"] = "The staged application's focused UI attribute was not an AX element"
                return observation
            }
            let focused = value as! AXUIElement
            let focusedPID = try pid(focused)
            try require(focusedPID == owner, "The focused AX element belongs to another process")
            observation["focusedPID"] = Int(focusedPID)
            try require(AXUIElementSetMessagingTimeout(focused, 0.4) == .success, "Could not bound focused element reads")
            var unavailable: [String] = []
            for (attribute, field) in [(kAXRoleAttribute, "role"), (kAXIdentifierAttribute, "identifier"),
                                       (kAXDescriptionAttribute, "description")] {
                if let value = try text(focused, attribute) { observation[field] = value }
                else { unavailable.append(attribute) }
            }
            observation["status"] = unavailable.isEmpty ? "observed" : "partial"
            observation["unavailableAttributes"] = unavailable
        } catch let error as AXReadFailure where error.status == AXError.cannotComplete.rawValue
            || error.status == AXError.invalidUIElement.rawValue {
            // Supplemental focus data can be unavailable. Identity, PID and
            // timeout guards throw different errors and remain fatal.
            observation["lastError"] = ["attribute": error.attribute, "status": error.status,
                                        "description": error.description]
        }
        return observation
    }

    private func recordEscapeObservation(_ phase: String, expected: Set<String>) throws {
        var observation: [String: Any] = ["phase": phase, "startedSystemUptime": ProcessInfo.processInfo.systemUptime]
        defer {
            observation["completedSystemUptime"] = ProcessInfo.processInfo.systemUptime
            var observations = record["escapeObservations"] as? [[String: Any]] ?? []
            observations.append(observation)
            record["escapeObservations"] = observations
        }
        do {
            try assertTargets()
            observation["workspace"] = try workspaceObservation(expected).evidence
            observation["focusedUIElement"] = try focusedReviewElementObservation()
            observation["status"] = "observed"
        } catch {
            observation["status"] = "failed"
            observation["reason"] = String(describing: error)
            throw error
        }
    }

    private func recordEscapeInputState(_ phase: String) {
        let foreground = NSWorkspace.shared.frontmostApplication
        var state: [String: Any] = [
            "phase": phase, "time": ISO8601DateFormatter().string(from: Date()),
            "systemUptime": ProcessInfo.processInfo.systemUptime,
            "pointerSent": ["x": pointer.x, "y": pointer.y],
            "mouseDownSent": mouseDown,
            "leftButtonReportedDown": CGEventSource.buttonState(.combinedSessionState, button: .left),
            "hidLeftButtonReportedDown": CGEventSource.buttonState(.hidSystemState, button: .left),
            "escapeKeyDownSent": escapeKeyDown,
            "escapeKeyReportedDown": CGEventSource.keyState(.combinedSessionState, key: 53),
            "hidEscapeKeyReportedDown": CGEventSource.keyState(.hidSystemState, key: 53),
            "modifiers": modifierObservation(),
            "foregroundPID": NSNull(), "foregroundBundleIdentifier": NSNull()
        ]
        if let foreground {
            state["foregroundPID"] = Int(foreground.processIdentifier)
            if let bundleIdentifier = foreground.bundleIdentifier { state["foregroundBundleIdentifier"] = bundleIdentifier }
        }
        var states = record["escapeInputStates"] as? [[String: Any]] ?? []
        states.append(state)
        record["escapeInputStates"] = states
    }

    private func modifierObservation() -> [String: Any] {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        return ["sessionFlags": flags.rawValue, "relevantFlags": flags.intersection(relevantModifiers).rawValue,
                "command": flags.contains(.maskCommand), "shift": flags.contains(.maskShift),
                "option": flags.contains(.maskAlternate), "control": flags.contains(.maskControl)]
    }

    private func recordFinderViewShortcutState(_ phase: String) {
        let probe = CGEvent(mouseEventSource: inputSource, mouseType: .mouseMoved,
                            mouseCursorPosition: pointer, mouseButton: .left)
        var states = record["finderViewShortcutStates"] as? [[String: Any]] ?? []
        states.append(["phase": phase, "systemUptime": ProcessInfo.processInfo.systemUptime,
                       "modifiers": modifierObservation(),
                       "unpostedMouseConstructorFlags": probe.map { $0.flags.rawValue as Any } ?? NSNull(),
                       "scope": "Input state and an unposted constructor probe; not application delivery acknowledgement."])
        record["finderViewShortcutStates"] = states
    }

    private func requireHit(_ point: CGPoint, owner: pid_t, stage: String) throws {
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &element)
        var check: [String: Any] = ["stage": stage, "point": ["x": point.x, "y": point.y],
                                    "expectedPID": Int(owner), "axStatus": result.rawValue]
        var observedPID: pid_t = 0
        var pidStatus: AXError?
        if result == .success, let element {
            let status = AXUIElementGetPid(element, &observedPID)
            pidStatus = status
            check["pidStatus"] = status.rawValue
            if pidStatus == .success {
                check["observedPID"] = Int(observedPID)
                if let identifier = NSRunningApplication(processIdentifier: observedPID)?.bundleIdentifier {
                    check["observedBundleIdentifier"] = identifier
                }
            }
        }
        if let foreground = NSWorkspace.shared.frontmostApplication { check["foregroundPID"] = Int(foreground.processIdentifier) }
        var checks = record["hitChecks"] as? [[String: Any]] ?? []
        checks.append(check)
        record["hitChecks"] = checks
        guard result == .success, element != nil else { throw DragReviewIssue.failed("Could not identify the native pointer target") }
        try require(pidStatus == .success, "Could not identify the AX element's process")
        try require(observedPID == owner, "Another process covers the intended native pointer target (\(stage))")
    }

    private func mouse(_ type: CGEventType, at point: CGPoint) throws {
        try require(ProcessInfo.processInfo.systemUptime < expiresAt, "The bounded native drag review timed out")
        try assertTargets()
        try require(CGDisplayBounds(CGMainDisplayID()).contains(point), "Refusing a pointer event outside the observed display")
        if sameHost != nil, type == .leftMouseDown {
            guard !mouseDown,
                  !CGEventSource.buttonState(.combinedSessionState, button: .left),
                  !CGEventSource.buttonState(.hidSystemState, button: .left) else {
                throw sameHostBlocked("mouse-already-down", "Refusing to take ownership of an already-held mouse button")
            }
        }
        // Reserve the final record for releasing our own button during cleanup.
        try require(mouseEventRecords.count < 255, "The bounded pointer event record limit was reached")
        guard let event = CGEvent(mouseEventSource: inputSource, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else {
            throw DragReviewIssue.failed("Could not create the native pointer event")
        }
        let constructorFlags = event.flags
        let sessionFlags = CGEventSource.flagsState(.combinedSessionState)
        try require(sessionFlags.intersection(relevantModifiers).isEmpty,
                    "Refusing plain pointer input while a Command, Shift, Option or Control modifier is held")
        // Keep constructor flags except the four guarded modifiers for this comparison.
        event.flags = constructorFlags.subtracting(relevantModifiers)
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        postMouseEvent(event, constructorFlags: constructorFlags, sessionFlags: sessionFlags, scope: "plain-gesture")
        pointer = point
        if type == .leftMouseDown { mouseDown = true }
        if type == .leftMouseUp { mouseDown = false }
    }

    private func postMouseEvent(_ event: CGEvent, constructorFlags: CGEventFlags,
                                sessionFlags: CGEventFlags, scope: String) {
        let started = ProcessInfo.processInfo.systemUptime
        let postedFlags = event.flags.rawValue
        event.post(tap: .cghidEventTap)
        mouseEventRecords.append([
            "scope": scope, "eventType": event.type.rawValue, "eventTap": "cghidEventTap",
            "sourceStateID": event.getIntegerValueField(.eventSourceStateID),
            "mouseEventNumber": event.getIntegerValueField(.mouseEventNumber),
            "timestampNanoseconds": event.timestamp,
            "location": ["x": event.location.x, "y": event.location.y],
            "constructorFlags": constructorFlags.rawValue, "postedFlags": postedFlags,
            "sessionFlagsBeforePost": sessionFlags.rawValue,
            "systemUptimeBeforePost": started, "systemUptimeAfterPost": ProcessInfo.processInfo.systemUptime,
            "postCalled": true
        ])
        record["mouseEvents"] = mouseEventRecords
    }

    private func postKeyEvent(_ event: CGEvent, code: CGKeyCode) {
        event.post(tap: .cghidEventTap)
        if code == 53 {
            syntheticEscapePosts += 1
            updateSameHostEscape([:])
        }
    }

    private func key(_ code: CGKeyCode, flags: CGEventFlags = []) throws {
        if code == 53, sameHost?.escapeInput == .external {
            throw sameHostBlocked("unexpected-synthetic-escape", "External Escape does not authorize a scripted Escape event")
        }
        try assertTargets()
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        try require(front == finderApp?.processIdentifier || front == reviewApp?.processIdentifier,
                    "Refusing a key event while another application is foreground")
        try require(!CGEventSource.keyState(.combinedSessionState, key: code),
                    "Refusing to take ownership of an already-held shortcut key")
        try require(CGEventSource.flagsState(.combinedSessionState).intersection(relevantModifiers).isEmpty,
                    "Refusing a shortcut while another modifier is held")
        guard let down = CGEvent(keyboardEventSource: inputSource, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: inputSource, virtualKey: code, keyDown: false) else {
            throw DragReviewIssue.failed("Could not create the native key event pair")
        }
        down.flags = flags
        up.flags = []
        postKeyEvent(down, code: code)
        defer { postKeyEvent(up, code: code) }
        if code == 18 { recordFinderViewShortcutState("after-key-down-before-paired-up") }
    }

    private func escapeWithDwell(movingTo motionPoint: CGPoint) async throws {
        if sameHost?.escapeInput == .external {
            throw sameHostBlocked("unexpected-synthetic-escape", "External Escape cannot use the automatic key pair")
        }
        let dwell = sameHost?.dwellSeconds ?? 0.15
        let leadInStarted = ProcessInfo.processInfo.systemUptime
        if let sameHost {
            updateSameHostEscape(["status": "automatic-lead-in",
                                  "leadInStartedSystemUptime": leadInStarted])
            if sameHost.leadInSeconds > 0 { try await pause(sameHost.leadInSeconds) }
        }
        try assertTargets()
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        try require(front == finderApp?.processIdentifier || front == reviewApp?.processIdentifier,
                    "Refusing a key event while another application is foreground")
        try require(CGPreflightPostEventAccess(), "Existing event-post authorization is unavailable")
        try require(!CGEventSource.keyState(.combinedSessionState, key: 53),
                    "Refusing to take ownership of an already-held Escape key")
        try require(mouseDown && CGEventSource.buttonState(.combinedSessionState, button: .left),
                    "Escape motion requires this probe's actual held mouse button")
        try require(motionPoint.x == pointer.x + 1 && motionPoint.y == pointer.y,
                    "Escape motion must advance exactly one point within the same target padding")
        guard let down = CGEvent(keyboardEventSource: inputSource, virtualKey: 53, keyDown: true),
              let up = CGEvent(keyboardEventSource: inputSource, virtualKey: 53, keyDown: false) else {
            throw DragReviewIssue.failed("Could not create the native Escape event pair")
        }
        down.flags = []
        up.flags = []
        record["escapeKeyProtocol"] = [
            "kind": "observer-protocol-experiment", "keyCode": 53, "eventTap": "cghidEventTap",
            "keyDownDwellSeconds": dwell,
            "downSourceStateID": down.getIntegerValueField(.eventSourceStateID),
            "upSourceStateID": up.getIntegerValueField(.eventSourceStateID),
            "keyboardType": down.getIntegerValueField(.keyboardEventKeyboardType),
            "keyEventLocation": ["x": down.location.x, "y": down.location.y],
            "downTimestampNanoseconds": down.timestamp, "upTimestampNanoseconds": up.timestamp,
            "downFlags": down.flags.rawValue, "upFlags": up.flags.rawValue,
            "continuedMotionPoint": ["x": motionPoint.x, "y": motionPoint.y],
            "continuedMotionDelta": ["x": motionPoint.x - pointer.x, "y": motionPoint.y - pointer.y],
            "scope": "Controlled continued-motion observer experiment; not a product fix or an Apple requirement."
        ]
        let downPosted = ProcessInfo.processInfo.systemUptime
        postKeyEvent(down, code: 53)
        escapeKeyDown = true
        updateSameHostEscape(["status": "automatic-key-held", "downPostedSystemUptime": downPosted,
                              "downWaitSeconds": downPosted - leadInStarted])
        defer {
            // Release only the exact key paired with our guarded down, even if
            // the bounded pause fails. This paired release sends no new key-down.
            let upPosted = ProcessInfo.processInfo.systemUptime
            postKeyEvent(up, code: 53)
            escapeKeyDown = false
            updateSameHostEscape(["upPostedSystemUptime": upPosted, "heldSeconds": upPosted - downPosted])
            recordEscapeInputState("after-key-up")
        }
        let motionDelay = sameHost == nil ? dwell / 2 : 0.075
        try await pause(sameHost == nil ? motionDelay
                        : max(0, downPosted + motionDelay - ProcessInfo.processInfo.systemUptime))
        recordEscapeInputState("before-held-motion")
        let motionFront = NSWorkspace.shared.frontmostApplication?.processIdentifier
        try require(motionFront == finderApp?.processIdentifier || motionFront == reviewApp?.processIdentifier,
                    "Refusing drag motion while another application is foreground")
        try require(mouseDown && CGEventSource.buttonState(.combinedSessionState, button: .left)
                    && escapeKeyDown && CGEventSource.keyState(.combinedSessionState, key: 53),
                    "The continued drag requires both this probe's mouse button and Escape to remain down")
        let motionStarted = ProcessInfo.processInfo.systemUptime
        try mouse(.leftMouseDragged, at: motionPoint)
        updateSameHostEscape(["motionStartedSystemUptime": motionStarted,
                              "motionDelaySeconds": motionStarted - downPosted])
        recordEscapeInputState("after-held-motion")
        try await pause(sameHost == nil ? dwell / 2
                        : max(0, downPosted + dwell - ProcessInfo.processInfo.systemUptime))
        // System input state is an observation, not an application delivery ACK.
        recordEscapeInputState("before-key-up")
        updateSameHostEscape(["status": "posted-down-and-up"])
    }

    private func externalEscapeState() -> (hid: Bool, combined: Bool) {
        let state = (hid: CGEventSource.keyState(.hidSystemState, key: 53),
                     combined: CGEventSource.keyState(.combinedSessionState, key: 53))
        externalEscapePollCount += 1
        updateSameHostEscape(["pollCount": externalEscapePollCount,
                              "lastHIDEscapeDown": state.hid, "lastCombinedEscapeDown": state.combined])
        return state
    }

    private func validateExternalEscapeContext() throws {
        if Task.isCancelled {
            throw sameHostBlocked("interrupted", "The external Escape observation was interrupted")
        }
        guard ProcessInfo.processInfo.systemUptime < expiresAt else {
            throw sameHostBlocked("run-deadline-exceeded", "The bounded external Escape observation expired")
        }
        do { try assertTargets() }
        catch {
            throw sameHostBlocked("invalid-target", "An external Escape target is no longer valid: \(error)")
        }
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard front == finderApp?.processIdentifier || front == reviewApp?.processIdentifier else {
            throw sameHostBlocked("invalid-foreground", "Another application became foreground during external Escape")
        }
        guard mouseDown,
              CGEventSource.buttonState(.combinedSessionState, button: .left),
              CGEventSource.buttonState(.hidSystemState, button: .left) else {
            throw sameHostBlocked("invalid-owned-mouse", "External Escape requires the observer's still-held mouse button")
        }
        guard CGEventSource.flagsState(.combinedSessionState).intersection(relevantModifiers).isEmpty,
              CGEventSource.flagsState(.hidSystemState).intersection(relevantModifiers).isEmpty else {
            throw sameHostBlocked("invalid-modifiers", "External Escape requires Command, Shift, Option and Control to remain released")
        }
        guard CGPreflightPostEventAccess() else {
            throw sameHostBlocked("post-access-unavailable", "Existing permission to release the owned mouse is unavailable")
        }
    }

    private func pauseForExternalEscapePoll() async throws {
        do { try await Task.sleep(nanoseconds: 10_000_000) }
        catch {
            throw sameHostBlocked("interrupted", "The external Escape observation was interrupted")
        }
    }

    private func holdExternalEscape(until deadline: Double, earlyReleaseStatus: String) async throws {
        while true {
            try validateExternalEscapeContext()
            let state = externalEscapeState()
            guard state.hid && state.combined else {
                throw sameHostBlocked(earlyReleaseStatus, "Escape was released before the requested held-key interval finished")
            }
            if ProcessInfo.processInfo.systemUptime >= deadline { return }
            try await pauseForExternalEscapePoll()
        }
    }

    private func escapeWithExternalInput(movingTo motionPoint: CGPoint) async throws {
        guard let sameHost, sameHost.escapeInput == .external else {
            throw sameHostBlocked("invalid-configuration", "The external Escape mode is unavailable")
        }
        try validateExternalEscapeContext()
        guard motionPoint.x == pointer.x + 1 && motionPoint.y == pointer.y else {
            throw sameHostBlocked("invalid-motion-geometry", "External Escape must retain the same one-point target motion")
        }
        let initialState = externalEscapeState()
        guard !initialState.hid && !initialState.combined else {
            throw sameHostBlocked("escape-already-down", "Release Escape before the external-input prompt")
        }
        record["escapeKeyProtocol"] = [
            "kind": "external-key-state-observation", "keyCode": 53,
            "inputDriver": "user-requested-external-Escape", "pollIntervalSeconds": 0.01,
            "continuedMotionPoint": ["x": motionPoint.x, "y": motionPoint.y],
            "continuedMotionDelta": ["x": motionPoint.x - pointer.x, "y": motionPoint.y - pointer.y],
            "hardwareProvenanceVerified": false, "stateObservationIsDeliveryAcknowledgement": false,
            "scope": "Only key 53 state is polled. No event tap, text collection, scripted Escape or owned physical key-up."
        ]
        let prompted = ProcessInfo.processInfo.systemUptime
        let downDeadline = min(expiresAt, prompted + sameHost.externalDownTimeoutSeconds)
        updateSameHostEscape(["status": "waiting-down", "promptSystemUptime": prompted,
                              "downDeadlineSystemUptime": downDeadline])
        sameHost.onPrompt?("press-escape")
        var observedDown: Double?
        while observedDown == nil {
            try validateExternalEscapeContext()
            let now = ProcessInfo.processInfo.systemUptime
            guard now < downDeadline else {
                throw sameHostBlocked("timed-out-waiting-down", "No complete Escape-down state was observed before the bounded prompt expired")
            }
            let state = externalEscapeState()
            if state.hid && state.combined {
                observedDown = ProcessInfo.processInfo.systemUptime
            } else {
                try await pauseForExternalEscapePoll()
            }
        }
        guard let down = observedDown else {
            throw sameHostBlocked("missing-down-observation", "The external Escape-down observation is unavailable")
        }
        updateSameHostEscape(["status": "external-key-held", "downObservedSystemUptime": down,
                              "downWaitSeconds": down - prompted])
        recordEscapeInputState("external-key-down-observed")
        try await holdExternalEscape(until: down + 0.075, earlyReleaseStatus: "released-before-motion")
        recordEscapeInputState("before-held-motion")
        let motionStarted = ProcessInfo.processInfo.systemUptime
        do { try mouse(.leftMouseDragged, at: motionPoint) }
        catch {
            throw sameHostBlocked("motion-failed", "The bounded external Escape motion could not be completed: \(error)")
        }
        updateSameHostEscape(["motionStartedSystemUptime": motionStarted,
                              "motionDelaySeconds": motionStarted - down])
        recordEscapeInputState("after-held-motion")
        try await holdExternalEscape(until: ProcessInfo.processInfo.systemUptime + 0.075,
                                     earlyReleaseStatus: "released-before-release-prompt")
        let releasePrompted = ProcessInfo.processInfo.systemUptime
        // A successful observation must remain inside the automatic replay's
        // four-second dwell bound as well as the configured key-up wait.
        let upDeadline = min(expiresAt, min(releasePrompted + sameHost.externalUpTimeoutSeconds, down + 4))
        updateSameHostEscape(["status": "waiting-up", "releasePromptSystemUptime": releasePrompted,
                              "upDeadlineSystemUptime": upDeadline])
        sameHost.onPrompt?("release-escape")
        while true {
            try validateExternalEscapeContext()
            let now = ProcessInfo.processInfo.systemUptime
            guard now < upDeadline else {
                throw sameHostBlocked("timed-out-waiting-up", "Escape was not observed released within the bounded replayable interval")
            }
            let state = externalEscapeState()
            if !state.hid && !state.combined {
                let up = ProcessInfo.processInfo.systemUptime
                let held = up - down
                guard (0.15...4).contains(held) else {
                    throw sameHostBlocked("invalid-held-duration", "The observed Escape interval cannot be replayed inside the fixed bounds")
                }
                updateSameHostEscape(["status": "observed-external-pair", "upObservedSystemUptime": up,
                                      "heldSeconds": held])
                recordEscapeInputState("external-key-up-observed")
                return
            }
            try await pauseForExternalEscapePoll()
        }
    }

    private func escapeWithKeyboardDriver() async throws {
        try assertTargets()
        guard target == .keyboardControl, theme == .orchard,
              let driver = keyboardDriver, let app = reviewApp else {
            throw DragReviewIssue.failed("The fixed Orchard keyboard comparison is not ready")
        }
        defer {
            recordEscapeInputState("after-xctest-request")
            record["keyboardDriver"] = driver.evidence
        }
        try require(NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
                    "The exact AppKit control must be foreground for the keyboard request")
        try require(mouseDown && CGEventSource.buttonState(.combinedSessionState, button: .left)
                    && CGEventSource.flagsState(.combinedSessionState).intersection(relevantModifiers).isEmpty
                    && !CGEventSource.keyState(.combinedSessionState, key: 53),
                    "The keyboard request requires our held mouse with clear modifiers and Escape up")
        record["escapeKeyProtocol"] = ["kind": "input-driver-comparison", "inputDriver": "XCTest", "keyCode": 53,
                                       "modifierFlags": 0, "continuedMotion": false,
                                       "scope": "One public typeKey call; no observer CG Escape, dwell or held-motion update."]
        try await driver.requestEscape(target: app, application: bundle, expiresAt: expiresAt)
    }

    private func moveHeld(to target: CGPoint) async throws {
        try require(mouseDown, "A continuous drag requires the existing mouse-down")
        let start = pointer
        for step in 1...18 {
            let fraction = CGFloat(step) / 18
            try mouse(.leftMouseDragged, at: CGPoint(x: start.x + (target.x - start.x) * fraction,
                                                    y: start.y + (target.y - start.y) * fraction))
            try await pause(0.025)
        }
        try await pause(0.25)
    }

    private func sourcePoint(_ input: URL, stage: String) async throws -> CGPoint {
        try assertTargets()
        try await focusFinderWindow()
        try await wait("Finder did not become foreground") {
            NSWorkspace.shared.frontmostApplication?.processIdentifier == self.finderApp?.processIdentifier
        }
        let source = try unique(finderNodes(), role: kAXImageRole, name: input.lastPathComponent)
        let rect = try frame(source)
        let point = CGPoint(x: rect.midX, y: rect.midY)
        try require(CGDisplayBounds(CGMainDisplayID()).contains(rect), "The source Finder icon is not fully onscreen")
        try requireHit(point, owner: finderApp!.processIdentifier, stage: stage)
        try mouse(.mouseMoved, at: point)
        try mouse(.leftMouseDown, at: point)
        try await pause(0.08)
        try mouse(.leftMouseUp, at: point)
        try await wait("Finder did not select the exact fixture icon") {
            let images = try self.finderNodes().filter { try self.text($0, kAXRoleAttribute) == kAXImageRole }
            let selected = try images.filter { (try self.read($0, kAXSelectedAttribute) as? NSNumber)?.boolValue == true }
            guard selected.count == 1 else { return false }
            return try self.names(selected[0]).contains(input.lastPathComponent)
        }
        return point
    }

    private func focusFinderWindow() async throws {
        try assertTargets()
        guard let window = finderWindow, let finder = finderApp,
              let review = reviewWindow, let app = reviewApp,
              try pid(window) == finder.processIdentifier, try pid(review) == app.processIdentifier,
              try text(window, kAXRoleAttribute) == kAXWindowRole, try text(review, kAXRoleAttribute) == kAXWindowRole,
              try text(window, kAXTitleAttribute) == folder.lastPathComponent,
              try text(review, kAXTitleAttribute) == target.windowTitle else {
            throw DragReviewIssue.failed("The fixed review/Finder windows are unavailable")
        }
        finder.activate(options: [])
        try await wait("Finder did not become foreground before arranging the fixed window stack") {
            NSWorkspace.shared.frontmostApplication?.processIdentifier == finder.processIdentifier
        }
        // Other windows can remain after XCTest. Raise only our two verified
        // windows, putting the drop target immediately behind its Finder source.
        try require(AXUIElementPerformAction(review, kAXRaiseAction as CFString) == .success,
                    "Could not raise the exact staged review window")
        try require(AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success,
                    "Could not raise the exact fixture Finder window")
        try await wait("The fixture Finder window did not become foreground") {
            NSWorkspace.shared.frontmostApplication?.processIdentifier == finder.processIdentifier
        }
    }

    private func capture(_ name: String, setup: Bool = false, diagnostic: Bool = false) async throws {
        let started = ProcessInfo.processInfo.systemUptime
        guard let output else { throw DragReviewIssue.failed("Evidence destination is not ready") }
        try assertTargets()
        if sameHost != nil {
            let list = try appNodes()
            let labels = try list.compactMap { node -> String? in
                let role = try text(node, kAXRoleAttribute)
                guard role == kAXButtonRole || role == kAXStaticTextRole else { return nil }
                return try names(node).sorted().joined(separator: " | ")
            }
            let event: [String: Any] = [
                "stage": name, "captureKind": "target-ax-and-input-state",
                "imagesCaptured": false, "screenCaptureRequired": false,
                "pointer": ["x": pointer.x, "y": pointer.y], "mouseDownSent": mouseDown,
                "leftButtonReportedDown": CGEventSource.buttonState(.combinedSessionState, button: .left),
                "hidLeftButtonReportedDown": CGEventSource.buttonState(.hidSystemState, button: .left),
                "escapeKeyReportedDown": CGEventSource.keyState(.combinedSessionState, key: 53),
                "hidEscapeKeyReportedDown": CGEventSource.keyState(.hidSystemState, key: 53),
                "displayPreferences": observedDisplayPreferences,
                "captureStartedSystemUptime": started,
                "captureCompletedSystemUptime": ProcessInfo.processInfo.systemUptime,
                "time": ISO8601DateFormatter().string(from: Date()), "workspaceAXLabels": labels
            ]
            if setup { record["setupSnapshot"] = event }
            else if diagnostic { diagnosticSnapshots.append(event) }
            else { events.append(event) }
            try JSONSerialization.data(withJSONObject: event, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent(name + ".json"), options: .atomic)
            return
        }
        let image = output.appendingPathComponent(name + ".png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-C", "-m", image.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer { if process.isRunning { process.terminate() } }
        let deadline = ProcessInfo.processInfo.systemUptime + 8
        while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline { try await pause(0.05) }
        if process.isRunning { process.terminate(); throw DragReviewIssue.failed("The authorized screen capture timed out") }
        try require(process.terminationStatus == 0, "The authorized screen capture failed")
        let data = try Data(contentsOf: image)
        guard let bitmap = NSBitmapImageRep(data: data) else { throw DragReviewIssue.failed("The captured image is unreadable") }
        let list = try appNodes()
        let labels = try list.compactMap { node -> String? in
            let role = try text(node, kAXRoleAttribute)
            guard role == kAXButtonRole || role == kAXStaticTextRole else { return nil }
            return try names(node).sorted().joined(separator: " | ")
        }
        let event: [String: Any] = [
            "stage": name, "image": image.lastPathComponent,
            "imageSHA256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            "pixelWidth": bitmap.pixelsWide, "pixelHeight": bitmap.pixelsHigh,
            "pointer": ["x": pointer.x, "y": pointer.y], "mouseDownSent": mouseDown,
            "leftButtonReportedDown": CGEventSource.buttonState(.combinedSessionState, button: .left),
            "displayPreferences": observedDisplayPreferences,
            "captureStartedSystemUptime": started,
            "captureCompletedSystemUptime": ProcessInfo.processInfo.systemUptime,
            "time": ISO8601DateFormatter().string(from: Date()), "workspaceAXLabels": labels
        ]
        if setup { record["setupSnapshot"] = event }
        else if diagnostic { diagnosticSnapshots.append(event) }
        else { events.append(event) }
        try JSONSerialization.data(withJSONObject: event, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent(name + ".json"), options: .atomic)
    }

    private func verifyOriginals() throws {
        try require(try fixtureSet() == inputNames, "A drag created, moved or removed a user file")
        for (name, bytes) in originals {
            try require(try Data(contentsOf: folder.appendingPathComponent(name)) == bytes, "A drag changed an original's bytes")
        }
    }

    func run() async throws {
        try validateSameHostOptions()
        sameHost?.onPrompt?("preparing")
        try validate()
        var permissions = ["accessibility": AXIsProcessTrusted(), "postEvents": CGPreflightPostEventAccess()]
        if sameHost == nil { permissions["screenCapture"] = CGPreflightScreenCaptureAccess() }
        record["preflight"] = permissions
        record["displayPreferencesAtStart"] = observedDisplayPreferences
        guard permissions.values.allSatisfy({ $0 }) else {
            throw DragReviewIssue.blocked("Existing authorization is insufficient; no permission was requested or changed")
        }
        guard let inputSource else {
            throw DragReviewIssue.blocked("Could not create the shared HID event source")
        }
        let previousIntervalFilter = inputSource.getLocalEventsFilterDuringSuppressionState(.eventSuppressionStateSuppressionInterval)
        let previousDragFilter = inputSource.getLocalEventsFilterDuringSuppressionState(.eventSuppressionStateRemoteMouseDrag)
        // Keep keyboard input enabled during both kinds of synthetic-input
        // suppression. This source-specific comparison does not retarget keys.
        inputSource.setLocalEventsFilterDuringSuppressionState(previousIntervalFilter.union(.permitLocalKeyboardEvents),
                                                               state: .eventSuppressionStateSuppressionInterval)
        inputSource.setLocalEventsFilterDuringSuppressionState(previousDragFilter.union(.permitLocalKeyboardEvents),
                                                               state: .eventSuppressionStateRemoteMouseDrag)
        let intervalFilter = inputSource.getLocalEventsFilterDuringSuppressionState(.eventSuppressionStateSuppressionInterval)
        let dragFilter = inputSource.getLocalEventsFilterDuringSuppressionState(.eventSuppressionStateRemoteMouseDrag)
        record["inputSource"] = [
            "kind": "shared-hid-keyboard-filter-comparison", "sourceStateID": inputSource.sourceStateID.rawValue,
            "localEventsSuppressionInterval": inputSource.localEventsSuppressionInterval,
            "previousSuppressionIntervalFilter": previousIntervalFilter.rawValue,
            "previousRemoteMouseDragFilter": previousDragFilter.rawValue,
            "suppressionIntervalFilter": intervalFilter.rawValue,
            "remoteMouseDragFilter": dragFilter.rawValue,
            "scope": "Shared HID source with keyboard pass-through; global key routing, suppression interval and other filter bits are unchanged."
        ]
        try require(intervalFilter.contains(.permitLocalKeyboardEvents) && dragFilter.contains(.permitLocalKeyboardEvents),
                    "The observer source did not retain keyboard pass-through")
        try require(NSRunningApplication.runningApplications(withBundleIdentifier: identifier).isEmpty,
                    "The isolated review application must be stopped before the standalone probe")
        if target == .keyboardControl {
            record["startupPhase"] = "keyboard-driver"
            let driver = try KeyboardControlDriver(directory: directory)
            keyboardDriver = driver
            defer { record["keyboardDriver"] = driver.evidence }
            try await driver.start(expiresAt: expiresAt)
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["-language", "en", "-theme", theme.rawValue, "-wheelEnabled", "NO",
                                   "-completionPresentation", "quiet", "-NSQuitAlwaysKeepsWindows", "NO"]
        if target != .production { configuration.arguments += ["-controlTheme", theme.rawValue] }
        if target == .keyboardControl { configuration.arguments += ["-controlEvidenceKind", "keyboard"] }
        configuration.addsToRecentItems = false
        reviewApp = try await NSWorkspace.shared.openApplication(at: bundle, configuration: configuration)
        guard let app = reviewApp else { throw DragReviewIssue.failed("The staged app did not launch") }
        try require(app.bundleIdentifier == identifier && app.bundleURL?.resolvingSymlinksInPath().path == bundle.path,
                    "The launch did not produce the exact staged app")
        try await wait("The production review window did not appear", retryWindowReadiness: true) {
            self.reviewWindow = try self.window(in: app, title: self.target.windowTitle)
            return self.reviewWindow != nil
        }
        let screen = CGDisplayBounds(CGMainDisplayID())
        try require(screen.width >= 900 && screen.height >= 700, "The display is too small for this bounded two-window observation")
        try arrange(reviewWindow!, owner: app.processIdentifier,
                    rect: CGRect(x: screen.minX + 16, y: screen.minY + 32, width: min(920, screen.width - 32), height: 560))
        let existing = try fixture("Existing")
        let single = try fixture("Single")
        _ = try await NSWorkspace.shared.open([existing], withApplicationAt: bundle, configuration: configuration)
        record["startupPhase"] = "initial-workspace"
        try await wait("The production app did not accept the sole initial fixture", retryInitialWorkspaceReadiness: true) {
            try self.workspaceContains([existing.lastPathComponent])
        }
        record["startupPhase"] = "fixture-finder-window"
        try require(NSWorkspace.shared.open(folder), "Finder could not open the isolated fixture folder")
        try await wait("Finder is unavailable") {
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").count == 1
        }
        finderApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
        try assertTargets()
        try await wait("The exact fixture Finder window did not appear", retryWindowReadiness: true) {
            self.finderWindow = try self.window(in: self.finderApp!, title: self.folder.lastPathComponent)
            return self.finderWindow != nil
        }
        try await focusFinderWindow()
        try await wait("Finder is not foreground for choosing its view") {
            NSWorkspace.shared.frontmostApplication?.processIdentifier == self.finderApp?.processIdentifier
        }
        recordFinderViewShortcutState("before-command-1")
        try key(18, flags: .maskCommand) // Native Command-1, with a paired unmodified key-up.
        recordFinderViewShortcutState("after-command-1")
        try await wait("The Finder view shortcut did not release its modifier flags") {
            CGEventSource.flagsState(.combinedSessionState).intersection(self.relevantModifiers).isEmpty
        }
        recordFinderViewShortcutState("after-modifier-clear-wait")
        record["startupPhase"] = "finder-icons"
        try await wait("Finder did not expose all four exact fixture icons", retryFinderIconReadiness: true) {
            let icons = try self.finderNodes().filter { try self.text($0, kAXRoleAttribute) == kAXImageRole }
            return try self.inputNames.allSatisfy { name in try icons.filter { try self.names($0).contains(name) }.count == 1 }
        }
        record["startupPhase"] = "target-geometry"
        let appElements = try appNodes()
        let header = try frame(unique(appElements, role: kAXStaticTextRole, name: "1 Selected"))
        let clear = try frame(unique(appElements, role: kAXButtonRole, name: "Clear"))
        record["startupPhase"] = "complete"
        let enter = CGPoint(x: (header.minX + clear.maxX) / 2, y: header.minY - 4)
        let escapeMotionPoint = CGPoint(x: enter.x + 1, y: enter.y)
        let releasePoint = target == .keyboardControl ? enter : escapeMotionPoint
        let topPadding = CGRect(x: header.minX, y: header.minY - 8, width: clear.maxX - header.minX, height: 8)
        let outside = CGPoint(x: enter.x, y: header.minY - 24)
        let finderTop = header.maxY + 100
        try arrange(finderWindow!, owner: finderApp!.processIdentifier,
                    rect: CGRect(x: screen.minX + 8, y: finderTop, width: min(920, screen.width - 16),
                                 height: min(360, screen.maxY - finderTop - 12)))
        try await focusFinderWindow()
        try await pause(0.3)
        let actualFinderFrame = try frame(finderWindow!)
        let actualReviewFrame = try frame(reviewWindow!)
        record["targetGeometry"] = ["header": NSStringFromRect(header), "entryInTopPadding": NSStringFromPoint(enter),
                                    "escapeMotionPoint": NSStringFromPoint(escapeMotionPoint), "topPadding": NSStringFromRect(topPadding),
                                    "releasePoint": NSStringFromPoint(releasePoint),
                                    "outside": NSStringFromPoint(outside), "reviewWindow": NSStringFromRect(actualReviewFrame),
                                    "finderWindow": NSStringFromRect(actualFinderFrame)]
        try await capture("setup-before-hit-checks", setup: true)
        try require(actualReviewFrame.contains(enter) && actualReviewFrame.contains(escapeMotionPoint)
                    && topPadding.contains(enter) && topPadding.contains(escapeMotionPoint),
                    "The one-point Escape motion must remain inside the review window's same top padding")
        try require(!actualFinderFrame.contains(enter) && !actualFinderFrame.contains(outside)
                    && !actualFinderFrame.contains(escapeMotionPoint),
                    "The fixture Finder window covers the observed target")
        try requireHit(enter, owner: app.processIdentifier, stage: "initial-entry")
        try requireHit(outside, owner: app.processIdentifier, stage: "initial-outside")

        let source = try await sourcePoint(single, stage: "cancel-source")
        try requireHit(enter, owner: app.processIdentifier, stage: "cancel-entry")
        try requireHit(outside, owner: app.processIdentifier, stage: "cancel-outside")
        try requireHit(escapeMotionPoint, owner: app.processIdentifier, stage: "cancel-held-motion")
        try await capture("00-before-drag")
        sameHost?.onPrompt?("dragging")
        try mouse(.leftMouseDown, at: source)
        try await pause(0.3)
        try await moveHeld(to: enter)
        try await capture("01-enter-top-padding")
        try await moveHeld(to: outside)
        try await capture("02-leave-file-area")
        try await moveHeld(to: enter)
        try await capture("03-reenter-top-padding")
        try recordEscapeObservation("before-key", expected: [existing.lastPathComponent])
        recordEscapeInputState(target == .keyboardControl ? "before-xctest-request" : "before-key-post")
        if sameHost?.escapeInput == .external { try await escapeWithExternalInput(movingTo: escapeMotionPoint) }
        else if target == .keyboardControl { try await escapeWithKeyboardDriver() }
        else { try await escapeWithDwell(movingTo: escapeMotionPoint) } // Escape while the same drag is still held.
        recordEscapeInputState(target == .keyboardControl ? "after-xctest-end" : "after-key-post")
        sameHost?.onPrompt?("settling")
        try await pause(0.15)
        let diagnosticStarted = ProcessInfo.processInfo.systemUptime
        recordEscapeInputState("before-held-observation")
        do {
            try recordEscapeObservation("after-key-held", expected: [existing.lastPathComponent])
            try await capture("diagnostic-after-escape-held", diagnostic: true)
            let completed = ProcessInfo.processInfo.systemUptime
            record["escapeHeldDiagnostic"] = [
                "stage": "diagnostic-after-escape-held", "status": "captured",
                "startedSystemUptime": diagnosticStarted, "completedSystemUptime": completed,
                "addedObservationSeconds": completed - diagnosticStarted, "addsKeyUpToReleaseDelay": true
            ]
        } catch {
            let completed = ProcessInfo.processInfo.systemUptime
            record["escapeHeldDiagnostic"] = [
                "stage": "diagnostic-after-escape-held", "status": "failed", "reason": String(describing: error),
                "startedSystemUptime": diagnosticStarted, "completedSystemUptime": completed,
                "addedObservationSeconds": completed - diagnosticStarted, "addsKeyUpToReleaseDelay": true
            ]
            throw error
        }
        recordEscapeInputState("before-release")
        try mouse(.leftMouseUp, at: releasePoint)
        recordEscapeInputState("after-release")
        try await pause(0.7)
        recordEscapeInputState("after-settle")
        // Freeze the original cancellation check before the capture adds any delay.
        let cancellation = try workspaceObservation([existing.lastPathComponent])
        record["escapeCancellation"] = cancellation.evidence
        do {
            try await capture("04-after-escape")
            record["escapeCancellationCapture"] = ["stage": "04-after-escape", "status": "captured"]
        } catch {
            record["escapeCancellationCapture"] = ["stage": "04-after-escape", "status": "failed",
                                                    "reason": String(describing: error)]
            throw error
        }
        try require(cancellation.matches, "Escape did not cancel the actual Finder drag")
        try verifyOriginals()

        let secondSource = try await sourcePoint(single, stage: "drop-source")
        try requireHit(enter, owner: app.processIdentifier, stage: "drop-entry")
        try requireHit(outside, owner: app.processIdentifier, stage: "drop-outside")
        try mouse(.leftMouseDown, at: secondSource)
        try await pause(0.3)
        try await moveHeld(to: enter)
        try await capture("05-before-accepted-drop")
        try mouse(.leftMouseUp, at: enter)
        try await wait("The real Finder drop did not add exactly its file") {
            try self.workspaceContains([existing.lastPathComponent, single.lastPathComponent])
        }
        try verifyOriginals()
        try await capture("06-after-accepted-drop")
        record["status"] = "captured"
        record["gestureOutcomesVerified"] = true
        record["originalBytesUnchanged"] = true
        record["userFileSetUnchanged"] = true
        record["metadataExclusion"] = "Only Finder's .DS_Store view metadata"
    }

    private func cleanupRead(_ node: AXUIElement, _ key: String, deadline: Double) throws -> CFTypeRef? {
        let remaining = deadline - ProcessInfo.processInfo.systemUptime
        try require(remaining > 0, "The bounded native drag cleanup timed out")
        try require(AXUIElementSetMessagingTimeout(node, Float(min(0.4, remaining))) == .success,
                    "Could not bound cleanup AX messaging")
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(node, key as CFString, &value)
        switch error {
        case .success: return value
        case .attributeUnsupported, .noValue: return nil
        default: throw DragReviewIssue.failed("Cleanup AX read failed for \(key): \(error.rawValue)")
        }
    }

    func cleanUp() async -> Bool {
        // Cleanup must still run after the per-theme 110-second clock expires.
        var deadline = ProcessInfo.processInfo.systemUptime + 8
        var errors: [String] = []
        var keyboardStopped = true
        if let driver = keyboardDriver, !driver.ended {
            // A synchronous XCTest input may still be running after its request
            // expires. Stop its owned processes before any further native input.
            keyboardStopped = await driver.stop(gracefully: false)
            record["keyboardDriver"] = driver.evidence
            if !keyboardStopped { errors.append("The keyboard driver did not stop; only our paired mouse release is allowed") }
        }
        if mouseDown {
            if target != .keyboardControl, sameHost?.escapeInput != .external,
               !CGEventSource.keyState(.combinedSessionState, key: 53),
               CGEventSource.flagsState(.combinedSessionState).intersection(relevantModifiers).isEmpty { try? key(53) }
            // Always release this probe's own held button, even if a target
            // has exited. Preserve any live modifiers instead of clearing them.
            if CGPreflightPostEventAccess(),
               let event = CGEvent(mouseEventSource: inputSource, mouseType: .leftMouseUp,
                                   mouseCursorPosition: pointer, mouseButton: .left) {
                let constructorFlags = event.flags
                let sessionFlags = CGEventSource.flagsState(.combinedSessionState)
                event.flags = sessionFlags
                postMouseEvent(event, constructorFlags: constructorFlags, sessionFlags: sessionFlags, scope: "owned-button-cleanup")
                mouseDown = false
            } else {
                errors.append("Could not release this probe's held mouse button")
            }
        }
        if let driver = keyboardDriver, driver.ended {
            // END means the only key call returned. Keep the runner alive until
            // the observed gesture (including an error-path release) is over.
            keyboardStopped = await driver.stop(gracefully: true)
            record["keyboardDriver"] = driver.evidence
            if !keyboardStopped { errors.append("The completed keyboard driver did not stop") }
            if !driver.completedNormally { errors.append("The keyboard XCTest did not complete its final handshake successfully") }
        }
        if target == .keyboardControl {
            // The separate driver stop has its own eight-second bound; retain
            // the original eight seconds for verified native target cleanup.
            deadline = ProcessInfo.processInfo.systemUptime + 8
        }
        var finderClosed = finderWindow == nil
        var finderRoot: AXUIElement?
        if keyboardStopped, let window = finderWindow, let finder = finderApp {
            if finder.isTerminated { finderClosed = true }
            else {
                do {
                    let windowPID = try pid(window)
                    try require(finder.bundleIdentifier == "com.apple.finder" &&
                                finder.bundleURL?.resolvingSymlinksInPath().path == "/System/Library/CoreServices/Finder.app" &&
                                windowPID == finder.processIdentifier,
                                "The cleanup Finder identity changed")
                    let root = AXUIElementCreateApplication(finder.processIdentifier)
                    guard let windows = try cleanupRead(root, kAXWindowsAttribute, deadline: deadline) as? [AXUIElement] else {
                        throw DragReviewIssue.failed("Could not confirm the fixture Finder window during cleanup")
                    }
                    finderClosed = !windows.contains { CFEqual($0, window) }
                    if !finderClosed {
                        let title = try cleanupRead(window, kAXTitleAttribute, deadline: deadline) as? String
                        try require(title == folder.lastPathComponent,
                                    "Refusing to close a different Finder folder")
                        guard let value = try cleanupRead(window, kAXCloseButtonAttribute, deadline: deadline),
                              CFGetTypeID(value) == AXUIElementGetTypeID() else {
                            throw DragReviewIssue.failed("The exact fixture Finder window has no close button")
                        }
                        let button = value as! AXUIElement
                        try require(try pid(button) == finder.processIdentifier,
                                    "The fixture close button belongs to another process")
                        let remaining = deadline - ProcessInfo.processInfo.systemUptime
                        try require(remaining > 0, "The bounded native drag cleanup timed out")
                        try require(AXUIElementSetMessagingTimeout(button, Float(min(0.4, remaining))) == .success &&
                                    AXUIElementPerformAction(button, kAXPressAction as CFString) == .success,
                                    "Could not close the exact fixture Finder window")
                        finderRoot = root
                    }
                } catch { errors.append(String(describing: error)) }
            }
        } else if keyboardStopped && finderWindow != nil {
            errors.append("The fixture Finder owner is unavailable during cleanup")
        }
        // Terminate only the exact staged app launched by this probe.
        if keyboardStopped, let app = reviewApp, !app.isTerminated {
            if app.bundleIdentifier == identifier && app.bundleURL?.resolvingSymlinksInPath().path == bundle.path {
                if !app.terminate() && !app.isTerminated { errors.append("The staged app refused normal termination") }
            } else { errors.append("Refusing to terminate an application whose staged identity changed") }
        }
        while ProcessInfo.processInfo.systemUptime < deadline {
            if let root = finderRoot, let window = finderWindow, !finderClosed {
                do {
                    guard let windows = try cleanupRead(root, kAXWindowsAttribute, deadline: deadline) as? [AXUIElement] else {
                        throw DragReviewIssue.failed("Could not confirm that the fixture Finder window closed")
                    }
                    finderClosed = !windows.contains { CFEqual($0, window) }
                } catch {
                    errors.append(String(describing: error))
                    finderRoot = nil
                }
            }
            if !CGEventSource.buttonState(.combinedSessionState, button: .left),
               reviewApp?.isTerminated ?? true,
               NSRunningApplication.runningApplications(withBundleIdentifier: identifier).isEmpty,
               finderClosed || finderRoot == nil { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        let leftButtonDown = CGEventSource.buttonState(.combinedSessionState, button: .left)
        let applicationStopped = reviewApp?.isTerminated ?? true
        let registryEmpty = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).isEmpty
        if leftButtonDown { errors.append("The left mouse button remains down; no further theme may run") }
        if !applicationStopped { errors.append("The staged app did not terminate before the cleanup deadline") }
        if !registryEmpty { errors.append("The fixed review bundle remains registered as running") }
        if !finderClosed { errors.append("The exact fixture Finder window was not confirmed closed") }
        if target == .keyboardControl {
            let escapeDown = CGEventSource.keyState(.combinedSessionState, key: 53)
            let flags = CGEventSource.flagsState(.combinedSessionState)
            record["keyboardCleanupInputState"] = ["systemUptime": ProcessInfo.processInfo.systemUptime,
                                                   "escapeKeyReportedDown": escapeDown,
                                                   "sessionFlags": flags.rawValue,
                                                   "relevantFlags": flags.intersection(relevantModifiers).rawValue]
            if escapeDown { errors.append("Escape remains down after the keyboard driver stopped; no synthetic key-up was sent") }
            if !flags.intersection(relevantModifiers).isEmpty { errors.append("A modifier remains held after keyboard driver cleanup") }
        } else if sameHost?.escapeInput == .external {
            let escapeDown = CGEventSource.keyState(.combinedSessionState, key: 53)
            let hidEscapeDown = CGEventSource.keyState(.hidSystemState, key: 53)
            let flags = CGEventSource.flagsState(.combinedSessionState)
            let hidFlags = CGEventSource.flagsState(.hidSystemState)
            record["keyboardCleanupInputState"] = ["systemUptime": ProcessInfo.processInfo.systemUptime,
                                                   "escapeKeyReportedDown": escapeDown,
                                                   "hidEscapeKeyReportedDown": hidEscapeDown,
                                                   "sessionFlags": flags.rawValue, "hidFlags": hidFlags.rawValue,
                                                   "relevantFlags": flags.intersection(relevantModifiers).rawValue]
            if escapeDown || hidEscapeDown {
                errors.append("External Escape remains down; the observer did not send a key-up it does not own")
            }
            if !flags.intersection(relevantModifiers).isEmpty || !hidFlags.intersection(relevantModifiers).isEmpty {
                errors.append("A modifier remains held after external Escape cleanup")
            }
        }
        updateSameHostEscape([:])
        record["stages"] = events
        record["diagnosticSnapshots"] = diagnosticSnapshots
        record["cleanup"] = ["completed": errors.isEmpty, "leftButtonReportedDown": leftButtonDown,
                             "applicationStopped": applicationStopped, "fixtureFinderWindowClosed": finderClosed,
                             "fixedBundleRegistryEmpty": registryEmpty, "timeoutSeconds": 8, "errors": errors]
        if target == .keyboardControl { record["keyboardDriverStopConfirmed"] = keyboardStopped }
        return errors.isEmpty
    }

    func finish() throws {
        guard let output else { throw DragReviewIssue.failed("The per-theme evidence destination was not created") }
        if let driver = keyboardDriver { record["keyboardDriver"] = driver.evidence }
        let data = try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: output.appendingPathComponent("report.json"), options: .atomic)
    }
}

#if !SAME_HOST_REVIEW
@main
private struct NativeDragReview {
    @MainActor
    static func main() async {
        guard CommandLine.arguments.count == 2
            || (CommandLine.arguments.count == 3 && ["--control", "--keyboard-control"].contains(CommandLine.arguments[2])) else {
            FileHandle.standardError.write(Data("Usage: NativeDragReview <isolated review directory> [--control | --keyboard-control]\n".utf8))
            exit(2)
        }
        let target: DragReviewTarget = CommandLine.arguments.count == 2 ? .production
            : (CommandLine.arguments[2] == "--keyboard-control" ? .keyboardControl : .control)
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        var aggregate: [String: Any] = [
            "schema": 2, "status": "not-run", "expectedThemes": target.themes.map(\.rawValue),
            "allThemesCaptured": false, "gestureOutcomesVerified": false,
            "outlineVisualReviewRequired": true, "outlineBehaviorVerified": false,
            "permissionRequested": false,
            "scope": "The same real Finder drag sequence in three fixed themes; visual outline review is separate."
        ]
        aggregate["targetKind"] = target == .production ? "production" : "standard-appkit-control"
        aggregate["inputDriver"] = target.inputDriver
        if target != .production {
            aggregate["scope"] = "The same Finder input into a standard AppKit reference destination. Fixture labels are not themes. This is a diagnostic control, not production verification."
        }
        if target == .keyboardControl {
            aggregate["scope"] = "One Orchard standard AppKit reference destination; public XCTest Escape and observer-owned Finder mouse. No production or physical-keyboard verification claim."
        }
        do {
            guard directory.lastPathComponent == "lemulip-native-ui" else {
                throw DragReviewIssue.failed("Use the isolated native UI staging directory")
            }
            let destination = directory.appendingPathComponent(target.evidenceName, isDirectory: true)
            let standardized = destination.standardizedFileURL
            let resolved = destination.resolvingSymlinksInPath()
            let samePath = standardized.path == resolved.path
            let existed = FileManager.default.fileExists(atPath: destination.path)
            // A new directory's URL hint can change during symlink resolution.
            // Compare filesystem paths and retain the former URL comparison for diagnosis.
            aggregate["evidenceRootValidation"] = ["urlIdentityMatches": standardized == resolved,
                                                 "canonicalPathsMatch": samePath,
                                                 "existedBeforeCreation": existed]
            guard samePath else {
                throw DragReviewIssue.failed("Refusing a symlinked drag evidence root")
            }
            guard !existed else {
                throw DragReviewIssue.failed("Refusing to replace an existing drag evidence root")
            }
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
            var reports: [[String: Any]] = []
            var stopReason: String?
            for theme in target.themes {
                if let stopReason {
                    reports.append(["theme": theme.rawValue, "status": "not-run", "reason": stopReason])
                    continue
                }
                // A new object gives each theme its own fixtures, AX handles,
                // original-byte receipt and bounded 110-second run clock.
                let review = DragReview(directory: directory, theme: theme, target: target)
                do { try await review.run() }
                catch let error as DragReviewIssue {
                    switch error {
                    case .blocked: review.record["status"] = "blocked"
                    case .failed: review.record["status"] = "failed"
                    }
                    review.record["reason"] = error.description
                } catch {
                    review.record["status"] = "failed"
                    review.record["reason"] = String(describing: error)
                }
                let clean = await review.cleanUp()
                if !clean {
                    review.record["status"] = "failed"
                    let reason = "Cleanup did not verify a safe transition after " + theme.rawValue
                    review.record["reason"] = [review.record["reason"] as? String, reason]
                        .compactMap { $0 }.joined(separator: "; ")
                    stopReason = reason
                }
                var reportRetained = false
                do { try review.finish(); reportRetained = true }
                catch {
                    review.record["status"] = "failed"
                    review.record["reportError"] = String(describing: error)
                }
                var summary: [String: Any] = ["theme": theme.rawValue,
                    "status": review.record["status"] as? String ?? "failed", "reportRetained": reportRetained]
                if reportRetained { summary["report"] = theme.rawValue + "/report.json" }
                for key in ["reason", "reportError", "gestureOutcomesVerified", "cleanup", "displayPreferencesAtStart", "keyboardDriverStopConfirmed"] {
                    if let value = review.record[key] { summary[key] = value }
                }
                reports.append(summary)
                for key in ["sourceCommit", "sourceTree", "architecture", "stagedGUI_SHA256",
                            "compiledTestSourceSHA256", "nativeDragReviewSourceSHA256", "controlGUI_SHA256",
                            "nativeDragControlSourceSHA256", "nativeDragKeyboardTestsSourceSHA256", "keyboardRunnerInfoSHA256",
                            "keyboardRunnerExecutableSHA256"] {
                    if aggregate[key] == nil, let value = review.record[key] { aggregate[key] = value }
                }
            }
            let statuses = reports.compactMap { $0["status"] as? String }
            let captured = statuses.count == target.themes.count && statuses.allSatisfy { $0 == "captured" }
            aggregate["themes"] = reports
            aggregate["allThemesCaptured"] = captured
            aggregate["gestureOutcomesVerified"] = captured
            aggregate["status"] = statuses.contains("failed") ? "failed" : (captured ? "captured" : "blocked")
            let data = try JSONSerialization.data(withJSONObject: aggregate, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: destination.appendingPathComponent("report.json"), options: .atomic)
        } catch {
            aggregate["status"] = "failed"
            aggregate["reason"] = String(describing: error)
        }
        if let data = try? JSONSerialization.data(withJSONObject: aggregate, options: [.prettyPrinted, .sortedKeys]) {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data([10]))
        } else {
            aggregate["status"] = "failed"
            FileHandle.standardError.write(Data("Could not encode the native drag report\n".utf8))
        }
        exit(aggregate["status"] as? String == "failed" ? 1 : 0)
    }
}
#endif
