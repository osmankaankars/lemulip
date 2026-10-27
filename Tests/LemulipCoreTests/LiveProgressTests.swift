import XCTest
@testable import LemulipCore

private final class EncoderProgressEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ConversionProgress] = []
    func append(_ value: ConversionProgress) { lock.lock(); storage.append(value); lock.unlock() }
    var values: [ConversionProgress] { lock.lock(); defer { lock.unlock() }; return storage }
}

extension EngineIntegrationTests {
    func testRealFFmpegReportsProgressAndPreservesInput() async throws {
        guard let ffmpeg = EngineLocator.find("ffmpeg"), EngineLocator.find("ffprobe") != nil else {
            throw XCTSkip("FFmpeg and ffprobe are required for live progress coverage")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("progress tone.wav")
        _ = try await ProcessRunner.checked(executable: ffmpeg,
            arguments: ["-nostdin", "-hide_banner", "-loglevel", "error", "-n", "-f", "lavfi", "-i",
                        "sine=frequency=440:duration=1", "-c:a", "pcm_s16le", input.path], timeout: 30)
        let original = try Data(contentsOf: input)
        let output = root.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        let events = EncoderProgressEvents()
        let reporter = ConversionProgressReporter(inputs: [input], handler: events.append)
        reporter.setPhase(.converting)
        let result = try await ConversionProgressScope.$reporter.withValue(reporter) {
            try await ExternalConverters.media([input], operation: FileOperation(id: "convert.flac", title: "FLAC"),
                options: ConversionOptions(), directory: output)
        }
        XCTAssertTrue(events.values.contains { ($0.fileFraction ?? 0) > 0 }, "No progress arrived from the real encoder")
        XCTAssertEqual(events.values.last?.completedFiles, 1)
        XCTAssertFalse(events.values.contains { $0.phase == .finished || $0.fractionCompleted == 1 })
        XCTAssertEqual(try Data(contentsOf: result.outputs[0]).prefix(4), Data("fLaC".utf8))
        XCTAssertEqual(try Data(contentsOf: input), original)
    }
}
