import Foundation

/// A deliberately small SpreadsheetML exporter. Delimited data has no type
/// schema, so every field stays text rather than becoming a number or formula.
enum SpreadsheetWriter {
    static let limits = TextCodec.DelimitedLimits(rows: 100_000, columns: 16_384,
        cells: 500_000, fieldUTF16: 32_767, fieldLineFeeds: 253)

    static func convert(inputs: [URL], directory: URL) async throws -> ConversionResult {
        guard !inputs.isEmpty, inputs.allSatisfy({ ["csv", "tsv"].contains($0.pathExtension.lowercased()) }) else {
            throw FreewheelError.unsupported("Choose CSV or TSV files for built-in Excel workbook export.")
        }
        var outputs: [URL] = []
        for input in inputs {
            try Task.checkCancellation()
            outputs.append(try await workbook(for: input, directory: directory))
        }
        return ConversionResult(outputs: outputs,
            note: "Each file became a single-sheet Excel workbook. All cells are stored as text; formulas, numbers, and dates are not inferred.")
    }

    private static func workbook(for input: URL, directory: URL) async throws -> URL {
        let text = try TextCodec.read(input)
        let package = directory.appendingPathComponent(".spreadsheet-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: package) }
        for child in ["_rels", "xl/_rels", "xl/worksheets"] {
            try FileManager.default.createDirectory(at: package.appendingPathComponent(child, isDirectory: true),
                withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        // All package names and relationships are fixed. No source path,
        // author, external resource, or machine metadata becomes a part.
        for (name, contents) in parts {
            try Task.checkCancellation()
            try Data(contents.utf8).write(to: package.appendingPathComponent(name), options: .withoutOverwriting)
        }
        let worksheet = try BufferedXMLWriter(url: package.appendingPathComponent("xl/worksheets/sheet1.xml"))
        try worksheet.append("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData>")
        var rowNumber = 0
        var columns: [String] = []
        try TextCodec.forEachDelimitedRow(text, delimiter: input.pathExtension.lowercased() == "csv" ? "," : "\t", limits: limits) { row in
            rowNumber += 1
            while columns.count < row.count { columns.append(columnName(columns.count)) }
            try worksheet.append("<row r=\"\(rowNumber)\">")
            for (index, field) in row.enumerated() {
                if index & 255 == 0 { try Task.checkCancellation() }
                try worksheet.append("<c r=\"\(columns[index])\(rowNumber)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">")
                try worksheet.append(escapedCellText(field))
                try worksheet.append("</t></is></c>")
            }
            try worksheet.append("</row>")
        }
        try worksheet.append("</sheetData></worksheet>\n")
        try worksheet.finish()
        try Task.checkCancellation()
        // Reuse the existing local ZIP writer and its cancellation callback.
        // Archive inputs are the package contents, not their parent folder.
        let archive = try await ExternalConverters.archives(
            ["[Content_Types].xml", "_rels", "xl"].map { package.appendingPathComponent($0) },
            operation: FileOperation(id: "archive.createZip", title: "Create ZIP"), directory: package)
        guard let zipped = archive.outputs.first, archive.outputs.count == 1 else {
            throw FreewheelError.operationFailed("The Excel workbook package could not be created.")
        }
        let output = OutputStore.uniqueURL(in: directory, stem: input.deletingPathExtension().lastPathComponent, extension: "xlsx")
        try FileManager.default.moveItem(at: zipped, to: output)
        return output
    }

    private static func columnName(_ index: Int) -> String {
        var value = index + 1
        var letters: [UInt8] = []
        while value > 0 {
            value -= 1
            letters.append(UInt8(65 + value % 26))
            value /= 26
        }
        return String(decoding: letters.reversed(), as: UTF8.self)
    }

    private static func escapedCellText(_ value: String) throws -> String {
        guard value.unicodeScalars.allSatisfy({ scalar in
            switch scalar.value {
            case 0x09, 0x0A, 0x0D, 0x20...0xD7FF, 0xE000...0xFFFD, 0x10000...0x10FFFF: return true
            default: return false
            }
        }) else { throw FreewheelError.invalidInput("A table cell contains a control character that cannot be saved in an Excel workbook.") }
        let bytes = Array(value.utf8)
        var escaped: [UInt8] = []
        escaped.reserveCapacity(bytes.count)
        func hex(_ byte: UInt8) -> Bool { (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte) }
        for (index, byte) in bytes.enumerated() {
            switch byte {
            case 38: escaped.append(contentsOf: "&amp;".utf8)
            case 60: escaped.append(contentsOf: "&lt;".utf8)
            case 62: escaped.append(contentsOf: "&gt;".utf8)
            case 13: escaped.append(contentsOf: "_x000D_".utf8)
            case 95 where index + 6 < bytes.count && bytes[index + 1] == 120 && bytes[index + 6] == 95
                && bytes[(index + 2)...(index + 5)].allSatisfy(hex):
                // Preserve a literal _xHHHH_ by escaping only its first
                // underscore. CR needs Xstring escaping; LF and tab do not.
                // Microsoft [MS-OI29500] 22.9.2.19, ST_Xstring.
                escaped.append(contentsOf: "_x005F_".utf8)
            default: escaped.append(byte)
            }
        }
        return String(decoding: escaped, as: UTF8.self)
    }

    private static let parts: [(String, String)] = [
        ("[Content_Types].xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>
        """),
        ("_rels/.rels", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
        """),
        ("xl/workbook.xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>
        """),
        ("xl/_rels/workbook.xml.rels", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>
        """),
    ]

    private final class BufferedXMLWriter {
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

        func append(_ text: String) throws {
            let data = Data(text.utf8)
            var offset = 0
            while offset < data.count {
                let count = min(capacity - buffer.count, data.count - offset)
                buffer.append(data.subdata(in: offset..<(offset + count)))
                offset += count
                if buffer.count == capacity { try flush() }
            }
        }

        func finish() throws {
            try flush()
            try handle.close()
            closed = true
        }

        private func flush() throws {
            try Task.checkCancellation()
            guard !buffer.isEmpty else { return }
            try handle.write(contentsOf: buffer)
            buffer.removeAll(keepingCapacity: true)
        }
    }
}
