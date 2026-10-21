import Foundation

/// A page keeps its original zero-based identity as it moves through the editor.
/// Rotation is a clockwise quarter-turn delta added to the source page's rotation.
public struct PDFPageEdit: Equatable, Hashable, Sendable {
    public var sourceIndex: Int
    public var rotationQuarterTurns: Int

    public init(sourceIndex: Int, rotationQuarterTurns: Int = 0) {
        self.sourceIndex = sourceIndex
        self.rotationQuarterTurns = rotationQuarterTurns
    }
}

/// The output consists of these pages, in this order. Omitting a source page
/// removes it from the new copy; a subset of the plan extracts selected pages.
/// The SHA-256 fingerprint binds edits to the bytes used for the preview.
public struct PDFOrganizePlan: Equatable, Sendable {
    public static let maximumPageCount = 1_000

    public var sourcePageCount: Int
    public var sourceFingerprint: String
    public var pages: [PDFPageEdit]

    public init(sourcePageCount: Int, sourceFingerprint: String, pages: [PDFPageEdit]) {
        self.sourcePageCount = sourcePageCount
        self.sourceFingerprint = sourceFingerprint
        self.pages = pages
    }

    public func validate() throws {
        guard (1...Self.maximumPageCount).contains(sourcePageCount),
              !pages.isEmpty, pages.count <= sourcePageCount,
              sourceFingerprint.utf8.count == 64,
              sourceFingerprint.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw LemulipError.invalidInput("Choose at least one page from a PDF with up to \(Self.maximumPageCount) pages, then reopen the editor if the source changed.")
        }
        var seen = Set<Int>()
        for page in pages {
            guard page.sourceIndex >= 0, page.sourceIndex < sourcePageCount,
                  seen.insert(page.sourceIndex).inserted,
                  (0...3).contains(page.rotationQuarterTurns) else {
                throw LemulipError.invalidInput("PDF pages must appear once, stay within the original page range, and use quarter-turn rotations.")
            }
        }
    }

    public func validate(sourcePageCount: Int, sourceFingerprint: String) throws {
        try validate()
        guard self.sourcePageCount == sourcePageCount,
              self.sourceFingerprint == sourceFingerprint else {
            throw LemulipError.invalidInput("The PDF changed after the editor opened. Reopen Organize PDF before exporting.")
        }
    }
}

public struct PDFOrganizeSource: Equatable, Sendable {
    public let pageCount: Int
    public let fingerprint: String
    public let isEncrypted: Bool

    public var initialPlan: PDFOrganizePlan {
        PDFOrganizePlan(sourcePageCount: pageCount, sourceFingerprint: fingerprint,
                        pages: (0..<pageCount).map { PDFPageEdit(sourceIndex: $0) })
    }
}
