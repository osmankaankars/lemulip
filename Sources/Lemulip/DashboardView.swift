#if os(macOS)
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import LemulipCore

struct DashboardView: View {
    @ObservedObject var model: AppController
    @State private var isTargeted = false
    @State private var showsShortcuts = false

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                SidebarNavigation(model: model, compact: geometry.size.width < 880)
                Rectangle().fill(Palette.line.opacity(0.55)).frame(width: 1)
                VStack(spacing: 0) {
                    mainToolbar
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            if model.section == "settings" { SettingsContent(model: model) }
                            else if model.section == "activity" { ActivityContent(model: model) }
                            else { workspace }
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .background(Palette.background)
        .foregroundStyle(Palette.ink)
        .tint(Palette.accent)
        .frame(minWidth: 720, minHeight: 560)
        .sheet(item: $model.pendingOperation, onDismiss: { model.cancelPending() }) { operation in
            if operation.id == "image.crop" {
                ImageCropView(model: model, inputs: model.pendingInputURLs)
            } else if operation.id == "media.crop" {
                VideoCropView(model: model, inputs: model.pendingInputURLs)
            } else if operation.id == "pdf.organize" {
                PDFOrganizeView(model: model, inputs: model.pendingInputURLs)
            } else if operation.id == "pdf.merge" {
                PDFMergeView(model: model, inputs: model.pendingInputURLs)
            } else if operation.id == "media.trim",
                      !model.pendingInputURLs.isEmpty,
                      model.pendingInputURLs.allSatisfy({ FileFamily.detect($0) == .audio }) {
                AudioTrimView(model: model, inputs: model.pendingInputURLs)
            } else if operation.id == "media.trim" {
                VideoTrimView(model: model, inputs: model.pendingInputURLs)
            } else {
                OperationOptionsView(model: model, operation: operation)
            }
        }
        .alert(model.text("Lemulip", "Lemulip"), isPresented: Binding(get: { model.alertMessage != nil }, set: { if !$0 { model.alertMessage = nil } })) {
            Button(model.text("OK", "Tamam"), role: .cancel) { model.alertMessage = nil }
        } message: { Text(model.alertMessage ?? "") }
    }

    private var mainToolbar: some View {
        HStack(spacing: 12) {
            Text(model.section == "settings" ? model.text("Settings", "Ayarlar") :
                 model.section == "activity" ? model.text("Activity", "İşlemler") : model.text("Workspace", "Çalışma Alanı"))
                .font(.system(size: 22, weight: .semibold)).tracking(-0.5)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 12)
            if model.section == "workspace" {
                if !model.files.isEmpty {
                    Button { model.chooseFiles() } label: {
                        Label(model.text("Add Files", "Dosya Ekle"), systemImage: "plus")
                    }.accessibilityIdentifier("workspace.add-files")
                }
                Button { showsShortcuts.toggle() } label: {
                    Image(systemName: "questionmark.circle").font(.system(size: 16))
                }.buttonStyle(.plain).foregroundStyle(Palette.muted)
                    .accessibilityLabel(model.text("Keyboard Shortcuts", "Klavye Kısayolları"))
                    .help(model.text("Keyboard Shortcuts", "Klavye Kısayolları"))
                    .popover(isPresented: $showsShortcuts, arrowEdge: .bottom) {
                        ShortcutHelp(model: model).padding(20).frame(width: 310)
                    }
            }
        }
        .padding(.horizontal, 24).padding(.top, 36).padding(.bottom, 14)
        .background(Palette.background)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.line.opacity(0.55)).frame(height: 1) }
    }

    private var workspace: some View {
        Group {
            if model.files.isEmpty {
                dropZone
                shortcutGuide
            } else {
                selectedFiles
                operationSection
            }
            if let latest = model.activity.first { recentActivity(latest) }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 16) {
            AppMark(size: 56)
            VStack(spacing: 7) {
                Text(model.text(isTargeted ? "Drop To Get Started" : "Drop Your Files Here",
                                isTargeted ? "Başlamak İçin Bırak" : "Dosyalarını Buraya Bırak"))
                    .font(.system(size: 22, weight: .semibold)).tracking(-0.5)
                Text(model.text("Images, Video, Audio, Documents And More", "Görsel, Video, Ses, Belge Ve Daha Fazlası"))
                    .font(.system(size: 13)).foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
            }
            Button { model.chooseFiles() } label: {
                HStack(spacing: 12) {
                    Label(model.text("Choose Files", "Dosya Seç"), systemImage: "plus")
                    Text("⌘O").font(.system(size: 12, design: .monospaced)).opacity(0.7)
                }.padding(.horizontal, 6).padding(.vertical, 3)
            }
            .buttonStyle(.borderedProminent).tint(Palette.primaryAction).foregroundStyle(Palette.onPrimary)
            .controlSize(.large).accessibilityIdentifier("workspace.choose-files")
        }
        .padding(.horizontal, 24).padding(.vertical, 34)
        .frame(maxWidth: .infinity)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .strokeBorder(isTargeted ? Palette.accent : Palette.line,
                          style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: [5, 5])))
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isTargeted, perform: loadDrop)
    }

    private var selectedFiles: some View {
        VStack(spacing: 0) {
            HStack {
                Label(model.text("\(model.files.count) Selected", "\(model.files.count) Dosya Seçildi"), systemImage: "doc.on.doc")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Button(model.text("Clear", "Temizle")) { model.files = [] }
                    .buttonStyle(.plain).foregroundStyle(Palette.muted)
            }.padding(.bottom, 12)
            ForEach(Array(model.files.enumerated()), id: \.element) { index, url in
                HStack(spacing: 12) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable().frame(width: 32, height: 32).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(url.lastPathComponent).font(.system(size: 13, weight: .medium))
                            .lineLimit(1).truncationMode(.middle).help(url.lastPathComponent)
                        Text(fileDetails(url)).font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if model.files.count > 1 {
                        Button { model.moveFile(index, by: -1) } label: { Image(systemName: "chevron.up") }
                            .disabled(index == 0).help(model.text("Move Up", "Yukarı Taşı"))
                            .accessibilityLabel(model.text("Move Up", "Yukarı Taşı"))
                        Button { model.moveFile(index, by: 1) } label: { Image(systemName: "chevron.down") }
                            .disabled(index == model.files.count - 1).help(model.text("Move Down", "Aşağı Taşı"))
                            .accessibilityLabel(model.text("Move Down", "Aşağı Taşı"))
                    }
                    Button { model.files.removeAll { $0 == url } } label: { Image(systemName: "xmark.circle") }
                        .help(model.text("Remove From Selection", "Seçimden Çıkar"))
                        .accessibilityLabel(model.text("Remove \(url.lastPathComponent)", "\(url.lastPathComponent) Dosyasını Çıkar"))
                }
                .buttonStyle(.plain).foregroundStyle(Palette.ink)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Palette.panel, in: RoundedRectangle(cornerRadius: 10))
                .padding(.bottom, 6)
            }
            if model.files.count > 1 {
                Text(model.text("Files Merge In This Order.", "Dosyalar Bu Sırayla Birleştirilir."))
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 5)
            }
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isTargeted, perform: loadDrop)
    }

    private var operationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Picker(model.text("Action Group", "İşlem Grubu"), selection: $model.mode) {
                    ForEach(WheelMode.allCases, id: \.self) { mode in
                        Text("\(mode.keySymbol) \(modeTitle(mode))").tag(mode)
                    }
                }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 350)
                Spacer(minLength: 8)
                Button { model.showWheel() } label: {
                    Image(systemName: "circle.hexagongrid").font(.system(size: 18))
                }.buttonStyle(.plain).foregroundStyle(Palette.accent)
                    .help(model.text("Open Wheel", "Çarkı Aç"))
                    .accessibilityLabel(model.text("Open Wheel", "Çarkı Aç"))
            }
            if model.operations.isEmpty {
                Text(model.text("Choose Files Of The Same Type For A Conversion. Actions Work With Any Selection.",
                                "Birlikte Dönüştürmek İçin Aynı Türde Dosyalar Seç. İşlemler Her Seçimle Çalışır."))
                    .font(.system(size: 13)).foregroundStyle(Palette.muted).padding(.vertical, 16)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(model.operations) { operation in OperationCard(operation: operation, model: model) }
                }
            }
        }
    }

    private var shortcutGuide: some View {
        HStack(spacing: 10) {
            ForEach(WheelMode.allCases, id: \.self) { mode in
                VStack(alignment: .leading, spacing: 10) {
                    Text(mode.keySymbol).font(.system(size: 22, weight: .medium))
                    Text(modeTitle(mode)).font(.system(size: 13, weight: .semibold))
                }.foregroundStyle(Palette.ink)
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.shortcutFill(mode), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityElement(children: .combine)
            }
        }
    }

    private func recentActivity(_ item: ActivityItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(model.text("Latest Activity", "Son İşlem")).font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(model.text("View All", "Tümünü Gör")) { model.section = "activity" }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.accent)
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
            "pdf.organize": "PDF düzenle", "pdf.merge": "PDF birleştir", "pdf.split": "Sayfalara ayır", "pdf.extract": "Sayfa çıkar", "pdf.rotate": "Sayfaları döndür", "pdf.compress": "Sıkıştır", "pdf.ocr": "Metni tanı",
            "media.compress": "Sıkıştır", "media.trim": "Kes", "media.crop": "Kadrajı kırp", "media.resize": "Boyutlandır", "media.mute": "Sesi kaldır", "media.extractAudio": "Sesi çıkar", "media.speed": "Hızı değiştir", "media.volume": "Ses düzeyi",
            "archive.extract": "Arşivi çıkar", "archive.createZip": "ZIP oluştur", "archive.createTar": "TAR oluştur", "archive.createGzip": "GZIP oluştur", "document.wordCount": "Kelime say",
            "action.airdrop": "AirDrop", "action.float": "Rafa bırak", "action.copy": "Kopyala…", "action.move": "Taşı…", "action.copyPath": "Yolu kopyala", "action.terminal": "Terminal"
        ][operation.id] ?? operation.title
    }
    static func detail(_ operation: FileOperation, language: String) -> String {
        guard language == "tr" else { return operation.detail }
        if let dependency = operation.dependency { return "Yerel \(dependency) motoru" }
        if operation.id == "convert.xlsx" { return "Microsoft Excel · Metin hücreleri" }
        if operation.id == "convert.docx" {
            return operation.detail == "Microsoft Word Document · Basic Formatting"
                ? "Microsoft Word · Temel biçimlendirme" : "Microsoft Word · Düz metin"
        }
        if operation.id.hasPrefix("convert.") { return operation.detail == "Every page · 300 DPI" ? "Her sayfa · 300 DPI" : "Bu Mac'te işlenir" }
        return [
            "image.compress": "Görsel kalitesini ayarla", "image.resize": "En boy oranını koru", "image.crop": "Koruyacağın alanı seç", "image.rotate": "90° adımlarla döndür", "image.flip": "Yatay olarak yansıt", "image.stripMetadata": "Temiz bir kopya oluştur",
            "media.trim": "Aralığı görerek ve oynatarak seç",
            "media.crop": "Videoda koruyacağın alanı seç",
            "pdf.organize": "Sayfaları gör, sırala ve düzenle", "pdf.merge": "Dosyaları önizle ve sırala", "pdf.split": "Her sayfa için yeni bir PDF", "pdf.extract": "Sayfa ve aralık seç", "pdf.rotate": "Tüm sayfaları döndür", "pdf.compress": "Sayfaları görsele dönüştürür", "pdf.ocr": "Taranmış sayfaları çevrimdışı oku",
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
                            Button { model.reveal([url]) } label: { Image(systemName: "arrow.up.right") }
                                .buttonStyle(.plain)
                                .accessibilityLabel(model.text("Show \(url.lastPathComponent) in Finder", "\(url.lastPathComponent) dosyasını Finder'da göster"))
                                .help(model.text("Show in Finder", "Finder'da göster"))
                        }.padding(10).background(Palette.panel, in: RoundedRectangle(cornerRadius: 8))
                            .onDrag { NSItemProvider(object: url as NSURL) }
                    }
                }
            }
        }.padding(16).background(Palette.background)
    }
}
#endif
