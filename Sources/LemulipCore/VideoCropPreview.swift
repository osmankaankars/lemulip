#if os(macOS)
import Foundation
import AVFoundation
import CoreGraphics
import CoreMedia

/// One immutable image is passed from the background decoder to the editor.
/// Crop coordinates use the full upright frame, independently of this preview.
public struct VideoCropPreview: @unchecked Sendable {
    public let image: CGImage
    public let sourceWidth: Int
    public let sourceHeight: Int
    public let durationSeconds: Double
    public let frameTimeSeconds: Double
    public let nativeOutputExtensions: [String]
}

extension NativeConverter {
    /// A single bounded still frame; playback uses its own restricted asset.
    /// No video/frame copy or persistent preview cache is created.
    public static func videoCropPreview(for input: URL, atSeconds: Double? = nil,
                                        maxPixelSize: Int = 1_280) async throws -> VideoCropPreview {
        try Task.checkCancellation()
        guard maxPixelSize > 0 else {
            throw LemulipError.invalidInput("The video crop preview size must be positive.")
        }
        if let atSeconds, !atSeconds.isFinite || atSeconds < 0 {
            throw LemulipError.invalidInput("Choose a preview time within the video.")
        }
        let source = try await VideoCropSource.load(input)
        let video = source.video
        if let atSeconds, atSeconds >= video.durationSeconds {
            throw LemulipError.invalidInput("Choose a preview time before the end of the video.")
        }
        let lastVideoTime = video.videoStartSeconds + video.videoDurationSeconds
            - min(0.000_001, video.videoDurationSeconds / 2)
        let proposed = atSeconds ?? min(0.5, video.durationSeconds / 2)
        let seconds = min(lastVideoTime, max(video.videoStartSeconds, proposed))
        let edge = min(maxPixelSize, 1_280)
        let generator = AVAssetImageGenerator(asset: video.asset)
        generator.appliesPreferredTrackTransform = true
        generator.apertureMode = .encodedPixels
        generator.maximumSize = CGSize(width: edge, height: edge)
        let frameInterval = video.nominalFrameRate.map { 1 / $0 } ?? 0.25
        let tolerance = CMTime(seconds: max(0.25, frameInterval), preferredTimescale: 1_000_000)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        let cancellation = VideoPreviewCancellation(asset: video.asset, generator: generator)
        return try await withTaskCancellationHandler(operation: {
            do {
                try Task.checkCancellation()
                let requested = CMTime(seconds: seconds, preferredTimescale: 1_000_000)
                let frame = try await generator.image(at: requested)
                try Task.checkCancellation()
                let actual = CMTimeGetSeconds(frame.actualTime)
                guard frame.image.width > 0, frame.image.height > 0,
                      frame.image.width <= edge, frame.image.height <= edge,
                      actual.isFinite, actual >= 0, actual < video.durationSeconds else {
                    throw LemulipError.operationFailed("The video decoder returned an invalid crop preview.")
                }
                return VideoCropPreview(image: frame.image,
                    sourceWidth: video.displayWidth, sourceHeight: video.displayHeight,
                    durationSeconds: video.durationSeconds, frameTimeSeconds: actual,
                    nativeOutputExtensions: video.nativeOutputExtensions)
            } catch {
                cancellation.cancel()
                try Task.checkCancellation()
                if let error = error as? LemulipError { throw error }
                throw VideoCropSource.decoderError
            }
        }, onCancel: { cancellation.cancel() })
    }
}

/// The common video loader enforces self-contained local media, finite timing,
/// one video track, at most one audio track, and native export compatibility.
/// Crop adds stricter pixel geometry so the player, still image, and export all
/// use the same displayed coordinate system.
struct VideoCropSource {
    let video: VideoTrimSource
    let track: AVAssetTrack
    let transform: CGAffineTransform
    let uprightBounds: CGRect

    static var decoderError: LemulipError {
        .unsupported("macOS cannot crop this video in the selected format. Convert it to a standard MP4 or MOV first.")
    }

    static var geometryError: LemulipError {
        .unsupported("Crop Video supports square pixels, a full-frame display aperture, and standard 90-degree rotations. Convert videos with custom transforms or display geometry to a standard MP4 or MOV first.")
    }

    static func load(_ input: URL) async throws -> VideoCropSource {
        let video = try await VideoTrimSource.load(input)
        let cancellation = VideoPreviewCancellation(asset: video.asset)
        return try await withTaskCancellationHandler(operation: {
            do {
                try Task.checkCancellation()
                let tracks = try await video.asset.loadTracks(withMediaType: .video)
                guard let track = tracks.first else { throw decoderError }
                let natural = try await track.load(.naturalSize)
                let transform = try await track.load(.preferredTransform)
                let descriptions = try await track.load(.formatDescriptions)
                guard video.displayWidth >= 2, video.displayHeight >= 2,
                      !descriptions.isEmpty, descriptions.count <= 32,
                      standardRotation(transform) else { throw geometryError }
                for description in descriptions {
                    let coded = CMVideoFormatDescriptionGetDimensions(description)
                    let aperture = CMVideoFormatDescriptionGetCleanAperture(description, originIsAtTopLeft: true)
                    let presentation = CMVideoFormatDescriptionGetPresentationDimensions(description,
                        usePixelAspectRatio: true, useCleanAperture: true)
                    guard matches(CGFloat(coded.width), natural.width), matches(CGFloat(coded.height), natural.height),
                          matches(aperture.minX, 0), matches(aperture.minY, 0),
                          matches(aperture.width, natural.width), matches(aperture.height, natural.height),
                          matches(presentation.width, natural.width), matches(presentation.height, natural.height) else {
                        throw geometryError
                    }
                }
                let bounds = CGRect(origin: .zero, size: natural).applying(transform).standardized
                guard matches(bounds.width, CGFloat(video.displayWidth)),
                      matches(bounds.height, CGFloat(video.displayHeight)) else { throw geometryError }
                try Task.checkCancellation()
                return VideoCropSource(video: video, track: track, transform: transform, uprightBounds: bounds)
            } catch {
                cancellation.cancel()
                try Task.checkCancellation()
                if let error = error as? LemulipError { throw error }
                throw decoderError
            }
        }, onCancel: { cancellation.cancel() })
    }

    private static func matches(_ first: CGFloat, _ second: CGFloat) -> Bool {
        first.isFinite && second.isFinite && abs(first - second) <= 0.001
    }

    private static func standardRotation(_ transform: CGAffineTransform) -> Bool {
        guard transform.tx.isFinite, transform.ty.isFinite else { return false }
        let rotations: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (1, 0, 0, 1), (0, 1, -1, 0), (-1, 0, 0, -1), (0, -1, 1, 0)
        ]
        return rotations.contains { a, b, c, d in
            matches(transform.a, a) && matches(transform.b, b) && matches(transform.c, c) && matches(transform.d, d)
        }
    }
}

/// Cancellation is the only operation exposed across task boundaries; session
/// configuration, export, and validation remain in their owning operation.
final class VideoCropExportCancellation: @unchecked Sendable {
    private let asset: AVAsset
    private let session: AVAssetExportSession

    init(asset: AVAsset, session: AVAssetExportSession) {
        self.asset = asset
        self.session = session
    }

    func cancel() {
        session.cancelExport()
        asset.cancelLoading()
    }
}
#endif
