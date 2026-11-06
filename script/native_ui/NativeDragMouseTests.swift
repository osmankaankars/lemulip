import XCTest
import AppKit
import ApplicationServices
import CoreFoundation
import Darwin
import Foundation

// A separate diagnostic test. The observer starts this runner before either
// application's input and keeps it alive in both Quartz and XCTest cases.
// Only the two explicitly requested public mouse gestures can generate input.
@MainActor
final class NativeDragMouseTests: XCTestCase {
    private struct Gesture {
        let index: Int
        let phase: String
        let sourcePID: pid_t
        let targetPID: pid_t
        let sourcePoint: CGPoint
        let targetPoint: CGPoint
        let sourceFrame: CGRect
        let targetFrame: CGRect
        let created: Double
        let expires: Double
        let destinationHold: Double
    }

    private let sourceIdentifier = "app.lemulip.NativeDragSource"
    private let targetIdentifier = "app.lemulip.NativeDragControl"
    private let runnerIdentifier = "app.lemulip.NativeDragMouseTests.xctrunner"
    private let modifiers: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
    private var caseName = "unavailable"
    private var nonce = "unavailable"

    func testMouseThroughPublicAPI() async {
        continueAfterFailure = false
        executionTimeAllowance = 150
        let testStarted = ProcessInfo.processInfo.systemUptime
        let deadline = testStarted + 150
        do {
            let configuredCase = ProcessInfo.processInfo.environment["LEMULIP_MOUSE_DRIVER_CASE"] ?? ""
            try require(["quartz-first", "xctest-first", "xctest-second", "quartz-second",
                         "quartz-sync-first", "quartz-deferred-first", "quartz-deferred-second", "quartz-sync-second"].contains(configuredCase),
                        "The mouse test requires one fixed comparison case")
            caseName = configuredCase
            let targetApplication = ReviewConfiguration.application.standardizedFileURL
            let root = targetApplication.deletingLastPathComponent()
            let sourceApplication = root.appendingPathComponent("Native Drag Source.app", isDirectory: true)
            let control = root.appendingPathComponent("MouseControl/" + caseName, isDirectory: true)
            let runnerBundle = root.appendingPathComponent(
                "MouseDerivedData/Build/Products/Debug/QualityReview-Runner.app", isDirectory: true)
            try require(root.lastPathComponent == "lemulip-native-ui"
                        && targetApplication.lastPathComponent == "Native Drag Control.app"
                        && ReviewConfiguration.fixtures.standardizedFileURL.path
                            == root.appendingPathComponent("Fixtures", isDirectory: true).path,
                        "Require the fixed isolated applications and fixture root")
            for directory in [root, control, sourceApplication, targetApplication, ReviewConfiguration.fixtures, runnerBundle] {
                try checkPath(directory, directory: true)
            }
            let current = NSRunningApplication.current
            try require(current.bundleIdentifier == runnerIdentifier
                        && current.bundleURL?.standardizedFileURL.path == runnerBundle.path
                        && current.bundleURL?.resolvingSymlinksInPath().path == runnerBundle.path
                        && current.executableURL?.resolvingSymlinksInPath().path
                            == runnerBundle.appendingPathComponent("Contents/MacOS/QualityReview-Runner").path,
                        "The mouse test must run in the fixed prebuilt runner")
            guard let configuration = try readObject(control.appendingPathComponent("configuration.json"),
                                                     missingAllowed: false, maximum: 4_096),
                  Set(configuration.keys) == Set(["schema", "case", "nonce"]),
                  let configuredNonce = configuration["nonce"] as? String else {
                throw issue("The exact mouse configuration is unavailable")
            }
            try require(try number(configuration, "schema") == 1
                        && configuration["case"] as? String == caseName
                        && configuredNonce.count == 32
                        && configuredNonce.allSatisfy({ "0123456789abcdef".contains($0) }),
                        "The mouse configuration has an invalid schema, case or nonce")
            nonce = configuredNonce
            for name in ["request-1.json", "request-2.json", "finished.json"] {
                try requireAbsent(control.appendingPathComponent(name))
                try requireAbsent(control.appendingPathComponent(name + ".pending"))
            }
            let readyState = inputState()
            try requireReleasedInput(readyState)
            try marker("READY", state: readyState)

            var completed = 0
            var previousEnd = testStarted
            while ProcessInfo.processInfo.systemUptime < deadline {
                if let finish = try readObject(control.appendingPathComponent("finished.json"), missingAllowed: true) {
                    try validateFinish(finish, completed: completed, previousEnd: previousEnd)
                    let finalState = inputState()
                    try requireReleasedInput(finalState)
                    try marker("FINISHED", fields: ["requestCount": completed], state: finalState)
                    return
                }
                if completed == 0 {
                    try require(try readObject(control.appendingPathComponent("request-2.json"), missingAllowed: true) == nil,
                                "The second mouse request appeared before the first gesture")
                }
                if completed < 2,
                   let request = try readObject(control.appendingPathComponent("request-\(completed + 1).json"),
                                                missingAllowed: true) {
                    try require(caseName.hasPrefix("xctest-"), "The idle Quartz comparison runner must not receive a gesture")
                    let gesture = try validateRequest(request, index: completed + 1, root: root,
                                                      previousEnd: previousEnd, deadline: deadline)
                    try requireApplications(gesture, sourceApplication: sourceApplication,
                                            targetApplication: targetApplication, requireSourceForeground: true)
                    let source = XCUIApplication(url: sourceApplication)
                    let target = XCUIApplication(url: targetApplication)
                    let sourceWindows = source.windows.matching(identifier: "Native Drag Source")
                    let targetWindows = target.windows.matching(identifier: "Native Drag Control")
                    try require(sourceWindows.count == 1 && targetWindows.count == 1,
                                "The requested source and destination windows must be unique")
                    let sourceWindow = sourceWindows.element(boundBy: 0)
                    let targetWindow = targetWindows.element(boundBy: 0)
                    let sourceFrame = sourceWindow.frame
                    let targetFrame = targetWindow.frame
                    try requireSameFrame(sourceFrame, gesture.sourceFrame)
                    try requireSameFrame(targetFrame, gesture.targetFrame)

                    // Both coordinates reference the source window. The second
                    // offset may lie outside it, but must remain on the measured
                    // destination and screen. No destination click or activation.
                    let origin = sourceWindow.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
                    let sourceCoordinate = origin.withOffset(CGVector(dx: gesture.sourcePoint.x - sourceFrame.minX,
                                                                      dy: gesture.sourcePoint.y - sourceFrame.minY))
                    let targetCoordinate = origin.withOffset(CGVector(dx: gesture.targetPoint.x - sourceFrame.minX,
                                                                      dy: gesture.targetPoint.y - sourceFrame.minY))
                    let sourceScreenPoint = sourceCoordinate.screenPoint
                    let targetScreenPoint = targetCoordinate.screenPoint
                    try requireSamePoint(sourceScreenPoint, gesture.sourcePoint)
                    try requireSamePoint(targetScreenPoint, gesture.targetPoint)
                    try requireOnScreen(sourceScreenPoint)
                    try requireOnScreen(targetScreenPoint)
                    try requireApplications(gesture, sourceApplication: sourceApplication,
                                            targetApplication: targetApplication, requireSourceForeground: true)
                    let now = ProcessInfo.processInfo.systemUptime
                    let nominalSeconds = 0.3 + hypot(Double(sourceScreenPoint.x - targetScreenPoint.x),
                                                    Double(sourceScreenPoint.y - targetScreenPoint.y)) / 400
                        + gesture.destinationHold
                    try require(now + nominalSeconds + 1 < gesture.expires,
                                "The public mouse gesture no longer fits its fixed bounded request")
                    let beginState = inputState()
                    try requireReleasedInput(beginState)
                    let fields: [String: Any] = [
                        "requestIndex": gesture.index, "phase": gesture.phase,
                        "sourcePID": Int(gesture.sourcePID), "targetPID": Int(gesture.targetPID)
                    ]
                    var beginFields = fields
                    beginFields["sourceWindowFrame"] = frameObject(sourceFrame)
                    beginFields["targetWindowFrame"] = frameObject(targetFrame)
                    beginFields["sourceScreenPoint"] = pointObject(sourceScreenPoint)
                    beginFields["targetScreenPoint"] = pointObject(targetScreenPoint)
                    try marker("BEGIN", fields: beginFields, state: beginState)

                    // The only input operation in this test. It is synchronous;
                    // the independent observer can post its global Escape while
                    // this call is holding the mouse at the destination.
                    sourceCoordinate.click(forDuration: 0.3, thenDragTo: targetCoordinate,
                                           withVelocity: XCUIGestureVelocity(rawValue: 400),
                                           thenHoldForDuration: gesture.destinationHold)

                    let completedAt = ProcessInfo.processInfo.systemUptime
                    let endState = inputState()
                    try require(completedAt <= gesture.expires, "The public mouse gesture exceeded its 20-second request")
                    try requireApplications(gesture, sourceApplication: sourceApplication,
                                            targetApplication: targetApplication, requireSourceForeground: false)
                    try requireReleasedInput(endState)
                    // END witnesses the public call's return and the released
                    // input state, not successful Escape cancellation or a drop.
                    try marker("END", fields: fields, state: endState, timestamp: completedAt)
                    completed += 1
                    previousEnd = completedAt
                    continue
                }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            throw issue("The observer did not finish the mouse runner within its 150-second lifetime")
        } catch {
            try? marker("FAILED", state: inputState())
            XCTFail("Native mouse comparison failed: \(error)")
        }
    }

    private func validateRequest(_ request: [String: Any], index: Int, root: URL,
                                 previousEnd: Double, deadline: Double) throws -> Gesture {
        let keys: Set<String> = [
            "schema", "case", "nonce", "action", "theme", "requestIndex", "phase", "runnerPID",
            "sourceBundleIdentifier", "sourceApplicationPath", "sourceExecutablePath", "sourceWindowTitle", "sourcePID",
            "targetBundleIdentifier", "targetApplicationPath", "targetExecutablePath", "targetWindowTitle", "targetPID",
            "coordinateSpace", "sourcePoint", "targetPoint", "sourceFrame", "targetFrame",
            "initialHoldSeconds", "velocityPointsPerSecond", "destinationHoldSeconds",
            "createdSystemUptime", "expiresSystemUptime"
        ]
        let phase = index == 1 ? "cancel" : "fresh"
        let source = root.appendingPathComponent("Native Drag Source.app", isDirectory: true)
        let target = root.appendingPathComponent("Native Drag Control.app", isDirectory: true)
        try require(Set(request.keys) == keys && request["case"] as? String == caseName
                    && request["nonce"] as? String == nonce && request["action"] as? String == "click-drag-hold"
                    && request["theme"] as? String == "orchard" && request["phase"] as? String == phase
                    && request["sourceBundleIdentifier"] as? String == sourceIdentifier
                    && request["targetBundleIdentifier"] as? String == targetIdentifier
                    && request["sourceApplicationPath"] as? String == source.path
                    && request["targetApplicationPath"] as? String == target.path
                    && request["sourceExecutablePath"] as? String == source.appendingPathComponent("Contents/MacOS/NativeDragSource").path
                    && request["targetExecutablePath"] as? String == target.appendingPathComponent("Contents/MacOS/NativeDragControl").path
                    && request["sourceWindowTitle"] as? String == "Native Drag Source"
                    && request["targetWindowTitle"] as? String == "Native Drag Control"
                    && request["coordinateSpace"] as? String == "quartz-global-top-left",
                    "The mouse request does not identify this exact fixed gesture")
        let schema = try number(request, "schema")
        let requestedIndex = try number(request, "requestIndex")
        let runnerPID = try number(request, "runnerPID")
        let initialHold = try number(request, "initialHoldSeconds")
        let velocity = try number(request, "velocityPointsPerSecond")
        let destinationHold = try number(request, "destinationHoldSeconds")
        let created = try number(request, "createdSystemUptime")
        let expires = try number(request, "expiresSystemUptime")
        try require(schema == 1 && requestedIndex == Double(index) && runnerPID == Double(getpid())
                    && initialHold == 0.3 && velocity == 400 && destinationHold == (index == 1 ? 5.0 : 1.0)
                    && created >= previousEnd && created <= ProcessInfo.processInfo.systemUptime
                    && expires > created && expires - created <= 20 && expires <= deadline,
                    "The mouse request has invalid timing, protocol constants or runner identity")
        let sourcePID = try processID(request, "sourcePID")
        let targetPID = try processID(request, "targetPID")
        try require(sourcePID != targetPID && sourcePID != getpid() && targetPID != getpid(),
                    "The mouse request process identities are not distinct")
        let sourceFrame = try rectangle(request, "sourceFrame")
        let targetFrame = try rectangle(request, "targetFrame")
        let sourcePoint = try point(request, "sourcePoint")
        let targetPoint = try point(request, "targetPoint")
        try require(sourceFrame.contains(sourcePoint) && targetFrame.contains(targetPoint),
                    "The requested points are outside their measured windows")
        try requireOnScreen(sourcePoint)
        try requireOnScreen(targetPoint)
        return Gesture(index: index, phase: phase, sourcePID: sourcePID, targetPID: targetPID,
                       sourcePoint: sourcePoint, targetPoint: targetPoint, sourceFrame: sourceFrame, targetFrame: targetFrame,
                       created: created, expires: expires, destinationHold: destinationHold)
    }

    private func validateFinish(_ object: [String: Any], completed: Int, previousEnd: Double) throws {
        try require(Set(object.keys) == Set(["schema", "case", "nonce", "action", "requestCount", "createdSystemUptime"])
                    && object["case"] as? String == caseName && object["nonce"] as? String == nonce
                    && object["action"] as? String == "finished",
                    "The observer completion marker does not belong to this case")
        let schema = try number(object, "schema"), count = try number(object, "requestCount")
        let time = try number(object, "createdSystemUptime")
        try require(schema == 1 && count == Double(completed) && time >= previousEnd
                    && time <= ProcessInfo.processInfo.systemUptime,
                    "The observer completion marker has an invalid count or timestamp")
    }

    private func requireApplications(_ gesture: Gesture, sourceApplication: URL, targetApplication: URL,
                                     requireSourceForeground: Bool) throws {
        try require(ProcessInfo.processInfo.systemUptime < gesture.expires, "The mouse gesture request expired")
        try requireApplication(sourceApplication, identifier: sourceIdentifier, executable: "NativeDragSource",
                               pid: gesture.sourcePID)
        try requireApplication(targetApplication, identifier: targetIdentifier, executable: "NativeDragControl",
                               pid: gesture.targetPID)
        if requireSourceForeground {
            try require(NSWorkspace.shared.frontmostApplication?.processIdentifier == gesture.sourcePID,
                        "The native source must already be foreground; the mouse runner never activates it")
        }
    }

    private func requireApplication(_ application: URL, identifier: String, executable: String, pid: pid_t) throws {
        try checkPath(application, directory: true)
        let executableURL = application.appendingPathComponent("Contents/MacOS/" + executable)
        try checkPath(executableURL, directory: false)
        let matches = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
        guard matches.count == 1, let running = matches.first else {
            throw issue("A requested mouse application is missing or ambiguous")
        }
        try require(!running.isTerminated && running.processIdentifier == pid
                    && running.bundleURL?.standardizedFileURL.path == application.path
                    && running.bundleURL?.resolvingSymlinksInPath().path == application.path
                    && running.executableURL?.standardizedFileURL.path == executableURL.path
                    && running.executableURL?.resolvingSymlinksInPath().path == executableURL.path,
                    "A requested mouse application changed its live identity")
    }

    private func requireOnScreen(_ point: CGPoint) throws {
        let contained = NSScreen.screens.contains { screen in
            guard let identifier = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return CGDisplayBounds(CGDirectDisplayID(identifier.uint32Value)).contains(point)
        }
        try require(contained, "The requested mouse coordinate is outside every active display")
    }

    private func requireSameFrame(_ actual: CGRect, _ expected: CGRect) throws {
        let a = frameObject(actual), b = frameObject(expected)
        try require(a.values.allSatisfy(\.isFinite) && actual.width > 0 && actual.height > 0
                    && a.keys.allSatisfy({ abs(a[$0]! - b[$0]!) <= 1 }),
                    "The XCTest window frame differs from the observer's measured global frame")
    }

    private func requireSamePoint(_ actual: CGPoint, _ expected: CGPoint) throws {
        try require(actual.x.isFinite && actual.y.isFinite
                    && abs(actual.x - expected.x) <= 1 && abs(actual.y - expected.y) <= 1,
                    "The XCTest coordinate differs from the requested global point")
    }

    private func frameObject(_ frame: CGRect) -> [String: Double] {
        ["x": Double(frame.minX), "y": Double(frame.minY), "width": Double(frame.width), "height": Double(frame.height)]
    }

    private func pointObject(_ point: CGPoint) -> [String: Double] {
        ["x": Double(point.x), "y": Double(point.y)]
    }

    private func rectangle(_ object: [String: Any], _ name: String) throws -> CGRect {
        guard let value = object[name] as? [String: Any], Set(value.keys) == Set(["x", "y", "width", "height"]) else {
            throw issue("The mouse protocol has an invalid rectangle: " + name)
        }
        let x = try number(value, "x"), y = try number(value, "y")
        let width = try number(value, "width"), height = try number(value, "height")
        try require(width > 0 && height > 0, "The mouse protocol has a nonpositive window size")
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func point(_ object: [String: Any], _ name: String) throws -> CGPoint {
        guard let value = object[name] as? [String: Any], Set(value.keys) == Set(["x", "y"]) else {
            throw issue("The mouse protocol has an invalid point: " + name)
        }
        return CGPoint(x: try number(value, "x"), y: try number(value, "y"))
    }

    private func processID(_ object: [String: Any], _ name: String) throws -> pid_t {
        let value = try number(object, name)
        try require(value > 0 && value <= Double(Int32.max) && value.rounded() == value,
                    "The mouse protocol has an invalid process ID")
        return pid_t(value)
    }

    private func inputState() -> [String: Any] {
        [
            "leftButtonReportedDown": CGEventSource.buttonState(.combinedSessionState, button: .left),
            "hidLeftButtonReportedDown": CGEventSource.buttonState(.hidSystemState, button: .left),
            "rightButtonReportedDown": CGEventSource.buttonState(.combinedSessionState, button: .right),
            "centerButtonReportedDown": CGEventSource.buttonState(.combinedSessionState, button: .center),
            "escapeKeyReportedDown": CGEventSource.keyState(.combinedSessionState, key: 53),
            "hidEscapeKeyReportedDown": CGEventSource.keyState(.hidSystemState, key: 53),
            "modifierFlags": CGEventSource.flagsState(.combinedSessionState).rawValue,
            "hidModifierFlags": CGEventSource.flagsState(.hidSystemState).rawValue
        ]
    }

    private func requireReleasedInput(_ state: [String: Any]) throws {
        for name in ["leftButtonReportedDown", "hidLeftButtonReportedDown", "rightButtonReportedDown",
                     "centerButtonReportedDown", "escapeKeyReportedDown", "hidEscapeKeyReportedDown"] {
            try require(state[name] as? Bool == false, "The mouse action boundary requires released input")
        }
        for name in ["modifierFlags", "hidModifierFlags"] {
            guard let flags = state[name] as? UInt64 else { throw issue("The input-state flags are unavailable") }
            try require(flags & modifiers.rawValue == 0, "A modifier is held at the mouse action boundary")
        }
    }

    private func marker(_ action: String, fields: [String: Any] = [:], state: [String: Any], timestamp: Double? = nil) throws {
        var witness = state
        witness.merge(fields) { _, value in value }
        witness["schema"] = 1
        witness["case"] = caseName
        witness["nonce"] = nonce
        witness["systemUptime"] = timestamp ?? ProcessInfo.processInfo.systemUptime
        witness["runnerPID"] = Int(getpid())
        let data = try JSONSerialization.data(withJSONObject: witness, options: [.sortedKeys])
        var line = Data(("LEMULIP_MOUSE_" + action + " ").utf8)
        line.append(data)
        line.append(0x0a)
        try FileHandle.standardOutput.write(contentsOf: line)
    }

    private func readObject(_ url: URL, missingAllowed: Bool, maximum: Int = 8_192) throws -> [String: Any]? {
        var attributes = stat()
        if lstat(url.path, &attributes) != 0 {
            if missingAllowed && errno == ENOENT { return nil }
            throw issue("A required mouse protocol file is unavailable")
        }
        try checkPath(url, directory: false)
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        try require(descriptor >= 0, "Could not open a mouse protocol file")
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        try require(fstat(descriptor, &attributes) == 0
                    && (attributes.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG)
                    && attributes.st_size > 0 && attributes.st_size <= off_t(maximum),
                    "The mouse protocol file is not a bounded regular file")
        let data = try handle.read(upToCount: maximum + 1) ?? Data()
        try require(data.count <= maximum, "The mouse protocol file grew beyond its size bound")
        guard String(data: data, encoding: .utf8) != nil,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw issue("The mouse protocol requires a UTF-8 JSON object")
        }
        return object
    }

    private func requireAbsent(_ url: URL) throws {
        var attributes = stat()
        try require(lstat(url.path, &attributes) != 0 && errno == ENOENT, "A mouse protocol output predates this runner")
    }

    private func checkPath(_ url: URL, directory: Bool) throws {
        try require(url.isFileURL && url.standardizedFileURL.path == url.resolvingSymlinksInPath().path,
                    "Symlinked mouse protocol paths are not allowed")
        var attributes = stat()
        try require(lstat(url.path, &attributes) == 0
                    && (attributes.st_mode & mode_t(S_IFMT)) == mode_t(directory ? S_IFDIR : S_IFREG),
                    "The mouse protocol path has the wrong file type")
    }

    private func number(_ object: [String: Any], _ name: String) throws -> Double {
        guard let value = object[name] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else {
            throw issue("The mouse protocol has an invalid numeric field: " + name)
        }
        return value.doubleValue
    }

    private func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw issue(message) }
    }

    private func issue(_ message: String) -> NSError {
        NSError(domain: "LemulipNativeMouseDriver", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
