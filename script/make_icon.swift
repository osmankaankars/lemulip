import AppKit

guard CommandLine.arguments.count == 2 else { fatalError("Usage: make_icon.swift OUTPUT.iconset") }
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Could not create icon bitmap") }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let unit = CGFloat(pixels) / 1024
        NSAffineTransform().apply { transform in transform.scale(by: unit); transform.concat() }
        let rect = NSRect(x: 40, y: 40, width: 944, height: 944)
        NSColor(calibratedRed: 0.07, green: 0.105, blue: 0.11, alpha: 1).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 215, yRadius: 215).fill()
        let center = NSPoint(x: 512, y: 512)
        for index in 0..<6 {
            let start = CGFloat(index) * 60 + 8
            let finish = start + 43
            let path = NSBezierPath()
            path.appendArc(withCenter: center, radius: 282, startAngle: start, endAngle: finish)
            path.appendArc(withCenter: center, radius: 157, startAngle: finish, endAngle: start, clockwise: true)
            path.close()
            NSColor(calibratedRed: 0.57, green: 0.92, blue: 0.78, alpha: index == 1 ? 0.42 : 1).setFill()
            path.fill()
        }
        NSColor(calibratedRed: 0.57, green: 0.92, blue: 0.78, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 461, y: 461, width: 102, height: 102)).fill()
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Could not render icon") }
        let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try data.write(to: directory.appendingPathComponent(filename))
    }
}

extension NSAffineTransform {
    func apply(_ body: (NSAffineTransform) -> Void) { body(self) }
}
