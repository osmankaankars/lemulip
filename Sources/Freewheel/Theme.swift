#if os(macOS)
import AppKit
import SwiftUI

/// Color is concentrated in actions and the app mark; file content stays neutral.
enum Palette {
    static let canvasColor = adaptive(light: 0xFFF9EB, dark: 0x14251D)
    static let panelColor = adaptive(light: 0xFFFEF6, dark: 0x1C3024)
    static let raisedColor = adaptive(light: 0xEDF1DC, dark: 0x2C4331)
    static let inkColor = adaptive(light: 0x173C2A, dark: 0xF2F7E9)
    static let mutedColor = adaptive(light: 0x526448, dark: 0xB5C7A5)
    static let accentColor = adaptive(light: 0x27591F, dark: 0xBDF620)
    static let lineColor = adaptive(light: 0xD2DEC5, dark: 0x42583D)

    static let background = Color(nsColor: canvasColor)
    static let panel = Color(nsColor: panelColor)
    static let raised = Color(nsColor: raisedColor)
    static let ink = Color(nsColor: inkColor)
    static let muted = Color(nsColor: mutedColor)
    static let accent = Color(nsColor: accentColor)
    static let line = Color(nsColor: lineColor)
    static let lime = Color(red: 189 / 255, green: 246 / 255, blue: 32 / 255)
    static let apricot = Color(red: 1, green: 156 / 255, blue: 69 / 255)
    static let onLime = Color(red: 23 / 255, green: 60 / 255, blue: 42 / 255)

    private static func adaptive(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        }
    }
}

/// Use glass for navigation chrome only, with an opaque accessibility fallback.
private struct NavigationChrome: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    let radius: CGFloat

    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content.background(Palette.panel, in: RoundedRectangle(cornerRadius: radius))
                .overlay(RoundedRectangle(cornerRadius: radius).stroke(Palette.line, lineWidth: 1))
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
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(Palette.line.opacity(0.7), lineWidth: 1))
    }
}

extension View {
    func navigationChrome(radius: CGFloat = 18) -> some View {
        modifier(NavigationChrome(radius: radius))
    }
}

struct AppMark: View {
    var size: CGFloat = 42

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable().interpolation(.high).scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
#endif
