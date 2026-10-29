#if os(macOS)
import AppKit
import XCTest
@testable import Lemulip

final class PanelAppearanceTests: XCTestCase {
    @MainActor
    func testEntryImmediatelyPreservesVisibilityGeometryAndInputEligibility() throws {
        try withPanel { panel, probe in
            let appearance = PanelAppearance(reduceMotion: { false }, reduceTransparency: { false })
            let frame = panel.frame
            var presentations = 0
            appearance.present(panel, kind: .wheel) {
                presentations += 1
                panel.orderFrontRegardless()
                XCTAssertTrue(panel.makeFirstResponder(probe))
            }
            // These checks run before yielding to an animation or completion.
            XCTAssertEqual(presentations, 1)
            XCTAssertTrue(panel.isVisible)
            XCTAssertEqual(panel.frame, frame)
            XCTAssertFalse(panel.ignoresMouseEvents)
            XCTAssertTrue(panel.firstResponder === probe)
            XCTAssertTrue(probe.hitTest(NSPoint(x: 20, y: 20)) === probe)
            XCTAssertGreaterThan(panel.alphaValue, 0.5, "The target must be visible from the first frame")
            XCTAssertLessThanOrEqual(panel.alphaValue, 1)
            appearance.dismiss()
            XCTAssertFalse(panel.isVisible)
            XCTAssertEqual(panel.alphaValue, 1)
        }
    }

    @MainActor
    func testRapidDismissAndReuseCannotReviveOrHideThePanel() async throws {
        let panel = makePanel()
        defer { panel.orderOut(nil); panel.close() }
        let appearance = PanelAppearance(reduceMotion: { false }, reduceTransparency: { false })
        let frame = panel.frame
        for _ in 0..<3 {
            appearance.present(panel, kind: .result) { panel.orderFrontRegardless() }
            XCTAssertTrue(panel.isVisible)
            appearance.dismiss()
            XCTAssertFalse(panel.isVisible)
            XCTAssertEqual(panel.alphaValue, 1)
        }
        appearance.present(panel, kind: .result) { panel.orderFrontRegardless() }
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertTrue(panel.isVisible, "An old entry must not hide the new presentation")
        XCTAssertEqual(panel.alphaValue, 1, accuracy: 0.001)
        XCTAssertEqual(panel.frame, frame)
        appearance.dismiss()
        try await Task.sleep(nanoseconds: 160_000_000)
        XCTAssertFalse(panel.isVisible, "A finished animation must not reopen a dismissed panel")
        XCTAssertEqual(panel.alphaValue, 1, accuracy: 0.001)
    }

    @MainActor
    func testVisiblePanelDoesNotRestartAnEntryOrChangeItsResponder() throws {
        try withPanel { panel, probe in
            let appearance = PanelAppearance(reduceMotion: { false }, reduceTransparency: { false })
            appearance.present(panel, kind: .wheel) {
                panel.orderFrontRegardless()
                XCTAssertTrue(panel.makeFirstResponder(probe))
            }
            appearance.present(panel, kind: .wheel) { panel.orderFrontRegardless() }
            XCTAssertTrue(panel.isVisible)
            XCTAssertEqual(panel.alphaValue, 1)
            XCTAssertTrue(panel.firstResponder === probe)
            appearance.dismiss()
        }
    }

    @MainActor
    func testAccessibilityPreferencesApplyOnEntryAndDuringPresentation() async throws {
        let panel = makePanel()
        defer { panel.orderOut(nil); panel.close() }
        let preferences = AppearancePreferences()
        let notifications = NotificationCenter()
        let appearance = PanelAppearance(reduceMotion: { preferences.reduceMotion },
            reduceTransparency: { preferences.reduceTransparency }, notifications: notifications)

        preferences.reduceMotion = true
        appearance.present(panel, kind: .wheel) { panel.orderFrontRegardless() }
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.alphaValue, 1)
        appearance.dismiss()

        preferences.reduceMotion = false
        preferences.reduceTransparency = true
        appearance.present(panel, kind: .result) { panel.orderFrontRegardless() }
        XCTAssertEqual(panel.alphaValue, 1)
        appearance.dismiss()

        preferences.reduceTransparency = false
        appearance.present(panel, kind: .result) { panel.orderFrontRegardless() }
        preferences.reduceMotion = true
        notifications.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.alphaValue, 1)
        try await Task.sleep(nanoseconds: 160_000_000)
        XCTAssertEqual(panel.alphaValue, 1)
        XCTAssertFalse(panel.ignoresMouseEvents)
        appearance.dismiss()

        preferences.reduceMotion = false
        appearance.present(panel, kind: .wheel) { panel.orderFrontRegardless() }
        preferences.reduceTransparency = true
        notifications.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.alphaValue, 1)
        try await Task.sleep(nanoseconds: 160_000_000)
        XCTAssertEqual(panel.alphaValue, 1)
        appearance.dismiss()
    }

    @MainActor
    private func makePanel() -> NSPanel {
        _ = NSApplication.shared
        let panel = NSPanel(contentRect: NSRect(x: 40, y: 40, width: 320, height: 180),
                            styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.title = "Lemulip Panel Appearance Test"
        panel.contentView = AppearanceInputProbe(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        return panel
    }

    @MainActor
    private func withPanel(_ body: (NSPanel, AppearanceInputProbe) throws -> Void) throws {
        let panel = makePanel()
        defer { panel.orderOut(nil); panel.close() }
        try body(panel, XCTUnwrap(panel.contentView as? AppearanceInputProbe))
    }
}

@MainActor
private final class AppearanceInputProbe: NSView {
    override var acceptsFirstResponder: Bool { true }
}

@MainActor
private final class AppearancePreferences {
    var reduceMotion = false
    var reduceTransparency = false
}
#endif
