# UNRELEASED UI REVIEW · YAYIMLANMAMIŞ ARAYÜZ İNCELEMESİ

## English

This is a temporary macOS 13+ review copy, with universal Apple Silicon/Intel executables and **no bundled third-party engines**. It is for physical PDF interaction, optional sound audition and native Retina screenshots. It is not the complete 0.1.20 release. The exact commit, version and staged metadata overrides are in `REVIEW-INFO.json`.

Download the final `UNRELEASED-UI-REVIEW-<run ID>` artifact only after this workflow passes. It contains the unchanged ZIP, its checksum and separate `native-arm64.json` / `native-x86_64.json` receipts. Those receipts establish signature/architecture checks, one actual app launch with three alive checks on each host, PDF merge/extraction and SRT-to-VTT conversion. They do not establish physical dragging, first-click Cancel, audible sound or Retina sharpness. Artifacts expire after 14 days; matching debug symbols are retained separately for 90 days.

### Open the separate copy

1. Unpack the Actions artifact and verify its inner ZIP from that directory:

   ```sh
   shasum -a 256 -c Lemulip-UI-Review.zip.sha256
   ```

2. Expand `Lemulip-UI-Review.zip`. Quit normal Lemulip after its jobs finish, then open **Lemulip UI Review.app** from the expanded folder. Keep your installed app in place. This copy is ad-hoc signed; if macOS requests approval, follow [Apple's app-specific opening instructions](https://support.apple.com/102445) for this reviewed copy.
3. Its bundle ID is `app.freewheel.Freewheel.UIReview`, so app preferences use a separate domain. Some in-app titles still say “Lemulip” because the source UI is unchanged. Optional installed-engine storage and macOS sound/accessibility settings remain shared; leave engine installation outside this review. Use only the supplied synthetic `Fixtures` and save outputs to a new folder outside this package.

### Physical review on your Mac

| Case | Action and record |
| --- | --- |
| Number entry | Open the three `Fixtures/Merge` PDFs in Merge PDFs. Sort by filename. Move one document using its position number and Return; check Undo/Redo. Repeat in Organize with `Fixtures/Organize/Page-Order.pdf`. An invalid number must leave the order unchanged; Esc must discard a pending number edit. |
| Real dragging | Start from original order. Click item 1's title/thumbnail, then Command-click item 3. Drag a selected handle and drop **before selected item 3** (top half of its Merge row; left half of its Organize card). Expected document/page order: `2, 1, 3` / `2, 1, 3, 4`. Check the insertion indicator, group order and Undo; export and inspect the output pages. Also try a drop onto an unselected item. |
| First Cancel click | In each editor, begin a position edit without Return. Click visible Cancel once: the pending editor should close with no output. Record whether only the draft closes or a second click is required; keep those results separate. Repeat with no active number edit. Cancel a destination chooser and confirm the editor stays usable. |
| Optional sound | In Settings, confirm Selection Sounds starts off in this review domain. At a comfortable volume, use Preview, then enable it. Browsing options and Cancel should remain quiet; confirm a PDF/SRT operation and listen for one tick. Test with the setting off and with macOS sound effects muted, then restore your settings. Record what is actually audible. |
| Keyboard and VoiceOver | Use Tab/Shift-Tab to reach Selection Sounds and Preview, then check the PDF position field and footer. With VoiceOver, record the announced names, on/off state and values for these controls and the operation options: quality as a percentage, speed as a multiplier and volume as a percentage. Repeat in English and Turkish where practical; mark any control you cannot reach or understand. |
| Retina and accessibility | On the physical Retina display, capture the workspace and PDF editor in light/dark appearances. Inspect original PNGs at native pixels for sharp text/icons and complete controls. Repeat immediate typing/Cancel with Reduce Motion and Reduce Transparency enabled. Record display scaling, screenshot pixel dimensions and macOS version; keep original captures without resizing. |

Report the commit, Mac architecture, macOS/display settings, each observed result and any missing control. Attach the original screenshot/output when relevant. These observations remain separate from CI receipts and marketing approval. To recheck unchanged package files, run `shasum -a 256 -c SHA256SUMS.txt` inside `Lemulip-UI-Review` after the app has quit.

## Türkçe

Bu, macOS 13+ için geçici bir inceleme kopyasıdır. Apple Silicon ve Intel çalıştırılabilirlerini içerir; **üçüncü taraf motorlar pakete eklenmemiştir**. Fiziksel PDF etkileşimi, isteğe bağlı ses denemesi ve gerçek Retina ekran görüntüleri içindir. Tam 0.1.20 yayını değildir. Kesin commit, sürüm ve paket kimliği değişiklikleri `REVIEW-INFO.json` içindedir.

İş akışı geçtikten sonra son `UNRELEASED-UI-REVIEW-<çalıştırma kimliği>` çıktısını indir. İçindeki ZIP değiştirilmeden iki mimaride doğrulanır; SHA-256 dosyası ve `native-arm64.json` / `native-x86_64.json` kayıtları yanında durur. Kontroller imzayı, mimarileri, her makinede tek açılışın üç canlılık ölçümünü, PDF birleştirme/çıkarma ve SRT→VTT dönüşümünü kapsar. Fiziksel sürükleme, ilk Cancel tıklaması, duyulan ses ve Retina keskinliği ayrıca gözlemlenir. İnceleme çıktısı 14 gün, eşleşen hata ayıklama sembolleri ayrı olarak 90 gün saklanır.

### Ayrı kopyayı aç

1. Actions çıktısını aç; iç ZIP'i bulunduğu klasörde yukarıdaki `shasum` komutuyla doğrula. Ardından `Lemulip-UI-Review.zip` dosyasını aç.
2. Normal Lemulip'in işleri bittikten sonra uygulamadan çık. Açılan klasördeki **Lemulip UI Review.app** uygulamasını çalıştır; kurulu uygulamayı yerinde bırak. Bu kopya ad-hoc imzalıdır. macOS onay isterse bu incelenen kopya için [Apple'ın uygulamaya özel açma adımlarını](https://support.apple.com/102445) izle.
3. `app.freewheel.Freewheel.UIReview` kimliği uygulama tercihlerini ayırır. Kaynak arayüz korunduğu için bazı başlıklarda “Lemulip” görünür. İsteğe bağlı motorların kurulum alanı ve macOS ses/erişilebilirlik ayarları ortaktır; bu incelemede motor kurma. Verilen yapay `Fixtures` dosyalarını kullan, çıktıları paketin dışında yeni bir klasöre kaydet.

### Mac üzerinde fiziksel inceleme

| Kontrol | Uygulama ve kaydedilecek sonuç |
| --- | --- |
| Sıra numarası | `Fixtures/Merge` içindeki üç PDF'i birleştirme ekranında aç, dosya adına göre sırala. Bir sıra numarasını değiştirip Enter'a bas; Geri al/Yinele'yi kontrol et. `Fixtures/Organize/Page-Order.pdf` ile Düzenle ekranında tekrarla. Geçersiz sayı sırayı değiştirmemeli; Esc, yazılmakta olan sayıdan vazgeçmeli. |
| Gerçek sürükleme | İlk sıradan başla. 1'in başlığına/küçük resmine tıkla, ardından Command ile 3'ü seçime ekle. Seçili tutamağı **seçili 3'ün önüne** bırak: birleştirmede satırın üst yarısı, düzenlemede kartın sol yarısı. Beklenen dosya/sayfa sırası `2, 1, 3` / `2, 1, 3, 4`. Bırakma çizgisini, grup sırasını ve Geri al'ı kontrol et; dışa aktarılan PDF'in sayfalarını aç. Seçili olmayan bir öğeye bırakmayı da dene. |
| İlk Vazgeç tıklaması | Her iki editörde bir sıra numarası yazmaya başla; Enter'a basmadan görünür Vazgeç düğmesine bir kez tıkla: bekleyen editör, çıktı oluşturmadan kapanmalı. Yalnızca sayı taslağı kapanıyorsa veya ikinci tıklama gerekiyorsa ayrı kaydet. Sayı düzenlenmiyorken tekrarla. Hedef klasör seçimini iptal ettikten sonra editörün kullanılabilir kaldığını da dene. |
| İsteğe bağlı ses | Ayarlar'da Seçim Sesleri'nin bu inceleme alanında kapalı başladığını doğrula. Uygun ses düzeyinde Dinle'yi kullan, sonra seçeneği aç. Seçenekleri gezerken ve Vazgeç'te ses olmamalı; PDF/SRT işlemini onaylarken tek sesi dinle. Ayar kapalıyken ve macOS ses efektleri sessizdeyken tekrarla; sonra ayarlarını eski haline getir. Gerçekte duyduğunu kaydet. |
| Klavye ve VoiceOver | Tab/Shift-Tab ile Seçim Sesleri ve Dinle'ye ulaş; PDF sıra alanını ve alt düğmeleri kontrol et. VoiceOver ile bu kontrollerin duyurulan adlarını, açık/kapalı durumunu ve işlem seçeneklerinin değerlerini kaydet: kalite yüzde, hız çarpan, ses düzeyi yüzde olarak anlaşılmalı. Mümkünse İngilizce ve Türkçe tekrarla; ulaşılamayan veya anlaşılamayan kontrolü belirt. |
| Retina ve erişilebilirlik | Fiziksel Retina ekranda çalışma alanını ve PDF editörünü açık/koyu görünümde yakala. Orijinal PNG'lerde, doğal piksel boyutunda yazı/simge keskinliğini ve eksiksiz kontrolleri incele. Hareketi Azalt ve Saydamlığı Azalt açıkken hızlı yazma/Vazgeç adımlarını tekrarla. Ekran ölçeğini, PNG piksel boyutunu ve macOS sürümünü kaydet; görüntüleri yeniden boyutlandırma. |

Commit'i, Mac mimarisini, macOS/ekran ayarlarını, gözlenen sonuçları ve eksik kontrolleri bildir; gerekiyorsa orijinal görüntüyü/çıktıyı ekle. Bu gözlemler CI kayıtlarından ve tanıtım görseli onayından ayrıdır. Uygulamadan çıktıktan sonra paket dosyalarını `Lemulip-UI-Review` klasöründe `shasum -a 256 -c SHA256SUMS.txt` ile tekrar kontrol edebilirsin.

## Maintainer reference

Only staged `CFBundleIdentifier`, `CFBundleName`, `CFBundleDisplayName` and the resulting signature bytes differ from the built app. The original app, source plist and thin build products are preserved; the existing symbol verifier checks runtime/UUID/dSYM invariants after re-signing. [Apple documents the bundle identifier's role in preferences and Launch Services](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CoreFoundationKeys.html). This workflow has no tag/release/site publication step and does not replace normal release gates.
