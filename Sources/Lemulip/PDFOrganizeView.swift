#if os(macOS)
import AppKit
import SwiftUI
import LemulipCore

@MainActor
struct PDFOrganizeView: View {
    @ObservedObject var model: AppController
    let inputs: [URL]
    @StateObject private var editor: PDFOrganizeEditor
    @FocusState private var focus: PDFEditorFocus?
    private let columns = 4

    init(model: AppController, inputs: [URL], editor: PDFOrganizeEditor? = nil) {
        self.model = model
        self.inputs = inputs
        _editor = StateObject(wrappedValue: editor ?? PDFOrganizeEditor())
    }

    // Only an uncommitted number edit blocks document actions. AppKit may
    // restore keyboard focus to a visible field after scrolling or a drag.
    @State private var editingPosition: Int?
    private var positionHasFocus: Bool {
        if case .position? = focus { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 24).padding(.vertical, 19)
            separator
            if editor.source != nil {
                editToolbar.padding(.horizontal, 24).padding(.vertical, 12)
                selectionSummary.padding(.horizontal, 24).padding(.bottom, 10)
                pageGrid
            } else {
                loadingState.frame(maxWidth: .infinity, maxHeight: .infinity).padding(40)
            }
            separator
            footer
        }
        .frame(width: 860, height: 680)
        .background(Palette.background).foregroundStyle(Palette.ink).tint(Palette.accent)
        .task(id: inputs) { await openDocument() }
        .onDisappear { editor.close() }
    }

    private var separator: some View { Rectangle().fill(Palette.line).frame(height: 1) }

    private var header: some View {
        HStack(spacing: 13) {
            Image(systemName: "rectangle.grid.2x2")
                .font(.system(size: 25)).foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 5) {
                Text(model.text("Organize PDF", "PDF düzenle"))
                    .font(.system(size: 23, weight: .semibold)).tracking(-0.5)
                Text(inputs.count == 1 ? inputs[0].lastPathComponent : model.text("Choose a Single PDF", "Tek bir PDF seç"))
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 16)
            HStack(spacing: 8) {
                Button { editor.undo() } label: { Label(model.text("Undo", "Geri al"), systemImage: "arrow.uturn.backward") }
                    .keyboardShortcut("z", modifiers: .command).disabled(!editor.canUndo || editingPosition != nil)
                Button { editor.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!editor.canRedo || editingPosition != nil)
                    .accessibilityLabel(model.text("Redo", "Yinele"))
                    .help(model.text("Redo (⇧⌘Z)", "Yinele (⇧⌘Z)"))
                Button(model.text("Reset", "Sıfırla")) { focus = .content; editor.reset() }.disabled(!editor.canReset)
                    .help(model.text("Restore All Pages, Their Original Order, and Rotation", "Tüm sayfaları, orijinal sırayı ve yönleri geri getir"))
            }.font(.system(size: 11))
        }
    }

    private var editToolbar: some View {
        HStack(spacing: 8) {
            Button { editor.moveSelection(by: -1) } label: {
                Label(model.text("Move Earlier", "Öne taşı"), systemImage: "arrow.left")
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            .disabled(!editor.canMoveEarlier || editingPosition != nil)
            .help(model.text("Move Earlier (⌥⌘←)", "Öne taşı (⌥⌘←)"))
            Button { editor.moveSelection(by: 1) } label: {
                Label(model.text("Move Later", "Arkaya taşı"), systemImage: "arrow.right")
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            .disabled(!editor.canMoveLater || editingPosition != nil)
            .help(model.text("Move Later (⌥⌘→)", "Arkaya taşı (⌥⌘→)"))
            Divider().frame(height: 20).padding(.horizontal, 3)
            Button { editor.rotateSelection(clockwise: false) } label: {
                Label(model.text("Rotate Left", "Sola döndür"), systemImage: "rotate.left")
            }
            .keyboardShortcut("l", modifiers: .command).disabled(editor.selectedPages.isEmpty || editingPosition != nil)
            .help(model.text("Rotate Left (⌘L)", "Sola döndür (⌘L)"))
            Button { editor.rotateSelection(clockwise: true) } label: {
                Label(model.text("Rotate Right", "Sağa döndür"), systemImage: "rotate.right")
            }
            .keyboardShortcut("r", modifiers: .command).disabled(editor.selectedPages.isEmpty || editingPosition != nil)
            .help(model.text("Rotate Right (⌘R)", "Sağa döndür (⌘R)"))
            Divider().frame(height: 20).padding(.horizontal, 3)
            Button { focus = .content; editor.removeSelection() } label: {
                Label(model.text("Remove", "Çıkar"), systemImage: "minus.circle")
            }
            .disabled(!editor.canRemove)
            .help(model.text("Remove From the Copy (Delete)", "Kopyadan çıkar (Delete)"))
            Spacer(minLength: 10)
            Button(model.text("Select All", "Tümünü seç")) { editor.selectAll(); focus = .content }
                .keyboardShortcut("a", modifiers: .command).disabled(editor.pages.isEmpty || positionHasFocus)
        }.font(.system(size: 11)).controlSize(.small)
    }

    private var selectionSummary: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Text(model.text(editor.pages.count == 1 ? "1 Page in Your Copy" : "\(editor.pages.count) Pages in Your Copy",
                                "Kopyanda \(editor.pages.count) sayfa"))
                    .font(.system(size: 12, weight: .semibold))
                Text(model.text("\(editor.selectedPages.count) Selected", "\(editor.selectedPages.count) seçili"))
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.accent)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Palette.accent.opacity(0.09), in: Capsule())
                Spacer()
                if editor.selectedPages.count == editor.pages.count {
                    Text(model.text("Keep at Least One Page in Your Copy", "Kopyanda en az bir sayfa kalmalı"))
                        .font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
            }
            Text(orderingHint)
                .font(.system(size: 10)).foregroundStyle(Palette.muted)
        }
    }

    private var orderingHint: String {
        if let editingPosition {
            let range = editor.positionRange(for: editingPosition)
            return model.text("Position \(range.lowerBound)–\(range.upperBound) · Enter to Move · Esc to Cancel · Selected Pages Move Together",
                              "Konum \(range.lowerBound)–\(range.upperBound) · Enter ile taşı · Esc ile vazgeç · Seçili sayfalar birlikte taşınır")
        }
        return model.text("⌘-Click to Add · Shift-Click for a Range · Drag the Handle or Edit a Page Number",
                          "⌘ ile seçime ekle · Shift ile aralık seç · Tutamaktan sürükle veya sayfa numarasını değiştir")
    }

    private var pageGrid: some View {
        GeometryReader { viewport in
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: columns), spacing: 16) {
                        ForEach(Array(editor.pages.enumerated()), id: \.element.sourceIndex) { index, page in
                            pageCard(page, outputIndex: index, width: max(1, (viewport.size.width - 90) / CGFloat(columns)))
                                .id(page.sourceIndex)
                                .background(GeometryReader { geometry in
                                    Color.clear.preference(key: PDFPageFrames.self,
                                        value: [page.sourceIndex: geometry.frame(in: .named("pdf-organizer-grid"))])
                                })
                        }
                    }.padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 24)
                }
                .coordinateSpace(name: "pdf-organizer-grid")
                .focusable().focused($focus, equals: .content)
                .onMoveCommand { direction in
                    if case .position? = focus { return }
                    if let target = editor.moveFocus(direction, columns: columns) { scroll.scrollTo(target) }
                }
                .onDeleteCommand { if case .position? = focus { return }; editor.removeSelection() }
                .onChange(of: editor.scrollRequest) { request in
                    if let request {
                        scroll.scrollTo(request.sourceIndex)
                        // A completed reorder ends position editing, including focus restored after a drag.
                        focus = .content
                    }
                }
                .onPreferenceChange(PDFPageFrames.self) { frames in
                    let bounds = CGRect(origin: .zero, size: viewport.size)
                    let nearbyBounds = bounds.insetBy(dx: 0, dy: -230)
                    let visible = editor.pages.filter { frames[$0.sourceIndex]?.intersects(bounds) == true }.map(\.sourceIndex)
                    let near = editor.pages.filter {
                        !visible.contains($0.sourceIndex) && frames[$0.sourceIndex]?.intersects(nearbyBounds) == true
                    }.map(\.sourceIndex)
                    editor.showPages(visible + near)
                }
            }
        }
        .accessibilityLabel(model.text("PDF Pages", "PDF sayfaları"))
        .accessibilityHint(model.text("Use arrow keys to select pages, Shift to extend the selection, and Delete to remove from the copy.",
                                      "Oklarla sayfa seç, Shift ile seçimi genişlet, Delete ile kopyadan çıkar."))
    }

    private func pageCard(_ page: PDFPageEdit, outputIndex: Int, width: CGFloat) -> some View {
        let selected = editor.selectedPages.contains(page.sourceIndex)
        let dropPosition = editor.dropPosition
        return VStack(spacing: 10) {
            Button {
                editor.select(page.sourceIndex, modifiers: NSEvent.modifierFlags)
                if editor.failedThumbnails.contains(page.sourceIndex) { editor.retryThumbnail(page.sourceIndex) }
                focus = .content
            } label: {
                ZStack(alignment: .topTrailing) {
                    thumbnail(page).frame(height: 136).frame(maxWidth: .infinity)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(selected ? Palette.onPrimary : Palette.muted,
                                         selected ? Palette.primaryAction : Palette.panel)
                        .background(Circle().fill(selected ? Palette.primaryAction : Palette.panel))
                        .padding(1)
                }
                .contentShape(Rectangle())
                .onDrag { focus = .content; return editor.beginDrag(page.sourceIndex) }
            }
            .buttonStyle(.plain).focusable(false)
            .accessibilityLabel(model.text("Page \(outputIndex + 1), Original Page \(page.sourceIndex + 1)",
                                           "Sayfa \(outputIndex + 1), Orijinal sayfa \(page.sourceIndex + 1)"))
            .accessibilityValue(model.text(selected ? "Selected" : "Not Selected", selected ? "Seçili" : "Seçili değil")
                + (page.rotationQuarterTurns == 0 ? "" : model.text(", Rotated \(page.rotationQuarterTurns * 90) Degrees", ", \(page.rotationQuarterTurns * 90) derece döndürüldü")))
            .accessibilityAction(named: Text(model.text("Add to Selection", "Seçime ekle"))) {
                if !editor.selectedPages.contains(page.sourceIndex) { editor.select(page.sourceIndex, modifiers: .command) }
            }
            .accessibilityAction(named: Text(model.text("Remove From Selection", "Seçimden çıkar"))) {
                if editor.selectedPages.contains(page.sourceIndex) { editor.select(page.sourceIndex, modifiers: .command) }
            }
            HStack(spacing: 6) {
                Text(model.text("Page", "Sayfa")).font(.system(size: 12, weight: .semibold))
                positionField(page.sourceIndex, outputIndex: outputIndex)
                Spacer(minLength: 2)
                Image(systemName: "line.3.horizontal").font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.muted).frame(width: 26, height: 28)
                    .background(Palette.raised, in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                    .onDrag { focus = .content; return editor.beginDrag(page.sourceIndex) }
                    .help(model.text("Drag to Move the Selected Pages Together", "Seçili sayfaları birlikte taşımak için sürükle"))
                    .accessibilityHidden(true)
            }
            HStack(spacing: 4) {
                Text(model.text("Original Page \(page.sourceIndex + 1)", "Orijinal sayfa \(page.sourceIndex + 1)"))
                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
                Spacer(minLength: 2)
                if page.rotationQuarterTurns != 0 {
                    Label("\(page.rotationQuarterTurns * 90)°", systemImage: "rotate.right")
                        .font(.system(size: 9)).foregroundStyle(Palette.muted)
                }
            }
        }
        .padding(11).frame(width: width)
        .background(selected ? Palette.accent.opacity(0.08) : Palette.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(selected ? Palette.accent : Palette.line, lineWidth: selected ? 2 : 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pdf.organize.card.\(page.sourceIndex)")
        .onDrop(of: [PDFOrganizeEditor.dragType], delegate: PDFPageDropDelegate(editor: editor, sourceIndex: page.sourceIndex, width: width))
        .overlay(alignment: dropPosition?.after == true ? .trailing : .leading) {
            if dropPosition?.sourceIndex == page.sourceIndex {
                Capsule().fill(Palette.accent).frame(width: 3).padding(.vertical, 4).offset(x: dropPosition?.after == true ? 7 : -7)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .contextMenu { pageMenu(page) }
    }

    private func positionField(_ sourceIndex: Int, outputIndex: Int) -> some View {
        let range = editor.positionRange(for: sourceIndex)
        return PDFPositionField(item: sourceIndex, position: outputIndex + 1,
            allowedPositions: range,
            label: model.text("Output Position for Original Page \(sourceIndex + 1)", "Orijinal sayfa \(sourceIndex + 1) için çıktı sırası"),
            hint: model.text("Enter a Position and Press Return. Selected Pages Move Together. Esc Cancels.",
                             "Bir konum yazıp Enter'a bas. Seçili sayfalar birlikte taşınır. Esc ile vazgeç."),
            invalidHint: model.text("Enter a Whole Number from \(range.lowerBound) to \(range.upperBound). The Selected Pages Keep Their Relative Order.",
                                    "\(range.lowerBound) ile \(range.upperBound) arasında tam sayı gir. Seçili sayfaların kendi aralarındaki sıra korunur."),
            focus: $focus, editingPosition: $editingPosition,
            beginEditing: {
                if !editor.selectedPages.contains(sourceIndex) { editor.select(sourceIndex) }
            },
            move: { editor.move(sourceIndex, toPosition: $0) })
    }

    @ViewBuilder private func thumbnail(_ page: PDFPageEdit) -> some View {
        if let thumbnail = editor.thumbnails[page.sourceIndex] {
            GeometryReader { frame in
                let oddTurn = page.rotationQuarterTurns.isMultiple(of: 2) == false
                let imageWidth = CGFloat(thumbnail.image.width)
                let imageHeight = CGFloat(thumbnail.image.height)
                let displayWidth = oddTurn ? imageHeight : imageWidth
                let displayHeight = oddTurn ? imageWidth : imageHeight
                let scale = min(max(1, frame.size.width - 18) / displayWidth, max(1, frame.size.height - 8) / displayHeight)
                Image(decorative: thumbnail.image, scale: 1)
                    .resizable().interpolation(.high)
                    .frame(width: imageWidth * scale, height: imageHeight * scale)
                    .background(.white)
                    .rotationEffect(.degrees(Double(page.rotationQuarterTurns * 90)))
                    .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
                    .position(x: frame.size.width / 2, y: frame.size.height / 2)
            }.accessibilityHidden(true)
        } else if editor.failedThumbnails.contains(page.sourceIndex) {
            VStack(spacing: 7) {
                Image(systemName: "doc.badge.ellipsis").font(.system(size: 24))
                Text(model.text("Preview Unavailable", "Önizleme kullanılamıyor")).font(.system(size: 10, weight: .medium))
                Text(model.text("Click to Retry", "Yeniden denemek için tıkla")).font(.system(size: 9))
            }.foregroundStyle(Palette.muted)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "doc").font(.system(size: 32)).foregroundStyle(Palette.muted.opacity(0.5))
                ProgressView().controlSize(.mini)
            }.accessibilityHidden(true)
        }
    }

    @ViewBuilder private func pageMenu(_ page: PDFPageEdit) -> some View {
        Button(model.text("Move to Position…", "Konuma taşı…")) { focus = .position(page.sourceIndex) }
        Button(model.text("Select This Page", "Bu sayfayı seç")) { editor.select(page.sourceIndex); focus = .content }
        Button(model.text("Add to Selection", "Seçime ekle")) {
            if !editor.selectedPages.contains(page.sourceIndex) { editor.select(page.sourceIndex, modifiers: .command) }
        }.disabled(editor.selectedPages.contains(page.sourceIndex))
        if editor.failedThumbnails.contains(page.sourceIndex) {
            Button(model.text("Retry Preview", "Önizlemeyi yeniden dene")) { editor.retryThumbnail(page.sourceIndex) }
        }
    }

    @ViewBuilder private var loadingState: some View {
        if let error = editor.errorMessage {
            VStack(spacing: 13) {
                Image(systemName: "doc.badge.ellipsis").font(.system(size: 32)).foregroundStyle(Palette.accent)
                Text(model.text("Could Not Open the PDF Organizer", "PDF düzenleyicisi açılamadı"))
                    .font(.system(size: 19, weight: .semibold))
                Text(error).font(.system(size: 13)).foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center).frame(maxWidth: 550)
            }
        } else {
            VStack(spacing: 15) {
                ProgressView().controlSize(.regular)
                Text(model.text("Opening Your PDF…", "PDF'in açılıyor…"))
                    .font(.system(size: 13)).foregroundStyle(Palette.muted)
                Text(model.text("You can cancel while the pages are being prepared.", "Sayfalar hazırlanırken istediğin an vazgeçebilirsin."))
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if editor.source?.isEncrypted == true {
                Label(model.text("This PDF is encrypted. The new copy will not be password protected.",
                                 "Bu PDF şifreli. Yeni kopya parola korumalı olmayacak."), systemImage: "lock.open")
                    .font(.system(size: 11)).foregroundStyle(Palette.ink)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.raised, in: RoundedRectangle(cornerRadius: 8))
            }
            HStack {
                Spacer()
                Button(model.text("Extract Selected", "Seçili Sayfaları Çıkar")) { submit(selectedOnly: true) }
                    .disabled(editor.exportPlan(selectedOnly: true) == nil || editingPosition != nil)
                    .help(model.text("Create A PDF With Selected Pages", "Seçili Sayfalardan Bir PDF Oluştur"))
            }.padding(.horizontal, 24)
            EditorFooter(language: model.language, isEnabled: editor.exportPlan(selectedOnly: false) != nil && editingPosition == nil,
                cancelShortcut: positionHasFocus ? nil : .cancelAction,
                onCancel: { editor.close(); model.cancelPending() }, onSubmit: { submit(selectedOnly: false) })
        }
    }

    private func openDocument() async {
        guard inputs.count == 1, let input = inputs.first, FileFamily.detect(input) == .pdf else {
            editor.failToOpen(model.text("Organize PDF works with one PDF at a time. Cancel and select a single PDF to continue.",
                                        "PDF düzenleyicisi tek dosyayla çalışır. Vazgeç ve devam etmek için bir PDF seç."))
            return
        }
        await editor.open(input)
    }

    private func submit(selectedOnly: Bool) {
        guard editingPosition == nil, let plan = editor.exportPlan(selectedOnly: selectedOnly) else { return }
        var options = ConversionOptions()
        options.pdfOrganization = plan
        model.submitPending(options, outputExtension: "pdf")
    }
}

private struct PDFPageFrames: PreferenceKey {
    static var defaultValue: [Int: CGRect] { [:] }
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newest in newest })
    }
}

private struct PDFPageDropDelegate: DropDelegate {
    let editor: PDFOrganizeEditor
    let sourceIndex: Int
    let width: CGFloat

    func validateDrop(info: DropInfo) -> Bool {
        MainActor.assumeIsolated {
            editor.isDragging && info.hasItemsConforming(to: [PDFOrganizeEditor.dragType])
        }
    }

    func dropEntered(info: DropInfo) { updatePosition(info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updatePosition(info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        MainActor.assumeIsolated {
            if editor.dropPosition?.sourceIndex == sourceIndex { editor.hoverDrop(nil) }
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        MainActor.assumeIsolated {
            editor.acceptDrop(info.itemProviders(for: [PDFOrganizeEditor.dragType]),
                at: PDFOrganizeEditor.DropPosition(sourceIndex: sourceIndex, after: info.location.x > width / 2))
        }
    }

    private func updatePosition(_ info: DropInfo) {
        MainActor.assumeIsolated {
            editor.hoverDrop(PDFOrganizeEditor.DropPosition(sourceIndex: sourceIndex, after: info.location.x > width / 2))
        }
    }
}
#endif
