#if os(macOS)
import Foundation
import LemulipCore

/// A controlled player failure is distinct from an AVFoundation diagnostic,
/// even when the system happens to return the same words.
enum MediaPlaybackFailure: Equatable, Sendable {
    case localAudioRequired
    case localVideoAndRangeRequired
    case preparationTimedOut
    case audioUnavailable
    case videoUnavailable
    case audioSeekFailed
    case videoSeekFailed
    case audioPlaybackFailed
    case videoPlaybackFailed
    case audioReadStalled
    case videoReadStalled
    case system(String)

    func message(language: String) -> String {
        let english: String
        let turkish: String
        switch self {
        case .localAudioRequired:
            english = "Choose an audio file saved on this Mac to preview."
            turkish = "Önizleme için Mac’inde kayıtlı bir ses dosyası seç."
        case .localVideoAndRangeRequired:
            english = "Choose a video saved on this Mac and a valid time range to preview."
            turkish = "Önizleme için Mac’inde kayıtlı bir video ve geçerli bir zaman aralığı seç."
        case .preparationTimedOut:
            english = "Playback could not be prepared. Try again."
            turkish = "Oynatma hazırlanamadı. Yeniden dene."
        case .audioUnavailable:
            english = "This audio file cannot be previewed. Try another file."
            turkish = "Bu ses dosyası önizlenemiyor. Başka bir dosya dene."
        case .videoUnavailable:
            english = "This video cannot be previewed. Try another file."
            turkish = "Bu video önizlenemiyor. Başka bir dosya dene."
        case .audioSeekFailed:
            english = "The preview could not reach the selected time. Try playing again."
            turkish = "Önizleme seçtiğin konuma gidemedi. Oynatmayı yeniden dene."
        case .videoSeekFailed:
            english = "The preview could not reach this time. Try seeking or playing again."
            turkish = "Önizleme bu konuma gidemedi. Konumu değiştirmeyi veya yeniden oynatmayı dene."
        case .audioPlaybackFailed:
            english = "This audio file could not finish playing. Try again."
            turkish = "Bu ses dosyasının oynatılması tamamlanamadı. Yeniden dene."
        case .videoPlaybackFailed:
            english = "This video could not finish playing. Try again."
            turkish = "Bu videonun oynatılması tamamlanamadı. Yeniden dene."
        case .audioReadStalled:
            english = "Playback stopped while reading this audio file. Try again."
            turkish = "Ses dosyası okunurken oynatma durdu. Yeniden dene."
        case .videoReadStalled:
            english = "Playback stopped while reading this video. Try again."
            turkish = "Video okunurken oynatma durdu. Yeniden dene."
        case .system(let diagnostic):
            return diagnostic
        }
        return language == "tr" ? turkish : english
    }
}

/// Presentation for controlled trim-preview and selected-export errors.
/// Match both the error case and the whole diagnostic. Core/CLI descriptions,
/// unknown messages, and system errors keep their original details.
enum MediaErrorPresentation {
    static func message(for error: Error, language: String) -> String {
        guard let failure = error as? LemulipError else { return error.localizedDescription }
        let turkish: String
        switch failure {
        case .invalidInput("Choose one local audio file for waveform trimming."):
            turkish = "Kırpmak için Mac’inde kayıtlı tek bir ses dosyası seç."
        case .invalidInput("Choose a readable audio file that is not empty."):
            turkish = "Boş olmayan, okunabilir bir ses dosyası seç."
        case .invalidInput("This audio file has no valid playable duration."):
            turkish = "Bu ses dosyasının oynatma süresi geçersiz. Başka bir ses dosyası seç."
        case .invalidInput("The waveform preview size must be positive."):
            turkish = "Dalga biçimi önizlemesinin boyutu sıfırdan büyük olmalı. Ses düzenleyicisini yeniden aç."
        case .invalidInput("The waveform duration or preview size is invalid."):
            turkish = "Dalga biçiminin süresi veya önizleme boyutu geçersiz. Ses düzenleyicisini yeniden aç."
        case .invalidInput("The decoded waveform contains invalid audio timing or samples."):
            turkish = "Ses verisindeki zaman bilgisi veya örnekler geçersiz. Dosyayı WAV ya da M4A’ya dönüştürüp yeniden dene."
        case .invalidInput("Choose a nonempty audio range entirely within the recording."):
            turkish = "Ses dosyası içinde, bitişi başlangıçtan sonra olan bir aralık seç."
        case .invalidInput("The audio duration changed after the waveform was prepared. Reopen Trim to select the updated recording."):
            turkish = "Sesin süresi, önizleme hazırlandıktan sonra değişti. Güncel dosyadan seçim yapmak için ses düzenleyicisini yeniden aç."
        case .invalidInput("Choose an audio output for the selected range."):
            turkish = "Seçtiğin aralık için bir ses çıktı biçimi seç."
        case .invalidInput("A waveform selection requires exactly one audio file."):
            turkish = "Seçtiğin aralığı kaydetmek için tek bir ses dosyası seçili olmalı."
        case .invalidInput("A waveform selection requires Trim Audio and exactly one audio file."):
            turkish = "Bu seçim için tek bir ses dosyası seçip ses düzenleyicisini kullan."
        case .invalidInput("An audio selection can only be used with Trim Audio."):
            turkish = "Bu ses seçimi yalnız ses kırpma işleminde kullanılabilir."
        case .invalidInput("Choose one local video file for editing."):
            turkish = "Düzenlemek için Mac’inde kayıtlı tek bir video dosyası seç."
        case .invalidInput("Choose a readable video file that is not empty."):
            turkish = "Boş olmayan, okunabilir bir video dosyası seç."
        case .invalidInput("This video has no finite playable duration. Save a complete local clip first."):
            turkish = "Bu videonun oynatma süresi geçersiz. Önce videonun tamamını Mac’ine kaydet."
        case .invalidInput("The video timeline preview size must be positive."):
            turkish = "Video zaman çizelgesinin önizleme boyutu sıfırdan büyük olmalı. Video düzenleyicisini yeniden aç."
        case .invalidInput("The video dimensions are invalid or exceed the supported preview limits."):
            turkish = "Videonun boyutları geçersiz veya önizleme sınırlarını aşıyor. Boyutlarını kontrol edip daha küçük bir kopyayla yeniden dene."
        case .invalidInput("The video track has no valid playable timeline."):
            turkish = "Videonun görüntü izinde geçerli bir zaman çizelgesi yok. Başka bir video dosyası seç."
        case .invalidInput("Choose a nonempty video range entirely within the clip."):
            turkish = "Video süresi içinde, bitişi başlangıçtan sonra olan bir aralık seç."
        case .invalidInput("The video duration changed after the timeline was prepared. Reopen Trim to select the updated clip."):
            turkish = "Videonun süresi, önizleme hazırlandıktan sonra değişti. Güncel dosyadan seçim yapmak için video düzenleyicisini yeniden aç."
        case .invalidInput("Choose MP4 or MOV for the selected video range."):
            turkish = "Seçtiğin video aralığı için MP4 veya MOV çıktı biçimini seç."
        case .invalidInput("A timeline selection requires exactly one video file."):
            turkish = "Seçtiğin aralığı kaydetmek için tek bir video dosyası seçili olmalı."
        case .invalidInput("A timeline selection requires Trim Video and exactly one video file."):
            turkish = "Bu seçim için tek bir video dosyası seçip video düzenleyicisini kullan."
        case .invalidInput("A video selection can only be used with Trim Video."):
            turkish = "Bu video seçimi yalnız video kırpma işleminde kullanılabilir."
        case .invalidInput("This media file has no playable duration."):
            turkish = "Bu dosyanın oynatma süresi geçersiz. Başka bir ses veya video dosyası seç."
        case .invalidInput("Trim times must be within the media duration, with end after start."):
            turkish = "Kırpma aralığı dosyanın süresi içinde olmalı; bitiş başlangıçtan sonra gelmeli."
        case .invalidInput("The selected range is shorter than the supported time precision."):
            turkish = "Seçtiğin aralık kaydedilemeyecek kadar kısa. Daha uzun bir aralık seç."
        case .invalidInput("This file has no audio track to extract."):
            turkish = "Bu dosyada çıkarılabilecek bir ses izi yok. Ses içeren bir dosya seç."
        case .invalidInput("This file has no video track. Choose an audio output."):
            turkish = "Bu dosyada görüntü izi yok. Bir ses çıktı biçimi seç."
        case .unsupported("macOS cannot prepare a waveform for this audio codec. Convert the recording to WAV or M4A first; FFmpeg can convert additional formats."):
            turkish = "macOS bu ses kodlaması için dalga biçimi hazırlayamıyor. Önce WAV veya M4A’ya dönüştür. Ek biçimleri dönüştürmek için FFmpeg’i kullanabilirsin."
        case .unsupported("This audio decoder produced an unusually large buffer. Convert the recording to WAV or M4A first."):
            turkish = "Ses çözülürken önizleme için fazla büyük bir veri bloğu oluştu. Önce WAV veya M4A’ya dönüştür."
        case .unsupported("Waveform trimming needs exactly one audio track. Convert the recording to WAV or M4A first."):
            turkish = "Kırpma önizlemesi için dosyada tek bir ses izi olmalı. Önce WAV veya M4A’ya dönüştür."
        case .unsupported("Waveform trimming supports mono or stereo audio from 8 to 192 kHz. Convert other channel layouts or sample rates to WAV or M4A first."):
            turkish = "Bu düzenleyici, 8 ile 192 kHz arasında örnekleme hızına sahip mono veya stereo sesi destekler. Farklı kanal düzenlerini veya örnekleme hızlarını önce WAV ya da M4A’ya dönüştür."
        case .unsupported("No native output format is available for this audio file. Convert it to WAV or M4A, then reopen the editor."):
            turkish = "Bu ses dosyası kullanılabilir çıktı biçimlerinde kaydedilemiyor. WAV veya M4A’ya dönüştürüp düzenleyiciyi yeniden aç."
        case .unsupported("The selected audio output needs FFmpeg."):
            turkish = "Seçtiğin ses çıktı biçimi için FFmpeg gerekiyor."
        case .unsupported("macOS cannot prepare this video for editing. Convert it to a standard MP4 or MOV first. Protected videos and files that reference other media are not supported."):
            turkish = "macOS bu videoyu düzenlemeye hazırlayamıyor. Önce standart bir MP4 veya MOV dosyasına dönüştür. Korumalı videolar ve başka medya dosyalarına başvuran videolar desteklenmiyor."
        case .unsupported("Native video editing supports one video track and at most one audio track. Flatten a multitrack project to MP4 or MOV first."):
            turkish = "Bu düzenleyici tek bir görüntü izini ve en fazla bir ses izini destekler. Çok izli projeyi önce tek bir MP4 veya MOV videosu olarak dışa aktar."
        case .unsupported("No native video output format is available for this file. Convert it to MP4 or MOV, then reopen Trim Video."):
            turkish = "Bu video kullanılabilir çıktı biçimlerinde kaydedilemiyor. MP4 veya MOV’a dönüştürüp video düzenleyicisini yeniden aç."
        case .unsupported("macOS cannot export this video in the selected format. Choose another available format."):
            turkish = "macOS bu videoyu seçtiğin biçimde kaydedemiyor. Kullanılabilir başka bir çıktı biçimi seç."
        case .unsupported("macOS cannot export this codec. Enable FFmpeg."):
            turkish = "macOS bu kodlamayla çıktı oluşturamıyor. FFmpeg’i ekleyip yeniden dene."
        case .unsupported("This media container needs FFmpeg."):
            turkish = "Bu dosya kapsayıcısı için FFmpeg gerekiyor."
        case .unsupported("AVFoundation could not export this media. Enable FFmpeg for this codec."):
            turkish = "macOS bu medya dosyasını kaydedemedi. Bu kodlama için FFmpeg’i ekleyip yeniden dene."
        case .unsupported("This audio codec needs FFmpeg."):
            turkish = "Bu ses kodlaması için FFmpeg gerekiyor."
        case .unsupported("Multichannel or unusual-rate audio needs FFmpeg."):
            turkish = "Çok kanallı veya farklı örnekleme hızına sahip bu ses için FFmpeg gerekiyor."
        case .unsupported("This audio stream needs FFmpeg."):
            turkish = "Bu ses akışı için FFmpeg gerekiyor."
        case .unsupported("This PCM output is unavailable on this macOS version."):
            turkish = "Bu PCM çıktısı kullandığın macOS sürümünde desteklenmiyor. Başka bir çıktı biçimi seç."
        case .unsupported("The native audio writer cannot handle this format."):
            turkish = "macOS bu ses biçimini kaydedemiyor. Başka bir çıktı biçimi seç."
        case .unsupported("macOS cannot read or write this audio stream. Enable FFmpeg."):
            turkish = "macOS bu ses akışını okuyamıyor veya kaydedemiyor. FFmpeg’i ekleyip yeniden dene."
        case .operationFailed("The video decoder returned an invalid timeline thumbnail."):
            turkish = "Videodan geçerli bir önizleme karesi alınamadı. Video düzenleyicisini yeniden açıp dene."
        case .operationFailed("Audio writing failed."):
            turkish = "Ses kopyası kaydedilemedi. Yeniden dene."
        case .operationFailed("An audio sample could not be written."):
            turkish = "Bir ses örneği kaydedilemedi. Yeniden dene."
        case .operationFailed("Audio decoding did not finish or the selected range contains no samples."):
            turkish = "Sesin okunması tamamlanamadı veya seçtiğin aralıkta ses örneği yok. Aralığı kontrol edip yeniden dene."
        case .operationFailed("Audio output could not be finalized."):
            turkish = "Ses kopyasının kaydedilmesi tamamlanamadı. Yeniden dene."
        case .operationFailed("The decoded audio contains invalid sample timing."):
            turkish = "Çözülen ses örneklerinin zaman bilgisi geçersiz. Dosyayı WAV veya M4A’ya dönüştürüp yeniden dene."
        case .operationFailed("The selected audio frames could not be read."):
            turkish = "Seçtiğin aralıktaki ses örnekleri okunamadı. Aralığı kontrol edip yeniden dene."
        case .missingDependency("FFmpeg"):
            return language == "tr"
                ? "FFmpeg’i Ayarlar → Biçim Desteği bölümünden ekleyip yeniden dene."
                : "Add FFmpeg in Settings → Format Support, then try again."
        default:
            return error.localizedDescription
        }
        return language == "tr" ? turkish : error.localizedDescription
    }
}
#endif
