
// Production controls, real AVPlayer progress and read-only staged input only.
// Playback position is the localized Text's AXValue, not part of its AXLabel.
extension QualityUITests {
    func testEnglishAudioResetSelectionAndPlaybackResume() throws {
        try audioResetSelectionAndPlaybackResume(language: "en")
    }

    func testTurkishAudioResetSelectionAndPlaybackResume() throws {
        try audioResetSelectionAndPlaybackResume(language: "tr")
    }

    private func audioResetSelectionAndPlaybackResume(language: String) throws {
        let app = launch(language: language)
        // FFmpeg stages this longer input before the sandboxed runner launches.
        // Keep the legacy 0.25-second Quality.wav and its folder untouched.
        let input = ReviewConfiguration.fixtures.appendingPathComponent("AudioControls/Playback.wav")
        let original = try Data(contentsOf: input)
        let folder = input.deletingLastPathComponent()
        let before = try contents(folder)
        XCTAssertEqual(before, Set([input]), "Require an isolated, input-only audio fixture folder")
        app.open(input)
        try openOperation("media.trim", in: app)

        let turkish = language == "tr"
        let start = app.textFields.matching(NSPredicate(format: "label == %@", turkish ? "Başlangıç" : "Start")).firstMatch
        let end = app.textFields.matching(NSPredicate(format: "label == %@", turkish ? "Bitiş" : "End")).firstMatch
        let play = app.buttons[turkish ? "Seçimi dinle" : "Play Selection"]
        let pause = app.buttons[turkish ? "Duraklat" : "Pause"]
        let reset = app.buttons[turkish ? "Seçimi sıfırla" : "Reset Selection"]
        let cancel = app.buttons[turkish ? "Vazgeç" : "Cancel"]
        let create = app.buttons["editor.create-copy"]
        let format = app.popUpButtons["audio-trim.output-format"]
        let position = app.staticTexts.matching(NSPredicate(format: "label == %@",
                                                            turkish ? "Oynatma konumu" : "Playback Position")).firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        XCTAssertTrue(end.exists)
        XCTAssertTrue(position.exists)
        expectAudioState("The real player must be ready before exercising its controls", timeout: 20) {
            play.exists && play.isEnabled
        }
        XCTAssertEqual(start.value as? String, "00:00.000")
        XCTAssertEqual(end.value as? String, "00:20.000")
        XCTAssertEqual(create.label, turkish ? "Kopya Oluştur" : "Create Copy")
        XCTAssertFalse(reset.isEnabled)
        XCTAssertEqual(format.value as? String, "WAV · 16-Bit PCM")
        format.click()
        let aiff = app.menuItems["AIFF · 16-Bit PCM"]
        XCTAssertTrue(aiff.waitForExistence(timeout: 5))
        aiff.click()

        replaceAudioTime(start, with: "00:02.000")
        replaceAudioTime(end, with: "00:18.000")
        expectAudioState("Valid live edits must enable playback and Create Copy") {
            play.isEnabled && create.isEnabled && reset.isEnabled
        }
        XCTAssertEqual(try audioPositionSeconds(position), 2, accuracy: 0.001)
        replaceAudioTime(start, with: "invalid")
        expectAudioState("Invalid text must disable both playback and the default Create Copy action") {
            !play.isEnabled && !create.isEnabled
        }
        let errorText = turkish
            ? "Sesin içinde, bitişi başlangıçtan sonra olan bir aralık gir. Saniye, dakika:saniye veya saat:dakika:saniye kullan."
            : "Enter a start and end inside the audio, with End after Start. Use seconds, MM:SS, or HH:MM:SS."
        let error = app.staticTexts.matching(NSPredicate(format: "value == %@ OR label == %@", errorText, errorText)).firstMatch
        XCTAssertTrue(error.exists && error.isHittable, "Invalid text must show the localized recovery guidance")
        XCTAssertTrue(reset.isEnabled && reset.isHittable)
        XCTAssertTrue(cancel.isEnabled && cancel.isHittable)
        XCTAssertTrue(create.isHittable)
        start.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(create.exists, "Return must leave the invalid editor open")
        XCTAssertFalse(create.isEnabled)
        XCTAssertFalse(play.isEnabled)
        XCTAssertEqual(start.value as? String, "invalid")
        XCTAssertEqual(try contents(folder), before)
        captureAudioState(app, name: "Audio " + language + " invalid")

        reset.click()
        try expectValue("00:00.000", of: start)
        try expectValue("00:20.000", of: end)
        expectAudioState("Reset Selection must recover the full valid range") {
            play.isEnabled && create.isEnabled && !reset.isEnabled
        }
        XCTAssertEqual(try audioPositionSeconds(position), 0, accuracy: 0.001)
        XCTAssertFalse(error.exists, "Reset Selection must clear the validation feedback")
        XCTAssertEqual(format.value as? String, "AIFF · 16-Bit PCM",
                       "Reset Selection must preserve the user's chosen output format")
        captureAudioState(app, name: "Audio " + language + " reset")

        replaceAudioTime(start, with: "00:02.000")
        replaceAudioTime(end, with: "00:18.000")
        XCTAssertEqual(try audioPositionSeconds(position), 2, accuracy: 0.001,
                       "A changed selection must start at its new Start")
        XCTAssertTrue(play.isEnabled && create.isEnabled)
        play.click()
        expectAudioState("Actual AVPlayer playback must reach a noticeable intermediate position") {
            guard let seconds = self.audioSeconds(position.value as? String) else { return false }
            return seconds >= 7 && pause.exists && pause.isEnabled
        }
        pause.click()
        expectAudioState("The actual Pause action must restore Play Selection") { play.exists && play.isEnabled }
        let paused = try audioPositionSeconds(position)
        XCTAssertGreaterThanOrEqual(paused, 7)
        XCTAssertLessThan(paused, 13, "Keep enough of the selection to observe both resume paths")
        let drift = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let seconds = self.audioSeconds(position.value as? String) else { return true }
            return abs(seconds - paused) > 0.02 || !play.exists || !play.isEnabled
        }, object: position)
        drift.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [drift], timeout: 1.2), .completed,
                       "Paused playback must remain stationary throughout the observation window")
        captureAudioState(app, name: "Audio " + language + " paused")

        try expectAudioResume(position, from: paused, name: "Audio " + language + " button resume") {
            play.click()
        }
        XCTAssertTrue(pause.exists && pause.isEnabled)
        captureAudioState(app, name: "Audio " + language + " resumed")
        pause.click()
        expectAudioState("Pause must still work after resuming") { play.exists && play.isEnabled }
        let beforeFocus = try audioPositionSeconds(position)

        // Click the actual labeled canvas to focus it. Its center lies inside
        // the 2–18 second selection; no guessed pixels or test-only hooks.
        let waveform = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@",
            turkish ? "Ses dalgası ve kırpma seçimi" : "Audio Waveform and Trim Selection")).firstMatch
        XCTAssertTrue(waveform.exists && waveform.isHittable)
        waveform.click()
        XCTAssertEqual(start.value as? String, "00:02.000")
        XCTAssertEqual(end.value as? String, "00:18.000")
        let keyboardPaused = try audioPositionSeconds(position)
        XCTAssertEqual(keyboardPaused, beforeFocus, accuracy: 0.02,
                       "Focusing the waveform must preserve the paused position for the Space scenario")
        XCTAssertLessThan(keyboardPaused, 16, "The keyboard resume must begin before the selection end")
        try expectAudioResume(position, from: keyboardPaused, name: "Audio " + language + " Space resume") {
            waveform.typeKey(" ", modifierFlags: [])
        }
        XCTAssertTrue(pause.exists && pause.isEnabled)
        waveform.typeKey(" ", modifierFlags: [])
        expectAudioState("Space on the focused waveform must also pause playback") { play.exists && play.isEnabled }
        captureAudioState(app, name: "Audio " + language + " Space pause")

        XCTAssertEqual(format.value as? String, "AIFF · 16-Bit PCM")
        XCTAssertTrue(cancel.isEnabled && cancel.isHittable)
        cancel.click()
        try expectEditorClosed(in: app)
        XCTAssertEqual(try Data(contentsOf: input), original, "Cancel must preserve the exact input bytes")
        XCTAssertEqual(try contents(folder), before, "Playback, invalid Return, Reset and Cancel must create no files")
    }

    private func replaceAudioTime(_ field: XCUIElement, with text: String) {
        XCTAssertTrue(field.isHittable)
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(text)
        XCTAssertEqual(field.value as? String, text)
    }

    private func expectAudioState(_ message: String, timeout: TimeInterval = 10,
                                  _ condition: @escaping () -> Bool) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: timeout), .completed, message)
    }

    private func audioSeconds(_ value: String?) -> Double? {
        guard let value else { return nil }
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1]),
              minutes.isFinite, seconds.isFinite, minutes >= 0, seconds >= 0, seconds < 60 else { return nil }
        return minutes * 60 + seconds
    }

    private func audioPositionSeconds(_ position: XCUIElement) throws -> Double {
        try XCTUnwrap(audioSeconds(position.value as? String), "Require the actual Playback Position AXValue")
    }

    private func expectAudioResume(_ position: XCUIElement, from paused: Double, name: String,
                                   resume: () -> Void) throws {
        let requested = ProcessInfo.processInfo.systemUptime
        resume()
        // Read immediately after the action, before waiting for a label or a
        // threshold. Bound this first observation so restarting at 2 seconds
        // cannot have enough time to catch up to the paused position unnoticed.
        let firstText = try XCTUnwrap(position.value as? String)
        let first = try XCTUnwrap(audioSeconds(firstText))
        let firstLatency = ProcessInfo.processInfo.systemUptime - requested
        var samples = ["Paused: \(paused)", "First AXValue: \(firstText); elapsed: \(firstLatency)"]
        XCTAssertLessThan(firstLatency, paused - 2 - 0.25,
                          "The first resumed observation must precede any possible restart catch-up")
        XCTAssertGreaterThanOrEqual(first, paused - 0.05, "Resume must not jump back to Start")
        var backwards = false
        var malformed = false
        var latest = first
        let progress = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let text = position.value as? String
            guard let seconds = self.audioSeconds(text) else { malformed = true; return true }
            samples.append("AXValue: \(text ?? "<missing>"); elapsed: \(ProcessInfo.processInfo.systemUptime - requested)")
            if seconds < latest - 0.05 { backwards = true; return true }
            latest = seconds
            return seconds >= paused + 0.4
        }, object: position)
        let result = XCTWaiter.wait(for: [progress], timeout: 8)
        let progressLatency = ProcessInfo.processInfo.systemUptime - requested
        samples.append("Progress observation elapsed: \(progressLatency)")
        let receipt = XCTAttachment(string: samples.joined(separator: "\n"))
        receipt.name = name + " AX values"
        receipt.lifetime = .keepAlways
        add(receipt)
        XCTAssertFalse(malformed, "Playback position must remain a readable AXValue")
        XCTAssertFalse(backwards, "Every observed resume sample must stay at or beyond the previous sample")
        XCTAssertEqual(result, .completed, "Resumed playback must actually advance")
        XCTAssertGreaterThanOrEqual(latest, paused + 0.4)
        XCTAssertLessThan(progressLatency, paused - 2 + 0.4 - 0.25,
                          "Observe progress before a restart could reach the same position, even if the first AX value was stale")
        XCTAssertLessThan(latest, 18, "Observe resume before playback reaches the selection end")
    }

    private func captureAudioState(_ app: XCUIApplication, name: String) {
        let graph = XCTAttachment(string: app.debugDescription)
        graph.name = name + " AX"
        graph.lifetime = .keepAlways
        add(graph)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
