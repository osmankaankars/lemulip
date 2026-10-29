#if os(macOS)
import AppKit
import AudioToolbox
import AVFoundation
import XCTest
import LemulipCore
@testable import Lemulip

final class SelectionFeedbackTests: XCTestCase {
    @MainActor
    func testPreferenceStartsOffAndSurvivesControllerRecreation() async throws {
        try await withFixture { fixture in
            let controller = AppController(selectionFeedback: fixture.feedback)
            XCTAssertFalse(controller.selectionSoundsEnabled)
            XCTAssertNil(fixture.defaults.object(forKey: SelectionFeedback.preferenceKey))

            controller.selectionSoundsEnabled = true
            let restored = SelectionFeedback(defaults: fixture.defaults, player: CueSpy())
            let restoredController = AppController(selectionFeedback: restored)
            XCTAssertTrue(restoredController.selectionSoundsEnabled)
            restoredController.selectionSoundsEnabled = false
            XCTAssertFalse(SelectionFeedback(defaults: fixture.defaults, player: CueSpy()).isEnabled)
            XCTAssertEqual(fixture.player.starts, 0, "Changing the preference itself must stay quiet")
        }
    }

    @MainActor
    func testExplicitPreviewWorksWithoutOptingIn() async throws {
        try await withFixture { fixture in
            let controller = AppController(selectionFeedback: fixture.feedback)
            controller.previewSelectionSound()
            XCTAssertEqual(fixture.player.starts, 1)
            XCTAssertFalse(controller.selectionSoundsEnabled)
            XCTAssertNil(fixture.defaults.object(forKey: SelectionFeedback.preferenceKey))

            fixture.player.complete(0)
            fixture.clock.time += 1
            fixture.feedback.commit(SelectionFeedback.Choice())
            XCTAssertEqual(fixture.player.starts, 1)
        }
    }

    @MainActor
    func testAChoiceIsConsumedEvenWhileDisabled() async throws {
        try await withFixture { fixture in
            let choice = SelectionFeedback.Choice()
            fixture.feedback.commit(choice)
            fixture.feedback.isEnabled = true
            fixture.feedback.commit(choice)
            XCTAssertEqual(fixture.player.starts, 0,
                           "Enabling sound must not replay a previously silent event")

            let next = SelectionFeedback.Choice()
            fixture.feedback.commit(next)
            fixture.player.complete(0)
            fixture.clock.time += 10
            fixture.feedback.commit(next)
            XCTAssertEqual(fixture.player.starts, 1,
                           "The same committed choice must never play twice")
        }
    }

    @MainActor
    func testRapidChoicesDoNotOverlapOrQueueDelayedCues() async throws {
        try await withFixture { fixture in
            fixture.feedback.isEnabled = true
            fixture.feedback.commit(SelectionFeedback.Choice())
            fixture.clock.time = 1
            let overlapping = SelectionFeedback.Choice()
            fixture.feedback.commit(overlapping)
            fixture.feedback.preview()
            XCTAssertEqual(fixture.player.starts, 1)

            fixture.player.complete(0)
            fixture.feedback.commit(overlapping)
            XCTAssertEqual(fixture.player.starts, 1, "An overlap must be dropped, not queued")
            fixture.feedback.commit(SelectionFeedback.Choice())
            XCTAssertEqual(fixture.player.starts, 2)

            fixture.player.complete(1)
            fixture.clock.time = 1.1
            let rapid = SelectionFeedback.Choice()
            fixture.feedback.commit(rapid)
            XCTAssertEqual(fixture.player.starts, 2)
            fixture.clock.time = 1.3
            fixture.feedback.commit(rapid)
            XCTAssertEqual(fixture.player.starts, 2)
            fixture.feedback.commit(SelectionFeedback.Choice())
            XCTAssertEqual(fixture.player.starts, 3)
        }
    }

    @MainActor
    func testDisableAndShutdownInvalidateLateCompletionCallbacks() async throws {
        try await withFixture { fixture in
            fixture.feedback.isEnabled = true
            fixture.feedback.preview()
            fixture.feedback.isEnabled = false
            XCTAssertEqual(fixture.player.stops, 1)

            fixture.clock.time = 1
            fixture.feedback.isEnabled = true
            fixture.feedback.preview()
            fixture.player.complete(0) // Completion from the disposed sound object.
            fixture.clock.time = 2
            fixture.feedback.preview()
            XCTAssertEqual(fixture.player.starts, 2,
                           "A late callback must not unlock a newer active cue")

            fixture.player.complete(1)
            fixture.feedback.preview()
            XCTAssertEqual(fixture.player.starts, 3)
            fixture.feedback.shutdown()
            fixture.player.complete(2)
            fixture.clock.time = 3
            fixture.feedback.preview()
            fixture.feedback.commit(SelectionFeedback.Choice())
            XCTAssertEqual(fixture.player.starts, 3)
        }
    }

    @MainActor
    func testUnavailableAudioDoesNotBlockSubsequentChoices() async throws {
        try await withFixture { fixture in
            fixture.feedback.isEnabled = true
            fixture.player.available = false
            let unavailable = SelectionFeedback.Choice()
            fixture.feedback.commit(unavailable)
            XCTAssertEqual(fixture.player.starts, 0)

            fixture.player.available = true
            fixture.feedback.commit(unavailable)
            XCTAssertEqual(fixture.player.starts, 0)
            fixture.feedback.commit(SelectionFeedback.Choice())
            XCTAssertEqual(fixture.player.starts, 1)
        }
    }

    @MainActor
    func testWorkspaceAndWheelInputRoutesEmitOncePerCommittedBatch() async throws {
        try await withFixture { fixture in
            try await withController(fixture) { controller in
                controller.selectionSoundsEnabled = true
                let inputs = try fixture.textInputs()
                let operation = FileOperation(id: "convert.txt", title: "TXT", outputExtension: "txt")
                controller.files = inputs
                controller.begin(operation) // Workspace, pinned tools, and search route.
                XCTAssertEqual(fixture.player.starts, 1)
                XCTAssertEqual(controller.activity.count, 1)
                XCTAssertEqual(controller.activity[0].inputs.count, 2)
                try await waitForJobs(controller)
                XCTAssertEqual(controller.activity[0].state, .succeeded)
                XCTAssertEqual(fixture.player.starts, 1, "Progress and completion must stay quiet")

                fixture.player.complete(0)
                fixture.clock.time += 1
                controller.files = []
                controller.begin(operation, inputs: inputs) // The wheel's explicit-input route.
                XCTAssertEqual(fixture.player.starts, 2)
                try await waitForJobs(controller)
                XCTAssertEqual(controller.activity.count, 2)
                XCTAssertTrue(controller.activity.allSatisfy { $0.state == .succeeded })
                XCTAssertEqual(fixture.player.starts, 2)
            }
        }
    }

    @MainActor
    func testOptionsAreSilentUntilConfirmationAndCancellationStaysSilent() async throws {
        try await withFixture { fixture in
            try await withController(fixture) { controller in
                controller.selectionSoundsEnabled = true
                let input = try fixture.imageInput()
                let operation = FileOperation(id: "image.resize", title: "Resize")
                controller.begin(operation, inputs: [input])
                XCTAssertNotNil(controller.pendingOperation)
                XCTAssertEqual(fixture.player.starts, 0)
                controller.cancelPending()
                controller.submitPending(ConversionOptions())
                XCTAssertEqual(fixture.player.starts, 0)
                XCTAssertTrue(controller.activity.isEmpty)

                controller.begin(operation, inputs: [input])
                var options = ConversionOptions()
                options.width = 12; options.height = 12
                options.destinationDirectory = fixture.directory
                controller.submitPending(options)
                controller.submitPending(options) // A duplicate final-action callback.
                XCTAssertEqual(fixture.player.starts, 1)
                XCTAssertEqual(controller.activity.count, 1)
                try await waitForJobs(controller)
                XCTAssertEqual(controller.activity[0].state, .succeeded)
                XCTAssertEqual(fixture.player.starts, 1)
            }
        }
    }

    @MainActor
    func testCanceledDestinationAndUnavailableOperationsStaySilent() async throws {
        try await withFixture { fixture in
            var destinationRequests = 0
            try await withController(fixture, destinationPicker: { _ in
                destinationRequests += 1
                return nil
            }) { controller in
                controller.selectionSoundsEnabled = true
                let inputs = try fixture.textInputs()
                controller.files = inputs
                controller.outputAlongsideOriginal = false
                controller.begin(FileOperation(id: "convert.txt", title: "TXT", outputExtension: "txt"))
                controller.begin(FileOperation(id: "action.copy", title: "Copy"))
                controller.begin(FileOperation(id: "action.move", title: "Move"))
                XCTAssertEqual(destinationRequests, 3)
                XCTAssertTrue(controller.activity.isEmpty)
                XCTAssertEqual(fixture.player.starts, 0)

                controller.begin(FileOperation(id: "convert.test", title: "Unavailable",
                                               dependency: "lemulip-no-such-test-engine"))
                XCTAssertNotNil(controller.alertMessage)
                controller.begin(FileOperation(id: "convert.txt", title: "TXT"), inputs: [])
                controller.begin(FileOperation(id: "action.float", title: "Shelf"),
                                 inputs: [fixture.directory.appendingPathComponent("missing.txt")])
                XCTAssertEqual(fixture.player.starts, 0)
                XCTAssertTrue(controller.activity.isEmpty)
            }
        }
    }

    @MainActor
    func testGeneratedCueDecodesAsShortQuietPCMAndDeletesItsPrivateFile() async throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("Lemulip-Cue-Test-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: parent) }
        var resource: SelectionCueFile? = try SelectionCueFile(parent: parent)
        let url = try XCTUnwrap(resource?.url)
        let data = try Data(contentsOf: url)
        XCTAssertEqual(data, SelectionCue.waveData(), "Playback must use the original generator's bytes")
        if let path = ProcessInfo.processInfo.environment["LEMULIP_SELECTION_REVIEW_DIR"] {
            let review = URL(fileURLWithPath: path, isDirectory: true)
            try FileManager.default.createDirectory(at: review, withIntermediateDirectories: true)
            try data.write(to: review.appendingPathComponent("selection.wav"), options: .withoutOverwriting)
            let environment = ProcessInfo.processInfo.environment
            let record: [String: Any] = [
                "sourceCommit": environment["LEMULIP_SELECTION_REVIEW_COMMIT"] ?? environment["GITHUB_SHA"] ?? "local",
                "workflowRun": environment["GITHUB_RUN_ID"] ?? "local",
                "generator": "Sources/Lemulip/SelectionCue.swift: SelectionCue.waveData()",
                "sampleRate": SelectionCue.sampleRate, "frameCount": SelectionCue.frameCount,
                "bytes": data.count, "listeningReviewPerformed": false
            ]
            let provenance = try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
            try provenance.write(to: review.appendingPathComponent("provenance.json"), options: .withoutOverwriting)
        }
        XCTAssertLessThan(data.count, 8_192)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int, 0o600)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: url.deletingLastPathComponent().path)[.posixPermissions] as? Int, 0o700)

        // Decode using the platform rather than trusting our own WAVE header writer.
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let duration = Double(file.length) / file.processingFormat.sampleRate
        XCTAssertEqual(file.processingFormat.channelCount, 1)
        XCTAssertGreaterThanOrEqual(duration, 0.04)
        XCTAssertLessThanOrEqual(duration, 0.08)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                   frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let samples = try XCTUnwrap(buffer.floatChannelData)[0]
        let values = Array(UnsafeBufferPointer(start: samples, count: Int(buffer.frameLength)))
        let peak = values.map { abs($0) }.max() ?? 0
        XCTAssertGreaterThan(peak, 0.03, "The cue must not be empty or accidentally silent")
        XCTAssertLessThan(peak, 0.18, "The generated PCM must retain ample headroom")
        XCTAssertEqual(values.first, 0)
        XCTAssertLessThan(abs(try XCTUnwrap(values.last)), 0.001)

        resource = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: parent.path).isEmpty)
    }

    @MainActor
    func testNativeSoundUsesUIPolicyAndDisposesWithoutPlaying() async throws {
        let player = SystemSelectionCuePlayer()
        defer { player.stop() }
        XCTAssertTrue(player.prepare(), "The native System Sound object must load with its UI policy")
        var identifier = try XCTUnwrap(player.soundID)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        XCTAssertEqual(AudioServicesGetProperty(kAudioServicesPropertyIsUISound,
            UInt32(MemoryLayout<SystemSoundID>.size), &identifier, &size, &value), kAudioServicesNoError)
        XCTAssertEqual(value, 1, "The cue must never bypass macOS UI-sound effects preferences")
        value = 1
        XCTAssertEqual(AudioServicesGetProperty(kAudioServicesPropertyCompletePlaybackIfAppDies,
            UInt32(MemoryLayout<SystemSoundID>.size), &identifier, &size, &value), kAudioServicesNoError)
        XCTAssertEqual(value, 0)
        player.stop()
        XCTAssertNil(player.soundID)
    }

    @MainActor
    private func withFixture(_ body: (FeedbackFixture) async throws -> Void) async throws {
        let fixture = try FeedbackFixture()
        defer { fixture.close() }
        try await body(fixture)
    }

    @MainActor
    private func withController(_ fixture: FeedbackFixture,
                                destinationPicker: ((String) -> URL?)? = nil,
                                _ body: (AppController) async throws -> Void) async throws {
        _ = NSApplication.shared
        let keys = ["outputAlongsideOriginal", "completionPresentation", "revealWhenFinished"]
        let saved = keys.map { ($0, UserDefaults.standard.object(forKey: $0)) }
        let controller = AppController(selectionFeedback: fixture.feedback, destinationPicker: destinationPicker)
        controller.outputAlongsideOriginal = true
        controller.completionPresentation = .quiet
        defer {
            controller.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
            for (key, value) in saved {
                if let value { UserDefaults.standard.set(value, forKey: key) }
                else { UserDefaults.standard.removeObject(forKey: key) }
            }
        }
        try await body(controller)
    }

    @MainActor
    private func waitForJobs(_ controller: AppController) async throws {
        for _ in 0..<150 {
            if !controller.isBusy { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("The small native fixture did not finish within three seconds")
    }
}

@MainActor
private final class CueSpy: SelectionCuePlaying {
    var available = true
    private(set) var starts = 0
    private(set) var stops = 0
    private var completions: [@MainActor () -> Void] = []

    func play(completion: @escaping @MainActor () -> Void) -> Bool {
        guard available else { return false }
        starts += 1
        completions.append(completion)
        return true
    }

    func complete(_ index: Int) { completions[index]() }
    func stop() { stops += 1 }
}

@MainActor
private final class CueClock { var time: TimeInterval = 0 }

@MainActor
private final class FeedbackFixture {
    let suite: String
    let defaults: UserDefaults
    let player: CueSpy
    let clock: CueClock
    let feedback: SelectionFeedback
    let directory: URL

    init() throws {
        let suite = "Lemulip.SelectionFeedback.Tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Lemulip-Feedback-Test-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        let player = CueSpy()
        let clock = CueClock()
        self.suite = suite
        self.defaults = defaults
        self.directory = directory
        self.player = player
        self.clock = clock
        feedback = SelectionFeedback(defaults: defaults, player: player, now: { clock.time })
    }

    func textInputs() throws -> [URL] {
        try ["first", "second"].map { name in
            let url = directory.appendingPathComponent(name + ".md")
            try Data("# Synthetic selection test\n\nA short local document.\n".utf8).write(to: url)
            return url
        }
    }

    func imageInput() throws -> URL {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for y in 0..<16 { for x in 0..<16 { bitmap.setColor(.systemGreen, atX: x, y: y) } }
        let url = directory.appendingPathComponent("sample.png")
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
        return url
    }

    func close() {
        feedback.shutdown()
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}
#endif
