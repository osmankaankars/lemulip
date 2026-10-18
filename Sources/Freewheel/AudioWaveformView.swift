#if os(macOS)
import AppKit
import SwiftUI
import FreewheelCore

@MainActor
struct AudioWaveformView: NSViewRepresentable {
    let peaks: [Float]
    @Binding var selection: AudioTrimSelection
    let playheadSeconds: Double
    let theme: AppTheme
    let language: String
    let onTogglePlayback: () -> Void

    func makeNSView(context: Context) -> AudioWaveformCanvas {
        let view = AudioWaveformCanvas(peaks: peaks)
        configure(view)
        return view
    }

    func updateNSView(_ view: AudioWaveformCanvas, context: Context) { configure(view) }

    private func configure(_ view: AudioWaveformCanvas) {
        let selectionChanged = view.selection != selection
        let languageChanged = view.language != language
        view.selection = selection
        view.playheadSeconds = playheadSeconds
        view.theme = theme
        view.language = language
        view.onChange = { selection = $0 }
        view.onTogglePlayback = onTogglePlayback
        if selectionChanged || languageChanged { view.updateAccessibility() }
        view.needsDisplay = true
        if selectionChanged { view.window?.invalidateCursorRects(for: view) }
    }
}

/// Reuses a bounded, precomputed waveform path. Moving the playhead does not
/// decode audio or rebuild the path, and no timer runs while the editor is idle.
@MainActor
final class AudioWaveformCanvas: NSView {
    private enum Handle { case start, end }
    private enum Drag { case handle(Handle), move }

    private let peaks: [Float]
    private var cachedWaveform = NSBezierPath()
    private var cachedFrame = CGRect.zero
    private var activeHandle = Handle.start
    private var drag: Drag?
    private var dragStartSeconds: Double = 0
    private var selectionAtDragStart: AudioTrimSelection?

    var selection = AudioTrimSelection(startSeconds: 0, endSeconds: 1, sourceDuration: 1)
    var playheadSeconds: Double = 0
    var theme = AppTheme.orchardNight
    var language = "en" {
        didSet { if oldValue != language { updateAccessibleActions() } }
    }
    var onChange: ((AudioTrimSelection) -> Void)?
    var onTogglePlayback: (() -> Void)?

    init(peaks: [Float]) {
        self.peaks = peaks
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

    private var waveformFrame: CGRect {
        CGRect(x: 25, y: 23, width: max(0, bounds.width - 50), height: max(0, bounds.height - 63))
    }
    private func x(_ seconds: Double) -> CGFloat {
        guard selection.sourceDuration > 0, seconds.isFinite else { return waveformFrame.minX }
        return waveformFrame.minX + CGFloat(max(0, min(1, seconds / selection.sourceDuration))) * waveformFrame.width
    }
    private func seconds(at point: CGPoint) -> Double {
        guard waveformFrame.width > 0 else { return 0 }
        return Double(max(0, min(1, (point.x - waveformFrame.minX) / waveformFrame.width))) * selection.sourceDuration
    }
    private var selectedFrame: CGRect {
        CGRect(x: x(selection.startSeconds), y: waveformFrame.minY,
               width: max(0, x(selection.endSeconds) - x(selection.startSeconds)), height: waveformFrame.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        Palette.raisedColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14).fill()
        let frame = waveformFrame
        guard frame.width > 0, frame.height > 0 else { return }
        rebuildWaveformIfNeeded(frame)

        Palette.accentColor.withAlphaComponent(0.08).setFill()
        NSBezierPath.fill(selectedFrame)
        Palette.lineColor.setStroke()
        let baseline = NSBezierPath()
        baseline.move(to: CGPoint(x: frame.minX, y: frame.midY))
        baseline.line(to: CGPoint(x: frame.maxX, y: frame.midY))
        baseline.lineWidth = 1; baseline.stroke()
        Palette.mutedColor.withAlphaComponent(0.45).setStroke()
        cachedWaveform.stroke()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: selectedFrame).addClip()
        Palette.accentColor.setStroke()
        cachedWaveform.stroke()
        NSGraphicsContext.restoreGraphicsState()

        let outline = NSBezierPath(rect: selectedFrame)
        Palette.accentColor.withAlphaComponent(0.5).setStroke()
        outline.lineWidth = 1; outline.stroke()
        drawRuler(in: frame)

        if playheadSeconds.isFinite, playheadSeconds >= selection.startSeconds,
           playheadSeconds <= selection.endSeconds {
            let playhead = NSBezierPath()
            let position = x(playheadSeconds)
            playhead.move(to: CGPoint(x: position, y: frame.minY - 6))
            playhead.line(to: CGPoint(x: position, y: frame.maxY + 6))
            Palette.panelColor.setStroke(); playhead.lineWidth = 3; playhead.stroke()
            Palette.inkColor.setStroke(); playhead.lineWidth = 1.25; playhead.stroke()
            let marker = NSBezierPath()
            marker.move(to: CGPoint(x: position - 4, y: frame.minY - 8))
            marker.line(to: CGPoint(x: position + 4, y: frame.minY - 8))
            marker.line(to: CGPoint(x: position, y: frame.minY - 3))
            marker.close(); Palette.inkColor.setFill(); marker.fill()
        }
        drawHandle(.start, at: x(selection.startSeconds))
        drawHandle(.end, at: x(selection.endSeconds))
        if window?.firstResponder === self {
            let focus = NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 3), xRadius: 11, yRadius: 11)
            Palette.accentColor.setStroke(); focus.lineWidth = 2; focus.stroke()
        }
    }

    private func rebuildWaveformIfNeeded(_ frame: CGRect) {
        guard cachedFrame != frame else { return }
        cachedFrame = frame
        let path = NSBezierPath()
        path.lineWidth = 2
        path.lineCapStyle = .round
        guard !peaks.isEmpty else { cachedWaveform = path; return }
        let count = min(peaks.count, max(1, Int(frame.width / 3)))
        for bucket in 0..<count {
            let lower = bucket * peaks.count / count
            let upper = max(lower + 1, (bucket + 1) * peaks.count / count)
            let peak = peaks[lower..<min(peaks.count, upper)].reduce(Float.zero) { result, value in
                value.isFinite ? max(result, min(1, abs(value))) : result
            }
            let height = max(0.5, CGFloat(peak) * (frame.height / 2 - 10))
            let position = frame.minX + (CGFloat(bucket) + 0.5) / CGFloat(count) * frame.width
            path.move(to: CGPoint(x: position, y: frame.midY - height))
            path.line(to: CGPoint(x: position, y: frame.midY + height))
        }
        cachedWaveform = path
    }

    private func drawHandle(_ handle: Handle, at position: CGFloat) {
        let frame = waveformFrame
        let center = handleCenter(handle)
        let line = NSBezierPath()
        line.move(to: CGPoint(x: position, y: frame.minY))
        line.line(to: CGPoint(x: position, y: frame.maxY))
        Palette.accentColor.setStroke(); line.lineWidth = 2; line.stroke()
        let knob = NSBezierPath(roundedRect: CGRect(x: position - 6, y: center.y - 19, width: 12, height: 38),
                                xRadius: 5, yRadius: 5)
        Palette.accentColor.setFill(); knob.fill()
        let grip = NSBezierPath()
        for offset: CGFloat in [-1.5, 1.5] {
            grip.move(to: CGPoint(x: position + offset, y: center.y - 5))
            grip.line(to: CGPoint(x: position + offset, y: center.y + 5))
        }
        Palette.panelColor.setStroke(); grip.lineWidth = 1; grip.stroke()
        if activeHandle == handle, window?.firstResponder === self {
            let ring = NSBezierPath(roundedRect: CGRect(x: position - 9, y: center.y - 22, width: 18, height: 44),
                                    xRadius: 7, yRadius: 7)
            Palette.inkColor.setStroke(); ring.lineWidth = 1; ring.stroke()
        }
    }

    private func handleCenter(_ handle: Handle) -> CGPoint {
        // Keep both handles reachable when a short selection is narrower than
        // their hit targets. Their timeline positions remain unchanged.
        let offset: CGFloat = selectedFrame.width < 28 ? (handle == .start ? -26 : 26) : 0
        return CGPoint(x: x(handle == .start ? selection.startSeconds : selection.endSeconds),
                       y: waveformFrame.midY + offset)
    }

    private func drawRuler(in frame: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: Palette.mutedColor
        ]
        for mark in 0...4 {
            let value = selection.sourceDuration * Double(mark) / 4
            let label = AudioTrimTime.string(value, milliseconds: selection.sourceDuration < 10) as NSString
            let size = label.size(withAttributes: attributes)
            let position = x(value)
            let originX = min(frame.maxX - size.width, max(frame.minX, position - size.width / 2))
            label.draw(at: CGPoint(x: originX, y: frame.maxY + 13), withAttributes: attributes)
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(waveformFrame, cursor: .crosshair)
        addCursorRect(selectedFrame, cursor: .openHand)
        for value in [selection.startSeconds, selection.endSeconds] {
            addCursorRect(CGRect(x: x(value) - 10, y: waveformFrame.minY - 4,
                                 width: 20, height: waveformFrame.height + 8), cursor: .resizeLeftRight)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        guard waveformFrame.insetBy(dx: -12, dy: -8).contains(point) else { return }
        let startDistance = abs(point.x - x(selection.startSeconds))
        let endDistance = abs(point.x - x(selection.endSeconds))
        if min(startDistance, endDistance) <= 12 {
            if selectedFrame.width < 28 {
                let start = handleCenter(.start), end = handleCenter(.end)
                activeHandle = hypot(point.x - start.x, point.y - start.y) <= hypot(point.x - end.x, point.y - end.y) ? .start : .end
            } else {
                activeHandle = startDistance <= endDistance ? .start : .end
            }
            drag = .handle(activeHandle)
        } else if selectedFrame.contains(point) {
            drag = .move
        } else {
            activeHandle = startDistance <= endDistance ? .start : .end
            drag = .handle(activeHandle)
            changeActiveHandle(to: seconds(at: point))
        }
        dragStartSeconds = seconds(at: point)
        selectionAtDragStart = selection
        needsDisplay = true
        updateAccessibility()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag, let original = selectionAtDragStart else { return }
        let value = seconds(at: convert(event.locationInWindow, from: nil))
        switch drag {
        case .move: setSelection(AudioTrimGeometry.moved(original, by: value - dragStartSeconds))
        case .handle(let handle):
            activeHandle = handle
            let delta = value - dragStartSeconds
            if handle == .start { setSelection(AudioTrimGeometry.startChanged(original, to: original.startSeconds + delta)) }
            else { setSelection(AudioTrimGeometry.endChanged(original, to: original.endSeconds + delta)) }
        }
    }

    override func mouseUp(with event: NSEvent) {
        drag = nil
        selectionAtDragStart = nil
        window?.invalidateCursorRects(for: self)
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.intersection([.command, .control, .option]).isEmpty else {
            super.keyDown(with: event); return
        }
        let step = modifiers.contains(.shift) ? 1.0 : 0.01
        switch event.keyCode {
        case 123: adjustActiveHandle(by: -step)
        case 124: adjustActiveHandle(by: step)
        case 1: selectHandle(.start)
        case 14: selectHandle(.end)
        case 49: onTogglePlayback?()
        case 48:
            if modifiers.contains(.shift) { window?.selectPreviousKeyView(self) }
            else { window?.selectNextKeyView(self) }
        default: super.keyDown(with: event)
        }
    }

    private func changeActiveHandle(to value: Double) {
        if activeHandle == .start { setSelection(AudioTrimGeometry.startChanged(selection, to: value)) }
        else { setSelection(AudioTrimGeometry.endChanged(selection, to: value)) }
    }
    private func selectHandle(_ handle: Handle) {
        activeHandle = handle
        needsDisplay = true
        updateAccessibility()
        NSAccessibility.post(element: self, notification: .valueChanged)
    }
    private func adjustActiveHandle(by delta: Double) {
        changeActiveHandle(to: (activeHandle == .start ? selection.startSeconds : selection.endSeconds) + delta)
    }
    private func adjust(_ handle: Handle, by delta: Double) -> Bool {
        activeHandle = handle
        let original = selection
        adjustActiveHandle(by: delta)
        return original != selection
    }
    private func setSelection(_ value: AudioTrimSelection) {
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
            NSAccessibilityCustomAction(name: turkish ? "Bitişi ileri al" : "Move End Later", handler: { [weak self] in self?.adjust(.end, by: 0.01) ?? false })
        ])
    }
    func updateAccessibility() {
        let start = AudioTrimTime.string(selection.startSeconds)
        let end = AudioTrimTime.string(selection.endSeconds)
        let active = activeHandle == .start ? (language == "tr" ? "başlangıç" : "start") : (language == "tr" ? "bitiş" : "end")
        setAccessibilityLabel(language == "tr" ? "Ses dalgası ve kırpma seçimi" : "Audio Waveform and Trim Selection")
        setAccessibilityValue(language == "tr" ? "Başlangıç \(start), bitiş \(end). Etkin tutamak: \(active)."
                              : "Start \(start), end \(end). Active handle: \(active).")
        setAccessibilityHelp(language == "tr"
            ? "S başlangıcı, E bitişi seçer. Sol ve sağ oklar 0,01 saniye, Shift ile 1 saniye ayarlar. Boşluk seçimi oynatır veya duraklatır. Kesin değerler için başlangıç ve bitiş alanlarını kullan."
            : "S selects the start handle; E selects the end. Left and right arrows adjust by 0.01 seconds, or 1 second with Shift. Space plays or pauses the selection. Use the Start and End fields for exact values.")
    }
}

#endif
