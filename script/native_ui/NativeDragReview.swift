import AppKit
import ApplicationServices
import CryptoKit
import Foundation

// A separate, explicitly interactive evidence probe. ReadOnlyAXSnapshot stays
// read-only. This executable never requests or changes any macOS permission.
// Usage: NativeDragReview <the prepare_native_ui.py review directory>
private enum DragReviewIssue: Error, CustomStringConvertible {
    case blocked(String)
    case failed(String)
    var description: String {
        switch self { case .blocked(let text), .failed(let text): return text }
    }
}

private enum DragReviewTheme: String, CaseIterable {
    case orchard, pistachio, lemonade
}

@MainActor
private final class DragReview {
    private let identifier = "app.lemulip.NativeUIReview"
    private let directory: URL
    private let theme: DragReviewTheme
    private var bundle: URL!
    private var folder: URL!
    private var output: URL?
    private var reviewApp: NSRunningApplication?
    private var finderApp: NSRunningApplication?
    private var reviewWindow: AXUIElement?
    private var finderWindow: AXUIElement?
    private var originals: [String: Data] = [:]
    private var inputNames: Set<String> = []
    private var mouseDown = false
    private var pointer = CGPoint.zero
    private var events: [[String: Any]] = []
    private let expiresAt = ProcessInfo.processInfo.systemUptime + 110
    var record: [String: Any] = [
        "schema": 1, "status": "not-run",
        "gestureOutcomesVerified": false, "outlineVisualReviewRequired": true,
        "outlineBehaviorVerified": false, "permissionRequested": false,
        "scope": "Real Finder drag; held entry, exit, re-entry, Escape and drop frames. Visual review is separate."
    ]

    init(directory: URL, theme: DragReviewTheme) {
        self.directory = directory.standardizedFileURL.resolvingSymlinksInPath()
        self.theme = theme
        record["theme"] = theme.rawValue
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
        default: throw DragReviewIssue.failed("AX read failed for \(key): \(error.rawValue)")
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

    private func wait(_ message: String, seconds: Double = 8, until condition: () throws -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        repeat {
            if try condition() { return }
            try await pause(0.1)
        } while ProcessInfo.processInfo.systemUptime < deadline
        throw DragReviewIssue.failed(message)
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
        bundle = directory.appendingPathComponent("Lemulip Native UI Review.app", isDirectory: true)
        folder = directory.appendingPathComponent("Fixtures/FinderDrop/" + theme.rawValue, isDirectory: true)
        let evidenceRoot = directory.appendingPathComponent("NativeDragEvidence", isDirectory: true)
        for url in [bundle!, folder!, evidenceRoot] {
            try require(url.standardizedFileURL.path == url.resolvingSymlinksInPath().path,
                        "Symlinked review targets are not allowed")
        }
        try require(try evidenceRoot.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true,
                    "The fixed evidence root is unavailable")
        let infoData = try Data(contentsOf: bundle.appendingPathComponent("Contents/Info.plist"))
        let info = try PropertyListSerialization.propertyList(from: infoData, options: [], format: nil) as? [String: Any]
        try require(info?["CFBundleIdentifier"] as? String == identifier && info?["CFBundleExecutable"] as? String == "Lemulip",
                    "The target is not the separately staged production application")
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
            for key in ["sourceCommit", "sourceTree", "architecture", "stagedGUI_SHA256", "compiledTestSourceSHA256",
                        "nativeDragReviewSourceSHA256"] {
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
        let list = try appNodes()
        let rows = try list.filter { try text($0, kAXRoleAttribute) == kAXButtonRole }
        var observed: Set<String> = []
        for name in inputNames {
            let matches = try rows.filter { try names($0).contains("Remove " + name) }
            if matches.count > 1 { return false }
            if matches.count == 1 { observed.insert(name) }
        }
        let count = try list.filter {
            guard try text($0, kAXRoleAttribute) == kAXStaticTextRole else { return false }
            return try names($0).contains("\(expected.count) Selected")
        }
        return observed == expected && count.count == 1
    }

    private func requireHit(_ point: CGPoint, owner: pid_t) throws {
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &element)
        guard result == .success, let element else { throw DragReviewIssue.failed("Could not identify the native pointer target") }
        try require(try pid(element) == owner, "Another process covers the intended native pointer target")
    }

    private func mouse(_ type: CGEventType, at point: CGPoint) throws {
        try require(ProcessInfo.processInfo.systemUptime < expiresAt, "The bounded native drag review timed out")
        try assertTargets()
        try require(CGDisplayBounds(CGMainDisplayID()).contains(point), "Refusing a pointer event outside the observed display")
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else {
            throw DragReviewIssue.failed("Could not create the native pointer event")
        }
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        event.post(tap: .cghidEventTap)
        pointer = point
        if type == .leftMouseDown { mouseDown = true }
        if type == .leftMouseUp { mouseDown = false }
    }

    private func key(_ code: CGKeyCode, flags: CGEventFlags = []) throws {
        try assertTargets()
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        try require(front == finderApp?.processIdentifier || front == reviewApp?.processIdentifier,
                    "Refusing a key event while another application is foreground")
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else {
                throw DragReviewIssue.failed("Could not create the native key event")
            }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
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

    private func sourcePoint(_ input: URL) async throws -> CGPoint {
        try assertTargets()
        try await focusFinderWindow()
        try await wait("Finder did not become foreground") {
            NSWorkspace.shared.frontmostApplication?.processIdentifier == self.finderApp?.processIdentifier
        }
        let source = try unique(finderNodes(), role: kAXImageRole, name: input.lastPathComponent)
        let rect = try frame(source)
        let point = CGPoint(x: rect.midX, y: rect.midY)
        try require(CGDisplayBounds(CGMainDisplayID()).contains(rect), "The source Finder icon is not fully onscreen")
        try requireHit(point, owner: finderApp!.processIdentifier)
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
              try pid(window) == finder.processIdentifier else {
            throw DragReviewIssue.failed("The fixed Finder window is unavailable")
        }
        // Earlier result-handoff tests may leave another Finder window open.
        // Raise this fixture window only, preserving the exposed drop target.
        finder.activate(options: [])
        try require(AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success,
                    "Could not raise the exact fixture Finder window")
        try await wait("The fixture Finder window did not become foreground") {
            NSWorkspace.shared.frontmostApplication?.processIdentifier == finder.processIdentifier
        }
    }

    private func capture(_ name: String) async throws {
        guard let output else { throw DragReviewIssue.failed("Evidence destination is not ready") }
        try assertTargets()
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
            "time": ISO8601DateFormatter().string(from: Date()), "workspaceAXLabels": labels
        ]
        events.append(event)
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
        try validate()
        let permissions = ["accessibility": AXIsProcessTrusted(), "postEvents": CGPreflightPostEventAccess(),
                           "screenCapture": CGPreflightScreenCaptureAccess()]
        record["preflight"] = permissions
        record["displayPreferencesAtStart"] = observedDisplayPreferences
        guard permissions.values.allSatisfy({ $0 }) else {
            throw DragReviewIssue.blocked("Existing authorization is insufficient; no permission was requested or changed")
        }
        try require(NSRunningApplication.runningApplications(withBundleIdentifier: identifier).isEmpty,
                    "The isolated review application must be stopped before the standalone probe")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["-language", "en", "-theme", theme.rawValue, "-wheelEnabled", "NO",
                                   "-completionPresentation", "quiet", "-NSQuitAlwaysKeepsWindows", "NO"]
        configuration.addsToRecentItems = false
        reviewApp = try await NSWorkspace.shared.openApplication(at: bundle, configuration: configuration)
        guard let app = reviewApp else { throw DragReviewIssue.failed("The staged app did not launch") }
        try require(app.bundleIdentifier == identifier && app.bundleURL?.resolvingSymlinksInPath().path == bundle.path,
                    "The launch did not produce the exact staged app")
        try await wait("The production review window did not appear") { try self.window(in: app, title: "Lemulip") != nil }
        reviewWindow = try window(in: app, title: "Lemulip")
        let screen = CGDisplayBounds(CGMainDisplayID())
        try require(screen.width >= 900 && screen.height >= 700, "The display is too small for this bounded two-window observation")
        try arrange(reviewWindow!, owner: app.processIdentifier,
                    rect: CGRect(x: screen.minX + 16, y: screen.minY + 32, width: min(920, screen.width - 32), height: 560))
        let existing = try fixture("Existing")
        let single = try fixture("Single")
        _ = try await NSWorkspace.shared.open([existing], withApplicationAt: bundle, configuration: configuration)
        try await wait("The production app did not accept the sole initial fixture") {
            try self.workspaceContains([existing.lastPathComponent])
        }
        try require(NSWorkspace.shared.open(folder), "Finder could not open the isolated fixture folder")
        try await wait("Finder is unavailable") {
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").count == 1
        }
        finderApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
        try assertTargets()
        try await wait("The exact fixture Finder window did not appear") {
            try self.window(in: self.finderApp!, title: self.folder.lastPathComponent) != nil
        }
        finderWindow = try window(in: finderApp!, title: folder.lastPathComponent)
        try await focusFinderWindow()
        try await wait("Finder is not foreground for choosing its view") {
            NSWorkspace.shared.frontmostApplication?.processIdentifier == self.finderApp?.processIdentifier
        }
        try key(18, flags: .maskCommand) // Native Command-1: Icon view.
        try await wait("Finder did not expose all four exact fixture icons") {
            let icons = try self.finderNodes().filter { try self.text($0, kAXRoleAttribute) == kAXImageRole }
            return try self.inputNames.allSatisfy { name in try icons.filter { try self.names($0).contains(name) }.count == 1 }
        }
        let appElements = try appNodes()
        let header = try frame(unique(appElements, role: kAXStaticTextRole, name: "1 Selected"))
        let clear = try frame(unique(appElements, role: kAXButtonRole, name: "Clear"))
        let enter = CGPoint(x: (header.minX + clear.maxX) / 2, y: header.minY - 4)
        let outside = CGPoint(x: enter.x, y: header.minY - 24)
        let finderTop = header.maxY + 100
        try arrange(finderWindow!, owner: finderApp!.processIdentifier,
                    rect: CGRect(x: screen.minX + 8, y: finderTop, width: min(920, screen.width - 16),
                                 height: min(360, screen.maxY - finderTop - 12)))
        try await pause(0.3)
        let actualFinderFrame = try frame(finderWindow!)
        try require(!actualFinderFrame.contains(enter) && !actualFinderFrame.contains(outside),
                    "The fixture Finder window covers the observed target")
        try requireHit(enter, owner: app.processIdentifier)
        try requireHit(outside, owner: app.processIdentifier)
        record["targetGeometry"] = ["header": NSStringFromRect(header), "entryInTopPadding": NSStringFromPoint(enter),
                                    "outside": NSStringFromPoint(outside), "reviewWindow": NSStringFromRect(try frame(reviewWindow!)),
                                    "finderWindow": NSStringFromRect(try frame(finderWindow!))]

        let source = try await sourcePoint(single)
        try requireHit(enter, owner: app.processIdentifier)
        try requireHit(outside, owner: app.processIdentifier)
        try await capture("00-before-drag")
        try mouse(.leftMouseDown, at: source)
        try await pause(0.3)
        try await moveHeld(to: enter)
        try await capture("01-enter-top-padding")
        try await moveHeld(to: outside)
        try await capture("02-leave-file-area")
        try await moveHeld(to: enter)
        try await capture("03-reenter-top-padding")
        try key(53) // Escape while the same drag is still held.
        try await pause(0.15)
        try mouse(.leftMouseUp, at: enter)
        try await pause(0.7)
        try require(try workspaceContains([existing.lastPathComponent]), "Escape did not cancel the actual Finder drag")
        try verifyOriginals()
        try await capture("04-after-escape")

        let secondSource = try await sourcePoint(single)
        try requireHit(enter, owner: app.processIdentifier)
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
        let deadline = ProcessInfo.processInfo.systemUptime + 8
        var errors: [String] = []
        if mouseDown {
            try? key(53)
            // Always release this probe's own held button, even if a target
            // has exited and its normal identity guard now fails.
            if CGPreflightPostEventAccess(),
               let event = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                                   mouseCursorPosition: pointer, mouseButton: .left) {
                event.post(tap: .cghidEventTap)
                mouseDown = false
            } else {
                errors.append("Could not release this probe's held mouse button")
            }
        }
        var finderClosed = finderWindow == nil
        var finderRoot: AXUIElement?
        if let window = finderWindow, let finder = finderApp {
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
        } else if finderWindow != nil {
            errors.append("The fixture Finder owner is unavailable during cleanup")
        }
        // Terminate only the exact staged app launched by this probe.
        if let app = reviewApp, !app.isTerminated {
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
        record["stages"] = events
        record["cleanup"] = ["completed": errors.isEmpty, "leftButtonReportedDown": leftButtonDown,
                             "applicationStopped": applicationStopped, "fixtureFinderWindowClosed": finderClosed,
                             "fixedBundleRegistryEmpty": registryEmpty, "timeoutSeconds": 8, "errors": errors]
        return errors.isEmpty
    }

    func finish() throws {
        guard let output else { throw DragReviewIssue.failed("The per-theme evidence destination was not created") }
        let data = try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: output.appendingPathComponent("report.json"), options: .atomic)
    }
}

@main
private struct NativeDragReview {
    @MainActor
    static func main() async {
        guard CommandLine.arguments.count == 2 else {
            FileHandle.standardError.write(Data("Usage: NativeDragReview <isolated review directory>\n".utf8))
            exit(2)
        }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        var aggregate: [String: Any] = [
            "schema": 2, "status": "not-run", "expectedThemes": DragReviewTheme.allCases.map(\.rawValue),
            "allThemesCaptured": false, "gestureOutcomesVerified": false,
            "outlineVisualReviewRequired": true, "outlineBehaviorVerified": false,
            "permissionRequested": false,
            "scope": "The same real Finder drag sequence in three fixed themes; visual outline review is separate."
        ]
        do {
            guard directory.lastPathComponent == "lemulip-native-ui" else {
                throw DragReviewIssue.failed("Use the isolated native UI staging directory")
            }
            let destination = directory.appendingPathComponent("NativeDragEvidence", isDirectory: true)
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
            for theme in DragReviewTheme.allCases {
                if let stopReason {
                    reports.append(["theme": theme.rawValue, "status": "not-run", "reason": stopReason])
                    continue
                }
                // A new object gives each theme its own fixtures, AX handles,
                // original-byte receipt and bounded 110-second run clock.
                let review = DragReview(directory: directory, theme: theme)
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
                for key in ["reason", "reportError", "gestureOutcomesVerified", "cleanup", "displayPreferencesAtStart"] {
                    if let value = review.record[key] { summary[key] = value }
                }
                reports.append(summary)
                for key in ["sourceCommit", "sourceTree", "architecture", "stagedGUI_SHA256",
                            "compiledTestSourceSHA256", "nativeDragReviewSourceSHA256"] {
                    if aggregate[key] == nil, let value = review.record[key] { aggregate[key] = value }
                }
            }
            let statuses = reports.compactMap { $0["status"] as? String }
            let captured = statuses.count == DragReviewTheme.allCases.count && statuses.allSatisfy { $0 == "captured" }
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
