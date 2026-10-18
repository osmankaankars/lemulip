#if os(macOS)
import Foundation
import AVFoundation
import CoreGraphics
import CoreMedia

/// An immutable, bounded CGImage can cross from the decode task to the editor.
/// The timestamp is the actual decoded frame time, not a claimed exact seek.
public struct VideoTrimThumbnail: @unchecked Sendable {
    public let image: CGImage
    public let timeSeconds: Double
}

public struct VideoTrimPreview: Sendable {
    public let durationSeconds: Double
    public let thumbnails: [VideoTrimThumbnail]
    public let displayWidth: Int
    public let displayHeight: Int
    public let nominalFrameRate: Double?
    public let nativeOutputExtensions: [String]
}

extension NativeConverter {
    /// Prepare a small filmstrip off the main actor. At most 24 thumbnails are
    /// retained, each at most 192 pixels per edge. The source is never copied
    /// or rewritten, and no decoded frame cache is written to disk.
    public static func videoTrimPreview(for input: URL, maxThumbnailCount: Int = 12,
                                         maxPixelSize: Int = 192) async throws -> VideoTrimPreview {
        try Task.checkCancellation()
        guard maxThumbnailCount > 0, maxPixelSize > 0 else {
            throw FreewheelError.invalidInput("The video timeline preview size must be positive.")
        }
        let source = try await VideoTrimSource.load(input)
        let count = min(maxThumbnailCount, 24)
        let edge = min(maxPixelSize, 192)
        let generator = AVAssetImageGenerator(asset: source.asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: edge, height: edge)
        // A thumbnail is a visual summary, not a frame-accurate cut marker.
        // Keep requests inside the video track, and avoid the exclusive EOF.
        let interval = source.durationSeconds / Double(count)
        let frameInterval = source.nominalFrameRate.map { 1 / $0 } ?? 0.25
        let tolerance = CMTime(seconds: max(frameInterval, min(0.25, interval / 2)), preferredTimescale: 1_000_000)
        let lastVideoTime = source.videoStartSeconds + source.videoDurationSeconds
            - min(0.000_001, source.videoDurationSeconds / 2)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        let cancellation = VideoPreviewCancellation(asset: source.asset, generator: generator)
        return try await withTaskCancellationHandler(operation: {
            do {
                var thumbnails: [VideoTrimThumbnail] = []
                thumbnails.reserveCapacity(count)
                for index in 0..<count {
                    try Task.checkCancellation()
                    let center = (Double(index) + 0.5) * interval
                    let requestedSeconds = min(lastVideoTime, max(source.videoStartSeconds, center))
                    let requested = CMTime(seconds: requestedSeconds, preferredTimescale: 1_000_000)
                    let frame = try await generator.image(at: requested)
                    try Task.checkCancellation()
                    let actual = CMTimeGetSeconds(frame.actualTime)
                    guard frame.image.width > 0, frame.image.height > 0,
                          frame.image.width <= edge, frame.image.height <= edge,
                          actual.isFinite, actual >= 0, actual < source.durationSeconds else {
                        throw FreewheelError.operationFailed("The video decoder returned an invalid timeline thumbnail.")
                    }
                    thumbnails.append(VideoTrimThumbnail(image: frame.image, timeSeconds: actual))
                }
                return VideoTrimPreview(durationSeconds: source.durationSeconds, thumbnails: thumbnails,
                    displayWidth: source.displayWidth, displayHeight: source.displayHeight,
                    nominalFrameRate: source.nominalFrameRate,
                    nativeOutputExtensions: source.nativeOutputExtensions)
            } catch {
                cancellation.cancel()
                try Task.checkCancellation()
                if let error = error as? FreewheelError { throw error }
                throw VideoTrimSource.decoderError
            }
        }, onCancel: { cancellation.cancel() })
    }
}

/// The metadata and decoder objects remain inside their owning background
/// operation. The player creates its own equally restricted local asset.
struct VideoTrimSource {
    let asset: AVURLAsset
    let duration: CMTime
    let durationSeconds: Double
    let videoStartSeconds: Double
    let videoDurationSeconds: Double
    let displayWidth: Int
    let displayHeight: Int
    let nominalFrameRate: Double?
    let nativeOutputExtensions: [String]

    static var decoderError: FreewheelError {
        .unsupported("macOS cannot prepare this video for editing. Convert it to a standard MP4 or MOV first. Protected videos and files that reference other media are not supported.")
    }

    static func load(_ input: URL) async throws -> VideoTrimSource {
        try Task.checkCancellation()
        guard input.isFileURL, !input.path.contains("\0"), FileFamily.detect(input) == .video else {
            throw FreewheelError.invalidInput("Choose one local video file for editing.")
        }
        let values = try input.resourceValues(forKeys: [.isRegularFileKey, .isReadableKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isReadable != false, (values.fileSize ?? 0) > 0 else {
            throw FreewheelError.invalidInput("Choose a readable video file that is not empty.")
        }
        let asset = AVURLAsset(url: input, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: true,
            AVURLAssetReferenceRestrictionsKey: NSNumber(value: AVAssetReferenceRestrictions.forbidAll.rawValue),
            AVURLAssetShouldSupportAliasDataReferencesKey: false
        ])
        let cancellation = VideoPreviewCancellation(asset: asset)
        return try await withTaskCancellationHandler(operation: {
            do { return try await readMetadata(asset) }
            catch {
                cancellation.cancel()
                try Task.checkCancellation()
                if let error = error as? FreewheelError { throw error }
                throw decoderError
            }
        }, onCancel: { cancellation.cancel() })
    }

    private static func readMetadata(_ asset: AVURLAsset) async throws -> VideoTrimSource {
        try Task.checkCancellation()
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite, seconds > 0, seconds <= 86_400 * 365 else {
            throw FreewheelError.invalidInput("This video has no finite playable duration. Save a complete local clip first.")
        }
        let playable = try await asset.load(.isPlayable)
        let exportable = try await asset.load(.isExportable)
        let protected = try await asset.load(.hasProtectedContent)
        guard playable, exportable, !protected else { throw decoderError }
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        guard tracks.count == 1, let track = tracks.first, audio.count <= 1 else {
            throw FreewheelError.unsupported("Native video editing supports one video track and at most one audio track. Flatten a multitrack project to MP4 or MOV first.")
        }
        let natural = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let bounds = CGRect(origin: .zero, size: natural).applying(transform).standardized
        guard natural.width.isFinite, natural.height.isFinite,
              natural.width > 0, natural.height > 0,
              natural.width <= 16_384, natural.height <= 16_384,
              natural.width * natural.height <= 150_000_000,
              bounds.width.isFinite, bounds.height.isFinite,
              bounds.width >= 1, bounds.height >= 1,
              bounds.width <= 16_384, bounds.height <= 16_384,
              bounds.width * bounds.height <= 150_000_000 else {
            throw FreewheelError.invalidInput("The video dimensions are invalid or exceed the supported preview limits.")
        }
        let trackRange = try await track.load(.timeRange)
        let trackStart = CMTimeGetSeconds(trackRange.start)
        let trackEnd = CMTimeGetSeconds(CMTimeRangeGetEnd(trackRange))
        guard trackStart.isFinite, trackEnd.isFinite, trackEnd > max(0, trackStart), trackStart < seconds else {
            throw FreewheelError.invalidInput("The video track has no valid playable timeline.")
        }
        let videoStart = max(0, trackStart)
        let videoEnd = min(seconds, trackEnd)
        let frameRate = Double(try await track.load(.nominalFrameRate))
        let rate: Double? = frameRate.isFinite && frameRate > 0 && frameRate <= 1_000 ? frameRate : nil
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw decoderError
        }
        let compatible = await session.compatibleFileTypes
        var formats: [String] = []
        if compatible.contains(.mp4) { formats.append("mp4") }
        if compatible.contains(.mov) { formats.append("mov") }
        try Task.checkCancellation()
        guard !formats.isEmpty else { throw decoderError }
        return VideoTrimSource(asset: asset, duration: duration, durationSeconds: seconds,
            videoStartSeconds: videoStart, videoDurationSeconds: videoEnd - videoStart,
            displayWidth: Int(bounds.width.rounded()), displayHeight: Int(bounds.height.rounded()),
            nominalFrameRate: rate, nativeOutputExtensions: formats)
    }
}

/// Only AVFoundation's explicit cancellation methods cross task boundaries.
/// Normal asset/generator access stays in its owning operation.
final class VideoPreviewCancellation: @unchecked Sendable {
    private let asset: AVAsset
    private let generator: AVAssetImageGenerator?

    init(asset: AVAsset, generator: AVAssetImageGenerator? = nil) {
        self.asset = asset
        self.generator = generator
    }

    func cancel() {
        generator?.cancelAllCGImageGeneration()
        asset.cancelLoading()
    }
}
#endif
