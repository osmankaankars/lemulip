#if SAME_HOST_REVIEW
import AppKit
import ApplicationServices
import CryptoKit
import Darwin
import Foundation

// Prebuilt, explicitly interactive diagnostics. No runtime compiler, network,
// event tap, global event monitor, screen capture, or permission request.
private enum SameHostKit {
    static let bundleIdentifier = "app.lemulip.SameHostDragReview"
    static let executable = "LemulipInputCheck"
    static let applicationIdentifier = "app.lemulip.NativeUIReview"
    static let applicationName = "Lemulip Native UI Review.app"
    static let applicationCommit = "d821d7343675e2850705d141ef9b3b93a6aee945"
    static let applicationTree = "425baa28f00ec24551dd70c0cc874a75fa3be0c1"
    static let observerBaseCommit = "c91b08e1f6f5293281e2b54423c53221a289ad90"
    static let cancellationFailure = "Escape did not cancel the actual Finder drag"
    static let manifestName = "kit-manifest.json"
    static let maximumFiles = 4_096
    static let maximumEntries = 8_192
    static let maximumFileBytes = 268_435_456
    static let maximumTotalBytes = 1_073_741_824
    static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "unsupported"
        #endif
    }
}

private enum SameHostHelperError: Error {
    case package, arguments, destination
}

// Only these fixed codes and a bounded enumeration index leave the verifier.
// Underlying errors, URLs, filenames and file contents are never exported.
private enum PackageVerificationCode: String, Sendable {
    case bundleIdentifier = "PV-B01", executableName = "PV-B02", executableURL = "PV-B03"
    case architecture = "PV-B04", resourcesURL = "PV-B05", payloadDirectory = "PV-B06"
    case reviewDirectory = "PV-P01", rootName = "PV-P02"
    case manifestDigest = "PV-M01", manifestJSON = "PV-M02", schema = "PV-M03"
    case diagnosticFlags = "PV-M04", applicationCommit = "PV-M05", applicationTree = "PV-M06"
    case observerBase = "PV-M07", helperCommit = "PV-M08", helperTree = "PV-M09"
    case observerHashFormat = "PV-M10", helperHashFormat = "PV-M11", guiHashFormat = "PV-M12"
    case fileMap = "PV-M13", pathLength = "PV-M14", pathCharacters = "PV-M15"
    case pathComponents = "PV-M16", fileHashFormat = "PV-M17"
    case enumerator = "PV-E01", entryCount = "PV-E02", entryMetadata = "PV-E03"
    case entrySymlink = "PV-E04", entryNormalization = "PV-E05", entryPrefix = "PV-E06"
    case entryRegular = "PV-E07", entryListed = "PV-E08", entryDigest = "PV-E09"
    case entrySizeAndHash = "PV-E10", entryDuplicate = "PV-E11", enumerationError = "PV-E12"
    case exactInventory = "PV-E13"
    case binaryHashLink = "PV-A01", provenanceListed = "PV-A02", appInfoDigest = "PV-A03"
    case appInfoParse = "PV-A04", appInfoDictionary = "PV-A05", appIdentifier = "PV-A06"
    case appExecutable = "PV-A07"
    case provenanceJSON = "PV-V01", provenanceCommit = "PV-V02", provenanceTree = "PV-V03"
    case provenanceHash = "PV-V04"
    case fixtureCount = "PV-F01", fixtureCandidate = "PV-F02", fixtureName = "PV-F03"
    case fixtureDigest = "PV-F04", fixtureRead = "PV-F05", fixtureContents = "PV-F06"
    case unclassified = "PV-U00"

    var stage: String {
        switch rawValue.prefix(4) {
        case "PV-B": return "bundle"
        case "PV-P": return "payload"
        case "PV-M": return "manifest"
        case "PV-E": return "entries"
        case "PV-A": return "application"
        case "PV-V": return "provenance"
        case "PV-F": return "fixtures"
        default: return "verification"
        }
    }

    var displayReason: String {
        switch self {
        case .entryNormalization: return "yol normalizasyonu"
        case .entryPrefix: return "paket içi yol sınırı"
        case .entrySymlink: return "sembolik bağlantı kontrolü"
        case .entrySizeAndHash: return "dosya boyutu veya özeti"
        case .exactInventory: return "dosya envanteri"
        default:
            switch stage {
            case "bundle": return "yardımcı uygulama kimliği"
            case "payload": return "paket dizini"
            case "manifest": return "paket manifesti"
            case "entries": return "paket dosyası kontrolü"
            case "application": return "tanı uygulaması kimliği"
            case "provenance": return "kaynak kimliği"
            case "fixtures": return "örnek dosyalar"
            default: return "doğrulama işlemi"
            }
        }
    }
}

private struct PackageVerificationFailure: Error {
    let code: PackageVerificationCode
    let entryIndex: Int?

    init(_ code: PackageVerificationCode, entryIndex: Int? = nil) {
        self.code = code
        self.entryIndex = entryIndex.flatMap { (0...(SameHostKit.maximumEntries + 1)).contains($0) ? $0 : nil }
    }

    var receipt: [String: Any] {
        var result: [String: Any] = ["status": "FAIL", "stage": code.stage, "code": code.rawValue]
        if let entryIndex { result["entryIndex"] = entryIndex }
        return result
    }
}

private func verificationOperation<T>(_ code: PackageVerificationCode, entryIndex: Int? = nil,
                                       _ operation: () throws -> T) throws -> T {
    do { return try operation() }
    catch let failure as PackageVerificationFailure { throw failure }
    catch { throw PackageVerificationFailure(code, entryIndex: entryIndex) }
}

private func kitRequire(_ condition: Bool, code: PackageVerificationCode? = nil, entryIndex: Int? = nil) throws {
    if !condition {
        if let code { throw PackageVerificationFailure(code, entryIndex: entryIndex) }
        throw SameHostHelperError.package
    }
}

private func exactBoolean(_ value: Any?, _ expected: Bool) -> Bool {
    guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return false }
    return number.boolValue == expected
}

private func boundedNumber(_ value: Any?, in range: ClosedRange<Double>) -> Double? {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
          number.doubleValue.isFinite, range.contains(number.doubleValue) else { return nil }
    return number.doubleValue
}

private func hexadecimal(_ value: String, count: Int) -> Bool {
    value.utf8.count == count && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
}

private func fileDigest(_ url: URL, maximum: Int) throws -> (String, Int) {
    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
    guard values.isRegularFile == true, values.isSymbolicLink == false,
          let size = values.fileSize, size >= 0, size <= maximum else { throw SameHostHelperError.package }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var digest = SHA256()
    var readBytes = 0
    while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
        readBytes += data.count
        guard readBytes <= maximum, readBytes <= size else { throw SameHostHelperError.package }
        digest.update(data: data)
    }
    guard readBytes == size else { throw SameHostHelperError.package }
    return (digest.finalize().map { String(format: "%02x", $0) }.joined(), size)
}

private func boundedJSON(_ url: URL, maximum: Int = 4_194_304) throws -> [String: Any] {
    _ = try fileDigest(url, maximum: maximum)
    let data = try Data(contentsOf: url)
    guard data.count <= maximum,
          let dictionary = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw SameHostHelperError.package
    }
    return dictionary
}

private func checkedDirectory(_ url: URL) throws {
    let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard values.isDirectory == true, values.isSymbolicLink == false else { throw SameHostHelperError.destination }
}

private func makeNewDirectory(_ url: URL) throws {
    guard !FileManager.default.fileExists(atPath: url.path) else { throw SameHostHelperError.destination }
    try checkedDirectory(url.deletingLastPathComponent())
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false,
                                            attributes: [.posixPermissions: 0o700])
    try checkedDirectory(url)
}

private func writeNewJSON(_ value: [String: Any], to url: URL) throws {
    try checkedDirectory(url.deletingLastPathComponent())
    let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url, options: .withoutOverwriting)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
}

private struct VerifiedSameHostPayload {
    let root: URL
    let manifest: [String: Any]
    let manifestDigest: String

    static func fromMainBundle() throws -> VerifiedSameHostPayload {
        try kitRequire(Bundle.main.bundleIdentifier == SameHostKit.bundleIdentifier, code: .bundleIdentifier)
        try kitRequire(Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String == SameHostKit.executable,
                       code: .executableName)
        try kitRequire(Bundle.main.executableURL?.lastPathComponent == SameHostKit.executable, code: .executableURL)
        try kitRequire(SameHostKit.architecture == "arm64", code: .architecture)
        guard let resources = Bundle.main.resourceURL else { throw PackageVerificationFailure(.resourcesURL) }
        let payload = resources.appendingPathComponent("Payload", isDirectory: true)
        try verificationOperation(.payloadDirectory) { try checkedDirectory(payload) }
        return try verify(payload.appendingPathComponent("lemulip-native-ui", isDirectory: true))
    }

    static func verify(_ proposedRoot: URL) throws -> VerifiedSameHostPayload {
        try verificationOperation(.reviewDirectory) { try checkedDirectory(proposedRoot) }
        let root = proposedRoot.standardizedFileURL.resolvingSymlinksInPath()
        try kitRequire(root.lastPathComponent == "lemulip-native-ui", code: .rootName)
        let manifestURL = root.appendingPathComponent(SameHostKit.manifestName)
        let digest = try verificationOperation(.manifestDigest) { try fileDigest(manifestURL, maximum: 2_097_152).0 }
        let manifest = try verificationOperation(.manifestJSON) { try boundedJSON(manifestURL, maximum: 2_097_152) }
        try kitRequire(boundedNumber(manifest["schema"], in: 1...1) == 1, code: .schema)
        try kitRequire(exactBoolean(manifest["diagnosticOnly"], true) && exactBoolean(manifest["releaseReady"], false),
                       code: .diagnosticFlags)
        try kitRequire(manifest["applicationCommit"] as? String == SameHostKit.applicationCommit, code: .applicationCommit)
        try kitRequire(manifest["applicationTree"] as? String == SameHostKit.applicationTree, code: .applicationTree)
        try kitRequire(manifest["observerBaseCommit"] as? String == SameHostKit.observerBaseCommit, code: .observerBase)
        for key in ["helperCommit", "helperTree"] {
            if key == "helperTree" && manifest[key] == nil { continue }
            guard let value = manifest[key] as? String, hexadecimal(value, count: 40) else {
                throw PackageVerificationFailure(key == "helperCommit" ? .helperCommit : .helperTree)
            }
        }
        for key in ["observerSourceSHA256", "helperSourceSHA256", "stagedGUI_SHA256"] {
            guard let value = manifest[key] as? String, hexadecimal(value, count: 64) else {
                throw PackageVerificationFailure(key == "observerSourceSHA256" ? .observerHashFormat
                    : (key == "helperSourceSHA256" ? .helperHashFormat : .guiHashFormat))
            }
        }
        guard let files = manifest["files"] as? [String: String],
              !files.isEmpty, files.count <= SameHostKit.maximumFiles else { throw PackageVerificationFailure(.fileMap) }
        for (path, hash) in files {
            let parts = path.split(separator: "/", omittingEmptySubsequences: false)
            try kitRequire(!parts.isEmpty && path.utf8.count <= 1_024 && path != SameHostKit.manifestName, code: .pathLength)
            try kitRequire(!path.contains("\\") && !path.unicodeScalars.contains { $0.value < 32 || $0.value == 127 },
                           code: .pathCharacters)
            try kitRequire(parts.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }, code: .pathComponents)
            try kitRequire(hexadecimal(hash, count: 64), code: .fileHashFormat)
        }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        var enumerationFailed = false
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                              options: [], errorHandler: { _, _ in
            enumerationFailed = true
            return false
        }) else { throw PackageVerificationFailure(.enumerator) }
        var observed: Set<String> = []
        var entries = 0
        var totalBytes = 0
        let prefix = root.path + "/"
        for case let entry as URL in enumerator {
            entries += 1
            try kitRequire(entries <= SameHostKit.maximumEntries, code: .entryCount, entryIndex: entries)
            let values = try verificationOperation(.entryMetadata, entryIndex: entries) {
                try entry.resourceValues(forKeys: Set(keys))
            }
            try kitRequire(values.isSymbolicLink == false, code: .entrySymlink, entryIndex: entries)
            try kitRequire(entry.standardizedFileURL.path == entry.resolvingSymlinksInPath().path,
                           code: .entryNormalization, entryIndex: entries)
            // An enumerator can return /private/var while the resolved root uses /var.
            // Compare and slice the same resolved spelling; retain all entry guards.
            let resolvedEntry = entry.resolvingSymlinksInPath()
            try kitRequire(resolvedEntry.path.hasPrefix(prefix), code: .entryPrefix, entryIndex: entries)
            if values.isDirectory == true { continue }
            try kitRequire(values.isRegularFile == true, code: .entryRegular, entryIndex: entries)
            let relative = String(resolvedEntry.path.dropFirst(prefix.count))
            if relative == SameHostKit.manifestName { continue }
            guard let expected = files[relative] else { throw PackageVerificationFailure(.entryListed, entryIndex: entries) }
            let (actual, bytes) = try verificationOperation(.entryDigest, entryIndex: entries) {
                try fileDigest(entry, maximum: SameHostKit.maximumFileBytes)
            }
            totalBytes += bytes
            try kitRequire(totalBytes <= SameHostKit.maximumTotalBytes && actual == expected,
                           code: .entrySizeAndHash, entryIndex: entries)
            try kitRequire(observed.insert(relative).inserted, code: .entryDuplicate, entryIndex: entries)
        }
        try kitRequire(!enumerationFailed && observed == Set(files.keys),
                       code: enumerationFailed ? .enumerationError : .exactInventory)
        let binaryPath = SameHostKit.applicationName + "/Contents/MacOS/Lemulip"
        try kitRequire(files[binaryPath] == manifest["stagedGUI_SHA256"] as? String, code: .binaryHashLink)
        try kitRequire(files["provenance.json"] != nil, code: .provenanceListed)
        let appInfo = root.appendingPathComponent(SameHostKit.applicationName + "/Contents/Info.plist")
        _ = try verificationOperation(.appInfoDigest) { try fileDigest(appInfo, maximum: 262_144) }
        let plist = try verificationOperation(.appInfoParse) {
            try PropertyListSerialization.propertyList(from: Data(contentsOf: appInfo), options: [], format: nil)
        }
        guard let info = plist as? [String: Any] else { throw PackageVerificationFailure(.appInfoDictionary) }
        try kitRequire(info["CFBundleIdentifier"] as? String == SameHostKit.applicationIdentifier, code: .appIdentifier)
        try kitRequire(info["CFBundleExecutable"] as? String == "Lemulip", code: .appExecutable)
        let provenance = try verificationOperation(.provenanceJSON) {
            try boundedJSON(root.appendingPathComponent("provenance.json"))
        }
        try kitRequire(provenance["sourceCommit"] as? String == SameHostKit.applicationCommit, code: .provenanceCommit)
        try kitRequire(provenance["sourceTree"] as? String == SameHostKit.applicationTree, code: .provenanceTree)
        try kitRequire(provenance["stagedGUI_SHA256"] as? String == manifest["stagedGUI_SHA256"] as? String,
                       code: .provenanceHash)
        let fixturePrefix = "Fixtures/FinderDrop/orchard/"
        let fixturePaths = files.keys.filter { $0.hasPrefix(fixturePrefix) }
        try kitRequire(fixturePaths.count == 4, code: .fixtureCount)
        for role in ["Existing", "Single", "Multi-A", "Multi-B"] {
            let candidates = fixturePaths.filter { $0.hasPrefix(fixturePrefix + role + "-") && $0.hasSuffix(".txt") }
            try kitRequire(candidates.count == 1, code: .fixtureCandidate)
            let name = String(candidates[0].dropFirst(fixturePrefix.count))
            let token = String(name.dropFirst(role.count + 1).dropLast(4))
            try kitRequire(hexadecimal(token, count: 32), code: .fixtureName)
            let fixture = root.appendingPathComponent(candidates[0])
            _ = try verificationOperation(.fixtureDigest) { try fileDigest(fixture, maximum: 65_535) }
            try verificationOperation(.fixtureRead) {
                try kitRequire(try Data(contentsOf: fixture) == Data("Synthetic Finder input: orchard, \(role). Preserve these bytes.\n".utf8),
                               code: .fixtureContents)
            }
        }
        return VerifiedSameHostPayload(root: root, manifest: manifest, manifestDigest: digest)
    }

    func identityRecord() -> [String: Any] {
        var result: [String: Any] = ["sourceCommit": SameHostKit.applicationCommit,
                                   "sourceTree": SameHostKit.applicationTree,
                                   "observerBaseCommit": SameHostKit.observerBaseCommit,
                                   "architecture": SameHostKit.architecture]
        for key in ["helperCommit", "helperTree", "observerSourceSHA256", "helperSourceSHA256", "stagedGUI_SHA256"] {
            if let value = manifest[key] as? String { result[key] = value }
        }
        return result
    }
}

private struct SameHostPackageLoad {
    let payload: VerifiedSameHostPayload?
    let failure: PackageVerificationFailure?

    static func fromMainBundle() -> SameHostPackageLoad {
        do { return SameHostPackageLoad(payload: try VerifiedSameHostPayload.fromMainBundle(), failure: nil) }
        catch let failure as PackageVerificationFailure { return SameHostPackageLoad(payload: nil, failure: failure) }
        catch { return SameHostPackageLoad(payload: nil, failure: PackageVerificationFailure(.unclassified)) }
    }

    var receipt: [String: Any] {
        failure?.receipt ?? ["status": "PASS", "stage": "complete", "code": "ok"]
    }
}

private enum SameHostLaunchMode {
    case interactive
    case verify
    case smoke(URL)
    case ciBaseline(URL)
    case ciHumanTimeout(URL)

    static func parse(_ arguments: [String]) throws -> SameHostLaunchMode {
        if arguments.isEmpty { return .interactive }
        if arguments == ["--verify-package"] { return .verify }
        guard arguments.count == 2, !arguments[1].isEmpty else { throw SameHostHelperError.arguments }
        let destination = URL(fileURLWithPath: arguments[1]).standardizedFileURL
        switch arguments[0] {
        case "--smoke-ui": return .smoke(destination)
        case "--ci-baseline": return .ciBaseline(destination)
        case "--ci-human-timeout": return .ciHumanTimeout(destination)
        default: throw SameHostHelperError.arguments
        }
    }

    var isInteractive: Bool { if case .interactive = self { return true }; return false }
    var isSmoke: Bool { if case .smoke = self { return true }; return false }
}

private enum SameHostPhase: String {
    case baseline, physical, replay
    var title: String {
        switch self {
        case .baseline: return "Otomatik Escape"
        case .physical: return "Sizin Escape tuşunuz"
        case .replay: return "Aynı bekleme süreleriyle otomatik Escape"
        }
    }
}

private struct SameHostCaseResult {
    let phase: SameHostPhase
    var record: [String: Any]
    let reportRetained: Bool

    var cleanupCompleted: Bool {
        guard let cleanup = record["cleanup"] as? [String: Any] else { return false }
        return exactBoolean(cleanup["completed"], true)
            && exactBoolean(cleanup["leftButtonReportedDown"], false)
            && exactBoolean(cleanup["applicationStopped"], true)
            && exactBoolean(cleanup["fixtureFinderWindowClosed"], true)
            && exactBoolean(cleanup["fixedBundleRegistryEmpty"], true)
            && (cleanup["errors"] as? [String])?.isEmpty == true
    }

    var initialWorkspaceCorrect: Bool {
        let observations = (record["escapeObservations"] as? [[String: Any]] ?? []).filter { $0["phase"] as? String == "before-key" }
        guard observations.count == 1, let workspace = observations[0]["workspace"] as? [String: Any],
              let names = workspace["observedFilenames"] as? [String], names.count == 1 else { return false }
        let name = names[0]
        guard name.hasPrefix("Existing-"), name.hasSuffix(".txt"),
              hexadecimal(String(name.dropFirst(9).dropLast(4)), count: 32) else { return false }
        return exactBoolean(workspace["matchesExpectedWorkspace"], true)
            && workspace["selectedCountLabels"] as? [String] == ["1 Selected"]
    }

    var cancellation: Bool? {
        guard let workspace = record["escapeCancellation"] as? [String: Any] else { return nil }
        if exactBoolean(workspace["matchesExpectedWorkspace"], true) { return true }
        if exactBoolean(workspace["matchesExpectedWorkspace"], false) { return false }
        return nil
    }

    var normalDropVerified: Bool {
        let stages = record["stages"] as? [[String: Any]] ?? []
        return exactBoolean(record["gestureOutcomesVerified"], true)
            && stages.contains { $0["stage"] as? String == "06-after-accepted-drop" }
            && exactBoolean(record["originalBytesUnchanged"], true)
            && exactBoolean(record["userFileSetUnchanged"], true)
    }

    var passed: Bool {
        record["status"] as? String == "captured" && initialWorkspaceCorrect && cancellation == true
            && normalDropVerified && cleanupCompleted && reportRetained
    }

    var specificCancellationFailure: Bool {
        record["status"] as? String == "failed"
            && record["reason"] as? String == SameHostKit.cancellationFailure
            && cancellation == false && initialWorkspaceCorrect && cleanupCompleted && reportRetained
    }

    var replayTiming: (Double, Double)? {
        guard passed, let escape = record["sameHostEscape"] as? [String: Any],
              escape["mode"] as? String == "external",
              escape["status"] as? String == "observed-external-pair",
              boundedNumber(escape["syntheticEscapePosts"], in: 0...0) == 0,
              let wait = boundedNumber(escape["downWaitSeconds"], in: 0...12),
              let held = boundedNumber(escape["heldSeconds"], in: 0.15...4) else { return nil }
        return (wait, held)
    }

    var safeErrorCode: String {
        if !cleanupCompleted { return "cleanup-incomplete" }
        if !reportRetained { return "report-not-retained" }
        return primaryErrorCode
    }

    // Preserve the original stop reason even when cleanup changes the final status.
    var primaryErrorCode: String {
        switch record["reason"] as? String {
        case "The launch did not produce the exact staged app": return "launch-identity-mismatch"
        case "Opening the initial fixture did not reuse the exact staged app": return "document-open-identity-mismatch"
        case SameHostKit.cancellationFailure: return "escape-cancellation-failed"
        case "Existing authorization is insufficient; no permission was requested or changed",
             "Existing event-post authorization is unavailable",
             "Existing permission to release the owned mouse is unavailable": return "permission-unavailable"
        default: break
        }
        if passed { return "none" }
        if record["helperCancelled"] as? Bool == true { return "cancelled" }
        let escape = record["sameHostEscape"] as? [String: Any] ?? [:]
        switch escape["status"] as? String {
        case "timed-out-waiting-down": return "escape-down-not-observed"
        case "timed-out-waiting-up": return "escape-up-not-observed"
        default: break
        }
        let preflight = record["preflight"] as? [String: Any] ?? [:]
        if exactBoolean(preflight["accessibility"], false) || exactBoolean(preflight["postEvents"], false) {
            return "permission-unavailable"
        }
        return "diagnostic-stopped"
    }

    var safeStartupPhase: String? {
        guard let phase = record["startupPhase"] as? String,
              ["keyboard-driver", "application-launch", "launch-identity", "application-window",
               "initial-workspace", "fixture-finder-window", "finder-icons", "target-geometry", "complete"].contains(phase)
        else { return nil }
        return phase
    }

    var cleanupErrorCodes: [String] {
        let cleanup = record["cleanup"] as? [String: Any] ?? [:]
        return (cleanup["errors"] as? [String] ?? []).prefix(64).map { error in
            switch error {
            case "Refusing to terminate an application whose staged identity changed": return "cleanup-identity-mismatch"
            case "The staged app did not terminate before the cleanup deadline": return "cleanup-application-still-running"
            case "The fixed review bundle remains registered as running": return "cleanup-registry-not-empty"
            default: return "cleanup-other-error"
            }
        }
    }

    var failureDetail: String {
        let cleanupCodes = cleanupErrorCodes
        let cleanupDetail = cleanupCodes.isEmpty ? "" : " (" + cleanupCodes.joined(separator: ", ") + ")"
        return "İlk durma kodu: \(primaryErrorDescription). Başlangıç aşaması: \(safeStartupPhase ?? "unavailable"). "
            + "Temizleme: \(cleanupCompleted ? "tamamlandı" : "tamamlanmadı")\(cleanupDetail)."
    }

    var primaryErrorDescription: String {
        primaryErrorCode == "diagnostic-stopped" ? "diagnostic-stopped (ilk neden sınıflandırılamadı)" : primaryErrorCode
    }

    private func safeBooleans(_ value: Any?, keys: [String]) -> [String: Any] {
        let source = value as? [String: Any] ?? [:]
        var result: [String: Any] = [:]
        for key in keys {
            if exactBoolean(source[key], true) { result[key] = true }
            else if exactBoolean(source[key], false) { result[key] = false }
        }
        return result
    }

    func shareableSummary() -> [String: Any] {
        var summary: [String: Any] = [
            "phase": phase.rawValue, "passed": passed, "reportRetained": reportRetained,
            "initialWorkspaceCorrect": initialWorkspaceCorrect,
            "normalDropVerified": normalDropVerified, "errorCode": safeErrorCode,
            "primaryErrorCode": primaryErrorCode,
            "physicalInputVerified": false, "imagesCaptured": false
        ]
        if let safeStartupPhase { summary["startupPhase"] = safeStartupPhase }
        summary["preflight"] = safeBooleans(record["preflight"], keys: ["accessibility", "postEvents"])
        let identityKeys = ["bundleIdentifierMatches", "bundleURLPresent", "resolvedBundlePathMatches",
                            "bundlePathHasTranslocationComponent", "requestedFreshInstance", "allowsRunningApplicationSubstitution"]
        if record["launchIdentity"] != nil {
            summary["launchIdentity"] = safeBooleans(record["launchIdentity"], keys: identityKeys)
        }
        if record["documentOpenIdentity"] != nil {
            summary["documentOpenIdentity"] = safeBooleans(record["documentOpenIdentity"], keys: identityKeys + ["sameProcessAsLaunched"])
        }
        if let cancellation { summary["escapeCancelled"] = cancellation }
        let status = record["status"] as? String ?? "failed"
        summary["status"] = ["captured", "failed", "blocked", "cancelled"].contains(status) ? status : "failed"
        let cleanup = record["cleanup"] as? [String: Any] ?? [:]
        var safeCleanup: [String: Any] = [:]
        for key in ["completed", "leftButtonReportedDown", "applicationStopped", "fixtureFinderWindowClosed", "fixedBundleRegistryEmpty"] {
            if exactBoolean(cleanup[key], true) { safeCleanup[key] = true }
            else if exactBoolean(cleanup[key], false) { safeCleanup[key] = false }
        }
        safeCleanup["errorCount"] = (cleanup["errors"] as? [String] ?? []).count
        safeCleanup["errorCodes"] = cleanupErrorCodes
        summary["cleanup"] = safeCleanup
        let escape = record["sameHostEscape"] as? [String: Any] ?? [:]
        var safeEscape: [String: Any] = ["hardwareProvenanceVerified": false, "stateObservationIsDeliveryAcknowledgement": false]
        if let mode = escape["mode"] as? String, ["automatic", "external"].contains(mode) { safeEscape["mode"] = mode }
        for key in ["leadInSeconds", "dwellSeconds", "externalDownTimeoutSeconds", "externalUpTimeoutSeconds",
                    "downWaitSeconds", "heldSeconds", "motionDelaySeconds", "syntheticEscapePosts"] {
            if let number = boundedNumber(escape[key], in: 0...120) { safeEscape[key] = number }
        }
        summary["escape"] = safeEscape
        var flagRecords: [[String: Any]] = []
        for entry in (record["mouseEvents"] as? [[String: Any]] ?? []).prefix(256) {
            var flags: [String: Any] = [:]
            for key in ["eventType", "sourceStateID", "constructorFlags", "sessionFlagsBeforePost", "postedFlags"] {
                if boundedNumber(entry[key], in: 0...Double(UInt64.max)) != nil { flags[key] = entry[key] }
            }
            if !flags.isEmpty { flagRecords.append(flags) }
        }
        summary["pointerFlags"] = flagRecords
        var states: [[String: Any]] = []
        for entry in (record["escapeInputStates"] as? [[String: Any]] ?? []).prefix(64) {
            var state: [String: Any] = [:]
            for key in ["mouseDownSent", "leftButtonReportedDown", "hidLeftButtonReportedDown", "escapeKeyDownSent",
                        "escapeKeyReportedDown", "hidEscapeKeyReportedDown"] {
                if exactBoolean(entry[key], true) { state[key] = true }
                else if exactBoolean(entry[key], false) { state[key] = false }
            }
            let modifiers = entry["modifiers"] as? [String: Any] ?? [:]
            for key in ["sessionFlags", "relevantFlags"] {
                if boundedNumber(modifiers[key], in: 0...Double(UInt64.max)) != nil { state[key] = modifiers[key] }
            }
            if !state.isEmpty { states.append(state) }
        }
        summary["inputStates"] = states
        return summary
    }
}

@MainActor
private enum SameHostCaseRunner {
    static func run(payload: VerifiedSameHostPayload, session: URL, phase: SameHostPhase,
                    options: SameHostDragOptions) async -> SameHostCaseResult {
        var initial: [String: Any] = payload.identityRecord()
        initial.merge(["status": "blocked", "theme": "orchard", "targetKind": "production",
                       "gestureOutcomesVerified": false, "helperPhase": phase.rawValue,
                       "diagnosticOnly": true, "releaseReady": false], uniquingKeysWith: { _, new in new })
        let stage: URL
        do {
            try Task.checkCancellation()
            guard NSRunningApplication.runningApplications(withBundleIdentifier: SameHostKit.applicationIdentifier).isEmpty else {
                throw SameHostHelperError.destination
            }
            let parent = session.appendingPathComponent(phase.rawValue, isDirectory: true)
            try makeNewDirectory(parent)
            stage = parent.appendingPathComponent("lemulip-native-ui", isDirectory: true)
            try FileManager.default.copyItem(at: payload.root, to: stage)
            let copied = try VerifiedSameHostPayload.verify(stage)
            try kitRequire(copied.manifestDigest == payload.manifestDigest)
            try makeNewDirectory(stage.appendingPathComponent("NativeDragEvidence", isDirectory: true))
            try Task.checkCancellation()
        } catch {
            initial["reason"] = "The same-host helper stopped before starting a diagnostic case"
            initial["helperCancelled"] = error is CancellationError
            if let failure = error as? PackageVerificationFailure { initial["verification"] = failure.receipt }
            initial["cleanup"] = ["completed": true, "leftButtonReportedDown": false,
                                  "applicationStopped": true, "fixtureFinderWindowClosed": true,
                                  "fixedBundleRegistryEmpty": NSRunningApplication.runningApplications(withBundleIdentifier: SameHostKit.applicationIdentifier).isEmpty,
                                  "errors": [String]()]
            return SameHostCaseResult(phase: phase, record: initial, reportRetained: false)
        }
        let review = DragReview(directory: stage, theme: .orchard, target: .production, sameHost: options)
        review.record.merge(initial, uniquingKeysWith: { _, new in new })
        do { try await review.run() }
        catch let issue as DragReviewIssue {
            switch issue {
            case .blocked: review.record["status"] = "blocked"
            case .failed: review.record["status"] = "failed"
            }
            review.record["reason"] = issue.description
        } catch is CancellationError {
            review.record["status"] = "blocked"
            review.record["reason"] = "The user cancelled the same-host diagnostic"
            review.record["helperCancelled"] = true
        } catch {
            review.record["status"] = "failed"
            review.record["reason"] = "The same-host diagnostic could not complete"
        }
        // This unstructured task deliberately has its own cancellation state.
        // Closing the helper must not cancel cleanup of the input it owns.
        let cleanup = Task { @MainActor in await review.cleanUp() }
        let cleaned = await cleanup.value
        if !cleaned {
            review.record["status"] = "failed"
            review.record["helperCleanupFailed"] = true
        }
        var retained = false
        do {
            try review.finish()
            let report = try boundedJSON(stage.appendingPathComponent("NativeDragEvidence/orchard/report.json"))
            retained = report["sourceCommit"] as? String == SameHostKit.applicationCommit
                && report["helperPhase"] as? String == phase.rawValue
        } catch {
            review.record["reportError"] = "The local diagnostic report could not be retained"
        }
        return SameHostCaseResult(phase: phase, record: review.record, reportRetained: retained)
    }
}

@MainActor
private final class SameHostCuePanel: NSPanel {
    private let cue = NSTextField(labelWithString: "")
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    static func make() -> SameHostCuePanel {
        let panel = SameHostCuePanel(contentRect: NSRect(x: 0, y: 0, width: 760, height: 40),
                                    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.configure()
        return panel
    }

    private func configure() {
        isFloatingPanel = true
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.97)
        isOpaque = false
        hasShadow = true
        cue.font = .systemFont(ofSize: 14, weight: .semibold)
        cue.alignment = .center
        cue.lineBreakMode = .byTruncatingTail
        cue.translatesAutoresizingMaskIntoConstraints = false
        contentView?.addSubview(cue)
        if let contentView {
            NSLayoutConstraint.activate([
                cue.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
                cue.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
                cue.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
            ])
        }
    }

    func show(_ message: String, audible: Bool = false) {
        guard let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == CGMainDisplayID()
        }) ?? NSScreen.main else { return }
        let width = min(900, screen.frame.width - 32)
        setFrame(NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - 72,
                        width: width, height: 40), display: false)
        cue.stringValue = message
        orderFrontRegardless()
        if audible { NSSound.beep() }
    }
}

@MainActor
private final class SameHostApplication: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let mode: SameHostLaunchMode
    private var packageLoad: SameHostPackageLoad
    private var payload: VerifiedSameHostPayload? { packageLoad.payload }
    private var window: NSWindow?
    private var statusLabel = NSTextField(wrappingLabelWithString: "")
    private var permissionLabel = NSTextField(wrappingLabelWithString: "")
    private var startButton = NSButton()
    private var refreshButton = NSButton()
    private var resultButton = NSButton()
    private var cuePanel: SameHostCuePanel?
    private var task: Task<Void, Never>?
    private var terminationPending = false
    private var inputCleanupBlocked = false
    private var latestResult: URL?
    private var latestFailureDetail = ""
    private var activePhase = SameHostPhase.baseline

    init(mode: SameHostLaunchMode, packageLoad: SameHostPackageLoad) {
        self.mode = mode
        self.packageLoad = packageLoad
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        switch mode {
        case .interactive, .smoke:
            buildWindow()
            refreshPermissions()
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            if case .smoke(let output) = mode { beginSmoke(output) }
        case .ciBaseline(let output): beginCI(output: output, external: false)
        case .ciHumanTimeout(let output): beginCI(output: output, external: true)
        case .verify: break
        }
    }

    private func buildWindow() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 690, height: 570),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Lemulip Giriş Karşılaştırması"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        let title = NSTextField(labelWithString: "Escape davranışını aynı Mac’te karşılaştırın")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        let overview = NSTextField(wrappingLabelWithString:
            "Önce Finder sürüklemesi ve otomatik Escape denenir. İptal sorunu burada da oluşursa ikinci turda sizin Escape tuşunuz kullanılır.")
        let instructions = NSTextField(wrappingLabelWithString:
            "Başlat’tan sonra fareye dokunmayın. Üstteki işaret “ESCAPE’E BASILI TUTUN” dediğinde Escape’e basılı tutun; “ESCAPE’İ BIRAKIN” dediğinde bırakın. Otomatik turlarda klavyeye de dokunmayın.")
        let scope = NSTextField(wrappingLabelWithString:
            "Ekran görüntüsü alınmaz ve genel tuş akışı dinlenmez. Yalnız bu kısa test sırasında Escape’in basılı/bırakılmış durumu kontrol edilir. Sonuç yerel olarak kaydedilir.")
        scope.textColor = .secondaryLabelColor
        for label in [overview, instructions, scope, permissionLabel, statusLabel] {
            label.font = .systemFont(ofSize: 13)
            label.maximumNumberOfLines = 0
            label.setContentCompressionResistancePriority(.required, for: .vertical)
        }
        permissionLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        startButton = NSButton(title: "Başlat", target: self, action: #selector(startPressed(_:)))
        refreshButton = NSButton(title: "İzinleri Yenile", target: self, action: #selector(refreshPressed(_:)))
        resultButton = NSButton(title: "Sonucu Göster", target: self, action: #selector(showResult(_:)))
        let quit = NSButton(title: "Çıkış", target: self, action: #selector(quitPressed(_:)))
        for button in [startButton, refreshButton, resultButton, quit] { button.bezelStyle = .rounded }
        resultButton.isEnabled = false
        let buttons = NSStackView(views: [startButton, refreshButton, resultButton, quit])
        buttons.orientation = .horizontal
        buttons.spacing = 10
        let stack = NSStackView(views: [title, overview, instructions, scope, permissionLabel, statusLabel, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        guard let content = window.contentView else { return }
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 26),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -26),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 26),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -22)
        ])
        for label in [overview, instructions, scope, permissionLabel, statusLabel] {
            label.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        let menu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu()
        let quitItem = NSMenuItem(title: "Lemulip Input Check’ten Çık", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        applicationMenu.addItem(quitItem)
        applicationItem.submenu = applicationMenu
        menu.addItem(applicationItem)
        NSApp.mainMenu = menu
    }

    private func refreshPermissions() {
        let accessibility = AXIsProcessTrusted()
        let posting = CGPreflightPostEventAccess()
        let oldReview = !NSRunningApplication.runningApplications(withBundleIdentifier: SameHostKit.applicationIdentifier).isEmpty
        let failureDetail = latestFailureDetail.isEmpty ? "" : " " + latestFailureDetail
        permissionLabel.stringValue = "Erişilebilirlik: \(accessibility ? "hazır" : "eksik") · Giriş gönderme: \(posting ? "hazır" : "eksik")"
        startButton.isEnabled = mode.isInteractive && task == nil && payload != nil && accessibility && posting
            && !oldReview && !inputCleanupBlocked
        refreshButton.isEnabled = task == nil
        if payload == nil {
            let failure = packageLoad.failure ?? PackageVerificationFailure(.unclassified)
            statusLabel.stringValue = "Paket doğrulanamadı — \(failure.code.rawValue) (\(failure.code.displayReason)). Kontrol başlatılmadı. Bu kodu paylaşabilirsiniz."
        } else if mode.isSmoke {
            statusLabel.stringValue = "Arayüz açılışı kontrol ediliyor. Başlat devre dışı; hiçbir fare veya klavye girdisi gönderilmeyecek."
        } else if inputCleanupBlocked {
            statusLabel.stringValue = latestFailureDetail + " Giriş temizliği tamamen doğrulanamadığı için yeni tur başlatılmayacak. Escape’e basılıysanız bırakın. Sonucu Göster’den ayrıntıları inceleyebilirsiniz."
        } else if !accessibility {
            statusLabel.stringValue = "Sistem Ayarları > Gizlilik ve Güvenlik > Erişilebilirlik bölümüne Lemulip Input Check’i (LemulipInputCheck) ekleyip etkinleştirin; sonra bu uygulamayı kapatıp aynı kopyayı yeniden açın. Terminal’e izin vermeniz gerekmez." + failureDetail
        } else if !posting {
            statusLabel.stringValue = "Erişilebilirlik hazır; bu çalışan süreç için giriş gönderme kontrolü henüz geçmedi. Bu uygulamayı kapatıp aynı kopyayı yeniden açın ve İzinleri Yenile’yi seçin." + failureDetail
        } else if oldReview {
            statusLabel.stringValue = "Önce açık Lemulip Native UI Review uygulamasını kapatın, ardından İzinleri Yenile’yi seçin. Açık olan bu kopya kontrol tarafından kapatılmaz." + failureDetail
        } else if latestResult == nil && latestFailureDetail.isEmpty {
            statusLabel.stringValue = "Hazır. Bu bir tanı kontrolüdür; sürüm onayı veya fiziksel girişin donanım doğrulaması değildir."
        }
    }

    @objc private func refreshPressed(_ sender: Any?) {
        guard task == nil else { return }
        packageLoad = SameHostPackageLoad.fromMainBundle()
        refreshPermissions()
    }

    @objc private func startPressed(_ sender: Any?) {
        guard mode.isInteractive, task == nil else { return }
        packageLoad = SameHostPackageLoad.fromMainBundle()
        refreshPermissions()
        guard startButton.isEnabled, let payload else { return }
        latestFailureDetail = ""
        startButton.isEnabled = false
        refreshButton.isEnabled = false
        resultButton.isEnabled = false
        window?.orderOut(nil)
        cuePanel = SameHostCuePanel.make()
        cuePanel?.show("Otomatik kontrol başlıyor — fareye ve klavyeye dokunmayın")
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runInteractive(payload)
            self.completeInteractiveRun()
        }
    }

    private func options(external: Bool, leadIn: Double = 0, dwell: Double = 0.15,
                         displayPrompts: Bool) -> SameHostDragOptions {
        var options = SameHostDragOptions()
        options.escapeInput = external ? .external : .automatic
        options.leadInSeconds = leadIn
        options.dwellSeconds = dwell
        options.externalDownTimeoutSeconds = 12
        options.externalUpTimeoutSeconds = 4
        if displayPrompts {
            options.onPrompt = { [weak self] prompt in self?.showPrompt(prompt) }
        }
        return options
    }

    private func showPrompt(_ prompt: String) {
        if terminationPending {
            cuePanel?.show("Kontrol durduruluyor — Escape’e basılıysanız bırakın; fareye dokunmayın")
            return
        }
        switch prompt {
        case "press-escape": cuePanel?.show("ESCAPE’E BASILI TUTUN — bırak işaretini bekleyin; fareye dokunmayın", audible: true)
        case "release-escape": cuePanel?.show("ESCAPE’İ ŞİMDİ BIRAKIN — fareye dokunmayın", audible: true)
        case "settling": cuePanel?.show("Sonuç kontrol ediliyor — fareye ve klavyeye dokunmayın")
        case "dragging": cuePanel?.show(activePhase == .physical
            ? "Sürükleme hazırlanıyor — Escape işaretini bekleyin; fareye dokunmayın"
            : "Otomatik sürükleme sürüyor — fareye ve klavyeye dokunmayın")
        default: cuePanel?.show(activePhase.title + " hazırlanıyor — fareye ve klavyeye dokunmayın")
        }
    }

    private func runInteractive(_ payload: VerifiedSameHostPayload) async {
        var cases: [SameHostCaseResult] = []
        var outcome = "not-started"
        do {
            let session = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
                .appendingPathComponent("LemulipInputCheck-" + UUID().uuidString, isDirectory: true)
            try makeNewDirectory(session)
            activePhase = .baseline
            let baseline = await SameHostCaseRunner.run(payload: payload, session: session, phase: .baseline,
                options: options(external: false, displayPrompts: true))
            cases.append(baseline)
            if Task.isCancelled { outcome = "cancelled" }
            else if !baseline.cleanupCompleted || !baseline.reportRetained { outcome = "baseline-incomplete" }
            else if baseline.passed { outcome = "baseline-passed-physical-skipped" }
            else if !baseline.specificCancellationFailure { outcome = "baseline-did-not-reach-comparison" }
            else {
                activePhase = .physical
                showPrompt("preparing")
                let physical = await SameHostCaseRunner.run(payload: payload, session: session, phase: .physical,
                    options: options(external: true, displayPrompts: true))
                cases.append(physical)
                if Task.isCancelled { outcome = "cancelled" }
                else if !physical.cleanupCompleted || !physical.reportRetained { outcome = "physical-incomplete" }
                else if !physical.passed { outcome = physical.specificCancellationFailure ? "both-cancellation-failed" : "physical-not-completed" }
                else if let (wait, held) = physical.replayTiming {
                    activePhase = .replay
                    showPrompt("preparing")
                    let replay = await SameHostCaseRunner.run(payload: payload, session: session, phase: .replay,
                        options: options(external: false, leadIn: wait, dwell: held, displayPrompts: true))
                    cases.append(replay)
                    if Task.isCancelled { outcome = "cancelled" }
                    else if !replay.cleanupCompleted || !replay.reportRetained { outcome = "replay-incomplete" }
                    else if replay.passed { outcome = "physical-and-timing-replay-passed" }
                    else if replay.specificCancellationFailure { outcome = "physical-passed-timing-replay-failed" }
                    else { outcome = "replay-not-completed" }
                } else { outcome = "physical-passed-timing-out-of-range" }
            }
        } catch is CancellationError { outcome = "cancelled" }
        catch { outcome = "helper-startup-failed" }
        inputCleanupBlocked = cases.contains { !$0.cleanupCompleted }
        latestFailureDetail = cases.last.map { $0.passed ? "" : $0.failureDetail } ?? ""
        let failureDetail = latestFailureDetail.isEmpty ? "" : " " + latestFailureDetail
        do {
            latestResult = try retainShareableResult(payload: payload, cases: cases, outcome: outcome)
            statusLabel.stringValue = outcomeMessage(outcome) + failureDetail + " Sonucu Göster ile yerel TXT özetini açabilirsiniz."
        } catch {
            latestResult = nil
            statusLabel.stringValue = outcomeMessage(outcome) + failureDetail + " Sonuç dosyası kaydedilemedi."
        }
    }

    private func outcomeMessage(_ outcome: String) -> String {
        switch outcome {
        case "baseline-passed-physical-skipped":
            return "Otomatik Escape bu Mac’te iptal etti ve yeni normal bırakma doğrulandı. Sorun tekrar oluşmadığından fiziksel tur atlandı."
        case "physical-and-timing-replay-passed":
            return "Sizin Escape’iniz ve gözlenen bekleme süreleriyle otomatik tekrar başarılı oldu. Bekleme süresi sonuçla ilişkili olabilir; kaynak farkı tek başına ayrıştırılmadı."
        case "physical-passed-timing-replay-failed":
            return "Sizin Escape’iniz iptal etti; aynı gözlenen sürelerle otomatik tekrar iptal etmedi. Bu, bu Mac’te gözlenen bir giriş yolu farkıdır; donanım kökeni veya kök neden kanıtı değildir."
        case "both-cancellation-failed":
            return "Bu çalışmada hem otomatik Escape hem sizin Escape’iniz iptal kontrolünü geçemedi."
        case "cancelled": return "Kontrol durduruldu. Tamamlanmış aşamalar ve giriş temizliğinin durumu özete kaydedildi."
        case "physical-passed-timing-out-of-range":
            return "Sizin Escape’iniz ve yeni normal bırakma başarılı oldu. Gözlenen süreler tekrar sınırının dışında olduğundan otomatik tekrar yapılmadı."
        default: return "Karşılaştırma tamamlanamadı. Sonraki tur başlatılmadı; özette durma ve giriş temizliği bilgisi bulunur."
        }
    }

    private func retainShareableResult(payload: VerifiedSameHostPayload, cases: [SameHostCaseResult], outcome: String) throws -> URL {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw SameHostHelperError.destination
        }
        try checkedDirectory(support)
        let application = support.appendingPathComponent("LemulipInputCheck", isDirectory: true)
        let results = application.appendingPathComponent("Results", isDirectory: true)
        for directory in [application, results] {
            if FileManager.default.fileExists(atPath: directory.path) { try checkedDirectory(directory) }
            else { try makeNewDirectory(directory) }
        }
        let identifier = UUID().uuidString
        let base = "Lemulip-karsilastirma-" + identifier
        var summary: [String: Any] = [
            "schema": 1, "diagnosticOnly": true, "releaseReady": false,
            "physicalInputVerified": false, "hardwareProvenanceVerified": false,
            "imagesCaptured": false, "globalKeyboardMonitorInstalled": false,
            "outcome": outcome, "osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
            "architecture": SameHostKit.architecture, "cases": cases.map { $0.shareableSummary() }
        ]
        summary["identity"] = payload.identityRecord()
        try writeNewJSON(summary, to: results.appendingPathComponent(base + ".json"))
        var lines = [
            "Lemulip — aynı Mac’te Escape karşılaştırması", "",
            outcomeMessage(outcome), "",
            "Bu bir tanı kaydıdır; sürüm veya kabul onayı değildir.",
            "Fiziksel girişin donanım kökeni API ile doğrulanmadı. Ekran görüntüsü alınmadı; genel tuş akışı dinlenmedi.",
            "Sistem: " + ProcessInfo.processInfo.operatingSystemVersionString,
            "Mimari: " + SameHostKit.architecture,
            "Uygulama commit: " + SameHostKit.applicationCommit,
            "Uygulama tree: " + SameHostKit.applicationTree,
            "Gözlemci tabanı: " + SameHostKit.observerBaseCommit,
            "Yardımcı commit: " + (payload.manifest["helperCommit"] as? String ?? "unavailable"), ""
        ]
        for result in cases {
            lines.append(result.phase.title)
            lines.append("  Başarılı: \(result.passed ? "evet" : "hayır")")
            lines.append("  Başlangıç Existing / 1 Selected: \(result.initialWorkspaceCorrect ? "doğrulandı" : "doğrulanmadı")")
            lines.append("  Escape iptali: \(result.cancellation.map { $0 ? "evet" : "hayır" } ?? "ölçülmedi")")
            lines.append("  Yeni normal bırakma: \(result.normalDropVerified ? "doğrulandı" : "doğrulanmadı")")
            lines.append("  Giriş temizliği: \(result.cleanupCompleted ? "tamamlandı" : "TAMAMLANMADI")")
            lines.append("  Temizleme hata kodları: " + (result.cleanupErrorCodes.isEmpty ? "none" : result.cleanupErrorCodes.joined(separator: ", ")))
            lines.append("  Yerel tanı raporu saklandı: \(result.reportRetained ? "evet" : "hayır")")
            lines.append("  Durum kodu: " + result.safeErrorCode)
            lines.append("  İlk durma kodu: " + result.primaryErrorDescription)
            lines.append("  Başlangıç aşaması: " + (result.safeStartupPhase ?? "unavailable"))
            // Render only fields that already passed the JSON summary's allowlists.
            let safe = result.shareableSummary()
            for (field, title) in [("preflight", "Ön kontrol"), ("launchIdentity", "Başlatma kimliği"),
                                   ("documentOpenIdentity", "Dosya açma kimliği")] {
                guard let values = safe[field] as? [String: Any], !values.isEmpty else { continue }
                let flags = values.keys.sorted().compactMap { key -> String? in
                    if exactBoolean(values[key], true) { return key + "=true" }
                    if exactBoolean(values[key], false) { return key + "=false" }
                    return nil
                }
                lines.append("  " + title + ": " + flags.joined(separator: ", "))
            }
            let escape = result.record["sameHostEscape"] as? [String: Any] ?? [:]
            if let wait = boundedNumber(escape["downWaitSeconds"], in: 0...120) {
                lines.append(String(format: "  Escape basılı gözlemine kadar: %.3f sn", wait))
            }
            if let held = boundedNumber(escape["heldSeconds"], in: 0...120) {
                lines.append(String(format: "  Gözlenen basılı kalma: %.3f sn", held))
            }
            lines.append("")
        }
        lines.append("Özet ham dosya yolları, pencere etiketleri veya tuş metni içermez. Otomatik paylaşım yapılmadı.")
        let textURL = results.appendingPathComponent(base + ".txt")
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: textURL, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: textURL.path)
        return textURL
    }

    private func completeInteractiveRun() {
        task = nil
        cuePanel?.orderOut(nil)
        cuePanel = nil
        if terminationPending {
            NSApp.reply(toApplicationShouldTerminate: true)
            return
        }
        refreshPermissions()
        resultButton.isEnabled = latestResult != nil
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func beginSmoke(_ output: URL) {
        startButton.isEnabled = false
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            var success = self.payload != nil
            do { try await Task.sleep(nanoseconds: 3_000_000_000) }
            catch { success = false }
            var result = Self.inputFreeReceipt(status: success ? "PASS" : "FAIL", packageLoad: self.packageLoad)
            result["mode"] = "ui-smoke"
            result["seconds"] = 3
            do { try writeNewJSON(result, to: output) }
            catch { success = false }
            self.task = nil
            Darwin.exit(success ? 0 : 1)
        }
    }

    private func beginCI(output: URL, external: Bool) {
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            var ownsOutput = false
            do {
                try makeNewDirectory(output)
                ownsOutput = true
                guard let payload = self.payload else { throw SameHostHelperError.package }
                let phase: SameHostPhase = external ? .physical : .baseline
                let result = await SameHostCaseRunner.run(payload: payload, session: output, phase: phase,
                    options: self.options(external: external, displayPrompts: false))
                let receipt: [String: Any] = ["schema": 1, "mode": external ? "ci-human-timeout" : "ci-baseline",
                    "diagnosticOnly": true, "releaseReady": false, "physicalInputVerified": false,
                    "case": result.record, "reportRetained": result.reportRetained]
                try writeNewJSON(receipt, to: output.appendingPathComponent("result.json"))
                self.task = nil
                Darwin.exit(result.reportRetained && result.cleanupCompleted ? 0 : 1)
            } catch {
                if ownsOutput {
                    let failed: [String: Any] = ["schema": 1,
                        "mode": external ? "ci-human-timeout" : "ci-baseline",
                        "diagnosticOnly": true, "releaseReady": false, "physicalInputVerified": false,
                        "reportRetained": false,
                        "verification": self.packageLoad.receipt,
                        "case": ["status": "blocked", "helperErrorCode": "helper-preflight-or-receipt-failed",
                                 "gestureOutcomesVerified": false]]
                    try? writeNewJSON(failed, to: output.appendingPathComponent("result.json"))
                }
                self.task = nil
                FileHandle.standardError.write(Data("The diagnostic could not retain its bounded execution receipt.\n".utf8))
                Darwin.exit(1)
            }
        }
    }

    static func inputFreeReceipt(status: String, packageLoad: SameHostPackageLoad) -> [String: Any] {
        ["schema": 1, "status": status, "payloadVerified": packageLoad.payload != nil,
         "helperBundleIdentifier": SameHostKit.bundleIdentifier,
         "diagnosticOnly": true, "releaseReady": false, "inputEventsSent": 0,
         "verification": packageLoad.receipt]
    }

    @objc private func showResult(_ sender: Any?) {
        guard task == nil, let latestResult else { return }
        NSWorkspace.shared.activateFileViewerSelecting([latestResult])
    }

    @objc private func quitPressed(_ sender: Any?) { NSApp.terminate(sender) }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.terminate(sender)
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let task else { return .terminateNow }
        terminationPending = true
        task.cancel()
        cuePanel?.show("Kontrol durduruluyor — Escape’e basılıysanız bırakın; fareye dokunmayın")
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

#if SAME_HOST_SUMMARY_CHECK
// CI-only, input-free regression of the actual shareable-summary code. This
// entrypoint is absent from the shipped helper and never initializes NSApp.
@main
private struct NativeDragSameHostSummaryCheck {
    static func main() {
        do {
            let privateMarker = "summary-check-private-data"
            let identityKeys = ["bundleIdentifierMatches", "bundleURLPresent", "resolvedBundlePathMatches",
                                "bundlePathHasTranslocationComponent", "requestedFreshInstance", "allowsRunningApplicationSubstitution"]
            var identity: [String: Any] = Dictionary(uniqueKeysWithValues: identityKeys.map { ($0, false as Any) })
            identity["requestedFreshInstance"] = true
            identity["unexpectedBoolean"] = true
            identity["privatePath"] = privateMarker
            let cleanup: [String: Any] = ["completed": false, "leftButtonReportedDown": false,
                "applicationStopped": false, "fixtureFinderWindowClosed": true, "fixedBundleRegistryEmpty": false,
                "errors": ["Refusing to terminate an application whose staged identity changed",
                           "The staged app did not terminate before the cleanup deadline",
                           "The fixed review bundle remains registered as running", privateMarker]]
            var record: [String: Any] = ["status": "failed", "startupPhase": "launch-identity",
                "reason": "The launch did not produce the exact staged app", "launchIdentity": identity,
                "preflight": ["accessibility": true, "postEvents": true, "unexpectedBoolean": true], "cleanup": cleanup]
            let launch = SameHostCaseResult(phase: .baseline, record: record, reportRetained: true)
            let launchSummary = launch.shareableSummary()
            try kitRequire(launch.safeErrorCode == "cleanup-incomplete" && launch.primaryErrorCode == "launch-identity-mismatch")
            try kitRequire(launchSummary["errorCode"] as? String == "cleanup-incomplete"
                           && launchSummary["primaryErrorCode"] as? String == "launch-identity-mismatch")
            try kitRequire(launchSummary["startupPhase"] as? String == "launch-identity")
            try kitRequire(Set((launchSummary["launchIdentity"] as? [String: Any] ?? [:]).keys) == Set(identityKeys))
            try kitRequire(Set((launchSummary["preflight"] as? [String: Any] ?? [:]).keys) == Set(["accessibility", "postEvents"]))
            let expectedCleanupCodes = ["cleanup-identity-mismatch", "cleanup-application-still-running",
                                        "cleanup-registry-not-empty", "cleanup-other-error"]
            try kitRequire((launchSummary["cleanup"] as? [String: Any])?["errorCodes"] as? [String] == expectedCleanupCodes)
            try kitRequire(launch.failureDetail.contains("launch-identity-mismatch") && launch.failureDetail.contains("cleanup-identity-mismatch"))

            record["reason"] = "Opening the initial fixture did not reuse the exact staged app"
            record["startupPhase"] = "initial-workspace"
            identity["sameProcessAsLaunched"] = false
            record["documentOpenIdentity"] = identity
            let document = SameHostCaseResult(phase: .baseline, record: record, reportRetained: true)
            let documentSummary = document.shareableSummary()
            try kitRequire(document.primaryErrorCode == "document-open-identity-mismatch" && document.safeErrorCode == "cleanup-incomplete")
            try kitRequire(documentSummary["startupPhase"] as? String == "initial-workspace")
            try kitRequire(Set((documentSummary["documentOpenIdentity"] as? [String: Any] ?? [:]).keys) == Set(identityKeys + ["sameProcessAsLaunched"]))

            record["reason"] = privateMarker
            record["startupPhase"] = privateMarker
            record["launchIdentity"] = ["bundleURLPresent": NSNumber(value: 1), "privatePath": privateMarker] as [String: Any]
            record["preflight"] = ["accessibility": NSNumber(value: 1), "postEvents": true, "unexpectedBoolean": true] as [String: Any]
            let unknown = SameHostCaseResult(phase: .baseline, record: record, reportRetained: true)
            let unknownSummary = unknown.shareableSummary()
            try kitRequire(unknown.primaryErrorCode == "diagnostic-stopped" && unknownSummary["startupPhase"] == nil)
            try kitRequire((unknownSummary["launchIdentity"] as? [String: Any])?.isEmpty == true)
            try kitRequire(Set((unknownSummary["preflight"] as? [String: Any] ?? [:]).keys) == Set(["postEvents"]))
            let encoded = try JSONSerialization.data(withJSONObject: [launchSummary, documentSummary, unknownSummary], options: [.sortedKeys])
            let text = String(decoding: encoded, as: UTF8.self)
            try kitRequire(!text.contains(privateMarker) && !text.contains("privatePath") && !text.contains("unexpectedBoolean"))
            try kitRequire(!unknown.failureDetail.contains(privateMarker))

            record["reason"] = "Existing authorization is insufficient; no permission was requested or changed"
            record["preflight"] = ["accessibility": true, "postEvents": false]
            let permission = SameHostCaseResult(phase: .baseline, record: record, reportRetained: true)
            try kitRequire(permission.primaryErrorCode == "permission-unavailable" && permission.safeErrorCode == "cleanup-incomplete")
            let receipt: [String: Any] = ["schema": 1, "status": "PASS", "mode": "summary-self-check",
                "scenarios": 4, "inputEventsSent": 0, "diagnosticOnly": true, "releaseReady": false]
            FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys]))
            FileHandle.standardOutput.write(Data("\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("The input-free summary regression failed.\n".utf8))
            Darwin.exit(1)
        }
    }
}
#else
@main
private struct NativeDragSameHost {
    @MainActor
    static func main() {
        let mode: SameHostLaunchMode
        do { mode = try SameHostLaunchMode.parse(Array(CommandLine.arguments.dropFirst())) }
        catch {
            FileHandle.standardError.write(Data("Invalid diagnostic launch arguments.\n".utf8))
            Darwin.exit(2)
        }
        let packageLoad = SameHostPackageLoad.fromMainBundle()
        let payload = packageLoad.payload
        if case .verify = mode {
            let receipt = SameHostApplication.inputFreeReceipt(status: payload == nil ? "FAIL" : "PASS", packageLoad: packageLoad)
            if let data = try? JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys]) {
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            }
            Darwin.exit(payload == nil ? 1 : 0)
        }
        let application = NSApplication.shared
        application.setActivationPolicy(mode.isInteractive || mode.isSmoke ? .regular : .accessory)
        let delegate = SameHostApplication(mode: mode, packageLoad: packageLoad)
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
#endif
#endif
