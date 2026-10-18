#if os(macOS)
import XCTest
import AppKit
import AVFoundation
import CoreGraphics
import CoreVideo
import CoreText
import ImageIO
import PDFKit
@testable import FreewheelCore

/// All media fixtures are generated here. No user files, screenshots, document
/// contents, or machine-specific paths are checked into the repository.
final class NativeConverterTests: XCTestCase {
    private struct Workspace {
        let root: URL
        let inputs: URL
        let stage: URL
    }

    private func workspace() throws -> Workspace {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("freewheel-native-tests-\(UUID().uuidString)", isDirectory: true)
        let inputs = root.appendingPathComponent("input", isDirectory: true)
        let stage = root.appendingPathComponent("stage", isDirectory: true)
        try FileManager.default.createDirectory(at: inputs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return Workspace(root: root, inputs: inputs, stage: stage)
    }

    private func freshStage(_ workspace: Workspace) throws -> URL {
        let url = workspace.root.appendingPathComponent("stage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func operation(_ id: String, ext: String? = nil) -> FileOperation {
        FileOperation(id: id, title: id, outputExtension: ext)
    }

    private func bitmap(width: Int, height: Int, draw: (CGContext) -> Void) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        draw(context)
        return try XCTUnwrap(context.makeImage())
    }

    @discardableResult
    private func image(_ url: URL, width: Int = 60, height: Int = 30,
                       type: String = "public.png", metadata: [CFString: Any] = [:],
                       draw: ((CGContext) -> Void)? = nil) throws -> URL {
        let pixels = try bitmap(width: width, height: height) { context in
            if let draw = draw { draw(context) }
            else {
                context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.4, alpha: 1))
                context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            }
        }
        let writer = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil))
        CGImageDestinationAddImage(writer, pixels, metadata as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
        return url
    }

    private func decodedImage(_ url: URL) throws -> CGImage {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private func color(_ image: CGImage, x: Int, y: Int) throws -> NSColor {
        // Sample in the fixture's explicit sRGB space, without an AppKit color-space round trip.
        // A one-pixel image also keeps CGContext's drawing axes out of pixel-coordinate checks.
        let pixel = try XCTUnwrap(image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)))
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
            bytesPerRow: 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.setBlendMode(.copy)
        context.interpolationQuality = .none
        context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return try withExtendedLifetime(context) {
            let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
            let alpha = CGFloat(bytes[3]) / 255
            // The context stores premultiplied RGB; NSColor expects unassociated components.
            let divisor = CGFloat(max(1, bytes[3]))
            return NSColor(srgbRed: CGFloat(bytes[0]) / divisor, green: CGFloat(bytes[1]) / divisor,
                           blue: CGFloat(bytes[2]) / divisor, alpha: alpha)
        }
    }

    /// Explicit top-to-bottom rows avoid relying on CGContext's drawing axes.
    private func pixelFile(_ url: URL, width: Int, height: Int, rgba: [UInt8],
                           type: String = "public.png", orientation: Int = 1, frames: Int = 1) throws -> URL {
        XCTAssertEqual(rgba.count, width * height * 4)
        let provider = try XCTUnwrap(CGDataProvider(data: Data(rgba) as CFData))
        let pixels = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8,
            bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let writer = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type as CFString, frames, nil))
        for _ in 0..<frames {
            CGImageDestinationAddImage(writer, pixels, [
                kCGImagePropertyOrientation: orientation,
                kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFOrientation: orientation]
            ] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(writer))
        return url
    }

    private func assertPixel(_ image: CGImage, x: Int, y: Int, rgba: [UInt8],
                             file: StaticString = #filePath, line: UInt = #line) throws {
        let pixel = try color(image, x: x, y: y)
        XCTAssertEqual(pixel.alphaComponent, CGFloat(rgba[3]) / 255, accuracy: 0.02, file: file, line: line)
        if rgba[3] > 0 {
            XCTAssertEqual(pixel.redComponent, CGFloat(rgba[0]) / 255, accuracy: 0.02, file: file, line: line)
            XCTAssertEqual(pixel.greenComponent, CGFloat(rgba[1]) / 255, accuracy: 0.02, file: file, line: line)
            XCTAssertEqual(pixel.blueComponent, CGFloat(rgba[2]) / 255, accuracy: 0.02, file: file, line: line)
        }
    }

    @discardableResult
    private func pdf(_ url: URL, pages: [(CGSize, String)]) throws -> URL {
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: nil, nil))
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        for (size, text) in pages {
            var box = CGRect(origin: .zero, size: size)
            context.beginPDFPage([kCGPDFContextMediaBox as String: Data(bytes: &box, count: MemoryLayout<CGRect>.size)] as CFDictionary)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(box)
            if !text.isEmpty {
                let string = NSAttributedString(string: text, attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font,
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
                ])
                context.textPosition = CGPoint(x: 12, y: max(12, size.height - 24))
                CTLineDraw(CTLineCreateWithAttributedString(string), context)
            }
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }

    func testJPEGOrientationIsAppliedOnceAndGPSMetadataIsRemoved() async throws {
        let work = try workspace()
        let source = try image(work.inputs.appendingPathComponent("oriented.jpg"), width: 60, height: 30,
                               type: "public.jpeg", metadata: [
                                kCGImagePropertyOrientation: 6,
                                kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 1.0,
                                    kCGImagePropertyGPSLatitudeRef: "N", kCGImagePropertyGPSLongitude: 2.0,
                                    kCGImagePropertyGPSLongitudeRef: "E"]
                               ])
        let original = try Data(contentsOf: source)
        let result = try await NativeConverter.convert(inputs: [source], operation: operation("convert.png"),
            options: ConversionOptions(), outputDirectory: work.stage)
        let output = try XCTUnwrap(result.outputs.first)
        let pixels = try decodedImage(output)
        XCTAssertEqual(pixels.width, 30)
        XCTAssertEqual(pixels.height, 60)
        let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any])
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary as String])
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertTrue(output.path.hasPrefix(work.stage.path + "/"))
    }

    func testTransparentJPEGUsesWhiteBackground() async throws {
        let work = try workspace()
        let source = try image(work.inputs.appendingPathComponent("transparent.png"), width: 40, height: 40) { context in
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 15, y: 15, width: 10, height: 10))
        }
        let result = try await NativeConverter.convert(inputs: [source], operation: operation("convert.jpg"),
            options: ConversionOptions(), outputDirectory: work.stage)
        let corner = try color(decodedImage(XCTUnwrap(result.outputs.first)), x: 1, y: 1)
        XCTAssertGreaterThan(corner.redComponent, 0.94)
        XCTAssertGreaterThan(corner.greenComponent, 0.94)
        XCTAssertGreaterThan(corner.blueComponent, 0.94)
    }

    func testResizePreservesAspectRatioAndNeverUpscales() async throws {
        let work = try workspace()
        let source = try image(work.inputs.appendingPathComponent("wide.png"))
        var options = ConversionOptions(); options.maxDimension = 24
        let smaller = try await NativeConverter.convert(inputs: [source], operation: operation("image.resize"),
            options: options, outputDirectory: work.stage)
        let pixels = try decodedImage(XCTUnwrap(smaller.outputs.first))
        XCTAssertEqual(pixels.width, 24); XCTAssertEqual(pixels.height, 12)
        options.maxDimension = 200
        let larger = try await NativeConverter.convert(inputs: [source], operation: operation("image.resize"),
            options: options, outputDirectory: freshStage(work))
        let unchanged = try decodedImage(XCTUnwrap(larger.outputs.first))
        XCTAssertEqual(unchanged.width, 60); XCTAssertEqual(unchanged.height, 30)
    }

    func testCenteredCropAndHorizontalFlipUsePixels() async throws {
        let work = try workspace()
        let source = try image(work.inputs.appendingPathComponent("stripes.png"), width: 6, height: 4) { context in
            for (index, components) in [[1.0, 0, 0], [0, 1.0, 0], [0, 0, 1.0]].enumerated() {
                context.setFillColor(CGColor(red: components[0], green: components[1], blue: components[2], alpha: 1))
                context.fill(CGRect(x: index * 2, y: 0, width: 2, height: 4))
            }
        }
        var options = ConversionOptions(); options.width = 2; options.height = 4
        let crop = try await NativeConverter.convert(inputs: [source], operation: operation("image.crop"),
            options: options, outputDirectory: work.stage)
        let cropped = try decodedImage(XCTUnwrap(crop.outputs.first))
        XCTAssertEqual(cropped.width, 2); XCTAssertEqual(cropped.height, 4)
        XCTAssertGreaterThan(try color(cropped, x: 0, y: 0).greenComponent, 0.95)
        let flip = try await NativeConverter.convert(inputs: [source], operation: operation("image.flip"),
            options: options, outputDirectory: freshStage(work))
        XCTAssertGreaterThan(try color(decodedImage(XCTUnwrap(flip.outputs.first)), x: 0, y: 0).blueComponent, 0.95)
    }

    func testImageRotationHasExactDimensionsAtRightAngles() async throws {
        let work = try workspace()
        let source = try image(work.inputs.appendingPathComponent("wide.png"))
        var options = ConversionOptions(); options.rotationDegrees = 90
        let result = try await NativeConverter.convert(inputs: [source], operation: operation("image.rotate"),
            options: options, outputDirectory: work.stage)
        let pixels = try decodedImage(XCTUnwrap(result.outputs.first))
        XCTAssertEqual(pixels.width, 30); XCTAssertEqual(pixels.height, 60)
    }

    func testSelectedCropUsesTopLeftPixelsAndPreservesTransparencyAndOriginal() async throws {
        let work = try workspace()
        let yellow: [UInt8] = [255, 255, 0, 255], clear: [UInt8] = [0, 0, 0, 0]
        let red: [UInt8] = [255, 0, 0, 255], green: [UInt8] = [0, 255, 0, 255], blue: [UInt8] = [0, 0, 255, 255]
        let rows = [yellow, clear, red, yellow, yellow, green, blue, yellow, yellow, yellow, yellow, yellow]
        let source = try pixelFile(work.inputs.appendingPathComponent("selection.png"), width: 4, height: 3,
                                   rgba: rows.flatMap { $0 })
        let original = try Data(contentsOf: source)
        // Verify the sampler against untouched fixture pixels before exercising the converter.
        let fixture = try decodedImage(source)
        try assertPixel(fixture, x: 1, y: 0, rgba: clear)
        try assertPixel(fixture, x: 2, y: 0, rgba: red)
        try assertPixel(fixture, x: 1, y: 1, rgba: green)
        try assertPixel(fixture, x: 2, y: 1, rgba: blue)
        var options = ConversionOptions()
        options.imageCrop = ImageCropRegion(x: 1, y: 0, width: 2, height: 2, sourceWidth: 4, sourceHeight: 3)
        let result = try await NativeConverter.convert(inputs: [source], operation: operation("image.crop"),
            options: options, outputDirectory: work.stage)
        let pixels = try decodedImage(XCTUnwrap(result.outputs.first))
        XCTAssertEqual(pixels.width, 2); XCTAssertEqual(pixels.height, 2)
        try assertPixel(pixels, x: 0, y: 0, rgba: clear)
        try assertPixel(pixels, x: 1, y: 0, rgba: red)
        try assertPixel(pixels, x: 0, y: 1, rgba: green)
        try assertPixel(pixels, x: 1, y: 1, rgba: blue)
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testCropPreviewAndSelectionFollowAllEightEXIFOrientations() async throws {
        let work = try workspace()
        let palette: [[UInt8]] = [
            [255, 0, 0, 255], [0, 255, 0, 255], [0, 0, 255, 255],
            [255, 255, 0, 255], [255, 0, 255, 255], [0, 255, 255, 255]
        ]
        // A two-column, three-row lossless raster, including every mirrored case.
        let expected = [
            [0, 1, 2, 3, 4, 5], [1, 0, 3, 2, 5, 4],
            [5, 4, 3, 2, 1, 0], [4, 5, 2, 3, 0, 1],
            [0, 2, 4, 1, 3, 5], [4, 2, 0, 5, 3, 1],
            [5, 3, 1, 4, 2, 0], [1, 3, 5, 0, 2, 4]
        ]
        for orientation in 1...8 {
            let source = try pixelFile(work.inputs.appendingPathComponent("orientation-\(orientation).tiff"),
                width: 2, height: 3, rgba: palette.flatMap { $0 }, type: "public.tiff", orientation: orientation)
            let original = try Data(contentsOf: source)
            let raw = try XCTUnwrap(CGImageSourceCreateWithURL(source as CFURL, nil))
            let metadata = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(raw, 0, nil) as? [String: Any])
            XCTAssertEqual((metadata[kCGImagePropertyOrientation as String] as? NSNumber)?.intValue, orientation)
            if orientation == 1 {
                let fixture = try decodedImage(source)
                for index in palette.indices {
                    try assertPixel(fixture, x: index % 2, y: index / 2, rgba: palette[index])
                }
            }
            let preview = try NativeConverter.imageCropPreview(for: source)
            let width = orientation >= 5 ? 3 : 2, height = orientation >= 5 ? 2 : 3
            XCTAssertEqual(preview.sourceWidth, width); XCTAssertEqual(preview.sourceHeight, height)
            XCTAssertEqual(preview.image.width, width); XCTAssertEqual(preview.image.height, height)
            for y in 0..<height {
                for x in 0..<width {
                    try assertPixel(preview.image, x: x, y: y, rgba: palette[expected[orientation - 1][y * width + x]])
                }
            }
            var options = ConversionOptions(); options.removeMetadata = false
            options.imageCrop = ImageCropRegion(x: 0, y: 0, width: 1, height: 1, sourceWidth: width, sourceHeight: height)
            let result = try await NativeConverter.convert(inputs: [source], operation: operation("image.crop", ext: "png"),
                options: options, outputDirectory: freshStage(work))
            let output = try XCTUnwrap(result.outputs.first)
            let pixels = try decodedImage(output)
            XCTAssertEqual(pixels.width, 1); XCTAssertEqual(pixels.height, 1)
            try assertPixel(pixels, x: 0, y: 0, rgba: palette[expected[orientation - 1][0]])
            let roundTrip = try NativeConverter.imageCropPreview(for: output)
            XCTAssertEqual(roundTrip.sourceWidth, 1); XCTAssertEqual(roundTrip.sourceHeight, 1)
            try assertPixel(roundTrip.image, x: 0, y: 0, rgba: palette[expected[orientation - 1][0]])
            XCTAssertEqual(try Data(contentsOf: source), original)
        }
    }

    func testCropPreviewIsBoundedButExportUsesFullResolution() async throws {
        let work = try workspace()
        let source = try image(work.inputs.appendingPathComponent("original.png"), width: 320, height: 160)
        let original = try Data(contentsOf: source)
        let preview = try NativeConverter.imageCropPreview(for: source, maxPixelSize: 32)
        XCTAssertEqual(preview.image.width, 32); XCTAssertEqual(preview.image.height, 16)
        XCTAssertEqual(preview.sourceWidth, 320); XCTAssertEqual(preview.sourceHeight, 160)
        var options = ConversionOptions()
        options.imageCrop = ImageCropRegion(x: 64, y: 32, width: 128, height: 64, sourceWidth: 320, sourceHeight: 160)
        let result = try await NativeConverter.convert(inputs: [source], operation: operation("image.crop"),
            options: options, outputDirectory: work.stage)
        let pixels = try decodedImage(XCTUnwrap(result.outputs.first))
        XCTAssertEqual(pixels.width, 128); XCTAssertEqual(pixels.height, 64)
        XCTAssertEqual(try Data(contentsOf: source), original)
        let larger = try image(work.inputs.appendingPathComponent("bounded.png"), width: 2_000, height: 1_000)
        let capped = try NativeConverter.imageCropPreview(for: larger, maxPixelSize: Int.max)
        XCTAssertEqual(capped.image.width, 1_600); XCTAssertEqual(capped.image.height, 800)
        XCTAssertThrowsError(try NativeConverter.imageCropPreview(for: source, maxPixelSize: 0))
        XCTAssertThrowsError(try NativeConverter.imageCropPreview(for: source, maxPixelSize: Int.min))
        // A narrow fixture exceeds the edge limit without allocating a huge raster.
        let tooWide = try image(work.inputs.appendingPathComponent("too-wide.png"), width: 20_000, height: 1)
        XCTAssertThrowsError(try NativeConverter.imageCropPreview(for: tooWide, maxPixelSize: 16)) { error in
            guard case FreewheelError.invalidInput = error else { return XCTFail("An oversized original must fail before preview decoding") }
        }
    }

    func testSelectedCropRejectsChangedSourceSVGAndMultipleFramesWithoutOutput() async throws {
        let work = try workspace()
        let source = try image(work.inputs.appendingPathComponent("changed.png"), width: 10, height: 8)
        let original = try Data(contentsOf: source)
        var options = ConversionOptions()
        options.imageCrop = ImageCropRegion(x: 0, y: 0, width: 2, height: 2, sourceWidth: 9, sourceHeight: 8)
        do {
            _ = try await NativeConverter.convert(inputs: [source], operation: operation("image.crop"),
                options: options, outputDirectory: work.stage)
            XCTFail("A stale selection must not be applied to different dimensions")
        } catch FreewheelError.invalidInput(let message) { XCTAssertTrue(message.contains("dimensions changed")) }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: work.stage.path).isEmpty)
        let svg = work.inputs.appendingPathComponent("vector.svg")
        try "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"8\"><rect width=\"10\" height=\"8\"/></svg>".write(to: svg, atomically: true, encoding: .utf8)
        let multi = try pixelFile(work.inputs.appendingPathComponent("frames.tiff"), width: 1, height: 1,
            rgba: [255, 0, 0, 255], type: "public.tiff", frames: 2)
        for input in [svg, multi] {
            XCTAssertThrowsError(try NativeConverter.imageCropPreview(for: input)) { error in
                guard case FreewheelError.unsupported = error else { return XCTFail("Expected a clear still-image limitation") }
            }
            options.imageCrop = ImageCropRegion(x: 0, y: 0, width: 1, height: 1, sourceWidth: 1, sourceHeight: 1)
            do {
                _ = try await NativeConverter.convert(inputs: [input], operation: operation("image.crop", ext: "png"),
                    options: options, outputDirectory: work.stage)
                XCTFail("Visual crop must not silently flatten SVG or choose one frame")
            } catch FreewheelError.unsupported { }
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: work.stage.path).isEmpty)
        }
        let stillGIF = try pixelFile(work.inputs.appendingPathComponent("still.gif"), width: 1, height: 1,
            rgba: [255, 0, 0, 255], type: "com.compuserve.gif")
        XCTAssertThrowsError(try NativeConverter.imageCropPreview(for: stillGIF)) { error in
            guard case FreewheelError.unsupported(let message) = error else {
                return XCTFail("The preview must check its output encoder before editing begins")
            }
            XCTAssertTrue(message.contains("PNG or JPEG"))
            XCTAssertTrue(message.contains("save a visual crop"))
        }
        options.imageCrop = ImageCropRegion(x: 0, y: 0, width: 2, height: 2, sourceWidth: 10, sourceHeight: 8)
        do {
            _ = try await NativeConverter.convert(inputs: [source], operation: operation("image.crop", ext: "pdf"),
                options: options, outputDirectory: work.stage)
            XCTFail("Image-to-PDF routing must never discard a selected crop")
        } catch FreewheelError.unsupported { }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: work.stage.path).isEmpty)
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testCancelledCropPreviewAndExportLeaveTheOriginalAndStageAlone() async throws {
        let work = try workspace()
        let source = try image(work.inputs.appendingPathComponent("cancelled.png"), width: 10, height: 8)
        let original = try Data(contentsOf: source)
        let preview = Task {
            while !Task.isCancelled { await Task.yield() }
            return try NativeConverter.imageCropPreview(for: source)
        }
        preview.cancel()
        do { _ = try await preview.value; XCTFail("Cancelled preview should not decode") }
        catch is CancellationError { }
        var options = ConversionOptions()
        options.imageCrop = ImageCropRegion(x: 0, y: 0, width: 2, height: 2, sourceWidth: 10, sourceHeight: 8)
        let selected = options
        let export = Task {
            while !Task.isCancelled { await Task.yield() }
            return try await NativeConverter.convert(inputs: [source], operation: FileOperation(id: "image.crop", title: "Crop"),
                options: selected, outputDirectory: work.stage)
        }
        export.cancel()
        do { _ = try await export.value; XCTFail("Cancelled crop should not export") }
        catch FreewheelError.cancelled { }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: work.stage.path).isEmpty)
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testCropRejectsDimensionsLargerThanTheSource() async throws {
        let work = try workspace()
        let source = try image(work.inputs.appendingPathComponent("small.png"), width: 20, height: 10)
        var options = ConversionOptions(); options.width = 40; options.height = 10
        do {
            _ = try await NativeConverter.convert(inputs: [source], operation: operation("image.crop"),
                options: options, outputDirectory: work.stage)
            XCTFail("Crop must not silently return dimensions different from those requested")
        } catch FreewheelError.invalidInput(let message) { XCTAssertTrue(message.contains("Crop dimensions")) }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: work.stage.path).isEmpty)
    }

    func testInvalidSizeDoesNotCreateOutput() async throws {
        let work = try workspace()
        let source = try image(work.inputs.appendingPathComponent("input.png"))
        var options = ConversionOptions(); options.maxDimension = Int.max
        do {
            _ = try await NativeConverter.convert(inputs: [source], operation: operation("image.resize"),
                options: options, outputDirectory: work.stage)
            XCTFail("Oversized resize should be rejected")
        } catch FreewheelError.invalidInput { }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: work.stage.path).isEmpty)
    }

    func testFailedBatchRemovesPartialStagingFilesAndKeepsInputs() async throws {
        let work = try workspace()
        let good = try image(work.inputs.appendingPathComponent("good.png"))
        let original = try Data(contentsOf: good)
        let bad = work.inputs.appendingPathComponent("bad.png")
        try Data("This is not a PNG".utf8).write(to: bad)
        do {
            _ = try await NativeConverter.convert(inputs: [good, bad], operation: operation("convert.jpg"),
                options: ConversionOptions(), outputDirectory: work.stage)
            XCTFail("Unreadable input should fail the whole batch")
        } catch FreewheelError.unsupported { }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: work.stage.path).isEmpty)
        XCTAssertEqual(try Data(contentsOf: good), original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: bad.path))
    }

    func testNonemptyStagingIsRejectedWithoutDeletingExistingFiles() async throws {
        let work = try workspace()
        let source = try image(work.inputs.appendingPathComponent("input.png"))
        let unrelated = work.stage.appendingPathComponent("keep.txt")
        try Data("Keep this file".utf8).write(to: unrelated)
        do {
            _ = try await NativeConverter.convert(inputs: [source], operation: operation("convert.jpg"),
                options: ConversionOptions(), outputDirectory: work.stage)
            XCTFail("An existing staging file must not be deleted")
        } catch FreewheelError.invalidInput { }
        XCTAssertEqual(try String(contentsOf: unrelated, encoding: .utf8), "Keep this file")
    }

    func testMultipleImagesBecomeSeparatePDFPagesWithCorrectOrientation() async throws {
        let work = try workspace()
        let landscape = try image(work.inputs.appendingPathComponent("landscape.png"), width: 60, height: 30)
        let portrait = try image(work.inputs.appendingPathComponent("portrait.png"), width: 30, height: 60)
        let result = try await NativeConverter.convert(inputs: [landscape, portrait], operation: operation("convert.pdf"),
            options: ConversionOptions(), outputDirectory: work.stage)
        let document = try XCTUnwrap(PDFDocument(url: XCTUnwrap(result.outputs.first)))
        XCTAssertEqual(document.pageCount, 2)
        let first = try XCTUnwrap(document.page(at: 0)).bounds(for: .mediaBox)
        let second = try XCTUnwrap(document.page(at: 1)).bounds(for: .mediaBox)
        XCTAssertEqual(first.width / first.height, 2, accuracy: 0.001)
        XCTAssertEqual(second.height / second.width, 2, accuracy: 0.001)
    }

    func testPDFToImagesExportsEveryPageAt300DPI() async throws {
        let work = try workspace()
        let source = try pdf(work.inputs.appendingPathComponent("three-pages.pdf"), pages: [
            (CGSize(width: 72, height: 36), "A"), (CGSize(width: 36, height: 72), "B"),
            (CGSize(width: 72, height: 72), "C")
        ])
        let result = try await NativeConverter.convert(inputs: [source], operation: operation("convert.png"),
            options: ConversionOptions(), outputDirectory: work.stage)
        XCTAssertEqual(result.outputs.count, 3)
        XCTAssertEqual(try decodedImage(result.outputs[0]).width, 300)
        XCTAssertEqual(try decodedImage(result.outputs[0]).height, 150)
        XCTAssertEqual(try decodedImage(result.outputs[1]).width, 150)
        XCTAssertEqual(try decodedImage(result.outputs[1]).height, 300)
        XCTAssertTrue(result.note?.contains("300 DPI") == true)
    }

    func testPDFExtractPreservesRequestedOrderAndRejectsOutOfBoundsPages() async throws {
        let work = try workspace()
        let source = try pdf(work.inputs.appendingPathComponent("pages.pdf"), pages: [
            (CGSize(width: 200, height: 100), "Alpha"), (CGSize(width: 200, height: 100), "Bravo"),
            (CGSize(width: 200, height: 100), "Charlie")
        ])
        var options = ConversionOptions(); options.pageRange = "3,1-2,3"
        let result = try await NativeConverter.convert(inputs: [source], operation: operation("pdf.extract"),
            options: options, outputDirectory: work.stage)
        let document = try XCTUnwrap(PDFDocument(url: XCTUnwrap(result.outputs.first)))
        XCTAssertEqual(document.pageCount, 3)
        XCTAssertTrue(document.page(at: 0)?.string?.contains("Charlie") == true)
        XCTAssertTrue(document.page(at: 1)?.string?.contains("Alpha") == true)
        options.pageRange = "0-9"
        let emptyStage = try freshStage(work)
        do {
            _ = try await NativeConverter.convert(inputs: [source], operation: operation("pdf.extract"),
                options: options, outputDirectory: emptyStage)
            XCTFail("Out-of-range pages must be rejected")
        } catch FreewheelError.invalidInput { }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: emptyStage.path).isEmpty)
    }

    func testRotatedCropBoxRendersAnnotationsAndCorrectDimensions() async throws {
        let work = try workspace()
        let original = try pdf(work.inputs.appendingPathComponent("original.pdf"),
            pages: [(CGSize(width: 200, height: 200), "")])
        for rotation in [0, 90, 180, 270] {
            let document = try XCTUnwrap(PDFDocument(url: original))
            let page = try XCTUnwrap(document.page(at: 0))
            page.setBounds(CGRect(x: 100, y: 40, width: 80, height: 60), for: .cropBox)
            page.rotation = rotation
            let annotation = PDFAnnotation(bounds: CGRect(x: 120, y: 60, width: 20, height: 20),
                                           forType: .square, withProperties: nil)
            annotation.interiorColor = .red
            annotation.color = .red
            page.addAnnotation(annotation)
            let source = work.inputs.appendingPathComponent("cropped-\(rotation).pdf")
            XCTAssertTrue(document.write(to: source))
            let result = try await NativeConverter.convert(inputs: [source], operation: operation("convert.png"),
                options: ConversionOptions(), outputDirectory: freshStage(work))
            let pixels = try decodedImage(XCTUnwrap(result.outputs.first))
            let swapsAxes = rotation == 90 || rotation == 270
            XCTAssertEqual(pixels.width, swapsAxes ? 250 : 334, "Rotation \(rotation)")
            XCTAssertEqual(pixels.height, swapsAxes ? 334 : 250, "Rotation \(rotation)")
            let bitmap = NSBitmapImageRep(cgImage: pixels)
            var redPixels = 0
            for y in stride(from: 0, to: pixels.height, by: 8) {
                for x in stride(from: 0, to: pixels.width, by: 8) {
                    if let value = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                       value.redComponent > 0.7, value.greenComponent < 0.3, value.blueComponent < 0.3 {
                        redPixels += 1
                    }
                }
            }
            XCTAssertGreaterThan(redPixels, 10,
                "Rotation \(rotation): the crop-box offset must not move the visible annotation outside the page")
        }
    }

    func testPDFMergeAndRotationKeepPageCountsAndOriginals() async throws {
        let work = try workspace()
        let one = try pdf(work.inputs.appendingPathComponent("one.pdf"), pages: [(CGSize(width: 200, height: 100), "One")])
        let two = try pdf(work.inputs.appendingPathComponent("two.pdf"), pages: [
            (CGSize(width: 100, height: 200), "Two"), (CGSize(width: 120, height: 120), "Three")
        ])
        let original = try Data(contentsOf: one)
        let merged = try await NativeConverter.convert(inputs: [one, two], operation: operation("pdf.merge"),
            options: ConversionOptions(), outputDirectory: work.stage)
        let mergedURL = try XCTUnwrap(merged.outputs.first)
        XCTAssertEqual(try XCTUnwrap(PDFDocument(url: mergedURL)).pageCount, 3)
        var options = ConversionOptions(); options.rotationDegrees = 90
        let rotated = try await NativeConverter.convert(inputs: [mergedURL], operation: operation("pdf.rotate"),
            options: options, outputDirectory: freshStage(work))
        let document = try XCTUnwrap(PDFDocument(url: XCTUnwrap(rotated.outputs.first)))
        XCTAssertEqual(document.pageCount, 3)
        for index in 0..<document.pageCount { XCTAssertEqual(document.page(at: index)?.rotation, 90) }
        XCTAssertEqual(try Data(contentsOf: one), original)
    }

    func testPDFCompressionKeepsPhysicalPageDimensionsAndDisclosesFlattening() async throws {
        let work = try workspace()
        let source = try pdf(work.inputs.appendingPathComponent("input.pdf"), pages: [(CGSize(width: 200, height: 100), "Selectable text")])
        let result = try await NativeConverter.convert(inputs: [source], operation: operation("pdf.compress"),
            options: ConversionOptions(), outputDirectory: work.stage)
        let document = try XCTUnwrap(PDFDocument(url: XCTUnwrap(result.outputs.first)))
        let page = try XCTUnwrap(document.page(at: 0))
        XCTAssertEqual(page.bounds(for: .mediaBox).width, 200, accuracy: 0.01)
        XCTAssertEqual(page.bounds(for: .mediaBox).height, 100, accuracy: 0.01)
        XCTAssertTrue((page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertTrue(result.note?.contains("flattens") == true)
    }

    func testScannedPDFTextExtractionFailsWithActionableOCRMessage() async throws {
        let work = try workspace()
        let source = try pdf(work.inputs.appendingPathComponent("scan.pdf"), pages: [(CGSize(width: 100, height: 100), "")])
        do {
            _ = try await NativeConverter.convert(inputs: [source], operation: operation("convert.txt"),
                options: ConversionOptions(), outputDirectory: work.stage)
            XCTFail("A scanned PDF must not silently produce an empty text file")
        } catch FreewheelError.invalidInput(let message) { XCTAssertTrue(message.contains("OCR")) }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: work.stage.path).isEmpty)
    }

    func testTextPDFPaginationRetainsFinalContent() async throws {
        let work = try workspace()
        let source = work.inputs.appendingPathComponent("long.txt")
        let text = (0..<250).map { "Generated line \($0) for pagination." }.joined(separator: "\n") + "\nFINALMARKER"
        try Data(text.utf8).write(to: source)
        let result = try await NativeConverter.convert(inputs: [source], operation: operation("convert.pdf"),
            options: ConversionOptions(), outputDirectory: work.stage)
        let document = try XCTUnwrap(PDFDocument(url: XCTUnwrap(result.outputs.first)))
        XCTAssertGreaterThan(document.pageCount, 1)
        XCTAssertTrue(document.string?.contains("FINALMARKER") == true)
    }

    func testHTMLTextImportIgnoresScriptsAndExternalResources() async throws {
        let work = try workspace()
        let source = work.inputs.appendingPathComponent("document.html")
        let html = "<html><head><link rel='stylesheet' href='https://example.invalid/style.css'></head><body><p>Alpha &amp; Omega</p><img src='https://example.invalid/image.png'><script>unwanted script</script><p>End &#33;</p></body></html>"
        try Data(html.utf8).write(to: source)
        let result = try await NativeConverter.convert(inputs: [source], operation: operation("convert.txt"),
            options: ConversionOptions(), outputDirectory: work.stage)
        let text = try String(contentsOf: XCTUnwrap(result.outputs.first), encoding: .utf8)
        XCTAssertTrue(text.contains("Alpha & Omega")); XCTAssertTrue(text.contains("End !"))
        XCTAssertFalse(text.contains("script")); XCTAssertFalse(text.contains("https:"))
    }

    func testSVGExternalResourcesAreRejectedBeforeRendering() async throws {
        let work = try workspace()
        let source = work.inputs.appendingPathComponent("external.svg")
        let svg = "<svg xmlns='http://www.w3.org/2000/svg' width='20' height='20'><image href='https://example.invalid/image.png' width='20' height='20'/></svg>"
        try Data(svg.utf8).write(to: source)
        do {
            _ = try await NativeConverter.convert(inputs: [source], operation: operation("convert.png"),
                options: ConversionOptions(), outputDirectory: work.stage)
            XCTFail("An SVG must not load external resources")
        } catch FreewheelError.invalidInput(let message) { XCTAssertTrue(message.contains("external")) }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: work.stage.path).isEmpty)
    }

    func testPDFWordCountReturnsInformationWithoutCreatingFiles() async throws {
        let work = try workspace()
        let source = try pdf(work.inputs.appendingPathComponent("words.pdf"), pages: [(CGSize(width: 200, height: 100), "one two three")])
        let result = try await NativeConverter.convert(inputs: [source], operation: operation("document.wordCount"),
            options: ConversionOptions(), outputDirectory: work.stage)
        XCTAssertTrue(result.outputs.isEmpty)
        XCTAssertTrue(result.note?.contains("3 words") == true)
    }

    private func audioFixture(_ url: URL, sampleRate: Double = 44_100, channels: Int = 2,
                              frames: Int = 44_100, sample: (Int, Int) -> Float) throws {
        try autoreleasepool {
            let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate,
                                                   channels: AVAudioChannelCount(channels)))
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_096))
            let data = try XCTUnwrap(buffer.floatChannelData)
            let file = try AVAudioFile(forWriting: url, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels, AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false
            ])
            var position = 0
            while position < frames {
                let count = min(4_096, frames - position)
                buffer.frameLength = AVAudioFrameCount(count)
                for channel in 0..<channels {
                    for frame in 0..<count { data[channel][frame] = sample(position + frame, channel) }
                }
                try file.write(from: buffer)
                position += count
            }
        }
    }

    func testNativeWaveformSummarizesStereoWithoutChangingInput() async throws {
        let work = try workspace()
        let input = work.inputs.appendingPathComponent("levels.wav")
        try audioFixture(input) { frame, channel in
            let level: Float = [0.1, 0.3, 0.6, 0.9][min(3, frame * 4 / 44_100)]
            return channel == 0 ? level : -level
        }
        let original = try Data(contentsOf: input)
        let preview = try await NativeConverter.audioTrimPreview(for: input, maxSamples: 4)
        XCTAssertEqual(preview.durationSeconds, 1, accuracy: 1 / 44_100)
        XCTAssertEqual(preview.channelCount, 2)
        XCTAssertEqual(preview.sampleRate, 44_100, accuracy: 0.5)
        XCTAssertEqual(preview.peaks.count, 4)
        for (actual, expected) in zip(preview.peaks, [Float(0.1), 0.3, 0.6, 0.9]) {
            XCTAssertEqual(actual, expected, accuracy: 0.0001)
        }
        XCTAssertTrue(preview.nativeOutputExtensions.contains("wav"))
        XCTAssertTrue(preview.nativeOutputExtensions.contains("aiff"))
        let maximum = try await NativeConverter.audioTrimPreview(for: input, maxSamples: Int.max)
        XCTAssertEqual(maximum.peaks.count, 4_096)
        XCTAssertEqual(try Data(contentsOf: input), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: work.inputs.path), ["levels.wav"])
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: work.stage.path).isEmpty)
    }

    func testNativeWaveformTrimKeepsSelectedPCMFramesAndOriginalBytes() async throws {
        let work = try workspace()
        let input = work.inputs.appendingPathComponent("ramp.wav")
        try audioFixture(input) { frame, channel in
            Float(frame) / 44_100 * (channel == 0 ? 0.8 : -0.8)
        }
        let original = try Data(contentsOf: input)
        let preview = try await NativeConverter.audioTrimPreview(for: input, maxSamples: 32)
        let start: Double = 0.123, end: Double = 0.567
        let fixtureSampleRate: Double = 44_100
        let amplitude: Double = 0.8
        let sampleAccuracy: Float = 0.0001
        let expectedFirstFrame: Double = ceil(start * preview.sampleRate)
        let expectedFrames: Double = ceil(end * preview.sampleRate) - expectedFirstFrame
        let expectedLastFrame: Double = ceil(end * fixtureSampleRate) - 1
        let firstSampleValue: Double = expectedFirstFrame / fixtureSampleRate * amplitude
        let lastSampleValue: Double = expectedLastFrame / fixtureSampleRate * amplitude
        let expectedFirstSample: Float = Float(firstSampleValue)
        let expectedLastSample: Float = Float(lastSampleValue)
        var options = ConversionOptions()
        options.audioTrim = AudioTrimSelection(startSeconds: start, endSeconds: end,
                                               sourceDuration: preview.durationSeconds)
        // Legacy values intentionally disagree: the bound selection is decisive.
        options.startSeconds = 0; options.endSeconds = 30
        for ext in ["wav", "aiff"] {
            let result = try await NativeConverter.convert(inputs: [input], operation: operation("media.trim", ext: ext),
                options: options, outputDirectory: freshStage(work))
            let output = try XCTUnwrap(result.outputs.first)
            XCTAssertTrue(output.lastPathComponent.contains("trimmed"))
            let file = try AVAudioFile(forReading: output)
            XCTAssertEqual(file.processingFormat.channelCount, 2)
            XCTAssertEqual(Double(file.length), expectedFrames, accuracy: 2)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1))
            try file.read(into: buffer)
            let channels = try XCTUnwrap(buffer.floatChannelData)
            XCTAssertEqual(channels[0][0], expectedFirstSample, accuracy: sampleAccuracy)
            XCTAssertEqual(channels[1][0], -expectedFirstSample, accuracy: sampleAccuracy)
            file.framePosition = file.length - 1
            try file.read(into: buffer)
            XCTAssertEqual(channels[0][0], expectedLastSample, accuracy: sampleAccuracy)
            XCTAssertTrue(result.note?.contains("16-bit PCM") == true)
        }
        XCTAssertEqual(try Data(contentsOf: input), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: work.inputs.path), ["ramp.wav"])
    }

    func testNativeWaveformTrimReencodesM4AWithCodecPrecisionNotice() async throws {
        let work = try workspace()
        let input = work.inputs.appendingPathComponent("tone.wav")
        try audioFixture(input, channels: 1) { frame, _ in Float(sin(Double(frame) * 2 * .pi * 440 / 44_100)) * 0.2 }
        let preview = try await NativeConverter.audioTrimPreview(for: input, maxSamples: 32)
        guard preview.nativeOutputExtensions.contains("m4a") else { throw XCTSkip("This macOS codec set does not export M4A") }
        var options = ConversionOptions()
        options.audioTrim = AudioTrimSelection(startSeconds: 0.210, endSeconds: 0.710,
                                               sourceDuration: preview.durationSeconds)
        let result = try await NativeConverter.convert(inputs: [input], operation: operation("media.trim", ext: "m4a"),
            options: options, outputDirectory: work.stage)
        let asset = AVURLAsset(url: try XCTUnwrap(result.outputs.first))
        let duration = try await asset.load(.duration)
        XCTAssertEqual(CMTimeGetSeconds(duration), 0.5, accuracy: 0.08)
        XCTAssertTrue(result.note?.contains("M4A re-encodes AAC") == true)
        XCTAssertTrue(result.note?.contains("padding") == true)
    }

    func testNativeWaveformRejectsInvalidSourcesAndStaleDurationWithoutOutput() async throws {
        let work = try workspace()
        let valid = work.inputs.appendingPathComponent("valid.wav")
        try audioFixture(valid, frames: 4_410) { _, _ in 0.1 }
        let empty = work.inputs.appendingPathComponent("empty.wav")
        try Data().write(to: empty)
        let text = work.inputs.appendingPathComponent("text.txt")
        try Data("Not audio".utf8).write(to: text)
        for input in [empty, text, URL(string: "https://example.invalid/recording.wav")!] {
            do {
                _ = try await NativeConverter.audioTrimPreview(for: input)
                XCTFail("An invalid waveform source was accepted")
            } catch FreewheelError.invalidInput { }
        }
        do {
            _ = try await NativeConverter.audioTrimPreview(for: valid, maxSamples: 0)
            XCTFail("An empty waveform size was accepted")
        } catch FreewheelError.invalidInput { }
        var options = ConversionOptions()
        options.audioTrim = AudioTrimSelection(startSeconds: 0, endSeconds: 0.05, sourceDuration: 1)
        do {
            _ = try await NativeConverter.convert(inputs: [valid], operation: operation("media.trim", ext: "wav"),
                options: options, outputDirectory: work.stage)
            XCTFail("A stale source duration was accepted")
        } catch FreewheelError.invalidInput(let message) { XCTAssertTrue(message.contains("changed")) }
        // The FFmpeg route must run the same stale-source check before fallback.
        do {
            _ = try await ConversionEngine().run(inputs: [valid], operation: operation("media.trim", ext: "mp3"), options: options)
            XCTFail("A stale waveform was passed to FFmpeg")
        } catch FreewheelError.invalidInput(let message) { XCTAssertTrue(message.contains("changed")) }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: work.stage.path).isEmpty)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: work.inputs.path)), ["valid.wav", "empty.wav", "text.txt"])
    }

    func testNativeWaveformAndSelectedExportRespectCancellation() async throws {
        let work = try workspace()
        let input = work.inputs.appendingPathComponent("recording.wav")
        try audioFixture(input, frames: 4_410) { _, _ in 0.1 }
        let original = try Data(contentsOf: input)
        let waveform = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await NativeConverter.audioTrimPreview(for: input)
        }
        do { _ = try await waveform.value; XCTFail("Cancelled waveform preparation completed") }
        catch is CancellationError { }
        let export = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            var options = ConversionOptions()
            options.audioTrim = AudioTrimSelection(startSeconds: 0, endSeconds: 0.05, sourceDuration: 0.1)
            return try await NativeConverter.convert(inputs: [input],
                operation: FileOperation(id: "media.trim", title: "Trim", outputExtension: "wav"),
                options: options, outputDirectory: work.stage)
        }
        do { _ = try await export.value; XCTFail("Cancelled audio export completed") }
        catch FreewheelError.cancelled { }
        XCTAssertEqual(try Data(contentsOf: input), original)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: work.stage.path).isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: work.inputs.path), ["recording.wav"])
    }

    /// Tiny generated H.264 clips keep the repository free of binary fixtures.
    /// The first half is red and the second half blue, so an exported range can
    /// be checked by its actual decoded content as well as its duration.
    private func videoFixture(_ url: URL, width: Int = 64, height: Int = 32,
                              frames: Int = 60, portrait: Bool = false) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 200_000, AVVideoMaxKeyFrameIntervalKey: 30]
        ])
        input.expectsMediaDataInRealTime = false
        if portrait {
            input.transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: CGFloat(height), ty: 0)
        }
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ])
        XCTAssertTrue(writer.canAdd(input))
        writer.add(input)
        guard writer.startWriting() else { throw FreewheelError.operationFailed("The generated video writer did not start.") }
        writer.startSession(atSourceTime: .zero)
        let pool = try XCTUnwrap(adaptor.pixelBufferPool)
        do {
            for frame in 0..<frames {
                let deadline = Date().addingTimeInterval(15)
                while !input.isReadyForMoreMediaData {
                    guard writer.status == .writing, Date() < deadline else {
                        throw FreewheelError.operationFailed("The generated video writer stopped accepting frames.")
                    }
                    try await Task.sleep(nanoseconds: 1_000_000)
                }
                try autoreleasepool {
                    var pixelBuffer: CVPixelBuffer?
                    XCTAssertEqual(CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer), kCVReturnSuccess)
                    let buffer = try XCTUnwrap(pixelBuffer)
                    XCTAssertEqual(CVPixelBufferLockBaseAddress(buffer, []), kCVReturnSuccess)
                    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
                    let bytes = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
                    let stride = CVPixelBufferGetBytesPerRow(buffer)
                    let blue = frame >= frames / 2
                    for y in 0..<height {
                        for x in 0..<width {
                            let offset = y * stride + x * 4
                            bytes[offset] = blue ? 255 : 0
                            bytes[offset + 1] = 0
                            bytes[offset + 2] = blue ? 0 : 255
                            bytes[offset + 3] = 255
                        }
                    }
                    let time = CMTime(value: Int64(frame), timescale: 30)
                    guard adaptor.append(buffer, withPresentationTime: time) else {
                        throw FreewheelError.operationFailed("The generated video frame was rejected.")
                    }
                }
            }
            input.markAsFinished()
            writer.endSession(atSourceTime: CMTime(value: Int64(frames), timescale: 30))
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                writer.finishWriting { continuation.resume() }
            }
            XCTAssertEqual(writer.status, .completed)
        } catch {
            writer.cancelWriting()
            throw error
        }
    }

    private func videoWithAudioFixture(_ url: URL, workspace: Workspace) async throws {
        let silent = workspace.root.appendingPathComponent("generated-video.mov")
        let sound = workspace.root.appendingPathComponent("generated-audio.wav")
        try await videoFixture(silent)
        try audioFixture(sound, channels: 1, frames: 88_200) { frame, _ in
            let phase: Double = Double(frame) * 2 * Double.pi * 440 / 44_100
            return Float(sin(phase)) * 0.2
        }
        let videoAsset = AVURLAsset(url: silent)
        let audioAsset = AVURLAsset(url: sound)
        let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
        let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
        let sourceVideo = try XCTUnwrap(videoTracks.first)
        let sourceAudio = try XCTUnwrap(audioTracks.first)
        let composition = AVMutableComposition()
        let picture = try XCTUnwrap(composition.addMutableTrack(withMediaType: .video,
                                                                preferredTrackID: kCMPersistentTrackID_Invalid))
        let audio = try XCTUnwrap(composition.addMutableTrack(withMediaType: .audio,
                                                              preferredTrackID: kCMPersistentTrackID_Invalid))
        let range = CMTimeRange(start: .zero, duration: CMTime(value: 2, timescale: 1))
        try picture.insertTimeRange(range, of: sourceVideo, at: .zero)
        try audio.insertTimeRange(range, of: sourceAudio, at: .zero)
        let session = try XCTUnwrap(AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality))
        session.outputURL = url
        session.outputFileType = .mov
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { continuation.resume() }
        }
        XCTAssertEqual(session.status, .completed)
    }

    func testNativeVideoTimelineIsBoundedRotatedAndLeavesOriginalUntouched() async throws {
        let work = try workspace()
        let input = work.inputs.appendingPathComponent("portrait.mov")
        try await videoFixture(input, width: 256, height: 128, frames: 12, portrait: true)
        let original = try Data(contentsOf: input)
        let preview = try await NativeConverter.videoTrimPreview(for: input,
            maxThumbnailCount: Int.max, maxPixelSize: Int.max)
        XCTAssertEqual(preview.durationSeconds, 0.4, accuracy: 0.001)
        XCTAssertEqual(preview.displayWidth, 128)
        XCTAssertEqual(preview.displayHeight, 256)
        XCTAssertEqual(try XCTUnwrap(preview.nominalFrameRate), 30, accuracy: 0.1)
        XCTAssertEqual(preview.thumbnails.count, 24)
        XCTAssertTrue(preview.nativeOutputExtensions.contains("mp4"))
        XCTAssertTrue(preview.nativeOutputExtensions.contains("mov"))
        for frame in preview.thumbnails {
            XCTAssertGreaterThan(frame.image.height, frame.image.width)
            XCTAssertLessThanOrEqual(frame.image.height, 192)
            XCTAssertGreaterThan(frame.image.height, 0)
            XCTAssertGreaterThanOrEqual(frame.timeSeconds, 0)
            XCTAssertLessThan(frame.timeSeconds, preview.durationSeconds)
        }
        let small = try await NativeConverter.videoTrimPreview(for: input, maxThumbnailCount: 1, maxPixelSize: 32)
        XCTAssertEqual(small.thumbnails.count, 1)
        XCTAssertLessThanOrEqual(try XCTUnwrap(small.thumbnails.first).image.height, 32)
        XCTAssertEqual(try Data(contentsOf: input), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: work.inputs.path), ["portrait.mov"])
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: work.stage.path).isEmpty)
    }

    func testNativeSelectedVideoExportsRangeWithAudioAndOriginalBytes() async throws {
        let work = try workspace()
        let input = work.inputs.appendingPathComponent("colors-with-audio.mov")
        try await videoWithAudioFixture(input, workspace: work)
        let original = try Data(contentsOf: input)
        let preview = try await NativeConverter.videoTrimPreview(for: input, maxThumbnailCount: 2)
        var options = ConversionOptions()
        options.videoTrim = VideoTrimSelection(startSeconds: 1.1, endSeconds: 1.7,
                                               sourceDuration: preview.durationSeconds)
        options.startSeconds = 0
        options.endSeconds = 30
        for ext in ["mp4", "mov"] {
            let result = try await NativeConverter.convert(inputs: [input], operation: operation("media.trim", ext: ext),
                options: options, outputDirectory: freshStage(work))
            let output = try XCTUnwrap(result.outputs.first)
            XCTAssertTrue(output.lastPathComponent.contains("trimmed"))
            let asset = AVURLAsset(url: output)
            let duration = try await asset.load(.duration)
            let audio = try await asset.loadTracks(withMediaType: .audio)
            XCTAssertEqual(CMTimeGetSeconds(duration), 0.6, accuracy: 0.08)
            XCTAssertEqual(audio.count, 1)
            let resultPreview = try await NativeConverter.videoTrimPreview(for: output, maxThumbnailCount: 1)
            let frame = try XCTUnwrap(resultPreview.thumbnails.first).image
            let pixel = try color(frame, x: frame.width / 2, y: frame.height / 2)
            // Lossy H.264 is checked by dominant content, not exact RGB bytes.
            XCTAssertGreaterThan(pixel.blueComponent, 0.75)
            XCTAssertLessThan(pixel.redComponent, 0.25)
            XCTAssertTrue(result.note?.contains("re-encoded") == true)
            XCTAssertTrue(result.note?.contains("boundaries") == true)
        }
        XCTAssertEqual(try Data(contentsOf: input), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: work.inputs.path), ["colors-with-audio.mov"])
    }

    func testNativeVideoTrimKeepsFullAndBoundaryRangesOriented() async throws {
        let work = try workspace()
        let input = work.inputs.appendingPathComponent("boundary.mov")
        try await videoFixture(input, portrait: true)
        let original = try Data(contentsOf: input)
        let preview = try await NativeConverter.videoTrimPreview(for: input, maxThumbnailCount: 1)
        let total = preview.durationSeconds
        let selections = [
            VideoTrimGeometry.fullDuration(total),
            VideoTrimSelection(startSeconds: 0, endSeconds: 0.1, sourceDuration: total),
            VideoTrimSelection(startSeconds: total - 0.1, endSeconds: total, sourceDuration: total)
        ]
        for selection in selections {
            var options = ConversionOptions(); options.videoTrim = selection
            let result = try await NativeConverter.convert(inputs: [input], operation: operation("media.trim", ext: "mp4"),
                options: options, outputDirectory: freshStage(work))
            let output = try XCTUnwrap(result.outputs.first)
            let exported = try await NativeConverter.videoTrimPreview(for: output, maxThumbnailCount: 1)
            XCTAssertEqual(exported.durationSeconds, selection.durationSeconds, accuracy: 0.04)
            XCTAssertEqual(exported.displayWidth, 32)
            XCTAssertEqual(exported.displayHeight, 64)
            let frame = try XCTUnwrap(exported.thumbnails.first).image
            XCTAssertGreaterThan(frame.height, frame.width)
        }
        XCTAssertEqual(try Data(contentsOf: input), original)
    }

    func testNativeVideoTrimRejectsInvalidSourcesAndStaleDuration() async throws {
        let work = try workspace()
        let valid = work.inputs.appendingPathComponent("valid.mov")
        try await videoFixture(valid, frames: 6)
        let original = try Data(contentsOf: valid)
        let empty = work.inputs.appendingPathComponent("empty.mov")
        let text = work.inputs.appendingPathComponent("text.txt")
        let fake = work.inputs.appendingPathComponent("fake.mp4")
        try Data().write(to: empty)
        try Data("Not video".utf8).write(to: text)
        try Data("Not video".utf8).write(to: fake)
        for input in [empty, text, URL(string: "https://example.invalid/video.mp4")!] {
            do {
                _ = try await NativeConverter.videoTrimPreview(for: input)
                XCTFail("An invalid video source was accepted")
            } catch FreewheelError.invalidInput { }
        }
        do {
            _ = try await NativeConverter.videoTrimPreview(for: fake)
            XCTFail("Non-video data was accepted based on its extension")
        } catch FreewheelError.unsupported { }
          catch FreewheelError.invalidInput { }
        for (count, edge) in [(0, 192), (12, 0), (Int.min, 192), (12, Int.min)] {
            do {
                _ = try await NativeConverter.videoTrimPreview(for: valid, maxThumbnailCount: count, maxPixelSize: edge)
                XCTFail("An invalid thumbnail size was accepted")
            } catch FreewheelError.invalidInput { }
        }
        var options = ConversionOptions()
        options.videoTrim = VideoTrimSelection(startSeconds: 0, endSeconds: 0.1, sourceDuration: 1)
        do {
            _ = try await NativeConverter.convert(inputs: [valid], operation: operation("media.trim", ext: "mp4"),
                options: options, outputDirectory: work.stage)
            XCTFail("A stale video duration was accepted")
        } catch FreewheelError.invalidInput(let message) { XCTAssertTrue(message.contains("changed")) }
        // The shared engine must retain the source-bound native route, even
        // when an external engine happens to be installed on the machine.
        do {
            _ = try await ConversionEngine().run(inputs: [valid], operation: operation("media.trim", ext: "mov"), options: options)
            XCTFail("A stale selection reached another conversion route")
        } catch FreewheelError.invalidInput(let message) { XCTAssertTrue(message.contains("changed")) }
        XCTAssertEqual(try Data(contentsOf: valid), original)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: work.stage.path).isEmpty)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: work.inputs.path)), ["valid.mov", "empty.mov", "text.txt", "fake.mp4"])
    }

    func testNativeVideoTimelineAndSelectedExportRespectCancellation() async throws {
        let work = try workspace()
        let input = work.inputs.appendingPathComponent("clip.mov")
        try await videoFixture(input, frames: 6)
        let original = try Data(contentsOf: input)
        let preview = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await NativeConverter.videoTrimPreview(for: input)
        }
        do { _ = try await preview.value; XCTFail("Cancelled video preview completed") }
        catch is CancellationError { }
        let export = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            var options = ConversionOptions()
            options.videoTrim = VideoTrimSelection(startSeconds: 0, endSeconds: 0.1, sourceDuration: 0.2)
            return try await NativeConverter.convert(inputs: [input],
                operation: FileOperation(id: "media.trim", title: "Trim", outputExtension: "mp4"),
                options: options, outputDirectory: work.stage)
        }
        do { _ = try await export.value; XCTFail("Cancelled video export completed") }
        catch FreewheelError.cancelled { }
        XCTAssertEqual(try Data(contentsOf: input), original)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: work.stage.path).isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: work.inputs.path), ["clip.mov"])
    }

    func testNativeAudioExportWritesDecodableAIFF() async throws {
        let work = try workspace()
        let input = work.inputs.appendingPathComponent("tone.wav")
        try autoreleasepool {
            let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_410))
            buffer.frameLength = 4_410
            let samples = try XCTUnwrap(buffer.floatChannelData)[0]
            for index in 0..<4_410 { samples[index] = Float(sin(Double(index) * 2 * .pi * 440 / 44_100)) * 0.1 }
            let file = try AVAudioFile(forWriting: input, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false
            ])
            try file.write(from: buffer)
        }
        let result = try await NativeConverter.convert(inputs: [input], operation: operation("convert.aiff"),
            options: ConversionOptions(), outputDirectory: work.stage)
        let file = try AVAudioFile(forReading: XCTUnwrap(result.outputs.first))
        XCTAssertEqual(file.fileFormat.channelCount, 1)
        XCTAssertEqual(file.fileFormat.sampleRate, 44_100, accuracy: 1)
        XCTAssertEqual(Double(file.length), 4_410, accuracy: 2)
    }
}
#endif
