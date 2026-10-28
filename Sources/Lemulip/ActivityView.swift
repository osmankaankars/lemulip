#if os(macOS)
import AppKit
import SwiftUI
import LemulipCore

struct ActivityContent: View {
    @ObservedObject var model: AppController
    private var activeCount: Int { model.activity.filter { $0.state == .running || $0.state == .waiting }.count }
    private var failedCount: Int { model.activity.filter { $0.state == .failed }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if model.activity.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "checkmark.circle").font(.system(size: 30, weight: .light)).foregroundStyle(Palette.muted)
                    Text(model.text("Your Results Appear Here", "Sonuçların Burada Görünür"))
                        .font(.system(size: 18, weight: .semibold))
                    Text(model.text("Choose A File To Get Started.", "Başlamak İçin Bir Dosya Seç."))
                        .font(.system(size: 13)).foregroundStyle(Palette.muted)
                    Button(model.text("Choose Files", "Dosya Seç")) { model.chooseFiles() }
                        .buttonStyle(.borderedProminent).tint(Palette.primaryAction).foregroundStyle(Palette.onPrimary)
                }.frame(maxWidth: .infinity).padding(.vertical, 54)
            } else {
                HStack(spacing: 12) {
                    Text(model.text("\(model.completedCount) Completed", "\(model.completedCount) Tamamlandı"))
                    if activeCount > 0 {
                        Text("·").accessibilityHidden(true)
                        Text(model.text("\(activeCount) Processing", "\(activeCount) İşleniyor"))
                    }
                    if failedCount > 0 {
                        Text("·").accessibilityHidden(true)
                        Text(model.text("\(failedCount) Needs Attention", "\(failedCount) Kontrol Bekliyor"))
                    }
                    Spacer(minLength: 8)
                    Button(model.text("Clear Finished", "Bitenleri Temizle")) { model.clearActivity() }
                        .buttonStyle(.plain).foregroundStyle(Palette.accent)
                }.font(.system(size: 12)).foregroundStyle(Palette.muted)
                LazyVStack(spacing: 10) {
                    ForEach(model.activity) { ActivityRow(item: $0, model: model) }
                }
            }
        }
    }
}

struct ActivityRow: View {
    let item: ActivityItem
    @ObservedObject var model: AppController
    private var active: Bool { item.state == .running || item.state == .waiting }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            statusIcon
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.inputs.count == 1 ? item.inputs[0].lastPathComponent : model.text("\(item.inputs.count) Files", "\(item.inputs.count) Dosya"))
                        .font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(OperationNames.title(item.operation, language: model.language))
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted)
                }
                HStack(spacing: 7) {
                    if item.state == .succeeded { Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.accent) }
                    Text(statusText).textSelection(.enabled)
                }.font(.system(size: 12)).foregroundStyle(item.state == .failed ? .orange : Palette.muted)
                if item.state == .running, let progress = item.progress {
                    if let fraction = progress.fractionCompleted, progress.phase == .converting {
                        HStack(spacing: 12) {
                            ProgressView(value: fraction).tint(Palette.accent)
                                .accessibilityLabel(model.text("Conversion Progress", "Dönüşüm İlerlemesi"))
                            Text("\(Int(fraction * 100))%")
                                .font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted)
                        }
                    }
                    if progress.phase == .converting && progress.totalFiles > 1 {
                        Text(model.text("\(progress.completedFiles) / \(progress.totalFiles) Files Processed", "\(progress.completedFiles) / \(progress.totalFiles) Dosya İşlendi"))
                            .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }
                }
                if !item.message.isEmpty {
                    DisclosureGroup(model.text("Details", "Ayrıntılar")) {
                        Text(item.message).font(.system(size: 12)).foregroundStyle(Palette.muted)
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                    }.font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                if !item.outputs.isEmpty {
                    ForEach(item.outputs.prefix(4), id: \.self) { url in
                        Button { model.reveal([url]) } label: {
                            Label(url.lastPathComponent, systemImage: "doc")
                                .font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                        }.buttonStyle(.plain).foregroundStyle(Palette.accent)
                            .help(url.lastPathComponent)
                            .onDrag { NSItemProvider(object: url as NSURL) }
                    }
                    if item.outputs.count > 4 {
                        Text(model.text("+ \(item.outputs.count - 4) More Files", "+ \(item.outputs.count - 4) Dosya Daha"))
                            .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }
                    OutputActions(urls: item.outputs, model: model).padding(.top, 4)
                }
            }
            if active && !item.operation.id.hasPrefix("action.") {
                Button { model.cancelJob(item.id) } label: { Image(systemName: "xmark.circle") }
                    .buttonStyle(.plain).foregroundStyle(Palette.muted)
                    .help(model.text("Cancel", "İptal Et"))
                    .accessibilityLabel(model.text("Cancel Conversion", "Dönüşümü İptal Et"))
            } else if model.canRetry(item) {
                Button { model.retryJob(item.id) } label: {
                    Label(model.text("Retry", "Tekrar Dene"), systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                }.buttonStyle(.plain).foregroundStyle(Palette.accent)
                    .help(model.text("Retry With The Same Settings", "Aynı Ayarlarla Tekrar Dene"))
            }
        }.padding(16).background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private var statusIcon: some View {
        if item.state == .running {
            ProgressView().controlSize(.small).frame(width: 34, height: 34)
        } else if let url = item.outputs.first ?? item.inputs.first {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
                .frame(width: 34, height: 34).accessibilityHidden(true)
        } else {
            Image(systemName: "doc").font(.system(size: 24)).foregroundStyle(Palette.muted)
                .frame(width: 34, height: 34).accessibilityHidden(true)
        }
    }

    private var statusText: String {
        switch item.state {
        case .waiting: return model.text("Queued", "Sırada")
        case .running:
            if item.progress?.phase == .preparing { return model.text("Preparing…", "Hazırlanıyor…") }
            if item.progress?.phase == .publishing || item.progress?.phase == .finished { return model.text("Saving New Files…", "Yeni Dosyalar Kaydediliyor…") }
            return model.text("Processing…", "İşleniyor…")
        case .succeeded: return model.text("Completed · \(item.outputs.count) \(item.outputs.count == 1 ? "New File" : "New Files")", "Tamamlandı · \(item.outputs.count) Yeni Dosya")
        case .failed: return model.text("Could Not Complete", "Tamamlanamadı")
        case .cancelled: return model.text("Cancelled", "İptal Edildi")
        }
    }
}
#endif
