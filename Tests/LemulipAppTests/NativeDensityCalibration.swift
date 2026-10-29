#if os(macOS)
import AppKit
import SwiftUI

@MainActor
final class DensityDrawLog {
    var draws: [[String: Any]] = []

    func record(_ element: String) {
        guard let ctm = NSGraphicsContext.current?.cgContext.ctm else { return }
        draws.append(["element": element,
                      "scaleX": Double(hypot(ctm.a, ctm.b)), "scaleY": Double(hypot(ctm.c, ctm.d)),
                      "ctm": [Double(ctm.a), Double(ctm.b), Double(ctm.c), Double(ctm.d), Double(ctm.tx), Double(ctm.ty)]])
    }

    func hasFreshDraw(_ element: String, scale: Double) -> Bool {
        draws.contains {
            $0["element"] as? String == element
                && abs(($0["scaleX"] as? Double ?? 0) - scale) < 0.01
                && abs(($0["scaleY"] as? Double ?? 0) - scale) < 0.01
        }
    }
}

/// Deliberately not a product mockup. Both halves carry unrecoverable-at-1x
/// half-point detail, and the lower half uses an actual editable NSTextField.
@MainActor
struct NativeDensityCalibration: View {
    let log: DensityDrawLog

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                Color.white
                Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1).frame(width: 8, height: 8)
                Text("SwiftUI — Il1MW 0123456789")
                    .font(.system(size: 12)).foregroundStyle(.black).fixedSize().offset(x: 16, y: 12)
                DensityBars(phase: 0).fill(.black, style: FillStyle(antialiased: true))
                    .frame(width: 64, height: 12).offset(x: 16, y: 42)
                DensityBars(phase: 0.5).fill(.black, style: FillStyle(antialiased: true))
                    .frame(width: 64, height: 12).offset(x: 16, y: 64)
                Path { path in
                    path.move(to: CGPoint(x: 16, y: 108))
                    path.addLine(to: CGPoint(x: 90, y: 86))
                    path.addLine(to: CGPoint(x: 158, y: 108))
                    path.addEllipse(in: CGRect(x: 186, y: 82, width: 27, height: 27))
                }.stroke(.black, lineWidth: 0.5)
            }.frame(width: 320, height: 120)
            DensityNativeRepresentable(log: log).frame(width: 320, height: 120)
        }.frame(width: 320, height: 240).environment(\.colorScheme, .light)
    }
}

private struct DensityBars: Shape {
    let phase: CGFloat
    func path(in rect: CGRect) -> Path {
        Path { path in
            for index in 0..<Int(rect.width) {
                path.addRect(CGRect(x: CGFloat(index) + phase, y: 0, width: 0.5, height: rect.height))
            }
        }
    }
}

@MainActor
private struct DensityNativeRepresentable: NSViewRepresentable {
    let log: DensityDrawLog

    func makeNSView(context: Context) -> DensityNativeView {
        let view = DensityNativeView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))
        view.log = log
        let field = DensityTextField(frame: NSRect(x: 16, y: 10, width: 280, height: 22))
        field.log = log
        field.stringValue = "AppKit — Il1MW 0123456789"
        field.font = .systemFont(ofSize: 12)
        field.textColor = .black
        field.isEditable = true
        field.isSelectable = true
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.setAccessibilityLabel("Native density calibration text")
        view.addSubview(field)
        return view
    }
    func updateNSView(_ nsView: DensityNativeView, context: Context) {}
}

@MainActor
private final class DensityNativeView: NSView {
    var log: DensityDrawLog?
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        log?.record("nativeVectors")
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setFillColor(NSColor.white.cgColor)
        context.fill(bounds)
        context.setFillColor(NSColor.blue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        context.setFillColor(NSColor.black.cgColor)
        for (y, phase) in [(42.0, 0.0), (64.0, 0.5)] {
            for index in 0..<64 {
                context.fill(CGRect(x: 16 + Double(index) + phase, y: y, width: 0.5, height: 12))
            }
        }
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: 16, y: 108))
        context.addLine(to: CGPoint(x: 90, y: 86))
        context.addLine(to: CGPoint(x: 158, y: 108))
        context.addEllipse(in: CGRect(x: 186, y: 82, width: 27, height: 27))
        context.strokePath()
    }
}

@MainActor
private final class DensityTextField: NSTextField {
    var log: DensityDrawLog?
    override func draw(_ dirtyRect: NSRect) {
        log?.record("nativeText")
        super.draw(dirtyRect)
    }
}
#endif
