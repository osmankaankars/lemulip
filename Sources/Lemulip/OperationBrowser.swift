#if os(macOS)
import AppKit
import SwiftUI
import LemulipCore

struct OperationBrowser: View {
    @ObservedObject var model: AppController
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    private var searching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var operations: [FileOperation] {
        let available = searching ? model.availableOperations : model.operations
        return OperationDiscovery.matching(available, query: query,
            localizedTitles: Dictionary(uniqueKeysWithValues: available.map { ($0.id, OperationNames.title($0, language: model.language)) }),
            localizedDetails: Dictionary(uniqueKeysWithValues: available.map { ($0.id, OperationNames.detail($0, language: model.language)) }))
    }
    private var pinned: [FileOperation] {
        OperationDiscovery.pinned(from: model.availableOperations, identifiers: model.pinnedOperationIDs)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                TextField(model.text("Find A Format Or Tool", "Biçim Veya Araç Ara"), text: $query)
                    .textFieldStyle(.plain).font(.system(size: 13)).focused($searchFocused)
                    .accessibilityIdentifier("workspace.operation-search")
                    .onChange(of: query) { value in if value.count > 512 { query = String(value.prefix(512)) } }
                    .onSubmit { if operations.count == 1 { model.begin(operations[0]) } }
                    .onExitCommand { if query.isEmpty { searchFocused = false } else { query = "" } }
                if query.isEmpty {
                    Text("⌘F").font(.system(size: 11)).foregroundStyle(Palette.muted).accessibilityHidden(true)
                } else {
                    Button { query = ""; searchFocused = true } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(Palette.muted)
                        .accessibilityLabel(model.text("Clear Search", "Aramayı Temizle"))
                }
            }.padding(12).background(Palette.panel, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.line))
            if !searching && !pinned.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.text("Pinned", "Sabitlenenler")).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.muted)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(pinned) { operation in
                            Button { model.begin(operation) } label: {
                                Label(OperationNames.title(operation, language: model.language), systemImage: operation.symbol)
                                    .font(.system(size: 12, weight: .medium)).lineLimit(1)
                                    .padding(.horizontal, 11).padding(.vertical, 9).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Palette.raised, in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain).foregroundStyle(Palette.ink)
                                .contextMenu { Button(model.text("Unpin", "Sabitlemeyi Kaldır")) { model.togglePin(operation) } }
                        }
                    }
                }
            }
            if operations.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.text(searching ? "No Matching Tools" : "No Tools For This Selection",
                                    searching ? "Eşleşen Araç Yok" : "Bu Seçim İçin Araç Yok"))
                        .font(.system(size: 14, weight: .medium))
                    Text(model.text(searching ? "Try A Format Like WebP Or A Tool Like Crop." : "File Actions Work With Any Selection.",
                                    searching ? "WebP Gibi Bir Biçim Veya Kırp Gibi Bir Araç Dene." : "Dosya İşlemleri Her Seçimle Çalışır."))
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                }.padding(.vertical, 18)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(operations) { operation in OperationCard(operation: operation, model: model) }
                }
            }
        }
        .onChange(of: model.mode) { _ in query = "" }
        .onChange(of: model.operationSearchRequest) { _ in consumeSearchRequest() }
        .onAppear { consumeSearchRequest() }
    }

    private func consumeSearchRequest() {
        guard model.operationSearchRequest != nil else { return }
        model.operationSearchRequest = nil
        DispatchQueue.main.async { searchFocused = true }
    }
}
#endif
