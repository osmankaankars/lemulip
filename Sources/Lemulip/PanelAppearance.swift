#if os(macOS)
import AppKit
import QuartzCore

/// A short entry response for Lemulip's own panels. Geometry, focus and input
/// remain synchronous; no action waits for animation completion.
@MainActor
final class PanelAppearance {
    enum Kind {
        case wheel, result
        var duration: TimeInterval { self == .wheel ? 0.09 : 0.14 }
    }

    private weak var panel: NSPanel?
    private let reduceMotion: () -> Bool
    private let reduceTransparency: () -> Bool
    private let notifications: NotificationCenter
    private var observer: NSObjectProtocol?

    init(reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion },
         reduceTransparency: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency },
         notifications: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
        self.notifications = notifications
        observer = notifications.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.prefersImmediateAppearance else { return }
                    self.finishAppearance()
                }
            }
    }

    deinit {
        if let observer { notifications.removeObserver(observer) }
    }

    func present(_ panel: NSPanel, kind: Kind, orderFront: () -> Void) {
        finishAppearance()
        self.panel = panel
        let shouldAnimate = !panel.isVisible && !prefersImmediateAppearance
        panel.animationBehavior = .none
        // Keep the operation target visible and eligible from the first frame.
        // A zero-alpha window would add an invisible part of the gesture.
        setAlphaImmediately(shouldAnimate ? 0.72 : 1, for: panel)
        orderFront()
        guard shouldAnimate else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = kind.duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    func dismiss() {
        panel?.orderOut(nil)
        finishAppearance()
    }

    private var prefersImmediateAppearance: Bool { reduceMotion() || reduceTransparency() }

    private func finishAppearance() {
        guard let panel else { return }
        setAlphaImmediately(1, for: panel)
    }

    private func setAlphaImmediately(_ value: CGFloat, for panel: NSPanel) {
        // AppKit stops an in-flight property animation when its animator receives
        // a new value in a zero-duration context. Reuse cannot revive an old fade.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().alphaValue = value
        }
    }
}
#endif
