
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
        let input = try isolatedPDFFixture(valid: true)
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
        let result = app.buttons["completion.output." + output.path]
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
        let app = launch(language: "en", outputAlongsideOriginal: false)
        let input = try isolatedPDFFixture(valid: true)
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
    }

    private func invalidPDFRecovery(language: String) throws {
        let app = launch(language: language)
        let input = try isolatedPDFFixture(valid: false)
        let original = try Data(contentsOf: input)
        let folder = input.deletingLastPathComponent()
        let before = try contents(folder)
        app.open(input)
        try openOperation("pdf.organize", in: app)
        let title = app.staticTexts["pdf.organize.error-title"]
        let detail = app.staticTexts["pdf.organize.error-detail"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertTrue(detail.isHittable)
        XCTAssertEqual(title.label, language == "tr" ? "PDF düzenleyicisi açılamadı" : "Could Not Open the PDF Organizer")
        XCTAssertEqual(detail.label, language == "tr"
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

    private func isolatedPDFFixture(valid: Bool) throws -> URL {
        // Each case owns a new synthetic fixture directory. A unique filename
        // also prevents an unrelated Finder window from satisfying the handoff.
        let identity = UUID().uuidString
        let folder = ReviewConfiguration.fixtures.appendingPathComponent("PDF-Result-" + identity,
                                                                         isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let input = folder.appendingPathComponent((valid ? "Pages-" : "Invalid-") + identity + ".pdf")
        if valid {
            try FileManager.default.copyItem(at: ReviewConfiguration.fixtures.appendingPathComponent("Organize/Page-Order.pdf"),
                                             to: input)
        } else {
            try Data("This is a deliberately invalid PDF fixture.\n".utf8).write(to: input)
        }
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
