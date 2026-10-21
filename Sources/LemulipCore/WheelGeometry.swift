import Foundation

public struct WheelPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct WheelBounds: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// Geometry uses coordinates relative to the wheel center, with positive y up.
/// Item zero is at the top, and subsequent items run clockwise.
public enum WheelGeometry {
    /// The inner boundary belongs to the safe hub; the outer boundary is hittable.
    /// A sector boundary belongs to the next sector in the clockwise direction.
    public static func index(at point: WheelPoint, itemCount: Int,
                             innerRadius: Double = 62, outerRadius: Double = 168) -> Int? {
        guard (1...8).contains(itemCount), point.x.isFinite, point.y.isFinite,
              innerRadius.isFinite, outerRadius.isFinite,
              innerRadius >= 0, outerRadius > innerRadius else { return nil }
        let distance = hypot(point.x, point.y)
        guard distance > innerRadius, distance <= outerRadius else { return nil }
        let circle = 2 * Double.pi
        let sector = circle / Double(itemCount)
        var angle = atan2(point.x, point.y)
        if angle < 0 { angle += circle }
        return Int(floor((angle + sector / 2) / sector)) % itemCount
    }

    /// Invalid placement requests return the center without producing NaN values.
    public static func position(index: Int, itemCount: Int, radius: Double) -> WheelPoint {
        guard (1...8).contains(itemCount), (0..<itemCount).contains(index),
              radius.isFinite, radius >= 0 else { return WheelPoint(x: 0, y: 0) }
        let angle = Double(index) * 2 * Double.pi / Double(itemCount)
        return WheelPoint(x: sin(angle) * radius, y: cos(angle) * radius)
    }

    /// Centers an oversized panel on that axis rather than pinning it to an edge.
    /// Invalid proposed coordinates fall back to the corresponding bounds midpoint.
    public static func clampedCenter(proposed: WheelPoint, halfSize: Double,
                                     bounds: WheelBounds) -> WheelPoint {
        func clamp(_ value: Double, origin: Double, length: Double) -> Double {
            guard origin.isFinite, length.isFinite, length >= 0 else {
                return value.isFinite ? value : 0
            }
            let midpoint = origin + length / 2
            guard midpoint.isFinite else { return origin }
            guard halfSize.isFinite, halfSize >= 0, halfSize < length / 2 else {
                return midpoint
            }
            let lower = origin + halfSize
            let upper = origin + (length - halfSize)
            guard lower.isFinite, upper.isFinite else { return midpoint }
            return min(max(value.isFinite ? value : midpoint, lower), upper)
        }
        return WheelPoint(x: clamp(proposed.x, origin: bounds.x, length: bounds.width),
                          y: clamp(proposed.y, origin: bounds.y, length: bounds.height))
    }
}
