
// Roadmap P2: exercise complete editing flows through the real application.
// These cases deliberately retain the earlier single-item drag regressions.
extension QualityUITests {
    func testMergeDisjointSelectionDragUndoRedoAndExport() throws {
        try selectedGroupWorkflow(organize: false)
    }

    func testOrganizerDisjointSelectionDragUndoRedoAndExport() throws {
        try selectedGroupWorkflow(organize: true)
    }

    func testMergeInvalidPositionEscapeAndCancelPreserveFiles() throws {
        try cancelledGroupWorkflow(organize: false)
    }

    func testOrganizerInvalidPositionEscapeAndCancelPreserveFile() throws {
        try cancelledGroupWorkflow(organize: true)
    }

    func testMergeScrolledListDragUndoAndMoveToFirst() throws {
        try scrolledWorkflow(organize: false)
    }

    func testOrganizerScrolledGridDragUndoAndMoveToFirst() throws {
        try scrolledWorkflow(organize: true)
    }

    private func selectedGroupWorkflow(organize: Bool) throws {
        let app = launch(language: "en")
        let inputs = workflowInputs(organize: organize, long: false)
        let originals = try inputs.map { try Data(contentsOf: $0) }
        let folder = try XCTUnwrap(inputs.first).deletingLastPathComponent()
        let before = try contents(folder)
        for input in inputs { app.open(input) }
        try openOperation(organize ? "pdf.organize" : "pdf.merge", in: app)
        try selectDisjointGroup(in: app, organize: organize)
        let target = organize ? 3 : 2
        dragSource(0, to: target, after: true, in: app, organize: organize)
        let moved = organize ? [1, 3, 0, 2] : [1, 0, 2]
        try expectOrder(moved, in: app)
        XCTAssertTrue(app.staticTexts["2 Selected"].exists, "Dragging must retain both selected items")
        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.isEnabled)
        undo.click()
        try expectOrder(Array(0..<moved.count), in: app)
        XCTAssertFalse(undo.isEnabled, "One group drag must be exactly one undo step")
        XCTAssertTrue(app.staticTexts["2 Selected"].exists)
        app.typeKey("z", modifierFlags: [.command, .shift])
        try expectOrder(moved, in: app)
        XCTAssertTrue(app.staticTexts["2 Selected"].exists)
        app.buttons["editor.create-copy"].click()
        let output = try waitForOutput(in: folder, excluding: before)
        let prefix = organize ? "PAGE " : "FILE "
        XCTAssertEqual(try pageLabels(output), moved.map { prefix + String($0 + 1) })
        XCTAssertEqual(try inputs.map { try Data(contentsOf: $0) }, originals)
        XCTAssertEqual(try contents(folder).subtracting(before), [output], "No extra or partial output is allowed")
    }

    private func cancelledGroupWorkflow(organize: Bool) throws {
        let app = launch(language: "en")
        let inputs = workflowInputs(organize: organize, long: false)
        let originals = try inputs.map { try Data(contentsOf: $0) }
        let folder = try XCTUnwrap(inputs.first).deletingLastPathComponent()
        let before = try contents(folder)
        for input in inputs { app.open(input) }
        let operation = organize ? "pdf.organize" : "pdf.merge"
        try openOperation(operation, in: app)
        try selectDisjointGroup(in: app, organize: organize)
        let field = app.textFields["pdf.position.0"]
        replacePosition(field, with: "0")
        XCTAssertEqual(field.value as? String, "0", "Keep invalid input available for correction")
        XCTAssertFalse(app.buttons["editor.create-copy"].isEnabled)
        XCTAssertFalse(app.buttons["Undo"].isEnabled, "Invalid input cannot add history")
        app.typeKey(.escape, modifierFlags: [])
        try expectValue("1", of: field)
        XCTAssertTrue(app.buttons["editor.create-copy"].exists, "Escape in the field must not close the editor")
        XCTAssertTrue(app.buttons["editor.create-copy"].isEnabled)
        XCTAssertTrue(app.staticTexts["2 Selected"].exists)
        replacePosition(field, with: organize ? "3" : "2")
        try expectOrder(organize ? [1, 3, 0, 2] : [1, 0, 2], in: app)
        XCTAssertTrue(app.staticTexts["2 Selected"].exists, "Typing a position must preserve the selected group")
        app.buttons["Cancel"].click()
        try expectEditorClosed(in: app)
        XCTAssertEqual(try contents(folder), before, "Cancelling must not publish any output")
        XCTAssertEqual(try inputs.map { try Data(contentsOf: $0) }, originals)
        let reopen = app.buttons["operation." + operation]
        XCTAssertTrue(reopen.waitForExistence(timeout: 5))
        reopen.click()
        try expectOrder(Array(0..<(organize ? 4 : 3)), in: app)
        XCTAssertFalse(app.buttons["Undo"].isEnabled, "A reopened editor starts with the original order")
        app.buttons["Cancel"].click()
        try expectEditorClosed(in: app)
        XCTAssertEqual(try contents(folder), before)
    }

    private func scrolledWorkflow(organize: Bool) throws {
        let app = launch(language: "en")
        let inputs = workflowInputs(organize: organize, long: true)
        let originals = try inputs.map { try Data(contentsOf: $0) }
        let folder = try XCTUnwrap(inputs.first).deletingLastPathComponent()
        let before = try contents(folder)
        for input in inputs { app.open(input) }
        try openOperation(organize ? "pdf.organize" : "pdf.merge", in: app)
        let count = organize ? 24 : 18
        let last = app.textFields["pdf.position.\(count - 1)"]
        let window = app.windows.containing(.button, identifier: "editor.create-copy").firstMatch
        let scroller = window.scrollViews.firstMatch
        XCTAssertTrue(scroller.waitForExistence(timeout: 10))
        XCTAssertFalse(last.exists && last.isHittable, "The fixture must require a real scroll")
        var scrolls = 0
        while !(last.exists && last.isHittable), scrolls < 18 {
            scroller.scroll(byDeltaX: 0, deltaY: -420)
            scrolls += 1
        }
        XCTAssertGreaterThan(scrolls, 0)
        XCTAssertTrue(last.exists && last.isHittable, "Scrolling must make the final item's control usable")
        XCTAssertEqual(last.value as? String, String(count))
        dragSource(count - 1, to: count - 2, after: false, in: app, organize: organize)
        try expectValue(String(count - 1), of: last)
        try expectValue(String(count), of: app.textFields["pdf.position.\(count - 2)"])
        app.buttons["Undo"].click()
        try expectValue(String(count), of: last)
        app.typeKey("z", modifierFlags: [.command, .shift])
        try expectValue(String(count - 1), of: last)
        replacePosition(last, with: "1")
        try expectValue("1", of: last)
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: last)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 5), .completed,
                       "Moving to the first position must reveal the moved item")
        try expectValue("2", of: app.textFields["pdf.position.0"])
        app.buttons["editor.create-copy"].click()
        let output = try waitForOutput(in: folder, excluding: before)
        let expected = [count] + Array(1..<count)
        let prefix = organize ? "PAGE " : "FILE "
        XCTAssertEqual(try pageLabels(output), expected.map { prefix + String($0) })
        XCTAssertEqual(try inputs.map { try Data(contentsOf: $0) }, originals)
        XCTAssertEqual(try contents(folder).subtracting(before), [output])
    }

    private func workflowInputs(organize: Bool, long: Bool) -> [URL] {
        if organize {
            return [ReviewConfiguration.fixtures.appendingPathComponent(long ? "LongOrganize/Long-Order.pdf" : "Organize/Page-Order.pdf")]
        }
        return (1...(long ? 18 : 3)).map {
            ReviewConfiguration.fixtures.appendingPathComponent((long ? "LongMerge/" : "MultiMerge/") + String(format: "%02d.pdf", $0))
        }
    }

    private func workflowItem(_ index: Int, in app: XCUIApplication, organize: Bool) -> XCUIElement {
        app.descendants(matching: .any)[(organize ? "pdf.organize.card." : "pdf.merge.row.") + String(index)].firstMatch
    }

    private func selectDisjointGroup(in app: XCUIApplication, organize: Bool) throws {
        let first = workflowItem(0, in: app, organize: organize)
        let third = workflowItem(2, in: app, organize: organize)
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertTrue(third.waitForExistence(timeout: 10))
        first.buttons.firstMatch.click()
        XCUIElement.perform(withKeyModifiers: .command) { third.buttons.firstMatch.click() }
        XCTAssertTrue(app.staticTexts["2 Selected"].waitForExistence(timeout: 5))
    }

    private func dragSource(_ source: Int, to target: Int, after: Bool, in app: XCUIApplication, organize: Bool) {
        let start = workflowItem(source, in: app, organize: organize)
        let end = workflowItem(target, in: app, organize: organize)
        XCTAssertTrue(start.exists)
        XCTAssertTrue(end.exists)
        let grab = start.coordinate(withNormalizedOffset: CGVector(dx: organize ? 0.5 : 0.96, dy: organize ? 0.35 : 0.5))
        let drop = end.coordinate(withNormalizedOffset: CGVector(dx: organize ? (after ? 0.85 : 0.15) : 0.65,
                                                                dy: organize ? 0.35 : (after ? 0.85 : 0.15)))
        grab.click(forDuration: 0.7, thenDragTo: drop)
    }

    private func replacePosition(_ field: XCUIElement, with value: String) {
        XCTAssertTrue(field.isHittable)
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(value)
        field.typeKey(.return, modifierFlags: [])
    }

    private func expectOrder(_ sources: [Int], in app: XCUIApplication) throws {
        for (position, source) in sources.enumerated() {
            try expectValue(String(position + 1), of: app.textFields["pdf.position.\(source)"])
        }
    }

    private func expectEditorClosed(in app: XCUIApplication) throws {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                     object: app.buttons["editor.create-copy"])
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }
}
