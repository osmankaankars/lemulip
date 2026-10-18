import Foundation

public enum FileFamily: String, Codable, CaseIterable, Sendable {
    case image, audio, video, pdf, document, presentation, spreadsheet, subtitle, archive, folder, other

    public var title: String { rawValue.capitalized }

    public static func detect(_ url: URL) -> FileFamily {
        var directory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue {
            if ["pages", "key", "numbers", "rtfd"].contains(url.pathExtension.lowercased()) {
                return url.pathExtension.lowercased() == "key" ? .presentation : url.pathExtension.lowercased() == "numbers" ? .spreadsheet : .document
            }
            return .folder
        }
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "webp", "heic", "heif", "tif", "tiff", "avif", "bmp", "svg", "gif", "ico": return .image
        case "mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff", "aif", "wma", "aac": return .audio
        case "mp4", "mov", "mkv", "webm", "avi", "wmv", "m4v": return .video
        case "pdf": return .pdf
        case "doc", "docx", "pages", "md", "markdown", "txt", "rtf", "rtfd", "html", "htm", "epub", "odt", "textclipping": return .document
        case "ppt", "pptx", "odp", "key": return .presentation
        case "xls", "xlsx", "ods", "csv", "tsv", "numbers": return .spreadsheet
        case "srt", "vtt": return .subtitle
        case "zip", "tar", "gz", "tgz", "bz2", "xz", "rar", "7z": return .archive
        default: return .other
        }
    }
}

public enum WheelMode: String, CaseIterable, Sendable {
    case convert, tools, actions
    public var title: String { rawValue.capitalized }
    public var symbol: String { self == .convert ? "arrow.triangle.2.circlepath" : self == .tools ? "slider.horizontal.3" : "folder" }
    public var keySymbol: String { self == .convert ? "⇧" : self == .tools ? "⌘" : "⌃" }
}

public struct FileOperation: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var symbol: String
    public var outputExtension: String?
    public var detail: String
    public var dependency: String?
    public init(id: String, title: String, symbol: String = "arrow.triangle.2.circlepath", outputExtension: String? = nil, detail: String = "", dependency: String? = nil) {
        self.id = id; self.title = title; self.symbol = symbol; self.outputExtension = outputExtension; self.detail = detail; self.dependency = dependency
    }
}

/// Integer pixels measured from the top-left of the original image after its
/// EXIF orientation is applied. The source dimensions bind a selection to the
/// full-size raster, independently of the editor's smaller preview.
public struct ImageCropRegion: Equatable, Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int
    public var sourceWidth: Int
    public var sourceHeight: Int

    public init(x: Int, y: Int, width: Int, height: Int, sourceWidth: Int, sourceHeight: Int) {
        self.x = x; self.y = y; self.width = width; self.height = height
        self.sourceWidth = sourceWidth; self.sourceHeight = sourceHeight
    }

    func validateBounds() throws {
        // Subtract only after checking sizes. Adding x + width (or y + height)
        // could overflow for invalid values supplied by another caller.
        guard sourceWidth > 0, sourceHeight > 0, width > 0, height > 0,
              x >= 0, y >= 0, width <= sourceWidth, height <= sourceHeight,
              x <= sourceWidth - width, y <= sourceHeight - height else {
            throw FreewheelError.invalidInput("Choose a crop with positive dimensions entirely inside the image.")
        }
    }
}

public struct ConversionOptions: Sendable {
    public var quality: Double = 0.82
    public var maxDimension: Int = 1920
    public var width: Int = 1200
    public var height: Int = 1200
    /// Nil keeps the command-line tool's centered width/height crop.
    public var imageCrop: ImageCropRegion? = nil
    /// The visual audio editor binds its range to one recording's duration.
    /// Nil keeps the command-line tool's independent start/end options.
    public var audioTrim: AudioTrimSelection? = nil
    /// A selected video range always uses the native MP4/MOV export path.
    public var videoTrim: VideoTrimSelection? = nil
    /// A full-duration spatial crop in the upright video's source pixels.
    public var videoCrop: VideoCropRegion? = nil
    public var startSeconds: Double = 0
    public var endSeconds: Double = 30
    public var rotationDegrees: Int = 90
    public var framesPerSecond: Int = 15
    public var speedMultiplier: Double = 2
    public var volumeMultiplier: Double = 1.5
    public var pageRange: String = "1"
    public var password: String = ""
    public var destinationDirectory: URL?
    public var removeMetadata: Bool = true
    public init() {}
}

public struct ConversionResult: Sendable {
    public let outputs: [URL]
    public let note: String?
    public init(outputs: [URL], note: String? = nil) { self.outputs = outputs; self.note = note }
}

public enum FreewheelError: LocalizedError {
    case unsupported(String), missingDependency(String), invalidInput(String), operationFailed(String), cancelled
    public var errorDescription: String? {
        switch self {
        case .unsupported(let message), .invalidInput(let message), .operationFailed(let message): return message
        case .missingDependency(let name): return "Install \(name) to enable this operation. Open Settings → Engines for instructions."
        case .cancelled: return "Operation cancelled."
        }
    }
}
