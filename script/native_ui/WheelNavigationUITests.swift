
// These screenshots and AX values come from the normally launched Mac app.
// They verify wheel navigation/geometry, not acoustic output or VoiceOver speech.
extension QualityUITests {
    func testEnglishWheelPointerKeyboardAndVisualReview() throws {
        try wheelNavigationReview(language: "en", openLabel: "Open Wheel", wheelLabel: "Lemulip file operations")
    }

    func testTurkishWheelPointerKeyboardAndVisualReview() throws {
        try wheelNavigationReview(language: "tr", openLabel: "Çarkı Aç", wheelLabel: "Lemulip dosya işlemleri")
    }

    private func wheelNavigationReview(language: String, openLabel: String, wheelLabel: String) throws {
        let app = launch(language: language)
        let input = ReviewConfiguration.fixtures.appendingPathComponent("Quality.png")
        let original = try Data(contentsOf: input)
        let before = try contents(input.deletingLastPathComponent())
        app.open(input)
        let open = app.buttons[openLabel]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.click()
        let wheel = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", wheelLabel)).firstMatch
        XCTAssertTrue(wheel.waitForExistence(timeout: 10))
        XCTAssertTrue(wheel.isEnabled)
        XCTAssertTrue(wheel.isHittable)
        let initial = try XCTUnwrap(wheel.value as? String)
        XCTAssertFalse(initial.isEmpty)
        app.typeKey(.rightArrow, modifierFlags: [])
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let value = wheel.value as? String else { return false }
            return !value.isEmpty && value != initial
        }, object: wheel)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        // Item zero is at the top of the 420-point production wheel.
        // Hover, rather than click, so no conversion can be launched.
        wheel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.217)).hover()
        try expectValue(initial, of: wheel)
        let frame = wheel.frame
        XCTAssertEqual(frame.width, 420, accuracy: 2)
        XCTAssertEqual(frame.height, 420, accuracy: 2)
        let shot = XCTAttachment(screenshot: wheel.screenshot())
        shot.name = "Native wheel - " + language
        shot.lifetime = .keepAlways
        add(shot)
        app.typeKey(.escape, modifierFlags: [])
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: wheel)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        XCTAssertEqual(try Data(contentsOf: input), original)
        XCTAssertEqual(try contents(input.deletingLastPathComponent()), before,
                       "Navigating and cancelling the wheel must not create an output")
    }
}
