import Foundation

/// The menu describes implemented routes, not a marketing count of format pairs.
public enum Catalog {
    public static func operations(for inputs: [URL], mode: WheelMode) -> [FileOperation] {
        guard !inputs.isEmpty else { return [] }
        if mode == .actions { return actions }
        let families = Set(inputs.map(FileFamily.detect))
        guard families.count == 1, let family = families.first else {
            return mode == .tools ? archiveTools(for: inputs) : []
        }
        if mode == .tools {
            return tools(for: family, count: inputs.count).filter { $0.id != "archive.createGzip" || !containsDirectory(inputs) }.map { operation in
                var operation = operation
                if operation.id == "document.wordCount" {
                    if inputs.contains(where: { $0.pathExtension.lowercased() == "epub" }) { operation.dependency = "pandoc" }
                    else if inputs.contains(where: { ["doc", "docx", "odt", "pages"].contains($0.pathExtension.lowercased()) }) { operation.dependency = "libreoffice" }
                }
                return operation
            }
        }
        let extensions: [String]
        switch family {
        case .image: extensions = ["png", "jpg", "heic", "tiff", "webp", "avif", "bmp", "pdf"]
        case .audio: extensions = ["mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff"]
        case .video: extensions = ["mp4", "mov", "mkv", "webm", "gif", "mp3", "m4a"]
        case .pdf: extensions = ["png", "jpg", "txt", "md"]
        case .document: extensions = ["pdf", "docx", "odt", "rtf", "html", "txt", "md", "epub"]
        case .presentation: extensions = ["pdf", "pptx", "odp"]
        case .spreadsheet: extensions = ["xlsx", "ods", "csv", "tsv", "pdf"]
        case .subtitle: extensions = ["srt", "vtt", "txt"]
        case .archive: return [op("archive.extract", "Extract", "shippingbox", "Create a new folder; never overwrite existing files")] + archiveCreation
        case .folder, .other: return archiveTools(for: inputs)
        }
        return extensions.filter { ext in
            !inputs.allSatisfy { normalizedExtension($0.pathExtension) == ext }
        }.map { ext in
            let dependency = dependency(for: family, inputs: inputs, output: ext)
            let detail: String
            if family == .pdf && ["jpg", "png"].contains(ext) { detail = "Every page · 300 DPI" }
            else if family == .pdf { detail = "Extract selectable text" }
            else if family == .image && ext == "pdf" && inputs.count > 1 { detail = "Combine in the order shown" }
            else if ext == "epub" { detail = "Reflowable ebook" }
            else if ext == "docx" { detail = "Microsoft Word Document" }
            else if ext == "xlsx" { detail = "Microsoft Excel Workbook" }
            else if ext == "pptx" { detail = "Microsoft PowerPoint Presentation" }
            else { detail = dependency.map { "Local \($0) engine" } ?? "Built into macOS" }
            return FileOperation(id: "convert.\(ext)", title: ext.uppercased(), symbol: symbol(for: family, output: ext), outputExtension: ext, detail: detail, dependency: dependency)
        }
    }

    public static let actions: [FileOperation] = [
        op("action.airdrop", "AirDrop", "airplayaudio", "Share with nearby devices"),
        op("action.float", "Float", "rectangle.on.rectangle", "Keep files on a floating shelf"),
        op("action.copy", "Copy To…", "doc.on.doc", "Choose a destination folder"),
        op("action.move", "Move To…", "folder", "Choose a destination folder"),
        op("action.copyPath", "Copy Path", "link", "Copy absolute file paths"),
        op("action.terminal", "Terminal", "terminal", "Open the containing folder")
    ]

    public static let archiveCreation: [FileOperation] = [
        op("archive.createZip", "Create ZIP", "doc.zipper", "Compress the selection"),
        op("archive.createTar", "Create TAR", "shippingbox", "Bundle the selection"),
        op("archive.createGzip", "Create GZIP", "archivebox", "Compress each file separately")
    ]

    public static func tools(for family: FileFamily, count: Int) -> [FileOperation] {
        switch family {
        case .image:
            return [
                op("image.compress", "Compress", "arrow.down.right.and.arrow.up.left", "Adjust image quality"),
                op("image.resize", "Resize", "arrow.up.left.and.arrow.down.right", "Keep the original aspect ratio"),
                op("image.crop", "Crop", "crop", "Choose the area to keep"),
                op("image.rotate", "Rotate", "rotate.right", "Rotate in 90° steps"),
                op("image.flip", "Flip", "arrow.left.and.right.righttriangle.left.righttriangle.right", "Mirror horizontally"),
                op("image.stripMetadata", "Remove Metadata", "eye.slash", "Create a clean copy")
            ]
        case .pdf:
            var result = [
                op("pdf.split", "Split Pages", "square.split.2x2", "One new PDF per page"),
                op("pdf.extract", "Extract Pages", "doc.on.doc", "Choose page numbers and ranges"),
                op("pdf.rotate", "Rotate Pages", "rotate.right", "Rotate every page"),
                op("pdf.compress", "Compress", "arrow.down.right.and.arrow.up.left", "Flatten pages to reduce size"),
                op("pdf.ocr", "Recognize Text", "text.viewfinder", "Offline OCR for scanned pages")
            ]
            if count > 1 { result.insert(op("pdf.merge", "Merge PDFs", "doc.on.doc.fill", "Combine in the order shown"), at: 0) }
            return result
        case .video:
            #if os(macOS)
            let visualEdits = [
                op("media.trim", "Trim", "scissors", "Preview the range to keep"),
                op("media.crop", "Crop", "crop", "Choose the area to keep")
            ]
            #else
            let visualEdits = [op("media.trim", "Trim", "scissors", "Choose start and end time", "ffmpeg")]
            #endif
            return [
                op("media.compress", "Compress", "arrow.down.right.and.arrow.up.left", "H.264 · adjust quality", "ffmpeg")
            ] + visualEdits + [
                op("media.resize", "Resize", "arrow.up.left.and.arrow.down.right", "Fit within a maximum dimension", "ffmpeg"),
                op("media.mute", "Remove Audio", "speaker.slash", "Export a silent video", "ffmpeg"),
                op("media.extractAudio", "Extract Audio", "waveform", "Save the audio track", "ffmpeg"),
                op("media.speed", "Change Speed", "speedometer", "Change playback speed", "ffmpeg"),
                op("media.volume", "Adjust Volume", "speaker.wave.2", "Change audio volume", "ffmpeg")
            ]
        case .audio:
            #if os(macOS)
            let trim = op("media.trim", "Trim", "scissors", "See and hear the range to keep")
            #else
            let trim = op("media.trim", "Trim", "scissors", "Choose start and end time", "ffmpeg")
            #endif
            return [
                op("media.compress", "Compress", "arrow.down.right.and.arrow.up.left", "Reduce audio bitrate", "ffmpeg"),
                trim,
                op("media.speed", "Change Speed", "speedometer", "Change playback speed", "ffmpeg"),
                op("media.volume", "Adjust Volume", "speaker.wave.2", "Change audio volume", "ffmpeg")
            ]
        case .archive: return [op("archive.extract", "Extract", "shippingbox", "Extract into a new folder")] + archiveCreation
        case .document: return [op("document.wordCount", "Word Count", "text.word.spacing", "Count words locally")] + archiveCreation
        default: return archiveCreation
        }
    }

    private static func archiveTools(for inputs: [URL]) -> [FileOperation] {
        archiveCreation.filter { $0.id != "archive.createGzip" || !containsDirectory(inputs) }
    }

    private static func containsDirectory(_ inputs: [URL]) -> Bool {
        inputs.contains { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

    public static func normalizedExtension(_ value: String) -> String {
        switch value.lowercased() {
        case "jpeg": return "jpg"
        case "tif": return "tiff"
        case "aif": return "aiff"
        case "markdown": return "md"
        case "htm": return "html"
        default: return value.lowercased()
        }
    }

    private static func dependency(for family: FileFamily, inputs: [URL], output: String) -> String? {
        switch family {
        case .image: return ["webp", "avif"].contains(output) ? "imagemagick" : nil
        case .audio: return ["m4a", "wav", "aiff"].contains(output) ? nil : "ffmpeg"
        case .video: return ["mp4", "mov", "m4a"].contains(output) ? nil : "ffmpeg"
        case .presentation: return "libreoffice"
        case .spreadsheet:
            if inputs.allSatisfy({ ["csv", "tsv"].contains($0.pathExtension.lowercased()) }) && ["csv", "tsv"].contains(output) { return nil }
            return "libreoffice"
        case .document:
            if output == "epub" || inputs.contains(where: { $0.pathExtension.lowercased() == "epub" }) { return "pandoc" }
            if ["html", "docx", "odt"].contains(output) && inputs.contains(where: { ["md", "markdown"].contains($0.pathExtension.lowercased()) }) { return "pandoc" }
            if ["docx", "odt"].contains(output) || inputs.contains(where: { ["doc", "docx", "odt", "pages"].contains($0.pathExtension.lowercased()) }) { return "libreoffice" }
            return nil
        default: return nil
        }
    }

    private static func op(_ id: String, _ title: String, _ symbol: String, _ detail: String, _ dependency: String? = nil) -> FileOperation {
        FileOperation(id: id, title: title, symbol: symbol, detail: detail, dependency: dependency)
    }

    private static func symbol(for family: FileFamily, output: String) -> String {
        if output == "pdf" { return "doc.richtext" }
        if ["mp3", "m4a", "wav", "flac", "aiff", "opus", "ogg"].contains(output) { return "waveform" }
        switch family {
        case .image, .pdf: return ["txt", "md"].contains(output) ? "doc.text" : "photo"
        case .video: return "film"
        case .spreadsheet: return "tablecells"
        case .presentation: return "rectangle.on.rectangle"
        default: return "doc.text"
        }
    }
}
