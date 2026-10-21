import Foundation

enum TextCodec {
    static let maximumInputBytes = 32 * 1024 * 1024

    struct DelimitedLimits {
        let rows: Int
        let columns: Int
        let cells: Int
        let fieldUTF16: Int
        let fieldLineFeeds: Int
    }

    private struct Cue {
        let start: Int64
        let end: Int64
        let text: String
    }

    static func read(_ input: URL) throws -> String {
        let data = try readData(input)
        let text: String?
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) { text = String(data: data, encoding: .utf16) }
        else { text = String(data: data, encoding: .utf8) }
        guard let text else { throw LemulipError.invalidInput("Save this text file as UTF-8 or UTF-16 and try again.") }
        return text.first == "\u{FEFF}" ? String(text.dropFirst()) : text
    }

    static func readData(_ input: URL) throws -> Data {
        try Task.checkCancellation()
        let size = try input.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= maximumInputBytes else { throw LemulipError.invalidInput("Text files larger than 32 MiB are not supported by this tool.") }
        let handle = try FileHandle(forReadingFrom: input)
        defer { try? handle.close() }
        var data = Data()
        // Read at most one byte beyond the limit. A file growing after the
        // size check must not turn a bounded text job into an unbounded read.
        while true {
            try Task.checkCancellation()
            let count = min(65_536, maximumInputBytes + 1 - data.count)
            guard let chunk = try handle.read(upToCount: count), !chunk.isEmpty else { break }
            data.append(chunk)
            guard data.count <= maximumInputBytes else { throw LemulipError.invalidInput("Text files larger than 32 MiB are not supported by this tool.") }
        }
        return data
    }

    static func convertSubtitles(_ input: String, from source: String, to target: String) throws -> String {
        guard ["srt", "vtt"].contains(source), ["srt", "vtt", "txt"].contains(target) else {
            throw LemulipError.unsupported("Choose SRT, WebVTT, or plain text for subtitle output.")
        }
        let cues = try parseSubtitles(input, format: source)
        if target == "txt" { return cues.map { plainSubtitle($0.text) }.joined(separator: "\n\n") + (cues.isEmpty ? "" : "\n") }
        let blocks = cues.enumerated().map { index, cue in
            let timing = "\(timestamp(cue.start, comma: target == "srt")) --> \(timestamp(cue.end, comma: target == "srt"))"
            if target == "srt" { return "\(index + 1)\n\(timing)\n\(plainSubtitle(cue.text))" }
            return "\(timing)\n\(cue.text)"
        }
        return (target == "vtt" ? "WEBVTT\n\n" : "") + blocks.joined(separator: "\n\n") + (blocks.isEmpty ? "" : "\n")
    }

    private static func parseSubtitles(_ input: String, format: String) throws -> [Cue] {
        var source = input.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if source.first == "\u{FEFF}" { source.removeFirst() }
        if format == "vtt" {
            guard source.hasPrefix("WEBVTT"), source.dropFirst(6).first.map({ $0.isWhitespace }) ?? true else {
                throw LemulipError.invalidInput("This WebVTT file is missing its WEBVTT header.")
            }
            if let headerEnd = source.range(of: "\n\n") { source = String(source[headerEnd.upperBound...]) }
            else { return [] }
        }
        let separator = try NSRegularExpression(pattern: "\\n[\\t ]*\\n+")
        let pieces = separator.stringByReplacingMatches(in: source, range: NSRange(source.startIndex..., in: source), withTemplate: "\u{001E}").components(separatedBy: "\u{001E}")
        var cues: [Cue] = []
        for block in pieces {
            let lines = block.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
            guard let first = lines.first, !first.isEmpty else { continue }
            if format == "vtt", first == "NOTE" || first.hasPrefix("NOTE ") || first == "STYLE" || first == "REGION" { continue }
            guard let timingIndex = lines.prefix(2).firstIndex(where: { $0.contains("-->") }) else {
                throw LemulipError.invalidInput("A subtitle cue is missing its start and end timestamps.")
            }
            let endpoints = lines[timingIndex].components(separatedBy: "-->")
            guard endpoints.count == 2,
                  let start = parseTimestamp(endpoints[0].trimmingCharacters(in: .whitespaces)),
                  let endPart = endpoints[1].split(whereSeparator: { $0.isWhitespace }).first,
                  let end = parseTimestamp(String(endPart)), end >= start else {
                throw LemulipError.invalidInput("A subtitle cue has an invalid timestamp or ends before it starts.")
            }
            let content = lines.dropFirst(timingIndex + 1).joined(separator: "\n")
            guard !content.isEmpty else { throw LemulipError.invalidInput("A subtitle cue contains no text.") }
            cues.append(Cue(start: start, end: end, text: content))
        }
        return cues
    }

    private static func parseTimestamp(_ text: String) -> Int64? {
        let components = text.replacingOccurrences(of: ",", with: ".").split(separator: ":", omittingEmptySubsequences: false)
        guard components.count == 2 || components.count == 3 else { return nil }
        let secondParts = components.last!.split(separator: ".", omittingEmptySubsequences: false)
        guard secondParts.count == 2, (1...3).contains(secondParts[1].count),
              secondParts[1].allSatisfy({ $0.isASCII && $0.isNumber }),
              let seconds = Int64(secondParts[0]), (0..<60).contains(seconds),
              let minutes = Int64(components[components.count - 2]), (0..<60).contains(minutes) else { return nil }
        let hours = components.count == 3 ? Int64(components[0]) : 0
        guard let hours, (0...99_999).contains(hours),
              let millis = Int64(String(secondParts[1]) + String(repeating: "0", count: 3 - secondParts[1].count)) else { return nil }
        return ((hours * 60 + minutes) * 60 + seconds) * 1_000 + millis
    }

    private static func timestamp(_ value: Int64, comma: Bool) -> String {
        let hours = value / 3_600_000, minutes = (value / 60_000) % 60, seconds = (value / 1_000) % 60, millis = value % 1_000
        return String(format: "%02lld:%02lld:%02lld%@%03lld", hours, minutes, seconds, comma ? "," : ".", millis)
    }

    private static func plainSubtitle(_ text: String) -> String {
        let noTags = text.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
        return noTags.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&amp;", with: "&")
    }

    static func convertDelimited(_ text: String, from source: Character, to target: Character) throws -> String {
        let rows = try parseDelimited(text, delimiter: source)
        return rows.map { row in
            row.map { field in
                if field.contains(target) || field.contains("\"") || field.contains("\n") || field.contains("\r") {
                    return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                }
                return field
            }.joined(separator: String(target))
        }.joined(separator: "\r\n") + (rows.isEmpty ? "" : "\r\n")
    }

    /// RFC 4180-style quoting is also used for TSV so tabs/newlines remain inside their fields.
    static func parseDelimited(_ text: String, delimiter: Character) throws -> [[String]] {
        var rows: [[String]] = []
        try forEachDelimitedRow(text, delimiter: delimiter) { rows.append($0) }
        return rows
    }

    /// Delivers a row at a time so workbook export never retains the full cell
    /// table. Limits apply before each row or field can increase that table.
    static func forEachDelimitedRow(_ text: String, delimiter: Character,
                                    limits: DelimitedLimits? = nil,
                                    body: ([String]) throws -> Void) throws {
        guard delimiter == "," || delimiter == "\t" else { throw LemulipError.invalidInput("Choose a comma or tab delimiter.") }
        if let limits {
            guard limits.rows > 0, limits.columns > 0, limits.cells > 0,
                  limits.fieldUTF16 > 0, limits.fieldLineFeeds >= 0,
                  limits.fieldUTF16 <= Int.max / 3 else {
                throw LemulipError.invalidInput("The table limits are invalid.")
            }
        }
        try Task.checkCancellation()
        let marker: UInt8 = delimiter == "," ? 44 : 9
        var bytes = Array(text.utf8)
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes.removeFirst(3) }
        try Task.checkCancellation()
        if bytes.isEmpty { return }
        enum State { case start, unquoted, quoted, afterQuote }
        var state = State.start
        var row: [String] = [], field: [UInt8] = []
        var rowCount = 0, cellCount = 0, lineFeeds = 0
        var index = 0, nextCancellationCheck = 0, endedRow = false
        func appendByte(_ byte: UInt8) throws {
            if let limits {
                // A valid scalar uses at most three UTF-8 bytes per UTF-16
                // code unit. This stops a huge field before decoding it.
                guard field.count < limits.fieldUTF16 * 3 else {
                    throw LemulipError.invalidInput("An Excel cell exceeds the \(limits.fieldUTF16)-character text limit.")
                }
                if byte == 10 {
                    guard lineFeeds < limits.fieldLineFeeds else {
                        throw LemulipError.invalidInput("An Excel cell exceeds the \(limits.fieldLineFeeds)-line-break limit.")
                    }
                    lineFeeds += 1
                }
            }
            field.append(byte)
        }
        func finishField() throws {
            if let limits {
                guard rowCount < limits.rows else { throw LemulipError.invalidInput("This table exceeds Lemulip's \(limits.rows)-row workbook limit.") }
                guard row.count < limits.columns else { throw LemulipError.invalidInput("A table row exceeds Excel's \(limits.columns)-column limit.") }
                guard cellCount < limits.cells else { throw LemulipError.invalidInput("This table exceeds Lemulip's \(limits.cells)-cell workbook limit.") }
            }
            let value = String(decoding: field, as: UTF8.self)
            if let limits, value.utf16.count > limits.fieldUTF16 {
                throw LemulipError.invalidInput("An Excel cell exceeds the \(limits.fieldUTF16)-character text limit.")
            }
            row.append(value); cellCount += 1
            field.removeAll(keepingCapacity: true); lineFeeds = 0; state = .start
        }
        func finishRow() throws {
            try Task.checkCancellation()
            try body(row)
            rowCount += 1
            row.removeAll(keepingCapacity: true)
        }
        while index < bytes.count {
            if index >= nextCancellationCheck {
                try Task.checkCancellation(); nextCancellationCheck = index + 16_384
            }
            let byte = bytes[index]
            endedRow = false
            if state == .quoted {
                if byte == 34 {
                    if index + 1 < bytes.count, bytes[index + 1] == 34 { try appendByte(34); index += 1 }
                    else { state = .afterQuote }
                } else { try appendByte(byte) }
            } else if byte == marker {
                try finishField()
            } else if byte == 10 || byte == 13 {
                try finishField(); try finishRow(); endedRow = true
                if byte == 13, index + 1 < bytes.count, bytes[index + 1] == 10 { index += 1 }
            } else if state == .afterQuote {
                throw LemulipError.invalidInput("A quoted table field has unexpected characters after its closing quote.")
            } else if byte == 34 {
                guard state == .start else { throw LemulipError.invalidInput("A table field contains an unescaped quote.") }
                state = .quoted
            } else {
                state = .unquoted; try appendByte(byte)
            }
            index += 1
        }
        guard state != .quoted else { throw LemulipError.invalidInput("A quoted table field is missing its closing quote.") }
        if !endedRow { try finishField(); try finishRow() }
    }

    static func wordCount(_ text: String) -> String {
        let expression = try! NSRegularExpression(pattern: "[\\p{L}\\p{N}]+(?:['’−-][\\p{L}\\p{N}]+)*")
        let count = expression.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.isEmpty ? 0 : normalized.split(separator: "\n", omittingEmptySubsequences: false).count - (normalized.hasSuffix("\n") ? 1 : 0)
        return "\(count) words · \(text.count) characters · \(lines) lines"
    }
}
