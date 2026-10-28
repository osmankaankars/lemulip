#if os(macOS)
import AppKit
import SwiftUI
import LemulipCore

struct ResultCardView: View {
    @ObservedObject var model: AppController
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(model.text("Ready To Use", "Kullanıma Hazır"), systemImage: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.accent)
                Spacer()
                Button { model.dismissResultCard() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).help(model.text("Dismiss", "Kapat"))
                    .accessibilityLabel(model.text("Dismiss Results", "Sonuçları Kapat"))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.completionResults.urls, id: \.self) { url in
                        HStack(spacing: 10) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                .resizable().frame(width: 32, height: 32).accessibilityHidden(true)
                            Button { model.reveal([url]) } label: {
                                Text(url.lastPathComponent).font(.system(size: 12, weight: .medium))
                                    .lineLimit(2).truncationMode(.middle).multilineTextAlignment(.leading)
                            }.buttonStyle(.plain).help(url.lastPathComponent)
                            Spacer(minLength: 0)
                        }.padding(.vertical, 4)
                            .onDrag { NSItemProvider(object: url as NSURL) }
                    }
                }
            }.frame(height: min(152, CGFloat(model.completionResults.urls.count) * 48))
            OutputActions(urls: model.completionResults.urls, model: model)
            if model.completionResults.omittedCount > 0 {
                Button(model.text("More Results In Activity", "Diğer Sonuçlar İşlemlerde")) {
                    model.section = "activity"; model.showMainWindow()
                }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.accent)
            }
        }.padding(18).frame(width: 396, alignment: .topLeading).foregroundStyle(Palette.ink).background(Palette.background)
            .accessibilityIdentifier("completion.results")
    }
}
#endif
