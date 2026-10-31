
// Real controls and persisted settings only. Invoking Preview is not proof of
// audible output, mute behavior, headphone quality or VoiceOver narration.
extension QualityUITests {
    func testEnglishSelectionSoundPreferenceSurvivesRelaunch() throws {
        try selectionSoundLifecycle(language: "en", label: "Selection Sounds",
                                    previewLabel: "Preview Selection Sound")
    }

    func testTurkishSelectionSoundPreferenceSurvivesRelaunch() throws {
        try selectionSoundLifecycle(language: "tr", label: "Seçim Sesleri",
                                    previewLabel: "Seçim Sesini Dinle")
    }

    private func selectionSoundLifecycle(language: String, label: String, previewLabel: String) throws {
        let app = launch(language: language)
        // The isolated review app has its own preference domain. Do not write
        // preferences or add launch overrides that could manufacture persistence.
        var toggle = try openSoundSettings(in: app, label: label, previewLabel: previewLabel)
        try expectSoundEnabled(false, in: toggle)
        let preview = app.buttons["settings.selection-sounds.preview"]
        preview.click()
        try expectSoundEnabled(false, in: toggle)

        toggle.click()
        try expectSoundEnabled(true, in: toggle)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        toggle = try openSoundSettings(in: app, label: label, previewLabel: previewLabel)
        try expectSoundEnabled(true, in: toggle)
        app.buttons["settings.selection-sounds.preview"].click()
        try expectSoundEnabled(true, in: toggle)

        toggle.click()
        try expectSoundEnabled(false, in: toggle)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        toggle = try openSoundSettings(in: app, label: label, previewLabel: previewLabel)
        try expectSoundEnabled(false, in: toggle)
        // Leave the review copy off for subsequent cases and physical audition.
    }

    private func openSoundSettings(in app: XCUIApplication, label: String,
                                   previewLabel: String) throws -> XCUIElement {
        let settings = app.buttons["navigation.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.click()
        let toggle = app.descendants(matching: .any)["settings.selection-sounds"].firstMatch
        let preview = app.buttons["settings.selection-sounds.preview"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        XCTAssertTrue([XCUIElement.ElementType.checkBox, .switch, .toggle].contains(toggle.elementType),
                      "Require an actual toggle, not the surrounding label")
        XCTAssertEqual(toggle.label, label)
        XCTAssertEqual(preview.label, previewLabel)
        XCTAssertTrue(toggle.isEnabled)
        XCTAssertTrue(preview.isEnabled)
        // Settings may extend below the current window on a small CI display.
        // Scroll the real content instead of invoking a hidden control directly.
        for _ in 0..<6 {
            if toggle.isHittable && preview.isHittable { break }
            app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -160)
        }
        XCTAssertTrue(toggle.isHittable)
        XCTAssertTrue(preview.isHittable)
        return toggle
    }

    private func expectSoundEnabled(_ enabled: Bool, in toggle: XCUIElement) throws {
        let expected = enabled ? 1 : 0
        let predicate = NSPredicate { _, _ in
            if let number = toggle.value as? NSNumber { return number.intValue == expected }
            if let text = toggle.value as? String { return text == String(expected) }
            return false
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed,
                       "The real sound preference must be \(enabled ? "on" : "off")")
    }
}
