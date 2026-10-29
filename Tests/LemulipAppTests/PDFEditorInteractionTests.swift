#if os(macOS)
import AppKit
import CoreGraphics
import CoreText
import SwiftUI
import XCTest
import LemulipCore
@testable import Lemulip

/// These tests host the production SwiftUI editors in this process's own window.
/// Events go through NSApplication only after checking the target/key window.
/// They do not post global CGEvents, use cross-process accessibility automation, or establish
/// that a physical mouse drag works. Captures render the hosted view itself.
final class PDFEditorInteractionTests: XCTestCase {
    @MainActor private var dispatchedLifecycleEvents = 0

    @MainActor
    func testMergeNumberEntryReturnEscapeAndFocus() async throws {
        let inputs = try makeFiles(["10 Notes.pdf", "02 Report.pdf", "01 Cover.pdf"], pages: [1, 2, 1])
        let model = AppController()
        model.pendingOperation = FileOperation(id: "pdf.merge", title: "Merge PDF", outputExtension: "pdf")
        let editor = PDFMergeEditor()
        defer { editor.close() }
        let view = PDFMergeView(model: model, inputs: inputs, editor: editor)
        try await withWindow(view, size: NSSize(width: 820, height: 660), name: "merge") { window, host in
            try await waitFor("The actual merge view must finish opening its inputs") { editor.isReady }
            try await waitFor("Three visible native position fields numbered 1 through 3 must be rendered") { positionFields(in: host).count == 3 }
            try await waitFor("The visible synthetic PDF covers must load") { editor.thumbnails.count == 3 }
            try capture(host, window: window, name: "merge-initial", state: ["order": editor.documents.map(\.inputIndex)])

            let first = try positionField(atOutputPosition: 1, in: host)
            try await enter("3", in: first, window: window)
            try await press("\r", code: 36, in: window)
            try await waitFor("Return must move the file through the production number field") {
                editor.documents.map(\.inputIndex) == [1, 2, 0]
            }
            XCTAssertEqual(model.pendingOperation?.id, "pdf.merge", "Return must not submit or close the editor")
            XCTAssertTrue(model.activity.isEmpty, "Number entry must not start an export")
            try await press("\u{F700}", code: 126, in: window)
            try await waitFor("Up must navigate the list immediately after Return") { editor.selectedDocuments == [2] }
            try capture(host, window: window, name: "merge-after-return", state: [
                "order": editor.documents.map(\.inputIndex), "selected": editor.selectedDocuments.sorted()
            ])

            let moved = try positionField(atOutputPosition: 3, in: host)
            try await enter("99", in: moved, window: window)
            try await press("\r", code: 36, in: window)
            try await waitFor("An invalid number must remain in the active field") {
                moved.isFocused && (window.firstResponder as? NSTextView)?.string == "99"
            }
            XCTAssertEqual(editor.documents.map(\.inputIndex), [1, 2, 0])
            try capture(host, window: window, name: "merge-invalid-position", state: ["order": editor.documents.map(\.inputIndex)])
            try await press("\u{1B}", code: 53, in: window)
            try await waitFor("Escape must discard the draft and restore the displayed position") {
                !moved.isFocused && moved.value == "3" && (window.firstResponder as? NSTextView)?.isFieldEditor != true
            }
            XCTAssertEqual(model.pendingOperation?.id, "pdf.merge", "Escape must not close the editor while editing a number")
            XCTAssertEqual(editor.documents.map(\.inputIndex), [1, 2, 0])
            XCTAssertTrue(model.activity.isEmpty)
            try await press("\u{F700}", code: 126, in: window)
            try await waitFor("Up must navigate the list immediately after Escape") { editor.selectedDocuments == [2] }

            let previous = try positionField(atOutputPosition: 1, in: host)
            let next = try positionField(atOutputPosition: 2, in: host)
            try await enter("3", in: previous, window: window)
            try await enter("1", in: next, window: window)
            try await waitFor("Changing fields must cancel the previous draft without stealing focus") {
                previous.value == "1" && !previous.isFocused && next.isFocused
            }
            try await press("\r", code: 36, in: window)
            try await waitFor("The newly focused field must accept its own edit") {
                editor.documents.map(\.inputIndex) == [2, 1, 0]
            }
            XCTAssertEqual(model.pendingOperation?.id, "pdf.merge")
            XCTAssertTrue(model.activity.isEmpty)
            try capture(host, window: window, name: "merge-after-field-switch", state: ["order": editor.documents.map(\.inputIndex)])
            try await press("\u{1B}", code: 53, in: window)
            try await waitFor("Escape from the list must cancel the pending merge after number editing ends") {
                model.pendingOperation == nil
            }
            XCTAssertTrue(model.activity.isEmpty)
        }
    }

    @MainActor
    func testOrganizerNumberEntryReturnEscapeAndFocus() async throws {
        let inputs = try makeFiles(["Review Pages.pdf"], pages: [4])
        let model = AppController()
        model.pendingOperation = FileOperation(id: "pdf.organize", title: "Organize PDF", outputExtension: "pdf")
        let editor = PDFOrganizeEditor()
        defer { editor.close() }
        let view = PDFOrganizeView(model: model, inputs: inputs, editor: editor)
        try await withWindow(view, size: NSSize(width: 860, height: 680), name: "organize") { window, host in
            try await waitFor("The actual organize view must finish opening the PDF") { editor.source != nil }
            try await waitFor("Four visible native page position fields numbered 1 through 4 must be rendered") { positionFields(in: host).count == 4 }
            try await waitFor("The visible synthetic page previews must load") { editor.thumbnails.count == 4 }
            try capture(host, window: window, name: "organize-initial", state: ["order": editor.pages.map(\.sourceIndex)])

            let first = try positionField(atOutputPosition: 1, in: host)
            try await enter("4", in: first, window: window)
            try await press("\r", code: 36, in: window)
            try await waitFor("Return must move the page through the production number field") {
                editor.pages.map(\.sourceIndex) == [1, 2, 3, 0]
            }
            XCTAssertEqual(model.pendingOperation?.id, "pdf.organize")
            XCTAssertTrue(model.activity.isEmpty, "Number entry must not start an export")
            try await press("\u{F702}", code: 123, in: window)
            try await waitFor("Left must navigate the grid immediately after Return") { editor.selectedPages == [3] }
            try capture(host, window: window, name: "organize-after-return", state: [
                "order": editor.pages.map(\.sourceIndex), "selected": editor.selectedPages.sorted()
            ])

            let second = try positionField(atOutputPosition: 2, in: host)
            try await enter("1", in: second, window: window)
            try await press("\u{1B}", code: 53, in: window)
            try await waitFor("Escape must cancel a valid but unsubmitted page position") {
                !second.isFocused && second.value == "2" && (window.firstResponder as? NSTextView)?.isFieldEditor != true
            }
            XCTAssertEqual(editor.pages.map(\.sourceIndex), [1, 2, 3, 0])
            XCTAssertEqual(model.pendingOperation?.id, "pdf.organize", "Escape must not close the editor")
            XCTAssertTrue(model.activity.isEmpty)
            try await press("\u{F702}", code: 123, in: window)
            try await waitFor("Left must navigate the grid immediately after Escape") { editor.selectedPages == [1] }
            try capture(host, window: window, name: "organize-after-escape", state: [
                "order": editor.pages.map(\.sourceIndex), "selected": editor.selectedPages.sorted()
            ])
            try await press("\u{1B}", code: 53, in: window)
            try await waitFor("Escape from the grid must cancel the pending organizer after number editing ends") {
                model.pendingOperation == nil
            }
            XCTAssertTrue(model.activity.isEmpty)
        }
    }

    @MainActor
    func testMergeDragPointerProbe() async throws { try await reviewMergePointer(cancel: false) }

    @MainActor
    func testOrganizerDragPointerProbe() async throws { try await reviewOrganizerPointer(cancel: false) }

    @MainActor
    func testMergeVisibleCancelPointerProbe() async throws { try await reviewMergePointer(cancel: true) }

    @MainActor
    func testOrganizerVisibleCancelPointerProbe() async throws { try await reviewOrganizerPointer(cancel: true) }

    @MainActor
    private func pointerModel() throws -> AppController {
        let environment = ProcessInfo.processInfo.environment
        guard environment["LEMULIP_PDF_POINTER_PROBE"] == "1",
              environment["LEMULIP_PDF_POINTER_WATCHDOG"] == "45" else {
            throw XCTSkip("Run script/review_pdf_pointer.py for the bounded own-window pointer diagnostic")
        }
        let model = AppController()
        guard model.language == "en", model.theme == .orchardNight else {
            throw InteractionFailure("The observed-pixel pointer fixture requires English and Orchard Night")
        }
        return model
    }

    @MainActor
    private func reviewMergePointer(cancel: Bool) async throws {
        let model = try pointerModel()
        let inputs = try makeFiles(["10 Notes.pdf", "02 Report.pdf", "01 Cover.pdf"], pages: [1, 2, 1])
        model.pendingOperation = FileOperation(id: "pdf.merge", title: "Merge PDF", outputExtension: "pdf")
        let editor = PDFMergeEditor()
        defer { editor.close() }
        let name = cancel ? "merge-pointer-cancel" : "merge-pointer-drag"
        try await withWindow(PDFMergeView(model: model, inputs: inputs, editor: editor),
                             size: NSSize(width: 820, height: 660), name: name) { window, host in
            try await waitFor("The merge pointer fixture must render all three real fields and covers") {
                editor.isReady && positionFields(in: host).count == 3 && editor.thumbnails.count == 3
            }
            let first = try positionField(atOutputPosition: 1, in: host)
            let third = try positionField(atOutputPosition: 3, in: host)
            let firstFrame = first.native.convert(first.native.bounds, to: nil)
            let thirdFrame = third.native.convert(third.native.bounds, to: nil)
            let observe: @MainActor () -> PointerObservation = {
                PointerObservation(dragging: editor.isDragging, target: editor.dropPosition?.inputIndex,
                    after: editor.dropPosition?.after, order: editor.documents.map(\.inputIndex),
                    selected: editor.selectedDocuments.sorted(), pending: model.pendingOperation?.id,
                    activityCount: model.activity.count)
            }
            if cancel {
                try await enter("3", in: first, window: window)
                let target = try cancelTarget(in: host, window: window, fallback: NSPoint(x: 663, y: 30))
                try capture(host, window: window, name: name + "-before", state: observe().record)
                _ = try await pointerSequence(from: target.point, to: target.point, drag: false,
                    host: host, window: window, name: name, locator: target.locator, observe: observe)
                try await requireFirstCancelClick(
                    "Clicking the visible Cancel button must discard the pending merge while a number draft is active",
                    target: target, host: host, window: window, name: name, observe: observe)
            } else {
                // Selection is fixture setup, not a claim that Command-click was tested.
                editor.select(2, modifiers: .command)
                XCTAssertEqual(editor.selectedDocuments, [0, 2])
                try capture(host, window: window, name: name + "-before", state: observe().record)
                let result = try await pointerSequence(
                    from: NSPoint(x: 769, y: firstFrame.midY),
                    to: NSPoint(x: 769, y: thirdFrame.midY + 25), drag: true,
                    host: host, window: window, name: name,
                    locator: "Handle center x769 measured in the 820x660 production capture; row y from actual native fields; upper-quarter destination is 25pt above the third field center",
                    observe: observe)
                try await waitFor("The real merge drop must produce [1,0,2]; local event delivery alone does not prove a native dragging session") {
                    editor.documents.map(\.inputIndex) == [1, 0, 2]
                }
                XCTAssertTrue(result.sawDragToken, "Production onDrag must create the real token")
                XCTAssertTrue(result.sawIntendedCue, "Production onDrop must show the insertion cue before selected target 2")
                XCTAssertEqual(editor.selectedDocuments, [0, 2])
                XCTAssertEqual(model.pendingOperation?.id, "pdf.merge")
            }
            XCTAssertTrue(model.activity.isEmpty)
            try capture(host, window: window, name: name + "-after", state: observe().record)
        }
    }

    @MainActor
    private func reviewOrganizerPointer(cancel: Bool) async throws {
        let model = try pointerModel()
        let inputs = try makeFiles(["Review Pages.pdf"], pages: [4])
        model.pendingOperation = FileOperation(id: "pdf.organize", title: "Organize PDF", outputExtension: "pdf")
        let editor = PDFOrganizeEditor()
        defer { editor.close() }
        let name = cancel ? "organize-pointer-cancel" : "organize-pointer-drag"
        try await withWindow(PDFOrganizeView(model: model, inputs: inputs, editor: editor),
                             size: NSSize(width: 860, height: 680), name: name) { window, host in
            try await waitFor("The organizer pointer fixture must render all four real fields and previews") {
                editor.source != nil && positionFields(in: host).count == 4 && editor.thumbnails.count == 4
            }
            let first = try positionField(atOutputPosition: 1, in: host)
            let third = try positionField(atOutputPosition: 3, in: host)
            let firstFrame = first.native.convert(first.native.bounds, to: nil)
            let thirdFrame = third.native.convert(third.native.bounds, to: nil)
            let observe: @MainActor () -> PointerObservation = {
                PointerObservation(dragging: editor.isDragging, target: editor.dropPosition?.sourceIndex,
                    after: editor.dropPosition?.after, order: editor.pages.map(\.sourceIndex),
                    selected: editor.selectedPages.sorted(), pending: model.pendingOperation?.id,
                    activityCount: model.activity.count)
            }
            if cancel {
                try await enter("4", in: first, window: window)
                let target = try cancelTarget(in: host, window: window, fallback: NSPoint(x: 703, y: 30))
                try capture(host, window: window, name: name + "-before", state: observe().record)
                _ = try await pointerSequence(from: target.point, to: target.point, drag: false,
                    host: host, window: window, name: name, locator: target.locator, observe: observe)
                try await requireFirstCancelClick(
                    "Clicking the visible Cancel button must discard the pending organizer while a number draft is active",
                    target: target, host: host, window: window, name: name, observe: observe)
            } else {
                editor.select(2, modifiers: .command)
                XCTAssertEqual(editor.selectedPages, [0, 2])
                try capture(host, window: window, name: name + "-before", state: observe().record)
                let result = try await pointerSequence(
                    from: NSPoint(x: firstFrame.minX + 121, y: firstFrame.midY),
                    to: NSPoint(x: thirdFrame.minX - 26, y: thirdFrame.midY), drag: true,
                    host: host, window: window, name: name,
                    locator: "Handle center x192 and destination x458 measured in the 860x680 production capture; actual field frames supply the offsets +121/-26 and shared y",
                    observe: observe)
                try await waitFor("The real organizer drop must produce [1,0,2,3]; local event delivery alone does not prove a native dragging session") {
                    editor.pages.map(\.sourceIndex) == [1, 0, 2, 3]
                }
                XCTAssertTrue(result.sawDragToken, "Production onDrag must create the real token")
                XCTAssertTrue(result.sawIntendedCue, "Production onDrop must show the insertion cue before selected target 2")
                XCTAssertEqual(editor.selectedPages, [0, 2])
                XCTAssertEqual(model.pendingOperation?.id, "pdf.organize")
            }
            XCTAssertTrue(model.activity.isEmpty)
            try capture(host, window: window, name: name + "-after", state: observe().record)
        }
    }

    @MainActor
    private func withWindow<Content: View>(_ view: Content, size: NSSize, name: String,
        body: (NSWindow, NSHostingView<Content>) async throws -> Void) async throws {
        let application = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first, "Native interaction tests require a WindowServer display")
        let policy = application.activationPolicy()
        XCTAssertTrue(application.setActivationPolicy(.regular))
        defer { _ = application.setActivationPolicy(policy) }
        if !NSRunningApplication.current.isFinishedLaunching {
            guard application.delegate == nil else {
                throw InteractionFailure("The review host must not launch a production application delegate")
            }
            guard UserDefaults.standard.object(forKey: "NSOpen") == nil else {
                throw InteractionFailure("The synthetic review host requires no NSOpen launch files")
            }
            // XCTest creates NSApplication without running its normal app loop.
            // Finish its public launch lifecycle before requesting activation.
            application.finishLaunching()
        }
        dispatchedLifecycleEvents = 0
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Lemulip PDF Interaction Review"
        window.appearance = NSAppearance(named: AppTheme.saved.appearanceName)
        let host = NSHostingView(rootView: view)
        window.contentView = host
        window.setContentSize(size)
        window.setFrameTopLeftPoint(NSPoint(x: screen.visibleFrame.minX + 30, y: screen.visibleFrame.maxY - 30))
        defer {
            window.contentView = nil
            window.close()
        }
        application.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        do {
            try await waitFor("The synthetic review window must become key before receiving events", servicing: window) {
                window.isVisible && window.isKeyWindow && application.keyWindow === window
            }
            try await body(window, host)
        } catch {
            try? capture(host, window: window, name: name + "-failure", state: ["failure": String(describing: error)])
            throw error
        }
    }

    @MainActor
    private static func accessibilityElements(in view: NSView) -> [any NSAccessibilityProtocol] {
        var pending: [any NSAccessibilityProtocol] = [view]
        var visited = Set<ObjectIdentifier>()
        var result: [any NSAccessibilityProtocol] = []
        while let element = pending.popLast(), result.count < 512 {
            guard visited.insert(ObjectIdentifier(element as AnyObject)).inserted else { continue }
            result.append(element)
            pending.append(contentsOf: (element.accessibilityChildren() ?? []).compactMap { $0 as? NSAccessibilityProtocol })
            pending.append(contentsOf: (element.accessibilityChildrenInNavigationOrder() ?? []).compactMap { $0 as? NSAccessibilityProtocol })
        }
        return result
    }

    @MainActor
    private static func accessibilityChildMetadata(_ child: Any) -> [String: Any] {
        // Preserve evidence before filtering for the full protocol: SwiftUI can
        // provide virtual nodes with only a base or role-specific conformance.
        ["class": String(reflecting: type(of: child)),
         "fullProtocol": child is NSAccessibilityProtocol,
         "baseProtocol": child is NSAccessibilityElementProtocol,
         "groupProtocol": child is NSAccessibilityGroup,
         "staticTextProtocol": child is NSAccessibilityStaticText,
         "buttonProtocol": child is NSAccessibilityButton]
    }

    @MainActor
    private func positionFields(in view: NSView) -> [Int: PositionControl] {
        // Native CI captures establish that these are real editable NSTextFields,
        // while SwiftUI keeps their semantic identifiers off the native controls.
        // Before typing, require every field to display one unique output position.
        let native = nativeTextFields(in: view).filter(\.isEditable)
        var result: [Int: PositionControl] = [:]
        for field in native {
            let control = PositionControl(native: field, host: view)
            guard control.isEligible, let position = Int(field.stringValue),
                  field.stringValue == String(position), position >= 1, position <= native.count,
                  result[position] == nil else { return [:] }
            result[position] = control
        }
        return result
    }

    @MainActor
    private func positionField(atOutputPosition position: Int, in view: NSView) throws -> PositionControl {
        try XCTUnwrap(positionFields(in: view)[position],
                      "The visible output position must identify exactly one eligible native field")
    }

    @MainActor
    private struct PositionControl {
        let native: NSTextField
        let host: NSView
        var isEligible: Bool {
            guard let window = host.window, native.window === window,
                  native.isDescendant(of: host), !native.isHiddenOrHasHiddenAncestor,
                  native.isEditable, native.isEnabled, native.acceptsFirstResponder else { return false }
            let frame = host.convert(native.bounds, from: native)
            return frame.width > 0 && frame.height > 0 && host.visibleRect.contains(frame)
                && native.visibleRect.contains(native.bounds)
        }
        var isFocused: Bool {
            guard isEligible, let editor = native.currentEditor() else { return false }
            return host.window?.firstResponder === editor
        }
        var value: String { isEligible ? native.stringValue : "" }
    }

    @MainActor
    private func enter(_ value: String, in field: PositionControl, window: NSWindow) async throws {
        let initialValue = field.value
        guard field.host.window === window, NSApp.keyWindow === window, window.isKeyWindow,
              field.isEligible else {
            throw InteractionFailure("Refusing to focus a control outside the synthetic key window")
        }
        // AppKit's documented first-responder route focuses the actual production
        // field. It neither assigns the draft nor calls a model/delegate action.
        guard window.makeFirstResponder(field.native) else {
            throw InteractionFailure("The native position field refused first-responder status")
        }
        try await Task.sleep(nanoseconds: 20_000_000)
        try await waitFor("The native text editor must receive focus") {
            field.isFocused && (window.firstResponder as? NSTextView)?.isFieldEditor == true
        }
        let textEditor = try XCTUnwrap(window.firstResponder as? NSTextView)
        textEditor.selectAll(nil)
        let keyCodes: [Character: UInt16] = ["0": 29, "1": 18, "2": 19, "3": 20, "4": 21, "9": 25]
        for character in value {
            try await press(String(character), code: try XCTUnwrap(keyCodes[character]), in: window)
        }
        do {
            try await waitFor("Native key events must update the text editor") { textEditor.string == value }
        } catch {
            throw InteractionFailure("Native key events must update the text editor: expected \(value.debugDescription), initial \(initialValue.debugDescription), actual \(textEditor.string.debugDescription), native value \(field.native.stringValue.debugDescription), target field focused \(field.isFocused), own window key \(NSApp.keyWindow === window && window.isKeyWindow)")
        }
    }

    @MainActor
    private func press(_ characters: String, code: UInt16, in window: NSWindow) async throws {
        guard NSApp.keyWindow === window, window.isKeyWindow else {
            throw InteractionFailure("Refusing to send an event outside the synthetic key window")
        }
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = try XCTUnwrap(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: characters, charactersIgnoringModifiers: characters,
                isARepeat: false, keyCode: code))
            guard event.window === window else { throw InteractionFailure("The constructed event has the wrong window") }
            NSApp.sendEvent(event)
        }
        // Let AppKit and SwiftUI finish this event transaction before the next key.
        // Each assertion still waits for its specific observable result.
        try await Task.sleep(nanoseconds: 20_000_000)
    }

    private struct PointerObservation: Equatable {
        let dragging: Bool
        let target: Int?
        let after: Bool?
        let order: [Int]
        let selected: [Int]
        let pending: String?
        let activityCount: Int
        var record: [String: Any] {
            ["productionDragTokenPresent": dragging, "dropTarget": target ?? -1,
             "dropSide": after.map { $0 ? "after" : "before" } ?? "none",
             "order": order, "selected": selected, "pendingOperation": pending ?? "none",
             "activityCount": activityCount]
        }
    }

    @MainActor
    private final class PointerProgress {
        var nextEvent = 0
        var events: [[String: Any]] = []
        var observations: [[String: Any]] = []
        var lastObservation: PointerObservation?
        var sawDragToken = false
        var sawIntendedCue = false
        var capturedCue = false
        var finishedPostingAt: Date?
        var outerDispatchCount = 0
        var error: Error?
    }

    @MainActor
    private func cancelTarget(in host: NSView, window: NSWindow, fallback: NSPoint) throws -> (point: NSPoint, locator: String, view: NSView) {
        let matches = nativeButtons(in: host).filter { $0.title == "Cancel" }
        guard matches.count <= 1 else { throw InteractionFailure("The visible Cancel button is ambiguous") }
        var point = fallback
        var locator = "Visible Cancel center measured from the exact 69b03 production capture; no native NSButton title was available"
        if let button = matches.first {
            let frame = button.convert(button.bounds, to: nil)
            guard button.window === window, button.isDescendant(of: host), button.isEnabled,
                  !button.isHiddenOrHasHiddenAncestor, button.visibleRect.contains(button.bounds),
                  host.convert(host.bounds, to: nil).contains(frame), frame.width > 0, frame.height > 0 else {
                throw InteractionFailure("The native Cancel button is not eligible in this own-window fixture")
            }
            point = NSPoint(x: frame.midX, y: frame.midY)
            locator = "Unique visible enabled native NSButton titled Cancel; actual frame " + NSStringFromRect(frame)
        }
        let container = try XCTUnwrap(host.superview, "The Cancel target must remain attached to its own window")
        guard host.window === window, window.isVisible, window.isKeyWindow, NSApp.keyWindow === window,
              host.convert(host.bounds, to: nil).contains(point),
              let hit = host.hitTest(container.convert(point, from: nil)),
              hit.window === window, hit === host || hit.isDescendant(of: host),
              !hit.isHiddenOrHasHiddenAncestor else {
            throw InteractionFailure("The visible Cancel target must hit this own key window")
        }
        return (point, locator, hit)
    }

    @MainActor
    private func requireFirstCancelClick(_ requirement: String,
        target: (point: NSPoint, locator: String, view: NSView),
        host: NSView, window: NSWindow, name: String,
        observe: @escaping @MainActor () -> PointerObservation) async throws {
        do {
            try await waitFor(requirement) { observe().pending == nil }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Preserve the failed first click before any further input. A later
            // successful click is diagnostic only and must never pass this test.
            let firstState = observe()
            try capture(host, window: window, name: name + "-after-first-click", state: firstState.record)
            var record: [String: Any] = [
                "firstClickRequirementPassed": false, "firstClickState": firstState.record,
                "secondClickSequenceStarted": false, "sameTargetRevalidated": false
            ]
            do {
                if observe().pending != nil {
                    let repeated = try cancelTarget(in: host, window: window, fallback: target.point)
                    guard repeated.point == target.point, repeated.view === target.view,
                          observe().pending == firstState.pending else {
                        throw InteractionFailure("The second Cancel click must target the same visible button and pending operation")
                    }
                    record["sameTargetRevalidated"] = true
                    record["secondClickSequenceStarted"] = true
                    _ = try await pointerSequence(from: repeated.point, to: repeated.point, drag: false,
                        host: host, window: window, name: name + "-second-click",
                        locator: repeated.locator + "; same native hit view as the first click", observe: observe)
                    try await waitFor("The diagnostic second Cancel click did not clear the pending operation") {
                        observe().pending == nil
                    }
                } else {
                    record["secondClickSkipped"] = "The pending operation cleared after the first-click deadline; no further input was sent"
                }
            } catch {
                record["secondClickError"] = String(describing: error)
            }
            let finalState = observe()
            record["pendingClearedAfterDiagnostic"] = finalState.pending == nil
            record["finalState"] = finalState.record
            try capture(host, window: window, name: name + "-after-second-click", state: record)
            throw InteractionFailure(requirement + "; first-click requirement failed; pending cleared after diagnostic: \(finalState.pending == nil)")
        }
    }

    @MainActor
    private func pointerSequence(from start: NSPoint, to end: NSPoint, drag: Bool,
        host: NSView, window: NSWindow, name: String, locator: String,
        observe: @escaping @MainActor () -> PointerObservation) async throws -> PointerProgress {
        guard let path = ProcessInfo.processInfo.environment["LEMULIP_PDF_REVIEW_DIR"], !path.isEmpty else {
            throw InteractionFailure("Pointer diagnostics require an artifact directory before sending events")
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var sequence: [(NSEvent.EventType, NSPoint)] = [(.leftMouseDown, start)]
        if drag {
            for step in 1...12 {
                let fraction = CGFloat(step) / 12
                sequence.append((.leftMouseDragged, NSPoint(x: start.x + (end.x - start.x) * fraction,
                                                       y: start.y + (end.y - start.y) * fraction)))
            }
            // Let the actual drop target keep its insertion cue visible before release.
            for _ in 0..<8 { sequence.append((.leftMouseDragged, end)) }
        }
        sequence.append((.leftMouseUp, end))
        let plan = sequence
        let frame = host.convert(host.bounds, to: nil)
        guard frame.origin == .zero,
              frame.size == (name.hasPrefix("merge") ? NSSize(width: 820, height: 660) : NSSize(width: 860, height: 680)),
              host.window === window, window.isVisible, window.isKeyWindow, NSApp.keyWindow === window else {
            throw InteractionFailure("The observed-pixel calibration does not match this visible own key window")
        }
        let container = try XCTUnwrap(host.superview, "The hosted view must remain attached to its native window hierarchy")
        let hits: [[String: Any]] = try plan.map { type, point in
            // NSView.hitTest takes a point in its superview's coordinates.
            guard frame.contains(point), let hit = host.hitTest(container.convert(point, from: nil)),
                  hit.window === window, hit === host || hit.isDescendant(of: host) else {
                throw InteractionFailure("A calibrated pointer point does not hit this synthetic window's view hierarchy")
            }
            return ["type": String(describing: type), "x": Double(point.x), "y": Double(point.y),
                    "hitClass": String(reflecting: Swift.type(of: hit)), "hitBelongsToOwnHost": true,
                    "hitFrameInWindow": NSStringFromRect(hit.convert(hit.bounds, to: nil))]
        }
        let progress = PointerProgress()
        let environment = ProcessInfo.processInfo.environment
        let save: @MainActor (String) throws -> Void = { phase in
            let record: [String: Any] = [
                "scenario": name, "phase": phase,
                "sourceCommit": environment["LEMULIP_PDF_REVIEW_COMMIT"] ?? "local",
                "runID": environment["GITHUB_RUN_ID"] ?? "local",
                "method": "Public NSEvents queued only in this XCTest process's synthetic window",
                "hardwareMouseVerified": false, "globalInputPosted": false, "testDirectlyCalledModelReorderOrDropDelegate": false,
                "selectionSetup": "Disjoint selection 0 and 2 is model fixture setup only in drag cases",
                "calibrationHead": "69b03c93044da330ccc73e2599f06d222b740016",
                "calibrationArtifactSHA256": "8e9564309fd7a858debd6020f397ad9ca435fe4cf0bae217a1ecb0ba049baee8",
                "calibrationCaptures": ["merge-initial.png", "organize-initial.png"],
                "locator": locator, "windowNumber": window.windowNumber,
                "logicalFrame": NSStringFromRect(frame), "plannedPointsAndHitTests": hits,
                "eventsPosted": progress.events, "outerLoopDispatchCount": progress.outerDispatchCount,
                "productionObservations": progress.observations,
                "sawProductionDragToken": progress.sawDragToken,
                "sawInsertionCueBeforeSelectedTarget2": progress.sawIntendedCue,
                "error": progress.error.map { String(describing: $0) } ?? "none"
            ]
            try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
                .write(to: directory.appendingPathComponent(name + "-progress.json"), options: .atomic)
        }
        let sample: @MainActor () throws -> Void = {
            let current = observe()
            progress.sawDragToken = progress.sawDragToken || current.dragging
            progress.sawIntendedCue = progress.sawIntendedCue || (current.target == 2 && current.after == false)
            if current != progress.lastObservation {
                progress.lastObservation = current
                progress.observations.append(current.record)
                try save("observed-production-state")
            }
            if drag, progress.sawIntendedCue, !progress.capturedCue {
                progress.capturedCue = true
                try self.capture(host, window: window, name: name + "-insertion-cue", state: current.record)
            }
        }
        try sample()
        try save("ready-before-input")
        let eventNumbers = Set(4200..<(4200 + plan.count))
        let timer = Timer(timeInterval: 0.04, repeats: true) { timer in
            MainActor.assumeIsolated {
                do {
                    try sample()
                    guard NSApp.keyWindow === window, window.isKeyWindow, host.window === window else {
                        throw InteractionFailure("Refusing to post pointer input after the own key-window guard changed")
                    }
                    let index = progress.nextEvent
                    guard index < plan.count else { timer.invalidate(); return }
                    let (type, point) = plan[index]
                    let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                        context: nil, eventNumber: 4200 + index, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1))
                    guard event.window === window else { throw InteractionFailure("Constructed pointer event has a different target window") }
                    NSApp.postEvent(event, atStart: false)
                    progress.events.append(["type": String(describing: type), "eventNumber": event.eventNumber,
                                            "x": Double(point.x), "y": Double(point.y)])
                    progress.nextEvent += 1
                    if progress.nextEvent == plan.count { progress.finishedPostingAt = Date(); timer.invalidate() }
                    try save("posted-own-window-event")
                } catch {
                    progress.error = error
                    timer.invalidate()
                    try? save("event-delivery-error")
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
        defer { timer.invalidate() }
        let deadline = Date().addingTimeInterval(6)
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        while Date() < deadline {
            if let error = progress.error { throw error }
            try sample()
            if let event = NSApp.nextEvent(matching: mask, until: Date().addingTimeInterval(0.02), inMode: .default, dequeue: true) {
                guard event.window === window, NSApp.keyWindow === window, window.isKeyWindow,
                      eventNumbers.contains(event.eventNumber) else {
                    throw InteractionFailure("Refusing to dispatch a pointer event outside the exact own-window event plan")
                }
                // Dequeue first so NSApp.currentEvent is the actual synthetic event.
                // Native tracking may consume subsequent queued events itself.
                NSApp.sendEvent(event)
                progress.outerDispatchCount += 1
            } else if let finished = progress.finishedPostingAt, Date().timeIntervalSince(finished) > 0.2 {
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        if let error = progress.error { throw error }
        guard progress.finishedPostingAt != nil else {
            throw InteractionFailure("Own-process pointer delivery did not complete; no native drag success is established")
        }
        try sample()
        try save("own-event-sequence-finished")
        return progress
    }

    @MainActor
    private func waitFor(_ message: String, servicing window: NSWindow? = nil, condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline {
            if let window { try serviceLifecycleEvents(for: window) }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        guard condition() else { throw InteractionFailure(message) }
    }

    @MainActor
    private func serviceLifecycleEvents(for window: NSWindow) throws {
        // App activation is delivered through AppKit's event queue. Yielding to
        // Swift concurrency alone does not dequeue and dispatch those events.
        // This bounded pump handles only this process's lifecycle events; test
        // keyboard events keep the strict key-window/target checks in press().
        let mask: NSEvent.EventTypeMask = [.appKitDefined, .applicationDefined]
        for _ in 0..<32 {
            guard let event = NSApp.nextEvent(matching: mask, until: .distantPast, inMode: .default, dequeue: true) else { break }
            guard event.window == nil || event.window === window else {
                throw InteractionFailure("Refusing to dispatch a lifecycle event for a different window")
            }
            NSApp.sendEvent(event)
            dispatchedLifecycleEvents += 1
        }
        NSApp.updateWindows()
    }

    @MainActor
    private func capture(_ view: NSView, window: NSWindow, name: String, state: [String: Any]) throws {
        guard let path = ProcessInfo.processInfo.environment["LEMULIP_PDF_REVIEW_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent(name + ".png"), options: .withoutOverwriting)
        let environment = ProcessInfo.processInfo.environment
        let provenance: [String: Any] = [
            "capture": "NSView.cacheDisplay of the production SwiftUI editor hosted in an AppKit test window",
            "scenario": name,
            "sourceCommit": environment["LEMULIP_PDF_REVIEW_COMMIT"] ?? environment["GITHUB_SHA"] ?? "unrecorded-local-checkout",
            "runID": environment["GITHUB_RUN_ID"] ?? "local",
            "operatingSystem": ProcessInfo.processInfo.operatingSystemVersionString,
            "theme": AppTheme.saved.rawValue,
            "logicalWidth": Double(view.bounds.width), "logicalHeight": Double(view.bounds.height),
            "pixelWidth": bitmap.pixelsWide, "pixelHeight": bitmap.pixelsHigh,
            "windowBackingScale": Double(window.backingScaleFactor),
            "renderScaleX": Double(bitmap.pixelsWide) / Double(max(1, view.bounds.width)),
            "renderScaleY": Double(bitmap.pixelsHigh) / Double(max(1, view.bounds.height)),
            "resizedAfterCapture": false,
            "appKit": [
                "applicationIsRunning": NSApp.isRunning,
                "applicationIsActive": NSApp.isActive,
                "processFinishedLaunching": NSRunningApplication.current.isFinishedLaunching,
                "activationPolicy": NSApp.activationPolicy().rawValue,
                "applicationDelegateIsNil": NSApp.delegate == nil,
                "windowIsVisible": window.isVisible,
                "windowCanBecomeKey": window.canBecomeKey,
                "windowCanBecomeMain": window.canBecomeMain,
                "windowIsKey": window.isKeyWindow,
                "windowIsMain": window.isMainWindow,
                "windowNumber": window.windowNumber,
                "keyWindowNumber": NSApp.keyWindow?.windowNumber ?? -1,
                "mainWindowNumber": NSApp.mainWindow?.windowNumber ?? -1,
                "firstResponderType": window.firstResponder.map { String(describing: type(of: $0)) } ?? "nil",
                "firstResponderIsFieldEditor": (window.firstResponder as? NSTextView)?.isFieldEditor ?? false,
                "firstResponderText": (window.firstResponder as? NSTextView)?.string ?? "",
                "dispatchedLifecycleEvents": dispatchedLifecycleEvents
            ] as [String: Any],
            "accessibilityElements": Self.accessibilityElements(in: view).map { element -> [String: Any] in
                let identifier: String? = element.accessibilityIdentifier()
                return [
                    "identifier": identifier ?? "", "role": element.accessibilityRole()?.rawValue ?? "",
                    "label": element.accessibilityLabel() ?? "", "value": element.accessibilityValue() as? String ?? "",
                    "focused": element.isAccessibilityFocused(), "frameInScreen": NSStringFromRect(element.accessibilityFrame())
                ]
            },
            "rawAccessibilityChildren": Self.accessibilityElements(in: view).map { element -> [String: Any] in
                let children = element.accessibilityChildren() ?? []
                let navigation = element.accessibilityChildrenInNavigationOrder() ?? []
                return [
                    "parentClass": String(reflecting: type(of: element)),
                    "childCountBeforeCast": children.count,
                    "navigationChildCountBeforeCast": navigation.count,
                    "childrenBeforeCast": children.prefix(64).map { Self.accessibilityChildMetadata($0) },
                    "navigationChildrenBeforeCast": navigation.prefix(64).map { Self.accessibilityChildMetadata($0) }
                ]
            },
            "nativeTextFields": nativeTextFields(in: view).map { field -> [String: Any] in
                let element: any NSAccessibilityProtocol = field
                let identifier: String? = element.accessibilityIdentifier()
                return [
                    "class": String(reflecting: type(of: field)),
                    "identifier": identifier ?? "", "role": element.accessibilityRole()?.rawValue ?? "",
                    "editable": field.isEditable, "value": field.stringValue,
                    "enabled": field.isEnabled, "acceptsFirstResponder": field.acceptsFirstResponder,
                    "hidden": field.isHiddenOrHasHiddenAncestor,
                    "frameInWindow": NSStringFromRect(field.convert(field.bounds, to: nil)),
                    "visibleRect": NSStringFromRect(field.visibleRect), "bounds": NSStringFromRect(field.bounds),
                    "currentEditorIsFirstResponder": field.currentEditor().map { $0 === window.firstResponder } ?? false
                ]
            },
            "input": "Neutral PDFs generated by PDFEditorInteractionTests; no user documents",
            "state": state
        ]
        let data = try JSONSerialization.data(withJSONObject: provenance, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: directory.appendingPathComponent(name + ".json"), options: .withoutOverwriting)
    }

    @MainActor
    private func nativeTextFields(in view: NSView) -> [NSTextField] {
        var result = (view as? NSTextField).map { [$0] } ?? []
        for child in view.subviews { result.append(contentsOf: nativeTextFields(in: child)) }
        return result
    }

    @MainActor
    private func nativeButtons(in view: NSView) -> [NSButton] {
        var result = (view as? NSButton).map { [$0] } ?? []
        for child in view.subviews { result.append(contentsOf: nativeButtons(in: child)) }
        return result
    }

    private struct InteractionFailure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    private func makeFiles(_ names: [String], pages: [Int]) throws -> [URL] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Lemulip-PDF-Interaction-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let titles = ["Project notes", "Quarterly report", "Document cover", "Reference pages"]
        let colors: [(CGFloat, CGFloat, CGFloat)] = [(0.17, 0.38, 0.29), (0.22, 0.34, 0.51), (0.55, 0.36, 0.18), (0.41, 0.27, 0.46)]
        return try names.enumerated().map { index, name in
            let url = directory.appendingPathComponent(name)
            var box = CGRect(x: 0, y: 0, width: 420, height: 594)
            let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
            for page in 1...pages[index] {
                context.beginPDFPage(nil)
                context.setFillColor(CGColor(gray: 1, alpha: 1))
                context.fill(box)
                let color = colors[(index + page - 1) % colors.count]
                context.setFillColor(CGColor(red: color.0, green: color.1, blue: color.2, alpha: 1))
                context.fill(CGRect(x: 30, y: 450, width: 360, height: 100))
                let heading = NSAttributedString(string: titles[(index + page - 1) % titles.count], attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica-Bold" as CFString, 24, nil),
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1)
                ])
                context.textPosition = CGPoint(x: 46, y: 492)
                CTLineDraw(CTLineCreateWithAttributedString(heading), context)
                let detail = NSAttributedString(string: "Synthetic review document  /  Page \(page)", attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 14, nil),
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.25, alpha: 1)
                ])
                context.textPosition = CGPoint(x: 30, y: 416)
                CTLineDraw(CTLineCreateWithAttributedString(detail), context)
                context.setFillColor(CGColor(gray: 0.87, alpha: 1))
                for line in 0..<7 { context.fill(CGRect(x: 30, y: CGFloat(370 - line * 24), width: line == 6 ? 205 : 340, height: 5)) }
                context.endPDFPage()
            }
            context.closePDF()
            return url
        }
    }
}
#endif
