#if os(macOS)
import SwiftUI
import LemulipCore

@MainActor
struct AudioTrimView: View {
    private enum OutputFormat: String, CaseIterable, Identifiable {
        case m4a, wav, aiff
        var id: String { rawValue }
        var title: String {
            switch self {
            case .m4a: return "M4A · AAC"
            case .wav: return "WAV · 16-Bit PCM"
            case .aiff: return "AIFF · 16-Bit PCM"
            }
        }
    }

    @ObservedObject var model: AppController
    let inputs: [URL]
    @StateObject private var playback = AudioTrimPlayback()
    @State private var preview: AudioTrimPreview?
    @State private var selection: AudioTrimSelection?
    @State private var startText = ""
    @State private var endText = ""
    @State private var outputFormat = OutputFormat.m4a
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            header.padding(24)
            Rectangle().fill(Palette.line).frame(height: 1)
            if let preview, let selection {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        AudioWaveformView(peaks: preview.peaks,
                            selection: Binding(get: { self.selection ?? selection }, set: { setSelection($0) }),
                            playheadSeconds: playback.positionSeconds, theme: model.theme, language: model.language,
                            onTogglePlayback: { togglePlayback() })
                            .frame(height: 195)
                        transport(selection: selection)
                        selectionControls(preview: preview, selection: selection)
                        if let error = validationError ?? playback.errorMessage {
                            Label(error, systemImage: "exclamationmark.circle")
                                .font(.system(size: 11)).foregroundStyle(Palette.accent)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(model.text("Drag the handles to trim, or drag inside to move the selection. Focus the waveform: S selects Start, E selects End; arrow keys adjust by 0.01 s, Shift by 1 s. Space plays or pauses.",
                                            "Tutamaklarla kırp, seçimin içini sürükleyerek taşı. Dalga biçimine odaklan: S başlangıcı, E bitişi seçer; oklar 0,01 sn, Shift ile 1 sn ayarlar. Boşluk oynatır veya duraklatır."))
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
        .frame(width: 820, height: 610)
        .background(Palette.background).foregroundStyle(Palette.ink).tint(Palette.accent)
        .task { await loadPreview() }
        .onDisappear { playback.shutdown() }
    }

    private var header: some View {
        HStack(spacing: 13) {
            Image(systemName: "waveform").font(.system(size: 24)).foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 5) {
                Text(model.text("Trim Audio", "Sesi kırp")).font(.system(size: 23, weight: .semibold)).tracking(-0.5)
                Text(inputs.count == 1 ? inputs[0].lastPathComponent : model.text("Choose a Single Audio File", "Tek bir ses dosyası seç"))
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 16)
            if let preview {
                VStack(alignment: .trailing, spacing: 5) {
                    Text(AudioTrimTime.string(preview.durationSeconds)).font(.system(size: 13, weight: .medium, design: .monospaced))
                    Text(String(format: "%.1f kHz", preview.sampleRate / 1_000) + " · "
                         + (preview.channelCount == 1 ? model.text("Mono", "Mono") : model.text("Stereo", "Stereo")))
                        .font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
            }
        }
    }

    private func transport(selection: AudioTrimSelection) -> some View {
        HStack(spacing: 14) {
            Button { togglePlayback() } label: {
                Label(playback.isPlaying || playback.isSeeking ? model.text("Pause", "Duraklat") : model.text("Play Selection", "Seçimi dinle"),
                      systemImage: playback.isPlaying || playback.isSeeking ? "pause.fill" : "play.fill")
                    .frame(minWidth: 116)
            }.controlSize(.large)
                .disabled((!playback.isReady && !playback.isPlaying && !playback.isSeeking) || validationError != nil)
            Text(AudioTrimTime.string(playback.positionSeconds)).font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.muted)
                .accessibilityLabel(model.text("Playback Position", "Oynatma konumu"))
                .accessibilityValue(AudioTrimTime.string(playback.positionSeconds))
            if !playback.isReady && playback.errorMessage == nil {
                ProgressView().controlSize(.small)
                Text(model.text("Preparing Playback…", "Oynatma hazırlanıyor…")).font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
            if playback.errorMessage != nil {
                Button(model.text("Retry Playback", "Oynatmayı yeniden dene")) { preparePlayback(selection) }
                    .font(.system(size: 11))
            }
            Spacer(minLength: 6)
            Button(model.text("Reset", "Sıfırla")) { reset() }
                .font(.system(size: 12))
                .disabled(selection.startSeconds == 0 && selection.endSeconds == selection.sourceDuration && validationError == nil)
        }
    }

    private func selectionControls(preview: AudioTrimPreview, selection: AudioTrimSelection) -> some View {
        HStack(alignment: .top, spacing: 18) {
            timeField(model.text("Start", "Başlangıç"), text: Binding(get: { startText }, set: { startText = $0; applyTimes() }))
            timeField(model.text("End", "Bitiş"), text: Binding(get: { endText }, set: { endText = $0; applyTimes() }))
            VStack(alignment: .leading, spacing: 9) {
                Text(model.text("Selected Duration", "Seçilen süre")).font(.system(size: 10)).foregroundStyle(Palette.muted)
                Text(AudioTrimTime.string(selection.durationSeconds)).font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Palette.accent)
                    .accessibilityLabel(model.text("Selected Duration", "Seçilen süre"))
                    .accessibilityValue(AudioTrimTime.string(selection.durationSeconds))
            }.frame(width: 145, alignment: .leading)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 7) {
                Text(model.text("Save As", "Çıktı biçimi")).font(.system(size: 10)).foregroundStyle(Palette.muted)
                Picker(model.text("Save As", "Çıktı biçimi"), selection: $outputFormat) {
                    ForEach(availableFormats(preview)) { format in Text(format.title).tag(format) }
                }.labelsHidden().pickerStyle(.menu)
                Text(outputFormat == .m4a ? model.text("AAC Re-Encoded Copy", "AAC olarak yeniden kodlanır") : model.text("Uncompressed 16-Bit Copy", "Sıkıştırılmamış 16 bit kopya"))
                    .font(.system(size: 9)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(width: 179, alignment: .leading)
        }
    }

    private func timeField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 10)).foregroundStyle(Palette.muted)
            TextField("00:00.000", text: text).textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced)).accessibilityLabel(title)
            Text(model.text("Time or Seconds", "Süre veya saniye")).font(.system(size: 9)).foregroundStyle(Palette.muted)
        }.frame(width: 137)
    }

    @ViewBuilder private var loadingState: some View {
        if let loadError {
            VStack(spacing: 13) {
                Image(systemName: "exclamationmark.circle").font(.system(size: 32)).foregroundStyle(Palette.accent)
                Text(model.text("Could Not Open the Audio Editor", "Ses düzenleyicisi açılamadı"))
                    .font(.system(size: 19, weight: .semibold))
                Text(loadError).font(.system(size: 13)).foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center).frame(maxWidth: 500)
            }
        } else {
            VStack(spacing: 15) {
                ProgressView().controlSize(.regular)
                Text(model.text("Reading Your Waveform…", "Ses dalgan okunuyor…")).font(.system(size: 13)).foregroundStyle(Palette.muted)
                Text(model.text("You can cancel while the audio is being read.", "Ses okunurken işlemi iptal edebilirsin."))
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Label(model.text("Your Original Stays Untouched", "Orijinal dosyan korunur"), systemImage: "checkmark.shield")
                .font(.system(size: 10)).foregroundStyle(Palette.muted)
            Spacer()
            Button(model.text("Cancel", "Vazgeç")) { playback.shutdown(); model.cancelPending() }
                .keyboardShortcut(.cancelAction)
            Button(model.text("Create Copy", "Kopya oluştur")) { submit() }
                .buttonStyle(.borderedProminent).tint(Palette.primaryAction).foregroundStyle(Palette.onPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(selection == nil || validationError != nil || loadError != nil || preview.map({ availableFormats($0).isEmpty }) != false)
        }
    }

    private var parsedTimes: (start: Double, end: Double)? {
        guard let selection, let parsed = AudioTrimTime.selection(startText: startText, endText: endText, preserving: selection) else { return nil }
        return (parsed.startSeconds, parsed.endSeconds)
    }

    private var validationError: String? {
        guard let preview else { return nil }
        guard let times = parsedTimes, times.start >= 0, times.end <= preview.durationSeconds,
              times.end > times.start else {
            return model.text("Enter a start and end inside the audio, with End after Start. Use seconds, MM:SS, or HH:MM:SS.",
                              "Sesin içinde, bitişi başlangıçtan sonra olan bir aralık gir. Saniye, dakika:saniye veya saat:dakika:saniye kullan.")
        }
        let minimum = AudioTrimGeometry.minimumDuration(sourceDuration: preview.durationSeconds)
        guard times.end - times.start + 0.000_000_001 >= minimum else {
            return model.text("Keep at least \(AudioTrimTime.string(minimum)) of audio.", "En az \(AudioTrimTime.string(minimum)) uzunluğunda ses seç.")
        }
        return nil
    }

    private func availableFormats(_ preview: AudioTrimPreview) -> [OutputFormat] {
        OutputFormat.allCases.filter { preview.nativeOutputExtensions.contains($0.rawValue) }
    }

    private func setSelection(_ value: AudioTrimSelection) {
        selection = value
        startText = AudioTrimTime.string(value.startSeconds)
        endText = AudioTrimTime.string(value.endSeconds)
        playback.changeSelection(value)
    }

    private func applyTimes() {
        playback.pause()
        guard validationError == nil, let preview, let times = parsedTimes else { return }
        let value = AudioTrimSelection(startSeconds: times.start, endSeconds: times.end, sourceDuration: preview.durationSeconds)
        selection = value
        playback.changeSelection(value)
    }

    private func reset() {
        guard let preview else { return }
        setSelection(AudioTrimGeometry.fullDuration(preview.durationSeconds))
    }

    private func togglePlayback() {
        guard validationError == nil else { return }
        playback.togglePlayback()
    }

    private func preparePlayback(_ selection: AudioTrimSelection) {
        guard let input = inputs.first else { return }
        playback.prepare(url: input, selection: selection)
    }

    private func loadPreview() async {
        guard inputs.count == 1, let input = inputs.first, FileFamily.detect(input) == .audio else {
            loadError = model.text("The waveform editor works with one audio file at a time. Cancel and select a single audio file to continue.",
                                   "Dalga biçimi düzenleyicisi tek ses dosyasıyla çalışır. Vazgeç ve devam etmek için bir ses dosyası seç.")
            return
        }
        let worker = Task.detached(priority: .userInitiated) {
            try await NativeConverter.audioTrimPreview(for: input, maxSamples: 1_200)
        }
        do {
            let result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
            try Task.checkCancellation()
            guard let format = availableFormats(result).first else {
                throw LemulipError.unsupported("No native output format is available for this audio file. Convert it to WAV or M4A, then reopen the editor.")
            }
            preview = result
            outputFormat = format
            let fullSelection = AudioTrimGeometry.fullDuration(result.durationSeconds)
            setSelection(fullSelection)
            preparePlayback(fullSelection)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            loadError = error.localizedDescription
        }
    }

    private func submit() {
        guard validationError == nil, let selection, let preview,
              availableFormats(preview).contains(outputFormat) else { return }
        playback.shutdown()
        var options = ConversionOptions()
        options.audioTrim = selection
        model.submitPending(options, outputExtension: outputFormat.rawValue)
    }
}
#endif
