#if os(macOS)
import AppKit

/// Exports the synthetic host through AppKit's PDF drawing path. A rasterized
/// PDF is diagnostic evidence, never a Retina screenshot or approved asset.
@MainActor
enum NativeReviewPDF {
    static func saveCalibration(of view: NSView, log: DensityDrawLog, directory: URL) throws {
        guard view.bounds.origin == .zero, view.bounds.size == NSSize(width: 320, height: 240) else {
            throw NativeReviewFailure("The PDF probe requires the unchanged 320 by 240 point calibration host")
        }
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        log.draws.removeAll()
        let pdf = view.dataWithPDF(inside: view.bounds)
        try pdf.write(to: directory.appendingPathComponent("calibration.pdf"), options: .withoutOverwriting)
        var record = NativeReviewBitmap.provenance
        let exportDetails: [String: Any] = [
            "capture": "NSView.dataWithPDF(inside:) of the synthetic SwiftUI/AppKit calibration host",
            "captureKind": "Native view PDF export; not a screen capture",
            "logicalWidth": 320, "logicalHeight": 240,
            "windowBackingScale": Double(view.window?.backingScaleFactor ?? 0),
            "observedSwiftUIEnvironmentScales": log.environmentScales,
            "pdfSHA256": NativeReviewBitmap.digest(pdf), "pdfBytes": pdf.count,
            "drawsDuringPDFExport": log.draws,
            "production2xCandidatesAllowed": false, "inputEventsSent": false,
            "layerScaleOverridden": false, "environmentScaleOverridden": false,
            "assetEligibility": "Diagnostic only; raw PDF objects and original pixels require review",
            "references": [
                "https://developer.apple.com/documentation/appkit/nsview/datawithpdf(inside:)",
                "https://developer.apple.com/documentation/coregraphics/cgpdfpage/getdrawingtransform(_:rect:rotate:preserveaspectratio:)",
                "https://developer.apple.com/documentation/coregraphics/cgcontext/drawpdfpage(_:)"
            ]
        ]
        record.merge(exportDetails, uniquingKeysWith: { _, value in value })
        // Retain the exact export even if parsing or rasterization fails later.
        try NativeReviewBitmap.writeJSON(record, name: "calibration-pdf-export", directory: directory)
        guard let provider = CGDataProvider(data: pdf as CFData),
              let document = CGPDFDocument(provider), document.numberOfPages == 1,
              let page = document.page(at: 1) else {
            throw NativeReviewFailure("The native PDF export must contain exactly one readable page")
        }
        let box = page.getBoxRect(.mediaBox)
        guard box.size == view.bounds.size, page.rotationAngle == 0 else {
            throw NativeReviewFailure("The native PDF page must retain the calibration's point dimensions and orientation")
        }
        let width = 640, height = 480
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
            throw NativeReviewFailure("Could not allocate the PDF diagnostic raster context")
        }
        let pixels = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(pixels)
        let transform = page.getDrawingTransform(.mediaBox, rect: pixels, rotate: 0, preserveAspectRatio: true)
        context.concatenate(transform)
        context.drawPDFPage(page)
        guard let image = context.makeImage(), let data = context.data else {
            throw NativeReviewFailure("Could not read the rendered PDF diagnostic")
        }
        let bitmap = NSBitmapImageRep(cgImage: image)
        bitmap.size = view.bounds.size
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NativeReviewFailure("Could not encode the rendered PDF diagnostic")
        }
        try png.write(to: directory.appendingPathComponent("calibration-pdf-2x.png"), options: .withoutOverwriting)
        let ctm = context.ctm
        let renderDetails: [String: Any] = [
            "captureKind": "Native view PDF export rasterized at two pixels per point; not a Retina screenshot",
            "pdfMediaBox": [Double(box.minX), Double(box.minY), Double(box.width), Double(box.height)],
            "pdfPageCount": document.numberOfPages, "pdfPageRotation": Int(page.rotationAngle),
            "pdfToPixelTransform": [Double(transform.a), Double(transform.b), Double(transform.c),
                                    Double(transform.d), Double(transform.tx), Double(transform.ty)],
            "drawingCTM": [Double(ctm.a), Double(ctm.b), Double(ctm.c), Double(ctm.d), Double(ctm.tx), Double(ctm.ty)],
            "requestedPDFRasterScale": 2, "pixelWidth": bitmap.pixelsWide, "pixelHeight": bitmap.pixelsHigh,
            "colorSpace": "NSDeviceRGBColorSpace", "resizedAfterCapture": false,
            "pngSHA256": NativeReviewBitmap.digest(png), "pngBytes": png.count,
            "rawPixelSHA256": NativeReviewBitmap.digest(Data(bytes: data, count: context.bytesPerRow * height)),
            "rawPixelSource": "CGContext RGBA8 premultipliedLast byteOrder32Big", "rawPixelBytesPerRow": context.bytesPerRow,
            "pdfContentInspection": "Pending: inspect font/text/vector operators and embedded raster images before drawing a density conclusion"
        ]
        record.merge(renderDetails, uniquingKeysWith: { _, value in value })
        try NativeReviewBitmap.writeJSON(record, name: "calibration-pdf-2x", directory: directory)
    }
}
#endif
