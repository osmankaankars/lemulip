#if os(macOS)
import AppKit
import Combine
import CoreGraphics
import CoreText
import PDFKit
import XCTest
import LemulipCore
@testable import Lemulip

/// Exercises the real editors and NSItemProvider payloads with synthetic PDFs.
/// Mouse gestures and TextField focus still require a native interaction check.
final class PDFEditorOrderingTests: XCTestCase {
    @MainActor
    func testMergePreservesIncomingOrderUntilExplicitlySorted() async throws {
        let fixture = try makeFiles(["Page 10.pdf", "Page 2.pdf", "Page 1.pdf"], pageCounts: [1, 2, 3])
        let editor = PDFMergeEditor()
        defer { editor.close() }
        await editor.open(fixture.inputs)
        XCTAssertNil(editor.errorMessage)
        XCTAssertEqual(editor.documents.map(\.inputIndex), [0, 1, 2])
        XCTAssertEqual(editor.exportPlan()?.sources.map(\.inputIndex), [0, 1, 2])
        XCTAssertFalse(editor.canUndo, "Opening must not silently sort the supplied order")

        editor.sortByFilename()
        XCTAssertEqual(editor.documents.map(\.inputIndex), [2, 1, 0], "Natural ordering must place 2 before 10")
        XCTAssertEqual(editor.entries.map(\.firstPage), [1, 4, 6])
        XCTAssertEqual(editor.entries.map(\.lastPage), [3, 5, 6])
        XCTAssertEqual(editor.selectedDocuments, [0])
        editor.undo()
        XCTAssertEqual(editor.documents.map(\.inputIndex), [0, 1, 2])
        editor.redo()
        XCTAssertEqual(editor.documents.map(\.inputIndex), [2, 1, 0])
        editor.reverseOrder()
        XCTAssertEqual(editor.documents.map(\.inputIndex), [0, 1, 2])
        editor.undo()
        editor.restoreInputOrder()
        XCTAssertEqual(editor.documents.map(\.inputIndex), [0, 1, 2])
    }

    @MainActor
    func testFilenameTiesKeepCurrentOrderAndRestoringOrderDoesNotRestoreRemovedFiles() async throws {
        let fixture = try makeFiles(["Same.pdf", "Page 2.pdf", "Same.pdf", "Page 1.pdf"])
        let editor = PDFMergeEditor()
        defer { editor.close() }
        await editor.open(fixture.inputs)
        editor.reverseOrder()
        editor.sortByFilename()
        XCTAssertEqual(editor.documents.map(\.inputIndex), [3, 1, 2, 0],
                       "Equal names in different folders must keep their deliberate relative order")
        editor.select(1)
        editor.removeSelection()
        editor.restoreInputOrder()
        XCTAssertEqual(editor.documents.map(\.inputIndex), [0, 2, 3])
        XCTAssertEqual(editor.exportPlan()?.sourceInputCount, 4)
        editor.undo()
        XCTAssertEqual(editor.documents.map(\.inputIndex), [3, 2, 0])
    }

    @MainActor
    func testMergePositionMovesSelectionToExactAnchorPositionWithUndoAndBounds() async throws {
        let fixture = try makeFiles(["0.pdf", "1.pdf", "2.pdf", "3.pdf", "4.pdf"])
        let editor = PDFMergeEditor()
        defer { editor.close() }
        await editor.open(fixture.inputs)
        XCTAssertTrue(editor.move(0, toPosition: 1))
        XCTAssertFalse(editor.canUndo, "A valid no-op must not create history")
        XCTAssertTrue(editor.move(0, toPosition: 5))
        XCTAssertEqual(editor.documents.map(\.inputIndex), [1, 2, 3, 4, 0])
        editor.undo()
        XCTAssertEqual(editor.documents.map(\.inputIndex), [0, 1, 2, 3, 4])
        XCTAssertTrue(editor.canRedo)
        for position in [Int.min, 0, 6, Int.max] {
            XCTAssertFalse(editor.move(0, toPosition: position))
        }
        XCTAssertTrue(editor.canRedo, "Invalid positions must not mutate redo history")

        editor.select(1)
        editor.select(3, modifiers: .command)
        XCTAssertEqual(editor.positionRange(for: 1), 1...4)
        XCTAssertEqual(editor.positionRange(for: 3), 2...5)
        XCTAssertFalse(editor.move(3, toPosition: 1), "The second selected item cannot precede the first")
        XCTAssertTrue(editor.move(3, toPosition: 5))
        XCTAssertEqual(editor.documents.map(\.inputIndex), [0, 2, 4, 1, 3])
        XCTAssertEqual(editor.selectedDocuments, [1, 3])
        XCTAssertEqual(editor.focusedDocument, 3)
        XCTAssertEqual(editor.exportPlan()?.sources.map(\.inputIndex), [0, 2, 4, 1, 3])
        editor.undo()
        XCTAssertEqual(editor.documents.map(\.inputIndex), [0, 1, 2, 3, 4])
        XCTAssertEqual(editor.selectedDocuments, [1, 3])
        editor.redo()
        XCTAssertEqual(editor.documents.map(\.inputIndex), [0, 2, 4, 1, 3])
    }

    @MainActor
    func testMergeEditedOrderReachesRealOutputWithoutChangingOriginals() async throws {
        let fixture = try makeFiles(["A.pdf", "B.pdf", "C.pdf"])
        let originals = try fixture.inputs.map { try Data(contentsOf: $0) }
        let editor = PDFMergeEditor()
        defer { editor.close() }
        await editor.open(fixture.inputs)
        XCTAssertTrue(editor.move(0, toPosition: 3))
        var options = ConversionOptions()
        options.pdfMerge = try XCTUnwrap(editor.exportPlan())
        options.destinationDirectory = fixture.output
        let result = try await ConversionEngine().run(inputs: fixture.inputs,
            operation: FileOperation(id: "pdf.merge", title: "Merge PDF", outputExtension: "pdf"), options: options)
        let output = try XCTUnwrap(result.outputs.first)
        let merged = try XCTUnwrap(PDFDocument(url: output))
        XCTAssertEqual(merged.pageCount, 3)
        for (position, source) in [1, 2, 0].enumerated() {
            XCTAssertTrue(merged.page(at: position)?.string?.contains("File \(source) Page 1") == true)
        }
        XCTAssertEqual(try fixture.inputs.map { try Data(contentsOf: $0) }, originals)
    }

    @MainActor
    func testMergeDragRoundTripAllowsBoundaryBesideSelectedDocument() async throws {
        let fixture = try makeFiles(["A.pdf", "B.pdf", "C.pdf", "D.pdf"])
        let editor = PDFMergeEditor()
        defer { editor.close() }
        await editor.open(fixture.inputs)
        editor.select(0)
        editor.select(2, modifiers: .command)
        let provider = editor.beginDrag(0)
        let token = try await dragData(provider, type: PDFMergeEditor.dragType)
        XCTAssertNotNil(UUID(uuidString: String(decoding: token, as: UTF8.self)))
        let changed = expectation(description: "Selected documents move beside their own boundary")
        let observation = editor.$documents.dropFirst().sink { documents in
            if documents.map(\.inputIndex) == [1, 0, 2, 3] { changed.fulfill() }
        }
        defer { observation.cancel() }
        XCTAssertTrue(editor.acceptDrop([provider], at: .init(inputIndex: 2, after: false)))
        await fulfillment(of: [changed], timeout: 3)
        observation.cancel()
        XCTAssertEqual(editor.documents.map(\.inputIndex), [1, 0, 2, 3])
        XCTAssertEqual(editor.selectedDocuments, [0, 2])
        XCTAssertFalse(editor.isDragging)
        editor.undo()
        XCTAssertEqual(editor.documents.map(\.inputIndex), [0, 1, 2, 3])
        editor.redo()
        XCTAssertEqual(editor.documents.map(\.inputIndex), [1, 0, 2, 3])
    }

    @MainActor
    func testMergeEditsInvalidateOldDragProviders() async throws {
        let fixture = try makeFiles(["A.pdf", "B.pdf", "C.pdf"])
        let editor = PDFMergeEditor()
        defer { editor.close() }
        await editor.open(fixture.inputs)
        let first = editor.beginDrag(0)
        let firstToken = try await dragData(first, type: PDFMergeEditor.dragType)
        let second = editor.beginDrag(1)
        let secondToken = try await dragData(second, type: PDFMergeEditor.dragType)
        XCTAssertNotEqual(firstToken, secondToken, "Every drag must have its own session token")
        XCTAssertTrue(editor.move(1, toPosition: 3))
        XCTAssertFalse(editor.isDragging)
        XCTAssertFalse(editor.acceptDrop([first], at: .init(inputIndex: 0, after: false)))
        XCTAssertFalse(editor.acceptDrop([second], at: .init(inputIndex: 0, after: false)))
        XCTAssertEqual(editor.documents.map(\.inputIndex), [0, 2, 1])
        editor.close()
        XCTAssertFalse(editor.beginDrag(0).hasItemConformingToTypeIdentifier(PDFMergeEditor.dragType))
    }

    @MainActor
    func testOrganizerPositionKeepsPageIdentityRotationSelectionAndUndo() async throws {
        let fixture = try makeFiles(["Pages.pdf"], pageCounts: [6])
        let editor = PDFOrganizeEditor()
        defer { editor.close() }
        await editor.open(fixture.inputs[0])
        XCTAssertNil(editor.errorMessage)
        XCTAssertEqual(editor.pages.map(\.sourceIndex), [0, 1, 2, 3, 4, 5])
        XCTAssertTrue(editor.move(0, toPosition: 1))
        XCTAssertFalse(editor.canUndo)
        editor.select(1)
        editor.select(3, modifiers: .command)
        editor.rotateSelection(clockwise: true)
        XCTAssertEqual(editor.positionRange(for: 3), 2...6)
        for position in [Int.min, 0, 1, 7, Int.max] {
            XCTAssertFalse(editor.move(3, toPosition: position))
        }
        XCTAssertTrue(editor.move(3, toPosition: 6))
        XCTAssertEqual(editor.pages.map(\.sourceIndex), [0, 2, 4, 5, 1, 3])
        XCTAssertEqual(editor.selectedPages, [1, 3])
        XCTAssertEqual(editor.focusedPage, 3)
        XCTAssertEqual(editor.exportPlan(selectedOnly: true)?.pages.map(\.sourceIndex), [1, 3])
        XCTAssertEqual(editor.pages.suffix(2).map(\.rotationQuarterTurns), [1, 1])
        editor.undo()
        XCTAssertEqual(editor.pages.map(\.sourceIndex), [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(editor.pages.filter { [1, 3].contains($0.sourceIndex) }.map(\.rotationQuarterTurns), [1, 1])
        editor.redo()
        XCTAssertEqual(editor.pages.map(\.sourceIndex), [0, 2, 4, 5, 1, 3])
        editor.selectAll()
        XCTAssertEqual(editor.positionRange(for: 3), 6...6)
        XCTAssertFalse(editor.move(3, toPosition: 1))
    }

    @MainActor
    func testOrganizerDragRoundTripAllowsBoundaryBesideSelectedPage() async throws {
        let fixture = try makeFiles(["Pages.pdf"], pageCounts: [5])
        let editor = PDFOrganizeEditor()
        defer { editor.close() }
        await editor.open(fixture.inputs[0])
        editor.select(1)
        editor.select(3, modifiers: .command)
        let provider = editor.beginDrag(3)
        let token = try await dragData(provider, type: PDFOrganizeEditor.dragType)
        XCTAssertNotNil(UUID(uuidString: String(decoding: token, as: UTF8.self)))
        let changed = expectation(description: "Selected pages move beside their own boundary")
        let observation = editor.$pages.dropFirst().sink { pages in
            if pages.map(\.sourceIndex) == [0, 1, 3, 2, 4] { changed.fulfill() }
        }
        defer { observation.cancel() }
        XCTAssertTrue(editor.acceptDrop([provider], at: .init(sourceIndex: 1, after: true)))
        await fulfillment(of: [changed], timeout: 3)
        observation.cancel()
        XCTAssertEqual(editor.pages.map(\.sourceIndex), [0, 1, 3, 2, 4])
        XCTAssertEqual(editor.selectedPages, [1, 3])
        XCTAssertFalse(editor.isDragging)
        editor.undo()
        XCTAssertEqual(editor.pages.map(\.sourceIndex), [0, 1, 2, 3, 4])
        editor.redo()
        XCTAssertEqual(editor.pages.map(\.sourceIndex), [0, 1, 3, 2, 4])

        let stale = editor.beginDrag(1)
        editor.rotateSelection(clockwise: true)
        XCTAssertFalse(editor.acceptDrop([stale], at: .init(sourceIndex: 0, after: false)))
        editor.close()
        XCTAssertFalse(editor.beginDrag(0).hasItemConformingToTypeIdentifier(PDFOrganizeEditor.dragType))
    }

    private func dragData(_ provider: NSItemProvider, type: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
                if let error { continuation.resume(throwing: error) }
                else if let data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: NSError(domain: "PDFEditorOrderingTests", code: 1)) }
            }
        }
    }

    private func makeFiles(_ names: [String], pageCounts: [Int]? = nil) throws -> (inputs: [URL], output: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Lemulip-PDF-Order-" + UUID().uuidString)
        let output = root.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        var inputs: [URL] = []
        for (index, name) in names.enumerated() {
            let directory = root.appendingPathComponent("input-\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(name)
            var box = CGRect(x: 0, y: 0, width: 300, height: 200)
            let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
            let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
            for page in 1...(pageCounts?[index] ?? 1) {
                context.beginPDFPage(nil)
                let string = NSAttributedString(string: "File \(index) Page \(page)", attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font
                ])
                context.textPosition = CGPoint(x: 20, y: 100)
                CTLineDraw(CTLineCreateWithAttributedString(string), context)
                context.endPDFPage()
            }
            context.closePDF()
            inputs.append(url)
        }
        return (inputs, output)
    }
}
#endif
