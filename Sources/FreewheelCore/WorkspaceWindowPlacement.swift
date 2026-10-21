import Foundation

/// Keeps a restored workspace reachable without disturbing a usable placement.
/// Screen rectangles are AppKit points and may have negative origins.
public enum WorkspaceWindowPlacement {
    public static func recoveredFrame(_ frame: CGRect, visibleScreens: [CGRect],
                                      preferredScreen: CGRect?, minimumSize: CGSize) -> CGRect {
        let screens = visibleScreens.filter(isUsable)
        guard isUsable(frame), !screens.isEmpty else { return frame }

        // A window may intentionally span displays. Preserve it while enough
        // of its title bar remains available to move or close it.
        let titleHeight = min(CGFloat(28), frame.height)
        let titleBar = CGRect(x: frame.minX, y: frame.maxY - titleHeight,
                              width: frame.width, height: titleHeight)
        if screens.contains(where: {
            let visible = titleBar.intersection($0)
            return !visible.isNull && visible.width >= min(CGFloat(160), titleBar.width)
                && visible.height >= min(CGFloat(20), titleHeight)
        }) { return frame }

        let overlap = screens.max { overlapArea(frame, $0) < overlapArea(frame, $1) }!
        let fallback = preferredScreen.flatMap { screens.contains($0) ? $0 : nil } ?? screens[0]
        let screen = overlapArea(frame, overlap) > 0 ? overlap : fallback
        let minWidth = minimumSize.width.isFinite ? max(0, minimumSize.width) : 0
        let minHeight = minimumSize.height.isFinite ? max(0, minimumSize.height) : 0
        let width = max(minWidth, min(frame.width, screen.width))
        let height = max(minHeight, min(frame.height, screen.height))

        // If the display is smaller than the supported minimum, keep the
        // title bar and left-side window controls reachable without shrinking
        // the workspace below its layout minimum.
        let x = min(max(frame.minX, screen.minX), max(screen.minX, screen.maxX - width))
        let y = min(max(frame.minY, screen.minY), screen.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func isUsable(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.width.isFinite && rect.height.isFinite
            && rect.width > 0 && rect.height > 0
    }

    private static func overlapArea(_ frame: CGRect, _ screen: CGRect) -> CGFloat {
        let overlap = frame.intersection(screen)
        return overlap.isNull ? 0 : overlap.width * overlap.height
    }
}
