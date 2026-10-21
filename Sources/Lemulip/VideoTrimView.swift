#if os(macOS)
import AppKit
import AVFoundation
import QuartzCore
import SwiftUI
import LemulipCore

@MainActor
struct VideoTrimView: View {
    private enum OutputFormat: String, CaseIterable, Identifiable {
        case mp4, mov
        var id: String { rawValue }
        var title: String { rawValue.uppercased() }
    }

    @ObservedObject var model: AppController
    let inputs: [URL]
    @StateObject private var playback = VideoTrimPlayback()
    @State private var preview: VideoTrimPreview?
    @State private var selection: VideoTrimSelection?
    @State private var startText = ""
    @State private var endText = ""
    @State private var outputFormat = OutputFormat.mp4
    @State private var loadError: String?
    @State private var previewWorker: Task<VideoTrimPreview, Error>?
    @State private var previewLoadID = UUID()

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 24).padding(.vertical, 20)
            Rectangle().fill(Palette.line).frame(height: 1)
            if let preview, let selection {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 22) {
                            videoSurface.frame(height: 236)
                            selectionControls(preview: preview, selection: selection)
                                .frame(width: 224, alignment: .leading)
                        }
                        VideoTrimTimelineView(thumbnails: preview.thumbnails,
                            selection: Binding(get: { self.selection ?? selection }, set: { setSelection($0) }),
                            playheadSeconds: playback.positionSeconds, theme: model.theme, language: model.language,
                            onSeek: { seek(to: $0) }, onTogglePlayback: { togglePlayback() })
                            .frame(height: 118)
                        transport(selection: selection)
                        if let error = validationError ?? playback.errorMessage {
                            Label(error, systemImage: "exclamationmark.circle")
                                .font(.system(size: 11)).foregroundStyle(Palette.accent)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(model.text("Drag handles to trim, or drag inside to move the range. Click to seek; drag the ruler to scrub. Focus the timeline: S selects Start, E selects End, P selects the playhead; arrows adjust by 0.01 s, Shift by 1 s. Space plays or pauses.",
                                            "Tutamaklarla kırp, aralığı taşımak için içini sürükle. Önizlemek için tıkla; zaman cetvelini sürükleyerek ilerle. Zaman çizelgesinde S başlangıcı, E bitişi, P oynatma konumunu seçer; oklar 0,01 sn, Shift ile 1 sn ayarlar. Boşluk oynatır veya duraklatır."))
                            .font(.system(size: 10)).foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }.padding(24)
                }
            } else {
                loadingState.frame(maxWidth: .infinity, maxHeight: .infinity).padding(40)
            }
            Rectangle().fill(Palette.line).frame(height: 1)
            footer.padding(.horizontal, 24).padding(.vertical, 17)
        }
        .frame(width: 840, height: 680)
        .background(Palette.background).foregroundStyle(Palette.ink).tint(Palette.accent)
        .task(id: inputs) { await loadPreview() }
        .onDisappear { closePreview() }
    }

    private var header: some View {
        HStack(spacing: 13) {
            Image(systemName: "film").font(.system(size: 25)).foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 5) {
                Text(model.text("Trim Video", "Videoyu kırp")).font(.system(size: 23, weight: .semibold)).tracking(-0.5)
                Text(inputs.count == 1 ? inputs[0].lastPathComponent : model.text("Choose a Single Video", "Tek bir video seç"))
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 16)
            if let preview {
                VStack(alignment: .trailing, spacing: 5) {
                    Text(VideoTrimTime.string(preview.durationSeconds))
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                    Text(videoDetails(preview)).font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
            }
        }
    }

    private var videoSurface: some View {
        ZStack {
            Color.black
            VideoPlayerSurface(player: playback.player, language: model.language)
            if !playback.isReady && playback.errorMessage == nil {
                ProgressView().controlSize(.regular).tint(.white)
                    .accessibilityLabel(model.text("Preparing Video Playback", "Video önizlemesi hazırlanıyor"))
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line, lineWidth: 1))
    }

    private func selectionControls(preview: VideoTrimPreview, selection: VideoTrimSelection) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                timeField(model.text("Start", "Başlangıç"), text: Binding(get: { startText }, set: { startText = $0; applyTimes() }))
                timeField(model.text("End", "Bitiş"), text: Binding(get: { endText }, set: { endText = $0; applyTimes() }))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(model.text("Selected Duration", "Seçilen süre")).font(.system(size: 10)).foregroundStyle(Palette.muted)
                Text(VideoTrimTime.string(selection.durationSeconds))
                    .font(.system(size: 17, weight: .semibold, design: .monospaced)).foregroundStyle(Palette.accent)
                    .accessibilityLabel(model.text("Selected Duration", "Seçilen süre"))
                    .accessibilityValue(VideoTrimTime.string(selection.durationSeconds))
            }
            Rectangle().fill(Palette.line).frame(height: 1)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 14) {
                    Text(model.text("Save As", "Çıktı biçimi")).font(.system(size: 11)).foregroundStyle(Palette.muted)
                    Spacer(minLength: 0)
                    Picker(model.text("Save As", "Çıktı biçimi"), selection: $outputFormat) {
                        ForEach(availableFormats(preview)) { format in Text(format.title).tag(format) }
                    }.labelsHidden().pickerStyle(.menu).frame(width: 93)
                }
                Text(model.text("Re-Encoded Video Copy", "Yeniden kodlanmış video kopyası"))
                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
            Button(model.text("Reset Selection", "Seçimi sıfırla")) { reset() }
                .font(.system(size: 11))
                .disabled(selection.startSeconds == 0 && selection.endSeconds == selection.sourceDuration && validationError == nil)
        }
    }

    private func timeField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 10)).foregroundStyle(Palette.muted)
            TextField("00:00.000", text: text).textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced)).accessibilityLabel(title)
            Text(model.text("Time or Seconds", "Süre veya saniye")).font(.system(size: 9)).foregroundStyle(Palette.muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func transport(selection: VideoTrimSelection) -> some View {
        HStack(spacing: 14) {
            Button { togglePlayback() } label: {
                Label(playback.isPlaybackRequested ? model.text("Pause", "Duraklat") : model.text("Play Selection", "Seçimi oynat"),
                      systemImage: playback.isPlaybackRequested ? "pause.fill" : "play.fill")
                    .frame(minWidth: 118)
            }.controlSize(.large)
                .disabled((!playback.isReady && !playback.isPlaybackRequested) || validationError != nil)
            Button { seek(to: selection.startSeconds) } label: {
                Image(systemName: "backward.end.fill")
            }
            .help(model.text("Go to Selection Start", "Seçimin başlangıcına git"))
            .accessibilityLabel(model.text("Go to Selection Start", "Seçimin başlangıcına git"))
            .disabled(!playback.isReady || validationError != nil)
            Text(VideoTrimTime.string(playback.positionSeconds))
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.muted)
                .accessibilityLabel(model.text("Playback Position", "Oynatma konumu"))
                .accessibilityValue(VideoTrimTime.string(playback.positionSeconds))
            if playback.isSeeking && !playback.isPlaybackRequested {
                ProgressView().controlSize(.small).accessibilityLabel(model.text("Seeking", "Konuma gidiliyor"))
            }
            Spacer(minLength: 6)
            if playback.errorMessage != nil {
                Button(model.text("Retry Playback", "Oynatmayı yeniden dene")) { preparePlayback(selection) }
                    .font(.system(size: 11))
            }
            Text(model.text("Playback Stays Inside Your Selection", "Önizleme seçtiğin aralıkta kalır"))
                .font(.system(size: 10)).foregroundStyle(Palette.muted)
        }
    }

    @ViewBuilder private var loadingState: some View {
        if let loadError {
            VStack(spacing: 13) {
                Image(systemName: "exclamationmark.circle").font(.system(size: 32)).foregroundStyle(Palette.accent)
                Text(model.text("Could Not Open the Video Editor", "Video düzenleyicisi açılamadı"))
                    .font(.system(size: 19, weight: .semibold))
                Text(loadError).font(.system(size: 13)).foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center).frame(maxWidth: 530)
            }
        } else {
            VStack(spacing: 15) {
                ProgressView().controlSize(.regular)
                Text(model.text("Preparing Your Video…", "Videon hazırlanıyor…"))
                    .font(.system(size: 13)).foregroundStyle(Palette.muted)
                Text(model.text("Reading a small thumbnail overview. You can cancel at any time.", "Küçük bir kare özeti hazırlanıyor. İstediğin an vazgeçebilirsin."))
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

    private var parsedSelection: VideoTrimSelection? {
        guard let selection else { return nil }
        return VideoTrimTime.selection(startText: startText, endText: endText, preserving: selection)
    }

    private var validationError: String? {
        guard let preview else { return nil }
        guard let parsed = parsedSelection else {
            return model.text("Enter a start and end inside the video, with End after Start. Use seconds, MM:SS, or HH:MM:SS.",
                              "Videonun içinde, bitişi başlangıçtan sonra olan bir aralık gir. Saniye, dakika:saniye veya saat:dakika:saniye kullan.")
        }
        let minimum = VideoTrimGeometry.minimumDuration(sourceDuration: preview.durationSeconds)
        guard parsed.durationSeconds + 0.000_000_001 >= minimum else {
            return model.text("Keep at least \(VideoTrimTime.string(minimum)) of video.", "En az \(VideoTrimTime.string(minimum)) uzunluğunda video seç.")
        }
        return nil
    }

    private func availableFormats(_ preview: VideoTrimPreview) -> [OutputFormat] {
        OutputFormat.allCases.filter { preview.nativeOutputExtensions.contains($0.rawValue) }
    }

    private func videoDetails(_ preview: VideoTrimPreview) -> String {
        let dimensions = "\(preview.displayWidth) × \(preview.displayHeight)"
        guard let frameRate = preview.nominalFrameRate, frameRate.isFinite, frameRate > 0 else { return dimensions }
        return dimensions + String(format: " · %.2f fps", frameRate)
    }

    private func setSelection(_ value: VideoTrimSelection) {
        let old = selection
        selection = value
        startText = VideoTrimTime.string(value.startSeconds)
        endText = VideoTrimTime.string(value.endSeconds)
        let edge = old?.startSeconds == value.startSeconds && old?.endSeconds != value.endSeconds ? value.endSeconds : value.startSeconds
        playback.changeSelection(value, previewing: edge)
    }

    private func applyTimes() {
        playback.pause()
        guard validationError == nil, let value = parsedSelection else { return }
        let old = selection
        selection = value
        let edge = old?.startSeconds == value.startSeconds && old?.endSeconds != value.endSeconds ? value.endSeconds : value.startSeconds
        playback.changeSelection(value, previewing: edge)
    }

    private func reset() {
        guard let preview else { return }
        setSelection(VideoTrimGeometry.fullDuration(preview.durationSeconds))
    }

    private func seek(to seconds: Double) {
        guard validationError == nil else { return }
        playback.seek(to: seconds)
    }

    private func togglePlayback() {
        guard validationError == nil else { return }
        playback.togglePlayback()
    }

    private func preparePlayback(_ selection: VideoTrimSelection) {
        guard let input = inputs.first else { return }
        playback.prepare(url: input, selection: selection)
    }

    private func loadPreview() async {
        closePreview()
        loadError = nil
        let generation = UUID()
        previewLoadID = generation
        guard inputs.count == 1, let input = inputs.first, FileFamily.detect(input) == .video else {
            loadError = model.text("Trim Video works with one video at a time. Cancel and select a single video. To trim audio, select one audio file instead.",
                                   "Video düzenleyicisi tek videoyla çalışır. Vazgeçip bir video seç. Ses kırpmak için bir ses dosyası seçebilirsin.")
            return
        }
        let worker = Task.detached(priority: .userInitiated) {
            try await NativeConverter.videoTrimPreview(for: input, maxThumbnailCount: 12, maxPixelSize: 192)
        }
        previewWorker = worker
        defer { if previewLoadID == generation { previewWorker = nil } }
        do {
            let result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
            try Task.checkCancellation()
            guard previewLoadID == generation else { return }
            guard let format = availableFormats(result).first else {
                throw LemulipError.unsupported("No native video output format is available for this file. Convert it to MP4 or MOV, then reopen Trim Video.")
            }
            preview = result
            outputFormat = format
            let fullSelection = VideoTrimGeometry.fullDuration(result.durationSeconds)
            setSelection(fullSelection)
            preparePlayback(fullSelection)
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
        preview = nil
        selection = nil
    }

    private func submit() {
        guard validationError == nil, let selection, let preview,
              availableFormats(preview).contains(outputFormat) else { return }
        var options = ConversionOptions()
        options.videoTrim = selection
        closePreview()
        model.submitPending(options, outputExtension: outputFormat.rawValue)
    }
}

/// AVPlayerLayer preserves the video's display transform and aspect ratio.
/// Its only controls live in the editor, so playback cannot escape the range.
@MainActor
struct VideoPlayerSurface: NSViewRepresentable {
    let player: AVPlayer?
    let language: String
    var onReadinessChanged: ((Bool) -> Void)?

    func makeNSView(context: Context) -> VideoPlayerLayerView {
        let view = VideoPlayerLayerView(frame: .zero)
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: VideoPlayerLayerView, context: Context) {
        view.setPlayer(player, onReadinessChanged: onReadinessChanged)
        view.setAccessibilityLabel(language == "tr" ? "Video önizlemesi" : "Video Preview")
        view.setAccessibilityHelp(language == "tr"
            ? "Zaman çizelgesiyle bir kare seç, Oynat düğmesiyle seçtiğin aralığı izle."
            : "Use the timeline to choose a frame and Play Selection to watch the selected range.")
    }

    static func dismantleNSView(_ view: VideoPlayerLayerView, coordinator: ()) {
        view.disconnectPlayer()
    }
}

@MainActor
final class VideoPlayerLayerView: NSView {
    private var playerLayer = AVPlayerLayer()
    private var readinessObservation: NSKeyValueObservation?
    private var readinessGeneration = UUID()
    private var onReadinessChanged: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.black.cgColor
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(playerLayer)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
    }

    required init?(coder: NSCoder) { return nil }

    deinit { readinessObservation?.invalidate() }

    func setPlayer(_ player: AVPlayer?, onReadinessChanged: ((Bool) -> Void)?) {
        self.onReadinessChanged = onReadinessChanged
        guard playerLayer.player !== player else { return }
        readinessGeneration = UUID()
        readinessObservation?.invalidate()
        readinessObservation = nil
        playerLayer.player = nil
        playerLayer.removeFromSuperlayer()
        // A fresh layer cannot expose a frame retained from a previous player.
        // Its readiness event confirms actual video output, not a finished or
        // cancelled seek. The still image stays visible until that event.
        let videoLayer = AVPlayerLayer()
        videoLayer.videoGravity = .resizeAspect
        videoLayer.backgroundColor = NSColor.black.cgColor
        videoLayer.frame = bounds
        playerLayer = videoLayer
        layer?.addSublayer(videoLayer)
        let generation = readinessGeneration
        readinessObservation = videoLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, self.readinessGeneration == generation else { return }
                self.onReadinessChanged?(self.playerLayer.player != nil && self.playerLayer.isReadyForDisplay)
            }
        }
        videoLayer.player = player
    }

    func disconnectPlayer() {
        readinessGeneration = UUID()
        readinessObservation?.invalidate()
        readinessObservation = nil
        onReadinessChanged = nil
        playerLayer.player = nil
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}
#endif
