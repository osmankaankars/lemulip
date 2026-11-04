
// This case changes only the disposable runner's two ordinary display
// preferences through System Settings, then restores the observed originals.
// It never writes defaults/TCC, injects app preferences, or claims that a still
// screenshot establishes animation timing or heard VoiceOver narration.
extension QualityUITests {
    func testRealDisplayPreferencesKeepWheelAndPDFResultsUsable() throws {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.systempreferences")
        settings.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        settings.launch()
        addTeardownBlock { @MainActor in
            if settings.state != .notRunning { settings.terminate() }
        }
        try openDisplayReviewSettings(settings)
        let initial = try displayReviewControlValues(in: settings)
        try expectDisplayReviewWorkspace(initial)
        captureDisplayReview(settings, name: "Display preferences before review", expected: initial)

        // XCTest executes registered teardown blocks even when a later
        // assertion fails with continueAfterFailure=false. Register restoration
        // before the first change and report restoration failures as failures.
        addTeardownBlock { @MainActor in
            // A failed action can leave the app's always-visible result panel
            // above System Settings. Close only our isolated app before restoring
            // the runner, so that panel cannot intercept the cleanup clicks.
            if let runningApp = self.application, runningApp.state != .notRunning {
                self.captureDisplayReview(runningApp, name: "App before display preference restoration")
                runningApp.terminate()
            }
            settings.activate()
            try self.restoreDisplayReviewPreferences(initial, in: settings)
            self.captureDisplayReview(settings, name: "Display preferences restored", expected: initial)
        }

        // Keep the production app alive while the system values change. Both
        // NSWorkspace reads and ordinary UI interactions use the real values.
        let app = launch(language: "en", completion: "card", theme: "orchard")
        let cases: [(String, DisplayReviewPreferences)] = [
            ("AccessibilityMotion", .init(reduceMotion: true, reduceTransparency: false)),
            ("AccessibilityTransparency", .init(reduceMotion: false, reduceTransparency: true))
        ]
        for (scenario, preference) in cases {
            settings.activate()
            try setDisplayReviewPreferences(preference, in: settings)
            captureDisplayReview(settings, name: scenario + " actual System Settings", expected: preference)
            app.activate()
            try exerciseDisplayReviewFlow(scenario, in: app, preferences: preference)
        }
    }

    private struct DisplayReviewPreferences: Equatable {
        let reduceMotion: Bool
        let reduceTransparency: Bool

        @MainActor static var workspace: Self {
            Self(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                 reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
        }

        var text: String { "Reduce Motion=\(reduceMotion), Reduce Transparency=\(reduceTransparency)" }
    }

    private func openDisplayReviewSettings(_ settings: XCUIApplication) throws {
        guard settings.windows.firstMatch.waitForExistence(timeout: 15) else {
            throw displayReviewError("System Settings did not open")
        }
        // Navigate the visible menu and pane, not a private preference API or
        // an undocumented direct write to com.apple.universalaccess.
        let viewMenu = settings.menuBars.menuBarItems["View"]
        guard viewMenu.waitForExistence(timeout: 10) else {
            captureDisplayReview(settings, name: "System Settings menu unavailable")
            throw displayReviewError("The real System Settings View menu is unavailable")
        }
        viewMenu.click()
        let accessibility = settings.menuItems["Accessibility"]
        guard accessibility.waitForExistence(timeout: 5), accessibility.isEnabled else {
            captureDisplayReview(settings, name: "System Settings Accessibility menu unavailable")
            throw displayReviewError("The real Accessibility menu item is unavailable")
        }
        accessibility.click()
        let display = settings.buttons.matching(NSPredicate(format: "label == %@", "Display")).firstMatch
        guard display.waitForExistence(timeout: 10), display.isHittable else {
            captureDisplayReview(settings, name: "System Settings Display pane unavailable")
            throw displayReviewError("The real Accessibility Display pane is unavailable on this runner")
        }
        display.click()
        _ = try displayReviewToggle("Reduce motion", in: settings)
        _ = try displayReviewToggle("Reduce transparency", in: settings)
    }

    private func displayReviewToggle(_ title: String, in settings: XCUIApplication) throws -> XCUIElement {
        // The real Display pane exposes these captions as sibling StaticText
        // elements. Its binary controls carry these exact AX identifiers on
        // both native runners, rather than the captions as their own labels.
        let identifiers = ["Reduce motion": "AX_REDUCE_MOTION",
                           "Reduce transparency": "AX_REDUCE_TRANSPARENCY"]
        guard let identifier = identifiers[title] else {
            throw displayReviewError("Unsupported display preference: \(title)")
        }
        let predicate = NSPredicate(format: "identifier == %@", identifier)
        let checkBoxes = settings.checkBoxes.matching(predicate)
        let switches = settings.switches.matching(predicate)
        let available = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            checkBoxes.count > 0 || switches.count > 0
        }, object: settings)
        guard XCTWaiter.wait(for: [available], timeout: 8) == .completed else {
            captureDisplayReview(settings, name: title + " control unavailable")
            throw displayReviewError("System Settings did not expose the actual \(title) control")
        }
        let matches = checkBoxes.allElementsBoundByIndex + switches.allElementsBoundByIndex
        guard matches.count == 1 else {
            captureDisplayReview(settings, name: title + " control ambiguous")
            throw displayReviewError("System Settings must expose exactly one \(identifier) binary control")
        }
        let result = matches[0]
        if !result.isHittable {
            // Use only a real scroll container that contains this named
            // control; never scroll the unrelated settings sidebar by guess.
            let containers = settings.scrollViews.allElementsBoundByIndex.filter {
                $0.checkBoxes.matching(predicate).count > 0 || $0.switches.matching(predicate).count > 0
            }
            if let container = containers.last {
                for _ in 0..<6 {
                    if result.isHittable { break }
                    let above = result.frame.maxY > 0 && result.frame.maxY < container.frame.minY
                    container.scroll(byDeltaX: 0, deltaY: above ? 160 : -160)
                }
            }
        }
        guard result.isEnabled, result.isHittable else {
            captureDisplayReview(settings, name: title + " control not interactive")
            throw displayReviewError("System Settings \(title) is not enabled and hittable")
        }
        _ = try displayReviewToggleValue(result)
        return result
    }

    private func displayReviewToggleValue(_ control: XCUIElement) throws -> Bool {
        let value = (control.value as? NSNumber)?.intValue ?? Int(control.value as? String ?? "")
        guard let value, value == 0 || value == 1 else {
            throw displayReviewError("The named display control did not expose a binary value")
        }
        return value == 1
    }

    private func displayReviewControlValues(in settings: XCUIApplication) throws -> DisplayReviewPreferences {
        DisplayReviewPreferences(
            reduceMotion: try displayReviewToggleValue(displayReviewToggle("Reduce motion", in: settings)),
            reduceTransparency: try displayReviewToggleValue(displayReviewToggle("Reduce transparency", in: settings)))
    }

    private func setDisplayReviewToggle(_ title: String, enabled: Bool, in settings: XCUIApplication) throws {
        let control = try displayReviewToggle(title, in: settings)
        if try displayReviewToggleValue(control) != enabled { control.click() }
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let value = (control.value as? NSNumber)?.intValue ?? Int(control.value as? String ?? "")
            return value == (enabled ? 1 : 0)
        }, object: control)
        guard XCTWaiter.wait(for: [changed], timeout: 8) == .completed else {
            captureDisplayReview(settings, name: title + " change not confirmed")
            throw displayReviewError("The real \(title) control did not become \(enabled ? "on" : "off")")
        }
    }

    private func setDisplayReviewPreferences(_ expected: DisplayReviewPreferences,
                                             in settings: XCUIApplication) throws {
        try setDisplayReviewToggle("Reduce motion", enabled: expected.reduceMotion, in: settings)
        try setDisplayReviewToggle("Reduce transparency", enabled: expected.reduceTransparency, in: settings)
        XCTAssertEqual(try displayReviewControlValues(in: settings), expected)
        try expectDisplayReviewWorkspace(expected)
    }

    private func expectDisplayReviewWorkspace(_ expected: DisplayReviewPreferences) throws {
        let observed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            DisplayReviewPreferences.workspace == expected
        }, object: nil)
        guard XCTWaiter.wait(for: [observed], timeout: 10) == .completed else {
            throw displayReviewError("NSWorkspace did not observe \(expected.text); observed \(DisplayReviewPreferences.workspace.text)")
        }
    }

    private func restoreDisplayReviewPreferences(_ initial: DisplayReviewPreferences,
                                                in settings: XCUIApplication) throws {
        // Attempt both restorations even if the first one fails. Missing UI or
        // an unconfirmed NSWorkspace value remains a visible failed check.
        var errors: [String] = []
        for (title, enabled) in [("Reduce motion", initial.reduceMotion),
                                 ("Reduce transparency", initial.reduceTransparency)] {
            do { try setDisplayReviewToggle(title, enabled: enabled, in: settings) }
            catch { errors.append(String(describing: error)) }
        }
        do { try expectDisplayReviewWorkspace(initial) }
        catch { errors.append(String(describing: error)) }
        if !errors.isEmpty {
            captureDisplayReview(settings, name: "Display preference restoration failed", expected: initial)
            throw displayReviewError(errors.joined(separator: "\n"))
        }
    }

    private func exerciseDisplayReviewFlow(_ scenario: String, in app: XCUIApplication,
                                           preferences: DisplayReviewPreferences) throws {
        let clear = app.buttons["Clear"]
        if clear.exists {
            XCTAssertTrue(clear.isHittable)
            clear.click()
        }
        let input = try preparedPDFFixture(scenario)
        let original = try Data(contentsOf: input)
        let folder = input.deletingLastPathComponent()
        let before = try contents(folder)
        app.open(input)

        let open = app.buttons["Open Wheel"]
        XCTAssertTrue(open.waitForExistence(timeout: 10) && open.isHittable)
        open.click()
        let wheel = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Lemulip file operations")).firstMatch
        XCTAssertTrue(wheel.waitForExistence(timeout: 10) && wheel.isEnabled && wheel.isHittable)
        let initialWheelValue = try XCTUnwrap(wheel.value as? String)
        XCTAssertFalse(initialWheelValue.isEmpty)
        app.typeKey(.rightArrow, modifierFlags: [])
        let navigation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let value = wheel.value as? String else { return false }
            return !value.isEmpty && value != initialWheelValue
        }, object: wheel)
        XCTAssertEqual(XCTWaiter.wait(for: [navigation], timeout: 5), .completed,
                       "The actual wheel must remain keyboard operable with \(preferences.text)")
        captureDisplayReview(app, name: scenario + " wheel", expected: preferences)
        app.typeKey(.escape, modifierFlags: [])
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: wheel)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 5), .completed)
        XCTAssertEqual(try contents(folder), before)

        try openOperation("pdf.organize", in: app)
        let position = app.textFields["pdf.position.0"]
        XCTAssertTrue(position.waitForExistence(timeout: 10))
        replacePosition(position, with: "2")
        try expectOrder([1, 0, 2, 3], in: app)
        let create = app.buttons["editor.create-copy"]
        XCTAssertTrue(create.isEnabled && create.isHittable)
        captureDisplayReview(app, name: scenario + " edited PDF", expected: preferences)
        create.click()
        let output = try waitForOutput(in: folder, excluding: before)
        XCTAssertEqual(try pageLabels(output), ["PAGE 2", "PAGE 1", "PAGE 3", "PAGE 4"])
        XCTAssertEqual(try Data(contentsOf: input), original)
        XCTAssertEqual(try contents(folder).subtracting(before), [output])

        let result = app.buttons.matching(NSPredicate(format: "identifier == %@",
                                                      "completion.output." + output.path)).firstMatch
        let dismiss = app.buttons["Dismiss Results"]
        XCTAssertTrue(result.waitForExistence(timeout: 10) && result.isEnabled && result.isHittable)
        XCTAssertEqual(result.label, "Show \(output.lastPathComponent) in Finder")
        XCTAssertTrue(dismiss.isEnabled && dismiss.isHittable)
        captureDisplayReview(app, name: scenario + " usable result card", expected: preferences)
        dismiss.click()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: result)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed,
                       "The real result panel must dismiss with \(preferences.text)")
        XCTAssertEqual(try Data(contentsOf: input), original)
        try expectDisplayReviewWorkspace(preferences)
    }

    private func captureDisplayReview(_ app: XCUIApplication, name: String,
                                      expected: DisplayReviewPreferences? = nil) {
        let values = XCTAttachment(string: [
            "Expected system preferences: \(expected?.text ?? "record only")",
            "Observed NSWorkspace preferences: \(DisplayReviewPreferences.workspace.text)",
            "Observation: real UI and completed interactions; no animation-timing or VoiceOver-speech claim."
        ].joined(separator: "\n"))
        values.name = name + " NSWorkspace values"
        values.lifetime = .keepAlways
        add(values)
        let graph = XCTAttachment(string: app.debugDescription)
        graph.name = name + " AX"
        graph.lifetime = .keepAlways
        add(graph)
        // The result card and wheel are separate native panels; a screen
        // screenshot includes them even if the main-window crop does not.
        let screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screen.name = name
        screen.lifetime = .keepAlways
        add(screen)
    }

    private func displayReviewError(_ message: String) -> NSError {
        NSError(domain: "LemulipDisplayPreferenceReview", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}
