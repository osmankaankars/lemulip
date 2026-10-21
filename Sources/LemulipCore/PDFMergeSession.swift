#if os(macOS)
import Foundation
import PDFKit

/// Reads source summaries and first-page previews one at a time. Unlike the
/// page organizer, a merge preview never retains a document or source snapshot
/// between requests, regardless of how many PDFs appear in the list.
public actor PDFMergeSession {
    public static let thumbnailPixelLimit = PDFOrganizeSession.thumbnailPixelLimit
    public static let thumbnailCacheLimit = 24

    private let inputs: [URL]
    private var checkedInputs: [URL]?
    private var sources: [Int: PDFMergeSource] = [:]
    private var inspectedBytes: Int64 = 0
    private var thumbnails: [Int: PDFPageThumbnail] = [:]
    private var recency: [Int] = []
    private var closed = false

    public init(inputs: [URL]) { self.inputs = inputs }

    /// The UI awaits this in input order and can show progress after each file.
    /// A high initial page total is allowed so files can be removed in the UI;
    /// PDFMergePlan validates the final total before export.
    public func source(for inputIndex: Int) throws -> PDFMergeSource {
        try Task.checkCancellation()
        let input = try checkedInput(at: inputIndex)
        if let source = sources[inputIndex] { return source }
        let source = try PDFSourceSnapshot.withFileContext(input) {
            try autoreleasepool {
                let snapshot = try PDFSourceSnapshot.capture(input,
                    byteLimit: PDFMergePlan.maximumTotalBytes - inspectedBytes)
                let document = try snapshot.openDocument()
                let source = PDFMergeSource(inputIndex: inputIndex, pageCount: document.pageCount,
                    fingerprint: snapshot.fingerprint, byteCount: snapshot.byteCount,
                    isEncrypted: document.isEncrypted)
                try Task.checkCancellation()
                return withExtendedLifetime(snapshot) { source }
            }
        }
        sources[inputIndex] = source
        inspectedBytes += source.byteCount
        return source
    }

    public func thumbnail(for inputIndex: Int) throws -> PDFPageThumbnail {
        try Task.checkCancellation()
        let input = try checkedInput(at: inputIndex)
        guard let source = sources[inputIndex] else {
            throw LemulipError.invalidInput("Wait for \(input.lastPathComponent) to finish opening before showing its preview.")
        }
        if let cached = thumbnails[inputIndex] {
            touch(inputIndex)
            return cached
        }
        let thumbnail = try PDFSourceSnapshot.withFileContext(input) {
            try autoreleasepool {
                let snapshot = try PDFSourceSnapshot.capture(input)
                guard snapshot.fingerprint == source.fingerprint, snapshot.byteCount == source.byteCount else {
                    throw LemulipError.invalidInput("This PDF changed after the merge preview opened. Reopen Merge PDF before exporting.")
                }
                let document = try snapshot.openDocument()
                guard document.pageCount == source.pageCount, document.isEncrypted == source.isEncrypted else {
                    throw LemulipError.invalidInput("This PDF changed after the merge preview opened. Reopen Merge PDF before exporting.")
                }
                let result = try PDFSourceSnapshot.thumbnail(in: document, at: 0)
                try Task.checkCancellation()
                return withExtendedLifetime(snapshot) { result }
            }
        }
        while thumbnails.count >= Self.thumbnailCacheLimit, let oldest = recency.first {
            thumbnails.removeValue(forKey: oldest)
            recency.removeFirst()
        }
        thumbnails[inputIndex] = thumbnail
        touch(inputIndex)
        return thumbnail
    }

    public func close() {
        closed = true
        sources.removeAll()
        inspectedBytes = 0
        thumbnails.removeAll()
        recency.removeAll()
        checkedInputs = nil
    }

    var cachedThumbnailCount: Int { thumbnails.count }
    var inspectedByteCount: Int64 { inspectedBytes }

    private func checkedInput(at index: Int) throws -> URL {
        guard !closed else { throw LemulipError.cancelled }
        guard (2...PDFMergePlan.maximumInputCount).contains(inputs.count),
              index >= 0, index < inputs.count else {
            throw LemulipError.invalidInput("Choose between 2 and \(PDFMergePlan.maximumInputCount) PDF files for the merge preview.")
        }
        if checkedInputs == nil {
            var seen = Set<String>()
            checkedInputs = try inputs.map { input in
                guard input.isFileURL, !input.path.contains("\0"), FileFamily.detect(input) == .pdf else {
                    throw LemulipError.invalidInput("Choose local PDF files for the merge preview.")
                }
                let resolved = input.standardizedFileURL.resolvingSymlinksInPath()
                guard seen.insert(resolved.path).inserted else {
                    throw LemulipError.invalidInput("\(input.lastPathComponent) appears more than once. Choose each PDF once.")
                }
                return resolved
            }
        }
        guard let checkedInputs else { throw LemulipError.cancelled }
        return checkedInputs[index]
    }

    private func touch(_ index: Int) {
        recency.removeAll { $0 == index }
        recency.append(index)
    }
}
#endif
