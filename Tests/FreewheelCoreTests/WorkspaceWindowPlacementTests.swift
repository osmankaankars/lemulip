import Foundation
import XCTest
@testable import FreewheelCore

final class WorkspaceWindowPlacementTests: XCTestCase {
    private let minimumSize = CGSize(width: 850, height: 620)

    func testUsablePlacementIsPreservedExactly() {
        let screen = CGRect(x: 0, y: 23, width: 1440, height: 877)
        let frame = CGRect(x: 175, y: 120, width: 1050, height: 720)

        XCTAssertEqual(WorkspaceWindowPlacement.recoveredFrame(frame, visibleScreens: [screen],
            preferredScreen: screen, minimumSize: minimumSize), frame)
    }

    func testIntentionalWindowSpanningDisplaysKeepsItsSizeAndOrigin() {
        let left = CGRect(x: -1920, y: -100, width: 1920, height: 1080)
        let primary = CGRect(x: 0, y: 23, width: 1440, height: 877)
        let frame = CGRect(x: -600, y: 100, width: 1800, height: 720)

        XCTAssertEqual(WorkspaceWindowPlacement.recoveredFrame(frame, visibleScreens: [left, primary],
            preferredScreen: primary, minimumSize: minimumSize), frame)
    }

    func testPlacementOnDisplayWithNegativeCoordinatesIsPreserved() {
        let left = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = CGRect(x: -1770, y: -120, width: 1050, height: 720)

        XCTAssertEqual(WorkspaceWindowPlacement.recoveredFrame(frame, visibleScreens: [primary, left],
            preferredScreen: primary, minimumSize: minimumSize), frame)
    }

    func testDisconnectedDisplayPlacementRecoversToPreferredConnectedDisplay() {
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let left = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        let savedFrame = CGRect(x: 3200, y: 240, width: 1050, height: 720)

        let recovered = WorkspaceWindowPlacement.recoveredFrame(savedFrame,
            visibleScreens: [primary, left], preferredScreen: left, minimumSize: minimumSize)

        XCTAssertEqual(recovered, CGRect(x: -1050, y: 160, width: 1050, height: 720))
    }

    func testDisconnectedPreferredDisplayFallsBackToConnectedDisplay() {
        let connected = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let disconnected = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        let savedFrame = CGRect(x: 2400, y: 100, width: 1050, height: 720)

        let recovered = WorkspaceWindowPlacement.recoveredFrame(savedFrame,
            visibleScreens: [connected], preferredScreen: disconnected, minimumSize: minimumSize)

        XCTAssertEqual(recovered, CGRect(x: 390, y: 100, width: 1050, height: 720))
    }

    func testOffscreenTitleBarRecoversOnTheDisplayAlreadyContainingTheWindow() {
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let right = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let frame = CGRect(x: 1600, y: 650, width: 1050, height: 720)

        let recovered = WorkspaceWindowPlacement.recoveredFrame(frame,
            visibleScreens: [primary, right], preferredScreen: primary, minimumSize: minimumSize)

        XCTAssertEqual(recovered, CGRect(x: 1600, y: 360, width: 1050, height: 720))
    }

    func testOnlyANarrowSliverOfTitleBarDoesNotCountAsReachable() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = CGRect(x: 1410, y: 100, width: 1050, height: 720)

        let recovered = WorkspaceWindowPlacement.recoveredFrame(frame,
            visibleScreens: [screen], preferredScreen: screen, minimumSize: minimumSize)

        XCTAssertEqual(recovered, CGRect(x: 390, y: 100, width: 1050, height: 720))
    }

    func testNoVisibleScreensLeavesSavedPlacementUntouched() {
        let savedFrame = CGRect(x: 3200, y: 240, width: 1050, height: 720)

        XCTAssertEqual(WorkspaceWindowPlacement.recoveredFrame(savedFrame, visibleScreens: [],
            preferredScreen: nil, minimumSize: minimumSize), savedFrame)
    }

    func testOversizedDisconnectedWindowFitsTheAvailableDisplay() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let savedFrame = CGRect(x: 2000, y: 200, width: 1800, height: 1200)

        let recovered = WorkspaceWindowPlacement.recoveredFrame(savedFrame,
            visibleScreens: [screen], preferredScreen: screen, minimumSize: minimumSize)

        XCTAssertEqual(recovered, screen)
    }

    func testSmallDisplayPreservesLayoutMinimumAndKeepsTopLeftControlsReachable() {
        let screen = CGRect(x: -800, y: 40, width: 800, height: 560)
        let savedFrame = CGRect(x: 2000, y: 200, width: 1050, height: 720)

        let recovered = WorkspaceWindowPlacement.recoveredFrame(savedFrame,
            visibleScreens: [screen], preferredScreen: screen, minimumSize: minimumSize)

        XCTAssertEqual(recovered.size, minimumSize)
        XCTAssertEqual(recovered.minX, screen.minX)
        XCTAssertEqual(recovered.maxY, screen.maxY)
        XCTAssertEqual(WorkspaceWindowPlacement.recoveredFrame(recovered, visibleScreens: [screen],
            preferredScreen: screen, minimumSize: minimumSize), recovered,
            "Repeated display notifications must not move a recovered window again.")
    }
}
