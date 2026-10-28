#if os(macOS)
import AppKit
import XCTest
@testable import Lemulip

/// Real AppKit windows and the production screen-change handler are exercised
/// without starting global drag monitoring or changing the user's preferences.
/// This reproduces a disconnected display's stale coordinates; it is not a
/// substitute for physically disconnecting a monitor.
final class FloatingShelfWindowTests: XCTestCase {
    @MainActor
    func testRecoversShelfOutsideConnectedDisplays() async throws {
        try withShelves(count: 1) { controller, windows, screens in
            let window = windows[0]
            moveOffscreen(window, screens: screens)
            let size = window.frame.size
            XCTAssertFalse(hasReachableTitleBar(window.frame, screens: screens))
            let keyWindow = NSApp.keyWindow
            let wasActive = NSApp.isActive

            screenConfigurationChanged(controller)

            XCTAssertTrue(hasReachableTitleBar(window.frame, screens: screens),
                          "Screen changes must recover a shelf left on a disconnected display")
            XCTAssertEqual(window.frame.size, size)
            XCTAssertTrue(NSApp.keyWindow === keyWindow)
            XCTAssertEqual(NSApp.isActive, wasActive)
        }
    }

    @MainActor
    func testPreservesReachableShelf() async throws {
        try withShelves(count: 1) { controller, windows, screens in
            let window = windows[0]
            let screen = screens[0]
            window.setFrameOrigin(NSPoint(x: screen.minX + 40,
                                          y: screen.maxY - window.frame.height - 40))
            let original = window.frame
            XCTAssertTrue(hasReachableTitleBar(original, screens: screens))

            screenConfigurationChanged(controller)

            XCTAssertEqual(window.frame, original,
                           "A usable shelf placement must not jump after a display change")
        }
    }

    @MainActor
    func testRecoversMultipleShelvesIndependently() async throws {
        try withShelves(count: 3) { controller, windows, screens in
            let screen = screens[0]
            windows[0].setFrameOrigin(NSPoint(x: screen.minX + 30,
                                              y: screen.maxY - windows[0].frame.height - 30))
            let untouched = windows[0].frame
            moveOffscreen(windows[1], screens: screens)
            moveOffscreen(windows[2], screens: screens, offset: 12_000)
            XCTAssertFalse(hasReachableTitleBar(windows[1].frame, screens: screens))
            XCTAssertFalse(hasReachableTitleBar(windows[2].frame, screens: screens))

            screenConfigurationChanged(controller)

            XCTAssertEqual(windows[0].frame, untouched)
            for window in windows {
                XCTAssertTrue(hasReachableTitleBar(window.frame, screens: screens),
                              "Every retained shelf must remain reachable")
            }
        }
    }

    @MainActor
    func testDoesNotReopenHiddenShelf() async throws {
        try withShelves(count: 1) { controller, windows, screens in
            let window = windows[0]
            moveOffscreen(window, screens: screens)
            window.orderOut(nil)
            XCTAssertFalse(window.isVisible)

            screenConfigurationChanged(controller)

            XCTAssertFalse(window.isVisible, "Recovery must not present a hidden shelf")
        }
    }

    @MainActor
    func testDoesNotReopenClosedShelf() async throws {
        try withShelves(count: 1) { controller, windows, screens in
            let window = windows[0]
            moveOffscreen(window, screens: screens)
            window.close()
            XCTAssertFalse(window.isVisible)

            screenConfigurationChanged(controller)

            XCTAssertFalse(window.isVisible, "Recovery must not resurrect a closed shelf")
        }
    }

    @MainActor
    func testRecoveryIsIdempotent() async throws {
        try withShelves(count: 1) { controller, windows, screens in
            let window = windows[0]
            moveOffscreen(window, screens: screens)
            screenConfigurationChanged(controller)
            let recovered = window.frame
            XCTAssertTrue(hasReachableTitleBar(recovered, screens: screens))

            for _ in 0..<3 { screenConfigurationChanged(controller) }

            XCTAssertEqual(window.frame, recovered,
                           "Repeated display notifications must not keep moving the shelf")
        }
    }

    @MainActor
    private func withShelves(count: Int,
                            _ body: (AppController, [NSWindow], [CGRect]) throws -> Void) throws {
        let application = NSApplication.shared
        let screens = NSScreen.screens.map(\.visibleFrame)
        XCTAssertFalse(screens.isEmpty, "Native window tests require a WindowServer display")
        guard !screens.isEmpty else { return }
        let controller = AppController()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Lemulip-Shelf-Tests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        let input = directory.appendingPathComponent("sample.txt")
        var windows: [NSWindow] = []
        defer {
            // Detach the hosting views to release their controller reference.
            for window in windows { window.contentView = nil; window.close() }
            try? FileManager.default.removeItem(at: directory)
        }
        try Data("Shelf window test\n".utf8).write(to: input, options: .withoutOverwriting)
        for _ in 0..<count {
            let existing = Set(application.windows.map { ObjectIdentifier($0) })
            controller.showShelf([input])
            let window = try XCTUnwrap(application.windows.first {
                !existing.contains(ObjectIdentifier($0)) && $0 is NSPanel
            }, "showShelf must create a real AppKit panel")
            windows.append(window)
            XCTAssertTrue(window.isVisible)
        }
        try body(controller, windows, screens)
    }

    @MainActor
    private func screenConfigurationChanged(_ controller: AppController) {
        // The application registers this existing Objective-C selector at launch.
        // Invoke that exact handler without starting unrelated global drag polling.
        let selector = NSSelectorFromString("displayConfigurationChanged:")
        XCTAssertTrue(controller.responds(to: selector))
        _ = controller.perform(selector, with: NSNotification(
            name: NSApplication.didChangeScreenParametersNotification, object: NSApp))
    }

    @MainActor
    private func moveOffscreen(_ window: NSWindow, screens: [CGRect], offset: CGFloat = 10_000) {
        let right = screens.map(\.maxX).max() ?? 0
        let top = screens[0].maxY
        window.setFrameOrigin(NSPoint(x: right + offset,
                                      y: top - window.frame.height - 40))
    }

    private func hasReachableTitleBar(_ frame: CGRect, screens: [CGRect]) -> Bool {
        let height = min(CGFloat(28), frame.height)
        let titleBar = CGRect(x: frame.minX, y: frame.maxY - height,
                              width: frame.width, height: height)
        return screens.contains {
            let visible = titleBar.intersection($0)
            return !visible.isNull && visible.width >= min(CGFloat(160), titleBar.width)
                && visible.height >= min(CGFloat(20), height)
        }
    }
}
#endif
