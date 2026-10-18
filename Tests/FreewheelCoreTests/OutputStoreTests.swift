import XCTest
@testable import FreewheelCore

final class OutputStoreTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("freewheel-output-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }
    override func tearDownWithError() throws { if let root { try FileManager.default.removeItem(at: root) } }

    func testPublicationKeepsOriginalAndExistingConvertedFiles() throws {
        let original = root.appendingPathComponent("note.txt")
        try "Original".write(to: original, atomically: true, encoding: .utf8)
        try "Older output".write(to: root.appendingPathComponent("note (2).txt"), atomically: true, encoding: .utf8)
        let stage = try OutputStore.prepare(destination: root)
        let source = stage.appendingPathComponent("note.txt")
        try "New output".write(to: source, atomically: true, encoding: .utf8)
        let result = try OutputStore.publish(ConversionResult(outputs: [source]), from: stage, to: root)
        XCTAssertEqual(result.outputs.first?.lastPathComponent, "note (3).txt")
        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "Original")
        XCTAssertEqual(try String(contentsOf: result.outputs[0], encoding: .utf8), "New output")
    }

    func testBrokenSymlinkIsNeverReplaced() throws {
        let link = root.appendingPathComponent("note.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root.appendingPathComponent("missing"))
        XCTAssertEqual(OutputStore.uniqueURL(in: root, stem: "note", extension: "txt").lastPathComponent, "note (2).txt")
    }

    func testOutputNamesCannotEscapeTheirFolder() {
        let output = OutputStore.uniqueURL(in: root, stem: "../../outside\nfile", extension: "../../txt")
        XCTAssertEqual(output.deletingLastPathComponent().path, root.path)
        XCTAssertLessThan(OutputStore.safeStem(String(repeating: "🧡", count: 200)).utf8.count, 181)
    }

    func testSymlinkedOutputAncestorIsRejected() throws {
        let outside = root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        try "Keep".write(to: outside.appendingPathComponent("secret.txt"), atomically: true, encoding: .utf8)
        let stage = try OutputStore.prepare(destination: root)
        try FileManager.default.createSymbolicLink(at: stage.appendingPathComponent("link"), withDestinationURL: outside)
        XCTAssertThrowsError(try OutputStore.publish(ConversionResult(outputs: [stage.appendingPathComponent("link/secret.txt")]), from: stage, to: root))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("secret.txt").path))
    }

    func testFailedBatchPublicationRollsBackOnlyItsOwnOutputs() throws {
        let stage = try OutputStore.prepare(destination: root)
        let source = stage.appendingPathComponent("new.txt")
        try "New".write(to: source, atomically: true, encoding: .utf8)
        let existing = root.appendingPathComponent("keep.txt")
        try "Keep".write(to: existing, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try OutputStore.publish(ConversionResult(outputs: [source, existing]), from: stage, to: root))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("new.txt").path))
        XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), "Keep")
    }

    func testExclusiveCopyFallbackPreservesExistingFilesAndCopiesBytes() throws {
        let source = root.appendingPathComponent("source.dat")
        let destination = root.appendingPathComponent("destination.dat")
        let bytes = Data((0..<150_000).map { UInt8($0 % 251) })
        try bytes.write(to: source)
        XCTAssertTrue(try OutputStore.copyFileExclusively(source, to: destination))
        XCTAssertEqual(try Data(contentsOf: destination), bytes)
        try "Changed source".write(to: source, atomically: true, encoding: .utf8)
        XCTAssertFalse(try OutputStore.copyFileExclusively(source, to: destination))
        XCTAssertEqual(try Data(contentsOf: destination), bytes)
    }
}
