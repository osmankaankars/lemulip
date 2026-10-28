import Foundation

/// Presentation preferences contain no file history. Old Finder behavior is retained.
public enum CompletionPresentation: String, CaseIterable, Sendable {
    case quiet, finder, card

    public static func resolve(stored: String?, legacyReveal: Bool) -> Self {
        stored.flatMap(Self.init(rawValue:)) ?? (legacyReveal ? .finder : .quiet)
    }
}

/// A small, in-memory result surface. Existing rows never move when another job finishes.
public struct CompletionResults: Sendable {
    public private(set) var urls: [URL] = []
    public private(set) var omittedCount = 0
    public init() {}

    public mutating func append(_ outputs: [URL]) {
        var seen = Set(urls)
        for url in outputs where url.isFileURL {
            let normalized = url.standardizedFileURL
            guard seen.insert(normalized).inserted else { continue }
            if urls.count < 8 { urls.append(normalized) }
            else { omittedCount += 1 }
        }
    }

    public mutating func removeAll() {
        urls.removeAll(); omittedCount = 0
    }
}

/// Search and user pins are a separate presentation layer; Catalog and wheel order stay untouched.
public enum OperationDiscovery {
    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "ı", with: "i")
    }

    public static func matching(_ operations: [FileOperation], query: String,
                                localizedTitles: [String: String] = [:],
                                localizedDetails: [String: String] = [:]) -> [FileOperation] {
        let terms = normalized(String(query.prefix(512))).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return operations }
        return operations.filter { operation in
            let value = normalized([operation.id, operation.title, operation.detail,
                                    localizedTitles[operation.id] ?? "", localizedDetails[operation.id] ?? ""].joined(separator: " "))
            return terms.allSatisfy(value.contains)
        }
    }

    public static func normalizedPins(_ identifiers: [String]) -> [String] {
        var seen = Set<String>()
        return Array(identifiers.filter { identifier in
            identifier.count <= 96 && identifier.range(of: "^(convert|image|media|pdf|archive|document|action)\\.[A-Za-z0-9]+$", options: .regularExpression) != nil
                && seen.insert(identifier).inserted
        }.prefix(12))
    }

    public static func pinned(from operations: [FileOperation], identifiers: [String]) -> [FileOperation] {
        normalizedPins(identifiers).compactMap { id in operations.first { $0.id == id } }
    }
}
