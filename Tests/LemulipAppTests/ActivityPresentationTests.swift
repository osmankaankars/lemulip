#if os(macOS)
import Foundation
import XCTest
import LemulipCore
@testable import Lemulip

final class ActivityPresentationTests: XCTestCase {
    func testActualWordCountPreservesNamesAndDoesNotClaimNewFiles() async throws {
        let directory = try workspace()
        let inputs = [
            directory.appendingPathComponent("words: Örnek characters · lines.txt"),
            directory.appendingPathComponent("Second\nwords: satırlar.txt")
        ]
        let bodies = ["one two\nthree", "a"]
        for (input, body) in zip(inputs, bodies) { try Data(body.utf8).write(to: input) }
        let operation = FileOperation(id: "document.wordCount", title: "Count Words")
        let result = try await ConversionEngine().run(inputs: inputs, operation: operation)
        XCTAssertTrue(result.outputs.isEmpty, "A report must not create a result file")
        let note = try XCTUnwrap(result.note)
        let originalReport = "\(inputs[0].lastPathComponent): 3 words · 13 characters · 2 lines\n"
            + "\(inputs[1].lastPathComponent): 1 words · 1 characters · 1 lines"
        XCTAssertEqual(note, originalReport, "The core/CLI report remains unchanged")

        let turkish = ActivityPresentation.completionMessage(note: note, operationID: operation.id,
            inputs: inputs, options: ConversionOptions(), language: "tr")
        XCTAssertEqual(turkish, "\(inputs[0].lastPathComponent): 3 kelime · 13 karakter · 2 satır\n"
            + "\(inputs[1].lastPathComponent): 1 kelime · 1 karakter · 1 satır")
        let english = ActivityPresentation.completionMessage(note: note, operationID: operation.id,
            inputs: inputs, options: ConversionOptions(), language: "en")
        XCTAssertEqual(english, "\(inputs[0].lastPathComponent): 3 words · 13 characters · 2 lines\n"
            + "\(inputs[1].lastPathComponent): 1 word · 1 character · 1 line")
        var item = ActivityItem(operation: operation, inputs: inputs)
        item.state = .succeeded
        item.outputs = result.outputs
        XCTAssertEqual(ActivityPresentation.status(for: item, language: "en"), "Completed")
        XCTAssertEqual(ActivityPresentation.status(for: item, language: "tr"), "Tamamlandı")
        // Enumerate the exact fixture directory by entry name: macOS may spell
        // its temporary parent /var or /private/var in otherwise identical URLs.
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)),
                       Set(inputs.map(\.lastPathComponent)))
        for (input, body) in zip(inputs, bodies) { XCTAssertEqual(try Data(contentsOf: input), Data(body.utf8)) }
    }

    func testWordCountRejectsUnknownPartialOrMismatchedReportsWithoutReplacingText() {
        let input = URL(fileURLWithPath: "/tmp/words: Örnek.txt")
        let known = "\(input.lastPathComponent): 3 words · 13 characters · 2 lines"
        let reports = [
            known + "\nExtra diagnostic detail.",
            known + " unexpectedly",
            "Other.txt: 3 words · 13 characters · 2 lines",
            "\(input.lastPathComponent): three words · 13 characters · 2 lines",
            "\(input.lastPathComponent): -3 words · 13 characters · 2 lines",
            "\(input.lastPathComponent): 999999999999999999999999999999 words · 13 characters · 2 lines"
        ]
        for report in reports {
            for language in ["en", "tr"] {
                XCTAssertEqual(ActivityPresentation.completionMessage(note: report, operationID: "document.wordCount",
                    inputs: [input], options: ConversionOptions(), language: language), report)
            }
        }
        XCTAssertEqual(ActivityPresentation.completionMessage(note: known, operationID: "convert.txt",
            inputs: [input], options: ConversionOptions(), language: "tr"), known,
            "A different operation's text must not be interpreted as a word-count report")
        XCTAssertEqual(ActivityPresentation.completionMessage(note: known, operationID: "document.wordCount",
            inputs: [input, URL(fileURLWithPath: "/tmp/Missing.txt")], options: ConversionOptions(), language: "tr"), known,
            "A partial multi-file report must stay intact")
    }

    func testActualWordCountPreservesTheResolvedSymlinkSourceName() async throws {
        let directory = try workspace()
        let target = directory.appendingPathComponent("words: Gerçek characters.txt")
        let alias = directory.appendingPathComponent("Alias.txt")
        let original = Data("hello".utf8)
        try original.write(to: target)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: target)
        let result = try await ConversionEngine().run(inputs: [alias],
            operation: FileOperation(id: "document.wordCount", title: "Count Words"))
        XCTAssertTrue(result.outputs.isEmpty)
        let note = try XCTUnwrap(result.note)
        XCTAssertEqual(note, "\(target.lastPathComponent): 1 words · 5 characters · 1 lines")
        XCTAssertEqual(ActivityPresentation.completionMessage(note: note, operationID: "document.wordCount",
            inputs: [alias], options: ConversionOptions(), language: "tr"),
            "\(target.lastPathComponent): 1 kelime · 5 karakter · 1 satır",
            "Localize the report while retaining the engine's actual resolved source name")
        XCTAssertEqual(ActivityPresentation.completionMessage(note: note, operationID: "document.wordCount",
            inputs: [alias], options: ConversionOptions(), language: "en"),
            "\(target.lastPathComponent): 1 word · 5 characters · 1 line")
        XCTAssertEqual(try Data(contentsOf: target), original)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: alias.path), target.path)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)),
                       Set([target.lastPathComponent, alias.lastPathComponent]))
    }

    func testTransfersDescribeItemsAndConversionsDescribeNewFiles() {
        let outputs = [URL(fileURLWithPath: "/tmp/Report.pdf"), URL(fileURLWithPath: "/tmp/Folder", isDirectory: true)]
        for (operationID, english, turkish) in [
            ("action.move", "Moved · 2 items", "Taşındı · 2 öğe"),
            ("action.copy", "Copied · 2 items", "Kopyalandı · 2 öğe"),
            ("convert.pdf", "Completed · 2 new files", "Tamamlandı · 2 yeni dosya")
        ] {
            var item = ActivityItem(operation: FileOperation(id: operationID, title: operationID), inputs: outputs)
            item.state = .succeeded
            item.outputs = outputs
            XCTAssertEqual(ActivityPresentation.status(for: item, language: "en"), english)
            XCTAssertEqual(ActivityPresentation.status(for: item, language: "tr"), turkish)
            XCTAssertEqual(ActivityPresentation.status(for: item, language: "fr"), english,
                           "Unrecognized language preferences retain the existing English fallback")
        }
    }

    func testWordCountFormatsCountsWithoutChangingValuesOrFilename() {
        let input = URL(fileURLWithPath: "/tmp/1,000 words · 2.000 lines.txt")
        let report = "\(input.lastPathComponent): 1000 words · 2000 characters · 30 lines"
        XCTAssertEqual(ActivityPresentation.completionMessage(note: report, operationID: "document.wordCount",
            inputs: [input], options: ConversionOptions(), language: "tr"),
            "\(input.lastPathComponent): 1.000 kelime · 2.000 karakter · 30 satır")
        XCTAssertEqual(ActivityPresentation.completionMessage(note: report, operationID: "document.wordCount",
            inputs: [input], options: ConversionOptions(), language: "en"),
            "\(input.lastPathComponent): 1,000 words · 2,000 characters · 30 lines")
    }

    func testCompletionNotesRequireTheirOperationContextAndPreserveUnknownDetails() {
        let pdf = "Created a new PDF without password protection. Review links, bookmarks, forms, and signatures after changing pages."
        XCTAssertEqual(ActivityPresentation.completionMessage(note: pdf, operationID: "convert.pdf", inputs: [],
            options: ConversionOptions(), language: "tr"), pdf)
        var options = ConversionOptions()
        options.pdfOrganization = PDFOrganizePlan(sourcePageCount: 1, sourceFingerprint: String(repeating: "a", count: 64),
                                                 pages: [PDFPageEdit(sourceIndex: 0)])
        let extended = pdf + " Additional source warning."
        XCTAssertEqual(ActivityPresentation.completionMessage(note: extended, operationID: "pdf.organize", inputs: [],
            options: options, language: "tr"), extended)
        XCTAssertEqual(ActivityPresentation.completionMessage(note: pdf, operationID: "pdf.organize", inputs: [],
            options: options, language: "en"), pdf)
        XCTAssertEqual(ActivityPresentation.completionMessage(note: nil, operationID: "pdf.organize", inputs: [],
            options: options, language: "tr"), "")
    }

    private func workspace() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Lemulip-Activity-Language-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
}
#endif
