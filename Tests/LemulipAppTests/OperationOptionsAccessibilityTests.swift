#if os(macOS)
import AppKit
import SwiftUI
import XCTest
import LemulipCore
@testable import Lemulip

final class OperationOptionsAccessibilityTests: XCTestCase {
    private var dispatchedLifecycleEvents = 0

    @MainActor
    func testProductionOptionsExposeLocalizedControlNamesAndValues() async throws {
        let application = NSApplication.shared
        let policy = application.activationPolicy()
        XCTAssertTrue(application.setActivationPolicy(.regular))
        defer { _ = application.setActivationPolicy(policy) }
        if !NSRunningApplication.current.isFinishedLaunching {
            guard application.delegate == nil else {
                throw OptionsReviewFailure("The review host must not launch a production application delegate")
            }
            guard UserDefaults.standard.object(forKey: "NSOpen") == nil else {
                throw OptionsReviewFailure("The synthetic review host requires no NSOpen launch files")
            }
            application.finishLaunching()
        }
        let savedLanguage = UserDefaults.standard.object(forKey: "language")
        defer {
            if let savedLanguage { UserDefaults.standard.set(savedLanguage, forKey: "language") }
            else { UserDefaults.standard.removeObject(forKey: "language") }
        }
        let model = AppController()
        let cases: [(String, NSAccessibility.Role, String, String, String, String)] = [
            ("image.compress", .slider, "Quality", "82 percent", "Kalite", "Yüzde 82"),
            ("media.speed", .slider, "Playback Speed", "2.00 times", "Oynatma hızı", "2,00 kat"),
            ("media.volume", .slider, "Volume", "150 percent", "Ses düzeyi", "Yüzde 150"),
            ("image.resize", .textField, "Maximum Dimension (px)", "1920", "En büyük kenar (piksel)", "1920"),
            ("pdf.extract", .textField, "Page Numbers and Ranges", "1", "Sayfalar ve aralıklar", "1")
        ]
        var review: [[String: String]] = []
        for language in ["en", "tr"] {
            model.language = language
            for (operation, role, englishLabel, englishValue, turkishLabel, turkishValue) in cases {
                let label = language == "tr" ? turkishLabel : englishLabel
                let value = language == "tr" ? turkishValue : englishValue
                let window = NSWindow(contentRect: NSRect(x: 30, y: 30, width: 520, height: 480),
                                      styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.title = "Lemulip Options Accessibility Review"
                let host = NSHostingView(rootView: OperationOptionsView(model: model,
                    operation: FileOperation(id: operation, title: operation)))
                window.contentView = host
                dispatchedLifecycleEvents = 0
                application.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                do {
                    try await waitForKeyWindow(window)
                    let deadline = Date().addingTimeInterval(5)
                    while find(role: role, label: label, in: host) == nil, Date() < deadline {
                        try serviceLifecycleEvents(for: window)
                        host.layoutSubtreeIfNeeded()
                        try await Task.sleep(nanoseconds: 20_000_000)
                    }
                    let element = try XCTUnwrap(find(role: role, label: label, in: host),
                        "The actual \(language) \(operation) control must have its accessible name")
                    let description = element.valueDescription ?? (element.value as? String)
                    XCTAssertEqual(description, value, "The control must announce its value with the appropriate units")
                    XCTAssertTrue(element.enabled == true)
                    review.append(["language": language, "operation": operation, "label": label,
                                   "value": description ?? "missing", "role": role.rawValue])
                } catch {
                    do { try captureFailure(in: host, window: window, language: language, operation: operation) }
                    catch { XCTFail("Could not retain the options accessibility failure: \(error)") }
                    window.contentView = nil
                    window.close()
                    throw error
                }
                window.contentView = nil
                window.close()
            }
        }
        if let path = ProcessInfo.processInfo.environment["LEMULIP_EDITOR_REVIEW_DIR"], !path.isEmpty {
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let record: [String: Any] = [
                "sourceCommit": ProcessInfo.processInfo.environment["LEMULIP_EDITOR_REVIEW_COMMIT"] ?? "local",
                "evidence": "Accessible nodes queried from production OperationOptionsView hosted in native AppKit windows",
                "inputEventsSent": false, "controls": review
            ]
            try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
                .write(to: directory.appendingPathComponent("options-accessibility.json"), options: .withoutOverwriting)
        }
    }

    @MainActor
    private func find(role: NSAccessibility.Role, label: String, in view: NSView) -> NativeAccessibilityReview.Node? {
        NativeAccessibilityReview.walk(view).first(role: role, label: label)
    }

    @MainActor
    private func waitForKeyWindow(_ window: NSWindow) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !(window.isVisible && window.isKeyWindow && NSApp.keyWindow === window), Date() < deadline {
            try serviceLifecycleEvents(for: window)
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        guard window.isVisible && window.isKeyWindow && NSApp.keyWindow === window else {
            throw OptionsReviewFailure("The synthetic options window must become the actual key window")
        }
    }

    @MainActor
    private func serviceLifecycleEvents(for window: NSWindow) throws {
        // XCTest has no normal NSApplication event loop. Dispatch only this
        // process's lifecycle events for the constructed review window.
        let mask: NSEvent.EventTypeMask = [.appKitDefined, .applicationDefined]
        for _ in 0..<32 {
            guard let event = NSApp.nextEvent(matching: mask, until: .distantPast,
                                             inMode: .default, dequeue: true) else { break }
            guard event.window == nil || event.window === window else {
                throw OptionsReviewFailure("Refusing to dispatch a lifecycle event for a different window")
            }
            NSApp.sendEvent(event)
            dispatchedLifecycleEvents += 1
        }
        NSApp.updateWindows()
    }

    @MainActor
    private func captureFailure(in view: NSView, window: NSWindow, language: String, operation: String) throws {
        guard let path = ProcessInfo.processInfo.environment["LEMULIP_EDITOR_REVIEW_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = "options-accessibility-failure-" + language + "-" + operation
        let traversal = NativeAccessibilityReview.walk(view)
        let record: [String: Any] = [
            "sourceCommit": ProcessInfo.processInfo.environment["LEMULIP_EDITOR_REVIEW_COMMIT"] ?? "local",
            "workflowRun": ProcessInfo.processInfo.environment["GITHUB_RUN_ID"] ?? "local",
            "operation": operation, "language": language, "nodes": traversal.nodes.map(\.diagnostics),
            "traversalTruncated": traversal.truncated, "remainingQueuedNodes": traversal.remainingQueued, "inputEventsSent": false,
            "applicationIsActive": NSApp.isActive,
            "processFinishedLaunching": NSRunningApplication.current.isFinishedLaunching,
            "applicationDelegateIsNil": NSApp.delegate == nil,
            "windowIsVisible": window.isVisible, "windowIsKey": window.isKeyWindow,
            "windowNumber": window.windowNumber, "keyWindowNumber": NSApp.keyWindow?.windowNumber ?? -1,
            "dispatchedLifecycleEvents": dispatchedLifecycleEvents,
            "capture": "Read-only accessibility diagnostics and unresized production options view",
            "logicalWidth": Double(view.bounds.width), "logicalHeight": Double(view.bounds.height),
            "windowBackingScale": Double(window.backingScaleFactor)
        ]
        try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent(name + ".json"), options: .withoutOverwriting)
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: directory.appendingPathComponent(name + ".png"), options: .withoutOverwriting)
    }
}

private struct OptionsReviewFailure: Error { let message: String; init(_ message: String) { self.message = message } }
#endif
