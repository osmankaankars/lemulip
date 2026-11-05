import AppKit
import CryptoKit
import Darwin
import Foundation

// CI-only application-selection contract check. Never include this executable
// in the user kit. It uses no AX, CGEvent, event tap or permission-request API.
// Passing here does not identify the user's launch failure or App Translocation.
private enum LaunchCheckPins {
    static let applicationCommit = "d821d7343675e2850705d141ef9b3b93a6aee945"
    static let applicationTree = "425baa28f00ec24551dd70c0cc874a75fa3be0c1"
    static let observerBase = "c91b08e1f6f5293281e2b54423c53221a289ad90"
    static let identifier = "app.lemulip.NativeUIReview"
    static let application = "Lemulip Native UI Review.app"
    static let maximumFileBytes = 268_435_456
}

private struct LaunchCheckIssue: Error {
    let code: String
}

private func check(_ condition: Bool, _ code: String) throws {
    if !condition { throw LaunchCheckIssue(code: code) }
}

private func hex(_ value: String, count: Int) -> Bool {
    value.utf8.count == count && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
}

private func boolean(_ value: Any?, is expected: Bool) -> Bool {
    guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return false }
    return number.boolValue == expected
}

private func checkDirectory(_ url: URL) throws {
    let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    try check(values.isDirectory == true && values.isSymbolicLink == false, "directory-type")
}

private func makeDirectory(_ url: URL) throws {
    var information = stat()
    try check(lstat(url.path, &information) != 0 && errno == ENOENT, "destination-already-exists")
    try checkDirectory(url.deletingLastPathComponent())
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false,
                                            attributes: [.posixPermissions: 0o700])
    try checkDirectory(url)
}

private func digest(_ url: URL, maximum: Int = LaunchCheckPins.maximumFileBytes) throws -> (String, Int) {
    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
    guard values.isRegularFile == true, values.isSymbolicLink == false,
          let size = values.fileSize, size >= 0, size <= maximum else {
        throw LaunchCheckIssue(code: "file-type-or-size")
    }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hash = SHA256()
    var bytes = 0
    while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
        bytes += data.count
        try check(bytes <= size && bytes <= maximum, "file-read-bound")
        hash.update(data: data)
    }
    try check(bytes == size, "file-size-changed")
    return (hash.finalize().map { String(format: "%02x", $0) }.joined(), bytes)
}

private func smallData(_ url: URL, maximum: Int) throws -> Data {
    _ = try digest(url, maximum: maximum)
    let data = try Data(contentsOf: url)
    try check(data.count <= maximum, "small-file-read-bound")
    return data
}

private func dictionary(_ url: URL) throws -> [String: Any] {
    let data = try smallData(url, maximum: 2_097_152)
    guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw LaunchCheckIssue(code: "json-dictionary")
    }
    return result
}

private func inventory(_ proposedRoot: URL) throws -> [String: String] {
    try checkDirectory(proposedRoot)
    let root = proposedRoot.standardizedFileURL.resolvingSymlinksInPath()
    let prefix = root.path + "/"
    let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
    var enumerationFailed = false
    guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
        options: [], errorHandler: { _, _ in enumerationFailed = true; return false }) else {
        throw LaunchCheckIssue(code: "inventory-unavailable")
    }
    var entries = 0
    var bytes = 0
    var result: [String: String] = [:]
    for case let entry as URL in enumerator {
        entries += 1
        try check(entries <= 8_192, "inventory-entry-bound")
        let values = try entry.resourceValues(forKeys: Set(keys))
        try check(values.isSymbolicLink == false, "inventory-symlink")
        let resolved = entry.resolvingSymlinksInPath()
        try check(entry.standardizedFileURL.path == resolved.path && resolved.path.hasPrefix(prefix),
                  "inventory-containment")
        if values.isDirectory == true { continue }
        try check(values.isRegularFile == true, "inventory-file-type")
        let relative = String(resolved.path.dropFirst(prefix.count))
        try check(relative.utf8.count <= 1_024 && result[relative] == nil && result.count < 4_096,
                  "inventory-membership-bound")
        let (hash, size) = try digest(entry)
        bytes += size
        try check(bytes <= 1_073_741_824, "inventory-byte-bound")
        result[relative] = hash
    }
    try check(!enumerationFailed, "inventory-read-failed")
    return result
}

private struct LaunchCheckPayload {
    let root: URL
    let application: URL
    let fixture: URL
    let snapshot: [String: String]
    let applicationSnapshot: [String: String]
    let fixtureHash: String
    let sourceReceipt: [String: Any]

    static func verify(_ proposed: URL) throws -> LaunchCheckPayload {
        try check(proposed.lastPathComponent == "lemulip-native-ui", "payload-root-name")
        try checkDirectory(proposed)
        let root = proposed.standardizedFileURL.resolvingSymlinksInPath()
        try checkDirectory(root)
        let manifestURL = root.appendingPathComponent("kit-manifest.json")
        let manifest = try dictionary(manifestURL)
        guard let schema = manifest["schema"] as? NSNumber, CFGetTypeID(schema) != CFBooleanGetTypeID(),
              schema.doubleValue == 1, boolean(manifest["diagnosticOnly"], is: true),
              boolean(manifest["releaseReady"], is: false) else {
            throw LaunchCheckIssue(code: "manifest-scope")
        }
        try check(manifest["applicationCommit"] as? String == LaunchCheckPins.applicationCommit
                  && manifest["applicationTree"] as? String == LaunchCheckPins.applicationTree
                  && manifest["observerBaseCommit"] as? String == LaunchCheckPins.observerBase, "source-pins")
        guard let helperCommit = manifest["helperCommit"] as? String, hex(helperCommit, count: 40),
              let guiHash = manifest["stagedGUI_SHA256"] as? String, hex(guiHash, count: 64),
              let files = manifest["files"] as? [String: String], !files.isEmpty, files.count <= 4_096 else {
            throw LaunchCheckIssue(code: "manifest-identity")
        }
        let snapshot = try inventory(root)
        var payloadFiles = snapshot
        let manifestHash = payloadFiles.removeValue(forKey: "kit-manifest.json")
        try check(manifestHash != nil && files == payloadFiles, "manifest-file-inventory")
        let application = root.appendingPathComponent(LaunchCheckPins.application, isDirectory: true)
        let applicationPrefix = LaunchCheckPins.application + "/"
        var appFiles: [String: String] = [:]
        for (path, hash) in files where path.hasPrefix(applicationPrefix) {
            appFiles[String(path.dropFirst(applicationPrefix.count))] = hash
        }
        try check(!appFiles.isEmpty && appFiles["Contents/MacOS/Lemulip"] == guiHash, "application-hash")
        let info = try PropertyListSerialization.propertyList(
            from: smallData(application.appendingPathComponent("Contents/Info.plist"), maximum: 262_144),
            options: [], format: nil) as? [String: Any]
        try check(info?["CFBundleIdentifier"] as? String == LaunchCheckPins.identifier
                  && info?["CFBundleExecutable"] as? String == "Lemulip", "application-identity")
        try check(boolean(info?["LSMultipleInstancesProhibited"], is: true), "application-instance-policy")
        let provenance = try dictionary(root.appendingPathComponent("provenance.json"))
        try check(provenance["sourceCommit"] as? String == LaunchCheckPins.applicationCommit
                  && provenance["sourceTree"] as? String == LaunchCheckPins.applicationTree
                  && provenance["stagedGUI_SHA256"] as? String == guiHash, "application-provenance")
        let fixturePrefix = "Fixtures/FinderDrop/orchard/Existing-"
        let candidates = files.keys.filter { $0.hasPrefix(fixturePrefix) && $0.hasSuffix(".txt") }
        try check(candidates.count == 1, "existing-fixture-count")
        let relative = candidates[0]
        try check(hex(String(relative.dropFirst(fixturePrefix.count).dropLast(4)), count: 32), "existing-fixture-name")
        let fixture = root.appendingPathComponent(relative)
        let bytes = try smallData(fixture, maximum: 65_535)
        try check(bytes == Data("Synthetic Finder input: orchard, Existing. Preserve these bytes.\n".utf8),
                  "existing-fixture-contents")
        guard let fixtureHash = files[relative], let manifestHash else {
            throw LaunchCheckIssue(code: "fixture-manifest-identity")
        }
        return LaunchCheckPayload(root: root, application: application, fixture: fixture, snapshot: snapshot,
            applicationSnapshot: appFiles, fixtureHash: fixtureHash,
            sourceReceipt: ["applicationCommit": LaunchCheckPins.applicationCommit,
                            "applicationTree": LaunchCheckPins.applicationTree,
                            "observerBaseCommit": LaunchCheckPins.observerBase,
                            "helperCommit": helperCommit, "stagedGUI_SHA256": guiHash,
                            "manifestSHA256": manifestHash, "fixtureSHA256": fixtureHash,
                            "fixtureKind": "synthetic-orchard-existing", "multipleInstancesProhibited": true])
    }
}

@MainActor
private final class LaunchIdentityCheck {
    private struct OwnedApplication {
        let application: NSRunningApplication
        let bundle: URL
        let pid: pid_t
    }

    private let arguments = ["-language", "en", "-theme", "orchard", "-wheelEnabled", "NO",
                             "-completionPresentation", "quiet", "-NSQuitAlwaysKeepsWindows", "NO"]
    private var owned: [OwnedApplication] = []
    private var phase = "preflight"
    private var checks: [String: Bool] = [:]
    var result: [String: Any] = [
        "schema": 1, "status": "FAIL", "mode": "ci-strict-launch-identity",
        "diagnosticOnly": true, "releaseReady": false, "inputEventsSent": 0,
        "permissionRequested": false, "accessibilityUsed": false, "physicalInputVerified": false,
        "scope": "Sequential application selection and owned cleanup only; no input, cancellation acceptance or user-cause claim."
    ]

    private func receipt(_ app: NSRunningApplication, bundle: URL,
                         configuration: NSWorkspace.OpenConfiguration) -> [String: Bool] {
        SameHostAppLaunch.identityReceipt(for: app, expectedBundle: bundle,
            expectedIdentifier: LaunchCheckPins.identifier,
            requestedFreshInstance: configuration.createsNewApplicationInstance,
            allowsRunningApplicationSubstitution: configuration.allowsRunningApplicationSubstitution)
    }

    private func exactIdentity(_ app: NSRunningApplication, bundle: URL) -> Bool {
        !app.isTerminated && app.processIdentifier > 0 && app.bundleIdentifier == LaunchCheckPins.identifier
            && app.bundleURL?.resolvingSymlinksInPath().path == bundle.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func registryMatches(_ pids: Set<pid_t>) -> Bool {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: LaunchCheckPins.identifier)
        return apps.count == pids.count && Set(apps.map(\.processIdentifier)) == pids
    }

    private func waitForRegistry(_ pids: Set<pid_t>) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 8
        while !registryMatches(pids) {
            try check(ProcessInfo.processInfo.systemUptime < deadline, "running-registry-deadline")
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    func run(source: URL, output: URL) async {
        do {
            let payload = try LaunchCheckPayload.verify(source)
            result["source"] = payload.sourceReceipt
            try check(registryMatches([]), "preexisting-review-process")
            phase = "copy-a"
            let aRoot = output.appendingPathComponent("copy-a-" + UUID().uuidString, isDirectory: true)
            try makeDirectory(aRoot)
            let aBundle = aRoot.appendingPathComponent(LaunchCheckPins.application, isDirectory: true)
            try FileManager.default.copyItem(at: payload.application, to: aBundle)
            phase = "copy-b"
            let bRoot = URL(fileURLWithPath: "/private/var/tmp", isDirectory: true)
                .appendingPathComponent("lemulip-launch-identity-b-" + UUID().uuidString, isDirectory: true)
            try makeDirectory(bRoot)
            let bBundle = bRoot.appendingPathComponent(LaunchCheckPins.application, isDirectory: true)
            try FileManager.default.copyItem(at: payload.application, to: bBundle)
            let existing = bRoot.appendingPathComponent(payload.fixture.lastPathComponent)
            try FileManager.default.copyItem(at: payload.fixture, to: existing)
            let initialA = try inventory(aBundle)
            let initialB = try inventory(bBundle)
            checks["copiesMatchSource"] = initialA == payload.applicationSnapshot && initialB == payload.applicationSnapshot
            try check(checks["copiesMatchSource"] == true, "copy-integrity")
            try check(bBundle.path.hasPrefix("/private/var/tmp/"), "private-var-copy-location")
            let alias = URL(fileURLWithPath: String(bBundle.path.dropFirst("/private".count)), isDirectory: true)
            checks["privateVarAliasMatches"] = alias.path.hasPrefix("/var/tmp/")
                && alias.resolvingSymlinksInPath().path == bBundle.resolvingSymlinksInPath().path
            try check(checks["privateVarAliasMatches"] == true, "private-var-alias")

            phase = "launch-a"
            let aConfiguration = SameHostAppLaunch.makeConfiguration(arguments: arguments, freshInstance: true)
            let a = try await NSWorkspace.shared.openApplication(at: aBundle, configuration: aConfiguration)
            result["launchIdentityA"] = receipt(a, bundle: aBundle, configuration: aConfiguration)
            try check(exactIdentity(a, bundle: aBundle), "launch-a-identity")
            let firstPID = a.processIdentifier
            owned.append(OwnedApplication(application: a, bundle: aBundle, pid: firstPID))
            try await waitForRegistry([firstPID])

            // Pinned C12 forbids multiple simultaneous instances. Match the real
            // observer's empty-registry precondition before selecting the B copy.
            phase = "stop-first-copy"
            let firstCleanupTask = Task { @MainActor in await self.cleanUp() }
            let firstCleanup = await firstCleanupTask.value
            result["firstCopyCleanup"] = firstCleanup
            checks["firstCopyStoppedBeforeSecondLaunch"] = a.isTerminated
            checks["registryEmptyBeforeSecondLaunch"] = registryMatches([])
            try check(firstCleanup["completed"] as? Bool == true
                      && checks["firstCopyStoppedBeforeSecondLaunch"] == true
                      && checks["registryEmptyBeforeSecondLaunch"] == true, "first-copy-cleanup")

            phase = "launch-b-after-a-stopped"
            let bConfiguration = SameHostAppLaunch.makeConfiguration(arguments: arguments, freshInstance: true)
            let b = try await NSWorkspace.shared.openApplication(at: bBundle, configuration: bConfiguration)
            var bReceipt = receipt(b, bundle: bBundle, configuration: bConfiguration)
            let returnedBundle = b.bundleURL?.resolvingSymlinksInPath().path
            // Descriptive only: a terminated process's numeric PID may be reused.
            // These comparisons do not affect ownership or acceptance decisions.
            bReceipt["returnedPIDMatchesFirst"] = b.processIdentifier == firstPID
            bReceipt["returnedBundleMatchesFirst"] = returnedBundle == aBundle.resolvingSymlinksInPath().path
            bReceipt["returnedBundleMatchesSource"] = returnedBundle == payload.application.resolvingSymlinksInPath().path
            bReceipt["returnedApplicationFinishedLaunching"] = b.isFinishedLaunching
            bReceipt["returnedApplicationTerminated"] = b.isTerminated
            result["launchIdentityB"] = bReceipt
            try check(exactIdentity(b, bundle: bBundle), "launch-b-identity")
            owned.append(OwnedApplication(application: b, bundle: bBundle, pid: b.processIdentifier))
            try await waitForRegistry([b.processIdentifier])

            phase = "var-alias-reuse"
            let aliasConfiguration = SameHostAppLaunch.makeConfiguration(arguments: arguments, freshInstance: false)
            let aliasApp = try await NSWorkspace.shared.openApplication(at: alias, configuration: aliasConfiguration)
            var aliasReceipt = receipt(aliasApp, bundle: bBundle, configuration: aliasConfiguration)
            aliasReceipt["sameProcessAsLaunched"] = aliasApp.processIdentifier == b.processIdentifier
            result["aliasLaunchIdentity"] = aliasReceipt
            checks["aliasReusedB"] = exactIdentity(aliasApp, bundle: bBundle)
                && aliasApp.processIdentifier == b.processIdentifier
            try check(checks["aliasReusedB"] == true, "var-alias-did-not-reuse-b")

            phase = "document-open"
            try check(exactIdentity(b, bundle: bBundle), "launch-b-no-longer-running")
            let documentConfiguration = SameHostAppLaunch.makeConfiguration(arguments: arguments, freshInstance: false)
            let documentApp = try await NSWorkspace.shared.open([existing], withApplicationAt: alias,
                                                                configuration: documentConfiguration)
            var documentReceipt = receipt(documentApp, bundle: bBundle, configuration: documentConfiguration)
            documentReceipt["sameProcessAsLaunched"] = documentApp.processIdentifier == b.processIdentifier
            result["documentOpenIdentity"] = documentReceipt
            checks["documentReusedB"] = exactIdentity(documentApp, bundle: bBundle)
                && documentApp.processIdentifier == b.processIdentifier
            try check(checks["documentReusedB"] == true, "document-did-not-reuse-b")
            try await waitForRegistry([b.processIdentifier])

            phase = "post-launch-integrity"
            checks["sourceUnchanged"] = try inventory(payload.root) == payload.snapshot
            let finalA = try inventory(aBundle)
            let finalB = try inventory(bBundle)
            checks["copiesMatchSource"] = finalA == payload.applicationSnapshot && finalB == payload.applicationSnapshot
            checks["fixtureUnchanged"] = try digest(existing, maximum: 65_535).0 == payload.fixtureHash
            try check(checks["sourceUnchanged"] == true && checks["copiesMatchSource"] == true
                      && checks["fixtureUnchanged"] == true, "post-launch-integrity")
            phase = "complete"
        } catch {
            result["primaryFailureCode"] = (error as? LaunchCheckIssue)?.code ?? "native-operation-failed"
            result["primaryFailurePhase"] = phase
        }
        result["checks"] = checks
        // An independent task keeps cleanup available if the caller is cancelled.
        let cleanupTask = Task { @MainActor in await self.cleanUp() }
        let cleanup = await cleanupTask.value
        result["cleanup"] = cleanup
        if result["primaryFailureCode"] == nil && cleanup["completed"] as? Bool == true {
            result["status"] = "PASS"
        }
    }

    private func cleanUp() async -> [String: Any] {
        let deadline = ProcessInfo.processInfo.systemUptime + 8
        var errors: [String] = []
        var requested = 0
        for entry in owned.reversed() where !entry.application.isTerminated {
            guard entry.application.processIdentifier == entry.pid,
                  exactIdentity(entry.application, bundle: entry.bundle) else {
                errors.append("owned-identity-changed")
                continue
            }
            if entry.application.terminate() { requested += 1 }
            else if !entry.application.isTerminated { errors.append("normal-termination-request-failed") }
        }
        while ProcessInfo.processInfo.systemUptime < deadline {
            if owned.allSatisfy({ $0.application.isTerminated }) && registryMatches([]) { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        let stopped = owned.allSatisfy { $0.application.isTerminated }
        let empty = registryMatches([])
        if !stopped { errors.append("owned-process-cleanup-deadline") }
        if !empty { errors.append("review-registry-not-empty") }
        return ["completed": errors.isEmpty && stopped && empty,
                "ownedProcessCount": owned.count, "normalTerminationRequests": requested,
                "ownedProcessesStopped": stopped, "fixedBundleRegistryEmpty": empty,
                "timeoutSeconds": 8, "errorCodes": errors]
    }
}

@main
private struct NativeDragLaunchIdentityCheck {
    @MainActor
    static func main() async {
        let probe = LaunchIdentityCheck()
        var destination: URL?
        do {
            try check(CommandLine.arguments.count == 3, "arguments")
            let source = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            let proposedOutput = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true).standardizedFileURL
            let output = proposedOutput.deletingLastPathComponent().resolvingSymlinksInPath()
                .appendingPathComponent(proposedOutput.lastPathComponent, isDirectory: true)
            try makeDirectory(output)
            destination = output.appendingPathComponent("result.json")
            await probe.run(source: source, output: output)
        } catch {
            probe.result["primaryFailureCode"] = (error as? LaunchCheckIssue)?.code ?? "setup-operation-failed"
            probe.result["primaryFailurePhase"] = "setup"
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: probe.result, options: [.prettyPrinted, .sortedKeys])
            if let destination { try data.write(to: destination, options: .withoutOverwriting) }
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data([10]))
        } catch {
            FileHandle.standardError.write(Data("Could not retain the launch identity check result\n".utf8))
            exit(1)
        }
        exit(probe.result["status"] as? String == "PASS" ? 0 : 1)
    }
}
