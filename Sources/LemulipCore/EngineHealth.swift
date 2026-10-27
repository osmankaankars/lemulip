import Foundation

/// A bounded execution probe, not merely the presence of an executable file.
public struct EngineReport: Sendable {
    public enum State: String, Sendable { case missing, unusable, limited, ready }
    public let name: String
    public let executable: URL?
    public let state: State
    public let version: String?
    public let capabilities: Set<String>
    public let detail: String
    public var canRun: Bool { state == .ready || state == .limited }
}

public enum EngineHealth {
    public static func inspect(_ name: String, executable: URL? = nil, timeout: TimeInterval = 8) async throws -> EngineReport {
        try Task.checkCancellation()
        let name = name.lowercased() == "magick" ? "imagemagick" : name.lowercased()
        guard let path = executable ?? EngineLocator.find(name) else {
            return EngineReport(name: name, executable: nil, state: .missing, version: nil, capabilities: [], detail: "Not installed")
        }
        var version: String?
        do {
            let prefix: String
            let versionArguments: [String]
            switch name {
            case "ffmpeg", "ffprobe": prefix = "\(name) version "; versionArguments = ["-version"]
            case "imagemagick": prefix = "Version: ImageMagick "; versionArguments = ["-version"]
            case "pandoc": prefix = "pandoc "; versionArguments = ["--version"]
            case "libreoffice": prefix = "LibreOffice "; versionArguments = ["--headless", "--version"]
            default: throw LemulipError.unsupported("Unknown engine.")
            }
            let identity = try await probe(path, arguments: versionArguments, timeout: timeout)
            guard let first = identity.split(separator: "\n").first, first.hasPrefix(prefix) else {
                throw LemulipError.operationFailed("This executable did not identify itself as \(name).")
            }
            version = first.dropFirst(prefix.count).split(whereSeparator: \.isWhitespace).first.map(String.init)
            guard version?.contains(where: \.isNumber) == true else {
                throw LemulipError.operationFailed("The engine did not report a valid version.")
            }
            var capabilities = Set<String>(), expected = Set<String>()
            switch name {
            case "ffmpeg":
                let list = try await probe(path, arguments: ["-hide_banner", "-encoders"], timeout: timeout)
                for row in list.split(separator: "\n") {
                    let fields = row.split(whereSeparator: \.isWhitespace)
                    if fields.count >= 2, fields[0].count == 6,
                       ["V", "A", "S"].contains(String(fields[0].prefix(1))), fields[1] != "=" {
                        capabilities.insert(String(fields[1]))
                    }
                }
                expected = ["libx264", "aac", "libmp3lame", "libopus", "libvorbis", "libvpx-vp9", "pcm_s16le", "pcm_s16be", "flac", "gif"]
            case "imagemagick":
                let list = try await probe(path, arguments: ["-list", "format"], timeout: timeout)
                for row in list.split(separator: "\n") {
                    let fields = row.split(whereSeparator: \.isWhitespace)
                    guard fields.count >= 3,
                          let mode = fields.dropFirst().prefix(2).first(where: {
                              $0.count == 3 && ["r", "-"].contains(String($0.prefix(1))) &&
                              ["w", "-"].contains(String($0.dropFirst().prefix(1))) &&
                              ["+", "-"].contains(String($0.suffix(1)))
                          }) else { continue }
                    let format = fields[0].replacingOccurrences(of: "*", with: "").uppercased()
                    if mode.first == "r" { capabilities.insert("read:\(format)") }
                    if mode.dropFirst().first == "w" { capabilities.insert("write:\(format)") }
                }
                expected = ["write:PNG", "write:JPEG", "write:WEBP", "write:AVIF"]
            case "pandoc":
                let list = try await probe(path, arguments: ["--list-output-formats"], timeout: timeout)
                capabilities = Set(list.split(whereSeparator: \.isWhitespace).map(String.init))
                expected = ["docx", "odt", "epub3", "html5", "plain", "markdown", "rtf"]
                // Exercise the same sandbox as a real Word conversion with empty input.
                // Missing embedded templates must not produce a green status.
                let smoke = try await ProcessRunner.run(executable: path,
                    arguments: ["--sandbox", "--standalone", "--from=markdown", "--to=docx"],
                    maximumOutputBytes: 4_096, timeout: timeout)
                guard smoke.exitCode == 0, smoke.standardOutput.starts(with: [0x50, 0x4b]) else {
                    throw LemulipError.operationFailed("The Pandoc build cannot create Word documents with the file sandbox enabled. Use the official package with embedded templates.")
                }
            default: break
            }
            let missing = expected.subtracting(capabilities).sorted()
            return EngineReport(name: name, executable: path, state: missing.isEmpty ? .ready : .limited,
                version: version, capabilities: capabilities,
                detail: missing.isEmpty ? "Ready" : "Unavailable: " + missing.joined(separator: ", "))
        } catch {
            try Task.checkCancellation()
            return EngineReport(name: name, executable: path, state: .unusable, version: version,
                capabilities: [], detail: String(error.localizedDescription.prefix(400)))
        }
    }

    static func require(_ report: EngineReport, capabilities: Set<String> = []) throws -> URL {
        guard report.state != .missing else { throw LemulipError.missingDependency(report.name) }
        guard report.canRun, let path = report.executable else {
            throw LemulipError.operationFailed("\(report.name) was found but is not usable. \(report.detail)")
        }
        let missing = capabilities.subtracting(report.capabilities)
        guard missing.isEmpty else {
            throw LemulipError.unsupported("This \(report.name) build does not provide: \(missing.sorted().joined(separator: ", ")). Choose a supported output or install a compatible engine.")
        }
        return path
    }

    private static func probe(_ executable: URL, arguments: [String], timeout: TimeInterval) async throws -> String {
        let output = try await ProcessRunner.run(executable: executable, arguments: arguments, timeout: timeout)
        guard output.exitCode == 0 else {
            throw LemulipError.operationFailed("Engine check failed (exit \(output.exitCode)). \(output.errorText.prefix(200))")
        }
        return String(decoding: output.standardOutput + output.standardError, as: UTF8.self)
    }
}
