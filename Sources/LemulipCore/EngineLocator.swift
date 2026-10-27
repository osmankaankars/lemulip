import Foundation

/// Finds optional local converters without starting a shell or reading credentials.
public enum EngineLocator {
    public static func find(_ name: String, bundleURL: URL = Bundle.main.bundleURL,
                            homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let aliases: [String]
        switch name.lowercased() {
        case "imagemagick", "magick": aliases = ["magick", "convert"]
        case "libreoffice", "soffice": aliases = ["soffice", "libreoffice"]
        case "ffmpeg", "ffprobe", "pandoc": aliases = [name.lowercased()]
        default:
            guard !name.isEmpty, name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-_".contains($0)) }) else { return nil }
            aliases = [name]
        }
        let family: String
        switch name.lowercased() {
        case "ffmpeg", "ffprobe": family = "ffmpeg"
        case "imagemagick", "magick": family = "imagemagick"
        case "libreoffice", "soffice": family = "libreoffice"
        default: family = name.lowercased()
        }
        let managed = homeDirectory.appendingPathComponent("Library/Application Support/Lemulip/Engines")
        let bundled = bundleURL.appendingPathComponent("Contents/Helpers/Engines")
        // Signed CLI helpers live directly in Helpers; sources/notices are in Resources.
        var directories = [bundleURL.appendingPathComponent("Contents/Helpers").path]
        directories += [bundled, managed].map { $0.appendingPathComponent(family).appendingPathComponent("bin").path }
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            directories += path.split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
        }
        directories += ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        var candidates = directories.flatMap { directory in aliases.map { URL(fileURLWithPath: directory).appendingPathComponent($0) } }
        if aliases.contains("soffice") {
            candidates += [homeDirectory.appendingPathComponent("Applications/LibreOffice.app/Contents/MacOS/soffice"),
                           URL(fileURLWithPath: "/Applications/LibreOffice.app/Contents/MacOS/soffice")]
        }
        var seen = Set<String>()
        for url in candidates where seen.insert(url.path).inserted {
            var directory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &directory),
               !directory.boolValue, FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    public static func isAvailable(_ name: String) -> Bool { find(name) != nil }
}
