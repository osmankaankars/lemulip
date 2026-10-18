#if os(macOS)
import AppKit
import SwiftUI
import FreewheelCore

struct ActivityContent: View {
    @ObservedObject var model: AppController
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(model.text("A Little Less Busywork.", "Biraz daha az uğraş."))
                        .font(.system(size: 30, weight: .semibold)).tracking(-0.9)
                    Text(model.text("Progress and results from this session. History is kept in memory only.", "Bu oturumdaki işlemler ve sonuçları. Geçmiş yalnızca bellekte tutulur."))
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Button(model.text("Clear Finished", "Bitenleri temizle")) { model.clearActivity() }.buttonStyle(.plain).foregroundStyle(Palette.mint).font(.system(size: 12))
            }
            if model.activity.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 36, weight: .light)).foregroundStyle(Palette.mint)
                    Text(model.text("Your Next Conversion Starts Here.", "Bir sonraki dönüşümün burada görünecek.")).font(.system(size: 15, weight: .medium))
                    Button(model.text("Choose Files", "Dosya seç")) { model.chooseFiles() }.buttonStyle(.borderedProminent).tint(Palette.mint).foregroundStyle(Palette.background)
                }.frame(maxWidth: .infinity).padding(.vertical, 65).background(Palette.panel, in: RoundedRectangle(cornerRadius: 16))
            } else {
                HStack(spacing: 18) {
                    stat("\(model.completedCount)", model.text("Completed", "Tamamlandı"))
                    stat("\(model.activity.filter { $0.state == .running || $0.state == .waiting }.count)", model.text("In Progress", "Devam ediyor"))
                    stat("0", model.text("Files Uploaded", "Yüklenen dosya"))
                }
                LazyVStack(spacing: 10) { ForEach(model.activity) { ActivityRow(item: $0, model: model) } }
            }
        }
    }
    private func stat(_ number: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(number).font(.system(size: 29, weight: .medium, design: .rounded)).foregroundStyle(Palette.mint)
            Text(label).font(.system(size: 11)).foregroundStyle(Palette.muted)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ActivityRow: View {
    let item: ActivityItem
    @ObservedObject var model: AppController
    private var active: Bool { item.state == .running || item.state == .waiting }
    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(Palette.raised).frame(width: 39, height: 39)
                if item.state == .running { ProgressView().controlSize(.small) }
                else { Image(systemName: item.state == .succeeded ? "checkmark" : item.state == .failed ? "exclamationmark" : item.state == .cancelled ? "xmark" : "clock").foregroundStyle(item.state == .failed ? .orange : Palette.mint) }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(OperationNames.title(item.operation, language: model.language)).font(.system(size: 12, weight: .semibold))
                    Text("·").foregroundStyle(Palette.muted)
                    Text(item.inputs.count == 1 ? item.inputs[0].lastPathComponent : model.text("\(item.inputs.count) files", "\(item.inputs.count) dosya"))
                        .font(.system(size: 12)).foregroundStyle(Palette.muted).lineLimit(1)
                }
                Text(statusText).font(.system(size: 11)).foregroundStyle(item.state == .failed ? .orange : Palette.muted).textSelection(.enabled)
                if !item.message.isEmpty { Text(item.message).font(.system(size: 11)).foregroundStyle(Palette.muted).textSelection(.enabled) }
                if !item.outputs.isEmpty {
                    ForEach(item.outputs.prefix(4), id: \.self) { url in
                        Button { model.reveal([url]) } label: {
                            Label(url.lastPathComponent, systemImage: "doc").font(.system(size: 10)).foregroundStyle(Palette.mint).lineLimit(1)
                        }.buttonStyle(.plain)
                    }
                    if item.outputs.count > 4 { Text(model.text("+ \(item.outputs.count - 4) more", "+ \(item.outputs.count - 4) dosya daha")).font(.system(size: 10)).foregroundStyle(Palette.muted) }
                }
            }.padding(.top, 3)
            Spacer(minLength: 4)
            if active && !item.operation.id.hasPrefix("action.") {
                Button { model.cancelJob(item.id) } label: { Image(systemName: "xmark.circle").foregroundStyle(Palette.muted) }
                    .buttonStyle(.plain).help(model.text("Cancel", "İptal et"))
            } else if item.state == .succeeded && !item.outputs.isEmpty {
                Button { model.reveal(item.outputs) } label: { Image(systemName: "folder").foregroundStyle(Palette.mint) }
                    .buttonStyle(.plain).help(model.text("Show in Finder", "Finder'da göster"))
            }
        }.padding(17).background(Palette.panel, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line, lineWidth: 1))
    }
    private var statusText: String {
        switch item.state {
        case .waiting: return model.text("Queued", "Sırada")
        case .running: return model.text("Processing locally…", "Bu Mac'te işleniyor…")
        case .succeeded: return model.text("Finished · \(item.outputs.count) output files", "Tamamlandı · \(item.outputs.count) çıktı dosyası")
        case .failed: return model.text("Could not complete", "Tamamlanamadı")
        case .cancelled: return model.text("Cancelled", "İptal edildi")
        }
    }
}
#endif
