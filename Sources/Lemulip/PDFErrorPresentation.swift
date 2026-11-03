#if os(macOS)
import Foundation
import LemulipCore

/// Presentation for the organizer's controlled PDF diagnostics. Core and CLI
/// keep their existing error cases and English descriptions. Match whole known
/// messages only; an unknown or system error must retain its actual diagnostic.
enum PDFErrorPresentation {
    static func message(for error: Error, language: String) -> String {
        guard let failure = error as? LemulipError else { return error.localizedDescription }
        let detail: String
        switch failure {
        case .invalidInput(let message), .operationFailed(let message): detail = message
        default: return error.localizedDescription
        }

        let english: String
        let turkish: String
        switch detail {
        // PDFSourceSnapshot always names its private copy source.pdf. This
        // exact parse diagnostic must not present that internal filename as
        // the user's document or infer a cause such as corruption.
        case "source.pdf is not a readable PDF.":
            english = "This file could not be read as a PDF. Choose another PDF and try again."
            turkish = "Bu dosya PDF olarak okunamadı. Başka bir PDF seçip yeniden dene."
        case "Choose a local PDF for the preview.":
            english = detail
            turkish = "Önizleme için Mac’inde kayıtlı bir PDF seç."
        case "Choose a readable PDF for the preview.":
            english = detail
            turkish = "Bu PDF okunamıyor. Dosyaya erişebildiğini kontrol edip yeniden dene."
        case "PDF previews support nonempty, readable PDF files up to 512 MiB.":
            english = detail
            turkish = "Önizleme için boş olmayan, okunabilir ve en fazla 512 MiB büyüklüğünde bir PDF seç."
        case "A private PDF preview could not be prepared.":
            english = detail
            turkish = "PDF önizlemesi hazırlanamadı. Yeniden dene."
        case "The PDF changed or exceeded the 512 MiB preview limit.":
            english = detail
            turkish = "PDF okunurken değişti veya 512 MiB önizleme sınırını aştı. Kaydetme işlemi bittikten sonra boyutunu kontrol edip yeniden dene."
        case "The PDF changed while it was being opened. Try again after it finishes saving.":
            english = detail
            turkish = "PDF açılırken değişti. Kaydetme işlemi bittikten sonra yeniden dene."
        case "This PDF is password protected. Open it with its password and save an unlocked copy, then try again.":
            english = detail
            turkish = "Bu PDF parola korumalı. Parolasıyla açıp parolasız bir kopyasını kaydet, ardından yeniden dene."
        case "PDFs must contain between 1 and \(PDFOrganizePlan.maximumPageCount) pages.":
            english = detail
            turkish = "PDF, 1 ile \(PDFOrganizePlan.maximumPageCount) arasında sayfa içermeli. Bu aralıkta sayfası olan bir PDF seç."
        case "This PDF does not permit copying and organizing its pages. Ask its owner for a copy that permits these changes.":
            english = detail
            turkish = "Bu PDF, sayfalarını kopyalamaya ve düzenlemeye izin vermiyor. Dosya sahibinden bu değişikliklere izin veren bir kopya iste."
        case "The PDF changed after the editor opened. Reopen Organize PDF before exporting.":
            english = detail
            turkish = "PDF, düzenleyici açıldıktan sonra değişti. Kopya oluşturmadan önce PDF düzenleyicisini yeniden aç."
        case "Choose at least one page from a PDF with up to \(PDFOrganizePlan.maximumPageCount) pages, then reopen the editor if the source changed.":
            english = detail
            turkish = "En fazla \(PDFOrganizePlan.maximumPageCount) sayfalık bir PDF’den en az bir sayfa seç. Kaynak dosya değiştiyse düzenleyiciyi yeniden aç."
        case "PDF pages must appear once, stay within the original page range, and use quarter-turn rotations.":
            english = detail
            turkish = "Her sayfa yalnız bir kez kullanılmalı, orijinal sayfa aralığında kalmalı ve 90 derecelik adımlarla döndürülmeli. Sayfa seçimini kontrol et."
        case "A source PDF page has an unsupported rotation.":
            english = detail
            turkish = "Kaynak PDF’deki bir sayfanın dönüş açısı desteklenmiyor. Sayfaları 90 derecelik adımlarla döndürülmüş bir kopya seç."
        case "The PDF output could not be written.":
            english = detail
            turkish = "PDF kopyası kaydedilemedi. Hedef klasöre yazabildiğini ve yeterli boş alan olduğunu kontrol edip yeniden dene."
        default: return error.localizedDescription
        }
        return language == "tr" ? turkish : english
    }
}
#endif
