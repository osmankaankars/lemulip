#if os(macOS)
import AppKit
import CoreGraphics
import PDFKit
import XCTest
import LemulipCore
@testable import Lemulip

final class PDFMergeErrorPresentationTests: XCTestCase {
    @MainActor
    func testMalformedPDFKeepsItsLongUnicodeFilenameAndExplainsRecoveryInBothLanguages() async throws {
        let directory = try workspace()
        let first = try makePDF(directory.appendingPathComponent("First.pdf"))
        let name = "2026: Çınar ve Işık - " + String(repeating: "uzun dosya adı ", count: 5) + "rapor.pdf"
        let malformed = directory.appendingPathComponent(name)
        let original = Data("This is not a PDF, despite its extension.".utf8)
        try original.write(to: malformed)
        let firstBytes = try Data(contentsOf: first)
        let before = try contents(directory)

        for (language, explanation) in [
            ("en", "This file could not be read as a PDF. Choose another PDF and try again."),
            ("tr", "Bu dosya PDF olarak okunamadı. Başka bir PDF seçip yeniden dene.")
        ] {
            try await expectOpeningFailure([first, malformed], language: language,
                                           expected: name + ": " + explanation)
            XCTAssertEqual(try Data(contentsOf: malformed), original)
            XCTAssertEqual(try Data(contentsOf: first), firstBytes)
            XCTAssertEqual(try contents(directory), before)
        }
    }

    @MainActor
    func testMissingAndOversizedFilesRemainDistinctAndKeepTheirNames() async throws {
        let directory = try workspace()
        let first = try makePDF(directory.appendingPathComponent("First.pdf"))
        let missing = directory.appendingPathComponent("Eksik: Çınar.pdf")
        for (language, explanation) in [
            ("en", "This PDF could not be read. Check that you can access it and try again."),
            ("tr", "Bu PDF okunamıyor. Dosyaya erişebildiğini kontrol edip yeniden dene.")
        ] {
            try await expectOpeningFailure([first, missing], language: language,
                                           expected: missing.lastPathComponent + ": " + explanation)
        }

        // Reach the real source-size guard without allocating or decoding 512 MiB.
        let oversized = directory.appendingPathComponent("Too-Large.pdf")
        XCTAssertTrue(FileManager.default.createFile(atPath: oversized.path, contents: nil))
        let handle = try FileHandle(forWritingTo: oversized)
        let size: UInt64 = 512 * 1_024 * 1_024 + 1
        try handle.truncate(atOffset: size)
        try handle.close()
        let before = try contents(directory)
        for (language, explanation) in [
            ("en", "Choose a nonempty, readable PDF no larger than 512 MiB."),
            ("tr", "Boş olmayan, okunabilir ve en fazla 512 MiB büyüklüğünde bir PDF seç.")
        ] {
            try await expectOpeningFailure([first, oversized], language: language,
                                           expected: oversized.lastPathComponent + ": " + explanation)
            let attributes = try FileManager.default.attributesOfItem(atPath: oversized.path)
            XCTAssertEqual((attributes[.size] as? NSNumber)?.uint64Value, size)
            XCTAssertEqual(try contents(directory), before)
        }
    }

    @MainActor
    func testPasswordAndCopyPermissionFailuresKeepTheirRecoveryActions() async throws {
        let directory = try workspace()
        let plain = try makePDF(directory.appendingPathComponent("Plain.pdf"))
        let cases: [(name: String, password: String, permissions: UInt, english: String, turkish: String)] = [
            ("Locked: Çınar", "test-user-password", PDFAccessPermissions.allowsContentCopying.rawValue | PDFAccessPermissions.allowsDocumentAssembly.rawValue,
             "This PDF is password protected. Open it with its password and save an unlocked copy, then try again.",
             "Bu PDF parola korumalı. Parolasıyla açıp parolasız bir kopyasını kaydet, ardından yeniden dene."),
            ("Restricted: Çınar", "", PDFAccessPermissions.allowsDocumentAssembly.rawValue,
             "This PDF does not allow its pages to be copied and combined. Ask its owner for a copy that allows these changes.",
             "Bu PDF, sayfalarını kopyalamaya ve birleştirmeye izin vermiyor. Dosya sahibinden bu işlemlere izin veren bir kopya iste.")
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
            let before = try contents(directory)
            for (language, explanation) in [("en", item.english), ("tr", item.turkish)] {
                try await expectOpeningFailure([plain, input], language: language,
                                               expected: input.lastPathComponent + ": " + explanation)
                XCTAssertEqual(try Data(contentsOf: input), original)
                XCTAssertEqual(try contents(directory), before)
            }
        }
    }

    @MainActor
    func testDuplicateAndInputCountErrorsUseTheMergeContract() async throws {
        let directory = try workspace()
        let input = try makePDF(directory.appendingPathComponent("Teklif: İkinci kopya.pdf"))
        for (language, explanation) in [
            ("en", "This PDF is selected more than once. Choose it only once."),
            ("tr", "Bu PDF birden fazla kez seçilmiş. Dosyayı yalnızca bir kez seç.")
        ] {
            try await expectOpeningFailure([input, input], language: language,
                                           expected: input.lastPathComponent + ": " + explanation)
        }
        for inputs in [[input], Array(repeating: input, count: 101)] {
            try await expectOpeningFailure(inputs, language: "tr",
                                           expected: "Birleştirmek için 2 ile 100 arasında PDF seç.")
            try await expectOpeningFailure(inputs, language: "en", expected: "Choose 2 to 100 PDFs to merge.")
        }
        XCTAssertEqual(try contents(directory), [input.lastPathComponent])
    }

    @MainActor
    func testSymlinkErrorsRecognizeTheResolvedNameAndTheOriginalDuplicateName() async throws {
        let directory = try workspace()
        let first = try makePDF(directory.appendingPathComponent("First.pdf"))
        let malformed = directory.appendingPathComponent("Asıl: Çınar.pdf")
        let bytes = Data("Not a PDF".utf8)
        try bytes.write(to: malformed)
        let alias = directory.appendingPathComponent("Bağlantı: Görünen.pdf")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: malformed)
        try await expectOpeningFailure([first, alias], language: "tr",
            expected: "Asıl: Çınar.pdf: Bu dosya PDF olarak okunamadı. Başka bir PDF seçip yeniden dene.")
        XCTAssertEqual(try Data(contentsOf: malformed), bytes)

        let duplicate = directory.appendingPathComponent("Aynı dosya: Bağlantı.pdf")
        try FileManager.default.createSymbolicLink(at: duplicate, withDestinationURL: first)
        try await expectOpeningFailure([first, duplicate], language: "tr",
            expected: "Aynı dosya: Bağlantı.pdf: Bu PDF birden fazla kez seçilmiş. Dosyayı yalnızca bir kez seç.")
    }

    @MainActor
    func testChangedSourceLocalizesThumbnailAndExportErrorsWithoutPublishingOutput() async throws {
        let directory = try workspace()
        let first = try makePDF(directory.appendingPathComponent("First.pdf"))
        let second = try makePDF(directory.appendingPathComponent("Çınar: Son sürüm.pdf"))
        let inputs = [first, second]
        let editor = PDFMergeEditor()
        defer { editor.close() }
        await editor.open(inputs, language: "tr")
        XCTAssertTrue(editor.isReady)
        var options = ConversionOptions()
        options.pdfMerge = try XCTUnwrap(editor.exportPlan())
        let output = directory.appendingPathComponent("Output", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        options.destinationDirectory = output

        var changed = try Data(contentsOf: second)
        changed.append(Data("\n% A later saved version\n".utf8))
        try changed.write(to: second)
        editor.showDocuments([1])
        let deadline = Date().addingTimeInterval(5)
        while editor.thumbnailErrors[1] == nil, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let turkish = "Çınar: Son sürüm.pdf: Bu PDF, önizleme açıldıktan sonra değişti. Kopya oluşturmadan önce birleştirme ekranını yeniden aç."
        XCTAssertEqual(editor.thumbnailErrors[1], turkish)
        XCTAssertNil(editor.thumbnails[1])

        do {
            _ = try await ConversionEngine().run(inputs: inputs,
                operation: FileOperation(id: "pdf.merge", title: "Merge PDF", outputExtension: "pdf"), options: options)
            XCTFail("A changed source must not be exported using an old merge preview")
        } catch {
            guard case LemulipError.invalidInput(let detail) = error else {
                return XCTFail("The core must retain its invalidInput contract: \(error)")
            }
            XCTAssertEqual(detail, "Çınar: Son sürüm.pdf: This PDF changed after the merge preview opened. Reopen Merge PDF before exporting.")
            XCTAssertEqual(PDFMergeErrorPresentation.message(for: error, inputs: inputs, language: "tr"), turkish)
            XCTAssertEqual(PDFMergeErrorPresentation.message(for: error, inputs: inputs, language: "en"),
                "Çınar: Son sürüm.pdf: This PDF changed after the merge preview opened. Reopen Merge PDF before creating the copy.")
        }
        XCTAssertEqual(try Data(contentsOf: second), changed)
        XCTAssertTrue(try contents(output).isEmpty)
    }

    @MainActor
    func testRenamedSourceAfterPreviewKeepsItsFilenameAndExplainsExportRecovery() async throws {
        let directory = try workspace()
        let first = try makePDF(directory.appendingPathComponent("First.pdf"))
        let second = try makePDF(directory.appendingPathComponent("Çınar: İmzalı teklif.pdf"))
        let inputs = [first, second]
        let firstBytes = try Data(contentsOf: first)
        let secondBytes = try Data(contentsOf: second)
        let editor = PDFMergeEditor()
        defer { editor.close() }
        await editor.open(inputs, language: "tr")
        XCTAssertTrue(editor.isReady)
        var options = ConversionOptions()
        options.pdfMerge = try XCTUnwrap(editor.exportPlan())
        let output = directory.appendingPathComponent("Output", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        options.destinationDirectory = output

        // Rename after the actual preview has bound its source fingerprints.
        // Export must fail at the engine's retained-input readability check,
        // before creating or publishing a partial merged PDF.
        let renamed = directory.appendingPathComponent("Taşınan: İmzalı teklif.pdf")
        try FileManager.default.moveItem(at: second, to: renamed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.path))
        do {
            _ = try await ConversionEngine().run(inputs: inputs,
                operation: FileOperation(id: "pdf.merge", title: "Merge PDF", outputExtension: "pdf"), options: options)
            XCTFail("A retained source renamed after preview must not be exported")
        } catch {
            guard case LemulipError.invalidInput(let detail) = error else {
                return XCTFail("The core must retain its invalidInput contract: \(error)")
            }
            XCTAssertEqual(detail, "Çınar: İmzalı teklif.pdf is no longer a readable local PDF. Reopen Merge PDF after checking the file.")
            XCTAssertEqual(PDFMergeErrorPresentation.message(for: error, inputs: inputs, language: "tr"),
                "Çınar: İmzalı teklif.pdf: Bu PDF artık okunamıyor. Dosyayı açabildiğini kontrol edip birleştirme ekranını yeniden aç.")
            XCTAssertEqual(PDFMergeErrorPresentation.message(for: error, inputs: inputs, language: "en"),
                "Çınar: İmzalı teklif.pdf: This PDF can no longer be read. Check that you can still open the file, then reopen Merge PDF.")
        }
        XCTAssertEqual(try Data(contentsOf: first), firstBytes)
        XCTAssertEqual(try Data(contentsOf: renamed), secondBytes)
        XCTAssertTrue(try contents(output).isEmpty)
        XCTAssertEqual(try contents(directory), [first.lastPathComponent, renamed.lastPathComponent, output.lastPathComponent])
    }

    func testPageAndTotalSizeLimitsKeepTheirNumbersAndRecoveryAdvice() throws {
        func source(_ index: Int, pages: Int, bytes: Int64) -> PDFMergeSource {
            PDFMergeSource(inputIndex: index, pageCount: pages, fingerprint: String(repeating: "a", count: 64),
                           byteCount: bytes, isEncrypted: false)
        }
        let tooManyPages = PDFMergePlan(sourceInputCount: 2,
            sources: [source(0, pages: 1_000, bytes: 1), source(1, pages: 1, bytes: 1)])
        let tooManyBytes = PDFMergePlan(sourceInputCount: 2,
            sources: [source(0, pages: 1, bytes: 512 * 1_024 * 1_024), source(1, pages: 1, bytes: 1)])
        for (plan, english, turkish) in [
            (tooManyPages,
             "The merged PDF can contain up to 1000 pages. Remove a file to reduce the total.",
             "Birleştirilen PDF’de en fazla 1000 sayfa olabilir. Toplamı azaltmak için bir dosya çıkar."),
            (tooManyBytes,
             "The PDFs can total up to 512 MiB. Choose fewer or smaller files.",
             "PDF’lerin toplam boyutu en fazla 512 MiB olabilir. Daha az veya daha küçük dosyalar seç.")
        ] {
            XCTAssertThrowsError(try plan.validate()) { error in
                guard case LemulipError.invalidInput = error else { return XCTFail("Preserve the core validation category") }
                XCTAssertEqual(PDFMergeErrorPresentation.message(for: error, inputs: [], language: "en"), english)
                XCTAssertEqual(PDFMergeErrorPresentation.message(for: error, inputs: [], language: "tr"), turkish)
            }
        }
    }

    func testSuccessfulPDFNotesDescribeRealCopiesAndRetainProtectionWarnings() async throws {
        let directory = try workspace()
        let first = try makePDF(directory.appendingPathComponent("First.pdf"))
        let plain = try makePDF(directory.appendingPathComponent("Second.pdf"), width: 300)
        let protected = directory.appendingPathComponent("Protected.pdf")
        let document = try XCTUnwrap(PDFDocument(url: plain))
        XCTAssertTrue(document.write(to: protected, withOptions: [
            .ownerPasswordOption: "test-owner-password",
            .userPasswordOption: "",
            .accessPermissionsOption: NSNumber(value: PDFAccessPermissions.allowsContentCopying.rawValue
                | PDFAccessPermissions.allowsDocumentAssembly.rawValue)
        ]))
        let firstBytes = try Data(contentsOf: first)

        for input in [plain, protected] {
            let original = try Data(contentsOf: input)
            let openedDocument = try XCTUnwrap(PDFDocument(url: input))
            let wasEncrypted = input == protected
            XCTAssertEqual(openedDocument.isEncrypted, wasEncrypted)
            XCTAssertFalse(openedDocument.isLocked)

            let mergeSession = PDFMergeSession(inputs: [first, input])
            let firstSource = try await mergeSession.source(for: 0)
            let secondSource = try await mergeSession.source(for: 1)
            var mergeOptions = ConversionOptions()
            mergeOptions.pdfMerge = PDFMergePlan(sourceInputCount: 2, sources: [secondSource, firstSource])
            await mergeSession.close()

            let organizeSession = PDFOrganizeSession(input: input)
            let organizedSource = try await organizeSession.open()
            var organizePlan = organizedSource.initialPlan
            organizePlan.pages[0].rotationQuarterTurns = 1
            var organizeOptions = ConversionOptions()
            organizeOptions.pdfOrganization = organizePlan
            await organizeSession.close()

            for (operationID, inputs, originalOptions) in [
                ("pdf.merge", [first, input], mergeOptions),
                ("pdf.organize", [input], organizeOptions)
            ] {
                let folder = directory.appendingPathComponent(input.lastPathComponent + "-" + operationID,
                                                               isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
                var options = originalOptions
                options.destinationDirectory = folder
                let result = try await ConversionEngine().run(inputs: inputs,
                    operation: FileOperation(id: operationID, title: operationID, outputExtension: "pdf"), options: options)
                XCTAssertEqual(result.outputs.count, 1)
                let output = try XCTUnwrap(PDFDocument(url: XCTUnwrap(result.outputs.first)))
                XCTAssertFalse(output.isEncrypted)
                XCTAssertFalse(output.isLocked)
                if operationID == "pdf.merge" {
                    XCTAssertEqual(output.pageCount, 2)
                    XCTAssertEqual(output.page(at: 0)?.bounds(for: .mediaBox).width, 300)
                    XCTAssertEqual(output.page(at: 1)?.bounds(for: .mediaBox).width, 200)
                } else {
                    XCTAssertEqual(output.pageCount, 1)
                    XCTAssertEqual(output.page(at: 0)?.rotation, 90)
                }

                // Start with the actual engine result, not a fabricated note.
                // Each PDF copy must keep the review advice and disclose the
                // loss of password protection when its source was encrypted.
                let note = try XCTUnwrap(result.note)
                XCTAssertEqual(note.contains("without password protection"), wasEncrypted)
                XCTAssertEqual(ActivityPresentation.completionMessage(note: note, operationID: operationID,
                    inputs: inputs, options: options, language: "en"), note)
                let translated = ActivityPresentation.completionMessage(note: note, operationID: operationID,
                    inputs: inputs, options: options, language: "tr")
                XCTAssertNotEqual(translated, note)
                for detail in ["bağlantıları", "yer imlerini", "formları", "imzaları"] {
                    XCTAssertTrue(translated.contains(detail), "Retain the PDF review detail: \(detail)")
                }
                XCTAssertEqual(translated.contains("parola koruması olmayan"), wasEncrypted)
                if !wasEncrypted {
                    XCTAssertTrue(translated.localizedCaseInsensitiveContains("seçtiğin"))
                    if operationID == "pdf.organize" { XCTAssertTrue(translated.contains("dönüş")) }
                }
                XCTAssertEqual(ActivityPresentation.completionMessage(note: note, operationID: operationID,
                    inputs: inputs, options: ConversionOptions(), language: "tr"), note,
                    "A note outside its editor contract must remain intact")
                XCTAssertEqual(try Data(contentsOf: input), original)
                XCTAssertEqual(try Data(contentsOf: first), firstBytes)
            }
        }
    }

    func testCanonicalPageFailuresKeepThePageNumberAndRejectExtendedDiagnostics() {
        let input = URL(fileURLWithPath: "/tmp/Teklif: Çınar.pdf")
        let detail = "Teklif: Çınar.pdf: PDF page 12 could not be copied."
        let error = LemulipError.operationFailed(detail)
        XCTAssertEqual(PDFMergeErrorPresentation.message(for: error, inputs: [input], language: "tr"),
                       "Teklif: Çınar.pdf: PDF’nin 12. sayfası kopyalanamadı. Dosyayı kontrol edip yeniden dene.")
        XCTAssertEqual(PDFMergeErrorPresentation.message(for: error, inputs: [input], language: "en"),
                       "Teklif: Çınar.pdf: PDF page 12 could not be copied. Check the PDF and try again.")
        for suffix in ["PDF page 0 could not be copied.", "PDF page 01 could not be copied.",
                       "PDF page 1001 could not be copied.", "PDF page 12 could not be copied. Extra diagnostic."] {
            let unknown = LemulipError.operationFailed(input.lastPathComponent + ": " + suffix)
            XCTAssertEqual(PDFMergeErrorPresentation.message(for: unknown, inputs: [input], language: "tr"),
                           unknown.localizedDescription)
        }
    }

    func testUnknownMismatchedAndSystemDiagnosticsArePreservedVerbatim() {
        let input = URL(fileURLWithPath: "/tmp/Teklif: Çınar.pdf")
        let knownDetail = input.lastPathComponent + ": source.pdf is not a readable PDF."
        let missingDetail = input.lastPathComponent + " is no longer a readable local PDF. Reopen Merge PDF after checking the file."
        let errors: [Error] = [
            LemulipError.invalidInput(knownDetail + " Extra diagnostic detail."),
            LemulipError.invalidInput("Another file.pdf: source.pdf is not a readable PDF."),
            LemulipError.invalidInput("source.pdf is not a readable PDF."),
            LemulipError.operationFailed(knownDetail),
            LemulipError.unsupported(knownDetail),
            LemulipError.operationFailed(missingDetail),
            LemulipError.invalidInput(missingDetail + " Extra diagnostic detail."),
            LemulipError.invalidInput("Another file.pdf is no longer a readable local PDF. Reopen Merge PDF after checking the file."),
            LemulipError.invalidInput("A new merge reason; retain every detail."),
            LemulipError.operationFailed(input.lastPathComponent + ": A new file reason; retain every detail."),
            LemulipError.missingDependency("Example Engine"),
            LemulipError.cancelled,
            NSError(domain: "PDFMergeErrorPresentationTests", code: 42,
                    userInfo: [NSLocalizedDescriptionKey: knownDetail])
        ]
        for error in errors {
            for language in ["en", "tr"] {
                XCTAssertEqual(PDFMergeErrorPresentation.message(for: error, inputs: [input], language: language),
                               error.localizedDescription)
            }
        }
    }

    @MainActor
    private func expectOpeningFailure(_ inputs: [URL], language: String, expected: String) async throws {
        let editor = PDFMergeEditor()
        defer { editor.close() }
        await editor.open(inputs, language: language)
        XCTAssertEqual(editor.errorMessage, expected)
        XCTAssertFalse(editor.isLoading)
        XCTAssertFalse(editor.isReady)
        XCTAssertTrue(editor.documents.isEmpty)
        XCTAssertNil(editor.exportPlan(), "A failed merge preview must not enable export")
    }

    private func workspace() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Lemulip-Merge-Errors-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func contents(_ directory: URL) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
    }

    private func makePDF(_ url: URL, width: CGFloat = 200) throws -> URL {
        var box = CGRect(x: 0, y: 0, width: width, height: 200)
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
