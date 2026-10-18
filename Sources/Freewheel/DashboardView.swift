#if os(macOS)
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import FreewheelCore

struct DashboardView: View {
    @ObservedObject var model: AppController
    @State private var isTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar.padding(12)
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        if model.section == "settings" { SettingsContent(model: model) }
                        else if model.section == "activity" { ActivityContent(model: model) }
                        else { workspace }
                    }
                    .padding(32)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .background(Palette.background)
        .foregroundStyle(Palette.ink)
        .tint(Palette.accent)
        .frame(minWidth: 850, minHeight: 620)
        .sheet(item: $model.pendingOperation, onDismiss: { model.cancelPending() }) { operation in
            OperationOptionsView(model: model, operation: operation)
        }
        .alert(model.text("Lemulip", "Lemulip"), isPresented: Binding(get: { model.alertMessage != nil }, set: { if !$0 { model.alertMessage = nil } })) {
            Button(model.text("OK", "Tamam"), role: .cancel) { model.alertMessage = nil }
        } message: { Text(model.alertMessage ?? "") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                AppMark(size: 42)
                Text("Lemulip").font(.system(size: 20, weight: .semibold, design: .rounded)).tracking(-0.6)
            }.padding(.top, 40).padding(.bottom, 32)
            VStack(spacing: 7) {
                nav("workspace", "square.stack.3d.up", model.text("Workspace", "Çalışma alanı"))
                nav("activity", "clock.arrow.circlepath", model.text("Activity", "İşlemler"))
                nav("settings", "slider.horizontal.3", model.text("Settings", "Ayarlar"))
            }
            Spacer()
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 7) {
                    Circle().fill(model.wheelEnabled ? Palette.accent : Palette.muted).frame(width: 6, height: 6)
                    Text(model.text(model.wheelEnabled ? "Wheel is ready" : "Wheel is paused", model.wheelEnabled ? "Çark hazır" : "Çark duraklatıldı"))
                        .font(.system(size: 12, weight: .medium))
                }
                Text(model.text("Your Files.\nYour Mac. Your Control.", "Dosyaların.\nMac'in. Kontrol sende."))
                    .font(.system(size: 17, weight: .medium)).foregroundStyle(Palette.muted).lineSpacing(3)
                HStack(spacing: 5) {
                    Image(systemName: "lock.shield").font(.system(size: 10))
                    Text(model.text("Offline · Open Source", "ÇEVRİMDIŞI · AÇIK KAYNAK")).font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(0.4)
                }.foregroundStyle(Palette.muted)
            }.padding(.bottom, 28)
        }
        .padding(.horizontal, 22)
        .frame(width: 203)
        .navigationChrome(radius: 22)
    }

    private func nav(_ id: String, _ symbol: String, _ title: String) -> some View {
        Button {
            model.section = id
            if id == "settings" { model.engineRefresh += 1 }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: symbol).font(.system(size: 15)).frame(width: 19)
                Text(title).font(.system(size: 13, weight: model.section == id ? .semibold : .regular))
                Spacer()
                if id == "activity" && model.isBusy { ProgressView().controlSize(.mini) }
            }.foregroundStyle(model.section == id ? Palette.onLime : Palette.muted)
                .padding(.horizontal, 13).padding(.vertical, 12)
                .background(model.section == id ? Palette.lime : .clear, in: RoundedRectangle(cornerRadius: 11))
        }.buttonStyle(.plain)
    }

    private var topBar: some View {
        HStack {
            Text(model.section == "workspace" ? model.text("The Everyday File Tool", "GÜNLÜK DOSYA ARACIN") : model.section == "activity" ? model.text("This Session", "BU OTURUM") : model.text("Make It Yours", "KENDİNE GÖRE AYARLA"))
                .font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1.8).foregroundStyle(Palette.muted)
            Spacer()
            HStack(spacing: 6) { Image(systemName: "infinity"); Text(model.text("Free Forever", "Her zaman ücretsiz")) }
                .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.accent)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .overlay(Capsule().stroke(Palette.accent.opacity(0.2), lineWidth: 1))
        }.padding(.horizontal, 32).padding(.top, 36).padding(.bottom, 16)
    }

    private var workspace: some View {
        Group {
            VStack(alignment: .leading, spacing: 11) {
                Text(model.text("A Fresh Spin On Your Files.", "Dosyalarına taze bir dokunuş."))
                    .font(.system(size: 32, weight: .semibold)).tracking(-1.15)
                Text(model.text("Convert, refine, and move on. Everything happens on this Mac.", "Dönüştür, düzenle, devam et. Her işlem bu Mac'te gerçekleşir."))
                    .font(.system(size: 13)).foregroundStyle(Palette.muted)
            }
            if model.files.isEmpty { dropZone }
            else { selectedFiles; operationSection }
            if model.files.isEmpty { shortcutGuide }
            if let latest = model.activity.first { recentActivity(latest) }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 18) {
            AppMark(size: 112).padding(.top, 24)
            VStack(spacing: 7) {
                Text(model.text(isTargeted ? "Drop to Get Started" : "Drop Your Files Here", isTargeted ? "Başlamak için bırak" : "Dosyalarını buraya bırak"))
                    .font(.system(size: 19, weight: .medium))
                Text(model.text("Images, video, audio, documents, and more", "Görseller, video, ses, belgeler ve daha fazlası"))
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
            Button { model.chooseFiles() } label: {
                HStack(spacing: 8) { Image(systemName: "plus"); Text(model.text("Choose Files", "Dosya seç")); Text("⌘O").opacity(0.45) }
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.onLime)
                    .padding(.horizontal, 20).padding(.vertical, 12).background(Palette.lime, in: Capsule())
                    .overlay(Capsule().stroke(Palette.onLime.opacity(0.16), lineWidth: 1))
            }.buttonStyle(.plain).padding(.bottom, 27)
        }
        .frame(maxWidth: .infinity)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 24))
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 24).fill(LinearGradient(colors: [Palette.lime.opacity(isTargeted ? 0.28 : 0.10), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                .allowsHitTesting(false)
        }
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(isTargeted ? Palette.accent : Palette.line, style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: [6, 5])))
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isTargeted, perform: loadDrop)
    }

    private var selectedFiles: some View {
        VStack(spacing: 0) {
            HStack {
                Label(model.text("\(model.files.count) selected", "\(model.files.count) dosya seçildi"), systemImage: "doc.on.doc")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.muted)
                Spacer()
                Button(model.text("Add Files", "Dosya ekle")) { model.chooseFiles() }.buttonStyle(.plain).foregroundStyle(Palette.accent)
                Button(model.text("Clear", "Temizle")) { model.files = [] }.buttonStyle(.plain).foregroundStyle(Palette.muted).padding(.leading, 10)
            }.padding(16)
            Rectangle().fill(Palette.line).frame(height: 1)
            ForEach(Array(model.files.enumerated()), id: \.element) { index, url in
                HStack(spacing: 11) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(url.lastPathComponent).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Text(fileDetails(url)).font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1)
                    }
                    Spacer(minLength: 10)
                    if model.files.count > 1 {
                        Button { model.moveFile(index, by: -1) } label: { Image(systemName: "chevron.up") }.disabled(index == 0).help(model.text("Move Up", "Yukarı taşı"))
                        Button { model.moveFile(index, by: 1) } label: { Image(systemName: "chevron.down") }.disabled(index == model.files.count - 1).help(model.text("Move Down", "Aşağı taşı"))
                    }
                    Button { model.files.removeAll { $0 == url } } label: { Image(systemName: "xmark") }.help(model.text("Remove From Selection", "Seçimden çıkar"))
                }.buttonStyle(.plain).foregroundStyle(Palette.muted).padding(.horizontal, 16).padding(.vertical, 11)
            }
            if model.files.count > 1 {
                Text(model.text("The list order is used when merging files.", "Birleştirmede dosyaların bu sırası kullanılır."))
                    .font(.system(size: 10)).foregroundStyle(Palette.muted).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.bottom, 12)
            }
        }.background(Palette.panel, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Palette.line, lineWidth: 1))
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isTargeted, perform: loadDrop)
    }

    private var operationSection: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                HStack(spacing: 3) {
                    ForEach(WheelMode.allCases, id: \.self) { mode in
                        Button { model.mode = mode } label: {
                            HStack(spacing: 6) { Text(mode.keySymbol).foregroundStyle(Palette.muted); Text(modeTitle(mode)) }
                                .font(.system(size: 12, weight: .medium)).padding(.horizontal, 14).padding(.vertical, 8)
                                .background(model.mode == mode ? Palette.raised : .clear, in: RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(.plain)
                    }
                }.padding(5).navigationChrome(radius: 14)
                Spacer()
                Button { model.showWheel() } label: { Label(model.text("Open Wheel", "Çarkı aç"), systemImage: "circle.hexagongrid") }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.accent)
            }
            if model.operations.isEmpty {
                Text(model.text("Select files of the same type to convert them together. File actions work with any selection.", "Birlikte dönüştürmek için aynı türde dosyalar seç. Dosya işlemleri her seçimle çalışır."))
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).padding(.vertical, 16)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 138), spacing: 10)], spacing: 10) {
                    ForEach(model.operations) { operation in OperationCard(operation: operation, model: model) }
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield")
                Text(model.text("Conversions create new files. Originals stay untouched.", "Dönüşümler yeni dosya oluşturur. Orijinaller korunur."))
            }.font(.system(size: 10)).foregroundStyle(Palette.muted)
        }
    }

    private var shortcutGuide: some View {
        HStack(alignment: .top, spacing: 24) {
            ForEach(WheelMode.allCases, id: \.self) { mode in
                HStack(alignment: .top, spacing: 11) {
                    Text(mode.keySymbol).font(.system(size: 19, weight: .medium)).frame(width: 37, height: 37)
                        .background(Palette.raised, in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.line))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(modeTitle(mode)).font(.system(size: 12, weight: .semibold))
                        Text(model.text(mode == .convert ? "Make it a new format" : mode == .tools ? "Fine-tune the details" : "Get it where it belongs", mode == .convert ? "Biçimini değiştir" : mode == .tools ? "İnce ayarları yap" : "İstediğin yere taşı"))
                            .font(.system(size: 10)).foregroundStyle(Palette.muted)
                    }.padding(.top, 2)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .overlay(alignment: .bottomLeading) { EmptyView() }
        .padding(.bottom, 5)
        .accessibilityElement(children: .combine)
    }

    private func recentActivity(_ item: ActivityItem) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text(model.text("Latest Activity", "SON İŞLEM")).font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1.2).foregroundStyle(Palette.muted)
                Spacer()
                Button(model.text("View All", "Tümünü gör")) { model.section = "activity" }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.accent)
            }
            ActivityRow(item: item, model: model)
        }
    }

    private func modeTitle(_ mode: WheelMode) -> String {
        model.text(mode.title, mode == .convert ? "Dönüştür" : mode == .tools ? "Araçlar" : "İşlemler")
    }

    private func fileDetails(_ url: URL) -> String {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        return [url.pathExtension.uppercased(), size.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func loadDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        Task { @MainActor in
            var urls: [URL] = []
            for provider in providers {
                let url: URL? = await withCheckedContinuation { continuation in
                    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                        if let data = item as? Data { continuation.resume(returning: URL(dataRepresentation: data, relativeTo: nil)) }
                        else if let url = item as? URL { continuation.resume(returning: url) }
                        else { continuation.resume(returning: nil) }
                    }
                }
                if let url, url.isFileURL { urls.append(url) }
            }
            model.addFiles(urls)
        }
        return true
    }
}

struct OperationCard: View {
    let operation: FileOperation
    @ObservedObject var model: AppController
    @State private var hover = false
    private var missing: Bool { operation.dependency.map { !EngineLocator.isAvailable($0) } ?? false }
    var body: some View {
        Button { model.begin(operation) } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: operation.symbol).font(.system(size: 20, weight: .regular)).foregroundStyle(missing ? Palette.muted : Palette.accent)
                    Spacer()
                    Image(systemName: missing ? "plus.circle" : "arrow.up.right").font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(OperationNames.title(operation, language: model.language)).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
                    Text(missing ? model.text("Add \(operation.dependency ?? "engine")", "\(operation.dependency ?? "Motor") ekle") : OperationNames.detail(operation, language: model.language))
                        .font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(2).frame(height: 27, alignment: .topLeading)
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(hover ? Palette.raised : Palette.panel, in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(hover ? Palette.accent.opacity(0.5) : Palette.line, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 11))
        }.buttonStyle(.plain).onHover { hover = $0 }.help(operation.detail)
            .accessibilityLabel(OperationNames.title(operation, language: model.language))
    }
}

enum OperationNames {
    static func title(_ operation: FileOperation, language: String) -> String {
        guard language == "tr" else { return operation.title }
        return [
            "image.compress": "Sıkıştır", "image.resize": "Boyutlandır", "image.crop": "Kırp", "image.rotate": "Döndür", "image.flip": "Yansıt", "image.stripMetadata": "Meta veriyi temizle",
            "pdf.merge": "PDF birleştir", "pdf.split": "Sayfalara ayır", "pdf.extract": "Sayfa çıkar", "pdf.rotate": "Sayfaları döndür", "pdf.compress": "Sıkıştır", "pdf.ocr": "Metni tanı",
            "media.compress": "Sıkıştır", "media.trim": "Kes", "media.resize": "Boyutlandır", "media.mute": "Sesi kaldır", "media.extractAudio": "Sesi çıkar", "media.speed": "Hızı değiştir", "media.volume": "Ses düzeyi",
            "archive.extract": "Arşivi çıkar", "archive.createZip": "ZIP oluştur", "archive.createTar": "TAR oluştur", "archive.createGzip": "GZIP oluştur", "document.wordCount": "Kelime say",
            "action.airdrop": "AirDrop", "action.float": "Rafa bırak", "action.copy": "Kopyala…", "action.move": "Taşı…", "action.copyPath": "Yolu kopyala", "action.terminal": "Terminal"
        ][operation.id] ?? operation.title
    }
    static func detail(_ operation: FileOperation, language: String) -> String {
        guard language == "tr" else { return operation.detail }
        if let dependency = operation.dependency { return "Yerel \(dependency) motoru" }
        if operation.id.hasPrefix("convert.") { return operation.detail == "Every page · 300 DPI" ? "Her sayfa · 300 DPI" : "Bu Mac'te işlenir" }
        return [
            "image.compress": "Görsel kalitesini ayarla", "image.resize": "En boy oranını koru", "image.crop": "Merkezden belirli ölçüde kırp", "image.rotate": "90° adımlarla döndür", "image.flip": "Yatay olarak yansıt", "image.stripMetadata": "Temiz bir kopya oluştur",
            "pdf.merge": "Listedeki sırayla birleştir", "pdf.split": "Her sayfa için yeni bir PDF", "pdf.extract": "Sayfa ve aralık seç", "pdf.rotate": "Tüm sayfaları döndür", "pdf.compress": "Sayfaları görsele dönüştürür", "pdf.ocr": "Taranmış sayfaları çevrimdışı oku",
            "archive.extract": "Yeni bir klasöre çıkar", "archive.createZip": "Seçili dosyaları sıkıştır", "archive.createTar": "Seçili dosyaları paketle", "archive.createGzip": "Her dosyayı ayrı sıkıştır", "document.wordCount": "Kelimeleri yerel olarak say",
            "action.airdrop": "Yakındaki cihazlarla paylaş", "action.float": "Dosyaları yüzen rafta tut", "action.copy": "Hedef klasörü seç", "action.move": "Hedef klasörü seç", "action.copyPath": "Tam dosya yolunu kopyala", "action.terminal": "Bulunduğu klasörde aç"
        ][operation.id] ?? operation.detail
    }
}

struct FileShelfView: View {
    let urls: [URL]
    @ObservedObject var model: AppController
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.text("Drag a file from here into any app.", "Buradaki dosyaları başka bir uygulamaya sürükle."))
                .font(.system(size: 11)).foregroundStyle(Palette.muted)
            ScrollView {
                VStack(spacing: 7) {
                    ForEach(urls, id: \.self) { url in
                        HStack(spacing: 10) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 26, height: 26)
                            Text(url.lastPathComponent).font(.system(size: 12)).lineLimit(1)
                            Spacer()
                            Button { model.reveal([url]) } label: { Image(systemName: "arrow.up.right") }.buttonStyle(.plain)
                        }.padding(10).background(Palette.panel, in: RoundedRectangle(cornerRadius: 8))
                            .onDrag { NSItemProvider(object: url as NSURL) }
                    }
                }
            }
        }.padding(16).background(Palette.background)
    }
}
#endif
