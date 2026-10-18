# Formats and Conversion Limits

Lemulip selects operations from the file extensions in your selection. A listed format is a supported route, not a promise that every codec or document feature will survive conversion.

The tables below describe source **0.1.6**, which adds native visual video crop.
Native video trim starts with 0.1.5; check
[Releases](https://github.com/osmankaankars/lemulip/releases) for available builds. Some
features still need broader hands-on macOS testing. See [Installation](INSTALL.md)
for optional engines and [User Guide](USER_GUIDE.md) for controls.

## Images

| Route or Tool | Engine | Notes |
| --- | --- | --- |
| Images → PNG, JPEG, HEIC, TIFF, BMP | macOS ImageIO; ImageMagick fallback | Input decoding and output codecs depend on the installed system |
| Images → WebP, AVIF | ImageMagick | Requires an ImageMagick build with the relevant codec |
| Images → PDF | Built in | Multiple images become pages in the displayed order |
| Compress, resize, rotate, horizontal flip, remove metadata | Built in; ImageMagick fallback | Creates a new copy |
| Visual image crop | macOS ImageIO | One still raster; exports the selected area from the original resolution |
| CLI centered crop | Built in; ImageMagick fallback | Uses `--width` and `--height`; creates a new copy |
| SVG → raster image | Restricted native rendering; ImageMagick fallback | Self-contained SVG only; scripts and external content are rejected |

Recognized image extensions include PNG, JPEG, HEIC/HEIF, TIFF, BMP, WebP, AVIF, GIF, ICO, and SVG. Recognition alone does not guarantee that a particular file can be decoded.

For ordinary image conversion, the native converter exports every frame of a
multi-frame image as separate still files. Animation timing is not preserved.
The ImageMagick fallback uses the first frame only. For animated GIF output,
use a video input with FFmpeg.

The visual crop editor requires one still raster image that macOS can decode
and encode in its output format. Its preview is at most 1,600 pixels on the
longest edge; the original must fit within 40 megapixels and 16,384 pixels per
side. Preview and export apply image orientation consistently. SVG, multiple
inputs, multi-frame images, and unsupported codecs receive an explicit error.
A selected crop never falls back to a centered crop or exports the preview
bitmap. [The user guide](USER_GUIDE.md#visual-image-crop) describes its controls.

Transparency is flattened onto white for formats such as JPEG and BMP. Image conversions remove metadata by default.

## PDF

| Operation | Output | Notes |
| --- | --- | --- |
| Export pages | PNG or JPEG | Every page at 300 DPI, within rendering limits |
| Extract selectable text | TXT or Markdown | Text extraction; does not recreate the original layout |
| Recognize text | TXT | Offline OCR using macOS Vision |
| Merge | PDF | Combines files in the displayed order |
| Split | PDF files | One output per page |
| Extract pages | PDF | Page numbers and ranges, starting at 1 |
| Rotate pages | PDF | Rotates every page in the selected document |
| Compress | PDF | Flattens each page into an image |

PDF tools use the built-in macOS frameworks. OCR results depend on scan quality and the languages supported by the installed system.

**Flattening changes the document.** PDF compression removes searchable text, links, forms, signatures, and accessibility structure from the new copy. It may increase the file size.

PDF → editable DOCX, Pages, PowerPoint, or spreadsheet output is not implemented. The app and CLI do not provide PDF password entry. Unlock a protected PDF and save a readable copy before converting it. PDFs that disallow text copying are rejected by the text extraction and OCR routes.

## Audio and Video

| Input Family | Outputs in Convert | Engine |
| --- | --- | --- |
| Audio | M4A, WAV, AIFF | Native macOS export where codecs allow; FFmpeg when installed |
| Audio | MP3, FLAC, OGG, Opus | FFmpeg |
| Video | MP4, MOV, M4A | Native macOS export where codecs allow; FFmpeg when installed |
| Video | MKV, WebM, GIF, MP3 | FFmpeg |

Recognized inputs include common MP3, AAC, M4A, WAV, AIFF, FLAC, OGG, Opus, WMA, MP4, MOV, M4V, MKV, WebM, AVI, and WMV files. Containers can hold different codecs; an extension alone does not establish support.

**Audio waveform trim** uses native decoding, playback, and M4A/WAV/AIFF export.
It opens one audio file with exactly one mono or stereo track at 8–192 kHz,
provided macOS can decode it. The editor shows only available native output
choices. Additional codecs can be converted to a compatible WAV or M4A first
using optional FFmpeg. The waveform editor does not mix tracks or decode through
an external engine.

M4A output re-encodes AAC and can include encoder padding. WAV and AIFF output
uses uncompressed 16-bit PCM with boundaries selected from decoded samples.
The UI shows milliseconds and keeps the precise end of the full recording;
its smallest editable range is 10 milliseconds, or the full file when shorter.
Read [Audio Waveform Trim](USER_GUIDE.md#audio-waveform-trim) for the controls.

**Visual video trim**, new in source 0.1.5, uses native macOS preview and export
to MP4 or MOV. It accepts one local video file with one decodable video track
and at most one audio track. The file must contain its own media. The editor
offers only available native outputs.
Protected or live media, external media references, unsupported codecs, and
multiple selected files are rejected before editing. It does not silently
switch to FFmpeg or mix multiple tracks.

Video export re-encodes the selected original range and preserves its display
orientation. Video-frame and audio-codec boundaries may affect the exact output
duration; the editor does not promise lossless or frame-exact trimming. It
leaves the original untouched. See [Visual Video Trim](USER_GUIDE.md#visual-video-trim).

**Visual video crop**, new in source 0.1.6, applies one rectangle to the whole
clip and exports MP4 or MOV through native macOS tools. It keeps the clip's
audio and full source timeline; it does not combine a time trim with the crop. The source
file remains unchanged.

The crop is defined on the upright frame in source pixels. Output dimensions
are even numbers, at least 2 × 2 pixels. Odd requested dimensions round inward
by at most one pixel at the right or bottom; the image is not stretched to make
them fit. Export re-encodes H.264 video with AAC audio where present, so codec
and color representation can change. Frame timing follows the source track;
video-frame and audio-codec boundaries can still affect the output duration.

This first crop editor uses the same one-video / at-most-one-audio input scope
as native trim. It supports square pixels, a full clean aperture, and standard
0°, 90°, 180°, or 270° display rotations. Non-square pixels, custom apertures,
mirroring, and scaled or sheared display transforms need conversion to a
standard MP4 or MOV before opening Crop. Protected files and external media
references are not accepted. See [Visual Video Crop](USER_GUIDE.md#visual-video-crop).

The other desktop media tools use FFmpeg for compression, resizing, speed and
volume changes, audio removal, and audio extraction. Video compression produces
H.264 MP4; audio compression produces M4A. Additional video codecs can be
converted to a compatible MP4 or MOV before opening the native trim editor.

Lemulip uses the first video stream and first audio stream for its FFmpeg routes. It is not an editor for multiple tracks, subtitles embedded in video, or professional media metadata. Conversions can be lossy, and a compressed output is not guaranteed to be smaller.

## Documents, Slides, and Spreadsheets

**DOCX** is a Microsoft Word document, **XLSX** is an Excel workbook, and
**PPTX** is a PowerPoint presentation. LibreOffice is an optional local engine
that reads and writes those formats; it is not a separate output format.
You do not need Microsoft Office installed to run these conversions.

| Route | Engine | Fidelity |
| --- | --- | --- |
| TXT, Markdown, RTF, HTML → TXT, Markdown, RTF, HTML, PDF | Built in for basic routes | Text-focused; see exceptions below |
| Markdown → HTML, DOCX, ODT | Pandoc | Structured conversion |
| TXT, RTF, HTML → DOCX | LibreOffice | Creates a Word document; complex formatting may change |
| EPUB input or EPUB output | Pandoc; some source formats also need LibreOffice | Reflowable document conversion |
| DOC, DOCX, ODT and supported Pages input → configured document outputs | LibreOffice | Depends on the input document and installed fonts |
| PPT, PPTX, ODP → PDF, PPTX, ODP | LibreOffice | Layout may change |
| XLS, XLSX, ODS, CSV, TSV → XLSX, ODS, CSV, TSV, PDF | LibreOffice, except CSV ↔ TSV | Layout, formulas, and sheet handling depend on the output |
| CSV ↔ TSV | Built in | Preserves quoted delimiters and multiline fields |
| Word count | Built in for basic text; Pandoc or LibreOffice for other documents | Reports a count in Activity |

The engine runs in the background. You choose a file format in Lemulip and
receive that file, which can be opened in its compatible application.
LibreOffice documents its [Microsoft Office format support](https://help.libreoffice.org/latest/en-US/text/shared/guide/ms_user.html)
and [background conversion options](https://help.libreoffice.org/latest/en-US/text/shared/guide/start_parameters.html).

Basic Markdown conversion to PDF, RTF, or TXT preserves text. It does not render a full Markdown layout. Exporting an Office document as Markdown also produces plain text in a Markdown file. EPUB → PDF currently renders extracted text, not a reproduction of the ebook's layout.

Conversion does not fetch linked images, included local files, or remote resources. Linked content can be omitted. Office conversions run with macros disabled.

CSV and TSV output from a workbook contains the active sheet and loses formulas and formatting. It is unsuitable for preserving a multi-sheet workbook.

Pages, Keynote, and Numbers export is not implemented. Apple document-package and legacy import support depends on the local engine and is not guaranteed. RTFD packages and text clippings are recognized but do not have guaranteed conversion routes.

Use the [official Pandoc installer](https://pandoc.org/installing.html). Lemulip enables Pandoc's [sandbox](https://pandoc.org/MANUAL.html#option--sandbox); EPUB, DOCX, and ODT routes need an installed build with embedded templates.

## Subtitles

SRT ↔ VTT conversion is built in. Either format can also be exported as TXT. Plain text output removes subtitle timing. This does not extract subtitle tracks from a video file.

## Archives

| Operation | Behavior |
| --- | --- |
| Create ZIP | Compresses selected files and folders into one archive |
| Create TAR | Bundles selected files and folders into one archive |
| Create GZIP | Compresses each selected file separately; not available for folders |
| Extract | Creates a new output folder without replacing existing files |

Extraction uses macOS's libarchive. ZIP, TAR, and GZIP are supported; RAR, 7z, and other variants depend on the system library. Encrypted archives, symbolic links, hard links, and special files are rejected.

Archives are limited to 10,000 entries, 64 path levels, and 2 GiB of expanded content. To archive a folder, choose an output location outside that folder.

## File and Resource Limits

There are no paid tiers or daily conversion quotas. The implementation does enforce limits to keep jobs bounded:

- Up to 1,000 input files per conversion job.
- Native PDF and image-frame operations allow up to 1,000 pages or frames, with a separate cap on output count.
- Native image input is limited to 150 megapixels. Rendered images are limited to 40 megapixels and a maximum dimension of 16,384 pixels.
- Native text processing is limited to 32 MiB.
- Audio waveform summaries contain at most 4,096 peaks; the editor requests
  1,200. Decoding uses a reusable 4,096-frame scratch buffer and rejects an
  individual decoder buffer larger than 16 MiB. These are application buffer
  limits, not a measurement of the process's total memory use.
- Video preview requests contain at most 24 thumbnails, each at most 192 pixels
  on its longest edge; the editor requests 12. This bounds the application's
  thumbnail cache, not AVFoundation's total decoding or playback memory.
- Video crop keeps one preview image at most 1,280 pixels on its longest edge.
  It does not build a thumbnail strip or a persistent decoded-frame cache.
- Native video crop output is limited to 40 megapixels and 16,384 pixels per
  side, with even dimensions of at least 2 × 2 pixels. A larger accepted source
  needs a smaller crop before export.
- The native video trim source must have a finite duration of at most 365 days,
  display dimensions of at most 16,384 pixels per side, and at most 150 megapixels
  per frame. Available codecs can impose lower limits.
- Archive and optional-engine operations have their own size, time, and resource limits.

Files that exceed a limit fail with an error. Lemulip does not silently omit pages to fit a limit. Try a smaller selection or lower image dimensions when appropriate.
