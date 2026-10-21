import Foundation
import XCTest
@testable import LemulipCore

final class WheelGeometryTests: XCTestCase {
    func testFourCardinalSectorsStartAtTopAndRunClockwise() {
        XCTAssertEqual(WheelGeometry.index(at: WheelPoint(x: 0, y: 100), itemCount: 4), 0)
        XCTAssertEqual(WheelGeometry.index(at: WheelPoint(x: 100, y: 0), itemCount: 4), 1)
        XCTAssertEqual(WheelGeometry.index(at: WheelPoint(x: 0, y: -100), itemCount: 4), 2)
        XCTAssertEqual(WheelGeometry.index(at: WheelPoint(x: -100, y: 0), itemCount: 4), 3)
    }

    func testPositionsAndHitSectorsAgreeForEverySupportedCount() {
        for count in 1...8 {
            for index in 0..<count {
                let point = WheelGeometry.position(index: index, itemCount: count, radius: 100)
                XCTAssertEqual(hypot(point.x, point.y), 100, accuracy: 0.000_001)
                XCTAssertEqual(WheelGeometry.index(at: point, itemCount: count), index)
            }
        }
        let right = WheelGeometry.position(index: 1, itemCount: 4, radius: 100)
        XCTAssertEqual(right.x, 100, accuracy: 0.000_001)
        XCTAssertEqual(right.y, 0, accuracy: 0.000_001)
    }

    func testSectorsAreCenteredOnPositionsAndWrapAtTop() {
        func point(_ degrees: Double) -> WheelPoint {
            let radians = degrees * Double.pi / 180
            return WheelPoint(x: sin(radians) * 100, y: cos(radians) * 100)
        }
        XCTAssertEqual(WheelGeometry.index(at: point(44.999), itemCount: 4), 0)
        XCTAssertEqual(WheelGeometry.index(at: WheelPoint(x: 100, y: 100), itemCount: 4), 1)
        XCTAssertEqual(WheelGeometry.index(at: point(45.001), itemCount: 4), 1)
        XCTAssertEqual(WheelGeometry.index(at: point(-44.999), itemCount: 4), 0)
        XCTAssertEqual(WheelGeometry.index(at: point(-45.001), itemCount: 4), 3)
        XCTAssertEqual(WheelGeometry.index(at: point(359.999), itemCount: 4), 0)
    }

    func testHubAndOutsideCannotSelectAnOperation() {
        for point in [WheelPoint(x: 0, y: 0), WheelPoint(x: 0, y: 61.999),
                      WheelPoint(x: 0, y: 62), WheelPoint(x: 0, y: 168.001)] {
            XCTAssertNil(WheelGeometry.index(at: point, itemCount: 8))
        }
        XCTAssertEqual(WheelGeometry.index(at: WheelPoint(x: 0, y: 62.001), itemCount: 8), 0)
        XCTAssertEqual(WheelGeometry.index(at: WheelPoint(x: 0, y: 168), itemCount: 8), 0)
    }

    func testInvalidCountsCoordinatesAndRadiiDoNotProduceSelections() {
        let valid = WheelPoint(x: 0, y: 100)
        for count in [-1, 0, 9, Int.max] {
            XCTAssertNil(WheelGeometry.index(at: valid, itemCount: count))
            XCTAssertEqual(WheelGeometry.position(index: 0, itemCount: count, radius: 100),
                           WheelPoint(x: 0, y: 0))
        }
        for value in [Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertNil(WheelGeometry.index(at: WheelPoint(x: value, y: 100), itemCount: 4))
            XCTAssertNil(WheelGeometry.index(at: WheelPoint(x: 100, y: value), itemCount: 4))
            XCTAssertNil(WheelGeometry.index(at: valid, itemCount: 4, innerRadius: value))
            XCTAssertNil(WheelGeometry.index(at: valid, itemCount: 4, outerRadius: value))
            XCTAssertEqual(WheelGeometry.position(index: 0, itemCount: 4, radius: value),
                           WheelPoint(x: 0, y: 0))
        }
        XCTAssertNil(WheelGeometry.index(at: valid, itemCount: 4, innerRadius: -1))
        XCTAssertNil(WheelGeometry.index(at: valid, itemCount: 4, innerRadius: 100, outerRadius: 100))
        XCTAssertNil(WheelGeometry.index(at: valid, itemCount: 4, innerRadius: 101, outerRadius: 100))
        XCTAssertEqual(WheelGeometry.position(index: -1, itemCount: 4, radius: 100), WheelPoint(x: 0, y: 0))
        XCTAssertEqual(WheelGeometry.position(index: 4, itemCount: 4, radius: 100), WheelPoint(x: 0, y: 0))
        XCTAssertEqual(WheelGeometry.position(index: 0, itemCount: 4, radius: -1), WheelPoint(x: 0, y: 0))
    }

    func testVisibleBoundsClampCorrectlyOnMonitorWithNegativeOrigin() {
        let bounds = WheelBounds(x: -1920, y: -200, width: 1920, height: 1080)
        XCTAssertEqual(WheelGeometry.clampedCenter(proposed: WheelPoint(x: -2500, y: 2000),
                                                  halfSize: 180, bounds: bounds),
                       WheelPoint(x: -1740, y: 700))
        XCTAssertEqual(WheelGeometry.clampedCenter(proposed: WheelPoint(x: 200, y: -500),
                                                  halfSize: 180, bounds: bounds),
                       WheelPoint(x: -180, y: -20))
        let inside = WheelPoint(x: -1000, y: 400)
        XCTAssertEqual(WheelGeometry.clampedCenter(proposed: inside, halfSize: 180, bounds: bounds), inside)
    }

    func testUndersizedScreenCentersPanelOnEachConstrainedAxis() {
        XCTAssertEqual(WheelGeometry.clampedCenter(proposed: WheelPoint(x: 500, y: 500), halfSize: 180,
                                                  bounds: WheelBounds(x: -300, y: 50, width: 200, height: 100)),
                       WheelPoint(x: -200, y: 100))
        XCTAssertEqual(WheelGeometry.clampedCenter(proposed: WheelPoint(x: 1000, y: 1000), halfSize: 180,
                                                  bounds: WheelBounds(x: -300, y: 50, width: 200, height: 1000)),
                       WheelPoint(x: -200, y: 870))
    }

    func testClampingInvalidValuesUsesFiniteFallbacks() {
        let bounds = WheelBounds(x: -100, y: 100, width: 800, height: 600)
        XCTAssertEqual(WheelGeometry.clampedCenter(proposed: WheelPoint(x: .nan, y: .infinity),
                                                  halfSize: 180, bounds: bounds),
                       WheelPoint(x: 300, y: 400))
        XCTAssertEqual(WheelGeometry.clampedCenter(proposed: WheelPoint(x: 0, y: 0),
                                                  halfSize: .nan, bounds: bounds),
                       WheelPoint(x: 300, y: 400))
        let result = WheelGeometry.clampedCenter(proposed: WheelPoint(x: .nan, y: .infinity),
                                                halfSize: 180,
                                                bounds: WheelBounds(x: .nan, y: .infinity, width: -1, height: 10))
        XCTAssertTrue(result.x.isFinite && result.y.isFinite)
    }
}
