import XCTest
import AppKit
import ApplicationServices
import CoreFoundation

// A separate diagnostic runner, never part of the 58 production UI tests.
// It reads one fixed Escape request and reports through stdout. The external
// observer owns the held mouse, target lifecycle, evidence and cleanup.
@MainActor
final class NativeDragKeyboardTests: XCTestCase {
    private let targetIdentifier = "app.lemulip.NativeDragControl"
    private let modifiers: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]

    func testEscapeThroughPublicKeyboardAPI() async {
        continueAfterFailure = false
        executionTimeAllowance = 120
        var nonce = "unavailable"
        do {
            let application = ReviewConfiguration.application.standardizedFileURL
            let root = application.deletingLastPathComponent()
            let control = root.appendingPathComponent("KeyboardControl", isDirectory: true)
            try require(root.lastPathComponent == "lemulip-native-ui"
                        && application.lastPathComponent == "Native Drag Control.app"
                        && ReviewConfiguration.fixtures.standardizedFileURL.path == root.appendingPathComponent("Fixtures", isDirectory: true).path,
                        "Require the fixed isolated control application and fixture root")
            for directory in [root, application, control, ReviewConfiguration.fixtures] {
                try checkPath(directory, directory: true)
            }
            guard let configuration = try readObject(control.appendingPathComponent("configuration.json"), partial: false),
                  let configuredNonce = configuration["nonce"] as? String else {
                throw issue("The fixed keyboard configuration is unavailable")
            }
            try require(try number(configuration, "schema") == 1
                        && configuredNonce.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil,
                        "The keyboard configuration has an invalid schema or nonce")
            nonce = configuredNonce
            marker("READY", nonce: nonce, timestamp: false)

            let request = try await waitForObject(control.appendingPathComponent("request.json"), seconds: 60)
            let created = try number(request, "createdSystemUptime")
            let expires = try number(request, "expiresSystemUptime")
            let pidNumber = try number(request, "targetPID")
            let schema = try number(request, "schema"), flags = try number(request, "flags")
            let keyCode = try number(request, "keyCode")
            try require(schema == 1 && flags == 0 && keyCode == 53
                        && request["nonce"] as? String == nonce && request["action"] as? String == "escape"
                        && request["theme"] as? String == "orchard"
                        && request["targetBundleIdentifier"] as? String == targetIdentifier
                        && request["targetApplicationPath"] as? String == application.path,
                        "The request must be this run's exact Orchard Escape action")
            try require(pidNumber > 0 && pidNumber <= Double(Int32.max) && pidNumber.rounded() == pidNumber
                        && created <= ProcessInfo.processInfo.systemUptime && expires > created && expires - created <= 20,
                        "The request has an invalid process or bounded lifetime")
            let targetPID = pid_t(pidNumber)
            let target = XCUIApplication(url: application)
            try requireLiveTarget(application, pid: targetPID, expires: expires)
            marker("BEGIN", nonce: nonce)
            // Validate again immediately before the only input operation. Do
            // not launch, activate, click, change focus or post a CG key here.
            try requireLiveTarget(application, pid: targetPID, expires: expires)
            target.typeKey(.escape, modifierFlags: [])
            try requireLiveTarget(application, pid: targetPID, expires: expires)
            let completedAt = ProcessInfo.processInfo.systemUptime
            marker("END", nonce: nonce)

            // Let the observer finish its held frame, release, fresh acceptance
            // check and cleanup before this XCTest runner tears down.
            let finished = try await waitForObject(control.appendingPathComponent("finished.json"), seconds: 30)
            let finishedAt = try number(finished, "createdSystemUptime")
            try require(try number(finished, "schema") == 1 && finished["nonce"] as? String == nonce
                        && finished["action"] as? String == "finished"
                        && finishedAt >= completedAt && finishedAt <= ProcessInfo.processInfo.systemUptime,
                        "The observer completion marker does not belong to this run")
        } catch {
            marker("FAILED", nonce: nonce)
            XCTFail("Native keyboard comparison failed: \(error)")
        }
    }

    private func requireLiveTarget(_ application: URL, pid: pid_t, expires: Double) throws {
        try require(ProcessInfo.processInfo.systemUptime < expires, "The Escape request expired")
        let matches = NSRunningApplication.runningApplications(withBundleIdentifier: targetIdentifier)
        guard matches.count == 1, let running = matches.first else {
            throw issue("The exact control application is missing or ambiguous")
        }
        try require(!running.isTerminated && running.processIdentifier == pid
                    && running.bundleURL?.standardizedFileURL.path == application.path
                    && running.bundleURL?.resolvingSymlinksInPath().path == application.path
                    && NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                    "The verified control application must remain foreground")
        try require(CGEventSource.buttonState(.combinedSessionState, button: .left)
                    && CGEventSource.flagsState(.combinedSessionState).intersection(modifiers).isEmpty
                    && !CGEventSource.keyState(.combinedSessionState, key: 53),
                    "Require the existing held mouse with clear modifiers and Escape up")
    }

    private func waitForObject(_ url: URL, seconds: Double) async throws -> [String: Any] {
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        while ProcessInfo.processInfo.systemUptime < deadline {
            if let value = try readObject(url, partial: true) { return value }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw issue("The fixed keyboard protocol file did not become ready before its deadline")
    }

    private func readObject(_ url: URL, partial: Bool) throws -> [String: Any]? {
        if !FileManager.default.fileExists(atPath: url.path) {
            if partial { return nil }
            throw issue("A required keyboard protocol file is missing")
        }
        try checkPath(url, directory: false)
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        try require((values.fileSize ?? -1) >= 0 && (values.fileSize ?? 4097) <= 4096,
                    "The keyboard protocol file exceeds its size bound")
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 4097) ?? Data()
        try require(data.count <= 4096, "The keyboard protocol file grew beyond its size bound")
        guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw issue("The keyboard protocol is not UTF-8 JSON")
        }
        if partial && (text.isEmpty || (text.first == "{" && text.last != "}")) { return nil }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw issue("The keyboard protocol requires a JSON object")
        }
        return object
    }

    private func checkPath(_ url: URL, directory: Bool) throws {
        try require(url.standardizedFileURL.path == url.resolvingSymlinksInPath().path,
                    "Symlinked keyboard protocol paths are not allowed")
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
        try require(values.isSymbolicLink == false && (directory ? values.isDirectory == true : values.isRegularFile == true),
                    "The keyboard protocol path has the wrong file type")
    }

    private func number(_ object: [String: Any], _ key: String) throws -> Double {
        guard let value = object[key] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else {
            throw issue("The keyboard protocol has a missing or invalid numeric field: " + key)
        }
        return value.doubleValue
    }

    private func marker(_ phase: String, nonce: String, timestamp: Bool = true) {
        let time = timestamp ? " \(ProcessInfo.processInfo.systemUptime)" : ""
        FileHandle.standardOutput.write(Data(("LEMULIP_KEYBOARD_\(phase) \(nonce)\(time)\n").utf8))
    }

    private func require(_ condition: Bool, _ message: String) throws { if !condition { throw issue(message) } }
    private func issue(_ message: String) -> NSError {
        NSError(domain: "LemulipNativeKeyboardDriver", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
