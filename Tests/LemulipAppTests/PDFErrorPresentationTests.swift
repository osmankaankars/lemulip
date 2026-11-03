#if os(macOS)
import AppKit
import CoreGraphics
import PDFKit
import XCTest
import LemulipCore
@testable import Lemulip

final class PDFErrorPresentationTests: XCTestCase {
    @MainActor
    func testMalformedPDFExplainsRecoveryInEachLanguageAndPreservesInput() async throws {
        let directory = try workspace()
        let input = directory.appendingPathComponent("Not-A-PDF.pdf")
        let original = Data("This is a nonempty file, but it is not a PDF.".utf8)
        try original.write(to: input)

        for (language, expected) in [
            ("en", "This file could not be read as a PDF. Choose another PDF and try again."),
            ("tr", "Bu dosya PDF olarak okunamadı. Başka bir PDF seçip yeniden dene.")
        ] {
            try await expectOpeningFailure(input, language: language, expected: expected)
            XCTAssertEqual(try Data(contentsOf: input), original)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [input.lastPathComponent])
        }
    }

    @MainActor
    func testMissingAndOversizedPDFsKeepTheirSpecificRecoveryAdvice() async throws {
        let directory = try workspace()
        let missing = directory.appendingPathComponent("Missing.pdf")
        try await expectOpeningFailure(missing, language: "tr",
            expected: "Bu PDF okunamıyor. Dosyaya erişebildiğini kontrol edip yeniden dene.")
        try await expectOpeningFailure(missing, language: "en",
            expected: "Choose a readable PDF for the preview.")

        // A sparse file reaches the source-size guard without allocating or
        // decoding half a gigabyte. The public preview limit is 512 MiB.
        let oversized = directory.appendingPathComponent("Too-Large.pdf")
        XCTAssertTrue(FileManager.default.createFile(atPath: oversized.path, contents: nil))
        let handle = try FileHandle(forWritingTo: oversized)
        let size: UInt64 = 512 * 1_024 * 1_024 + 1
        try handle.truncate(atOffset: size)
        try handle.close()
        try await expectOpeningFailure(oversized, language: "tr",
            expected: "Önizleme için boş olmayan, okunabilir ve en fazla 512 MiB büyüklüğünde bir PDF seç.")
        try await expectOpeningFailure(oversized, language: "en",
            expected: "PDF previews support nonempty, readable PDF files up to 512 MiB.")
        let attributes = try FileManager.default.attributesOfItem(atPath: oversized.path)
        XCTAssertEqual((attributes[.size] as? NSNumber)?.uint64Value, size)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [oversized.lastPathComponent])
    }

    @MainActor
    func testPasswordAndCopyPermissionFailuresRemainDistinctInBothLanguages() async throws {
        let directory = try workspace()
        let plain = try makePDF(directory.appendingPathComponent("Plain.pdf"))
        let cases: [(name: String, password: String, permissions: UInt, english: String, turkish: String)] = [
            ("Locked", "test-user-password", PDFAccessPermissions.allowsContentCopying.rawValue | PDFAccessPermissions.allowsDocumentAssembly.rawValue,
             "This PDF is password protected. Open it with its password and save an unlocked copy, then try again.",
             "Bu PDF parola korumalı. Parolasıyla açıp parolasız bir kopyasını kaydet, ardından yeniden dene."),
            ("Restricted", "", PDFAccessPermissions.allowsDocumentAssembly.rawValue,
             "This PDF does not permit copying and organizing its pages. Ask its owner for a copy that permits these changes.",
             "Bu PDF, sayfalarını kopyalamaya ve düzenlemeye izin vermiyor. Dosya sahibinden bu değişikliklere izin veren bir kopya iste.")
        ]
        for item in cases {
            let input = directory.appendingPathComponent(item.name + ".pdf")
            let document = try XCTUnwrap(PDFDocument(url: plain))
            XCTAssertTrue(document.write(to: input, withOptions: [
                .ownerPasswordOption: "test-owner-password",
                .userPasswordOption: item.password,
                .accessPermissionsOption: NSNumber(value: item.permissions)
            ]))
            let original = try Data(contentsOf: input)
            for (language, expected) in [("en", item.english), ("tr", item.turkish)] {
                try await expectOpeningFailure(input, language: language, expected: expected)
                XCTAssertEqual(try Data(contentsOf: input), original)
            }
        }
    }

    func testChangedSourceValidationKeepsTheRecoveryInstructionAndCoreError() throws {
        let plan = PDFOrganizePlan(sourcePageCount: 1, sourceFingerprint: String(repeating: "a", count: 64),
                                   pages: [PDFPageEdit(sourceIndex: 0)])
        XCTAssertThrowsError(try plan.validate(sourcePageCount: 1, sourceFingerprint: String(repeating: "b", count: 64))) { error in
            guard case LemulipError.invalidInput(let diagnostic) = error else {
                return XCTFail("The core must retain its invalidInput contract")
            }
            XCTAssertEqual(diagnostic, "The PDF changed after the editor opened. Reopen Organize PDF before exporting.")
            XCTAssertEqual(PDFErrorPresentation.message(for: error, language: "en"), diagnostic)
            XCTAssertEqual(PDFErrorPresentation.message(for: error, language: "tr"),
                "PDF, düzenleyici açıldıktan sonra değişti. Kopya oluşturmadan önce PDF düzenleyicisini yeniden aç.")
        }
    }

    func testUnknownAndSystemDiagnosticsAreNeverGuessedOrReplaced() {
        let diagnostics: [Error] = [
            LemulipError.invalidInput("A new PDF validation reason; preserve this diagnostic."),
            LemulipError.operationFailed("A new file operation reason; preserve this diagnostic."),
            LemulipError.unsupported("Choose a readable PDF for the preview."),
            LemulipError.missingDependency("Example Engine"),
            NSError(domain: "PDFErrorPresentationTests", code: 42,
                    userInfo: [NSLocalizedDescriptionKey: "An exact system diagnostic."])
        ]
        for error in diagnostics {
            for language in ["en", "tr"] {
                XCTAssertEqual(PDFErrorPresentation.message(for: error, language: language), error.localizedDescription)
            }
        }
        // A longer diagnostic is not the known message. No prefix matching.
        let extended = LemulipError.invalidInput("Choose a readable PDF for the preview. Extra diagnostic detail.")
        XCTAssertEqual(PDFErrorPresentation.message(for: extended, language: "tr"), extended.localizedDescription)
    }

    @MainActor
    private func expectOpeningFailure(_ input: URL, language: String, expected: String) async throws {
        let editor = PDFOrganizeEditor()
        defer { editor.close() }
        await editor.open(input, language: language)
        XCTAssertEqual(editor.errorMessage, expected)
        XCTAssertNil(editor.source)
        XCTAssertFalse(editor.isLoading)
        XCTAssertTrue(editor.pages.isEmpty)
        XCTAssertNil(editor.exportPlan(selectedOnly: false), "A failed preview must never enable export")
    }

    private func workspace() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Lemulip-PDF-Errors-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func makePDF(_ url: URL) throws -> URL {
        var box = CGRect(x: 0, y: 0, width: 200, height: 200)
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(box)
        context.endPDFPage()
        context.closePDF()
        return url
    }
}
#endif
