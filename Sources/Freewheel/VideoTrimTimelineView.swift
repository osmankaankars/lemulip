#if os(macOS)
import AppKit
import SwiftUI
import FreewheelCore

@MainActor
struct VideoTrimTimelineView: NSViewRepresentable {
    let thumbnails: [VideoTrimThumbnail]
    @Binding var selection: VideoTrimSelection
    let playheadSeconds: Double
    let theme: AppTheme
    let language: String
    let onSeek: (Double) -> Void
    let onTogglePlayback: () -> Void

    func makeNSView(context: Context) -> VideoTrimTimelineCanvas {
        let view = VideoTrimTimelineCanvas(thumbnails: thumbnails)
        configure(view)
        return view
    }

    func updateNSView(_ view: VideoTrimTimelineCanvas, context: Context) { configure(view) }

    private func configure(_ view: VideoTrimTimelineCanvas) {
        let selectionChanged = view.selection != selection
        let languageChanged = view.language != language
        let positionChanged = view.playheadSeconds != playheadSeconds
        view.selection = selection
        view.playheadSeconds = playheadSeconds
        view.theme = theme
        view.language = language
        view.onChange = { selection = $0 }
        view.onSeek = onSeek
        view.onTogglePlayback = onTogglePlayback
        if selectionChanged || languageChanged || positionChanged { view.updateAccessibility() }
        view.needsDisplay = true
        if selectionChanged { view.window?.invalidateCursorRects(for: view) }
    }
}

/// Holds only the bounded thumbnail summary. Drawing or moving the playhead
/// never decodes a frame, and the paused timeline has no timer.
@MainActor
final class VideoTrimTimelineCanvas: NSView {
    private enum Target { case start, end, playhead }
    private enum Drag { case start, end, move, seek }

    private let images: [NSImage]
    private var activeTarget = Target.playhead
    private var drag: Drag?
    private var dragOrigin = CGPoint.zero
    private var dragStartSeconds: Double = 0
    private var selectionAtDragStart: VideoTrimSelection?
    private var didDrag = false

    var selection = VideoTrimSelection(startSeconds: 0, endSeconds: 1, sourceDuration: 1)
    var playheadSeconds: Double = 0
    var theme = AppTheme.orchardNight
    var language = "en" {
        didSet { if oldValue != language { updateAccessibleActions() } }
    }
    var onChange: ((VideoTrimSelection) -> Void)?
    var onSeek: ((Double) -> Void)?
    var onTogglePlayback: (() -> Void)?

    init(thumbnails: [VideoTrimThumbnail]) {
        images = thumbnails.prefix(24).map { thumbnail in
            NSImage(cgImage: thumbnail.image, size: NSSize(width: thumbnail.image.width, height: thumbnail.image.height))
        }
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        updateAccessibleActions()
        updateAccessibility()
    }

    required init?(coder: NSCoder) { return nil }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return true }

    private var stripFrame: CGRect {
        CGRect(x: 18, y: 16, width: max(0, bounds.width - 36), height: max(0, bounds.height - 50))
    }
    private var selectedFrame: CGRect {
        CGRect(x: x(selection.startSeconds), y: stripFrame.minY,
               width: max(0, x(selection.endSeconds) - x(selection.startSeconds)), height: stripFrame.height)
    }
    private func x(_ seconds: Double) -> CGFloat {
        guard selection.sourceDuration > 0, seconds.isFinite else { return stripFrame.minX }
        return stripFrame.minX + CGFloat(max(0, min(1, seconds / selection.sourceDuration))) * stripFrame.width
    }
    private func seconds(at point: CGPoint) -> Double {
        guard stripFrame.width > 0 else { return 0 }
        return Double(max(0, min(1, (point.x - stripFrame.minX) / stripFrame.width))) * selection.sourceDuration
    }

    override func draw(_ dirtyRect: NSRect) {
        Palette.raisedColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 13, yRadius: 13).fill()
        let frame = stripFrame
        guard frame.width > 0, frame.height > 0 else { return }
        drawThumbnails(in: frame)
        NSColor.black.withAlphaComponent(0.62).setFill()
        NSBezierPath.fill(CGRect(x: frame.minX, y: frame.minY, width: max(0, selectedFrame.minX - frame.minX), height: frame.height))
        NSBezierPath.fill(CGRect(x: selectedFrame.maxX, y: frame.minY, width: max(0, frame.maxX - selectedFrame.maxX), height: frame.height))
        let outline = NSBezierPath(rect: selectedFrame)
        Palette.accentColor.setStroke(); outline.lineWidth = 2; outline.stroke()
        drawPlayhead(in: frame)
        drawHandle(.start, at: x(selection.startSeconds))
        drawHandle(.end, at: x(selection.endSeconds))
        drawRuler(in: frame)
        if window?.firstResponder === self {
            let focus = NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 3), xRadius: 10, yRadius: 10)
            Palette.accentColor.setStroke(); focus.lineWidth = 2; focus.stroke()
        }
    }

    private func drawThumbnails(in frame: CGRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(roundedRect: frame, xRadius: 5, yRadius: 5).addClip()
        NSColor.black.setFill(); NSBezierPath.fill(frame)
        guard !images.isEmpty else { return }
        let cellWidth = frame.width / CGFloat(images.count)
        for (index, image) in images.enumerated() {
            let cell = CGRect(x: frame.minX + CGFloat(index) * cellWidth, y: frame.minY,
                              width: cellWidth + 0.5, height: frame.height)
            let imageSize = image.size
            guard imageSize.width > 0, imageSize.height > 0 else { continue }
            let scale = max(cell.width / imageSize.width, cell.height / imageSize.height)
            let sourceSize = CGSize(width: cell.width / scale, height: cell.height / scale)
            let source = CGRect(x: (imageSize.width - sourceSize.width) / 2,
                                y: (imageSize.height - sourceSize.height) / 2,
                                width: sourceSize.width, height: sourceSize.height)
            image.draw(in: cell, from: source, operation: .sourceOver, fraction: 1,
                       respectFlipped: true, hints: [.interpolation: NSNumber(value: NSImageInterpolation.medium.rawValue)])
        }
    }

    private func drawPlayhead(in frame: CGRect) {
        guard playheadSeconds.isFinite, playheadSeconds >= selection.startSeconds,
              playheadSeconds <= selection.endSeconds else { return }
        let position = x(playheadSeconds)
        let line = NSBezierPath()
        line.move(to: CGPoint(x: position, y: frame.minY - 5))
        line.line(to: CGPoint(x: position, y: frame.maxY + 5))
        NSColor.black.withAlphaComponent(0.8).setStroke(); line.lineWidth = 3; line.stroke()
        NSColor.white.setStroke(); line.lineWidth = 1.25; line.stroke()
        let marker = NSBezierPath()
        marker.move(to: CGPoint(x: position - 4, y: frame.minY - 7))
        marker.line(to: CGPoint(x: position + 4, y: frame.minY - 7))
        marker.line(to: CGPoint(x: position, y: frame.minY - 2))
        marker.close(); NSColor.white.setFill(); marker.fill()
    }

    private func handleCenter(_ target: Target) -> CGPoint {
        let offset: CGFloat = selectedFrame.width < 28 ? (target == .start ? -18 : 18) : 0
        return CGPoint(x: x(target == .start ? selection.startSeconds : selection.endSeconds),
                       y: stripFrame.midY + offset)
    }

    private func drawHandle(_ target: Target, at position: CGFloat) {
        let center = handleCenter(target)
        let knob = NSBezierPath(roundedRect: CGRect(x: position - 6, y: center.y - 15, width: 12, height: 30), xRadius: 4, yRadius: 4)
        Palette.accentColor.setFill(); knob.fill()
        let grip = NSBezierPath()
        for offset: CGFloat in [-1.5, 1.5] {
            grip.move(to: CGPoint(x: position + offset, y: center.y - 5))
            grip.line(to: CGPoint(x: position + offset, y: center.y + 5))
        }
        Palette.panelColor.setStroke(); grip.lineWidth = 1; grip.stroke()
        if activeTarget == target, window?.firstResponder === self {
            let ring = NSBezierPath(roundedRect: CGRect(x: position - 9, y: center.y - 18, width: 18, height: 36), xRadius: 6, yRadius: 6)
            Palette.inkColor.setStroke(); ring.lineWidth = 1; ring.stroke()
        }
    }

    private func drawRuler(in frame: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: Palette.mutedColor
        ]
        for mark in 0...4 {
            let value = selection.sourceDuration * Double(mark) / 4
            let label = VideoTrimTime.string(value, milliseconds: selection.sourceDuration < 10) as NSString
            let size = label.size(withAttributes: attributes)
            let originX = min(frame.maxX - size.width, max(frame.minX, x(value) - size.width / 2))
            label.draw(at: CGPoint(x: originX, y: frame.maxY + 12), withAttributes: attributes)
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(stripFrame, cursor: .crosshair)
        addCursorRect(selectedFrame, cursor: .openHand)
        addCursorRect(CGRect(x: stripFrame.minX, y: stripFrame.maxY + 5,
                             width: stripFrame.width, height: 28), cursor: .crosshair)
        for value in [selection.startSeconds, selection.endSeconds] {
            addCursorRect(CGRect(x: x(value) - 10, y: stripFrame.minY - 4,
                                 width: 20, height: stripFrame.height + 8), cursor: .resizeLeftRight)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        guard stripFrame.insetBy(dx: -12, dy: -8).contains(point) ||
                CGRect(x: stripFrame.minX, y: stripFrame.maxY + 5, width: stripFrame.width, height: 28).contains(point) else { return }
        dragOrigin = point
        dragStartSeconds = seconds(at: point)
        selectionAtDragStart = selection
        didDrag = false
        let startDistance = abs(point.x - x(selection.startSeconds))
        let endDistance = abs(point.x - x(selection.endSeconds))
        if point.y <= stripFrame.maxY + 4, min(startDistance, endDistance) <= 12 {
            if selectedFrame.width < 28 {
                let start = handleCenter(.start), end = handleCenter(.end)
                activeTarget = hypot(point.x - start.x, point.y - start.y) <= hypot(point.x - end.x, point.y - end.y) ? .start : .end
            } else { activeTarget = startDistance <= endDistance ? .start : .end }
            drag = activeTarget == .start ? .start : .end
            seek(to: activeTarget == .start ? selection.startSeconds : selection.endSeconds)
        } else if selectedFrame.contains(point) {
            activeTarget = .playhead
            drag = .move
        } else {
            activeTarget = .playhead
            drag = .seek
            seek(to: dragStartSeconds)
        }
        updateAccessibility()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag, let original = selectionAtDragStart else { return }
        let point = convert(event.locationInWindow, from: nil)
        if hypot(point.x - dragOrigin.x, point.y - dragOrigin.y) >= 3 { didDrag = true }
        guard didDrag else { return }
        let value = seconds(at: point)
        let delta = value - dragStartSeconds
        switch drag {
        case .move: setSelection(VideoTrimGeometry.moved(original, by: delta))
        case .start: setSelection(VideoTrimGeometry.startChanged(original, to: original.startSeconds + delta))
        case .end: setSelection(VideoTrimGeometry.endChanged(original, to: original.endSeconds + delta))
        case .seek: seek(to: value)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if drag == .move, !didDrag { seek(to: seconds(at: convert(event.locationInWindow, from: nil))) }
        drag = nil
        selectionAtDragStart = nil
        window?.invalidateCursorRects(for: self)
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.intersection([.command, .control, .option]).isEmpty else { super.keyDown(with: event); return }
        // Letters follow the active keyboard layout, including Turkish F and
        // Dvorak. Navigation keys keep their layout-independent key codes.
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "s": selectTarget(.start); return
        case "e": selectTarget(.end); return
        case "p": selectTarget(.playhead); return
        default: break
        }
        let step = modifiers.contains(.shift) ? 1.0 : 0.01
        switch event.keyCode {
        case 123: adjust(by: -step)
        case 124: adjust(by: step)
        case 49: if !event.isARepeat { onTogglePlayback?() }
        case 48:
            if modifiers.contains(.shift) { window?.selectPreviousKeyView(self) }
            else { window?.selectNextKeyView(self) }
        default: super.keyDown(with: event)
        }
    }

    private func selectTarget(_ target: Target) {
        activeTarget = target
        updateAccessibility()
        NSAccessibility.post(element: self, notification: .valueChanged)
        needsDisplay = true
    }

    private func adjust(by delta: Double) {
        switch activeTarget {
        case .start: setSelection(VideoTrimGeometry.startChanged(selection, to: selection.startSeconds + delta))
        case .end: setSelection(VideoTrimGeometry.endChanged(selection, to: selection.endSeconds + delta))
        case .playhead: seek(to: playheadSeconds + delta)
        }
    }

    private func adjust(_ target: Target, by delta: Double) -> Bool {
        activeTarget = target
        let original = selection, originalPosition = playheadSeconds
        adjust(by: delta)
        return original != selection || originalPosition != playheadSeconds
    }

    private func seek(to seconds: Double) {
        let value = min(selection.endSeconds, max(selection.startSeconds, seconds))
        playheadSeconds = value
        onSeek?(value)
        updateAccessibility()
        NSAccessibility.post(element: self, notification: .valueChanged)
        needsDisplay = true
    }

    private func setSelection(_ value: VideoTrimSelection) {
        guard value != selection else { return }
        selection = value
        onChange?(value)
        updateAccessibility()
        NSAccessibility.post(element: self, notification: .valueChanged)
        needsDisplay = true
    }

    private func updateAccessibleActions() {
        let turkish = language == "tr"
        setAccessibilityCustomActions([
            NSAccessibilityCustomAction(name: turkish ? "Başlangıcı erkene al" : "Move Start Earlier", handler: { [weak self] in self?.adjust(.start, by: -0.01) ?? false }),
            NSAccessibilityCustomAction(name: turkish ? "Başlangıcı ileri al" : "Move Start Later", handler: { [weak self] in self?.adjust(.start, by: 0.01) ?? false }),
            NSAccessibilityCustomAction(name: turkish ? "Bitişi erkene al" : "Move End Earlier", handler: { [weak self] in self?.adjust(.end, by: -0.01) ?? false }),
            NSAccessibilityCustomAction(name: turkish ? "Bitişi ileri al" : "Move End Later", handler: { [weak self] in self?.adjust(.end, by: 0.01) ?? false }),
            NSAccessibilityCustomAction(name: turkish ? "Önizlemeyi geri al" : "Seek Earlier", handler: { [weak self] in self?.adjust(.playhead, by: -0.01) ?? false }),
            NSAccessibilityCustomAction(name: turkish ? "Önizlemeyi ileri al" : "Seek Later", handler: { [weak self] in self?.adjust(.playhead, by: 0.01) ?? false })
        ])
    }

    func updateAccessibility() {
        let start = VideoTrimTime.string(selection.startSeconds), end = VideoTrimTime.string(selection.endSeconds)
        let position = VideoTrimTime.string(playheadSeconds)
        let active: String
        switch activeTarget {
        case .start: active = language == "tr" ? "başlangıç" : "start"
        case .end: active = language == "tr" ? "bitiş" : "end"
        case .playhead: active = language == "tr" ? "oynatma konumu" : "playhead"
        }
        setAccessibilityLabel(language == "tr" ? "Video zaman çizelgesi ve kırpma seçimi" : "Video Timeline and Trim Selection")
        setAccessibilityValue(language == "tr"
            ? "Başlangıç \(start), bitiş \(end), oynatma konumu \(position). Etkin kontrol: \(active)."
            : "Start \(start), end \(end), playhead \(position). Active control: \(active).")
        setAccessibilityHelp(language == "tr"
            ? "S başlangıcı, E bitişi, P oynatma konumunu seçer. Sol ve sağ oklar 0,01 saniye, Shift ile 1 saniye ayarlar. Boşluk oynatır veya duraklatır. Kesin değerler için Başlangıç ve Bitiş alanlarını kullan."
            : "S selects Start, E selects End, P selects the playhead. Left and right arrows adjust by 0.01 seconds, or 1 second with Shift. Space plays or pauses. Use the Start and End fields for exact values.")
    }
}
#endif
