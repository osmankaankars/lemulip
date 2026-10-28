#if os(macOS)
import SwiftUI
import LemulipCore

struct OperationOptionsView: View {
    @ObservedObject var model: AppController
    let operation: FileOperation
    @State private var quality = 0.82
    @State private var maxDimension = "1920"
    @State private var pageRange = "1"
    @State private var rotation = 90
    @State private var speed = 2.0
    @State private var volume = 1.5
    @State private var flattenAcknowledged = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 13) {
                Image(systemName: operation.symbol).font(.system(size: 24)).foregroundStyle(Palette.accent)
                VStack(alignment: .leading, spacing: 5) {
                    Text(OperationNames.title(operation, language: model.language)).font(.system(size: 21, weight: .semibold)).tracking(-0.5)
                    Text(model.text("A new copy will be created.", "Yeni bir kopya oluşturulur.")).font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
            }
            VStack(alignment: .leading, spacing: 18) {
                if operation.id.hasSuffix("compress") {
                    HStack { Text(model.text("Quality", "Kalite")); Spacer(); Text("\(Int(quality * 100))% ").monospacedDigit().foregroundStyle(Palette.accent) }
                    Slider(value: $quality, in: 0.15...1, step: 0.01)
                    HStack { Text(model.text("Smaller File", "Daha küçük dosya")); Spacer(); Text(model.text("Higher Quality", "Daha yüksek kalite")) }.font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
                if operation.id.hasSuffix("resize") || operation.id == "pdf.compress" {
                    field(model.text("Maximum Dimension (px)", "En büyük kenar (piksel)"), value: $maxDimension)
                    Text(model.text("Keeps the aspect ratio and never enlarges smaller images.", "En boy oranını korur; küçük görselleri büyütmez."))
                        .font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
                if operation.id.hasSuffix("rotate") {
                    Picker(model.text("Clockwise Rotation", "Saat yönünde dönüş"), selection: $rotation) { Text("90°").tag(90); Text("180°").tag(180); Text("270°").tag(270) }.pickerStyle(.segmented)
                }
                if operation.id == "pdf.extract" {
                    field(model.text("Page Numbers and Ranges", "Sayfalar ve aralıklar"), value: $pageRange)
                    Text(model.text("For example: 1, 3-5, 8. Page numbering starts at 1.", "Örnek: 1, 3-5, 8. Sayfa numaraları 1'den başlar."))
                        .font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
                if operation.id == "media.speed" {
                    HStack { Text(model.text("Playback Speed", "Oynatma hızı")); Spacer(); Text(String(format: "%.2f×", speed)).foregroundStyle(Palette.accent).monospacedDigit() }
                    Slider(value: $speed, in: 0.5...4, step: 0.25)
                }
                if operation.id == "media.volume" {
                    HStack { Text(model.text("Volume", "Ses düzeyi")); Spacer(); Text("\(Int(volume * 100))%").foregroundStyle(Palette.accent).monospacedDigit() }
                    Slider(value: $volume, in: 0...3, step: 0.05)
                }
                if operation.id == "pdf.compress" {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(model.text("PDF compression turns pages into images. Searchable text, links, forms, signatures, and accessibility tags are not kept in the new copy. The original PDF is preserved. Some files may become larger.", "PDF sıkıştırma, sayfaları görsele dönüştürür. Yeni kopyada aranabilir metin, bağlantı, form, imza ve erişilebilirlik etiketleri korunmaz. Orijinal PDF korunur. Bazı dosyalar büyüyebilir."))
                            .font(.system(size: 11)).foregroundStyle(.orange).lineSpacing(3)
                        Toggle(model.text("Create a Flattened Copy", "Sayfaları görsele dönüştürerek kopya oluştur"), isOn: $flattenAcknowledged).font(.system(size: 11))
                    }.padding(13).background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                }
                if let validationError { Text(validationError).font(.system(size: 11)).foregroundStyle(.orange) }
            }.font(.system(size: 12))
            }.padding(24)
            Divider().overlay(Palette.line)
            EditorFooter(language: model.language,
                         isEnabled: validationError == nil && !(operation.id == "pdf.compress" && !flattenAcknowledged),
                         onCancel: { model.cancelPending() }, onSubmit: submit)
        }.frame(width: 520).background(Palette.background).foregroundStyle(Palette.ink).tint(Palette.accent)
    }
    private func field(_ title: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) { Text(title).font(.system(size: 11)).foregroundStyle(Palette.muted); TextField("", text: value).textFieldStyle(.roundedBorder) }
    }
    private var validationError: String? {
        if operation.id.hasSuffix("resize") || operation.id == "pdf.compress" {
            guard let dimension = Int(maxDimension), (16...16000).contains(dimension) else { return model.text("Enter a dimension between 16 and 16000 pixels.", "16 ile 16000 piksel arasında bir ölçü gir.") }
        }
        if operation.id == "pdf.extract" && pageRange.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return model.text("Enter at least one page number.", "En az bir sayfa numarası gir.") }
        return nil
    }
    private func submit() {
        var options = ConversionOptions()
        options.quality = quality; options.maxDimension = Int(maxDimension) ?? 1920
        options.pageRange = pageRange; options.rotationDegrees = rotation; options.speedMultiplier = speed; options.volumeMultiplier = volume
        model.submitPending(options)
    }
}
#endif
