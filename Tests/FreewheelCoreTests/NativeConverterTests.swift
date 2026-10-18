#if os(macOS)
import XCTest
import AppKit
import AVFoundation
import CoreGraphics
import CoreVideo
import CoreText
import Darwin
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

    func testPDFMergePreviewLoadsSummariesAndBoundedFirstPageThumbnails() async throws {
        let work = try workspace()
        let first = try pdf(work.inputs.appendingPathComponent("first.pdf"),
                            pages: [(CGSize(width: 200, height: 100), "Cover")])
        var inputs = [first]
        for index in 1..<(PDFMergeSession.thumbnailCacheLimit + 2) {
            let copy = work.inputs.appendingPathComponent("document-\(index).pdf")
            try FileManager.default.copyItem(at: first, to: copy)
            inputs.append(copy)
        }
        let session = PDFMergeSession(inputs: inputs)
        var sources: [PDFMergeSource] = []
        for index in inputs.indices {
            let source = try await session.source(for: index)
            XCTAssertEqual(source.inputIndex, index)
            XCTAssertEqual(source.pageCount, 1)
            XCTAssertFalse(source.isEncrypted)
            XCTAssertEqual(source.fingerprint.utf8.count, 64)
            sources.append(source)
            let thumbnail = try await session.thumbnail(for: index)
            XCTAssertEqual(thumbnail.sourceIndex, 0)
            XCTAssertLessThanOrEqual(thumbnail.image.width, PDFMergeSession.thumbnailPixelLimit)
            XCTAssertLessThanOrEqual(thumbnail.image.height, PDFMergeSession.thumbnailPixelLimit)
            XCTAssertEqual(thumbnail.widthPoints, 200, accuracy: 0.01)
            let count = await session.cachedThumbnailCount
            XCTAssertLessThanOrEqual(count, PDFMergeSession.thumbnailCacheLimit)
        }
        let bytes = await session.inspectedByteCount
        XCTAssertEqual(bytes, sources.reduce(0) { $0 + $1.byteCount })
        let again = try await session.source(for: 0)
        XCTAssertEqual(again, sources[0])
        let bytesAfterRepeat = await session.inspectedByteCount
        XCTAssertEqual(bytesAfterRepeat, bytes, "Repeating a source request must not consume its budget twice")
        XCTAssertThrowsError(try PDFSourceSnapshot.capture(first, byteLimit: sources[0].byteCount - 1))
        await session.close()
        let closedCount = await session.cachedThumbnailCount
        let closedBytes = await session.inspectedByteCount
        XCTAssertEqual(closedCount, 0)
        XCTAssertEqual(closedBytes, 0)
        do { _ = try await session.thumbnail(for: 0); XCTFail("A closed merge preview rendered another page") }
        catch FreewheelError.cancelled { }
    }

    func testPDFMergePreviewExportsTheChosenFileOrderAndIgnoresRemovedInputs() async throws {
        let work = try workspace()
        let first = try pdf(work.inputs.appendingPathComponent("first.pdf"), pages: [
            (CGSize(width: 240, height: 160), "Alpha One"), (CGSize(width: 160, height: 240), "Alpha Two")])
        let removed = try pdf(work.inputs.appendingPathComponent("removed.pdf"),
                              pages: [(CGSize(width: 200, height: 100), "Omitted")])
        let last = try pdf(work.inputs.appendingPathComponent("last.pdf"), pages: [
            (CGSize(width: 300, height: 180), "Charlie One"), (CGSize(width: 180, height: 300), "Charlie Two")])
        let document = try XCTUnwrap(PDFDocument(url: last))
        document.documentAttributes = [PDFDocumentAttribute.authorAttribute: "Fixture Author"]
        let page = try XCTUnwrap(document.page(at: 0))
        page.rotation = 90
        page.setBounds(page.bounds(for: .mediaBox).insetBy(dx: 8, dy: 8), for: .cropBox)
        let annotation = PDFAnnotation(bounds: CGRect(x: 20, y: 20, width: 20, height: 20),
                                       forType: .square, withProperties: nil)
        annotation.contents = "Merge Annotation"
        annotation.interiorColor = .red
        page.addAnnotation(annotation)
        XCTAssertTrue(document.write(to: last))
        let originals = try [first, last].map { try Data(contentsOf: $0) }
        let inputs = [first, removed, last]
        let session = PDFMergeSession(inputs: inputs)
        var sources: [PDFMergeSource] = []
        for index in inputs.indices { sources.append(try await session.source(for: index)) }
        var options = ConversionOptions()
        options.pdfMerge = PDFMergePlan(sourceInputCount: 3, sources: [sources[2], sources[0]])
        options.destinationDirectory = work.stage
        let existing = work.stage.appendingPathComponent("Merged.pdf")
        let sentinel = Data("Keep Existing Output".utf8)
        try sentinel.write(to: existing)
        try FileManager.default.removeItem(at: removed)
        var outputs = Set<URL>()
        for alias in [false, true] {
            if alias { try FileManager.default.createSymbolicLink(at: removed, withDestinationURL: first) }
            let result = try await ConversionEngine().run(inputs: inputs, operation: operation("pdf.merge", ext: "pdf"), options: options)
            let output = try XCTUnwrap(result.outputs.first)
            XCTAssertTrue(outputs.insert(output).inserted)
            XCTAssertNotEqual(output, existing)
            let merged = try XCTUnwrap(PDFDocument(url: output))
            XCTAssertEqual(merged.pageCount, 4)
            for (index, text) in ["Charlie One", "Charlie Two", "Alpha One", "Alpha Two"].enumerated() {
                XCTAssertTrue(merged.page(at: index)?.string?.contains(text) == true)
            }
            XCTAssertFalse(merged.string?.contains("Omitted") == true)
            let cover = try XCTUnwrap(merged.page(at: 0))
            XCTAssertEqual(cover.rotation, page.rotation)
            XCTAssertEqual(cover.bounds(for: .mediaBox), page.bounds(for: .mediaBox))
            XCTAssertEqual(cover.bounds(for: .cropBox), page.bounds(for: .cropBox))
            XCTAssertEqual(cover.annotations.map(\.contents), page.annotations.map(\.contents))
            XCTAssertNil(merged.documentAttributes?[PDFDocumentAttribute.authorAttribute])
            XCTAssertEqual(try Data(contentsOf: existing), sentinel)
            XCTAssertEqual(try [first, last].map { try Data(contentsOf: $0) }, originals)
        }
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: work.stage.path)
            .contains(where: { $0.hasPrefix(".freewheel-") }))
        await session.close()
    }

    func testPDFMergePreviewRejectsChangedSourceBytesAndCancelledWork() async throws {
        let work = try workspace()
        let first = try pdf(work.inputs.appendingPathComponent("first.pdf"),
                            pages: [(CGSize(width: 200, height: 100), "First")])
        let second = try pdf(work.inputs.appendingPathComponent("second.pdf"),
                             pages: [(CGSize(width: 200, height: 100), "Second")])
        var bytes = try Data(contentsOf: second)
        bytes.append(Data("\n% Source Version A\n".utf8))
        try bytes.write(to: second)
        let originalDate = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: second.path)[.modificationDate] as? Date)
        let session = PDFMergeSession(inputs: [first, second])
        let firstSource = try await session.source(for: 0)
        let secondSource = try await session.source(for: 1)
        var options = ConversionOptions()
        options.pdfMerge = PDFMergePlan(sourceInputCount: 2, sources: [firstSource, secondSource])
        let original = bytes
        for grows in [false, true] {
            bytes = original
            if grows { bytes.append(Data("% Changed\n".utf8)) }
            else { bytes[bytes.count - 2] = 0x42 }
            try bytes.write(to: second)
            try FileManager.default.setAttributes([.modificationDate: originalDate], ofItemAtPath: second.path)
            do { _ = try await session.thumbnail(for: 1); XCTFail("A replaced PDF produced a stale cover preview") }
            catch FreewheelError.invalidInput(let message) {
                XCTAssertTrue(message.contains("changed"))
                XCTAssertTrue(message.contains(second.lastPathComponent))
                XCTAssertFalse(message.contains(work.root.path))
            }
            do {
                _ = try await NativeConverter.convert(inputs: [first, second], operation: operation("pdf.merge"),
                    options: options, outputDirectory: work.stage)
                XCTFail("A replaced PDF was merged using its old preview")
            } catch FreewheelError.invalidInput(let message) { XCTAssertTrue(message.contains("changed")) }
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: work.stage.path).isEmpty)
            XCTAssertEqual(try Data(contentsOf: second), bytes)
        }
        try original.write(to: second)
        let cancelledOpen = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await session.source(for: 0)
        }
        do { _ = try await cancelledOpen.value; XCTFail("A cancelled merge preview continued") }
        catch is CancellationError { }
        let cancelledExport = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await NativeConverter.convert(inputs: [first, second], operation: self.operation("pdf.merge"),
                options: options, outputDirectory: work.stage)
        }
        do { _ = try await cancelledExport.value; XCTFail("A cancelled merge export continued") }
        catch FreewheelError.cancelled { }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: work.stage.path).isEmpty)
        XCTAssertEqual(try Data(contentsOf: second), original)
        await session.close()
    }

    func testPDFMergePreviewHonorsDocumentPermissionsAndDisclosesUnprotectedOutput() async throws {
        let work = try workspace()
        let plain = try pdf(work.inputs.appendingPathComponent("plain.pdf"),
                            pages: [(CGSize(width: 200, height: 100), "Permitted Content")])
        let copy = PDFAccessPermissions.allowsContentCopying.rawValue
        let assembly = PDFAccessPermissions.allowsDocumentAssembly.rawValue
        let cases: [(String, UInt, Bool)] = [("allowed", copy | assembly, false),
            ("no-copy", assembly, false), ("no-assembly", copy, false), ("locked", copy | assembly, true)]
        for (name, permissions, locked) in cases {
            let source = work.inputs.appendingPathComponent("\(name).pdf")
            let document = try XCTUnwrap(PDFDocument(url: plain))
            let writeOptions: [PDFDocumentWriteOption: Any] = [
                .ownerPasswordOption: UUID().uuidString,
                .userPasswordOption: locked ? UUID().uuidString : "",
                .accessPermissionsOption: NSNumber(value: permissions)
            ]
            XCTAssertTrue(document.write(to: source, withOptions: writeOptions))
            let original = try Data(contentsOf: source)
            let snapshot = try PDFSourceSnapshot.capture(source)
            let session = PDFMergeSession(inputs: [plain, source])
            let first = try await session.source(for: 0)
            let protected = PDFMergeSource(inputIndex: 1, pageCount: 1, fingerprint: snapshot.fingerprint,
                byteCount: snapshot.byteCount, isEncrypted: true)
            var options = ConversionOptions()
            options.pdfMerge = PDFMergePlan(sourceInputCount: 2, sources: [first, protected])
            let stage = try freshStage(work)
            if name == "allowed" {
                let opened = try await session.source(for: 1)
                XCTAssertEqual(opened, protected)
                let result = try await NativeConverter.convert(inputs: [plain, source], operation: operation("pdf.merge"),
                    options: options, outputDirectory: stage)
                let output = try XCTUnwrap(PDFDocument(url: XCTUnwrap(result.outputs.first)))
                XCTAssertFalse(output.isEncrypted)
                XCTAssertEqual(output.pageCount, 2)
                XCTAssertTrue(result.note?.contains("without password protection") == true)
            } else {
                do { _ = try await session.source(for: 1); XCTFail("A locked or restricted PDF entered the merge preview") }
                catch FreewheelError.invalidInput(let message) { XCTAssertTrue(message.contains(source.lastPathComponent)) }
                do {
                    _ = try await NativeConverter.convert(inputs: [plain, source], operation: operation("pdf.merge"),
                        options: options, outputDirectory: stage)
                    XCTFail("Merge export bypassed source permissions")
                } catch FreewheelError.invalidInput { }
                XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: stage.path).isEmpty)
            }
            XCTAssertEqual(try Data(contentsOf: source), original)
            await session.close()
        }
    }

    func testPDFOrganizerLoadsBoundedThumbnailsFromOneStableSnapshot() async throws {
        let work = try workspace()
        let raw = try pdf(work.inputs.appendingPathComponent("raw.pdf"),
            pages: (0..<30).map { (CGSize(width: 160, height: 80), "Page \($0 + 1)") })
        let document = try XCTUnwrap(PDFDocument(url: raw))
        let first = try XCTUnwrap(document.page(at: 0))
        first.setBounds(CGRect(x: 20, y: 10, width: 120, height: 60), for: .cropBox)
        first.rotation = 90
        let annotation = PDFAnnotation(bounds: CGRect(x: 40, y: 20, width: 30, height: 20),
                                       forType: .square, withProperties: nil)
        annotation.interiorColor = .red; annotation.color = .red
        first.addAnnotation(annotation)
        let source = work.inputs.appendingPathComponent("pages.pdf")
        XCTAssertTrue(document.write(to: source))
        let original = try Data(contentsOf: source)
        let session = PDFOrganizeSession(input: source)
        let metadata = try await session.open()
        XCTAssertEqual(metadata.pageCount, 30)
        XCTAssertEqual(metadata.fingerprint.count, 64)
        let initialCache = await session.cachedThumbnailCount
        XCTAssertEqual(initialCache, 0, "Opening the editor must not render every page")
        let rotated = try await session.thumbnail(for: 0)
        XCTAssertEqual(rotated.widthPoints, 60, accuracy: 0.001)
        XCTAssertEqual(rotated.heightPoints, 120, accuracy: 0.001)
        var redPixels = 0
        for y in stride(from: 0, to: rotated.image.height, by: 8) {
            for x in stride(from: 0, to: rotated.image.width, by: 8) {
                let sample = try color(rotated.image, x: x, y: y)
                if sample.redComponent > 0.7, sample.greenComponent < 0.3, sample.blueComponent < 0.3 { redPixels += 1 }
            }
        }
        XCTAssertGreaterThan(redPixels, 2, "The rotated crop-box preview must retain visible annotations")
        for index in 1..<metadata.pageCount {
            let thumbnail = try await session.thumbnail(for: index)
            XCTAssertEqual(thumbnail.sourceIndex, index)
            XCTAssertLessThanOrEqual(thumbnail.image.width, PDFOrganizeSession.thumbnailPixelLimit)
            XCTAssertLessThanOrEqual(thumbnail.image.height, PDFOrganizeSession.thumbnailPixelLimit)
            let count = await session.cachedThumbnailCount
            XCTAssertLessThanOrEqual(count, PDFOrganizeSession.thumbnailCacheLimit)
        }
        for index in [-1, metadata.pageCount] {
            do { _ = try await session.thumbnail(for: index); XCTFail("An invalid page index was accepted") }
            catch FreewheelError.invalidInput { }
        }
        XCTAssertEqual(try Data(contentsOf: source), original)
        // PDFKit must keep reading the private snapshot, not a mutable original.
        try FileManager.default.removeItem(at: source)
        let retained = try await session.thumbnail(for: 0)
        XCTAssertEqual(retained.widthPoints, rotated.widthPoints)
        await session.close()
        let closedCache = await session.cachedThumbnailCount
        XCTAssertEqual(closedCache, 0)
        do { _ = try await session.thumbnail(for: 0); XCTFail("A closed editor continued decoding") }
        catch FreewheelError.cancelled { }
    }

    func testPDFOrganizerCopiesOrderedPagesTextBoxesAnnotationsAndAddedRotations() async throws {
        let work = try workspace()
        let raw = try pdf(work.inputs.appendingPathComponent("raw.pdf"), pages: [
            (CGSize(width: 240, height: 160), "Alpha"), (CGSize(width: 160, height: 240), "Bravo"),
            (CGSize(width: 300, height: 180), "Charlie")])
        let document = try XCTUnwrap(PDFDocument(url: raw))
        document.documentAttributes = [PDFDocumentAttribute.authorAttribute: "Fixture Author"]
        for (index, angle) in [90, 0, 270].enumerated() {
            let page = try XCTUnwrap(document.page(at: index))
            page.rotation = angle
            page.setBounds(page.bounds(for: .mediaBox).insetBy(dx: 10, dy: 10), for: .cropBox)
            let annotation = PDFAnnotation(bounds: CGRect(x: 20, y: 20, width: 20, height: 20),
                                           forType: .square, withProperties: nil)
            annotation.contents = "Annotation \(index + 1)"
            annotation.interiorColor = .red
            page.addAnnotation(annotation)
        }
        let source = work.inputs.appendingPathComponent("pages.pdf")
        XCTAssertTrue(document.write(to: source))
        let original = try Data(contentsOf: source)
        let session = PDFOrganizeSession(input: source)
        let metadata = try await session.open()
        var plan = metadata.initialPlan
        plan.pages = [PDFPageEdit(sourceIndex: 2, rotationQuarterTurns: 1),
                      PDFPageEdit(sourceIndex: 0, rotationQuarterTurns: 2)]
        var options = ConversionOptions(); options.pdfOrganization = plan
        let result = try await NativeConverter.convert(inputs: [source], operation: operation("pdf.organize", ext: "pdf"),
            options: options, outputDirectory: work.stage)
        let output = try XCTUnwrap(result.outputs.first)
        XCTAssertNotEqual(output, source)
        let organized = try XCTUnwrap(PDFDocument(url: output))
        XCTAssertEqual(organized.pageCount, 2)
        XCTAssertTrue(organized.page(at: 0)?.string?.contains("Charlie") == true)
        XCTAssertTrue(organized.page(at: 1)?.string?.contains("Alpha") == true)
        XCTAssertFalse(organized.string?.contains("Bravo") == true)
        for (position, sourceIndex, rotation) in [(0, 2, 0), (1, 0, 270)] {
            let page = try XCTUnwrap(organized.page(at: position))
            let originalPage = try XCTUnwrap(document.page(at: sourceIndex))
            XCTAssertEqual(page.rotation, rotation)
            XCTAssertEqual(page.bounds(for: .mediaBox), originalPage.bounds(for: .mediaBox))
            XCTAssertEqual(page.bounds(for: .cropBox), originalPage.bounds(for: .cropBox))
            XCTAssertEqual(page.annotations.map(\.contents), originalPage.annotations.map(\.contents))
        }
        XCTAssertNil(organized.documentAttributes?[PDFDocumentAttribute.authorAttribute])
        XCTAssertEqual(try Data(contentsOf: source), original)
        // Extracting one selected page keeps the same source identity and delta.
        plan.pages = [plan.pages[1]]; options.pdfOrganization = plan
        let extracted = try await ConversionEngine().run(inputs: [source],
            operation: operation("pdf.organize", ext: "pdf"), options: options)
        let onePage = try XCTUnwrap(PDFDocument(url: XCTUnwrap(extracted.outputs.first)))
        XCTAssertEqual(onePage.pageCount, 1)
        XCTAssertTrue(onePage.page(at: 0)?.string?.contains("Alpha") == true)
        XCTAssertEqual(onePage.page(at: 0)?.rotation, 270)
        XCTAssertEqual(try Data(contentsOf: source), original)
        await session.close()
    }

    func testPDFOrganizerRejectsChangedSourceBytesEvenWithTheSameSizeAndDate() async throws {
        let work = try workspace()
        let source = try pdf(work.inputs.appendingPathComponent("pages.pdf"),
                             pages: [(CGSize(width: 200, height: 100), "Original")])
        var bytes = try Data(contentsOf: source)
        bytes.append(Data("\n% Source Version A\n".utf8))
        try bytes.write(to: source)
        let originalDate = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: source.path)[.modificationDate] as? Date)
        let session = PDFOrganizeSession(input: source)
        let metadata = try await session.open()
        var options = ConversionOptions(); options.pdfOrganization = metadata.initialPlan
        bytes[bytes.count - 2] = 0x42
        try bytes.write(to: source)
        try FileManager.default.setAttributes([.modificationDate: originalDate], ofItemAtPath: source.path)
        do {
            _ = try await NativeConverter.convert(inputs: [source], operation: operation("pdf.organize"),
                options: options, outputDirectory: work.stage)
            XCTFail("A same-size replacement was accepted using stale page edits")
        } catch FreewheelError.invalidInput(let message) { XCTAssertTrue(message.contains("changed")) }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: work.stage.path).isEmpty)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        await session.close()
    }

    func testPDFOrganizerRespectsLockedAndRestrictedSourcesAndDisclosesUnprotectedCopies() async throws {
        let work = try workspace()
        let plain = try pdf(work.inputs.appendingPathComponent("plain.pdf"),
                            pages: [(CGSize(width: 200, height: 100), "Permitted Content")])
        let copy = PDFAccessPermissions.allowsContentCopying.rawValue
        let assembly = PDFAccessPermissions.allowsDocumentAssembly.rawValue
        let cases: [(String, UInt, Bool)] = [("allowed", copy | assembly, false),
            ("no-copy", assembly, false), ("no-assembly", copy, false), ("locked", copy | assembly, true)]
        for (name, permissions, locked) in cases {
            let source = work.inputs.appendingPathComponent("\(name).pdf")
            let document = try XCTUnwrap(PDFDocument(url: plain))
            let ownerPassword = UUID().uuidString
            let writeOptions: [PDFDocumentWriteOption: Any] = [
                .ownerPasswordOption: ownerPassword,
                .userPasswordOption: locked ? UUID().uuidString : "",
                .accessPermissionsOption: NSNumber(value: permissions)
            ]
            XCTAssertTrue(document.write(to: source, withOptions: writeOptions))
            let original = try Data(contentsOf: source)
            let reopened = try XCTUnwrap(PDFDocument(url: source))
            XCTAssertTrue(reopened.isEncrypted, "The fixture must actually be encrypted")
            XCTAssertEqual(reopened.isLocked, locked)
            if !locked {
                XCTAssertEqual(reopened.allowsCopying, permissions & copy != 0)
                XCTAssertEqual(reopened.allowsDocumentAssembly, permissions & assembly != 0)
            }
            let session = PDFOrganizeSession(input: source)
            let stage = try freshStage(work)
            if name == "allowed" {
                let metadata = try await session.open()
                XCTAssertTrue(metadata.isEncrypted)
                var options = ConversionOptions(); options.pdfOrganization = metadata.initialPlan
                let result = try await NativeConverter.convert(inputs: [source], operation: operation("pdf.organize"),
                    options: options, outputDirectory: stage)
                let output = try XCTUnwrap(PDFDocument(url: XCTUnwrap(result.outputs.first)))
                XCTAssertFalse(output.isEncrypted)
                XCTAssertTrue(output.string?.contains("Permitted Content") == true)
                XCTAssertTrue(result.note?.contains("without password protection") == true)
            } else {
                do { _ = try await session.open(); XCTFail("A locked or restricted PDF entered the editor") }
                catch FreewheelError.invalidInput { }
                var options = ConversionOptions()
                options.pdfOrganization = PDFOrganizePlan(sourcePageCount: 1,
                    sourceFingerprint: try PDFSourceSnapshot.capture(source).fingerprint, pages: [PDFPageEdit(sourceIndex: 0)])
                do {
                    _ = try await NativeConverter.convert(inputs: [source], operation: operation("pdf.organize"),
                        options: options, outputDirectory: stage)
                    XCTFail("Export bypassed the source PDF permissions")
                } catch FreewheelError.invalidInput { }
                XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: stage.path).isEmpty)
            }
            XCTAssertEqual(try Data(contentsOf: source), original)
            await session.close()
        }
    }

    func testPDFOrganizerRejectsNonregularOversizedAndCancelledInputs() async throws {
        let work = try workspace()
        let pipe = work.inputs.appendingPathComponent("pipe.pdf")
        XCTAssertEqual(mkfifo(pipe.path, 0o600), 0)
        let oversized = work.inputs.appendingPathComponent("oversized.pdf")
        XCTAssertTrue(FileManager.default.createFile(atPath: oversized.path, contents: nil))
        let handle = try FileHandle(forWritingTo: oversized)
        try handle.truncate(atOffset: UInt64(PDFSourceSnapshot.maximumBytes) + 1)
        try handle.close()
        let empty = work.inputs.appendingPathComponent("empty.pdf")
        let invalid = work.inputs.appendingPathComponent("invalid.pdf")
        try Data().write(to: empty)
        try Data("This is not a PDF".utf8).write(to: invalid)
        for input in [pipe, oversized, empty, invalid] {
            let session = PDFOrganizeSession(input: input)
            do { _ = try await session.open(); XCTFail("An invalid PDF source reached PDFKit") }
            catch FreewheelError.invalidInput { }
            await session.close()
        }
        let source = try pdf(work.inputs.appendingPathComponent("valid.pdf"),
                             pages: [(CGSize(width: 100, height: 100), "Valid")])
        let session = PDFOrganizeSession(input: source)
        let cancelledOpen = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await session.open()
        }
        do { _ = try await cancelledOpen.value; XCTFail("A cancelled editor open continued") }
        catch is CancellationError { }
        let metadata = try await session.open()
        let cancelledExport = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            var options = ConversionOptions(); options.pdfOrganization = metadata.initialPlan
            return try await NativeConverter.convert(inputs: [source], operation: self.operation("pdf.organize"),
                options: options, outputDirectory: work.stage)
        }
        do { _ = try await cancelledExport.value; XCTFail("A cancelled page export continued") }
        catch FreewheelError.cancelled { }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: work.stage.path).isEmpty)
        await session.close()
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

    func testNativeWordExportPreservesTextAndUsesPublicPackageMetadata() async throws {
        let work = try workspace()
        let input = work.inputs.appendingPathComponent("plain.txt")
        let text = "  İstanbul  東京 🍋\tSecond Column\n\nXML & < > \"quoted\"\nhttps://example.invalid/unchanged\nFINALMARKER"
        let original = Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)
        try original.write(to: input)
        let result = try await NativeConverter.convert(inputs: [input], operation: operation("convert.docx"),
            options: ConversionOptions(), outputDirectory: work.stage)
        let output = try XCTUnwrap(result.outputs.first)
        XCTAssertEqual(result.outputs.count, 1)
        XCTAssertEqual(output.pathExtension, "docx")
        XCTAssertEqual(try Data(contentsOf: input), original)
        XCTAssertTrue(result.note?.contains("Author and editor metadata use Lemulip") == true)
        let word = try Data(contentsOf: output)
        XCTAssertEqual(word.prefix(4), Data([0x50, 0x4B, 0x03, 0x04]))
        let reopened = try NSAttributedString(data: word,
            options: [.documentType: NSAttributedString.DocumentType.officeOpenXML], documentAttributes: nil)
        // TextKit may expose the final DOCX paragraph terminator as one extra
        // newline. No other whitespace or document content may disappear.
        XCTAssertTrue(reopened.string == text || reopened.string == text + "\n")

        // Inspect the real OPC package through the existing libarchive bridge;
        // checking only a PK signature would accept an arbitrary ZIP file.
        let extracted = try await ExternalConverters.archives([output], operation: operation("archive.extract"),
                                                               directory: freshStage(work))
        let package = try XCTUnwrap(extracted.outputs.first)
        let contentTypes = try XMLDocument(contentsOf: package.appendingPathComponent("[Content_Types].xml"),
                                           options: .nodeLoadExternalEntitiesNever)
        XCTAssertEqual(try contentTypes.nodes(forXPath: "/*[local-name()='Types']/*[local-name()='Override' and @ContentType='application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml']").count, 1)
        let relationships = try XMLDocument(contentsOf: package.appendingPathComponent("_rels/.rels"),
                                            options: .nodeLoadExternalEntitiesNever)
        let mainRelationship = try XCTUnwrap(try relationships.nodes(forXPath: "/*[local-name()='Relationships']/*[local-name()='Relationship']")
            .compactMap { $0 as? XMLElement }
            .first { $0.attribute(forName: "Type")?.stringValue?.hasSuffix("/officeDocument") == true })
        let target = try XCTUnwrap(mainRelationship.attribute(forName: "Target")?.stringValue)
        XCTAssertNotEqual(mainRelationship.attribute(forName: "TargetMode")?.stringValue, "External")
        XCTAssertFalse(target.split(separator: "/").contains(".."))
        let mainPath = target.hasPrefix("/") ? String(target.dropFirst()) : target
        let document = try XMLDocument(contentsOf: package.appendingPathComponent(mainPath), options: .nodeLoadExternalEntitiesNever)
        XCTAssertEqual(document.rootElement()?.localName, "document")
        let content = try document.nodes(forXPath: "//*[local-name()='t']").compactMap { $0.stringValue }.joined()
        XCTAssertTrue(content.contains("XML & < > \"quoted\""))
        XCTAssertTrue(content.contains("FINALMARKER"))

        let parts = try XCTUnwrap(FileManager.default.enumerator(at: package, includingPropertiesForKeys: nil))
        for case let part as URL in parts where ["xml", "rels"].contains(part.pathExtension) {
            let xml = try XMLDocument(contentsOf: part, options: .nodeLoadExternalEntitiesNever)
            let personalFields = try xml.nodes(forXPath: "//*[local-name()='creator' or local-name()='lastModifiedBy' or local-name()='Company' or local-name()='Manager']")
            for field in personalFields {
                XCTAssertTrue(["", "Lemulip"].contains(field.stringValue ?? ""), "Office metadata must contain only the public product identity")
            }
            XCTAssertTrue(try xml.nodes(forXPath: "//*[local-name()='Relationship' and @TargetMode='External']").isEmpty)
            XCTAssertFalse(try String(contentsOf: part, encoding: .utf8).contains(work.root.path))
        }
    }

    func testNativeWordExportDecodesUTF8AndBothUTF16ByteOrders() async throws {
        let work = try workspace()
        let inputText = "Alpha\r\n\r\nİstanbul\t東京\rFinal"
        let expected = "Alpha\n\nİstanbul\t東京\nFinal"
        let originals = [Data(inputText.utf8),
                         Data([0xFF, 0xFE]) + (try XCTUnwrap(inputText.data(using: .utf16LittleEndian))),
                         Data([0xFE, 0xFF]) + (try XCTUnwrap(inputText.data(using: .utf16BigEndian)))]
        for (index, original) in originals.enumerated() {
            let input = work.inputs.appendingPathComponent("encoding-\(index).TXT")
            try original.write(to: input)
            let result = try await NativeConverter.convert(inputs: [input], operation: operation("convert.docx"),
                options: ConversionOptions(), outputDirectory: freshStage(work))
            let reopened = try NSAttributedString(data: Data(contentsOf: XCTUnwrap(result.outputs.first)),
                options: [.documentType: NSAttributedString.DocumentType.officeOpenXML], documentAttributes: nil)
            XCTAssertTrue(reopened.string == expected || reopened.string == expected + "\n")
            XCTAssertEqual(try Data(contentsOf: input), original)
        }
    }

    func testNativeWordExportRejectsUnsupportedTextWithoutPublishingOutput() async throws {
        let work = try workspace()
        let invalidInputs = [Data([0xC3, 0x28]), Data([0xFF, 0xFE, 0x41]), Data([0xFF, 0xFE, 0x00, 0xD8]), Data([0xEF, 0xBB, 0xBF]),
                             Data("Alpha\u{0000}Beta".utf8), Data("Alpha\u{000B}Beta".utf8), Data("Alpha\u{FFFE}Beta".utf8)]
        for (index, original) in invalidInputs.enumerated() {
            let input = work.inputs.appendingPathComponent("invalid-\(index).txt")
            let stage = try freshStage(work)
            try original.write(to: input)
            do {
                _ = try await NativeConverter.convert(inputs: [input], operation: operation("convert.docx"),
                    options: ConversionOptions(), outputDirectory: stage)
                XCTFail("Invalid text must not silently become a Word document")
            } catch FreewheelError.invalidInput { }
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: stage.path).isEmpty)
            XCTAssertEqual(try Data(contentsOf: input), original)
        }
        let oversized = work.inputs.appendingPathComponent("oversized.txt")
        try Data("A".utf8).write(to: oversized)
        let handle = try FileHandle(forWritingTo: oversized)
        try handle.truncate(atOffset: 32 * 1_024 * 1_024 + 1)
        try handle.close()
        do {
            _ = try await NativeConverter.convert(inputs: [oversized], operation: operation("convert.docx"),
                options: ConversionOptions(), outputDirectory: work.stage)
            XCTFail("Word export must enforce the text input size bound")
        } catch FreewheelError.invalidInput { }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: work.stage.path).isEmpty)
    }

    func testNativeWordExportPreflightsRichInputsBeforeReadingTheBatch() async throws {
        let work = try workspace()
        let invalidText = work.inputs.appendingPathComponent("not-utf8.txt")
        try Data([0xC3, 0x28]).write(to: invalidText)
        for (ext, content) in [("rtf", #"{\rtf1\ansi {\field{\*\fldinst HYPERLINK "https://example.invalid/"}{\fldrslt Rich text}}}"#),
                               ("html", "<p>Rich <b>text</b></p>"), ("md", "# Heading")] {
            let rich = work.inputs.appendingPathComponent("rich.\(ext)")
            let original = Data(content.utf8)
            try original.write(to: rich)
            do {
                _ = try await NativeConverter.convert(inputs: [invalidText, rich], operation: operation("convert.docx"),
                    options: ConversionOptions(), outputDirectory: work.stage)
                XCTFail("Rich inputs must keep their optional document engine")
            } catch FreewheelError.unsupported { }
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: work.stage.path).isEmpty)
            XCTAssertEqual(try Data(contentsOf: rich), original)
        }
    }

    func testNativeRTFWordExportPreservesInstalledFontsAndParagraphFormatting() async throws {
        let work = try workspace()
        let input = work.inputs.appendingPathComponent("formatted.rtf")
        let text = "Orchard Notes\nBold Italic Both\nSecond Paragraph\tFinal"
        let regular = try XCTUnwrap(NSFont(name: "Helvetica", size: 12))
        let heading = try XCTUnwrap(NSFont(name: "Helvetica-Bold", size: 18))
        let italic = try XCTUnwrap(NSFont(name: "Helvetica-Oblique", size: 12))
        let both = try XCTUnwrap(NSFont(name: "Helvetica-BoldOblique", size: 12))
        let attributed = NSMutableAttributedString(string: text, attributes: [.font: regular])
        let titleStyle = NSMutableParagraphStyle()
        titleStyle.alignment = .center
        titleStyle.paragraphSpacingBefore = 6
        titleStyle.paragraphSpacing = 12
        let bodyStyle = NSMutableParagraphStyle()
        bodyStyle.alignment = .left
        bodyStyle.firstLineHeadIndent = 18
        bodyStyle.headIndent = 12
        bodyStyle.paragraphSpacing = 8
        attributed.addAttributes([.font: heading, .paragraphStyle: titleStyle],
            range: (text as NSString).range(of: "Orchard Notes\n"))
        attributed.addAttribute(.font, value: try XCTUnwrap(NSFont(name: "Helvetica-Bold", size: 12)),
            range: (text as NSString).range(of: "Bold"))
        attributed.addAttribute(.font, value: italic, range: (text as NSString).range(of: "Italic"))
        attributed.addAttribute(.font, value: both, range: (text as NSString).range(of: "Both"))
        attributed.addAttribute(.foregroundColor, value: NSColor(srgbRed: 0.2, green: 0.6, blue: 0.1, alpha: 1),
            range: (text as NSString).range(of: "Both"))
        attributed.addAttribute(.paragraphStyle, value: bodyStyle, range: (text as NSString).range(of: "Second Paragraph\tFinal"))
        let original = try attributed.data(from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf,
                                 .author: "Synthetic RTF Author", .editor: "Synthetic RTF Editor", .company: "Synthetic RTF Company"])
        try original.write(to: input)
        let result = try await NativeConverter.convert(inputs: [input], operation: operation("convert.docx"),
            options: ConversionOptions(), outputDirectory: work.stage)
        let output = try XCTUnwrap(result.outputs.first)
        XCTAssertEqual(result.outputs.count, 1)
        XCTAssertEqual(try Data(contentsOf: input), original)
        XCTAssertTrue(result.note?.contains("basic RTF formatting") == true)
        XCTAssertTrue(result.note?.contains("Page layout and margins are not reconstructed") == true)
        let reopened = try NSAttributedString(data: Data(contentsOf: output),
            options: [.documentType: NSAttributedString.DocumentType.officeOpenXML], documentAttributes: nil)
        XCTAssertTrue(reopened.string == text || reopened.string == text + "\n")
        for (phrase, size, bold, slanted) in [("Orchard Notes", CGFloat(18), true, false),
                                             ("Bold", 12, true, false), ("Italic", 12, false, true), ("Both", 12, true, true)] {
            let position = (reopened.string as NSString).range(of: phrase).location
            XCTAssertNotEqual(position, NSNotFound)
            guard position != NSNotFound else { continue }
            let font = try XCTUnwrap(reopened.attribute(.font, at: position, effectiveRange: nil) as? NSFont)
            XCTAssertEqual(font.familyName, regular.familyName)
            XCTAssertEqual(font.pointSize, size, accuracy: 0.1)
            XCTAssertEqual(font.fontDescriptor.symbolicTraits.contains(.bold), bold)
            XCTAssertEqual(font.fontDescriptor.symbolicTraits.contains(.italic), slanted)
        }
        let titleStart = try XCTUnwrap(reopened.string.range(of: "Orchard Notes")).lowerBound
        let titleOffset = titleStart.utf16Offset(in: reopened.string)
        let title = try XCTUnwrap(reopened.attribute(.paragraphStyle, at: titleOffset, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertEqual(title.alignment, .center)
        XCTAssertEqual(title.paragraphSpacingBefore, 6, accuracy: 0.1)
        XCTAssertEqual(title.paragraphSpacing, 12, accuracy: 0.1)
        let bodyPosition = try XCTUnwrap(reopened.string.range(of: "Second Paragraph")).lowerBound
        let bodyOffset = bodyPosition.utf16Offset(in: reopened.string)
        let body = try XCTUnwrap(reopened.attribute(.paragraphStyle, at: bodyOffset, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertEqual(body.alignment, .left)
        XCTAssertEqual(body.firstLineHeadIndent, 18, accuracy: 0.1)
        XCTAssertEqual(body.headIndent, 12, accuracy: 0.1)
        XCTAssertEqual(body.paragraphSpacing, 8, accuracy: 0.1)
        let colorStart = try XCTUnwrap(reopened.string.range(of: "Both")).lowerBound
        let colorPosition = colorStart.utf16Offset(in: reopened.string)
        let color = try XCTUnwrap((reopened.attribute(.foregroundColor, at: colorPosition, effectiveRange: nil) as? NSColor)?.usingColorSpace(.sRGB))
        XCTAssertEqual(color.redComponent, 0.2, accuracy: 0.01)
        XCTAssertEqual(color.greenComponent, 0.6, accuracy: 0.01)
        XCTAssertEqual(color.blueComponent, 0.1, accuracy: 0.01)
    }

    func testNativeRTFWordExportPreservesUnicodeEscapesAndUsesOnlyPublicMetadataInMixedBatch() async throws {
        let work = try workspace()
        let input = work.inputs.appendingPathComponent("escaped.RTF")
        let rtf = #"{\rtf1\ansi\ansicpg1252\uc1{\fonttbl{\f0\fswiss Helvetica;}}{\info{\author Synthetic RTF Author}{\operator Synthetic RTF Editor}{\company Synthetic RTF Company}}\f0\fs24 Caf\'e9 \u304?stanbul \u26481?\u20140? \u-10180?\u-8373? \{braces\} \\pict\par Final}"#
        let original = Data(rtf.utf8)
        let plain = work.inputs.appendingPathComponent("plain.txt")
        try original.write(to: input)
        try Data("Plain Text".utf8).write(to: plain)
        let result = try await NativeConverter.convert(inputs: [plain, input], operation: operation("convert.docx"),
            options: ConversionOptions(), outputDirectory: work.stage)
        XCTAssertEqual(result.outputs.count, 2)
        XCTAssertEqual(try Data(contentsOf: input), original)
        XCTAssertEqual(try String(contentsOf: plain, encoding: .utf8), "Plain Text")
        let output = try XCTUnwrap(result.outputs.last)
        let reopened = try NSAttributedString(data: Data(contentsOf: output),
            options: [.documentType: NSAttributedString.DocumentType.officeOpenXML], documentAttributes: nil)
        let expected = "Café İstanbul 東京 🍋 {braces} \\pict\nFinal"
        XCTAssertTrue(reopened.string == expected || reopened.string == expected + "\n")
        let extracted = try await ExternalConverters.archives([output], operation: operation("archive.extract"), directory: freshStage(work))
        let package = try XCTUnwrap(extracted.outputs.first)
        let parts = try XCTUnwrap(FileManager.default.enumerator(at: package, includingPropertiesForKeys: nil))
        for case let part as URL in parts where ["xml", "rels"].contains(part.pathExtension) {
            let xml = try XMLDocument(contentsOf: part, options: .nodeLoadExternalEntitiesNever)
            for field in try xml.nodes(forXPath: "//*[local-name()='creator' or local-name()='lastModifiedBy' or local-name()='Company' or local-name()='Manager']") {
                XCTAssertTrue(["", "Lemulip"].contains(field.stringValue ?? ""))
            }
            XCTAssertTrue(try xml.nodes(forXPath: "//*[local-name()='Relationship' and @TargetMode='External']").isEmpty)
            let content = try String(contentsOf: part, encoding: .utf8)
            XCTAssertFalse(content.contains("Synthetic RTF"))
            XCTAssertFalse(content.contains(work.root.path))
        }
    }

    func testNativeRTFWordExportKeepsComplexDocumentsOnTheOptionalEngineRoute() async throws {
        let work = try workspace()
        let plain = work.inputs.appendingPathComponent("first.txt")
        try Data("First file must not be published before the batch route is known.".utf8).write(to: plain)
        let complex = [#"{\pict\pngblip 89504e47}"#, #"{\object\objemb{\*\objdata 00}}"#,
                       #"\trowd\cellx2000\intbl Cell\cell\row"#, #"{\*\listtable{\list\listid1}}"#,
                       #"{\field{\*\fldinst HYPERLINK "https://example.invalid/"}{\fldrslt Link}}"#,
                       #"{\header Header}"#, #"{\footer Footer}"#, #"{\footnote Footnote}"#,
                       #"{\NeXTGraphic local-image.png \width100\height100}"#, #"{\*\unknownDestination Hidden text}"#,
                       #"\shad Styled text"#, #"\bin1 x"#]
        for (index, content) in complex.enumerated() {
            let input = work.inputs.appendingPathComponent("rich-\(index).rtf")
            let original = Data(("{\\rtf1\\ansi Text " + content + "}").utf8)
            try original.write(to: input)
            do {
                _ = try await NativeConverter.convert(inputs: [plain, input], operation: operation("convert.docx"),
                    options: ConversionOptions(), outputDirectory: work.stage)
                XCTFail("Complex RTF must not silently lose content")
            } catch FreewheelError.unsupported(let message) { XCTAssertTrue(message.contains("LibreOffice")) }
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: work.stage.path).isEmpty)
            XCTAssertEqual(try Data(contentsOf: input), original)
        }
    }

    func testNativeRTFWordExportRejectsMalformedBoundedAndCancelledInputWithoutOutput() async throws {
        let work = try workspace()
        let input = work.inputs.appendingPathComponent("invalid.rtf")
        let invalid = ["plain text", #"{\rtf2\ansi Text}"#, #"{\rtf1\ansi Unclosed"#,
                       #"{\rtf1\ansi Extra}}"#, #"{\rtf1\ansi \'xz}"#, #"{\rtf1\ansi \fs- Text}"#,
                       #"{\rtf1\ansi \fs2147483648 Text}"#, "{\\rtf1\\ansi Alpha\u{0000}Beta}", #"{\rtf1\ansi}"#,
                       "{\\rtf1 " + String(repeating: "{", count: 128) + "Text" + String(repeating: "}", count: 128) + "}"]
        for rtf in invalid {
            let original = Data(rtf.utf8)
            try original.write(to: input)
            do {
                _ = try await NativeConverter.convert(inputs: [input], operation: operation("convert.docx"),
                    options: ConversionOptions(), outputDirectory: work.stage)
                XCTFail("Malformed or unrepresentable basic RTF must not publish an output")
            } catch FreewheelError.invalidInput { }
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: work.stage.path).isEmpty)
            XCTAssertEqual(try Data(contentsOf: input), original)
        }
        try Data(#"{\rtf1\ansi Cancelled export}"#.utf8).write(to: input)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await NativeConverter.convert(inputs: [input], operation: operation("convert.docx"),
                options: ConversionOptions(), outputDirectory: work.stage)
        }
        do { _ = try await cancelled.value; XCTFail("Cancelled Word export must stop before writing") }
        catch FreewheelError.cancelled { }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: work.stage.path).isEmpty)
        let handle = try FileHandle(forWritingTo: input)
        try handle.truncate(atOffset: 32 * 1_024 * 1_024 + 1)
        try handle.close()
        do {
            _ = try await NativeConverter.convert(inputs: [input], operation: operation("convert.docx"),
                options: ConversionOptions(), outputDirectory: work.stage)
            XCTFail("RTF Word export must enforce the shared text input size bound")
        } catch FreewheelError.invalidInput { }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: work.stage.path).isEmpty)
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
                              frames: Int = 60, portrait: Bool = false,
                              transform: CGAffineTransform? = nil, quadrants: Bool = false,
                              pixelAspectRatio: Int? = nil) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        var settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 200_000, AVVideoMaxKeyFrameIntervalKey: 30]
        ]
        if let pixelAspectRatio {
            settings[AVVideoPixelAspectRatioKey] = [
                AVVideoPixelAspectRatioHorizontalSpacingKey: pixelAspectRatio,
                AVVideoPixelAspectRatioVerticalSpacingKey: 1
            ]
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        if let transform {
            input.transform = transform
        } else if portrait {
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
                            if quadrants {
                                let left = x < width / 2, top = y < height / 2
                                bytes[offset] = left && !top ? 255 : 0
                                bytes[offset + 1] = !left ? 255 : 0
                                bytes[offset + 2] = left == top ? 255 : 0
                            } else {
                                bytes[offset] = blue ? 255 : 0
                                bytes[offset + 1] = 0
                                bytes[offset + 2] = blue ? 0 : 255
                            }
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

    private func assertVideoColor(_ frame: CGImage, x: Int, y: Int, rgb: [Bool],
                                  file: StaticString = #filePath, line: UInt = #line) throws {
        let pixel = try color(frame, x: x, y: y)
        let values = [pixel.redComponent, pixel.greenComponent, pixel.blueComponent]
        for (actual, bright) in zip(values, rgb) {
            if bright { XCTAssertGreaterThan(actual, 0.7, file: file, line: line) }
            else { XCTAssertLessThan(actual, 0.3, file: file, line: line) }
        }
    }

    func testNativeVideoCropUsesUprightPixelsForEveryQuarterTurn() async throws {
        let work = try workspace()
        let transforms: [CGAffineTransform] = [
            .identity,
            CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 48, ty: 0),
            CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 64, ty: 48),
            CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 64)
        ]
        // Raw top-left/top-right/bottom-left/bottom-right are red/green/blue/yellow.
        // Expected colors are independent of the crop transform implementation.
        let topLeft: [[Bool]] = [[true, false, false], [false, false, true],
                                 [true, true, false], [false, true, false]]
        let bottomRight: [[Bool]] = [[true, true, false], [false, true, false],
                                     [true, false, false], [false, false, true]]
        for turn in 0..<4 {
            let input = work.inputs.appendingPathComponent("corners-\(turn).mov")
            try await videoFixture(input, width: 64, height: 48, frames: 12,
                                    transform: transforms[turn], quadrants: true)
            let original = try Data(contentsOf: input)
            let preview = try await NativeConverter.videoCropPreview(for: input, maxPixelSize: Int.max)
            let width = turn % 2 == 0 ? 64 : 48
            let height = turn % 2 == 0 ? 48 : 64
            XCTAssertEqual(preview.sourceWidth, width)
            XCTAssertEqual(preview.sourceHeight, height)
            XCTAssertEqual(preview.durationSeconds, 0.4, accuracy: 0.001)
            try assertVideoColor(preview.image, x: 4, y: 4, rgb: topLeft[turn])
            try assertVideoColor(preview.image, x: preview.image.width - 5,
                                 y: preview.image.height - 5, rgb: bottomRight[turn])
            let crop = VideoCropRegion(x: width / 2 + 4, y: height / 2 + 4,
                width: width / 2 - 8, height: height / 2 - 8,
                sourceWidth: width, sourceHeight: height, sourceDuration: preview.durationSeconds)
            var options = ConversionOptions(); options.videoCrop = crop
            let result = try await NativeConverter.convert(inputs: [input], operation: operation("media.crop", ext: "mp4"),
                options: options, outputDirectory: freshStage(work))
            let output = try XCTUnwrap(result.outputs.first)
            let exported = try await NativeConverter.videoCropPreview(for: output)
            XCTAssertEqual(exported.sourceWidth, crop.outputWidth)
            XCTAssertEqual(exported.sourceHeight, crop.outputHeight)
            XCTAssertEqual(exported.durationSeconds, 0.4, accuracy: 0.04)
            let frame = exported.image
            for (x, y) in [(2, 2), (frame.width - 3, 2), (2, frame.height - 3), (frame.width - 3, frame.height - 3)] {
                try assertVideoColor(frame, x: x, y: y, rgb: bottomRight[turn])
            }
            XCTAssertEqual(try Data(contentsOf: input), original)
        }
    }

    func testNativeVideoCropKeepsFullDurationAudioAndExactEvenSize() async throws {
        let work = try workspace()
        let wide = work.root.appendingPathComponent("wide-preview.mov")
        try await videoFixture(wide, width: 1_536, height: 768, frames: 1)
        let bounded = try await NativeConverter.videoCropPreview(for: wide, maxPixelSize: Int.max)
        XCTAssertEqual(bounded.sourceWidth, 1_536)
        XCTAssertEqual(bounded.sourceHeight, 768)
        XCTAssertLessThanOrEqual(bounded.image.width, 1_280)
        XCTAssertLessThanOrEqual(bounded.image.height, 1_280)
        let input = work.inputs.appendingPathComponent("sound-and-color.mov")
        try await videoWithAudioFixture(input, workspace: work)
        let original = try Data(contentsOf: input)
        let preview = try await NativeConverter.videoCropPreview(for: input, maxPixelSize: 24)
        XCTAssertLessThanOrEqual(preview.image.width, 24)
        XCTAssertLessThanOrEqual(preview.image.height, 24)
        XCTAssertEqual(preview.sourceWidth, 64)
        XCTAssertEqual(preview.sourceHeight, 32)
        var options = ConversionOptions()
        // Odd programmatic dimensions round inward without a scaling transform.
        options.videoCrop = VideoCropRegion(x: 9, y: 5, width: 33, height: 21,
            sourceWidth: 64, sourceHeight: 32, sourceDuration: preview.durationSeconds)
        // Spatial cropping must ignore independent legacy trim fields.
        options.startSeconds = 0.5; options.endSeconds = 1
        for ext in ["mp4", "mov"] {
            let result = try await NativeConverter.convert(inputs: [input], operation: operation("media.crop", ext: ext),
                options: options, outputDirectory: freshStage(work))
            let output = try XCTUnwrap(result.outputs.first)
            XCTAssertTrue(output.lastPathComponent.contains("cropped"))
            let asset = AVURLAsset(url: output)
            let audio = try await asset.loadTracks(withMediaType: .audio)
            XCTAssertEqual(audio.count, 1)
            let first = try await NativeConverter.videoCropPreview(for: output, atSeconds: 0.1)
            let last = try await NativeConverter.videoCropPreview(for: output, atSeconds: 1.8)
            XCTAssertEqual(first.sourceWidth, 32)
            XCTAssertEqual(first.sourceHeight, 20)
            XCTAssertEqual(first.durationSeconds, 2, accuracy: 0.08)
            try assertVideoColor(first.image, x: 4, y: 4, rgb: [true, false, false])
            try assertVideoColor(last.image, x: 4, y: 4, rgb: [false, false, true])
            XCTAssertTrue(result.note?.contains("without stretching") == true)
            XCTAssertTrue(result.note?.contains("H.264") == true)
        }
        XCTAssertEqual(try Data(contentsOf: input), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: work.inputs.path), ["sound-and-color.mov"])
    }

    func testNativeVideoCropRejectsMismatchedMetadataAndUnsupportedDisplayGeometry() async throws {
        let work = try workspace()
        let input = work.inputs.appendingPathComponent("valid.mov")
        try await videoFixture(input, frames: 6)
        let original = try Data(contentsOf: input)
        let invalidTime: [Double] = [-1, .nan, .infinity, 0.2]
        for time in invalidTime {
            do {
                _ = try await NativeConverter.videoCropPreview(for: input, atSeconds: time)
                XCTFail("An invalid crop preview time was accepted")
            } catch FreewheelError.invalidInput { }
        }
        do {
            _ = try await NativeConverter.videoCropPreview(for: input, maxPixelSize: 0)
            XCTFail("A zero-sized video crop preview was accepted")
        } catch FreewheelError.invalidInput { }
        for dimensionsChanged in [false, true] {
            var options = ConversionOptions()
            options.videoCrop = VideoCropRegion(x: 2, y: 2, width: 16, height: 16,
                sourceWidth: dimensionsChanged ? 66 : 64, sourceHeight: 32,
                sourceDuration: dimensionsChanged ? 0.2 : 1)
            do {
                _ = try await ConversionEngine().run(inputs: [input], operation: operation("media.crop", ext: "mp4"), options: options)
                XCTFail("A crop from changed source metadata was accepted")
            } catch FreewheelError.invalidInput(let message) { XCTAssertTrue(message.contains("changed")) }
        }
        let mirrored = work.inputs.appendingPathComponent("mirrored.mov")
        try await videoFixture(mirrored, frames: 6, transform: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 64, ty: 0))
        let nonsquare = work.inputs.appendingPathComponent("nonsquare.mov")
        try await videoFixture(nonsquare, frames: 6, pixelAspectRatio: 2)
        for unsupported in [mirrored, nonsquare] {
            do {
                _ = try await NativeConverter.videoCropPreview(for: unsupported)
                XCTFail("Unsupported display geometry was offered for cropping")
            } catch FreewheelError.unsupported { }
        }
        XCTAssertEqual(try Data(contentsOf: input), original)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: work.stage.path).isEmpty)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: work.inputs.path)), ["valid.mov", "mirrored.mov", "nonsquare.mov"])
    }

    func testNativeVideoCropPreviewAndExportRespectCancellation() async throws {
        let work = try workspace()
        let input = work.inputs.appendingPathComponent("clip.mov")
        try await videoFixture(input, frames: 6)
        let original = try Data(contentsOf: input)
        let preview = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await NativeConverter.videoCropPreview(for: input)
        }
        do { _ = try await preview.value; XCTFail("Cancelled crop preview completed") }
        catch is CancellationError { }
        let export = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            var options = ConversionOptions()
            options.videoCrop = VideoCropRegion(x: 0, y: 0, width: 16, height: 16,
                sourceWidth: 64, sourceHeight: 32, sourceDuration: 0.2)
            return try await NativeConverter.convert(inputs: [input],
                operation: FileOperation(id: "media.crop", title: "Crop Video", outputExtension: "mp4"),
                options: options, outputDirectory: work.stage)
        }
        do { _ = try await export.value; XCTFail("Cancelled video crop completed") }
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
