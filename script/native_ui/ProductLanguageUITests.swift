
// Follow real EN/TR flows with independently staged inputs. The runner reads
// files and drives native controls; it never supplies results or moves a file.
extension QualityUITests {
    func testEnglishMergeErrorPreservesTheLongFilename() throws {
        try mergeLanguageRecovery(language: "en")
    }

    func testTurkishMergeErrorPreservesTheLongFilename() throws {
        try mergeLanguageRecovery(language: "tr")
    }

    func testEnglishEmptyAudioExplainsRecovery() throws {
        try mediaLanguageRecovery(language: "en", audio: true)
    }

    func testTurkishEmptyAudioExplainsRecovery() throws {
        try mediaLanguageRecovery(language: "tr", audio: true)
    }

    func testEnglishEmptyVideoExplainsRecovery() throws {
        try mediaLanguageRecovery(language: "en", audio: false)
    }

    func testTurkishEmptyVideoExplainsRecovery() throws {
        try mediaLanguageRecovery(language: "tr", audio: false)
    }

    func testEnglishWordCountReportsTheActualCounts() throws {
        try wordCountLanguageResult(language: "en")
    }

    func testTurkishWordCountReportsTheActualCounts() throws {
        try wordCountLanguageResult(language: "tr")
    }

    func testEnglishMoveReportsTheActualFileTransfer() throws {
        try moveLanguageResult(language: "en")
    }

    func testTurkishMoveReportsTheActualFileTransfer() throws {
        try moveLanguageResult(language: "tr")
    }

    private func mergeLanguageRecovery(language: String) throws {
        let folder = languageFixtureFolder("Merge", language: language)
        let before = try contents(folder)
        XCTAssertEqual(before.count, 2)
        let invalid = try XCTUnwrap(before.first { $0.lastPathComponent.hasPrefix("2026 Örnek:") })
        let companion = folder.appendingPathComponent("Companion.pdf")
        XCTAssertTrue(before.contains(companion))
        let originalBytes = try before.map { ($0, try Data(contentsOf: $0)) }
        XCTAssertGreaterThan(invalid.lastPathComponent.count, 100, "Exercise a real long filename")
        XCTAssertGreaterThan(try Data(contentsOf: invalid).count, 0, "Reach PDF decoding, not the empty-file guard")
        let app = launch(language: language)
        app.open(companion)
        app.open(invalid)
        try openOperation("pdf.merge", in: app)
        let title = languageElement("pdf.merge.error-title", in: app)
        let detail = languageElement("pdf.merge.error-detail", in: app)
        try expectLanguageValue(language == "tr" ? "Birleştirme hazırlanamadı" : "Could Not Prepare the Merge", of: title)
        let recovery = language == "tr"
            ? "Bu dosya PDF olarak okunamadı. Başka bir PDF seçip yeniden dene."
            : "This file could not be read as a PDF. Choose another PDF and try again."
        try expectLanguageValue(invalid.lastPathComponent + ": " + recovery, of: detail)
        try cancelLanguageError(app, detail: detail, language: language, name: "Long PDF filename recovery - " + language)
        XCTAssertEqual(try contents(folder), before)
        for (input, bytes) in originalBytes { XCTAssertEqual(try Data(contentsOf: input), bytes) }
    }

    private func mediaLanguageRecovery(language: String, audio: Bool) throws {
        let folder = languageFixtureFolder(audio ? "Audio" : "Video", language: language)
        let input = try soleLanguageInput(in: folder, extension: audio ? "wav" : "mp4")
        XCTAssertEqual(try Data(contentsOf: input), Data())
        let app = launch(language: language)
        app.open(input)
        try openOperation("media.trim", in: app)
        let prefix = audio ? "audio-trim" : "video-trim"
        let title = languageElement(prefix + ".error-title", in: app)
        let detail = languageElement(prefix + ".error-detail", in: app)
        let expectedTitle: String
        let expectedDetail: String
        if audio {
            expectedTitle = language == "tr" ? "Ses düzenleyicisi açılamadı" : "Could Not Open the Audio Editor"
            expectedDetail = language == "tr" ? "Boş olmayan, okunabilir bir ses dosyası seç."
                : "Choose a readable audio file that is not empty."
        } else {
            expectedTitle = language == "tr" ? "Video düzenleyicisi açılamadı" : "Could Not Open the Video Editor"
            expectedDetail = language == "tr" ? "Boş olmayan, okunabilir bir video dosyası seç."
                : "Choose a readable video file that is not empty."
        }
        try expectLanguageValue(expectedTitle, of: title)
        try expectLanguageValue(expectedDetail, of: detail)
        try cancelLanguageError(app, detail: detail, language: language, name: prefix + " empty-file recovery - " + language)
        XCTAssertEqual(try contents(folder), [input])
        XCTAssertEqual(try Data(contentsOf: input), Data())
    }

    private func cancelLanguageError(_ app: XCUIApplication, detail: XCUIElement,
                                     language: String, name: String) throws {
        let create = app.buttons["editor.create-copy"]
        let cancel = app.buttons[language == "tr" ? "Vazgeç" : "Cancel"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        XCTAssertFalse(create.isEnabled)
        XCTAssertTrue(detail.isHittable, "The full recovery text must remain visible")
        XCTAssertLessThan(detail.frame.maxY, create.frame.minY, "The message must not collide with the footer")
        XCTAssertTrue(cancel.isEnabled)
        XCTAssertTrue(cancel.isHittable)
        captureLanguageState(app, name: name)
        cancel.click()
        try expectEditorClosed(in: app)
    }

    private func wordCountLanguageResult(language: String) throws {
        let folder = languageFixtureFolder("Count", language: language)
        let input = try soleLanguageInput(in: folder, extension: "txt")
        let original = try Data(contentsOf: input)
        XCTAssertEqual(original, Data("one two\nthree".utf8))
        XCTAssertTrue(input.lastPathComponent.hasPrefix("words: Örnek characters lines-"))
        let app = launch(language: language)
        app.buttons["navigation.activity"].click()
        let empty = app.staticTexts.matching(NSPredicate(format: "value == %@", language == "tr"
            ? "Başlamak için bir dosya seç." : "Choose a file to get started.")).firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: 5))
        XCTAssertTrue(empty.isHittable)
        captureLanguageState(app, name: "Activity before choosing a file - " + language)
        app.buttons["navigation.workspace"].click()
        app.open(input)
        try openOperation("document.wordCount", in: app)
        app.buttons["navigation.activity"].click()
        let status = languageElement("activity.status", in: app)
        try expectLanguageValue(language == "tr" ? "Tamamlandı" : "Completed", of: status)
        let details = languageElement("activity.detail-text", in: app)
        XCTAssertFalse(details.exists && details.isHittable)
        let disclosure = app.disclosureTriangles[language == "tr" ? "Ayrıntılar" : "Details"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
        XCTAssertTrue(disclosure.isEnabled)
        captureLanguageState(app, name: "Word count before expanding details - " + language)
        disclosure.click()
        let expected = input.lastPathComponent + (language == "tr"
            ? ": 3 kelime · 13 karakter · 2 satır" : ": 3 words · 13 characters · 2 lines")
        try expectLanguageValue(expected, of: details)
        XCTAssertTrue(details.isHittable, "The real report must be expanded before capture")
        XCTAssertTrue(status.isHittable)
        captureLanguageState(app, name: "Actual word-count report - " + language)
        XCTAssertEqual(try Data(contentsOf: input), original)
        XCTAssertEqual(try contents(folder), [input], "A report must not create an output file")
    }

    private func moveLanguageResult(language: String) throws {
        let folder = languageFixtureFolder("Move", language: language)
        let source = folder.appendingPathComponent("Source", isDirectory: true)
        let destination = folder.appendingPathComponent("Destination", isDirectory: true)
        let input = try soleLanguageInput(in: source, extension: "txt")
        let original = try Data(contentsOf: input)
        XCTAssertEqual(try contents(folder), [source, destination])
        XCTAssertTrue(try contents(destination).isEmpty)
        let app = launch(language: language)
        app.open(input)
        try openOperation("action.move", in: app)
        let choose = app.buttons[language == "tr" ? "Buraya taşı" : "Move Here"]
        XCTAssertTrue(choose.waitForExistence(timeout: 10), "Require the real native destination picker")
        app.typeKey("g", modifierFlags: [.command, .shift])
        let goToFolder = app.sheets.textFields.firstMatch
        XCTAssertTrue(goToFolder.waitForExistence(timeout: 5))
        goToFolder.click()
        goToFolder.typeKey("a", modifierFlags: .command)
        goToFolder.typeText(destination.path)
        goToFolder.typeKey(.return, modifierFlags: [])
        let navigationFinished = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !goToFolder.exists && choose.exists && choose.isEnabled && choose.isHittable
        }, object: choose)
        XCTAssertEqual(XCTWaiter.wait(for: [navigationFinished], timeout: 10), .completed)
        captureLanguageState(app, name: "Actual move destination before confirmation - " + language)
        choose.click()

        let target = destination.appendingPathComponent(input.lastPathComponent)
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !FileManager.default.fileExists(atPath: input.path) && FileManager.default.fileExists(atPath: target.path)
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 10), .completed,
                       "Only the production move action may transfer the prepared source")
        XCTAssertEqual(try Data(contentsOf: target), original)
        XCTAssertTrue(try contents(source).isEmpty)
        XCTAssertEqual(try contents(destination), [target])
        XCTAssertEqual(try contents(folder), [source, destination])
        app.buttons["navigation.activity"].click()
        let status = languageElement("activity.status", in: app)
        try expectLanguageValue(language == "tr" ? "Taşındı · 1 öğe" : "Moved · 1 item", of: status)
        XCTAssertTrue(status.isHittable)
        let output = app.buttons.matching(NSPredicate(format: "identifier == %@", "activity.output." + target.path)).firstMatch
        XCTAssertTrue(output.waitForExistence(timeout: 5))
        XCTAssertTrue(output.isHittable)
        let receipt = XCTAttachment(string: [
            "Source path: " + input.path,
            "Source still exists: \(FileManager.default.fileExists(atPath: input.path))",
            "Destination path: " + target.path,
            "Observed destination files: " + (try contents(destination).map(\.lastPathComponent).sorted().joined(separator: ", ")),
            "Destination bytes preserved: \((try Data(contentsOf: target)) == original)",
            "Observed status: \(status.value as? String ?? "<missing>")"
        ].joined(separator: "\n"))
        receipt.name = "Actual move file identity - " + language
        receipt.lifetime = .keepAlways
        add(receipt)
        captureLanguageState(app, name: "Actual moved-file result - " + language)
    }

    private func languageFixtureFolder(_ scenario: String, language: String) -> URL {
        ReviewConfiguration.fixtures.appendingPathComponent("ProductLanguage/" + scenario + "-" + language, isDirectory: true)
    }

    private func soleLanguageInput(in folder: URL, extension expectedExtension: String) throws -> URL {
        let files = try contents(folder)
        XCTAssertEqual(files.count, 1, "Require an unused input-only fixture")
        let input = try XCTUnwrap(files.first)
        XCTAssertEqual(input.pathExtension, expectedExtension)
        return input
    }

    private func languageElement(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        // Selectable SwiftUI Text can expose a different AX element type.
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", identifier)).firstMatch
    }

    private func expectLanguageValue(_ expected: String, of element: XCUIElement) throws {
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        let matches = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [matches], timeout: 10), .completed)
        XCTAssertEqual(try XCTUnwrap(element.value as? String), expected)
    }

    private func captureLanguageState(_ app: XCUIApplication, name: String) {
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
