#if os(macOS)
import Foundation
import AppKit
import AVFoundation
import CoreGraphics
import CoreText
import ImageIO
import PDFKit
import Vision

/// ImageIO creates an immutable CGImage. This value crosses from a background
/// decode task to the editor; neither the pixels nor the dimensions are mutated.
public struct ImageCropPreview: @unchecked Sendable {
    public let image: CGImage
    public let sourceWidth: Int
    public let sourceHeight: Int
}

/// Local Apple-framework conversions. The caller owns a fresh, private staging
/// directory and publishes the returned files only after the whole job succeeds.
public enum NativeConverter {
    private static let maximumRasterPixels = 40_000_000
    private static let maximumSourcePixels = 150_000_000
    private static let maximumDimension = 16_384
    private static let maximumPages = 1_000
    private static let maximumOutputs = 10_000
    private static let maximumTextBytes = 32 * 1_024 * 1_024
    private static let maximumCropPreviewEdge = 1_600

    /// A bounded, orientation-correct preview. Crop coordinates always refer to
    /// sourceWidth/sourceHeight, not to this smaller image's pixel dimensions.
    public static func imageCropPreview(for input: URL, maxPixelSize: Int = 1_600) throws -> ImageCropPreview {
        try Task.checkCancellation()
        guard maxPixelSize > 0 else {
            throw FreewheelError.invalidInput("The crop preview size must be positive.")
        }
        return try autoreleasepool {
            let original = try cropImageSource(input)
            // The editor saves in the source format. Check that encoder before
            // offering a selection the user would be unable to export.
            do { _ = try imageDestinationType(input.pathExtension.lowercased()) }
            catch FreewheelError.unsupported {
                throw FreewheelError.unsupported("macOS cannot save a visual crop in this image's format. Convert it to PNG or JPEG first, then open the crop editor.")
            }
            let edge = min(maxPixelSize, maximumCropPreviewEdge)
            let frame: ImageFrame
            do { frame = try decodeImage(original.source, index: 0, longEdge: edge) }
            catch FreewheelError.unsupported {
                throw FreewheelError.unsupported("macOS cannot preview this image for cropping. Convert it to PNG or JPEG first.")
            }
            try Task.checkCancellation()
            guard frame.image.width <= edge, frame.image.height <= edge else {
                throw FreewheelError.operationFailed("The image decoder exceeded the crop preview size limit.")
            }
            return ImageCropPreview(image: frame.image, sourceWidth: original.width, sourceHeight: original.height)
        }
    }

    public static func convert(
        inputs: [URL], operation: FileOperation, options: ConversionOptions,
        outputDirectory: URL
    ) async throws -> ConversionResult {
        try validateJob(inputs: inputs, outputDirectory: outputDirectory)
        do {
            try Task.checkCancellation()
            if let crop = options.imageCrop {
                guard operation.id == "image.crop", inputs.count == 1,
                      FileFamily.detect(inputs[0]) == .image else {
                    throw FreewheelError.invalidInput("A selected crop requires Crop Image and exactly one still image.")
                }
                try crop.validateBounds()
                try validateDimensions(width: crop.sourceWidth, height: crop.sourceHeight)
                guard inputs[0].pathExtension.lowercased() != "svg" else {
                    throw FreewheelError.unsupported("Visual cropping needs a still raster image. Convert SVG to PNG first.")
                }
                // This route also rejects non-raster output types rather than
                // accidentally entering imagesToPDF and discarding the selection.
                return try await convertImages(inputs, operation: operation, options: options,
                                               directory: outputDirectory)
            }
            if operation.id == "pdf.merge" {
                return try mergePDFs(inputs, options: options, directory: outputDirectory)
            }
            if operation.id == "document.wordCount" {
                return try countWords(inputs, options: options, directory: outputDirectory)
            }
            if inputs.allSatisfy({ FileFamily.detect($0) == .image }) {
                if outputExtension(operation) == "pdf" {
                    return try await imagesToPDF(inputs, options: options, directory: outputDirectory)
                }
                return try await convertImages(inputs, operation: operation, options: options,
                                               directory: outputDirectory)
            }
            if inputs.allSatisfy({ FileFamily.detect($0) == .pdf }) {
                return try convertPDFs(inputs, operation: operation, options: options,
                                       directory: outputDirectory)
            }
            if inputs.allSatisfy({ [.audio, .video].contains(FileFamily.detect($0)) }) {
                return try await convertMedia(inputs, operation: operation, options: options,
                                              directory: outputDirectory)
            }
            if inputs.allSatisfy({ FileFamily.detect($0) == .document }) {
                return try convertDocuments(inputs, operation: operation, directory: outputDirectory)
            }
            throw FreewheelError.unsupported("These files need an optional conversion engine.")
        } catch {
            // validateJob required an empty directory; everything here belongs
            // to this attempt. In particular, a failed native attempt must not
            // leave partial pages beside the external engine's retry.
            for file in (try? FileManager.default.contentsOfDirectory(
                at: outputDirectory, includingPropertiesForKeys: nil)) ?? [] {
                try? FileManager.default.removeItem(at: file)
            }
            if error is CancellationError { throw FreewheelError.cancelled }
            throw error
        }
    }

    private static func validateJob(inputs: [URL], outputDirectory: URL) throws {
        guard !inputs.isEmpty, inputs.count <= maximumPages else {
            throw FreewheelError.invalidInput("Choose between 1 and \(maximumPages) files.")
        }
        guard outputDirectory.isFileURL else {
            throw FreewheelError.invalidInput("The output directory must be a local folder.")
        }
        let values = try outputDirectory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true,
              try FileManager.default.contentsOfDirectory(atPath: outputDirectory.path).isEmpty else {
            throw FreewheelError.invalidInput("Native conversion requires an empty staging folder.")
        }
        for input in inputs {
            guard input.isFileURL else {
                throw FreewheelError.invalidInput("Only local files can be converted.")
            }
            let values = try input.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, FileManager.default.isReadableFile(atPath: input.path) else {
                throw FreewheelError.unsupported("Choose readable files. Document packages need an optional engine.")
            }
            guard (values.fileSize ?? 0) > 0 else {
                throw FreewheelError.invalidInput("\(input.lastPathComponent) is empty.")
            }
        }
    }

    private static func outputExtension(_ operation: FileOperation) -> String? {
        if let value = operation.outputExtension, !value.isEmpty { return value.lowercased() }
        if operation.id.hasPrefix("convert.") {
            return String(operation.id.dropFirst("convert.".count)).lowercased()
        }
        return nil
    }

    private static func outputURL(_ input: URL, suffix: String, ext: String, directory: URL) -> URL {
        let stem = input.deletingPathExtension().lastPathComponent
        return OutputStore.uniqueURL(in: directory, stem: (stem.isEmpty ? "Converted" : stem) + suffix,
                                     extension: ext)
    }

    private static func checkedQuality(_ value: Double) throws -> Double {
        guard value.isFinite, (0.05...1).contains(value) else {
            throw FreewheelError.invalidInput("Quality must be between 0.05 and 1.")
        }
        return value
    }

    private static func validateDimensions(width: Int, height: Int) throws {
        guard width > 0, height > 0, width <= maximumDimension, height <= maximumDimension,
              width <= maximumRasterPixels / height else {
            throw FreewheelError.invalidInput("The rendered image is too large. Use dimensions up to \(maximumDimension) pixels and 40 megapixels.")
        }
    }

    private static func checkedLongEdge(_ value: Int) throws -> Int {
        guard (1...maximumDimension).contains(value) else {
            throw FreewheelError.invalidInput("The longest edge must be between 1 and \(maximumDimension) pixels.")
        }
        return value
    }

    // MARK: - Images

    // A decoded frame is immutable. SVG returns one across MainActor.run; its
    // metadata dictionary is empty and never shared for mutation.
    private struct ImageFrame: @unchecked Sendable {
        let image: CGImage
        let properties: [String: Any]
    }

    private static func imageSource(_ url: URL) throws -> CGImageSource {
        guard let source = CGImageSourceCreateWithURL(url as CFURL,
                                                      [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0 else {
            throw FreewheelError.unsupported("macOS cannot decode this image. An optional image engine may support it.")
        }
        guard CGImageSourceGetCount(source) <= maximumPages else {
            throw FreewheelError.invalidInput("This image contains too many frames (limit: \(maximumPages)).")
        }
        return source
    }

    private static func cropImageSource(_ input: URL) throws -> (source: CGImageSource, width: Int, height: Int) {
        try Task.checkCancellation()
        guard input.isFileURL, !input.path.contains("\0") else {
            throw FreewheelError.invalidInput("Choose a local image to crop.")
        }
        guard FileFamily.detect(input) == .image, input.pathExtension.lowercased() != "svg" else {
            throw FreewheelError.unsupported("Visual cropping needs a still raster image. Convert SVG or other documents to PNG first.")
        }
        let values = try input.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, FileManager.default.isReadableFile(atPath: input.path),
              (values.fileSize ?? 0) > 0 else {
            throw FreewheelError.invalidInput("Choose a nonempty, readable image file to crop.")
        }
        let source: CGImageSource
        do { source = try imageSource(input) }
        catch FreewheelError.unsupported {
            throw FreewheelError.unsupported("macOS cannot read this image for cropping. Convert it to PNG or JPEG first.")
        }
        guard CGImageSourceGetCount(source) == 1 else {
            throw FreewheelError.unsupported("Visual cropping supports one still image. Export animated or multipage images to PNG first.")
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let rawWidth = (properties[kCGImagePropertyPixelWidth as String] as? NSNumber)?.doubleValue,
              let rawHeight = (properties[kCGImagePropertyPixelHeight as String] as? NSNumber)?.doubleValue,
              rawWidth.isFinite, rawHeight.isFinite, rawWidth >= 1, rawHeight >= 1,
              rawWidth <= Double(maximumDimension), rawHeight <= Double(maximumDimension),
              rawWidth.rounded(.towardZero) == rawWidth, rawHeight.rounded(.towardZero) == rawHeight else {
            throw FreewheelError.invalidInput("Visual cropping supports original images up to 16,384 pixels per edge and 40 megapixels.")
        }
        let width = Int(rawWidth), height = Int(rawHeight)
        // Reject an oversized original before requesting even a tiny thumbnail:
        // the same original must be safe to decode when the selection is saved.
        try validateDimensions(width: width, height: height)
        let orientation = (properties[kCGImagePropertyOrientation as String] as? NSNumber)?.intValue ?? 1
        guard (1...8).contains(orientation) else {
            throw FreewheelError.invalidInput("This image has an invalid orientation. Export a new PNG or JPEG before cropping.")
        }
        try Task.checkCancellation()
        return (source, orientation >= 5 ? height : width, orientation >= 5 ? width : height)
    }

    private static func decodeImage(_ source: CGImageSource, index: Int,
                                    longEdge: Int? = nil) throws -> ImageFrame {
        try Task.checkCancellation()
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any],
              let width = (properties[kCGImagePropertyPixelWidth as String] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight as String] as? NSNumber)?.intValue,
              width > 0, height > 0, width <= maximumSourcePixels / height else {
            throw FreewheelError.invalidInput("The image dimensions are invalid or exceed the 150-megapixel input limit.")
        }
        let requestedEdge = min(longEdge ?? max(width, height), max(width, height))
        let scale = min(1, Double(requestedEdge) / Double(max(width, height)))
        try validateDimensions(width: max(1, Int(ceil(Double(width) * scale))),
                               height: max(1, Int(ceil(Double(height) * scale))))
        // Asking ImageIO for a full-size thumbnail applies EXIF orientation once
        // and downsamples during decode, avoiding a full-resolution intermediate.
        let decodeOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: requestedEdge,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, decodeOptions as CFDictionary) else {
            throw FreewheelError.unsupported("macOS could not decode an image frame. Try the optional image engine.")
        }
        try Task.checkCancellation()
        try validateDimensions(width: image.width, height: image.height)
        return ImageFrame(image: image, properties: properties)
    }

    private static func convertImages(_ inputs: [URL], operation: FileOperation,
                                      options: ConversionOptions, directory: URL) async throws -> ConversionResult {
        let supportedTools: Set<String> = ["image.compress", "image.resize", "image.crop", "image.rotate",
                                          "image.flip", "image.stripMetadata"]
        guard operation.id.hasPrefix("convert.") || supportedTools.contains(operation.id) else {
            throw FreewheelError.unsupported("This image tool requires an optional engine.")
        }
        let quality = try checkedQuality(options.quality)
        let longEdge = operation.id == "image.resize" ? try checkedLongEdge(options.maxDimension) : nil
        if operation.id == "image.crop", options.imageCrop == nil {
            try validateDimensions(width: options.width, height: options.height)
        }
        var outputs: [URL] = []
        var notes = Set<String>()
        for input in inputs {
            try Task.checkCancellation()
            let ext = outputExtension(operation) ?? (input.pathExtension.lowercased() == "svg" ? "png" : input.pathExtension.lowercased())
            let type: String
            do { type = try imageDestinationType(ext) }
            catch FreewheelError.unsupported {
                guard options.imageCrop == nil else {
                    throw FreewheelError.unsupported("macOS cannot save the selected crop as \(ext.uppercased()). Convert the source to PNG or JPEG first, then make a new selection.")
                }
                throw FreewheelError.unsupported("macOS cannot encode \(ext.uppercased()) on this system. Enable the optional image engine.")
            }
            let suffix = operation.id.hasPrefix("image.") ? "-" + String(operation.id.dropFirst(6)) : "-converted"
            if input.pathExtension.lowercased() == "svg" {
                let frame = try await rasterizeSVG(input, longEdge: longEdge)
                let output = outputURL(input, suffix: String(suffix), ext: ext, directory: directory)
                try processImage(frame, operation: operation, options: options, quality: quality, type: type,
                                 destination: output)
                outputs.append(output)
                notes.insert("SVG output is rasterized. External SVG resources are not loaded.")
            } else {
                let source: CGImageSource
                if let crop = options.imageCrop {
                    let original = try cropImageSource(input)
                    guard crop.sourceWidth == original.width, crop.sourceHeight == original.height else {
                        throw FreewheelError.invalidInput("The image dimensions changed after the crop was selected. Open the crop editor again.")
                    }
                    source = original.source
                } else { source = try imageSource(input) }
                let count = CGImageSourceGetCount(source)
                guard count <= maximumOutputs - outputs.count else {
                    throw FreewheelError.invalidInput("A batch can produce at most \(maximumOutputs) image files. Split this selection into smaller batches.")
                }
                if count > 1 { notes.insert("All image frames were exported as separate still images; animation timing is not retained.") }
                for index in 0..<count {
                    try Task.checkCancellation()
                    let output = outputURL(input, suffix: String(suffix) + (count > 1 ? String(format: "-frame-%03d", index + 1) : ""),
                                           ext: ext, directory: directory)
                    try autoreleasepool {
                        do {
                            let frame = try decodeImage(source, index: index, longEdge: longEdge)
                            try processImage(frame, operation: operation, options: options, quality: quality,
                                             type: type, destination: output)
                        } catch FreewheelError.unsupported(let message) {
                            guard options.imageCrop == nil else {
                                throw FreewheelError.unsupported("macOS could not finish this selected crop in \(ext.uppercased()). Convert the source to PNG or JPEG first, then make a new selection.")
                            }
                            throw FreewheelError.unsupported(message)
                        }
                    }
                    outputs.append(output)
                }
            }
            if operation.id == "image.compress", ext == "png" || ext == "bmp" || ext == "tif" || ext == "tiff" {
                notes.insert("This format uses lossless image encoding; the quality slider affects JPEG and HEIC. A smaller file is not guaranteed.")
            }
        }
        try Task.checkCancellation()
        return ConversionResult(outputs: outputs, note: notes.isEmpty ? nil : notes.sorted().joined(separator: " "))
    }

    private static func processImage(_ frame: ImageFrame, operation: FileOperation,
                                     options: ConversionOptions, quality: Double,
                                     type: String, destination: URL) throws {
        try Task.checkCancellation()
        var image = frame.image
        switch operation.id {
        case "image.crop":
            let rect: CGRect
            if let crop = options.imageCrop {
                try crop.validateBounds()
                guard crop.sourceWidth == image.width, crop.sourceHeight == image.height else {
                    throw FreewheelError.invalidInput("The decoded image no longer matches the crop preview. Open the crop editor again.")
                }
                // CGImage crops use the first pixel of the top row as (0, 0).
                rect = CGRect(x: crop.x, y: crop.y, width: crop.width, height: crop.height)
            } else {
                guard options.width <= image.width, options.height <= image.height else {
                    throw FreewheelError.invalidInput("Crop dimensions exceed this image's \(image.width) × \(image.height) pixels. Choose a smaller crop.")
                }
                rect = CGRect(x: (image.width - options.width) / 2, y: (image.height - options.height) / 2,
                              width: options.width, height: options.height)
            }
            guard let cropped = image.cropping(to: rect) else {
                throw FreewheelError.operationFailed("The crop could not be created.")
            }
            image = cropped
        case "image.rotate": image = try rotatedImage(image, degrees: options.rotationDegrees)
        case "image.flip":
            image = try drawImage(image, width: image.width, height: image.height) { context in
                context.translateBy(x: CGFloat(image.width), y: 0)
                context.scaleBy(x: -1, y: 1)
            }
        default: break
        }
        let strip = options.removeMetadata || operation.id == "image.stripMetadata"
        try writeImage(image, type: type, quality: quality,
                       properties: strip ? [:] : frame.properties, destination: destination)
        try Task.checkCancellation()
    }

    private static func bitmap(width: Int, height: Int, opaque: Bool = false) throws -> CGContext {
        try validateDimensions(width: width, height: height)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw FreewheelError.operationFailed("Not enough memory to render this image.")
        }
        context.interpolationQuality = .high
        if opaque {
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return context
    }

    private static func drawImage(_ image: CGImage, width: Int, height: Int,
                                  opaque: Bool = false, transform: (CGContext) -> Void = { _ in }) throws -> CGImage {
        let context = try bitmap(width: width, height: height, opaque: opaque)
        transform(context)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let output = context.makeImage() else { throw FreewheelError.operationFailed("Image rendering failed.") }
        return output
    }

    private static func rotatedImage(_ image: CGImage, degrees: Int) throws -> CGImage {
        let normalized = ((degrees % 360) + 360) % 360
        if normalized == 0 { return image }
        let angle = -CGFloat(normalized) * .pi / 180 // Clockwise, like Finder's image tools.
        let width: Int, height: Int
        if normalized % 90 == 0 {
            width = normalized % 180 == 0 ? image.width : image.height
            height = normalized % 180 == 0 ? image.height : image.width
        } else {
            width = Int(ceil(abs(CGFloat(image.width) * cos(angle)) + abs(CGFloat(image.height) * sin(angle))))
            height = Int(ceil(abs(CGFloat(image.width) * sin(angle)) + abs(CGFloat(image.height) * cos(angle))))
        }
        return try drawImage(image, width: width, height: height) { context in
            context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
            context.rotate(by: angle)
            context.translateBy(x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2)
        }
    }

    private static func imageDestinationType(_ ext: String) throws -> String {
        let identifiers = ["jpg": "public.jpeg", "jpeg": "public.jpeg", "png": "public.png",
                           "heic": "public.heic", "heif": "public.heic", "tif": "public.tiff",
                           "tiff": "public.tiff", "bmp": "com.microsoft.bmp", "webp": "org.webmproject.webp",
                           "avif": "public.avif"]
        guard let type = identifiers[ext.lowercased()],
              (CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []).contains(type) else {
            throw FreewheelError.unsupported("macOS cannot encode \(ext.uppercased()) on this system. Enable the optional image engine.")
        }
        return type
    }

    private static func writeImage(_ image: CGImage, type: String, quality: Double,
                                   properties: [String: Any], destination: URL) throws {
        guard !FileManager.default.fileExists(atPath: destination.path),
              let writer = CGImageDestinationCreateWithURL(destination as CFURL, type as CFString, 1, nil) else {
            throw FreewheelError.operationFailed("Could not create a new image output.")
        }
        var metadata = properties
        metadata.removeValue(forKey: kCGImagePropertyPixelWidth as String)
        metadata.removeValue(forKey: kCGImagePropertyPixelHeight as String)
        metadata[kCGImagePropertyOrientation as String] = 1
        metadata[kCGImageDestinationLossyCompressionQuality as String] = quality
        if var tiff = metadata[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            tiff[kCGImagePropertyTIFFOrientation as String] = 1
            metadata[kCGImagePropertyTIFFDictionary as String] = tiff
        }
        if var exif = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            exif[kCGImagePropertyExifPixelXDimension as String] = image.width
            exif[kCGImagePropertyExifPixelYDimension as String] = image.height
            metadata[kCGImagePropertyExifDictionary as String] = exif
        }
        let opaque = type == "public.jpeg" || type == "com.microsoft.bmp"
        let encodedImage = opaque ? try drawImage(image, width: image.width, height: image.height, opaque: true) : image
        CGImageDestinationAddImage(writer, encodedImage, metadata as CFDictionary)
        guard CGImageDestinationFinalize(writer) else {
            throw FreewheelError.unsupported("The system image encoder could not finish this format. Try the optional image engine.")
        }
    }

    private static func rasterizeSVG(_ input: URL, longEdge: Int?) async throws -> ImageFrame {
        let data = try boundedTextData(input)
        let validator = SafeSVGValidator()
        guard let xml = String(data: data, encoding: .utf8),
              !xml.localizedCaseInsensitiveContains("<!DOCTYPE"),
              !xml.localizedCaseInsensitiveContains("<!ENTITY") else {
            throw FreewheelError.invalidInput("SVG must use UTF-8 and must not declare external entities.")
        }
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = validator
        guard parser.parse(), validator.valid, validator.sawSVG else {
            // This is a policy rejection, not a missing decoder: an external
            // engine must not retry it and accidentally load those resources.
            throw FreewheelError.invalidInput("This SVG contains malformed XML, scripting, styling, or external resources. Use a self-contained shape SVG.")
        }
        return try await MainActor.run {
            guard let image = NSImage(data: data), image.size.width.isFinite, image.size.height.isFinite,
                  image.size.width > 0, image.size.height > 0 else {
                throw FreewheelError.unsupported("This macOS version cannot rasterize this SVG. Enable the optional image engine.")
            }
            let scale = min(1, CGFloat(longEdge ?? maximumDimension) / max(image.size.width, image.size.height))
            let width = max(1, Int(ceil(image.size.width * scale)))
            let height = max(1, Int(ceil(image.size.height * scale)))
            let context = try bitmap(width: width, height: height)
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            image.draw(in: NSRect(x: 0, y: 0, width: width, height: height), from: .zero,
                       operation: .sourceOver, fraction: 1)
            guard let output = context.makeImage() else { throw FreewheelError.operationFailed("SVG rendering failed.") }
            return ImageFrame(image: output, properties: [:])
        }
    }

    private final class SafeSVGValidator: NSObject, XMLParserDelegate {
        var valid = true
        var sawSVG = false
        private var elements = 0
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String]) {
            elements += 1
            let tag = elementName.lowercased().split(separator: ":").last.map(String.init) ?? ""
            if tag == "svg" { sawSVG = true }
            if elements > 50_000 || ["script", "style", "foreignobject", "iframe", "object", "embed", "image", "use", "a"].contains(tag) {
                valid = false; parser.abortParsing(); return
            }
            for (key, value) in attributeDict {
                let name = key.lowercased(), content = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                // Namespace identifiers are not resource requests. Every normal
                // SVG declares the W3C namespace, which must remain acceptable.
                if name == "xmlns" || name.hasPrefix("xmlns:") { continue }
                if name.hasPrefix("on") || name == "style" || name == "xml:base" ||
                    ((name == "href" || name.hasSuffix(":href")) && !content.hasPrefix("#")) ||
                    ["@import", "http:", "https:", "file:", "javascript:", "data:"].contains(where: { content.contains($0) }) ||
                    (content.contains("url(") && content.range(of: #"^url\(\s*#[A-Za-z0-9_.:-]+\s*\)$"#, options: .regularExpression) == nil) {
                    valid = false; parser.abortParsing(); return
                }
            }
        }
        func parser(_ parser: XMLParser, foundProcessingInstructionWithTarget target: String, data: String?) {
            if target.lowercased() != "xml" { valid = false; parser.abortParsing() }
        }
        func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? {
            valid = false; parser.abortParsing(); return nil
        }
    }

    // MARK: - PDF

    private static func loadPDF(_ input: URL, password: String) throws -> PDFDocument {
        guard let document = PDFDocument(url: input) else {
            throw FreewheelError.invalidInput("\(input.lastPathComponent) is not a readable PDF.")
        }
        if document.isLocked {
            guard !password.isEmpty, document.unlock(withPassword: password), !document.isLocked else {
                throw FreewheelError.invalidInput("This PDF is password protected. Open it with its password and save an unlocked copy, then try again.")
            }
        }
        guard document.pageCount > 0, document.pageCount <= maximumPages else {
            throw FreewheelError.invalidInput("PDFs must contain between 1 and \(maximumPages) pages.")
        }
        return document
    }

    private static func copiedPage(_ document: PDFDocument, at index: Int) throws -> PDFPage {
        guard let page = document.page(at: index), let copy = page.copy() as? PDFPage else {
            throw FreewheelError.operationFailed("PDF page \(index + 1) could not be copied.")
        }
        return copy
    }

    private static func savePDF(_ document: PDFDocument, to output: URL) throws {
        guard !FileManager.default.fileExists(atPath: output.path), document.pageCount > 0,
              document.write(to: output) else {
            throw FreewheelError.operationFailed("The PDF output could not be written.")
        }
    }

    private static func mergePDFs(_ inputs: [URL], options: ConversionOptions,
                                  directory: URL) throws -> ConversionResult {
        guard inputs.count >= 2, inputs.allSatisfy({ FileFamily.detect($0) == .pdf }) else {
            throw FreewheelError.invalidInput("Choose at least two PDF files to merge.")
        }
        let merged = PDFDocument()
        var decrypted = false
        for input in inputs {
            try Task.checkCancellation()
            let document = try loadPDF(input, password: options.password)
            decrypted = decrypted || document.isEncrypted
            guard document.pageCount <= maximumPages - merged.pageCount else {
                throw FreewheelError.invalidInput("A merged PDF can contain at most \(maximumPages) pages.")
            }
            for index in 0..<document.pageCount {
                try Task.checkCancellation()
                merged.insert(try copiedPage(document, at: index), at: merged.pageCount)
            }
        }
        merged.documentAttributes = [:]
        let output = OutputStore.uniqueURL(in: directory, stem: "Merged", extension: "pdf")
        try savePDF(merged, to: output)
        return ConversionResult(outputs: [output], note: decrypted ? "The merged output is not password protected." : nil)
    }

    private static func convertPDFs(_ inputs: [URL], operation: FileOperation,
                                    options: ConversionOptions, directory: URL) throws -> ConversionResult {
        let ext = outputExtension(operation)
        var outputs: [URL] = []
        var notes = Set<String>()
        for input in inputs {
            try Task.checkCancellation()
            let document = try loadPDF(input, password: options.password)
            let pageOutputs = operation.id == "pdf.split" ||
                (operation.id.hasPrefix("convert.") && !["txt", "md", "rtf", "html"].contains(ext ?? ""))
            guard (pageOutputs ? document.pageCount : 1) <= maximumOutputs - outputs.count else {
                throw FreewheelError.invalidInput("A batch can produce at most \(maximumOutputs) files. Split this PDF selection into smaller batches.")
            }
            if document.isEncrypted { notes.insert("Converted outputs are not password protected.") }
            switch operation.id {
            case "pdf.split":
                for index in 0..<document.pageCount {
                    try Task.checkCancellation()
                    let output = outputURL(input, suffix: String(format: "-page-%03d", index + 1), ext: "pdf", directory: directory)
                    let split = PDFDocument()
                    split.insert(try copiedPage(document, at: index), at: 0)
                    split.documentAttributes = options.removeMetadata ? [:] : document.documentAttributes
                    try savePDF(split, to: output)
                    outputs.append(output)
                }
            case "pdf.extract", "pdf.rotate":
                let indices = operation.id == "pdf.extract" ? try pageIndices(options.pageRange, count: document.pageCount) : Array(0..<document.pageCount)
                if operation.id == "pdf.rotate", options.rotationDegrees % 90 != 0 {
                    throw FreewheelError.invalidInput("PDF rotation must be a multiple of 90 degrees.")
                }
                let result = PDFDocument()
                result.documentAttributes = options.removeMetadata ? [:] : document.documentAttributes
                for index in indices {
                    try Task.checkCancellation()
                    let page = try copiedPage(document, at: index)
                    if operation.id == "pdf.rotate" {
                        let angle = options.rotationDegrees % 360
                        page.rotation = ((page.rotation + angle) % 360 + 360) % 360
                    }
                    result.insert(page, at: result.pageCount)
                }
                let output = outputURL(input, suffix: operation.id == "pdf.rotate" ? "-rotated" : "-extracted", ext: "pdf", directory: directory)
                try savePDF(result, to: output)
                outputs.append(output)
            case "pdf.compress":
                let output = outputURL(input, suffix: "-compressed", ext: "pdf", directory: directory)
                try compressPDF(document, options: options, output: output)
                outputs.append(output)
                notes.insert("PDF compression flattens pages into images at up to 150 DPI. Text selection, links, forms, and vector detail are not retained; page dimensions are preserved. A smaller file is not guaranteed.")
            case "pdf.ocr":
                guard document.allowsCopying else { throw FreewheelError.invalidInput("This PDF does not permit text extraction.") }
                let text = try recognizePDFText(document)
                let output = outputURL(input, suffix: "-ocr", ext: "txt", directory: directory)
                try Data(text.utf8).write(to: output, options: .withoutOverwriting)
                outputs.append(output)
                notes.insert("OCR was performed locally with Apple Vision. Review recognized text for mistakes; the output is a text file, not a searchable PDF.")
            default:
                guard let ext = ext, operation.id.hasPrefix("convert.") else {
                    throw FreewheelError.unsupported("This PDF operation needs an optional engine.")
                }
                if ["txt", "md", "rtf", "html"].contains(ext) {
                    let text = try extractedText(document, markdown: ext == "md")
                    let output = outputURL(input, suffix: "-converted", ext: ext, directory: directory)
                    try writeDocument(NSAttributedString(string: text), ext: ext, output: output)
                    outputs.append(output)
                    notes.insert("PDF text was extracted from its existing text layer. Page layout and scanned text are not reconstructed; use OCR for scanned pages.")
                } else {
                    let type = try imageDestinationType(ext)
                    let quality = try checkedQuality(options.quality)
                    for index in 0..<document.pageCount {
                        try Task.checkCancellation()
                        let output = outputURL(input, suffix: String(format: "-page-%03d", index + 1), ext: ext, directory: directory)
                        try autoreleasepool {
                            guard let page = document.page(at: index) else { throw FreewheelError.operationFailed("A PDF page could not be read.") }
                            let image = try renderPDF(page, dpi: 300)
                            try writeImage(image, type: type, quality: quality, properties: [
                                kCGImagePropertyDPIWidth as String: 300,
                                kCGImagePropertyDPIHeight as String: 300
                            ], destination: output)
                        }
                        outputs.append(output)
                    }
                    notes.insert("Every PDF page was exported separately at 300 DPI.")
                }
            }
        }
        return ConversionResult(outputs: outputs, note: notes.isEmpty ? nil : notes.sorted().joined(separator: " "))
    }

    private static func pageIndices(_ specification: String, count: Int) throws -> [Int] {
        guard !specification.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              specification.count <= 10_000 else {
            throw FreewheelError.invalidInput("Enter page numbers such as 1-3,5.")
        }
        var result: [Int] = [], seen = Set<Int>()
        for part in specification.split(separator: ",", omittingEmptySubsequences: false) {
            let components = part.trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: "-", omittingEmptySubsequences: false)
            guard (1...2).contains(components.count),
                  let first = Int(components[0].trimmingCharacters(in: .whitespaces)),
                  let last = Int(components.last!.trimmingCharacters(in: .whitespaces)),
                  first >= 1, last >= first, last <= count else {
                throw FreewheelError.invalidInput("Page ranges must be within 1-\(count), for example 1-3,5.")
            }
            for page in first...last where seen.insert(page - 1).inserted { result.append(page - 1) }
        }
        guard !result.isEmpty else { throw FreewheelError.invalidInput("Choose at least one PDF page.") }
        return result
    }

    private static func pageSize(_ page: PDFPage) throws -> CGSize {
        guard let reference = page.pageRef else { throw FreewheelError.operationFailed("The PDF page could not be rendered.") }
        let box = reference.getBoxRect(.cropBox).intersection(reference.getBoxRect(.mediaBox))
        guard box.width.isFinite, box.height.isFinite, box.width > 0, box.height > 0,
              box.width <= 14_400, box.height <= 14_400 else {
            throw FreewheelError.invalidInput("The PDF page has invalid or excessively large dimensions.")
        }
        let turn = ((reference.rotationAngle % 360) + 360) % 360
        return turn == 90 || turn == 270 ? CGSize(width: box.height, height: box.width) : box.size
    }

    private static func renderPDF(_ page: PDFPage, dpi: CGFloat, longEdge: Int? = nil) throws -> CGImage {
        let size = try pageSize(page)
        var scale = dpi / 72
        if let limit = longEdge { scale = min(scale, CGFloat(limit) / max(size.width, size.height)) }
        func pixelCount(_ points: CGFloat) -> Int {
            let value = points * scale
            let nearest = value.rounded()
            // A mathematically whole pixel can land a few ULPs above its
            // integer value (for example, 60 points at 300 DPI). Keep ceiling
            // for fractional pixels without adding a spurious row or column.
            let count = abs(value - nearest) <= value.ulp * 4 ? nearest : ceil(value)
            return max(1, Int(count))
        }
        let width = pixelCount(size.width), height = pixelCount(size.height)
        let context = try bitmap(width: width, height: height, opaque: true)
        let drawingScale = min(CGFloat(width) / size.width, CGFloat(height) / size.height)
        context.translateBy(x: (CGFloat(width) - size.width * drawingScale) / 2,
                            y: (CGFloat(height) - size.height * drawingScale) / 2)
        context.scaleBy(x: drawingScale, y: drawingScale)
        // PDFKit draws the cropped, rotated content and visible annotations
        // together. Applying a separate CGPDFPage transform to annotations
        // mixes absolute page space with PDFKit's box-relative coordinates.
        page.draw(with: .cropBox, to: context)
        guard let image = context.makeImage() else { throw FreewheelError.operationFailed("PDF page rendering failed.") }
        return image
    }

    private static func beginPDFPage(_ context: CGContext, size: CGSize) {
        var box = CGRect(origin: .zero, size: size)
        let data = Data(bytes: &box, count: MemoryLayout<CGRect>.size)
        context.beginPDFPage([kCGPDFContextMediaBox as String: data] as CFDictionary)
    }

    private static func pdfContext(_ output: URL) throws -> CGContext {
        guard !FileManager.default.fileExists(atPath: output.path),
              let context = CGContext(output as CFURL, mediaBox: nil,
                                      [kCGPDFContextCreator as String: "Lemulip"] as CFDictionary) else {
            throw FreewheelError.operationFailed("A PDF output could not be created.")
        }
        return context
    }

    private static func imagesToPDF(_ inputs: [URL], options: ConversionOptions,
                                    directory: URL) async throws -> ConversionResult {
        let output = inputs.count == 1 ? outputURL(inputs[0], suffix: "-converted", ext: "pdf", directory: directory)
            : OutputStore.uniqueURL(in: directory, stem: "Images", extension: "pdf")
        let context = try pdfContext(output)
        defer { context.closePDF() }
        var pages = 0
        func append(_ frame: ImageFrame) throws {
            pages += 1
            guard pages <= maximumPages else { throw FreewheelError.invalidInput("An image PDF can contain at most \(maximumPages) pages.") }
            let image = frame.image
            // One page per image, with the oriented aspect ratio. Cap the page
            // to a familiar A4 long edge without cropping or upscaling pixels.
            let pointsPerPixel = min(1, 842 / CGFloat(max(image.width, image.height)))
            let size = CGSize(width: CGFloat(image.width) * pointsPerPixel, height: CGFloat(image.height) * pointsPerPixel)
            beginPDFPage(context, size: size)
            context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(origin: .zero, size: size))
            context.draw(image, in: CGRect(origin: .zero, size: size))
            context.endPDFPage()
        }
        for input in inputs {
            try Task.checkCancellation()
            if input.pathExtension.lowercased() == "svg" {
                try append(try await rasterizeSVG(input, longEdge: nil))
            } else {
                let source = try imageSource(input)
                for index in 0..<CGImageSourceGetCount(source) {
                    try Task.checkCancellation()
                    try autoreleasepool { try append(decodeImage(source, index: index)) }
                }
            }
        }
        return ConversionResult(outputs: [output], note: "Each image or image frame became one PDF page. Orientation and aspect ratio are preserved; the longest page edge is capped at 842 points.")
    }

    private static func compressPDF(_ document: PDFDocument, options: ConversionOptions, output: URL) throws {
        let quality = try checkedQuality(options.quality)
        let longEdge = try checkedLongEdge(options.maxDimension)
        let context = try pdfContext(output)
        defer { context.closePDF() }
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            try autoreleasepool {
                guard let page = document.page(at: index) else { throw FreewheelError.operationFailed("The PDF contains an unreadable page.") }
                let size = try pageSize(page)
                let image = try renderPDF(page, dpi: 150, longEdge: longEdge)
                let data = NSMutableData()
                guard let encoder = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else {
                    throw FreewheelError.operationFailed("The JPEG encoder is unavailable.")
                }
                CGImageDestinationAddImage(encoder, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
                guard CGImageDestinationFinalize(encoder), let provider = CGDataProvider(data: data as CFData),
                      let jpeg = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
                    throw FreewheelError.operationFailed("A PDF page could not be compressed.")
                }
                beginPDFPage(context, size: size)
                context.draw(jpeg, in: CGRect(origin: .zero, size: size))
                context.endPDFPage()
            }
        }
    }

    private static func extractedText(_ document: PDFDocument, markdown: Bool = false) throws -> String {
        guard document.allowsCopying else { throw FreewheelError.invalidInput("This PDF does not permit text extraction.") }
        var pages: [String] = []
        var hasText = false
        var total = 0
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            let text = document.page(at: index)?.string ?? ""
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { hasText = true }
            total += text.utf8.count
            guard total <= maximumTextBytes else { throw FreewheelError.invalidInput("The extracted text exceeds the 32 MB limit.") }
            pages.append(markdown ? "## Page \(index + 1)\n\n\(text)" : text)
        }
        guard hasText else {
            throw FreewheelError.invalidInput("This PDF has no readable text layer. Use the OCR tool to recognize scanned pages.")
        }
        return pages.joined(separator: markdown ? "\n\n" : "\n\u{000C}\n")
    }

    private static func recognizePDFText(_ document: PDFDocument) throws -> String {
        var pages: [String] = [], total = 0
        var hasText = false
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            let text: String = try autoreleasepool {
                guard let page = document.page(at: index) else { throw FreewheelError.operationFailed("A PDF page could not be read.") }
                let image = try renderPDF(page, dpi: 300, longEdge: 5_000)
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.automaticallyDetectsLanguage = true
                try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
                return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            }
            total += text.utf8.count
            guard total <= maximumTextBytes else { throw FreewheelError.invalidInput("The recognized text exceeds the 32 MB limit.") }
            if !text.isEmpty { hasText = true }
            pages.append("--- Page \(index + 1) ---\n\n\(text)")
        }
        guard hasText else { throw FreewheelError.operationFailed("OCR did not recognize text in this PDF. The scan may be blank, low resolution, or use an unsupported language.") }
        return pages.joined(separator: "\n\n")
    }

    // MARK: - Local text documents

    private static func boundedTextData(_ input: URL) throws -> Data {
        let size = try input.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= maximumTextBytes else {
            throw FreewheelError.invalidInput("Text and SVG inputs must be between 1 byte and 32 MB.")
        }
        let data = try Data(contentsOf: input, options: .mappedIfSafe)
        guard data.count <= maximumTextBytes else { throw FreewheelError.invalidInput("The input grew beyond the 32 MB limit.") }
        return data
    }

    private static func readDocument(_ input: URL) throws -> NSAttributedString {
        let ext = input.pathExtension.lowercased()
        guard ["txt", "md", "markdown", "rtf", "html", "htm"].contains(ext) else {
            throw FreewheelError.unsupported("Office and document-package formats need LibreOffice or another optional document engine.")
        }
        let data = try boundedTextData(input)
        if ext == "rtf" {
            guard let attributed = NSAttributedString(rtf: data, documentAttributes: nil) else {
                throw FreewheelError.invalidInput("The RTF document could not be read.")
            }
            return attributed
        }
        let string: String
        if let utf8 = String(data: data, encoding: .utf8) { string = utf8 }
        else if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
                let utf16 = String(data: data, encoding: .utf16) { string = utf16 }
        else { throw FreewheelError.invalidInput("Save this text document as UTF-8 or UTF-16 before converting it.") }
        return NSAttributedString(string: ["html", "htm"].contains(ext) ? plainTextFromHTML(string) : string)
    }

    private static func plainTextFromHTML(_ html: String) -> String {
        // Deliberately no NSAttributedString HTML importer or WebKit: those can
        // fetch remote images/styles. This text-only importer never resolves URLs.
        var text = html.replacingOccurrences(of: #"(?is)<(script|style|head|template|noscript)\b[^>]*>.*?</\1\s*>"#,
                                            with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?is)<\s*(br\b[^>]*|/(p|div|li|h[1-6]|tr|section|article)\s*)>"#,
                                         with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?s)<[^>]*>"#, with: "", options: .regularExpression)
        let names = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
                     "copy": "©", "reg": "®", "hellip": "…", "mdash": "—", "ndash": "–", "bull": "•"]
        if let regex = try? NSRegularExpression(pattern: #"&(#x[0-9A-Fa-f]+|#[0-9]+|[A-Za-z][A-Za-z0-9]+);"#) {
            let original = text as NSString
            let mutable = NSMutableString(string: text)
            for match in regex.matches(in: text, range: NSRange(location: 0, length: original.length)).reversed() {
                let entity = original.substring(with: match.range(at: 1))
                var replacement = names[entity]
                if entity.hasPrefix("#x"), let value = UInt32(entity.dropFirst(2), radix: 16), let scalar = UnicodeScalar(value) {
                    replacement = String(scalar)
                } else if entity.hasPrefix("#"), let value = UInt32(entity.dropFirst()), let scalar = UnicodeScalar(value) {
                    replacement = String(scalar)
                }
                if let replacement = replacement { mutable.replaceCharacters(in: match.range, with: replacement) }
            }
            text = mutable as String
        }
        return text.replacingOccurrences(of: #"\n[ \t]*\n(?:[ \t]*\n)+"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func convertDocuments(_ inputs: [URL], operation: FileOperation,
                                         directory: URL) throws -> ConversionResult {
        guard operation.id.hasPrefix("convert."), let ext = outputExtension(operation),
              ["txt", "md", "rtf", "html", "pdf"].contains(ext) else {
            throw FreewheelError.unsupported("This document conversion needs an optional document engine.")
        }
        var outputs: [URL] = []
        for input in inputs {
            try Task.checkCancellation()
            let output = outputURL(input, suffix: "-converted", ext: ext, directory: directory)
            try writeDocument(readDocument(input), ext: ext, output: output)
            outputs.append(output)
        }
        return ConversionResult(outputs: outputs, note: "Native document conversion preserves text and basic RTF formatting. HTML is imported as text without loading external resources; Markdown syntax is preserved as text. Complex layout and embedded objects need a document engine.")
    }

    private static func writeDocument(_ attributed: NSAttributedString, ext: String, output: URL) throws {
        switch ext {
        case "txt", "md": try Data(attributed.string.utf8).write(to: output, options: .withoutOverwriting)
        case "rtf":
            let data = try attributed.data(from: NSRange(location: 0, length: attributed.length),
                                           documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
            try data.write(to: output, options: .withoutOverwriting)
        case "html":
            let escaped = attributed.string.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
            let html = "<!doctype html>\n<html><head><meta charset=\"utf-8\"><title>Converted document</title></head><body><pre>\(escaped)</pre></body></html>\n"
            try Data(html.utf8).write(to: output, options: .withoutOverwriting)
        case "pdf": try textToPDF(attributed, output: output)
        default: throw FreewheelError.unsupported("This document format needs an optional engine.")
        }
    }

    private static func textToPDF(_ attributed: NSAttributedString, output: URL) throws {
        let text = NSMutableAttributedString(attributedString: attributed)
        let fullRange = NSRange(location: 0, length: text.length)
        // Plain text has no font attributes. Core Text otherwise chooses a very
        // small default; apply a readable size without replacing RTF font runs.
        text.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            if value == nil { text.addAttribute(.font, value: NSFont.systemFont(ofSize: 12), range: range) }
        }
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let context = try pdfContext(output)
        defer { context.closePDF() }
        let pageSize = CGSize(width: 595.28, height: 841.89)
        let path = CGPath(rect: CGRect(x: 48, y: 48, width: pageSize.width - 96, height: pageSize.height - 96), transform: nil)
        var location = 0, pages = 0
        repeat {
            try Task.checkCancellation()
            pages += 1
            guard pages <= maximumPages else { throw FreewheelError.invalidInput("The document would exceed \(maximumPages) PDF pages.") }
            beginPDFPage(context, size: pageSize)
            context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(origin: .zero, size: pageSize))
            context.textMatrix = .identity
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
            CTFrameDraw(frame, context)
            context.endPDFPage()
            let visible = CTFrameGetVisibleStringRange(frame)
            if text.length > 0, visible.length == 0 {
                throw FreewheelError.operationFailed("The document has content that cannot fit on a PDF page.")
            }
            location += visible.length
        } while location < text.length
    }

    private static func countWords(_ inputs: [URL], options: ConversionOptions,
                                   directory: URL) throws -> ConversionResult {
        var reports: [String] = []
        for input in inputs {
            try Task.checkCancellation()
            let string = FileFamily.detect(input) == .pdf
                ? try extractedText(loadPDF(input, password: options.password)) : try readDocument(input).string
            var words = 0
            string.enumerateSubstrings(in: string.startIndex..<string.endIndex, options: .byWords) { _, _, _, _ in words += 1 }
            reports.append("\(input.lastPathComponent): \(words) words · \(string.count) characters · \(string.isEmpty ? 0 : string.components(separatedBy: .newlines).count) lines")
        }
        return ConversionResult(outputs: [], note: reports.joined(separator: "\n"))
    }

    // MARK: - AVFoundation fallback

    private static func convertMedia(_ inputs: [URL], operation: FileOperation,
                                     options: ConversionOptions, directory: URL) async throws -> ConversionResult {
        let tools: Set<String> = ["media.compress", "media.trim", "media.resize", "media.mute", "media.extractAudio"]
        guard operation.id.hasPrefix("convert.") || tools.contains(operation.id) else {
            throw FreewheelError.unsupported("This media operation needs FFmpeg.")
        }
        var outputs: [URL] = []
        for input in inputs {
            try Task.checkCancellation()
            let ext = outputExtension(operation) ?? (operation.id == "media.extractAudio" || FileFamily.detect(input) == .audio ? "m4a" : "mp4")
            guard ["mp4", "mov", "m4a", "wav", "aiff", "aif"].contains(ext) else {
                throw FreewheelError.unsupported("This media format needs FFmpeg.")
            }
            if ["media.resize", "media.mute"].contains(operation.id), !["mp4", "mov"].contains(ext) {
                throw FreewheelError.invalidInput("Resize and mute require a video output.")
            }
            let output = outputURL(input, suffix: "-converted", ext: ext, directory: directory)
            // A QuickTime container can refer to media outside its own file.
            // Restrict those references so a local conversion cannot fetch a
            // remote URL or silently read a second, unselected local file.
            let asset = AVURLAsset(url: input, options: [
                AVURLAssetReferenceRestrictionsKey: NSNumber(value: AVAssetReferenceRestrictions.forbidAll.rawValue),
                AVURLAssetShouldSupportAliasDataReferencesKey: false
            ])
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            guard seconds.isFinite, seconds > 0 else { throw FreewheelError.invalidInput("This media file has no playable duration.") }
            var range = CMTimeRange(start: .zero, duration: duration)
            if operation.id == "media.trim" {
                guard options.startSeconds.isFinite, options.endSeconds.isFinite,
                      options.startSeconds >= 0, options.startSeconds < seconds,
                      options.endSeconds > options.startSeconds else {
                    throw FreewheelError.invalidInput("Trim times must be within the media duration, with end after start.")
                }
                range = CMTimeRange(start: CMTime(seconds: options.startSeconds, preferredTimescale: 600),
                                    end: CMTime(seconds: min(seconds, options.endSeconds), preferredTimescale: 600))
            }
            if ["wav", "aiff", "aif"].contains(ext) {
                try await exportPCM(asset, range: range, ext: ext, output: output)
            } else {
                try await exportMedia(asset, range: range, ext: ext, operation: operation,
                                      options: options, output: output)
            }
            outputs.append(output)
        }
        return ConversionResult(outputs: outputs, note: "Converted locally with AVFoundation. Codec support depends on macOS; FFmpeg enables additional formats and media tools.")
    }

    private static func exportMedia(_ source: AVAsset, range: CMTimeRange, ext: String,
                                    operation: FileOperation, options: ConversionOptions, output: URL) async throws {
        var asset = source
        let sourceVideo = try await source.loadTracks(withMediaType: .video)
        let sourceAudio = try await source.loadTracks(withMediaType: .audio)
        if ext == "m4a", sourceAudio.isEmpty { throw FreewheelError.invalidInput("This file has no audio track to extract.") }
        if ["mp4", "mov"].contains(ext), sourceVideo.isEmpty { throw FreewheelError.invalidInput("This file has no video track. Choose an audio output.") }
        if operation.id == "media.mute" {
            let composition = AVMutableComposition()
            for sourceTrack in sourceVideo {
                guard let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                    throw FreewheelError.operationFailed("A video track could not be created.")
                }
                let duration = try await source.load(.duration)
                try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceTrack, at: .zero)
                track.preferredTransform = try await sourceTrack.load(.preferredTransform)
            }
            asset = composition
        }
        let preset = ext == "m4a" ? AVAssetExportPresetAppleM4A
            : operation.id == "media.compress" ? AVAssetExportPresetMediumQuality : AVAssetExportPresetHighestQuality
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw FreewheelError.unsupported("macOS cannot export this codec. Enable FFmpeg.")
        }
        let type: AVFileType = ext == "m4a" ? .m4a : ext == "mov" ? .mov : .mp4
        guard session.supportedFileTypes.contains(type) else { throw FreewheelError.unsupported("This media container needs FFmpeg.") }
        session.outputURL = output
        session.outputFileType = type
        session.timeRange = range
        session.shouldOptimizeForNetworkUse = false
        if options.removeMetadata { session.metadata = [] }
        if operation.id == "media.resize" {
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                throw FreewheelError.invalidInput("This file has no video track to resize.")
            }
            session.videoComposition = try await resizedVideoComposition(asset, track: track, longEdge: checkedLongEdge(options.maxDimension))
        }
        await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                session.exportAsynchronously { continuation.resume() }
            }
        }, onCancel: { session.cancelExport() })
        try Task.checkCancellation()
        guard session.status == .completed else {
            if session.status == .cancelled { throw FreewheelError.cancelled }
            throw FreewheelError.unsupported("AVFoundation could not export this media. Enable FFmpeg for this codec.")
        }
    }

    private static func resizedVideoComposition(_ asset: AVAsset, track: AVAssetTrack,
                                                longEdge: Int) async throws -> AVVideoComposition {
        let natural = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let bounds = CGRect(origin: .zero, size: natural).applying(transform).standardized
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else {
            throw FreewheelError.invalidInput("Video dimensions are invalid.")
        }
        let factor = min(1, CGFloat(longEdge) / max(bounds.width, bounds.height))
        let width = max(2, Int(floor(bounds.width * factor / 2)) * 2)
        let height = max(2, Int(floor(bounds.height * factor / 2)) * 2)
        try validateDimensions(width: width, height: height)
        let scale = min(CGFloat(width) / bounds.width, CGFloat(height) / bounds.height)
        let shift = CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY)
        let centered = CGAffineTransform(translationX: (CGFloat(width) - bounds.width * scale) / 2,
                                        y: (CGFloat(height) - bounds.height * scale) / 2)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(transform.concatenating(shift).concatenating(CGAffineTransform(scaleX: scale, y: scale)).concatenating(centered), at: .zero)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: try await asset.load(.duration))
        instruction.layerInstructions = [layer]
        let composition = AVMutableVideoComposition()
        composition.instructions = [instruction]
        composition.renderSize = CGSize(width: width, height: height)
        let frameRate = try await track.load(.nominalFrameRate)
        composition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(1, min(120, frameRate > 0 ? frameRate.rounded() : 30))))
        return composition
    }

    private static func exportPCM(_ asset: AVAsset, range: CMTimeRange, ext: String, output: URL) async throws {
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw FreewheelError.invalidInput("This file has no audio track to extract.")
        }
        let descriptions = try await track.load(.formatDescriptions)
        guard let format = descriptions.first, let description = CMAudioFormatDescriptionGetStreamBasicDescription(format) else {
            throw FreewheelError.unsupported("This audio codec needs FFmpeg.")
        }
        let channels = Int(description.pointee.mChannelsPerFrame), rate = description.pointee.mSampleRate
        guard (1...2).contains(channels), rate.isFinite, (8_000...192_000).contains(rate) else {
            throw FreewheelError.unsupported("Multichannel or unusual-rate audio needs FFmpeg.")
        }
        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate,
            AVNumberOfChannelsKey: channels, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false]
        let source = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        source.alwaysCopiesSampleData = false
        guard reader.canAdd(source) else { throw FreewheelError.unsupported("This audio stream needs FFmpeg.") }
        reader.add(source); reader.timeRange = range
        let writer = try AVAssetWriter(outputURL: output, fileType: ext == "wav" ? .wav : .aiff)
        var destinationSettings = settings
        destinationSettings[AVLinearPCMIsBigEndianKey] = ext != "wav"
        guard writer.canApply(outputSettings: destinationSettings, forMediaType: .audio) else {
            throw FreewheelError.unsupported("This PCM output is unavailable on this macOS version.")
        }
        let sink = AVAssetWriterInput(mediaType: .audio, outputSettings: destinationSettings)
        sink.expectsMediaDataInRealTime = false
        guard writer.canAdd(sink) else { throw FreewheelError.unsupported("The native audio writer cannot handle this format.") }
        writer.add(sink)
        guard writer.startWriting(), reader.startReading() else {
            reader.cancelReading(); writer.cancelWriting()
            throw FreewheelError.unsupported("macOS cannot read or write this audio stream. Enable FFmpeg.")
        }
        writer.startSession(atSourceTime: range.start)
        do {
            while reader.status == .reading {
                try Task.checkCancellation()
                guard writer.status == .writing else { throw FreewheelError.operationFailed("Audio writing failed.") }
                if sink.isReadyForMoreMediaData {
                    guard let sample = source.copyNextSampleBuffer() else { break }
                    guard sink.append(sample) else { throw FreewheelError.operationFailed("An audio sample could not be written.") }
                } else {
                    try await Task.sleep(nanoseconds: 5_000_000)
                }
            }
            guard reader.status == .completed else { throw FreewheelError.operationFailed("Audio decoding did not finish.") }
            sink.markAsFinished()
            await withTaskCancellationHandler(operation: {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    writer.finishWriting { continuation.resume() }
                }
            }, onCancel: { writer.cancelWriting() })
            try Task.checkCancellation()
            guard writer.status == .completed else { throw FreewheelError.operationFailed("Audio output could not be finalized.") }
        } catch {
            reader.cancelReading(); writer.cancelWriting(); throw error
        }
    }
}
#endif
