import Foundation

/// Runs conversions in a private staging folder and publishes new files only after success.
/// Original files are never modified or removed.
public final class ConversionEngine: Sendable {
    public init() {}

    public func run(inputs: [URL], operation: FileOperation, options: ConversionOptions = .init()) async throws -> ConversionResult {
        do {
            try Task.checkCancellation()
            guard !inputs.isEmpty, inputs.count <= 1_000 else { throw FreewheelError.invalidInput("Select between 1 and 1,000 local files.") }
            try validateOptions(options, operation: operation)
            var seen = Set<String>()
            let validated = try inputs.map { input -> URL in
                guard input.isFileURL, !input.path.contains("\0") else { throw FreewheelError.invalidInput("Lemulip only converts files on this Mac. Download remote files first.") }
                let resolved = input.standardizedFileURL.resolvingSymlinksInPath()
                let values = try resolved.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isReadableKey])
                guard values.isRegularFile == true || values.isDirectory == true, values.isReadable != false else {
                    throw FreewheelError.invalidInput("An input is not a readable file or folder.")
                }
                guard seen.insert(resolved.path).inserted else { throw FreewheelError.invalidInput("The same input was selected more than once.") }
                return resolved
            }
            if options.imageCrop != nil {
                guard validated.count == 1, FileFamily.detect(validated[0]) == .image else {
                    throw FreewheelError.invalidInput("A selected crop requires exactly one still image.")
                }
            }
            let destination = (options.destinationDirectory ?? validated[0].deletingLastPathComponent()).standardizedFileURL.resolvingSymlinksInPath()
            guard destination.isFileURL else { throw FreewheelError.invalidInput("Choose a local output folder.") }
            if operation.id.hasPrefix("archive.create") {
                for input in validated {
                    let values = try input.resourceValues(forKeys: [.isDirectoryKey])
                    if values.isDirectory == true, destination.path == input.path || destination.path.hasPrefix(input.path + "/") {
                        throw FreewheelError.invalidInput("Choose an output folder outside the folders being archived.")
                    }
                }
            }
            let stage = try OutputStore.prepare(destination: destination)
            defer { try? FileManager.default.removeItem(at: stage) }
            let result = try await convert(validated, operation: operation, options: options, stage: stage)
            try Task.checkCancellation()
            guard !result.outputs.isEmpty || result.note != nil else { throw FreewheelError.operationFailed("The converter produced no output.") }
            return try OutputStore.publish(result, from: stage, to: destination)
        } catch is CancellationError { throw FreewheelError.cancelled }
    }

    private func convert(_ inputs: [URL], operation: FileOperation, options: ConversionOptions, stage: URL) async throws -> ConversionResult {
        let families = Set(inputs.map(FileFamily.detect))
        if operation.id.hasPrefix("archive.") { return try await ExternalConverters.archives(inputs, operation: operation, directory: stage) }
        if operation.id == "document.wordCount", inputs.allSatisfy({ ["txt", "md", "markdown", "csv", "tsv", "srt", "vtt"].contains($0.pathExtension.lowercased()) }) {
            let notes = try inputs.map { "\($0.lastPathComponent): \(TextCodec.wordCount(try TextCodec.read($0)))" }
            return ConversionResult(outputs: [], note: notes.joined(separator: "\n"))
        }
        let target = operation.outputExtension?.lowercased() ?? (operation.id.hasPrefix("convert.") ? String(operation.id.dropFirst(8)) : "")
        if operation.id.hasPrefix("convert."), !target.isEmpty,
           inputs.allSatisfy({ ["srt", "vtt"].contains($0.pathExtension.lowercased()) }), ["srt", "vtt", "txt"].contains(target) {
            return try textOutputs(inputs, target: target, directory: stage) { input in
                try TextCodec.convertSubtitles(TextCodec.read(input), from: input.pathExtension.lowercased(), to: target)
            }
        }
        if operation.id.hasPrefix("convert."), ["csv", "tsv"].contains(target), inputs.allSatisfy({ ["csv", "tsv"].contains($0.pathExtension.lowercased()) }) {
            return try textOutputs(inputs, target: target, directory: stage) { input in
                try TextCodec.convertDelimited(TextCodec.read(input), from: input.pathExtension.lowercased() == "csv" ? "," : "\t", to: target == "csv" ? "," : "\t")
            }
        }
        if operation.id.hasPrefix("media.") || (!families.isEmpty && families.isSubset(of: [.audio, .video])) {
            if EngineLocator.isAvailable("ffmpeg") { return try await ExternalConverters.media(inputs, operation: operation, options: options, directory: stage) }
            #if os(macOS)
            do { return try await NativeConverter.convert(inputs: inputs, operation: operation, options: options, outputDirectory: stage) }
            catch FreewheelError.unsupported { throw FreewheelError.missingDependency("FFmpeg") }
            #else
            throw FreewheelError.missingDependency("FFmpeg")
            #endif
        }
        if families == [.image] {
            if options.imageCrop != nil {
                // A centered external crop cannot reproduce an editor selection.
                #if os(macOS)
                return try await NativeConverter.convert(inputs: inputs, operation: operation, options: options, outputDirectory: stage)
                #else
                throw FreewheelError.unsupported("Selected image crops require the native macOS image engine.")
                #endif
            }
            #if os(macOS)
            do { return try await NativeConverter.convert(inputs: inputs, operation: operation, options: options, outputDirectory: stage) }
            catch FreewheelError.unsupported { /* Try an optional local image codec below. */ }
            #endif
            return try await ExternalConverters.image(inputs, operation: operation, options: options, directory: stage)
        }
        if families.contains(.presentation) || families.contains(.spreadsheet) {
            guard operation.id.hasPrefix("convert.") else { throw FreewheelError.unsupported("This spreadsheet or presentation tool is not available.") }
            return try await ExternalConverters.office(inputs, operation: operation, directory: stage)
        }
        let hasEPUB = inputs.contains { $0.pathExtension.lowercased() == "epub" }
        let hasMarkdown = inputs.contains { ["md", "markdown"].contains($0.pathExtension.lowercased()) }
        if operation.id.hasPrefix("convert."), target == "epub" || hasEPUB || hasMarkdown && ["html", "docx", "odt"].contains(target) {
            return try await pandocDocuments(inputs, target: target, options: options, stage: stage)
        }
        #if os(macOS)
        do { return try await NativeConverter.convert(inputs: inputs, operation: operation, options: options, outputDirectory: stage) }
        catch FreewheelError.unsupported { /* A document engine may support the remaining formats. */ }
        #endif
        if operation.id == "document.wordCount", families.isSubset(of: [.document]) {
            let textOperation = FileOperation(id: "convert.txt", title: "Text", outputExtension: "txt")
            let text = hasEPUB ? try await ExternalConverters.document(inputs, operation: textOperation, directory: stage) : try await ExternalConverters.office(inputs, operation: textOperation, directory: stage)
            let notes = try zip(inputs, text.outputs).map { input, output in "\(input.lastPathComponent): \(TextCodec.wordCount(try TextCodec.read(output)))" }
            return ConversionResult(outputs: [], note: notes.joined(separator: "\n"))
        }
        if operation.id.hasPrefix("convert."), families.isSubset(of: [.document, .pdf]) {
            if ["md", "markdown"].contains(target) {
                let textOperation = FileOperation(id: "convert.txt", title: "Text", outputExtension: "txt")
                let temporary = try await ExternalConverters.office(inputs, operation: textOperation, directory: stage)
                var outputs: [URL] = []
                for (input, text) in zip(inputs, temporary.outputs) {
                    let output = OutputStore.uniqueURL(in: stage, stem: input.deletingPathExtension().lastPathComponent, extension: target)
                    try FileManager.default.moveItem(at: text, to: output); outputs.append(output)
                }
                return ConversionResult(outputs: outputs, note: "Exported as plain text in a Markdown file. Office layout and styling are not converted into Markdown syntax.")
            }
            return try await ExternalConverters.office(inputs, operation: operation, directory: stage)
        }
        throw FreewheelError.unsupported("This combination of files and operation is not supported by the available local engines.")
    }

    private func pandocDocuments(_ inputs: [URL], target: String, options: ConversionOptions, stage: URL) async throws -> ConversionResult {
        var outputs: [URL] = []
        var notes = Set<String>()
        for original in inputs {
            try Task.checkCancellation()
            let job = stage.appendingPathComponent(".document-\(UUID().uuidString)", isDirectory: true)
            let preparation = job.appendingPathComponent("preparation", isDirectory: true)
            let converted = job.appendingPathComponent("converted", isDirectory: true)
            try FileManager.default.createDirectory(at: preparation, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.createDirectory(at: converted, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: job) }
            var input = original
            if !["md", "markdown", "txt", "html", "htm", "epub", "docx", "odt"].contains(original.pathExtension.lowercased()) {
                let textOperation = FileOperation(id: "convert.txt", title: "Text", outputExtension: "txt")
                var prepared: ConversionResult?
                #if os(macOS)
                do { prepared = try await NativeConverter.convert(inputs: [original], operation: textOperation, options: options, outputDirectory: preparation) }
                catch FreewheelError.unsupported { /* Try the office engine below. */ }
                #endif
                if prepared == nil { prepared = try await ExternalConverters.office([original], operation: textOperation, directory: preparation) }
                guard let file = prepared?.outputs.first else { throw FreewheelError.operationFailed("Could not prepare the document for ebook conversion.") }
                input = file
                notes.insert("This source format was imported as text; complex styling and embedded objects are not preserved.")
            }
            let intermediateTarget = target == "pdf" ? "txt" : target
            let operation = FileOperation(id: "convert.\(intermediateTarget)", title: intermediateTarget.uppercased(), outputExtension: intermediateTarget)
            let result = try await ExternalConverters.document([input], operation: operation, directory: converted)
            guard var file = result.outputs.first else { throw FreewheelError.operationFailed("The document converter produced no output.") }
            if target == "pdf" {
                let finalDirectory = job.appendingPathComponent("pdf", isDirectory: true)
                try FileManager.default.createDirectory(at: finalDirectory, withIntermediateDirectories: false)
                let pdfOperation = FileOperation(id: "convert.pdf", title: "PDF", outputExtension: "pdf")
                #if os(macOS)
                let pdf = try await NativeConverter.convert(inputs: [file], operation: pdfOperation, options: options, outputDirectory: finalDirectory)
                #else
                let pdf = try await ExternalConverters.office([file], operation: pdfOperation, directory: finalDirectory)
                #endif
                guard let rendered = pdf.outputs.first else { throw FreewheelError.operationFailed("Could not render document text as PDF.") }
                file = rendered
                notes.insert("Ebook PDF export preserves text; ebook styling and embedded images are not reproduced.")
            }
            let output = OutputStore.uniqueURL(in: stage, stem: original.deletingPathExtension().lastPathComponent, extension: target)
            try FileManager.default.moveItem(at: file, to: output); outputs.append(output)
        }
        notes.insert("Linked external resources are not loaded. Check formatting after document conversion.")
        return ConversionResult(outputs: outputs, note: notes.sorted().joined(separator: " "))
    }

    private func textOutputs(_ inputs: [URL], target: String, directory: URL, transform: (URL) throws -> String) throws -> ConversionResult {
        var outputs: [URL] = []
        for input in inputs {
            try Task.checkCancellation()
            let output = OutputStore.uniqueURL(in: directory, stem: input.deletingPathExtension().lastPathComponent, extension: target)
            try transform(input).write(to: output, atomically: true, encoding: .utf8); outputs.append(output)
        }
        return ConversionResult(outputs: outputs)
    }

    private func validateOptions(_ options: ConversionOptions, operation: FileOperation) throws {
        if let crop = options.imageCrop {
            guard operation.id == "image.crop" else {
                throw FreewheelError.invalidInput("An image selection can only be used with Crop Image.")
            }
            try crop.validateBounds()
            guard crop.sourceWidth <= 16_384, crop.sourceHeight <= 16_384,
                  crop.sourceWidth <= 40_000_000 / crop.sourceHeight else {
                throw FreewheelError.invalidInput("Visual cropping supports original images up to 16,384 pixels per edge and 40 megapixels.")
            }
        }
        if let ext = operation.outputExtension {
            guard !ext.isEmpty, ext.count <= 12, ext.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
                throw FreewheelError.invalidInput("The requested output extension is invalid.")
            }
        }
        guard operation.id.count <= 80, operation.id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == ".") }) else {
            throw FreewheelError.invalidInput("The requested operation is invalid.")
        }
        guard options.quality.isFinite, (0.05...1).contains(options.quality),
              (1...16_384).contains(options.maxDimension), (1...16_384).contains(options.width), (1...16_384).contains(options.height),
              (1...60).contains(options.framesPerSecond) else { throw FreewheelError.invalidInput("Choose valid image dimensions, frame rate, and a quality between 5% and 100%.") }
        if operation.id == "media.trim" {
            guard options.startSeconds.isFinite, options.endSeconds.isFinite, options.startSeconds >= 0, options.endSeconds > options.startSeconds else {
                throw FreewheelError.invalidInput("The trim end must be later than the start, and neither can be negative.")
            }
        }
        if operation.id == "media.speed" {
            guard options.speedMultiplier.isFinite, (0.25...4).contains(options.speedMultiplier) else { throw FreewheelError.invalidInput("Choose a speed between 0.25× and 4×.") }
        }
        if operation.id == "media.volume" {
            guard options.volumeMultiplier.isFinite, (0...5).contains(options.volumeMultiplier) else { throw FreewheelError.invalidInput("Choose a volume between 0% and 500%.") }
        }
    }
}
