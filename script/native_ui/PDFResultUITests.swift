
// Exercise recovery and the user's final handoff through the production app.
// Finder selection is checked with its public Copy as Pathname command, never
// by asking a test helper to reveal or select the expected output.
extension QualityUITests {
    func testEnglishInvalidPDFExplainsRecoveryAndCanCancel() throws {
        try invalidPDFRecovery(language: "en")
    }

    func testTurkishInvalidPDFExplainsRecoveryAndCanCancel() throws {
        try invalidPDFRecovery(language: "tr")
    }

    func testTurkishOrganizerResultRevealsTheProducedCopyInFinder() throws {
        let app = launch(language: "tr", completion: "card")
        let input = try preparedPDFFixture("FinderHandoff")
        let original = try Data(contentsOf: input)
        let folder = input.deletingLastPathComponent()
        let before = try contents(folder)
        app.open(input)
        try openOperation("pdf.organize", in: app, searchText: "PDF düzenle")
        let first = app.textFields["pdf.position.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        replacePosition(first, with: "2")
        try expectOrder([1, 0, 2, 3], in: app)
        capturePDFState(app, name: "Turkish organizer before creating the copy")
        app.buttons["editor.create-copy"].click()

        let output = try waitForOutput(in: folder, excluding: before)
        XCTAssertEqual(try pageLabels(output), ["PAGE 2", "PAGE 1", "PAGE 3", "PAGE 4"])
        XCTAssertEqual(try Data(contentsOf: input), original)
        XCTAssertEqual(try contents(folder).subtracting(before), [output])
        // XCTest's string subscript rejects identifiers longer than 128
        // characters. Match the complete path explicitly without truncating it.
        let result = app.buttons.matching(NSPredicate(format: "identifier == %@",
                                                      "completion.output." + output.path)).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        XCTAssertTrue(result.isHittable)
        XCTAssertEqual(result.label, output.lastPathComponent + " dosyasını Finder'da göster")
        capturePDFState(app, name: "Turkish result card before the Finder action")

        NSPasteboard.general.clearContents()
        result.click() // Only the production action may choose the Finder file.
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        let foreground = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            finder.state == .runningForeground
        }, object: finder)
        XCTAssertEqual(XCTWaiter.wait(for: [foreground], timeout: 10), .completed,
                       "The production result action must bring Finder forward")
        let expectedPath = output.resolvingSymlinksInPath().standardizedFileURL.path
        let selectionDeadline = Date().addingTimeInterval(10)
        var selectedCorrectOutput = false
        var copyAttempts = 0
        // Finder can become foreground before its selection finishes updating.
        // Re-copy that real selection within the same deadline; polling a stale
        // clipboard alone would never observe the later Finder selection.
        while !selectedCorrectOutput, Date() < selectionDeadline {
            guard finder.state == .runningForeground else { break }
            finder.typeKey("c", modifierFlags: [.command, .option])
            copyAttempts += 1
            let copiedSelection = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                guard let path = NSPasteboard.general.string(forType: .string),
                      !path.isEmpty, !path.contains("\n") else { return false }
                return URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path == expectedPath
            }, object: finder)
            let remaining = max(0, selectionDeadline.timeIntervalSinceNow)
            selectedCorrectOutput = XCTWaiter.wait(for: [copiedSelection], timeout: min(1, remaining)) == .completed
        }
        capturePDFState(finder, name: "Finder with the actual produced PDF selected")
        let copiedPath = NSPasteboard.general.string(forType: .string) ?? "<no pathname copied>"
        let receipt = XCTAttachment(string: "Expected output: \(output.path)\nFinder selection: \(copiedPath)\nCopy attempts: \(copyAttempts)")
        receipt.name = "Finder selected output pathname"
        receipt.lifetime = .keepAlways
        add(receipt)
        XCTAssertTrue(selectedCorrectOutput,
                       "Finder's actual selected pathname must be the newly produced copy")
        XCTAssertEqual(try Data(contentsOf: input), original)
    }

    func testOrganizerDestinationCancelPreservesTheEditedOrder() throws {
        let app = launch(language: "en")
        try setSaveBesideOriginal(false, in: app)
        let input = try preparedPDFFixture("DestinationCancel")
        let original = try Data(contentsOf: input)
        let folder = input.deletingLastPathComponent()
        let before = try contents(folder)
        app.open(input)
        try openOperation("pdf.organize", in: app, searchText: "Organize")
        let first = app.textFields["pdf.position.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        replacePosition(first, with: "2")
        try expectOrder([1, 0, 2, 3], in: app)
        app.buttons["editor.create-copy"].click()

        let chooseDestination = app.buttons["Save Here"]
        XCTAssertTrue(chooseDestination.waitForExistence(timeout: 10),
                      "The real destination picker must open")
        capturePDFState(app, name: "PDF destination picker before cancellation")
        // Escape is the native open-panel Cancel action. It must close only the
        // destination picker and return to the same pending editor and history.
        app.typeKey(.escape, modifierFlags: [])
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                 object: chooseDestination)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        XCTAssertTrue(app.buttons["editor.create-copy"].isHittable)
        try expectOrder([1, 0, 2, 3], in: app)
        XCTAssertTrue(app.buttons["Undo"].isEnabled)
        capturePDFState(app, name: "PDF editor retains its order after destination cancellation")
        app.buttons["Undo"].click()
        try expectOrder([0, 1, 2, 3], in: app)
        app.typeKey("z", modifierFlags: [.command, .shift])
        try expectOrder([1, 0, 2, 3], in: app)
        XCTAssertEqual(try contents(folder), before, "Canceling the destination must not submit a conversion")
        XCTAssertEqual(try Data(contentsOf: input), original)
        app.buttons["Cancel"].click()
        try expectEditorClosed(in: app)
        XCTAssertEqual(try contents(folder), before)
        try setSaveBesideOriginal(true, in: app)
    }

    private func invalidPDFRecovery(language: String) throws {
        let app = launch(language: language)
        let input = try preparedPDFFixture(language == "tr" ? "TurkishInvalid" : "EnglishInvalid")
        let original = try Data(contentsOf: input)
        let folder = input.deletingLastPathComponent()
        let before = try contents(folder)
        app.open(input)
        try openOperation("pdf.organize", in: app)
        let title = app.staticTexts["pdf.organize.error-title"]
        let detail = app.staticTexts["pdf.organize.error-detail"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertTrue(detail.isHittable)
        // Native SwiftUI Text exposes its content as AXValue, not AXLabel.
        XCTAssertEqual(try XCTUnwrap(title.value as? String),
                       language == "tr" ? "PDF düzenleyicisi açılamadı" : "Could Not Open the PDF Organizer")
        XCTAssertEqual(try XCTUnwrap(detail.value as? String), language == "tr"
            ? "Bu dosya PDF olarak okunamadı. Başka bir PDF seçip yeniden dene."
            : "This file could not be read as a PDF. Choose another PDF and try again.")
        XCTAssertFalse(app.buttons["editor.create-copy"].isEnabled)
        capturePDFState(app, name: "Invalid PDF recovery - " + language)
        let cancel = app.buttons[language == "tr" ? "Vazgeç" : "Cancel"]
        XCTAssertTrue(cancel.isHittable)
        cancel.click()
        try expectEditorClosed(in: app)
        XCTAssertEqual(try contents(folder), before)
        XCTAssertEqual(try Data(contentsOf: input), original)
    }

    private func setSaveBesideOriginal(_ enabled: Bool, in app: XCUIApplication) throws {
        // Change the real preference: a string launch argument is not a Boolean
        // UserDefaults object and cannot establish the destination-picker path.
        let settings = app.buttons["navigation.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.click()
        let toggle = app.checkBoxes["Save Beside The Original"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        for _ in 0..<8 {
            if toggle.isHittable { break }
            app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -160)
        }
        XCTAssertTrue(toggle.isHittable)
        XCTAssertTrue(toggle.isEnabled)
        let expected = enabled ? 1 : 0
        let current = try XCTUnwrap((toggle.value as? NSNumber)?.intValue ?? Int(toggle.value as? String ?? ""))
        XCTAssertTrue([0, 1].contains(current))
        if current != expected { toggle.click() }
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let value = (toggle.value as? NSNumber)?.intValue ?? Int(toggle.value as? String ?? "")
            return value == expected
        }, object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed,
                       "The actual output preference must be \(enabled ? "on" : "off")")
        if !enabled { capturePDFState(app, name: "Output folder selection enabled in Settings") }
        app.buttons["navigation.workspace"].click()
    }

    private func preparedPDFFixture(_ scenario: String) throws -> URL {
        // The staging process prepares one uniquely named input per case.
        // The sandboxed XCTest runner only reads it; it never prepares files or
        // widens filesystem access. A reused directory with output must fail.
        let folder = ReviewConfiguration.fixtures.appendingPathComponent("PDFResults/" + scenario,
                                                                         isDirectory: true)
        let inputs = try contents(folder)
        XCTAssertEqual(inputs.count, 1, "Require a fresh, input-only scenario directory")
        let input = try XCTUnwrap(inputs.first)
        XCTAssertEqual(input.pathExtension, "pdf")
        XCTAssertTrue(input.lastPathComponent.hasPrefix(scenario + "-"))
        return input
    }

    private func capturePDFState(_ app: XCUIApplication, name: String) {
        let graph = XCTAttachment(string: app.debugDescription)
        graph.name = name + " accessibility tree"
        graph.lifetime = .keepAlways
        add(graph)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
