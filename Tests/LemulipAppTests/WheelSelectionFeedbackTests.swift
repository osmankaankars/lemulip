#if os(macOS)
import AppKit
import XCTest
import LemulipCore
@testable import Lemulip

/// Exercise the production wheel's AppKit input handlers and the actual feedback
/// coordinator. A spy proves routing, not audible playback or physical dragging.
final class WheelSelectionFeedbackTests: XCTestCase {
    @MainActor
    func testHoverTicksOnlyForANewSectorAndRespectsThePreference() throws {
        try withWheel { model, view, player, clock, count in
            XCTAssertFalse(model.selectionSoundsEnabled)
            try hover(1, count: count, view: view)
            XCTAssertEqual(player.starts, 0, "The default-off preference must stay silent")
            model.selectionSoundsEnabled = true
            try hover(1, count: count, view: view)
            XCTAssertEqual(player.starts, 0, "Enabling sound must not replay the current highlight")
            try hover(2, count: count, view: view)
            XCTAssertEqual(player.starts, 1, "Moving to a new wheel sector must request a cue")
            player.finish(); clock.time += 1
            try hover(2, count: count, view: view)
            XCTAssertEqual(player.starts, 1, "Mouse movement inside one sector must not chatter")
            try hover(nil, count: count, view: view)
            XCTAssertEqual(player.starts, 1, "The safe center must remain silent")
            try hover(2, count: count, view: view)
            XCTAssertEqual(player.starts, 2, "Re-entering a sector after leaving is a new selection")
            player.finish(); clock.time += 1
            model.selectionSoundsEnabled = false
            try hover(3, count: count, view: view)
            XCTAssertEqual(player.starts, 2)
            XCTAssertTrue(model.activity.isEmpty, "Highlighting must never start a file operation")
        }
    }

    @MainActor
    func testKeyboardAndAccessibilityNavigationUseTheSameCueWithoutExecuting() throws {
        try withWheel { model, view, player, clock, _ in
            model.selectionSoundsEnabled = true
            XCTAssertEqual(player.starts, 0, "Showing a wheel must not emit an unsolicited sound")
            try key(124, characters: "\u{F703}", view: view)
            XCTAssertEqual(player.starts, 1, "Right Arrow must tick when the highlighted option changes")
            player.finish(); clock.time += 1
            XCTAssertTrue(view.accessibilityPerformIncrement())
            XCTAssertEqual(player.starts, 2, "Accessible navigation must use the same feedback path")
            player.finish(); clock.time += 1
            XCTAssertTrue(view.accessibilityPerformDecrement())
            XCTAssertEqual(player.starts, 3)
            player.finish(); clock.time += 1
            try key(53, characters: "\u{1b}", view: view)
            XCTAssertEqual(player.starts, 3, "Escape must not emit a selection cue")
            XCTAssertFalse(try XCTUnwrap(view.window).isVisible)
            XCTAssertTrue(model.activity.isEmpty)
        }
    }

    @MainActor
    func testRapidSectorChangesNeverQueueAndReopeningStaysSilent() throws {
        try withWheel { model, view, player, clock, count in
            model.selectionSoundsEnabled = true
            try hover(1, count: count, view: view)
            try hover(2, count: count, view: view)
            XCTAssertEqual(player.starts, 1, "Overlapping highlights must be dropped")
            player.finish()
            clock.time += 0.1
            try hover(3, count: count, view: view)
            XCTAssertEqual(player.starts, 1, "Rapid movement must keep the existing rate limit")
            clock.time += 1
            try hover(3, count: count, view: view)
            XCTAssertEqual(player.starts, 1, "A dropped sound must never replay later")
            try hover(1, count: count, view: view)
            XCTAssertEqual(player.starts, 2)
            player.finish(); clock.time += 1
            model.showWheel()
            XCTAssertEqual(player.starts, 2, "Programmatic opening and initial selection are silent")
        }
    }

    @MainActor
    private func withWheel(_ body: (AppController, NSView, WheelCueSpy, WheelCueClock, Int) throws -> Void) throws {
        _ = NSApplication.shared
        let suite = "Lemulip.WheelSound.Tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let player = WheelCueSpy(), clock = WheelCueClock()
        let feedback = SelectionFeedback(defaults: defaults, player: player, now: { clock.time })
        let model = AppController(selectionFeedback: feedback)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let input = directory.appendingPathComponent("wheel.txt")
        let original = Data("Synthetic wheel input.\n".utf8)
        try original.write(to: input)
        let existing = Set(NSApp.windows.map(ObjectIdentifier.init))
        var panel: NSWindow?
        defer {
            model.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
            panel?.contentView = nil; panel?.close()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        model.files = [input]; model.mode = .actions
        model.showWheel()
        panel = NSApp.windows.first { !existing.contains(ObjectIdentifier($0)) && $0 is NSPanel }
        let view = try XCTUnwrap(panel?.contentView)
        let count = min(8, Catalog.operations(for: [input], mode: .actions).count)
        XCTAssertGreaterThanOrEqual(count, 4)
        try body(model, view, player, clock, count)
        XCTAssertEqual(try Data(contentsOf: input), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["wheel.txt"])
    }

    @MainActor
    private func hover(_ index: Int?, count: Int, view: NSView) throws {
        let point = index.map { WheelGeometry.position(index: $0, itemCount: count, radius: 119) }
            ?? WheelPoint(x: 0, y: 0)
        let window = try XCTUnwrap(view.window)
        let location = view.convert(NSPoint(x: 210 + point.x, y: 210 + point.y), to: nil)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: location,
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
        view.mouseMoved(with: event)
    }

    @MainActor
    private func key(_ code: UInt16, characters: String, view: NSView) throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: try XCTUnwrap(view.window).windowNumber, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
        view.keyDown(with: event)
    }
}

@MainActor
private final class WheelCueClock { var time: TimeInterval = 0 }
@MainActor
private final class WheelCueSpy: SelectionCuePlaying {
    var starts = 0
    private var completion: (@MainActor () -> Void)?
    func play(completion: @escaping @MainActor () -> Void) -> Bool {
        starts += 1; self.completion = completion; return true
    }
    func stop() { completion = nil }
    func finish() { let callback = completion; completion = nil; callback?() }
}
#endif
