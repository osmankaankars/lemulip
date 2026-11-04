import AppKit
import CryptoKit
import Darwin
import Foundation

// An isolated AppKit control for the Finder-input observer. This is not the
// production application and contains no Escape handler or drag cancellation
// workaround. Its passive receipts distinguish destination callbacks from
// events dispatched through NSApplication.sendEvent; absence from sendEvent
// does not prove that AppKit's tracking loop never received an event.
private enum ControlIssue: Error, CustomStringConvertible {
    case invalid(String)
    var description: String { switch self { case .invalid(let message): return message } }
}

private func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw ControlIssue.invalid(message) }
}

private struct ControlConfiguration {
    let theme: String
    let evidenceKind: String
    let root: URL
    let folder: URL
    let traceURL: URL
    let originals: [String: Data]

    init() throws {
        let arguments = CommandLine.arguments
        let themeIndices = arguments.indices.filter { arguments[$0] == "-controlTheme" }
        try require(themeIndices.count == 1, "Require one explicit control theme")
        let index = themeIndices[0] + 1
        try require(arguments.indices.contains(index), "The control theme is missing")
        theme = arguments[index]
        try require(["orchard", "pistachio", "lemonade"].contains(theme), "Unknown control theme")
        let evidenceIndices = arguments.indices.filter { arguments[$0] == "-controlEvidenceKind" }
        if evidenceIndices.isEmpty {
            evidenceKind = "quartz"
        } else {
            try require(evidenceIndices.count == 1 && arguments.indices.contains(evidenceIndices[0] + 1),
                        "Require one fixed control evidence kind")
            evidenceKind = arguments[evidenceIndices[0] + 1]
            try require(evidenceKind == "keyboard" && theme == "orchard",
                        "The keyboard comparison is restricted to the Orchard control")
        }

        let bundle = Bundle.main.bundleURL.standardizedFileURL
        root = bundle.deletingLastPathComponent()
        try require(root.lastPathComponent == "lemulip-native-ui"
                    && bundle.lastPathComponent == "Native Drag Control.app"
                    && Bundle.main.bundleIdentifier == "app.lemulip.NativeDragControl"
                    && Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String == "NativeDragControl",
                    "Require the exact isolated AppKit control bundle")
        folder = root.appendingPathComponent("Fixtures/FinderDrop/" + theme, isDirectory: true)
        let evidenceName = evidenceKind == "keyboard" ? "NativeDragKeyboardEvidence" : "NativeDragControlEvidence"
        let evidence = root.appendingPathComponent(evidenceName + "/" + theme, isDirectory: true)
        for url in [root, bundle, folder, evidence] {
            try require(url.standardizedFileURL.path == url.resolvingSymlinksInPath().path,
                        "Symlinked control paths are not allowed")
            try require(try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true,
                        "The fixed control directory is unavailable")
        }
        traceURL = evidence.appendingPathComponent("receiver.jsonl")
        let inputs = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent != ".DS_Store" }
        try require(inputs.count == 4, "Require exactly four input-only Finder fixtures")
        var bytes: [String: Data] = [:]
        for prefix in ["Existing", "Single", "Multi-A", "Multi-B"] {
            let matching = inputs.filter { $0.lastPathComponent.hasPrefix(prefix + "-") && $0.pathExtension == "txt" }
            try require(matching.count == 1, "The fixed Finder fixture role is missing or ambiguous")
            let input = matching[0]
            try require(input.standardizedFileURL.path == input.resolvingSymlinksInPath().path,
                        "Symlinked Finder fixtures are not allowed")
            let values = try input.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            try require(values.isRegularFile == true && values.isSymbolicLink == false
                        && (values.fileSize ?? 0) > 0 && (values.fileSize ?? 0) < 65_536,
                        "Require small, nonempty regular Finder fixtures")
            bytes[input.lastPathComponent] = try Data(contentsOf: input)
        }
        try require(bytes.count == 4, "Finder fixture roles must be distinct")
        originals = bytes
    }

    func validated(_ urls: [URL]) throws -> [URL] {
        try require(!urls.isEmpty && urls.count <= 4, "Require one to four exact fixture URLs")
        return try urls.map { url in
            let expected = folder.appendingPathComponent(url.lastPathComponent)
            try require(url.isFileURL && (url.host == nil || url.host == "" || url.host == "localhost")
                        && url.query == nil && url.fragment == nil
                        && originals[url.lastPathComponent] != nil
                        && url.standardizedFileURL.path == expected.path
                        && url.resolvingSymlinksInPath().path == expected.path,
                        "Only the exact staged Finder fixture URLs are accepted")
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            try require(values.isRegularFile == true && values.isSymbolicLink == false
                        && (values.fileSize ?? 0) > 0 && (values.fileSize ?? 0) < 65_536,
                        "A fixture is no longer a small regular file")
            try require(try Data(contentsOf: expected) == originals[url.lastPathComponent],
                        "A fixture's original bytes changed")
            return expected
        }
    }

    func originalState() -> [String: Any] {
        do {
            let actual = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent != ".DS_Store" }
            let sameSet = Set(actual.map(\.lastPathComponent)) == Set(originals.keys)
            let sameBytes = try originals.keys.sorted().allSatisfy { name in
                _ = try validated([folder.appendingPathComponent(name)])
                return true
            }
            return ["originalBytesUnchanged": sameBytes, "fixtureFileSetUnchanged": sameSet]
        } catch {
            return ["originalBytesUnchanged": false, "fixtureFileSetUnchanged": false,
                    "originalCheckError": String(describing: error)]
        }
    }
}

private final class ControlTrace: @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()
    private var count = 0
    private var byteCount = 0
    private let maximumRecords = 10_000
    private let maximumBytes = 8 * 1_024 * 1_024

    init(url: URL) throws {
        let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                                     S_IRUSR | S_IWUSR)
        try require(descriptor >= 0, "Could not exclusively create the fixed receiver trace")
        handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    func record(_ event: String, _ fields: [String: Any] = [:]) {
        lock.lock()
        defer { lock.unlock() }
        do {
            var value = fields
            value["schema"] = 1
            value["event"] = event
            value["recordIndex"] = count
            value["systemUptime"] = ProcessInfo.processInfo.systemUptime
            value["time"] = ISO8601DateFormatter().string(from: Date())
            value["pid"] = Int(ProcessInfo.processInfo.processIdentifier)
            let withinLimit = count < maximumRecords && byteCount < maximumBytes - 8_192
            if !withinLimit {
                value = ["schema": 1, "event": "trace-limit", "recordIndex": count,
                         "systemUptime": ProcessInfo.processInfo.systemUptime]
            }
            var data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
            data.append(0x0a)
            try handle.write(contentsOf: data)
            try handle.synchronize()
            count += 1
            byteCount += data.count
            if !withinLimit { Darwin.exit(2) }
        } catch {
            FileHandle.standardError.write(Data(("Native drag control trace failed: \(error)\n").utf8))
            Darwin.exit(2)
        }
    }
}

@MainActor
@objc(NativeDragControlApplication)
private final class ControlApplication: NSApplication {
    var trace: ControlTrace?

    override func sendEvent(_ event: NSEvent) {
        if (event.type == .keyDown || event.type == .keyUp) && event.keyCode == 53 {
            trace?.record("escape-send-event", [
                "eventType": event.type == .keyDown ? "keyDown" : "keyUp",
                "keyCode": Int(event.keyCode), "eventTimestamp": event.timestamp,
                "isRepeat": event.type == .keyDown && event.isARepeat,
                "modifierFlags": event.modifierFlags.rawValue,
                "charactersUTF32": (event.characters ?? "").unicodeScalars.prefix(4).map(\.value),
                "charactersIgnoringModifiersUTF32": (event.charactersIgnoringModifiers ?? "").unicodeScalars.prefix(4).map(\.value),
                "applicationActive": isActive, "eventWindowNumber": event.windowNumber,
                "keyWindowNumber": keyWindow.map { $0.windowNumber as Any } ?? NSNull(),
                "scope": "Passive sendEvent receipt only; super is always called."
            ])
        }
        super.sendEvent(event)
    }
}

@MainActor
private final class ControlSelection {
    let configuration: ControlConfiguration
    let trace: ControlTrace
    private(set) var urls: [URL] = []
    var onChange: (() -> Void)?

    init(configuration: ControlConfiguration, trace: ControlTrace) {
        self.configuration = configuration
        self.trace = trace
    }

    func append(_ incoming: [URL], origin: String) throws {
        let accepted = try configuration.validated(incoming)
        var known = Set(urls)
        urls += accepted.filter { known.insert($0).inserted }
        onChange?()
        recordSelection(origin)
    }

    func clear() {
        urls = []
        onChange?()
        recordSelection("clear-button")
    }

    func remove(_ name: String) {
        urls.removeAll { $0.lastPathComponent == name }
        onChange?()
        recordSelection("remove-button")
    }

    private func recordSelection(_ origin: String) {
        var fields = configuration.originalState()
        fields["origin"] = origin
        fields["selectedFilenames"] = urls.map(\.lastPathComponent)
        trace.record("selection-changed", fields)
    }
}

@MainActor
private final class ControlDropView: NSView {
    private let selection: ControlSelection
    private let countLabel = NSTextField(labelWithString: "0 Selected")
    private let clearButton = NSButton(title: "Clear", target: nil, action: nil)
    private var fileLabels: [NSTextField] = []
    private var removeButtons: [NSButton] = []
    private var targeted = false { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }

    init(selection: ControlSelection) {
        self.selection = selection
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL])
        countLabel.font = .systemFont(ofSize: 13, weight: .medium)
        countLabel.setAccessibilityIdentifier("control.selected-count")
        addSubview(countLabel)
        clearButton.bezelStyle = .rounded
        clearButton.target = self
        clearButton.action = #selector(clearSelection)
        addSubview(clearButton)
        selection.onChange = { [weak self] in self?.refresh() }
        refresh()
    }

    required init?(coder: NSCoder) { nil }

    private func refresh() {
        countLabel.stringValue = "\(selection.urls.count) Selected"
        fileLabels.forEach { $0.removeFromSuperview() }
        removeButtons.forEach { $0.removeFromSuperview() }
        fileLabels = []
        removeButtons = []
        for url in selection.urls {
            let label = NSTextField(labelWithString: url.lastPathComponent)
            label.font = .systemFont(ofSize: 13)
            label.lineBreakMode = .byTruncatingMiddle
            addSubview(label)
            fileLabels.append(label)
            let button = NSButton(title: "Remove " + url.lastPathComponent, target: self, action: #selector(removeFile(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(url.lastPathComponent)
            button.bezelStyle = .rounded
            button.cell?.lineBreakMode = .byTruncatingTail
            addSubview(button)
            removeButtons.append(button)
        }
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        // The observer enters four points above this header, inside exactly
        // eight points of top padding. Its -24 point exit is outside this view.
        countLabel.frame = NSRect(x: 8, y: 8, width: 180, height: 20)
        clearButton.frame = NSRect(x: max(196, bounds.width - 88), y: 5, width: 80, height: 26)
        for index in fileLabels.indices {
            let y = CGFloat(44 + index * 52)
            fileLabels[index].frame = NSRect(x: 16, y: y + 4, width: max(100, bounds.width - 180), height: 24)
            removeButtons[index].frame = NSRect(x: max(128, bounds.width - 148), y: y, width: 132, height: 30)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 12, yRadius: 12)
        NSColor.controlBackgroundColor.setFill()
        border.fill()
        (targeted ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        border.lineWidth = targeted ? 2 : 1
        border.setLineDash([5, 5], count: 2, phase: 0)
        border.stroke()
    }

    @objc private func clearSelection() { selection.clear() }

    @objc private func removeFile(_ sender: NSButton) {
        if let name = sender.identifier?.rawValue { selection.remove(name) }
    }

    private func acceptedURLs(_ sender: NSDraggingInfo) -> [URL]? {
        guard sender.draggingSourceOperationMask.contains(.copy),
              let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                  options: [.urlReadingFileURLsOnly: true]) as? [URL] else { return nil }
        return try? selection.configuration.validated(urls)
    }

    private func record(_ callback: String, sender: NSDraggingInfo?, extra: [String: Any] = [:]) {
        var fields = selection.configuration.originalState()
        fields.merge(extra) { _, new in new }
        fields["selectedFilenames"] = selection.urls.map(\.lastPathComponent)
        fields["targeted"] = targeted
        fields["applicationActive"] = NSApp.isActive
        fields["currentModifierFlags"] = NSEvent.modifierFlags.rawValue
        if let event = NSApp.currentEvent {
            fields["applicationCurrentEventType"] = event.type.rawValue
            fields["applicationCurrentEventTimestamp"] = event.timestamp
            fields["applicationCurrentEventModifierFlags"] = event.modifierFlags.rawValue
        }
        if let sender {
            fields["sequenceNumber"] = sender.draggingSequenceNumber
            fields["sourceAllowedOperationMask"] = sender.draggingSourceOperationMask.rawValue
            fields["sourceIsInThisApplication"] = sender.draggingSource != nil
            fields["draggingLocationInWindow"] = ["x": sender.draggingLocation.x, "y": sender.draggingLocation.y]
        }
        selection.trace.record(callback, fields)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let accepted = acceptedURLs(sender) != nil
        targeted = accepted
        record("draggingEntered", sender: sender, extra: ["returnedCopy": accepted])
        return accepted ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let accepted = acceptedURLs(sender) != nil
        targeted = accepted
        record("draggingUpdated", sender: sender, extra: ["returnedCopy": accepted])
        return accepted ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        targeted = false
        record("draggingExited", sender: sender)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        targeted = false
        record("draggingEnded", sender: sender,
               extra: ["scope": "Destination notification; source operation result is not available here."])
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let accepted = acceptedURLs(sender) != nil
        record("prepareForDragOperation", sender: sender, extra: ["accepted": accepted])
        return accepted
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { targeted = false }
        guard let urls = acceptedURLs(sender) else {
            record("performDragOperation", sender: sender, extra: ["accepted": false])
            return false
        }
        do {
            try selection.append(urls, origin: "performDragOperation")
            record("performDragOperation", sender: sender, extra: ["accepted": true])
            return true
        } catch {
            record("performDragOperation", sender: sender,
                   extra: ["accepted": false, "reason": String(describing: error)])
            return false
        }
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        targeted = false
        record("concludeDragOperation", sender: sender)
    }
}

@MainActor
private final class ControlContentView: NSView {
    private let heading = NSTextField(labelWithString: "Standard AppKit Drag Control")
    private let explanation: NSTextField
    private let destination: ControlDropView
    override var isFlipped: Bool { true }

    init(selection: ControlSelection) {
        explanation = NSTextField(labelWithString: "\(selection.configuration.theme.capitalized) fixture scenario · separate control, not Lemulip UI")
        destination = ControlDropView(selection: selection)
        super.init(frame: NSRect(x: 0, y: 0, width: 920, height: 532))
        heading.font = .systemFont(ofSize: 22, weight: .semibold)
        explanation.font = .systemFont(ofSize: 12)
        explanation.textColor = .secondaryLabelColor
        addSubview(heading)
        addSubview(explanation)
        addSubview(destination)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        heading.frame = NSRect(x: 24, y: 20, width: bounds.width - 48, height: 30)
        explanation.frame = NSRect(x: 24, y: 54, width: bounds.width - 48, height: 20)
        destination.frame = NSRect(x: 24, y: 92, width: bounds.width - 48, height: min(320, bounds.height - 116))
    }
}

@MainActor
private final class ControlDelegate: NSObject, NSApplicationDelegate {
    private let selection: ControlSelection
    private var window: NSWindow?
    var watchdog: DispatchSourceTimer?

    init(selection: ControlSelection) { self.selection = selection }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let window = NSWindow(contentRect: NSRect(x: 80, y: 100, width: 920, height: 532),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Native Drag Control"
        window.contentMinSize = NSSize(width: 720, height: 532)
        window.isReleasedWhenClosed = false
        window.contentView = ControlContentView(selection: selection)
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        selection.trace.record("application-ready", ["windowTitle": window.title,
                               "scope": "Separate standard AppKit destination, no custom Escape handling."])
    }

    func application(_ application: NSApplication, open urls: [URL]) { receive(urls, origin: "open-urls") }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let accepted = receive(filenames.map { URL(fileURLWithPath: $0) }, origin: "open-files")
        sender.reply(toOpenOrPrint: accepted ? .success : .failure)
    }

    @discardableResult
    private func receive(_ urls: [URL], origin: String) -> Bool {
        do { try selection.append(urls, origin: origin); return true }
        catch {
            selection.trace.record("open-rejected", ["origin": origin, "requestedCount": urls.count,
                                   "reason": String(describing: error)])
            return false
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDidBecomeActive(_ notification: Notification) {
        selection.trace.record("application-became-active")
    }

    func applicationDidResignActive(_ notification: Notification) {
        selection.trace.record("application-resigned-active")
    }

    func applicationWillTerminate(_ notification: Notification) {
        watchdog?.cancel()
        selection.trace.record("application-terminated", selection.configuration.originalState())
    }
}

@main
private enum NativeDragControl {
    @MainActor
    static func main() {
        do {
            let configuration = try ControlConfiguration()
            let trace = try ControlTrace(url: configuration.traceURL)
            guard let application = ControlApplication.shared as? ControlApplication else {
                throw ControlIssue.invalid("The passive NSApplication subclass did not initialize")
            }
            application.trace = trace
            let selection = ControlSelection(configuration: configuration, trace: trace)
            let delegate = ControlDelegate(selection: selection)
            application.delegate = delegate
            trace.record("application-start", [
                "bundleIdentifier": "app.lemulip.NativeDragControl", "theme": configuration.theme,
                "evidenceKind": configuration.evidenceKind,
                "fixtureFilenames": configuration.originals.keys.sorted(),
                "originalSHA256": configuration.originals.mapValues { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() },
                "sendEventSubclassInstalled": true, "maximumLifetimeSeconds": 150,
                "scope": "Diagnostic AppKit control; production drag behavior is unchanged."
            ])
            // A one-shot process bound, not input polling. It also runs if an
            // AppKit tracking loop is active when the observer stops responding.
            let watchdog = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
            watchdog.schedule(deadline: .now() + 150)
            watchdog.setEventHandler {
                trace.record("application-timeout", configuration.originalState())
                Darwin.exit(124)
            }
            delegate.watchdog = watchdog
            watchdog.resume()
            withExtendedLifetime(delegate) { application.run() }
        } catch {
            FileHandle.standardError.write(Data(("Native drag control failed: \(error)\n").utf8))
            Darwin.exit(2)
        }
    }
}
