import AppKit

guard CommandLine.arguments.count == 3,
      let artwork = NSImage(contentsOfFile: CommandLine.arguments[1]),
      artwork.isValid else {
    fatalError("Usage: make_icon.swift INPUT.png OUTPUT.iconset")
}
let directory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

// Rasterize the reviewed master once at build time. The app only ships its ICNS;
// there is no runtime image generator, 3D engine, or animation dependency.
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        // Tag the blank RGB bitmap as sRGB before creating its drawing context.
        guard let baseBitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let bitmap = baseBitmap.retagging(with: NSColorSpace.sRGB),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Could not create icon bitmap") }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        artwork.draw(in: NSRect(x: 0, y: 0, width: CGFloat(pixels), height: CGFloat(pixels)),
                     from: .zero, operation: .copy, fraction: 1,
                     respectFlipped: false, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Could not render icon") }
        let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try data.write(to: directory.appendingPathComponent(filename))
    }
}
