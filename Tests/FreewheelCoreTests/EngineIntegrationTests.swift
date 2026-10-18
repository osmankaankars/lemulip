import XCTest
@testable import FreewheelCore

/// Real optional engines, using only generated fixtures. Missing engines are reported as skips.
final class EngineIntegrationTests: XCTestCase {
    private var root: URL!
    private let engine = ConversionEngine()
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("freewheel-integration-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }
    override func tearDownWithError() throws { if let root { try FileManager.default.removeItem(at: root) } }

    func testFFmpegAudioConversionAndSpeedWithRealWaveform() async throws {
        try require("ffmpeg"); try require("ffprobe")
        let input = root.appendingPathComponent("tone with spaces.wav")
        let original = waveData(); try original.write(to: input)
        let flac = try await engine.run(inputs: [input], operation: FileOperation(id: "convert.flac", title: "FLAC"))
        XCTAssertEqual(try Data(contentsOf: flac.outputs[0]).prefix(4), Data("fLaC".utf8))
        let mp3 = try await engine.run(inputs: [input], operation: FileOperation(id: "convert.mp3", title: "MP3"))
        XCTAssertGreaterThan(try mp3.outputs[0].resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0, 100)
        var options = ConversionOptions(); options.speedMultiplier = 2
        let faster = try await engine.run(inputs: [input], operation: FileOperation(id: "media.speed", title: "Speed"), options: options)
        let details = try await probe(faster.outputs[0])
        let format = try XCTUnwrap(details["format"] as? [String: Any])
        let duration = try XCTUnwrap(Double(try XCTUnwrap(format["duration"] as? String)))
        XCTAssertEqual(duration, 0.5, accuracy: 0.08)
        XCTAssertEqual(try Data(contentsOf: input), original)
    }

    func testFFmpegTrimResizeMuteAndAudioExtraction() async throws {
        try require("ffmpeg"); try require("ffprobe")
        let audio = root.appendingPathComponent("tone.wav"); try waveData().write(to: audio)
        let video = root.appendingPathComponent("sample.mp4")
        _ = try await ProcessRunner.checked(executable: EngineLocator.find("ffmpeg")!, arguments: ["-nostdin", "-hide_banner", "-loglevel", "error", "-n", "-f", "lavfi", "-i", "color=c=orange:s=96x64:r=10:d=1", "-i", audio.path, "-shortest", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-threads", "2", "-c:a", "aac", video.path], currentDirectory: root, timeout: 30)
        var options = ConversionOptions(); options.maxDimension = 48; options.startSeconds = 0.2; options.endSeconds = 0.7
        let resized = try await engine.run(inputs: [video], operation: FileOperation(id: "media.resize", title: "Resize"), options: options)
        let resizeInfo = try await probe(resized.outputs[0])
        let resizedStreams = try XCTUnwrap(resizeInfo["streams"] as? [[String: Any]])
        let videoStream = try XCTUnwrap(resizedStreams.first(where: { $0["codec_type"] as? String == "video" }))
        XCTAssertEqual(videoStream["width"] as? Int, 48); XCTAssertEqual(videoStream["height"] as? Int, 32)
        let muted = try await engine.run(inputs: [video], operation: FileOperation(id: "media.mute", title: "Mute"))
        let muteInfo = try await probe(muted.outputs[0])
        XCTAssertFalse(try XCTUnwrap(muteInfo["streams"] as? [[String: Any]]).contains(where: { $0["codec_type"] as? String == "audio" }))
        let trimmed = try await engine.run(inputs: [video], operation: FileOperation(id: "media.trim", title: "Trim"), options: options)
        let trimInfo = try await probe(trimmed.outputs[0])
        let format = try XCTUnwrap(trimInfo["format"] as? [String: Any])
        XCTAssertEqual(try XCTUnwrap(Double(try XCTUnwrap(format["duration"] as? String))), 0.5, accuracy: 0.13)
        let extracted = try await engine.run(inputs: [video], operation: FileOperation(id: "media.extractAudio", title: "Audio"))
        let audioInfo = try await probe(extracted.outputs[0])
        let audioStreams = try XCTUnwrap(audioInfo["streams"] as? [[String: Any]])
        XCTAssertTrue(audioStreams.contains(where: { $0["codec_type"] as? String == "audio" }))
        XCTAssertFalse(audioStreams.contains(where: { $0["codec_type"] as? String == "video" }))
    }

    func testImageMagickWebPEncodeAndSVGExternalResourceRejection() async throws {
        try require("imagemagick")
        let input = root.appendingPathComponent("sample.png")
        let png = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAIAAACQkWg2AAAAGUlEQVR4nGN8lmLEQApgIkn1qIZRDUNKAwC9yAGc4I0KFwAAAABJRU5ErkJggg=="))
        try png.write(to: input)
        let stage = try OutputStore.prepare(destination: root)
        let converted = try await ExternalConverters.image([input], operation: FileOperation(id: "convert.webp", title: "WebP"), options: ConversionOptions(), directory: stage)
        let bytes = try Data(contentsOf: converted.outputs[0])
        XCTAssertEqual(bytes.prefix(4), Data("RIFF".utf8)); XCTAssertEqual(bytes[8..<12], Data("WEBP".utf8))
        XCTAssertEqual(try Data(contentsOf: input), png)
        let unsafe = root.appendingPathComponent("external.svg")
        try "<svg xmlns=\"http://www.w3.org/2000/svg\"><image href=\"https://example.com/image.png\"/></svg>".write(to: unsafe, atomically: true, encoding: .utf8)
        do {
            _ = try await ExternalConverters.image([unsafe], operation: FileOperation(id: "convert.png", title: "PNG"), options: ConversionOptions(), directory: stage)
            XCTFail("Accepted external SVG resources")
        } catch FreewheelError.invalidInput { }
    }

    func testPandocMarkdownHTMLAndEPUBRoundTrip() async throws {
        try require("pandoc")
        let input = root.appendingPathComponent("sample.md")
        try "# Sample document\n\nA **bold** sentence with Unicode: İstanbul.\n".write(to: input, atomically: true, encoding: .utf8)
        let html = try await engine.run(inputs: [input], operation: FileOperation(id: "convert.html", title: "HTML"))
        let text = try String(contentsOf: html.outputs[0], encoding: .utf8)
        XCTAssertTrue(text.contains("<strong>bold</strong>")); XCTAssertTrue(text.contains("Sample document"))
        let epub = try await engine.run(inputs: [input], operation: FileOperation(id: "convert.epub", title: "EPUB"))
        XCTAssertEqual(try Data(contentsOf: epub.outputs[0]).prefix(2), Data("PK".utf8))
        let plain = try await engine.run(inputs: epub.outputs, operation: FileOperation(id: "convert.txt", title: "Text"))
        XCTAssertTrue(try String(contentsOf: plain.outputs[0], encoding: .utf8).contains("İstanbul"))
        // These formats need Pandoc's embedded reference data while --sandbox remains enabled.
        for fileExtension in ["docx", "odt"] {
            let document = try await engine.run(inputs: [input], operation: FileOperation(id: "convert.\(fileExtension)", title: fileExtension.uppercased()))
            XCTAssertEqual(try Data(contentsOf: document.outputs[0]).prefix(2), Data("PK".utf8))
            let roundTrip = try await ExternalConverters.document(document.outputs, operation: FileOperation(id: "convert.txt", title: "Text"), directory: root)
            XCTAssertTrue(try String(contentsOf: roundTrip.outputs[0], encoding: .utf8).contains("İstanbul"))
        }
    }

    func testLibreOfficeDocumentAndSpreadsheetConversions() async throws {
        try require("libreoffice")
        let textInput = root.appendingPathComponent("sample.txt")
        try "Sample document\n\nThis is a generated conversion fixture.\n".write(to: textInput, atomically: true, encoding: .utf8)
        let docx = try await engine.run(inputs: [textInput], operation: FileOperation(id: "convert.docx", title: "DOCX"))
        XCTAssertEqual(try Data(contentsOf: docx.outputs[0]).prefix(2), Data("PK".utf8))
        let markdown = try await engine.run(inputs: docx.outputs, operation: FileOperation(id: "convert.md", title: "Markdown"))
        XCTAssertTrue(try String(contentsOf: markdown.outputs[0], encoding: .utf8).contains("generated conversion fixture"))
        let csv = root.appendingPathComponent("table.csv")
        try "name,value\nAlpha,12\nBeta,34\n".write(to: csv, atomically: true, encoding: .utf8)
        let spreadsheet = try await engine.run(inputs: [csv], operation: FileOperation(id: "convert.xlsx", title: "Excel"))
        XCTAssertEqual(try Data(contentsOf: spreadsheet.outputs[0]).prefix(2), Data("PK".utf8))
        let tsv = try await engine.run(inputs: spreadsheet.outputs, operation: FileOperation(id: "convert.tsv", title: "TSV"))
        let table = try TextCodec.parseDelimited(TextCodec.read(tsv.outputs[0]), delimiter: "\t")
        XCTAssertEqual(table[1], ["Alpha", "12"])
    }

    private func require(_ name: String) throws {
        guard EngineLocator.isAvailable(name) else { throw XCTSkip("Optional \(name) engine is not installed") }
    }

    private func probe(_ input: URL) async throws -> [String: Any] {
        let output = try await ProcessRunner.checked(executable: EngineLocator.find("ffprobe")!, arguments: ["-v", "error", "-show_entries", "stream=codec_type,width,height:format=duration", "-of", "json", input.path], timeout: 20)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: output.standardOutput) as? [String: Any])
    }

    private func waveData() -> Data {
        let rate = 8_000, count = 8_000
        var data = Data("RIFF".utf8)
        func append32(_ value: UInt32) { for shift in stride(from: 0, to: 32, by: 8) { data.append(UInt8(truncatingIfNeeded: value >> shift)) } }
        func append16(_ value: UInt16) { data.append(UInt8(truncatingIfNeeded: value)); data.append(UInt8(truncatingIfNeeded: value >> 8)) }
        append32(UInt32(36 + count * 2)); data += Data("WAVEfmt ".utf8); append32(16)
        append16(1); append16(1); append32(UInt32(rate)); append32(UInt32(rate * 2)); append16(2); append16(16)
        data += Data("data".utf8); append32(UInt32(count * 2))
        for index in 0..<count {
            let sample = Int16(sin(2 * Double.pi * 440 * Double(index) / Double(rate)) * 10_000)
            append16(UInt16(bitPattern: sample))
        }
        return data
    }
}
