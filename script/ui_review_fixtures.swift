import Foundation
import CoreGraphics
import CoreText
import PDFKit

// Synthetic, visibly numbered pages serve both the native smoke and physical UI review.
func makePDF(_ url: URL, labels: [String]) throws {
    guard let context = CGContext(url as CFURL, mediaBox: nil, nil) else {
        throw NSError(domain: "UIReviewFixtures", code: 1)
    }
    let font = CTFontCreateWithName("Helvetica" as CFString, 28, nil)
    for label in labels {
        var box = CGRect(x: 0, y: 0, width: 420, height: 300)
        context.beginPDFPage([kCGPDFContextMediaBox as String:
            Data(bytes: &box, count: MemoryLayout<CGRect>.size)] as CFDictionary)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(box)
        let text = NSAttributedString(string: label, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
        ])
        context.textPosition = CGPoint(x: 24, y: 240)
        CTLineDraw(CTLineCreateWithAttributedString(text), context)
        context.endPDFPage()
    }
    context.closePDF()
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.count == 2 else {
        throw NSError(domain: "Usage: ui_review_fixtures.swift make DIRECTORY | inspect PDF", code: 2)
    }
    let url = URL(fileURLWithPath: arguments[1])
    switch arguments[0] {
    case "make":
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw NSError(domain: "Fixture directory must be new", code: 3)
        }
        let merge = url.appendingPathComponent("Merge", isDirectory: true)
        let organize = url.appendingPathComponent("Organize", isDirectory: true)
        try FileManager.default.createDirectory(at: merge, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: organize, withIntermediateDirectories: true)
        try makePDF(merge.appendingPathComponent("01-Cover.pdf"), labels: ["01 - Cover"])
        try makePDF(merge.appendingPathComponent("02-Report.pdf"), labels: ["02.1 - Report", "02.2 - Report"])
        try makePDF(merge.appendingPathComponent("03-Notes.pdf"), labels: ["03 - Notes"])
        try makePDF(organize.appendingPathComponent("Page-Order.pdf"), labels: (1...4).map { "PAGE \($0)" })
        try "1\n00:00:00,000 --> 00:00:01,000\nUI review subtitle\n".write(
            to: url.appendingPathComponent("Subtitle.srt"), atomically: true, encoding: .utf8)
    case "inspect":
        guard let document = PDFDocument(url: url), document.pageCount > 0 else {
            throw NSError(domain: "Unreadable PDF", code: 4)
        }
        let labels = (0..<document.pageCount).map {
            document.page(at: $0)?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        let data = try JSONSerialization.data(withJSONObject: labels, options: [.sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    default:
        throw NSError(domain: "Unknown fixture command", code: 5)
    }
} catch {
    FileHandle.standardError.write(Data("UI review fixture error: \(error)\n".utf8))
    exit(1)
}
