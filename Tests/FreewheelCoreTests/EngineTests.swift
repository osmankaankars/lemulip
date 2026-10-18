import XCTest
@testable import FreewheelCore
#if os(macOS)
import Darwin
#endif

final class EngineTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("freewheel-engine-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }
    override func tearDownWithError() throws { if let root { try FileManager.default.removeItem(at: root) } }

    func testBatchTextConversionAndConcurrencyNeverOverwriteInputs() async throws {
        let source = root.appendingPathComponent("subtitles.srt")
        let content = "1\n00:00:00,000 --> 00:00:01,000\nHello\n"
        try content.write(to: source, atomically: true, encoding: .utf8)
        let engine = ConversionEngine()
        let operation = FileOperation(id: "convert.vtt", title: "VTT", outputExtension: "vtt")
        async let first = engine.run(inputs: [source], operation: operation)
        async let second = engine.run(inputs: [source], operation: operation)
        let results = try await [first, second]
        XCTAssertEqual(Set(results.flatMap(\.outputs)).count, 2)
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), content)
        for output in results.flatMap(\.outputs) { XCTAssertTrue(try String(contentsOf: output, encoding: .utf8).hasPrefix("WEBVTT")) }
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains(where: { $0.hasPrefix(".freewheel-") }))
    }

    func testInvalidBatchLeavesNoPartialConvertedFiles() async throws {
        let valid = root.appendingPathComponent("valid.srt"), invalid = root.appendingPathComponent("invalid.srt")
        try "1\n00:00:00,000 --> 00:00:01,000\nHello\n".write(to: valid, atomically: true, encoding: .utf8)
        try "This is not a subtitle".write(to: invalid, atomically: true, encoding: .utf8)
        do {
            _ = try await ConversionEngine().run(inputs: [valid, invalid], operation: FileOperation(id: "convert.vtt", title: "VTT"))
            XCTFail("Converted an invalid batch")
        } catch { XCTAssertTrue(error is FreewheelError) }
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: root.path)), ["valid.srt", "invalid.srt"])
    }

    func testRemoteURLAndUnsafeExtensionAreRejected() async throws {
        do {
            _ = try await ConversionEngine().run(inputs: [URL(string: "https://example.com/file.png")!], operation: FileOperation(id: "convert.jpg", title: "JPG"))
            XCTFail("Accepted a remote input")
        } catch { XCTAssertTrue(error is FreewheelError) }
        let input = root.appendingPathComponent("table.csv")
        try "a,b\n1,2\n".write(to: input, atomically: true, encoding: .utf8)
        do {
            _ = try await ConversionEngine().run(inputs: [input], operation: FileOperation(id: "convert.tsv", title: "TSV", outputExtension: "../../outside"))
            XCTFail("Accepted an unsafe extension")
        } catch { XCTAssertTrue(error is FreewheelError) }
    }

    func testSelectedCropRejectsInvalidAndOverflowingBoundsBeforeStaging() async throws {
        let input = root.appendingPathComponent("input.png")
        try Data([0]).write(to: input) // Bounds must fail before any image decoder runs.
        let regions = [
            ImageCropRegion(x: -1, y: 0, width: 1, height: 1, sourceWidth: 10, sourceHeight: 10),
            ImageCropRegion(x: 0, y: -1, width: 1, height: 1, sourceWidth: 10, sourceHeight: 10),
            ImageCropRegion(x: 0, y: 0, width: 0, height: 1, sourceWidth: 10, sourceHeight: 10),
            ImageCropRegion(x: 0, y: 0, width: 1, height: Int.min, sourceWidth: 10, sourceHeight: 10),
            ImageCropRegion(x: 10, y: 0, width: 1, height: 1, sourceWidth: 10, sourceHeight: 10),
            ImageCropRegion(x: Int.max, y: 0, width: Int.max, height: 1, sourceWidth: Int.max, sourceHeight: 10),
            ImageCropRegion(x: 0, y: Int.max, width: 1, height: Int.max, sourceWidth: 10, sourceHeight: Int.max),
            ImageCropRegion(x: 0, y: 0, width: 1, height: 1, sourceWidth: Int.min, sourceHeight: 10),
            ImageCropRegion(x: 0, y: 0, width: 1, height: 1, sourceWidth: 20_000, sourceHeight: 1),
            ImageCropRegion(x: 0, y: 0, width: 1, height: 1, sourceWidth: 8_000, sourceHeight: 6_000)
        ]
        for region in regions {
            var options = ConversionOptions(); options.imageCrop = region
            do {
                _ = try await ConversionEngine().run(inputs: [input], operation: FileOperation(id: "image.crop", title: "Crop"), options: options)
                XCTFail("Invalid crop bounds were accepted: \(region)")
            } catch FreewheelError.invalidInput { }
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["input.png"])
    }

    func testSelectedCropRequiresOneImageAndTheCropOperation() async throws {
        let first = root.appendingPathComponent("first.png"), second = root.appendingPathComponent("second.png")
        let text = root.appendingPathComponent("document.txt")
        for file in [first, second, text] { try Data([0]).write(to: file) }
        var options = ConversionOptions()
        options.imageCrop = ImageCropRegion(x: 0, y: 0, width: 2, height: 2, sourceWidth: 10, sourceHeight: 10)
        for (inputs, id) in [([first], "convert.png"), ([first, second], "image.crop"), ([text], "image.crop")] {
            do {
                _ = try await ConversionEngine().run(inputs: inputs, operation: FileOperation(id: id, title: "Operation"), options: options)
                XCTFail("A selection must not be applied to another operation or several files")
            } catch FreewheelError.invalidInput { }
        }
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: root.path)), ["first.png", "second.png", "document.txt"])
    }

    func testUnsupportedSelectedCropNeverFallsBackToACenteredExternalCrop() async throws {
        let input = root.appendingPathComponent("vector.svg")
        let content = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\"><rect width=\"10\" height=\"10\"/></svg>"
        try content.write(to: input, atomically: true, encoding: .utf8)
        var options = ConversionOptions()
        options.imageCrop = ImageCropRegion(x: 0, y: 0, width: 2, height: 2, sourceWidth: 10, sourceHeight: 10)
        do {
            _ = try await ConversionEngine().run(inputs: [input], operation: FileOperation(id: "image.crop", title: "Crop", outputExtension: "png"), options: options)
            XCTFail("A selected region must not become a centered ImageMagick crop")
        } catch FreewheelError.unsupported(let message) {
            #if os(macOS)
            XCTAssertTrue(message.contains("SVG"))
            #else
            XCTAssertTrue(message.contains("native macOS"))
            #endif
        }
        XCTAssertEqual(try String(contentsOf: input, encoding: .utf8), content)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["vector.svg"])
    }

    func testCropMovementAndAllHandlesStayInsideTheImageWithoutCrossing() throws {
        let region = ImageCropRegion(x: 20, y: 10, width: 100, height: 80, sourceWidth: 200, sourceHeight: 120)
        XCTAssertEqual(ImageCropGeometry.moved(region, dx: 999, dy: -999),
            ImageCropRegion(x: 100, y: 0, width: 100, height: 80, sourceWidth: 200, sourceHeight: 120))
        XCTAssertEqual(ImageCropGeometry.resized(region, handle: .left, dx: 999, dy: 0),
            ImageCropRegion(x: 119, y: 10, width: 1, height: 80, sourceWidth: 200, sourceHeight: 120))
        for handle in ImageCropHandle.allCases {
            for (dx, dy) in [(-999.0, -999.0), (-999, 999), (999, -999), (999, 999)] {
                let resized = ImageCropGeometry.resized(region, handle: handle, dx: dx, dy: dy)
                XCTAssertNoThrow(try resized.validateBounds(), "Handle \(handle) crossed its opposite edge or the image boundary")
                XCTAssertEqual(resized.sourceWidth, 200); XCTAssertEqual(resized.sourceHeight, 120)
            }
        }
    }

    func testFixedRatioCropKeepsItsAnchorWhenShrinkingOrResizingAnEdge() throws {
        let square = ImageCropRegion(x: 20, y: 20, width: 100, height: 100, sourceWidth: 200, sourceHeight: 200)
        XCTAssertEqual(ImageCropGeometry.resized(square, handle: .bottomRight, dx: -40, dy: 0, aspectRatio: 1),
            ImageCropRegion(x: 20, y: 20, width: 60, height: 60, sourceWidth: 200, sourceHeight: 200))
        XCTAssertEqual(ImageCropGeometry.resized(square, handle: .topLeft, dx: 40, dy: 0, aspectRatio: 1),
            ImageCropRegion(x: 60, y: 60, width: 60, height: 60, sourceWidth: 200, sourceHeight: 200))
        let wide = ImageCropRegion(x: 20, y: 40, width: 80, height: 40, sourceWidth: 200, sourceHeight: 120)
        XCTAssertEqual(ImageCropGeometry.resized(wide, handle: .right, dx: 40, dy: 0, aspectRatio: 2),
            ImageCropRegion(x: 20, y: 30, width: 120, height: 60, sourceWidth: 200, sourceHeight: 120))
        let box = ImageCropRegion(x: 10, y: 20, width: 100, height: 80, sourceWidth: 200, sourceHeight: 200)
        XCTAssertEqual(ImageCropGeometry.fitted(box, aspectRatio: 2),
            ImageCropRegion(x: 10, y: 35, width: 100, height: 50, sourceWidth: 200, sourceHeight: 200))
    }

    func testCropSelectionHandlesEveryDragQuadrantAndNonfiniteInputs() throws {
        for (x, y) in [(30.0, 20.0), (70, 20), (30, 80), (70, 80)] {
            XCTAssertEqual(ImageCropGeometry.selected(fromX: 50, fromY: 50, toX: x, toY: y, sourceWidth: 200, sourceHeight: 200),
                ImageCropRegion(x: Int(min(50, x)), y: Int(min(50, y)), width: 20, height: 30, sourceWidth: 200, sourceHeight: 200))
        }
        let region = ImageCropRegion(x: 20, y: 10, width: 100, height: 80, sourceWidth: 200, sourceHeight: 120)
        XCTAssertEqual(ImageCropGeometry.moved(region, dx: .nan, dy: .infinity), region)
        for handle in ImageCropHandle.allCases {
            XCTAssertNoThrow(try ImageCropGeometry.resized(region, handle: handle, dx: -.infinity, dy: .nan, aspectRatio: .infinity).validateBounds())
        }
        XCTAssertNoThrow(try ImageCropGeometry.selected(fromX: .nan, fromY: .infinity, toX: -.infinity, toY: .nan,
            sourceWidth: Int.max, sourceHeight: Int.min, aspectRatio: .nan).validateBounds())
    }

    func testAudioSelectionRejectsInvalidRangesBeforeCreatingOutput() async throws {
        let input = root.appendingPathComponent("recording.wav")
        try Data([0]).write(to: input)
        let invalid = [
            AudioTrimSelection(startSeconds: -1, endSeconds: 1, sourceDuration: 5),
            AudioTrimSelection(startSeconds: 1, endSeconds: 1, sourceDuration: 5),
            AudioTrimSelection(startSeconds: 2, endSeconds: 1, sourceDuration: 5),
            AudioTrimSelection(startSeconds: 0, endSeconds: 6, sourceDuration: 5),
            AudioTrimSelection(startSeconds: .nan, endSeconds: 1, sourceDuration: 5),
            AudioTrimSelection(startSeconds: 0, endSeconds: .infinity, sourceDuration: 5),
            AudioTrimSelection(startSeconds: 0, endSeconds: 1, sourceDuration: .infinity),
            AudioTrimSelection(startSeconds: 0, endSeconds: 1, sourceDuration: 0)
        ]
        for selection in invalid {
            var options = ConversionOptions(); options.audioTrim = selection
            do {
                _ = try await ConversionEngine().run(inputs: [input],
                    operation: FileOperation(id: "media.trim", title: "Trim", outputExtension: "wav"), options: options)
                XCTFail("An invalid audio selection was accepted")
            } catch FreewheelError.invalidInput { }
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["recording.wav"])
    }

    func testAudioSelectionRequiresOneAudioFileAndTheTrimOperation() async throws {
        let first = root.appendingPathComponent("first.wav"), second = root.appendingPathComponent("second.wav")
        let video = root.appendingPathComponent("clip.mp4")
        for input in [first, second, video] { try Data([0]).write(to: input) }
        var options = ConversionOptions()
        options.audioTrim = AudioTrimSelection(startSeconds: 0, endSeconds: 1, sourceDuration: 5)
        for (inputs, id, ext) in [([first, second], "media.trim", "wav"),
                                  ([video], "media.trim", "wav"),
                                  ([first], "convert.wav", "wav"),
                                  ([first], "media.trim", "mp4")] {
            do {
                _ = try await ConversionEngine().run(inputs: inputs,
                    operation: FileOperation(id: id, title: "Operation", outputExtension: ext), options: options)
                XCTFail("A waveform selection was applied to the wrong input, operation, or output")
            } catch FreewheelError.invalidInput { }
        }
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: root.path)), ["first.wav", "second.wav", "clip.mp4"])
        let audioTrim = try XCTUnwrap(Catalog.operations(for: [first], mode: .tools).first { $0.id == "media.trim" })
        let videoTrim = try XCTUnwrap(Catalog.operations(for: [video], mode: .tools).first { $0.id == "media.trim" })
        #if os(macOS)
        XCTAssertNil(audioTrim.dependency)
        XCTAssertNil(videoTrim.dependency)
        #else
        XCTAssertEqual(audioTrim.dependency, "ffmpeg")
        XCTAssertEqual(videoTrim.dependency, "ffmpeg")
        #endif
    }

    func testVideoSelectionRejectsInvalidRangesBeforeCreatingOutput() async throws {
        let input = root.appendingPathComponent("clip.mp4")
        try Data([0]).write(to: input)
        let invalid = [
            VideoTrimSelection(startSeconds: -1, endSeconds: 1, sourceDuration: 5),
            VideoTrimSelection(startSeconds: 1, endSeconds: 1, sourceDuration: 5),
            VideoTrimSelection(startSeconds: 2, endSeconds: 1, sourceDuration: 5),
            VideoTrimSelection(startSeconds: 0, endSeconds: 6, sourceDuration: 5),
            VideoTrimSelection(startSeconds: .nan, endSeconds: 1, sourceDuration: 5),
            VideoTrimSelection(startSeconds: 0, endSeconds: .infinity, sourceDuration: 5),
            VideoTrimSelection(startSeconds: 0, endSeconds: 1, sourceDuration: .infinity),
            VideoTrimSelection(startSeconds: 0, endSeconds: 1, sourceDuration: 0)
        ]
        for selection in invalid {
            var options = ConversionOptions(); options.videoTrim = selection
            do {
                _ = try await ConversionEngine().run(inputs: [input],
                    operation: FileOperation(id: "media.trim", title: "Trim", outputExtension: "mp4"), options: options)
                XCTFail("An invalid video selection was accepted")
            } catch FreewheelError.invalidInput { }
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["clip.mp4"])
    }

    func testVideoSelectionRequiresOneVideoAndExclusiveTrimRoute() async throws {
        let first = root.appendingPathComponent("first.mp4"), second = root.appendingPathComponent("second.mov")
        let audio = root.appendingPathComponent("recording.wav")
        for input in [first, second, audio] { try Data([0]).write(to: input) }
        var options = ConversionOptions()
        options.videoTrim = VideoTrimSelection(startSeconds: 0, endSeconds: 1, sourceDuration: 5)
        let cases: [([URL], String, String)] = [
            ([first, second], "media.trim", "mp4"), ([audio], "media.trim", "mp4"),
            ([first, audio], "media.trim", "mp4"), ([first], "convert.mp4", "mp4"),
            ([first], "media.trim", "wav"), ([first], "media.trim", "webm")
        ]
        for (inputs, id, ext) in cases {
            do {
                _ = try await ConversionEngine().run(inputs: inputs,
                    operation: FileOperation(id: id, title: "Operation", outputExtension: ext), options: options)
                XCTFail("A timeline selection used the wrong inputs, operation, or output")
            } catch FreewheelError.invalidInput { }
        }
        let trim = FileOperation(id: "media.trim", title: "Trim", outputExtension: "mp4")
        for cropConflict in [false, true] {
            var conflicting = options
            if cropConflict {
                conflicting.imageCrop = ImageCropRegion(x: 0, y: 0, width: 1, height: 1, sourceWidth: 1, sourceHeight: 1)
            } else {
                conflicting.audioTrim = AudioTrimSelection(startSeconds: 0, endSeconds: 1, sourceDuration: 5)
            }
            do {
                _ = try await ConversionEngine().run(inputs: [first], operation: trim, options: conflicting)
                XCTFail("Two different editor selections were accepted together")
            } catch FreewheelError.invalidInput { }
        }
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: root.path)), ["first.mp4", "second.mov", "recording.wav"])
    }

    func testVideoTrimGeometryAndFieldsPreserveTinyAndFullEndpoints() throws {
        let totals: [Double] = [0.000_5, 0.007_3, 1.000_9, 8, 36_000.000_9]
        for total in totals {
            let full = VideoTrimGeometry.fullDuration(total)
            XCTAssertEqual(full.endSeconds, total)
            XCTAssertNoThrow(try full.validate())
            XCTAssertEqual(VideoTrimTime.selection(startText: VideoTrimTime.string(0),
                endText: VideoTrimTime.string(total), preserving: full), full)
            let changes: [Double] = [-100, 0, total, 100, .nan, .infinity]
            for seconds in changes {
                XCTAssertNoThrow(try VideoTrimGeometry.startChanged(full, to: seconds).validate())
                XCTAssertNoThrow(try VideoTrimGeometry.endChanged(full, to: seconds).validate())
                XCTAssertNoThrow(try VideoTrimGeometry.moved(full, by: seconds).validate())
            }
        }
        let nearEnd = VideoTrimSelection(startSeconds: 1.970_9, endSeconds: 2.000_9, sourceDuration: 2.000_9)
        XCTAssertEqual(VideoTrimTime.selection(startText: VideoTrimTime.string(nearEnd.startSeconds),
            endText: VideoTrimTime.string(nearEnd.endSeconds), preserving: nearEnd), nearEnd)
        let moved = VideoTrimGeometry.moved(nearEnd, by: -100)
        XCTAssertEqual(moved.startSeconds, 0)
        XCTAssertEqual(moved.durationSeconds, nearEnd.durationSeconds, accuracy: 0.000_000_001)
        XCTAssertNil(VideoTrimTime.selection(startText: "NaN", endText: "2", preserving: nearEnd))
        XCTAssertNil(VideoTrimTime.selection(startText: "1", endText: "1", preserving: nearEnd))
        XCTAssertThrowsError(try nearEnd.validate(sourceDuration: 2.01))
    }

    func testVideoCropRejectsInvalidOrOverflowingBoundsBeforeStaging() async throws {
        let input = root.appendingPathComponent("clip.mov")
        try Data([0]).write(to: input)
        let invalid = [
            VideoCropRegion(x: -1, y: 0, width: 2, height: 2, sourceWidth: 10, sourceHeight: 10, sourceDuration: 1),
            VideoCropRegion(x: 0, y: -1, width: 2, height: 2, sourceWidth: 10, sourceHeight: 10, sourceDuration: 1),
            VideoCropRegion(x: 0, y: 0, width: 1, height: 2, sourceWidth: 10, sourceHeight: 10, sourceDuration: 1),
            VideoCropRegion(x: 0, y: 0, width: 2, height: 0, sourceWidth: 10, sourceHeight: 10, sourceDuration: 1),
            VideoCropRegion(x: 9, y: 0, width: 2, height: 2, sourceWidth: 10, sourceHeight: 10, sourceDuration: 1),
            VideoCropRegion(x: Int.max, y: 0, width: Int.max, height: 2, sourceWidth: Int.max, sourceHeight: 10, sourceDuration: 1),
            VideoCropRegion(x: 0, y: 0, width: 2, height: 2, sourceWidth: 20_000, sourceHeight: 10, sourceDuration: 1),
            VideoCropRegion(x: 0, y: 0, width: 8_000, height: 6_000, sourceWidth: 8_000, sourceHeight: 6_000, sourceDuration: 1),
            VideoCropRegion(x: 0, y: 0, width: 2, height: 2, sourceWidth: 10, sourceHeight: 10, sourceDuration: .nan),
            VideoCropRegion(x: 0, y: 0, width: 2, height: 2, sourceWidth: 10, sourceHeight: 10, sourceDuration: 0)
        ]
        for crop in invalid {
            var options = ConversionOptions(); options.videoCrop = crop
            do {
                _ = try await ConversionEngine().run(inputs: [input],
                    operation: FileOperation(id: "media.crop", title: "Crop Video", outputExtension: "mp4"), options: options)
                XCTFail("An invalid video crop was accepted")
            } catch FreewheelError.invalidInput { }
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["clip.mov"])
    }

    func testVideoCropRequiresOneVideoAndExclusiveNativeCropRoute() async throws {
        let first = root.appendingPathComponent("first.mov"), second = root.appendingPathComponent("second.mp4")
        let audio = root.appendingPathComponent("sound.wav"), image = root.appendingPathComponent("image.png")
        for input in [first, second, audio, image] { try Data([0]).write(to: input) }
        var options = ConversionOptions()
        options.videoCrop = VideoCropRegion(x: 1, y: 2, width: 4, height: 6,
                                            sourceWidth: 10, sourceHeight: 10, sourceDuration: 1)
        let cases: [([URL], String, String)] = [
            ([first, second], "media.crop", "mp4"), ([audio], "media.crop", "mp4"),
            ([image], "media.crop", "mp4"), ([first, audio], "media.crop", "mp4"),
            ([first], "media.trim", "mp4"), ([first], "convert.mp4", "mp4"),
            ([first], "media.crop", "wav"), ([first], "media.crop", "webm")
        ]
        for (inputs, id, ext) in cases {
            do {
                _ = try await ConversionEngine().run(inputs: inputs,
                    operation: FileOperation(id: id, title: "Operation", outputExtension: ext), options: options)
                XCTFail("A video crop used the wrong input, operation, or output")
            } catch FreewheelError.invalidInput { }
        }
        let cropOperation = FileOperation(id: "media.crop", title: "Crop Video", outputExtension: "mp4")
        for conflict in 0..<3 {
            var conflicting = options
            if conflict == 0 { conflicting.imageCrop = options.videoCrop?.imageRegion }
            if conflict == 1 { conflicting.audioTrim = AudioTrimSelection(startSeconds: 0, endSeconds: 1, sourceDuration: 1) }
            if conflict == 2 { conflicting.videoTrim = VideoTrimSelection(startSeconds: 0, endSeconds: 1, sourceDuration: 1) }
            do {
                _ = try await ConversionEngine().run(inputs: [first], operation: cropOperation, options: conflicting)
                XCTFail("A video crop was combined with another editor selection")
            } catch FreewheelError.invalidInput { }
        }
        do {
            _ = try await ConversionEngine().run(inputs: [first], operation: cropOperation)
            XCTFail("A missing crop selection reached a generic converter")
        } catch FreewheelError.invalidInput { }
        let catalogCrop = Catalog.operations(for: [first], mode: .tools).first { $0.id == "media.crop" }
        #if os(macOS)
        XCTAssertNil(try XCTUnwrap(catalogCrop).dependency)
        #else
        XCTAssertNil(catalogCrop)
        #endif
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: root.path)), ["first.mov", "second.mp4", "sound.wav", "image.png"])
    }

    func testVideoCropGeometryKeepsEvenOutputInsideTheUprightSource() throws {
        let selected = ImageCropRegion(x: 3, y: 1, width: 7, height: 7, sourceWidth: 11, sourceHeight: 9)
        let normalized = VideoCropGeometry.normalized(selected)
        XCTAssertEqual(normalized, ImageCropRegion(x: 3, y: 1, width: 6, height: 6, sourceWidth: 11, sourceHeight: 9))
        let direct = VideoCropRegion(imageRegion: selected, sourceDuration: 1)
        XCTAssertEqual(direct.outputWidth, 6)
        XCTAssertEqual(direct.outputHeight, 6)
        XCTAssertNoThrow(try direct.validate())
        XCTAssertThrowsError(try direct.validate(sourceWidth: 12, sourceHeight: 9, sourceDuration: 1))
        XCTAssertThrowsError(try direct.validate(sourceWidth: 11, sourceHeight: 9, sourceDuration: 1.01))
        for handle in ImageCropHandle.allCases {
            for change in [-1_000.0, -1, 0, 1, 1_000, .nan, .infinity] {
                let resized = ImageCropGeometry.resized(selected, handle: handle, dx: change, dy: -change,
                                                        aspectRatio: 4.0 / 3.0)
                let region = VideoCropGeometry.normalized(resized)
                XCTAssertNoThrow(try VideoCropRegion(imageRegion: region, sourceDuration: 1).validate())
                XCTAssertEqual(region.width % 2, 0)
                XCTAssertEqual(region.height % 2, 0)
                XCTAssertGreaterThanOrEqual(region.width, 2)
                XCTAssertGreaterThanOrEqual(region.height, 2)
            }
        }
        let oversized = ImageCropRegion(x: Int.max, y: Int.min, width: Int.max, height: Int.min,
                                        sourceWidth: 101, sourceHeight: 99)
        XCTAssertEqual(VideoCropGeometry.normalized(oversized),
            ImageCropRegion(x: 1, y: 0, width: 100, height: 2, sourceWidth: 101, sourceHeight: 99))
    }

    func testAudioTrimHandlesPreserveLengthAndNeverCrossOrRoundPastEOF() throws {
        for total in [0.000_5, 0.007_3, 1.000_9, 8.0, 36_000.000_9] {
            let full = AudioTrimGeometry.fullDuration(total)
            XCTAssertEqual(full.endSeconds, total)
            XCTAssertNoThrow(try full.validate())
            for seconds in [-999.0, 0, 0.005, total / 2, total, total + 999, .nan, .infinity] {
                XCTAssertNoThrow(try AudioTrimGeometry.startChanged(full, to: seconds).validate())
                XCTAssertNoThrow(try AudioTrimGeometry.endChanged(full, to: seconds).validate())
                XCTAssertNoThrow(try AudioTrimGeometry.moved(full, by: seconds).validate())
            }
        }
        let selected = AudioTrimSelection(startSeconds: 1.250, endSeconds: 2.875, sourceDuration: 5.000_9)
        let moved = AudioTrimGeometry.moved(selected, by: 100)
        XCTAssertEqual(moved.endSeconds, selected.sourceDuration)
        XCTAssertEqual(moved.durationSeconds, selected.durationSeconds, accuracy: 0.000_000_001)
        XCTAssertEqual(AudioTrimGeometry.startChanged(selected, to: 99).startSeconds, 2.865, accuracy: 0.000_000_001)
        XCTAssertEqual(AudioTrimGeometry.endChanged(selected, to: -99).endSeconds, 1.260, accuracy: 0.000_000_001)
        XCTAssertThrowsError(try selected.validate(sourceDuration: 6))
    }

    func testAudioWaveformPeaksUseBothChannelsAndPreserveTimeGaps() throws {
        var samples: [Float] = []
        for frame in 0..<4_000 {
            samples.append(contentsOf: frame < 2_000 ? [0.1, -0.8] : [0.3, -0.3])
        }
        var whole = try AudioWaveformAccumulator(durationSeconds: 1, bucketCount: 4)
        try samples.withUnsafeBufferPointer { values in
            try whole.append(values, frames: 4_000, channelCount: 2, sampleRate: 8_000, presentationSeconds: 0.25)
        }
        XCTAssertEqual(whole.peaks, [0, 0.8, 0.3, 0])
        // A decoder choosing different packet sizes must produce the same peaks.
        var chunked = try AudioWaveformAccumulator(durationSeconds: 1, bucketCount: 4)
        for offset in stride(from: 0, to: 4_000, by: 137) {
            let frames = min(137, 4_000 - offset)
            try samples.withUnsafeBufferPointer { values in
                let chunk = UnsafeBufferPointer(start: values.baseAddress! + offset * 2, count: frames * 2)
                try chunked.append(chunk, frames: frames, channelCount: 2, sampleRate: 8_000,
                                   presentationSeconds: 0.25 + Double(offset) / 8_000)
            }
        }
        XCTAssertEqual(chunked.peaks, whole.peaks)
        // Decimal timing gaps expose floating-point bucket-boundary drift.
        // A peak at exactly 0.5 seconds must not leak into the preceding bucket.
        let ramp = (0..<8_000).map { Float($0 / 800 + 1) / 10 }
        for packetSize in [137, 1_024, 4_096] {
            var decimal = try AudioWaveformAccumulator(durationSeconds: 1.1, bucketCount: 11)
            for offset in stride(from: 0, to: ramp.count, by: packetSize) {
                let frames = min(packetSize, ramp.count - offset)
                try ramp.withUnsafeBufferPointer { values in
                    let chunk = UnsafeBufferPointer(start: values.baseAddress! + offset, count: frames)
                    try decimal.append(chunk, frames: frames, channelCount: 1, sampleRate: 8_000,
                                       presentationSeconds: 0.1 + Double(offset) / 8_000)
                }
            }
            XCTAssertEqual(decimal.peaks, [0] + (1...10).map { Float($0) / 10 })
        }
    }

    func testAudioTimestampParserRejectsMalformedValuesAndFormatsFractionalEOF() throws {
        for (text, expected) in [("1.250", 1.25), ("01:02.345", 62.345), ("01:02:03.004", 3_723.004),
                                 (" 00:00,125 ", 0.125), ("0.000500", 0.0005), ("65:01", 3_901)] {
            XCTAssertEqual(try XCTUnwrap(AudioTrimTime.parse(text)), expected, accuracy: 0.000_000_001)
        }
        for text in ["", " ", "NaN", "inf", "1e3", "+1", "-1", "1:60", "1:60:00", "1::2",
                     "1:2:3:4", "1.2.3", "1,2.3", "01:02x", "1 :02", "1: 02", ":20", "20:", "１"] {
            XCTAssertNil(AudioTrimTime.parse(text), "Malformed timestamp accepted: \(text)")
        }
        XCTAssertEqual(AudioTrimTime.string(1.0009), "00:01.001")
        XCTAssertEqual(AudioTrimTime.string(0.0005), "00:00.000500")
        XCTAssertEqual(AudioTrimTime.string(3_600.25), "01:00:00.250")
        XCTAssertEqual(AudioTrimTime.string(.nan), "—")
        XCTAssertEqual(AudioTrimTime.string(.greatestFiniteMagnitude), "—")
        XCTAssertEqual(AudioTrimGeometry.fullDuration(1.0009).endSeconds, 1.0009)
        for original in [AudioTrimGeometry.fullDuration(1.0009), AudioTrimGeometry.fullDuration(0.0005),
                         AudioTrimSelection(startSeconds: 0.9909, endSeconds: 1.0009, sourceDuration: 1.0009)] {
            XCTAssertEqual(AudioTrimTime.selection(startText: AudioTrimTime.string(original.startSeconds),
                endText: AudioTrimTime.string(original.endSeconds), preserving: original), original)
            XCTAssertNil(AudioTrimTime.selection(startText: "not a time", endText: AudioTrimTime.string(original.endSeconds), preserving: original))
            XCTAssertNil(AudioTrimTime.selection(startText: AudioTrimTime.string(original.startSeconds), endText: "", preserving: original))
        }
        let original = AudioTrimSelection(startSeconds: 0.2, endSeconds: 0.8, sourceDuration: 1.0009)
        XCTAssertEqual(AudioTrimTime.selection(startText: "00:00.200", endText: "00:01.001", preserving: original)?.endSeconds, 1.0009)
        XCTAssertNil(AudioTrimTime.selection(startText: "0.8", endText: "0.2", preserving: original))
        XCTAssertNil(AudioTrimTime.selection(startText: "0.2", endText: "0.2", preserving: original))
    }

    func testAudioWaveformSummaryStaysBoundedForLongRecordingsAndIgnoresPreroll() throws {
        var summary = try AudioWaveformAccumulator(durationSeconds: 36_000, bucketCount: 4_096)
        let values: [Float] = [0.5, .nan, .infinity, -0.75, 2]
        try values.withUnsafeBufferPointer { samples in
            try summary.append(samples, frames: values.count, channelCount: 1, sampleRate: 8_000, presentationSeconds: -1)
            XCTAssertFalse(summary.hasSamples)
            try summary.append(samples, frames: values.count, channelCount: 1, sampleRate: 8_000, presentationSeconds: 35_999)
        }
        XCTAssertEqual(summary.peaks.count, 4_096)
        XCTAssertEqual(summary.peaks.last, 1)
        XCTAssertEqual(summary.peaks.dropLast().reduce(0, +), 0)
        XCTAssertThrowsError(try AudioWaveformAccumulator(durationSeconds: 1, bucketCount: 4_097))
        XCTAssertThrowsError(try AudioWaveformAccumulator(durationSeconds: .nan, bucketCount: 4))
        try values.withUnsafeBufferPointer { samples in
            XCTAssertThrowsError(try summary.append(samples, frames: 5, channelCount: 2, sampleRate: 8_000, presentationSeconds: 0))
            XCTAssertThrowsError(try summary.append(samples, frames: 5, channelCount: 1, sampleRate: .nan, presentationSeconds: 0))
        }
    }

    func testProcessDrainsBothLargePipesAndBoundsMemory() async throws {
        guard let awk = EngineLocator.find("awk") else { throw XCTSkip("awk is unavailable") }
        let program = "BEGIN { for (i=0; i<6000; i++) { print \"stdout line with enough bytes to fill a pipe\"; print \"stderr line with enough bytes to fill a pipe\" > \"/dev/stderr\" } }"
        let result = try await ProcessRunner.run(executable: awk, arguments: [program], maximumOutputBytes: 16_384, timeout: 10)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.standardOutput.count, 16_384)
        XCTAssertEqual(result.standardError.count, 16_384)
    }

    func testProcessCancellationAndTimeoutStopChild() async throws {
        guard let sleep = EngineLocator.find("sleep") else { throw XCTSkip("sleep is unavailable") }
        let start = Date()
        let running = Task { try await ProcessRunner.run(executable: sleep, arguments: ["30"], timeout: 40) }
        try await Task.sleep(nanoseconds: 100_000_000)
        running.cancel()
        do { _ = try await running.value; XCTFail("Cancellation was ignored") }
        catch { XCTAssertTrue(error is FreewheelError || error is CancellationError) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
        do { _ = try await ProcessRunner.run(executable: sleep, arguments: ["30"], timeout: 0.1); XCTFail("Timeout was ignored") }
        catch { XCTAssertTrue(error.localizedDescription.contains("time limit")) }
    }

    func testOfficeProfileURLAndIPCNameMatchLibreOffice() throws {
        let profile = root.appendingPathComponent("office profile % # []", isDirectory: true)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: false)
        let url = try ExternalConverters.officeProfileURL(profile)
        XCTAssertTrue(url.hasSuffix("/office%20profile%20%25%20%23%20%5B%5D"))
        let canonicalProfile = try XCTUnwrap(URL(string: url))
        let sourceInfo = try FileManager.default.attributesOfItem(atPath: profile.path)
        let resolvedInfo = try FileManager.default.attributesOfItem(atPath: canonicalProfile.path)
        XCTAssertEqual(try XCTUnwrap(sourceInfo[.systemFileNumber] as? NSNumber), try XCTUnwrap(resolvedInfo[.systemFileNumber] as? NSNumber))
        XCTAssertEqual(try XCTUnwrap(sourceInfo[.systemNumber] as? NSNumber), try XCTUnwrap(resolvedInfo[.systemNumber] as? NSNumber))
        let link = root.appendingPathComponent("profile link", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: profile)
        XCTAssertEqual(try ExternalConverters.officeProfileURL(link), url)

        let pendingSocket = link.appendingPathComponent("private.sock")
        XCTAssertEqual(try ProcessRunner.canonicalUnixSocketPath(pendingSocket), canonicalProfile.path + "/private.sock")
        XCTAssertThrowsError(try ProcessRunner.canonicalUnixSocketPath(link.appendingPathComponent("missing/socket")))
        try FileManager.default.createSymbolicLink(at: pendingSocket, withDestinationURL: canonicalProfile.appendingPathComponent("other.sock"))
        XCTAssertThrowsError(try ProcessRunner.canonicalUnixSocketPath(pendingSocket), "A dangling socket symlink must not become a grant")
        try FileManager.default.removeItem(at: pendingSocket)
        try Data("occupied".utf8).write(to: pendingSocket)
        XCTAssertThrowsError(try ProcessRunner.canonicalUnixSocketPath(pendingSocket), "An occupied non-socket path must be rejected")
        XCTAssertThrowsError(try ExternalConverters.officeProfileURL(pendingSocket))
        #if os(macOS)
        // Foundation shortens /private paths. LibreOffice hashes their POSIX spelling.
        let fixture = "fw-office-\(UUID().uuidString)"
        let alias = URL(fileURLWithPath: "/tmp/\(fixture)/profile % # []", isDirectory: true)
        let physical = URL(fileURLWithPath: "/private/tmp/\(fixture)", isDirectory: true)
        try FileManager.default.createDirectory(at: alias, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: physical) }
        XCTAssertEqual(try ExternalConverters.officeProfileURL(alias), "file:///private/tmp/\(fixture)/profile%20%25%20%23%20%5B%5D")
        let pending = alias.appendingPathComponent("not-created.sock")
        XCTAssertFalse(FileManager.default.fileExists(atPath: pending.path))
        XCTAssertEqual(try ProcessRunner.canonicalUnixSocketPath(pending), "/private/tmp/\(fixture)/profile % # []/not-created.sock")

        // Independent MD5 vectors exercise LibreOffice's unpadded-byte spelling.
        for (profileURL, digest) in [
            ("file:///private/tmp/freewheel-profile", "8dde90caf5ca1b752d47c91e1954854"),
            ("file:///private/tmp/office%20profile%20%25%20%23%20%5B%5D", "1fa5e9fd753261a2573ad92a1224b74")
        ] {
            let sockets = try ExternalConverters.officeIPCSockets(profileURL: profileURL)
            XCTAssertEqual(sockets.map(\.lastPathComponent), Array(repeating: "OSL_PIPE_\(getuid())_SingleOfficeIPC_\(digest)", count: 2))
            XCTAssertEqual(sockets.map { $0.deletingLastPathComponent().path }, ["/private/tmp", "/private/var/tmp"])
        }
        #endif
    }

    #if os(macOS)
    func testProcessAllowsOnlyRequestedUnixSocketAndStillBlocksIP() async throws {
        let python = try XCTUnwrap(EngineLocator.find("python3"), "Python 3 is required for the native sandbox regression")
        // Keep below sockaddr_un's length limit, independent of Darwin's temp path.
        let directory = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("fw-ipc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let allowed = directory.appendingPathComponent("allowed\"(x).sock")
        let other = directory.appendingPathComponent("other.sock")
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        let listener = try XCTUnwrap(descriptor >= 0 ? descriptor : nil, "Could not create the ungranted test listener")
        defer { _ = Darwin.close(listener) }
        guard Darwin.fcntl(listener, F_SETFD, FD_CLOEXEC) == 0 else {
            XCTFail("Could not keep the test listener out of child processes")
            return
        }
        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        let path = Array((other.path + "\0").utf8)
        guard path.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            XCTFail("Generated IPC fixture exceeds the Unix socket path limit")
            return
        }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: path) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, Darwin.listen(listener, 1) == 0 else {
            XCTFail("Could not start the ungranted test listener")
            return
        }
        let program = """
        import errno, os, socket, sys
        allowed, other = sys.argv[1:]
        def blocked(address, family, kind, operation):
            with socket.socket(family, kind) as candidate:
                candidate.settimeout(1)
                try:
                    getattr(candidate, operation)(address)
                except OSError as error:
                    assert error.errno in (errno.EPERM, errno.EACCES), str(error)
                else:
                    raise AssertionError('An ungranted socket operation was allowed')
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
            server.settimeout(1)
            server.bind(allowed)
            server.listen(1)
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
                client.settimeout(1)
                client.connect(allowed)
                connection, _ = server.accept()
                with connection:
                    client.sendall(b'private IPC')
                    assert connection.recv(32) == b'private IPC'
            # These paths have valid parents; failure must be permission denial.
            blocked(allowed + '.other', socket.AF_UNIX, socket.SOCK_STREAM, 'bind')
            blocked(other, socket.AF_UNIX, socket.SOCK_STREAM, 'connect')
            blocked(('127.0.0.1', 0), socket.AF_INET, socket.SOCK_STREAM, 'bind')
            blocked(('127.0.0.1', 9), socket.AF_INET, socket.SOCK_STREAM, 'connect')
            blocked(('::1', 0), socket.AF_INET6, socket.SOCK_STREAM, 'bind')
            blocked(('::1', 9), socket.AF_INET6, socket.SOCK_STREAM, 'connect')
        os.unlink(allowed)
        """
        let result = try await ProcessRunner.run(executable: python, arguments: ["-I", "-c", program, allowed.path, other.path], timeout: 10, allowedUnixSockets: [allowed])
        XCTAssertEqual(result.exitCode, 0, result.errorText)
        let denied = try await ProcessRunner.run(executable: python, arguments: ["-I", "-c", program, allowed.path, other.path], timeout: 10)
        XCTAssertNotEqual(denied.exitCode, 0, "Unix sockets should remain blocked unless explicitly granted")
    }
    #endif
}
