#if os(macOS)
import Foundation
import LemulipCore

/// Localize the merge editor's controlled diagnostics without changing core or
/// CLI errors. A filename prefix must belong to this request, and the remaining
/// diagnostic must match a known message in its original error category.
enum PDFMergeErrorPresentation {
    private enum Kind: Equatable { case invalidInput, operationFailed }

    static func message(for error: Error, inputs: [URL], language: String) -> String {
        let detail: String
        let kind: Kind
        switch error {
        case LemulipError.invalidInput(let message):
            detail = message; kind = .invalidInput
        case LemulipError.operationFailed(let message):
            detail = message; kind = .operationFailed
        default:
            return error.localizedDescription
        }

        if let message = mergeMessage(detail, kind: kind, language: language) { return message }
        let filenames = Set(inputs.filter { $0.isFileURL && !$0.path.contains("\0") }.flatMap {
            [$0.lastPathComponent, $0.standardizedFileURL.resolvingSymlinksInPath().lastPathComponent]
        }).filter { !$0.isEmpty }.sorted { $0.count > $1.count }

        for filename in filenames {
            if kind == .invalidInput {
                if detail == "\(filename) appears more than once. Choose each PDF once." {
                    return text("\(filename): This PDF is selected more than once. Choose it only once.",
                                "\(filename): Bu PDF birden fazla kez seçilmiş. Dosyayı yalnızca bir kez seç.", language: language)
                }
                if detail == "Wait for \(filename) to finish opening before showing its preview." {
                    return text("\(filename): Wait for this PDF to finish opening before viewing its preview.",
                                "\(filename): Önizlemeyi görmek için PDF’nin açılmasını bekle.", language: language)
                }
                if detail == "\(filename) is no longer a readable local PDF. Reopen Merge PDF after checking the file." {
                    return text("\(filename): This PDF can no longer be read. Check that you can still open the file, then reopen Merge PDF.",
                                "\(filename): Bu PDF artık okunamıyor. Dosyayı açabildiğini kontrol edip birleştirme ekranını yeniden aç.", language: language)
                }
            } else if detail == "\(filename) could not be read. Check that it is a local, readable PDF and try again." {
                return text("\(filename): This PDF could not be read. Check that it is saved on your Mac and that you can access it, then try again.",
                            "\(filename): Bu PDF okunamadı. Dosyanın Mac’inde kayıtlı olduğunu ve dosyaya erişebildiğini kontrol edip yeniden dene.", language: language)
            }

            // Filenames can contain colons. Never split an arbitrary diagnostic
            // at its first colon or translate a merely similar message.
            let prefix = filename + ": "
            guard detail.hasPrefix(prefix) else { continue }
            let diagnostic = String(detail.dropFirst(prefix.count))
            if let message = sourceMessage(diagnostic, kind: kind, language: language) {
                return prefix + message
            }
        }
        return error.localizedDescription
    }

    private static func mergeMessage(_ detail: String, kind: Kind, language: String) -> String? {
        switch (kind, detail) {
        case (.invalidInput, "Choose between 2 and \(PDFMergePlan.maximumInputCount) PDF files for the merge preview."),
             (.invalidInput, "Keep at least two PDFs in a merge list with up to \(PDFMergePlan.maximumInputCount) files."):
            return text("Choose 2 to \(PDFMergePlan.maximumInputCount) PDFs to merge.",
                        "Birleştirmek için 2 ile \(PDFMergePlan.maximumInputCount) arasında PDF seç.", language: language)
        case (.invalidInput, "Choose local PDF files for the merge preview."):
            return text("Choose PDF files saved on your Mac.",
                        "Mac’inde kayıtlı PDF dosyalarını seç.", language: language)
        case (.invalidInput, "A PDF merge summary is invalid. Reopen Merge PDF before exporting."):
            return text("The merge preview could not be used. Reopen Merge PDF and try again.",
                        "Birleştirme önizlemesi kullanılamadı. Birleştirme ekranını yeniden açıp dene.", language: language)
        case (.invalidInput, "Each PDF can appear only once in the merge list."):
            return text("Each PDF can appear only once. Remove any duplicate files.",
                        "Her PDF yalnızca bir kez eklenebilir. Yinelenen dosyaları çıkar.", language: language)
        case (.invalidInput, "Keep at most \(PDFMergePlan.maximumPageCount) pages in the merged PDF. Remove a file to reduce the total."):
            return text("The merged PDF can contain up to \(PDFMergePlan.maximumPageCount) pages. Remove a file to reduce the total.",
                        "Birleştirilen PDF’de en fazla \(PDFMergePlan.maximumPageCount) sayfa olabilir. Toplamı azaltmak için bir dosya çıkar.", language: language)
        case (.invalidInput, "The PDFs in a visual merge must total at most 512 MiB."):
            return text("The PDFs can total up to 512 MiB. Choose fewer or smaller files.",
                        "PDF’lerin toplam boyutu en fazla 512 MiB olabilir. Daha az veya daha küçük dosyalar seç.", language: language)
        case (.invalidInput, "The PDF input list changed. Reopen Merge PDF before exporting."):
            return text("The selected files changed. Reopen Merge PDF before creating the copy.",
                        "Seçili dosyalar değişti. Kopya oluşturmadan önce birleştirme ekranını yeniden aç.", language: language)
        case (.operationFailed, "The PDF output could not be written."):
            return text("The PDF copy could not be saved. Check the destination folder and available disk space, then try again.",
                        "PDF kopyası kaydedilemedi. Hedef klasöre yazabildiğini ve yeterli boş alan olduğunu kontrol edip yeniden dene.", language: language)
        case (.operationFailed, "The merged PDF could not be verified. No output was published."):
            return text("The merged PDF could not be verified. No file was saved to the destination folder. Reopen Merge PDF and try again.",
                        "Birleştirilen PDF doğrulanamadı. Hedef klasöre dosya kaydedilmedi. Birleştirme ekranını yeniden açıp dene.", language: language)
        default:
            return nil
        }
    }

    private static func sourceMessage(_ detail: String, kind: Kind, language: String) -> String? {
        switch (kind, detail) {
        // The actual filename is supplied separately by withFileContext. The
        // source.pdf in this diagnostic names a private snapshot, not that file.
        case (.invalidInput, "source.pdf is not a readable PDF."):
            return text("This file could not be read as a PDF. Choose another PDF and try again.",
                        "Bu dosya PDF olarak okunamadı. Başka bir PDF seçip yeniden dene.", language: language)
        case (.invalidInput, "Choose a local PDF for the preview."):
            return text("Choose a PDF saved on your Mac.",
                        "Mac’inde kayıtlı bir PDF seç.", language: language)
        case (.invalidInput, "Choose a readable PDF for the preview."):
            return text("This PDF could not be read. Check that you can access it and try again.",
                        "Bu PDF okunamıyor. Dosyaya erişebildiğini kontrol edip yeniden dene.", language: language)
        case (.invalidInput, "PDF previews support nonempty, readable PDF files up to 512 MiB."):
            return text("Choose a nonempty, readable PDF no larger than 512 MiB.",
                        "Boş olmayan, okunabilir ve en fazla 512 MiB büyüklüğünde bir PDF seç.", language: language)
        case (.invalidInput, "The selected PDFs exceed the 512 MiB total size limit. Choose a smaller batch."):
            return text("The selected PDFs exceed 512 MiB in total. Choose fewer or smaller files.",
                        "Seçili PDF’lerin toplam boyutu 512 MiB sınırını aşıyor. Daha az veya daha küçük dosyalar seç.", language: language)
        case (.invalidInput, "The PDF changed or exceeded the 512 MiB preview limit."):
            return text("This PDF changed while opening or exceeded the merge’s 512 MiB total limit. Wait for it to finish saving, then check the size of your selection and try again.",
                        "Bu PDF okunurken değişti veya seçimin toplam boyutu 512 MiB sınırını aştı. Kaydetme işlemi bittikten sonra seçimin boyutunu kontrol edip yeniden dene.", language: language)
        case (.invalidInput, "The PDF changed while it was being opened. Try again after it finishes saving."):
            return text("This PDF changed while it was being opened. Try again after it finishes saving.",
                        "Bu PDF açılırken değişti. Kaydetme işlemi bittikten sonra yeniden dene.", language: language)
        case (.invalidInput, "This PDF is password protected. Open it with its password and save an unlocked copy, then try again."):
            return text(detail,
                        "Bu PDF parola korumalı. Parolasıyla açıp parolasız bir kopyasını kaydet, ardından yeniden dene.", language: language)
        case (.invalidInput, "PDFs must contain between 1 and \(PDFMergePlan.maximumPageCount) pages."):
            return text("Choose a PDF with 1 to \(PDFMergePlan.maximumPageCount) pages.",
                        "1 ile \(PDFMergePlan.maximumPageCount) arasında sayfası olan bir PDF seç.", language: language)
        case (.invalidInput, "This PDF does not permit copying and organizing its pages. Ask its owner for a copy that permits these changes."):
            return text("This PDF does not allow its pages to be copied and combined. Ask its owner for a copy that allows these changes.",
                        "Bu PDF, sayfalarını kopyalamaya ve birleştirmeye izin vermiyor. Dosya sahibinden bu işlemlere izin veren bir kopya iste.", language: language)
        case (.invalidInput, "This PDF changed after the merge preview opened. Reopen Merge PDF before exporting."):
            return text("This PDF changed after the merge preview opened. Reopen Merge PDF before creating the copy.",
                        "Bu PDF, önizleme açıldıktan sonra değişti. Kopya oluşturmadan önce birleştirme ekranını yeniden aç.", language: language)
        case (.invalidInput, "Choose a page within this PDF."):
            return text("This PDF’s preview could not be shown. Reopen Merge PDF and try again.",
                        "Bu PDF’nin önizlemesi gösterilemedi. Birleştirme ekranını yeniden açıp dene.", language: language)
        case (.invalidInput, "A source PDF page has an unsupported rotation."):
            return text("A page in this PDF has an unsupported rotation. Choose a copy with page rotations in 90-degree steps.",
                        "Bu PDF’deki bir sayfanın dönüş açısı desteklenmiyor. Sayfaları 90 derecelik adımlarla döndürülmüş bir kopya seç.", language: language)
        case (.invalidInput, "The PDF page has invalid or excessively large dimensions."):
            return text("A page in this PDF has invalid or overly large dimensions. Check its page size and try again.",
                        "Bu PDF’deki bir sayfanın boyutları geçersiz veya çok büyük. Sayfa boyutunu kontrol edip yeniden dene.", language: language)
        case (.operationFailed, "A private PDF preview could not be prepared."):
            return text("The PDF preview could not be prepared. Try again.",
                        "PDF önizlemesi hazırlanamadı. Yeniden dene.", language: language)
        case (.operationFailed, "The PDF page could not be rendered."),
             (.operationFailed, "PDF page rendering failed."):
            return text("The PDF page could not be displayed. Try again.",
                        "PDF sayfası görüntülenemedi. Yeniden dene.", language: language)
        case (.operationFailed, "A PDF preview exceeded its thumbnail size limit."):
            return text("The PDF preview is too large to display. Try opening this PDF again.",
                        "PDF önizlemesi gösterilemeyecek kadar büyük. Dosyayı yeniden açıp dene.", language: language)
        case (.operationFailed, "Not enough memory to render this image."):
            return text("There is not enough memory to display this PDF preview. Close unused apps and try again.",
                        "Bu PDF önizlemesini göstermek için yeterli bellek yok. Kullanmadığın uygulamaları kapatıp yeniden dene.", language: language)
        default:
            break
        }

        guard kind == .operationFailed else { return nil }
        for (suffix, verb, turkishVerb) in [(" could not be read.", "read", "okunamadı"),
                                           (" could not be copied.", "copied", "kopyalanamadı")] {
            let prefix = "PDF page "
            guard detail.hasPrefix(prefix), detail.hasSuffix(suffix) else { continue }
            let number = String(detail.dropFirst(prefix.count).dropLast(suffix.count))
            guard let page = Int(number), (1...PDFMergePlan.maximumPageCount).contains(page),
                  detail == "PDF page \(page)\(suffix)" else { continue }
            return text("PDF page \(page) could not be \(verb). Check the PDF and try again.",
                        "PDF’nin \(page). sayfası \(turkishVerb). Dosyayı kontrol edip yeniden dene.", language: language)
        }
        return nil
    }

    private static func text(_ english: String, _ turkish: String, language: String) -> String {
        language == "tr" ? turkish : english
    }
}
#endif
