#if os(macOS)
import AppKit
import SwiftUI
import FreewheelCore

enum CropAspectRatio: String, CaseIterable, Identifiable {
    case free = "Free", original = "Original", square = "1:1"
    case landscape = "4:3", portrait = "3:4", wide = "16:9", tall = "9:16"
    var id: String { rawValue }

    func value(width: Int, height: Int) -> Double? {
        switch self {
        case .free: return nil
        case .original: return Double(width) / Double(height)
        case .square: return 1
        case .landscape: return 4 / 3
        case .portrait: return 3 / 4
        case .wide: return 16 / 9
        case .tall: return 9 / 16
        }
    }
}

enum CropCanvasMedia { case image, video }

/// Both the live video surface and its crop overlay use this same rectangle.
/// View coordinates are display points; the selection remains in source pixels.
enum CropCanvasLayout {
    static func imageFrame(in bounds: CGRect, sourceWidth: Int, sourceHeight: Int) -> CGRect {
        let available = bounds.insetBy(dx: 20, dy: 20)
        guard available.width > 0, available.height > 0, sourceWidth > 0, sourceHeight > 0 else { return .zero }
        let scale = min(available.width / CGFloat(sourceWidth), available.height / CGFloat(sourceHeight))
        let size = CGSize(width: CGFloat(sourceWidth) * scale, height: CGFloat(sourceHeight) * scale)
        return CGRect(x: available.midX - size.width / 2, y: available.midY - size.height / 2,
                      width: size.width, height: size.height)
    }
}

/// The canvas displays a bounded preview, but all editing uses original pixels.
@MainActor
struct CropCanvasView: NSViewRepresentable {
    let image: CGImage
    @Binding var selection: ImageCropRegion
    let aspectRatio: Double?
    let showsGrid: Bool
    let theme: AppTheme
    let language: String
    var media = CropCanvasMedia.image
    var selectionTransform: ((ImageCropRegion) -> ImageCropRegion)?
    var onInteractionBegan: (() -> Void)?
    var onTogglePlayback: (() -> Void)?

    func makeNSView(context: Context) -> ImageCropCanvas {
        let view = ImageCropCanvas(image: image)
        configure(view, forceUpdate: true)
        return view
    }

    func updateNSView(_ view: ImageCropCanvas, context: Context) {
        configure(view)
    }

    static func dismantleNSView(_ view: ImageCropCanvas, coordinator: ()) {
        view.onChange = nil
        view.selectionTransform = nil
        view.onInteractionBegan = nil
        view.onTogglePlayback = nil
    }

    private func configure(_ view: ImageCropCanvas, forceUpdate: Bool = false) {
        let selectionChanged = view.selection != selection
        let mediaChanged = view.media != media
        let languageChanged = view.language != language
        let visualChanged = selectionChanged || mediaChanged || view.showsGrid != showsGrid || view.theme != theme
        view.selection = selection
        view.aspectRatio = aspectRatio
        view.showsGrid = showsGrid
        view.theme = theme
        view.language = language
        view.media = media
        view.selectionTransform = selectionTransform
        view.onInteractionBegan = onInteractionBegan
        view.onTogglePlayback = onTogglePlayback
        view.onChange = { selection = $0 }
        if forceUpdate || selectionChanged || mediaChanged || languageChanged { view.updateAccessibility() }
        if forceUpdate || visualChanged { view.needsDisplay = true }
        if forceUpdate || selectionChanged { view.window?.invalidateCursorRects(for: view) }
    }
}

@MainActor
final class ImageCropCanvas: NSView {
    private enum Drag {
        case move
        case resize(ImageCropHandle)
        case select
    }

    private let preview: NSImage
    private var drag: Drag?
    private var dragStart = CGPoint.zero
    private var selectionAtDragStart: ImageCropRegion?

    var selection = ImageCropGeometry.fullImage(width: 1, height: 1)
    var aspectRatio: Double?
    var showsGrid = true
    var theme = AppTheme.orchardNight
    var language = "en" {
        didSet { if language != oldValue { updateAccessibleActions() } }
    }
    var media = CropCanvasMedia.image {
        didSet { if media != oldValue { updateAccessibleActions() } }
    }
    var selectionTransform: ((ImageCropRegion) -> ImageCropRegion)?
    var onInteractionBegan: (() -> Void)?
    var onTogglePlayback: (() -> Void)?
    var onChange: ((ImageCropRegion) -> Void)?

    init(image: CGImage) {
        preview = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        updateAccessibleActions()
    }

    required init?(coder: NSCoder) { return nil }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    private var imageFrame: CGRect {
        CropCanvasLayout.imageFrame(in: bounds, sourceWidth: selection.sourceWidth, sourceHeight: selection.sourceHeight)
    }

    private var selectionFrame: CGRect {
        let frame = imageFrame
        let scaleX = frame.width / CGFloat(selection.sourceWidth)
        let scaleY = frame.height / CGFloat(selection.sourceHeight)
        return CGRect(x: frame.minX + CGFloat(selection.x) * scaleX,
                      y: frame.minY + CGFloat(selection.y) * scaleY,
                      width: CGFloat(selection.width) * scaleX,
                      height: CGFloat(selection.height) * scaleY)
    }

    override func draw(_ dirtyRect: NSRect) {
        if media == .image {
            Palette.raisedColor.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14).fill()
        }
        let frame = imageFrame
        guard frame.width > 0, frame.height > 0 else { return }

        if media == .image {
            // A small, static checkerboard makes transparent pixels distinguishable.
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: frame).addClip()
            NSColor(white: 0.82, alpha: 1).setFill()
            NSBezierPath.fill(frame)
            NSColor(white: 0.94, alpha: 1).setFill()
            let cell: CGFloat = 12
            for row in 0...Int(ceil(frame.height / cell)) {
                for column in 0...Int(ceil(frame.width / cell)) where (row + column).isMultiple(of: 2) {
                    NSBezierPath.fill(CGRect(x: frame.minX + CGFloat(column) * cell,
                                           y: frame.minY + CGFloat(row) * cell, width: cell, height: cell))
                }
            }
            NSGraphicsContext.current?.imageInterpolation = .high
            preview.draw(in: frame, from: CGRect(origin: .zero, size: preview.size),
                         operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
        }

        let crop = selectionFrame
        NSColor.black.withAlphaComponent(0.52).setFill()
        NSBezierPath.fill(CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: max(0, crop.minY - frame.minY)))
        NSBezierPath.fill(CGRect(x: frame.minX, y: crop.maxY, width: frame.width, height: max(0, frame.maxY - crop.maxY)))
        NSBezierPath.fill(CGRect(x: frame.minX, y: crop.minY, width: max(0, crop.minX - frame.minX), height: crop.height))
        NSBezierPath.fill(CGRect(x: crop.maxX, y: crop.minY, width: max(0, frame.maxX - crop.maxX), height: crop.height))

        if showsGrid {
            let grid = NSBezierPath()
            for fraction: CGFloat in [1 / 3, 2 / 3] {
                grid.move(to: CGPoint(x: crop.minX + crop.width * fraction, y: crop.minY))
                grid.line(to: CGPoint(x: crop.minX + crop.width * fraction, y: crop.maxY))
                grid.move(to: CGPoint(x: crop.minX, y: crop.minY + crop.height * fraction))
                grid.line(to: CGPoint(x: crop.maxX, y: crop.minY + crop.height * fraction))
            }
            NSColor.black.withAlphaComponent(0.35).setStroke()
            grid.lineWidth = 2; grid.stroke()
            NSColor.white.withAlphaComponent(0.75).setStroke()
            grid.lineWidth = 0.75; grid.stroke()
        }

        let outline = NSBezierPath(rect: crop)
        NSColor.black.withAlphaComponent(0.85).setStroke()
        outline.lineWidth = 3; outline.stroke()
        NSColor.white.setStroke()
        outline.lineWidth = 1.5; outline.stroke()
        for handle in ImageCropHandle.allCases {
            let center = point(for: handle)
            let marker = NSBezierPath(roundedRect: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8),
                                     xRadius: 2, yRadius: 2)
            NSColor.white.setFill(); marker.fill()
            NSColor.black.withAlphaComponent(0.8).setStroke()
            marker.lineWidth = 1; marker.stroke()
        }
        if window?.firstResponder === self {
            let focus = NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 3), xRadius: 11, yRadius: 11)
            Palette.accentColor.setStroke()
            focus.lineWidth = 2; focus.stroke()
        }
    }

    private func point(for handle: ImageCropHandle) -> CGPoint {
        let frame = selectionFrame
        switch handle {
        case .topLeft: return CGPoint(x: frame.minX, y: frame.minY)
        case .top: return CGPoint(x: frame.midX, y: frame.minY)
        case .topRight: return CGPoint(x: frame.maxX, y: frame.minY)
        case .right: return CGPoint(x: frame.maxX, y: frame.midY)
        case .bottomRight: return CGPoint(x: frame.maxX, y: frame.maxY)
        case .bottom: return CGPoint(x: frame.midX, y: frame.maxY)
        case .bottomLeft: return CGPoint(x: frame.minX, y: frame.maxY)
        case .left: return CGPoint(x: frame.minX, y: frame.midY)
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(imageFrame, cursor: .crosshair)
        addCursorRect(selectionFrame, cursor: .openHand)
        for handle in ImageCropHandle.allCases {
            let center = point(for: handle)
            let cursor: NSCursor
            switch handle {
            case .left, .right: cursor = .resizeLeftRight
            case .top, .bottom: cursor = .resizeUpDown
            default: cursor = .crosshair
            }
            addCursorRect(CGRect(x: center.x - 10, y: center.y - 10, width: 20, height: 20), cursor: cursor)
        }
    }

    private func imagePoint(_ point: CGPoint) -> CGPoint {
        let frame = imageFrame
        guard frame.width > 0, frame.height > 0 else { return .zero }
        return CGPoint(x: max(0, min(CGFloat(selection.sourceWidth),
                                    (point.x - frame.minX) / frame.width * CGFloat(selection.sourceWidth))),
                       y: max(0, min(CGFloat(selection.sourceHeight),
                                    (point.y - frame.minY) / frame.height * CGFloat(selection.sourceHeight))))
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let location = convert(event.locationInWindow, from: nil)
        guard imageFrame.insetBy(dx: -10, dy: -10).contains(location) else { return }
        onInteractionBegan?()
        let nearest = ImageCropHandle.allCases.min { first, second in
            let a = point(for: first), b = point(for: second)
            return hypot(a.x - location.x, a.y - location.y) < hypot(b.x - location.x, b.y - location.y)
        }
        if let handle = nearest, hypot(point(for: handle).x - location.x, point(for: handle).y - location.y) <= 12 {
            drag = .resize(handle)
        } else if selectionFrame.contains(location) {
            drag = .move
        } else {
            drag = .select
        }
        dragStart = imagePoint(location)
        selectionAtDragStart = selection
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag, let original = selectionAtDragStart else { return }
        let point = imagePoint(convert(event.locationInWindow, from: nil))
        let dx = Double(point.x - dragStart.x), dy = Double(point.y - dragStart.y)
        switch drag {
        case .move:
            setSelection(ImageCropGeometry.moved(original, dx: dx, dy: dy))
        case .resize(let handle):
            setSelection(ImageCropGeometry.resized(original, handle: handle, dx: dx, dy: dy, aspectRatio: aspectRatio))
        case .select:
            setSelection(ImageCropGeometry.selected(fromX: Double(dragStart.x), fromY: Double(dragStart.y),
                toX: Double(point.x), toY: Double(point.y), sourceWidth: original.sourceWidth,
                sourceHeight: original.sourceHeight, aspectRatio: aspectRatio))
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
        let step: Double = modifiers.contains(.shift) ? 10 : 1
        switch event.keyCode {
        case 123: move(dx: -step, dy: 0)
        case 124: move(dx: step, dy: 0)
        case 125: move(dx: 0, dy: step)
        case 126: move(dx: 0, dy: -step)
        case 49:
            if media == .video {
                if !event.isARepeat { onTogglePlayback?() }
            } else { super.keyDown(with: event) }
        case 48:
            if modifiers.contains(.shift) { window?.selectPreviousKeyView(self) }
            else { window?.selectNextKeyView(self) }
        default: super.keyDown(with: event)
        }
    }

    private func move(dx: Double, dy: Double) {
        setSelection(ImageCropGeometry.moved(selection, dx: dx, dy: dy))
    }

    private func updateAccessibleActions() {
        let turkish = language == "tr"
        var actions = [
            NSAccessibilityCustomAction(name: turkish ? "Kırpma alanını sola taşı" : "Move Crop Left", handler: { [weak self] in self?.move(dx: -1, dy: 0); return self != nil }),
            NSAccessibilityCustomAction(name: turkish ? "Kırpma alanını sağa taşı" : "Move Crop Right", handler: { [weak self] in self?.move(dx: 1, dy: 0); return self != nil }),
            NSAccessibilityCustomAction(name: turkish ? "Kırpma alanını yukarı taşı" : "Move Crop Up", handler: { [weak self] in self?.move(dx: 0, dy: -1); return self != nil }),
            NSAccessibilityCustomAction(name: turkish ? "Kırpma alanını aşağı taşı" : "Move Crop Down", handler: { [weak self] in self?.move(dx: 0, dy: 1); return self != nil })
        ]
        if media == .video {
            actions.append(NSAccessibilityCustomAction(name: turkish ? "Videoyu oynat veya duraklat" : "Play or Pause Video", handler: { [weak self] in
                guard let self, let toggle = self.onTogglePlayback else { return false }
                toggle()
                return true
            }))
        }
        setAccessibilityCustomActions(actions)
    }

    private func setSelection(_ value: ImageCropRegion) {
        let value = selectionTransform?(value) ?? value
        guard value != selection else { return }
        selection = value
        onChange?(value)
        updateAccessibility()
        NSAccessibility.post(element: self, notification: .valueChanged)
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    func updateAccessibility() {
        setAccessibilityLabel(media == .video
            ? (language == "tr" ? "Video kırpma alanı" : "Video Crop Canvas")
            : (language == "tr" ? "Görsel kırpma alanı" : "Image Crop Canvas"))
        var help = language == "tr"
            ? "Seçimi ok tuşlarıyla bir piksel, Shift ile on piksel taşı. Boyutu değiştirmek için genişlik ve yükseklik alanlarını kullan."
            : "Move the selection one pixel with arrow keys, or ten with Shift. Use the width and height fields to resize."
        if media == .video {
            help += language == "tr" ? " Boşluk videoyu oynatır veya duraklatır." : " Space plays or pauses the video."
        }
        setAccessibilityHelp(help)
        setAccessibilityValue(language == "tr"
            ? "\(selection.width) × \(selection.height) piksel; sol \(selection.x), üst \(selection.y)"
            : "\(selection.width) by \(selection.height) pixels; left \(selection.x), top \(selection.y)")
    }
}
#endif
