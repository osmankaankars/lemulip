#if os(macOS)
import AppKit
import SwiftUI
import XCTest
import LemulipCore
@testable import Lemulip

/// Captures production panel content without posting input events. These stills
/// establish content/geometry only, not physical drag or animation quality.
final class NativePanelReviewTests: XCTestCase {
    @MainActor
    func testWheelReusesItsOwnPanelAndRetainsReviewContent() async throws {
        _ = NSApplication.shared
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("review.txt")
        try Data("A synthetic panel review file.\n".utf8).write(to: input)
        let existing = Set(NSApp.windows.map(ObjectIdentifier.init))
        let wheel = DragWheelController()
        var panel: NSPanel?
        defer { wheel.stop(); panel?.contentView = nil; panel?.close() }
        wheel.show(files: [input], mode: .actions)
        panel = try XCTUnwrap(NSApp.windows.first {
            !existing.contains(ObjectIdentifier($0)) && $0 is NSPanel
        } as? NSPanel)
        let visible = try XCTUnwrap(panel)
        XCTAssertTrue(visible.isVisible)
        XCTAssertFalse(visible.ignoresMouseEvents)
        let frame = visible.frame
        wheel.dismiss()
        XCTAssertFalse(visible.isVisible)
        wheel.show(files: [input], mode: .actions)
        XCTAssertTrue(visible.isVisible)
        XCTAssertEqual(visible.frame.size, frame.size)
        // Reopening an already visible wheel must finish, not replay, its fade.
        wheel.show(files: [input], mode: .actions)
        XCTAssertEqual(visible.alphaValue, 1)
        try await Task.sleep(nanoseconds: 160_000_000)
        try capture(visible, name: "native-wheel-actions", state: ["panelReused": true, "inputEventsSent": false])
    }

    @MainActor
    func testCompletedOutputUsesAndReusesTheNonactivatingResultPanel() async throws {
        _ = NSApplication.shared
        let keys = ["outputAlongsideOriginal", "completionPresentation", "revealWhenFinished"]
        let saved = keys.map { ($0, UserDefaults.standard.object(forKey: $0)) }
        let directory = try fixtureDirectory()
        let suite = "Lemulip.NativePanelReview." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let feedback = SelectionFeedback(defaults: defaults, player: ReviewSilentCuePlayer())
        let model = AppController(selectionFeedback: feedback)
        var panel: NSPanel?
        defer {
            model.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
            panel?.contentView = nil
            panel?.close()
            defaults.removePersistentDomain(forName: suite)
            for (key, value) in saved {
                if let value { UserDefaults.standard.set(value, forKey: key) }
                else { UserDefaults.standard.removeObject(forKey: key) }
            }
            try? FileManager.default.removeItem(at: directory)
        }
        model.outputAlongsideOriginal = true
        model.completionPresentation = .card
        let input = directory.appendingPathComponent("review-notes.md")
        try Data("# Review notes\n\nA short synthetic document.\n".utf8).write(to: input)
        let existing = Set(NSApp.windows.map(ObjectIdentifier.init))
        let originalKeyWindow = NSApp.keyWindow
        let operation = FileOperation(id: "convert.txt", title: "TXT", outputExtension: "txt")
        model.begin(operation, inputs: [input])
        try await waitFor("The native conversion must show its result panel") {
            model.completedCount == 1 && NSApp.windows.contains {
                !existing.contains(ObjectIdentifier($0)) && $0.isVisible
                    && $0.contentView is NSHostingView<ResultCardView>
            }
        }
        panel = try XCTUnwrap(NSApp.windows.first {
            !existing.contains(ObjectIdentifier($0)) && $0.contentView is NSHostingView<ResultCardView>
        } as? NSPanel)
        let visible = try XCTUnwrap(panel)
        XCTAssertTrue(visible.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(NSApp.keyWindow === originalKeyWindow, "Automatic completion must not take keyboard focus")
        XCTAssertFalse(visible.ignoresMouseEvents)
        XCTAssertEqual(model.completionResults.urls.count, 1)
        model.dismissResultCard()
        XCTAssertFalse(visible.isVisible)
        model.begin(operation, inputs: [input])
        try await waitFor("A later result must reuse the same panel") { model.completedCount == 2 && visible.isVisible }
        XCTAssertEqual(model.completionResults.urls.count, 1)
        XCTAssertTrue(NSApp.keyWindow === originalKeyWindow)
        try await Task.sleep(nanoseconds: 180_000_000)
        try capture(visible, name: "native-result-card", state: ["panelReused": true, "inputEventsSent": false])
    }

    private func fixtureDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Lemulip-Panel-Review-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    @MainActor
    private func waitFor(_ message: String, condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        guard condition() else { throw PanelReviewFailure(message) }
    }

    @MainActor
    private func capture(_ panel: NSPanel, name: String, state: [String: Any]) throws {
        guard let path = ProcessInfo.processInfo.environment["LEMULIP_EDITOR_REVIEW_DIR"], !path.isEmpty else { return }
        let view = try XCTUnwrap(panel.contentView)
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: directory.appendingPathComponent(name + ".png"), options: .withoutOverwriting)
        let record: [String: Any] = [
            "capture": "NSView.cacheDisplay of the production panel content after entry",
            "sourceCommit": ProcessInfo.processInfo.environment["LEMULIP_EDITOR_REVIEW_COMMIT"] ?? "local",
            "workflowRun": ProcessInfo.processInfo.environment["GITHUB_RUN_ID"] ?? "local",
            "theme": AppTheme.saved.rawValue, "state": state,
            "logicalWidth": Double(view.bounds.width), "logicalHeight": Double(view.bounds.height),
            "pixelWidth": bitmap.pixelsWide, "pixelHeight": bitmap.pixelsHigh,
            "windowBackingScale": Double(panel.backingScaleFactor), "resizedAfterCapture": false,
            "animationOrPhysicalDragReview": false,
            "input": "Synthetic local text document; no user files"
        ]
        try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent(name + ".json"), options: .withoutOverwriting)
    }
}

@MainActor
private final class ReviewSilentCuePlayer: SelectionCuePlaying {
    func play(completion: @escaping @MainActor () -> Void) -> Bool { false }
    func stop() {}
}

private struct PanelReviewFailure: Error { let message: String; init(_ message: String) { self.message = message } }
#endif
