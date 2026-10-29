#if os(macOS)
import AppKit
import SwiftUI
import LemulipCore

struct SettingsContent: View {
    @ObservedObject var model: AppController
    @State private var copied: String?
    @State private var engineReports: [String: EngineReport] = [:]
    private let engines: [(String, String, String, String)] = [
        ("ffmpeg", "FFmpeg", "Video & Audio", "brew install ffmpeg"),
        ("imagemagick", "ImageMagick", "Images", "brew install imagemagick"),
        ("pandoc", "Pandoc", "Advanced Documents", "https://pandoc.org/installing.html"),
        ("libreoffice", "LibreOffice", "Office Documents", "brew install --cask libreoffice")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            appearanceSettings
            settingRow(model.text("Language", "Dil"), subtitle: model.text("Interface Language", "Arayüz Dili")) {
                Picker(model.text("Language", "Dil"), selection: $model.language) {
                    Text("English").tag("en"); Text("Türkçe").tag("tr")
                }.labelsHidden().frame(width: 132)
            }.background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
            settingsGroup(model.text("Drag & Shortcuts", "Sürükleme Ve Kısayollar")) {
                settingRow(model.text("Drag Wheel", "Sürükleme Çarkı"), subtitle: model.text("Drag A File, Then Tap ⇧, ⌘ Or ⌃.", "Dosyayı Sürükle, Ardından ⇧, ⌘ Veya ⌃ Tuşuna Dokun.")) {
                    Toggle(model.text("Drag Wheel", "Sürükleme Çarkı"), isOn: $model.wheelEnabled)
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }
            settingRow(model.text("Selection Sounds", "Seçim Sesleri"),
                       subtitle: model.text("A quiet tick when you confirm an operation. Follows macOS sound effects settings.",
                                            "İşlemi onayladığında kısa bir ses. macOS ses efekti ayarlarına uyar.")) {
                HStack(spacing: 12) {
                    Button { model.previewSelectionSound() } label: {
                        Label(model.text("Preview", "Dinle"), systemImage: "speaker.wave.1")
                    }.buttonStyle(.bordered).controlSize(.small)
                        .accessibilityLabel(model.text("Preview Selection Sound", "Seçim Sesini Dinle"))
                        .accessibilityHint(model.text("Play once without changing the setting. Follows macOS sound effects settings.",
                                                      "Ayarı değiştirmeden bir kez çal. macOS ses efekti ayarlarına uyar."))
                        .accessibilityIdentifier("settings.selection-sounds.preview")
                    Toggle(model.text("Selection Sounds", "Seçim Sesleri"), isOn: $model.selectionSoundsEnabled)
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                        .accessibilityHint(model.text("Play after confirming an operation, not while browsing its options.",
                                                      "Seçeneklere göz atarken değil, işlemi onayladıktan sonra çal."))
                        .accessibilityIdentifier("settings.selection-sounds")
                }
            }.background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
            settingsGroup(model.text("Output", "Çıktı")) {
                settingRow(model.text("Save Beside The Original", "Orijinalin Yanına Kaydet"), subtitle: model.text("Turn Off To Choose A Folder For Each Job.", "Her İşlemde Klasör Seçmek İçin Kapat.")) {
                    Toggle(model.text("Save Beside The Original", "Orijinalin Yanına Kaydet"), isOn: $model.outputAlongsideOriginal)
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                divider
                settingRow(model.text("When Finished", "Tamamlandığında"), subtitle: model.text("Choose How Results Appear.", "Sonuçların Nasıl Görüneceğini Seç.")) {
                    Picker(model.text("When Finished", "Tamamlandığında"), selection: $model.completionPresentation) {
                        Text(model.text("Stay Quiet", "Sessiz Kal")).tag(CompletionPresentation.quiet)
                        Text(model.text("Show In Finder", "Finder’da Göster")).tag(CompletionPresentation.finder)
                        Text(model.text("Show Result Card", "Sonuç Kartını Göster")).tag(CompletionPresentation.card)
                    }.labelsHidden().frame(width: 178).accessibilityIdentifier("settings.completion")
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(model.text("Format Support", "Biçim Desteği")).font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Button { model.engineRefresh += 1 } label: {
                        Label(model.text("Refresh", "Yenile"), systemImage: "arrow.clockwise")
                    }.buttonStyle(.plain).foregroundStyle(Palette.accent).font(.system(size: 12))
                }
                VStack(spacing: 0) {
                    ForEach(engines, id: \.0) { engine in
                        engineRow(engine)
                        if engine.0 != engines.last?.0 { divider }
                    }
                }.background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
                    .task(id: model.engineRefresh) {
                        engineReports = [:]
                        for engine in engines {
                            do {
                                let report = try await EngineHealth.inspect(engine.0)
                                try Task.checkCancellation()
                                engineReports[engine.0] = report
                            } catch { return }
                        }
                    }
            }
            DisclosureGroup(model.text("About Lemulip", "Lemulip Hakkında")) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Source Preview") · MIT License")
                    Text(model.text("Free And Open Source. Files Are Processed On This Mac. Only Your Preferences Are Saved.",
                                    "Ücretsiz Ve Açık Kaynak. Dosyalar Bu Mac’te İşlenir. Yalnızca Tercihlerin Kaydedilir."))
                    Text(model.text("Optional Document Support Downloads Only With Your Approval. AirDrop Shares Only When You Choose It.",
                                    "İsteğe Bağlı Belge Desteği Yalnızca Onayınla İndirilir. AirDrop Yalnızca Sen Seçtiğinde Paylaşır."))
                }.font(.system(size: 12)).foregroundStyle(Palette.muted).padding(.top, 8)
            }.font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.muted)
        }
    }

    private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 16, weight: .semibold))
            VStack(spacing: 0, content: content).background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func engineRow(_ engine: (String, String, String, String)) -> some View {
        let report = engineReports[engine.0]
        let ready = report?.state == .ready
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: ready ? "checkmark.circle.fill" : report?.state == .missing ? "plus.circle" : "circle.dotted")
                    .font(.system(size: 18)).foregroundStyle(ready ? Palette.accent : Palette.muted)
                Text(engineTitle(engine.0, fallback: engine.2)).font(.system(size: 13, weight: .medium))
                Spacer(minLength: 8)
                if engine.0 == "pandoc", report != nil, !ready {
                    PandocInstallButton(model: model, installed: ready)
                } else if let report {
                    Text(engineStatus(report)).font(.system(size: 12))
                        .foregroundStyle(ready ? Palette.accent : Palette.muted)
                } else {
                    Text(model.text("Checking…", "Kontrol Ediliyor…"))
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
            }
            if let report, report.state == .limited || report.state == .unusable {
                Text(report.detail).font(.system(size: 12)).foregroundStyle(Palette.muted).textSelection(.enabled)
            }
            DisclosureGroup(model.text("Details", "Ayrıntılar")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(engine.1 + (report?.version.map { " · " + $0 } ?? ""))
                        .font(.system(size: 12, weight: .medium))
                    if let path = EngineLocator.find(engine.0)?.path {
                        Text(path).font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled).lineLimit(2).truncationMode(.middle)
                    }
                    if engine.0 == "pandoc" {
                        Text(model.text("Official Package. Installed Only With Your Approval.", "Resmî Paket. Yalnızca Onayınla Kurulur."))
                    } else if report != nil && !ready {
                        Text(engine.3).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        Button(copied == engine.0 ? model.text("Copied", "Kopyalandı") : model.text("Copy Install Command", "Kurulum Komutunu Kopyala")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(engine.3, forType: .string)
                            copied = engine.0
                        }.buttonStyle(.plain).foregroundStyle(Palette.accent)
                        Link(model.text("Homebrew Instructions", "Homebrew Yönergeleri"), destination: URL(string: "https://brew.sh")!)
                    }
                }.font(.system(size: 12)).foregroundStyle(Palette.muted).padding(.top, 8)
            }.font(.system(size: 11)).foregroundStyle(Palette.muted)
        }.padding(16)
    }

    private func engineTitle(_ id: String, fallback: String) -> String {
        guard model.language == "tr" else { return fallback }
        return ["ffmpeg": "Video Ve Ses", "imagemagick": "Görseller", "pandoc": "Gelişmiş Belgeler", "libreoffice": "Office Belgeleri"][id] ?? fallback
    }

    private func engineStatus(_ report: EngineReport) -> String {
        switch report.state {
        case .ready: return model.text("Ready", "Hazır")
        case .limited: return model.text("Partial Support", "Kısmi Destek")
        case .unusable: return model.text("Needs Attention", "Kontrol Gerekli")
        case .missing: return model.text("Not Installed", "Kurulu Değil")
        }
    }

    private var appearanceSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.text("Appearance", "Görünüm")).font(.system(size: 16, weight: .semibold))
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

    private var divider: some View { Rectangle().fill(Palette.line.opacity(0.55)).frame(height: 1).padding(.horizontal, 16) }
    private func settingRow<Control: View>(_ title: String, subtitle: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) { Text(title).font(.system(size: 13, weight: .medium)); Text(subtitle).font(.system(size: 12)).foregroundStyle(Palette.muted) }
            Spacer(minLength: 16)
            control()
        }.padding(18)
    }
}
#endif
