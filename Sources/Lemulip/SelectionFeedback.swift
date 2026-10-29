#if os(macOS)
import AudioToolbox
import Foundation

@MainActor
protocol SelectionCuePlaying: AnyObject {
    /// Returns false when no cue can be started. Completion returns to the main actor.
    func play(completion: @escaping @MainActor () -> Void) -> Bool
    func stop()
}

/// One short, optional cue for a committed user choice. It never queues sounds.
/// A choice owns its consumed state, so deduplication needs no growing event-ID set.
@MainActor
final class SelectionFeedback {
    final class Choice {
        fileprivate var consumed = false
    }

    static let preferenceKey = "selectionSoundsEnabled"
    private let defaults: UserDefaults
    private let player: SelectionCuePlaying
    private let now: () -> TimeInterval
    private var activePlayback: UUID?
    private var lastStarted: TimeInterval?
    private var stopped = false
    private let minimumInterval: TimeInterval = 0.18

    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Self.preferenceKey)
            if !isEnabled { stopPlayback() }
        }
    }

    convenience init() {
        self.init(defaults: .standard, player: SystemSelectionCuePlayer())
    }

    init(defaults: UserDefaults, player: SelectionCuePlaying,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.defaults = defaults
        self.player = player
        self.now = now
        isEnabled = defaults.object(forKey: Self.preferenceKey) as? Bool ?? false
    }

    func commit(_ choice: Choice) {
        guard !choice.consumed else { return }
        // A disabled or coalesced event must not replay after a preference change
        // or a delayed callback. New user choices receive their own token.
        choice.consumed = true
        guard isEnabled else { return }
        playIfReady()
    }

    /// Explicit audition works while the preference is off and never changes it.
    /// It still uses the system UI-sound policy and the same overlap/rate guard.
    func preview() { playIfReady() }

    func shutdown() {
        guard !stopped else { return }
        stopped = true
        stopPlayback()
    }

    private func stopPlayback() {
        activePlayback = nil
        player.stop()
    }

    private func playIfReady() {
        guard !stopped, activePlayback == nil else { return }
        let time = now()
        if let lastStarted, time - lastStarted < minimumInterval { return }
        let playback = UUID()
        activePlayback = playback
        let started = player.play { [weak self] in
            guard self?.activePlayback == playback else { return }
            self?.activePlayback = nil
        }
        if started { lastStarted = time }
        else if activePlayback == playback { activePlayback = nil }
    }
}

/// The operating system mixes this UI effect at the user's sound-effects level.
/// No audio session, output-volume override, media pause, or audio engine is used.
@MainActor
final class SystemSelectionCuePlayer: SelectionCuePlaying {
    private(set) var soundID: SystemSoundID?
    private var file: SelectionCueFile?

    func play(completion: @escaping @MainActor () -> Void) -> Bool {
        guard prepare(), let soundID else { return false }
        AudioServicesPlaySystemSoundWithCompletion(soundID) {
            Task { @MainActor in completion() }
        }
        return true
    }

    /// Preparation is separate so native tests can inspect the policy without
    /// emitting audio or changing the Mac's sound-effects preferences.
    func prepare() -> Bool {
        if soundID != nil { return true }
        guard let file = try? SelectionCueFile() else { return false }
        var identifier: SystemSoundID = 0
        guard AudioServicesCreateSystemSoundID(file.url as CFURL, &identifier) == kAudioServicesNoError else {
            return false
        }
        // Explicitly retain Apple's default. Setting this to zero would bypass
        // the user's "Play user interface sound effects" setting on macOS.
        // https://developer.apple.com/documentation/audiotoolbox/kaudioservicespropertyisuisound
        var isUISound: UInt32 = 1
        let status = AudioServicesSetProperty(kAudioServicesPropertyIsUISound,
            UInt32(MemoryLayout<SystemSoundID>.size), &identifier,
            UInt32(MemoryLayout<UInt32>.size), &isUISound)
        guard status == kAudioServicesNoError else {
            AudioServicesDisposeSystemSoundID(identifier)
            return false
        }
        self.file = file
        soundID = identifier
        return true
    }

    func stop() {
        if let soundID { AudioServicesDisposeSystemSoundID(soundID) }
        soundID = nil
        file = nil
    }

    deinit {
        if let soundID { AudioServicesDisposeSystemSoundID(soundID) }
    }
}
#endif
