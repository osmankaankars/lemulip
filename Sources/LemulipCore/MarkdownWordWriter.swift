import Foundation

/// A bounded Markdown subset for dependency-free Word export. Syntax that this
/// writer cannot preserve is identified before any package is created, leaving
/// the engine free to select Pandoc for the entire batch.
enum MarkdownWordWriter {
    private static let nativeBytes = 4 * 1024 * 1024
    private static let maximumLines = 50_000
    private static let lineBytes = 16 * 1024
    private static let paragraphBytes = 64 * 1024
    private static let maximumBlocks = 10_000
    private static let maximumRuns = 100_000
    private static let maximumColumns = 32
    private static let maximumCells = 10_000
    private static let wordNamespace = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"

    static func preflight(_ inputs: [URL]) throws {
        guard !inputs.isEmpty, inputs.allSatisfy({ ["md", "markdown"].contains($0.pathExtension.lowercased()) }) else {
            throw LemulipError.unsupported("Choose Markdown files for built-in Word export.")
        }
        var unsupported: LemulipError?
        for input in inputs {
            try Task.checkCancellation()
            do { _ = try parsed(input) }
            catch LemulipError.unsupported(let message) {
                // Continue checking the batch: an earlier advanced document
                // must not conceal a later invalid encoding or oversized file.
                if unsupported == nil { unsupported = .unsupported(message) }
            }
        }
        if let unsupported { throw unsupported }
    }

    static func convert(inputs: [URL], directory: URL) async throws -> ConversionResult {
        do { try preflight(inputs) }
        catch LemulipError.unsupported { throw changedInputError() }
        var outputs: [URL] = []
        var finished = false
        defer { if !finished { for output in outputs { try? FileManager.default.removeItem(at: output) } } }
        for input in inputs {
            try Task.checkCancellation()
            let document: [Block]
            do { document = try parsed(input) }
            catch LemulipError.unsupported { throw changedInputError() }
            outputs.append(try await package(document, input: input, directory: directory))
        }
        try Task.checkCancellation()
        finished = true
        return ConversionResult(outputs: outputs,
            note: "Basic Markdown was exported as an editable Word document using Lemulip's built-in exporter. Advanced Markdown features use Pandoc.")
    }

    private static func changedInputError() -> LemulipError {
        .invalidInput("The Markdown input changed or exceeds built-in Word export support. Start a new conversion to select Pandoc for advanced Markdown.")
    }

    /// Pandoc reads UTF-8. The all-Markdown DOCX fallback uses these bytes in
    /// private preparation copies, retaining the same strict input validation.
    static func validatedUTF8(_ input: URL) throws -> Data {
        let source = try decoded(input)
        try Task.checkCancellation()
        return Data(source.text.utf8)
    }

    private static func parsed(_ input: URL) throws -> [Block] {
        let source = try decoded(input)
        guard source.encodedBytes <= nativeBytes, source.text.utf8.count <= nativeBytes else {
            throw unsupported("Markdown larger than 4 MiB")
        }
        let text = source.text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var parser = try Parser(text)
        return try parser.parse()
    }

    private static func decoded(_ input: URL) throws -> (encodedBytes: Int, text: String) {
        let data = try TextCodec.readData(input)
        let text: String?
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            guard data.count % 2 == 0 else { throw encodingError() }
            let littleEndian = data[0] == 0xFF
            func unit(_ index: Int) -> UInt16 {
                let first = UInt16(data[index]), second = UInt16(data[index + 1])
                return littleEndian ? first | second << 8 : first << 8 | second
            }
            var index = 2
            var nextCancellationCheck = 2
            while index < data.count {
                if index >= nextCancellationCheck {
                    try Task.checkCancellation(); nextCancellationCheck = index + 16_384
                }
                let value = unit(index)
                if (0xD800...0xDBFF).contains(value) {
                    guard index + 3 < data.count, (0xDC00...0xDFFF).contains(unit(index + 2)) else { throw encodingError() }
                    index += 4
                } else {
                    guard !(0xDC00...0xDFFF).contains(value) else { throw encodingError() }
                    index += 2
                }
            }
            text = String(data: data, encoding: .utf16)
        } else {
            text = String(data: data, encoding: .utf8)
        }
        guard var text else { throw encodingError() }
        if text.first == "\u{FEFF}" { text.removeFirst() }
        for (index, scalar) in text.unicodeScalars.enumerated() {
            if index & 4_095 == 0 { try Task.checkCancellation() }
            switch scalar.value {
            case 0x09, 0x0A, 0x0D, 0x20...0xD7FF, 0xE000...0xFFFD, 0x10000...0x10FFFF: break
            default: throw LemulipError.invalidInput("The Markdown file contains a control character that cannot be saved in a Word document.")
            }
        }
        return (data.count, text)
    }

    private static func encodingError() -> LemulipError {
        .invalidInput("Save this Markdown file as valid UTF-8 or UTF-16 with a byte-order mark and try again.")
    }

    private static func unsupported(_ feature: String) -> LemulipError {
        .unsupported("\(feature) requires Pandoc for Markdown-to-Word export.")
    }

    private struct Run {
        let text: String
        var bold = false
        var italic = false
        var code = false
    }

    private struct ListMarker {
        let delimiter: Character
        let start: Int?
        let content: String

        func matches(_ other: ListMarker) -> Bool {
            delimiter == other.delimiter && (start == nil) == (other.start == nil)
        }
    }

    private enum Block {
        case paragraph([Run], heading: Int?)
        case list(ListMarker, [[Run]])
        case code(String)
        case table([String], [[[Run]]])
    }

    private struct Parser {
        let lines: [Substring]
        var index = 0
        var blocks = 0
        var runs = 0
        var cells = 0

        init(_ text: String) throws {
            lines = text.split(separator: "\n", maxSplits: maximumLines, omittingEmptySubsequences: false)
            guard lines.count <= maximumLines else { throw unsupported("More than 50,000 Markdown lines") }
            for (index, line) in lines.enumerated() {
                if index & 255 == 0 { try Task.checkCancellation() }
                guard line.utf8.count <= lineBytes else { throw unsupported("Markdown lines longer than 16 KiB") }
            }
        }

        mutating func parse() throws -> [Block] {
            var result: [Block] = []
            while index < lines.count {
                try Task.checkCancellation()
                let line = String(lines[index])
                if blank(line) { index += 1; continue }
                try validateBlockLine(line)
                if let fence = fence(line) {
                    try countBlock()
                    result.append(.code(try code(fence)))
                } else if let heading = heading(line) {
                    try countBlock()
                    result.append(.paragraph(try inline(heading.text), heading: heading.level))
                    index += 1
                } else if let marker = try marker(line) {
                    result.append(try list(marker))
                } else if isTableStart(at: index) {
                    result.append(try table())
                } else {
                    try countBlock()
                    result.append(.paragraph(try paragraph(), heading: nil))
                }
            }
            return result
        }

        private func blank(_ line: String) -> Bool { line.allSatisfy { $0 == " " || $0 == "\t" } }
        private func trimmed(_ line: String) -> String { line.trimmingCharacters(in: CharacterSet(charactersIn: " \t")) }

        private func validateBlockLine(_ line: String) throws {
            guard line.first != " ", line.first != "\t" else { throw unsupported("Indented or nested Markdown blocks") }
            if advancedListMarker(line) { throw unsupported("Alphabetic, Roman, parenthesized, or example Markdown lists") }
            let compact = line.filter { $0 != " " && $0 != "\t" }
            let setext = compact.first.map { first in
                (first == "-" || first == "=") && compact.allSatisfy { $0 == first }
            } ?? false
            if line.hasPrefix(">") || line.hasPrefix(": ") || line.hasPrefix(":\t") || line.hasPrefix("%")
                || line.hasPrefix("+++") || line.hasPrefix(":::")
                || setext || compact.count >= 3 && (compact.first == "*" || compact.first == "_") && compact.allSatisfy({ $0 == compact.first }) {
                throw unsupported("Block quotes, front matter, rules, or extended Markdown blocks")
            }
            if line.hasSuffix("  ") || line.hasSuffix("\t") || line.hasSuffix("\\") {
                throw unsupported("Explicit Markdown line breaks")
            }
        }

        private func advancedListMarker(_ line: String) -> Bool {
            // Pandoc's fancy_lists and example_lists extend CommonMark list
            // prefixes. Decline them before paragraph joining can erase their
            // structure. The parser has already bounded each line to 16 KiB.
            let characters = Array(line)
            guard !characters.isEmpty else { return false }
            let parenthesized = characters[0] == "("
            var position = parenthesized ? 1 : 0
            let start = position
            while position < characters.count, characters[position].isASCII, characters[position].isNumber { position += 1 }
            let digits = position - start
            var candidate = false
            var capitalInitial = false
            if position < characters.count, characters[position] == "@" {
                candidate = true; position += 1
                while position < characters.count {
                    let value = characters[position]
                    guard value.isLetter || value.isNumber || value == "_" || value == "-" else { break }
                    position += 1
                }
            } else if digits > 0 {
                // One to nine unparenthesized decimal digits are native.
                candidate = parenthesized || digits > 9
            } else if position < characters.count, characters[position] == "#" {
                candidate = true; position += 1
            } else {
                while position < characters.count, characters[position].isASCII, characters[position].isLetter { position += 1 }
                let token = characters[start..<position]
                let roman = !token.isEmpty && (token.allSatisfy { "ivxlcdm".contains($0) } || token.allSatisfy { "IVXLCDM".contains($0) })
                candidate = token.count == 1 || roman
                capitalInitial = token.count == 1 && token.first?.isUppercase == true
            }
            guard candidate, position < characters.count else { return false }
            let delimiter = characters[position]
            if parenthesized {
                guard delimiter == ")" else { return false }
            } else {
                guard delimiter == "." || delimiter == ")" else { return false }
            }
            position += 1
            if position == characters.count { return true }
            guard characters[position] == " " || characters[position] == "\t" else { return false }
            if capitalInitial, !parenthesized, delimiter == "." {
                // A single capital letter with a period needs two spaces in
                // Pandoc. Keep ordinary initials such as "J. Smith" native.
                return characters[position] == "\t" || position + 1 < characters.count
                    && (characters[position + 1] == " " || characters[position + 1] == "\t")
            }
            return true
        }

        private func heading(_ line: String) -> (level: Int, text: String)? {
            let count = line.prefix { $0 == "#" }.count
            guard (1...6).contains(count) else { return nil }
            let rest = line.dropFirst(count)
            guard rest.isEmpty || rest.first == " " || rest.first == "\t" else { return nil }
            var content = trimmed(String(rest))
            let closing = content.reversed().prefix { $0 == "#" }.count
            if closing > 0 {
                let before = content.dropLast(closing)
                if before.isEmpty || before.last == " " || before.last == "\t" { content = trimmed(String(before)) }
            }
            return (count, content)
        }

        private func fence(_ line: String) -> (marker: Character, length: Int, info: String)? {
            guard let first = line.first, first == "`" || first == "~" else { return nil }
            let count = line.prefix { $0 == first }.count
            guard count >= 3 else { return nil }
            return (first, count, trimmed(String(line.dropFirst(count))))
        }

        private mutating func code(_ opening: (marker: Character, length: Int, info: String)) throws -> String {
            guard opening.length <= 32, opening.info.utf8.allSatisfy({
                (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || [35, 43, 45, 46, 95].contains($0)
            }) else { throw unsupported("Extended fenced-code attributes") }
            index += 1
            var content: [Substring] = []
            while index < lines.count {
                try Task.checkCancellation()
                let line = String(lines[index])
                if let closing = fence(line), closing.marker == opening.marker,
                   closing.length >= opening.length, closing.info.isEmpty {
                    index += 1
                    return content.joined(separator: "\n")
                }
                content.append(lines[index]); index += 1
            }
            throw unsupported("An unclosed Markdown code fence")
        }

        private func marker(_ line: String) throws -> ListMarker? {
            let bytes = Array(line.utf8)
            guard let first = bytes.first else { return nil }
            var end = 0
            var start: Int?
            let delimiter: Character
            if [42, 43, 45].contains(first) {
                delimiter = Character(UnicodeScalar(first)); end = 1
            } else if (48...57).contains(first) {
                while end < bytes.count, (48...57).contains(bytes[end]) { end += 1 }
                guard end <= 9, end < bytes.count, bytes[end] == 46 || bytes[end] == 41 else { return nil }
                start = Int(String(decoding: bytes[..<end], as: UTF8.self))
                delimiter = Character(UnicodeScalar(bytes[end])); end += 1
            } else { return nil }
            guard end == bytes.count || bytes[end] == 32 || bytes[end] == 9 else { return nil }
            let whitespaceStart = end
            while end < bytes.count, bytes[end] == 32 { end += 1 }
            guard (1...4).contains(end - whitespaceStart), end < bytes.count, bytes[end] != 9 else {
                throw unsupported("Empty, indented, or tab-separated Markdown list items")
            }
            return ListMarker(delimiter: delimiter, start: start,
                              content: trimmed(String(decoding: bytes[end...], as: UTF8.self)))
        }

        private mutating func list(_ first: ListMarker) throws -> Block {
            var items: [[Run]] = []
            while index < lines.count {
                try Task.checkCancellation()
                let line = String(lines[index])
                guard !blank(line), let current = try marker(line), first.matches(current) else { break }
                try validateBlockLine(line)
                try validateBlockLine(current.content)
                guard heading(current.content) == nil, fence(current.content) == nil,
                      try marker(current.content) == nil else { throw unsupported("Nested or structured Markdown list items") }
                try countBlock()
                items.append(try inline(current.content)); index += 1
                if index < lines.count, blank(String(lines[index])) {
                    var next = index
                    while next < lines.count, blank(String(lines[next])) { next += 1 }
                    if next < lines.count, let marker = try marker(String(lines[next])), first.matches(marker) {
                        throw unsupported("Loose or multiline Markdown lists")
                    }
                    break
                }
                if index < lines.count {
                    let next = String(lines[index])
                    if try marker(next) == nil, heading(next) == nil, fence(next) == nil {
                        throw unsupported("Multiline Markdown list items")
                    }
                }
            }
            return .list(first, items)
        }

        private func isTableStart(at position: Int) -> Bool {
            guard position + 1 < lines.count, lines[position].contains("|"), lines[position + 1].contains("|") else { return false }
            let delimiter = trimmed(String(lines[position + 1]))
            return delimiter.contains("-") && delimiter.allSatisfy { "|-: \t".contains($0) }
        }

        private func tableCells(_ line: String) throws -> [String] {
            guard !line.contains("\\"), line.first != " ", line.first != "\t" else {
                throw unsupported("Escaped or indented Markdown tables")
            }
            let line = trimmed(line)
            var values = line.split(separator: "|", omittingEmptySubsequences: false)
            if line.hasPrefix("|") { values.removeFirst() }
            if line.hasSuffix("|"), !values.isEmpty { values.removeLast() }
            guard !values.isEmpty, values.count <= maximumColumns else { throw unsupported("Markdown tables with more than 32 columns") }
            return values.map { trimmed(String($0)) }
        }

        private mutating func table() throws -> Block {
            let header = try tableCells(String(lines[index]))
            let separators = try tableCells(String(lines[index + 1]))
            guard header.count == separators.count else { throw unsupported("Uneven Markdown table headers") }
            let alignment = try separators.map { cell -> String in
                var value = cell
                if value.first == ":" { value.removeFirst() }
                if value.last == ":" { value.removeLast() }
                guard value.count >= 3, value.allSatisfy({ $0 == "-" }) else { throw unsupported("Extended Markdown table separators") }
                if cell.first == ":", cell.last == ":" { return "center" }
                return cell.last == ":" ? "right" : "left"
            }
            try countBlock()
            var rows: [[[Run]]] = []
            try addTableRow(header, to: &rows)
            index += 2
            while index < lines.count, !blank(String(lines[index])), lines[index].contains("|") {
                try Task.checkCancellation()
                let line = String(lines[index])
                try validateBlockLine(line)
                guard heading(line) == nil, fence(line) == nil, try marker(line) == nil else {
                    throw unsupported("Ambiguous Markdown table boundaries")
                }
                let values = try tableCells(line)
                guard values.count == header.count else { throw unsupported("Uneven or multiline Markdown table rows") }
                try addTableRow(values, to: &rows)
                index += 1
            }
            if index < lines.count, !blank(String(lines[index])) {
                let line = String(lines[index])
                let listMarker = try marker(line)
                guard heading(line) != nil || fence(line) != nil || listMarker != nil else {
                    throw unsupported("A Markdown table continuation without cell separators")
                }
            }
            return .table(alignment, rows)
        }

        private mutating func addTableRow(_ values: [String], to rows: inout [[[Run]]]) throws {
            guard cells <= maximumCells - values.count else { throw unsupported("Markdown tables with more than 10,000 cells") }
            cells += values.count
            var row: [[Run]] = []
            for value in values { row.append(try inline(value)) }
            rows.append(row)
        }

        private mutating func paragraph() throws -> [Run] {
            var text = ""
            var bytes = 0
            while index < lines.count {
                try Task.checkCancellation()
                let line = String(lines[index])
                if blank(line) { break }
                try validateBlockLine(line)
                if !text.isEmpty {
                    if let marker = try marker(line) {
                        guard marker.start == nil || marker.start == 1 else { throw unsupported("Ambiguous ordered-list continuation") }
                        break
                    }
                    if heading(line) != nil || fence(line) != nil { break }
                    if isTableStart(at: index) { throw unsupported("A table joined to a preceding paragraph") }
                }
                try requireClosedInlineCode(on: line)
                let part = trimmed(line)
                bytes += part.utf8.count + (text.isEmpty ? 0 : 1)
                guard bytes <= paragraphBytes else { throw unsupported("Markdown paragraphs longer than 64 KiB") }
                if !text.isEmpty { text.append(" ") }
                text.append(part); index += 1
            }
            return try inline(text)
        }

        private func requireClosedInlineCode(on line: String) throws {
            let bytes = Array(line.utf8)
            var position = 0
            var open = false
            while position < bytes.count {
                if bytes[position] == 92, !open { position += 2; continue }
                if bytes[position] == 96 { open.toggle() }
                position += 1
            }
            guard !open else { throw unsupported("Inline code spanning multiple Markdown lines") }
        }

        private mutating func countBlock() throws {
            guard blocks < maximumBlocks else { throw unsupported("More than 10,000 Markdown blocks or list items") }
            blocks += 1
        }

        private mutating func inline(_ text: String) throws -> [Run] {
            let characters = Array(text)
            var result: [Run] = []
            var literal = ""
            var position = 0
            func punctuation(_ value: Character) -> Bool {
                value.unicodeScalars.allSatisfy { CharacterSet.punctuationCharacters.contains($0) || CharacterSet.symbols.contains($0) }
            }
            func boundary(_ value: Character?) -> Bool { value == nil || value!.isWhitespace || punctuation(value!) }
            func escapable(_ value: Character) -> Bool { "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~".contains(value) }
            func entity(at start: Int, end: Int) -> Bool {
                guard start + 1 < end else { return false }
                var position = start + 1
                let numeric = characters[position] == "#"
                var hexadecimal = false
                if numeric {
                    position += 1
                    if position < end, characters[position] == "x" || characters[position] == "X" {
                        hexadecimal = true; position += 1
                    }
                } else if !characters[position].isASCII || !characters[position].isLetter { return false }
                let first = position
                while position < end, position - start <= 64 {
                    let value = characters[position]
                    let accepted: Bool
                    if numeric { accepted = value.isASCII && (value.isNumber || hexadecimal && "abcdefABCDEF".contains(value)) }
                    else { accepted = value.isASCII && (value.isLetter || value.isNumber) }
                    if !accepted { break }
                    position += 1
                }
                return position > first && position < end && characters[position] == ";"
            }
            func plain(_ content: ArraySlice<Character>) throws -> String {
                var value = ""
                var index = content.startIndex
                while index < content.endIndex {
                    let character = content[index]
                    if character == "\\" {
                        guard index + 1 < content.endIndex, escapable(content[index + 1]) else { throw unsupported("LaTeX or extended Markdown escapes") }
                        value.append(content[index + 1]); index += 2
                    } else {
                        if "*_`[]{}$~^".contains(character) { throw unsupported("Nested or extended inline Markdown") }
                        if character == "<", index + 1 < content.endIndex, !content[index + 1].isWhitespace {
                            throw unsupported("HTML or links in Markdown")
                        }
                        if character == "&", entity(at: index, end: content.endIndex) {
                            throw unsupported("Markdown entities")
                        }
                        value.append(character); index += 1
                    }
                }
                return value
            }
            func append(_ run: Run) throws {
                guard !run.text.isEmpty else { return }
                guard runs < maximumRuns else { throw unsupported("More than 100,000 Markdown text runs") }
                runs += 1; result.append(run)
            }
            func flush() throws {
                if !literal.isEmpty { try append(Run(text: literal)); literal.removeAll(keepingCapacity: true) }
            }
            while position < characters.count {
                if position & 1_023 == 0 { try Task.checkCancellation() }
                let character = characters[position]
                if character == "\\" {
                    guard position + 1 < characters.count, escapable(characters[position + 1]) else { throw unsupported("LaTeX or extended Markdown escapes") }
                    literal.append(characters[position + 1]); position += 2; continue
                }
                if character == "`" {
                    guard position + 1 < characters.count, characters[position + 1] != "`",
                          let end = characters[(position + 1)...].firstIndex(of: "`"),
                          end + 1 == characters.count || characters[end + 1] != "`" else {
                        throw unsupported("Complex or unclosed inline code")
                    }
                    var content = String(characters[(position + 1)..<end])
                    if content.first == " ", content.last == " ", !content.allSatisfy({ $0 == " " }) {
                        content.removeFirst(); content.removeLast()
                    }
                    try flush(); try append(Run(text: content, code: true)); position = end + 1; continue
                }
                if character == "*" || character == "_" {
                    let previous = position > 0 ? characters[position - 1] : nil
                    let next = position + 1 < characters.count ? characters[position + 1] : nil
                    if character == "_", let previous, let next, !boundary(previous), !boundary(next) {
                        literal.append(character); position += 1; continue
                    }
                    let count = next == character ? 2 : 1
                    let start = position + count
                    guard start < characters.count, characters[start] != character,
                          !characters[start].isWhitespace, boundary(previous) else { throw unsupported("Complex Markdown emphasis") }
                    var end = start
                    while end < characters.count {
                        if characters[end] == "\\" { end += 2; continue }
                        if characters[end] == character { break }
                        end += 1
                    }
                    guard end < characters.count, end > start, !characters[end - 1].isWhitespace,
                          end + count <= characters.count,
                          (0..<count).allSatisfy({ characters[end + $0] == character }),
                          end + count == characters.count || characters[end + count] != character,
                          boundary(end + count < characters.count ? characters[end + count] : nil) else {
                        throw unsupported("Complex or unclosed Markdown emphasis")
                    }
                    let content = try plain(characters[start..<end])
                    try flush(); try append(Run(text: content, bold: count == 2, italic: count == 1))
                    position = end + count; continue
                }
                if "[]{}$~^".contains(character) { throw unsupported("Links, images, notes, math, or extended inline Markdown") }
                if character == "<", position + 1 < characters.count, !characters[position + 1].isWhitespace {
                    throw unsupported("HTML or links in Markdown")
                }
                if character == "&", entity(at: position, end: characters.count) { throw unsupported("Markdown entities") }
                if character == "|" { throw unsupported("Ambiguous Markdown table syntax") }
                if character == "=", position + 1 < characters.count, characters[position + 1] == "=" {
                    throw unsupported("Extended Markdown emphasis")
                }
                literal.append(character); position += 1
            }
            try flush()
            return result
        }
    }

    private static func package(_ document: [Block], input: URL, directory: URL) async throws -> URL {
        let package = directory.appendingPathComponent(".markdown-word-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: package) }
        for child in ["_rels", "word/_rels", "docProps"] {
            try FileManager.default.createDirectory(at: package.appendingPathComponent(child, isDirectory: true),
                withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        for (name, contents) in fixedParts + [("word/styles.xml", styles)] {
            try Task.checkCancellation()
            try Data(contents.utf8).write(to: package.appendingPathComponent(name), options: .withoutOverwriting)
        }
        let body = try XMLWriter(url: package.appendingPathComponent("word/document.xml"))
        try body.append("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<w:document xmlns:w=\"\(wordNamespace)\"><w:body>")
        var listID = 0
        for block in document {
            try Task.checkCancellation()
            switch block {
            case .paragraph(let runs, let level):
                try paragraph(runs, style: level.map { "Heading\($0)" } ?? "Normal", writer: body)
            case .list(_, let items):
                listID += 1
                for runs in items { try paragraph(runs, style: "ListParagraph", listID: listID, writer: body) }
            case .code(let code):
                try paragraph([Run(text: code)], style: "CodeBlock", writer: body)
            case .table(let alignments, let rows):
                try table(rows, alignments: alignments, writer: body)
            }
        }
        if document.isEmpty { try body.append("<w:p/>") }
        if let last = document.last, case .table = last { try body.append("<w:p/>") }
        try body.append("<w:sectPr><w:pgSz w:w=\"12240\" w:h=\"15840\"/><w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\" w:header=\"720\" w:footer=\"720\" w:gutter=\"0\"/></w:sectPr></w:body></w:document>")
        try body.finish()
        try numbering(document, url: package.appendingPathComponent("word/numbering.xml"))
        try Task.checkCancellation()
        let archive = try await ExternalConverters.archives(
            ["[Content_Types].xml", "_rels", "word", "docProps"].map { package.appendingPathComponent($0) },
            operation: FileOperation(id: "archive.createZip", title: "Create ZIP"), directory: package)
        guard archive.outputs.count == 1, let zipped = archive.outputs.first else {
            throw LemulipError.operationFailed("The Word document package could not be created.")
        }
        try Task.checkCancellation()
        let output = OutputStore.uniqueURL(in: directory, stem: input.deletingPathExtension().lastPathComponent, extension: "docx")
        try FileManager.default.moveItem(at: zipped, to: output)
        return output
    }

    private static func paragraph(_ runs: [Run], style: String = "Normal", listID: Int? = nil,
                                  alignment: String? = nil, header: Bool = false, writer: XMLWriter) throws {
        try writer.append("<w:p><w:pPr><w:pStyle w:val=\"\(style)\"/>")
        if let listID { try writer.append("<w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"\(listID)\"/></w:numPr>") }
        if let alignment { try writer.append("<w:jc w:val=\"\(alignment)\"/>") }
        try writer.append("</w:pPr>")
        for run in runs {
            try Task.checkCancellation()
            try writer.append("<w:r>")
            if run.bold || run.italic || run.code || header {
                try writer.append("<w:rPr>")
                if run.code { try writer.append("<w:rFonts w:ascii=\"Courier New\" w:hAnsi=\"Courier New\"/>") }
                if run.bold || header { try writer.append("<w:b/>") }
                if run.italic { try writer.append("<w:i/>") }
                if run.code { try writer.append("<w:sz w:val=\"20\"/><w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"F4F5F7\"/>") }
                try writer.append("</w:rPr>")
            }
            try writer.text(run.text)
            try writer.append("</w:r>")
        }
        try writer.append("</w:p>")
    }

    private static func table(_ rows: [[[Run]]], alignments: [String], writer: XMLWriter) throws {
        let width = 9_360 / alignments.count
        try writer.append("<w:tbl><w:tblPr><w:tblW w:w=\"9360\" w:type=\"dxa\"/><w:tblBorders>")
        for side in ["top", "left", "bottom", "right", "insideH", "insideV"] {
            try writer.append("<w:\(side) w:val=\"single\" w:sz=\"4\" w:color=\"D5D8DD\"/>")
        }
        try writer.append("</w:tblBorders><w:tblLayout w:type=\"fixed\"/><w:tblCellMar><w:top w:w=\"80\" w:type=\"dxa\"/><w:left w:w=\"100\" w:type=\"dxa\"/><w:bottom w:w=\"80\" w:type=\"dxa\"/><w:right w:w=\"100\" w:type=\"dxa\"/></w:tblCellMar></w:tblPr><w:tblGrid>")
        for _ in alignments { try writer.append("<w:gridCol w:w=\"\(width)\"/>") }
        try writer.append("</w:tblGrid>")
        for (rowIndex, row) in rows.enumerated() {
            try Task.checkCancellation()
            try writer.append("<w:tr>")
            if rowIndex == 0 { try writer.append("<w:trPr><w:tblHeader/></w:trPr>") }
            for (column, runs) in row.enumerated() {
                try writer.append("<w:tc><w:tcPr><w:tcW w:w=\"\(width)\" w:type=\"dxa\"/>")
                if rowIndex == 0 { try writer.append("<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"F4F5F7\"/>") }
                try writer.append("</w:tcPr>")
                try paragraph(runs, alignment: alignments[column], header: rowIndex == 0, writer: writer)
                try writer.append("</w:tc>")
            }
            try writer.append("</w:tr>")
        }
        try writer.append("</w:tbl>")
    }

    private static func numbering(_ document: [Block], url: URL) throws {
        let writer = try XMLWriter(url: url)
        try writer.append("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<w:numbering xmlns:w=\"\(wordNamespace)\">")
        var count = 0
        for block in document {
            guard case .list(let marker, _) = block else { continue }
            try Task.checkCancellation()
            let format = marker.start == nil ? "bullet" : "decimal"
            let text = marker.start == nil ? "•" : "%1\(marker.delimiter)"
            try writer.append("<w:abstractNum w:abstractNumId=\"\(count)\"><w:multiLevelType w:val=\"singleLevel\"/><w:lvl w:ilvl=\"0\"><w:start w:val=\"\(marker.start ?? 1)\"/><w:numFmt w:val=\"\(format)\"/><w:lvlText w:val=\"\(text)\"/><w:lvlJc w:val=\"left\"/><w:pPr><w:tabs><w:tab w:val=\"num\" w:pos=\"720\"/></w:tabs><w:ind w:left=\"720\" w:hanging=\"360\"/></w:pPr></w:lvl></w:abstractNum>")
            count += 1
        }
        for id in 0..<count { try writer.append("<w:num w:numId=\"\(id + 1)\"><w:abstractNumId w:val=\"\(id)\"/></w:num>") }
        try writer.append("</w:numbering>")
        try writer.finish()
    }

    private static let fixedParts: [(String, String)] = [
        ("[Content_Types].xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/><Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/></Types>
        """),
        ("_rels/.rels", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/></Relationships>
        """),
        ("word/_rels/document.xml.rels", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/></Relationships>
        """),
        ("docProps/core.xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:creator>Lemulip</dc:creator><cp:lastModifiedBy>Lemulip</cp:lastModifiedBy></cp:coreProperties>
        """),
    ]

    private static var styles: String {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<w:styles xmlns:w=\"\(wordNamespace)\"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii=\"Arial\" w:hAnsi=\"Arial\"/><w:sz w:val=\"22\"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after=\"160\" w:line=\"276\" w:lineRule=\"auto\"/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"Normal\"><w:name w:val=\"Normal\"/><w:qFormat/></w:style>"
        for (index, size) in [32, 28, 26, 24, 22, 22].enumerated() {
            xml += "<w:style w:type=\"paragraph\" w:styleId=\"Heading\(index + 1)\"><w:name w:val=\"heading \(index + 1)\"/><w:basedOn w:val=\"Normal\"/><w:next w:val=\"Normal\"/><w:qFormat/><w:pPr><w:keepNext/><w:keepLines/><w:spacing w:before=\"240\" w:after=\"120\"/><w:outlineLvl w:val=\"\(index)\"/></w:pPr><w:rPr><w:b/><w:sz w:val=\"\(size)\"/></w:rPr></w:style>"
        }
        xml += "<w:style w:type=\"paragraph\" w:styleId=\"ListParagraph\"><w:name w:val=\"List Paragraph\"/><w:basedOn w:val=\"Normal\"/><w:pPr><w:spacing w:after=\"80\"/></w:pPr></w:style><w:style w:type=\"paragraph\" w:styleId=\"CodeBlock\"><w:name w:val=\"Code Block\"/><w:basedOn w:val=\"Normal\"/><w:pPr><w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"F4F5F7\"/><w:tabs>"
        for position in stride(from: 480, through: 9_120, by: 480) { xml += "<w:tab w:val=\"left\" w:pos=\"\(position)\"/>" }
        xml += "</w:tabs><w:spacing w:before=\"120\" w:after=\"160\" w:line=\"240\" w:lineRule=\"auto\"/></w:pPr><w:rPr><w:rFonts w:ascii=\"Courier New\" w:hAnsi=\"Courier New\"/><w:sz w:val=\"20\"/></w:rPr></w:style></w:styles>"
        return xml
    }

    private final class XMLWriter {
        private let handle: FileHandle
        private var buffer = Data()
        private var closed = false
        private let capacity = 65_536

        init(url: URL) throws {
            try Data().write(to: url, options: .withoutOverwriting)
            handle = try FileHandle(forWritingTo: url)
            buffer.reserveCapacity(capacity)
        }

        deinit { if !closed { try? handle.close() } }

        func append(_ value: String) throws {
            let data = Data(value.utf8)
            var offset = 0
            while offset < data.count {
                let count = min(capacity - buffer.count, data.count - offset)
                buffer.append(data.subdata(in: offset..<(offset + count)))
                offset += count
                if buffer.count == capacity { try flush() }
            }
        }

        func text(_ value: String) throws {
            var text = ""
            var bytes = 0
            func emit() throws {
                if !text.isEmpty {
                    try append("<w:t xml:space=\"preserve\">\(text)</w:t>")
                    text.removeAll(keepingCapacity: true); bytes = 0
                }
            }
            for scalar in value.unicodeScalars {
                if scalar == "\t" || scalar == "\n" {
                    try emit(); try append(scalar == "\t" ? "<w:tab/>" : "<w:br/>")
                } else {
                    switch scalar {
                    case "&": text += "&amp;"; bytes += 5
                    case "<": text += "&lt;"; bytes += 4
                    case ">": text += "&gt;"; bytes += 4
                    default: text.unicodeScalars.append(scalar); bytes += scalar.utf8.count
                    }
                    if bytes >= 8_192 { try Task.checkCancellation(); try emit() }
                }
            }
            try emit()
        }

        func finish() throws {
            try flush(); try handle.close(); closed = true
        }

        private func flush() throws {
            try Task.checkCancellation()
            guard !buffer.isEmpty else { return }
            try handle.write(contentsOf: buffer); buffer.removeAll(keepingCapacity: true)
        }
    }
}
