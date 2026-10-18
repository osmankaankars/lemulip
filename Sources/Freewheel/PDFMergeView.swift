#if os(macOS)
import AppKit
import SwiftUI
import FreewheelCore

@MainActor
struct PDFMergeView: View {
    @ObservedObject var model: AppController
    let inputs: [URL]
    @StateObject private var editor = PDFMergeEditor()
    @FocusState private var listFocused: Bool
    private let rowHeight: CGFloat = 100

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 24).padding(.vertical, 19)
            separator
            if editor.isReady {
                editToolbar.padding(.horizontal, 24).padding(.vertical, 12)
                mergeSummary.padding(.horizontal, 24).padding(.bottom, 12)
                documentList
            } else {
                loadingState.frame(maxWidth: .infinity, maxHeight: .infinity).padding(40)
            }
            separator
            footer.padding(.horizontal, 24).padding(.vertical, 16)
        }
        .frame(width: 820, height: 660)
        .background(Palette.background).foregroundStyle(Palette.ink).tint(Palette.accent)
        .task(id: inputs) { await openDocuments() }
        .onDisappear { editor.close() }
    }

    private var separator: some View { Rectangle().fill(Palette.line).frame(height: 1) }

    private var header: some View {
        HStack(spacing: 13) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 25)).foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 5) {
                Text(model.text("Merge PDF", "PDF birleştir"))
                    .font(.system(size: 23, weight: .semibold)).tracking(-0.5)
                Text(model.text("Arrange Your Files Into One PDF", "Dosyalarını tek bir PDF olarak sırala"))
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 16)
            HStack(spacing: 8) {
                Button { editor.undo() } label: { Label(model.text("Undo", "Geri al"), systemImage: "arrow.uturn.backward") }
                    .keyboardShortcut("z", modifiers: .command).disabled(!editor.canUndo)
                Button { editor.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!editor.canRedo)
                    .accessibilityLabel(model.text("Redo", "Yinele"))
                    .help(model.text("Redo (⇧⌘Z)", "Yinele (⇧⌘Z)"))
                Button(model.text("Reset", "Sıfırla")) { editor.reset() }.disabled(!editor.canReset)
                    .help(model.text("Restore Every File in Its Original Order", "Tüm dosyaları orijinal sırayla geri getir"))
            }.font(.system(size: 11))
        }
    }

    private var editToolbar: some View {
        HStack(spacing: 8) {
            Button { editor.moveSelection(by: -1) } label: {
                Label(model.text("Move Earlier", "Öne taşı"), systemImage: "arrow.up")
            }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            .disabled(!editor.canMoveEarlier)
            .help(model.text("Move Earlier (⌥⌘↑)", "Öne taşı (⌥⌘↑)"))
            Button { editor.moveSelection(by: 1) } label: {
                Label(model.text("Move Later", "Arkaya taşı"), systemImage: "arrow.down")
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            .disabled(!editor.canMoveLater)
            .help(model.text("Move Later (⌥⌘↓)", "Arkaya taşı (⌥⌘↓)"))
            Divider().frame(height: 20).padding(.horizontal, 3)
            Button { editor.removeSelection() } label: {
                Label(model.text("Remove", "Çıkar"), systemImage: "minus.circle")
            }
            .disabled(!editor.canRemove)
            .help(model.text("Remove From the Copy (Delete)", "Kopyadan çıkar (Delete)"))
            Spacer(minLength: 10)
            Button(model.text("Select All", "Tümünü seç")) { editor.selectAll(); listFocused = true }
                .keyboardShortcut("a", modifiers: .command).disabled(editor.documents.isEmpty)
        }.font(.system(size: 11)).controlSize(.small)
    }

    private var mergeSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Label(model.text("\(editor.documents.count) PDFs", "\(editor.documents.count) PDF"), systemImage: "doc.on.doc")
                    .font(.system(size: 12, weight: .semibold))
                Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(Palette.muted)
                Text(model.text("\(editor.pageCount) Pages in Your Copy", "Kopyanda \(editor.pageCount) sayfa"))
                    .font(.system(size: 12, weight: .semibold))
                Text(model.text("\(editor.selectedDocuments.count) Selected", "\(editor.selectedDocuments.count) seçili"))
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.accent)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Palette.accent.opacity(0.09), in: Capsule())
                Spacer(minLength: 4)
            }
            HStack {
                Text(model.text("⌘-Click to Add · Shift-Click to Select a Range · Drag to Reorder",
                                "⌘ ile seçime ekle · Shift ile aralık seç · Sıralamak için sürükle"))
                Spacer(minLength: 8)
                if !editor.canRemove, !editor.selectedDocuments.isEmpty {
                    Text(model.text("Keep at Least Two PDFs", "En az iki PDF kalmalı"))
                }
            }.font(.system(size: 10)).foregroundStyle(Palette.muted)
        }
    }

    private var documentList: some View {
        GeometryReader { viewport in
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(editor.entries) { entry in
                            documentRow(entry)
                                .id(entry.id)
                                .background(GeometryReader { geometry in
                                    Color.clear.preference(key: PDFMergeRowFrames.self,
                                        value: [entry.id: geometry.frame(in: .named("pdf-merge-list"))])
                                })
                        }
                    }.padding(.horizontal, 24).padding(.top, 4).padding(.bottom, 22)
                }
                .coordinateSpace(name: "pdf-merge-list")
                .focusable().focused($listFocused)
                .onMoveCommand { direction in
                    if let target = editor.moveFocus(direction) { scroll.scrollTo(target) }
                }
                .onDeleteCommand { editor.removeSelection() }
                .onChange(of: editor.scrollRequest) { request in
                    if let request { scroll.scrollTo(request.inputIndex) }
                }
                .onPreferenceChange(PDFMergeRowFrames.self) { frames in
                    let bounds = CGRect(origin: .zero, size: viewport.size)
                    let nearbyBounds = bounds.insetBy(dx: 0, dy: -(rowHeight + 10))
                    let visible = editor.documents.filter { frames[$0.inputIndex]?.intersects(bounds) == true }.map(\.inputIndex)
                    let near = editor.documents.filter {
                        !visible.contains($0.inputIndex) && frames[$0.inputIndex]?.intersects(nearbyBounds) == true
                    }.map(\.inputIndex)
                    editor.showDocuments(visible + near)
                }
            }
        }
        .accessibilityLabel(model.text("PDF Merge Order", "PDF birleştirme sırası"))
        .accessibilityHint(model.text("Use Up and Down to select files, Shift to extend the selection, and Delete to remove from the copy.",
                                      "Yukarı ve aşağı oklarla dosya seç, Shift ile seçimi genişlet, Delete ile kopyadan çıkar."))
    }

    private func documentRow(_ entry: PDFMergeEditor.Entry) -> some View {
        let inputIndex = entry.id
        let selected = editor.selectedDocuments.contains(inputIndex)
        let filename = inputs[inputIndex].lastPathComponent
        let dropPosition = editor.dropPosition
        return Button {
            editor.select(inputIndex, modifiers: NSEvent.modifierFlags)
            if editor.thumbnailErrors[inputIndex] != nil { editor.retryThumbnail(inputIndex) }
            listFocused = true
        } label: {
            HStack(spacing: 15) {
                VStack(spacing: 9) {
                    Text("\(entry.outputIndex + 1)").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(Palette.muted)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17)).foregroundStyle(selected ? Palette.accent : Palette.muted.opacity(0.6))
                }.frame(width: 24)
                thumbnail(inputIndex).frame(width: 58, height: 72)
                VStack(alignment: .leading, spacing: 8) {
                    Text(filename).font(.system(size: 13, weight: .semibold))
                        .lineLimit(1).truncationMode(.middle)
                    Text(model.text("Original File \(inputIndex + 1) · \(entry.source.pageCount == 1 ? "1 Page" : "\(entry.source.pageCount) Pages")",
                                    "Orijinal dosya \(inputIndex + 1) · \(entry.source.pageCount) sayfa"))
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    if let error = editor.thumbnailErrors[inputIndex] {
                        Text(model.text("Preview Unavailable · Click to Retry", "Önizleme kullanılamıyor · Yeniden denemek için tıkla"))
                            .font(.system(size: 10)).foregroundStyle(Palette.muted).help(error)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 5) {
                    Text(pageRange(entry)).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                    Text(model.text("In Your Copy", "Kopyandaki yeri"))
                        .font(.system(size: 10)).foregroundStyle(Palette.muted)
                }.padding(.horizontal, 11).padding(.vertical, 9)
                    .background(Palette.raised.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
                Image(systemName: "line.3.horizontal").font(.system(size: 11))
                    .foregroundStyle(Palette.muted.opacity(0.6)).accessibilityHidden(true)
            }
            .padding(.horizontal, 13).frame(height: rowHeight)
            .background(selected ? Palette.accent.opacity(0.08) : Palette.panel, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(selected ? Palette.accent : Palette.line, lineWidth: selected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain).focusable(false).help(editor.thumbnailErrors[inputIndex] ?? filename)
        .accessibilityLabel(model.text("File \(entry.outputIndex + 1), \(filename), Original File \(inputIndex + 1), \(entry.source.pageCount) Pages",
                                       "Dosya \(entry.outputIndex + 1), \(filename), Orijinal dosya \(inputIndex + 1), \(entry.source.pageCount) sayfa"))
        .accessibilityValue(pageRange(entry) + model.text(" in Your Copy, ", " kopyandaki yeri, ")
            + model.text(selected ? "Selected" : "Not Selected", selected ? "Seçili" : "Seçili değil"))
        .accessibilityAction(named: Text(model.text("Add to Selection", "Seçime ekle"))) {
            if !editor.selectedDocuments.contains(inputIndex) { editor.select(inputIndex, modifiers: .command) }
        }
        .accessibilityAction(named: Text(model.text("Remove From Selection", "Seçimden çıkar"))) {
            if editor.selectedDocuments.contains(inputIndex) { editor.select(inputIndex, modifiers: .command) }
        }
        .onDrag { editor.beginDrag(inputIndex) }
        .onDrop(of: [PDFMergeEditor.dragType], delegate: PDFMergeDropDelegate(editor: editor, inputIndex: inputIndex, height: rowHeight))
        .overlay(alignment: dropPosition?.after == true ? .bottom : .top) {
            if dropPosition?.inputIndex == inputIndex {
                Capsule().fill(Palette.accent).frame(height: 3).padding(.horizontal, 4)
                    .offset(y: dropPosition?.after == true ? 5 : -5)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .contextMenu { documentMenu(inputIndex) }
    }

    @ViewBuilder private func thumbnail(_ inputIndex: Int) -> some View {
        if let thumbnail = editor.thumbnails[inputIndex] {
            Image(decorative: thumbnail.image, scale: 1)
                .resizable().interpolation(.high).scaledToFit()
                .shadow(color: .black.opacity(0.16), radius: 3, y: 2)
                .accessibilityHidden(true)
        } else if editor.thumbnailErrors[inputIndex] != nil {
            Image(systemName: "doc.badge.ellipsis").font(.system(size: 25))
                .foregroundStyle(Palette.muted).accessibilityHidden(true)
        } else {
            ZStack {
                Image(systemName: "doc").font(.system(size: 36)).foregroundStyle(Palette.muted.opacity(0.25))
                ProgressView().controlSize(.mini)
            }.accessibilityHidden(true)
        }
    }

    @ViewBuilder private func documentMenu(_ inputIndex: Int) -> some View {
        Button(model.text("Select This File", "Bu dosyayı seç")) { editor.select(inputIndex); listFocused = true }
        Button(model.text("Add to Selection", "Seçime ekle")) {
            if !editor.selectedDocuments.contains(inputIndex) { editor.select(inputIndex, modifiers: .command) }
        }.disabled(editor.selectedDocuments.contains(inputIndex))
        if editor.thumbnailErrors[inputIndex] != nil {
            Button(model.text("Retry Preview", "Önizlemeyi yeniden dene")) { editor.retryThumbnail(inputIndex) }
        }
    }

    @ViewBuilder private var loadingState: some View {
        if let error = editor.errorMessage {
            VStack(spacing: 13) {
                Image(systemName: "doc.badge.ellipsis").font(.system(size: 32)).foregroundStyle(Palette.accent)
                Text(model.text("Could Not Prepare the Merge", "Birleştirme hazırlanamadı"))
                    .font(.system(size: 19, weight: .semibold))
                Text(error).font(.system(size: 13)).foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center).frame(maxWidth: 560)
            }
        } else {
            VStack(spacing: 14) {
                ProgressView(value: Double(editor.openedCount), total: Double(max(1, inputs.count)))
                    .progressViewStyle(.linear).frame(width: 240)
                Text(model.text("Opening PDF \(min(editor.openedCount + 1, inputs.count)) of \(inputs.count)…",
                                "PDF açılıyor: \(min(editor.openedCount + 1, inputs.count)) / \(inputs.count)…"))
                    .font(.system(size: 14, weight: .medium))
                Text(editor.openingName).font(.system(size: 12)).foregroundStyle(Palette.muted)
                    .lineLimit(1).truncationMode(.middle).frame(maxWidth: 540)
                Text(model.text("You can cancel while your files are being prepared.", "Dosyaların hazırlanırken istediğin an vazgeçebilirsin."))
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if editor.exceedsPageLimit {
                Label(model.text(editor.documents.count > 2
                    ? "Keep at most \(PDFMergePlan.maximumPageCount) pages in your copy. Remove a PDF to reduce the total."
                    : "These PDFs exceed \(PDFMergePlan.maximumPageCount) pages. Cancel and choose a smaller selection.",
                    editor.documents.count > 2
                    ? "Kopyanda en fazla \(PDFMergePlan.maximumPageCount) sayfa olabilir. Toplamı azaltmak için bir PDF çıkar."
                    : "Bu PDF'ler \(PDFMergePlan.maximumPageCount) sayfayı aşıyor. Vazgeç ve daha küçük bir seçim yap."),
                    systemImage: "info.circle")
                    .font(.system(size: 11)).foregroundStyle(Palette.ink)
            }
            if editor.hasEncryptedSources {
                Label(model.text("One or more PDFs are encrypted. The merged copy will not be password protected.",
                                 "Bir veya daha fazla PDF şifreli. Birleştirilen kopya parola korumalı olmayacak."), systemImage: "lock.open")
                    .font(.system(size: 11)).foregroundStyle(Palette.ink)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.raised, in: RoundedRectangle(cornerRadius: 8))
            }
            HStack(spacing: 12) {
                Label(model.text("Your Originals Stay Untouched", "Orijinal dosyaların korunur"), systemImage: "checkmark.shield")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
                Spacer(minLength: 12)
                Button(model.text("Cancel", "Vazgeç")) { editor.close(); model.cancelPending() }
                    .keyboardShortcut(.cancelAction)
                Button(model.text("Create Copy", "Kopya oluştur")) { submit() }
                    .buttonStyle(.borderedProminent).tint(Palette.primaryAction).foregroundStyle(Palette.onPrimary)
                    .keyboardShortcut(.defaultAction).disabled(editor.exportPlan() == nil)
            }
        }
    }

    private func pageRange(_ entry: PDFMergeEditor.Entry) -> String {
        model.text(entry.firstPage == entry.lastPage ? "Page \(entry.firstPage)" : "Pages \(entry.firstPage)–\(entry.lastPage)",
                   entry.firstPage == entry.lastPage ? "Sayfa \(entry.firstPage)" : "Sayfa \(entry.firstPage)–\(entry.lastPage)")
    }

    private func openDocuments() async {
        guard inputs.count >= 2, inputs.allSatisfy({ FileFamily.detect($0) == .pdf }) else {
            editor.failToOpen(model.text("Merge PDF works with at least two PDFs. Cancel and select your PDF files to continue.",
                                        "Birleştirmek için en az iki PDF gerekiyor. Vazgeç ve devam etmek için PDF dosyalarını seç."))
            return
        }
        await editor.open(inputs)
    }

    private func submit() {
        guard let plan = editor.exportPlan() else { return }
        var options = ConversionOptions()
        options.pdfMerge = plan
        editor.close()
        model.submitPending(options, outputExtension: "pdf")
    }
}

private struct PDFMergeRowFrames: PreferenceKey {
    static var defaultValue: [Int: CGRect] { [:] }
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newest in newest })
    }
}

private struct PDFMergeDropDelegate: DropDelegate {
    let editor: PDFMergeEditor
    let inputIndex: Int
    let height: CGFloat

    func validateDrop(info: DropInfo) -> Bool {
        MainActor.assumeIsolated {
            editor.isDragging && info.hasItemsConforming(to: [PDFMergeEditor.dragType])
        }
    }

    func dropEntered(info: DropInfo) { updatePosition(info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updatePosition(info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        MainActor.assumeIsolated {
            if editor.dropPosition?.inputIndex == inputIndex { editor.hoverDrop(nil) }
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        MainActor.assumeIsolated {
            editor.acceptDrop(info.itemProviders(for: [PDFMergeEditor.dragType]),
                at: PDFMergeEditor.DropPosition(inputIndex: inputIndex, after: info.location.y > height / 2))
        }
    }

    private func updatePosition(_ info: DropInfo) {
        MainActor.assumeIsolated {
            editor.hoverDrop(PDFMergeEditor.DropPosition(inputIndex: inputIndex, after: info.location.y > height / 2))
        }
    }
}
#endif
