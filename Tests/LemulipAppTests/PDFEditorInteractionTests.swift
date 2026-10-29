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
/// They do not post global CGEvents, use accessibility automation, or establish
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
            try await waitFor("Three native position fields must be rendered") { positionFields(in: host).count == 3 }
            try await waitFor("The visible synthetic PDF covers must load") { editor.thumbnails.count == 3 }
            try capture(host, window: window, name: "merge-initial", state: ["order": editor.documents.map(\.inputIndex)])

            let first = try positionField(0, in: host)
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

            let moved = try positionField(0, in: host)
            try await enter("99", in: moved, window: window)
            try await press("\r", code: 36, in: window)
            try await waitFor("An invalid number must remain in the active field") {
                (moved.currentEditor() as? NSTextView)?.string == "99"
            }
            XCTAssertEqual(editor.documents.map(\.inputIndex), [1, 2, 0])
            try capture(host, window: window, name: "merge-invalid-position", state: ["order": editor.documents.map(\.inputIndex)])
            try await press("\u{1B}", code: 53, in: window)
            try await waitFor("Escape must discard the draft and restore the displayed position") {
                moved.currentEditor() == nil && moved.stringValue == "3"
            }
            XCTAssertEqual(model.pendingOperation?.id, "pdf.merge", "Escape must not close the editor while editing a number")
            XCTAssertEqual(editor.documents.map(\.inputIndex), [1, 2, 0])
            XCTAssertTrue(model.activity.isEmpty)
            try await press("\u{F700}", code: 126, in: window)
            try await waitFor("Up must navigate the list immediately after Escape") { editor.selectedDocuments == [2] }

            let previous = try positionField(1, in: host)
            let next = try positionField(2, in: host)
            try await enter("3", in: previous, window: window)
            try await enter("1", in: next, window: window)
            try await waitFor("Changing fields must cancel the previous draft without stealing focus") {
                previous.stringValue == "1" && next.currentEditor() != nil
            }
            try await press("\r", code: 36, in: window)
            try await waitFor("The newly focused field must accept its own edit") {
                editor.documents.map(\.inputIndex) == [2, 1, 0]
            }
            XCTAssertEqual(model.pendingOperation?.id, "pdf.merge")
            XCTAssertTrue(model.activity.isEmpty)
            try capture(host, window: window, name: "merge-after-field-switch", state: ["order": editor.documents.map(\.inputIndex)])
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
            try await waitFor("Four native page position fields must be rendered") { positionFields(in: host).count == 4 }
            try await waitFor("The visible synthetic page previews must load") { editor.thumbnails.count == 4 }
            try capture(host, window: window, name: "organize-initial", state: ["order": editor.pages.map(\.sourceIndex)])

            let first = try positionField(0, in: host)
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

            let second = try positionField(2, in: host)
            try await enter("1", in: second, window: window)
            try await press("\u{1B}", code: 53, in: window)
            try await waitFor("Escape must cancel a valid but unsubmitted page position") {
                second.currentEditor() == nil && second.stringValue == "2"
            }
            XCTAssertEqual(editor.pages.map(\.sourceIndex), [1, 2, 3, 0])
            XCTAssertEqual(model.pendingOperation?.id, "pdf.organize", "Escape must not close the editor")
            XCTAssertTrue(model.activity.isEmpty)
            try await press("\u{F702}", code: 123, in: window)
            try await waitFor("Left must navigate the grid immediately after Escape") { editor.selectedPages == [1] }
            try capture(host, window: window, name: "organize-after-escape", state: [
                "order": editor.pages.map(\.sourceIndex), "selected": editor.selectedPages.sorted()
            ])
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
    private func positionFields(in view: NSView) -> [NSTextField] {
        var result: [NSTextField] = []
        if let field = view as? NSTextField, field.accessibilityIdentifier().hasPrefix("pdf.position.") {
            result.append(field)
        }
        for child in view.subviews { result.append(contentsOf: positionFields(in: child)) }
        return result
    }

    @MainActor
    private func positionField(_ item: Int, in view: NSView) throws -> NSTextField {
        try XCTUnwrap(positionFields(in: view).first { $0.accessibilityIdentifier() == "pdf.position.\(item)" },
                      "The production number field must expose its stable accessibility identifier")
    }

    @MainActor
    private func enter(_ value: String, in field: NSTextField, window: NSWindow) async throws {
        XCTAssertTrue(field.window === window)
        XCTAssertTrue(window.makeFirstResponder(field))
        try await waitFor("The native text editor must receive focus") {
            field.currentEditor() != nil && window.firstResponder === field.currentEditor()
        }
        let textEditor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        textEditor.selectAll(nil)
        let keyCodes: [Character: UInt16] = ["0": 29, "1": 18, "2": 19, "3": 20, "4": 21, "9": 25]
        for character in value {
            try await press(String(character), code: try XCTUnwrap(keyCodes[character]), in: window)
        }
        try await waitFor("Native key events must update the text editor") { textEditor.string == value }
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
                "dispatchedLifecycleEvents": dispatchedLifecycleEvents
            ] as [String: Any],
            "input": "Neutral PDFs generated by PDFEditorInteractionTests; no user documents",
            "state": state
        ]
        let data = try JSONSerialization.data(withJSONObject: provenance, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: directory.appendingPathComponent(name + ".json"), options: .withoutOverwriting)
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
