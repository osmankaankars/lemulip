import Foundation

/// A range on the original audio timeline, measured in seconds. The end is
/// exclusive. The source duration is checked again before export; this does not
/// detect an external replacement with the same duration.
public struct AudioTrimSelection: Equatable, Sendable {
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
            throw LemulipError.invalidInput("Choose a nonempty audio range entirely within the recording.")
        }
    }

    func validate(sourceDuration actualDuration: Double) throws {
        try validate()
        guard actualDuration.isFinite, actualDuration > 0,
              abs(actualDuration - sourceDuration) <= 0.001,
              startSeconds < actualDuration, endSeconds <= actualDuration + 0.001 else {
            throw LemulipError.invalidInput("The audio duration changed after the waveform was prepared. Reopen Trim to select the updated recording.")
        }
    }
}

/// Geometry shared by the waveform handles and keyboard controls. Handle
/// positions use milliseconds; selecting the full recording preserves its EOF.
public enum AudioTrimGeometry {
    public static func minimumDuration(sourceDuration: Double) -> Double {
        min(duration(sourceDuration), 0.010)
    }

    public static func fullDuration(_ sourceDuration: Double) -> AudioTrimSelection {
        let total = duration(sourceDuration)
        return AudioTrimSelection(startSeconds: 0, endSeconds: total, sourceDuration: total)
    }

    public static func moved(_ selection: AudioTrimSelection, by delta: Double) -> AudioTrimSelection {
        var result = sanitized(selection)
        guard delta.isFinite else { return result }
        let length = result.durationSeconds
        let maximumStart = result.sourceDuration - length
        result.startSeconds = min(maximumStart, max(0, rounded(result.startSeconds + delta)))
        result.endSeconds = min(result.sourceDuration, result.startSeconds + length)
        return result
    }

    public static func startChanged(_ selection: AudioTrimSelection, to seconds: Double) -> AudioTrimSelection {
        var result = sanitized(selection)
        guard seconds.isFinite else { return result }
        result.startSeconds = min(result.endSeconds - minimumDuration(sourceDuration: result.sourceDuration),
                                  max(0, rounded(seconds)))
        return result
    }

    public static func endChanged(_ selection: AudioTrimSelection, to seconds: Double) -> AudioTrimSelection {
        var result = sanitized(selection)
        guard seconds.isFinite else { return result }
        result.endSeconds = max(result.startSeconds + minimumDuration(sourceDuration: result.sourceDuration),
                                min(result.sourceDuration, rounded(seconds)))
        return result
    }

    private static func sanitized(_ selection: AudioTrimSelection) -> AudioTrimSelection {
        let total = duration(selection.sourceDuration)
        let minimum = minimumDuration(sourceDuration: total)
        let start = selection.startSeconds.isFinite ? min(total - minimum, max(0, selection.startSeconds)) : 0
        let end = selection.endSeconds.isFinite ? min(total, max(start + minimum, selection.endSeconds)) : total
        return AudioTrimSelection(startSeconds: start, endSeconds: end, sourceDuration: total)
    }

    private static func duration(_ value: Double) -> Double {
        value.isFinite && value > 0 ? min(value, 86_400 * 365) : 0.010
    }

    private static func rounded(_ value: Double) -> Double {
        // Clamp before multiplying so even malformed drags cannot overflow.
        (min(86_400 * 365, max(0, value)) * 1_000).rounded() / 1_000
    }
}

/// A fixed-size summary; no decoded audio buffers are retained by the editor.
public struct AudioTrimPreview: Sendable {
    public let durationSeconds: Double
    /// Absolute peaks across all channels, with equal time widths, in 0...1.
    public let peaks: [Float]
    public let sampleRate: Double
    public let channelCount: Int
    public let nativeOutputExtensions: [String]
}

/// Timestamp parsing used by the editor's actual fields. Accepts seconds,
/// MM:SS, or HH:MM:SS, with optional fractional seconds and no signs or NaN.
public enum AudioTrimTime {
    public static func parse(_ text: String) -> Double? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        let components = value.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(components.count), let last = components.last,
              !last.isEmpty, last.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
              last.filter({ $0 == "." }).count <= 1, let seconds = Double(last), seconds.isFinite, seconds >= 0,
              components.count == 1 || seconds < 60 else { return nil }
        var total = seconds
        var multiplier: Double = 60
        for (index, component) in components.dropLast().reversed().enumerated() {
            guard !component.isEmpty, component.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let part = Double(component), part.isFinite,
                  !(components.count == 3 && index == 0 && part >= 60) else { return nil }
            total += part * multiplier
            multiplier *= 60
        }
        return total.isFinite ? total : nil
    }

    /// Labels round to milliseconds, but unchanged labels retain their precise
    /// model values. This keeps Full/Reset and a 10 ms range at EOF valid even
    /// when the recording ends between displayed milliseconds.
    public static func selection(startText: String, endText: String,
                                 preserving selection: AudioTrimSelection) -> AudioTrimSelection? {
        guard var start = parse(startText), var end = parse(endText) else { return nil }
        if startText == string(selection.startSeconds) { start = selection.startSeconds }
        if endText == string(selection.endSeconds) { end = selection.endSeconds }
        if endText == string(selection.sourceDuration) { end = selection.sourceDuration }
        let result = AudioTrimSelection(startSeconds: start, endSeconds: end, sourceDuration: selection.sourceDuration)
        guard (try? result.validate()) != nil else { return nil }
        return result
    }

    public static func string(_ seconds: Double, milliseconds: Bool = true) -> String {
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int64.max / 1_000_000) else { return "—" }
        let precision: Int64 = milliseconds ? (seconds > 0 && seconds < 0.001 ? 1_000_000 : 1_000) : 1
        let ticks = Int64((seconds * Double(precision)).rounded())
        let whole = ticks / precision
        let hours = whole / 3_600
        let minutes = (whole % 3_600) / 60
        let remaining = whole % 60
        let base = hours > 0
            ? String(format: "%02lld:%02lld:%02lld", hours, minutes, remaining)
            : String(format: "%02lld:%02lld", minutes, remaining)
        guard milliseconds else { return base }
        let fraction = ticks % precision
        return base + (precision == 1_000 ? String(format: ".%03lld", fraction) : String(format: ".%06lld", fraction))
    }
}

/// Reduces a stream of interleaved Float32 PCM into equal-width time buckets.
/// Each channel contributes its absolute peak; opposite-phase stereo cannot
/// cancel itself out. Sample timestamps preserve initial gaps and decoder preroll.
struct AudioWaveformAccumulator {
    let durationSeconds: Double
    private(set) var peaks: [Float]
    private(set) var hasSamples = false

    init(durationSeconds: Double, bucketCount: Int) throws {
        guard durationSeconds.isFinite, durationSeconds > 0,
              durationSeconds <= 86_400 * 365, (1...4_096).contains(bucketCount) else {
            throw LemulipError.invalidInput("The waveform duration or preview size is invalid.")
        }
        self.durationSeconds = durationSeconds
        self.peaks = Array(repeating: 0, count: bucketCount)
    }

    mutating func append(_ samples: UnsafeBufferPointer<Float>, frames: Int, channelCount: Int,
                         sampleRate: Double, presentationSeconds: Double) throws {
        guard frames >= 0, (1...2).contains(channelCount),
              frames <= samples.count / channelCount, sampleRate.isFinite,
              (8_000...192_000).contains(sampleRate), presentationSeconds.isFinite else {
            throw LemulipError.invalidInput("The decoded waveform contains invalid audio timing or samples.")
        }
        for frame in 0..<frames {
            if frame % 4_096 == 0 { try Task.checkCancellation() }
            let seconds = presentationSeconds + Double(frame) / sampleRate
            guard seconds >= 0, seconds < durationSeconds else { continue }
            let position = seconds / durationSeconds * Double(peaks.count)
            let boundary = position.rounded()
            // Packet timestamps and per-frame offsets can put an exact bucket
            // boundary a few floating-point ULPs below its integer. Stabilize
            // that boundary so decoder packet sizes cannot change the summary.
            let stable = abs(position - boundary) <= position.ulp * 8 ? boundary : position
            let bucket = min(peaks.count - 1, Int(stable))
            var peak: Float = 0
            for channel in 0..<channelCount {
                let value = samples[frame * channelCount + channel]
                if value.isFinite { peak = max(peak, min(1, abs(value))) }
            }
            peaks[bucket] = max(peaks[bucket], peak)
            hasSamples = true
        }
    }
}
