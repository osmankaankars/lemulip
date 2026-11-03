
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

    func testWAVTrimDefaultsToSourceFormatAndKeepsManualChoice() throws {
        let app = launch(language: "en")
        let input = ReviewConfiguration.fixtures.appendingPathComponent("Quality.wav")
        let original = try Data(contentsOf: input)
        let directory = input.deletingLastPathComponent()
        let before = try contents(directory)
        app.open(input)
        try openOperation("media.trim", in: app)
        let format = app.popUpButtons["audio-trim.output-format"]
        XCTAssertTrue(format.waitForExistence(timeout: 15))
        XCTAssertEqual(format.value as? String, "WAV · 16-Bit PCM",
                       "A supported WAV source must not begin with a lossy AAC output selected")
        XCTAssertTrue(format.isEnabled)
        XCTAssertTrue(format.isHittable)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Audio trim with source WAV selected"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        format.click()
        let aiff = app.menuItems["AIFF · 16-Bit PCM"]
        XCTAssertTrue(aiff.waitForExistence(timeout: 5))
        aiff.click()
        XCTAssertEqual(format.value as? String, "AIFF · 16-Bit PCM",
                       "Source-aware defaults must keep the output format editable")
        app.buttons["Cancel"].click()
        try expectEditorClosed(in: app)
        XCTAssertEqual(try contents(directory), before)
        XCTAssertEqual(try Data(contentsOf: input), original)
    }

    func testMergeFirstCancelClickDiscardsActivePositionDraft() throws {
        try firstCancelClick(organize: false)
    }

    func testTurkishMergeFirstCancelClickDiscardsActivePositionDraft() throws {
        try firstCancelClick(organize: false, language: "tr")
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

    private func firstCancelClick(organize: Bool, language: String = "en") throws {
        let app = launch(language: language)
        let isTurkish = language == "tr"
        let editorName = (organize ? "PDF organizer" : "PDF merge") + " (\(language))"
        let inputs = workflowInputs(organize: organize, long: false)
        let originals = try inputs.map { try Data(contentsOf: $0) }
        let directory = try XCTUnwrap(inputs.first).deletingLastPathComponent()
        let before = try contents(directory)
        for input in inputs { app.open(input) }
        let operation = organize ? "pdf.organize" : "pdf.merge"
        try openOperation(operation, in: app)
        let field = app.textFields["pdf.position.0"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        let idleHint: String
        let explanation: String
        if organize {
            idleHint = isTurkish ? "Sayfaları sürükle veya sıra numaralarını değiştir." : "Drag pages or edit their position."
            explanation = isTurkish
                ? "Bir sayfayı seçime eklemek veya seçimden çıkarmak için ⌘ ile tıkla. Aralık seçmek için Shift ile tıkla. Seçili sayfaları birlikte taşımak için tutamaktan sürükle."
                : "⌘-click a page to add or remove it from the selection. Shift-click to select a range. Drag the handle to move selected pages together."
        } else {
            idleHint = isTurkish ? "Dosyaları sürükle veya sıra numaralarını değiştir." : "Drag files or edit their position."
            explanation = isTurkish
                ? "Bir dosyayı seçime eklemek veya seçimden çıkarmak için ⌘ ile tıkla. Aralık seçmek için Shift ile tıkla. Seçili dosyaları birlikte taşımak için tutamaktan sürükle."
                : "⌘-click a file to add or remove it from the selection. Shift-click to select a range. Drag the handle to move selected files together."
        }
        let hint = app.staticTexts.matching(NSPredicate(format: "value == %@", idleHint)).firstMatch
        XCTAssertTrue(hint.waitForExistence(timeout: 5))
        XCTAssertTrue(hint.isHittable)
        let help = app.disclosureTriangles[isTurkish ? "Klavye Ve İpuçları" : "Keyboard & Tips"]
        XCTAssertTrue(help.waitForExistence(timeout: 5))
        let details = app.staticTexts["editor.help.details"]
        XCTAssertFalse(details.exists && details.isHittable)
        let collapsed = XCTAttachment(screenshot: app.screenshot())
        collapsed.name = editorName + " with concise ordering guidance"
        collapsed.lifetime = .keepAlways
        add(collapsed)
        let beforeHelp = XCTAttachment(string: app.debugDescription)
        beforeHelp.name = editorName + " help before disclosure click"
        beforeHelp.lifetime = .keepAlways
        add(beforeHelp)
        // The native disclosure's AX frame starts left of its visible chevron.
        // Both editors' help and identified first item share the 24-point inset;
        // use that item's x and the disclosure's y to hit the actual arrow.
        let firstItem = workflowItem(0, in: app, organize: organize)
        XCTAssertTrue(firstItem.waitForExistence(timeout: 5))
        firstItem.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 5, dy: help.frame.midY - firstItem.frame.minY)).click()
        let visibleHelp = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            details.exists && details.isHittable
        }, object: details)
        let helpResult = XCTWaiter.wait(for: [visibleHelp], timeout: 5)
        let afterHelp = XCTAttachment(string: app.debugDescription)
        afterHelp.name = editorName + " help after disclosure click"
        afterHelp.lifetime = .keepAlways
        add(afterHelp)
        XCTAssertEqual(helpResult, .completed,
                       "Require the explanation to be visibly expanded before checking layout or capturing it")
        XCTAssertEqual(details.value as? String, explanation, "The expanded production help must use the selected language")
        XCTAssertTrue(field.isEnabled)
        XCTAssertTrue(field.isHittable, "Expanded help must leave position editing reachable")
        if !organize {
            for index in inputs.indices {
                XCTAssertTrue(app.textFields["pdf.position.\(index)"].isHittable,
                              "Expanded merge help must leave every fixture file's position reachable")
            }
        }
        let createCopy = app.buttons["editor.create-copy"]
        XCTAssertEqual(createCopy.label, isTurkish ? "Kopya Oluştur" : "Create Copy")
        XCTAssertTrue(createCopy.isEnabled)
        XCTAssertTrue(createCopy.isHittable)
        let cancel = app.buttons[isTurkish ? "Vazgeç" : "Cancel"]
        XCTAssertTrue(cancel.isEnabled)
        XCTAssertTrue(cancel.isHittable)
        let expanded = XCTAttachment(screenshot: app.screenshot())
        expanded.name = editorName + " with keyboard help expanded"
        expanded.lifetime = .keepAlways
        add(expanded)
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText("3")
        // Deliberately do NOT press Return/Escape or blur the draft first.
        XCTAssertEqual(field.value as? String, "3")
        let range = "1–\(organize ? 4 : 3)"
        let activeHint = isTurkish
            ? "Sıra \(range) · Enter ile taşı · Esc ile vazgeç · Seçili \(organize ? "sayfalar" : "dosyalar") birlikte taşınır"
            : "Position \(range) · Enter to Move · Esc to Cancel · Selected \(organize ? "Pages" : "Files") Move Together"
        let activeGuidance = app.staticTexts.matching(NSPredicate(format: "value == %@", activeHint)).firstMatch
        XCTAssertTrue(activeGuidance.waitForExistence(timeout: 5))
        XCTAssertTrue(activeGuidance.isHittable)
        XCTAssertFalse(createCopy.isEnabled)
        XCTAssertTrue(cancel.isEnabled)
        XCTAssertTrue(cancel.isHittable)
        let draft = XCTAttachment(screenshot: app.screenshot())
        draft.name = editorName + " with active position draft"
        draft.lifetime = .keepAlways
        add(draft)
        cancel.click() // Exactly one pointer click must discard the active draft.
        try expectEditorClosed(in: app)
        XCTAssertEqual(try contents(directory), before)
        XCTAssertEqual(try inputs.map { try Data(contentsOf: $0) }, originals)
        let reopen = app.buttons["operation." + operation]
        XCTAssertTrue(reopen.waitForExistence(timeout: 5))
        reopen.click()
        try expectOrder(Array(0..<(organize ? 4 : 3)), in: app)
        XCTAssertFalse(app.buttons[isTurkish ? "Geri al" : "Undo"].isEnabled)
        app.buttons[isTurkish ? "Vazgeç" : "Cancel"].click()
        try expectEditorClosed(in: app)
        XCTAssertEqual(try contents(directory), before)
        XCTAssertEqual(try inputs.map { try Data(contentsOf: $0) }, originals)
    }
}
