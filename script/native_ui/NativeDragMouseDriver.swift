import AppKit
import ApplicationServices
import CoreFoundation
import CryptoKit
import Darwin
import Foundation

// Owns one prebuilt public-XCTest mouse runner. It never posts input or
// activates either application. The observer owns the separate Escape pair.
@MainActor
final class MouseControlDriver {
    private struct Request {
        let index: Int
        let phase: String
        let created: Double
        let expires: Double
        let sourcePID: pid_t
        let targetPID: pid_t
        let object: [String: Any]
    }

    private let directory: URL
    private let caseName: String
    private let control: URL
    private let project: URL
    private let derivedData: URL
    private let runnerBundle: URL
    private let runnerExecutable: URL
    private let testsExecutable: URL
    private let testRun: URL
    private let runnerIdentifier = "app.lemulip.NativeDragMouseTests.xctrunner"
    private let sourceIdentifier = "app.lemulip.NativeDragSource"
    private let targetIdentifier = "app.lemulip.NativeDragControl"
    private let process = Process()
    private var logHandle: FileHandle?
    private var runner: NSRunningApplication?
    // Freeze the positive PID while the owned instance is fully verified alive.
    // NSRunningApplication metadata may become unavailable after termination.
    private var boundRunnerPID: pid_t?
    private var nonce = ""
    private var started = false
    private var startedAt = 0.0
    private var lifetimeExpires = 0.0
    private var requests: [Request] = []
    private var completedRequests = 0
    private var markerLines: [String] = []
    private var ready = false
    private var finishedAt: Double?
    private var finishedAcknowledged = false
    private var finishedObservedAt: Double?
    private var retirementObserved = false
    private var protocolFailed = false
    private var lastMarkerTime = 0.0
    private(set) var completedNormally = false
    private(set) var evidence: [String: Any] = ["inputDriver": "XCTest", "status": "not-started"]

    var gestureRunning: Bool { requests.count > completedRequests }

    init(directory: URL, caseName: String) throws {
        self.directory = directory.standardizedFileURL
        self.caseName = caseName
        control = self.directory.appendingPathComponent("MouseControl/" + caseName, isDirectory: true)
        project = self.directory.appendingPathComponent("MouseRunner/QualityReview.xcodeproj", isDirectory: true)
        derivedData = self.directory.appendingPathComponent("MouseDerivedData", isDirectory: true)
        runnerBundle = derivedData.appendingPathComponent("Build/Products/Debug/QualityReview-Runner.app", isDirectory: true)
        runnerExecutable = runnerBundle.appendingPathComponent("Contents/MacOS/QualityReview-Runner")
        testsExecutable = runnerBundle.appendingPathComponent("Contents/PlugIns/QualityReview.xctest/Contents/MacOS/QualityReview")
        testRun = derivedData.appendingPathComponent("Build/Products/D13-" + caseName + ".xctestrun")
        try require(directory.isFileURL && self.directory.lastPathComponent == "lemulip-native-ui",
                    "Require the fixed mouse staging root")
        try require(["quartz-first", "xctest-first", "xctest-second", "quartz-second"].contains(caseName),
                    "The mouse driver case is not in the fixed comparison")
        for url in [self.directory, control, project, derivedData, runnerBundle] {
            try checkPath(url, directory: true)
        }
        let configurationData = try readBounded(control.appendingPathComponent("configuration.json"), maximum: 4_096)
        guard let configuration = try JSONSerialization.jsonObject(with: configurationData) as? [String: Any],
              Set(configuration.keys) == Set(["schema", "case", "nonce"]),
              let value = configuration["nonce"] as? String else {
            throw issue("The mouse configuration is not the exact expected object")
        }
        try require(try number(configuration, "schema") == 1 && configuration["case"] as? String == caseName
                    && value.count == 32 && value.allSatisfy({ "0123456789abcdef".contains($0) }),
                    "The mouse configuration has an invalid schema or nonce")
        nonce = value
        let infoData = try readBounded(runnerBundle.appendingPathComponent("Contents/Info.plist"), maximum: 262_144)
        let info = try PropertyListSerialization.propertyList(from: infoData, options: [], format: nil) as? [String: Any]
        try require(info?["CFBundleIdentifier"] as? String == runnerIdentifier
                    && info?["CFBundleExecutable"] as? String == "QualityReview-Runner",
                    "The mouse runner does not match its fixed prebuilt identity")
        let executableData = try readBounded(runnerExecutable, maximum: 268_435_456)
        let testsData = try readBounded(testsExecutable, maximum: 268_435_456)
        let testRunData = try readBounded(testRun, maximum: 1_048_576)
        try require(!executableData.isEmpty && !testsData.isEmpty, "A prebuilt mouse runner executable is empty")
        try require(NSRunningApplication.runningApplications(withBundleIdentifier: runnerIdentifier).isEmpty,
                    "The fixed mouse runner must be stopped before this case")
        for name in ["xcodebuild.log", "request-1.json", "request-2.json", "finished.json"] {
            try requireAbsent(control.appendingPathComponent(name))
            try requireAbsent(control.appendingPathComponent(name + ".pending"))
        }
        evidence = [
            "inputDriver": "XCTest", "status": "validated", "nonce": nonce, "case": caseName,
            "runnerBundleIdentifier": runnerIdentifier, "runnerApplicationPath": runnerBundle.path,
            "runnerExecutablePath": runnerExecutable.path, "projectPath": project.path,
            "mouseTestsExecutablePath": testsExecutable.path, "mouseTestsExecutableSHA256": digest(testsData),
            "mouseXCTestRunPath": testRun.path, "mouseConfigurationPath": control.appendingPathComponent("configuration.json").path,
            "mouseRunnerInfoSHA256": digest(infoData), "mouseRunnerExecutableSHA256": digest(executableData),
            "mouseConfigurationSHA256": digest(configurationData), "mouseXCTestRunSHA256": digest(testRunData),
            "readyTimeoutSeconds": 60, "gestureTimeoutSeconds": 20, "lifetimeSeconds": 150,
            "stopTimeoutSeconds": 8, "publishedRequestCount": 0, "completedRequestCount": 0,
            "requests": [[String: Any]](), "markerReceipts": [[String: Any]](),
            "runnerRetirementObservations": [[String: Any]]()
        ]
    }

    private func issue(_ text: String) -> NSError {
        NSError(domain: "LemulipNativeMouseDriver", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }

    private func require(_ condition: Bool, _ text: String) throws {
        if !condition { throw issue(text) }
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func number(_ object: [String: Any], _ name: String) throws -> Double {
        guard let value = object[name] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
              value.doubleValue.isFinite else {
            throw issue("The mouse protocol has an invalid numeric field: " + name)
        }
        return value.doubleValue
    }

    private func boolean(_ object: [String: Any], _ name: String) throws -> Bool {
        guard let value = object[name] as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else {
            throw issue("The mouse protocol has an invalid Boolean field: " + name)
        }
        return value.boolValue
    }

    private func requireAbsent(_ url: URL) throws {
        var attributes = stat()
        try require(lstat(url.path, &attributes) != 0 && errno == ENOENT,
                    "Refusing an existing mouse protocol output")
    }

    private func checkPath(_ url: URL, directory: Bool) throws {
        try require(url.isFileURL && url.standardizedFileURL.path == url.resolvingSymlinksInPath().path,
                    "Symlinked mouse driver paths are not allowed")
        var attributes = stat()
        try require(lstat(url.path, &attributes) == 0
                    && (attributes.st_mode & mode_t(S_IFMT)) == mode_t(directory ? S_IFDIR : S_IFREG),
                    "A fixed mouse driver path has the wrong file type")
    }

    private func readBounded(_ url: URL, maximum: Int) throws -> Data {
        try checkPath(url, directory: false)
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        try require(descriptor >= 0, "Could not open the fixed mouse driver file")
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var attributes = stat()
        try require(fstat(descriptor, &attributes) == 0
                    && (attributes.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG)
                    && attributes.st_size >= 0 && attributes.st_size <= off_t(maximum),
                    "The opened mouse driver file is not a bounded regular file")
        let data = try handle.read(upToCount: maximum + 1) ?? Data()
        try require(data.count <= maximum, "A mouse driver file exceeded its size bound")
        return data
    }

    private func publish(_ name: String, object: [String: Any]) throws {
        try require(["request-1.json", "request-2.json", "finished.json"].contains(name),
                    "Only fixed mouse protocol outputs may be written")
        try checkPath(control, directory: true)
        let temporary = control.appendingPathComponent(name + ".pending")
        let destination = control.appendingPathComponent(name)
        let descriptor = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                                     S_IRUSR | S_IWUSR)
        try require(descriptor >= 0, "Could not exclusively create a mouse protocol file")
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close(); Darwin.unlink(temporary.path) }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try require(data.count <= 8_192, "The mouse request exceeds its size bound")
        try handle.write(contentsOf: data)
        try handle.synchronize()
        // Publish a completed file atomically without replacing an older one.
        try require(Darwin.link(temporary.path, destination.path) == 0,
                    "Could not publish the exclusive mouse protocol file")
    }

    private func currentRunner(allowRetirementUntil retirementDeadline: Double? = nil) throws -> NSRunningApplication? {
        let matches = NSRunningApplication.runningApplications(withBundleIdentifier: runnerIdentifier)
        if matches.count > 1 {
            recordIdentityFailure("registry", checks: ["registryUnique": false, "driverStarted": started,
                                                       "boundRunnerPresent": runner != nil])
        }
        try require(matches.count <= 1, "The fixed mouse runner is ambiguous")
        guard let current = matches.first else { return nil }
        let bundleURL = current.bundleURL
        let executableURL = current.executableURL
        let currentPID = current.processIdentifier
        let processNotTerminated = !current.isTerminated
        let instanceMatches = runner.map { current.isEqual($0) } ?? false
        let pidMatches = boundRunnerPID.map { currentPID == $0 } ?? false
        let observed = ProcessInfo.processInfo.systemUptime
        // Only stop may observe this terminal transition. FINISHED has already
        // proved released input. The same owned instance and frozen positive PID
        // may retire with terminated or missing metadata, never as a signal target.
        if let retirementDeadline, let boundRunnerPID, let finishedObservedAt,
           started && ready && finishedAt != nil && finishedAcknowledged && !protocolFailed && !gestureRunning,
           boundRunnerPID > 0 && instanceMatches && pidMatches,
           (!processNotTerminated || (bundleURL == nil && executableURL == nil)),
           finishedObservedAt < observed && observed <= retirementDeadline {
            var observations = evidence["runnerRetirementObservations"] as? [[String: Any]] ?? []
            try require(observations.count < 161, "The terminal mouse runner observation exceeded its bound")
            observations.append([
                "runnerPID": Int(boundRunnerPID), "observedRunnerPID": Int(currentPID),
                "observedSystemUptime": observed,
                "finishedObservedSystemUptime": finishedObservedAt, "registryCount": matches.count,
                "boundRunnerPIDMatches": pidMatches, "boundRunnerInstanceMatches": instanceMatches,
                "bundleURLMissing": bundleURL == nil, "executableURLMissing": executableURL == nil,
                "finishedAcknowledged": true, "finishedPublished": true, "gestureOutstanding": false,
                "processNotTerminated": processNotTerminated,
                "retirementReason": processNotTerminated ? "identity-urls-unavailable" : "terminated"
            ])
            evidence["runnerRetirementObservations"] = observations
            retirementObserved = true
            return nil
        }
        let checks: [String: Bool] = [
            "driverStarted": started, "processNotTerminated": processNotTerminated, "currentPIDPositive": currentPID > 0,
            "bundlePathMatches": bundleURL?.standardizedFileURL.path == runnerBundle.path,
            "resolvedBundlePathMatches": bundleURL?.resolvingSymlinksInPath().path == runnerBundle.path,
            "executablePathMatches": executableURL?.standardizedFileURL.path == runnerExecutable.path,
            "resolvedExecutablePathMatches": executableURL?.resolvingSymlinksInPath().path == runnerExecutable.path
        ]
        let recordedChecks = checks.merging([
            "boundRunnerPresent": runner != nil, "boundRunnerPIDMatches": pidMatches,
            "boundRunnerInstanceMatches": instanceMatches,
            "bundleURLMissing": bundleURL == nil, "executableURLMissing": executableURL == nil
        ]) { _, value in value }
        let identityMatches = checks.values.allSatisfy { $0 }
        if !identityMatches {
            recordIdentityFailure("process-identity", checks: recordedChecks,
                                  observedRunnerPID: currentPID, observedSystemUptime: observed)
        }
        try require(identityMatches,
                    "The mouse runner process has an unexpected identity")
        if runner != nil {
            if !pidMatches || !instanceMatches {
                recordIdentityFailure("bound-runner", checks: recordedChecks,
                                      observedRunnerPID: currentPID, observedSystemUptime: observed)
            }
            try require(pidMatches && instanceMatches, "The owned mouse runner instance or PID changed")
        } else {
            try require(boundRunnerPID == nil, "The mouse runner PID was already bound")
            runner = current
            boundRunnerPID = currentPID
            evidence["runnerPID"] = Int(currentPID)
        }
        return current
    }

    private func recordIdentityFailure(_ check: String, checks: [String: Bool],
                                       observedRunnerPID: pid_t? = nil, observedSystemUptime: Double? = nil) {
        evidence["runnerIdentityFailureCount"] = (evidence["runnerIdentityFailureCount"] as? Int ?? 0) + 1
        var failures = evidence["runnerIdentityFailures"] as? [[String: Any]] ?? []
        // Retain bounded PID/Boolean observations, never unexpected path strings.
        if failures.count < 8 {
            failures.append(["check": check, "checks": checks,
                "boundRunnerPID": boundRunnerPID.map { Int($0) as Any } ?? NSNull(),
                "observedRunnerPID": observedRunnerPID.map { Int($0) as Any } ?? NSNull(),
                "observedSystemUptime": observedSystemUptime ?? ProcessInfo.processInfo.systemUptime])
            evidence["runnerIdentityFailures"] = failures
        }
    }

    private func refreshMarkers() throws {
        let data = try readBounded(control.appendingPathComponent("xcodebuild.log"), maximum: 8 * 1_024 * 1_024)
        let end = data.lastIndex(of: 0x0a).map { data.index(after: $0) } ?? data.startIndex
        guard let log = String(data: data[..<end], encoding: .utf8) else {
            throw issue("The mouse driver log is not UTF-8")
        }
        let lines = log.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init).filter { $0.hasPrefix("LEMULIP_MOUSE_") }
        try require(lines.count >= markerLines.count && Array(lines.prefix(markerLines.count)) == markerLines,
                    "The retained mouse marker history changed")
        try require(lines.count <= 7, "The mouse runner exceeded its bounded marker count")
        for line in lines.dropFirst(markerLines.count) {
            guard let separator = line.firstIndex(of: " ") else {
                throw issue("A mouse marker has no JSON witness")
            }
            let marker = String(line[..<separator].dropFirst("LEMULIP_MOUSE_".count))
            let payload = Data(line[line.index(after: separator)...].utf8)
            try require(payload.count <= 8_192, "A mouse marker exceeded its size bound")
            guard let witness = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
                throw issue("A mouse marker witness is not a JSON object")
            }
            try validateMarker(marker, witness: witness)
            markerLines.append(line)
            var receipts = evidence["markerReceipts"] as? [[String: Any]] ?? []
            let observed = ProcessInfo.processInfo.systemUptime
            receipts.append(["marker": marker, "line": line, "witness": witness,
                             "observedSystemUptime": observed])
            evidence["markerReceipts"] = receipts
            if marker == "FINISHED" { finishedObservedAt = observed }
        }
        try require(!protocolFailed, "The public XCTest mouse driver reported failure")
    }

    private func validateMarker(_ marker: String, witness: [String: Any]) throws {
        let baseKeys: Set<String> = [
            "schema", "case", "nonce", "systemUptime", "runnerPID", "leftButtonReportedDown", "hidLeftButtonReportedDown",
            "rightButtonReportedDown", "centerButtonReportedDown", "escapeKeyReportedDown", "hidEscapeKeyReportedDown",
            "modifierFlags", "hidModifierFlags"
        ]
        var keys = baseKeys
        if marker == "BEGIN" || marker == "END" {
            keys.formUnion(["requestIndex", "phase", "sourcePID", "targetPID"])
        }
        if marker == "BEGIN" {
            keys.formUnion(["sourceWindowFrame", "targetWindowFrame", "sourceScreenPoint", "targetScreenPoint"])
        }
        if marker == "FINISHED" { keys.insert("requestCount") }
        try require(["READY", "BEGIN", "END", "FINISHED", "FAILED"].contains(marker)
                    && Set(witness.keys) == keys && witness["nonce"] as? String == nonce
                    && witness["case"] as? String == caseName,
                    "The mouse marker has an unexpected schema, action or nonce")
        let schema = try number(witness, "schema")
        let time = try number(witness, "systemUptime")
        let pid = try number(witness, "runnerPID")
        try require(schema == 1 && pid > 0 && pid <= Double(Int32.max) && pid.rounded() == pid
                    && time >= startedAt && time >= lastMarkerTime
                    && time <= ProcessInfo.processInfo.systemUptime
                    && (!finishedAcknowledged && !protocolFailed),
                    "A mouse marker has an invalid process, timestamp or terminal order")
        if let boundRunnerPID {
            try require(pid == Double(boundRunnerPID), "A mouse witness belongs to another runner PID")
        }
        for key in ["leftButtonReportedDown", "hidLeftButtonReportedDown", "rightButtonReportedDown",
                    "centerButtonReportedDown", "escapeKeyReportedDown", "hidEscapeKeyReportedDown"] {
            _ = try boolean(witness, key)
        }
        for key in ["modifierFlags", "hidModifierFlags"] {
            let flags = try number(witness, key)
            try require(flags >= 0 && flags <= Double(UInt32.max) && flags.rounded() == flags,
                        "A mouse witness contains invalid modifier flags")
        }
        switch marker {
        case "READY":
            try require(!ready && markerLines.isEmpty && time <= lifetimeExpires, "The mouse READY marker is out of order")
            try requireReleasedInput(witness)
            ready = true
        case "BEGIN", "END":
            let indexValue = try number(witness, "requestIndex")
            try require(ready && indexValue >= 1 && indexValue <= 2 && indexValue.rounded() == indexValue,
                        "The mouse gesture marker has an invalid request index")
            let index = Int(indexValue)
            try require(index <= requests.count, "The mouse runner acted without a published request")
            let request = requests[index - 1]
            let sourcePID = try number(witness, "sourcePID")
            let targetPID = try number(witness, "targetPID")
            try require(witness["phase"] as? String == request.phase
                        && sourcePID == Double(request.sourcePID) && targetPID == Double(request.targetPID)
                        && time >= request.created && time <= request.expires,
                        "The mouse gesture witness does not match its exact bounded request")
            let previous = markerLines.last?.split(separator: " ", maxSplits: 1).first.map(String.init)
            if marker == "BEGIN" {
                try require(index == completedRequests + 1
                            && (previous == "LEMULIP_MOUSE_READY" || previous == "LEMULIP_MOUSE_END"),
                            "The mouse BEGIN marker is out of order")
                for field in ["sourceWindowFrame", "targetWindowFrame", "sourceScreenPoint", "targetScreenPoint"] {
                    try validateGeometryWitness(witness, request: request.object, field: field)
                }
            } else {
                try require(index == completedRequests + 1 && previous == "LEMULIP_MOUSE_BEGIN",
                            "The mouse END marker is out of order")
            }
            try requireReleasedInput(witness)
            if marker == "END" {
                completedRequests += 1
                evidence["completedRequestCount"] = completedRequests
            }
        case "FINISHED":
            let count = try number(witness, "requestCount")
            try require(ready && finishedAt != nil && time >= (finishedAt ?? .infinity)
                        && !gestureRunning && count == Double(requests.count),
                        "The mouse FINISHED marker does not match this observer's completion")
            try requireReleasedInput(witness)
            finishedAcknowledged = true
        case "FAILED":
            protocolFailed = true
        default:
            throw issue("The mouse marker is not supported")
        }
        lastMarkerTime = time
    }

    private func requireReleasedInput(_ witness: [String: Any]) throws {
        for key in ["leftButtonReportedDown", "hidLeftButtonReportedDown", "rightButtonReportedDown",
                    "centerButtonReportedDown", "escapeKeyReportedDown", "hidEscapeKeyReportedDown"] {
            try require(try !boolean(witness, key), "The mouse runner marker reports held input at an action boundary")
        }
        let relevant: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
        for key in ["modifierFlags", "hidModifierFlags"] {
            let flags = UInt64(try number(witness, key))
            try require(flags & relevant.rawValue == 0, "The mouse runner marker reports a held modifier")
        }
    }

    private func validateGeometryWitness(_ witness: [String: Any], request: [String: Any], field: String) throws {
        let requestField: String
        switch field {
        case "sourceWindowFrame": requestField = "sourceFrame"
        case "targetWindowFrame": requestField = "targetFrame"
        case "sourceScreenPoint": requestField = "sourcePoint"
        default: requestField = "targetPoint"
        }
        guard let actual = witness[field] as? [String: Any], let expected = request[requestField] as? [String: Any] else {
            throw issue("A mouse gesture geometry witness is missing")
        }
        let keys: Set<String> = field.hasSuffix("Frame") ? ["x", "y", "width", "height"] : ["x", "y"]
        try require(Set(actual.keys) == keys && Set(expected.keys) == keys,
                    "A mouse gesture geometry witness has unexpected fields")
        for key in keys {
            let observed = try number(actual, key)
            let requested = try number(expected, key)
            try require(abs(observed - requested) <= 1, "The XCTest gesture geometry differs from the measured request")
        }
    }

    private func waitForReady(expiresAt: Double) async throws {
        let deadline = min(expiresAt, startedAt + 60)
        while ProcessInfo.processInfo.systemUptime < deadline {
            let live = try currentRunner()
            try refreshMarkers()
            try require(process.isRunning, "The mouse driver exited before its READY handshake")
            if ready, let live, let boundRunnerPID {
                let receipts = evidence["markerReceipts"] as? [[String: Any]] ?? []
                let witness = receipts.first?["witness"] as? [String: Any] ?? [:]
                let witnessPID = try number(witness, "runnerPID")
                try require(live.processIdentifier == boundRunnerPID
                            && witnessPID == Double(boundRunnerPID),
                            "The READY witness has no matching live runner")
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw issue("The mouse driver did not become ready within its bounded wait")
    }

    func start(expiresAt: Double) async throws {
        let now = ProcessInfo.processInfo.systemUptime
        try require(!started && expiresAt.isFinite && now < expiresAt,
                    "The mouse driver must start within this case's bounded lifetime")
        try require(NSRunningApplication.runningApplications(withBundleIdentifier: runnerIdentifier).isEmpty,
                    "The fixed mouse runner appeared before this observer started it")
        let descriptor = Darwin.open(control.appendingPathComponent("xcodebuild.log").path,
                                     O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        try require(descriptor >= 0, "Could not exclusively create the mouse driver log")
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        logHandle = handle
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.currentDirectoryURL = directory
        process.arguments = [
            "xcodebuild", "test-without-building", "-xctestrun", testRun.path, "-destination", "platform=macOS",
            "-only-testing:QualityReview/NativeDragMouseTests/testMouseThroughPublicAPI",
            "-parallel-testing-enabled", "NO", "-test-timeouts-enabled", "YES",
            "-default-test-execution-time-allowance", "150", "-maximum-test-execution-time-allowance", "150"
        ]
        process.standardOutput = handle
        process.standardError = handle
        startedAt = now
        lifetimeExpires = min(expiresAt, now + 150)
        try process.run()
        started = true
        evidence["processPID"] = Int(process.processIdentifier)
        evidence["startedSystemUptime"] = startedAt
        evidence["expiresSystemUptime"] = lifetimeExpires
        evidence["status"] = "waiting-for-ready"
        try await waitForReady(expiresAt: lifetimeExpires)
        evidence["status"] = "ready"
    }

    private func validateApplication(_ app: NSRunningApplication, application: URL, identifier: String,
                                     bundleName: String, executable: String) throws {
        let expected = directory.appendingPathComponent(bundleName, isDirectory: true)
        let expectedExecutable = expected.appendingPathComponent("Contents/MacOS/" + executable)
        try require(application.standardizedFileURL.path == expected.path, "The mouse request names an unexpected application")
        try checkPath(expected, directory: true)
        try checkPath(expectedExecutable, directory: false)
        let matches = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
        try require(matches.count == 1 && matches.first?.processIdentifier == app.processIdentifier
                    && !app.isTerminated && app.processIdentifier > 0
                    && app.bundleIdentifier == identifier
                    && app.bundleURL?.standardizedFileURL.path == expected.path
                    && app.bundleURL?.resolvingSymlinksInPath().path == expected.path
                    && app.executableURL?.standardizedFileURL.path == expectedExecutable.path
                    && app.executableURL?.resolvingSymlinksInPath().path == expectedExecutable.path,
                    "The mouse request application has an unexpected live identity")
    }

    private func rectangle(_ value: CGRect) throws -> [String: Double] {
        let fields = ["x": Double(value.minX), "y": Double(value.minY),
                      "width": Double(value.width), "height": Double(value.height)]
        try require(fields.values.allSatisfy(\.isFinite) && value.width > 0 && value.height > 0,
                    "The mouse request contains an invalid window frame")
        return fields
    }

    private func point(_ value: CGPoint, within frame: CGRect) throws -> [String: Double] {
        try require(value.x.isFinite && value.y.isFinite && frame.contains(value),
                    "The mouse request point is outside its measured window")
        let onScreen = NSScreen.screens.contains { screen in
            guard let identifier = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return CGDisplayBounds(CGDirectDisplayID(identifier.uint32Value)).contains(value)
        }
        try require(onScreen, "The mouse request point is outside every active screen")
        return ["x": Double(value.x), "y": Double(value.y)]
    }

    func requestGesture(source: NSRunningApplication, application: URL, sourcePoint: CGPoint, targetPoint: CGPoint,
                        sourceFrame: CGRect, target: NSRunningApplication, targetApplication: URL, targetFrame: CGRect,
                        phase: String, destinationHold: Double, expiresAt: Double) async throws {
        try require(started && ready && !gestureRunning && !protocolFailed && finishedAt == nil && process.isRunning,
                    "Require this case's live idle mouse runner")
        guard (try currentRunner()) != nil, let boundRunnerPID else {
            throw issue("The mouse runner disappeared before its request")
        }
        try refreshMarkers()
        let index = requests.count + 1
        try require(caseName.hasPrefix("xctest-") && index <= 2 && phase == (index == 1 ? "cancel" : "fresh")
                    && destinationHold == (index == 1 ? 5.0 : 1.0),
                    "Only the fixed cancellation and fresh-drop gestures may be requested")
        try validateApplication(source, application: application, identifier: sourceIdentifier,
                                bundleName: "Native Drag Source.app", executable: "NativeDragSource")
        try validateApplication(target, application: targetApplication, identifier: targetIdentifier,
                                bundleName: "Native Drag Control.app", executable: "NativeDragControl")
        try require(NSWorkspace.shared.frontmostApplication?.processIdentifier == source.processIdentifier,
                    "The verified native source must be foreground before requesting its mouse gesture")
        let sourceFrameObject = try rectangle(sourceFrame), targetFrameObject = try rectangle(targetFrame)
        let sourcePointObject = try point(sourcePoint, within: sourceFrame)
        let targetPointObject = try point(targetPoint, within: targetFrame)
        let created = ProcessInfo.processInfo.systemUptime
        let expires = min(created + 20, min(expiresAt, lifetimeExpires))
        try require(expiresAt.isFinite && expires > created, "No bounded lifetime remains for the mouse request")
        let request: [String: Any] = [
            "schema": 1, "case": caseName, "nonce": nonce, "action": "click-drag-hold", "theme": "orchard",
            "requestIndex": index, "phase": phase, "runnerPID": Int(boundRunnerPID),
            "sourceBundleIdentifier": sourceIdentifier, "sourceApplicationPath": application.standardizedFileURL.path,
            "sourceExecutablePath": application.appendingPathComponent("Contents/MacOS/NativeDragSource").standardizedFileURL.path,
            "sourceWindowTitle": "Native Drag Source", "sourcePID": Int(source.processIdentifier),
            "targetBundleIdentifier": targetIdentifier, "targetApplicationPath": targetApplication.standardizedFileURL.path,
            "targetExecutablePath": targetApplication.appendingPathComponent("Contents/MacOS/NativeDragControl").standardizedFileURL.path,
            "targetWindowTitle": "Native Drag Control", "targetPID": Int(target.processIdentifier),
            "coordinateSpace": "quartz-global-top-left", "sourcePoint": sourcePointObject, "targetPoint": targetPointObject,
            "sourceFrame": sourceFrameObject, "targetFrame": targetFrameObject,
            "initialHoldSeconds": 0.3, "velocityPointsPerSecond": 400, "destinationHoldSeconds": destinationHold,
            "createdSystemUptime": created, "expiresSystemUptime": expires
        ]
        do {
            try publish("request-\(index).json", object: request)
            requests.append(Request(index: index, phase: phase, created: created, expires: expires,
                                    sourcePID: source.processIdentifier, targetPID: target.processIdentifier, object: request))
            evidence["requests"] = requests.map(\.object)
            evidence["publishedRequestCount"] = requests.count
            evidence["status"] = "gesture-request-published"
            var publications = evidence["requestPublications"] as? [[String: Any]] ?? []
            publications.append(["requestIndex": index, "systemUptime": ProcessInfo.processInfo.systemUptime])
            evidence["requestPublications"] = publications
        } catch {
            evidence["status"] = "gesture-publication-failed"
            evidence["reason"] = String(describing: error)
            throw error
        }
        // Deliberately do not wait for BEGIN or END: the independent observer
        // must be able to post Escape while XCTest is inside its mouse hold.
    }

    func waitForGestureEnd(expiresAt: Double) async throws {
        guard let request = requests.last, gestureRunning else { throw issue("There is no outstanding mouse gesture") }
        let deadline = min(request.expires, min(expiresAt, lifetimeExpires))
        do {
            try refreshMarkers()
            if completedRequests == request.index {
                evidence["status"] = "gesture-ended"
                return
            }
            while ProcessInfo.processInfo.systemUptime < deadline {
                try require(process.isRunning && (try currentRunner()) != nil,
                            "The mouse runner exited during its bounded gesture")
                try refreshMarkers()
                if completedRequests == request.index {
                    evidence["status"] = "gesture-ended"
                    return
                }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            throw issue("The mouse driver did not report END within its bounded gesture")
        } catch {
            evidence["status"] = "gesture-failed"
            evidence["reason"] = String(describing: error)
            throw error
        }
    }

    func stop(gracefully: Bool) async -> Bool {
        let began = ProcessInfo.processInfo.systemUptime
        let deadline = began + 8
        var errors: [String] = []
        var finishPublished = false
        if started {
            do { _ = try currentRunner(); try refreshMarkers() }
            catch { errors.append(String(describing: error)) }
        }
        if gracefully && started && ready && !gestureRunning && !protocolFailed && errors.isEmpty {
            do {
                let finish: [String: Any] = ["schema": 1, "case": caseName, "nonce": nonce, "action": "finished",
                                            "requestCount": requests.count, "createdSystemUptime": began]
                try publish("finished.json", object: finish)
                finishedAt = began
                evidence["finished"] = finish
                finishPublished = true
            } catch { errors.append(String(describing: error)) }
        }
        var terminated = false
        var forced = false
        repeat {
            let now = ProcessInfo.processInfo.systemUptime
            var verifiedRunner: NSRunningApplication?
            // Read the terminal handshake before inspecting transient process
            // metadata. A partial or invalid marker still fails closed.
            if started {
                do { try refreshMarkers() }
                catch { if errors.isEmpty { errors.append(String(describing: error)) } }
            }
            do {
                verifiedRunner = try currentRunner(
                    allowRetirementUntil: finishPublished && errors.isEmpty ? deadline : nil)
            }
            catch { if errors.isEmpty { errors.append(String(describing: error)) } }
            let registryEmpty = NSRunningApplication.runningApplications(withBundleIdentifier: runnerIdentifier).isEmpty
            if !process.isRunning && registryEmpty { break }
            if !retirementObserved && !terminated && (!finishPublished || now >= began + 6) {
                if started && process.isRunning { process.terminate() }
                if let verifiedRunner { _ = verifiedRunner.terminate() }
                terminated = true
            }
            if !retirementObserved && !forced && now >= deadline - 1 {
                if started && process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
                if let verifiedRunner { _ = verifiedRunner.forceTerminate() }
                forced = true
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        } while ProcessInfo.processInfo.systemUptime < deadline
        let processStopped = !process.isRunning
        let registryEmpty = NSRunningApplication.runningApplications(withBundleIdentifier: runnerIdentifier).isEmpty
        let stopped = processStopped && registryEmpty
        if started {
            do { try refreshMarkers() }
            catch { if errors.isEmpty { errors.append(String(describing: error)) } }
            if processStopped { evidence["processExitStatus"] = process.terminationStatus }
        }
        completedNormally = finishPublished && finishedAcknowledged && stopped && started
            && process.terminationStatus == 0 && errors.isEmpty && !terminated && !forced
        evidence["cleanup"] = [
            "stopConfirmed": stopped, "processStopped": processStopped, "runnerRegistryEmpty": registryEmpty,
            "finishedPublished": finishPublished, "finishedAcknowledged": finishedAcknowledged,
            "normalCompletion": completedNormally, "terminationRequested": terminated, "forceTerminationRequested": forced,
            "gestureOutstanding": gestureRunning, "runnerRetirementObserved": retirementObserved, "timeoutSeconds": 8,
            "elapsedSeconds": ProcessInfo.processInfo.systemUptime - began, "errors": errors
        ]
        evidence["status"] = completedNormally ? "completed" : (stopped ? "stopped" : "stop-failed")
        if stopped { try? logHandle?.close(); logHandle = nil }
        return stopped
    }
}
