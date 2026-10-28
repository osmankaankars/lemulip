#if os(macOS)
import SwiftUI
import LemulipCore

@MainActor
struct ImageCropView: View {
    @ObservedObject var model: AppController
    let inputs: [URL]
    @State private var preview: ImageCropPreview?
    @State private var selection: ImageCropRegion?
    @State private var ratio = CropAspectRatio.free
    @State private var showsGrid = true
    @State private var widthText = ""
    @State private var heightText = ""
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            header.padding(24)
            Rectangle().fill(Palette.line).frame(height: 1)
            if let preview, let selection {
                HStack(alignment: .top, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        CropCanvasView(image: preview.image,
                            selection: Binding(get: { self.selection ?? selection }, set: { setSelection($0) }),
                            aspectRatio: ratio.value(width: preview.sourceWidth, height: preview.sourceHeight),
                            showsGrid: showsGrid, theme: model.theme, language: model.language)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Text(model.text("Drag a handle to resize. Drag inside to move.", "Boyut için tutamakları, taşımak için seçimin içini sürükle."))
                            .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }
                    ScrollView {
                        inspector(preview: preview, selection: selection)
                    }.frame(width: 205)
                }.padding(24)
            } else {
                loadingState.frame(maxWidth: .infinity, maxHeight: .infinity).padding(40)
            }
            Rectangle().fill(Palette.line).frame(height: 1)
            footer
        }
        .frame(width: 820, height: 590)
        .background(Palette.background).foregroundStyle(Palette.ink).tint(Palette.accent)
        .task { await loadPreview() }
    }

    private var header: some View {
        HStack(spacing: 13) {
            Image(systemName: "crop").font(.system(size: 24)).foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 5) {
                Text(model.text("Crop Image", "Görseli kırp")).font(.system(size: 21, weight: .semibold)).tracking(-0.5)
                Text(inputs.count == 1 ? inputs[0].lastPathComponent : model.text("Choose a Single Image", "Tek bir görsel seç"))
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 16)
            if let preview {
                VStack(alignment: .trailing, spacing: 5) {
                    Text("\(preview.sourceWidth) × \(preview.sourceHeight) px")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                    Text(model.text("Original Size", "Orijinal boyut"))
                        .font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
            }
        }
    }

    private func inspector(preview: ImageCropPreview, selection: ImageCropRegion) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 9) {
                Text(model.text("Aspect Ratio", "En boy oranı")).font(.system(size: 12, weight: .semibold))
                Picker(model.text("Aspect Ratio", "En boy oranı"), selection: Binding(get: { ratio }, set: { changeRatio($0) })) {
                    ForEach(CropAspectRatio.allCases) { option in
                        Text(option == .free ? model.text("Free", "Serbest") : option == .original ? model.text("Original", "Orijinal") : option.rawValue)
                            .tag(option)
                    }
                }.labelsHidden().pickerStyle(.menu)
            }
            VStack(alignment: .leading, spacing: 9) {
                Text(model.text("Output Size", "Çıktı boyutu")).font(.system(size: 12, weight: .semibold))
                HStack(spacing: 10) {
                    dimensionField(model.text("Width (px)", "Genişlik (px)"), text: Binding(get: { widthText }, set: { widthText = $0; applyDimensions() }))
                    dimensionField(model.text("Height (px)", "Yükseklik (px)"), text: Binding(get: { heightText }, set: { heightText = $0; applyDimensions() }))
                }
                Text(model.text("Enter exact dimensions to use a free ratio.", "Serbest oran için tam piksel ölçülerini gir."))
                    .font(.system(size: 10)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
            if let validationError {
                Label(validationError, systemImage: "exclamationmark.circle")
                    .font(.system(size: 11)).foregroundStyle(Palette.accent)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(validationError)
            }
            Toggle(model.text("Show Grid", "Izgarayı göster"), isOn: $showsGrid).font(.system(size: 12))
            VStack(alignment: .leading, spacing: 7) {
                Text(model.text("Fine Adjustment", "Hassas ayar")).font(.system(size: 12, weight: .semibold))
                Text(model.text("Focus the image, then use arrow keys to move by 1 px. Hold Shift for 10 px.", "Görsele odaklan; ok tuşlarıyla 1 px, Shift ile 10 px taşı."))
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                Text(model.text("Left \(selection.x) · Top \(selection.y) px", "Sol \(selection.x) · Üst \(selection.y) px"))
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 0)
            Button(model.text("Reset", "Sıfırla")) { reset(preview) }
                .font(.system(size: 12)).disabled(selection == ImageCropGeometry.fullImage(width: preview.sourceWidth, height: preview.sourceHeight) && ratio == .free && validationError == nil)
        }
    }

    private func dimensionField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 10)).foregroundStyle(Palette.muted)
            TextField(title, text: text).textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced)).accessibilityLabel(title)
        }
    }

    @ViewBuilder private var loadingState: some View {
        if let loadError {
            VStack(spacing: 13) {
                Image(systemName: "exclamationmark.circle").font(.system(size: 32)).foregroundStyle(Palette.accent)
                Text(model.text("Could Not Open the Crop Editor", "Kırpma düzenleyicisi açılamadı"))
                    .font(.system(size: 19, weight: .semibold))
                Text(loadError).font(.system(size: 13)).foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center).frame(maxWidth: 470)
            }
        } else {
            VStack(spacing: 15) {
                ProgressView().controlSize(.regular)
                Text(model.text("Preparing Your Image…", "Görselin hazırlanıyor…")).font(.system(size: 13)).foregroundStyle(Palette.muted)
            }
        }
    }

    private var footer: some View {
        EditorFooter(language: model.language,
            isEnabled: selection != nil && validationError == nil && loadError == nil,
            onCancel: { model.cancelPending() }, onSubmit: { submit() })
    }

    private var validationError: String? {
        guard let preview else { return nil }
        guard let width = Int(widthText), let height = Int(heightText),
              (1...preview.sourceWidth).contains(width), (1...preview.sourceHeight).contains(height) else {
            return model.text("Enter a width from 1–\(preview.sourceWidth) and a height from 1–\(preview.sourceHeight) pixels.",
                              "Genişlik 1–\(preview.sourceWidth), yükseklik 1–\(preview.sourceHeight) piksel arasında olmalı.")
        }
        return nil
    }

    private func setSelection(_ value: ImageCropRegion) {
        selection = value
        widthText = String(value.width)
        heightText = String(value.height)
    }

    private func applyDimensions() {
        guard validationError == nil, let selection,
              let width = Int(widthText), let height = Int(heightText) else { return }
        ratio = .free
        self.selection = ImageCropGeometry.sized(selection, width: width, height: height)
    }

    private func changeRatio(_ value: CropAspectRatio) {
        ratio = value
        guard let preview, let selection else { return }
        if let aspect = value.value(width: preview.sourceWidth, height: preview.sourceHeight) {
            setSelection(ImageCropGeometry.fitted(selection, aspectRatio: aspect))
        } else {
            setSelection(selection)
        }
    }

    private func reset(_ preview: ImageCropPreview) {
        ratio = .free
        setSelection(ImageCropGeometry.fullImage(width: preview.sourceWidth, height: preview.sourceHeight))
    }

    private func loadPreview() async {
        guard inputs.count == 1, let input = inputs.first else {
            loadError = model.text("Interactive cropping works with one image at a time. Cancel and select a single image to continue.",
                                   "Görsel kırpma tek dosyayla çalışır. Vazgeç ve devam etmek için bir görsel seç.")
            return
        }
        let worker = Task.detached(priority: .userInitiated) {
            try NativeConverter.imageCropPreview(for: input, maxPixelSize: 1600)
        }
        do {
            let result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
            try Task.checkCancellation()
            preview = result
            reset(result)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            loadError = error.localizedDescription
        }
    }

    private func submit() {
        guard validationError == nil, let selection else { return }
        var options = ConversionOptions()
        options.width = selection.width
        options.height = selection.height
        options.imageCrop = selection
        model.submitPending(options)
    }
}
#endif
