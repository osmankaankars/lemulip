import Foundation

/// Integer pixels from the top-left of the displayed, upright source frame.
/// Source dimensions and duration are rechecked before export. This does not
/// detect a replacement video with identical dimensions and duration.
public struct VideoCropRegion: Equatable, Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int
    public var sourceWidth: Int
    public var sourceHeight: Int
    public var sourceDuration: Double

    public init(x: Int, y: Int, width: Int, height: Int,
                sourceWidth: Int, sourceHeight: Int, sourceDuration: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
        self.sourceWidth = sourceWidth; self.sourceHeight = sourceHeight
        self.sourceDuration = sourceDuration
    }

    public init(imageRegion: ImageCropRegion, sourceDuration: Double) {
        self.init(x: imageRegion.x, y: imageRegion.y, width: imageRegion.width, height: imageRegion.height,
                  sourceWidth: imageRegion.sourceWidth, sourceHeight: imageRegion.sourceHeight,
                  sourceDuration: sourceDuration)
    }

    public var imageRegion: ImageCropRegion {
        ImageCropRegion(x: x, y: y, width: width, height: height,
                        sourceWidth: sourceWidth, sourceHeight: sourceHeight)
    }

    /// H.264 output uses even dimensions. An odd edge is rounded inward by one
    /// pixel at the right or bottom; the selected content is never stretched.
    public var outputWidth: Int { width / 2 * 2 }
    public var outputHeight: Int { height / 2 * 2 }

    public func validate() throws {
        try imageRegion.validateBounds()
        guard sourceWidth >= 2, sourceHeight >= 2,
              sourceWidth <= 16_384, sourceHeight <= 16_384,
              sourceWidth <= 150_000_000 / sourceHeight,
              width >= 2, height >= 2,
              outputWidth <= 40_000_000 / outputHeight,
              sourceDuration.isFinite, sourceDuration > 0,
              sourceDuration <= 86_400 * 365 else {
            throw FreewheelError.invalidInput("Choose a video crop at least 2 pixels per edge and at most 40 megapixels, inside a source up to 16,384 pixels per edge.")
        }
    }

    func validate(sourceWidth actualWidth: Int, sourceHeight actualHeight: Int,
                  sourceDuration actualDuration: Double) throws {
        try validate()
        guard actualWidth == sourceWidth, actualHeight == sourceHeight,
              actualDuration.isFinite, abs(actualDuration - sourceDuration) <= 0.001 else {
            throw FreewheelError.invalidInput("The video dimensions or duration changed after the crop preview was prepared. Reopen Crop Video to select the updated clip.")
        }
    }
}

public enum VideoCropGeometry {
    /// Reuse image drag/ratio geometry, then align the visible selection with
    /// the encoder's even output dimensions. The origin is preserved whenever
    /// bounds allow; no aspect stretching or automatic upscaling is introduced.
    public static func normalized(_ region: ImageCropRegion) -> ImageCropRegion {
        let sourceWidth = min(16_384, max(2, region.sourceWidth))
        let sourceHeight = min(16_384, max(2, region.sourceHeight))
        let width = min(sourceWidth, max(2, region.width)) / 2 * 2
        let height = min(sourceHeight, max(2, region.height)) / 2 * 2
        return ImageCropRegion(x: min(sourceWidth - width, max(0, region.x)),
            y: min(sourceHeight - height, max(0, region.y)), width: width, height: height,
            sourceWidth: sourceWidth, sourceHeight: sourceHeight)
    }
}
