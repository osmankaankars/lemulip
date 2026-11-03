#if os(macOS)
import AVFoundation
import Combine
import LemulipCore

/// Owns one local preview player. Time observers exist only while playing;
/// closing the editor releases the player, observers, and pending seeks.
@MainActor
final class AudioTrimPlayback: ObservableObject {
    @Published private(set) var isReady = false
    @Published private(set) var isPlaying = false
    @Published private(set) var isSeeking = false
    @Published private(set) var positionSeconds: Double = 0
    @Published private(set) var failure: MediaPlaybackFailure?

    var errorMessage: String? { failure?.message(language: "en") }

    private var player: AVPlayer?
    private var asset: AVURLAsset?
    private var selection: AudioTrimSelection?
    private var statusObservation: NSKeyValueObservation?
    private var playbackNotifications: [NSObjectProtocol] = []
    private var periodicObserver: Any?
    private var boundaryObserver: Any?
    private var readinessTimeout: Task<Void, Never>?
    private var seekTimeout: Task<Void, Never>?
    private var loadID = UUID()
    private var playbackID = UUID()

    func prepare(url: URL, selection: AudioTrimSelection) {
        shutdown()
        guard url.isFileURL else {
            failure = .localAudioRequired
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
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.actionAtItemEnd = .pause
        player = newPlayer
        let currentLoadID = loadID

        // KVO and notifications may arrive off the actor. Transfer only the
        // generation token, then read the owned item on the main actor.
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, self.loadID == currentLoadID else { return }
                self.refreshStatus()
            }
        }
        readinessTimeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 15_000_000_000) }
            catch { return }
            guard let self, self.loadID == currentLoadID, !self.isReady else { return }
            self.fail(.preparationTimedOut)
        }
    }

    func changeSelection(_ value: AudioTrimSelection) {
        pause()
        selection = value
        positionSeconds = value.startSeconds
        player?.currentItem?.forwardPlaybackEndTime = time(value.endSeconds)
    }

    func togglePlayback() {
        if isPlaying || isSeeking { pause() }
        else { playSelection() }
    }

    func pause() {
        playbackID = UUID()
        seekTimeout?.cancel()
        seekTimeout = nil
        player?.pause()
        player?.currentItem?.cancelPendingSeeks()
        // A paused player or pending seek may still report the previous range's time.
        if isPlaying, let selection, let current = player?.currentTime().seconds, current.isFinite {
            positionSeconds = min(selection.endSeconds, max(selection.startSeconds, current))
        }
        isPlaying = false
        isSeeking = false
        removePlaybackObservers()
    }

    func shutdown() {
        pause()
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
        failure = nil
        positionSeconds = 0
    }

    private func refreshStatus() {
        guard let item = player?.currentItem else { return }
        switch item.status {
        case .readyToPlay:
            readinessTimeout?.cancel()
            readinessTimeout = nil
            isReady = true
            failure = nil
        case .failed:
            isReady = false
            fail(item.error.map { MediaPlaybackFailure.system($0.localizedDescription) } ?? .audioUnavailable)
        case .unknown:
            isReady = false
        @unknown default:
            isReady = false
            fail(.audioUnavailable)
        }
    }

    private func playSelection() {
        guard isReady, let player, let selection, (try? selection.validate()) != nil else { return }
        let position = min(selection.endSeconds, max(selection.startSeconds, positionSeconds))
        let target = position >= selection.endSeconds ? selection.startSeconds : position
        pause()
        failure = nil
        isSeeking = true
        positionSeconds = target
        player.currentItem?.forwardPlaybackEndTime = time(selection.endSeconds)
        let currentPlaybackID = playbackID
        player.seek(to: time(target), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor [weak self] in
                guard let self, self.playbackID == currentPlaybackID, self.isSeeking else { return }
                self.seekTimeout?.cancel()
                self.seekTimeout = nil
                guard finished, self.player?.currentItem?.status == .readyToPlay else {
                    self.fail(.audioSeekFailed)
                    return
                }
                self.isSeeking = false
                self.isPlaying = true
                self.addPlaybackObservers(generation: currentPlaybackID)
                self.player?.play()
            }
        }
        seekTimeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 15_000_000_000) }
            catch { return }
            guard let self, self.playbackID == currentPlaybackID, self.isSeeking else { return }
            self.fail(.audioSeekFailed)
        }
    }

    private func addPlaybackObservers(generation: UUID) {
        guard let player, let item = player.currentItem, let selection else { return }
        periodicObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 20), queue: .main
        ) { [weak self] value in
            let seconds = value.seconds
            Task { @MainActor [weak self] in
                guard let self, self.playbackID == generation, self.isPlaying, seconds.isFinite,
                      let selection = self.selection else { return }
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
                let error = self.player?.currentItem?.error
                self.fail(error.map { MediaPlaybackFailure.system($0.localizedDescription) } ?? .audioPlaybackFailed)
            }
        })
        playbackNotifications.append(NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.playbackID == generation, self.isPlaying else { return }
                self.fail(.audioReadStalled)
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
        pause()
        positionSeconds = end
    }

    private func fail(_ value: MediaPlaybackFailure) {
        pause()
        readinessTimeout?.cancel()
        readinessTimeout = nil
        failure = value
    }

    private func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 1_000_000)
    }
}
#endif
