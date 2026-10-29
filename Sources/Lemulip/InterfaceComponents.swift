#if os(macOS)
import AppKit
import SwiftUI
import LemulipCore

struct SidebarNavigation: View {
    @ObservedObject var model: AppController
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                AppMark(size: 30)
                if !compact { AppWordmark(size: 18) }
            }.padding(.horizontal, 10).padding(.top, 39).padding(.bottom, 24)
            item("workspace", "square.stack.3d.up", model.text("Workspace", "Çalışma Alanı"))
            item("activity", "clock.arrow.circlepath", model.text("Activity", "İşlemler"))
            Spacer(minLength: 20)
            HStack(spacing: 7) {
                Circle().fill(model.wheelEnabled ? Palette.accent : Palette.muted).frame(width: 6, height: 6)
                if !compact {
                    Text(model.text(model.wheelEnabled ? "Wheel Ready" : "Wheel Paused",
                                    model.wheelEnabled ? "Çark Hazır" : "Çark Duraklatıldı"))
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
            }.padding(.horizontal, compact ? 22 : 12).padding(.bottom, 8)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(model.text(model.wheelEnabled ? "Wheel Ready" : "Wheel Paused",
                                               model.wheelEnabled ? "Çark Hazır" : "Çark Duraklatıldı"))
            item("settings", "slider.horizontal.3", model.text("Settings", "Ayarlar"))
        }
        .padding(.horizontal, 10).padding(.bottom, 16)
        .frame(width: compact ? 68 : 188)
        .background(Palette.panel.opacity(0.55))
    }

    private func item(_ id: String, _ symbol: String, _ title: String) -> some View {
        Button {
            model.section = id
            if id == "settings" { model.engineRefresh += 1 }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 16)).frame(width: 22)
                if !compact {
                    Text(title).font(.system(size: 13, weight: model.section == id ? .semibold : .regular))
                    Spacer(minLength: 0)
                    if id == "activity" && model.isBusy { ProgressView().controlSize(.mini) }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
            .foregroundStyle(model.section == id ? Palette.ink : Palette.muted)
            .background(model.section == id ? Palette.raised : .clear, in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain).help(title).accessibilityLabel(title)
        .accessibilityValue(model.section == id ? model.text("Selected", "Seçili") : "")
        .accessibilityIdentifier("navigation.\(id)")
    }
}

struct ShortcutHelp: View {
    @ObservedObject var model: AppController
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.text("Drag A File. Tap A Key.", "Dosyayı Sürükle. Bir Tuşa Dokun."))
                .font(.system(size: 17, weight: .semibold)).accessibilityAddTraits(.isHeader)
            ForEach(WheelMode.allCases, id: \.self) { mode in
                HStack(spacing: 12) {
                    Text(mode.keySymbol).font(.system(size: 19, weight: .medium))
                        .frame(width: 35, height: 32)
                        .background(Palette.shortcutFill(mode), in: RoundedRectangle(cornerRadius: 7))
                    Text(model.text(mode.title, mode == .convert ? "Dönüştür" : mode == .tools ? "Araçlar" : "İşlemler"))
                        .font(.system(size: 13))
                }
            }
            Text(model.text("Drop On An Action To Begin. Escape Cancels.", "Başlatmak İçin İşlemin Üzerine Bırak. Escape İptal Eder."))
                .font(.system(size: 12)).foregroundStyle(Palette.muted)
            Button(model.text("Try With A Sample", "Örnek Dosyayla Dene")) { model.tryPracticeFile() }
                .buttonStyle(.borderedProminent).tint(Palette.primaryAction).foregroundStyle(Palette.onPrimary)
                .accessibilityIdentifier("help.practice")
            Text(model.text("Opens A Practice Image In Finder. Your Files Stay As They Are.", "Finder’da Bir Örnek Görsel Açılır. Dosyaların Değişmez."))
                .font(.system(size: 11)).foregroundStyle(Palette.muted)
        }.foregroundStyle(Palette.ink)
    }
}

/// Shared editor actions keep keyboard behavior and validation at every call site.
struct EditorFooter: View {
    let language: String
    var isEnabled: Bool
    var cancelShortcut: KeyboardShortcut? = .cancelAction
    let onCancel: () -> Void
    let onSubmit: () -> Void
    private func text(_ en: String, _ tr: String) -> String { language == "tr" ? tr : en }

    var body: some View {
        HStack(spacing: 12) {
            Label(text("Original Kept", "Orijinal Korunur"), systemImage: "checkmark.shield")
                .font(.system(size: 12)).foregroundStyle(Palette.muted)
            Spacer(minLength: 12)
            Button(text("Cancel", "Vazgeç"), action: onCancel)
                .keyboardShortcut(cancelShortcut).controlSize(.large)
            Button(text("Create Copy", "Kopya Oluştur"), action: onSubmit)
                .buttonStyle(.borderedProminent).tint(Palette.primaryAction).foregroundStyle(Palette.onPrimary)
                .controlSize(.large).keyboardShortcut(.defaultAction).disabled(!isEnabled)
                .accessibilityIdentifier("editor.create-copy")
        }.padding(.horizontal, 24).padding(.vertical, 16)
            .background(Palette.panel.opacity(0.6))
    }
}

struct EditorHelp: View {
    let language: String
    let explanation: String
    var body: some View {
        DisclosureGroup(language == "tr" ? "Klavye Ve İpuçları" : "Keyboard & Tips") {
            Text(explanation).font(.system(size: 12)).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
        }.font(.system(size: 12)).foregroundStyle(Palette.muted)
    }
}

struct OutputActions: View {
    let urls: [URL]
    @ObservedObject var model: AppController
    var body: some View {
        HStack(spacing: 14) {
            Button { model.reveal(urls) } label: {
                Label(model.text("Show In Finder", "Finder’da Göster"), systemImage: "folder")
            }
            Button { model.copyOutputs(urls) } label: {
                Label(model.text("Copy", "Kopyala"), systemImage: "doc.on.doc")
            }
            Button { model.showShelf(urls) } label: {
                Label(model.text("Float", "Rafa Bırak"), systemImage: "rectangle.on.rectangle")
            }
        }
        .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.accent)
        .disabled(urls.isEmpty)
    }
}
#endif
