import Foundation

/// Pinned upstream packages. Network access is only used after an explicit install action.
struct PandocPackage: Sendable {
    let version = "3.12.1"
    let architecture: String
    let sha256: String
    var url: URL {
        URL(string: "https://github.com/jgm/pandoc/releases/download/\(version)/pandoc-\(version)-\(architecture)-macOS.zip")!
    }
    init(architecture: String) throws {
        self.architecture = architecture
        switch architecture {
        case "arm64": sha256 = "c2146cf33a583f3ac93eccddf1bb662371d5cfcce1aad1c87ad860cca1435d46"
        case "x86_64": sha256 = "81ed3e2cfecf096df15d407152f89a684fd65221082b919963f738e977fad3bc"
        default: throw LemulipError.unsupported("No reviewed document engine is available for this architecture.")
        }
    }
    static func allowsDownload(_ url: URL) -> Bool {
        url.scheme == "https" && url.user == nil && url.password == nil &&
        (url.port == nil || url.port == 443) &&
        ["github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"].contains(url.host?.lowercased() ?? "")
    }
}

#if os(macOS)
import CryptoKit

/// Downloads the unmodified official archive, never shell commands or unverified code.
public actor EngineInstaller {
    public static let shared = EngineInstaller()
    private var installing = false
    private static let maximumArchiveBytes: Int64 = 200 * 1024 * 1024
    private static var package: PandocPackage {
        get throws {
            #if arch(arm64)
            return try PandocPackage(architecture: "arm64")
            #elseif arch(x86_64)
            return try PandocPackage(architecture: "x86_64")
            #else
            throw LemulipError.unsupported("Unsupported architecture.")
            #endif
        }
    }

    public func installPandoc() async throws -> EngineReport {
        guard !installing else { throw LemulipError.operationFailed("A document engine installation is already running.") }
        installing = true
        defer { installing = false }
        try Task.checkCancellation()
        let package = try Self.package
        let policy = DownloadPolicy(maximumBytes: Self.maximumArchiveBytes)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        let session = URLSession(configuration: configuration, delegate: policy, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (download, response) = try await session.download(from: package.url)
        defer { try? FileManager.default.removeItem(at: download) }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let url = response.url, PandocPackage.allowsDownload(url) else {
            throw LemulipError.operationFailed("The official document engine download could not be verified.")
        }
        return try await Self.installDownloadedPandoc(download, homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
    }

    /// Internal entry point lets native CI exercise the exact checked upstream archive offline.
    static func installDownloadedPandoc(_ archive: URL, homeDirectory: URL) async throws -> EngineReport {
        try Task.checkCancellation()
        guard archive.isFileURL, homeDirectory.isFileURL else { throw LemulipError.invalidInput("Installation requires local paths.") }
        let package = try Self.package
        let attributes = try archive.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard attributes.isRegularFile == true, attributes.isSymbolicLink != true,
              let size = attributes.fileSize, size > 0, Int64(size) <= maximumArchiveBytes else {
            throw LemulipError.invalidInput("The document engine archive is invalid or too large.")
        }
        let handle = try FileHandle(forReadingFrom: archive)
        defer { try? handle.close() }
        var hash = SHA256(); var bytes: Int64 = 0
        while let block = try handle.read(upToCount: 1_048_576), !block.isEmpty {
            try Task.checkCancellation()
            bytes += Int64(block.count)
            guard bytes <= maximumArchiveBytes else { throw LemulipError.invalidInput("The archive exceeds its size limit.") }
            hash.update(data: block)
        }
        let actual = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == package.sha256 else { throw LemulipError.invalidInput("The document engine checksum does not match. Nothing was installed.") }
        let manager = FileManager.default
        let home = homeDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let engines = home.appendingPathComponent("Library/Application Support/Lemulip/Engines", isDirectory: true)
        var directory = home
        for part in ["Library", "Application Support", "Lemulip", "Engines"] {
            directory.appendPathComponent(part, isDirectory: true)
            if let values = try? directory.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey]) {
                guard values.isSymbolicLink != true, values.isDirectory == true else {
                    throw LemulipError.invalidInput("The engine installation folder must not contain links or files.")
                }
            } else {
                try manager.createDirectory(at: directory, withIntermediateDirectories: false,
                                            attributes: [.posixPermissions: 0o700])
            }
        }
        let destination = engines.appendingPathComponent("pandoc", isDirectory: true)
        guard !manager.fileExists(atPath: destination.path),
              (try? destination.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
            throw LemulipError.operationFailed("A managed document engine already exists. It was left unchanged.")
        }
        let stage = engines.appendingPathComponent(".install-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? manager.removeItem(at: stage) }
        // Copy the already verified archive into our private staging directory and
        // verify the copied bytes too; the source can no longer be swapped under extraction.
        let copy = stage.appendingPathComponent("pandoc.zip")
        try manager.copyItem(at: archive, to: copy)
        let copied = try Data(contentsOf: copy, options: .mappedIfSafe)
        guard copied.count == size, SHA256.hash(data: copied).map({ String(format: "%02x", $0) }).joined() == package.sha256 else {
            throw LemulipError.invalidInput("The archive changed during installation.")
        }
        try Task.checkCancellation()
        let extracted = stage.appendingPathComponent("expanded", isDirectory: true)
        try manager.createDirectory(at: extracted, withIntermediateDirectories: false)
        let result = try await ExternalConverters.archives([copy], operation: FileOperation(id: "archive.extract", title: "Extract"), directory: extracted)
        guard let root = result.outputs.first else { throw LemulipError.operationFailed("The archive contains no engine.") }
        let expected = root.appendingPathComponent("pandoc-\(package.version)-\(package.architecture)", isDirectory: true)
        let executable = expected.appendingPathComponent("bin/pandoc")
        guard manager.fileExists(atPath: executable.path) else { throw LemulipError.invalidInput("The official archive has an unexpected layout.") }
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let report = try await EngineHealth.inspect("pandoc", executable: executable, timeout: 15)
        guard report.state == .ready else { throw LemulipError.operationFailed("The document engine failed its local compatibility check. " + report.detail) }
        try Task.checkCancellation()
        // moveItem refuses an existing destination; it never replaces a user's engine.
        try manager.moveItem(at: expected, to: destination)
        do {
            let installed = try await EngineHealth.inspect("pandoc", executable: destination.appendingPathComponent("bin/pandoc"), timeout: 15)
            guard installed.state == .ready else { throw LemulipError.operationFailed("The installed document engine failed verification.") }
            return installed
        } catch {
            try? manager.removeItem(at: destination)
            throw error
        }
    }
}

private final class DownloadPolicy: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let maximumBytes: Int64
    init(maximumBytes: Int64) { self.maximumBytes = maximumBytes }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map(PandocPackage.allowsDownload) == true ? request : nil)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > maximumBytes || totalBytesExpectedToWrite > maximumBytes { downloadTask.cancel() }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}
#endif
