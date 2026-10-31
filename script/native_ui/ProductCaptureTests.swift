import XCTest
import AppKit
import PDFKit
import CryptoKit

/// Capture real, normally launched application windows. Test fixtures are
/// synthetic documents/media; no UI is composited, repainted or enlarged.
@MainActor
final class ProductCaptureTests: XCTestCase {
    private var app: XCUIApplication?
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app?.terminate(); app = nil }

    private func launch(_ language: String = "en", theme: String = "orchard") -> XCUIApplication {
        app?.terminate()
        let value = XCUIApplication(url: ReviewConfiguration.application)
        app = value
        value.launchArguments = ["-language", language, "-theme", theme,
            "-wheelEnabled", "NO", "-selectionSoundsEnabled", "NO",
            "-completionPresentation", "quiet", "-outputAlongsideOriginal", "YES",
            "-NSQuitAlwaysKeepsWindows", "NO"]
        value.launch()
        XCTAssertTrue(value.windows.firstMatch.waitForExistence(timeout: 15))
        return value
    }

    private func fixture(_ name: String) -> URL { ReviewConfiguration.fixtures.appendingPathComponent(name) }

    private func operation(_ id: String, in app: XCUIApplication) {
        let search = app.textFields["workspace.operation-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.click(); search.typeKey("a", modifierFlags: [.command]); search.typeText(id)
        let button = app.buttons["operation." + id]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        XCTAssertTrue(button.isEnabled); button.click()
    }

    private func ready(_ app: XCUIApplication) {
        let button = app.buttons["editor.create-copy"]
        XCTAssertTrue(button.waitForExistence(timeout: 15))
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 20), .completed)
        XCTAssertTrue(button.isHittable)
    }

    private func capture(_ name: String, _ app: XCUIApplication, element: XCUIElement? = nil) throws {
        let target = element ?? app.windows.firstMatch
        XCTAssertTrue(target.exists)
        let frame = target.frame
        XCTAssertGreaterThan(frame.width, 0); XCTAssertGreaterThan(frame.height, 0)
        let screenshot = target.screenshot()
        let windowCapture = try nativeWindowPNG(app)
        let png = windowCapture ?? screenshot.pngRepresentation
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: png))
        let shot = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        shot.name = "capture-" + name; shot.lifetime = .keepAlways; add(shot)
        let record: [String: Any] = ["id": name, "capture": windowCapture == nil ? "XCTest screenshot of running application" : "macOS window capture without shadow",
            "width": bitmap.pixelsWide, "height": bitmap.pixelsHigh,
            "logicalWidth": frame.width, "logicalHeight": frame.height,
            "scaleX": Double(bitmap.pixelsWide) / frame.width,
            "scaleY": Double(bitmap.pixelsHigh) / frame.height,
            "sha256": SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined(),
            "syntheticInput": true, "uiRepainted": false, "resampled": false]
        let details = XCTAttachment(data: try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys, .prettyPrinted]),
                                    uniformTypeIdentifier: "public.json")
        details.name = "geometry-" + name; details.lifetime = .keepAlways; add(details)
        let graph = XCTAttachment(string: app.debugDescription)
        graph.name = "semantics-" + name; graph.lifetime = .keepAlways; add(graph)
    }

    private func nativeWindowPNG(_ app: XCUIApplication) throws -> Data? {
        guard let running = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "app.lemulip.NativeUIReview"
        }), let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
        let window = windows.first(where: {
            ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == running.processIdentifier &&
            ($0[kCGWindowName as String] as? String) == "Lemulip" &&
            ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 0
        }), let number = window[kCGWindowNumber as String] as? NSNumber else { return nil }
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: destination) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", "-l", number.stringValue, destination.path]
        try process.run()
        let deadline = Date().addingTimeInterval(8)
        while process.isRunning && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
        if process.isRunning { process.terminate(); return nil }
        guard process.terminationStatus == 0, let bytes = try? Data(contentsOf: destination),
              NSBitmapImageRep(data: bytes) != nil else { return nil }
        return bytes
    }

    func testWorkspaceThemesAndEmptySearch() throws {
        for theme in ["orchard", "pistachio", "lemonade"] {
            let app = launch(theme: theme)
            XCTAssertTrue(app.buttons["workspace.choose-files"].waitForExistence(timeout: 10))
            try capture("empty-" + theme, app)
            app.open(fixture("Morning light.jpg"))
            XCTAssertTrue(app.textFields["workspace.operation-search"].waitForExistence(timeout: 10))
            try capture("workspace-" + theme, app)
            let search = app.textFields["workspace.operation-search"]
            search.click(); search.typeText("no-such-format-123")
            XCTAssertTrue(app.staticTexts["No Matching Tools"].waitForExistence(timeout: 5))
            try capture("search-empty-" + theme, app)
            search.typeKey(.escape, modifierFlags: [])
            XCTAssertEqual(search.value as? String, "")
        }
    }

    func testTurkishWorkspaceAndSettings() throws {
        let app = launch("tr")
        app.open(fixture("Morning light.jpg"))
        XCTAssertTrue(app.textFields["workspace.operation-search"].waitForExistence(timeout: 10))
        try capture("workspace-tr", app)
        app.buttons["navigation.settings"].click()
        XCTAssertTrue(app.buttons["settings.selection-sounds.preview"].waitForExistence(timeout: 10))
        try capture("settings-tr", app)
    }

    func testPDFArrangementAndExport() throws {
        let app = launch()
        let input = fixture("Field notes.pdf")
        let before = try Data(contentsOf: input)
        app.open(input); operation("pdf.organize", in: app); ready(app)
        let field = app.textFields["pdf.position.0"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.click(); field.typeKey("a", modifierFlags: [.command]); field.typeText("3")
        field.typeKey(.return, modifierFlags: [])
        XCTAssertEqual(field.value as? String, "3")
        try capture("pdf-organize", app)
        let folder = input.deletingLastPathComponent()
        let existing = Set(try FileManager.default.contentsOfDirectory(atPath: folder.path))
        app.buttons["editor.create-copy"].click()
        let result = try output(in: folder, excluding: existing, ext: "pdf")
        let document = try XCTUnwrap(PDFDocument(url: result))
        XCTAssertEqual(document.pageCount, 4)
        XCTAssertTrue(try XCTUnwrap(document.page(at: 2)?.string).contains("A little room to explore"))
        XCTAssertEqual(try Data(contentsOf: input), before)
    }

    func testPageRangeErrorAndRecovery() throws {
        let app = launch("tr")
        app.open(fixture("Field notes.pdf")); operation("pdf.extract", in: app)
        let field = app.textFields.matching(NSPredicate(format: "label == %@", "Sayfalar ve aralıklar")).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.click(); field.typeKey("a", modifierFlags: [.command]); field.typeText("3-1")
        XCTAssertFalse(app.buttons["editor.create-copy"].isEnabled)
        try capture("pdf-invalid-range-tr", app)
        field.typeKey("a", modifierFlags: [.command]); field.typeText("1,3")
        ready(app)
        try capture("pdf-corrected-range-tr", app)
        app.typeKey(.escape, modifierFlags: [])
    }

    func testVideoCropReadyState() throws {
        let app = launch()
        app.open(fixture("Morning light.mov")); operation("media.crop", in: app); ready(app)
        try capture("crop-video", app)
    }

    func testAudioTrimReadyState() throws {
        let app = launch()
        app.open(fixture("Quiet afternoon.wav")); operation("media.trim", in: app); ready(app)
        try capture("trim-audio", app)
    }

    func testCompletedActivityFromRealConversion() throws {
        let app = launch()
        let input = fixture("Morning light.jpg")
        let original = try Data(contentsOf: input)
        let folder = input.deletingLastPathComponent()
        let existing = Set(try FileManager.default.contentsOfDirectory(atPath: folder.path))
        app.open(input); operation("convert.png", in: app)
        let result = try output(in: folder, excluding: existing, ext: "png")
        XCTAssertNotNil(NSImage(contentsOf: result))
        app.buttons["navigation.activity"].click()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value == %@", "1 Completed")).firstMatch.waitForExistence(timeout: 10))
        try capture("activity", app)
        XCTAssertEqual(try Data(contentsOf: input), original)
    }

    private func output(in folder: URL, excluding existing: Set<String>, ext: String) throws -> URL {
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            let now = Set(try FileManager.default.contentsOfDirectory(atPath: folder.path))
            if let name = now.subtracting(existing).first(where: { $0.hasSuffix("." + ext) }) {
                return folder.appendingPathComponent(name)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTFail("Expected a real completed output")
        throw NSError(domain: "ProductCapture", code: 1)
    }
}
