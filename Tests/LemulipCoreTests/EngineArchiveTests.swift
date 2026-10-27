import XCTest
@testable import LemulipCore

final class EngineArchiveTests: XCTestCase {
    private var root: URL!
    private let engine = ConversionEngine()
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("lemulip-archive-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }
    override func tearDownWithError() throws { if let root { try FileManager.default.removeItem(at: root) } }

    func testZIPAndTARRoundTripNestedFoldersAndUnicode() async throws {
        let folder = root.appendingPathComponent("Sample folder")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("nested"), withIntermediateDirectories: true)
        try "Hello 🌍".write(to: folder.appendingPathComponent("nested/read me.txt"), atomically: true, encoding: .utf8)
        try Data([0, 1, 2, 255]).write(to: folder.appendingPathComponent("bytes.bin"))
        for operation in ["archive.createZip", "archive.createTar"] {
            let archive = try await engine.run(inputs: [folder], operation: FileOperation(id: operation, title: "Archive"))
            let result = try await engine.run(inputs: archive.outputs, operation: FileOperation(id: "archive.extract", title: "Extract"))
            let extracted = try XCTUnwrap(result.outputs.first).appendingPathComponent("Sample folder")
            XCTAssertEqual(try String(contentsOf: extracted.appendingPathComponent("nested/read me.txt"), encoding: .utf8), "Hello 🌍")
            XCTAssertEqual(try Data(contentsOf: extracted.appendingPathComponent("bytes.bin")), Data([0, 1, 2, 255]))
            XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
        }
    }

    func testGzipRoundTripPreservesFilenameAndOriginal() async throws {
        let original = root.appendingPathComponent("notes.txt")
        let content = String(repeating: "A sample line.\n", count: 200)
        try content.write(to: original, atomically: true, encoding: .utf8)
        let compressed = try await engine.run(inputs: [original], operation: FileOperation(id: "archive.createGzip", title: "Gzip"))
        XCTAssertEqual(compressed.outputs.first?.lastPathComponent, "notes.txt.gz")
        let extracted = try await engine.run(inputs: compressed.outputs, operation: FileOperation(id: "archive.extract", title: "Extract"))
        XCTAssertEqual(try String(contentsOf: extracted.outputs[0].appendingPathComponent("notes.txt"), encoding: .utf8), content)
        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), content)
    }

    func testArchiveTraversalAndLinksAreRejectedWithoutPublishingPartialOutput() async throws {
        let invalidEntries: [(String, UInt8, String)] = [("../escaped.txt", 48, ""), ("/escaped.txt", 48, ""), ("safe/../../escaped.txt", 48, ""), ("C:\\escaped.txt", 48, ""), ("linked", 50, "../escaped.txt"), ("hardlinked", 49, "safe.txt"), ("device", 51, "")]
        for (index, item) in invalidEntries.enumerated() {
            let archive = root.appendingPathComponent("unsafe-\(index).tar")
            var data = tarEntry(name: "safe.txt", content: Data("safe".utf8))
            data += tarEntry(name: item.0, content: item.1 == 48 ? Data("unsafe".utf8) : Data(), type: item.1, link: item.2)
            data += Data(repeating: 0, count: 1024)
            try data.write(to: archive)
            do {
                _ = try await engine.run(inputs: [archive], operation: FileOperation(id: "archive.extract", title: "Extract"))
                XCTFail("Accepted an unsafe archive entry: \(item.0)")
            } catch { XCTAssertTrue(error is LemulipError) }
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("unsafe-\(index) extracted").path))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("escaped.txt").path))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains(where: { $0.hasPrefix(".lemulip-") }))
    }

    func testOversizedAndDuplicateArchiveEntriesAreRejected() async throws {
        let huge = root.appendingPathComponent("huge.tar")
        try (tarEntry(name: "huge.bin", content: Data(), declaredSize: 2_147_483_649) + Data(repeating: 0, count: 1024)).write(to: huge)
        let duplicate = root.appendingPathComponent("duplicate.tar")
        try (tarEntry(name: "same.txt", content: Data("first".utf8)) + tarEntry(name: "same.txt", content: Data("second".utf8)) + Data(repeating: 0, count: 1024)).write(to: duplicate)
        for input in [huge, duplicate] {
            do {
                _ = try await engine.run(inputs: [input], operation: FileOperation(id: "archive.extract", title: "Extract"))
                XCTFail("Accepted an oversized or duplicate archive")
            } catch { XCTAssertTrue(error is LemulipError) }
        }
    }

    func testArchiveCreationRejectsSymlinksAndDestinationInsideInput() async throws {
        let folder = root.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let file = root.appendingPathComponent("source.txt")
        try "Sample".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("link.txt"), withDestinationURL: file)
        do {
            _ = try await engine.run(inputs: [folder], operation: FileOperation(id: "archive.createZip", title: "ZIP"))
            XCTFail("Archived a symbolic link")
        } catch { XCTAssertTrue(error is LemulipError) }
        var options = ConversionOptions(); options.destinationDirectory = folder
        do {
            _ = try await engine.run(inputs: [folder], operation: FileOperation(id: "archive.createZip", title: "ZIP"), options: options)
            XCTFail("Allowed recursive output location")
        } catch { XCTAssertTrue(error.localizedDescription.contains("outside")) }
    }

    func testVerifiedPackageAliasesAreSkippedWithoutCreatingLinks() async throws {
        let prefix = "pandoc-3.12.1-arm64/bin/"
        let aliases = [prefix + "pandoc-lua", prefix + "pandoc-server"]
        let archive = root.appendingPathComponent("engine.tar")
        let binary = Data("verified binary fixture".utf8)
        var data = tarEntry(name: prefix + "pandoc", content: binary)
        for alias in aliases { data += tarEntry(name: alias, content: Data(), type: 50, link: "pandoc") }
        data += Data(repeating: 0, count: 1024)
        try data.write(to: archive)
        let stage = root.appendingPathComponent("stage")
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
        let result = try await ExternalConverters.archives([archive], operation: FileOperation(id: "archive.extract", title: "Extract"),
                                                           directory: stage, ignoredSymbolicLinks: aliases)
        let output = try XCTUnwrap(result.outputs.first)
        XCTAssertEqual(try Data(contentsOf: output.appendingPathComponent(prefix + "pandoc")), binary)
        for alias in aliases {
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent(alias).path))
            XCTAssertNil(try? FileManager.default.destinationOfSymbolicLink(atPath: output.appendingPathComponent(alias).path))
        }
        // The same archive remains rejected by ordinary user-file extraction.
        do {
            _ = try await ConversionEngine().run(inputs: [archive], operation: FileOperation(id: "archive.extract", title: "Extract"))
            XCTFail("User archives must still reject links")
        } catch { XCTAssertTrue(error.localizedDescription.contains("link")) }
    }

    func testIgnoredAliasesDoNotPermitOtherLinksTraversalOrDevices() async throws {
        let cases: [(String, UInt8, String)] = [("other", 50, "pandoc"), ("alias", 49, "pandoc"),
                                               ("alias", 51, ""), ("../alias", 50, "pandoc")]
        for (index, entry) in cases.enumerated() {
            let archive = root.appendingPathComponent("bad-package-\(index).tar")
            try (tarEntry(name: "pandoc", content: Data("binary".utf8)) +
                 tarEntry(name: entry.0, content: Data(), type: entry.1, link: entry.2) +
                 Data(repeating: 0, count: 1024)).write(to: archive)
            let stage = root.appendingPathComponent("stage-\(index)")
            try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
            do {
                _ = try await ExternalConverters.archives([archive], operation: FileOperation(id: "archive.extract", title: "Extract"),
                                                          directory: stage, ignoredSymbolicLinks: ["alias", "../alias"])
                XCTFail("Unexpected entry must not be accepted: \(entry.0)")
            } catch { XCTAssertTrue(error is LemulipError) }
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("alias").path))
        }
    }

    private func tarEntry(name: String, content: Data, type: UInt8 = 48, link: String = "", declaredSize: UInt64? = nil) -> Data {
        var header = [UInt8](repeating: 0, count: 512)
        func put(_ text: String, at offset: Int, length: Int) { for (index, byte) in text.utf8.prefix(length).enumerated() { header[offset + index] = byte } }
        func octal(_ value: UInt64, width: Int) -> String { let text = String(value, radix: 8); return String(repeating: "0", count: max(0, width - text.count - 1)) + text + "\0" }
        put(name, at: 0, length: 100); put("0000644\0", at: 100, length: 8)
        put("0000000\0", at: 108, length: 8); put("0000000\0", at: 116, length: 8)
        put(octal(declaredSize ?? UInt64(content.count), width: 12), at: 124, length: 12)
        put("00000000000\0", at: 136, length: 12)
        put("        ", at: 148, length: 8); header[156] = type
        put(link, at: 157, length: 100); put("ustar\0", at: 257, length: 6); put("00", at: 263, length: 2)
        let checksum = header.reduce(0) { $0 + UInt64($1) }
        let checksumText = String(checksum, radix: 8)
        put(String(repeating: "0", count: 6 - checksumText.count) + checksumText + "\0 ", at: 148, length: 8)
        var data = Data(header); data += content
        if content.count % 512 != 0 { data += Data(repeating: 0, count: 512 - content.count % 512) }
        return data
    }
}
