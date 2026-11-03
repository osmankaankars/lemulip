#if os(macOS)
import AppKit
import XCTest
import LemulipCore
@testable import Lemulip

/// AppKit input-handler regression coverage, separate from external UI evidence.
final class VideoTimelineKeyboardTests: XCTestCase {
    @MainActor
    func testSelectionLettersIgnoreRepeatWhileOrdinaryKeysStillSelectTargets() throws {
        _ = NSApplication.shared
        let view = VideoTrimTimelineCanvas(thumbnails: [])
        view.selection = VideoTrimSelection(startSeconds: 2, endSeconds: 8, sourceDuration: 10)
        view.playheadSeconds = 4
        view.updateAccessibility()
        for (key, target) in [("s", "start"), ("e", "end"), ("p", "playhead")] {
            let before = view.accessibilityValue() as? String
            try keyDown(key, code: 0, repeating: true, in: view)
            XCTAssertEqual(view.accessibilityValue() as? String, before,
                           "A repeated selection letter must not select or announce a new target")
            try keyDown(key, code: 0, repeating: false, in: view)
            XCTAssertTrue((view.accessibilityValue() as? String)?.hasSuffix("Active control: \(target).") == true)
        }
        XCTAssertEqual(view.selection.startSeconds, 2)
        XCTAssertEqual(view.selection.endSeconds, 8)
        XCTAssertEqual(view.playheadSeconds, 4)
    }

    @MainActor
    func testArrowRepeatAdjustsTheSelectedBoundaryAndSpaceRepeatDoesNotTogglePlayback() throws {
        _ = NSApplication.shared
        let view = VideoTrimTimelineCanvas(thumbnails: [])
        view.selection = VideoTrimSelection(startSeconds: 2, endSeconds: 8, sourceDuration: 10)
        var changes: [VideoTrimSelection] = []
        var toggles = 0
        view.onChange = { changes.append($0) }
        view.onTogglePlayback = { toggles += 1 }
        try keyDown("s", code: 0, repeating: false, in: view)
        try keyDown("\u{F703}", code: 124, repeating: false, in: view)
        try keyDown("\u{F703}", code: 124, repeating: true, in: view)
        XCTAssertEqual(changes.count, 2)
        XCTAssertEqual(view.selection.startSeconds, 2.02, accuracy: 0.0001)
        XCTAssertEqual(view.selection.endSeconds, 8)
        try keyDown(" ", code: 49, repeating: false, in: view)
        try keyDown(" ", code: 49, repeating: true, in: view)
        XCTAssertEqual(toggles, 1)
    }

    @MainActor
    private func keyDown(_ characters: String, code: UInt16, repeating: Bool,
                         in view: VideoTrimTimelineCanvas) throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: repeating, keyCode: code))
        view.keyDown(with: event)
    }
}
#endif
