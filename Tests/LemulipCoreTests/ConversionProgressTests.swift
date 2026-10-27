import XCTest
@testable import LemulipCore

private final class ProgressEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ConversionProgress] = []
    func append(_ value: ConversionProgress) { lock.lock(); storage.append(value); lock.unlock() }
    var values: [ConversionProgress] { lock.lock(); defer { lock.unlock() }; return storage }
}

final class ConversionProgressTests: XCTestCase {
    func testProgressIsAbsentUntilReportedAndFinishesOnlyAfterPublication() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let inputs = ["a.srt", "b.srt"].map { root.appendingPathComponent($0) }
        for input in inputs { try "1\n00:00:01,000 --> 00:00:02,000\nHello\n".write(to: input, atomically: true, encoding: .utf8) }
        let events = ProgressEvents()
        let result = try await ConversionEngine().run(inputs: inputs, operation: FileOperation(id: "convert.vtt", title: "VTT"), progress: events.append)
        XCTAssertEqual(result.outputs.count, 2)
        XCTAssertEqual(events.values.first?.phase, .preparing)
        XCTAssertTrue(events.values.contains { $0.completedFiles == 1 && $0.totalFiles == 2 })
        XCTAssertTrue(events.values.contains { $0.phase == .publishing })
        XCTAssertEqual(events.values.last?.phase, .finished)
        XCTAssertEqual(events.values.last?.fractionCompleted, 1)
        XCTAssertFalse(events.values.dropLast().contains { $0.fractionCompleted == 1 })
    }
    func testFailureDoesNotReportFinishedOrPublishPartialBatch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("a.srt"), second = root.appendingPathComponent("b.srt")
        try "1\n00:00:01,000 --> 00:00:02,000\nHello\n".write(to: first, atomically: true, encoding: .utf8)
        try "not a subtitle".write(to: second, atomically: true, encoding: .utf8)
        let events = ProgressEvents()
        do {
            _ = try await ConversionEngine().run(inputs: [first, second], operation: FileOperation(id: "convert.vtt", title: "VTT"), progress: events.append)
            XCTFail("Expected invalid subtitle")
        } catch {}
        XCTAssertFalse(events.values.contains { $0.phase == .finished })
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("a.vtt").path))
    }
    func testFFmpegProgressHandlesChunkBoundariesInvalidValuesAndBounds() {
        let events = ProgressEvents()
        let parser = FFmpegProgressParser(duration: 10) { fraction in
            events.append(ConversionProgress(phase: .converting, completedFiles: 0, totalFiles: 1, fileFraction: fraction))
        }
        parser.consume(Data("out_time_".utf8)); parser.consume(Data("us=2500000\nprogress=continue\n".utf8))
        XCTAssertEqual(events.values.last?.fileFraction, 0.25)
        for line in ["out_time_us=N/A\n", "out_time_us=-1\n", "out_time_us=nan\n"] { parser.consume(Data(line.utf8)) }
        XCTAssertEqual(events.values.last?.fileFraction, 0.25)
        parser.consume(Data(repeating: 65, count: 100_000)); parser.consume(Data("\nout_time_us=99999999\n".utf8))
        XCTAssertEqual(events.values.last?.fileFraction, 1)
        XCTAssertLessThanOrEqual(parser.bufferedByteCount, 4096)
        XCTAssertLessThan(events.values.last!.fractionCompleted!, 1)
    }
    func testProcessStreamingContinuesAfterCapturedOutputBudget() async throws {
        let events = ProgressEvents()
        let parser = FFmpegProgressParser(duration: 10) { fraction in
            events.append(ConversionProgress(phase: .converting, completedFiles: 0, totalFiles: 1, fileFraction: fraction))
        }
        let result = try await ProcessRunner.run(executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf 'out_time_us=2500000\\n'; printf 'out_time_us=7500000\\n'"],
            maximumOutputBytes: 5, standardOutputHandler: { parser.consume($0) })
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.standardOutput.count, 5)
        XCTAssertEqual(events.values.map { $0.fileFraction }, [0.25, 0.75])
    }

    func testUnknownDurationDoesNotInventAPercentage() {
        let events = ProgressEvents()
        let parser = FFmpegProgressParser(duration: nil) { _ in XCTFail("Unknown duration is indeterminate") }
        parser.consume(Data("out_time_us=1000000\nprogress=end\n".utf8))
        let progress = ConversionProgress(phase: .converting, completedFiles: 0, totalFiles: 3, fileFraction: nil)
        XCTAssertNil(progress.fractionCompleted)
        XCTAssertTrue(events.values.isEmpty)
    }
    func testRetryKeepsExactRequestOptionsAndOnlyAllowsFailedConversions() {
        var options = ConversionOptions(); options.startSeconds = 12.34; options.endSeconds = 22.45
        options.destinationDirectory = URL(fileURLWithPath: "/tmp/chosen")
        options.removeMetadata = false; options.quality = 0.37
        let request = ConversionRequest(inputs: [URL(fileURLWithPath: "/tmp/clip.mp4")], operation: FileOperation(id: "media.trim", title: "Trim"), options: options)
        XCTAssertEqual(request.options.startSeconds, 12.34)
        XCTAssertEqual(request.options.destinationDirectory, options.destinationDirectory)
        XCTAssertFalse(request.options.removeMetadata)
        XCTAssertTrue(request.canRetry(after: .failed)); XCTAssertTrue(request.canRetry(after: .cancelled))
        for state in [ConversionJobState.waiting, .running, .succeeded] { XCTAssertFalse(request.canRetry(after: state)) }
        let move = ConversionRequest(inputs: request.inputs, operation: FileOperation(id: "action.move", title: "Move"), options: options)
        XCTAssertFalse(move.canRetry(after: .failed))
    }
}
