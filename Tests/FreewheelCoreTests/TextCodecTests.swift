import XCTest
@testable import FreewheelCore

final class TextCodecTests: XCTestCase {
    func testSRTToVTTKeepsTimingUnicodeAndMultilineText() throws {
        let input = "\u{FEFF}1\r\n00:00:01,250 --> 00:00:03,010\r\nMerhaba dünya\r\nSecond line\r\n\r\n2\r\n00:01:59,999 --> 00:02:00,000\r\nGoodbye\r\n"
        let converted = try TextCodec.convertSubtitles(input, from: "srt", to: "vtt")
        XCTAssertTrue(converted.hasPrefix("WEBVTT\n\n00:00:01.250 --> 00:00:03.010\n"))
        XCTAssertTrue(converted.contains("Merhaba dünya\nSecond line"))
        XCTAssertTrue(converted.contains("00:01:59.999 --> 00:02:00.000"))
    }

    func testWebVTTIdentifiersSettingsAndNotesConvertToSRT() throws {
        let input = "WEBVTT\n\nNOTE A comment\nnot a cue\n\ncue-one\n01:02.300 --> 01:04.550 align:start position:10%\n<v Speaker><b>Hello</b> &amp; welcome\n"
        let converted = try TextCodec.convertSubtitles(input, from: "vtt", to: "srt")
        XCTAssertEqual(converted, "1\n00:01:02,300 --> 00:01:04,550\nHello & welcome\n")
    }

    func testSubtitlePlainTextHasNoTimestampsOrFormatting() throws {
        let input = "1\n00:00:00,000 --> 00:00:01,000\n<i>One</i>\n\n2\n00:00:01,000 --> 00:00:02,000\nTwo\n"
        XCTAssertEqual(try TextCodec.convertSubtitles(input, from: "srt", to: "txt"), "One\n\nTwo\n")
    }

    func testInvalidSubtitleIsRejectedInsteadOfSilentlyDroppingCue() {
        XCTAssertThrowsError(try TextCodec.convertSubtitles("1\n00:00:02,000 --> 00:00:01,000\nText", from: "srt", to: "vtt"))
        XCTAssertThrowsError(try TextCodec.convertSubtitles("1\n00:99:00,000 --> 01:00:00,000\nText", from: "srt", to: "vtt"))
        XCTAssertThrowsError(try TextCodec.convertSubtitles("not a subtitle", from: "srt", to: "vtt"))
        XCTAssertThrowsError(try TextCodec.convertSubtitles("00:00.000 --> 00:01.000\nText", from: "vtt", to: "srt"))
    }

    func testCSVToTSVRoundTripPreservesQuotesNewlinesTabsAndEmptyCells() throws {
        let input = "name,note,value,empty\r\n\"Ada, Jr.\",\"Line one\r\nLine two with \"\"quotes\"\"\",\"tab\there\",\r\nΩ,last,42,\r\n"
        let tsv = try TextCodec.convertDelimited(input, from: ",", to: "\t")
        let roundTrip = try TextCodec.convertDelimited(tsv, from: "\t", to: ",")
        XCTAssertEqual(try TextCodec.parseDelimited(roundTrip, delimiter: ","), try TextCodec.parseDelimited(input, delimiter: ","))
        XCTAssertEqual(try TextCodec.parseDelimited(tsv, delimiter: "\t")[1][1], "Line one\r\nLine two with \"quotes\"")
        XCTAssertEqual(try TextCodec.parseDelimited(tsv, delimiter: "\t")[1][3], "")
    }

    func testCSVHandlesEmptyInputFinalDelimiterAndCRLineEndings() throws {
        XCTAssertEqual(try TextCodec.parseDelimited("", delimiter: ","), [])
        XCTAssertEqual(try TextCodec.parseDelimited("a,", delimiter: ","), [["a", ""]])
        XCTAssertEqual(try TextCodec.parseDelimited("a,b\rc,d\r", delimiter: ","), [["a", "b"], ["c", "d"]])
        XCTAssertEqual(try TextCodec.parseDelimited("\u{FEFF}a,b\n", delimiter: ","), [["a", "b"]])
    }

    func testInvalidCSVQuoteDoesNotSilentlyCorruptData() {
        XCTAssertThrowsError(try TextCodec.parseDelimited("a,\"unterminated", delimiter: ","))
        XCTAssertThrowsError(try TextCodec.parseDelimited("a,\"value\"junk", delimiter: ","))
        XCTAssertThrowsError(try TextCodec.parseDelimited("a,un\"escaped", delimiter: ","))
    }

    func testDelimitedRowsStreamQuotedValuesAndStopWhenConsumerFails() throws {
        var rows: [[String]] = []
        try TextCodec.forEachDelimitedRow("\u{FEFF}name,note,empty\r\n\"Ada, Jr.\",\"one\r\ntwo\"\"quoted\"\"\",\r\n\r\n", delimiter: ",") { rows.append($0) }
        XCTAssertEqual(rows, [["name", "note", "empty"], ["Ada, Jr.", "one\r\ntwo\"quoted\"", ""], [""]])
        var delivered = 0
        XCTAssertThrowsError(try TextCodec.forEachDelimitedRow("a,b\nc,d\ne,f\n", delimiter: ",") { _ in
            delivered += 1
            throw FreewheelError.operationFailed("Stop Reading")
        })
        XCTAssertEqual(delivered, 1)
    }

    func testDelimitedLimitsRejectRowsColumnsCellsAndUTF16WithoutTruncation() throws {
        let limits = TextCodec.DelimitedLimits(rows: 2, columns: 3, cells: 5, fieldUTF16: 3, fieldLineFeeds: 1)
        var rows: [[String]] = []
        try TextCodec.forEachDelimitedRow("1,2,3\n4,5", delimiter: ",", limits: limits) { rows.append($0) }
        XCTAssertEqual(rows, [["1", "2", "3"], ["4", "5"]])
        for input in ["1,2,3,4", "1\n2\n3", "1,2,3\n4,5,6", "🍋ab", "\"\n\n\""] {
            XCTAssertThrowsError(try TextCodec.forEachDelimitedRow(input, delimiter: ",", limits: limits) { _ in })
        }
        let longest = String(repeating: "🍋", count: 16_383) + "a"
        var accepted: [[String]] = []
        try TextCodec.forEachDelimitedRow(longest, delimiter: ",", limits: SpreadsheetWriter.limits) { accepted.append($0) }
        XCTAssertEqual(accepted, [[longest]])
        XCTAssertThrowsError(try TextCodec.forEachDelimitedRow(longest + "a", delimiter: ",", limits: SpreadsheetWriter.limits) { _ in })
        let lineFeeds = "\"" + String(repeating: "\n", count: 253) + "\""
        XCTAssertNoThrow(try TextCodec.forEachDelimitedRow(lineFeeds, delimiter: ",", limits: SpreadsheetWriter.limits) { _ in })
    }

    func testWorkbookRowAndCellBudgetsStopDelimiterHeavyInputsEarly() throws {
        var count = 0
        let tooManyRows = String(repeating: "\n", count: 100_001)
        XCTAssertThrowsError(try TextCodec.forEachDelimitedRow(tooManyRows, delimiter: ",", limits: SpreadsheetWriter.limits) { _ in count += 1 })
        XCTAssertEqual(count, 100_000)
        let row = String(repeating: ",", count: 9) + "\n"
        var cells = 0
        XCTAssertThrowsError(try TextCodec.forEachDelimitedRow(String(repeating: row, count: 50_001), delimiter: ",", limits: SpreadsheetWriter.limits) { values in cells += values.count })
        XCTAssertEqual(cells, 500_000)
    }

    func testDelimitedParsingObservesCancellationInsideALongQuotedField() async throws {
        let task = Task {
            var delivered = 0
            do {
                try TextCodec.forEachDelimitedRow("first\n\"" + String(repeating: "\"\"", count: 20_000) + "\"", delimiter: ",") { _ in
                    delivered += 1
                    withUnsafeCurrentTask { $0?.cancel() }
                }
                XCTFail("A cancelled parser finished the table")
            } catch is CancellationError { XCTAssertEqual(delivered, 1) }
        }
        try await task.value
    }

    func testTextReaderRejectsOversizedActualFileAndKeepsUTF8BOMBehavior() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lemulip-text-limit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("large.csv")
        try Data().write(to: input)
        let handle = try FileHandle(forWritingTo: input)
        try handle.truncate(atOffset: UInt64(TextCodec.maximumInputBytes + 1))
        try handle.close()
        XCTAssertThrowsError(try TextCodec.read(input))
        XCTAssertThrowsError(try TextCodec.readData(input))
        let bom = directory.appendingPathComponent("bom.csv")
        try Data([0xEF, 0xBB, 0xBF] + Array("İstanbul,00123\n".utf8)).write(to: bom)
        XCTAssertEqual(try TextCodec.read(bom), "İstanbul,00123\n")
    }

    func testTextByteReaderChecksCancellationBeforeOpeningTheInput() async throws {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try TextCodec.readData(FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString).txt"))
                XCTFail("A cancelled byte read succeeded")
            } catch is CancellationError { }
        }
        try await task.value
    }

    func testWordCountIncludesTurkishAndUnicodeText() {
        XCTAssertEqual(TextCodec.wordCount("Merhaba dünya\nHello again\n"), "4 words · 26 characters · 2 lines")
        XCTAssertEqual(TextCodec.wordCount(""), "0 words · 0 characters · 0 lines")
    }
}
