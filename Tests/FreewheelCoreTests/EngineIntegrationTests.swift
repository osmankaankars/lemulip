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
        let secondPage = try XCTUnwrap(document.nodes(forXPath: "//*[local-name()='p'][.//*[local-name()='t']='A Fresh Page']").first)
        let pageBreak = try secondPage.nodes(forXPath: "./*[local-name()='pPr']/*[local-name()='pageBreakBefore']").first
        let pageBreakValue = try pageBreak?.nodes(forXPath: "./@*[local-name()='val']").first?.stringValue ?? "1"
        let paragraphStartsPage = pageBreak != nil && ["1", "true", "on"].contains(pageBreakValue)
        // LibreOffice can write the equivalent page break as the first inline
        // item. A break after heading text, or an ordinary line break, is not enough.
        let firstInline = try secondPage.nodes(forXPath: ".//*[local-name()='r']/*[not(local-name()='rPr')]").first
        let inlineBreakType = try firstInline?.nodes(forXPath: "./@*[local-name()='type']").first?.stringValue
        let startsWithPageBreak = firstInline?.localName == "br" && inlineBreakType == "page"
        XCTAssertTrue(paragraphStartsPage || startsWithPageBreak, "The second-page heading must follow an explicit page boundary.")
        XCTAssertEqual(try secondPage.nodes(forXPath: "preceding::*[local-name()='tbl']").count, 1)
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
        try XMLDocument(contentsOf: package.appendingPathComponent(part), options: .nodeLoadExternalEntitiesNever)
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
