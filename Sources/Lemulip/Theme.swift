#if os(macOS)
import AppKit
import SwiftUI
import LemulipCore

enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case orchardNight = "orchard"
    case vividPistachio = "pistachio"
    case lemonDrop = "lemonade"

    static let preferenceKey = "theme"
    static var saved: AppTheme {
        UserDefaults.standard.string(forKey: preferenceKey).flatMap(AppTheme.init(rawValue:)) ?? .orchardNight
    }

    var id: String { rawValue }
    var name: String {
        switch self {
        case .orchardNight: return "Orchard Night"
        case .vividPistachio: return "Vivid Pistachio"
        case .lemonDrop: return "Lemon Drop"
        }
    }
    var appearanceName: NSAppearance.Name { self == .orchardNight ? .darkAqua : .aqua }

    var colors: ThemeColors {
        switch self {
        case .orchardNight:
            return ThemeColors(canvas: 0x14251D, panel: 0x1C3024, raised: 0x2C4331,
                               ink: 0xF2F7E9, muted: 0xB5C7A5, accent: 0xBDF620,
                               line: 0x42583D, primary: 0xBDF620, onPrimary: 0x173C2A)
        case .vividPistachio:
            return ThemeColors(canvas: 0xFFF9EB, panel: 0xFFFEF6, raised: 0xEDF1DC,
                               ink: 0x173C2A, muted: 0x526448, accent: 0x27591F,
                               line: 0xD2DEC5, primary: 0xBDF620, onPrimary: 0x173C2A)
        case .lemonDrop:
            return ThemeColors(canvas: 0xFFFAED, panel: 0xFFFEF7, raised: 0xFFF0C0,
                               ink: 0x3C3318, muted: 0x6E6040, accent: 0x76551C,
                               line: 0xE7D9B5, primary: 0xFFDB23, onPrimary: 0x3C3318)
        }
    }
}

struct ThemeColors: Sendable {
    let canvas: UInt32
    let panel: UInt32
    let raised: UInt32
    let ink: UInt32
    let muted: UInt32
    let accent: UInt32
    let line: UInt32
    let primary: UInt32
    let onPrimary: UInt32
}

/// Color snapshots change with the saved theme even when both themes use Aqua.
/// UserDefaults provides synchronized reads without a mutable global color cache.
enum Palette {
    static var theme: AppTheme { AppTheme.saved }
    static var canvasColor: NSColor { nsColor(theme.colors.canvas) }
    static var panelColor: NSColor { nsColor(theme.colors.panel) }
    static var raisedColor: NSColor { nsColor(theme.colors.raised) }
    static var inkColor: NSColor { nsColor(theme.colors.ink) }
    static var mutedColor: NSColor { nsColor(theme.colors.muted) }
    static var accentColor: NSColor { nsColor(theme.colors.accent) }
    static var lineColor: NSColor { nsColor(theme.colors.line) }

    static var editorCanvasColor: NSColor { nsColor(theme == .orchardNight ? 0x1C1F20 : 0xEBEDE9) }
    static var editorCanvas: Color { Color(nsColor: editorCanvasColor) }
    static func shortcutFill(_ mode: WheelMode) -> Color {
        switch mode {
        case .convert: return primaryAction.opacity(theme == .orchardNight ? 0.14 : 0.18)
        case .tools: return color(0xEDAB76).opacity(theme == .orchardNight ? 0.17 : 0.20)
        case .actions: return color(0xBBA4E2).opacity(theme == .orchardNight ? 0.17 : 0.20)
        }
    }

    static var background: Color { Color(nsColor: canvasColor) }
    static var panel: Color { Color(nsColor: panelColor) }
    static var raised: Color { Color(nsColor: raisedColor) }
    static var ink: Color { Color(nsColor: inkColor) }
    static var muted: Color { Color(nsColor: mutedColor) }
    static var accent: Color { Color(nsColor: accentColor) }
    static var line: Color { Color(nsColor: lineColor) }
    static var primaryAction: Color { color(theme.colors.primary) }
    static var onPrimary: Color { color(theme.colors.onPrimary) }
    // Keep existing view call sites compatible; these aliases also turn yellow.
    static var lime: Color { primaryAction }
    static var onLime: Color { onPrimary }
    static let apricot = Color(red: 1, green: 156 / 255, blue: 69 / 255)

    static func color(_ value: UInt32) -> Color { Color(nsColor: nsColor(value)) }
    private static func nsColor(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                green: CGFloat((value >> 8) & 255) / 255,
                blue: CGFloat(value & 255) / 255, alpha: 1)
    }
}

/// Use glass for navigation chrome only, with an opaque accessibility fallback.
private struct NavigationChrome: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    let radius: CGFloat
    let theme: AppTheme

    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content.background(Palette.color(theme.colors.panel), in: RoundedRectangle(cornerRadius: radius))
                .overlay(RoundedRectangle(cornerRadius: radius).stroke(Palette.color(contrast == .increased ? theme.colors.ink : theme.colors.line), lineWidth: 1))
        } else {
            // Older toolchains can still build the macOS 13-compatible fallback.
            #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius))
            } else {
                standardMaterial(content)
            }
            #else
            standardMaterial(content)
            #endif
        }
    }

    private func standardMaterial(_ content: Content) -> some View {
        content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(Palette.color(theme.colors.line).opacity(0.7), lineWidth: 1))
    }
}

extension View {
    func navigationChrome(radius: CGFloat = 18) -> some View {
        modifier(NavigationChrome(radius: radius, theme: Palette.theme))
    }
}

struct AppMark: View {
    var size: CGFloat = 42

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .renderingMode(.original)
            .resizable().interpolation(.high).scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Use the system's rounded face for native branding without bundling a font.
struct AppWordmark: View {
    var size: CGFloat = 20

    var body: some View {
        Text("Lemulip")
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .tracking(-size * 0.02)
            .fixedSize(horizontal: true, vertical: false)
    }
}
#endif
