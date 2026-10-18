#if os(macOS)
import Foundation
import CoreGraphics
import CryptoKit
import Darwin
import PDFKit

/// The pixels are immutable. No PDFDocument or PDFPage crosses the actor boundary.
public struct PDFPageThumbnail: @unchecked Sendable {
    public let image: CGImage
    public let sourceIndex: Int
    public let widthPoints: Double
    public let heightPoints: Double
}

/// Owns one PDFKit document and its small LRU thumbnail cache. Every PDFKit call
/// is synchronous within this actor; rendering never overlaps another page read.
public actor PDFOrganizeSession {
    public static let thumbnailPixelLimit = 320
    public static let thumbnailCacheLimit = 24

    private let input: URL
    private var snapshot: PDFSourceSnapshot?
    private var document: PDFDocument?
    private var source: PDFOrganizeSource?
    private var thumbnails: [Int: PDFPageThumbnail] = [:]
    private var recency: [Int] = []
    private var closed = false

    public init(input: URL) { self.input = input }

    public func open() throws -> PDFOrganizeSource {
        try Task.checkCancellation()
        guard !closed else { throw FreewheelError.cancelled }
        if let source { return source }
        let snapshot = try PDFSourceSnapshot.capture(input)
        let document = try snapshot.openDocument()
        let source = PDFOrganizeSource(pageCount: document.pageCount,
                                       fingerprint: snapshot.fingerprint,
                                       isEncrypted: document.isEncrypted)
        try Task.checkCancellation()
        self.snapshot = snapshot
        self.document = document
        self.source = source
        return source
    }

    public func thumbnail(for sourceIndex: Int) throws -> PDFPageThumbnail {
        try Task.checkCancellation()
        guard !closed, let document else { throw FreewheelError.cancelled }
        guard sourceIndex >= 0, sourceIndex < document.pageCount else {
            throw FreewheelError.invalidInput("Choose a page within this PDF.")
        }
        if let cached = thumbnails[sourceIndex] {
            touch(sourceIndex)
            return cached
        }
        let thumbnail = try PDFSourceSnapshot.thumbnail(in: document, at: sourceIndex)
        try Task.checkCancellation()
        while thumbnails.count >= Self.thumbnailCacheLimit, let oldest = recency.first {
            thumbnails.removeValue(forKey: oldest)
            recency.removeFirst()
        }
        thumbnails[sourceIndex] = thumbnail
        touch(sourceIndex)
        return thumbnail
    }

    public func close() {
        closed = true
        thumbnails.removeAll()
        recency.removeAll()
        document = nil
        source = nil
        snapshot = nil
    }

    // Internal diagnostics let native tests verify the bounded cache without
    // exposing page objects or making the UI inspect implementation details.
    var cachedThumbnailCount: Int { thumbnails.count }

    private func touch(_ index: Int) {
        recency.removeAll { $0 == index }
        recency.append(index)
    }
}

/// PDFKit reads lazily, so a private source snapshot keeps all previews and page
/// copies on the same bytes even if another app saves over the original file.
/// The copy is streamed, hashed, size-limited, and removed with its owner.
final class PDFSourceSnapshot {
    static let maximumBytes: Int64 = 512 * 1_024 * 1_024
    let url: URL
    let fingerprint: String
    let byteCount: Int64
    private let directory: URL

    private init(url: URL, fingerprint: String, byteCount: Int64, directory: URL) {
        self.url = url; self.fingerprint = fingerprint
        self.byteCount = byteCount; self.directory = directory
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    static func capture(_ input: URL, byteLimit: Int64 = PDFSourceSnapshot.maximumBytes) throws -> PDFSourceSnapshot {
        try Task.checkCancellation()
        guard input.isFileURL, !input.path.contains("\0"), FileFamily.detect(input) == .pdf else {
            throw FreewheelError.invalidInput("Choose a local PDF for the preview.")
        }
        // O_NONBLOCK prevents a named pipe masquerading as a .pdf from blocking
        // before fstat can reject it. It does not change regular-file reads.
        let descriptor = Darwin.open(input.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw FreewheelError.invalidInput("Choose a readable PDF for the preview.")
        }
        let reader = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? reader.close() }
        var before = stat()
        guard fstat(reader.fileDescriptor, &before) == 0,
              before.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              before.st_size > 0, before.st_size <= maximumBytes else {
            throw FreewheelError.invalidInput("PDF previews support nonempty, readable PDF files up to 512 MiB.")
        }
        guard byteLimit > 0, byteLimit <= maximumBytes, before.st_size <= byteLimit else {
            throw FreewheelError.invalidInput("The selected PDFs exceed the 512 MiB total size limit. Choose a smaller batch.")
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lemulip-pdf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        var owned = false
        defer { if !owned { try? FileManager.default.removeItem(at: directory) } }
        let url = directory.appendingPathComponent("source.pdf")
        guard FileManager.default.createFile(atPath: url.path, contents: nil,
                                              attributes: [.posixPermissions: 0o600]) else {
            throw FreewheelError.operationFailed("A private PDF preview could not be prepared.")
        }
        let writer = try FileHandle(forWritingTo: url)
        defer { try? writer.close() }
        var hash = SHA256()
        var total: Int64 = 0
        while true {
            try Task.checkCancellation()
            let count: Int64 = try autoreleasepool {
                guard let chunk = try reader.read(upToCount: 256 * 1_024), !chunk.isEmpty else { return 0 }
                guard Int64(chunk.count) <= byteLimit - total else {
                    throw FreewheelError.invalidInput("The PDF changed or exceeded the 512 MiB preview limit.")
                }
                hash.update(data: chunk)
                try writer.write(contentsOf: chunk)
                return Int64(chunk.count)
            }
            if count == 0 { break }
            total += count
        }
        var after = stat(), current = stat()
        guard fstat(reader.fileDescriptor, &after) == 0,
              fstatat(AT_FDCWD, input.path, &current, 0) == 0,
              sameFileVersion(before, after), sameFileVersion(before, current), total == before.st_size else {
            throw FreewheelError.invalidInput("The PDF changed while it was being opened. Try again after it finishes saving.")
        }
        try writer.close()
        try Task.checkCancellation()
        let fingerprint = hash.finalize().map { String(format: "%02x", $0) }.joined()
        let result = PDFSourceSnapshot(url: url, fingerprint: fingerprint, byteCount: total, directory: directory)
        owned = true
        return result
    }

    func openDocument() throws -> PDFDocument {
        let document = try NativeConverter.loadPDF(url, password: "")
        guard document.allowsDocumentAssembly, document.allowsCopying else {
            throw FreewheelError.invalidInput("This PDF does not permit copying and organizing its pages. Ask its owner for a copy that permits these changes.")
        }
        return document
    }

    static func thumbnail(in document: PDFDocument, at sourceIndex: Int) throws -> PDFPageThumbnail {
        try Task.checkCancellation()
        return try autoreleasepool {
            guard sourceIndex >= 0, sourceIndex < document.pageCount else {
                throw FreewheelError.invalidInput("Choose a page within this PDF.")
            }
            guard let page = document.page(at: sourceIndex) else {
                throw FreewheelError.operationFailed("PDF page \(sourceIndex + 1) could not be read.")
            }
            guard page.rotation % 90 == 0 else {
                throw FreewheelError.invalidInput("A source PDF page has an unsupported rotation.")
            }
            let limit = PDFOrganizeSession.thumbnailPixelLimit
            let size = try NativeConverter.pageSize(page)
            let image = try NativeConverter.renderPDF(page, dpi: 144, longEdge: limit)
            guard image.width <= limit, image.height <= limit else {
                throw FreewheelError.operationFailed("A PDF preview exceeded its thumbnail size limit.")
            }
            return PDFPageThumbnail(image: image, sourceIndex: sourceIndex,
                                    widthPoints: Double(size.width), heightPoints: Double(size.height))
        }
    }

    /// Native file errors can contain full paths. Keep a useful filename and
    /// the controlled PDF diagnostic, without exposing private folder names.
    static func withFileContext<T>(_ input: URL, _ body: () throws -> T) throws -> T {
        do { return try body() }
        catch is CancellationError { throw CancellationError() }
        catch FreewheelError.cancelled { throw FreewheelError.cancelled }
        catch FreewheelError.invalidInput(let message) {
            throw FreewheelError.invalidInput("\(input.lastPathComponent): \(message)")
        } catch FreewheelError.operationFailed(let message) {
            throw FreewheelError.operationFailed("\(input.lastPathComponent): \(message)")
        } catch {
            throw FreewheelError.operationFailed("\(input.lastPathComponent) could not be read. Check that it is a local, readable PDF and try again.")
        }
    }

    private static func sameFileVersion(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino && lhs.st_size == rhs.st_size &&
        lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec &&
        lhs.st_ctimespec.tv_sec == rhs.st_ctimespec.tv_sec && lhs.st_ctimespec.tv_nsec == rhs.st_ctimespec.tv_nsec
    }
}
#endif
