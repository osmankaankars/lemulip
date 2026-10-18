#if os(macOS)
import Foundation
import AVFoundation
import AudioToolbox
import CoreMedia

extension NativeConverter {
    /// Call from a background task. The reader releases every decoded buffer
    /// before requesting another, while the returned summary never exceeds
    /// 4,096 floats. There is no waveform cache or temporary audio file.
    public static func audioTrimPreview(for input: URL, maxSamples: Int = 1_200) async throws -> AudioTrimPreview {
        try Task.checkCancellation()
        guard maxSamples > 0 else { throw FreewheelError.invalidInput("The waveform preview size must be positive.") }
        let source = try await AudioTrimSource.load(input)
        var summary = try AudioWaveformAccumulator(durationSeconds: source.durationSeconds,
                                                   bucketCount: min(maxSamples, 4_096))
        let reader = try AVAssetReader(asset: source.asset)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: source.sampleRate,
            AVNumberOfChannelsKey: source.channelCount, AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let output = AVAssetReaderTrackOutput(track: source.track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw AudioTrimSource.decoderError }
        reader.add(output)
        reader.timeRange = CMTimeRange(start: .zero, duration: source.duration)
        let cancellation = AudioReadWriteCancellation(reader: reader)

        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            guard reader.startReading() else {
                try Task.checkCancellation()
                throw AudioTrimSource.decoderError
            }
            do {
                // A fixed 32 KiB at most for two-channel audio. Copying in small
                // blocks also handles Core Media buffers that aren't contiguous.
                var scratch = Array(repeating: Float.zero, count: 4_096 * source.channelCount)
                while reader.status == .reading {
                    try Task.checkCancellation()
                    let found = try autoreleasepool { () throws -> Bool in
                        guard let sample = output.copyNextSampleBuffer() else { return false }
                        guard let description = CMSampleBufferGetFormatDescription(sample),
                              let format = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
                              format.mFormatID == kAudioFormatLinearPCM,
                              format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                              format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0,
                              format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,
                              format.mBitsPerChannel == 32,
                              Int(format.mChannelsPerFrame) == source.channelCount,
                              Int(format.mBytesPerFrame) == source.channelCount * MemoryLayout<Float>.size,
                              abs(format.mSampleRate - source.sampleRate) < 0.5,
                              let block = CMSampleBufferGetDataBuffer(sample) else {
                            throw AudioTrimSource.decoderError
                        }
                        let frames = CMSampleBufferGetNumSamples(sample)
                        let bytesPerFrame = source.channelCount * MemoryLayout<Float>.size
                        let bytes = CMBlockBufferGetDataLength(block)
                        // Reject an abnormal decoder buffer instead of copying a
                        // recording-sized allocation into application memory.
                        guard frames >= 0, frames <= 2_097_152,
                              bytes <= 16 * 1_024 * 1_024,
                              frames <= bytes / bytesPerFrame else {
                            throw FreewheelError.unsupported("This audio decoder produced an unusually large buffer. Convert the recording to WAV or M4A first.")
                        }
                        let presentation = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
                        guard presentation.isFinite else { throw AudioTrimSource.decoderError }
                        var offset = 0
                        while offset < frames {
                            try Task.checkCancellation()
                            let count = min(4_096, frames - offset)
                            try scratch.withUnsafeMutableBufferPointer { buffer in
                                let status = CMBlockBufferCopyDataBytes(block, atOffset: offset * bytesPerFrame,
                                    dataLength: count * bytesPerFrame, destination: buffer.baseAddress!)
                                guard status == kCMBlockBufferNoErr else { throw AudioTrimSource.decoderError }
                                let values = UnsafeBufferPointer(start: buffer.baseAddress, count: count * source.channelCount)
                                try summary.append(values, frames: count, channelCount: source.channelCount,
                                    sampleRate: source.sampleRate,
                                    presentationSeconds: presentation + Double(offset) / source.sampleRate)
                            }
                            offset += count
                        }
                        return true
                    }
                    if !found { break }
                }
                try Task.checkCancellation()
                guard reader.status == .completed, summary.hasSamples else { throw AudioTrimSource.decoderError }
                return AudioTrimPreview(durationSeconds: source.durationSeconds, peaks: summary.peaks,
                    sampleRate: source.sampleRate, channelCount: source.channelCount,
                    nativeOutputExtensions: source.nativeOutputExtensions)
            } catch {
                reader.cancelReading()
                try Task.checkCancellation()
                throw error
            }
        }, onCancel: { cancellation.cancel() })
    }

    /// Recheck native metadata and source duration independently of the editor,
    /// including before FFmpeg export. The duration check is not a content hash.
    static func validateAudioTrimExport(for input: URL, selection: AudioTrimSelection,
                                        outputExtension: String) async throws {
        let source = try await AudioTrimSource.load(input)
        try selection.validate(sourceDuration: source.durationSeconds)
        guard ExternalConverters.audioExtensions.contains(outputExtension) else {
            throw FreewheelError.invalidInput("Choose an audio output for the selected range.")
        }
        guard source.nativeOutputExtensions.contains(outputExtension) ||
                outputExtension == "aif" && source.nativeOutputExtensions.contains("aiff") ||
                EngineLocator.isAvailable("ffmpeg") else {
            throw FreewheelError.missingDependency("FFmpeg")
        }
    }
}

/// AVFoundation objects stay inside the background operation. Only the immutable
/// waveform value is passed back to the UI.
struct AudioTrimSource {
    let asset: AVURLAsset
    let track: AVAssetTrack
    let duration: CMTime
    let durationSeconds: Double
    let sampleRate: Double
    let channelCount: Int
    let nativeOutputExtensions: [String]

    static var decoderError: FreewheelError {
        .unsupported("macOS cannot prepare a waveform for this audio codec. Convert the recording to WAV or M4A first; FFmpeg can convert additional formats.")
    }

    static func load(_ input: URL) async throws -> AudioTrimSource {
        try Task.checkCancellation()
        guard input.isFileURL, !input.path.contains("\0"), FileFamily.detect(input) == .audio else {
            throw FreewheelError.invalidInput("Choose one local audio file for waveform trimming.")
        }
        let values = try input.resourceValues(forKeys: [.isRegularFileKey, .isReadableKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isReadable != false, (values.fileSize ?? 0) > 0 else {
            throw FreewheelError.invalidInput("Choose a readable audio file that is not empty.")
        }
        let asset = AVURLAsset(url: input, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: true,
            AVURLAssetReferenceRestrictionsKey: NSNumber(value: AVAssetReferenceRestrictions.forbidAll.rawValue),
            AVURLAssetShouldSupportAliasDataReferencesKey: false
        ])
        let cancellation = AudioAssetLoadingCancellation(asset: asset)
        return try await withTaskCancellationHandler(operation: {
            do { return try await readMetadata(asset) }
            catch {
                try Task.checkCancellation()
                if let error = error as? FreewheelError { throw error }
                throw decoderError
            }
        }, onCancel: { cancellation.cancel() })
    }

    private static func readMetadata(_ asset: AVURLAsset) async throws -> AudioTrimSource {
        try Task.checkCancellation()
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite, seconds > 0, seconds <= 86_400 * 365 else {
            throw FreewheelError.invalidInput("This audio file has no valid playable duration.")
        }
        let playable = try await asset.load(.isPlayable)
        let protected = try await asset.load(.hasProtectedContent)
        guard playable, !protected else {
            throw decoderError
        }
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard tracks.count == 1, let track = tracks.first else {
            throw FreewheelError.unsupported("Waveform trimming needs exactly one audio track. Convert the recording to WAV or M4A first.")
        }
        let descriptions = try await track.load(.formatDescriptions)
        guard let description = descriptions.first,
              let format = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee else {
            throw decoderError
        }
        let channels = Int(format.mChannelsPerFrame), rate = format.mSampleRate
        guard (1...2).contains(channels), rate.isFinite, (8_000...192_000).contains(rate) else {
            throw FreewheelError.unsupported("Waveform trimming supports mono or stereo audio from 8 to 192 kHz. Convert other channel layouts or sample rates to WAV or M4A first.")
        }
        var formats = ["wav", "aiff"]
        if let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A),
           session.supportedFileTypes.contains(.m4a) { formats.insert("m4a", at: 0) }
        try Task.checkCancellation()
        return AudioTrimSource(asset: asset, track: track, duration: duration, durationSeconds: seconds,
                               sampleRate: rate, channelCount: channels, nativeOutputExtensions: formats)
    }
}

/// The asset's cancellation method also interrupts duration/track metadata
/// loading, before a reader exists. Its other APIs stay in the loading task.
private final class AudioAssetLoadingCancellation: @unchecked Sendable {
    private let asset: AVAsset
    init(asset: AVAsset) { self.asset = asset }
    func cancel() { asset.cancelLoading() }
}

/// AVFoundation explicitly provides these cancellation methods to interrupt
/// in-progress reads/writes. No other access is exposed across task boundaries;
/// construction and normal reader/writer operations stay in their owning task.
final class AudioReadWriteCancellation: @unchecked Sendable {
    private let reader: AVAssetReader
    private let writer: AVAssetWriter?

    init(reader: AVAssetReader, writer: AVAssetWriter? = nil) {
        self.reader = reader
        self.writer = writer
    }

    func cancel() {
        reader.cancelReading()
        writer?.cancelWriting()
    }
}
#endif
