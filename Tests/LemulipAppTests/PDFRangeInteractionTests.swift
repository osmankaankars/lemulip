#if os(macOS)
import AppKit
import CoreText
import PDFKit
import SwiftUI
import XCTest
import LemulipCore
@testable import Lemulip

/// Sends public AppKit key events only to this process's synthetic key window.
/// The production options view must retain invalid input and export a corrected
/// range. This is not a physical keyboard or VoiceOver review.
final class PDFRangeInteractionTests: XCTestCase {
    @MainActor
    func testEnglishInvalidRangeCanBeCorrectedWithoutLosingTheForm() async throws {
        try await review(language: "en")
    }

    @MainActor
    func testTurkishInvalidRangeCanBeCorrectedWithoutLosingTheForm() async throws {
        try await review(language: "tr")
    }

    @MainActor
    private func review(language: String) async throws {
        let keys = ["language", "outputAlongsideOriginal", "completionPresentation", "revealWhenFinished"]
        let saved = keys.map { ($0, UserDefaults.standard.object(forKey: $0)) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Lemulip-Range-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        let controller = AppController()
        defer {
            controller.cancelPending()
            controller.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
            for (key, value) in saved {
                if let value { UserDefaults.standard.set(value, forKey: key) }
                else { UserDefaults.standard.removeObject(forKey: key) }
            }
            try? FileManager.default.removeItem(at: directory)
        }
        controller.language = language
        controller.outputAlongsideOriginal = true
        controller.completionPresentation = .quiet
        let source = directory.appendingPathComponent("Three-Pages.pdf")
        try makePDF(at: source)
        let original = try Data(contentsOf: source)
        controller.files = [source]
        controller.begin(FileOperation(id: "pdf.extract", title: "Extract Pages", outputExtension: "pdf"))

        try await withWindow(RangeOptionsHost(model: controller)) { window, host in
            do {
                try await waitFor("The actual page-range field must be present") {
                    self.fields(in: host).count == 1
                }
                let invalid = ["1,,2", "3-1", "0", "1-"]
                for value in invalid {
                    let field = try XCTUnwrap(fields(in: host).first)
                    try await enter(value, in: field, window: window)
                    // Finish the native text edit, then invoke the window's
                    // normal default button by Return, not a model callback.
                    XCTAssertTrue(window.makeFirstResponder(nil))
                    try await press("\r", code: 36, in: window)
                    try await Task.sleep(nanoseconds: 100_000_000)
                    XCTAssertEqual(controller.pendingOperation?.id, "pdf.extract",
                                   "Malformed range \(value) must leave the same editor open")
                    XCTAssertTrue(controller.activity.isEmpty,
                                  "Malformed range \(value) must not enqueue a doomed job")
                    guard controller.pendingOperation != nil, controller.activity.isEmpty else {
                        throw ReviewFailure("The form closed or a job was queued for malformed range \(value)")
                    }
                    XCTAssertEqual(field.stringValue, value, "The invalid text must stay editable")
                    let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
                    XCTAssertEqual(files, [source.lastPathComponent])
                    guard field.stringValue == value, files == [source.lastPathComponent] else {
                        throw ReviewFailure("Invalid text was lost or an unexpected file was created")
                    }
                    try capture(host, name: "range-\(language)-\(invalid.firstIndex(of: value)!)")
                }

                let field = try XCTUnwrap(fields(in: host).first)
                try await enter("3,1-2,3", in: field, window: window)
                XCTAssertTrue(window.makeFirstResponder(nil))
                try await press("\r", code: 36, in: window)
                try await waitFor("Correcting the same form must create exactly one result") {
                    controller.pendingOperation == nil && controller.activity.count == 1
                        && controller.activity[0].state == .succeeded
                }
                let output = try XCTUnwrap(controller.activity[0].outputs.first)
                let document = try XCTUnwrap(PDFDocument(url: output))
                XCTAssertEqual(document.pageCount, 3)
                let labels = (0..<document.pageCount).map { document.page(at: $0)?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
                XCTAssertEqual(labels, ["Charlie", "Alpha", "Bravo"])
                let originalPreserved = try Data(contentsOf: source) == original
                XCTAssertTrue(originalPreserved, "Extraction must preserve the original bytes")
                guard document.pageCount == 3, labels == ["Charlie", "Alpha", "Bravo"], originalPreserved else {
                    throw ReviewFailure("Output order or original preservation did not match the observed contract")
                }
                try record(language: language, invalid: invalid, labels: labels)
            } catch {
                try? capture(host, name: "range-\(language)-failure")
                throw error
            }
        }
    }

    @MainActor
    private func withWindow<Content: View>(_ content: Content,
        body: (NSWindow, NSHostingView<Content>) async throws -> Void) async throws {
        let application = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first, "The native review requires a WindowServer display")
        let policy = application.activationPolicy()
        XCTAssertTrue(application.setActivationPolicy(.regular))
        defer { _ = application.setActivationPolicy(policy) }
        if !NSRunningApplication.current.isFinishedLaunching {
            guard application.delegate == nil, UserDefaults.standard.object(forKey: "NSOpen") == nil else {
                throw ReviewFailure("The synthetic host must not launch a production delegate or open launch files")
            }
            application.finishLaunching()
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Lemulip PDF Range Review"
        window.appearance = NSAppearance(named: AppTheme.saved.appearanceName)
        let host = NSHostingView(rootView: content)
        window.contentView = host
        window.setContentSize(NSSize(width: 520, height: 360))
        window.setFrameTopLeftPoint(NSPoint(x: screen.visibleFrame.minX + 30, y: screen.visibleFrame.maxY - 30))
        defer { window.contentView = nil; window.close() }
        application.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        try await waitFor("The review window must become key", servicing: window) {
            window.isVisible && window.isKeyWindow && application.keyWindow === window
        }
        try await body(window, host)
    }

    @MainActor
    private func fields(in view: NSView) -> [NSTextField] {
        let own = (view as? NSTextField).map { field in
            field.isEditable && field.isEnabled && !field.isHiddenOrHasHiddenAncestor ? [field] : []
        } ?? []
        return own + view.subviews.flatMap { fields(in: $0) }
    }

    @MainActor
    private func enter(_ value: String, in field: NSTextField, window: NSWindow) async throws {
        guard field.window === window, NSApp.keyWindow === window, window.isKeyWindow,
              field.isEditable, field.isEnabled, !field.isHiddenOrHasHiddenAncestor else {
            throw ReviewFailure("The field must belong to the synthetic key window")
        }
        XCTAssertTrue(window.makeFirstResponder(field))
        try await waitFor("The native field editor must receive focus") {
            field.currentEditor() != nil && window.firstResponder === field.currentEditor()
        }
        let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
        XCTAssertTrue(editor.isFieldEditor)
        editor.selectAll(nil)
        let codes: [Character: UInt16] = ["0": 29, "1": 18, "2": 19, "3": 20, ",": 43, "-": 27]
        for character in value { try await press(String(character), code: XCTUnwrap(codes[character]), in: window) }
        try await waitFor("Native keys must enter the full range") { editor.string == value }
    }

    @MainActor
    private func press(_ characters: String, code: UInt16, in window: NSWindow) async throws {
        guard NSApp.keyWindow === window, window.isKeyWindow else {
            throw ReviewFailure("Refusing to send input outside the synthetic key window")
        }
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = try XCTUnwrap(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: characters, charactersIgnoringModifiers: characters,
                isARepeat: false, keyCode: code))
            guard event.window === window else { throw ReviewFailure("The constructed event has the wrong window") }
            NSApp.sendEvent(event)
        }
        try await Task.sleep(nanoseconds: 20_000_000)
    }

    @MainActor
    private func waitFor(_ message: String, servicing window: NSWindow? = nil,
                         condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(8)
        while !condition(), Date() < deadline {
            if let window {
                for _ in 0..<32 {
                    guard let event = NSApp.nextEvent(matching: [.appKitDefined, .applicationDefined],
                        until: .distantPast, inMode: .default, dequeue: true) else { break }
                    guard event.window == nil || event.window === window else {
                        throw ReviewFailure("Refusing a lifecycle event for a different window")
                    }
                    NSApp.sendEvent(event)
                }
                NSApp.updateWindows()
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        guard condition() else { throw ReviewFailure(message) }
    }

    private func makePDF(at url: URL) throws {
        var box = CGRect(x: 0, y: 0, width: 240, height: 160)
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        for label in ["Alpha", "Bravo", "Charlie"] {
            context.beginPDFPage(nil)
            context.textPosition = CGPoint(x: 20, y: 80)
            let text = NSAttributedString(string: label, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 18, nil)
            ])
            CTLineDraw(CTLineCreateWithAttributedString(text), context)
            context.endPDFPage()
        }
        context.closePDF()
    }

    @MainActor
    private func capture(_ view: NSView, name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["LEMULIP_RANGE_REVIEW_DIR"] else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent(name + ".png"), options: .withoutOverwriting)
    }

    private func record(language: String, invalid: [String], labels: [String]) throws {
        guard let path = ProcessInfo.processInfo.environment["LEMULIP_RANGE_REVIEW_DIR"] else { return }
        let record: [String: Any] = ["language": language, "rejectedInputs": invalid,
            "outputPages": labels, "originalPreserved": true,
            "inputDelivery": "Own-window public AppKit key events; no physical-input or VoiceOver claim",
            "sourceCommit": ProcessInfo.processInfo.environment["LEMULIP_RANGE_REVIEW_COMMIT"] ?? ""]
        try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: path).appendingPathComponent("range-\(language).json"), options: .withoutOverwriting)
    }

    private struct ReviewFailure: Error, CustomStringConvertible { let description: String; init(_ text: String) { description = text } }
}

private struct RangeOptionsHost: View {
    @ObservedObject var model: AppController
    var body: some View {
        if let operation = model.pendingOperation { OperationOptionsView(model: model, operation: operation) }
        else { Text("Review complete") }
    }
}
#endif
