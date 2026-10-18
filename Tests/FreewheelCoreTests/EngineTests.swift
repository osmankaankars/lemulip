import XCTest
@testable import FreewheelCore

final class EngineTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("freewheel-engine-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }
    override func tearDownWithError() throws { if let root { try FileManager.default.removeItem(at: root) } }

    func testBatchTextConversionAndConcurrencyNeverOverwriteInputs() async throws {
        let source = root.appendingPathComponent("subtitles.srt")
        let content = "1\n00:00:00,000 --> 00:00:01,000\nHello\n"
        try content.write(to: source, atomically: true, encoding: .utf8)
        let engine = ConversionEngine()
        let operation = FileOperation(id: "convert.vtt", title: "VTT", outputExtension: "vtt")
        async let first = engine.run(inputs: [source], operation: operation)
        async let second = engine.run(inputs: [source], operation: operation)
        let results = try await [first, second]
        XCTAssertEqual(Set(results.flatMap(\.outputs)).count, 2)
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), content)
        for output in results.flatMap(\.outputs) { XCTAssertTrue(try String(contentsOf: output, encoding: .utf8).hasPrefix("WEBVTT")) }
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains(where: { $0.hasPrefix(".freewheel-") }))
    }

    func testInvalidBatchLeavesNoPartialConvertedFiles() async throws {
        let valid = root.appendingPathComponent("valid.srt"), invalid = root.appendingPathComponent("invalid.srt")
        try "1\n00:00:00,000 --> 00:00:01,000\nHello\n".write(to: valid, atomically: true, encoding: .utf8)
        try "This is not a subtitle".write(to: invalid, atomically: true, encoding: .utf8)
        do {
            _ = try await ConversionEngine().run(inputs: [valid, invalid], operation: FileOperation(id: "convert.vtt", title: "VTT"))
            XCTFail("Converted an invalid batch")
        } catch { XCTAssertTrue(error is FreewheelError) }
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: root.path)), ["valid.srt", "invalid.srt"])
    }

    func testRemoteURLAndUnsafeExtensionAreRejected() async throws {
        do {
            _ = try await ConversionEngine().run(inputs: [URL(string: "https://example.com/file.png")!], operation: FileOperation(id: "convert.jpg", title: "JPG"))
            XCTFail("Accepted a remote input")
        } catch { XCTAssertTrue(error is FreewheelError) }
        let input = root.appendingPathComponent("table.csv")
        try "a,b\n1,2\n".write(to: input, atomically: true, encoding: .utf8)
        do {
            _ = try await ConversionEngine().run(inputs: [input], operation: FileOperation(id: "convert.tsv", title: "TSV", outputExtension: "../../outside"))
            XCTFail("Accepted an unsafe extension")
        } catch { XCTAssertTrue(error is FreewheelError) }
    }

    func testProcessDrainsBothLargePipesAndBoundsMemory() async throws {
        guard let awk = EngineLocator.find("awk") else { throw XCTSkip("awk is unavailable") }
        let program = "BEGIN { for (i=0; i<6000; i++) { print \"stdout line with enough bytes to fill a pipe\"; print \"stderr line with enough bytes to fill a pipe\" > \"/dev/stderr\" } }"
        let result = try await ProcessRunner.run(executable: awk, arguments: [program], maximumOutputBytes: 16_384, timeout: 10)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.standardOutput.count, 16_384)
        XCTAssertEqual(result.standardError.count, 16_384)
    }

    func testProcessCancellationAndTimeoutStopChild() async throws {
        guard let sleep = EngineLocator.find("sleep") else { throw XCTSkip("sleep is unavailable") }
        let start = Date()
        let running = Task { try await ProcessRunner.run(executable: sleep, arguments: ["30"], timeout: 40) }
        try await Task.sleep(nanoseconds: 100_000_000)
        running.cancel()
        do { _ = try await running.value; XCTFail("Cancellation was ignored") }
        catch { XCTAssertTrue(error is FreewheelError || error is CancellationError) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
        do { _ = try await ProcessRunner.run(executable: sleep, arguments: ["30"], timeout: 0.1); XCTFail("Timeout was ignored") }
        catch { XCTAssertTrue(error.localizedDescription.contains("time limit")) }
    }
}
