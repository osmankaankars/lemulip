
// Complete the legacy options matrix through the normally launched app.
// Media controls require a real FFmpeg installation and a decoded WAV fixture.
extension QualityUITests {
    func testEnglishSpeedControl() throws {
        try remainingOption(language: "en", operation: "media.speed", label: "Playback Speed",
                            value: "2.00 times", numericValue: 2.0)
    }

    func testTurkishSpeedControl() throws {
        try remainingOption(language: "tr", operation: "media.speed", label: "Oynatma hızı",
                            value: "2,00 kat", numericValue: 2.0)
    }

    func testEnglishVolumeControl() throws {
        try remainingOption(language: "en", operation: "media.volume", label: "Volume",
                            value: "150 percent", numericValue: 1.5)
    }

    func testTurkishVolumeControl() throws {
        try remainingOption(language: "tr", operation: "media.volume", label: "Ses düzeyi",
                            value: "Yüzde 150", numericValue: 1.5)
    }

    func testEnglishPageRangeControl() throws {
        try remainingOption(language: "en", operation: "pdf.extract", label: "Page Numbers and Ranges",
                            value: "1", numericValue: nil)
    }

    func testTurkishPageRangeControl() throws {
        try remainingOption(language: "tr", operation: "pdf.extract", label: "Sayfalar ve aralıklar",
                            value: "1", numericValue: nil)
    }

    func testMergeFirstCancelClickDiscardsActivePositionDraft() throws {
        try firstCancelClick(organize: false)
    }

    func testOrganizerFirstCancelClickDiscardsActivePositionDraft() throws {
        try firstCancelClick(organize: true)
    }

    private func remainingOption(language: String, operation: String, label: String,
                                 value: String, numericValue: Double?) throws {
        let app = launch(language: language)
        let input = ReviewConfiguration.fixtures.appendingPathComponent(
            numericValue == nil ? "Organize/Page-Order.pdf" : "Quality.wav")
        let original = try Data(contentsOf: input)
        let directory = input.deletingLastPathComponent()
        let before = try contents(directory)
        app.open(input)
        try openOperation(operation, in: app)
        let query = numericValue == nil ? app.textFields : app.sliders
        let control = query.matching(NSPredicate(format: "label == %@", label)).firstMatch
        XCTAssertTrue(control.waitForExistence(timeout: 10), "Require the actual localized production control")
        if let numericValue {
            XCTAssertEqual(try XCTUnwrap(control.value as? NSNumber).doubleValue, numericValue, accuracy: 0.0001)
            XCTAssertEqual(try sliderValueDescription(label: label), value,
                           "Read the exact spoken units from the authorized real-app snapshot")
        } else {
            XCTAssertEqual(control.value as? String, value)
        }
        XCTAssertTrue(control.isEnabled)
        XCTAssertTrue(control.isHittable)
        app.buttons[language == "tr" ? "Vazgeç" : "Cancel"].click()
        try expectEditorClosed(in: app)
        XCTAssertEqual(try contents(directory), before, "Inspecting options must not publish output")
        XCTAssertEqual(try Data(contentsOf: input), original)
    }

    private func firstCancelClick(organize: Bool) throws {
        let app = launch(language: "en")
        let inputs = workflowInputs(organize: organize, long: false)
        let originals = try inputs.map { try Data(contentsOf: $0) }
        let directory = try XCTUnwrap(inputs.first).deletingLastPathComponent()
        let before = try contents(directory)
        for input in inputs { app.open(input) }
        let operation = organize ? "pdf.organize" : "pdf.merge"
        try openOperation(operation, in: app)
        let field = app.textFields["pdf.position.0"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText("3")
        // Deliberately do NOT press Return/Escape or blur the draft first.
        XCTAssertEqual(field.value as? String, "3")
        XCTAssertFalse(app.buttons["editor.create-copy"].isEnabled)
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.isEnabled)
        XCTAssertTrue(cancel.isHittable)
        cancel.click() // Exactly one pointer click must discard the active draft.
        try expectEditorClosed(in: app)
        XCTAssertEqual(try contents(directory), before)
        XCTAssertEqual(try inputs.map { try Data(contentsOf: $0) }, originals)
        let reopen = app.buttons["operation." + operation]
        XCTAssertTrue(reopen.waitForExistence(timeout: 5))
        reopen.click()
        try expectOrder(Array(0..<(organize ? 4 : 3)), in: app)
        XCTAssertFalse(app.buttons["Undo"].isEnabled)
        app.buttons["Cancel"].click()
        try expectEditorClosed(in: app)
        XCTAssertEqual(try contents(directory), before)
        XCTAssertEqual(try inputs.map { try Data(contentsOf: $0) }, originals)
    }
}
