#if os(macOS)
import AppKit
import FreewheelCore

/// Observes drag metadata only. A destination drop, or an explicit manual click,
/// is required before any operation can execute.
@MainActor
final class DragWheelController {
    var enabled = true { didSet { if !enabled { dismiss(); resetDrag() } } }
    var onDrop: (([URL], FileOperation) -> Void)?
    var onShowMain: (() -> Void)?

    private var timer: Timer?
    private var panel: WheelPanel?
    private var wheelView: DragWheelView?
    private var idleChangeCount = NSPasteboard(name: .drag).changeCount
    private var trackedChangeCount: Int?
    private var trackedURLs: [URL] = []
    private var wasPressed = false
    private var previousModifiers: NSEvent.ModifierFlags = []
    private var dismissalGeneration = 0
    fileprivate private(set) var manual = false
    fileprivate private(set) var files: [URL] = []
    fileprivate private(set) var mode: WheelMode = .convert
    fileprivate private(set) var operations: [FileOperation] = []
    fileprivate private(set) var page = 0
    fileprivate var language: String { UserDefaults.standard.string(forKey: "language") ?? (Locale.preferredLanguages.first?.hasPrefix("tr") == true ? "tr" : "en") }
    fileprivate var visibleOperations: [FileOperation] { Array(operations.dropFirst(page * 8).prefix(8)) }
    fileprivate var pageCount: Int { max(1, (operations.count + 7) / 8) }

    init() {}

    func start() {
        guard timer == nil else { return }
        resetDrag()
        previousModifiers = NSEvent.modifierFlags.intersection([.shift, .command, .control])
        let polling = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in
            // This timer is installed only on the main run loop. Run immediately
            // in its tracking mode instead of queuing work until a drag finishes.
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(polling, forMode: .common)
        timer = polling
    }

    func stop() { timer?.invalidate(); timer = nil; dismiss(); resetDrag() }

    func show(files: [URL], mode: WheelMode = .convert) {
        let local = files.filter(\.isFileURL)
        guard !local.isEmpty else { onShowMain?(); return }
        present(files: local, mode: mode, manual: true)
    }

    func dismiss() {
        dismissalGeneration += 1
        panel?.orderOut(nil)
        wheelView?.clearDrag()
    }

    private func resetDrag() {
        idleChangeCount = NSPasteboard(name: .drag).changeCount
        trackedChangeCount = nil; trackedURLs = []; wasPressed = false
    }

    private func poll() {
        let pressed = NSEvent.pressedMouseButtons & 1 != 0
        let modifiers = NSEvent.modifierFlags.intersection([.shift, .command, .control])
        let rising = modifiers.subtracting(previousModifiers)
        previousModifiers = modifiers
        let pasteboard = NSPasteboard(name: .drag)
        let change = pasteboard.changeCount
        guard enabled else { idleChangeCount = change; wasPressed = pressed; return }
        guard pressed else {
            if wasPressed && panel?.isVisible == true && !manual {
                dismissalGeneration += 1
                let generation = dismissalGeneration
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
                    guard let self, self.dismissalGeneration == generation, NSEvent.pressedMouseButtons & 1 == 0 else { return }
                    self.dismiss()
                }
            }
            resetDrag()
            return
        }
        let alreadyTracking = trackedChangeCount != nil
        wasPressed = true
        if change != idleChangeCount && change != trackedChangeCount {
            // Never read the general clipboard, or stale drag contents while idle.
            trackedChangeCount = change
            trackedURLs = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []).filter(\.isFileURL)
        }
        guard alreadyTracking, !trackedURLs.isEmpty else { return }
        let requested: WheelMode?
        if rising.contains(.shift) { requested = .convert }
        else if rising.contains(.command) { requested = .tools }
        else if rising.contains(.control) { requested = .actions }
        else { requested = nil }
        if let requested { present(files: trackedURLs, mode: requested, manual: false) }
    }

    private func present(files: [URL], mode: WheelMode, manual: Bool) {
        dismissalGeneration += 1
        self.files = files; self.mode = mode; self.manual = manual; page = 0
        operations = Catalog.operations(for: files, mode: mode)
        if panel == nil {
            let window = WheelPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 420), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = true
            window.level = .floating; window.hidesOnDeactivate = false; window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let view = DragWheelView(frame: NSRect(x: 0, y: 0, width: 420, height: 420), controller: self)
            window.contentView = view; window.acceptsMouseMovedEvents = true
            panel = window; wheelView = view
        }
        guard let panel else { return }
        panel.acceptsKeyboard = manual
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let center = WheelGeometry.clampedCenter(proposed: WheelPoint(x: Double(mouse.x), y: Double(mouse.y)), halfSize: 210, bounds: WheelBounds(x: Double(bounds.minX), y: Double(bounds.minY), width: Double(bounds.width), height: Double(bounds.height)))
        panel.setFrameOrigin(NSPoint(x: center.x - 210, y: center.y - 210))
        wheelView?.selectedIndex = manual && !visibleOperations.isEmpty ? 0 : nil
        wheelView?.needsDisplay = true
        if manual { panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(wheelView) }
        else { panel.orderFrontRegardless() }
    }

    fileprivate func changeMode(_ requested: WheelMode) {
        mode = requested; page = 0; operations = Catalog.operations(for: files, mode: requested)
        wheelView?.selectedIndex = manual && !visibleOperations.isEmpty ? 0 : nil
        wheelView?.needsDisplay = true
    }

    fileprivate func changePage(_ delta: Int) {
        guard pageCount > 1 else { return }
        page = (page + delta + pageCount) % pageCount
        wheelView?.selectedIndex = manual ? 0 : nil; wheelView?.needsDisplay = true
    }

    fileprivate func captureDrag(_ sender: NSDraggingInfo) -> [URL]? {
        guard NSEvent.pressedMouseButtons & 1 != 0 else { return nil }
        // Polling binds the payload to a fresh drag-pasteboard generation.
        poll()
        guard sender.draggingPasteboard.name == .drag,
              sender.draggingPasteboard.changeCount == trackedChangeCount,
              !trackedURLs.isEmpty else { return nil }
        if files != trackedURLs {
            files = trackedURLs; page = 0
            operations = Catalog.operations(for: trackedURLs, mode: mode)
            wheelView?.selectedIndex = nil; wheelView?.needsDisplay = true
        }
        return trackedURLs
    }

    fileprivate func execute(_ operation: FileOperation, inputs: [URL]) {
        dismiss()
        // Finish AppKit's drop transaction before the app opens an options sheet.
        DispatchQueue.main.async { [weak self] in self?.onDrop?(inputs, operation) }
    }

    fileprivate func text(_ english: String, _ turkish: String) -> String { language == "tr" ? turkish : english }
}

@MainActor
private final class WheelPanel: NSPanel {
    var acceptsKeyboard = false
    override var canBecomeKey: Bool { acceptsKeyboard }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class DragWheelView: NSView {
    private weak var controller: DragWheelController?
    var selectedIndex: Int? { didSet { needsDisplay = true } }
    private var tracking: NSTrackingArea?
    private var acceptedSequence: Int?
    private var acceptedURLs: [URL] = []
    private var lastScroll = TimeInterval.zero
    private let accent = Palette.accentColor
    private let muted = Palette.mutedColor
    private var center: NSPoint { NSPoint(x: 210, y: 210) }

    init(frame: NSRect, controller: DragWheelController) {
        self.controller = controller
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        setAccessibilityElement(true)
        setAccessibilityLabel("Freewheel file operations. Use arrow keys and Return, or drop onto an operation.")
    }
    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }

    private func index(at point: NSPoint) -> Int? {
        WheelGeometry.index(at: WheelPoint(x: Double(point.x - center.x), y: Double(point.y - center.y)), itemCount: controller?.visibleOperations.count ?? 0)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let controller else { return }
        Palette.panelColor.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 7, dy: 7), xRadius: 38, yRadius: 38).fill()
        Palette.lineColor.setStroke()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 7.5, dy: 7.5), xRadius: 38, yRadius: 38).stroke()
        let visible = controller.visibleOperations
        for (index, operation) in visible.enumerated() {
            let step = 360.0 / Double(visible.count)
            let start = 90 - Double(index) * step + step / 2 - 1.3
            let end = 90 - Double(index) * step - step / 2 + 1.3
            func point(_ radius: CGFloat, _ degrees: Double) -> NSPoint {
                NSPoint(x: center.x + radius * CGFloat(cos(degrees * .pi / 180)), y: center.y + radius * CGFloat(sin(degrees * .pi / 180)))
            }
            let segment = NSBezierPath()
            segment.move(to: point(62, start)); segment.line(to: point(168, start))
            segment.appendArc(withCenter: center, radius: 168, startAngle: CGFloat(start), endAngle: CGFloat(end), clockwise: true)
            segment.line(to: point(62, end))
            segment.appendArc(withCenter: center, radius: 62, startAngle: CGFloat(end), endAngle: CGFloat(start), clockwise: false)
            segment.close()
            (selectedIndex == index ? accent.withAlphaComponent(0.20) : Palette.raisedColor).setFill(); segment.fill()
            if selectedIndex == index { accent.withAlphaComponent(0.65).setStroke(); segment.lineWidth = 1.2; segment.stroke() }
            let position = WheelGeometry.position(index: index, itemCount: visible.count, radius: 119)
            let location = NSPoint(x: center.x + CGFloat(position.x), y: center.y + CGFloat(position.y))
            let missing = operation.dependency.map { !EngineLocator.isAvailable($0) } ?? false
            symbol(operation.symbol, rect: NSRect(x: location.x - 12, y: location.y + 2, width: 24, height: 24), color: missing ? muted : accent)
            label(OperationNames.title(operation, language: controller.language), rect: NSRect(x: location.x - 49, y: location.y - 30, width: 98, height: 30), size: 10.5, color: missing ? muted : Palette.inkColor)
        }
        Palette.raisedColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: 152, y: 152, width: 116, height: 116)).fill()
        symbol("xmark", rect: NSRect(x: 201, y: 214, width: 18, height: 18), color: muted)
        label(controller.text("Cancel", "Vazgeç"), rect: NSRect(x: 158, y: 184, width: 104, height: 22), size: 11, color: muted)
        for (index, mode) in WheelMode.allCases.enumerated() {
            let rect = NSRect(x: 65 + index * 98, y: 377, width: 94, height: 25)
            if mode == controller.mode { accent.withAlphaComponent(0.12).setFill(); NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill() }
            let title = controller.text(mode.title, mode == .convert ? "Dönüştür" : mode == .tools ? "Araçlar" : "İşlemler")
            label(title, rect: rect.insetBy(dx: 2, dy: 5), size: 10, color: mode == controller.mode ? accent : muted)
        }
        if visible.isEmpty { label(controller.text("No operations for this selection", "Bu seçim için işlem yok"), rect: NSRect(x: 42, y: 300, width: 336, height: 34), size: 11, color: muted) }
        if controller.pageCount > 1 {
            label("‹", rect: NSRect(x: 70, y: 24, width: 34, height: 25), size: 21, color: accent)
            label("\(controller.page + 1) / \(controller.pageCount)", rect: NSRect(x: 155, y: 25, width: 110, height: 22), size: 11, color: muted)
            label("›", rect: NSRect(x: 316, y: 24, width: 34, height: 25), size: 21, color: accent)
        } else {
            label(controller.manual ? controller.text("Click or use arrows + Return · Esc to close", "Tıkla veya oklar + Enter · Esc ile kapat") : controller.text("Drop onto an operation", "Bir işlemin üzerine bırak"), rect: NSRect(x: 28, y: 26, width: 364, height: 20), size: 10, color: muted)
        }
    }

    private func label(_ text: String, rect: NSRect, size: CGFloat, color: NSColor) {
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: color, .paragraphStyle: paragraph])
    }
    private func symbol(_ name: String, rect: NSRect, color: NSColor) {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [color]))?.draw(in: rect)
    }

    override func mouseMoved(with event: NSEvent) { selectedIndex = index(at: convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { if controller?.manual == false { selectedIndex = nil } }
    override func mouseDown(with event: NSEvent) {
        guard let controller, controller.manual else { return }
        let point = convert(event.locationInWindow, from: nil)
        if hypot(point.x - center.x, point.y - center.y) < 62 { controller.dismiss(); return }
        if point.y >= 377 && point.y <= 402 {
            for (index, mode) in WheelMode.allCases.enumerated() where NSRect(x: 65 + index * 98, y: 377, width: 94, height: 25).contains(point) { controller.changeMode(mode); return }
        }
        if point.y < 52 && controller.pageCount > 1 { controller.changePage(point.x < 210 ? -1 : 1); return }
        guard let index = index(at: point), controller.visibleOperations.indices.contains(index) else { return }
        controller.execute(controller.visibleOperations[index], inputs: controller.files)
    }

    override func keyDown(with event: NSEvent) {
        guard let controller, controller.manual else { return }
        switch event.keyCode {
        case 53: controller.dismiss()
        case 123, 126: moveSelection(-1)
        case 124, 125: moveSelection(1)
        case 116: controller.changePage(-1)
        case 121: controller.changePage(1)
        case 48:
            let modes = WheelMode.allCases
            if let index = modes.firstIndex(of: controller.mode) { controller.changeMode(modes[(index + 1) % modes.count]) }
        case 36, 76:
            if let selectedIndex, controller.visibleOperations.indices.contains(selectedIndex) { controller.execute(controller.visibleOperations[selectedIndex], inputs: controller.files) }
        default: super.keyDown(with: event)
        }
    }
    private func moveSelection(_ delta: Int) {
        guard let count = controller?.visibleOperations.count, count > 0 else { return }
        selectedIndex = ((selectedIndex ?? (delta > 0 ? -1 : 0)) + delta + count) % count
    }
    override func scrollWheel(with event: NSEvent) {
        guard event.timestamp - lastScroll > 0.18, abs(event.scrollingDeltaY) > 0.5 else { return }
        lastScroll = event.timestamp; controller?.changePage(event.scrollingDeltaY > 0 ? -1 : 1)
    }

    func clearDrag() { acceptedSequence = nil; acceptedURLs = []; selectedIndex = nil }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let urls = controller?.captureDrag(sender) else { return [] }
        acceptedSequence = sender.draggingSequenceNumber; acceptedURLs = urls
        return draggingUpdated(sender)
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard acceptedSequence == sender.draggingSequenceNumber, !acceptedURLs.isEmpty else { return [] }
        selectedIndex = index(at: convert(sender.draggingLocation, from: nil))
        return selectedIndex == nil ? [] : .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { clearDrag() }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        acceptedSequence == sender.draggingSequenceNumber && !acceptedURLs.isEmpty && index(at: convert(sender.draggingLocation, from: nil)) != nil
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let controller, acceptedSequence == sender.draggingSequenceNumber, !acceptedURLs.isEmpty,
              let index = index(at: convert(sender.draggingLocation, from: nil)), controller.visibleOperations.indices.contains(index) else { return false }
        let urls = acceptedURLs, operation = controller.visibleOperations[index]
        controller.execute(operation, inputs: urls)
        return true
    }
    override func draggingEnded(_ sender: NSDraggingInfo) {
        clearDrag()
        if controller?.manual == false { controller?.dismiss() }
    }
}
#endif
