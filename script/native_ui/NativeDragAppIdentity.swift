import AppKit
import CryptoKit
import Darwin
import Foundation
import Security

// These errors are safe to include in the shared diagnostic report. Never
// attach an underlying Foundation/Security error, which may contain a path.
enum SameHostAppIdentityFailure: String, Error, CaseIterable, CustomStringConvertible {
    case invalidExpectation = "expectation-invalid"
    case expectedContentsMismatch = "expected-contents-mismatch"
    case expectedSignatureInvalid = "expected-signature-invalid"
    case expectedCodeIdentityUnavailable = "expected-code-identity-unavailable"
    case processIdentityUnavailable = "process-identity-unavailable"
    case runtimePathUnavailable = "runtime-path-unavailable"
    case runtimeCodeUnavailable = "runtime-code-unavailable"
    case runtimeSignatureInvalid = "runtime-signature-invalid"
    case runtimeCodeMismatch = "runtime-code-mismatch"
    case runtimeBundleLinkMismatch = "runtime-bundle-link-mismatch"
    case runtimeContentsMismatch = "runtime-contents-mismatch"
    case processIdentityChanged = "process-identity-changed"

    var code: String { rawValue }
    var description: String { "The same-host application identity check failed (\(rawValue))" }
}

fileprivate enum SameHostCodeValidation {
    static let strictFlags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures)

    static func canonical(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    static func localFileURL(_ url: URL) -> Bool {
        url.isFileURL && url.path.hasPrefix("/")
            && (url.host == nil || url.host == "" || url.host == "localhost")
    }

    static func staticCode(at url: URL, failure: SameHostAppIdentityFailure) throws -> SecStaticCode {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else {
            throw failure
        }
        return code
    }

    static func onDiskCode(for code: SecCode) throws -> SecStaticCode {
        var result: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &result) == errSecSuccess, let result else {
            throw SameHostAppIdentityFailure.runtimeCodeUnavailable
        }
        return result
    }

    struct Metadata {
        let identifier: String
        let hash: Data
        let bundle: URL
        let executable: URL
    }

    // Call only after validating the corresponding static or dynamic code.
    // CopySigningInformation itself does not validate a signature.
    static func metadata(for code: SecStaticCode, failure: SameHostAppIdentityFailure) throws -> Metadata {
        var information: CFDictionary?
        var path: CFURL?
        guard SecCodeCopySigningInformation(code, [], &information) == errSecSuccess,
              let information = information as? [String: Any],
              let identifier = information[kSecCodeInfoIdentifier as String] as? String,
              let hash = information[kSecCodeInfoUnique as String] as? Data,
              // This diagnostic pins the existing thin C12 binary. The public
              // cdhash requirement uses its 20-byte canonical code hash.
              hash.count == 20,
              let executable = information[kSecCodeInfoMainExecutable as String] as? URL,
              SecCodeCopyPath(code, [], &path) == errSecSuccess, let path else {
            throw failure
        }
        let bundle = path as URL
        guard localFileURL(bundle), localFileURL(executable) else { throw failure }
        return Metadata(identifier: identifier, hash: hash,
                        bundle: canonical(bundle), executable: canonical(executable))
    }

    static func checkDynamic(_ code: SecCode, requirement: SecRequirement) throws {
        let status = SecCodeCheckValidity(code, [], requirement)
        guard status == errSecSuccess else {
            throw status == errSecCSReqFailed
                ? SameHostAppIdentityFailure.runtimeCodeMismatch
                : SameHostAppIdentityFailure.runtimeSignatureInvalid
        }
    }
}

@MainActor
fileprivate struct SameHostProcessIdentity {
    let identifier: String
    let pid: pid_t
    let launchDate: Date
    let bundle: URL
    let executable: URL

    init(_ app: NSRunningApplication, expectedIdentifier: String, executableName: String) throws {
        guard !app.isTerminated, app.processIdentifier > 0,
              app.bundleIdentifier == expectedIdentifier,
              let launchDate = app.launchDate,
              launchDate.timeIntervalSince1970.isFinite,
              launchDate.timeIntervalSince1970 > 0 else {
            throw SameHostAppIdentityFailure.processIdentityUnavailable
        }
        guard let bundle = app.bundleURL, let executable = app.executableURL,
              SameHostCodeValidation.localFileURL(bundle),
              SameHostCodeValidation.localFileURL(executable) else {
            throw SameHostAppIdentityFailure.runtimePathUnavailable
        }
        let normalizedBundle = SameHostCodeValidation.canonical(bundle)
        let normalizedExecutable = SameHostCodeValidation.canonical(executable)
        guard normalizedBundle.pathExtension == "app",
              normalizedExecutable.path == normalizedBundle
                .appendingPathComponent("Contents/MacOS/" + executableName).path else {
            throw SameHostAppIdentityFailure.runtimeBundleLinkMismatch
        }
        self.identifier = expectedIdentifier
        self.pid = app.processIdentifier
        self.launchDate = launchDate
        self.bundle = normalizedBundle
        self.executable = normalizedExecutable
    }

    func matches(_ app: NSRunningApplication) -> Bool {
        !app.isTerminated && app.processIdentifier == pid && app.bundleIdentifier == identifier
            && app.launchDate == launchDate
            && app.bundleURL.map { SameHostCodeValidation.canonical($0).path } == bundle.path
            && app.executableURL.map { SameHostCodeValidation.canonical($0).path } == executable.path
    }

    func matches(_ metadata: SameHostCodeValidation.Metadata) -> Bool {
        metadata.identifier == identifier && metadata.bundle.path == bundle.path
            && metadata.executable.path == executable.path
    }
}

// A content identity, not a test for App Translocation. The expected file map
// comes only from the already verified, pinned package manifest. A different
// runtime path is acceptable only after all content and live-code checks pass.
@MainActor
final class SameHostAppIdentity {
    private let expectedBundle: URL
    private let expectedIdentifier: String
    private let executableName: String
    private let expectedFiles: [String: String]
    private let codeHash: Data
    private let requirement: SecRequirement

    init(expectedBundle: URL, expectedIdentifier: String, executableName: String,
         expectedFiles: [String: String]) throws {
        guard !expectedIdentifier.isEmpty, expectedIdentifier.utf8.count <= 255,
              !executableName.isEmpty, executableName.utf8.count <= 255,
              !executableName.contains("/"), !executableName.contains("\\"),
              executableName != ".", executableName != "..",
              expectedBundle.pathExtension == "app",
              expectedFiles["Contents/Info.plist"] != nil,
              expectedFiles["Contents/MacOS/" + executableName] != nil,
              expectedFiles["Contents/_CodeSignature/CodeResources"] != nil else {
            throw SameHostAppIdentityFailure.invalidExpectation
        }
        try Self.verifyContents(at: expectedBundle, expectedFiles: expectedFiles)
        let bundle = SameHostCodeValidation.canonical(expectedBundle)
        let staticCode = try SameHostCodeValidation.staticCode(at: bundle, failure: .expectedSignatureInvalid)
        guard SecStaticCodeCheckValidity(staticCode, SameHostCodeValidation.strictFlags, nil) == errSecSuccess else {
            throw SameHostAppIdentityFailure.expectedSignatureInvalid
        }
        let metadata = try SameHostCodeValidation.metadata(for: staticCode, failure: .expectedCodeIdentityUnavailable)
        guard metadata.identifier == expectedIdentifier, metadata.bundle.path == bundle.path,
              metadata.executable.path == bundle.appendingPathComponent("Contents/MacOS/" + executableName).path else {
            throw SameHostAppIdentityFailure.expectedCodeIdentityUnavailable
        }
        do {
            let infoURL = bundle.appendingPathComponent("Contents/Info.plist")
            let info = try PropertyListSerialization.propertyList(
                from: Self.smallData(at: infoURL, maximum: 262_144), options: [], format: nil) as? [String: Any]
            guard info?["CFBundleIdentifier"] as? String == expectedIdentifier,
                  info?["CFBundleExecutable"] as? String == executableName else {
                throw SameHostAppIdentityFailure.expectedCodeIdentityUnavailable
            }
        } catch {
            throw SameHostAppIdentityFailure.expectedCodeIdentityUnavailable
        }
        let hex = metadata.hash.map { String(format: "%02x", $0) }.joined()
        var pinnedRequirement: SecRequirement?
        guard SecRequirementCreateWithString("cdhash H\"\(hex)\"" as CFString, [], &pinnedRequirement) == errSecSuccess,
              let pinnedRequirement,
              SecStaticCodeCheckValidity(staticCode, SameHostCodeValidation.strictFlags, pinnedRequirement) == errSecSuccess else {
            throw SameHostAppIdentityFailure.expectedCodeIdentityUnavailable
        }
        self.expectedBundle = bundle
        self.expectedIdentifier = expectedIdentifier
        self.executableName = executableName
        self.expectedFiles = expectedFiles
        self.codeHash = metadata.hash
        self.requirement = pinnedRequirement
    }

    func claim(_ app: NSRunningApplication) throws -> SameHostOwnedApplication {
        let process = try SameHostProcessIdentity(app, expectedIdentifier: expectedIdentifier,
                                                 executableName: executableName)
        let attributes = [kSecGuestAttributePid as String: NSNumber(value: process.pid)] as CFDictionary
        var guest: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &guest) == errSecSuccess, let guest else {
            throw SameHostAppIdentityFailure.runtimeCodeUnavailable
        }
        try SameHostCodeValidation.checkDynamic(guest, requirement: requirement)
        let staticCode = try SameHostCodeValidation.onDiskCode(for: guest)
        let status = SecStaticCodeCheckValidity(staticCode, SameHostCodeValidation.strictFlags, requirement)
        guard status == errSecSuccess else {
            throw status == errSecCSReqFailed
                ? SameHostAppIdentityFailure.runtimeCodeMismatch
                : SameHostAppIdentityFailure.runtimeSignatureInvalid
        }
        let metadata = try SameHostCodeValidation.metadata(for: staticCode, failure: .runtimeCodeUnavailable)
        guard metadata.hash == codeHash else { throw SameHostAppIdentityFailure.runtimeCodeMismatch }
        guard process.matches(metadata) else { throw SameHostAppIdentityFailure.runtimeBundleLinkMismatch }
        do { try Self.verifyContents(at: process.bundle, expectedFiles: expectedFiles) }
        catch { throw SameHostAppIdentityFailure.runtimeContentsMismatch }
        guard process.matches(app) else { throw SameHostAppIdentityFailure.processIdentityChanged }

        let owned = SameHostOwnedApplication(application: app, process: process, code: guest,
            codeHash: codeHash, requirement: requirement, expectedBundle: expectedBundle)
        try owned.validate(app)
        return owned
    }

    // Also used by the input-free CI harness for isolated negative fixtures.
    // Extra directories, including empty ones, are not part of the sealed app.
    static func verifyContents(at proposed: URL, expectedFiles: [String: String]) throws {
        let maximumFiles = 128
        let maximumEntries = 512
        let maximumFileBytes = 134_217_728
        let maximumTotalBytes = 268_435_456
        guard !expectedFiles.isEmpty, expectedFiles.count <= maximumFiles else {
            throw SameHostAppIdentityFailure.invalidExpectation
        }
        var expectedDirectories = Set<String>()
        for (path, hash) in expectedFiles {
            let components = path.split(separator: "/", omittingEmptySubsequences: false)
            guard !components.isEmpty, path.utf8.count <= 1_024,
                  !path.contains("\\"),
                  !path.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
                  components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                  hash.utf8.count == 64,
                  hash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
                throw SameHostAppIdentityFailure.invalidExpectation
            }
            for count in 1..<components.count {
                expectedDirectories.insert(components.prefix(count).joined(separator: "/"))
            }
        }
        guard expectedDirectories.isDisjoint(with: expectedFiles.keys),
              expectedDirectories.count + expectedFiles.count <= maximumEntries else {
            throw SameHostAppIdentityFailure.invalidExpectation
        }
        do {
            try Self.checkDirectory(proposed)
            let root = SameHostCodeValidation.canonical(proposed)
            try Self.checkDirectory(root)
            let prefix = root.path + "/"
            let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
            var enumerationFailed = false
            guard let entries = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                options: [], errorHandler: { _, _ in enumerationFailed = true; return false }) else {
                throw SameHostAppIdentityFailure.expectedContentsMismatch
            }
            var files = Set<String>()
            var directories = Set<String>()
            var entryCount = 0
            var byteCount = 0
            while let item = entries.nextObject() {
                guard let entry = item as? URL else { throw SameHostAppIdentityFailure.expectedContentsMismatch }
                entryCount += 1
                guard entryCount <= maximumEntries else { throw SameHostAppIdentityFailure.expectedContentsMismatch }
                let values = try entry.resourceValues(forKeys: Set(keys))
                let normalized = SameHostCodeValidation.canonical(entry)
                guard values.isSymbolicLink == false, normalized.path.hasPrefix(prefix),
                      entry.standardizedFileURL.path == normalized.path else {
                    throw SameHostAppIdentityFailure.expectedContentsMismatch
                }
                // Enumeration can use /private/var while Foundation's root is
                // /var. Both containment and slicing use the resolved spelling.
                let relative = String(normalized.path.dropFirst(prefix.count))
                if values.isDirectory == true {
                    guard expectedDirectories.contains(relative), directories.insert(relative).inserted else {
                        throw SameHostAppIdentityFailure.expectedContentsMismatch
                    }
                } else {
                    guard values.isRegularFile == true, let expected = expectedFiles[relative],
                          files.insert(relative).inserted else {
                        throw SameHostAppIdentityFailure.expectedContentsMismatch
                    }
                    let (digest, size) = try Self.digest(at: entry, maximum: maximumFileBytes)
                    byteCount += size
                    guard byteCount <= maximumTotalBytes, digest == expected else {
                        throw SameHostAppIdentityFailure.expectedContentsMismatch
                    }
                }
            }
            guard !enumerationFailed, files == Set(expectedFiles.keys), directories == expectedDirectories else {
                throw SameHostAppIdentityFailure.expectedContentsMismatch
            }
            try Self.checkDirectory(root)
        } catch {
            throw SameHostAppIdentityFailure.expectedContentsMismatch
        }
    }

    private static func checkDirectory(_ url: URL) throws {
        guard SameHostCodeValidation.localFileURL(url) else { throw SameHostAppIdentityFailure.expectedContentsMismatch }
        var path = url.path
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        var metadata = stat()
        guard Darwin.lstat(path, &metadata) == 0,
              (metadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else {
            throw SameHostAppIdentityFailure.expectedContentsMismatch
        }
    }

    private static func readFile(at url: URL, maximum: Int, consume: (Data) throws -> Void) throws -> Int {
        // O_NONBLOCK avoids waiting on a non-regular file if a leaf changes
        // between enumeration and opening; fstat still requires a regular file.
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else { throw SameHostAppIdentityFailure.expectedContentsMismatch }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var before = stat()
        guard Darwin.fstat(descriptor, &before) == 0,
              (before.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              before.st_size >= 0, before.st_size <= off_t(maximum) else {
            throw SameHostAppIdentityFailure.expectedContentsMismatch
        }
        var count = 0
        while let bytes = try handle.read(upToCount: 1_048_576), !bytes.isEmpty {
            count += bytes.count
            guard count <= maximum, count <= Int(before.st_size) else { throw SameHostAppIdentityFailure.expectedContentsMismatch }
            try consume(bytes)
        }
        var after = stat()
        guard count == Int(before.st_size), Darwin.fstat(descriptor, &after) == 0,
              after.st_size == before.st_size,
              after.st_mtimespec.tv_sec == before.st_mtimespec.tv_sec,
              after.st_mtimespec.tv_nsec == before.st_mtimespec.tv_nsec,
              after.st_ctimespec.tv_sec == before.st_ctimespec.tv_sec,
              after.st_ctimespec.tv_nsec == before.st_ctimespec.tv_nsec else {
            throw SameHostAppIdentityFailure.expectedContentsMismatch
        }
        return count
    }

    private static func digest(at url: URL, maximum: Int) throws -> (String, Int) {
        var digest = SHA256()
        let size = try readFile(at: url, maximum: maximum) { digest.update(data: $0) }
        return (digest.finalize().map { String(format: "%02x", $0) }.joined(), size)
    }

    private static func smallData(at url: URL, maximum: Int) throws -> Data {
        var data = Data()
        _ = try readFile(at: url, maximum: maximum) { data.append($0) }
        return data
    }
}

// This token owns the original NSWorkspace result only after claim succeeds.
// A same-code replacement process does not inherit the token. Retaining a PID
// alone would be insufficient: both app objects must still report the captured
// launch date and URLs, and the original object must still be alive.
@MainActor
final class SameHostOwnedApplication {
    let bundleURL: URL
    let receipt: [String: Bool]
    private let application: NSRunningApplication
    private let process: SameHostProcessIdentity
    private let code: SecCode
    private let codeHash: Data
    private let requirement: SecRequirement

    fileprivate init(application: NSRunningApplication, process: SameHostProcessIdentity, code: SecCode,
                     codeHash: Data, requirement: SecRequirement, expectedBundle: URL) {
        self.application = application
        self.process = process
        self.code = code
        self.codeHash = codeHash
        self.requirement = requirement
        self.bundleURL = process.bundle
        self.receipt = [
            "expectedBundleContentsVerified": true,
            "expectedStaticCodeValid": true,
            "runtimeBundleContentsVerified": true,
            "runtimeStaticCodeValid": true,
            "runtimeDynamicCodeValid": true,
            "codeDirectoryHashMatches": true,
            "securityBundlePathMatches": true,
            "securityExecutablePathMatches": true,
            "processIdentifierPresent": true,
            "launchDatePresent": true,
            "sameLaunchInstance": true,
            "runtimeBundlePathMatchesExpected": process.bundle.path == expectedBundle.path
        ]
    }

    func matches(_ app: NSRunningApplication) -> Bool {
        process.matches(application) && process.matches(app)
    }

    // Used at document-open and cleanup boundaries. No resource inventory or
    // file hashing occurs here, or in the cheap checks during the held drag.
    func validate(_ app: NSRunningApplication) throws {
        guard matches(app) else { throw SameHostAppIdentityFailure.processIdentityChanged }
        try SameHostCodeValidation.checkDynamic(code, requirement: requirement)
        let staticCode = try SameHostCodeValidation.onDiskCode(for: code)
        let metadata = try SameHostCodeValidation.metadata(for: staticCode, failure: .runtimeCodeUnavailable)
        guard metadata.hash == codeHash else { throw SameHostAppIdentityFailure.runtimeCodeMismatch }
        guard process.matches(metadata) else { throw SameHostAppIdentityFailure.runtimeBundleLinkMismatch }
        guard matches(app) else { throw SameHostAppIdentityFailure.processIdentityChanged }
    }
}
