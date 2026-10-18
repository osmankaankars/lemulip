import Foundation

/// A PDF keeps its original input identity while the merge list is reordered.
/// Its content fingerprint binds the summary and cover preview to the export.
public struct PDFMergeSource: Equatable, Sendable {
    public let inputIndex: Int
    public let pageCount: Int
    public let fingerprint: String
    public let byteCount: Int64
    public let isEncrypted: Bool

    public init(inputIndex: Int, pageCount: Int, fingerprint: String,
                byteCount: Int64, isEncrypted: Bool) {
        self.inputIndex = inputIndex
        self.pageCount = pageCount
        self.fingerprint = fingerprint
        self.byteCount = byteCount
        self.isEncrypted = isEncrypted
    }

    func validate(inputCount: Int) throws {
        guard inputIndex >= 0, inputIndex < inputCount,
              (1...PDFMergePlan.maximumPageCount).contains(pageCount),
              byteCount > 0, byteCount <= PDFMergePlan.maximumTotalBytes,
              fingerprint.utf8.count == 64,
              fingerprint.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw FreewheelError.invalidInput("A PDF merge summary is invalid. Reopen Merge PDF before exporting.")
        }
    }
}

/// Retained files appear exactly once, in the chosen order. Pages within each
/// file keep their original order. The original input count includes removals.
public struct PDFMergePlan: Equatable, Sendable {
    public static let maximumInputCount = 100
    public static let maximumPageCount = PDFOrganizePlan.maximumPageCount
    public static let maximumTotalBytes: Int64 = 512 * 1_024 * 1_024

    public var sourceInputCount: Int
    public var sources: [PDFMergeSource]

    public init(sourceInputCount: Int, sources: [PDFMergeSource]) {
        self.sourceInputCount = sourceInputCount
        self.sources = sources
    }

    public func validate() throws {
        guard (2...Self.maximumInputCount).contains(sourceInputCount),
              sources.count >= 2, sources.count <= sourceInputCount else {
            throw FreewheelError.invalidInput("Keep at least two PDFs in a merge list with up to \(Self.maximumInputCount) files.")
        }
        var seen = Set<Int>()
        var pageCount = 0
        var byteCount: Int64 = 0
        for source in sources {
            try source.validate(inputCount: sourceInputCount)
            guard seen.insert(source.inputIndex).inserted else {
                throw FreewheelError.invalidInput("Each PDF can appear only once in the merge list.")
            }
            guard source.pageCount <= Self.maximumPageCount - pageCount else {
                throw FreewheelError.invalidInput("Keep at most \(Self.maximumPageCount) pages in the merged PDF. Remove a file to reduce the total.")
            }
            guard source.byteCount <= Self.maximumTotalBytes - byteCount else {
                throw FreewheelError.invalidInput("The PDFs in a visual merge must total at most 512 MiB.")
            }
            pageCount += source.pageCount
            byteCount += source.byteCount
        }
    }

    public func validate(sourceInputCount: Int) throws {
        try validate()
        guard self.sourceInputCount == sourceInputCount else {
            throw FreewheelError.invalidInput("The PDF input list changed. Reopen Merge PDF before exporting.")
        }
    }
}
