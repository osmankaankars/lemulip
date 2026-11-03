#if os(macOS)
import Foundation
import LemulipCore

/// The app describes completed work without changing the engine's reports or
/// treating a file transfer as a conversion that creates a new file.
enum ActivityPresentation {
    static func status(for item: ActivityItem, language: String) -> String {
        func text(_ english: String, _ turkish: String) -> String {
            language == "tr" ? turkish : english
        }
        switch item.state {
        case .waiting: return text("Queued", "Sırada")
        case .running:
            if item.operation.id == "action.move" { return text("Moving…", "Taşınıyor…") }
            if item.operation.id == "action.copy" { return text("Copying…", "Kopyalanıyor…") }
            if item.progress?.phase == .preparing { return text("Preparing…", "Hazırlanıyor…") }
            if item.progress?.phase == .publishing || item.progress?.phase == .finished {
                if item.operation.id == "document.wordCount" { return text("Finishing…", "Tamamlanıyor…") }
                return text("Saving new files…", "Yeni dosyalar kaydediliyor…")
            }
            return text("Processing…", "İşleniyor…")
        case .succeeded:
            guard !item.outputs.isEmpty else { return text("Completed", "Tamamlandı") }
            let count = number(item.outputs.count, language: language)
            switch item.operation.id {
            case "action.move":
                return text(item.outputs.count == 1 ? "Moved · \(count) item" : "Moved · \(count) items",
                            "Taşındı · \(count) öğe")
            case "action.copy":
                return text(item.outputs.count == 1 ? "Copied · \(count) item" : "Copied · \(count) items",
                            "Kopyalandı · \(count) öğe")
            default:
                return text(item.outputs.count == 1 ? "Completed · \(count) new file" : "Completed · \(count) new files",
                            "Tamamlandı · \(count) yeni dosya")
            }
        case .failed: return text("Could not complete", "Tamamlanamadı")
        case .cancelled: return text("Cancelled", "İptal edildi")
        }
    }

    static func number(_ value: Int, language: String) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: language == "tr" ? "tr_TR" : "en_US")
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    static func completionMessage(note: String?, operationID: String, inputs: [URL],
                                  options: ConversionOptions, language: String) -> String {
        guard let note else { return "" }
        if operationID == "document.wordCount",
           let report = wordCountReport(note, inputs: inputs, language: language) {
            return report
        }
        guard language == "tr" else { return note }
        if options.pdfOrganization != nil {
            switch note {
            case "Created a new PDF without password protection. Review links, bookmarks, forms, and signatures after changing pages.":
                return "Parola koruması olmayan yeni bir PDF oluşturuldu. Kopyadaki bağlantıları, yer imlerini, formları ve imzaları kontrol et."
            case "Created a new PDF with the selected page order and rotations. Review links, bookmarks, forms, and signatures after changing pages.":
                return "Seçtiğin sayfa sırası ve dönüşlerle yeni bir PDF oluşturuldu. Kopyadaki bağlantıları, yer imlerini, formları ve imzaları kontrol et."
            default: return note
            }
        }
        if options.pdfMerge != nil {
            switch note {
            case "Created a merged PDF without password protection. Review links, bookmarks, forms, and signatures after merging.":
                return "Dosyalar parola koruması olmayan yeni bir PDF’de birleştirildi. Kopyadaki bağlantıları, yer imlerini, formları ve imzaları kontrol et."
            case "Created a new PDF in the selected file order. Review links, bookmarks, forms, and signatures after merging.":
                return "Dosyalar seçtiğin sırayla yeni bir PDF’de birleştirildi. Kopyadaki bağlantıları, yer imlerini, formları ve imzaları kontrol et."
            default: return note
            }
        }
        if options.audioTrim != nil {
            switch note {
            case "The selected audio was exported locally with AVFoundation. WAV and AIFF use 16-bit PCM at source sample boundaries; M4A re-encodes AAC and may include codec-frame padding. Original files were kept.":
                return "Seçilen ses bu Mac’te AVFoundation ile dışa aktarıldı. WAV ve AIFF, kaynak örnek sınırlarında 16 bit PCM kullanır. M4A, AAC olarak yeniden kodlanır; kodlama nedeniyle başlangıç veya bitişte ek süre olabilir. Orijinal dosyalar korundu."
            case "The selected audio was re-encoded locally with FFmpeg. Compressed formats may include codec-frame padding; original files were kept.":
                return "Seçilen ses bu Mac’te FFmpeg ile yeniden kodlandı. Sıkıştırılmış biçimlerde, kodlama nedeniyle başlangıç veya bitişte ek süre olabilir. Orijinal dosyalar korundu."
            default: return note
            }
        }
        if options.videoTrim != nil,
           note == "The selected video was re-encoded locally with AVFoundation. Video-frame timing and audio-codec padding can affect the exact boundaries; this is not a lossless cut. Original files were kept." {
            return "Seçilen video bu Mac’te AVFoundation ile yeniden kodlandı. Video karelerinin zamanlaması ve ses kodlamasının eklediği süre, başlangıç ve bitiş sınırlarını etkileyebilir; bu işlem kayıpsız kesme değildir. Orijinal dosyalar korundu."
        }
        return note
    }

    private static func wordCountReport(_ note: String, inputs: [URL], language: String) -> String? {
        guard !inputs.isEmpty,
              let expression = try? NSRegularExpression(pattern: "([0-9]+) words · ([0-9]+) characters · ([0-9]+) lines") else { return nil }
        var cursor = note.startIndex
        var reports: [String] = []
        for (index, input) in inputs.enumerated() {
            // Filenames may contain colons, newlines or the report's unit words.
            // Consume each complete known name in order, then only numeric data.
            guard input.isFileURL, !input.path.contains("\0") else { return nil }
            let names = Set([input.lastPathComponent,
                             input.standardizedFileURL.resolvingSymlinksInPath().lastPathComponent])
            // The engine validates and resolves symlinks before writing reports.
            // Preserve whichever complete request-derived name it actually used.
            guard let prefix = names.filter({ !$0.isEmpty }).sorted(by: { $0.count > $1.count })
                .map({ $0 + ": " }).first(where: { note[cursor...].hasPrefix($0) }) else { return nil }
            cursor = note.index(cursor, offsetBy: prefix.count)
            guard let match = expression.firstMatch(in: note, options: .anchored,
                                                    range: NSRange(cursor..<note.endIndex, in: note)),
                  let range = Range(match.range, in: note) else { return nil }
            var counts: [Int] = []
            for group in 1...3 {
                guard let valueRange = Range(match.range(at: group), in: note),
                      let value = Int(note[valueRange]) else { return nil }
                counts.append(value)
            }
            let words = number(counts[0], language: language)
            let characters = number(counts[1], language: language)
            let lines = number(counts[2], language: language)
            if language == "tr" {
                reports.append("\(prefix)\(words) kelime · \(characters) karakter · \(lines) satır")
            } else {
                let wordUnit = counts[0] == 1 ? "word" : "words"
                let characterUnit = counts[1] == 1 ? "character" : "characters"
                let lineUnit = counts[2] == 1 ? "line" : "lines"
                reports.append("\(prefix)\(words) \(wordUnit) · \(characters) \(characterUnit) · \(lines) \(lineUnit)")
            }
            cursor = range.upperBound
            if index < inputs.count - 1 {
                guard cursor < note.endIndex, note[cursor] == "\n" else { return nil }
                cursor = note.index(after: cursor)
            }
        }
        // A new report shape or extra diagnostic stays intact, never partly translated.
        return cursor == note.endIndex ? reports.joined(separator: "\n") : nil
    }
}
#endif
