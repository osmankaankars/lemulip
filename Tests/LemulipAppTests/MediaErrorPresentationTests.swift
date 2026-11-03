#if os(macOS)
import Foundation
import XCTest
import LemulipCore
@testable import Lemulip

final class MediaErrorPresentationTests: XCTestCase {
    func testEmptyMediaFilesUseTheirActualPreviewErrorsInBothLanguages() async throws {
        let directory = try workspace()
        let cases: [(name: String, isAudio: Bool, english: String, turkish: String)] = [
            ("Empty.wav", true, "Choose a readable audio file that is not empty.",
             "Boş olmayan, okunabilir bir ses dosyası seç."),
            ("Empty.mp4", false, "Choose a readable video file that is not empty.",
             "Boş olmayan, okunabilir bir video dosyası seç.")
        ]
        var inputs: Set<String> = []
        for item in cases {
            let input = directory.appendingPathComponent(item.name)
            try Data().write(to: input)
            inputs.insert(item.name)
            var observed: Error?
            do {
                if item.isAudio { _ = try await NativeConverter.audioTrimPreview(for: input) }
                else { _ = try await NativeConverter.videoTrimPreview(for: input) }
            } catch { observed = error }

            let error = try XCTUnwrap(observed, "An empty file must fail before a preview is available")
            guard case LemulipError.invalidInput(let diagnostic) = error else {
                return XCTFail("The core must retain the readable/nonempty invalidInput contract")
            }
            XCTAssertEqual(diagnostic, item.english)
            XCTAssertEqual(MediaErrorPresentation.message(for: error, language: "en"), item.english)
            XCTAssertEqual(MediaErrorPresentation.message(for: error, language: "tr"), item.turkish)
            XCTAssertEqual(try Data(contentsOf: input), Data())
            XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)), inputs)
        }
    }

    func testInvalidSelectionsKeepTheCoreContractAndLocalizedRangeAdvice() {
        let audio = AudioTrimSelection(startSeconds: 3, endSeconds: 2, sourceDuration: 5)
        XCTAssertThrowsError(try audio.validate()) { error in
            guard case LemulipError.invalidInput(let diagnostic) = error else {
                return XCTFail("Invalid audio selections must retain their core error case")
            }
            XCTAssertEqual(diagnostic, "Choose a nonempty audio range entirely within the recording.")
            XCTAssertEqual(MediaErrorPresentation.message(for: error, language: "en"), diagnostic)
            XCTAssertEqual(MediaErrorPresentation.message(for: error, language: "tr"),
                           "Ses dosyası içinde, bitişi başlangıçtan sonra olan bir aralık seç.")
        }

        let video = VideoTrimSelection(startSeconds: 0, endSeconds: 6, sourceDuration: 5)
        XCTAssertThrowsError(try video.validate()) { error in
            guard case LemulipError.invalidInput(let diagnostic) = error else {
                return XCTFail("Invalid video selections must retain their core error case")
            }
            XCTAssertEqual(diagnostic, "Choose a nonempty video range entirely within the clip.")
            XCTAssertEqual(MediaErrorPresentation.message(for: error, language: "en"), diagnostic)
            XCTAssertEqual(MediaErrorPresentation.message(for: error, language: "tr"),
                           "Video süresi içinde, bitişi başlangıçtan sonra olan bir aralık seç.")
        }
    }

    @MainActor
    func testPlayerInputFailuresAreTypedLocalizedAndClearedOnShutdown() throws {
        let remote = try XCTUnwrap(URL(string: "https://example.invalid/Preview.wav"))
        let audio = AudioTrimPlayback()
        let video = VideoTrimPlayback()
        defer { audio.shutdown(); video.shutdown() }

        audio.prepare(url: remote, selection: AudioTrimSelection(startSeconds: 0, endSeconds: 1, sourceDuration: 1))
        XCTAssertEqual(audio.failure, .localAudioRequired)
        XCTAssertEqual(audio.errorMessage, "Choose an audio file saved on this Mac to preview.")
        XCTAssertEqual(audio.failure?.message(language: "tr"), "Önizleme için Mac’inde kayıtlı bir ses dosyası seç.")
        XCTAssertFalse(audio.isReady)
        XCTAssertFalse(audio.isPlaying)
        XCTAssertFalse(audio.isSeeking)

        // A local URL with an invalid range also fails before a player is made.
        video.prepare(url: URL(fileURLWithPath: "/Preview.mp4"),
                      selection: VideoTrimSelection(startSeconds: 2, endSeconds: 1, sourceDuration: 3))
        XCTAssertEqual(video.failure, .localVideoAndRangeRequired)
        XCTAssertEqual(video.errorMessage, "Choose a video saved on this Mac and a valid time range to preview.")
        XCTAssertEqual(video.failure?.message(language: "tr"),
                       "Önizleme için Mac’inde kayıtlı bir video ve geçerli bir zaman aralığı seç.")
        XCTAssertNil(video.player)
        XCTAssertFalse(video.isReady)
        XCTAssertFalse(video.isPlaying)
        XCTAssertFalse(video.isSeeking)

        audio.shutdown()
        video.shutdown()
        XCTAssertNil(audio.failure)
        XCTAssertNil(audio.errorMessage)
        XCTAssertNil(video.failure)
        XCTAssertNil(video.errorMessage)
    }

    func testUnknownWrongCaseAndSystemDiagnosticsRemainVerbatim() {
        let known = "Choose a readable audio file that is not empty."
        let filename = "çok-uzun-kayıt-2026-\"deneme\".wav"
        let errors: [Error] = [
            LemulipError.invalidInput(known + " Additional source detail."),
            LemulipError.unsupported(known),
            LemulipError.operationFailed("A new media failure for \(filename)."),
            LemulipError.missingDependency("Other media engine"),
            NSError(domain: "MediaErrorPresentationTests", code: 42,
                    userInfo: [NSLocalizedDescriptionKey: known]),
            NSError(domain: "MediaErrorPresentationTests", code: 73,
                    userInfo: [NSLocalizedDescriptionKey: "Read failure for \(filename)."])
        ]
        for error in errors {
            for language in ["en", "tr"] {
                XCTAssertEqual(MediaErrorPresentation.message(for: error, language: language), error.localizedDescription)
            }
        }

        // Origin, rather than a matching English string, determines localization.
        let diagnostic = "Playback could not be prepared. Try again."
        let systemError = NSError(domain: "MediaErrorPresentationTests", code: 91,
                                  userInfo: [NSLocalizedDescriptionKey: diagnostic])
        let failure = MediaPlaybackFailure.system(systemError.localizedDescription)
        XCTAssertEqual(failure.message(language: "en"), diagnostic)
        XCTAssertEqual(failure.message(language: "tr"), diagnostic)
        XCTAssertEqual(MediaPlaybackFailure.preparationTimedOut.message(language: "tr"),
                       "Oynatma hazırlanamadı. Yeniden dene.")
    }

    func testKnownFFmpegRecoveryNamesTheCurrentSettingsSection() {
        let error = LemulipError.missingDependency("FFmpeg")
        XCTAssertEqual(MediaErrorPresentation.message(for: error, language: "en"),
                       "Add FFmpeg in Settings → Format Support, then try again.")
        XCTAssertEqual(MediaErrorPresentation.message(for: error, language: "tr"),
                       "FFmpeg’i Ayarlar → Biçim Desteği bölümünden ekleyip yeniden dene.")
        XCTAssertEqual(error.localizedDescription,
                       "Install FFmpeg to enable this operation. Open Settings → Engines for instructions.",
                       "App presentation must not change the core/CLI diagnostic")
    }

    private func workspace() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Lemulip-Media-Errors-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
}
#endif
