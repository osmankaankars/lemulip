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

    func testWordCountIncludesTurkishAndUnicodeText() {
        XCTAssertEqual(TextCodec.wordCount("Merhaba dünya\nHello again\n"), "4 words · 26 characters · 2 lines")
        XCTAssertEqual(TextCodec.wordCount(""), "0 words · 0 characters · 0 lines")
    }
}
