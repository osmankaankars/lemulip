#if os(macOS)
import AppKit
import SwiftUI
import LemulipCore

/// Holds only source summaries and an ordered merge plan. A single core session
/// creates one short-lived source snapshot per request and caches bounded covers.
@MainActor
final class PDFMergeEditor: ObservableObject {
    struct Entry: Identifiable {
        let source: PDFMergeSource
        let outputIndex: Int
        let firstPage: Int
        let lastPage: Int
        var id: Int { source.inputIndex }
    }

    struct DropPosition: Equatable {
        let inputIndex: Int
        let after: Bool
    }

    struct ScrollRequest: Equatable {
        let inputIndex: Int
        let id = UUID()
    }

    private struct Snapshot {
        let documents: [PDFMergeSource]
        let selection: Set<Int>
        let focusedDocument: Int?
        let anchor: Int?
    }

    static let dragType = "app.lemulip.pdf-merge-document"
    private static let historyLimit = 40

    @Published private(set) var documents: [PDFMergeSource] = []
    @Published private(set) var selectedDocuments: Set<Int> = []
    @Published private(set) var focusedDocument: Int?
    @Published private(set) var thumbnails: [Int: PDFPageThumbnail] = [:]
    @Published private(set) var thumbnailErrors: [Int: String] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var openedCount = 0
    @Published private(set) var openingName = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var dropPosition: DropPosition?
    @Published private(set) var scrollRequest: ScrollRequest?

    private var initialSources: [PDFMergeSource] = []
    private var sourceInputCount = 0
    private var session: PDFMergeSession?
    private var openingWorker: Task<[PDFMergeSource], Error>?
    private var thumbnailWorker: Task<Void, Never>?
    private var generation = UUID()
    private var visibleDocuments: [Int] = []
    private var selectionAnchor: Int?
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var dragToken: String?
    private var draggedDocuments: [Int] = []

    var isReady: Bool { !initialSources.isEmpty && !isLoading }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var canReset: Bool { documents != initialSources }
    var canRemove: Bool { !selectedDocuments.isEmpty && documents.count - selectedDocuments.count >= 2 }
    var isDragging: Bool { dragToken != nil }
    var pageCount: Int { documents.reduce(0) { $0 + $1.pageCount } }
    var hasEncryptedSources: Bool { documents.contains(where: \.isEncrypted) }
    var exceedsPageLimit: Bool { pageCount > PDFMergePlan.maximumPageCount }
    var canMoveEarlier: Bool {
        documents.indices.dropFirst().contains {
            selectedDocuments.contains(documents[$0].inputIndex) && !selectedDocuments.contains(documents[$0 - 1].inputIndex)
        }
    }
    var canMoveLater: Bool {
        documents.indices.dropLast().contains {
            selectedDocuments.contains(documents[$0].inputIndex) && !selectedDocuments.contains(documents[$0 + 1].inputIndex)
        }
    }

    var entries: [Entry] {
        var firstPage = 1
        return documents.enumerated().map { index, source in
            let entry = Entry(source: source, outputIndex: index,
                              firstPage: firstPage, lastPage: firstPage + source.pageCount - 1)
            firstPage += source.pageCount
            return entry
        }
    }

    func open(_ inputs: [URL]) async {
        close()
        let loadID = generation
        sourceInputCount = inputs.count
        isLoading = true
        let openedSession = PDFMergeSession(inputs: inputs)
        session = openedSession
        let worker = Task { [weak self] () throws -> [PDFMergeSource] in
            var sources: [PDFMergeSource] = []
            for (index, input) in inputs.enumerated() {
                try Task.checkCancellation()
                guard let self, self.generation == loadID else { throw CancellationError() }
                self.openingName = input.lastPathComponent
                let source = try await openedSession.source(for: index)
                try Task.checkCancellation()
                guard self.generation == loadID else { throw CancellationError() }
                sources.append(source)
                self.openedCount = sources.count
            }
            return sources
        }
        openingWorker = worker
        do {
            let sources = try await withTaskCancellationHandler(operation: {
                try await worker.value
            }, onCancel: { worker.cancel() })
            try Task.checkCancellation()
            guard generation == loadID else { return }
            initialSources = sources
            documents = sources
            if let first = sources.first?.inputIndex {
                selectedDocuments = [first]
                focusedDocument = first
                selectionAnchor = first
            }
            openingWorker = nil
            isLoading = false
        } catch is CancellationError {
            if generation == loadID { openingWorker = nil; isLoading = false }
            await openedSession.close()
        } catch {
            guard generation == loadID, !Task.isCancelled else {
                await openedSession.close()
                return
            }
            errorMessage = error.localizedDescription
            openingWorker = nil
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
        openingWorker?.cancel()
        openingWorker = nil
        thumbnailWorker?.cancel()
        thumbnailWorker = nil
        let openedSession = session
        session = nil
        if let openedSession { Task { await openedSession.close() } }
        initialSources = []
        sourceInputCount = 0
        documents = []
        selectedDocuments = []
        focusedDocument = nil
        thumbnails = [:]
        thumbnailErrors = [:]
        visibleDocuments = []
        selectionAnchor = nil
        undoStack = []
        redoStack = []
        dragToken = nil
        draggedDocuments = []
        dropPosition = nil
        scrollRequest = nil
        isLoading = false
        openedCount = 0
        openingName = ""
        errorMessage = nil
    }

    deinit {
        openingWorker?.cancel()
        thumbnailWorker?.cancel()
        let openedSession = session
        if let openedSession { Task { await openedSession.close() } }
    }

    /// The view supplies visible rows and their immediate neighbors. Images are
    /// discarded from the UI as those rows leave this bounded window.
    func showDocuments(_ inputIndices: [Int]) {
        let available = Set(documents.map(\.inputIndex))
        var seen = Set<Int>()
        let next = Array(inputIndices.filter { available.contains($0) && seen.insert($0).inserted }
            .prefix(PDFMergeSession.thumbnailCacheLimit))
        guard visibleDocuments != next else { return }
        visibleDocuments = next
        let retained = Set(next)
        thumbnails = thumbnails.filter { retained.contains($0.key) }
        thumbnailErrors = thumbnailErrors.filter { retained.contains($0.key) }
        startThumbnailWorker()
    }

    func retryThumbnail(_ inputIndex: Int) {
        thumbnailErrors.removeValue(forKey: inputIndex)
        startThumbnailWorker()
    }

    private func startThumbnailWorker() {
        guard thumbnailWorker == nil, let session, isReady else { return }
        let loadID = generation
        thumbnailWorker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.generation == loadID,
                      let next = self.visibleDocuments.first(where: {
                          self.thumbnails[$0] == nil && self.thumbnailErrors[$0] == nil
                      }) else { break }
                do {
                    let thumbnail = try await session.thumbnail(for: next)
                    try Task.checkCancellation()
                    guard self.generation == loadID else { break }
                    if self.visibleDocuments.contains(next) { self.thumbnails[next] = thumbnail }
                } catch is CancellationError {
                    break
                } catch {
                    guard self.generation == loadID else { break }
                    if self.visibleDocuments.contains(next) { self.thumbnailErrors[next] = error.localizedDescription }
                }
            }
            if let self, self.generation == loadID { self.thumbnailWorker = nil }
        }
    }

    func select(_ inputIndex: Int, modifiers: NSEvent.ModifierFlags = []) {
        guard let index = documents.firstIndex(where: { $0.inputIndex == inputIndex }) else { return }
        if modifiers.contains(.shift), let anchor = selectionAnchor,
           let anchorIndex = documents.firstIndex(where: { $0.inputIndex == anchor }) {
            let range = Set(documents[min(index, anchorIndex)...max(index, anchorIndex)].map(\.inputIndex))
            selectedDocuments = modifiers.contains(.command) ? selectedDocuments.union(range) : range
        } else if modifiers.contains(.command) {
            if selectedDocuments.contains(inputIndex) { selectedDocuments.remove(inputIndex) }
            else { selectedDocuments.insert(inputIndex) }
            selectionAnchor = inputIndex
        } else {
            selectedDocuments = [inputIndex]
            selectionAnchor = inputIndex
        }
        focusedDocument = inputIndex
    }

    func selectAll() {
        selectedDocuments = Set(documents.map(\.inputIndex))
        if focusedDocument == nil { focusedDocument = documents.first?.inputIndex }
        if selectionAnchor == nil { selectionAnchor = focusedDocument }
    }

    func moveFocus(_ direction: MoveCommandDirection) -> Int? {
        guard !documents.isEmpty,
              NSEvent.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return nil }
        let current = documents.firstIndex(where: { $0.inputIndex == focusedDocument }) ?? 0
        let offset: Int
        switch direction {
        case .up: offset = -1
        case .down: offset = 1
        default: return nil
        }
        let next = documents[min(documents.count - 1, max(0, current + offset))].inputIndex
        select(next, modifiers: NSEvent.modifierFlags.intersection(.shift))
        return next
    }

    func moveSelection(by offset: Int) {
        guard offset < 0 ? canMoveEarlier : canMoveLater else { return }
        var next = documents
        if offset < 0 {
            for index in next.indices.dropFirst() where selectedDocuments.contains(next[index].inputIndex) && !selectedDocuments.contains(next[index - 1].inputIndex) {
                next.swapAt(index, index - 1)
            }
        } else {
            for index in next.indices.dropLast().reversed() where selectedDocuments.contains(next[index].inputIndex) && !selectedDocuments.contains(next[index + 1].inputIndex) {
                next.swapAt(index, index + 1)
            }
        }
        apply(next, selection: selectedDocuments)
        revealSelection()
    }

    func removeSelection() {
        guard canRemove else { return }
        let removedIndex = documents.firstIndex { selectedDocuments.contains($0.inputIndex) } ?? 0
        let next = documents.filter { !selectedDocuments.contains($0.inputIndex) }
        let focus = next[min(removedIndex, next.count - 1)].inputIndex
        apply(next, selection: [focus], focus: focus)
        revealSelection()
    }

    func reset() {
        guard canReset, let first = initialSources.first?.inputIndex else { return }
        apply(initialSources, selection: [first], focus: first)
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

    func exportPlan() -> PDFMergePlan? {
        guard isReady else { return nil }
        let plan = PDFMergePlan(sourceInputCount: sourceInputCount, sources: documents)
        do { try plan.validate(); return plan }
        catch { return nil }
    }

    func beginDrag(_ inputIndex: Int) -> NSItemProvider {
        if !selectedDocuments.contains(inputIndex) { select(inputIndex) }
        let token = UUID().uuidString
        dragToken = token
        draggedDocuments = documents.filter { selectedDocuments.contains($0.inputIndex) }.map(\.inputIndex)
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
        let dragged = Set(draggedDocuments)
        defer { dragToken = nil; draggedDocuments = []; dropPosition = nil }
        guard !dragged.isEmpty, !dragged.contains(position.inputIndex) else { return }
        let moving = documents.filter { dragged.contains($0.inputIndex) }
        var next = documents.filter { !dragged.contains($0.inputIndex) }
        guard let target = next.firstIndex(where: { $0.inputIndex == position.inputIndex }) else { return }
        next.insert(contentsOf: moving, at: target + (position.after ? 1 : 0))
        apply(next, selection: dragged)
        revealSelection()
    }

    private var snapshot: Snapshot {
        Snapshot(documents: documents, selection: selectedDocuments,
                 focusedDocument: focusedDocument, anchor: selectionAnchor)
    }

    private func append(_ value: Snapshot, to history: inout [Snapshot]) {
        history.append(value)
        if history.count > Self.historyLimit { history.removeFirst(history.count - Self.historyLimit) }
    }

    private func apply(_ next: [PDFMergeSource], selection: Set<Int>, focus: Int? = nil) {
        guard documents != next else { return }
        append(snapshot, to: &undoStack)
        redoStack.removeAll(keepingCapacity: true)
        documents = next
        selectedDocuments = selection
        if let focus { focusedDocument = focus; selectionAnchor = focus }
        let retained = Set(next.map(\.inputIndex))
        showDocuments(visibleDocuments.filter { retained.contains($0) })
    }

    private func restore(_ state: Snapshot) {
        documents = state.documents
        selectedDocuments = state.selection
        focusedDocument = state.focusedDocument
        selectionAnchor = state.anchor
        dragToken = nil
        draggedDocuments = []
        dropPosition = nil
        let retained = Set(documents.map(\.inputIndex))
        showDocuments(visibleDocuments.filter { retained.contains($0) })
        revealSelection()
    }

    private func revealSelection() {
        if let focusedDocument, selectedDocuments.contains(focusedDocument) {
            scrollRequest = ScrollRequest(inputIndex: focusedDocument)
        } else if let first = documents.first(where: { selectedDocuments.contains($0.inputIndex) }) {
            focusedDocument = first.inputIndex
            scrollRequest = ScrollRequest(inputIndex: first.inputIndex)
        }
    }
}
#endif
