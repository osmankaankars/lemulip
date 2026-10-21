#if os(macOS)
import AVFoundation
import Combine
import LemulipCore

/// Owns the editor's only video player. Seeks carry generation tokens, and
/// playback observers exist only while playing. Closing releases every owner.
@MainActor
final class VideoTrimPlayback: ObservableObject {
    // Keep this as stored state so defensive deinit cleanup does not invoke
    // a MainActor-isolated property-wrapper getter on older Swift toolchains.
    private(set) var player: AVPlayer? { willSet { objectWillChange.send() } }
    @Published private(set) var isReady = false
    @Published private(set) var isPlaying = false
    @Published private(set) var isSeeking = false
    @Published private(set) var positionSeconds: Double = 0
    @Published private(set) var errorMessage: String?

    private var asset: AVURLAsset?
    private var selection: VideoTrimSelection?
    private var statusObservation: NSKeyValueObservation?
    private var playbackNotifications: [NSObjectProtocol] = []
    private var periodicObserver: Any?
    private var boundaryObserver: Any?
    private var readinessTimeout: Task<Void, Never>?
    private var seekTimeout: Task<Void, Never>?
    private var loadID = UUID()
    private var playbackID = UUID()
    private var playAfterSeek = false

    var isPlaybackRequested: Bool { isPlaying || (isSeeking && playAfterSeek) }

    deinit {
        readinessTimeout?.cancel()
        seekTimeout?.cancel()
        statusObservation?.invalidate()
        player?.pause()
        player?.currentItem?.cancelPendingSeeks()
        if let periodicObserver { player?.removeTimeObserver(periodicObserver) }
        if let boundaryObserver { player?.removeTimeObserver(boundaryObserver) }
        for token in playbackNotifications { NotificationCenter.default.removeObserver(token) }
        asset?.cancelLoading()
        player?.replaceCurrentItem(with: nil)
    }

    func prepare(url: URL, selection: VideoTrimSelection) {
        shutdown()
        guard url.isFileURL, (try? selection.validate()) != nil else {
            errorMessage = "Choose a local video with a valid time range to preview."
            return
        }
        self.selection = selection
        positionSeconds = selection.startSeconds
        let sourceAsset = AVURLAsset(url: url, options: [
            AVURLAssetReferenceRestrictionsKey: NSNumber(value: AVAssetReferenceRestrictions.forbidAll.rawValue),
            AVURLAssetShouldSupportAliasDataReferencesKey: false,
            AVURLAssetPreferPreciseDurationAndTimingKey: true
        ])
        asset = sourceAsset
        let item = AVPlayerItem(asset: sourceAsset)
        item.forwardPlaybackEndTime = time(selection.endSeconds)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.actionAtItemEnd = .pause
        player = newPlayer
        let generation = loadID

        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, self.loadID == generation else { return }
                self.refreshStatus()
            }
        }
        readinessTimeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 15_000_000_000) }
            catch { return }
            guard let self, self.loadID == generation, !self.isReady else { return }
            self.fail("Playback could not become ready. Try reopening the preview.")
        }
    }

    func changeSelection(_ value: VideoTrimSelection, previewing seconds: Double) {
        guard (try? value.validate()) != nil else { return }
        pause()
        selection = value
        player?.currentItem?.forwardPlaybackEndTime = time(value.endSeconds)
        seek(to: seconds)
    }

    func togglePlayback() {
        if isPlaybackRequested { pause() }
        else { playSelection() }
    }

    /// A paused seek is always confined to the current selection. A newer
    /// request invalidates the preceding completion before cancelling its seek.
    func seek(to seconds: Double) {
        guard seconds.isFinite, let selection else { return }
        let target = min(selection.endSeconds, max(selection.startSeconds, seconds))
        beginSeek(to: target, thenPlay: false)
    }

    func pause() { stopActivity(readPosition: true) }

    func shutdown() {
        stopActivity(readPosition: false)
        loadID = UUID()
        readinessTimeout?.cancel()
        readinessTimeout = nil
        statusObservation?.invalidate()
        statusObservation = nil
        asset?.cancelLoading()
        player?.replaceCurrentItem(with: nil)
        player = nil
        asset = nil
        selection = nil
        isReady = false
        errorMessage = nil
        positionSeconds = 0
    }

    private func stopActivity(readPosition: Bool) {
        playbackID = UUID()
        seekTimeout?.cancel()
        seekTimeout = nil
        if readPosition, isPlaying, let selection,
           let current = player?.currentTime().seconds, current.isFinite {
            positionSeconds = min(selection.endSeconds, max(selection.startSeconds, current))
        }
        player?.pause()
        player?.currentItem?.cancelPendingSeeks()
        playAfterSeek = false
        isPlaying = false
        isSeeking = false
        removePlaybackObservers()
    }

    private func refreshStatus() {
        guard let item = player?.currentItem else { return }
        switch item.status {
        case .readyToPlay:
            let firstReadiness = !isReady
            readinessTimeout?.cancel()
            readinessTimeout = nil
            isReady = true
            errorMessage = nil
            if firstReadiness { seek(to: positionSeconds) }
        case .failed:
            isReady = false
            fail(item.error?.localizedDescription ?? "This video cannot be played by the native preview.")
        case .unknown:
            isReady = false
        @unknown default:
            isReady = false
            fail("This video cannot be played by the native preview.")
        }
    }

    private func playSelection() {
        guard isReady, let selection, (try? selection.validate()) != nil else { return }
        let position = min(selection.endSeconds, max(selection.startSeconds, positionSeconds))
        let target = position >= selection.endSeconds ? selection.startSeconds : position
        beginSeek(to: target, thenPlay: true)
    }

    private func beginSeek(to seconds: Double, thenPlay: Bool) {
        stopActivity(readPosition: false)
        positionSeconds = seconds
        guard isReady, let player, let selection else { return }
        errorMessage = nil
        playAfterSeek = thenPlay
        isSeeking = true
        player.currentItem?.forwardPlaybackEndTime = time(selection.endSeconds)
        let generation = playbackID
        let sourceGeneration = loadID
        player.seek(to: previewTime(seconds), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor [weak self] in
                guard let self, self.loadID == sourceGeneration,
                      self.playbackID == generation, self.isSeeking else { return }
                self.seekTimeout?.cancel()
                self.seekTimeout = nil
                guard finished, self.player?.currentItem?.status == .readyToPlay else {
                    self.fail("The preview could not reach this time. Try seeking or playing again.")
                    return
                }
                self.isSeeking = false
                self.playAfterSeek = false
                if thenPlay {
                    self.isPlaying = true
                    self.addPlaybackObservers(generation: generation)
                    self.player?.play()
                }
            }
        }
        seekTimeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 15_000_000_000) }
            catch { return }
            guard let self, self.loadID == sourceGeneration,
                  self.playbackID == generation, self.isSeeking else { return }
            self.fail("The preview could not reach this time. Try seeking or playing again.")
        }
    }

    private func addPlaybackObservers(generation: UUID) {
        guard let player, let item = player.currentItem, let selection else { return }
        periodicObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 20), queue: .main
        ) { [weak self] value in
            let seconds = value.seconds
            Task { @MainActor [weak self] in
                guard let self, self.playbackID == generation, self.isPlaying,
                      seconds.isFinite, let selection = self.selection else { return }
                self.positionSeconds = min(selection.endSeconds, max(selection.startSeconds, seconds))
                if seconds >= selection.endSeconds { self.finishSelection() }
            }
        }
        boundaryObserver = player.addBoundaryTimeObserver(
            forTimes: [NSValue(time: time(selection.endSeconds))], queue: .main
        ) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.playbackID == generation, self.isPlaying else { return }
                self.finishSelection()
            }
        }
        playbackNotifications.append(NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.playbackID == generation, self.isPlaying else { return }
                self.finishSelection()
            }
        })
        playbackNotifications.append(NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.playbackID == generation, self.isPlaying else { return }
                self.fail(self.player?.currentItem?.error?.localizedDescription
                    ?? "This video could not finish playing. Try reopening the preview.")
            }
        })
        playbackNotifications.append(NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.playbackID == generation, self.isPlaying else { return }
                self.fail("Playback stopped while reading this video. Try reopening the preview.")
            }
        })
    }

    private func removePlaybackObservers() {
        if let periodicObserver { player?.removeTimeObserver(periodicObserver) }
        if let boundaryObserver { player?.removeTimeObserver(boundaryObserver) }
        periodicObserver = nil
        boundaryObserver = nil
        for token in playbackNotifications { NotificationCenter.default.removeObserver(token) }
        playbackNotifications.removeAll()
    }

    private func finishSelection() {
        let end = selection?.endSeconds ?? positionSeconds
        stopActivity(readPosition: false)
        positionSeconds = end
    }

    private func fail(_ message: String) {
        stopActivity(readPosition: false)
        readinessTimeout?.cancel()
        readinessTimeout = nil
        errorMessage = message
    }

    private func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 1_000_000)
    }

    private func previewTime(_ seconds: Double) -> CMTime {
        let requested = time(seconds)
        guard let selection, seconds >= selection.endSeconds else { return requested }
        // End is exclusive. Decode just before it, including at source EOF,
        // while the playhead label and export retain the exact selected End.
        // A clock tick avoids assuming a fixed frame rate for phone videos.
        let preceding = CMTimeSubtract(requested, CMTime(value: 1, timescale: 1_000_000))
        return CMTimeMaximum(time(selection.startSeconds), preceding)
    }
}
#endif
