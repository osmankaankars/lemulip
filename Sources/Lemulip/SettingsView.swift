#if os(macOS)
import AppKit
import SwiftUI
import LemulipCore

struct SettingsContent: View {
    @ObservedObject var model: AppController
    @State private var copied: String?
    private let engines: [(String, String, String, String)] = [
        ("ffmpeg", "FFmpeg", "Video & audio formats, compression, trim, speed", "brew install ffmpeg"),
        ("imagemagick", "ImageMagick", "WebP, AVIF & additional image codecs", "brew install imagemagick"),
        ("libreoffice", "LibreOffice", "Rich documents, existing workbooks & slides", "brew install --cask libreoffice"),
        ("pandoc", "Pandoc", "EPUB & structured document conversion", "https://pandoc.org/installing.html")
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 27) {
            VStack(alignment: .leading, spacing: 10) {
                Text(model.text("Small App. Your Rules.", "Küçük uygulama. Senin kuralların."))
                    .font(.system(size: 30, weight: .semibold)).tracking(-0.9)
                Text(model.text("No account, subscription, or daily quotas.", "Hesap, abonelik ya da günlük kota yok."))
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
            appearanceSettings
            VStack(spacing: 0) {
                settingRow(model.text("Language", "Dil"), subtitle: model.text("App interface language", "Uygulama arayüzünün dili")) {
                    Picker("", selection: $model.language) { Text("English").tag("en"); Text("Türkçe").tag("tr") }.labelsHidden().frame(width: 132)
                }
                divider
                settingRow(model.text("Drag Wheel", "Sürükleme çarkı"), subtitle: model.text("Start dragging, then tap ⇧, ⌘, or ⌃", "Sürüklemeye başla, ardından ⇧, ⌘ veya ⌃ tuşuna dokun")) {
                    Toggle("", isOn: $model.wheelEnabled).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                divider
                settingRow(model.text("Save in the First File's Folder", "İlk dosyanın klasörüne kaydet"), subtitle: model.text("Turn off to choose a destination for each job", "Her işlemde hedef klasör seçmek için kapat")) {
                    Toggle("", isOn: $model.outputAlongsideOriginal).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                divider
                settingRow(model.text("Reveal Finished Files", "Biten dosyaları göster"), subtitle: model.text("Show results in Finder after a successful job", "Tamamlanan işlemin sonuçlarını Finder'da göster")) {
                    Toggle("", isOn: $model.revealWhenFinished).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }.background(Palette.panel, in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(Palette.line))

            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Text(model.text("Local Engines", "YEREL MOTORLAR")).font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1.4).foregroundStyle(Palette.muted)
                    Spacer()
                    Button { model.engineRefresh += 1 } label: { Label(model.text("Refresh", "Yenile"), systemImage: "arrow.clockwise") }
                        .buttonStyle(.plain).foregroundStyle(Palette.accent).font(.system(size: 11))
                }
                Text(model.text("Images, PDFs, OCR, archives, subtitles, and basic text tools are built in. TXT, basic RTF, and basic Markdown to Word need no extra engine. Complex RTF needs LibreOffice; advanced Markdown needs Pandoc. CSV/TSV to Excel is built in and keeps every value as text. Add free engines for more formats; conversions stay local.", "Görsel, PDF, OCR, arşiv, altyazı ve temel metin araçları uygulamada hazır. TXT, temel RTF ve temel Markdown dosyalarından Word’e dönüşüm için ek motor gerekmez. Karmaşık RTF dosyaları LibreOffice, gelişmiş Markdown dosyaları Pandoc gerektirir. CSV/TSV’den Excel’e dönüşüm uygulamada hazırdır ve tüm değerleri metin olarak korur. Daha fazla biçim için ücretsiz motorlar ekleyebilirsin; dönüşümler yerelde çalışır."))
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(4)
                VStack(spacing: 0) {
                    ForEach(engines, id: \.0) { engine in
                        let installed = EngineLocator.isAvailable(engine.0)
                        HStack(alignment: .center, spacing: 14) {
                            Image(systemName: installed ? "checkmark.circle.fill" : "plus.circle").font(.system(size: 19)).foregroundStyle(installed ? Palette.accent : Palette.muted)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(engine.1).font(.system(size: 13, weight: .semibold))
                                Text(engineSubtitle(engine.0, fallback: engine.2)).font(.system(size: 10)).foregroundStyle(Palette.muted)
                                if engine.0 == "pandoc" {
                                    Text(model.text("Use the official installer with built-in templates.", "Şablonları içinde olan resmî kurulum paketini kullan."))
                                        .font(.system(size: 9)).foregroundStyle(Palette.muted)
                                }
                                if let path = EngineLocator.find(engine.0)?.path { Text(path).font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.middle) }
                            }
                            Spacer(minLength: 8)
                            Button {
                                if engine.0 == "pandoc", let url = URL(string: engine.3) { NSWorkspace.shared.open(url) }
                                else { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(engine.3, forType: .string); copied = engine.0 }
                            } label: {
                                Text(engine.0 == "pandoc" ? model.text("Open Installer Page", "Kurulum sayfasını aç") : (copied == engine.0 ? model.text("Copied", "Kopyalandı") : model.text("Copy Install Command", "Kurulum komutunu kopyala")))
                                    .font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.accent).padding(.horizontal, 10).padding(.vertical, 7)
                                    .background(Palette.accent.opacity(0.07), in: Capsule())
                            }.buttonStyle(.plain)
                        }.padding(17)
                        if engine.0 != engines.last?.0 { divider }
                    }
                }.id(model.engineRefresh).background(Palette.panel, in: RoundedRectangle(cornerRadius: 13)).overlay(RoundedRectangle(cornerRadius: 13).stroke(Palette.line))
                HStack {
                    Text(model.text("Install commands require Homebrew. Pandoc uses its official installer. No automatic downloads.", "Kurulum komutları Homebrew gerektirir. Pandoc için resmî paket kullanılır. Otomatik indirme yok."))
                        .font(.system(size: 10)).foregroundStyle(Palette.muted)
                    Spacer()
                    Link("Homebrew ↗", destination: URL(string: "https://brew.sh")!).font(.system(size: 10)).foregroundStyle(Palette.accent)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Label(model.text("Privacy by Design", "Gizlilik uygulamanın temelinde"), systemImage: "lock.shield").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.accent)
                Text(model.text("No analytics, file uploads, update pings, or persistent file history. Only your settings are saved. AirDrop shares files only when you explicitly choose it.", "Analitik, dosya yükleme, güncelleme sorgusu veya kalıcı dosya geçmişi yok. Yalnızca ayarların kaydedilir. AirDrop, sen seçtiğinde dosya paylaşır."))
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(4)
                HStack(spacing: 10) {
                    AppMark(size: 32)
                    VStack(alignment: .leading, spacing: 3) {
                        AppWordmark(size: 16)
                        Text("\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Source Preview") · MIT License")
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
                    }
                }.padding(.top, 4).accessibilityElement(children: .combine)
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Palette.accent.opacity(0.04), in: RoundedRectangle(cornerRadius: 13))
        }
    }

    private var appearanceSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.text("Appearance", "Görünüm")).font(.system(size: 16, weight: .semibold))
            Text(model.text("Theme", "Tema")).font(.system(size: 11)).foregroundStyle(Palette.muted)
            HStack(spacing: 10) {
                ForEach(AppTheme.allCases) { theme in
                    Button { model.theme = theme } label: {
                        VStack(alignment: .leading, spacing: 11) {
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 5).fill(Palette.color(theme.colors.panel)).frame(width: 23)
                                VStack(alignment: .leading, spacing: 6) {
                                    Capsule().fill(Palette.color(theme.colors.ink)).frame(width: 41, height: 4)
                                    Capsule().fill(Palette.color(theme.colors.muted)).frame(width: 56, height: 3)
                                    Capsule().fill(Palette.color(theme.colors.primary)).frame(width: 34, height: 12)
                                }
                                Spacer(minLength: 0)
                            }.padding(10).frame(height: 67)
                                .background(Palette.color(theme.colors.canvas), in: RoundedRectangle(cornerRadius: 9))
                                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.color(theme.colors.line), lineWidth: 1))
                                .accessibilityHidden(true)
                            HStack(spacing: 5) {
                                Text(theme.name).font(.system(size: 11, weight: .medium)).lineLimit(1).minimumScaleFactor(0.9)
                                Spacer(minLength: 0)
                                Image(systemName: model.theme == theme ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(model.theme == theme ? Palette.accent : Palette.muted)
                                    .font(.system(size: 12))
                            }.foregroundStyle(Palette.ink)
                        }.padding(10).frame(maxWidth: .infinity)
                            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 13))
                            .overlay(RoundedRectangle(cornerRadius: 13).stroke(model.theme == theme ? Palette.accent : Palette.line, lineWidth: model.theme == theme ? 2 : 1))
                    }.buttonStyle(.plain)
                        .accessibilityLabel(theme.name)
                        .accessibilityValue(model.theme == theme ? model.text("Selected", "Seçili") : model.text("Not Selected", "Seçili değil"))
                        .accessibilityHint(model.text("Apply This Theme", "Bu temayı uygula"))
                }
            }
        }
    }

    private var divider: some View { Rectangle().fill(Palette.line).frame(height: 1).padding(.horizontal, 17) }
    private func settingRow<Control: View>(_ title: String, subtitle: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) { Text(title).font(.system(size: 12, weight: .medium)); Text(subtitle).font(.system(size: 10)).foregroundStyle(Palette.muted) }
            Spacer(minLength: 16)
            control()
        }.padding(18)
    }
    private func engineSubtitle(_ id: String, fallback: String) -> String {
        guard model.language == "tr" else { return fallback }
        return ["ffmpeg": "Video ve ses biçimleri, sıkıştırma, kesme, hız", "imagemagick": "WebP, AVIF ve ek görsel biçimleri", "libreoffice": "Biçimlendirilmiş belgeler, mevcut çalışma kitapları ve sunumlar", "pandoc": "EPUB ve yapılandırılmış belge dönüşümü"][id] ?? fallback
    }
}
#endif
