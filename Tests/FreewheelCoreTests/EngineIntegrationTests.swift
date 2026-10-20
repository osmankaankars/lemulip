import XCTest
#if os(macOS)
import AppKit
import Darwin
#else
import Glibc
#endif
#if canImport(FoundationXML)
import FoundationXML
#endif
@testable import FreewheelCore

/// Real optional engines, using only generated fixtures. Missing engines are reported as skips.
final class EngineIntegrationTests: XCTestCase {
    private var root: URL!
    private let engine = ConversionEngine()
    private let wordNamespace = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    private let packageRelationshipNamespace = "http://schemas.openxmlformats.org/package/2006/relationships"
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
        // Keep explicit Pandoc coverage now that basic Markdown Word export is
        // built in. Its embedded reference data is still needed with --sandbox.
        for fileExtension in ["docx", "odt"] {
            let document = try await ExternalConverters.document([input], operation: FileOperation(id: "convert.\(fileExtension)", title: fileExtension.uppercased()), directory: root)
            XCTAssertEqual(try Data(contentsOf: document.outputs[0]).prefix(2), Data("PK".utf8))
            let roundTrip = try await ExternalConverters.document(document.outputs, operation: FileOperation(id: "convert.txt", title: "Text"), directory: root)
            XCTAssertTrue(try String(contentsOf: roundTrip.outputs[0], encoding: .utf8).contains("İstanbul"))
        }
    }

    func testHTMLWordExportKeepsHeadingEmphasisAndTable() async throws {
        try require("libreoffice")
        let html = """
        <!doctype html>
        <html><head><meta charset="utf-8"><title>Orchard Notes</title></head><body>
        <h1>Orchard Notes</h1>
        <p>A <strong>bold phrase</strong>, an <em>italic phrase</em>, and symbols: İstanbul · 東京 &amp; &lt; &gt;.</p>
        <table><tr><th>Fruit</th><th>Count</th></tr><tr><td>Lemon</td><td>12</td></tr></table>
        <p>After the Table</p>
        </body></html>
        """
        // HTML and the case-insensitive HTM alias must take the same Writer route.
        for ext in ["html", "HTM"] {
            try await checkMarkupWordExport("orchard.\(ext)", text: html, markdown: false,
                                            reviewCase: ext == "html" ? "word-html" : nil)
        }
    }

    func testMarkdownWordExportKeepsListsCodeAndTable() async throws {
        let markdown = """
        # Orchard Notes

        A **bold phrase**, an *italic phrase*, and symbols: İstanbul · 東京 & < >.

        - Lemon
        - Pistachio

        1. First Step
        2. Second Step

        ```text
          keep  two spaces
            four spaces
        **literal** <tag> & end
        ```

        | Fruit | Count |
        | --- | --- |
        | Lemon | 12 |

        After the Table
        """
        try await checkMarkupWordExport("orchard.md", text: markdown, markdown: true, reviewCase: "word-markdown")
    }

    func testAdvancedMarkdownWordUsesPandocForTheWholeBatch() async throws {
        try require("pandoc")
        let basic = root.appendingPathComponent("basic.md")
        let advanced = root.appendingPathComponent("advanced.MARKDOWN")
        let basicText = "# Basic Notes\n\nA **bold** sentence.\n"
        let advancedText = """
        # Advanced Notes

        Read [the guide](https://example.com/guide).

        > Quoted citrus.

        - Parent Item
            - Nested Item
        """
        try Data(basicText.utf8).write(to: basic)
        try Data(advancedText.utf8).write(to: advanced)
        let result = try await engine.run(inputs: [basic, advanced],
            operation: FileOperation(id: "convert.docx", title: "DOCX"))
        XCTAssertEqual(result.outputs.map(\.lastPathComponent), ["basic.docx", "advanced.docx"])
        XCTAssertTrue(result.note?.contains("Converted locally with Pandoc") == true)
        let extracted = try await ExternalConverters.archives(result.outputs,
            operation: FileOperation(id: "archive.extract", title: "Extract"), directory: root)
        XCTAssertEqual(extracted.outputs.count, 2)
        // Compare the simple first source against a direct Pandoc export. A
        // per-file native attempt would mix exporters within one batch. Package
        // timestamps are irrelevant; the Word document part is deterministic.
        let referenceFolder = root.appendingPathComponent("pandoc-reference", isDirectory: true)
        try FileManager.default.createDirectory(at: referenceFolder, withIntermediateDirectories: false)
        let reference = try await ExternalConverters.document([basic],
            operation: FileOperation(id: "convert.docx", title: "DOCX"), directory: referenceFolder)
        let referenceExtracted = try await ExternalConverters.archives(reference.outputs,
            operation: FileOperation(id: "archive.extract", title: "Extract"), directory: referenceFolder)
        let firstPackage = try XCTUnwrap(extracted.outputs.first)
        let referencePackage = try XCTUnwrap(referenceExtracted.outputs.first)
        XCTAssertEqual(try Data(contentsOf: firstPackage.appendingPathComponent("word/document.xml")),
                       try Data(contentsOf: referencePackage.appendingPathComponent("word/document.xml")))
        let package = try XCTUnwrap(extracted.outputs.last)
        let document = try officeXML(package, "word/document.xml")
        let relationships = try officeXML(package, "word/_rels/document.xml.rels")
        let styles = try officeXML(package, "word/styles.xml")
        try withExtendedLifetime((document, relationships, styles)) {
            let relationshipRoot = try XCTUnwrap(relationships.rootElement())
            XCTAssertEqual(relationshipRoot.localName, "Relationships")
            XCTAssertEqual(relationshipRoot.uri, packageRelationshipNamespace)
            let styleRoot = try XCTUnwrap(styles.rootElement())
            XCTAssertEqual(styleRoot.localName, "styles")
            XCTAssertEqual(styleRoot.uri, wordNamespace)
            let body = try XCTUnwrap(wordChild(document.rootElement(), "body"), "Missing Word body in Pandoc output")
            let paragraphs = body.elements(forLocalName: "p", uri: wordNamespace)
            let hyperlinks = paragraphs.flatMap { $0.elements(forLocalName: "hyperlink", uri: wordNamespace) }
            XCTAssertEqual(hyperlinks.count, 1)
            let hyperlink = try XCTUnwrap(hyperlinks.first, "Missing Word hyperlink in Pandoc output")
            XCTAssertEqual(wordText(hyperlink), "the guide")
            let relationshipID = try XCTUnwrap(hyperlink.attribute(forLocalName: "id",
                uri: "http://schemas.openxmlformats.org/officeDocument/2006/relationships")?.stringValue)
            let matchingRelationships = relationshipRoot
                .elements(forLocalName: "Relationship", uri: packageRelationshipNamespace)
                .filter { unqualifiedAttribute($0, "Id") == relationshipID }
            XCTAssertEqual(matchingRelationships.count, 1)
            let relationship = try XCTUnwrap(matchingRelationships.first)
            XCTAssertEqual(unqualifiedAttribute(relationship, "Target"), "https://example.com/guide")
            XCTAssertEqual(unqualifiedAttribute(relationship, "TargetMode"), "External")
            let quoted = try XCTUnwrap(paragraphs.first { wordText($0) == "Quoted citrus." })
            let styleID = try XCTUnwrap(wordChild(quoted, "pPr", "pStyle")?
                .attribute(forLocalName: "val", uri: wordNamespace)?.stringValue)
            let quoteStyle = try XCTUnwrap(styleRoot.elements(forLocalName: "style", uri: wordNamespace)
                .first { $0.attribute(forLocalName: "styleId", uri: wordNamespace)?.stringValue == styleID })
            let quoteIndentText = wordChild(quoteStyle, "pPr", "ind")?
                .attribute(forLocalName: "left", uri: wordNamespace)?.stringValue
            let quoteIndent = quoteIndentText.flatMap(Int.init)
            XCTAssertGreaterThan(try XCTUnwrap(quoteIndent), 0, "The quotation lost its paragraph indentation")
            let nested = try XCTUnwrap(paragraphs.first { wordText($0) == "Nested Item" })
            XCTAssertEqual(wordChild(nested, "pPr", "numPr", "ilvl")?
                .attribute(forLocalName: "val", uri: wordNamespace)?.stringValue, "1")
        }
        XCTAssertEqual(try Data(contentsOf: basic), Data(basicText.utf8))
        XCTAssertEqual(try Data(contentsOf: advanced), Data(advancedText.utf8))
    }

    func testInvalidMarkdownBatchDoesNotFallBackOrPublish() async throws {
        let advanced = root.appendingPathComponent("advanced.md")
        let invalid = root.appendingPathComponent("invalid.markdown")
        let original = Data("Read [the guide](https://example.com).\n".utf8)
        let invalidBytes = Data([0xC3, 0x28])
        try original.write(to: advanced); try invalidBytes.write(to: invalid)
        let existing = root.appendingPathComponent("advanced.docx")
        let sentinel = Data("Keep this existing file unchanged.".utf8)
        try sentinel.write(to: existing)
        let before = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
        do {
            _ = try await engine.run(inputs: [advanced, invalid],
                operation: FileOperation(id: "convert.docx", title: "DOCX"))
            XCTFail("Invalid encoding was accepted or sent to a capability fallback")
        } catch FreewheelError.invalidInput { }
        // An unsupported first source must not hide a later invalid input.
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted(), before)
        XCTAssertEqual(try Data(contentsOf: advanced), original)
        XCTAssertEqual(try Data(contentsOf: invalid), invalidBytes)
        XCTAssertEqual(try Data(contentsOf: existing), sentinel)
    }

    func testAdvancedMarkdownWordFallbackNormalizesUTF16WithoutChangingInputs() async throws {
        try require("pandoc")
        let title = "İstanbul 東京 😀"
        let sourceText = "# \(title)\r\n\r\nA **bold** sentence.\r\n"
        let little = root.appendingPathComponent("little.md")
        let big = root.appendingPathComponent("big.MARKDOWN")
        let advanced = root.appendingPathComponent("advanced.md")
        let littleBytes = Data([0xFF, 0xFE]) + (try XCTUnwrap(sourceText.data(using: .utf16LittleEndian)))
        let bigBytes = Data([0xFE, 0xFF]) + (try XCTUnwrap(sourceText.data(using: .utf16BigEndian)))
        let advancedBytes = Data("Read [the guide](https://example.com/guide).\n".utf8)
        let sources = [(little, littleBytes), (big, bigBytes), (advanced, advancedBytes)]
        for (input, bytes) in sources { try bytes.write(to: input) }
        let result = try await engine.run(inputs: sources.map(\.0),
            operation: FileOperation(id: "convert.docx", title: "DOCX"))
        XCTAssertEqual(result.outputs.map(\.lastPathComponent), ["little.docx", "big.docx", "advanced.docx"])
        XCTAssertTrue(result.note?.contains("Converted locally with Pandoc") == true)
        let expectedNames = Set(sources.map { $0.0.lastPathComponent } + result.outputs.map(\.lastPathComponent))
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: root.path)), expectedNames,
                       "Private Markdown preparation folders must be removed after export")
        let extracted = try await ExternalConverters.archives(Array(result.outputs.prefix(2)),
            operation: FileOperation(id: "archive.extract", title: "Extract"), directory: root)
        XCTAssertEqual(extracted.outputs.count, 2)
        for package in extracted.outputs {
            let document = try officeXML(package, "word/document.xml")
            try withExtendedLifetime(document) {
                let heading = try XCTUnwrap(wordChild(document.rootElement(), "body")?
                    .elements(forLocalName: "p", uri: wordNamespace).first, "Missing Word heading in Pandoc output")
                XCTAssertEqual(wordText(heading), title)
                XCTAssertEqual(wordChild(heading, "pPr", "pStyle")?
                    .attribute(forLocalName: "val", uri: wordNamespace)?.stringValue, "Heading1")
            }
        }
        for (input, bytes) in sources { XCTAssertEqual(try Data(contentsOf: input), bytes) }
    }

    func testAdvancedMarkdownWordXMLReaderKeepsNamespacesAndScope() throws {
        for prefix in ["w", "word"] {
            let source = """
            <\(prefix):document xmlns:\(prefix)="\(wordNamespace)" xmlns:other="urn:unrelated"><other:body/>
            <\(prefix):body><other:p/><\(prefix):p><\(prefix):pPr>
            <other:pStyle other:val="Wrong"/><\(prefix):pStyle other:val="Wrong" \(prefix):val="Heading1"/>
            </\(prefix):pPr><\(prefix):r><\(prefix):t>İstanbul 東京 😀</\(prefix):t><other:t>Ignore</other:t></\(prefix):r></\(prefix):p>
            <\(prefix):p><\(prefix):r><\(prefix):t>Next Paragraph</\(prefix):t></\(prefix):r></\(prefix):p></\(prefix):body></\(prefix):document>
            """
            try Data(source.utf8).write(to: root.appendingPathComponent("document.xml"))
            let document = try officeXML(root, "document.xml")
            try withExtendedLifetime(document) {
                let body = try XCTUnwrap(wordChild(document.rootElement(), "body"))
                let paragraphs = body.elements(forLocalName: "p", uri: wordNamespace)
                XCTAssertEqual(paragraphs.map { wordText($0) }, ["İstanbul 東京 😀", "Next Paragraph"])
                let style = try XCTUnwrap(wordChild(paragraphs.first, "pPr", "pStyle"))
                XCTAssertEqual(style.attribute(forLocalName: "val", uri: wordNamespace)?.stringValue, "Heading1")
                XCTAssertNil(wordChild(body, "p"), "A single-child lookup must reject duplicate paragraphs")
            }
        }
        let source = """
        <Relationships xmlns="\(packageRelationshipNamespace)" xmlns:other="urn:unrelated">
        <other:Relationship Id="rId1" Target="Wrong"/><Relationship Id="rId1" other:Target="Wrong" Target="https://example.com/guide" TargetMode="External"/>
        <Relationship Id="rId2" other:Target="https://example.com/guide"/>
        </Relationships>
        """
        try Data(source.utf8).write(to: root.appendingPathComponent("document.xml.rels"))
        let relationships = try officeXML(root, "document.xml.rels")
        try withExtendedLifetime(relationships) {
            let entries = try XCTUnwrap(relationships.rootElement()).elements(forLocalName: "Relationship", uri: packageRelationshipNamespace)
            XCTAssertEqual(entries.count, 2)
            let link = try XCTUnwrap(entries.first { unqualifiedAttribute($0, "Id") == "rId1" })
            XCTAssertEqual(unqualifiedAttribute(link, "Target"), "https://example.com/guide")
            XCTAssertEqual(unqualifiedAttribute(link, "TargetMode"), "External")
            XCTAssertNil(unqualifiedAttribute(try XCTUnwrap(entries.last), "Target"), "A foreign attribute must not replace an unqualified target")
        }
    }

    private func checkMarkupWordExport(_ name: String, text: String, markdown: Bool,
                                       reviewCase: String?) async throws {
        let source = root.appendingPathComponent(name), original = Data(text.utf8)
        try original.write(to: source)
        let result = try await engine.run(inputs: [source], operation: FileOperation(id: "convert.docx", title: "DOCX"))
        if markdown {
            XCTAssertTrue(result.note?.contains("Basic Markdown was exported") == true)
            XCTAssertTrue(result.note?.contains("built-in exporter") == true)
        }
        XCTAssertEqual(result.outputs.count, 1)
        let output = try XCTUnwrap(result.outputs.first)
        let extracted = try await ExternalConverters.archives([output],
            operation: FileOperation(id: "archive.extract", title: "Extract"), directory: root)
        let package = try XCTUnwrap(extracted.outputs.first)
        let documentSource = try Data(contentsOf: package.appendingPathComponent("word/document.xml"))
        let document = try officeXML(package, "word/document.xml")
        let issues = markupWordIssues(document, styles: try officeXML(package, "word/styles.xml"),
            numbering: markdown ? try officeXML(package, "word/numbering.xml") : nil, markdown: markdown)
        XCTAssertTrue(issues.isEmpty, "Markup Word export: \(issues.joined(separator: "; ")). Generated document XML: \(String(decoding: documentSource, as: UTF8.self))")
        XCTAssertEqual(try Data(contentsOf: source), original)
        if let reviewCase {
            try captureOfficeReview(reviewCase, files: [("source.\(markdown ? "md" : "html")", source), ("converted.docx", output)])
        }
    }

    func testMarkupWordVerificationRejectsLostStructureAndFormatting() throws {
        func run(_ text: String, _ style: String = "") -> String {
            "<w:r>\(style.isEmpty ? "" : "<w:rPr><w:rStyle w:val=\"\(style)\"/></w:rPr>")<w:t xml:space=\"preserve\">\(text)</w:t></w:r>"
        }
        func paragraph(_ text: String, _ properties: String = "") -> String {
            "<w:p><w:pPr>\(properties)</w:pPr>\(run(text))</w:p>"
        }
        let table = "<w:tbl>" + [["Fruit", "Count"], ["Lemon", "12"]].map { row in
            "<w:tr>" + row.map { "<w:tc>\(paragraph($0))</w:tc>" }.joined() + "</w:tr>"
        }.joined() + "</w:tbl>"
        let list = [("Lemon", "7"), ("Pistachio", "7"), ("First Step", "8"), ("Second Step", "8")].map {
            paragraph($0.0, "<w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"\($0.1)\"/></w:numPr>")
        }.joined()
        let body = paragraph("Orchard Notes", "<w:pStyle w:val=\"LeafHeading\"/>")
            + "<w:p>" + run("A ") + run("bold ", "LeafBold") + run("phrase", "LeafBold")
            + run(", an ") + run("italic phrase", "LeafItalic") + run(", and symbols: İstanbul · 東京 &amp; &lt; &gt;.") + "</w:p>"
            + list + "<w:p>" + run("  keep  two spaces") + "<w:r><w:br/></w:r>"
            + run("    four spaces") + "<w:r><w:br/></w:r>" + run("**literal** &lt;tag&gt; &amp; end") + "</w:p>"
            + table + paragraph("After the Table")
        let styles = """
        <w:styles xmlns:w="\(wordNamespace)">
        <w:style w:type="paragraph" w:styleId="LeafHeading"><w:basedOn w:val="OutlineBase"/></w:style>
        <w:style w:type="paragraph" w:styleId="OutlineBase"><w:pPr><w:outlineLvl w:val="0"/></w:pPr></w:style>
        <w:style w:type="character" w:styleId="LeafBold"><w:basedOn w:val="WeightBase"/></w:style>
        <w:style w:type="character" w:styleId="WeightBase"><w:rPr><w:b/></w:rPr></w:style>
        <w:style w:type="character" w:styleId="LeafItalic"><w:basedOn w:val="SlantBase"/></w:style>
        <w:style w:type="character" w:styleId="SlantBase"><w:rPr><w:i/></w:rPr></w:style>
        </w:styles>
        """
        let numbering = """
        <w:numbering xmlns:w="\(wordNamespace)">
        <w:abstractNum w:abstractNumId="21"><w:lvl w:ilvl="0"><w:numFmt w:val="bullet"/><w:lvlText w:val="•"/></w:lvl></w:abstractNum>
        <w:abstractNum w:abstractNumId="22"><w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="decimal"/><w:lvlText w:val="%1."/></w:lvl></w:abstractNum>
        <w:num w:numId="7"><w:abstractNumId w:val="21"/></w:num>
        <w:num w:numId="8"><w:abstractNumId w:val="22"/><w:lvlOverride w:ilvl="0"><w:startOverride w:val="1"/></w:lvlOverride></w:num>
        </w:numbering>
        """
        func issues(_ body: String, _ styles: String, _ numbering: String, prefix: String = "w") throws -> [String] {
            let document = "<w:document xmlns:w=\"\(wordNamespace)\" xmlns:other=\"urn:unrelated\"><w:body>\(body)</w:body></w:document>"
            func xml(_ text: String) throws -> XMLDocument {
                let part = "markup-\(UUID().uuidString).xml"
                let file = root.appendingPathComponent(part)
                let source = text.replacingOccurrences(of: "w:", with: "\(prefix):")
                    .replacingOccurrences(of: "xmlns:w=", with: "xmlns:\(prefix)=")
                try Data(source.utf8).write(to: file, options: .withoutOverwriting)
                defer { try? FileManager.default.removeItem(at: file) }
                return try officeXML(root, part)
            }
            return try markupWordIssues(xml(document), styles: xml(styles), numbering: xml(numbering), markdown: true)
        }
        XCTAssertTrue(try issues(body, styles, numbering).isEmpty)
        XCTAssertTrue(try issues(body, styles, numbering, prefix: "word").isEmpty)
        // Pandoc can put separators and code indentation in their own text runs.
        // Exercise the same file loader used for real Office package parts.
        let splitBody = body
            .replacingOccurrences(of: run("A "), with: run("A") + run(" "))
            .replacingOccurrences(of: run(", an "), with: run(", an") + run(" "))
            .replacingOccurrences(of: run("  keep  two spaces"), with: run("  ") + run("keep") + run("  ") + run("two spaces"))
            .replacingOccurrences(of: run("    four spaces"), with: run("    ") + run("four spaces"))
        XCTAssertTrue(try issues(splitBody, styles, numbering).isEmpty)
        XCTAssertTrue(try issues(splitBody, styles, numbering, prefix: "word").isEmpty)
        XCTAssertFalse(try issues(splitBody.replacingOccurrences(of: run(" "), with: ""), styles, numbering).isEmpty,
                       "Accepted missing word separators")
        XCTAssertFalse(try issues(splitBody.replacingOccurrences(of: run("  "), with: run(" ")), styles, numbering).isEmpty,
                       "Accepted shortened code whitespace")
        let mutations: [(String, String, String, String)] = [
            ("wrong heading level", body, styles.replacingOccurrences(of: "outlineLvl w:val=\"0\"", with: "outlineLvl w:val=\"1\""), numbering),
            ("style cycle", body, styles.replacingOccurrences(of: "w:val=\"OutlineBase\"", with: "w:val=\"LeafHeading\""), numbering),
            ("foreign attribute", body, styles.replacingOccurrences(of: "<w:outlineLvl w:val=\"0\"/>", with: "<w:outlineLvl xmlns:other=\"urn:unrelated\" other:val=\"0\"/>"), numbering),
            ("partly missing bold", body.replacingOccurrences(of: run("phrase", "LeafBold"), with: run("phrase")), styles, numbering),
            ("missing italic", body, styles.replacingOccurrences(of: "<w:i/>", with: "<w:i w:val=\"0\"/>"), numbering),
            ("table order", table + body.replacingOccurrences(of: table, with: ""), styles, numbering),
            ("table value", body.replacingOccurrences(of: run("12"), with: run("13")), styles, numbering),
            ("bullet definition", body, styles, numbering.replacingOccurrences(of: "w:val=\"bullet\"", with: "w:val=\"decimal\"")),
            ("numbered start", body, styles, numbering.replacingOccurrences(of: "startOverride w:val=\"1\"", with: "startOverride w:val=\"4\"")),
            ("missing numbered start", body, styles, numbering.replacingOccurrences(of: "<w:start w:val=\"1\"/>", with: "").replacingOccurrences(of: "<w:startOverride w:val=\"1\"/>", with: "")),
            ("code spaces", body.replacingOccurrences(of: "  keep  two spaces", with: "keep two spaces"), styles, numbering),
            ("code whitespace marker", body.replacingOccurrences(of: "xml:space=\"preserve\">  keep", with: ">  keep"), styles, numbering),
            ("code line breaks", body.replacingOccurrences(of: "<w:r><w:br/></w:r>", with: ""), styles, numbering)
        ]
        for (name, changedBody, changedStyles, changedNumbers) in mutations {
            XCTAssertFalse(try issues(changedBody, changedStyles, changedNumbers).isEmpty, "Accepted \(name)")
        }
    }

    // A focused semantic check for these two generated documents, not a general
    // Word renderer. Keep each XML owner alive while resolving inherited namespaces.
    private func markupWordIssues(_ document: XMLDocument, styles: XMLDocument,
                                  numbering: XMLDocument?, markdown: Bool) -> [String] {
        withExtendedLifetime((document, styles, numbering)) {
            func children(_ node: XMLElement?, _ name: String) -> [XMLElement] {
                node?.elements(forLocalName: name, uri: wordNamespace) ?? []
            }
            func at(_ node: XMLElement?, _ path: String...) -> XMLElement? {
                var result = node
                for name in path { let matches = children(result, name); guard matches.count == 1 else { return nil }; result = matches[0] }
                return result
            }
            func value(_ node: XMLElement?, _ name: String = "val") -> String? {
                node?.attribute(forLocalName: name, uri: wordNamespace)?.stringValue
            }
            func text(_ node: XMLElement) -> String {
                guard node.uri == wordNamespace else { return "" }
                switch node.localName {
                case "t": return node.stringValue ?? ""
                case "tab": return "\t"
                case "br", "cr": return [nil, "textWrapping"].contains(value(node, "type")) ? "\n" : "\u{000C}"
                default: return (node.children ?? []).compactMap { $0 as? XMLElement }.map(text).joined()
                }
            }
            func chain(_ id: String?, type: String) -> [XMLElement]? {
                var next = id, seen = Set<String>(), result: [XMLElement] = []
                while let identifier = next {
                    guard seen.insert(identifier).inserted else { return nil }
                    let matches = children(styles.rootElement(), "style").filter { value($0, "styleId") == identifier && value($0, "type") == type }
                    guard matches.count == 1 else { return nil }
                    result.append(matches[0]); next = value(at(matches[0], "basedOn"))
                }
                return result
            }
            func paragraphSources(_ paragraph: XMLElement) -> [XMLElement] {
                guard let inherited = chain(value(at(paragraph, "pPr", "pStyle")), type: "paragraph") else { return [] }
                return [paragraph] + inherited
            }
            func enabled(_ run: XMLElement, paragraph: XMLElement, property: String) -> Bool {
                guard let inherited = chain(value(at(run, "rPr", "rStyle")), type: "character") else { return false }
                let paragraphs = paragraphSources(paragraph); guard !paragraphs.isEmpty else { return false }
                let defaults = at(styles.rootElement(), "docDefaults", "rPrDefault", "rPr", property)
                var on = defaults.map { ["1", "true", "on"].contains(value($0) ?? "1") } ?? false
                // Bold and italic toggle within styles; direct run formatting overrides them.
                for style in Array(paragraphs.dropFirst().reversed()) + inherited.reversed() {
                    if let flag = at(style, "rPr", property), ["1", "true", "on"].contains(value(flag) ?? "1") { on.toggle() }
                }
                if let direct = at(run, "rPr", property) { on = ["1", "true", "on"].contains(value(direct) ?? "1") }
                return on
            }
            func formatted(_ phrase: String, property: String, paragraph: XMLElement) -> Bool {
                let whole = text(paragraph) as NSString, range = (text(paragraph) as NSString).range(of: phrase)
                guard range.location != NSNotFound else { return false }
                var offset = 0, covered = 0
                for run in children(paragraph, "r") {
                    let length = (text(run) as NSString).length
                    let overlap = NSIntersectionRange(range, NSRange(location: offset, length: length)).length
                    if overlap > 0 { guard enabled(run, paragraph: paragraph, property: property) else { return false }; covered += overlap }
                    offset += length
                }
                return offset == whole.length && covered == range.length
            }
            func listID(_ paragraph: XMLElement, format: String) -> String? {
                let properties = paragraphSources(paragraph).compactMap { at($0, "pPr", "numPr") }.first
                guard let id = value(at(properties, "numId")), id != "0", value(at(properties, "ilvl")) == "0" else { return nil }
                let instances = children(numbering?.rootElement(), "num").filter { value($0, "numId") == id }
                guard instances.count == 1, let abstractID = value(at(instances[0], "abstractNumId")) else { return nil }
                let definitions = children(numbering?.rootElement(), "abstractNum").filter { value($0, "abstractNumId") == abstractID }
                guard definitions.count == 1 else { return nil }
                let levels = children(definitions[0], "lvl").filter { value($0, "ilvl") == "0" }
                let overrides = children(instances[0], "lvlOverride").filter { value($0, "ilvl") == "0" }
                guard levels.count == 1, overrides.count <= 1 else { return nil }
                let level = at(overrides.first, "lvl") ?? levels[0]
                guard value(at(level, "numFmt")) == format, let marker = value(at(level, "lvlText")), !marker.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
                if format == "decimal" {
                    guard marker == "%1.", (value(at(overrides.first, "startOverride")) ?? value(at(level, "start"))) == "1" else { return nil }
                }
                return id
            }
            guard document.rootElement()?.uri == wordNamespace, document.rootElement()?.localName == "document",
                  styles.rootElement()?.uri == wordNamespace, let body = at(document.rootElement(), "body") else { return ["Missing Word document or styles"] }
            let blocks = (body.children ?? []).compactMap { $0 as? XMLElement }.filter { $0.uri == wordNamespace && ["p", "tbl"].contains($0.localName ?? "") }
            let code = "  keep  two spaces\n    four spaces\n**literal** <tag> & end"
            let expected = ["Orchard Notes", "A bold phrase, an italic phrase, and symbols: İstanbul · 東京 & < >."]
                + (markdown ? ["Lemon", "Pistachio", "First Step", "Second Step", code] : []) + ["[Table]", "After the Table"]
            guard blocks.map({ $0.localName == "tbl" ? "[Table]" : text($0) }) == expected else { return ["Body text, code whitespace, or table order changed"] }
            var issues: [String] = []
            let outline = paragraphSources(blocks[0]).compactMap { at($0, "pPr", "outlineLvl") }.first
            if value(outline) != "0" { issues.append("Level-one heading lost its resolved outline level") }
            for (phrase, property) in [("bold phrase", "b"), ("italic phrase", "i")] {
                if !formatted(phrase, property: property, paragraph: blocks[1]) { issues.append("Formatting lost from \(phrase)") }
            }
            let table = blocks[blocks.count - 2]
            let cells = children(table, "tr").map { row in children(row, "tc").map { cell in children(cell, "p").map(text).joined(separator: "\n") } }
            if cells != [["Fruit", "Count"], ["Lemon", "12"]] { issues.append("Table cells changed") }
            if markdown {
                for (start, format) in [(2, "bullet"), (4, "decimal")] {
                    if let first = listID(blocks[start], format: format), listID(blocks[start + 1], format: format) == first { }
                    else { issues.append("\(format) list definition or numbering changed") }
                }
                for run in children(blocks[6], "r") {
                    for item in children(run, "t") where (item.stringValue ?? "").first?.isWhitespace == true {
                        if item.attribute(forLocalName: "space", uri: "http://www.w3.org/XML/1998/namespace")?.stringValue != "preserve" { issues.append("Code spaces lack XML preservation") }
                    }
                }
            }
            return issues
        }
    }

    func testLibreOfficeDocumentAndSpreadsheetConversions() async throws {
        try require("libreoffice")
        let textInput = root.appendingPathComponent("sample.txt")
        try "Sample document\n\nThis is a generated conversion fixture.\n".write(to: textInput, atomically: true, encoding: .utf8)
        // Keep explicit engine coverage now that plain-text Word export is
        // built into the Mac app.
        let docx = try await ExternalConverters.office([textInput], operation: FileOperation(id: "convert.docx", title: "DOCX"), directory: root)
        XCTAssertEqual(try Data(contentsOf: docx.outputs[0]).prefix(2), Data("PK".utf8))
        let markdown = try await engine.run(inputs: docx.outputs, operation: FileOperation(id: "convert.md", title: "Markdown"))
        XCTAssertTrue(try String(contentsOf: markdown.outputs[0], encoding: .utf8).contains("generated conversion fixture"))
        let csv = root.appendingPathComponent("table.csv")
        try "name,value\nAlpha,12\nBeta,34\n".write(to: csv, atomically: true, encoding: .utf8)
        let spreadsheet = try await ExternalConverters.office([csv], operation: FileOperation(id: "convert.xlsx", title: "Excel"), directory: root)
        XCTAssertEqual(try Data(contentsOf: spreadsheet.outputs[0]).prefix(2), Data("PK".utf8))
        let tsv = try await engine.run(inputs: spreadsheet.outputs, operation: FileOperation(id: "convert.tsv", title: "TSV"))
        let table = try TextCodec.parseDelimited(TextCodec.read(tsv.outputs[0]), delimiter: "\t")
        XCTAssertEqual(table[1], ["Alpha", "12"])
    }

    func testBuiltInSpreadsheetTextCellsOpenInLibreOffice() async throws {
        try require("libreoffice")
        let source = root.appendingPathComponent("literal-values.csv")
        let original = "name,identifier,long number,expression\nİstanbul,00123,12345678901234567890,=1+2\nnote,_x0041_,12/03/2026,  Keep  \n"
        try original.write(to: source, atomically: true, encoding: .utf8)
        let workbook = try await engine.run(inputs: [source], operation: FileOperation(id: "convert.xlsx", title: "XLSX"))
        let imported = try await ExternalConverters.office(workbook.outputs,
            operation: FileOperation(id: "convert.tsv", title: "TSV"), directory: root)
        let rows = try TextCodec.parseDelimited(TextCodec.read(imported.outputs[0]), delimiter: "\t")
        XCTAssertEqual(rows, [
            ["name", "identifier", "long number", "expression"],
            ["İstanbul", "00123", "12345678901234567890", "=1+2"],
            ["note", "_x0041_", "12/03/2026", "  Keep  "]
        ])
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), original)
        try captureOfficeReview("excel-text", files: [
            ("source.csv", source), ("converted.xlsx", try XCTUnwrap(workbook.outputs.first))
        ])
    }

    func testLibreOfficeRichWordRoundTripKeepsTableAndRunFormatting() async throws {
        try require("libreoffice")
        let source = try await officeFixture("rich-notes.docx", parts: wordFixtureParts())
        let original = try Data(contentsOf: source)
        let result = try await officeRoundTrip(source, through: "odt", reviewCase: "word-layout")
        let document = try officeXML(result, "word/document.xml")
        let tables = try document.nodes(forXPath: "//*[local-name()='tbl']")
        XCTAssertEqual(tables.count, 1)
        let table = try XCTUnwrap(tables.first)
        let rows = try table.nodes(forXPath: "./*[local-name()='tr']")
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(try rows.map { try $0.nodes(forXPath: "./*[local-name()='tc']").count }, [2, 2])
        XCTAssertEqual(try table.nodes(forXPath: ".//*[local-name()='t']").compactMap(\.stringValue),
                       ["Item", "Amount", "İstanbul", "12.50"])
        let heading = try XCTUnwrap(document.nodes(forXPath: "//*[local-name()='r'][*[local-name()='t']='Orchard Notes']").first)
        for property in ["b", "i"] {
            let value = try XCTUnwrap(heading.nodes(forXPath: "./*[local-name()='rPr']/*[local-name()='\(property)']").first)
            XCTAssertFalse(["0", "false", "off"].contains(try value.nodes(forXPath: "./@*[local-name()='val']").first?.stringValue ?? "1"))
        }
        XCTAssertTrue(try heading.nodes(forXPath: ".//*[local-name()='rFonts']/@*[local-name()='ascii']").contains { $0.stringValue == "Arial" })
        XCTAssertEqual(try heading.nodes(forXPath: ".//*[local-name()='sz']/@*[local-name()='val']").first?.stringValue, "28")
        XCTAssertTrue(try document.nodes(forXPath: "//*[local-name()='t']").contains { $0.stringValue == "A second paragraph with Unicode: İstanbul." })
        XCTAssertTrue(wordPageBoundaryIsPreserved(document),
                      "The unique second-page heading must follow the table and an explicit page boundary. Generated Word body: \(document.rootElement()?.xmlString ?? "missing")")
        XCTAssertTrue(try document.nodes(forXPath: "//*[local-name()='t']").contains {
            $0.stringValue == "This paragraph follows an explicit page break. The table stays on the first page."
        })
        XCTAssertEqual(try Data(contentsOf: source), original)
        // These are stored table and font properties. Font availability and
        // exact Word pagination require a separate native visual review.
    }

    #if os(macOS)
    func testNativeRTFWordExportKeepsFormattingWhenOpenedInLibreOffice() async throws {
        try require("libreoffice")
        let source = root.appendingPathComponent("formatted-letter.rtf")
        let original = Data(#"{\rtf1\ansi\deff0{\fonttbl{\f0\fswiss Arial;}}\pard\qc\sb120\sa240\f0\fs28\b\i Orchard Notes\b0\i0\par\pard\ql\fs22 Second Paragraph}"#.utf8)
        try original.write(to: source)
        let word = try await engine.run(inputs: [source], operation: FileOperation(id: "convert.docx", title: "DOCX"))
        XCTAssertEqual(word.outputs.count, 1)
        XCTAssertTrue(word.note?.contains("using macOS") == true)
        let reopened = try await ExternalConverters.office(word.outputs,
            operation: FileOperation(id: "convert.rtf", title: "RTF"), directory: root)
        let document = try NSAttributedString(data: Data(contentsOf: XCTUnwrap(reopened.outputs.first)),
            options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        let heading = (document.string as NSString).range(of: "Orchard Notes")
        XCTAssertNotEqual(heading.location, NSNotFound)
        guard heading.location != NSNotFound else { return }
        let attributes = document.attributes(at: heading.location, effectiveRange: nil)
        let font = try XCTUnwrap(attributes[.font] as? NSFont)
        let traits = font.fontDescriptor.symbolicTraits
        XCTAssertTrue(traits.contains(.bold))
        XCTAssertTrue(traits.contains(.italic))
        XCTAssertEqual(font.pointSize, 14, accuracy: 0.1)
        XCTAssertEqual(font.familyName, "Arial")
        XCTAssertEqual((attributes[.paragraphStyle] as? NSParagraphStyle)?.alignment, .center)
        XCTAssertTrue(document.string.contains("Second Paragraph"))
        XCTAssertEqual(try Data(contentsOf: source), original)
        try captureOfficeReview("word-rtf", files: [
            ("source.rtf", source), ("converted.docx", try XCTUnwrap(word.outputs.first))
        ])
    }
    #endif

    func testComplexRTFWordExportUsesTheOfficeEngineWithoutLosingItsTable() async throws {
        try require("libreoffice")
        let source = root.appendingPathComponent("table-letter.rtf")
        let original = Data(#"{\rtf1\ansi\deff0{\fonttbl{\f0\fswiss Arial;}}\trowd\cellx2000\cellx4000\intbl Left Cell\cell Right Cell\cell\row\pard After Table\par}"#.utf8)
        try original.write(to: source)
        let plain = root.appendingPathComponent("plain-letter.txt")
        try Data("Plain Letter".utf8).write(to: plain)
        let word = try await engine.run(inputs: [plain, source], operation: FileOperation(id: "convert.docx", title: "DOCX"))
        XCTAssertEqual(word.outputs.count, 2)
        let tableOutput = try XCTUnwrap(word.outputs.first { $0.deletingPathExtension().lastPathComponent.hasPrefix("table-letter") })
        let unpacked = try await ExternalConverters.archives([tableOutput],
            operation: FileOperation(id: "archive.extract", title: "Extract"), directory: root)
        let document = try officeXML(XCTUnwrap(unpacked.outputs.first), "word/document.xml")
        let tables = try document.nodes(forXPath: "//*[local-name()='tbl']")
        XCTAssertEqual(tables.count, 1)
        XCTAssertEqual(try tables.first?.nodes(forXPath: ".//*[local-name()='t']").compactMap(\.stringValue), ["Left Cell", "Right Cell"])
        XCTAssertTrue(try document.nodes(forXPath: "//*[local-name()='t']").contains { $0.stringValue == "After Table" })
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertEqual(try Data(contentsOf: plain), Data("Plain Letter".utf8))
    }

    func testLibreOfficeWorkbookRoundTripKeepsSheetsFormulasAndCellTypes() async throws {
        try require("libreoffice")
        let source = try await officeFixture("budget.xlsx", parts: spreadsheetFixtureParts())
        let original = try Data(contentsOf: source)
        let result = try await officeRoundTrip(source, through: "ods", reviewCase: "excel-formulas")
        let workbook = try officeXML(result, "xl/workbook.xml")
        let sheets = try workbook.nodes(forXPath: "//*[local-name()='sheet']")
        XCTAssertEqual(try sheets.map { try $0.nodes(forXPath: "./@name").first?.stringValue }, ["Budget", "Summary"])
        let sheetParts = try withExtendedLifetime(workbook) {
            try relatedOfficeParts(result, mainPart: "xl/workbook.xml", elements: sheets)
        }
        XCTAssertEqual(sheetParts.count, 2)
        guard sheetParts.count == 2 else { throw FreewheelError.operationFailed("The converted workbook did not keep both sheets.") }
        let budget = try officeXML(result, sheetParts[0]), summary = try officeXML(result, sheetParts[1])
        let shared = FileManager.default.fileExists(atPath: result.appendingPathComponent("xl/sharedStrings.xml").path)
            ? try officeXML(result, "xl/sharedStrings.xml").nodes(forXPath: "//*[local-name()='si']") : []
        func cell(_ sheet: XMLDocument, _ address: String) throws -> XMLNode {
            try XCTUnwrap(sheet.nodes(forXPath: "//*[local-name()='c' and @r='\(address)']").first)
        }
        func text(_ node: XMLNode) throws -> String {
            let kind = try node.nodes(forXPath: "./@t").first?.stringValue
            if kind == "s" {
                let index = try XCTUnwrap(Int(try XCTUnwrap(node.nodes(forXPath: "./*[local-name()='v']").first?.stringValue)))
                guard shared.indices.contains(index) else { throw FreewheelError.operationFailed("Invalid shared-string index in the converted workbook.") }
                return try shared[index].nodes(forXPath: ".//*[local-name()='t']").compactMap(\.stringValue).joined()
            }
            XCTAssertEqual(kind, "inlineStr")
            return try node.nodes(forXPath: ".//*[local-name()='t']").compactMap(\.stringValue).joined()
        }
        XCTAssertEqual(try text(cell(budget, "A2")), "00123")
        XCTAssertEqual(try text(cell(budget, "A3")), "İstanbul")
        XCTAssertEqual(try text(cell(budget, "D2")), "12345678901234567890")
        let number = try cell(budget, "B2")
        XCTAssertTrue([nil, "n"].contains(try number.nodes(forXPath: "./@t").first?.stringValue))
        XCTAssertEqual(try number.nodes(forXPath: "./*[local-name()='v']").first?.stringValue, "12.5")
        XCTAssertEqual(try cell(budget, "C2").nodes(forXPath: "./@t").first?.stringValue, "b")
        XCTAssertEqual(try cell(budget, "C2").nodes(forXPath: "./*[local-name()='v']").first?.stringValue, "1")
        for (sheet, address, expression, value) in [(budget, "B4", "SUM(B2:B3)", 20.0), (summary, "A1", "Budget!B4*2", 40.0)] {
            let formula = try cell(sheet, address)
            let expressionAfter = try XCTUnwrap(formula.nodes(forXPath: "./*[local-name()='f']").first?.stringValue)
            XCTAssertEqual(expressionAfter.replacingOccurrences(of: "'", with: ""), expression)
            XCTAssertEqual(try XCTUnwrap(Double(try XCTUnwrap(formula.nodes(forXPath: "./*[local-name()='v']").first?.stringValue))), value, accuracy: 0.000001)
        }
        let styles = try officeXML(result, "xl/styles.xml")
        let styleIndex = try XCTUnwrap(Int(try XCTUnwrap(number.nodes(forXPath: "./@s").first?.stringValue)))
        let formats = try styles.nodes(forXPath: "//*[local-name()='cellXfs']/*[local-name()='xf']")
        XCTAssertTrue(formats.indices.contains(styleIndex))
        if formats.indices.contains(styleIndex) {
            let formatID = try XCTUnwrap(formats[styleIndex].nodes(forXPath: "./@numFmtId").first?.stringValue)
            let custom = try styles.nodes(forXPath: "//*[local-name()='numFmt' and @numFmtId='\(formatID)']/@formatCode").first?.stringValue
            XCTAssertTrue(formatID == "2" || custom == "0.00", "The two-decimal number format must survive.")
        }
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testLibreOfficePresentationRoundTripKeepsSlideOrderAndGeometry() async throws {
        try require("libreoffice")
        let source = try await officeFixture("two-slides.pptx", parts: presentationFixtureParts())
        let original = try Data(contentsOf: source)
        let result = try await officeRoundTrip(source, through: "odp", reviewCase: "powerpoint-layout")
        let presentation = try officeXML(result, "ppt/presentation.xml")
        let slides = try presentation.nodes(forXPath: "//*[local-name()='sldId']")
        XCTAssertEqual(slides.count, 2)
        for (attribute, expected) in [("cx", 12_192_000.0), ("cy", 6_858_000.0)] {
            let actual = try XCTUnwrap(Double(try XCTUnwrap(presentation.nodes(forXPath: "//*[local-name()='sldSz']/@\(attribute)").first?.stringValue)))
            XCTAssertEqual(actual, expected, accuracy: 9_144)
        }
        let slideParts = try withExtendedLifetime(presentation) {
            try relatedOfficeParts(result, mainPart: "ppt/presentation.xml", elements: slides)
        }
        guard slideParts.count == 2 else { throw FreewheelError.operationFailed("The converted presentation did not keep both slides.") }
        for (index, title) in ["Orchard Overview", "Lemon Details"].enumerated() {
            let slide = try officeXML(result, slideParts[index])
            let shapes = try slide.nodes(forXPath: "//*[local-name()='sp']")
            let heading = try XCTUnwrap(shapes.first { (try? $0.nodes(forXPath: ".//*[local-name()='t']").compactMap(\.stringValue).joined()) == title })
            XCTAssertTrue(try heading.nodes(forXPath: ".//*[local-name()='latin']/@typeface").contains { $0.stringValue == "Arial" })
            XCTAssertTrue(try heading.nodes(forXPath: ".//*[local-name()='rPr']/@sz").contains { $0.stringValue == "2400" })
            let marker = try XCTUnwrap(shapes.first { (try? $0.nodes(forXPath: ".//*[local-name()='t']").compactMap(\.stringValue).joined()) == "Panel \(index + 1)" })
            for (shape, x, y, width, height) in [(heading, 914_400.0, 914_400.0, 9_144_000.0, 685_800.0),
                                               (marker, Double(914_400 + index * 4_572_000), 2_286_000.0, 3_048_000.0, 1_524_000.0)] {
                for (element, attribute, expected) in [("off", "x", x), ("off", "y", y), ("ext", "cx", width), ("ext", "cy", height)] {
                    let path = "./*[local-name()='spPr']/*[local-name()='xfrm']/*[local-name()='\(element)']/@\(attribute)"
                    let actual = try XCTUnwrap(Double(try XCTUnwrap(shape.nodes(forXPath: path).first?.stringValue)))
                    // 0.01 inch allows Office's coordinate rounding, without
                    // accepting a visibly moved or resized shape.
                    XCTAssertEqual(actual, expected, accuracy: 9_144)
                }
            }
        }
        XCTAssertEqual(try Data(contentsOf: source), original)
        // Stored geometry is checked, not PowerPoint's renderer or animations.
    }

    func testOfficeRelationshipsResolveInheritedNamespacesAndDocumentOrder() throws {
        let namespace = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
        let document = try XMLDocument(xmlString: """
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
                  xmlns:link="\(namespace)" xmlns:other="urn:unrelated">
          <sheets>
            <sheet name="First" id="decoy" other:id="wrong" link:id="rSecond"/>
            <sheet name="Second" xmlns:rel="\(namespace)" rel:id="rFirst"/>
          </sheets>
        </workbook>
        """, options: .nodeLoadExternalEntitiesNever)
        let folder = root.appendingPathComponent("xl/_rels", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try officeRelationships([
            ("rFirst", "worksheet", "worksheets/second.xml"),
            ("rSecond", "worksheet", "worksheets/first.xml"),
            ("wrong", "worksheet", "worksheets/unrelated.xml"),
            ("decoy", "worksheet", "worksheets/unnamespaced.xml")
        ]).write(to: folder.appendingPathComponent("workbook.xml.rels"), atomically: false, encoding: .utf8)
        // Keep the owning document alive while resolving inherited namespace
        // declarations from its child nodes on both Foundation implementations.
        let parts = try withExtendedLifetime(document) {
            try relatedOfficeParts(root, mainPart: "xl/workbook.xml",
                elements: document.nodes(forXPath: "//*[local-name()='sheet']"))
        }
        XCTAssertEqual(parts, ["xl/worksheets/first.xml", "xl/worksheets/second.xml"])
    }

    func testWordPageBoundaryRequiresTheRightParagraphAndBreak() throws {
        let table = "<w:tbl><w:tr><w:tc><w:p><w:r><w:t>Table Cell</w:t></w:r></w:p></w:tc></w:tr></w:tbl>"
        let title = "<w:r><w:t>A Fresh Page</w:t></w:r>"
        let page = "<w:r><w:br w:type=\"page\"/></w:r>"
        let explicit = "<w:p><w:pPr><w:pageBreakBefore/></w:pPr>\(title)</w:p>"
        let inline = "<w:p>\(page)\(title)</w:p>"
        func check(_ content: String) throws -> Bool {
            let document = try XMLDocument(xmlString:
                "<w:document xmlns:w=\"\(wordNamespace)\" xmlns:other=\"urn:unrelated\"><w:body>\(content)</w:body></w:document>",
                options: .nodeLoadExternalEntitiesNever)
            return wordPageBoundaryIsPreserved(document)
        }
        XCTAssertTrue(try check(table + explicit))
        XCTAssertTrue(try check(table + inline))
        XCTAssertTrue(try check(table + "<w:p>\(page)<w:r><w:t>A Fresh </w:t></w:r><w:r><w:t>Page</w:t></w:r></w:p>"))
        XCTAssertTrue(try check(table + "<w:p><w:pPr><w:pageBreakBefore w:val=\"true\"/></w:pPr>\(title)</w:p>"))
        // Reusing a local name in another namespace must not replace a Word attribute.
        XCTAssertTrue(try check(table + "<w:p><w:r><w:br other:type=\"line\" w:type=\"page\"/></w:r>\(title)</w:p>"))
        for disabled in ["0", "false", "off"] {
            XCTAssertFalse(try check(table + "<w:p><w:pPr><w:pageBreakBefore w:val=\"\(disabled)\"/></w:pPr>\(title)</w:p>"))
        }
        for invalid in [
            explicit, explicit + table, table + table + explicit, table + explicit + inline,
            "<w:tbl><w:tr><w:tc>\(explicit)</w:tc></w:tr></w:tbl>",
            table + "<w:p>\(title)\(page)</w:p>",
            table + "<w:p><w:r><w:br/></w:r>\(title)</w:p>",
            table + "<w:p><w:r><w:br w:type=\"column\"/></w:r>\(title)</w:p>",
            table + "<w:p><w:r><w:br other:type=\"page\"/></w:r>\(title)</w:p>",
            table + "<w:p><w:r><w:tab/></w:r>\(page)\(title)</w:p>",
            table + "<w:p><w:hyperlink>\(title)</w:hyperlink>\(page)</w:p>",
            table + "<w:p><w:r><w:drawing/></w:r>\(page)\(title)</w:p>"
        ] {
            XCTAssertFalse(try check(invalid), "Accepted an invalid Word page boundary: \(invalid)")
        }
        let alternate = try XMLDocument(xmlString:
            "<document xmlns=\"\(wordNamespace)\" xmlns:word=\"\(wordNamespace)\"><body><tbl/><p><r><br word:type=\"page\"/></r><r><t>A Fresh Page</t></r></p></body></document>",
            options: .nodeLoadExternalEntitiesNever)
        XCTAssertTrue(wordPageBoundaryIsPreserved(alternate))
    }

    private func wordPageBoundaryIsPreserved(_ document: XMLDocument) -> Bool {
        withExtendedLifetime(document) {
            guard let rootElement = document.rootElement(), rootElement.localName == "document",
                  rootElement.uri == wordNamespace else { return false }
            let bodies = rootElement.elements(forLocalName: "body", uri: wordNamespace)
            guard bodies.count == 1 else { return false }
            let blocks = (bodies[0].children ?? []).compactMap { $0 as? XMLElement }
            let tables = blocks.indices.filter { blocks[$0].uri == wordNamespace && blocks[$0].localName == "tbl" }
            let headings = blocks.indices.filter {
                blocks[$0].uri == wordNamespace && blocks[$0].localName == "p"
                    && wordText(blocks[$0]) == "A Fresh Page"
            }
            // Select the exact body paragraph and compare document order directly.
            // A matching heading inside a table or a duplicate heading is invalid.
            guard tables.count == 1, headings.count == 1, tables[0] < headings[0] else { return false }
            let paragraph = blocks[headings[0]]
            let properties = paragraph.elements(forLocalName: "pPr", uri: wordNamespace)
            guard properties.count <= 1 else { return false }
            let breaks = properties.first?.elements(forLocalName: "pageBreakBefore", uri: wordNamespace) ?? []
            guard breaks.count <= 1 else { return false }
            if let pageBreak = breaks.first {
                let value = pageBreak.attribute(forLocalName: "val", uri: wordNamespace)?.stringValue ?? "1"
                if ["1", "true", "on"].contains(value) { return true }
            }
            // Keep the same two accepted forms: a paragraph property or a leading
            // inline page break. Never skip visible content to find a later break.
            let content = (paragraph.children ?? []).compactMap { $0 as? XMLElement }.flatMap { child -> [XMLElement] in
                if child.uri == wordNamespace && ["pPr", "bookmarkStart", "bookmarkEnd", "proofErr"].contains(child.localName ?? "") {
                    return []
                }
                guard child.uri == wordNamespace && child.localName == "r" else { return [child] }
                return (child.children ?? []).compactMap { $0 as? XMLElement }
                    .filter { !($0.uri == wordNamespace && $0.localName == "rPr") }
            }
            guard let first = content.first, first.uri == wordNamespace, first.localName == "br" else { return false }
            return first.attribute(forLocalName: "type", uri: wordNamespace)?.stringValue == "page"
        }
    }

    // Namespace-filtered XPath lookups missed Pandoc nodes on macOS. Use
    // direct children and explicit namespace identities throughout these checks.
    private func wordChild(_ parent: XMLElement?, _ names: String...) -> XMLElement? {
        var current = parent
        for name in names {
            let matches = current?.elements(forLocalName: name, uri: wordNamespace) ?? []
            guard matches.count == 1 else { return nil }
            current = matches[0]
        }
        return current
    }

    private func unqualifiedAttribute(_ element: XMLElement, _ name: String) -> String? {
        // In parsed XML, unprefixed attributes have no namespace. Matching the
        // full name rejects foreign prefixes without reading an attribute URI.
        guard !name.contains(":") else { return nil }
        let matches = (element.attributes ?? []).filter { $0.name == name }
        return matches.count == 1 ? matches[0].stringValue : nil
    }

    private func wordText(_ element: XMLElement) -> String {
        if element.uri == wordNamespace && element.localName == "t" { return element.stringValue ?? "" }
        return (element.children ?? []).compactMap { $0 as? XMLElement }.map { wordText($0) }.joined()
    }

    private func officeRoundTrip(_ source: URL, through intermediate: String, reviewCase: String? = nil) async throws -> URL {
        let middle = try await engine.run(inputs: [source], operation: FileOperation(id: "convert.\(intermediate)", title: intermediate.uppercased()))
        let result = try await engine.run(inputs: middle.outputs, operation: FileOperation(id: "convert.\(source.pathExtension)", title: source.pathExtension.uppercased()))
        XCTAssertEqual(middle.outputs.count, 1); XCTAssertEqual(result.outputs.count, 1)
        if let reviewCase {
            // These pending copies are packaged only after the complete selected
            // test run succeeds, including the assertions on the extracted result.
            try captureOfficeReview(reviewCase, files: [
                ("source.\(source.pathExtension)", source),
                ("intermediate.\(intermediate)", try XCTUnwrap(middle.outputs.first)),
                ("converted.\(source.pathExtension)", try XCTUnwrap(result.outputs.first))
            ])
        }
        let extracted = try await ExternalConverters.archives(result.outputs, operation: FileOperation(id: "archive.extract", title: "Extract"), directory: root)
        return try XCTUnwrap(extracted.outputs.first)
    }

    private func captureOfficeReview(_ caseName: String, files: [(String, URL)]) throws {
        guard let path = ProcessInfo.processInfo.environment["LEMULIP_OFFICE_REVIEW_DIR"] else { return }
        guard path.hasPrefix("/") else {
            throw FreewheelError.operationFailed("The Office review destination must be an absolute path.")
        }
        let destination = URL(fileURLWithPath: path, isDirectory: true)
        var directoryInfo = stat()
        guard lstat(destination.path, &directoryInfo) == 0,
              directoryInfo.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              directoryInfo.st_mode & 0o077 == 0, directoryInfo.st_uid == geteuid() else {
            throw FreewheelError.operationFailed("The Office review destination must be an existing private directory owned by the current user.")
        }
        let folder = destination.appendingPathComponent(caseName, isDirectory: true)
        guard mkdir(folder.path, 0o700) == 0 else {
            throw FreewheelError.operationFailed("An Office review case could not be created. Use a new empty review destination.")
        }
        var complete = false
        defer { if !complete { try? FileManager.default.removeItem(at: folder) } }
        let sourcePrefix = root.resolvingSymlinksInPath().path + "/"
        let limit = 8 * 1_024 * 1_024
        for (name, source) in files {
            guard source.resolvingSymlinksInPath().path.hasPrefix(sourcePrefix) else {
                throw FreewheelError.operationFailed("Office review files must come from the generated test documents.")
            }
            let descriptor = open(source.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            guard descriptor >= 0 else {
                throw FreewheelError.operationFailed("An Office review source could not be opened as a regular file.")
            }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            defer { try? handle.close() }
            var information = stat()
            guard fstat(descriptor, &information) == 0,
                  information.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
                  information.st_size > 0, information.st_size <= off_t(limit) else {
                throw FreewheelError.operationFailed("Office review files must be nonempty regular files no larger than 8 MiB.")
            }
            var bytes = Data()
            while let chunk = try handle.read(upToCount: min(65_536, limit - bytes.count + 1)), !chunk.isEmpty {
                bytes.append(chunk)
                guard bytes.count <= limit else {
                    throw FreewheelError.operationFailed("An Office review file exceeded the 8 MiB limit while being copied.")
                }
            }
            guard bytes.count == Int(information.st_size) else {
                throw FreewheelError.operationFailed("An Office review file changed while being copied.")
            }
            try bytes.write(to: folder.appendingPathComponent(name), options: .withoutOverwriting)
        }
        complete = true
    }

    private func officeXML(_ package: URL, _ part: String) throws -> XMLDocument {
        // Word text can consist only of spaces. Make them visible text nodes on
        // macOS; nodePreserveWhitespace would suppress this promotion option.
        try XMLDocument(contentsOf: package.appendingPathComponent(part),
                        options: [.nodeLoadExternalEntitiesNever, .nodePromoteSignificantWhitespace])
    }

    private func relatedOfficeParts(_ package: URL, mainPart: String, elements: [XMLNode]) throws -> [String] {
        let main = URL(fileURLWithPath: mainPart)
        let base = main.deletingLastPathComponent().lastPathComponent
        let relationships = try officeXML(package, "\(base)/_rels/\(main.lastPathComponent).rels")
        return try elements.map { element in
            let node = try XCTUnwrap(element as? XMLElement)
            // Match through the attribute API, independent of the prefix
            // chosen by the writer or the XPath namespace context.
            let identifier = try XCTUnwrap(node.attribute(forLocalName: "id",
                uri: "http://schemas.openxmlformats.org/officeDocument/2006/relationships")?.stringValue,
                "Missing Office relationship ID on \(node.name ?? "element"); attributes: \((node.attributes ?? []).map { "\($0.name ?? "?") [\($0.uri ?? "no namespace")]" }.joined(separator: ", "))")
            let relation = try XCTUnwrap(relationships.nodes(forXPath: "/*[local-name()='Relationships']/*[local-name()='Relationship' and @Id='\(identifier)']").first)
            XCTAssertNotEqual(try relation.nodes(forXPath: "./@TargetMode").first?.stringValue, "External")
            let target = try XCTUnwrap(relation.nodes(forXPath: "./@Target").first?.stringValue)
            return target.hasPrefix("/") ? String(target.dropFirst()) : "\(base)/\(target)"
        }
    }

    private func officeFixture(_ name: String, parts: [String: String]) async throws -> URL {
        let folder = root.appendingPathComponent("fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        for (path, xml) in parts {
            let file = folder.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try xml.write(to: file, atomically: false, encoding: .utf8)
        }
        let entries = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        let archive = try await ExternalConverters.archives(entries, operation: FileOperation(id: "archive.createZip", title: "Create ZIP"), directory: root)
        let file = root.appendingPathComponent(name)
        try FileManager.default.moveItem(at: XCTUnwrap(archive.outputs.first), to: file)
        return file
    }

    private func officeRelationships(_ entries: [(String, String, String)]) -> String {
        "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">" + entries.map {
            "<Relationship Id=\"\($0.0)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/\($0.1)\" Target=\"\($0.2)\"/>"
        }.joined() + "</Relationships>"
    }

    private func officeContentTypes(_ entries: [(String, String)]) -> String {
        "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/>" + entries.map {
            "<Override PartName=\"/\($0.0)\" ContentType=\"application/vnd.openxmlformats-officedocument.\($0.1)+xml\"/>"
        }.joined() + "</Types>"
    }

    private func wordFixtureParts() -> [String: String] {
        let tableRows = [["Item", "Amount"], ["İstanbul", "12.50"]].map { cells in
            "<w:tr>" + cells.map { "<w:tc><w:tcPr><w:tcW w:w=\"3600\" w:type=\"dxa\"/></w:tcPr><w:p><w:r><w:t>\($0)</w:t></w:r></w:p></w:tc>" }.joined() + "</w:tr>"
        }.joined()
        return [
            "[Content_Types].xml": officeContentTypes([("word/document.xml", "wordprocessingml.document.main")]),
            "_rels/.rels": officeRelationships([("rId1", "officeDocument", "word/document.xml")]),
            "word/document.xml": """
            <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>
            <w:p><w:r><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/><w:b/><w:i/><w:sz w:val="28"/></w:rPr><w:t>Orchard Notes</w:t></w:r></w:p>
            <w:p><w:r><w:t>A second paragraph with Unicode: İstanbul.</w:t></w:r></w:p>
            <w:tbl><w:tblPr><w:tblW w:w="7200" w:type="dxa"/></w:tblPr><w:tblGrid><w:gridCol w:w="3600"/><w:gridCol w:w="3600"/></w:tblGrid>\(tableRows)</w:tbl>
            <w:p><w:pPr><w:pageBreakBefore/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/><w:b/><w:sz w:val="28"/></w:rPr><w:t>A Fresh Page</w:t></w:r></w:p>
            <w:p><w:r><w:t>This paragraph follows an explicit page break. The table stays on the first page.</w:t></w:r></w:p>
            <w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr>
            </w:body></w:document>
            """
        ]
    }

    private func spreadsheetFixtureParts() -> [String: String] {
        let namespace = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
        return [
            "[Content_Types].xml": officeContentTypes([("xl/workbook.xml", "spreadsheetml.sheet.main"), ("xl/styles.xml", "spreadsheetml.styles"), ("xl/worksheets/sheet1.xml", "spreadsheetml.worksheet"), ("xl/worksheets/sheet2.xml", "spreadsheetml.worksheet")]),
            "_rels/.rels": officeRelationships([("rId1", "officeDocument", "xl/workbook.xml")]),
            "xl/_rels/workbook.xml.rels": officeRelationships([("rId1", "worksheet", "worksheets/sheet1.xml"), ("rId2", "worksheet", "worksheets/sheet2.xml"), ("rId3", "styles", "styles.xml")]),
            "xl/workbook.xml": "<workbook xmlns=\"\(namespace)\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets><sheet name=\"Budget\" sheetId=\"1\" r:id=\"rId1\"/><sheet name=\"Summary\" sheetId=\"2\" r:id=\"rId2\"/></sheets><calcPr fullCalcOnLoad=\"1\"/></workbook>",
            "xl/styles.xml": "<styleSheet xmlns=\"\(namespace)\"><fonts count=\"1\"><font><sz val=\"11\"/><name val=\"Arial\"/></font></fonts><fills count=\"2\"><fill><patternFill patternType=\"none\"/></fill><fill><patternFill patternType=\"gray125\"/></fill></fills><borders count=\"1\"><border/></borders><cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs><cellXfs count=\"2\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\"/><xf numFmtId=\"2\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyNumberFormat=\"1\"/></cellXfs><cellStyles count=\"1\"><cellStyle name=\"Normal\" xfId=\"0\" builtinId=\"0\"/></cellStyles></styleSheet>",
            "xl/worksheets/sheet1.xml": """
            <worksheet xmlns="\(namespace)"><sheetData>
            <row r="1"><c r="A1" t="inlineStr"><is><t>Identifier</t></is></c><c r="B1" t="inlineStr"><is><t>Amount</t></is></c></row>
            <row r="2"><c r="A2" t="inlineStr"><is><t>00123</t></is></c><c r="B2" s="1"><v>12.5</v></c><c r="C2" t="b"><v>1</v></c><c r="D2" t="inlineStr"><is><t>12345678901234567890</t></is></c></row>
            <row r="3"><c r="A3" t="inlineStr"><is><t>İstanbul</t></is></c><c r="B3" s="1"><v>7.5</v></c></row>
            <row r="4"><c r="B4" s="1"><f>SUM(B2:B3)</f><v>20</v></c></row>
            </sheetData></worksheet>
            """,
            "xl/worksheets/sheet2.xml": "<worksheet xmlns=\"\(namespace)\"><sheetData><row r=\"1\"><c r=\"A1\"><f>Budget!B4*2</f><v>40</v></c></row></sheetData></worksheet>"
        ]
    }

    private func presentationFixtureParts() -> [String: String] {
        let namespaces = "xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\""
        let group = "<p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"0\" cy=\"0\"/><a:chOff x=\"0\" y=\"0\"/><a:chExt cx=\"0\" cy=\"0\"/></a:xfrm></p:grpSpPr>"
        let colors = [("dk1", "000000"), ("lt1", "FFFFFF"), ("dk2", "13261D"), ("lt2", "F8F8F2"), ("accent1", "00A36C"), ("accent2", "FFC928"), ("accent3", "DD6247"), ("accent4", "247BA0"), ("accent5", "8E6C9B"), ("accent6", "52796F"), ("hlink", "0563C1"), ("folHlink", "954F72")]
        let fills = String(repeating: "<a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill>", count: 3)
        let lines = String(repeating: "<a:ln w=\"6350\"><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill><a:prstDash val=\"solid\"/></a:ln>", count: 3)
        var parts = [
            "[Content_Types].xml": officeContentTypes([("ppt/presentation.xml", "presentationml.presentation.main"), ("ppt/presProps.xml", "presentationml.presProps"), ("ppt/slideMasters/slideMaster1.xml", "presentationml.slideMaster"), ("ppt/slideLayouts/slideLayout1.xml", "presentationml.slideLayout"), ("ppt/theme/theme1.xml", "theme"), ("ppt/slides/slide1.xml", "presentationml.slide"), ("ppt/slides/slide2.xml", "presentationml.slide")]),
            "_rels/.rels": officeRelationships([("rId1", "officeDocument", "ppt/presentation.xml")]),
            "ppt/presentation.xml": "<p:presentation \(namespaces)><p:sldMasterIdLst><p:sldMasterId id=\"2147483648\" r:id=\"rId1\"/></p:sldMasterIdLst><p:sldIdLst><p:sldId id=\"256\" r:id=\"rId2\"/><p:sldId id=\"257\" r:id=\"rId3\"/></p:sldIdLst><p:sldSz cx=\"12192000\" cy=\"6858000\"/><p:notesSz cx=\"6858000\" cy=\"9144000\"/></p:presentation>",
            "ppt/_rels/presentation.xml.rels": officeRelationships([("rId1", "slideMaster", "slideMasters/slideMaster1.xml"), ("rId2", "slide", "slides/slide1.xml"), ("rId3", "slide", "slides/slide2.xml"), ("rId4", "presProps", "presProps.xml")]),
            "ppt/presProps.xml": "<p:presentationPr \(namespaces)/>",
            "ppt/slideMasters/slideMaster1.xml": "<p:sldMaster \(namespaces)><p:cSld><p:spTree>\(group)</p:spTree></p:cSld><p:clrMap bg1=\"lt1\" tx1=\"dk1\" bg2=\"lt2\" tx2=\"dk2\" accent1=\"accent1\" accent2=\"accent2\" accent3=\"accent3\" accent4=\"accent4\" accent5=\"accent5\" accent6=\"accent6\" hlink=\"hlink\" folHlink=\"folHlink\"/><p:sldLayoutIdLst><p:sldLayoutId id=\"2147483649\" r:id=\"rId1\"/></p:sldLayoutIdLst><p:txStyles><p:titleStyle/><p:bodyStyle/><p:otherStyle/></p:txStyles></p:sldMaster>",
            "ppt/slideMasters/_rels/slideMaster1.xml.rels": officeRelationships([("rId1", "slideLayout", "../slideLayouts/slideLayout1.xml"), ("rId2", "theme", "../theme/theme1.xml")]),
            "ppt/slideLayouts/slideLayout1.xml": "<p:sldLayout \(namespaces) type=\"blank\" preserve=\"1\"><p:cSld name=\"Blank\"><p:spTree>\(group)</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>",
            "ppt/slideLayouts/_rels/slideLayout1.xml.rels": officeRelationships([("rId1", "slideMaster", "../slideMasters/slideMaster1.xml")])
        ]
        let colorScheme = colors.map { "<a:\($0.0)><a:srgbClr val=\"\($0.1)\"/></a:\($0.0)>" }.joined()
        parts["ppt/theme/theme1.xml"] = "<a:theme xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" name=\"Fixture\"><a:themeElements><a:clrScheme name=\"Fixture\">\(colorScheme)</a:clrScheme><a:fontScheme name=\"Fixture\"><a:majorFont><a:latin typeface=\"Arial\"/><a:ea typeface=\"\"/><a:cs typeface=\"\"/></a:majorFont><a:minorFont><a:latin typeface=\"Arial\"/><a:ea typeface=\"\"/><a:cs typeface=\"\"/></a:minorFont></a:fontScheme><a:fmtScheme name=\"Fixture\"><a:fillStyleLst>\(fills)</a:fillStyleLst><a:lnStyleLst>\(lines)</a:lnStyleLst><a:effectStyleLst>\(String(repeating: "<a:effectStyle><a:effectLst/></a:effectStyle>", count: 3))</a:effectStyleLst><a:bgFillStyleLst>\(fills)</a:bgFillStyleLst></a:fmtScheme></a:themeElements></a:theme>"
        func shape(_ id: Int, _ text: String, x: Int, y: Int, width: Int, height: Int, fill: String) -> String {
            "<p:sp><p:nvSpPr><p:cNvPr id=\"\(id)\" name=\"\(text)\"/><p:cNvSpPr txBox=\"1\"/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x=\"\(x)\" y=\"\(y)\"/><a:ext cx=\"\(width)\" cy=\"\(height)\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom>\(fill)<a:ln><a:noFill/></a:ln></p:spPr><p:txBody><a:bodyPr wrap=\"square\"/><a:lstStyle/><a:p><a:r><a:rPr lang=\"en-US\" sz=\"2400\"><a:solidFill><a:srgbClr val=\"13261D\"/></a:solidFill><a:latin typeface=\"Arial\"/></a:rPr><a:t>\(text)</a:t></a:r><a:endParaRPr lang=\"en-US\"/></a:p></p:txBody></p:sp>"
        }
        for (index, title) in ["Orchard Overview", "Lemon Details"].enumerated() {
            let heading = shape(2, title, x: 914_400, y: 914_400, width: 9_144_000, height: 685_800, fill: "<a:noFill/>")
            let panel = shape(3, "Panel \(index + 1)", x: 914_400 + index * 4_572_000, y: 2_286_000, width: 3_048_000, height: 1_524_000, fill: "<a:solidFill><a:srgbClr val=\"00A36C\"/></a:solidFill>")
            parts["ppt/slides/slide\(index + 1).xml"] = "<p:sld \(namespaces)><p:cSld><p:spTree>\(group)\(heading)\(panel)</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>"
            parts["ppt/slides/_rels/slide\(index + 1).xml.rels"] = officeRelationships([("rId1", "slideLayout", "../slideLayouts/slideLayout1.xml")])
        }
        return parts
    }

    #if os(macOS)
    func testNativePlainTextWordExportOpensInLibreOffice() async throws {
        try require("libreoffice")
        let source = root.appendingPathComponent("notes.txt")
        let original = "Plain Text & <Symbols>\n\nİstanbul • 東京\n  Two  Spaces\tOne Tab\nFinal Paragraph\n"
        try original.write(to: source, atomically: true, encoding: .utf8)
        let word = try await engine.run(inputs: [source], operation: FileOperation(id: "convert.docx", title: "DOCX"))
        let imported = try await ExternalConverters.office(word.outputs,
            operation: FileOperation(id: "convert.txt", title: "TXT"), directory: root)
        // Word readers may normalize paragraph terminators and the mandatory
        // final paragraph. Interior whitespace and paragraph order must survive.
        func paragraphs(_ text: String) -> String {
            text.replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .trimmingCharacters(in: .newlines)
        }
        XCTAssertEqual(paragraphs(try TextCodec.read(imported.outputs[0])), paragraphs(original))
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), original)
        try captureOfficeReview("word-text", files: [
            ("source.txt", source), ("converted.docx", try XCTUnwrap(word.outputs.first))
        ])
    }
    #endif

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
