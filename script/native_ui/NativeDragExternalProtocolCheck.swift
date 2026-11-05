import AppKit
import ApplicationServices
import Darwin
import Foundation

// CI-only protocol exercise. This executable is never included in the user kit.
// Its own, explicitly synthetic Escape pair exercises the observer's external
// key-state path; it cannot establish physical-keyboard behavior.
@MainActor
private final class SyntheticExternalEscape {
    private let stagedBundle: URL
    private var task: Task<Void, Error>?
    private(set) var posts = 0
    private(set) var downTime: Double?
    private(set) var upTime: Double?

    init(stagedBundle: URL) { self.stagedBundle = stagedBundle }

    func start() {
        guard task == nil else { return }
        task = Task { @MainActor in
            try await Task.sleep(nanoseconds: 100_000_000)
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "app.lemulip.NativeUIReview")
            guard apps.count == 1, let target = apps.first,
                  target.bundleURL?.resolvingSymlinksInPath().path == stagedBundle.path,
                  !target.isTerminated,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier,
                  CGPreflightPostEventAccess(),
                  CGEventSource.buttonState(.combinedSessionState, button: .left),
                  !CGEventSource.keyState(.combinedSessionState, key: 53),
                  !CGEventSource.keyState(.hidSystemState, key: 53),
                  CGEventSource.flagsState(.combinedSessionState)
                    .intersection([.maskCommand, .maskShift, .maskControl, .maskAlternate]).isEmpty,
                  let source = CGEventSource(stateID: .hidSystemState),
                  let down = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: false) else {
                throw DragReviewIssue.failed("The CI stimulus requires the exact foreground target and an unowned Escape key")
            }
            down.flags = []
            up.flags = []
            downTime = ProcessInfo.processInfo.systemUptime
            down.post(tap: .cghidEventTap)
            posts += 1
            defer {
                // Always pair only this test stimulus's own key-down.
                up.post(tap: .cghidEventTap)
                posts += 1
                upTime = ProcessInfo.processInfo.systemUptime
            }
            try await Task.sleep(nanoseconds: 350_000_000)
            withExtendedLifetime(source) {}
        }
    }

    func finish() async throws {
        guard let task else { throw DragReviewIssue.failed("The observer never requested its external Escape phase") }
        try await task.value
    }
}

@main
private struct NativeDragExternalProtocolCheck {
    @MainActor
    private static func expectedApplicationFiles(in source: URL) throws -> [String: String] {
        let manifestURL = source.appendingPathComponent("kit-manifest.json")
        let values = try manifestURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        let maximum = 2_097_152
        guard values.isRegularFile == true, values.isSymbolicLink == false,
              let size = values.fileSize, size > 0, size <= maximum else {
            throw DragReviewIssue.failed("The CI payload manifest must be a bounded regular file")
        }
        let descriptor = open(manifestURL.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw DragReviewIssue.failed("The CI payload manifest could not be opened safely") }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var information = stat()
        guard fstat(descriptor, &information) == 0, information.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              information.st_size == Int64(size) else {
            throw DragReviewIssue.failed("The CI payload manifest file identity changed")
        }
        var data = Data()
        while let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty {
            data.append(chunk)
            guard data.count <= size && data.count <= maximum else {
                throw DragReviewIssue.failed("The CI payload manifest exceeded its read bound")
            }
        }
        guard data.count == size,
              let manifest = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let schema = manifest["schema"] as? NSNumber, CFGetTypeID(schema) != CFBooleanGetTypeID(), schema.doubleValue == 1,
              let diagnostic = manifest["diagnosticOnly"] as? NSNumber, CFGetTypeID(diagnostic) == CFBooleanGetTypeID(), diagnostic.boolValue,
              let release = manifest["releaseReady"] as? NSNumber, CFGetTypeID(release) == CFBooleanGetTypeID(), !release.boolValue,
              manifest["applicationCommit"] as? String == "d821d7343675e2850705d141ef9b3b93a6aee945",
              manifest["applicationTree"] as? String == "425baa28f00ec24551dd70c0cc874a75fa3be0c1",
              let files = manifest["files"] as? [String: String], !files.isEmpty, files.count <= 4_096 else {
            throw DragReviewIssue.failed("The CI payload manifest does not identify the pinned diagnostic C12 source")
        }
        for (path, hash) in files {
            let components = path.split(separator: "/", omittingEmptySubsequences: false)
            guard path.utf8.count <= 1_024, !components.isEmpty,
                  !path.contains("\\"), !path.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
                  components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                  hash.utf8.count == 64,
                  hash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
                throw DragReviewIssue.failed("The CI payload manifest contains an invalid file expectation")
            }
        }
        let application = "Lemulip Native UI Review.app"
        let prefix = application + "/"
        let expected = Dictionary(uniqueKeysWithValues: files.compactMap { path, hash -> (String, String)? in
            path.hasPrefix(prefix) ? (String(path.dropFirst(prefix.count)), hash) : nil
        })
        guard !expected.isEmpty, let guiHash = manifest["stagedGUI_SHA256"] as? String,
              expected["Contents/MacOS/Lemulip"] == guiHash else {
            throw DragReviewIssue.failed("The CI payload manifest does not seal the pinned application executable")
        }
        _ = try SameHostAppIdentity(expectedBundle: source.appendingPathComponent(application, isDirectory: true),
                                    expectedIdentifier: "app.lemulip.NativeUIReview", executableName: "Lemulip",
                                    expectedFiles: expected)
        return expected
    }

    @MainActor
    static func main() async {
        var result: [String: Any] = ["schema": 1, "status": "FAIL", "mode": "ci-synthetic-external-protocol",
                                     "diagnosticOnly": true, "releaseReady": false,
                                     "physicalInputVerified": false,
                                     "scope": "A test-owned CG Escape pair exercises external observation; not physical input or native acceptance."]
        var destination: URL?
        do {
            guard CommandLine.arguments.count == 3 else {
                throw DragReviewIssue.failed("Usage: NativeDragExternalProtocolCheck <verified payload> <new output directory>")
            }
            let source = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).standardizedFileURL
            let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true).standardizedFileURL
            guard source.lastPathComponent == "lemulip-native-ui",
                  source.path == source.resolvingSymlinksInPath().path,
                  output.path == output.resolvingSymlinksInPath().path,
                  !FileManager.default.fileExists(atPath: output.path) else {
                throw DragReviewIssue.failed("Require a fixed payload and a new output directory")
            }
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
            destination = output.appendingPathComponent("result.json")
            let applicationFiles = try expectedApplicationFiles(in: source)
            result["expectedApplicationFilesVerified"] = true
            let directory = output.appendingPathComponent("lemulip-native-ui", isDirectory: true)
            try FileManager.default.copyItem(at: source, to: directory)
            try FileManager.default.createDirectory(at: directory.appendingPathComponent("NativeDragEvidence"),
                                                    withIntermediateDirectories: false)
            let stimulus = SyntheticExternalEscape(stagedBundle: directory.appendingPathComponent("Lemulip Native UI Review.app"))
            var options = SameHostDragOptions()
            options.expectedApplicationFiles = applicationFiles
            options.escapeInput = .external
            options.onPrompt = { prompt in if prompt == "press-escape" { stimulus.start() } }
            let review = DragReview(directory: directory, theme: .orchard, target: .production, sameHost: options)
            do { try await review.run() }
            catch let error as DragReviewIssue {
                switch error { case .blocked: review.record["status"] = "blocked"; case .failed: review.record["status"] = "failed" }
                review.record["reason"] = error.description
            } catch {
                review.record["status"] = "failed"
                review.record["reason"] = String(describing: error)
            }
            do { try await stimulus.finish() }
            catch { result["stimulusError"] = String(describing: error) }
            let clean = await review.cleanUp()
            do { try review.finish(); result["reportRetained"] = true }
            catch { result["reportRetained"] = false; result["reportError"] = String(describing: error) }
            result["case"] = review.record
            result["testStimulusPosts"] = stimulus.posts
            result["testStimulusDownUptime"] = stimulus.downTime.map { $0 as Any } ?? NSNull()
            result["testStimulusUpUptime"] = stimulus.upTime.map { $0 as Any } ?? NSNull()
            let external = review.record["sameHostEscape"] as? [String: Any] ?? [:]
            let observed = external["status"] as? String == "observed-external-pair"
            let noObserverEscape = (external["syntheticEscapePosts"] as? NSNumber)?.intValue == 0
            let dwell = (external["heldSeconds"] as? NSNumber)?.doubleValue ?? -1
            let cancellation = review.record["escapeCancellation"] as? [String: Any]
            let noImages = !(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }.contains { $0.pathExtension.lowercased() == "png" && !$0.path.contains(".app/") } ?? true)
            guard stimulus.posts == 2, result["stimulusError"] == nil,
                  observed, noObserverEscape, dwell >= 0.15, dwell <= 4,
                  cancellation != nil, clean, result["reportRetained"] as? Bool == true, noImages else {
                throw DragReviewIssue.failed("The external-key protocol or its bounded cleanup was not demonstrated")
            }
            result["status"] = "PASS"
        } catch { result["reason"] = String(describing: error) }
        do {
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            if let destination { try data.write(to: destination, options: .withoutOverwriting) }
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data([10]))
        } catch {
            FileHandle.standardError.write(Data("Could not retain the CI protocol result\n".utf8))
            exit(1)
        }
        exit(result["status"] as? String == "PASS" ? 0 : 1)
    }
}
