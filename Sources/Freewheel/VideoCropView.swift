#if os(macOS)
import SwiftUI
import FreewheelCore

@MainActor
struct VideoCropView: View {
    private enum OutputFormat: String, CaseIterable, Identifiable {
        case mp4, mov
        var id: String { rawValue }
        var title: String { rawValue.uppercased() }
    }

    @ObservedObject var model: AppController
    let inputs: [URL]
    @StateObject private var playback = VideoTrimPlayback()
    @State private var preview: VideoCropPreview?
    @State private var selection: ImageCropRegion?
    @State private var ratio = CropAspectRatio.free
    @State private var showsGrid = true
    @State private var widthText = ""
    @State private var heightText = ""
    @State private var outputFormat = OutputFormat.mp4
    @State private var hasVideoFrame = false
    @State private var loadError: String?
    @State private var previewWorker: Task<VideoCropPreview, Error>?
    @State private var previewLoadID = UUID()

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 24).padding(.vertical, 20)
            Rectangle().fill(Palette.line).frame(height: 1)
            if let preview, let selection {
                HStack(alignment: .top, spacing: 22) {
                    VStack(alignment: .leading, spacing: 12) {
                        cropSurface(preview: preview, selection: selection)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        transport
                        scrubber(preview: preview)
                        Text(model.text("Drag a handle to resize. Drag inside to move. The crop applies to the whole video.",
                                            "Boyut için tutamakları, taşımak için seçimin içini sürükle. Kırpma tüm videoya uygulanır."))
                            .font(.system(size: 11)).foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ScrollView { inspector(preview: preview, selection: selection) }
                        .frame(width: 215)
                }.padding(24)
            } else {
                loadingState.frame(maxWidth: .infinity, maxHeight: .infinity).padding(40)
            }
            Rectangle().fill(Palette.line).frame(height: 1)
            footer.padding(.horizontal, 24).padding(.vertical, 17)
        }
        .frame(width: 840, height: 670)
        .background(Palette.background).foregroundStyle(Palette.ink).tint(Palette.accent)
        .task(id: inputs) { await loadPreview() }
        .onDisappear { closePreview() }
    }

    private var header: some View {
        HStack(spacing: 13) {
            Image(systemName: "crop").font(.system(size: 25)).foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 5) {
                Text(model.text("Crop Video", "Video kadrajını kırp"))
                    .font(.system(size: 23, weight: .semibold)).tracking(-0.5)
                Text(inputs.count == 1 ? inputs[0].lastPathComponent : model.text("Choose a Single Video", "Tek bir video seç"))
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 16)
            if let preview {
                VStack(alignment: .trailing, spacing: 5) {
                    Text("\(preview.sourceWidth) × \(preview.sourceHeight) px")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                    Text(VideoTrimTime.string(preview.durationSeconds))
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
                }
            }
        }
    }

    private func cropSurface(preview: VideoCropPreview, selection: ImageCropRegion) -> some View {
        GeometryReader { geometry in
            let frame = CropCanvasLayout.imageFrame(in: CGRect(origin: .zero, size: geometry.size),
                sourceWidth: preview.sourceWidth, sourceHeight: preview.sourceHeight)
            ZStack(alignment: .topLeading) {
                Palette.raised
                Image(decorative: preview.image, scale: 1, orientation: .up)
                    .resizable().interpolation(.high)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .accessibilityHidden(true)
                VideoPlayerSurface(player: playback.player, language: model.language,
                    onReadinessChanged: { ready in
                        hasVideoFrame = ready && self.preview != nil && playback.player != nil
                    })
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .opacity(hasVideoFrame ? 1 : 0)
                    .allowsHitTesting(false).accessibilityHidden(true)
                CropCanvasView(image: preview.image,
                    selection: Binding(get: { self.selection ?? selection }, set: { setSelection($0) }),
                    aspectRatio: ratio.value(width: preview.sourceWidth, height: preview.sourceHeight),
                    showsGrid: showsGrid, theme: model.theme, language: model.language,
                    media: .video, selectionTransform: VideoCropGeometry.normalized,
                    onInteractionBegan: { playback.pause() }, onTogglePlayback: { togglePlayback() })
                    .zIndex(1)
            }.clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var transport: some View {
        HStack(spacing: 12) {
            Button { togglePlayback() } label: {
                Label(playback.isPlaybackRequested ? model.text("Pause", "Duraklat") : model.text("Play Video", "Videoyu oynat"),
                      systemImage: playback.isPlaybackRequested ? "pause.fill" : "play.fill")
                    .frame(minWidth: 92)
            }.controlSize(.large)
                .disabled(!playback.isReady && !playback.isPlaybackRequested)
            Button { playback.seek(to: 0) } label: {
                Image(systemName: "backward.end.fill")
            }
            .accessibilityLabel(model.text("Go to Start", "Başlangıca git"))
            .help(model.text("Go to Start", "Başlangıca git"))
            .disabled(!playback.isReady)
            Spacer(minLength: 0)
            if !hasVideoFrame {
                if playback.errorMessage == nil { ProgressView().controlSize(.small) }
                Text(model.text("Still Frame Preview", "Sabit kare önizlemesi"))
                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
            } else if playback.isSeeking {
                ProgressView().controlSize(.small)
                    .accessibilityLabel(model.text("Seeking", "Konuma gidiliyor"))
            }
        }
    }

    private func scrubber(preview: VideoCropPreview) -> some View {
        HStack(spacing: 10) {
            Text(VideoTrimTime.string(playback.positionSeconds))
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
                .accessibilityLabel(model.text("Playback Position", "Oynatma konumu"))
                .accessibilityValue(VideoTrimTime.string(playback.positionSeconds))
            Slider(value: Binding(get: {
                min(preview.durationSeconds, max(0, playback.positionSeconds))
            }, set: { playback.seek(to: $0) }), in: 0...preview.durationSeconds,
                step: min(0.01, preview.durationSeconds))
                .accessibilityLabel(model.text("Preview Position", "Önizleme konumu"))
                .accessibilityValue(VideoTrimTime.string(playback.positionSeconds))
                .disabled(!playback.isReady)
            Text(VideoTrimTime.string(preview.durationSeconds))
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
        }
    }

    private func inspector(preview: VideoCropPreview, selection: ImageCropRegion) -> some View {
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
            }
            Toggle(model.text("Show Grid", "Izgarayı göster"), isOn: $showsGrid).font(.system(size: 12))
            VStack(alignment: .leading, spacing: 7) {
                Text(model.text("Fine Adjustment", "Hassas ayar")).font(.system(size: 12, weight: .semibold))
                Text(model.text("Focus the video. Arrow keys move the crop by 1 px, Shift by 10 px. Space plays or pauses.",
                                    "Videoya odaklan. Oklar kadrajı 1 px, Shift ile 10 px taşır. Boşluk oynatır veya duraklatır."))
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                Text(model.text("Left \(selection.x) · Top \(selection.y) px", "Sol \(selection.x) · Üst \(selection.y) px"))
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
            }
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 12) {
                    Text(model.text("Save As", "Çıktı biçimi")).font(.system(size: 12, weight: .semibold))
                    Spacer(minLength: 0)
                    Picker(model.text("Save As", "Çıktı biçimi"), selection: $outputFormat) {
                        ForEach(availableFormats(preview)) { format in Text(format.title).tag(format) }
                    }.labelsHidden().pickerStyle(.menu).frame(width: 90)
                }
                Text(model.text("Re-Encoded Video Copy", "Yeniden kodlanmış video kopyası"))
                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
            Button(model.text("Reset Crop", "Kadrajı sıfırla")) { reset(preview) }
                .font(.system(size: 12))
                .disabled(selection == fullRegion(preview) && ratio == .free && validationError == nil)
            if let error = playback.errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.system(size: 11)).foregroundStyle(Palette.accent)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(model.text("Retry Playback", "Oynatmayı yeniden dene")) { preparePlayback(preview) }
                        .font(.system(size: 11))
                }
            }
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
                Text(model.text("Could Not Open the Video Crop Editor", "Video kadraj düzenleyicisi açılamadı"))
                    .font(.system(size: 19, weight: .semibold))
                Text(loadError).font(.system(size: 13)).foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center).frame(maxWidth: 520)
            }
        } else {
            VStack(spacing: 15) {
                ProgressView().controlSize(.regular)
                Text(model.text("Preparing Your Video…", "Videon hazırlanıyor…"))
                    .font(.system(size: 13)).foregroundStyle(Palette.muted)
                Text(model.text("You can cancel while the preview is being prepared.", "Önizleme hazırlanırken istediğin an vazgeçebilirsin."))
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Label(model.text("Your Original Stays Untouched", "Orijinal dosyan korunur"), systemImage: "checkmark.shield")
                .font(.system(size: 10)).foregroundStyle(Palette.muted)
            Spacer()
            Button(model.text("Cancel", "Vazgeç")) { closePreview(); model.cancelPending() }
                .keyboardShortcut(.cancelAction)
            Button(model.text("Create Copy", "Kopya oluştur")) { submit() }
                .buttonStyle(.borderedProminent).tint(Palette.primaryAction).foregroundStyle(Palette.onPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(selection == nil || validationError != nil || loadError != nil || preview.map({ availableFormats($0).isEmpty }) != false)
        }
    }

    private var validationError: String? {
        guard let preview else { return nil }
        guard let width = Int(widthText), let height = Int(heightText),
              (2...preview.sourceWidth).contains(width), (2...preview.sourceHeight).contains(height) else {
            return model.text("Enter a width from 2–\(preview.sourceWidth) and a height from 2–\(preview.sourceHeight) pixels.",
                              "Genişlik 2–\(preview.sourceWidth), yükseklik 2–\(preview.sourceHeight) piksel arasında olmalı.")
        }
        guard width.isMultiple(of: 2), height.isMultiple(of: 2) else {
            return model.text("Use even pixel dimensions for MP4 and MOV, such as 1080 × 1920.",
                              "MP4 ve MOV için 1080 × 1920 gibi çift piksel ölçüleri kullan.")
        }
        if let selection {
            let candidate = ImageCropGeometry.sized(selection, width: width, height: height)
            do {
                try VideoCropRegion(imageRegion: candidate, sourceDuration: preview.durationSeconds).validate()
            } catch {
                return model.text(error.localizedDescription,
                                  "Kaynak sınırları içinde, her kenarı en az 2 piksel ve toplamı en fazla 40 megapiksel olan bir kadraj seç.")
            }
        }
        return nil
    }

    private func availableFormats(_ preview: VideoCropPreview) -> [OutputFormat] {
        OutputFormat.allCases.filter { preview.nativeOutputExtensions.contains($0.rawValue) }
    }

    private func fullRegion(_ preview: VideoCropPreview) -> ImageCropRegion {
        VideoCropGeometry.normalized(ImageCropGeometry.fullImage(width: preview.sourceWidth, height: preview.sourceHeight))
    }

    private func setSelection(_ value: ImageCropRegion) {
        playback.pause()
        let region = VideoCropGeometry.normalized(value)
        selection = region
        widthText = String(region.width)
        heightText = String(region.height)
    }

    private func applyDimensions() {
        playback.pause()
        guard validationError == nil, let selection,
              let width = Int(widthText), let height = Int(heightText) else { return }
        ratio = .free
        self.selection = VideoCropGeometry.normalized(ImageCropGeometry.sized(selection, width: width, height: height))
    }

    private func changeRatio(_ value: CropAspectRatio) {
        ratio = value
        guard let preview, let selection else { return }
        if let aspect = value.value(width: preview.sourceWidth, height: preview.sourceHeight) {
            setSelection(ImageCropGeometry.fitted(selection, aspectRatio: aspect))
        } else { setSelection(selection) }
    }

    private func reset(_ preview: VideoCropPreview) {
        ratio = .free
        setSelection(fullRegion(preview))
    }

    private func togglePlayback() {
        guard preview != nil else { return }
        playback.togglePlayback()
    }

    private func preparePlayback(_ preview: VideoCropPreview) {
        guard let input = inputs.first else { return }
        hasVideoFrame = false
        playback.prepare(url: input, selection: VideoTrimGeometry.fullDuration(preview.durationSeconds))
        playback.seek(to: preview.frameTimeSeconds)
    }

    private func loadPreview() async {
        closePreview()
        loadError = nil
        let generation = UUID()
        previewLoadID = generation
        guard inputs.count == 1, let input = inputs.first, FileFamily.detect(input) == .video else {
            loadError = model.text("Crop Video works with one video at a time. Cancel and select a single video to continue.",
                                   "Video kadraj düzenleyicisi tek videoyla çalışır. Vazgeç ve devam etmek için bir video seç.")
            return
        }
        let worker = Task.detached(priority: .userInitiated) {
            try await NativeConverter.videoCropPreview(for: input, maxPixelSize: 1_280)
        }
        previewWorker = worker
        defer { if previewLoadID == generation { previewWorker = nil } }
        do {
            let result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
            try Task.checkCancellation()
            guard previewLoadID == generation else { return }
            guard let format = availableFormats(result).first else {
                throw FreewheelError.unsupported("No native video output format is available for this file. Convert it to MP4 or MOV, then reopen Crop Video.")
            }
            preview = result
            outputFormat = format
            reset(result)
            preparePlayback(result)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, previewLoadID == generation else { return }
            loadError = error.localizedDescription
        }
    }

    private func closePreview() {
        previewLoadID = UUID()
        previewWorker?.cancel()
        previewWorker = nil
        playback.shutdown()
        hasVideoFrame = false
        preview = nil
        selection = nil
    }

    private func submit() {
        guard validationError == nil, let selection, let preview,
              availableFormats(preview).contains(outputFormat) else { return }
        var options = ConversionOptions()
        options.videoCrop = VideoCropRegion(imageRegion: selection, sourceDuration: preview.durationSeconds)
        closePreview()
        model.submitPending(options, outputExtension: outputFormat.rawValue)
    }
}
#endif
