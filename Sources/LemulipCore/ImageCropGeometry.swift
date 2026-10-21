import Foundation

/// The edge or corner being dragged in top-left-oriented source-image coordinates.
public enum ImageCropHandle: CaseIterable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    fileprivate var horizontalDirection: Int {
        switch self {
        case .topLeft, .left, .bottomLeft: return -1
        case .topRight, .right, .bottomRight: return 1
        case .top, .bottom: return 0
        }
    }

    fileprivate var verticalDirection: Int {
        switch self {
        case .topLeft, .top, .topRight: return -1
        case .bottomLeft, .bottom, .bottomRight: return 1
        case .left, .right: return 0
        }
    }
}

/// Pure crop geometry in oriented source-image pixels, with (0, 0) at the top left.
///
/// Regions use positive whole-pixel dimensions and remain inside their source image.
/// Fractional drag distances are rounded only when producing the returned region.
/// A ratio is width / height; rounded dimensions differ from the continuous result
/// by at most one pixel. Centered operations may shift the center by half a pixel
/// when the old and new dimensions have different parity.
public enum ImageCropGeometry {
    private static let maximumSourceDimension = 16_384

    public static func fullImage(width: Int, height: Int) -> ImageCropRegion {
        let width = sourceDimension(width), height = sourceDimension(height)
        return ImageCropRegion(x: 0, y: 0, width: width, height: height,
                               sourceWidth: width, sourceHeight: height)
    }

    /// Moves the crop without changing its dimensions. Non-finite deltas mean zero.
    public static func moved(_ region: ImageCropRegion, dx: Double, dy: Double) -> ImageCropRegion {
        let region = normalized(region)
        return make(region,
                    x: whole(Double(region.x) + delta(dx),
                             minimum: 0, maximum: region.sourceWidth - region.width),
                    y: whole(Double(region.y) + delta(dy),
                             minimum: 0, maximum: region.sourceHeight - region.height),
                    width: region.width, height: region.height)
    }

    /// Resizes an edge or corner, clamping at the image boundary and opposite anchor.
    /// Pass the starting region and the cumulative distance for a drag gesture.
    /// Fixed-ratio corners keep the opposite corner; fixed-ratio edges keep the
    /// opposite edge and expand symmetrically around the perpendicular center.
    public static func resized(_ region: ImageCropRegion, handle: ImageCropHandle,
                               dx: Double, dy: Double,
                               aspectRatio: Double? = nil) -> ImageCropRegion {
        let region = normalized(region)
        let dx = delta(dx)
        let dy = delta(dy)
        let horizontal = handle.horizontalDirection, vertical = handle.verticalDirection
        guard let ratio = validRatio(aspectRatio) else {
            var left = region.x, top = region.y
            var right = region.x + region.width, bottom = region.y + region.height
            if horizontal < 0 {
                left = whole(Double(left) + dx, minimum: 0, maximum: right - 1)
            } else if horizontal > 0 {
                right = whole(Double(right) + dx, minimum: left + 1, maximum: region.sourceWidth)
            }
            if vertical < 0 {
                top = whole(Double(top) + dy, minimum: 0, maximum: bottom - 1)
            } else if vertical > 0 {
                bottom = whole(Double(bottom) + dy, minimum: top + 1, maximum: region.sourceHeight)
            }
            return make(region, x: left, y: top, width: right - left, height: bottom - top)
        }

        if horizontal != 0 && vertical != 0 {
            let anchorX = horizontal > 0 ? region.x : region.x + region.width
            let anchorY = vertical > 0 ? region.y : region.y + region.height
            // Compare drag distances, rather than the two resulting dimensions:
            // a horizontal-only inward drag must shrink a fixed-ratio corner.
            let requestedWidth: Double
            if abs(dx) >= abs(dy) * ratio {
                requestedWidth = Double(region.width) + Double(horizontal) * dx
            } else {
                requestedWidth = (Double(region.height) + Double(vertical) * dy) * ratio
            }
            return corner(region, anchorX: anchorX, anchorY: anchorY,
                          horizontal: horizontal, vertical: vertical,
                          requestedWidth: requestedWidth, ratio: ratio)
        }

        if horizontal != 0 {
            let anchorX = horizontal > 0 ? region.x : region.x + region.width
            let centerY = Double(region.y) + Double(region.height) / 2
            let maximumWidth = horizontal > 0 ? region.sourceWidth - anchorX : anchorX
            let maximumHeight = Int(2 * min(centerY, Double(region.sourceHeight) - centerY))
            let size = ratioSize(requestedWidth: Double(region.width) + Double(horizontal) * dx,
                                 ratio: ratio, maximumWidth: maximumWidth, maximumHeight: maximumHeight)
            return make(region, x: horizontal > 0 ? anchorX : anchorX - size.width,
                        y: whole(centerY - Double(size.height) / 2,
                                 minimum: 0, maximum: region.sourceHeight - size.height),
                        width: size.width, height: size.height)
        }

        let anchorY = vertical > 0 ? region.y : region.y + region.height
        let centerX = Double(region.x) + Double(region.width) / 2
        let maximumWidth = Int(2 * min(centerX, Double(region.sourceWidth) - centerX))
        let maximumHeight = vertical > 0 ? region.sourceHeight - anchorY : anchorY
        let size = ratioSize(requestedWidth: (Double(region.height) + Double(vertical) * dy) * ratio,
                             ratio: ratio, maximumWidth: maximumWidth, maximumHeight: maximumHeight)
        return make(region,
                    x: whole(centerX - Double(size.width) / 2,
                             minimum: 0, maximum: region.sourceWidth - size.width),
                    y: vertical > 0 ? anchorY : anchorY - size.height,
                    width: size.width, height: size.height)
    }

    /// Creates a selection from a press and drag, including drags in all four quadrants.
    public static func selected(fromX: Double, fromY: Double, toX: Double, toY: Double,
                                sourceWidth: Int, sourceHeight: Int,
                                aspectRatio: Double? = nil) -> ImageCropRegion {
        let image = fullImage(width: sourceWidth, height: sourceHeight)
        let fromX = coordinate(fromX, limit: image.sourceWidth, fallback: 0)
        let fromY = coordinate(fromY, limit: image.sourceHeight, fallback: 0)
        let toX = coordinate(toX, limit: image.sourceWidth, fallback: fromX)
        let toY = coordinate(toY, limit: image.sourceHeight, fallback: fromY)
        let anchorX = whole(fromX, minimum: 0, maximum: image.sourceWidth)
        let anchorY = whole(fromY, minimum: 0, maximum: image.sourceHeight)
        var horizontal = toX < fromX ? -1 : 1, vertical = toY < fromY ? -1 : 1
        // A click exactly on an outer boundary still selects one pixel inside it.
        if anchorX == 0 { horizontal = 1 }
        if anchorX == image.sourceWidth { horizontal = -1 }
        if anchorY == 0 { vertical = 1 }
        if anchorY == image.sourceHeight { vertical = -1 }
        let requestedWidth = abs(toX - fromX), requestedHeight = abs(toY - fromY)
        if let ratio = validRatio(aspectRatio) {
            return corner(image, anchorX: anchorX, anchorY: anchorY,
                          horizontal: horizontal, vertical: vertical,
                          requestedWidth: max(requestedWidth, requestedHeight * ratio), ratio: ratio)
        }
        let width = whole(requestedWidth, minimum: 1,
                          maximum: horizontal > 0 ? image.sourceWidth - anchorX : anchorX)
        let height = whole(requestedHeight, minimum: 1,
                           maximum: vertical > 0 ? image.sourceHeight - anchorY : anchorY)
        return make(image, x: horizontal > 0 ? anchorX : anchorX - width,
                    y: vertical > 0 ? anchorY : anchorY - height, width: width, height: height)
    }

    /// Fits the largest centered rectangle of the requested ratio inside the crop.
    public static func fitted(_ region: ImageCropRegion, aspectRatio: Double) -> ImageCropRegion {
        let region = normalized(region)
        guard let ratio = validRatio(aspectRatio) else { return region }
        let size = ratioSize(requestedWidth: Double(region.width), ratio: ratio,
                             maximumWidth: region.width, maximumHeight: region.height)
        return make(region,
                    x: whole(Double(region.x) + Double(region.width - size.width) / 2,
                             minimum: region.x, maximum: region.x + region.width - size.width),
                    y: whole(Double(region.y) + Double(region.height - size.height) / 2,
                             minimum: region.y, maximum: region.y + region.height - size.height),
                    width: size.width, height: size.height)
    }

    /// Applies numeric pixel dimensions and keeps the old center as far as bounds allow.
    public static func sized(_ region: ImageCropRegion, width: Int, height: Int) -> ImageCropRegion {
        let region = normalized(region)
        let width = min(region.sourceWidth, max(1, width))
        let height = min(region.sourceHeight, max(1, height))
        return make(region,
                    x: whole(Double(region.x) + Double(region.width - width) / 2,
                             minimum: 0, maximum: region.sourceWidth - width),
                    y: whole(Double(region.y) + Double(region.height - height) / 2,
                             minimum: 0, maximum: region.sourceHeight - height),
                    width: width, height: height)
    }

    private static func corner(_ region: ImageCropRegion, anchorX: Int, anchorY: Int,
                               horizontal: Int, vertical: Int,
                               requestedWidth: Double, ratio: Double) -> ImageCropRegion {
        let size = ratioSize(requestedWidth: requestedWidth, ratio: ratio,
                             maximumWidth: horizontal > 0 ? region.sourceWidth - anchorX : anchorX,
                             maximumHeight: vertical > 0 ? region.sourceHeight - anchorY : anchorY)
        return make(region, x: horizontal > 0 ? anchorX : anchorX - size.width,
                    y: vertical > 0 ? anchorY : anchorY - size.height,
                    width: size.width, height: size.height)
    }

    private static func ratioSize(requestedWidth: Double, ratio: Double,
                                  maximumWidth: Int, maximumHeight: Int) -> (width: Int, height: Int) {
        // Intermediate infinity from a very large finite ratio is harmless here:
        // the finite source bounds are applied before converting to integer pixels.
        let minimumWidth = max(1, ratio)
        let width = min(Double(maximumWidth), Double(maximumHeight) * ratio,
                        max(minimumWidth, requestedWidth.isNaN ? minimumWidth : requestedWidth))
        let height = min(Double(maximumHeight), width / ratio)
        return (whole(width, minimum: 1, maximum: maximumWidth),
                whole(height, minimum: 1, maximum: maximumHeight))
    }

    private static func normalized(_ region: ImageCropRegion) -> ImageCropRegion {
        let sourceWidth = sourceDimension(region.sourceWidth), sourceHeight = sourceDimension(region.sourceHeight)
        let width = min(sourceWidth, max(1, region.width)), height = min(sourceHeight, max(1, region.height))
        return ImageCropRegion(x: min(sourceWidth - width, max(0, region.x)),
                               y: min(sourceHeight - height, max(0, region.y)),
                               width: width, height: height, sourceWidth: sourceWidth, sourceHeight: sourceHeight)
    }

    private static func make(_ region: ImageCropRegion, x: Int, y: Int,
                             width: Int, height: Int) -> ImageCropRegion {
        ImageCropRegion(x: x, y: y, width: width, height: height,
                        sourceWidth: region.sourceWidth, sourceHeight: region.sourceHeight)
    }

    private static func sourceDimension(_ value: Int) -> Int {
        min(maximumSourceDimension, max(1, value))
    }

    private static func validRatio(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    private static func delta(_ value: Double) -> Double {
        value.isFinite ? value : 0
    }

    private static func coordinate(_ value: Double, limit: Int, fallback: Double) -> Double {
        value.isFinite ? min(Double(limit), max(0, value)) : fallback
    }

    private static func whole(_ value: Double, minimum: Int, maximum: Int) -> Int {
        let finite = value.isFinite ? value : Double(minimum)
        return Int(min(Double(maximum), max(Double(minimum), finite)).rounded())
    }
}
