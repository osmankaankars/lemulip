#if os(macOS)
import SwiftUI
import LemulipCore

struct PandocInstallButton: View {
    @ObservedObject var model: AppController
    let installed: Bool
    @State private var confirmation = false
    @State private var task: Task<Void, Never>?
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if task != nil {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Button(model.text("Cancel", "İptal")) { task?.cancel() }
                }
                Text(model.text("Downloading And Verifying", "İndiriliyor ve doğrulanıyor"))
                    .font(.system(size: 9)).foregroundStyle(Palette.muted)
            } else {
                Button(installed ? model.text("Ready", "Hazır") : model.text("Install", "Kur")) { confirmation = true }
                    .disabled(installed)
                    .foregroundStyle(Palette.accent).font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Palette.accent.opacity(0.07), in: Capsule()).buttonStyle(.plain)
            }
        }
        .alert(model.text("Install Document Engine?", "Belge motoru kurulsun mu?"), isPresented: $confirmation) {
            Button(model.text("Cancel", "Vazgeç"), role: .cancel) {}
            Button(model.text("Download And Install", "İndir ve kur")) { install() }
        } message: {
            Text(model.text("Downloads the official Pandoc package from GitHub into your Lemulip support folder. No administrator password or Terminal command. Your files are not uploaded.", "Resmî Pandoc paketi GitHub'dan Lemulip destek klasörüne indirilir. Yönetici parolası veya Terminal komutu gerekmez. Dosyaların yüklenmez."))
        }
        .alert(model.text("Installation Not Completed", "Kurulum tamamlanmadı"), isPresented: Binding(
            get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button(model.text("OK", "Tamam")) { failure = nil }
            } message: { Text(failure ?? "") }
        .onDisappear { task?.cancel() }
    }

    private func install() {
        guard task == nil else { return }
        task = Task { @MainActor in
            defer { task = nil }
            do {
                _ = try await EngineInstaller.shared.installPandoc()
                model.engineRefresh += 1
            } catch is CancellationError {
                // Cancellation is an expected user action, not an error alert.
            } catch let error as URLError where error.code == .cancelled {
            } catch LemulipError.cancelled {
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}
#endif
