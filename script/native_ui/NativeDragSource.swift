import AppKit
import CryptoKit
import Darwin
import Foundation

// A standard, copy-only AppKit source for the isolated drag comparison. Escape
// is observed only in NSApplication.sendEvent and is always dispatched onward.
// A source-ended operation of .none is not, by itself, proof of cancellation.
private enum SourceIssue: Error, CustomStringConvertible {
    case invalid(String)
    var description: String { switch self { case .invalid(let message): return message } }
}

private func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw SourceIssue.invalid(message) }
}

private let activationCases = ["raise-first", "no-raise-first", "no-raise-second", "raise-second"]

private func pointJSON(_ point: NSPoint) -> [String: Double] {
    ["x": Double(point.x), "y": Double(point.y)]
}

private func rectJSON(_ rect: NSRect) -> [String: Double] {
    ["x": Double(rect.minX), "y": Double(rect.minY),
     "width": Double(rect.width), "height": Double(rect.height)]
}

private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func readRegularFile(_ url: URL, maximumBytes: Int) throws -> Data {
    try require(url.standardizedFileURL.path == url.resolvingSymlinksInPath().path,
                "Symlinked source inputs are not allowed")
    let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    try require(descriptor >= 0, "A fixed source input could not be opened")
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    defer { try? handle.close() }
    var before = stat()
    try require(Darwin.fstat(descriptor, &before) == 0
                && before.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG)
                && before.st_size > 0 && before.st_size <= maximumBytes,
                "Require a bounded, nonempty regular source input")
    var data = Data()
    while data.count <= maximumBytes {
        let chunk = try handle.read(upToCount: min(65_536, maximumBytes + 1 - data.count)) ?? Data()
        if chunk.isEmpty { break }
        data.append(chunk)
    }
    var after = stat()
    try require(Darwin.fstat(descriptor, &after) == 0 && data.count == before.st_size
                && data.count <= maximumBytes && after.st_size == before.st_size
                && after.st_ino == before.st_ino && after.st_dev == before.st_dev,
                "A fixed source input changed while being read")
    return data
}

private struct SourceConfiguration {
    let sourceCase: String
    let root: URL
    let bundle: URL
    let folder: URL
    let traceURL: URL
    let single: URL
    let originals: [String: Data]
    let provenance: [String: String]
    let requestedFrameCG: NSRect
    let requestedPointCG: NSPoint

    var activationCase: String? { activationCases.contains(sourceCase) ? sourceCase : nil }

    var activationBinding: [String: String] {
        guard let activationCase else { return [:] }
        return ["activationCase": activationCase,
                "targetRaisePolicy": activationCase.hasPrefix("no-raise-") ? "omitted" : "present"]
    }

    init() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let keys: Set<String> = ["--case", "--frame-x", "--frame-y", "--frame-width",
                                 "--frame-height", "--point-x", "--point-y"]
        try require(arguments.count == keys.count * 2, "Require the exact native-source argument set")
        var values: [String: String] = [:]
        for index in stride(from: 0, to: arguments.count, by: 2) {
            let key = arguments[index]
            try require(keys.contains(key) && values[key] == nil, "Unknown or duplicate native-source argument")
            values[key] = arguments[index + 1]
        }
        sourceCase = values["--case"] ?? ""
        try require((["appkit-first", "appkit-second"] + activationCases).contains(sourceCase), "Unknown native-source case")
        func number(_ key: String) throws -> CGFloat {
            guard let value = values[key].flatMap(Double.init), value.isFinite else {
                throw SourceIssue.invalid("Native-source geometry must contain finite numbers")
            }
            return CGFloat(value)
        }
        requestedFrameCG = try NSRect(x: number("--frame-x"), y: number("--frame-y"),
                                      width: number("--frame-width"), height: number("--frame-height"))
        requestedPointCG = try NSPoint(x: number("--point-x"), y: number("--point-y"))
        try require(requestedFrameCG.width > 0 && requestedFrameCG.height > 0
                    && requestedFrameCG.contains(requestedPointCG), "The source point must be inside its window")

        bundle = Bundle.main.bundleURL.standardizedFileURL
        root = bundle.deletingLastPathComponent()
        try require(root.lastPathComponent == "lemulip-native-ui"
                    && bundle.lastPathComponent == "Native Drag Source.app"
                    && Bundle.main.bundleIdentifier == "app.lemulip.NativeDragSource"
                    && Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String == "NativeDragSource"
                    && Bundle.main.object(forInfoDictionaryKey: "NSPrincipalClass") as? String == "NativeDragSourceApplication",
                    "Require the exact isolated AppKit source bundle")
        folder = root.appendingPathComponent("Fixtures/FinderDrop/orchard", isDirectory: true)
        let evidencePrefix = activationCases.contains(sourceCase)
            ? "NativeDragControlEvidence-Capture-ax-only-Lifecycle-appkit-Activation-"
            : "NativeDragControlEvidence-Capture-ax-only-Lifecycle-appkit-Source-"
        let evidence = root.appendingPathComponent(evidencePrefix + sourceCase + "/orchard", isDirectory: true)
        for directory in [root, bundle, folder, evidence] {
            try require(directory.standardizedFileURL.path == directory.resolvingSymlinksInPath().path
                        && (try directory.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true,
                        "The fixed source directories must already exist without symlinks")
        }
        traceURL = evidence.appendingPathComponent("source.jsonl")
        let inputs = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent != ".DS_Store" }
        try require(inputs.count == 4, "Require exactly four fixed source fixtures")
        var bytes: [String: Data] = [:]
        var singleURL: URL?
        for role in ["Existing", "Single", "Multi-A", "Multi-B"] {
            let pattern = "^" + role + "-[a-f0-9]{32}\\.txt$"
            let matching = inputs.filter { $0.lastPathComponent.range(of: pattern, options: .regularExpression) != nil }
            try require(matching.count == 1, "A fixed source fixture role is missing or ambiguous")
            bytes[matching[0].lastPathComponent] = try readRegularFile(matching[0], maximumBytes: 65_535)
            if role == "Single" { singleURL = matching[0] }
        }
        guard let singleURL else { throw SourceIssue.invalid("The Single source fixture is unavailable") }
        single = singleURL
        originals = bytes

        let provenanceData = try readRegularFile(root.appendingPathComponent("provenance.json"), maximumBytes: 262_144)
        guard let raw = try JSONSerialization.jsonObject(with: provenanceData) as? [String: Any] else {
            throw SourceIssue.invalid("The staged source provenance is invalid")
        }
        var binding: [String: String] = [:]
        for key in ["nativeDragSourceSourceSHA256", "sourceGUI_SHA256", "observerExperimentCommit",
                    "observerExperimentTree", "sourceCommit", "sourceTree", "architecture"] {
            guard let value = raw[key] as? String else { throw SourceIssue.invalid("Source provenance is incomplete") }
            binding[key] = value
            if key != "architecture" {
                let count = key.hasSuffix("SHA256") ? 64 : 40
                try require(value.range(of: "^[a-f0-9]{\(count)}$", options: .regularExpression) != nil,
                            "Source provenance contains a malformed digest")
            }
        }
        try require(binding["sourceCommit"] == "d821d7343675e2850705d141ef9b3b93a6aee945"
                    && binding["sourceTree"] == "425baa28f00ec24551dd70c0cc874a75fa3be0c1",
                    "The source comparison requires the pinned C12 product baseline")
        #if arch(arm64)
        let architecture = "arm64"
        #elseif arch(x86_64)
        let architecture = "x86_64"
        #else
        let architecture = "unsupported"
        #endif
        try require(binding["architecture"] == architecture && architecture != "unsupported",
                    "The source architecture does not match its provenance")
        let executable = bundle.appendingPathComponent("Contents/MacOS/NativeDragSource")
        try require(Bundle.main.executableURL?.standardizedFileURL.path == executable.path,
                    "The source executable is outside the fixed bundle")
        try require(try sha256(readRegularFile(executable, maximumBytes: 134_217_728)) == binding["sourceGUI_SHA256"],
                    "The running source executable does not match its staged digest")
        provenance = binding
    }

    func assertOriginals() throws {
        try require(folder.path == folder.resolvingSymlinksInPath().path, "The source fixture folder changed identity")
        let actual = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent != ".DS_Store" }
        try require(Set(actual.map(\.lastPathComponent)) == Set(originals.keys), "The source fixture file set changed")
        for (name, data) in originals {
            try require(try readRegularFile(folder.appendingPathComponent(name), maximumBytes: 65_535) == data,
                        "A source fixture's original bytes changed")
        }
    }

    func originalState() -> [String: Any] {
        do {
            try assertOriginals()
            return ["originalBytesUnchanged": true, "fixtureFileSetUnchanged": true]
        } catch {
            return ["originalBytesUnchanged": false, "fixtureFileSetUnchanged": false,
                    "originalCheckError": String(describing: error)]
        }
    }
}

// AppKit screen points use a bottom-left origin; the observer supplies Quartz /
// AX global points with a top-left origin. Bind the conversion to the actual
// primary NSScreen/CGDisplay pair instead of assuming either origin is zero.
@MainActor
private struct ScreenMapping {
    let appKitFrame: NSRect
    let quartzFrame: CGRect

    init() throws {
        let display = CGMainDisplayID()
        guard let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display
        }) else { throw SourceIssue.invalid("The primary AppKit screen could not be matched to its display") }
        appKitFrame = screen.frame
        quartzFrame = CGDisplayBounds(display)
        try require(abs(appKitFrame.width - quartzFrame.width) < 0.5
                    && abs(appKitFrame.height - quartzFrame.height) < 0.5,
                    "The screen coordinate spaces do not have matching logical dimensions")
    }

    func appKit(_ point: NSPoint) -> NSPoint {
        NSPoint(x: appKitFrame.minX + point.x - quartzFrame.minX,
                y: appKitFrame.maxY - (point.y - quartzFrame.minY))
    }

    func quartz(_ point: NSPoint) -> NSPoint {
        NSPoint(x: quartzFrame.minX + point.x - appKitFrame.minX,
                y: quartzFrame.minY + appKitFrame.maxY - point.y)
    }

    func appKit(_ rect: NSRect) -> NSRect {
        let origin = appKit(NSPoint(x: rect.minX, y: rect.maxY))
        return NSRect(origin: origin, size: rect.size)
    }

    func quartz(_ rect: NSRect) -> NSRect {
        let origin = quartz(NSPoint(x: rect.minX, y: rect.maxY))
        return NSRect(origin: origin, size: rect.size)
    }
}

// Timestamp and serialize on receipt, but do not add disk synchronization to
// drag callbacks. Startup is flushed before input; the remaining bounded buffer
// is flushed on owned termination, a fatal error, or the watchdog. The observer
// reads AX during input and the comparator reads this trace after cleanup.
private final class SourceTrace: @unchecked Sendable {
    private let handle: FileHandle
    private let sourceCase: String
    private let activationBinding: [String: String]
    private let lock = NSLock()
    private var buffer = Data()
    private var count = 0
    private var byteCount = 0
    private let maximumRecords = 10_000
    private let maximumBytes = 8 * 1_024 * 1_024

    init(url: URL, sourceCase: String, activationBinding: [String: String] = [:]) throws {
        self.sourceCase = sourceCase
        self.activationBinding = activationBinding
        let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                                     S_IRUSR | S_IWUSR)
        try require(descriptor >= 0, "Could not exclusively create the fixed source trace")
        handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    private func encoded(_ event: String, _ fields: [String: Any]) throws -> Data {
        var value = fields
        value["schema"] = 1
        value["event"] = event
        value["sourceCase"] = sourceCase
        value["dragSourceKind"] = "native-appkit"
        value.merge(activationBinding.mapValues { $0 as Any }) { _, fixed in fixed }
        value["recordIndex"] = count
        value["systemUptime"] = ProcessInfo.processInfo.systemUptime
        value["pid"] = Int(ProcessInfo.processInfo.processIdentifier)
        var data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        data.append(0x0a)
        return data
    }

    func record(_ event: String, _ fields: [String: Any] = [:]) {
        lock.lock()
        defer { lock.unlock() }
        do {
            let data = try encoded(event, fields)
            if count >= maximumRecords - 1 || byteCount + data.count > maximumBytes - 8_192 {
                buffer.append(try encoded("trace-limit", [:]))
                try flushLocked()
                Darwin.exit(2)
            }
            buffer.append(data)
            count += 1
            byteCount += data.count
        } catch { fatalTrace(error) }
    }

    func flush() {
        lock.lock()
        defer { lock.unlock() }
        do { try flushLocked() } catch { fatalTrace(error) }
    }

    private func flushLocked() throws {
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            buffer.removeAll(keepingCapacity: true)
        }
        try handle.synchronize()
    }

    private func fatalTrace(_ error: Error) -> Never {
        FileHandle.standardError.write(Data(("Native drag source trace failed: \(error)\n").utf8))
        Darwin.exit(2)
    }

    func fail(_ error: Error) -> Never {
        record("source-failed", ["reason": String(describing: error)])
        flush()
        Darwin.exit(2)
    }
}

@MainActor
private func applicationState(window: NSWindow? = nil, includeWindowDetails: Bool = false) -> [String: Any] {
    var fields: [String: Any] = ["applicationActive": NSApp.isActive,
                                "keyWindowNumber": NSApp.keyWindow.map { $0.windowNumber as Any } ?? NSNull()]
    if includeWindowDetails {
        let cursor = NSEvent.mouseLocation
        fields["mainWindowNumber"] = NSApp.mainWindow.map { $0.windowNumber as Any } ?? NSNull()
        fields["windowNumber"] = window.map { $0.windowNumber as Any } ?? NSNull()
        fields["windowIsKey"] = window.map { $0.isKeyWindow as Any } ?? NSNull()
        fields["windowIsMain"] = window.map { $0.isMainWindow as Any } ?? NSNull()
        fields["windowCanBecomeKey"] = window.map { $0.canBecomeKey as Any } ?? NSNull()
        fields["windowCanBecomeMain"] = window.map { $0.canBecomeMain as Any } ?? NSNull()
        fields["windowVisible"] = window.map { $0.isVisible as Any } ?? NSNull()
        fields["observedCursorScreen"] = ["x": Double(cursor.x), "y": Double(cursor.y)]
        fields["cursorCoordinateSpace"] = "AppKit-screen-bottom-left"
    }
    return fields
}

@MainActor
@objc(NativeDragSourceApplication)
private final class SourceApplication: NSApplication {
    var trace: SourceTrace?
    var recordsActivationState = false
    weak var observedWindow: NSWindow?

    override func sendEvent(_ event: NSEvent) {
        let received = ProcessInfo.processInfo.systemUptime
        if (event.type == .keyDown || event.type == .keyUp) && event.keyCode == 53 {
            var fields = applicationState(window: observedWindow, includeWindowDetails: recordsActivationState)
            fields.merge(["eventType": event.type == .keyDown ? "keyDown" : "keyUp",
                          "keyCode": 53, "eventTimestamp": event.timestamp,
                          "callbackSystemUptime": received, "modifierFlags": event.modifierFlags.rawValue,
                          "isRepeat": event.type == .keyDown && event.isARepeat,
                          "eventWindowNumber": event.windowNumber]) { _, value in value }
            trace?.record("escape-send-event", fields)
        }
        super.sendEvent(event)
    }
}

@MainActor
private final class SourceIconView: NSView, NSDraggingSource {
    let configuration: SourceConfiguration
    let trace: SourceTrace
    let mapping: ScreenMapping
    private let icon: NSImage
    private var originalMouseDown: NSEvent?
    private var sessionRequested = false
    private var session: NSDraggingSession?
    private(set) var sessionIndex = 0
    private var selected = false

    var sessionActive: Bool { sessionRequested }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(frame: NSRect, configuration: SourceConfiguration, trace: SourceTrace, mapping: ScreenMapping) {
        self.configuration = configuration
        self.trace = trace
        self.mapping = mapping
        icon = NSWorkspace.shared.icon(forFile: configuration.single.path)
        icon.size = frame.size
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(configuration.single.lastPathComponent)
        setAccessibilitySelected(false)
        setAccessibilityChildren([])
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        if selected {
            NSColor.selectedContentBackgroundColor.withAlphaComponent(0.3).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        }
        icon.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
    }

    override func mouseDown(with event: NSEvent) {
        guard !sessionRequested else { return }
        selected = true
        setAccessibilitySelected(true)
        needsDisplay = true
        window?.makeFirstResponder(self)
        originalMouseDown = event
        mouseRecord("source-mouse-down", event)
    }

    override func mouseUp(with event: NSEvent) {
        originalMouseDown = nil
        mouseRecord("source-mouse-up", event)
    }

    private func mouseRecord(_ name: String, _ event: NSEvent) {
        var fields = applicationState(window: window, includeWindowDetails: configuration.activationCase != nil)
        fields.merge(["selected": selected, "filename": configuration.single.lastPathComponent,
                      "eventTimestamp": event.timestamp, "locationInWindow": pointJSON(event.locationInWindow),
                      "windowNumber": event.windowNumber, "sessionIndex": sessionIndex]) { _, value in value }
        trace.record(name, fields)
    }

    override func mouseDragged(with event: NSEvent) {
        guard !sessionRequested, let mouseDown = originalMouseDown else { return }
        do {
            try configuration.assertOriginals()
            try require(sessionIndex < 2, "Only the two fixed source sessions are allowed")
            sessionIndex += 1
            sessionRequested = true
            originalMouseDown = nil
            let item = NSDraggingItem(pasteboardWriter: configuration.single as NSURL)
            item.setDraggingFrame(bounds, contents: icon)
            trace.record("source-session-requested", [
                "sessionIndex": sessionIndex, "filename": configuration.single.lastPathComponent,
                "originalMouseDownTimestamp": mouseDown.timestamp, "firstMouseDraggedTimestamp": event.timestamp,
                "originalBytesUnchanged": true, "fixtureFileSetUnchanged": true, "offeredOperationMask": 1
            ])
            let created = beginDraggingSession(with: [item], event: mouseDown, source: self)
            if sessionRequested { session = created }
            trace.record("source-session-created", callbackFields(created, point: NSEvent.mouseLocation,
                                                                  received: ProcessInfo.processInfo.systemUptime))
        } catch { trace.fail(error) }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // Finder may offer other operations. Deliberately offer copy only so
        // this diagnostic never asks a destination to move or delete fixtures.
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        let received = ProcessInfo.processInfo.systemUptime
        var fields = callbackFields(session, point: screenPoint, received: received)
        let originals = configuration.originalState()
        fields.merge(originals) { _, value in value }
        trace.record("source-will-begin", fields)
        if originals["originalBytesUnchanged"] as? Bool != true || originals["fixtureFileSetUnchanged"] as? Bool != true {
            trace.fail(SourceIssue.invalid("The original source fixtures changed before the native session"))
        }
    }

    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        let received = ProcessInfo.processInfo.systemUptime
        trace.record("source-moved", callbackFields(session, point: screenPoint, received: received))
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let received = ProcessInfo.processInfo.systemUptime
        var fields = callbackFields(session, point: screenPoint, received: received)
        fields["operationRawValue"] = Int(operation.rawValue)
        let originals = configuration.originalState()
        fields.merge(originals) { _, value in value }
        trace.record("source-ended", fields)
        self.session = nil
        sessionRequested = false
        originalMouseDown = nil
        if originals["originalBytesUnchanged"] as? Bool != true || originals["fixtureFileSetUnchanged"] as? Bool != true {
            trace.fail(SourceIssue.invalid("The original source fixtures changed during the native session"))
        }
    }

    private func callbackFields(_ session: NSDraggingSession, point: NSPoint, received: TimeInterval) -> [String: Any] {
        var fields = applicationState(window: window, includeWindowDetails: configuration.activationCase != nil)
        fields.merge([
            "callbackSystemUptime": received, "sessionIndex": sessionIndex,
            "sequenceNumber": session.draggingSequenceNumber, "filename": configuration.single.lastPathComponent,
            "callbackPointScreen": pointJSON(point), "callbackPointCoordinateSpace": "AppKit-screen-bottom-left",
            "observedCursorCG": pointJSON(mapping.quartz(NSEvent.mouseLocation)),
            "offeredOperationMask": Int(NSDragOperation.copy.rawValue),
            "pasteboardTypes": session.draggingPasteboard.types?.map(\.rawValue) ?? [],
            "animatesToStartingPositionsOnCancelOrFail": session.animatesToStartingPositionsOnCancelOrFail
        ]) { _, value in value }
        return fields
    }
}

@MainActor
private final class SourceDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let configuration: SourceConfiguration
    let trace: SourceTrace
    var window: NSWindow?
    var iconView: SourceIconView?
    var watchdog: DispatchSourceTimer?

    init(configuration: SourceConfiguration, trace: SourceTrace) {
        self.configuration = configuration
        self.trace = trace
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let mapping = try ScreenMapping()
            try require(mapping.quartzFrame.contains(configuration.requestedFrameCG),
                        "The source window must remain on the primary display")
            NSApp.setActivationPolicy(.regular)
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "Native Drag Source"
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.setFrame(mapping.appKit(configuration.requestedFrameCG), display: false)
            let content = NSView(frame: window.contentView?.bounds ?? .zero)
            window.contentView = content
            let pointInWindow = window.convertPoint(fromScreen: mapping.appKit(configuration.requestedPointCG))
            let pointInContent = content.convert(pointInWindow, from: nil)
            let imageFrame = NSRect(x: pointInContent.x - 24, y: pointInContent.y - 24, width: 48, height: 48)
            try require(content.bounds.contains(imageFrame), "The source icon must fit inside window content")
            let image = SourceIconView(frame: imageFrame, configuration: configuration, trace: trace, mapping: mapping)
            content.addSubview(image)
            self.window = window
            iconView = image
            if configuration.activationCase != nil {
                window.delegate = self
                (NSApp as? SourceApplication)?.observedWindow = window
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            content.layoutSubtreeIfNeeded()
            window.displayIfNeeded()

            let actualWindow = mapping.quartz(window.frame)
            let actualImage = mapping.quartz(window.convertToScreen(image.convert(image.bounds, to: nil)))
            let actualPoint = NSPoint(x: actualImage.midX, y: actualImage.midY)
            let requested = configuration.requestedFrameCG
            try require(abs(actualWindow.minX - requested.minX) <= 0.5
                        && abs(actualWindow.minY - requested.minY) <= 0.5
                        && abs(actualWindow.width - requested.width) <= 0.5
                        && abs(actualWindow.height - requested.height) <= 0.5
                        && abs(actualPoint.x - configuration.requestedPointCG.x) <= 0.5
                        && abs(actualPoint.y - configuration.requestedPointCG.y) <= 0.5,
                        "The native source did not preserve the supplied window and icon geometry")
            try configuration.assertOriginals()
            var fields: [String: Any] = configuration.provenance.mapValues { $0 as Any }
            fields.merge([
                "bundleIdentifier": "app.lemulip.NativeDragSource", "executableName": "NativeDragSource",
                "bundleName": "Native Drag Source.app", "sourceBundlePath": configuration.bundle.path,
                "stagingRoot": configuration.root.path, "windowTitle": window.title,
                "requestedWindowFrameCG": rectJSON(requested), "actualWindowFrameCG": rectJSON(actualWindow),
                "requestedSourcePointCG": pointJSON(configuration.requestedPointCG),
                "sourcePointCG": pointJSON(actualPoint), "imageFrameCG": rectJSON(actualImage),
                "geometryCoordinateSpace": "Quartz-global-top-left",
                "appKitDisplayFrame": rectJSON(mapping.appKitFrame), "quartzDisplayBounds": rectJSON(mapping.quartzFrame),
                "filename": configuration.single.lastPathComponent, "originalSHA256": configuration.originals.mapValues(sha256),
                "originalBytesUnchanged": true, "fixtureFileSetUnchanged": true,
                "offeredOperationMask": 1, "sendEventSubclassInstalled": true,
                "traceBuffering": "startup-and-termination-flush", "maximumLifetimeSeconds": 130
            ]) { _, value in value }
            if configuration.activationCase != nil {
                let received = ProcessInfo.processInfo.systemUptime
                fields.merge(applicationState(window: window, includeWindowDetails: true)) { _, value in value }
                fields["callbackSystemUptime"] = received
            }
            trace.record("source-ready", fields)
            trace.flush()
        } catch { trace.fail(error) }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        let received = ProcessInfo.processInfo.systemUptime
        var fields = applicationState(window: window, includeWindowDetails: configuration.activationCase != nil)
        if configuration.activationCase != nil { fields["callbackSystemUptime"] = received }
        trace.record("application-became-active", fields)
    }

    func applicationDidResignActive(_ notification: Notification) {
        let received = ProcessInfo.processInfo.systemUptime
        var fields = applicationState(window: window, includeWindowDetails: configuration.activationCase != nil)
        if configuration.activationCase != nil { fields["callbackSystemUptime"] = received }
        trace.record("application-resigned-active", fields)
    }

    private func recordWindowTransition(_ name: String, received: TimeInterval) {
        guard configuration.activationCase != nil else { return }
        var fields = applicationState(window: window, includeWindowDetails: true)
        fields["callbackSystemUptime"] = received
        trace.record(name, fields)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        let received = ProcessInfo.processInfo.systemUptime
        recordWindowTransition("window-became-key", received: received)
    }

    func windowDidResignKey(_ notification: Notification) {
        let received = ProcessInfo.processInfo.systemUptime
        recordWindowTransition("window-resigned-key", received: received)
    }

    func windowDidBecomeMain(_ notification: Notification) {
        let received = ProcessInfo.processInfo.systemUptime
        recordWindowTransition("window-became-main", received: received)
    }

    func windowDidResignMain(_ notification: Notification) {
        let received = ProcessInfo.processInfo.systemUptime
        recordWindowTransition("window-resigned-main", received: received)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        let received = ProcessInfo.processInfo.systemUptime
        watchdog?.cancel()
        var fields = configuration.originalState()
        fields["activeSession"] = iconView?.sessionActive ?? false
        fields["sessionCount"] = iconView?.sessionIndex ?? 0
        if configuration.activationCase != nil {
            fields.merge(applicationState(window: window, includeWindowDetails: true)) { _, value in value }
            fields["callbackSystemUptime"] = received
        }
        trace.record("application-terminating", fields)
        trace.flush()
    }
}

@main
private enum NativeDragSource {
    @MainActor
    static func main() {
        do {
            let configuration = try SourceConfiguration()
            let trace = try SourceTrace(url: configuration.traceURL, sourceCase: configuration.sourceCase,
                                        activationBinding: configuration.activationBinding)
            guard let application = SourceApplication.shared as? SourceApplication else {
                throw SourceIssue.invalid("The passive source NSApplication subclass did not initialize")
            }
            application.trace = trace
            application.recordsActivationState = configuration.activationCase != nil
            let delegate = SourceDelegate(configuration: configuration, trace: trace)
            application.delegate = delegate
            let watchdog = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
            watchdog.schedule(deadline: .now() + 130)
            watchdog.setEventHandler {
                trace.record("watchdog-timeout", configuration.originalState())
                trace.flush()
                Darwin.exit(124)
            }
            delegate.watchdog = watchdog
            watchdog.resume()
            withExtendedLifetime(delegate) { application.run() }
        } catch {
            FileHandle.standardError.write(Data(("Native drag source failed: \(error)\n").utf8))
            Darwin.exit(2)
        }
    }
}
