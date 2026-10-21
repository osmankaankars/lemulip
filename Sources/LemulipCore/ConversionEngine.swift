import Foundation

/// Runs conversions in a private staging folder and publishes new files only after success.
/// Original files are never modified or removed.
public final class ConversionEngine: Sendable {
    public init() {}

    public func run(inputs: [URL], operation: FileOperation, options: ConversionOptions = .init()) async throws -> ConversionResult {
        do {
            try Task.checkCancellation()
            guard !inputs.isEmpty, inputs.count <= 1_000 else { throw LemulipError.invalidInput("Select between 1 and 1,000 local files.") }
            var options = options
            if let selection = options.audioTrim {
                options.startSeconds = selection.startSeconds
                options.endSeconds = selection.endSeconds
            }
            if let selection = options.videoTrim {
                options.startSeconds = selection.startSeconds
                options.endSeconds = selection.endSeconds
            }
            try validateOptions(options, operation: operation)
            try options.pdfMerge?.validate(sourceInputCount: inputs.count)
            let retainedPDFInputs = options.pdfMerge.map { Set($0.sources.map(\.inputIndex)) }
            var seen = Set<String>()
            let validated = try inputs.enumerated().map { index, input -> URL in
                guard input.isFileURL, !input.path.contains("\0") else { throw LemulipError.invalidInput("Lemulip only converts files on this Mac. Download remote files first.") }
                let resolved = input.standardizedFileURL.resolvingSymlinksInPath()
                // A removed merge input keeps its index but need not still be
                // present. Only retained PDFs participate in the new output.
                if retainedPDFInputs?.contains(index) ?? true {
                    let values: URLResourceValues
                    do { values = try resolved.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isReadableKey]) }
                    catch {
                        if retainedPDFInputs != nil {
                            throw LemulipError.invalidInput("\(input.lastPathComponent) is no longer a readable local PDF. Reopen Merge PDF after checking the file.")
                        }
                        throw error
                    }
                    guard values.isRegularFile == true || values.isDirectory == true, values.isReadable != false else {
                        throw LemulipError.invalidInput("An input is not a readable file or folder.")
                    }
                    guard seen.insert(resolved.path).inserted else { throw LemulipError.invalidInput("The same input was selected more than once.") }
                }
                return resolved
            }
            if options.imageCrop != nil {
                guard validated.count == 1, FileFamily.detect(validated[0]) == .image else {
                    throw LemulipError.invalidInput("A selected crop requires exactly one still image.")
                }
            }
            if options.audioTrim != nil {
                guard validated.count == 1, FileFamily.detect(validated[0]) == .audio else {
                    throw LemulipError.invalidInput("A waveform selection requires exactly one audio file.")
                }
            }
            if options.videoTrim != nil {
                guard validated.count == 1, FileFamily.detect(validated[0]) == .video else {
                    throw LemulipError.invalidInput("A timeline selection requires exactly one video file.")
                }
            }
            if options.videoCrop != nil {
                guard validated.count == 1, FileFamily.detect(validated[0]) == .video else {
                    throw LemulipError.invalidInput("A selected video crop requires exactly one video file.")
                }
            }
            if options.pdfOrganization != nil {
                guard validated.count == 1, FileFamily.detect(validated[0]) == .pdf else {
                    throw LemulipError.invalidInput("Organize PDF requires exactly one PDF file.")
                }
            }
            if let plan = options.pdfMerge {
                guard plan.sources.allSatisfy({ FileFamily.detect(validated[$0.inputIndex]) == .pdf }) else {
                    throw LemulipError.invalidInput("The merge preview requires PDF files.")
                }
            }
            let firstOutputInput = options.pdfMerge?.sources.first?.inputIndex ?? 0
            let destination = (options.destinationDirectory ?? validated[firstOutputInput].deletingLastPathComponent()).standardizedFileURL.resolvingSymlinksInPath()
            guard destination.isFileURL else { throw LemulipError.invalidInput("Choose a local output folder.") }
            if operation.id.hasPrefix("archive.create") {
                for input in validated {
                    let values = try input.resourceValues(forKeys: [.isDirectoryKey])
                    if values.isDirectory == true, destination.path == input.path || destination.path.hasPrefix(input.path + "/") {
                        throw LemulipError.invalidInput("Choose an output folder outside the folders being archived.")
                    }
                }
            }
            let stage = try OutputStore.prepare(destination: destination)
            defer { try? FileManager.default.removeItem(at: stage) }
            let result = try await convert(validated, operation: operation, options: options, stage: stage)
            try Task.checkCancellation()
            guard !result.outputs.isEmpty || result.note != nil else { throw LemulipError.operationFailed("The converter produced no output.") }
            return try OutputStore.publish(result, from: stage, to: destination)
        } catch is CancellationError { throw LemulipError.cancelled }
    }

    private func convert(_ inputs: [URL], operation: FileOperation, options: ConversionOptions, stage: URL) async throws -> ConversionResult {
        let families = Set(inputs.map(FileFamily.detect))
        if options.pdfMerge != nil {
            // Generic or external merges cannot replace a preview-bound plan:
            // they would lose the chosen order or reintroduce removed files.
            #if os(macOS)
            return try await NativeConverter.convert(inputs: inputs, operation: operation,
                                                      options: options, outputDirectory: stage)
            #else
            throw LemulipError.unsupported("PDF merge previews require the native macOS editor. The command-line tool can merge PDFs in their input order.")
            #endif
        }
        if options.pdfOrganization != nil {
            // An ordered page plan must never fall through to a converter that
            // would discard page order, omissions, or rotation deltas.
            #if os(macOS)
            return try await NativeConverter.convert(inputs: inputs, operation: operation,
                                                      options: options, outputDirectory: stage)
            #else
            throw LemulipError.unsupported("Page organization requires the native macOS PDF editor.")
            #endif
        }
        if options.videoCrop != nil {
            #if os(macOS)
            return try await NativeConverter.convert(inputs: inputs, operation: operation,
                                                      options: options, outputDirectory: stage)
            #else
            throw LemulipError.unsupported("Selected video crops require the native macOS video editor.")
            #endif
        }
        if options.videoTrim != nil {
            // The editor's source-bound selection must never fall through to
            // a general conversion or an external route with different timing.
            #if os(macOS)
            return try await NativeConverter.convert(inputs: inputs, operation: operation,
                                                      options: options, outputDirectory: stage)
            #else
            throw LemulipError.unsupported("Video timeline selections require the native macOS editor. The command-line tool accepts start and end times with FFmpeg.")
            #endif
        }
        if let selection = options.audioTrim {
            #if os(macOS)
            let ext = operation.outputExtension?.lowercased() ?? "m4a"
            try await NativeConverter.validateAudioTrimExport(for: inputs[0], selection: selection,
                                                              outputExtension: ext)
            if ["m4a", "wav", "aiff", "aif"].contains(ext) {
                do {
                    return try await NativeConverter.convert(inputs: inputs, operation: operation,
                                                              options: options, outputDirectory: stage)
                } catch LemulipError.unsupported {
                    // Both engines receive the exact selected range. The native
                    // converter removes its partial output before this retry.
                }
            }
            guard EngineLocator.isAvailable("ffmpeg") else { throw LemulipError.missingDependency("FFmpeg") }
            var export = operation
            export.outputExtension = ext
            let result = try await ExternalConverters.media(inputs, operation: export, options: options, directory: stage)
            return ConversionResult(outputs: result.outputs,
                note: "The selected audio was re-encoded locally with FFmpeg. Compressed formats may include codec-frame padding; original files were kept.")
            #else
            throw LemulipError.unsupported("Waveform selections require the native macOS audio editor. The command-line tool accepts start and end times with FFmpeg.")
            #endif
        }
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
        if operation.id.hasPrefix("convert."), target == "xlsx",
           inputs.allSatisfy({ ["csv", "tsv"].contains($0.pathExtension.lowercased()) }) {
            // CSV and TSV have no type schema. Keep the same literal text
            // semantics even when an optional spreadsheet engine is installed.
            return try await SpreadsheetWriter.convert(inputs: inputs, directory: stage)
        }
        if operation.id.hasPrefix("media.") || (!families.isEmpty && families.isSubset(of: [.audio, .video])) {
            if EngineLocator.isAvailable("ffmpeg") { return try await ExternalConverters.media(inputs, operation: operation, options: options, directory: stage) }
            #if os(macOS)
            do { return try await NativeConverter.convert(inputs: inputs, operation: operation, options: options, outputDirectory: stage) }
            catch LemulipError.unsupported { throw LemulipError.missingDependency("FFmpeg") }
            #else
            throw LemulipError.missingDependency("FFmpeg")
            #endif
        }
        if families == [.image] {
            if options.imageCrop != nil {
                // A centered external crop cannot reproduce an editor selection.
                #if os(macOS)
                return try await NativeConverter.convert(inputs: inputs, operation: operation, options: options, outputDirectory: stage)
                #else
                throw LemulipError.unsupported("Selected image crops require the native macOS image engine.")
                #endif
            }
            #if os(macOS)
            do { return try await NativeConverter.convert(inputs: inputs, operation: operation, options: options, outputDirectory: stage) }
            catch LemulipError.unsupported { /* Try an optional local image codec below. */ }
            #endif
            return try await ExternalConverters.image(inputs, operation: operation, options: options, directory: stage)
        }
        if families.contains(.presentation) || families.contains(.spreadsheet) {
            guard operation.id.hasPrefix("convert.") else { throw LemulipError.unsupported("This spreadsheet or presentation tool is not available.") }
            return try await ExternalConverters.office(inputs, operation: operation, directory: stage)
        }
        let hasEPUB = inputs.contains { $0.pathExtension.lowercased() == "epub" }
        let hasMarkdown = inputs.contains { ["md", "markdown"].contains($0.pathExtension.lowercased()) }
        if operation.id.hasPrefix("convert."), target == "docx",
           inputs.allSatisfy({ ["md", "markdown"].contains($0.pathExtension.lowercased()) }) {
            // Choose one route for the entire batch before any native output is
            // written. Invalid input and later conversion failures must not retry
            // through an engine with different Markdown interpretation.
            do { try MarkdownWordWriter.preflight(inputs) }
            catch LemulipError.unsupported(let reason) {
                guard EngineLocator.isAvailable("pandoc") else {
                    throw LemulipError.unsupported("\(reason) \(LemulipError.missingDependency("Pandoc").localizedDescription)")
                }
                let result = try await pandocDocuments(inputs, target: target, options: options, stage: stage,
                                                      prepareMarkdownUTF8: true)
                return ConversionResult(outputs: result.outputs,
                    note: "Converted locally with Pandoc to preserve Markdown features outside the built-in Word exporter. " + (result.note ?? ""))
            }
            return try await MarkdownWordWriter.convert(inputs: inputs, directory: stage)
        }
        if operation.id.hasPrefix("convert."), target == "epub" || hasEPUB || hasMarkdown && ["html", "docx", "odt"].contains(target) {
            return try await pandocDocuments(inputs, target: target, options: options, stage: stage)
        }
        #if os(macOS)
        do { return try await NativeConverter.convert(inputs: inputs, operation: operation, options: options, outputDirectory: stage) }
        catch LemulipError.unsupported { /* A document engine may support the remaining formats. */ }
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
        throw LemulipError.unsupported("This combination of files and operation is not supported by the available local engines.")
    }

    private func pandocDocuments(_ inputs: [URL], target: String, options: ConversionOptions, stage: URL,
                                 prepareMarkdownUTF8: Bool = false) async throws -> ConversionResult {
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
            if prepareMarkdownUTF8 {
                // The native Markdown preflight accepts BOM UTF-16 as well as
                // UTF-8. Pandoc otherwise guesses Latin-1 for these files and
                // can report success after corrupting their text. Give this
                // whole-batch fallback a validated private UTF-8 copy instead.
                input = preparation.appendingPathComponent(original.lastPathComponent)
                try MarkdownWordWriter.validatedUTF8(original).write(to: input, options: .withoutOverwriting)
            } else if !["md", "markdown", "txt", "html", "htm", "epub", "docx", "odt"].contains(original.pathExtension.lowercased()) {
                let textOperation = FileOperation(id: "convert.txt", title: "Text", outputExtension: "txt")
                var prepared: ConversionResult?
                #if os(macOS)
                do { prepared = try await NativeConverter.convert(inputs: [original], operation: textOperation, options: options, outputDirectory: preparation) }
                catch LemulipError.unsupported { /* Try the office engine below. */ }
                #endif
                if prepared == nil { prepared = try await ExternalConverters.office([original], operation: textOperation, directory: preparation) }
                guard let file = prepared?.outputs.first else { throw LemulipError.operationFailed("Could not prepare the document for ebook conversion.") }
                input = file
                notes.insert("This source format was imported as text; complex styling and embedded objects are not preserved.")
            }
            let intermediateTarget = target == "pdf" ? "txt" : target
            let operation = FileOperation(id: "convert.\(intermediateTarget)", title: intermediateTarget.uppercased(), outputExtension: intermediateTarget)
            let result = try await ExternalConverters.document([input], operation: operation, directory: converted)
            guard var file = result.outputs.first else { throw LemulipError.operationFailed("The document converter produced no output.") }
            if target == "pdf" {
                let finalDirectory = job.appendingPathComponent("pdf", isDirectory: true)
                try FileManager.default.createDirectory(at: finalDirectory, withIntermediateDirectories: false)
                let pdfOperation = FileOperation(id: "convert.pdf", title: "PDF", outputExtension: "pdf")
                #if os(macOS)
                let pdf = try await NativeConverter.convert(inputs: [file], operation: pdfOperation, options: options, outputDirectory: finalDirectory)
                #else
                let pdf = try await ExternalConverters.office([file], operation: pdfOperation, directory: finalDirectory)
                #endif
                guard let rendered = pdf.outputs.first else { throw LemulipError.operationFailed("Could not render document text as PDF.") }
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
        if let plan = options.pdfMerge {
            guard operation.id == "pdf.merge", options.pdfOrganization == nil,
                  options.imageCrop == nil, options.audioTrim == nil,
                  options.videoTrim == nil, options.videoCrop == nil else {
                throw LemulipError.invalidInput("A PDF merge plan can only be used with Merge PDF, without another editor selection.")
            }
            try plan.validate()
            if let ext = operation.outputExtension?.lowercased(), ext != "pdf" {
                throw LemulipError.invalidInput("Choose PDF output for the merge preview.")
            }
        }
        if operation.id == "pdf.organize", options.pdfOrganization == nil {
            throw LemulipError.invalidInput("Choose pages in Organize PDF before exporting.")
        }
        if let plan = options.pdfOrganization {
            guard operation.id == "pdf.organize", options.imageCrop == nil,
                  options.audioTrim == nil, options.videoTrim == nil, options.videoCrop == nil else {
                throw LemulipError.invalidInput("A PDF page plan can only be used with Organize PDF, without another editor selection.")
            }
            try plan.validate()
            if let ext = operation.outputExtension?.lowercased(), ext != "pdf" {
                throw LemulipError.invalidInput("Choose PDF output for the organized pages.")
            }
        }
        if operation.id == "media.crop", options.videoCrop == nil {
            throw LemulipError.invalidInput("Choose a crop in the video editor before exporting.")
        }
        if let selection = options.audioTrim {
            guard operation.id == "media.trim", options.imageCrop == nil, options.videoTrim == nil, options.videoCrop == nil else {
                throw LemulipError.invalidInput("An audio selection can only be used with Trim Audio.")
            }
            try selection.validate()
            if let ext = operation.outputExtension?.lowercased(), !ExternalConverters.audioExtensions.contains(ext) {
                throw LemulipError.invalidInput("Choose an audio output for the selected range.")
            }
        }
        if let selection = options.videoTrim {
            guard operation.id == "media.trim", options.imageCrop == nil, options.audioTrim == nil, options.videoCrop == nil else {
                throw LemulipError.invalidInput("A video selection can only be used with Trim Video.")
            }
            try selection.validate()
            if let ext = operation.outputExtension?.lowercased(), !["mp4", "mov"].contains(ext) {
                throw LemulipError.invalidInput("Choose MP4 or MOV for the selected video range.")
            }
        }
        if let crop = options.videoCrop {
            guard operation.id == "media.crop", options.imageCrop == nil,
                  options.audioTrim == nil, options.videoTrim == nil else {
                throw LemulipError.invalidInput("A video crop can only be used with Crop Video, without a separate trim or image selection.")
            }
            try crop.validate()
            if let ext = operation.outputExtension?.lowercased(), !["mp4", "mov"].contains(ext) {
                throw LemulipError.invalidInput("Choose MP4 or MOV for the selected video crop.")
            }
        }
        if let crop = options.imageCrop {
            guard operation.id == "image.crop" else {
                throw LemulipError.invalidInput("An image selection can only be used with Crop Image.")
            }
            try crop.validateBounds()
            guard crop.sourceWidth <= 16_384, crop.sourceHeight <= 16_384,
                  crop.sourceWidth <= 40_000_000 / crop.sourceHeight else {
                throw LemulipError.invalidInput("Visual cropping supports original images up to 16,384 pixels per edge and 40 megapixels.")
            }
        }
        if let ext = operation.outputExtension {
            guard !ext.isEmpty, ext.count <= 12, ext.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
                throw LemulipError.invalidInput("The requested output extension is invalid.")
            }
        }
        guard operation.id.count <= 80, operation.id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == ".") }) else {
            throw LemulipError.invalidInput("The requested operation is invalid.")
        }
        guard options.quality.isFinite, (0.05...1).contains(options.quality),
              (1...16_384).contains(options.maxDimension), (1...16_384).contains(options.width), (1...16_384).contains(options.height),
              (1...60).contains(options.framesPerSecond) else { throw LemulipError.invalidInput("Choose valid image dimensions, frame rate, and a quality between 5% and 100%.") }
        if operation.id == "media.trim" {
            guard options.startSeconds.isFinite, options.endSeconds.isFinite, options.startSeconds >= 0, options.endSeconds > options.startSeconds else {
                throw LemulipError.invalidInput("The trim end must be later than the start, and neither can be negative.")
            }
        }
        if operation.id == "media.speed" {
            guard options.speedMultiplier.isFinite, (0.25...4).contains(options.speedMultiplier) else { throw LemulipError.invalidInput("Choose a speed between 0.25× and 4×.") }
        }
        if operation.id == "media.volume" {
            guard options.volumeMultiplier.isFinite, (0...5).contains(options.volumeMultiplier) else { throw LemulipError.invalidInput("Choose a volume between 0% and 500%.") }
        }
    }
}
