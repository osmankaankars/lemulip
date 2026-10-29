import Foundation

/// A page selection can be checked while the user types without opening a PDF
/// or expanding its ranges. The converter validates the actual document bounds
/// before expanding pages in the requested order.
public struct PDFPageRange: Sendable {
    public static let maximumSpecificationLength = 10_000

    public enum SyntaxError: Error, Equatable, Sendable {
        case empty
        case tooLong
        case invalidRange
    }

    private let ranges: [ClosedRange<Int>]

    public init(_ specification: String) throws {
        guard !specification.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SyntaxError.empty
        }
        guard specification.count <= Self.maximumSpecificationLength else {
            throw SyntaxError.tooLong
        }
        var ranges: [ClosedRange<Int>] = []
        for part in specification.split(separator: ",", omittingEmptySubsequences: false) {
            let components = part.trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: "-", omittingEmptySubsequences: false)
            guard (1...2).contains(components.count),
                  let first = Int(components[0].trimmingCharacters(in: .whitespaces)),
                  let last = Int(components.last!.trimmingCharacters(in: .whitespaces)),
                  first >= 1, last >= first else {
                throw SyntaxError.invalidRange
            }
            ranges.append(first...last)
        }
        self.ranges = ranges
    }

    /// Returns zero-based page indices, retaining the first occurrence of each
    /// page. Every range must fit the source before any range is expanded.
    public func indices(pageCount: Int) throws -> [Int] {
        guard pageCount > 0, ranges.allSatisfy({ $0.upperBound <= pageCount }) else {
            throw LemulipError.invalidInput("Page ranges must be within 1-\(pageCount), for example 1-3,5.")
        }
        var result: [Int] = [], seen = Set<Int>()
        for range in ranges {
            for page in range where seen.insert(page - 1).inserted { result.append(page - 1) }
        }
        return result
    }
}
