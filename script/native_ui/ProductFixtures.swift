import AppKit
import CoreGraphics
import CoreText
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = root.appendingPathComponent("Field notes.pdf")
let context = CGContext(destination as CFURL, mediaBox: nil, nil)!
let green = CGColor(red: 0.09, green: 0.23, blue: 0.16, alpha: 1)
let pages = [("01", "A little room to explore", "FIELD NOTES", "A small collection of places, ideas and useful details."),
             ("02", "Take the slower route", "PLACES", "A morning walk. A quiet corner. Something worth keeping."),
             ("03", "Keep the good parts", "OBSERVATIONS", "Collect what matters. Leave a little space for the unexpected."),
             ("04", "Make it your own", "NEXT STEPS", "Arrange the pages, add your notes, and create a new copy.")]
for (number, title, category, detail) in pages {
    var box = CGRect(x: 0, y: 0, width: 420, height: 560)
    context.beginPDFPage([kCGPDFContextMediaBox as String: Data(bytes: &box, count: MemoryLayout<CGRect>.size)] as CFDictionary)
    context.setFillColor(CGColor(red: 1, green: 0.98, blue: 0.92, alpha: 1)); context.fill(box)
    context.setFillColor(green); context.fill(CGRect(x: 0, y: 0, width: 420, height: 170))
    func text(_ string: String, _ size: CGFloat, _ x: CGFloat, _ y: CGFloat, _ color: CGColor = green) {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, size, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color]
        context.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes)), context)
    }
    text(category, 11, 32, 510); text(number, 74, 28, 376)
    text(title, 23, 32, 325)
    let words = detail.split(separator: ".")
    for (i, line) in words.enumerated() where !line.isEmpty { text(String(line).trimmingCharacters(in: .whitespaces) + ".", 11, 32, 284 - CGFloat(i * 20)) }
    let cream = CGColor(red: 1, green: 0.98, blue: 0.92, alpha: 1)
    text("LE MULIP / SAMPLE DOCUMENT", 10, 32, 110, cream)
    text("A real PDF for trying the page tools.", 12, 32, 82, cream)
    text("Synthetic content. Originals are kept.", 10, 32, 56, cream)
    context.endPDFPage()
}
context.closePDF()
