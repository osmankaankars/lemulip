#if os(macOS)
import Combine
import Foundation
import XCTest
import LemulipCore
@testable import Lemulip

/// Uses the public playback state and a local PCM WAV, with no injected player or clock.
final class AudioTrimPlaybackTests: XCTestCase {
    @MainActor
    func testPauseResumesFromTheRetainedPosition() async throws {
        let playback = AudioTrimPlayback()
        defer { playback.shutdown() }
        let selection = AudioTrimSelection(startSeconds: 1, endSeconds: 5, sourceDuration: 6)
        playback.prepare(url: try makeWAV(), selection: selection)
        try await waitFor("The local WAV must become ready", playback: playback) { playback.isReady }

        playback.togglePlayback()
        try await waitFor("Playback must advance before pausing", playback: playback) {
            playback.isPlaying && playback.positionSeconds >= 1.5
        }
        playback.pause()
        let pausedPosition = playback.positionSeconds
        XCTAssertFalse(playback.isPlaying)
        XCTAssertFalse(playback.isSeeking)
        XCTAssertGreaterThanOrEqual(pausedPosition, 1.5)
        XCTAssertLessThan(pausedPosition, selection.endSeconds)

        playback.togglePlayback()
        XCTAssertEqual(playback.positionSeconds, pausedPosition, accuracy: 0.001,
                       "Play must retain the paused position instead of resetting to Start")
        try await waitFor("The resumed player must advance from its retained position", playback: playback) {
            playback.isPlaying && (playback.positionSeconds >= pausedPosition + 0.2
                || playback.positionSeconds < pausedPosition - 0.1)
        }
        XCTAssertGreaterThanOrEqual(playback.positionSeconds, pausedPosition + 0.2,
                                    "The actual seek must resume rather than replay earlier audio")
        XCTAssertLessThanOrEqual(playback.positionSeconds, selection.endSeconds)
    }

    @MainActor
    func testChangedRangeKeepsItsNewStartThroughRepeatedPauseAndSeekCancellation() async throws {
        let playback = AudioTrimPlayback()
        defer { playback.shutdown() }
        playback.prepare(url: try makeWAV(),
                         selection: AudioTrimSelection(startSeconds: 1, endSeconds: 5, sourceDuration: 6))
        try await waitFor("The local WAV must become ready", playback: playback) { playback.isReady }
        playback.togglePlayback()
        try await waitFor("Playback must leave the future selection's Start", playback: playback) {
            playback.isPlaying && playback.positionSeconds >= 1.5
        }

        let changed = AudioTrimSelection(startSeconds: 0.25, endSeconds: 4.5, sourceDuration: 6)
        playback.changeSelection(changed)
        XCTAssertFalse(playback.isPlaying)
        XCTAssertEqual(playback.positionSeconds, changed.startSeconds)
        // Invalid time-field edits can pause again before another range is accepted.
        playback.pause()
        XCTAssertEqual(playback.positionSeconds, changed.startSeconds,
                       "A paused player's old clock must not replace the newly selected Start")

        playback.togglePlayback()
        XCTAssertTrue(playback.isSeeking)
        XCTAssertEqual(playback.positionSeconds, changed.startSeconds)
        playback.pause()
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertFalse(playback.isPlaying, "A cancelled seek completion must not start playback")
        XCTAssertFalse(playback.isSeeking)
        XCTAssertEqual(playback.positionSeconds, changed.startSeconds,
                       "Cancelling a pending seek must retain its intended position")

        // Capture the first advancing player report, rather than whichever time
        // polling sees later. The old clock (at least 1.5 s) is inside this range.
        var firstProgress: Double?
        let observation = playback.$positionSeconds.sink { position in
            guard firstProgress == nil, playback.isPlaying,
                  position > changed.startSeconds + 0.01 else { return }
            firstProgress = position
        }
        defer { observation.cancel() }
        playback.togglePlayback()
        XCTAssertEqual(playback.positionSeconds, changed.startSeconds)
        try await waitFor("Playback must actually begin near the changed range's Start", playback: playback) {
            firstProgress != nil
        }
        let firstPosition = try XCTUnwrap(firstProgress)
        XCTAssertLessThanOrEqual(firstPosition, changed.startSeconds + 0.75,
                                 "Allow observer delivery time, but reject a seek to the old clock")
    }

    @MainActor
    func testSelectionEndRestartsAtStartAndPendingRestartCanBePaused() async throws {
        let playback = AudioTrimPlayback()
        defer { playback.shutdown() }
        let selection = AudioTrimSelection(startSeconds: 1, endSeconds: 1.3, sourceDuration: 6)
        playback.prepare(url: try makeWAV(), selection: selection)
        try await waitFor("The local WAV must become ready", playback: playback) { playback.isReady }
        playback.togglePlayback()
        try await waitFor("Playback must stop at the selection's End", playback: playback) {
            !playback.isPlaying && !playback.isSeeking && playback.positionSeconds == selection.endSeconds
        }

        playback.togglePlayback()
        XCTAssertTrue(playback.isSeeking)
        XCTAssertEqual(playback.positionSeconds, selection.startSeconds,
                       "Play at End must restart the selection")
        playback.pause()
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertFalse(playback.isPlaying)
        XCTAssertFalse(playback.isSeeking)
        XCTAssertEqual(playback.positionSeconds, selection.startSeconds,
                       "Pausing a pending restart must not restore the previous End")

        playback.togglePlayback()
        try await waitFor("The restarted selection must still stop at End", playback: playback) {
            !playback.isPlaying && !playback.isSeeking && playback.positionSeconds == selection.endSeconds
        }
    }

    @MainActor
    func testShutdownCancelsPendingPlaybackAndAllowsAnotherPrepare() async throws {
        let playback = AudioTrimPlayback()
        defer { playback.shutdown() }
        let input = try makeWAV()
        playback.prepare(url: input,
                         selection: AudioTrimSelection(startSeconds: 2, endSeconds: 4, sourceDuration: 6))
        try await waitFor("The local WAV must become ready", playback: playback) { playback.isReady }
        playback.togglePlayback()
        XCTAssertTrue(playback.isSeeking)
        playback.shutdown()
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertFalse(playback.isReady)
        XCTAssertFalse(playback.isPlaying)
        XCTAssertFalse(playback.isSeeking)
        XCTAssertEqual(playback.positionSeconds, 0)
        XCTAssertNil(playback.errorMessage)

        playback.prepare(url: input,
                         selection: AudioTrimSelection(startSeconds: 0.5, endSeconds: 2, sourceDuration: 6))
        try await waitFor("A new preparation must not inherit cancelled playback", playback: playback) { playback.isReady }
        XCTAssertEqual(playback.positionSeconds, 0.5)
        playback.togglePlayback()
        try await waitFor("The newly prepared selection must play", playback: playback) {
            playback.isPlaying && playback.positionSeconds >= 0.7
        }
    }

    @MainActor
    private func waitFor(_ message: String, playback: AudioTrimPlayback, condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !condition(), playback.errorMessage == nil, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        guard playback.errorMessage == nil, condition() else {
            throw NSError(domain: "AudioTrimPlaybackTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "\(message). Error: \(playback.errorMessage ?? "none"); position: \(playback.positionSeconds); playing: \(playback.isPlaying); seeking: \(playback.isSeeking)."])
        }
    }

    private func makeWAV() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Lemulip-Playback-\(UUID().uuidString).wav")
        let sampleRate = 8_000
        let sampleCount = sampleRate * 6
        var data = Data("RIFF".utf8)
        func append32(_ value: UInt32) {
            for shift in stride(from: 0, to: 32, by: 8) { data.append(UInt8(truncatingIfNeeded: value >> shift)) }
        }
        func append16(_ value: UInt16) {
            data.append(UInt8(truncatingIfNeeded: value))
            data.append(UInt8(truncatingIfNeeded: value >> 8))
        }
        append32(UInt32(36 + sampleCount * 2))
        data += Data("WAVEfmt ".utf8)
        append32(16)
        append16(1)
        append16(1)
        append32(UInt32(sampleRate))
        append32(UInt32(sampleRate * 2))
        append16(2)
        append16(16)
        data += Data("data".utf8)
        append32(UInt32(sampleCount * 2))
        data += Data(count: sampleCount * 2)
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
#endif
