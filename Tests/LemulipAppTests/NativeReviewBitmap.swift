#if os(macOS)
import AppKit
import CryptoKit

/// Offscreen drawing of a real view hierarchy, not a screen/window screenshot.
/// The density probe must pass before this path supplies 2x production candidates.
@MainActor
enum NativeReviewBitmap {
    static func render(_ view: NSView, scale: Int) throws -> NSBitmapImageRep {
        let size = view.bounds.size
        guard (1...2).contains(scale), view.bounds.origin == .zero,
              size.width > 0, size.height > 0,
              size.width.rounded() == size.width, size.height.rounded() == size.height else {
            throw NativeReviewFailure("Capture requires positive, integral logical bounds and a 1x or 2x scale")
        }
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let bytes = bitmap.bitmapData else { throw NativeReviewFailure("Could not allocate native review bitmap") }
        bytes.initialize(repeating: 0, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        // Apple's High Resolution Guidelines, listing 3-3: pixels and user size
        // are distinct. AppKit obtains the drawing scale from this context.
        bitmap.size = size
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw NativeReviewFailure("Could not create native review drawing context")
        }
        view.layoutSubtreeIfNeeded()
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        view.displayIgnoringOpacity(view.bounds, in: context)
        // Do not call scaleBy, change layer contentsScale, or resize the result.
        return bitmap
    }

    static func save(_ bitmap: NSBitmapImageRep, of view: NSView, scale: Int,
                     name: String, directory: URL, state: [String: Any]) throws {
        guard let png = bitmap.representation(using: .png, properties: [:]),
              let pixels = bitmap.bitmapData else { throw NativeReviewFailure("Could not encode native review PNG") }
        let pixelData = Data(bytes: pixels, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        try png.write(to: directory.appendingPathComponent(name + ".png"), options: .withoutOverwriting)
        var record = provenance
        record.merge([
            "capture": "NSView.displayIgnoringOpacity(_:in:) of the real hosted view into an NSBitmapImageRep",
            "captureKind": "Offscreen native view rendering; not a screen or window screenshot",
            "logicalWidth": Double(view.bounds.width), "logicalHeight": Double(view.bounds.height),
            "pixelWidth": bitmap.pixelsWide, "pixelHeight": bitmap.pixelsHigh,
            "windowBackingScale": Double(view.window?.backingScaleFactor ?? 0),
            "offscreenRenderScale": scale, "colorSpace": "NSDeviceRGBColorSpace",
            "pngSHA256": digest(png), "pngBytes": png.count,
            "rawPixelSHA256": digest(pixelData), "rawPixelBytesPerRow": bitmap.bytesPerRow,
            "resizedAfterCapture": false, "layerScaleOverridden": false,
            "inputEventsSent": false, "state": state
        ], uniquingKeysWith: { _, value in value })
        try writeJSON(record, name: name, directory: directory)
    }

    static var provenance: [String: Any] {
        ["sourceCommit": ProcessInfo.processInfo.environment["LEMULIP_EDITOR_REVIEW_COMMIT"] ?? "local",
         "workflowRun": ProcessInfo.processInfo.environment["GITHUB_RUN_ID"] ?? "local",
         "workflowAttempt": ProcessInfo.processInfo.environment["GITHUB_RUN_ATTEMPT"] ?? "local",
         "runnerArchitecture": ProcessInfo.processInfo.environment["RUNNER_ARCH"] ?? "local",
         "operatingSystem": ProcessInfo.processInfo.operatingSystemVersionString]
    }

    static func writeJSON(_ value: [String: Any], name: String, directory: URL) throws {
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent(name + ".json"), options: .withoutOverwriting)
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Samples the diagnostic only. No scaled image is created for comparisons.
@MainActor
struct DensityPixels {
    let bitmap: NSBitmapImageRep
    let scale: Int
    let invertedRows: Bool

    init(_ bitmap: NSBitmapImageRep, scale: Int) throws {
        self.bitmap = bitmap
        self.scale = scale
        func isRed(_ color: NSColor?) -> Bool {
            guard let rgb = color?.usingColorSpace(.deviceRGB) else { return false }
            return rgb.redComponent > 0.8 && rgb.greenComponent < 0.2 && rgb.blueComponent < 0.2
        }
        let x = 2 * scale, y = 2 * scale
        if isRed(bitmap.colorAt(x: x, y: y)) { invertedRows = false }
        else if isRed(bitmap.colorAt(x: x, y: bitmap.pixelsHigh - 1 - y)) { invertedRows = true }
        else { throw NativeReviewFailure("The calibration's SwiftUI origin marker is missing") }
    }

    func luminance(x: Int, y: Int) -> Double {
        let row = invertedRows ? bitmap.pixelsHigh - 1 - y : y
        guard let rgb = bitmap.colorAt(x: x, y: row)?.usingColorSpace(.deviceRGB) else { return .nan }
        return Double((rgb.redComponent + rgb.greenComponent + rgb.blueComponent) / 3)
    }

    func stripe(y: Int, phase: Int) -> [String: Any] {
        precondition(scale == 2)
        let values = (4..<124).map { luminance(x: 16 * scale + $0, y: y * scale) }
        let dark = values.enumerated().filter { ($0.offset + phase).isMultiple(of: 2) }.map(\.element)
        let light = values.enumerated().filter { !($0.offset + phase).isMultiple(of: 2) }.map(\.element)
        let darkMean = dark.reduce(0, +) / Double(dark.count)
        let lightMean = light.reduce(0, +) / Double(light.count)
        return ["darkMean": darkMean, "lightMean": lightMean,
                "contrast": lightMean - darkMean, "sampleColumns": values,
                "passed": darkMean < 0.2 && lightMean > 0.8 && lightMean - darkMean > 0.7]
    }

    /// Glyph-region detail is supporting evidence alongside both resolved stripe
    /// fields and fresh native draw CTMs. It is never the sole density gate.
    func textDetail(comparedTo one: DensityPixels, top: Int) -> [String: Any] {
        var nearestError = 0.0, linearError = 0.0
        var inkSamples = 0, varyingBlocks = 0
        for y in top..<(top + 26) {
            for x in 16..<296 {
                let samples = (0..<4).map { index in luminance(x: x * 2 + index % 2, y: y * 2 + index / 2) }
                if (samples.max() ?? 0) - (samples.min() ?? 0) > 0.12 { varyingBlocks += 1 }
                for index in 0..<4 {
                    let value = samples[index]
                    let source = one.luminance(x: x, y: y)
                    guard value < 0.98 || source < 0.98 else { continue }
                    // Pixel-center mapping for a hypothetical bilinear 1x enlargement.
                    // Evaluate its value only; never save or use an enlarged bitmap.
                    let adjacentX = x + (index % 2 == 0 ? -1 : 1)
                    let adjacentY = y + (index / 2 == 0 ? -1 : 1)
                    let linear = source * 0.5625
                        + one.luminance(x: adjacentX, y: y) * 0.1875
                        + one.luminance(x: x, y: adjacentY) * 0.1875
                        + one.luminance(x: adjacentX, y: adjacentY) * 0.0625
                    nearestError += abs(value - source)
                    linearError += abs(value - linear)
                    inkSamples += 1
                }
            }
        }
        let nearest = nearestError / Double(max(inkSamples, 1))
        let linear = linearError / Double(max(inkSamples, 1))
        return ["inkSamples": inkSamples, "varyingTwoByTwoBlocks": varyingBlocks,
                "meanErrorFromNearest1x": nearest, "meanErrorFromBilinear1x": linear,
                "passed": inkSamples >= 100 && varyingBlocks >= 12 && nearest > 0.03 && linear > 0.02]
    }
}

struct NativeReviewFailure: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
#endif
