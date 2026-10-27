import Foundation
import CLemulipArchive
#if os(macOS)
import Darwin
import CryptoKit
#else
import Glibc
#endif

enum ExternalConverters {
    static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "ogg", "opus", "wma"]
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "mkv", "webm", "avi", "wmv", "gif"]
    static let officeExtensions: Set<String> = ["doc", "docx", "odt", "rtf", "ppt", "pptx", "odp", "xls", "xlsx", "ods", "csv", "tsv", "pdf", "html", "txt"]

    static func media(_ inputs: [URL], operation: FileOperation, options: ConversionOptions, directory: URL) async throws -> ConversionResult {
        let health = try await EngineHealth.inspect("ffmpeg")
        let ffmpeg = try EngineHealth.require(health)
        var outputs: [URL] = []
        for input in inputs {
            try Task.checkCancellation()
            let inputFamily = FileFamily.detect(input)
            guard inputFamily == .audio || inputFamily == .video else { throw LemulipError.invalidInput("Select audio or video files for this tool.") }
            let sourceExtension = input.pathExtension.lowercased()
            let target: String
            if let requested = operation.outputExtension { target = requested.lowercased() }
            else if operation.id.hasPrefix("convert.") { target = String(operation.id.dropFirst(8)) }
            else if operation.id == "media.extractAudio" { target = "m4a" }
            else if operation.id == "media.compress" { target = inputFamily == .audio ? "m4a" : "mp4" }
            else { target = sourceExtension }
            guard audioExtensions.contains(target) || videoExtensions.contains(target) else {
                throw LemulipError.unsupported("FFmpeg output is not configured for .\(target).")
            }
            if inputFamily == .audio, videoExtensions.contains(target) { throw LemulipError.unsupported("An audio file cannot be converted into a video without an image track.") }
            let output = outputURL(for: input, operation: operation, extension: target, directory: directory)
            var arguments = ["-nostdin", "-hide_banner", "-loglevel", "error", "-n", "-filter_threads", "2", "-filter_complex_threads", "2", "-protocol_whitelist", "file,pipe",
                             "-format_whitelist", mediaDemuxers(sourceExtension), "-i", input.path]
            if operation.id == "media.trim" {
                if let duration = try await mediaDuration(input), options.startSeconds >= duration {
                    throw LemulipError.invalidInput("The trim start is beyond the end of \(input.lastPathComponent).")
                }
                arguments += ["-ss", decimal(options.startSeconds), "-t", decimal(options.endSeconds - options.startSeconds)]
            }
            if options.removeMetadata { arguments += ["-map_metadata", "-1", "-map_chapters", "-1"] }
            if target == "gif" {
                let dimension = min(options.maxDimension, 1920)
                var filter = "fps=\(options.framesPerSecond),scale=w='min(iw,\(dimension))':h='min(ih,\(dimension))':force_original_aspect_ratio=decrease:flags=lanczos"
                if operation.id == "media.speed" { filter = "setpts=PTS/\(decimal(options.speedMultiplier))," + filter }
                arguments += ["-filter_complex", "[0:v:0]\(filter),split[a][b];[a]palettegen[p];[b][p]paletteuse", "-an", "-loop", "0", "-threads", "4", output.path]
            } else if audioExtensions.contains(target) {
                arguments += ["-map", "0:a:0", "-vn"]
                if operation.id == "media.speed" { arguments += ["-af", tempoFilter(options.speedMultiplier)] }
                if operation.id == "media.volume" { arguments += ["-af", "volume=\(decimal(options.volumeMultiplier))"] }
                arguments += audioEncoding(target, compressed: operation.id == "media.compress", quality: options.quality)
                arguments += ["-threads", "4", output.path]
            } else {
                arguments += ["-map", "0:v:0"]
                if operation.id == "media.mute" { arguments += ["-an"] }
                else { arguments += ["-map", "0:a:0?"] }
                var videoFilters: [String] = []
                if operation.id == "media.resize" || operation.id == "media.compress" {
                    let max = options.maxDimension
                    videoFilters.append("scale=w='min(iw,\(max))':h='min(ih,\(max))':force_original_aspect_ratio=decrease:force_divisible_by=2")
                }
                if operation.id == "media.speed" {
                    videoFilters.append("setpts=PTS/\(decimal(options.speedMultiplier))")
                    arguments += ["-af", tempoFilter(options.speedMultiplier)]
                }
                if operation.id == "media.volume" { arguments += ["-af", "volume=\(decimal(options.volumeMultiplier))"] }
                videoFilters.append("pad=ceil(iw/2)*2:ceil(ih/2)*2")
                arguments += ["-vf", videoFilters.joined(separator: ",")]
                let crf = String(Int((36 - options.quality * 18).rounded()))
                switch target {
                case "webm": arguments += ["-c:v", "libvpx-vp9", "-crf", crf, "-b:v", "0", "-c:a", "libopus", "-b:a", "128k"]
                case "avi": arguments += ["-c:v", "mpeg4", "-q:v", "4", "-c:a", "libmp3lame", "-b:a", "192k"]
                case "wmv": arguments += ["-c:v", "wmv2", "-b:v", "2500k", "-c:a", "wmav2", "-b:a", "160k"]
                default:
                    arguments += ["-c:v", "libx264", "-preset", "medium", "-crf", crf, "-c:a", "aac", "-b:a", "160k"]
                    if ["mp4", "mov", "m4v"].contains(target) { arguments += ["-movflags", "+faststart"] }
                }
                arguments += ["-pix_fmt", "yuv420p", "-threads", "4", output.path]
            }
            let codecs = requiredEncoders(in: arguments)
            _ = try EngineHealth.require(health, capabilities: codecs)
            _ = try await ProcessRunner.checked(executable: ffmpeg, arguments: arguments, currentDirectory: directory)
            try requireFile(output); outputs.append(output)
        }
        return ConversionResult(outputs: outputs, note: operation.id == "media.compress" ? "Compression depends on the source; compare the output size before removing any original." : nil)
    }

    static func requiredEncoders(in arguments: [String]) -> Set<String> {
        let optionalAudio = arguments.contains("-an") || arguments.indices.contains { index in
            arguments[index] == "-map" && index + 1 < arguments.count && arguments[index + 1] == "0:a:0?"
        }
        return Set(arguments.indices.compactMap { index -> String? in
            let flag = arguments[index]
            guard ["-c:v", "-c:a"].contains(flag), index + 1 < arguments.count else { return nil }
            // An optional audio map can select no streams. FFmpeg checks that encoder
            // if audio is actually present; requiring it here would reject silent video.
            if flag == "-c:a" && optionalAudio { return nil }
            return arguments[index + 1]
        })
    }

    private static func mediaDemuxers(_ ext: String) -> String {
        switch ext {
        case "mp4", "mov", "m4v", "m4a": return "mov,mp4,m4a,3gp,3g2,mj2"
        case "mkv", "webm": return "matroska,webm"
        case "aif", "aiff": return "aiff"
        case "opus", "ogg": return "ogg"
        case "wma", "wmv": return "asf"
        default: return ext
        }
    }

    private static func mediaDuration(_ input: URL) async throws -> Double? {
        guard let ffprobe = EngineLocator.find("ffprobe") else { return nil }
        let result = try await ProcessRunner.checked(executable: ffprobe, arguments: ["-v", "error", "-protocol_whitelist", "file,pipe", "-format_whitelist", mediaDemuxers(input.pathExtension.lowercased()), "-show_entries", "format=duration", "-of", "json", input.path], timeout: 30)
        guard let json = try? JSONSerialization.jsonObject(with: result.standardOutput) as? [String: Any],
              let format = json["format"] as? [String: Any], let value = format["duration"] as? String,
              let duration = Double(value), duration.isFinite, duration > 0 else { return nil }
        return duration
    }

    private static func audioEncoding(_ ext: String, compressed: Bool, quality: Double) -> [String] {
        let bitrate = compressed ? "\(Int((64 + quality * 128).rounded()))k" : "192k"
        switch ext {
        case "mp3": return ["-c:a", "libmp3lame", "-b:a", bitrate]
        case "m4a", "aac": return ["-c:a", "aac", "-b:a", bitrate]
        case "wav": return ["-c:a", "pcm_s16le"]
        case "aif", "aiff": return ["-c:a", "pcm_s16be"]
        case "flac": return ["-c:a", "flac", "-compression_level", "8"]
        case "ogg": return ["-c:a", "libvorbis", "-q:a", compressed ? "3" : "5"]
        case "opus": return ["-c:a", "libopus", "-b:a", compressed ? "96k" : "128k"]
        case "wma": return ["-c:a", "wmav2", "-b:a", "160k"]
        default: return []
        }
    }

    private static func tempoFilter(_ multiplier: Double) -> String {
        var remainder = multiplier, filters: [String] = []
        while remainder > 2 { filters.append("atempo=2"); remainder /= 2 }
        while remainder < 0.5 { filters.append("atempo=0.5"); remainder /= 0.5 }
        filters.append("atempo=\(decimal(remainder))")
        return filters.joined(separator: ",")
    }

    static func image(_ inputs: [URL], operation: FileOperation, options: ConversionOptions, directory: URL) async throws -> ConversionResult {
        let health = try await EngineHealth.inspect("imagemagick")
        let magick = try EngineHealth.require(health)
        let profile = directory.appendingPathComponent(".image-policy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: profile) }
        let policy = """
        <?xml version="1.0" encoding="UTF-8"?>
        <policymap>
          <policy domain="resource" name="memory" value="256MiB"/>
          <policy domain="resource" name="map" value="512MiB"/>
          <policy domain="resource" name="disk" value="1GiB"/>
          <policy domain="resource" name="width" value="32768"/>
          <policy domain="resource" name="height" value="32768"/>
          <policy domain="resource" name="list-length" value="256"/>
          <policy domain="resource" name="time" value="120"/>
          <policy domain="resource" name="thread" value="4"/>
          <policy domain="delegate" rights="none" pattern="*"/>
          <policy domain="filter" rights="none" pattern="*"/>
          <policy domain="path" rights="none" pattern="@*"/>
          <policy domain="coder" rights="none" pattern="*"/>
          <policy domain="coder" rights="read|write" pattern="{PNG,JPEG,JPG,WEBP,AVIF,HEIC,HEIF,TIFF,TIF,BMP,GIF,ICO,SVG,MSVG}"/>
          <policy domain="coder" rights="write" pattern="INFO"/>
        </policymap>
        """
        try policy.write(to: profile.appendingPathComponent("policy.xml"), atomically: true, encoding: .utf8)
        var outputs: [URL] = []
        for input in inputs {
            try Task.checkCancellation()
            let source = input.pathExtension.lowercased()
            let target = operation.outputExtension?.lowercased() ?? (operation.id.hasPrefix("convert.") ? String(operation.id.dropFirst(8)) : source)
            let raster: Set<String> = ["jpg", "jpeg", "png", "webp", "avif", "heic", "heif", "tif", "tiff", "bmp", "gif", "ico"]
            guard raster.contains(source) || source == "svg", raster.contains(target) else {
                throw LemulipError.unsupported("This image conversion is not supported by the configured local engines.")
            }
            let aliases = ["jpg": "JPEG", "jpeg": "JPEG", "tif": "TIFF", "heif": "HEIC", "svg": "MSVG"]
            _ = try EngineHealth.require(health, capabilities: ["read:\(aliases[source] ?? source.uppercased())", "write:\(aliases[target] ?? target.uppercased())"])
            if source == "svg" { try validateSVG(try TextCodec.read(input)) }
            let copy = profile.appendingPathComponent("source-\(UUID().uuidString).\(source)")
            try FileManager.default.copyItem(at: input, to: copy)
            let temporaryOutput = profile.appendingPathComponent("output-\(UUID().uuidString).\(target)")
            let inputSpec = source == "svg" ? "MSVG:\(copy.path)[0]" : copy.path + "[0]"
            if operation.id == "image.crop" {
                let dimensions = try await ProcessRunner.checked(executable: magick, arguments: [inputSpec, "-auto-orient", "-format", "%w %h", "info:"], currentDirectory: profile,
                    environment: ["MAGICK_CONFIGURE_PATH": profile.path, "MAGICK_TEMPORARY_PATH": profile.path], timeout: 120)
                let numbers = String(decoding: dimensions.standardOutput, as: UTF8.self).split(whereSeparator: \.isWhitespace).compactMap { Int($0) }
                guard numbers.count == 2, options.width <= numbers[0], options.height <= numbers[1] else {
                    throw LemulipError.invalidInput("The crop width and height cannot exceed the source image dimensions.")
                }
            }
            var arguments = ["-limit", "memory", "256MiB", "-limit", "map", "512MiB", "-limit", "thread", "4", inputSpec, "-auto-orient"]
            switch operation.id {
            case "image.resize": arguments += ["-resize", "\(options.maxDimension)x\(options.maxDimension)>"]
            case "image.crop": arguments += ["-gravity", "center", "-crop", "\(options.width)x\(options.height)+0+0", "+repage"]
            case "image.rotate": arguments += ["-rotate", String(options.rotationDegrees)]
            case "image.flip": arguments += ["-flop"]
            default: break
            }
            if options.removeMetadata || operation.id == "image.stripMetadata" { arguments += ["-strip"] }
            if ["jpg", "jpeg", "bmp"].contains(target) { arguments += ["-background", "white", "-alpha", "remove", "-alpha", "off"] }
            arguments += ["-quality", String(Int((options.quality * 100).rounded())), temporaryOutput.path]
            _ = try await ProcessRunner.checked(executable: magick, arguments: arguments, currentDirectory: profile,
                environment: ["MAGICK_CONFIGURE_PATH": profile.path, "MAGICK_TEMPORARY_PATH": profile.path], timeout: 180)
            try requireFile(temporaryOutput)
            let output = outputURL(for: input, operation: operation, extension: target, directory: directory)
            try FileManager.default.moveItem(at: temporaryOutput, to: output); outputs.append(output)
        }
        return ConversionResult(outputs: outputs, note: inputs.contains(where: { $0.pathExtension.lowercased() == "gif" }) ? "Image conversion uses the first frame of animated images." : nil)
    }

    private static func validateSVG(_ text: String) throws {
        let forbidden = ["<!doctype", "<!entity", "<script", "<foreignobject", "<image"]
        let lower = text.lowercased()
        if forbidden.contains(where: lower.contains) { throw LemulipError.invalidInput("Use a self-contained SVG without scripts, entities, embedded documents, or external images.") }
        let expression = try NSRegularExpression(pattern: "(?:href\\s*=\\s*[\"']([^\"']*)|url\\(\\s*[\"']?([^)'\"]+))", options: .caseInsensitive)
        for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            for index in 1..<match.numberOfRanges {
                if let range = Range(match.range(at: index), in: text), !text[range].trimmingCharacters(in: .whitespaces).hasPrefix("#") {
                    throw LemulipError.invalidInput("SVG conversion does not load linked files or network resources.")
                }
            }
        }
    }

    static func office(_ inputs: [URL], operation: FileOperation, directory: URL) async throws -> ConversionResult {
        let office = try EngineHealth.require(try await EngineHealth.inspect("libreoffice"))
        let target = operation.outputExtension?.lowercased() ?? String(operation.id.dropFirst(8))
        guard officeExtensions.contains(target) else { throw LemulipError.unsupported("LibreOffice conversion to .\(target) is not configured.") }
        var outputs: [URL] = []
        for input in inputs {
            try Task.checkCancellation()
            let job = directory.appendingPathComponent(".office-\(UUID().uuidString)", isDirectory: true)
            let profile = job.appendingPathComponent("profile", isDirectory: true)
            let userProfile = profile.appendingPathComponent("user", isDirectory: true)
            let out = job.appendingPathComponent("output", isDirectory: true)
            try FileManager.default.createDirectory(at: userProfile, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: job) }
            let settings = """
            <?xml version="1.0" encoding="UTF-8"?>
            <oor:items xmlns:oor="http://openoffice.org/2001/registry">
              <item oor:path="/org.openoffice.Office.Common/Security/Scripting">
                <prop oor:name="DisableMacrosExecution" oor:op="fuse"><value>true</value></prop>
                <prop oor:name="MacroSecurityLevel" oor:op="fuse"><value>3</value></prop>
                <prop oor:name="DisableActiveContent" oor:op="fuse"><value>true</value></prop>
                <prop oor:name="BlockUntrustedRefererLinks" oor:op="fuse"><value>true</value></prop>
              </item>
              <item oor:path="/org.openoffice.Office.Calc/Content/Update">
                <prop oor:name="Link" oor:op="fuse"><value>1</value></prop>
              </item>
            </oor:items>
            """
            try settings.write(to: userProfile.appendingPathComponent("registrymodifications.xcu"), atomically: true, encoding: .utf8)
            // Isolate names so Office's output naming cannot turn an input name into an option or overwrite a sibling.
            let copiedInput = job.appendingPathComponent("input.\(input.pathExtension.lowercased())")
            try FileManager.default.copyItem(at: input, to: copiedInput)
            let htmlWordExport = target == "docx" && ["html", "htm"].contains(input.pathExtension.lowercased())
            let filter: String
            switch target {
            case "csv": filter = "csv:Text - txt - csv (StarCalc):44,34,76,1"
            case "tsv": filter = "csv:Text - txt - csv (StarCalc):9,34,76,1"
            case "docx" where htmlWordExport: filter = "docx:Office Open XML Text"
            default: filter = target
            }
            let profileURL = try officeProfileURL(profile)
            var ipcSockets: [URL] = []
            #if os(macOS)
            ipcSockets = try officeIPCSockets(profileURL: profileURL)
            #endif
            var arguments = ["-env:UserInstallation=\(profileURL)", "--headless", "--norestore", "--nodefault", "--nolockcheck", "--nofirststartwizard"]
            if htmlWordExport {
                // Writer/Web has no automatic DOCX filter. Import as a Writer
                // document to retain heading semantics, then select Word export.
                arguments.append("--infilter=HTML (StarWriter)")
            }
            arguments += ["--convert-to", filter, "--outdir", out.path, copiedInput.path]
            _ = try await ProcessRunner.checked(executable: office, arguments: arguments, currentDirectory: job, timeout: 180, allowedUnixSockets: ipcSockets)
            let expected = out.appendingPathComponent("input.\(target == "tsv" ? "csv" : target)")
            try requireFile(expected)
            if target == "html", try FileManager.default.contentsOfDirectory(atPath: out.path).count > 1 {
                let bundle = OutputStore.uniqueURL(in: directory, stem: input.deletingPathExtension().lastPathComponent + " HTML", extension: "")
                try FileManager.default.moveItem(at: expected, to: out.appendingPathComponent("index.html"))
                try FileManager.default.moveItem(at: out, to: bundle); outputs.append(bundle)
                continue
            }
            let output = outputURL(for: input, operation: operation, extension: target, directory: directory)
            try FileManager.default.moveItem(at: expected, to: output); outputs.append(output)
        }
        return ConversionResult(outputs: outputs, note: target == "csv" || target == "tsv" ? "CSV and TSV export the active sheet only; formulas and formatting become values." : target == "html" ? "HTML with embedded media is saved as a folder containing index.html and its resources. Complex layouts may change." : "Complex layouts may change when moving between office formats.")
    }

    static func officeProfileURL(_ profile: URL) throws -> String {
        // Match LibreOffice's canonical file-URL spelling, without a trailing slash.
        // sal/osl/unx/file_url.cxx uses this URI character set.
        let characters = CharacterSet(charactersIn: "!$&'()*+,-./0123456789:=@ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz~")
        let path = try ProcessRunner.canonicalDirectoryPath(profile)
        return "file://" + path.addingPercentEncoding(withAllowedCharacters: characters)!
    }

    #if os(macOS)
    static func officeIPCSockets(profileURL: String) throws -> [URL] {
        // LibreOffice 26.8 and current master use UTF-16 bytes and unpadded hex
        // for the profile's IPC name. MD5 here reproduces a name, not a security check.
        // https://github.com/LibreOffice/core/blob/libreoffice-26.8.0.3/desktop/source/deployment/misc/dp_misc.cxx
        let bytes = Data(profileURL.utf16.flatMap { [UInt8(truncatingIfNeeded: $0), UInt8($0 >> 8)] })
        let digest = Insecure.MD5.hash(data: bytes).map { String($0, radix: 16) }.joined()
        let name = "OSL_PIPE_\(getuid())_SingleOfficeIPC_\(digest)"
        // OSL_SOCKET_PATH is only a fallback when both standard directories are
        // unwritable, so an environment override would not relocate a normal run.
        return try ["/tmp", "/var/tmp"].map {
            let socket = URL(fileURLWithPath: $0, isDirectory: true).appendingPathComponent(name)
            return URL(fileURLWithPath: try ProcessRunner.canonicalUnixSocketPath(socket), isDirectory: false)
        }
    }
    #endif

    static func document(_ inputs: [URL], operation: FileOperation, directory: URL) async throws -> ConversionResult {
        let health = try await EngineHealth.inspect("pandoc")
        let pandoc = try EngineHealth.require(health)
        let target = operation.outputExtension?.lowercased() ?? String(operation.id.dropFirst(8))
        let readers = ["md": "markdown", "markdown": "markdown", "txt": "markdown", "html": "html", "htm": "html", "epub": "epub", "docx": "docx", "odt": "odt"]
        let writers = ["md": "markdown", "markdown": "markdown", "txt": "plain", "html": "html5", "htm": "html5", "epub": "epub3", "docx": "docx", "odt": "odt", "rtf": "rtf"]
        guard let writer = writers[target] else { throw LemulipError.unsupported("Pandoc output is not configured for .\(target).") }
        _ = try EngineHealth.require(health, capabilities: [writer])
        var outputs: [URL] = []
        for input in inputs {
            try Task.checkCancellation()
            guard let reader = readers[input.pathExtension.lowercased()] else { throw LemulipError.unsupported("This document format needs LibreOffice or a native macOS converter.") }
            let output = outputURL(for: input, operation: operation, extension: target, directory: directory)
            do {
                _ = try await ProcessRunner.checked(executable: pandoc, arguments: ["--sandbox", "--standalone", "--wrap=none", "--from=\(reader)", "--to=\(writer)", "--output=\(output.path)", input.path], currentDirectory: directory, timeout: 120)
            } catch LemulipError.operationFailed(let message) where message.contains("Could not find data file") {
                throw LemulipError.operationFailed("This Pandoc build cannot load the templates required for an offline conversion. Install the official Pandoc package with embedded data files from pandoc.org/installing.html, then reopen Lemulip. The file sandbox remains enabled.")
            }
            try requireFile(output, allowEmpty: ["txt", "md", "markdown"].contains(target)); outputs.append(output)
        }
        return ConversionResult(outputs: outputs, note: "Linked external resources are not loaded. Check formatting after document conversion.")
    }

    static func archives(_ inputs: [URL], operation: FileOperation, directory: URL) async throws -> ConversionResult {
        let cancellation = ArchiveCancellation()
        return try await withTaskCancellationHandler(operation: {
            let context = Unmanaged.passUnretained(cancellation).toOpaque()
            let callback: @convention(c) (UnsafeMutableRawPointer?) -> Int32 = { pointer in
                guard let pointer else { return 1 }
                return Unmanaged<ArchiveCancellation>.fromOpaque(pointer).takeUnretainedValue().isCancelled ? 1 : 0
            }
            var outputs: [URL] = []
            var error = [CChar](repeating: 0, count: 2048)
            if operation.id == "archive.extract" {
                for input in inputs {
                    try Task.checkCancellation()
                    let ext = input.pathExtension.lowercased()
                    let rawName = input.deletingPathExtension().lastPathComponent
                    let stem = rawName.hasSuffix(".tar") ? String(rawName.dropLast(4)) : rawName
                    let output = OutputStore.uniqueURL(in: directory, stem: stem + " extracted", extension: "")
                    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                    let code = lemulip_archive_extract(input.path, output.path, rawName, ["gz", "bz2", "xz"].contains(ext) ? 1 : 0, &error, error.count, callback, context)
                    try Task.checkCancellation()
                    guard code == 0 else { throw LemulipError.operationFailed(String(cString: error)) }
                    outputs.append(output)
                }
            } else {
                let format: Int32, ext: String
                switch operation.id {
                case "archive.createZip": format = Int32(LEMULIP_ARCHIVE_ZIP.rawValue); ext = "zip"
                case "archive.createTar": format = Int32(LEMULIP_ARCHIVE_TAR.rawValue); ext = "tar"
                case "archive.createGzip": format = Int32(LEMULIP_ARCHIVE_GZIP.rawValue); ext = "gz"
                default: throw LemulipError.unsupported("Choose ZIP, TAR, or Gzip for archive creation.")
                }
                let groups = operation.id == "archive.createGzip" ? inputs.map { [$0] } : [inputs]
                for group in groups {
                    try Task.checkCancellation()
                    if operation.id == "archive.createGzip", try group[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
                        throw LemulipError.invalidInput("Gzip compresses individual files. Choose ZIP or TAR for folders.")
                    }
                    var seen = Set<String>()
                    let names: [String] = group.map { input in
                        let base = OutputStore.safeStem(input.lastPathComponent)
                        var name = base, number = 2
                        while !seen.insert(name.precomposedStringWithCanonicalMapping.lowercased()).inserted { name = "\(base) (\(number))"; number += 1 }
                        return name
                    }
                    let stem = group.count == 1 ? (ext == "gz" ? group[0].lastPathComponent : group[0].deletingPathExtension().lastPathComponent) : "Archive"
                    let output = OutputStore.uniqueURL(in: directory, stem: stem, extension: ext)
                    let pathStorage = group.map { strdup($0.path) }
                    let nameStorage = names.map { strdup($0) }
                    defer { pathStorage.forEach { free($0) }; nameStorage.forEach { free($0) } }
                    guard pathStorage.allSatisfy({ $0 != nil }), nameStorage.allSatisfy({ $0 != nil }) else {
                        throw LemulipError.operationFailed("Not enough memory to create the archive.")
                    }
                    let paths = pathStorage.map { $0.map { UnsafePointer<CChar>($0) } }
                    let entryNames = nameStorage.map { $0.map { UnsafePointer<CChar>($0) } }
                    let code = paths.withUnsafeBufferPointer { paths in
                        entryNames.withUnsafeBufferPointer { names in
                            lemulip_archive_create(paths.baseAddress, names.baseAddress, group.count, output.path, format, &error, error.count, callback, context)
                        }
                    }
                    try Task.checkCancellation()
                    guard code == 0 else { throw LemulipError.operationFailed(String(cString: error)) }
                    outputs.append(output)
                }
            }
            return ConversionResult(outputs: outputs)
        }, onCancel: { cancellation.cancel() })
    }

    private static func outputURL(for input: URL, operation: FileOperation, extension ext: String, directory: URL) -> URL {
        let suffix: String
        switch operation.id {
        case "media.compress", "image.compress": suffix = " compressed"
        case "media.resize", "image.resize": suffix = " resized"
        case "media.trim": suffix = " trimmed"
        case "media.mute": suffix = " muted"
        case "media.extractAudio": suffix = " audio"
        case "media.speed": suffix = " speed"
        case "media.volume": suffix = " volume"
        case "image.crop": suffix = " cropped"
        case "image.rotate": suffix = " rotated"
        case "image.flip": suffix = " flipped"
        case "image.stripMetadata": suffix = " clean"
        default: suffix = ""
        }
        return OutputStore.uniqueURL(in: directory, stem: input.deletingPathExtension().lastPathComponent + suffix, extension: ext)
    }

    private static func requireFile(_ url: URL, allowEmpty: Bool = false) throws {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values?.isRegularFile == true, values?.isSymbolicLink != true, allowEmpty || (values?.fileSize ?? 0) > 0 else {
            throw LemulipError.operationFailed("The converter did not produce a valid output file. The source or requested format may not be supported.")
        }
    }

    private static func decimal(_ number: Double) -> String { String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), number) }
}

private final class ArchiveCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func cancel() { lock.lock(); value = true; lock.unlock() }
}
