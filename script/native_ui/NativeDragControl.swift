import AppKit
import CryptoKit
import Darwin
import Foundation

#if LEMULIP_RECEIVER_SYNC_TRACE && (LEMULIP_EVENT_ORIGIN_TRACE || LEMULIP_DISPATCH_STACK_TRACE)
#error("Receiver synchronization tracing cannot be combined with event-origin or dispatch-stack tracing")
#endif

// An isolated AppKit control for the Finder-input observer. This is not the
// production application and contains no Escape handler or drag cancellation
// workaround. Its passive receipts distinguish destination callbacks from
// events dispatched through NSApplication.sendEvent; absence from sendEvent
// does not prove that AppKit's tracking loop never received an event.
private enum ControlIssue: Error, CustomStringConvertible {
    case invalid(String)
    var description: String { switch self { case .invalid(let message): return message } }
}

private func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw ControlIssue.invalid(message) }
}

private let heldAXCases = ["ax-read-first", "ax-quiet-first", "ax-quiet-second", "ax-read-second"]
private let receiverSyncCases = ["quartz-sync-first", "quartz-deferred-first", "quartz-deferred-second", "quartz-sync-second"]
private let mouseDriverCases = ["quartz-first", "xctest-first", "xctest-second", "quartz-second"] + receiverSyncCases
private let activationCases = ["raise-first", "no-raise-first", "no-raise-second", "raise-second"] + heldAXCases + mouseDriverCases

private struct ControlConfiguration {
    let theme: String
    let evidenceKind: String
    let root: URL
    let folder: URL
    let traceURL: URL
    let originals: [String: Data]

    var activationCase: String? {
        evidenceKind.hasPrefix("activation-") ? String(evidenceKind.dropFirst("activation-".count)) : nil
    }

    var targetRaisePolicy: String? {
        activationCase.map { $0.hasPrefix("no-raise-") ? "omitted" : "present" }
    }

    var activationTraceURL: URL? {
        activationCase == nil ? nil : traceURL.deletingLastPathComponent().appendingPathComponent("activation.jsonl")
    }

    var sourceCase: String? {
        if let activationCase { return activationCase }
        return evidenceKind.hasPrefix("source-") ? String(evidenceKind.dropFirst("source-".count)) : nil
    }

    var sourceBinding: [String: Any] {
        guard let sourceCase else { return [:] }
        var fields: [String: Any] = ["sourceCase": sourceCase,
            "dragSourceKind": activationCase != nil || sourceCase.hasPrefix("appkit-") ? "native-appkit" : "finder"]
        if let activationCase, let targetRaisePolicy {
            fields["activationCase"] = activationCase
            fields["targetRaisePolicy"] = targetRaisePolicy
            if heldAXCases.contains(activationCase) {
                fields["heldAXCase"] = activationCase
                fields["heldAXPolicy"] = activationCase.hasPrefix("ax-quiet-") ? "omitted" : "present"
            }
            if mouseDriverCases.contains(activationCase) {
                fields["mouseDriverCase"] = activationCase
                fields["mouseProducer"] = activationCase.hasPrefix("xctest-") ? "xctest" : "quartz"
            }
            if receiverSyncCases.contains(activationCase) {
                fields["receiverSyncCase"] = activationCase
                fields["receiverTraceSyncPolicy"] = activationCase.hasPrefix("quartz-deferred-") ? "lifecycle" : "per-record"
            }
        }
        return fields
    }

    init() throws {
        let arguments = CommandLine.arguments
        let themeIndices = arguments.indices.filter { arguments[$0] == "-controlTheme" }
        try require(themeIndices.count == 1, "Require one explicit control theme")
        let index = themeIndices[0] + 1
        try require(arguments.indices.contains(index), "The control theme is missing")
        theme = arguments[index]
        try require(["orchard", "pistachio", "lemonade"].contains(theme), "Unknown control theme")
        let evidenceIndices = arguments.indices.filter { arguments[$0] == "-controlEvidenceKind" }
        if evidenceIndices.isEmpty {
            evidenceKind = "quartz"
        } else {
            try require(evidenceIndices.count == 1 && arguments.indices.contains(evidenceIndices[0] + 1),
                        "Require one fixed control evidence kind")
            evidenceKind = arguments[evidenceIndices[0] + 1]
            let kinds = ["keyboard", "capture-screenshots", "capture-ax-only", "lifecycle-appkit",
                         "source-finder-first", "source-appkit-first", "source-appkit-second", "source-finder-second"]
                + activationCases.map { "activation-" + $0 }
            try require(kinds.contains(evidenceKind)
                        && theme == "orchard", "The comparison is restricted to the Orchard control")
        }
        let receiverSyncCase = evidenceKind.hasPrefix("activation-")
            ? String(evidenceKind.dropFirst("activation-".count)) : ""
        #if LEMULIP_RECEIVER_SYNC_TRACE
        try require(receiverSyncCases.contains(receiverSyncCase),
                    "Receiver synchronization tracing requires a fixed receiver-sync case")
        #else
        try require(!receiverSyncCases.contains(receiverSyncCase),
                    "Receiver-sync cases require the isolated receiver synchronization build")
        #endif

        let bundle = Bundle.main.bundleURL.standardizedFileURL
        root = bundle.deletingLastPathComponent()
        try require(root.lastPathComponent == "lemulip-native-ui"
                    && bundle.lastPathComponent == "Native Drag Control.app"
                    && Bundle.main.bundleIdentifier == "app.lemulip.NativeDragControl"
                    && Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String == "NativeDragControl",
                    "Require the exact isolated AppKit control bundle")
        folder = root.appendingPathComponent("Fixtures/FinderDrop/" + theme, isDirectory: true)
        let evidenceName: String
        switch evidenceKind {
        case "keyboard": evidenceName = "NativeDragKeyboardEvidence"
        case "capture-screenshots": evidenceName = "NativeDragControlEvidence-Capture-screenshots"
        case "capture-ax-only": evidenceName = "NativeDragControlEvidence-Capture-ax-only"
        case "lifecycle-appkit": evidenceName = "NativeDragControlEvidence-Capture-ax-only-Lifecycle-appkit"
        case "source-finder-first", "source-appkit-first", "source-appkit-second", "source-finder-second":
            evidenceName = "NativeDragControlEvidence-Capture-ax-only-Lifecycle-appkit-Source-"
                + String(evidenceKind.dropFirst("source-".count))
        case "activation-raise-first", "activation-no-raise-first", "activation-no-raise-second", "activation-raise-second",
             "activation-ax-read-first", "activation-ax-quiet-first", "activation-ax-quiet-second", "activation-ax-read-second":
            evidenceName = "NativeDragControlEvidence-Capture-ax-only-Lifecycle-appkit-Activation-"
                + String(evidenceKind.dropFirst("activation-".count))
        case "activation-quartz-first", "activation-xctest-first", "activation-xctest-second", "activation-quartz-second",
             "activation-quartz-sync-first", "activation-quartz-deferred-first",
             "activation-quartz-deferred-second", "activation-quartz-sync-second":
            evidenceName = "NativeDragControlEvidence-Capture-ax-only-Lifecycle-appkit-MouseDriver-"
                + String(evidenceKind.dropFirst("activation-".count))
        default: evidenceName = "NativeDragControlEvidence"
        }
        let evidence = root.appendingPathComponent(evidenceName + "/" + theme, isDirectory: true)
        for url in [root, bundle, folder, evidence] {
            try require(url.standardizedFileURL.path == url.resolvingSymlinksInPath().path,
                        "Symlinked control paths are not allowed")
            try require(try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true,
                        "The fixed control directory is unavailable")
        }
        traceURL = evidence.appendingPathComponent("receiver.jsonl")
        let inputs = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent != ".DS_Store" }
        try require(inputs.count == 4, "Require exactly four input-only Finder fixtures")
        var bytes: [String: Data] = [:]
        for prefix in ["Existing", "Single", "Multi-A", "Multi-B"] {
            let matching = inputs.filter { $0.lastPathComponent.hasPrefix(prefix + "-") && $0.pathExtension == "txt" }
            try require(matching.count == 1, "The fixed Finder fixture role is missing or ambiguous")
            let input = matching[0]
            try require(input.standardizedFileURL.path == input.resolvingSymlinksInPath().path,
                        "Symlinked Finder fixtures are not allowed")
            let values = try input.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            try require(values.isRegularFile == true && values.isSymbolicLink == false
                        && (values.fileSize ?? 0) > 0 && (values.fileSize ?? 0) < 65_536,
                        "Require small, nonempty regular Finder fixtures")
            bytes[input.lastPathComponent] = try Data(contentsOf: input)
        }
        try require(bytes.count == 4, "Finder fixture roles must be distinct")
        originals = bytes
    }

    func validated(_ urls: [URL]) throws -> [URL] {
        try require(!urls.isEmpty && urls.count <= 4, "Require one to four exact fixture URLs")
        return try urls.map { url in
            let expected = folder.appendingPathComponent(url.lastPathComponent)
            try require(url.isFileURL && (url.host == nil || url.host == "" || url.host == "localhost")
                        && url.query == nil && url.fragment == nil
                        && originals[url.lastPathComponent] != nil
                        && url.standardizedFileURL.path == expected.path
                        && url.resolvingSymlinksInPath().path == expected.path,
                        "Only the exact staged Finder fixture URLs are accepted")
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            try require(values.isRegularFile == true && values.isSymbolicLink == false
                        && (values.fileSize ?? 0) > 0 && (values.fileSize ?? 0) < 65_536,
                        "A fixture is no longer a small regular file")
            try require(try Data(contentsOf: expected) == originals[url.lastPathComponent],
                        "A fixture's original bytes changed")
            return expected
        }
    }

    func originalState() -> [String: Any] {
        do {
            let actual = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent != ".DS_Store" }
            let sameSet = Set(actual.map(\.lastPathComponent)) == Set(originals.keys)
            let sameBytes = try originals.keys.sorted().allSatisfy { name in
                _ = try validated([folder.appendingPathComponent(name)])
                return true
            }
            return ["originalBytesUnchanged": sameBytes, "fixtureFileSetUnchanged": sameSet]
        } catch {
            return ["originalBytesUnchanged": false, "fixtureFileSetUnchanged": false,
                    "originalCheckError": String(describing: error)]
        }
    }
}

private final class ControlTrace: @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()
    private var count = 0
    private var byteCount = 0
    private let maximumRecords = 10_000
    private let maximumBytes = 8 * 1_024 * 1_024
    private let sourceBinding: [String: Any]
    #if LEMULIP_RECEIVER_SYNC_TRACE
    private struct WriteReceipt {
        let recordIndex: Int
        let event: String
        let recordSystemUptime: TimeInterval
        let byteOffset: Int
        let byteCount: Int
        let writeStartedSystemUptime: TimeInterval
        let writeCompletedSystemUptime: TimeInterval
        let synchronizeStartedSystemUptime: TimeInterval?
        let synchronizeCompletedSystemUptime: TimeInterval?

        var fields: [String: Any] {
            ["recordIndex": recordIndex, "event": event, "recordSystemUptime": recordSystemUptime,
             "byteOffset": byteOffset, "byteCount": byteCount,
             "writeStartedSystemUptime": writeStartedSystemUptime,
             "writeCompletedSystemUptime": writeCompletedSystemUptime,
             "synchronizeAttempted": synchronizeStartedSystemUptime != nil,
             "synchronizeStartedSystemUptime": synchronizeStartedSystemUptime.map { $0 as Any } ?? NSNull(),
             "synchronizeCompletedSystemUptime": synchronizeCompletedSystemUptime.map { $0 as Any } ?? NSNull()]
        }
    }

    private let receiverSyncCase: String
    private let receiverTraceSyncPolicy: String
    private var writeReceipts: [WriteReceipt] = []
    private var perRecordSynchronizeCount = 0
    private var synchronizationFinished = false
    #endif

    init(url: URL, sourceBinding: [String: Any] = [:]) throws {
        self.sourceBinding = sourceBinding
        #if LEMULIP_RECEIVER_SYNC_TRACE
        guard let receiverSyncCase = sourceBinding["receiverSyncCase"] as? String,
              receiverSyncCases.contains(receiverSyncCase) else {
            throw ControlIssue.invalid("The receiver trace requires a fixed receiver-sync binding")
        }
        let policy = receiverSyncCase.hasPrefix("quartz-deferred-") ? "lifecycle" : "per-record"
        try require(sourceBinding["receiverTraceSyncPolicy"] as? String == policy
                    && url.lastPathComponent == "receiver.jsonl",
                    "The receiver trace synchronization binding is invalid")
        self.receiverSyncCase = receiverSyncCase
        receiverTraceSyncPolicy = policy
        #endif
        let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                                     S_IRUSR | S_IWUSR)
        try require(descriptor >= 0, "Could not exclusively create the fixed receiver trace")
        handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    func record(_ event: String, _ fields: [String: Any] = [:]) {
        lock.lock()
        defer { lock.unlock() }
        do {
            var value = fields
            value.merge(sourceBinding) { _, fixed in fixed }
            value["schema"] = 1
            value["event"] = event
            value["recordIndex"] = count
            let recordSystemUptime = ProcessInfo.processInfo.systemUptime
            value["systemUptime"] = recordSystemUptime
            value["time"] = ISO8601DateFormatter().string(from: Date())
            value["pid"] = Int(ProcessInfo.processInfo.processIdentifier)
            let withinLimit = count < maximumRecords && byteCount < maximumBytes - 8_192
            if !withinLimit {
                value = ["schema": 1, "event": "trace-limit", "recordIndex": count,
                         "systemUptime": ProcessInfo.processInfo.systemUptime]
            }
            var data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
            data.append(0x0a)
            #if LEMULIP_RECEIVER_SYNC_TRACE
            // Keep every complete line immediately readable by the existing
            // observer. Only the explicit synchronization policy differs.
            let writeStarted = ProcessInfo.processInfo.systemUptime
            try handle.write(contentsOf: data)
            let writeCompleted = ProcessInfo.processInfo.systemUptime
            var synchronizeStarted: TimeInterval?
            var synchronizeCompleted: TimeInterval?
            if receiverTraceSyncPolicy == "per-record" || !withinLimit {
                synchronizeStarted = ProcessInfo.processInfo.systemUptime
                try handle.synchronize()
                synchronizeCompleted = ProcessInfo.processInfo.systemUptime
            }
            // A trace-limit row keeps the original fatal framing and is
            // synchronized before exit, but can never yield a complete receipt.
            if withinLimit {
                writeReceipts.append(WriteReceipt(
                    recordIndex: count, event: event, recordSystemUptime: recordSystemUptime,
                    byteOffset: byteCount, byteCount: data.count,
                    writeStartedSystemUptime: writeStarted, writeCompletedSystemUptime: writeCompleted,
                    synchronizeStartedSystemUptime: synchronizeStarted,
                    synchronizeCompletedSystemUptime: synchronizeCompleted))
                if synchronizeStarted != nil { perRecordSynchronizeCount += 1 }
            }
            #else
            try handle.write(contentsOf: data)
            try handle.synchronize()
            #endif
            count += 1
            byteCount += data.count
            if !withinLimit { Darwin.exit(2) }
        } catch {
            FileHandle.standardError.write(Data(("Native drag control trace failed: \(error)\n").utf8))
            Darwin.exit(2)
        }
    }

    #if LEMULIP_RECEIVER_SYNC_TRACE
    // Receipts stay in bounded memory until the existing termination journal
    // entry. There is no extra setup flush: the policy covers the whole trace.
    // A failed write, synchronization, or limit yields no complete receipt.
    func finishSynchronization(phase: String) -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        do {
            let normal = phase == "termination"
            try require(normal || phase == "watchdog", "Unknown receiver synchronization lifecycle phase")
            try require(!synchronizationFinished && count > 0 && count <= maximumRecords
                        && byteCount <= maximumBytes && writeReceipts.count == count,
                        "The receiver trace synchronization receipt is incomplete or already finalized")
            try require(writeReceipts.last?.event == (normal ? "application-terminated" : "application-timeout"),
                        "The receiver trace has no matching final lifecycle row")
            let started = ProcessInfo.processInfo.systemUptime
            try handle.synchronize()
            let completed = ProcessInfo.processInfo.systemUptime
            synchronizationFinished = true
            // Do not suppress any later receiver callback. A late raw row will
            // disagree with this snapshot and the artifact validator rejects it.
            return [
                "schema": 1, "status": normal ? "complete" : "incomplete",
                "reasonCode": normal ? NSNull() as Any : "watchdog-termination",
                "receiverSyncCase": receiverSyncCase, "receiverTraceSyncPolicy": receiverTraceSyncPolicy,
                "targetPID": Int(ProcessInfo.processInfo.processIdentifier), "traceFileName": "receiver.jsonl",
                "recordWritePolicy": "immediate", "synchronizationAPI": "FileHandle.synchronize",
                "maximumRecordCount": maximumRecords, "maximumTraceBytes": maximumBytes,
                "recordCount": count, "writtenByteCount": byteCount,
                "perRecordSynchronizeCount": perRecordSynchronizeCount,
                "records": writeReceipts.map(\.fields),
                "lifecycleSynchronization": ["phase": phase, "recordCount": count, "writtenByteCount": byteCount,
                    "startedSystemUptime": started, "completedSystemUptime": completed, "succeeded": true]
            ]
        } catch {
            FileHandle.standardError.write(Data(("Native drag receiver synchronization failed: \(error)\n").utf8))
            Darwin.exit(2)
        }
    }
    #endif
}

// D11 adds a separate journal without changing the receiver trace or drop
// implementation. Nothing in this journal is written or synchronized while
// dispatching events, handling AXRaise, or tracking a drag. It is drained only
// at normal termination, the owned watchdog, or a fatal journal limit.
private final class ActivationJournal: @unchecked Sendable {
    private let handle: FileHandle
    private let binding: [String: Any]
    let startupFields: [String: Any]
    private let lock = NSLock()
    private var buffer = Data()
    private var count = 0
    private var byteCount = 0
    private let maximumRecords = 4_096
    private let maximumBytes = 4 * 1_024 * 1_024

    init(configuration: ControlConfiguration) throws {
        guard let url = configuration.activationTraceURL else {
            throw ControlIssue.invalid("The activation journal requires an explicit activation case")
        }
        try require(url.lastPathComponent == "activation.jsonl"
                    && url.deletingLastPathComponent().path == url.deletingLastPathComponent().resolvingSymlinksInPath().path,
                    "The fixed activation journal directory changed identity")
        let bundle = Bundle.main.bundleURL.standardizedFileURL
        try require(Bundle.main.object(forInfoDictionaryKey: "NSPrincipalClass") as? String == "NativeDragControlApplication",
                    "The activation comparison requires the passive control application subclass")
        let data = try Self.readRegularFile(configuration.root.appendingPathComponent("provenance.json"), maximumBytes: 262_144)
        guard let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ControlIssue.invalid("The activation comparison provenance is invalid")
        }
        var provenance: [String: String] = [:]
        for key in ["nativeDragControlSourceSHA256", "controlGUI_SHA256", "observerExperimentCommit",
                    "observerExperimentTree", "sourceCommit", "sourceTree", "architecture"] {
            guard let value = raw[key] as? String else {
                throw ControlIssue.invalid("The activation comparison provenance is incomplete")
            }
            provenance[key] = value
            if key != "architecture" {
                let length = key.hasSuffix("SHA256") ? 64 : 40
                try require(value.range(of: "^[a-f0-9]{\(length)}$", options: .regularExpression) != nil,
                            "The activation comparison provenance contains a malformed digest")
            }
        }
        try require(provenance["sourceCommit"] == "d821d7343675e2850705d141ef9b3b93a6aee945"
                    && provenance["sourceTree"] == "425baa28f00ec24551dd70c0cc874a75fa3be0c1",
                    "The activation comparison requires the pinned C12 product baseline")
        #if arch(arm64)
        let architecture = "arm64"
        #elseif arch(x86_64)
        let architecture = "x86_64"
        #else
        let architecture = "unsupported"
        #endif
        try require(provenance["architecture"] == architecture && architecture != "unsupported",
                    "The activation comparison architecture does not match its provenance")
        let executable = bundle.appendingPathComponent("Contents/MacOS/NativeDragControl")
        try require(Bundle.main.executableURL?.standardizedFileURL.path == executable.path,
                    "The activation control executable is outside its fixed bundle")
        let executableData = try Self.readRegularFile(executable, maximumBytes: 134_217_728)
        try require(Self.sha256(executableData) == provenance["controlGUI_SHA256"],
                    "The activation control executable does not match its staged digest")
        binding = configuration.sourceBinding
        var fields: [String: Any] = provenance.mapValues { $0 as Any }
        #if LEMULIP_EVENT_ORIGIN_TRACE
        try require(mouseDriverCases.contains(configuration.sourceCase ?? ""),
                    "Event-origin tracing requires a fixed mouse-driver case")
        fields["targetMouseEventIdentitySchema"] = 1
        #endif
        #if LEMULIP_DISPATCH_STACK_TRACE
        fields["targetDispatchStackSchema"] = 1
        #endif
        #if LEMULIP_RECEIVER_SYNC_TRACE
        fields["receiverTraceSynchronizationSchema"] = 1
        #endif
        fields.merge([
            "bundleIdentifier": "app.lemulip.NativeDragControl", "executableName": "NativeDragControl",
            "bundleName": "Native Drag Control.app", "targetBundlePath": bundle.path,
            "stagingRoot": configuration.root.path, "traceFileName": "activation.jsonl",
            "originalSHA256": configuration.originals.mapValues(Self.sha256),
            "maximumRecords": maximumRecords, "maximumBytes": maximumBytes,
            "flushPolicy": "termination-or-watchdog"
        ]) { _, value in value }
        startupFields = fields
        let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                                     S_IRUSR | S_IWUSR)
        try require(descriptor >= 0, "Could not exclusively create the fixed activation journal")
        handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func readRegularFile(_ url: URL, maximumBytes: Int) throws -> Data {
        try require(url.standardizedFileURL.path == url.resolvingSymlinksInPath().path,
                    "Symlinked activation comparison inputs are not allowed")
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        try require(descriptor >= 0, "A fixed activation comparison input could not be opened")
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var before = stat()
        try require(Darwin.fstat(descriptor, &before) == 0
                    && before.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG)
                    && before.st_size > 0 && before.st_size <= maximumBytes,
                    "Require a bounded, nonempty regular activation comparison input")
        var bytes = Data()
        while bytes.count <= maximumBytes {
            let chunk = try handle.read(upToCount: min(65_536, maximumBytes + 1 - bytes.count)) ?? Data()
            if chunk.isEmpty { break }
            bytes.append(chunk)
        }
        var after = stat()
        try require(Darwin.fstat(descriptor, &after) == 0 && bytes.count == before.st_size
                    && bytes.count <= maximumBytes && after.st_size == before.st_size
                    && after.st_ino == before.st_ino && after.st_dev == before.st_dev,
                    "An activation comparison input changed while being read")
        return bytes
    }

    private func encoded(_ event: String, _ fields: [String: Any]) throws -> Data {
        var value = fields
        value.merge(binding) { _, fixed in fixed }
        value["schema"] = 1
        value["event"] = event
        value["recordIndex"] = count
        value["systemUptime"] = ProcessInfo.processInfo.systemUptime
        value["pid"] = Int(ProcessInfo.processInfo.processIdentifier)
        var data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        data.append(0x0a)
        return data
    }

    func record(_ event: String, _ fields: [String: Any] = [:]) {
        lock.lock()
        defer { lock.unlock() }
        do {
            let data = try encoded(event, fields)
            if count >= maximumRecords - 1 || byteCount + data.count > maximumBytes - 8_192 {
                buffer.append(try encoded("trace-limit", [:]))
                try flushLocked()
                Darwin.exit(2)
            }
            buffer.append(data)
            count += 1
            byteCount += data.count
        } catch { fatalJournal(error) }
    }

    func flush() {
        lock.lock()
        defer { lock.unlock() }
        do { try flushLocked() } catch { fatalJournal(error) }
    }

    private func flushLocked() throws {
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            buffer.removeAll(keepingCapacity: true)
        }
        try handle.synchronize()
    }

    private func fatalJournal(_ error: Error) -> Never {
        FileHandle.standardError.write(Data(("Native drag activation journal failed: \(error)\n").utf8))
        Darwin.exit(2)
    }
}

@MainActor
private func activationState(window: NSWindow?, received: TimeInterval) -> [String: Any] {
    let cursor = NSEvent.mouseLocation
    return [
        "callbackSystemUptime": received, "applicationActive": NSApp.isActive,
        "keyWindowNumber": NSApp.keyWindow.map { $0.windowNumber as Any } ?? NSNull(),
        "mainWindowNumber": NSApp.mainWindow.map { $0.windowNumber as Any } ?? NSNull(),
        "windowNumber": window.map { $0.windowNumber as Any } ?? NSNull(),
        "windowIsKey": window.map { $0.isKeyWindow as Any } ?? NSNull(),
        "windowIsMain": window.map { $0.isMainWindow as Any } ?? NSNull(),
        "windowCanBecomeKey": window.map { $0.canBecomeKey as Any } ?? NSNull(),
        "windowCanBecomeMain": window.map { $0.canBecomeMain as Any } ?? NSNull(),
        "windowVisible": window.map { $0.isVisible as Any } ?? NSNull(),
        "observedCursorScreen": ["x": Double(cursor.x), "y": Double(cursor.y)],
        "cursorCoordinateSpace": "AppKit-screen-bottom-left"
    ]
}

@MainActor
@objc(NativeDragControlApplication)
private final class ControlApplication: NSApplication {
    var trace: ControlTrace?
    var activationJournal: ActivationJournal?
    weak var observedWindow: NSWindow?
    private var dispatchIndex = 0
    #if LEMULIP_DISPATCH_STACK_TRACE
    private struct DispatchStackCapture {
        let targetPID: Int
        let dispatchIndex: Int
        let eventTimestamp: TimeInterval
        let mainThread: Bool
        let started: TimeInterval
        let completed: TimeInterval
        let capturedFrameCount: Int
        let addresses: [UInt]
    }
    private var firstDispatchStack: DispatchStackCapture?
    private var completedDispatchStack: [String: Any]?

    private func captureFirstDispatchStack(_ event: NSEvent) {
        guard event.type == .leftMouseDragged, firstDispatchStack == nil else { return }
        let started = ProcessInfo.processInfo.systemUptime
        let values = Thread.callStackReturnAddresses
        let addresses = values.prefix(48).map(\.uintValue)
        let completed = ProcessInfo.processInfo.systemUptime
        firstDispatchStack = DispatchStackCapture(
            targetPID: Int(ProcessInfo.processInfo.processIdentifier), dispatchIndex: dispatchIndex + 1,
            eventTimestamp: event.timestamp, mainThread: Thread.isMainThread,
            started: started, completed: completed, capturedFrameCount: values.count, addresses: addresses)
    }

    // Resolve the retained entry addresses only from the existing termination
    // callback. No symbol lookup, journal write, or extra event occurs at entry.
    func finishDispatchStackObservation() -> [String: Any] {
        if let completedDispatchStack { return completedDispatchStack }
        guard let captured = firstDispatchStack else {
            let missing: [String: Any] = ["schema": 1, "status": "unavailable",
                "reasonCode": "first-target-leftMouseDragged-not-observed"]
            completedDispatchStack = missing
            return missing
        }
        let started = ProcessInfo.processInfo.systemUptime
        let pointers = captured.addresses.map { UnsafeMutableRawPointer(bitPattern: $0) }
        let symbols = pointers.withUnsafeBufferPointer { buffer in
            buffer.isEmpty ? nil : backtrace_symbols(buffer.baseAddress, Int32(buffer.count))
        }
        defer { if let symbols { free(symbols) } }
        let hexAddresses = captured.addresses.map { "0x" + String($0, radix: 16) }
        var frames: [[String: Any]] = []
        for (index, address) in hexAddresses.enumerated() {
            var rendered: String?
            var truncated = false
            if let symbol = symbols?[index] {
                // Bound decoding as well as serialized characters. A rendered
                // backtrace line can still contain an unavailable symbol name.
                let byteCount = strnlen(symbol, 4_097)
                let bytes = UnsafeRawPointer(symbol).assumingMemoryBound(to: UInt8.self)
                let text = String(decoding: UnsafeBufferPointer(start: bytes, count: min(byteCount, 4_096)), as: UTF8.self)
                truncated = byteCount > 4_096 || text.count > 512
                if !text.isEmpty { rendered = String(text.prefix(512)) }
            }
            frames.append(["frameIndex": index, "returnAddress": address,
                "symbolStatus": rendered == nil ? "unresolved" : "rendered",
                "symbol": rendered.map { $0 as Any } ?? NSNull(), "symbolTruncated": truncated])
        }
        let complete = !frames.isEmpty && frames.allSatisfy { $0["symbolStatus"] as? String == "rendered" }
        let receipt: [String: Any] = [
            "schema": 1, "status": complete ? "complete" : "unavailable",
            "reasonCode": complete ? NSNull() : (frames.isEmpty ? "empty-captured-stack" : "one-or-more-symbols-unresolved") as Any,
            "targetPID": captured.targetPID, "dispatchIndex": captured.dispatchIndex, "eventType": 6,
            "eventTimestamp": captured.eventTimestamp, "mainThread": captured.mainThread,
            "captureStartedSystemUptime": captured.started, "captureCompletedSystemUptime": captured.completed,
            "maximumFrames": 48, "capturedFrameCount": captured.capturedFrameCount,
            "retainedFrameCount": captured.addresses.count, "returnAddresses": hexAddresses,
            "framesTruncated": captured.capturedFrameCount > captured.addresses.count,
            "symbolicationMethod": "backtrace_symbols", "maximumSymbolCharacters": 512,
            "symbolicationStartedSystemUptime": started,
            "symbolicationCompletedSystemUptime": ProcessInfo.processInfo.systemUptime,
            "symbolicationMainThread": Thread.isMainThread, "frames": frames
        ]
        completedDispatchStack = receipt
        return receipt
    }
    #endif

    override func sendEvent(_ event: NSEvent) {
        let entered = ProcessInfo.processInfo.systemUptime
        var dispatchKind: String?
        var dispatchFields: [String: Any] = [:]
        if activationJournal != nil {
            if event.type == .appKitDefined {
                // subtype is valid for AppKit-defined events. Do not read it
                // from key events or infer undocumented data1/data2 meanings.
                let subtype = event.subtype
                if subtype == .applicationActivated || subtype == .applicationDeactivated {
                    dispatchKind = "appkit-defined"
                    dispatchFields["eventSubtype"] = Int(subtype.rawValue)
                    dispatchFields["eventSubtypeName"] = subtype == .applicationActivated
                        ? "applicationActivated" : "applicationDeactivated"
                }
            } else if [.leftMouseDown, .leftMouseUp, .leftMouseDragged].contains(event.type) {
                dispatchKind = "target-mouse"
                #if LEMULIP_DISPATCH_STACK_TRACE
                // This one-shot capture precedes both NSEvent.cgEvent and the
                // normal super.sendEvent dispatch. Keep the original event.
                captureFirstDispatchStack(event)
                #endif
                dispatchFields["locationInWindow"] = ["x": Double(event.locationInWindow.x),
                                                      "y": Double(event.locationInWindow.y)]
                dispatchFields["modifierFlags"] = event.modifierFlags.rawValue
                dispatchFields["eventMatchesOwnedWindow"] = event.windowNumber == observedWindow?.windowNumber
                #if LEMULIP_EVENT_ORIGIN_TRACE
                // Observe the event already being dispatched. Do not alter
                // or post input, and preserve these values for the return
                // receipt instead of resampling a possibly different event.
                var delivered: [String: Any] = [
                    "eventType": event.type.rawValue, "eventNumber": event.eventNumber,
                    "buttonNumber": event.buttonNumber,
                    "clickCount": event.type == .leftMouseDragged ? NSNull() : event.clickCount as Any,
                    "pressure": event.pressure, "modifierFlags": event.modifierFlags.rawValue,
                    "cgEventPresent": false
                ]
                if let cg = event.cgEvent {
                    delivered["cgEventPresent"] = true
                    delivered["cgSourceStateID"] = cg.getIntegerValueField(.eventSourceStateID)
                    delivered["cgSourcePID"] = cg.getIntegerValueField(.eventSourceUnixProcessID)
                    delivered["cgMouseEventNumber"] = cg.getIntegerValueField(.mouseEventNumber)
                    delivered["cgMousePressure"] = cg.getDoubleValueField(.mouseEventPressure)
                    delivered["cgTimestampNanoseconds"] = cg.timestamp
                }
                dispatchFields["deliveredMouseEvent"] = delivered
                #endif
            }
            if let dispatchKind {
                dispatchIndex += 1
                dispatchFields["dispatchIndex"] = dispatchIndex
                dispatchFields["eventType"] = Int(event.type.rawValue)
                dispatchFields["eventTimestamp"] = event.timestamp
                dispatchFields["eventWindowNumber"] = event.windowNumber
                var fields = activationState(window: observedWindow, received: entered)
                fields.merge(dispatchFields) { _, value in value }
                activationJournal?.record(dispatchKind + "-enter", fields)
            }
        }
        if (event.type == .keyDown || event.type == .keyUp) && event.keyCode == 53 {
            trace?.record("escape-send-event", [
                "eventType": event.type == .keyDown ? "keyDown" : "keyUp",
                "keyCode": Int(event.keyCode), "eventTimestamp": event.timestamp,
                "isRepeat": event.type == .keyDown && event.isARepeat,
                "modifierFlags": event.modifierFlags.rawValue,
                "charactersUTF32": (event.characters ?? "").unicodeScalars.prefix(4).map(\.value),
                "charactersIgnoringModifiersUTF32": (event.charactersIgnoringModifiers ?? "").unicodeScalars.prefix(4).map(\.value),
                "applicationActive": isActive, "eventWindowNumber": event.windowNumber,
                "keyWindowNumber": keyWindow.map { $0.windowNumber as Any } ?? NSNull(),
                "scope": "Passive sendEvent receipt only; super is always called."
            ])
        }
        super.sendEvent(event)
        let returned = ProcessInfo.processInfo.systemUptime
        if let dispatchKind {
            var fields = activationState(window: observedWindow, received: returned)
            fields.merge(dispatchFields) { _, value in value }
            activationJournal?.record(dispatchKind + "-return", fields)
        }
    }
}

@MainActor
private final class ControlSelection {
    let configuration: ControlConfiguration
    let trace: ControlTrace
    private(set) var urls: [URL] = []
    var onChange: (() -> Void)?

    init(configuration: ControlConfiguration, trace: ControlTrace) {
        self.configuration = configuration
        self.trace = trace
    }

    func append(_ incoming: [URL], origin: String) throws {
        let accepted = try configuration.validated(incoming)
        var known = Set(urls)
        urls += accepted.filter { known.insert($0).inserted }
        onChange?()
        recordSelection(origin)
    }

    func clear() {
        urls = []
        onChange?()
        recordSelection("clear-button")
    }

    func remove(_ name: String) {
        urls.removeAll { $0.lastPathComponent == name }
        onChange?()
        recordSelection("remove-button")
    }

    private func recordSelection(_ origin: String) {
        var fields = configuration.originalState()
        fields["origin"] = origin
        fields["selectedFilenames"] = urls.map(\.lastPathComponent)
        trace.record("selection-changed", fields)
    }
}

@MainActor
private final class ControlDropView: NSView {
    private let selection: ControlSelection
    private let countLabel = NSTextField(labelWithString: "0 Selected")
    private let clearButton = NSButton(title: "Clear", target: nil, action: nil)
    private var fileLabels: [NSTextField] = []
    private var removeButtons: [NSButton] = []
    private var targeted = false { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }

    init(selection: ControlSelection) {
        self.selection = selection
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL])
        countLabel.font = .systemFont(ofSize: 13, weight: .medium)
        countLabel.setAccessibilityIdentifier("control.selected-count")
        addSubview(countLabel)
        clearButton.bezelStyle = .rounded
        clearButton.target = self
        clearButton.action = #selector(clearSelection)
        addSubview(clearButton)
        selection.onChange = { [weak self] in self?.refresh() }
        refresh()
    }

    required init?(coder: NSCoder) { nil }

    private func refresh() {
        countLabel.stringValue = "\(selection.urls.count) Selected"
        fileLabels.forEach { $0.removeFromSuperview() }
        removeButtons.forEach { $0.removeFromSuperview() }
        fileLabels = []
        removeButtons = []
        for url in selection.urls {
            let label = NSTextField(labelWithString: url.lastPathComponent)
            label.font = .systemFont(ofSize: 13)
            label.lineBreakMode = .byTruncatingMiddle
            addSubview(label)
            fileLabels.append(label)
            let button = NSButton(title: "Remove " + url.lastPathComponent, target: self, action: #selector(removeFile(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(url.lastPathComponent)
            button.bezelStyle = .rounded
            button.cell?.lineBreakMode = .byTruncatingTail
            addSubview(button)
            removeButtons.append(button)
        }
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        // The observer enters four points above this header, inside exactly
        // eight points of top padding. Its -24 point exit is outside this view.
        countLabel.frame = NSRect(x: 8, y: 8, width: 180, height: 20)
        clearButton.frame = NSRect(x: max(196, bounds.width - 88), y: 5, width: 80, height: 26)
        for index in fileLabels.indices {
            let y = CGFloat(44 + index * 52)
            fileLabels[index].frame = NSRect(x: 16, y: y + 4, width: max(100, bounds.width - 180), height: 24)
            removeButtons[index].frame = NSRect(x: max(128, bounds.width - 148), y: y, width: 132, height: 30)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 12, yRadius: 12)
        NSColor.controlBackgroundColor.setFill()
        border.fill()
        (targeted ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        border.lineWidth = targeted ? 2 : 1
        border.setLineDash([5, 5], count: 2, phase: 0)
        border.stroke()
    }

    @objc private func clearSelection() { selection.clear() }

    @objc private func removeFile(_ sender: NSButton) {
        if let name = sender.identifier?.rawValue { selection.remove(name) }
    }

    private func acceptedURLs(_ sender: NSDraggingInfo) -> [URL]? {
        guard sender.draggingSourceOperationMask.contains(.copy),
              let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                  options: [.urlReadingFileURLsOnly: true]) as? [URL] else { return nil }
        return try? selection.configuration.validated(urls)
    }

    private func record(_ callback: String, sender: NSDraggingInfo?, extra: [String: Any] = [:]) {
        var fields = selection.configuration.originalState()
        fields.merge(extra) { _, new in new }
        fields["selectedFilenames"] = selection.urls.map(\.lastPathComponent)
        fields["targeted"] = targeted
        fields["applicationActive"] = NSApp.isActive
        fields["currentModifierFlags"] = NSEvent.modifierFlags.rawValue
        if let event = NSApp.currentEvent {
            fields["applicationCurrentEventType"] = event.type.rawValue
            fields["applicationCurrentEventTimestamp"] = event.timestamp
            fields["applicationCurrentEventModifierFlags"] = event.modifierFlags.rawValue
        }
        if let sender {
            fields["sequenceNumber"] = sender.draggingSequenceNumber
            fields["sourceAllowedOperationMask"] = sender.draggingSourceOperationMask.rawValue
            fields["pasteboardTypes"] = sender.draggingPasteboard.types?.map(\.rawValue).sorted() ?? []
            fields["sourceIsInThisApplication"] = sender.draggingSource != nil
            fields["draggingLocationInWindow"] = ["x": sender.draggingLocation.x, "y": sender.draggingLocation.y]
        }
        selection.trace.record(callback, fields)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let accepted = acceptedURLs(sender) != nil
        targeted = accepted
        record("draggingEntered", sender: sender, extra: ["returnedCopy": accepted])
        return accepted ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let accepted = acceptedURLs(sender) != nil
        targeted = accepted
        record("draggingUpdated", sender: sender, extra: ["returnedCopy": accepted])
        return accepted ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        targeted = false
        record("draggingExited", sender: sender)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        targeted = false
        record("draggingEnded", sender: sender,
               extra: ["scope": "Destination notification; source operation result is not available here."])
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let accepted = acceptedURLs(sender) != nil
        record("prepareForDragOperation", sender: sender, extra: ["accepted": accepted])
        return accepted
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { targeted = false }
        guard let urls = acceptedURLs(sender) else {
            record("performDragOperation", sender: sender, extra: ["accepted": false])
            return false
        }
        do {
            try selection.append(urls, origin: "performDragOperation")
            record("performDragOperation", sender: sender, extra: ["accepted": true])
            return true
        } catch {
            record("performDragOperation", sender: sender,
                   extra: ["accepted": false, "reason": String(describing: error)])
            return false
        }
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        targeted = false
        record("concludeDragOperation", sender: sender)
    }
}

@MainActor
private final class ControlContentView: NSView {
    private let heading = NSTextField(labelWithString: "Standard AppKit Drag Control")
    private let explanation: NSTextField
    private let destination: ControlDropView
    override var isFlipped: Bool { true }

    init(selection: ControlSelection) {
        explanation = NSTextField(labelWithString: "\(selection.configuration.theme.capitalized) fixture scenario · separate control, not Lemulip UI")
        destination = ControlDropView(selection: selection)
        super.init(frame: NSRect(x: 0, y: 0, width: 920, height: 532))
        heading.font = .systemFont(ofSize: 22, weight: .semibold)
        explanation.font = .systemFont(ofSize: 12)
        explanation.textColor = .secondaryLabelColor
        addSubview(heading)
        addSubview(explanation)
        addSubview(destination)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        heading.frame = NSRect(x: 24, y: 20, width: bounds.width - 48, height: 30)
        explanation.frame = NSRect(x: 24, y: 54, width: bounds.width - 48, height: 20)
        destination.frame = NSRect(x: 24, y: 92, width: bounds.width - 48, height: min(320, bounds.height - 116))
    }
}

@MainActor
private final class ControlDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let selection: ControlSelection
    private let activationJournal: ActivationJournal?
    private var window: NSWindow?
    var watchdog: DispatchSourceTimer?

    init(selection: ControlSelection, activationJournal: ActivationJournal?) {
        self.selection = selection
        self.activationJournal = activationJournal
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let window = NSWindow(contentRect: NSRect(x: 80, y: 100, width: 920, height: 532),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        if activationJournal != nil { window.delegate = self }
        window.title = "Native Drag Control"
        window.contentMinSize = NSSize(width: 720, height: 532)
        window.isReleasedWhenClosed = false
        window.contentView = ControlContentView(selection: selection)
        self.window = window
        (NSApp as? ControlApplication)?.observedWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        selection.trace.record("application-ready", ["windowTitle": window.title,
                               "scope": "Separate standard AppKit destination, no custom Escape handling."])
        if let activationJournal {
            let received = ProcessInfo.processInfo.systemUptime
            var fields = activationState(window: window, received: received)
            fields["windowTitle"] = window.title
            fields["windowClass"] = NSStringFromClass(type(of: window))
            fields["normalNSWindow"] = !(window is NSPanel)
            fields["targetAXRaiseOverrideInstalled"] = false
            fields["targetRaiseObservation"] = "observer-request-ledger-only"
            fields["styleMask"] = window.styleMask.rawValue
            fields["windowLevel"] = window.level.rawValue
            #if LEMULIP_EVENT_ORIGIN_TRACE
            fields["targetMouseEventIdentitySchema"] = 1
            #endif
            #if LEMULIP_DISPATCH_STACK_TRACE
            fields["targetDispatchStackSchema"] = 1
            #endif
            #if LEMULIP_RECEIVER_SYNC_TRACE
            fields["receiverTraceSynchronizationSchema"] = 1
            #endif
            activationJournal.record("activation-ready", fields)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) { receive(urls, origin: "open-urls") }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let accepted = receive(filenames.map { URL(fileURLWithPath: $0) }, origin: "open-files")
        sender.reply(toOpenOrPrint: accepted ? .success : .failure)
    }

    @discardableResult
    private func receive(_ urls: [URL], origin: String) -> Bool {
        do { try selection.append(urls, origin: origin); return true }
        catch {
            selection.trace.record("open-rejected", ["origin": origin, "requestedCount": urls.count,
                                   "reason": String(describing: error)])
            return false
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDidBecomeActive(_ notification: Notification) {
        let received = ProcessInfo.processInfo.systemUptime
        activationJournal?.record("application-became-active", activationState(window: window, received: received))
        selection.trace.record("application-became-active")
    }

    func applicationDidResignActive(_ notification: Notification) {
        let received = ProcessInfo.processInfo.systemUptime
        activationJournal?.record("application-resigned-active", activationState(window: window, received: received))
        selection.trace.record("application-resigned-active")
    }

    func windowDidBecomeKey(_ notification: Notification) {
        let received = ProcessInfo.processInfo.systemUptime
        activationJournal?.record("window-became-key", activationState(window: window, received: received))
    }

    func windowDidResignKey(_ notification: Notification) {
        let received = ProcessInfo.processInfo.systemUptime
        activationJournal?.record("window-resigned-key", activationState(window: window, received: received))
    }

    func windowDidBecomeMain(_ notification: Notification) {
        let received = ProcessInfo.processInfo.systemUptime
        activationJournal?.record("window-became-main", activationState(window: window, received: received))
    }

    func windowDidResignMain(_ notification: Notification) {
        let received = ProcessInfo.processInfo.systemUptime
        activationJournal?.record("window-resigned-main", activationState(window: window, received: received))
    }

    func applicationWillTerminate(_ notification: Notification) {
        let received = ProcessInfo.processInfo.systemUptime
        watchdog?.cancel()
        let originals = selection.configuration.originalState()
        selection.trace.record("application-terminated", originals)
        if let activationJournal {
            var fields = activationState(window: window, received: received)
            fields.merge(originals) { _, value in value }
            #if LEMULIP_DISPATCH_STACK_TRACE
            if let application = NSApp as? ControlApplication {
                fields["dispatchStackObservation"] = application.finishDispatchStackObservation()
            }
            #endif
            #if LEMULIP_RECEIVER_SYNC_TRACE
            fields["receiverTraceSynchronization"] = selection.trace.finishSynchronization(phase: "termination")
            #endif
            activationJournal.record("activation-terminating", fields)
            activationJournal.flush()
        }
    }
}

@main
private enum NativeDragControl {
    @MainActor
    static func main() {
        do {
            let configuration = try ControlConfiguration()
            let trace = try ControlTrace(url: configuration.traceURL, sourceBinding: configuration.sourceBinding)
            let activationJournal = try configuration.activationCase.map { _ in try ActivationJournal(configuration: configuration) }
            guard let application = ControlApplication.shared as? ControlApplication else {
                throw ControlIssue.invalid("The passive NSApplication subclass did not initialize")
            }
            application.trace = trace
            application.activationJournal = activationJournal
            let selection = ControlSelection(configuration: configuration, trace: trace)
            let delegate = ControlDelegate(selection: selection, activationJournal: activationJournal)
            application.delegate = delegate
            if let activationJournal {
                let received = ProcessInfo.processInfo.systemUptime
                var fields = activationState(window: nil, received: received)
                fields.merge(activationJournal.startupFields) { _, value in value }
                fields.merge(configuration.originalState()) { _, value in value }
                activationJournal.record("activation-start", fields)
            }
            trace.record("application-start", [
                "bundleIdentifier": "app.lemulip.NativeDragControl", "theme": configuration.theme,
                "bundlePath": Bundle.main.bundleURL.standardizedFileURL.path,
                "executablePath": Bundle.main.executableURL?.standardizedFileURL.path ?? "",
                "stagingRoot": configuration.root.path,
                "evidenceKind": configuration.evidenceKind,
                "fixtureFilenames": configuration.originals.keys.sorted(),
                "originalSHA256": configuration.originals.mapValues { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() },
                "sendEventSubclassInstalled": true, "maximumLifetimeSeconds": 150,
                "scope": "Diagnostic AppKit control; production drag behavior is unchanged."
            ])
            // A one-shot process bound, not input polling. It also runs if an
            // AppKit tracking loop is active when the observer stops responding.
            let watchdog = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
            watchdog.schedule(deadline: .now() + 150)
            watchdog.setEventHandler {
                let received = ProcessInfo.processInfo.systemUptime
                let originals = configuration.originalState()
                var fields = originals
                fields["callbackSystemUptime"] = received
                trace.record("application-timeout", originals)
                #if LEMULIP_RECEIVER_SYNC_TRACE
                fields["receiverTraceSynchronization"] = trace.finishSynchronization(phase: "watchdog")
                #endif
                activationJournal?.record("activation-timeout", fields)
                activationJournal?.flush()
                Darwin.exit(124)
            }
            delegate.watchdog = watchdog
            watchdog.resume()
            withExtendedLifetime(delegate) { application.run() }
        } catch {
            FileHandle.standardError.write(Data(("Native drag control failed: \(error)\n").utf8))
            Darwin.exit(2)
        }
    }
}
