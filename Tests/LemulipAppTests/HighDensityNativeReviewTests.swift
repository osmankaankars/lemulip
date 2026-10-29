#if os(macOS)
import AppKit
import SwiftUI
import XCTest
import LemulipCore
@testable import Lemulip

/// A bounded W3 experiment. No production UI, system display, event-routing or
/// audio policy is changed. Artifacts are candidates for review, never site assets.
final class HighDensityNativeReviewTests: XCTestCase {
    @MainActor
    func testNativePDFExportCalibrationArtifacts() async throws {
        guard let path = ProcessInfo.processInfo.environment["LEMULIP_EDITOR_REVIEW_DIR"], !path.isEmpty else {
            throw XCTSkip("Set LEMULIP_EDITOR_REVIEW_DIR to run the native PDF calibration probe")
        }
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: path, isDirectory: true)
            .appendingPathComponent("native-pdf-calibration", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let log = DensityDrawLog()
        try await withHost(NativeDensityCalibration(log: log), size: NSSize(width: 320, height: 240),
                           appearance: .aqua) { _, host in
            try await self.waitFor("The PDF calibration must retain its actual native field and observed SwiftUI scale") {
                self.firstView(NSTextField.self, in: host) != nil && !log.environmentScales.isEmpty
            }
            try NativeReviewPDF.saveCalibration(of: host, log: log, directory: directory)
        }
    }

    @MainActor
    func testExplicitDisplayScaleCalibration() async throws {
        guard let path = ProcessInfo.processInfo.environment["LEMULIP_EDITOR_REVIEW_DIR"], !path.isEmpty else {
            throw XCTSkip("Set LEMULIP_EDITOR_REVIEW_DIR to run the W3 native rendering experiment")
        }
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: path, isDirectory: true)
            .appendingPathComponent("high-density-explicit-environment", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // This separate experiment sets the documented SwiftUI environment value
        // only on its synthetic calibration host. It does not approve a product
        // asset or pretend the runner's physical display has changed density.
        let passed = try await calibrate(directory: directory, environmentScale: 2)
        XCTAssertTrue(passed, "The explicit displayScale experiment failed its unchanged numerical gate; raw visual review remains required even if it passes")
    }

    @MainActor
    func testCalibratedOffscreenRenderingAndSelectionSoundSettings() async throws {
        guard let path = ProcessInfo.processInfo.environment["LEMULIP_EDITOR_REVIEW_DIR"], !path.isEmpty else {
            throw XCTSkip("Set LEMULIP_EDITOR_REVIEW_DIR to run the W3 native rendering experiment")
        }
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent("high-density", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let calibrated: Bool
        do {
            calibrated = try await calibrate(directory: directory)
        } catch {
            var failure = NativeReviewBitmap.provenance
            let details: [String: Any] = ["status": "failed", "production2xCandidatesAllowed": false,
                                          "reason": String(describing: error), "inputEventsSent": false]
            failure.merge(details, uniquingKeysWith: { _, value in value })
            try NativeReviewBitmap.writeJSON(failure, name: "calibration-failure", directory: directory)
            calibrated = false
        }
        // A1 remains useful if a 2x layer path fails: retain its clearly labeled
        // 1x content and actual accessible nodes, without dispatching an action.
        try await reviewProductionViews(directory: directory, calibrated: calibrated)
        XCTAssertTrue(calibrated, "W3 density calibration failed or is mixed. Inspect calibration.json; do not promote these diagnostics as 2x assets.")
    }

    @MainActor
    private func calibrate(directory: URL, environmentScale: CGFloat? = nil) async throws -> Bool {
        let log = DensityDrawLog()
        let root: AnyView
        if let environmentScale {
            root = AnyView(NativeDensityCalibration(log: log).environment(\.displayScale, environmentScale))
        } else {
            root = AnyView(NativeDensityCalibration(log: log))
        }
        return try await withHost(root, size: NSSize(width: 320, height: 240),
                                  appearance: .aqua) { _, host in
            try await waitFor("The real native calibration text field must exist") {
                self.firstView(NSTextField.self, in: host) != nil
            }
            try await self.waitFor("The calibration must observe its actual SwiftUI displayScale") {
                !log.environmentScales.isEmpty
            }
            if let environmentScale {
                XCTAssertEqual(log.environmentScales.last, Double(environmentScale))
            }
            host.displayIfNeeded()
            log.draws.removeAll()
            let one = try NativeReviewBitmap.render(host, scale: 1)
            let oneDraws = log.draws
            log.draws.removeAll()
            let two = try NativeReviewBitmap.render(host, scale: 2)
            let twoDraws = log.draws
            let vectorsFresh = log.hasFreshDraw("nativeVectors", scale: 2)
            let textFresh = log.hasFreshDraw("nativeText", scale: 2)
            var state: [String: Any] = ["view": "Synthetic density calibration; not product UI",
                                       "text": "12pt SwiftUI Text and native NSTextField: Il1MW 0123456789",
                                       "assetEligibility": "Diagnostic only"]
            state["explicitSwiftUIEnvironmentScale"] = environmentScale.map { Double($0) } ?? 0
            state["observedSwiftUIEnvironmentScales"] = log.environmentScales
            try NativeReviewBitmap.save(one, of: host, scale: 1, name: "calibration-1x", directory: directory, state: state)
            try NativeReviewBitmap.save(two, of: host, scale: 2, name: "calibration-2x", directory: directory, state: state)
            let low = try DensityPixels(one, scale: 1)
            let high = try DensityPixels(two, scale: 2)
            let stripes = [
                "swiftUI": high.stripe(y: 48, phase: 0), "swiftUIPhaseShifted": high.stripe(y: 70, phase: 1),
                "native": high.stripe(y: 168, phase: 0), "nativePhaseShifted": high.stripe(y: 190, phase: 1)
            ]
            let text = ["swiftUI": high.textDetail(comparedTo: low, top: 8),
                        "native": high.textDetail(comparedTo: low, top: 128)]
            let dimensionsPass = one.pixelsWide == 320 && one.pixelsHigh == 240
                && two.pixelsWide == 640 && two.pixelsHigh == 480
            let passed = dimensionsPass && vectorsFresh && textFresh
                && stripes.values.allSatisfy { $0["passed"] as? Bool == true }
                && text.values.allSatisfy { $0["passed"] as? Bool == true }
            var report = NativeReviewBitmap.provenance
            report["explicitSwiftUIEnvironmentScale"] = environmentScale.map { Double($0) } ?? 0
            report["observedSwiftUIEnvironmentScales"] = log.environmentScales
            report["environmentScaleExperimentOnly"] = environmentScale != nil
            let details: [String: Any] = [
                "status": passed ? "passed-numerical-gate" : "failed-or-mixed",
                "production2xCandidatesAllowed": passed && environmentScale == nil,
                "visualReviewRequired": "Inspect both raw PNGs at original pixels, especially the two 12pt text regions and native control. Numerical checks do not approve a marketing image.",
                "logicalSize": [320, 240], "windowBackingScale": Double(host.window?.backingScaleFactor ?? 0),
                "offscreenRenderScales": [1, 2], "dimensionsPassed": dimensionsPass,
                "freshNativeVectorDrawAt2x": vectorsFresh, "freshNativeTextDrawAt2x": textFresh,
                "drawsAt1x": oneDraws, "drawsAt2x": twoDraws,
                "stripeSamples": stripes, "textDetail": text,
                "sampleRowsInverted1x": low.invertedRows, "sampleRowsInverted2x": high.invertedRows,
                "inputEventsSent": false, "screenCapture": false,
                "references": [
                    "https://developer.apple.com/library/archive/documentation/GraphicsAnimation/Conceptual/HighResolutionOSX/CapturingScreenContents/CapturingScreenContents.html",
                    "https://developer.apple.com/documentation/appkit/nsview/displayignoringopacity(_:in:)",
                    "https://developer.apple.com/documentation/swiftui/environmentvalues/displayscale"
                ]
            ]
            report.merge(details, uniquingKeysWith: { _, value in value })
            try NativeReviewBitmap.writeJSON(report, name: "calibration", directory: directory)
            return passed
        }
    }

    @MainActor
    private func reviewProductionViews(directory: URL, calibrated: Bool) async throws {
        let keys = ["language", AppTheme.preferenceKey]
        let saved = keys.map { ($0, UserDefaults.standard.object(forKey: $0)) }
        let appearance = NSApp.appearance
        let suite = "Lemulip.HighDensityReview." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let player = CaptureSilentCuePlayer()
        let feedback = SelectionFeedback(defaults: defaults, player: player)
        let model = AppController(selectionFeedback: feedback)
        let fixtureDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("Lemulip-Density-Fixture-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: false)
        defer {
            model.cancelPending()
            model.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
            defaults.removePersistentDomain(forName: suite)
            for (key, value) in saved {
                if let value { UserDefaults.standard.set(value, forKey: key) }
                else { UserDefaults.standard.removeObject(forKey: key) }
            }
            NSApp.appearance = appearance
            try? FileManager.default.removeItem(at: fixtureDirectory)
        }

        var nodes: [[String: Any]] = []
        model.section = "settings"
        for language in ["en", "tr"] {
            model.language = language
            model.theme = language == "en" ? .orchardNight : .vividPistachio
            for enabled in [false, true] {
                model.selectionSoundsEnabled = enabled
                try await withHost(DashboardView(model: model), size: NSSize(width: 1020, height: 820),
                                   appearance: model.theme.appearanceName) { window, host in
                    // Retain actual content even if a later accessibility lookup
                    // reveals an SDK or view-tree difference.
                    if (language == "en" && !enabled) || (language == "tr" && enabled) {
                        let state: [String: Any] = [
                            "view": "Production DashboardView with its real SettingsContent",
                            "language": language, "theme": model.theme.rawValue, "selectionSoundsEnabled": enabled,
                            "stateSetup": "Bound model preference; no UI action or preview sound dispatched",
                            "assetEligibility": "Review candidate only; exact pixels require visual review"
                        ]
                        let name = "settings-" + language + (enabled ? "-sound-on" : "-sound-off")
                        try self.saveView(host, name: name, directory: directory, calibrated: calibrated, state: state)
                    }
                    let preview: NativeAccessibilityReview.Node
                    let toggle: NativeAccessibilityReview.Node
                    do {
                        try await self.waitFor("Production SettingsContent must expose Preview and Selection Sounds") {
                            self.control("settings.selection-sounds.preview", roles: ["AXButton"], in: host) != nil
                                && self.control("settings.selection-sounds", roles: ["AXCheckBox", "AXSwitch"], in: host) != nil
                        }
                        preview = try XCTUnwrap(self.control("settings.selection-sounds.preview", roles: ["AXButton"], in: host))
                        toggle = try XCTUnwrap(self.control("settings.selection-sounds", roles: ["AXCheckBox", "AXSwitch"], in: host))
                    } catch {
                        let traversal = NativeAccessibilityReview.walk(host)
                        var failure = NativeReviewBitmap.provenance
                        failure["language"] = language
                        failure["preferenceEnabled"] = enabled
                        failure["error"] = String(describing: error)
                        failure["nodes"] = traversal.nodes.map(\.diagnostics)
                        failure["traversalTruncated"] = traversal.truncated
                        failure["remainingQueuedNodes"] = traversal.remainingQueued
                        failure["inputEventsSent"] = false
                        try NativeReviewBitmap.writeJSON(failure,
                            name: "settings-accessibility-failure-" + language + (enabled ? "-on" : "-off"), directory: directory)
                        XCTFail("Actual Settings accessibility lookup failed for \(language), sounds enabled=\(enabled): \(error)")
                        // Keep each other language/state review available without
                        // turning this missing semantic evidence into a pass.
                        return
                    }
                    let previewName = language == "en" ? "Preview Selection Sound" : "Seçim Sesini Dinle"
                    let toggleName = language == "en" ? "Selection Sounds" : "Seçim Sesleri"
                    XCTAssertEqual(preview.label ?? preview.title, previewName)
                    XCTAssertEqual(toggle.label ?? toggle.title, toggleName)
                    XCTAssertTrue(preview.enabled == true, "Preview stays available while the preference is off")
                    XCTAssertTrue(toggle.enabled == true)
                    XCTAssertEqual((toggle.value as? NSNumber)?.boolValue, enabled)
                    XCTAssertFalse((preview.help ?? "").isEmpty)
                    XCTAssertFalse((toggle.help ?? "").isEmpty)
                    for (identifier, element) in [("preview", preview), ("toggle", toggle)] {
                        let screenFrame = try XCTUnwrap(element.frame, "The actual setting must expose its frame")
                        let frame = host.convert(window.convertFromScreen(screenFrame), from: nil)
                        XCTAssertFalse(frame.isEmpty)
                        XCTAssertTrue(host.bounds.contains(frame), "The reviewed setting must be fully visible in this capture")
                        var node: [String: Any] = [
                            "language": language, "theme": model.theme.rawValue, "preferenceEnabled": enabled,
                            "control": identifier, "role": element.role?.rawValue ?? "missing",
                            "name": element.label ?? element.title ?? "missing",
                            "hint": element.help ?? "missing",
                            "value": (element.value as? NSNumber)?.stringValue ?? "not-valued",
                            "logicalFrame": [Double(frame.minX), Double(frame.minY), Double(frame.width), Double(frame.height)]
                        ]
                        if let enabled = element.enabled { node["enabled"] = enabled }
                        else { node["enabled"] = NSNull() }
                        nodes.append(node)
                    }
                }
            }
        }
        XCTAssertEqual(nodes.count, 8, "Both actual controls must be reviewed in both languages and preference states")
        XCTAssertEqual(player.playCount, 0, "Reading/capturing settings must not audition audio")
        var accessibility = NativeReviewBitmap.provenance
        let details: [String: Any] = [
            "evidence": "Actual accessible nodes of production SettingsContent inside DashboardView",
            "controls": nodes, "expectedControlCount": 8, "observedControlCount": nodes.count,
            "inputEventsSent": false, "previewInvoked": false,
            "hardwareListeningOrMuteReview": false,
            "stateSetup": "Model preference changed in an isolated defaults suite; no accessibility action was dispatched"
        ]
        accessibility.merge(details, uniquingKeysWith: { _, value in value })
        try NativeReviewBitmap.writeJSON(accessibility, name: "settings-accessibility", directory: directory)

        guard calibrated else { return }
        model.language = "en"
        model.theme = .orchardNight
        let input = try imageFixture(in: fixtureDirectory)
        let inputHash = NativeReviewBitmap.digest(try Data(contentsOf: input))
        model.files = [input]
        model.section = "workspace"
        try await withHost(DashboardView(model: model), size: NSSize(width: 1020, height: 700),
                           appearance: model.theme.appearanceName) { _, host in
            try await Task.sleep(nanoseconds: 100_000_000)
            try self.saveView(host, name: "workspace", directory: directory, calibrated: true,
                              state: ["view": "Production DashboardView", "language": "en", "theme": model.theme.rawValue,
                                      "input": input.lastPathComponent, "inputSHA256": inputHash,
                                      "assetEligibility": "Review candidate; synthetic input, no UI reconstructed"])
        }
        model.begin(FileOperation(id: "image.crop", title: "Crop Image"), inputs: [input])
        try await withHost(ImageCropView(model: model, inputs: [input]), size: NSSize(width: 820, height: 590),
                           appearance: model.theme.appearanceName) { _, host in
            try await self.waitFor("The actual crop canvas must finish decoding the synthetic image") {
                self.firstView(ImageCropCanvas.self, in: host)?.selection.sourceWidth == 640
            }
            let canvas = try XCTUnwrap(self.firstView(ImageCropCanvas.self, in: host))
            let crop = ImageCropRegion(x: 96, y: 48, width: 448, height: 288, sourceWidth: 640, sourceHeight: 400)
            canvas.onChange?(crop)
            try await self.waitFor("The production crop binding must reflect the review fixture") { canvas.selection == crop }
            try self.saveView(host, name: "image-crop", directory: directory, calibrated: true,
                              state: ["view": "Production ImageCropView and native ImageCropCanvas",
                                      "language": "en", "theme": model.theme.rawValue,
                                      "input": input.lastPathComponent, "inputSHA256": inputHash,
                                      "stateSetup": "Crop selected through the actual canvas binding; no key or drag events",
                                      "crop": [96, 48, 448, 288], "assetEligibility": "Review candidate; synthetic input"])
        }
        XCTAssertEqual(NativeReviewBitmap.digest(try Data(contentsOf: input)), inputHash)
    }

    @MainActor
    private func saveView(_ view: NSView, name: String, directory: URL, calibrated: Bool, state: [String: Any]) throws {
        for scale in calibrated ? [1, 2] : [1] {
            let bitmap = try NativeReviewBitmap.render(view, scale: scale)
            var evidence = state
            evidence["densityCalibration"] = calibrated ? "passed-numerical-gate" : "failed-or-mixed; 1x evidence only"
            try NativeReviewBitmap.save(bitmap, of: view, scale: scale, name: name + "-\(scale)x", directory: directory, state: evidence)
        }
    }

    @MainActor
    private func withHost<V: View, Result>(_ root: V, size: NSSize, appearance: NSAppearance.Name,
        body: (NSWindow, NSHostingView<V>) async throws -> Result) async throws -> Result {
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: 40, y: 40), size: size),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Lemulip Native Rendering Review"
        window.appearance = NSAppearance(named: appearance)
        let host = NSHostingView(rootView: root)
        window.contentView = host
        window.setContentSize(size)
        window.orderFrontRegardless()
        defer { window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded()
        // Rendering and read-only accessibility checks do not require a key
        // window. Existing keyboard harnesses keep their strict prerequisites.
        try await Task.sleep(nanoseconds: 60_000_000)
        return try await body(window, host)
    }

    @MainActor
    private func waitFor(_ message: String, condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        guard condition() else { throw NativeReviewFailure(message) }
    }

    @MainActor
    private func firstView<V: NSView>(_ type: V.Type, in view: NSView) -> V? {
        if let match = view as? V { return match }
        for child in view.subviews {
            if let match = firstView(type, in: child) { return match }
        }
        return nil
    }

    @MainActor
    private func control(_ identifier: String, roles: Set<String>, in view: NSView) -> NativeAccessibilityReview.Node? {
        NativeAccessibilityReview.walk(view).nodes.first { element in
            element.identifier == identifier && roles.contains(element.role?.rawValue ?? "")
        }
    }

    @MainActor
    private func imageFixture(in directory: URL) throws -> URL {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 640, pixelsHigh: 400,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let bytes = try XCTUnwrap(bitmap.bitmapData)
        for y in 0..<400 {
            for x in 0..<640 {
                let offset = y * bitmap.bytesPerRow + x * 4
                let alternate = ((x / 40) + (y / 40)).isMultiple(of: 2)
                bytes[offset] = alternate ? 196 : 85
                bytes[offset + 1] = alternate ? 221 : 139
                bytes[offset + 2] = alternate ? 130 : 97
                bytes[offset + 3] = 255
            }
        }
        let file = directory.appendingPathComponent("synthetic-orchard-grid.png")
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: file)
        return file
    }
}

@MainActor
private final class CaptureSilentCuePlayer: SelectionCuePlaying {
    private(set) var playCount = 0
    func play(completion: @escaping @MainActor () -> Void) -> Bool { playCount += 1; return false }
    func stop() {}
}
#endif
