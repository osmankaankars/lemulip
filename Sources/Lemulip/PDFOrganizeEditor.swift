#if os(macOS)
import AppKit
import SwiftUI
import LemulipCore

/// Editing only changes a small page plan. PDFKit stays inside the core session.
@MainActor
final class PDFOrganizeEditor: ObservableObject {
    private struct Snapshot {
        let pages: [PDFPageEdit]
        let selection: Set<Int>
        let focusedPage: Int?
        let anchor: Int?
    }

    struct DropPosition: Equatable {
        let sourceIndex: Int
        let after: Bool
    }

    struct ScrollRequest: Equatable {
        let sourceIndex: Int
        let id = UUID()
    }

    static let dragType = "app.lemulip.pdf-organizer-page"
    private static let historyLimit = 40

    @Published private(set) var source: PDFOrganizeSource?
    @Published private(set) var pages: [PDFPageEdit] = []
    @Published private(set) var selectedPages: Set<Int> = []
    @Published private(set) var focusedPage: Int?
    @Published private(set) var thumbnails: [Int: PDFPageThumbnail] = [:]
    @Published private(set) var failedThumbnails: Set<Int> = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var dropPosition: DropPosition?
    @Published private(set) var scrollRequest: ScrollRequest?

    private var session: PDFOrganizeSession?
    private var thumbnailWorker: Task<Void, Never>?
    private var generation = UUID()
    private var visiblePages: [Int] = []
    private var selectionAnchor: Int?
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var dragToken: String?
    private var draggedPages: [Int] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var canReset: Bool { source.map { $0.initialPlan.pages != pages } ?? false }
    var canRemove: Bool { !selectedPages.isEmpty && selectedPages.count < pages.count }
    var isDragging: Bool { dragToken != nil }
    var canMoveEarlier: Bool {
        pages.indices.dropFirst().contains {
            selectedPages.contains(pages[$0].sourceIndex) && !selectedPages.contains(pages[$0 - 1].sourceIndex)
        }
    }
    var canMoveLater: Bool {
        pages.indices.dropLast().contains {
            selectedPages.contains(pages[$0].sourceIndex) && !selectedPages.contains(pages[$0 + 1].sourceIndex)
        }
    }

    func open(_ input: URL) async {
        close()
        let loadID = generation
        isLoading = true
        let openedSession = PDFOrganizeSession(input: input)
        session = openedSession
        do {
            let openedSource = try await openedSession.open()
            try Task.checkCancellation()
            guard generation == loadID else { return }
            source = openedSource
            pages = openedSource.initialPlan.pages
            selectedPages = [0]
            focusedPage = 0
            selectionAnchor = 0
            isLoading = false
        } catch is CancellationError {
            if generation == loadID { isLoading = false }
            await openedSession.close()
        } catch {
            guard generation == loadID, !Task.isCancelled else {
                await openedSession.close()
                return
            }
            errorMessage = error.localizedDescription
            isLoading = false
            await openedSession.close()
        }
    }

    func failToOpen(_ message: String) {
        close()
        errorMessage = message
    }

    func close() {
        generation = UUID()
        thumbnailWorker?.cancel()
        thumbnailWorker = nil
        let openedSession = session
        session = nil
        if let openedSession { Task { await openedSession.close() } }
        source = nil
        pages = []
        selectedPages = []
        focusedPage = nil
        selectionAnchor = nil
        thumbnails = [:]
        failedThumbnails = []
        visiblePages = []
        undoStack = []
        redoStack = []
        dragToken = nil
        draggedPages = []
        dropPosition = nil
        scrollRequest = nil
        isLoading = false
        errorMessage = nil
    }

    deinit {
        thumbnailWorker?.cancel()
        let openedSession = session
        if let openedSession { Task { await openedSession.close() } }
    }

    /// The grid passes the viewport and one nearby row, never the whole PDF.
    func showPages(_ sourceIndices: [Int]) {
        let available = Set(pages.map(\.sourceIndex))
        var seen = Set<Int>()
        let next = Array(sourceIndices.filter { available.contains($0) && seen.insert($0).inserted }
            .prefix(PDFOrganizeSession.thumbnailCacheLimit))
        guard visiblePages != next else { return }
        visiblePages = next
        let retained = Set(next)
        thumbnails = thumbnails.filter { retained.contains($0.key) }
        failedThumbnails.formIntersection(retained)
        startThumbnailWorker()
    }

    func retryThumbnail(_ sourceIndex: Int) {
        failedThumbnails.remove(sourceIndex)
        startThumbnailWorker()
    }

    private func startThumbnailWorker() {
        guard thumbnailWorker == nil, let session, source != nil else { return }
        let loadID = generation
        thumbnailWorker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.generation == loadID,
                      let next = self.visiblePages.first(where: {
                          self.thumbnails[$0] == nil && !self.failedThumbnails.contains($0)
                      }) else { break }
                do {
                    let thumbnail = try await session.thumbnail(for: next)
                    try Task.checkCancellation()
                    guard self.generation == loadID else { break }
                    if self.visiblePages.contains(next) { self.thumbnails[next] = thumbnail }
                } catch is CancellationError {
                    break
                } catch {
                    guard self.generation == loadID else { break }
                    if self.visiblePages.contains(next) { self.failedThumbnails.insert(next) }
                }
            }
            if let self, self.generation == loadID { self.thumbnailWorker = nil }
        }
    }

    func select(_ sourceIndex: Int, modifiers: NSEvent.ModifierFlags = []) {
        guard let index = pages.firstIndex(where: { $0.sourceIndex == sourceIndex }) else { return }
        if modifiers.contains(.shift), let anchor = selectionAnchor,
           let anchorIndex = pages.firstIndex(where: { $0.sourceIndex == anchor }) {
            let range = Set(pages[min(index, anchorIndex)...max(index, anchorIndex)].map(\.sourceIndex))
            selectedPages = modifiers.contains(.command) ? selectedPages.union(range) : range
        } else if modifiers.contains(.command) {
            if selectedPages.contains(sourceIndex) { selectedPages.remove(sourceIndex) }
            else { selectedPages.insert(sourceIndex) }
            selectionAnchor = sourceIndex
        } else {
            selectedPages = [sourceIndex]
            selectionAnchor = sourceIndex
        }
        focusedPage = sourceIndex
    }

    func selectAll() {
        selectedPages = Set(pages.map(\.sourceIndex))
        if focusedPage == nil { focusedPage = pages.first?.sourceIndex }
        if selectionAnchor == nil { selectionAnchor = focusedPage }
    }

    func moveFocus(_ direction: MoveCommandDirection, columns: Int) -> Int? {
        guard !pages.isEmpty else { return nil }
        guard NSEvent.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return nil }
        let current = pages.firstIndex(where: { $0.sourceIndex == focusedPage }) ?? 0
        let offset: Int
        switch direction {
        case .left: offset = -1
        case .right: offset = 1
        case .up: offset = -columns
        case .down: offset = columns
        @unknown default: return nil
        }
        let next = pages[min(pages.count - 1, max(0, current + offset))].sourceIndex
        select(next, modifiers: NSEvent.modifierFlags.intersection(.shift))
        return next
    }

    func moveSelection(by offset: Int) {
        guard offset < 0 ? canMoveEarlier : canMoveLater else { return }
        var next = pages
        if offset < 0 {
            for index in next.indices.dropFirst() where selectedPages.contains(next[index].sourceIndex) && !selectedPages.contains(next[index - 1].sourceIndex) {
                next.swapAt(index, index - 1)
            }
        } else {
            for index in next.indices.dropLast().reversed() where selectedPages.contains(next[index].sourceIndex) && !selectedPages.contains(next[index + 1].sourceIndex) {
                next.swapAt(index, index + 1)
            }
        }
        apply(next, selection: selectedPages)
        revealSelection()
    }

    func rotateSelection(clockwise: Bool) {
        guard !selectedPages.isEmpty else { return }
        let next = pages.map { page -> PDFPageEdit in
            guard selectedPages.contains(page.sourceIndex) else { return page }
            var changed = page
            changed.rotationQuarterTurns = (changed.rotationQuarterTurns + (clockwise ? 1 : 3)) % 4
            return changed
        }
        apply(next, selection: selectedPages)
    }

    func removeSelection() {
        guard canRemove else { return }
        let firstRemovedIndex = pages.firstIndex { selectedPages.contains($0.sourceIndex) } ?? 0
        let next = pages.filter { !selectedPages.contains($0.sourceIndex) }
        let nextFocus = next[min(firstRemovedIndex, next.count - 1)].sourceIndex
        apply(next, selection: [nextFocus], focus: nextFocus)
        revealSelection()
    }

    func reset() {
        guard let source, canReset else { return }
        apply(source.initialPlan.pages, selection: [0], focus: 0)
        revealSelection()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        append(snapshot, to: &redoStack)
        restore(previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        append(snapshot, to: &undoStack)
        restore(next)
    }

    func exportPlan(selectedOnly: Bool) -> PDFOrganizePlan? {
        guard let source else { return nil }
        let outputPages = selectedOnly ? pages.filter { selectedPages.contains($0.sourceIndex) } : pages
        let plan = PDFOrganizePlan(sourcePageCount: source.pageCount, sourceFingerprint: source.fingerprint, pages: outputPages)
        do { try plan.validate(); return plan }
        catch { return nil }
    }

    func beginDrag(_ sourceIndex: Int) -> NSItemProvider {
        if !selectedPages.contains(sourceIndex) { select(sourceIndex) }
        let token = UUID().uuidString
        dragToken = token
        draggedPages = pages.filter { selectedPages.contains($0.sourceIndex) }.map(\.sourceIndex)
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: Self.dragType, visibility: .ownProcess) { completion in
            completion(Data(token.utf8), nil)
            return nil
        }
        return provider
    }

    func hoverDrop(_ position: DropPosition?) {
        if dropPosition != position { dropPosition = position }
    }

    func acceptDrop(_ providers: [NSItemProvider], at position: DropPosition) -> Bool {
        guard let token = dragToken,
              let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(Self.dragType) }) else { return false }
        let loadID = generation
        dropPosition = nil
        provider.loadDataRepresentation(forTypeIdentifier: Self.dragType) { [weak self] data, _ in
            guard let data, data.count == token.utf8.count, String(data: data, encoding: .utf8) == token else { return }
            Task { @MainActor [weak self] in
                guard let self, self.generation == loadID, self.dragToken == token else { return }
                self.finishDrop(at: position)
            }
        }
        return true
    }

    private func finishDrop(at position: DropPosition) {
        let dragged = Set(draggedPages)
        defer { dragToken = nil; draggedPages = []; dropPosition = nil }
        guard !dragged.isEmpty, !dragged.contains(position.sourceIndex) else { return }
        let moving = pages.filter { dragged.contains($0.sourceIndex) }
        var next = pages.filter { !dragged.contains($0.sourceIndex) }
        guard let target = next.firstIndex(where: { $0.sourceIndex == position.sourceIndex }) else { return }
        next.insert(contentsOf: moving, at: target + (position.after ? 1 : 0))
        apply(next, selection: dragged)
        revealSelection()
    }

    private var snapshot: Snapshot {
        Snapshot(pages: pages, selection: selectedPages, focusedPage: focusedPage, anchor: selectionAnchor)
    }

    private func append(_ value: Snapshot, to history: inout [Snapshot]) {
        history.append(value)
        if history.count > Self.historyLimit { history.removeFirst(history.count - Self.historyLimit) }
    }

    private func apply(_ next: [PDFPageEdit], selection: Set<Int>, focus: Int? = nil) {
        guard pages != next else { return }
        append(snapshot, to: &undoStack)
        redoStack.removeAll(keepingCapacity: true)
        pages = next
        selectedPages = selection
        if let focus { focusedPage = focus; selectionAnchor = focus }
        let retained = Set(next.map(\.sourceIndex))
        showPages(visiblePages.filter { retained.contains($0) })
    }

    private func restore(_ state: Snapshot) {
        pages = state.pages
        selectedPages = state.selection
        focusedPage = state.focusedPage
        selectionAnchor = state.anchor
        dropPosition = nil
        dragToken = nil
        draggedPages = []
        let retained = Set(pages.map(\.sourceIndex))
        showPages(visiblePages.filter { retained.contains($0) })
        revealSelection()
    }

    private func revealSelection() {
        if let focusedPage, selectedPages.contains(focusedPage) {
            scrollRequest = ScrollRequest(sourceIndex: focusedPage)
        } else if let first = pages.first(where: { selectedPages.contains($0.sourceIndex) }) {
            focusedPage = first.sourceIndex
            scrollRequest = ScrollRequest(sourceIndex: first.sourceIndex)
        }
    }
}
#endif
