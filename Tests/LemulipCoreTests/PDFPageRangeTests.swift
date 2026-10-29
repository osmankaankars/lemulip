import XCTest
@testable import LemulipCore

final class PDFPageRangeTests: XCTestCase {
    func testRequestedOrderAndOverlapsKeepEachPageOnlyOnce() throws {
        let range = try PDFPageRange("3,1-2,3,2-4")
        XCTAssertEqual(try range.indices(pageCount: 4), [2, 0, 1, 3])
    }

    func testWhitespaceAndExplicitPositiveSignsKeepExistingSyntax() throws {
        let range = try PDFPageRange("\n +3 , \t+1 - +2 \n, 0004 ")
        XCTAssertEqual(try range.indices(pageCount: 4), [2, 0, 1, 3])
    }

    func testEmptyInputHasItsOwnRecoverableError() {
        for specification in ["", " ", "\n\t "] {
            assertSyntaxError(specification, .empty)
        }
    }

    func testMalformedInputIsRejectedWithoutNeedingADocument() {
        for specification in ["0", "-1", "3-1", "1,,2", ",1", "1,", "1-", "1--2",
                              "1-2-3", "one", "1.5", "+", "++1", "1 2", "1\n-2",
                              String(Int.max) + "0", "1-" + String(Int.max) + "0"] {
            assertSyntaxError(specification, .invalidRange)
        }
    }

    func testExistingLengthLimitIncludesSurroundingWhitespace() throws {
        let atLimit = "1" + String(repeating: " ", count: PDFPageRange.maximumSpecificationLength - 1)
        XCTAssertEqual(try PDFPageRange(atLimit).indices(pageCount: 1), [0])
        assertSyntaxError(atLimit + " ", .tooLong)
    }

    func testLargeRangesCanBeValidatedWithoutExpandingThem() throws {
        let range = try PDFPageRange("1-\(Int.max)")
        assertBoundsError(range, pageCount: 3)
        assertSyntaxError("1-\(Int.max),0", .invalidRange)
    }

    func testEveryRequestedPageMustExistInTheDocument() throws {
        let range = try PDFPageRange("1-3,4")
        assertBoundsError(range, pageCount: 3)
        assertBoundsError(try PDFPageRange("1"), pageCount: 0)
        assertBoundsError(try PDFPageRange("1"), pageCount: -1)
        XCTAssertEqual(try range.indices(pageCount: 4), [0, 1, 2, 3])
    }

    private func assertSyntaxError(_ specification: String, _ expected: PDFPageRange.SyntaxError,
                                   file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try PDFPageRange(specification), file: file, line: line) { error in
            XCTAssertEqual(error as? PDFPageRange.SyntaxError, expected, file: file, line: line)
        }
    }

    private func assertBoundsError(_ range: PDFPageRange, pageCount: Int,
                                   file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try range.indices(pageCount: pageCount), file: file, line: line) { error in
            guard case LemulipError.invalidInput = error else {
                XCTFail("Expected an invalid PDF page bound, got \(error)", file: file, line: line)
                return
            }
        }
    }
}
