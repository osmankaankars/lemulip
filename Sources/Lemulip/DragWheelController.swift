#if os(macOS)
import AppKit
import LemulipCore

/// Observes drag metadata only. A destination drop, or an explicit manual click,
/// is required before any operation can execute.
@MainActor
final class DragWheelController {
    var enabled = true { didSet { if !enabled { dismiss(); resetDrag() } } }
    var onDrop: (([URL], FileOperation) -> Void)?
    var onShowMain: (() -> Void)?

    private var timer: Timer?
    private var panel: WheelPanel?
    private let panelAppearance = PanelAppearance()
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
    fileprivate var isTrackingDrag: Bool { trackedChangeCount != nil }

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

    func refreshAppearance() {
        wheelView?.needsDisplay = true
        wheelView?.updateAccessibility()
        panel?.invalidateShadow()
    }

    func show(files: [URL], mode: WheelMode = .convert) {
        let local = files.filter(\.isFileURL)
        guard !local.isEmpty else { onShowMain?(); return }
        present(files: local, mode: mode, manual: true)
    }

    func dismiss() {
        dismissalGeneration += 1
        panelAppearance.dismiss()
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
        wheelView?.updateAccessibility(notify: false)
        panelAppearance.present(panel, kind: .wheel) {
            if manual { panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(wheelView) }
            else { panel.orderFrontRegardless() }
        }
        if manual { wheelView?.announceAccessibilityFocus() }
    }

    fileprivate func changeMode(_ requested: WheelMode) {
        mode = requested; page = 0; operations = Catalog.operations(for: files, mode: requested)
        wheelView?.selectedIndex = manual && !visibleOperations.isEmpty ? 0 : nil
        wheelView?.needsDisplay = true
        wheelView?.updateAccessibility()
    }

    fileprivate func changePage(_ delta: Int) {
        guard pageCount > 1 else { return }
        page = (page + delta + pageCount) % pageCount
        wheelView?.selectedIndex = manual ? 0 : nil; wheelView?.needsDisplay = true
        wheelView?.updateAccessibility()
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
            wheelView?.updateAccessibility(notify: false)
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
    var selectedIndex: Int? {
        didSet {
            needsDisplay = true
            if oldValue != selectedIndex { updateAccessibilityValue() }
        }
    }
    private var tracking: NSTrackingArea?
    private var acceptedSequence: Int?
    private var acceptedURLs: [URL] = []
    private var lastScroll = TimeInterval.zero
    private var lastAccessibilityValue: String?
    private var accent: NSColor { Palette.accentColor }
    private var muted: NSColor { Palette.mutedColor }
    private var center: NSPoint { NSPoint(x: 210, y: 210) }

    init(frame: NSRect, controller: DragWheelController) {
        self.controller = controller
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        setAccessibilityRole(.group)
        updateAccessibility(notify: false)
    }
    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { controller?.manual == true }

    private var isManualWheelAvailable: Bool {
        guard let controller else { return false }
        // A manual panel can receive a real Finder drag too. Accessibility and
        // keyboard actions must never submit that drag's payload or bypass drop.
        return controller.manual && window?.isVisible == true && !isHiddenOrHasHiddenAncestor
            && acceptedSequence == nil && !controller.isTrackingDrag
    }
    private var canPerformManualAction: Bool {
        isManualWheelAvailable && NSEvent.pressedMouseButtons == 0
    }

    private var selectedOperation: FileOperation? {
        guard let controller, let selectedIndex,
              controller.visibleOperations.indices.contains(selectedIndex) else { return nil }
        return controller.visibleOperations[selectedIndex]
    }

    override func isAccessibilityEnabled() -> Bool { canPerformManualAction }
    override func isAccessibilityFocused() -> Bool {
        controller?.manual == true && window?.isVisible == true
            && window?.isKeyWindow == true && window?.firstResponder === self
    }
    override func setAccessibilityFocused(_ focused: Bool) {
        guard focused, canPerformManualAction, let window else { return }
        let wasFocused = isAccessibilityFocused()
        window.makeKey()
        if window.makeFirstResponder(self), !wasFocused { announceAccessibilityFocus() }
    }
    func announceAccessibilityFocus() {
        guard canPerformManualAction, isAccessibilityFocused() else { return }
        NSAccessibility.post(element: self, notification: .focusedUIElementChanged)
    }

    override func isAccessibilitySelectorAllowed(_ selector: Selector) -> Bool {
        switch selector {
        case #selector(accessibilityPerformPress), #selector(accessibilityPerformConfirm):
            return canPerformManualAction && selectedOperation != nil
        case #selector(accessibilityPerformIncrement), #selector(accessibilityPerformDecrement):
            return canPerformManualAction && controller?.visibleOperations.isEmpty == false
        case #selector(accessibilityPerformCancel), #selector(setAccessibilityFocused(_:)):
            return canPerformManualAction
        case #selector(setAccessibilityValue(_:)):
            return false
        default: return super.isAccessibilitySelectorAllowed(selector)
        }
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        canPerformManualAction ? super.accessibilityCustomActions() : nil
    }
    override func accessibilityPerformIncrement() -> Bool {
        guard canPerformManualAction else { return false }
        return moveSelection(1)
    }
    override func accessibilityPerformDecrement() -> Bool {
        guard canPerformManualAction else { return false }
        return moveSelection(-1)
    }
    override func accessibilityPerformPress() -> Bool { chooseSelectedOperation() }
    override func accessibilityPerformConfirm() -> Bool { chooseSelectedOperation() }
    override func accessibilityPerformCancel() -> Bool {
        guard canPerformManualAction, let controller else { return false }
        controller.dismiss()
        return true
    }

    private func chooseSelectedOperation() -> Bool {
        guard canPerformManualAction, let controller, let operation = selectedOperation else { return false }
        controller.execute(operation, inputs: controller.files)
        return true
    }
    private func selectOperation(_ operation: FileOperation, mode: WheelMode, page: Int) -> Bool {
        guard canPerformManualAction, let controller, controller.mode == mode, controller.page == page,
              let index = controller.visibleOperations.firstIndex(of: operation) else { return false }
        selectedIndex = index
        return true
    }
    private func selectMode(_ mode: WheelMode) -> Bool {
        guard canPerformManualAction, let controller else { return false }
        controller.changeMode(mode)
        return true
    }
    private func movePage(_ delta: Int) -> Bool {
        guard canPerformManualAction, let controller, controller.pageCount > 1 else { return false }
        controller.changePage(delta)
        return true
    }

    func updateAccessibility(notify: Bool = true) {
        guard let controller else { return }
        setAccessibilityElement(controller.manual)
        guard controller.manual else {
            setAccessibilityCustomActions(nil)
            updateAccessibilityValue(notify: false)
            return
        }
        setAccessibilityLabel(controller.text("Lemulip file operations", "Lemulip dosya işlemleri"))
        setAccessibilityHelp(controller.text(
            "Arrow keys select an operation. Return chooses it. Tab changes mode; Shift-Tab goes back. Page Up and Page Down change page. Escape cancels. Accessibility actions also select operations, modes, and pages.",
            "Ok tuşları bir işlem seçer. Return seçimi uygular. Tab modu değiştirir; Shift-Tab geri gider. Page Up ve Page Down sayfayı değiştirir. Escape kapatır. Erişilebilirlik eylemleriyle de işlem, mod ve sayfa seçebilirsin."))
        var actions: [NSAccessibilityCustomAction] = []
        if !controller.visibleOperations.isEmpty {
            actions += [
                NSAccessibilityCustomAction(name: controller.text("Choose Selected Operation", "Seçili işlemi uygula"), handler: { [weak self] in self?.accessibilityPerformPress() ?? false }),
                NSAccessibilityCustomAction(name: controller.text("Next Operation", "Sonraki işlem"), handler: { [weak self] in self?.accessibilityPerformIncrement() ?? false }),
                NSAccessibilityCustomAction(name: controller.text("Previous Operation", "Önceki işlem"), handler: { [weak self] in self?.accessibilityPerformDecrement() ?? false })
            ]
            let mode = controller.mode, page = controller.page
            for operation in controller.visibleOperations {
                let title = OperationNames.title(operation, language: controller.language)
                actions.append(NSAccessibilityCustomAction(name: controller.text("Select \(title)", "\(title) seç"), handler: { [weak self] in
                    self?.selectOperation(operation, mode: mode, page: page) ?? false
                }))
            }
        }
        for mode in WheelMode.allCases where mode != controller.mode {
            let title = modeTitle(mode)
            actions.append(NSAccessibilityCustomAction(name: controller.text("Show \(title)", "\(title) modunu göster"), handler: { [weak self] in self?.selectMode(mode) ?? false }))
        }
        if controller.pageCount > 1 {
            actions += [
                NSAccessibilityCustomAction(name: controller.text("Previous Page", "Önceki sayfa"), handler: { [weak self] in self?.movePage(-1) ?? false }),
                NSAccessibilityCustomAction(name: controller.text("Next Page", "Sonraki sayfa"), handler: { [weak self] in self?.movePage(1) ?? false })
            ]
        }
        actions.append(NSAccessibilityCustomAction(name: controller.text("Cancel", "Vazgeç"), handler: { [weak self] in self?.accessibilityPerformCancel() ?? false }))
        setAccessibilityCustomActions(actions)
        updateAccessibilityValue(notify: notify)
    }

    private func updateAccessibilityValue(notify: Bool = true) {
        guard let controller, controller.manual else {
            if lastAccessibilityValue != nil {
                lastAccessibilityValue = nil
                setAccessibilityValue(nil)
            }
            return
        }
        let selection: String
        if let operation = selectedOperation, let selectedIndex {
            let title = OperationNames.title(operation, language: controller.language)
            let count = controller.visibleOperations.count
            selection = controller.text("\(title), operation \(selectedIndex + 1) of \(count)", "\(title), \(count) işlemin \(selectedIndex + 1). işlemi")
        } else {
            selection = controller.visibleOperations.isEmpty
                ? controller.text("No operations for this selection", "Bu seçim için işlem yok")
                : controller.text("No operation selected", "İşlem seçilmedi")
        }
        let page = controller.text("Page \(controller.page + 1) of \(controller.pageCount)", "Sayfa \(controller.page + 1) / \(controller.pageCount)")
        let value = "\(modeTitle(controller.mode)). \(page). \(selection)."
        let changed = value != lastAccessibilityValue
        lastAccessibilityValue = value
        setAccessibilityValue(value)
        if notify, changed, isManualWheelAvailable {
            NSAccessibility.post(element: self, notification: .valueChanged)
        }
    }

    private func modeTitle(_ mode: WheelMode) -> String {
        controller?.text(mode.title, mode == .convert ? "Dönüştür" : mode == .tools ? "Araçlar" : "İşlemler") ?? mode.title
    }

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
        let visible = controller.visibleOperations
        if visible.isEmpty {
            let ring = NSBezierPath(ovalIn: NSRect(x: 42, y: 42, width: 336, height: 336))
            ring.append(NSBezierPath(ovalIn: NSRect(x: 148, y: 148, width: 124, height: 124)))
            ring.windingRule = .evenOdd
            Palette.raisedColor.setFill(); ring.fill()
        }
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
            // Each sector carries its own surface; the surrounding panel is clear.
            Palette.raisedColor.setFill(); segment.fill()
            if selectedIndex == index {
                accent.withAlphaComponent(0.20).setFill(); segment.fill()
                accent.withAlphaComponent(0.65).setStroke(); segment.lineWidth = 1.2; segment.stroke()
            }
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
            Palette.panelColor.setFill(); NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
            if mode == controller.mode { accent.withAlphaComponent(0.12).setFill(); NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill() }
            let title = modeTitle(mode)
            label(title, rect: rect.insetBy(dx: 2, dy: 5), size: 10, color: mode == controller.mode ? accent : muted)
        }
        if visible.isEmpty { label(controller.text("No operations for this selection", "Bu seçim için işlem yok"), rect: NSRect(x: 42, y: 300, width: 336, height: 34), size: 11, color: muted) }
        if controller.pageCount > 1 {
            for rect in [NSRect(x: 70, y: 24, width: 34, height: 25), NSRect(x: 155, y: 24, width: 110, height: 25), NSRect(x: 316, y: 24, width: 34, height: 25)] {
                Palette.panelColor.setFill(); NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
            }
            label("‹", rect: NSRect(x: 70, y: 24, width: 34, height: 25), size: 21, color: accent)
            label("\(controller.page + 1) / \(controller.pageCount)", rect: NSRect(x: 155, y: 25, width: 110, height: 22), size: 11, color: muted)
            label("›", rect: NSRect(x: 316, y: 24, width: 34, height: 25), size: 21, color: accent)
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
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard canPerformManualAction, let controller,
              modifiers.intersection([.command, .control, .option]).isEmpty else {
            super.keyDown(with: event); return
        }
        switch event.keyCode {
        case 53: controller.dismiss()
        case 123, 126: moveSelection(-1)
        case 124, 125: moveSelection(1)
        case 116: controller.changePage(-1)
        case 121: controller.changePage(1)
        case 48:
            let modes = WheelMode.allCases
            let delta = modifiers.contains(.shift) ? -1 : 1
            if let index = modes.firstIndex(of: controller.mode) { controller.changeMode(modes[(index + delta + modes.count) % modes.count]) }
        case 36, 76:
            _ = chooseSelectedOperation()
        default: super.keyDown(with: event)
        }
    }
    @discardableResult
    private func moveSelection(_ delta: Int) -> Bool {
        guard let count = controller?.visibleOperations.count, count > 0 else { return false }
        let next = ((selectedIndex ?? (delta > 0 ? -1 : 0)) + delta + count) % count
        guard next != selectedIndex else { return false }
        selectedIndex = next
        return true
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
