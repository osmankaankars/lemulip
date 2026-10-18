#if os(macOS)
import AppKit
import Foundation

/// A small attributed-text route to AppKit's Word writer. RTF is checked before
/// import because an RTF reader may ignore destinations it cannot represent.
enum NativeWordExporter {
    private static let richContentMessage = "This RTF uses content beyond basic text formatting. LibreOffice is required to preserve objects, tables, lists, fields, links, headers, or other rich document features."

    static func preflight(_ inputs: [URL]) throws {
        // Select one route for the entire batch before producing any output.
        guard inputs.allSatisfy({ ["txt", "rtf"].contains($0.pathExtension.lowercased()) }) else {
            throw FreewheelError.unsupported("Built-in Word export accepts TXT and basic RTF files. Other rich documents need their optional document engine.")
        }
        for input in inputs where input.pathExtension.lowercased() == "rtf" {
            try Task.checkCancellation()
            try autoreleasepool { _ = try readRTF(input) }
        }
    }

    static func wordData(_ input: URL) throws -> Data {
        try Task.checkCancellation()
        let attributed = try input.pathExtension.lowercased() == "rtf" ? readRTF(input) : readText(input)
        try checkWordCharacters(attributed.string, format: input.pathExtension.uppercased())
        // Do not copy the RTF document-attributes dictionary. It may contain a
        // person's name, organization, title, or a source-system location.
        let word = try attributed.data(from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML,
                                 .author: "Lemulip", .editor: "Lemulip", .company: "", .manager: ""])
        try Task.checkCancellation()
        guard !word.isEmpty else { throw FreewheelError.operationFailed("macOS did not produce a Word document.") }
        return word
    }

    static func note(for inputs: [URL]) -> String {
        if inputs.contains(where: { $0.pathExtension.lowercased() == "rtf" }) {
            return "Exported text and basic RTF formatting as editable Word documents using macOS. Installed fonts, bold and italic text, text colors, and basic paragraph formatting are preserved. Page layout and margins are not reconstructed; unavailable fonts may be substituted. Author and editor metadata use Lemulip."
        }
        return "Exported plain text as editable Word documents using macOS. Text, paragraph breaks, and tabs are preserved; line endings are normalized. Rich layout is not reconstructed. Author and editor metadata use Lemulip."
    }

    private static func readText(_ input: URL) throws -> NSAttributedString {
        let data = try boundedData(input)
        let decoded: String?
        if data.starts(with: [0xFF, 0xFE]) {
            decoded = data.count.isMultiple(of: 2) ? String(data: data.dropFirst(2), encoding: .utf16LittleEndian) : nil
        } else if data.starts(with: [0xFE, 0xFF]) {
            decoded = data.count.isMultiple(of: 2) ? String(data: data.dropFirst(2), encoding: .utf16BigEndian) : nil
        } else {
            decoded = String(data: data.starts(with: [0xEF, 0xBB, 0xBF]) ? data.dropFirst(3) : data, encoding: .utf8)
        }
        guard let decoded else {
            throw FreewheelError.invalidInput("Save this TXT file as UTF-8 or BOM-marked UTF-16 before creating a Word document.")
        }
        let text = decoded.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        guard !text.isEmpty else {
            throw FreewheelError.invalidInput("This TXT file contains only an encoding marker. Add text before creating a Word document.")
        }
        return NSAttributedString(string: text)
    }

    private static func boundedData(_ input: URL) throws -> Data {
        let data = try TextCodec.readData(input)
        guard !data.isEmpty else {
            throw FreewheelError.invalidInput("Text documents must be between 1 byte and 32 MB.")
        }
        return data
    }

    private static func checkWordCharacters(_ text: String, format: String) throws {
        for (index, scalar) in text.unicodeScalars.enumerated() {
            if index.isMultiple(of: 16_384) { try Task.checkCancellation() }
            let value = scalar.value
            guard value == 9 || value == 10 || value == 13 ||
                    (0x20...0xD7FF).contains(value) || (0xE000...0xFFFD).contains(value) ||
                    (0x10000...0x10FFFF).contains(value) else {
                throw FreewheelError.invalidInput("This \(format) file contains a character that built-in Word export cannot preserve. Remove unsupported control characters or Unicode noncharacters and try again.")
            }
        }
    }

    private static func readRTF(_ input: URL) throws -> NSAttributedString {
        let data = try boundedData(input)
        try RTFPreflight.check(data)
        try Task.checkCancellation()
        let attributed: NSAttributedString
        do {
            attributed = try NSAttributedString(data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        } catch {
            throw FreewheelError.invalidInput("The RTF document could not be read. Open it in a text editor and save a valid RTF copy before converting it.")
        }
        try Task.checkCancellation()
        guard attributed.length > 0 else {
            throw FreewheelError.invalidInput("This RTF document contains no text to export as a Word document.")
        }
        try checkWordCharacters(attributed.string, format: "RTF")
        var range = NSRange(location: 0, length: 0)
        var position = 0
        while position < attributed.length {
            try Task.checkCancellation()
            let attributes = attributed.attributes(at: position, effectiveRange: &range)
            for (key, value) in attributes {
                switch key {
                case .font, .foregroundColor, .backgroundColor, .underlineColor, .strikethroughColor, .strokeColor, .writingDirection:
                    break
                case .paragraphStyle:
                    guard let style = value as? NSParagraphStyle,
                          style.textBlocks.isEmpty, style.textLists.isEmpty else {
                        throw FreewheelError.unsupported(richContentMessage + " (Unsupported imported paragraph structure.)")
                    }
                case .underlineStyle, .strikethroughStyle:
                    guard let style = value as? NSNumber, [0, NSUnderlineStyle.single.rawValue].contains(style.intValue) else {
                        throw FreewheelError.unsupported(richContentMessage + " (Unsupported imported underline or strikethrough style.)")
                    }
                case .kern, .expansion, .obliqueness, .strokeWidth, .baselineOffset, .superscript:
                    guard (value as? NSNumber)?.doubleValue == 0 else {
                        throw FreewheelError.unsupported(richContentMessage + " (Unsupported imported typography effect.)")
                    }
                case .ligature:
                    guard (value as? NSNumber)?.intValue == 1 else {
                        throw FreewheelError.unsupported(richContentMessage + " (Unsupported imported ligature setting.)")
                    }
                default:
                    // Includes attachments and links, even if a future RTF
                    // importer exposes them through a newly supported control.
                    throw FreewheelError.unsupported(richContentMessage + " (Unsupported imported text attribute.)")
                }
            }
            position = NSMaxRange(range)
        }
        return attributed
    }

    private enum RTFPreflight {
        private enum Destination { case body, fonts, colors, expandedColors, metadata }
        private struct Group {
            var destination: Destination
            var opening = true
            var starred = false
        }

        // Unknown controls take the document-engine route instead of asking
        // AppKit to silently ignore them. This is a scope check, not an RTF reader.
        private static let textControls: Set<String> = [
            "ansi", "ansicpg", "mac", "pc", "pca", "deff", "deflang", "deflangfe", "uc", "u",
            "f", "fs", "fsmilli", "plain", "b", "i", "cf", "cb", "highlight", "ul", "ulnone", "ulc", "strike", "strikec",
            "pard", "par", "line", "tab", "ql", "qr", "qc", "qj", "qnatural", "pardirnatural", "ltrpar", "rtlpar", "ltrch", "rtlch",
            "fi", "li", "ri", "sb", "sa", "sl", "slmult", "slleading", "slminimum", "slmaximum", "pardeftab", "deftab",
            "tx", "tql", "tqr", "tqc", "tqdec", "lang", "langfe", "langnp", "langfenp",
            "cocoartf", "cocoatextscaling", "cocoaplatform", "vieww", "viewh", "viewkind", "viewscale",
            "paperw", "paperh", "margl", "margr", "margt", "margb", "widowctrl", "strokec"
        ]
        private static let fontControls: Set<String> = [
            "f", "fnil", "froman", "fswiss", "fmodern", "fscript", "fdecor", "ftech", "fbidi", "fcharset", "fprq", "cpg"
        ]
        private static let metadataControls: Set<String> = [
            "author", "operator", "title", "subject", "keywords", "comment", "doccomm", "company", "manager", "category",
            "creatim", "revtim", "printim", "buptim", "yr", "mo", "dy", "hr", "min", "sec",
            "version", "vern", "edmins", "nofpages", "nofwords", "nofchars", "nofcharsws", "id", "u", "uc"
        ]
        private static let zeroOnlyControls: Set<String> = [
            "expnd", "expndtw", "kerning", "expansion", "obliqueness", "outl", "strokewidth", "shad", "partightenfactor", "hyphauto"
        ]

        static func check(_ data: Data) throws {
            guard data.starts(with: Array("{\\rtf1".utf8)) else { throw malformed() }
            try data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                var groups: [Group] = []
                var index = 0, nextCancellationCheck = 0, controls = 0
                var headerSeen = false, rootClosed = false
                while index < bytes.count {
                    if index >= nextCancellationCheck {
                        try Task.checkCancellation()
                        nextCancellationCheck = index + 16_384
                    }
                    let byte = bytes[index]
                    if rootClosed {
                        guard [UInt8(9), 10, 13, 32].contains(byte) else { throw malformed() }
                        index += 1
                        continue
                    }
                    if byte == 123 { // {
                        guard groups.count < 128 else {
                            throw FreewheelError.invalidInput("This RTF document is nested too deeply for built-in Word export.")
                        }
                        let destination = groups.last?.destination ?? .body
                        if !groups.isEmpty { groups[groups.count - 1].opening = false }
                        groups.append(Group(destination: destination))
                        index += 1
                        continue
                    }
                    guard !groups.isEmpty else { throw malformed() }
                    if byte == 125 { // }
                        guard !groups[groups.count - 1].starred else { throw malformed() }
                        groups.removeLast()
                        rootClosed = groups.isEmpty
                        index += 1
                        continue
                    }
                    guard byte != 0 else { throw malformed() }
                    if byte != 92 { // Ordinary text; raw CR/LF are ignored by RTF.
                        if byte != 10 && byte != 13 { groups[groups.count - 1].opening = false }
                        guard !groups[groups.count - 1].starred || byte == 10 || byte == 13 else { throw malformed() }
                        index += 1
                        continue
                    }
                    index += 1
                    guard index < bytes.count else { throw malformed() }
                    let symbol = bytes[index]
                    if symbol == 42 { // A starred destination must be recognized.
                        guard groups[groups.count - 1].opening, !groups[groups.count - 1].starred else { throw malformed() }
                        groups[groups.count - 1].starred = true
                        index += 1
                        continue
                    }
                    if !isLetter(symbol) {
                        guard !groups[groups.count - 1].starred else { throw malformed() }
                        if symbol == 39 { // \'hh represents a literal byte, not RTF syntax.
                            guard index + 2 < bytes.count, isHex(bytes[index + 1]), isHex(bytes[index + 2]) else { throw malformed() }
                            index += 3
                        } else {
                            guard [UInt8(92), 123, 125, 126, 45, 95, 10, 13].contains(symbol) else {
                                throw FreewheelError.unsupported(richContentMessage + " (Unsupported RTF escape.)")
                            }
                            index += 1
                            if symbol == 13, index < bytes.count, bytes[index] == 10 { index += 1 }
                        }
                        groups[groups.count - 1].opening = false
                        continue
                    }
                    let start = index
                    while index < bytes.count, isLetter(bytes[index]) {
                        guard index - start < 32 else { throw malformed() }
                        index += 1
                    }
                    let word = String(decoding: bytes[start..<index], as: UTF8.self)
                    let numberStart = index
                    if index < bytes.count, bytes[index] == 45 { index += 1 }
                    let digitsStart = index
                    while index < bytes.count, (48...57).contains(bytes[index]) {
                        guard index - digitsStart < 10 else { throw malformed() }
                        index += 1
                    }
                    let number: Int32?
                    if index != numberStart {
                        guard index > digitsStart, index - digitsStart <= 10,
                              let value = Int32(String(decoding: bytes[numberStart..<index], as: UTF8.self)) else { throw malformed() }
                        number = value
                    } else { number = nil }
                    if index < bytes.count, bytes[index] == 32 { index += 1 }
                    controls += 1
                    guard controls <= 250_000 else {
                        throw FreewheelError.unsupported("This RTF contains too many formatting commands for built-in Word export. Use LibreOffice for this document.")
                    }
                    let current = groups[groups.count - 1]
                    if word == "rtf" {
                        guard !headerSeen, groups.count == 1, current.opening, !current.starred, number == 1 else { throw malformed() }
                        headerSeen = true
                    } else if current.opening, groups.count > 1, ["fonttbl", "colortbl", "expandedcolortbl", "info", "generator"].contains(word) {
                        guard current.destination == .body else { throw unsupportedControl(word) }
                        switch word {
                        case "fonttbl": groups[groups.count - 1].destination = .fonts
                        case "colortbl": groups[groups.count - 1].destination = .colors
                        case "expandedcolortbl": groups[groups.count - 1].destination = .expandedColors
                        default: groups[groups.count - 1].destination = .metadata
                        }
                    } else {
                        // RTF writers may mark company metadata as an ignorable
                        // destination. This exception is only for a new metadata subgroup.
                        let companyMetadata = current.opening && current.destination == .metadata && word == "company" && number == nil
                        guard !current.starred || companyMetadata else { throw unsupportedControl(word) }
                        let supported: Bool
                        switch current.destination {
                        case .body:
                            supported = textControls.contains(word) || (zeroOnlyControls.contains(word) && number == 0) ||
                                (word == "CocoaLigature" && number == 1)
                        case .fonts: supported = fontControls.contains(word)
                        case .colors: supported = ["red", "green", "blue"].contains(word)
                        case .expandedColors: supported = ["cssrgb", "csgenericrgb", "csgray", "cspthree", "c"].contains(word)
                        case .metadata: supported = metadataControls.contains(word)
                        }
                        guard supported else { throw unsupportedControl(word) }
                    }
                    groups[groups.count - 1].opening = false
                    groups[groups.count - 1].starred = false
                }
                guard headerSeen, rootClosed, groups.isEmpty else { throw malformed() }
            }
        }

        private static func isLetter(_ byte: UInt8) -> Bool { (65...90).contains(byte) || (97...122).contains(byte) }
        private static func isHex(_ byte: UInt8) -> Bool { (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte) }
        private static func unsupportedControl(_ word: String) -> FreewheelError {
            // The scanner bounds this ASCII control name to 32 letters. Do not
            // include source text, numeric parameters, metadata values, or paths.
            .unsupported(richContentMessage + " (Unsupported RTF control: \\" + word + ".)")
        }
        private static func malformed() -> FreewheelError {
            .invalidInput("The RTF document has an invalid header, escape sequence, or group structure. Save a valid RTF copy before converting it.")
        }
    }
}
#endif
