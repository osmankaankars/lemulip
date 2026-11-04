
// Review the changed states in the normally launched application. The minimum
// workspace and each fixed-size editor are measured separately. These captures
// are not a reduced-motion preference test or an audible VoiceOver review.
extension QualityUITests {
    func testStateOrchardEnglishMinimumWorkspaceAndPDFKeyboard() throws {
        try stateAccessibilityReview(theme: "orchard", language: "en", editor: .pdf)
    }

    func testStateOrchardTurkishMinimumWorkspaceAndPDFKeyboard() throws {
        try stateAccessibilityReview(theme: "orchard", language: "tr", editor: .pdf)
    }

    func testStatePistachioEnglishMinimumWorkspaceAndAudioKeyboard() throws {
        try stateAccessibilityReview(theme: "pistachio", language: "en", editor: .audio)
    }

    func testStatePistachioTurkishMinimumWorkspaceAndAudioKeyboard() throws {
        try stateAccessibilityReview(theme: "pistachio", language: "tr", editor: .audio)
    }

    func testStateLemonadeEnglishMinimumWorkspaceAndVideoKeyboard() throws {
        try stateAccessibilityReview(theme: "lemonade", language: "en", editor: .video)
    }

    func testStateLemonadeTurkishMinimumWorkspaceAndVideoKeyboard() throws {
        try stateAccessibilityReview(theme: "lemonade", language: "tr", editor: .video)
    }

    private enum StateReviewEditor: Equatable { case pdf, audio, video }

    private func stateAccessibilityReview(theme: String, language: String,
                                          editor: StateReviewEditor) throws {
        let folder = languageFixtureFolder("Merge", language: language)
        let before = try contents(folder)
        XCTAssertEqual(before.count, 2, "Reuse the input-only long-name recovery fixture")
        let invalid = try XCTUnwrap(before.first { $0.lastPathComponent.hasPrefix("2026 Örnek:") })
        let companion = folder.appendingPathComponent("Companion.pdf")
        XCTAssertTrue(before.contains(companion))
        XCTAssertGreaterThan(invalid.lastPathComponent.count, 100)
        let originals = try before.map { ($0, try Data(contentsOf: $0)) }
        let app = launch(language: language, theme: theme, windowFrame: try stateMinimumWindowFrame())

        try stateCheckMinimumWorkspace(app, theme: theme, language: language)
        app.open(companion)
        app.open(invalid)
        let add = app.buttons["workspace.add-files"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        XCTAssertTrue(add.isEnabled && add.isHittable)
        let removeName = language == "tr"
            ? invalid.lastPathComponent + " Dosyasını Çıkar" : "Remove " + invalid.lastPathComponent
        let removeCandidates = app.buttons.matching(NSPredicate(format: "label CONTAINS %@",
            language == "tr" ? "Dosyasını Çıkar" : "Remove ")).allElementsBoundByIndex
        // APFS can decompose the filename. Compare the complete label with
        // Swift's canonical Unicode equality, keeping every character intact.
        let removeMatches = removeCandidates.filter { $0.label == removeName }
        XCTAssertEqual(removeMatches.count, 1)
        let remove = try XCTUnwrap(removeMatches.first)
        XCTAssertTrue(remove.exists && remove.isHittable,
                      "The long filename must retain its full accessible removal label")
        stateExpectMinimumWorkspaceFrame(app)
        try captureStateReview(app, theme: theme, language: language, state: "minimum workspace with long filename")

        // Use app-level keystrokes, so typing cannot silently focus the field.
        let search = app.textFields["workspace.operation-search"]
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        try stateExpectSearchFocus(name: "Command-F focuses search")
        app.typeText("no-such-tool-state07")
        XCTAssertEqual(search.value as? String, "no-such-tool-state07")
        app.typeKey(.escape, modifierFlags: [])
        try expectValue("", of: search)
        try stateExpectSearchFocus(name: "First Escape clears search and keeps focus")
        app.typeKey(.escape, modifierFlags: [])
        let afterEscape = try stateFocusedElement(name: "Second Escape leaves search")
        XCTAssertNotEqual(afterEscape?["AXIdentifier"] as? String, "workspace.operation-search")

        app.typeKey("f", modifierFlags: .command)
        try stateExpectSearchFocus(name: "Command-F returns to search")
        app.typeText(language == "tr" ? "PDF birleştir" : "Merge PDFs")
        let merge = app.buttons["operation.pdf.merge"]
        XCTAssertTrue(merge.waitForExistence(timeout: 5))
        XCTAssertTrue(merge.isEnabled && merge.isHittable)
        app.typeKey(.return, modifierFlags: [])
        let title = languageElement("pdf.merge.error-title", in: app)
        let detail = languageElement("pdf.merge.error-detail", in: app)
        try expectLanguageValue(language == "tr" ? "Birleştirme hazırlanamadı" : "Could Not Prepare the Merge", of: title)
        let recovery = language == "tr"
            ? "Bu dosya PDF olarak okunamadı. Başka bir PDF seçip yeniden dene."
            : "This file could not be read as a PDF. Choose another PDF and try again."
        try expectLanguageValue(invalid.lastPathComponent + ": " + recovery, of: detail)
        try stateCheckFooter(app, language: language, createEnabled: false)
        XCTAssertTrue(detail.isHittable)
        XCTAssertLessThan(detail.frame.maxY, app.buttons["editor.create-copy"].frame.minY,
                          "The complete long-name recovery text must not overlap the footer")
        try captureStateReview(app, theme: theme, language: language, state: "long PDF recovery")
        app.typeKey(.escape, modifierFlags: [])
        try expectEditorClosed(in: app)

        let clear = app.buttons[language == "tr" ? "Temizle" : "Clear"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        XCTAssertTrue(clear.isHittable)
        clear.click()
        XCTAssertTrue(app.buttons["workspace.choose-files"].waitForExistence(timeout: 5))
        switch editor {
        case .pdf:
            try statePDFKeyboard(app, input: companion, theme: theme, language: language)
        case .audio, .video:
            try stateMediaKeyboard(app, audio: editor == .audio, theme: theme, language: language)
        }
        XCTAssertEqual(try contents(folder), before, "Inspection and cancellation must create no PDF output")
        for (input, bytes) in originals { XCTAssertEqual(try Data(contentsOf: input), bytes) }
    }

    private var stateMinimumContentLayoutSize: NSSize { NSSize(width: 720, height: 560) }

    private var stateContentLayoutWindowStyle: NSWindow.StyleMask {
        // DashboardView's minimum applies below the title bar. The production
        // window also has fullSizeContentView, which extends its background
        // beneath that bar; omit that flag only when converting the usable
        // content-layout size to the outer window size reported by XCTest.
        [.titled, .closable, .miniaturizable, .resizable]
    }

    private var stateMinimumWindowSize: NSSize {
        NSWindow.frameRect(forContentRect: NSRect(origin: .zero, size: stateMinimumContentLayoutSize),
                           styleMask: stateContentLayoutWindowStyle).size
    }

    private func stateExpectMinimumWorkspaceFrame(_ app: XCUIApplication) {
        let observed = app.windows.firstMatch.frame
        let expected = stateMinimumWindowSize
        XCTAssertEqual(observed.width, expected.width, accuracy: 2,
                       "Measure the actual outer window for the minimum content layout")
        XCTAssertEqual(observed.height, expected.height, accuracy: 2)
    }

    private func stateMinimumWindowFrame() throws -> String {
        let screen = try XCTUnwrap(NSScreen.main, "The native review requires an actual display")
        let visible = screen.visibleFrame
        let minimum = stateMinimumWindowSize
        XCTAssertGreaterThanOrEqual(visible.width, minimum.width)
        XCTAssertGreaterThanOrEqual(visible.height, minimum.height)
        // Exercise the application's existing saved-window restoration path.
        // Keep its top near the display top so a larger native sheet can fit.
        let x = visible.midX - minimum.width / 2
        let y = max(visible.minY, visible.maxY - minimum.height - 8)
        return [x, y, minimum.width, minimum.height, screen.frame.minX, screen.frame.minY,
                screen.frame.width, screen.frame.height]
            .map { String(Int($0.rounded())) }.joined(separator: " ")
    }

    private func stateCheckMinimumWorkspace(_ app: XCUIApplication, theme: String,
                                            language: String) throws {
        stateExpectMinimumWorkspaceFrame(app)
        for (id, english, turkish) in [("workspace", "Workspace", "Çalışma Alanı"),
                                       ("activity", "Activity", "İşlemler"),
                                       ("settings", "Settings", "Ayarlar")] {
            let item = app.buttons["navigation." + id]
            XCTAssertTrue(item.exists && item.isEnabled && item.isHittable)
            XCTAssertEqual(item.label, language == "tr" ? turkish : english)
            XCTAssertLessThan(item.frame.width, 100, "Review the real compact sidebar")
        }
        app.buttons["navigation.settings"].click()
        let names = ["orchard": "Orchard Night", "pistachio": "Vivid Pistachio", "lemonade": "Lemon Drop"]
        for (key, name) in names {
            let choice = app.buttons[name]
            XCTAssertTrue(choice.waitForExistence(timeout: 5))
            XCTAssertTrue(choice.isHittable)
            let expected = key == theme
                ? (language == "tr" ? "Seçili" : "Selected")
                : (language == "tr" ? "Seçili değil" : "Not Selected")
            XCTAssertEqual(choice.value as? String, expected,
                           "The real settings must confirm the theme, not only the launch argument")
        }
        try captureStateReview(app, theme: theme, language: language, state: "minimum settings with confirmed theme")
        app.buttons["navigation.workspace"].click()
    }

    private func statePDFKeyboard(_ app: XCUIApplication, input: URL, theme: String,
                                  language: String) throws {
        app.open(input)
        try openOperation("pdf.organize", in: app)
        let first = app.textFields["pdf.position.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        try stateCheckFooter(app, language: language, createEnabled: true)
        XCTAssertEqual(first.value as? String, "1")
        replacePosition(first, with: "0")
        XCTAssertEqual(first.value as? String, "0")
        XCTAssertFalse(app.buttons["editor.create-copy"].isEnabled)
        try captureStateReview(app, theme: theme, language: language, state: "PDF invalid position")
        app.typeKey(.escape, modifierFlags: [])
        try expectValue("1", of: first)
        try stateCheckFooter(app, language: language, createEnabled: true)
        try captureStateReview(app, theme: theme, language: language, state: "PDF field Escape restores position")
        // The first Escape belongs to the draft. The next belongs to Cancel.
        app.typeKey(.escape, modifierFlags: [])
        try expectEditorClosed(in: app)
    }

    private func stateMediaKeyboard(_ app: XCUIApplication, audio: Bool, theme: String,
                                    language: String) throws {
        let input = ReviewConfiguration.fixtures.appendingPathComponent(audio
            ? "AudioControls/Playback.wav" : "VideoControls/Playback.mp4")
        let folder = input.deletingLastPathComponent()
        let before = try contents(folder)
        XCTAssertEqual(before, [input], "Use the existing input-only media fixture")
        let original = try Data(contentsOf: input)
        app.open(input)
        try openOperation("media.trim", in: app)
        let turkish = language == "tr"
        let start = app.textFields.matching(NSPredicate(format: "label == %@", turkish ? "Başlangıç" : "Start")).firstMatch
        let end = app.textFields.matching(NSPredicate(format: "label == %@", turkish ? "Bitiş" : "End")).firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 20))
        let playName = turkish ? (audio ? "Seçimi dinle" : "Seçimi oynat") : "Play Selection"
        let play = app.buttons[playName]
        expectAudioState("The real media preview must be ready", timeout: 20) { play.exists && play.isEnabled }
        replaceAudioTime(start, with: "00:02.000")
        replaceAudioTime(end, with: "00:18.000")
        try stateCheckFooter(app, language: language, createEnabled: true)
        let canvasName: String
        if audio {
            canvasName = turkish ? "Ses dalgası ve kırpma seçimi" : "Audio Waveform and Trim Selection"
        } else {
            canvasName = turkish ? "Video zaman çizelgesi ve kırpma seçimi" : "Video Timeline and Trim Selection"
        }
        let canvas = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", canvasName)).firstMatch
        XCTAssertTrue(canvas.exists && canvas.isHittable)
        canvas.click()
        try stateExpectCanvasFocus(canvasName, name: "Media canvas receives focus")
        app.typeKey("s", modifierFlags: [])
        app.typeKey(.rightArrow, modifierFlags: .shift)
        try expectValue("00:03.000", of: start)
        app.typeKey("e", modifierFlags: [])
        app.typeKey(.leftArrow, modifierFlags: .shift)
        try expectValue("00:17.000", of: end)
        XCTAssertEqual(start.value as? String, "00:03.000")

        // Observe real focus through the read-only, fixed-process AX reader.
        // Sending keys to `app`, rather than `canvas`, never refocuses it for us.
        app.typeKey(.tab, modifierFlags: [])
        let afterTab = try XCTUnwrap(stateFocusedElement(name: "Tab leaves media canvas"))
        XCTAssertNotEqual(afterTab["AXDescription"] as? String, canvasName)
        app.typeKey(.tab, modifierFlags: .shift)
        try stateExpectCanvasFocus(canvasName, name: "Shift-Tab returns to media canvas")
        app.typeKey(.tab, modifierFlags: .shift)
        let afterBackTab = try XCTUnwrap(stateFocusedElement(name: "Shift-Tab leaves media canvas"))
        XCTAssertNotEqual(afterBackTab["AXDescription"] as? String, canvasName)
        app.typeKey(.tab, modifierFlags: [])
        try stateExpectCanvasFocus(canvasName, name: "Tab returns to media canvas")

        if audio {
            app.typeKey("s", modifierFlags: [])
            app.typeKey(.rightArrow, modifierFlags: [])
            try expectValue("00:03.010", of: start)
            let expected = turkish
                ? "Başlangıç 00:03.010, bitiş 00:17.000. Etkin tutamak: başlangıç."
                : "Start 00:03.010, end 00:17.000. Active handle: start."
            try expectValue(expected, of: canvas)
        } else {
            // Moving End previews that edge. P must adjust only the playhead.
            let position = app.staticTexts.matching(NSPredicate(format: "label == %@",
                turkish ? "Oynatma konumu" : "Playback Position")).firstMatch
            expectAudioState("The edited video end must be the settled preview position") {
                guard let seconds = self.audioSeconds(position.value as? String) else { return false }
                return abs(seconds - 17) < 0.02 && play.isEnabled
            }
            app.typeKey("p", modifierFlags: [])
            app.typeKey(.leftArrow, modifierFlags: .shift)
            expectAudioState("The real video playhead must move earlier by one second") {
                guard let seconds = self.audioSeconds(position.value as? String) else { return false }
                return abs(seconds - 16) < 0.02 && play.isEnabled
            }
            XCTAssertEqual(start.value as? String, "00:03.000")
            XCTAssertEqual(end.value as? String, "00:17.000")
            let suffix = turkish ? "Etkin kontrol: oynatma konumu." : "Active control: playhead."
            XCTAssertTrue(try XCTUnwrap(canvas.value as? String).hasSuffix(suffix))
        }
        try stateCheckFooter(app, language: language, createEnabled: true)
        try captureStateReview(app, theme: theme, language: language,
                               state: audio ? "audio canvas keyboard and focus" : "video canvas keyboard and focus")
        app.typeKey(.escape, modifierFlags: [])
        try expectEditorClosed(in: app)
        XCTAssertEqual(try Data(contentsOf: input), original)
        XCTAssertEqual(try contents(folder), before, "Keyboard editing and Cancel must create no media output")
    }

    private func stateCheckFooter(_ app: XCUIApplication, language: String, createEnabled: Bool) throws {
        let create = app.buttons["editor.create-copy"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        let cancel = app.buttons[language == "tr" ? "Vazgeç" : "Cancel"]
        XCTAssertTrue(cancel.exists && cancel.isEnabled && cancel.isHittable)
        XCTAssertEqual(create.isEnabled, createEnabled)
        if createEnabled { XCTAssertTrue(create.isHittable) }
        let sheet = app.sheets.containing(.button, identifier: "editor.create-copy").firstMatch
        XCTAssertTrue(sheet.exists)
        XCTAssertGreaterThan(sheet.frame.width, 0)
        XCTAssertGreaterThan(sheet.frame.height, 0)
        let bounds = sheet.frame.insetBy(dx: -1, dy: -1)
        XCTAssertTrue(bounds.contains(cancel.frame), "Cancel must remain inside the real editor sheet")
        XCTAssertTrue(bounds.contains(create.frame), "Create Copy must remain inside the real editor sheet")
    }

    private func stateFocusedElement(name: String) throws -> [String: Any]? {
        let snapshot = try nativeAXSnapshot()
        let data = try JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "State 07 focus - " + name
        attachment.lifetime = .keepAlways
        add(attachment)
        return snapshot["focusedElement"] as? [String: Any]
    }

    private func stateExpectSearchFocus(name: String) throws {
        let focused = try XCTUnwrap(stateFocusedElement(name: name))
        XCTAssertEqual(focused["AXIdentifier"] as? String, "workspace.operation-search")
    }

    private func stateExpectCanvasFocus(_ label: String, name: String) throws {
        let focused = try XCTUnwrap(stateFocusedElement(name: name))
        XCTAssertEqual(focused["role"] as? String, "AXGroup")
        XCTAssertEqual(focused["AXDescription"] as? String, label)
    }

    private func captureStateReview(_ app: XCUIApplication, theme: String, language: String,
                                    state: String) throws {
        let name = "State 07 - " + theme + " - " + language + " - " + state
        func frameRecord(_ element: XCUIElement) -> [String: Any] {
            let frame = element.frame
            return ["title": element.title, "identifier": element.identifier,
                    "frame": [frame.minX, frame.minY, frame.width, frame.height]]
        }
        let record: [String: Any] = [
            "themeConfirmedInSettings": theme, "language": language, "state": state,
            "requestedWorkspaceContentLayoutMinimum": [stateMinimumContentLayoutSize.width,
                                                        stateMinimumContentLayoutSize.height],
            "expectedWorkspaceOuterMinimum": [stateMinimumWindowSize.width, stateMinimumWindowSize.height],
            "contentLayoutFrameStyleMask": stateContentLayoutWindowStyle.rawValue,
            "observedWindows": app.windows.allElementsBoundByIndex.map(frameRecord),
            "observedSheets": app.sheets.allElementsBoundByIndex.map(frameRecord),
            "screenFramesInAppKitCoordinates": NSScreen.screens.map {
                [$0.frame.minX, $0.frame.minY, $0.frame.width, $0.frame.height]
            },
            "scope": "The 720-by-560 minimum is the Dashboard content layout below the title bar. "
                + "AppKit computes its expected outer window size; observed window and sheet frames are recorded separately. "
                + "Editors retain their actual production sizes."
        ]
        let metadata = XCTAttachment(data: try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
                                     uniformTypeIdentifier: "public.json")
        metadata.name = name + " geometry"
        metadata.lifetime = .keepAlways
        add(metadata)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + " AX"
        tree.lifetime = .keepAlways
        add(tree)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
