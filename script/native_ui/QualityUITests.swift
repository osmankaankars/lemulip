import XCTest
import PDFKit

/// External UI tests: the unchanged production app runs its normal event loop.
/// This is not a VoiceOver audition or proof of Retina display quality.
@MainActor
final class QualityUITests: XCTestCase {
    private var application: XCUIApplication?

    override func setUpWithError() throws { continueAfterFailure = false }

    override func tearDownWithError() throws {
        if let application {
            let graph = XCTAttachment(string: application.debugDescription)
            graph.name = name + " accessibility tree"
            graph.lifetime = .keepAlways
            add(graph)
            if application.state != .notRunning {
                let screenshot = XCTAttachment(screenshot: application.screenshot())
                screenshot.name = name + " running application"
                screenshot.lifetime = .keepAlways
                add(screenshot)
                application.terminate()
            }
        }
        application = nil
    }

    func testEnglishQualityControl() throws {
        try option(language: "en", operation: "image.compress", label: "Quality", value: "82 percent", slider: true)
    }

    func testTurkishQualityControl() throws {
        try option(language: "tr", operation: "image.compress", label: "Kalite", value: "Yüzde 82", slider: true)
    }

    func testEnglishDimensionControl() throws {
        try option(language: "en", operation: "image.resize", label: "Maximum Dimension (px)", value: "1920", slider: false)
    }

    func testTurkishDimensionControl() throws {
        try option(language: "tr", operation: "image.resize", label: "En büyük kenar (piksel)", value: "1920", slider: false)
    }

    func testMergeDragPublishesTheDisplayedOrderAndPreservesOriginals() throws {
        let app = launch(language: "en")
        let names = ["01-Cover.pdf", "02-Report.pdf", "03-Notes.pdf"]
        let inputs = names.map { ReviewConfiguration.fixtures.appendingPathComponent("Merge/" + $0) }
        let originals = try inputs.map { try Data(contentsOf: $0) }
        let folder = try XCTUnwrap(inputs.first?.deletingLastPathComponent())
        let before = try contents(folder)
        for input in inputs { app.open(input) }
        try openOperation("pdf.merge", in: app)
        let first = app.descendants(matching: .any)["pdf.merge.row.0"].firstMatch
        let last = app.descendants(matching: .any)["pdf.merge.row.2"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertTrue(last.waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["pdf.position.0"].value as? String, "1")
        // The visible handle is intentionally hidden from AX. Coordinates are
        // relative to the actual identified row, never guessed screen pixels.
        let grab = first.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5))
        let drop = last.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.85))
        grab.click(forDuration: 0.7, thenDragTo: drop)
        try expectValue("3", of: app.textFields["pdf.position.0"])
        try expectValue("1", of: app.textFields["pdf.position.1"])
        try expectValue("2", of: app.textFields["pdf.position.2"])
        let create = app.buttons["editor.create-copy"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.click()
        let output = try waitForOutput(in: folder, excluding: before)
        XCTAssertEqual(try pageLabels(output), ["02.1 - Report", "02.2 - Report", "03 - Notes", "01 - Cover"])
        for (input, bytes) in zip(inputs, originals) { XCTAssertEqual(try Data(contentsOf: input), bytes) }
    }

    func testOrganizerDragPublishesTheDisplayedOrderAndPreservesOriginal() throws {
        let app = launch(language: "en")
        let input = ReviewConfiguration.fixtures.appendingPathComponent("Organize/Page-Order.pdf")
        let original = try Data(contentsOf: input)
        let folder = input.deletingLastPathComponent()
        let before = try contents(folder)
        app.open(input)
        try openOperation("pdf.organize", in: app)
        let first = app.descendants(matching: .any)["pdf.organize.card.0"].firstMatch
        let second = app.descendants(matching: .any)["pdf.organize.card.1"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertTrue(second.waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["pdf.position.0"].value as? String, "1")
        // Drag the thumbnail button and insert into the right half of page 2.
        first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            .click(forDuration: 0.7, thenDragTo: second.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.35)))
        try expectValue("2", of: app.textFields["pdf.position.0"])
        try expectValue("1", of: app.textFields["pdf.position.1"])
        let create = app.buttons["editor.create-copy"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.click()
        let output = try waitForOutput(in: folder, excluding: before)
        XCTAssertEqual(try pageLabels(output), ["PAGE 2", "PAGE 1", "PAGE 3", "PAGE 4"])
        XCTAssertEqual(try Data(contentsOf: input), original)
    }

    private func launch(language: String) -> XCUIApplication {
        let app = XCUIApplication(url: ReviewConfiguration.application)
        application = app
        app.launchArguments = ["-language", language, "-wheelEnabled", "NO", "-completionPresentation", "quiet",
                               "-outputAlongsideOriginal", "YES", "-NSQuitAlwaysKeepsWindows", "NO"]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        return app
    }

    private func option(language: String, operation: String, label: String, value: String, slider: Bool) throws {
        let app = launch(language: language)
        app.open(ReviewConfiguration.fixtures.appendingPathComponent("Quality.png"))
        try openOperation(operation, in: app)
        let query = slider ? app.sliders : app.textFields
        let control = query.matching(NSPredicate(format: "label == %@", label)).firstMatch
        XCTAssertTrue(control.waitForExistence(timeout: 10), "The production control must expose its localized name")
        XCTAssertEqual(control.value as? String, value, "The production control must expose its localized units")
        XCTAssertTrue(control.isEnabled)
        XCTAssertTrue(control.isHittable)
    }

    private func openOperation(_ id: String, in app: XCUIApplication) throws {
        let search = app.textFields["workspace.operation-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.click()
        search.typeText(id)
        let operation = app.buttons["operation." + id]
        XCTAssertTrue(operation.waitForExistence(timeout: 10))
        operation.click()
    }

    private func expectValue(_ value: String, of field: XCUIElement) throws {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed,
                       "An actual pointer drop must update the production position field")
    }

    private func contents(_ directory: URL) throws -> Set<URL> {
        Set(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))
    }

    private func waitForOutput(in folder: URL, excluding before: Set<URL>) throws -> URL {
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            let created = try contents(folder).subtracting(before).filter { $0.pathExtension.lowercased() == "pdf" }
            if created.count == 1, let output = created.first, let document = PDFDocument(url: output), document.pageCount > 0 { return output }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTFail("The UI submission did not publish one complete PDF")
        throw ReviewFailure.missingOutput
    }

    private func pageLabels(_ url: URL) throws -> [String] {
        let document = try XCTUnwrap(PDFDocument(url: url))
        return try (0..<document.pageCount).map {
            try XCTUnwrap(document.page(at: $0)?.string).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private enum ReviewFailure: Error { case missingOutput }
}
