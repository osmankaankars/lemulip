import Foundation

/// A range on the original video timeline, with an exclusive end. Export
/// rechecks the source duration; a replacement with the same duration is not
/// detected by this value. Video and audio codecs determine boundary precision.
public struct VideoTrimSelection: Equatable, Sendable {
    public var startSeconds: Double
    public var endSeconds: Double
    public var sourceDuration: Double

    public init(startSeconds: Double, endSeconds: Double, sourceDuration: Double) {
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.sourceDuration = sourceDuration
    }

    public var durationSeconds: Double { endSeconds - startSeconds }

    public func validate() throws {
        guard sourceDuration.isFinite, sourceDuration > 0,
              sourceDuration <= 86_400 * 365,
              startSeconds.isFinite, endSeconds.isFinite,
              startSeconds >= 0, endSeconds > startSeconds,
              endSeconds <= sourceDuration else {
            throw FreewheelError.invalidInput("Choose a nonempty video range entirely within the clip.")
        }
    }

    func validate(sourceDuration actualDuration: Double) throws {
        try validate()
        guard actualDuration.isFinite, actualDuration > 0,
              abs(actualDuration - sourceDuration) <= 0.001,
              startSeconds < actualDuration, endSeconds <= actualDuration + 0.001 else {
            throw FreewheelError.invalidInput("The video duration changed after the timeline was prepared. Reopen Trim to select the updated clip.")
        }
    }

    fileprivate var temporalSelection: AudioTrimSelection {
        AudioTrimSelection(startSeconds: startSeconds, endSeconds: endSeconds,
                           sourceDuration: sourceDuration)
    }

    fileprivate init(_ selection: AudioTrimSelection) {
        self.init(startSeconds: selection.startSeconds, endSeconds: selection.endSeconds,
                  sourceDuration: selection.sourceDuration)
    }
}

/// The video editor shares the existing millisecond handle geometry. The model
/// keeps the exact end of the source, including fractions below a millisecond;
/// these controls do not claim frame-accurate or lossless trimming.
public enum VideoTrimGeometry {
    public static func minimumDuration(sourceDuration: Double) -> Double {
        AudioTrimGeometry.minimumDuration(sourceDuration: sourceDuration)
    }

    public static func fullDuration(_ sourceDuration: Double) -> VideoTrimSelection {
        VideoTrimSelection(AudioTrimGeometry.fullDuration(sourceDuration))
    }

    public static func moved(_ selection: VideoTrimSelection, by delta: Double) -> VideoTrimSelection {
        VideoTrimSelection(AudioTrimGeometry.moved(selection.temporalSelection, by: delta))
    }

    public static func startChanged(_ selection: VideoTrimSelection, to seconds: Double) -> VideoTrimSelection {
        VideoTrimSelection(AudioTrimGeometry.startChanged(selection.temporalSelection, to: seconds))
    }

    public static func endChanged(_ selection: VideoTrimSelection, to seconds: Double) -> VideoTrimSelection {
        VideoTrimSelection(AudioTrimGeometry.endChanged(selection.temporalSelection, to: seconds))
    }
}

/// Seconds, MM:SS, or HH:MM:SS, with optional fractions. Unchanged timestamp
/// fields retain their model values rather than rounding an endpoint past EOF.
public enum VideoTrimTime {
    public static func parse(_ text: String) -> Double? { AudioTrimTime.parse(text) }

    public static func string(_ seconds: Double, milliseconds: Bool = true) -> String {
        AudioTrimTime.string(seconds, milliseconds: milliseconds)
    }

    public static func selection(startText: String, endText: String,
                                 preserving selection: VideoTrimSelection) -> VideoTrimSelection? {
        guard let range = AudioTrimTime.selection(startText: startText, endText: endText,
                                                   preserving: selection.temporalSelection) else { return nil }
        return VideoTrimSelection(range)
    }
}
