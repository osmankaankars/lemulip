
// A number field is not a reorder command until its numeric position changes.
// In particular, Return must not close gaps in a noncontiguous selection.
extension QualityUITests {
    func testMergeUnchangedPositionReturnPreservesDisjointSelectionAndHistory() throws {
        try unchangedPositionWorkflow(organize: false, retype: false)
    }

    func testOrganizerUnchangedPositionReturnPreservesDisjointSelectionAndHistory() throws {
        try unchangedPositionWorkflow(organize: true, retype: false)
    }

    func testMergeEquivalentPositionInputPreservesDisjointSelectionAndHistory() throws {
        try unchangedPositionWorkflow(organize: false, retype: true)
    }

    func testOrganizerEquivalentPositionInputPreservesDisjointSelectionAndHistory() throws {
        try unchangedPositionWorkflow(organize: true, retype: true)
    }

    private func unchangedPositionWorkflow(organize: Bool, retype: Bool) throws {
        let app = launch(language: "en")
        let inputs = workflowInputs(organize: organize, long: false)
        let originals = try inputs.map { try Data(contentsOf: $0) }
        let folder = try XCTUnwrap(inputs.first).deletingLastPathComponent()
        let before = try contents(folder)
        for input in inputs { app.open(input) }
        try openOperation(organize ? "pdf.organize" : "pdf.merge", in: app)
        try selectDisjointGroup(in: app, organize: organize)
        let field = app.textFields["pdf.position.0"]
        XCTAssertTrue(field.isHittable)
        field.click()
        if retype {
            field.typeKey("a", modifierFlags: .command)
            field.typeText("01")
        }
        field.typeKey(.return, modifierFlags: [])
        try expectOrder(Array(0..<(organize ? 4 : 3)), in: app)
        XCTAssertTrue(app.staticTexts["2 Selected"].exists,
                      "An unchanged position must not select a different item or collapse a group")
        XCTAssertFalse(app.buttons["Undo"].isEnabled, "An unchanged number must not add undo history")
        XCTAssertFalse(app.buttons["Redo"].isEnabled)
        XCTAssertTrue(app.buttons["editor.create-copy"].isEnabled,
                      "Return should finish number editing without exporting or disabling document actions")
        XCTAssertEqual(try contents(folder), before, "Return in a number field must not create an output")
        app.buttons["editor.create-copy"].click()
        let output = try waitForOutput(in: folder, excluding: before)
        let prefix = organize ? "PAGE " : "FILE "
        XCTAssertEqual(try pageLabels(output), (1...(organize ? 4 : 3)).map { prefix + String($0) })
        XCTAssertEqual(try inputs.map { try Data(contentsOf: $0) }, originals)
        XCTAssertEqual(try contents(folder).subtracting(before), [output])
    }
}
