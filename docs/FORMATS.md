# Formats and conversion limits

Freewheel selects operations from the file extensions in your selection. A listed format is a supported route, not a promise that every codec or document feature will survive conversion.

The tables below describe the current implementation. Some features still need broader hands-on macOS testing. See [Installation](INSTALL.md) for optional engines and [the user guide](USER_GUIDE.md) for controls.

## Images

| Route or tool | Engine | Notes |
| --- | --- | --- |
| Images → PNG, JPEG, HEIC, TIFF, BMP | macOS ImageIO; ImageMagick fallback | Input decoding and output codecs depend on the installed system |
| Images → WebP, AVIF | ImageMagick | Requires an ImageMagick build with the relevant codec |
| Images → PDF | Built in | Multiple images become pages in the displayed order |
| Compress, resize, center crop, rotate, horizontal flip, remove metadata | Built in; ImageMagick fallback | Creates a new copy |
| SVG → raster image | Restricted native rendering; ImageMagick fallback | Self-contained SVG only; scripts and external content are rejected |

Recognized image extensions include PNG, JPEG, HEIC/HEIF, TIFF, BMP, WebP, AVIF, GIF, ICO, and SVG. Recognition alone does not guarantee that a particular file can be decoded.

The native converter exports every frame of a multi-frame image as separate still files. Animation timing is not preserved. The ImageMagick fallback uses the first frame only. For animated GIF output, use a video input with FFmpeg.

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

## Audio and video

| Input family | Outputs in Convert | Engine |
| --- | --- | --- |
| Audio | M4A, WAV, AIFF | Native macOS export where codecs allow; FFmpeg when installed |
| Audio | MP3, FLAC, OGG, Opus | FFmpeg |
| Video | MP4, MOV, M4A | Native macOS export where codecs allow; FFmpeg when installed |
| Video | MKV, WebM, GIF, MP3 | FFmpeg |

Recognized inputs include common MP3, AAC, M4A, WAV, AIFF, FLAC, OGG, Opus, WMA, MP4, MOV, M4V, MKV, WebM, AVI, and WMV files. Containers can hold different codecs; an extension alone does not establish support.

The desktop media tools use FFmpeg for compression, trimming, resizing, speed and volume changes, audio removal, and audio extraction. Video compression produces H.264 MP4; audio compression produces M4A.

Freewheel uses the first video stream and first audio stream for its FFmpeg routes. It is not an editor for multiple tracks, subtitles embedded in video, or professional media metadata. Conversions can be lossy, and a compressed output is not guaranteed to be smaller.

## Documents, slides, and spreadsheets

| Route | Engine | Fidelity |
| --- | --- | --- |
| TXT, Markdown, RTF, HTML → TXT, Markdown, RTF, HTML, PDF | Built in for basic routes | Text-focused; see exceptions below |
| Markdown → HTML, DOCX, ODT | Pandoc | Structured conversion |
| EPUB input or EPUB output | Pandoc; some source formats also need LibreOffice | Reflowable document conversion |
| DOC, DOCX, ODT and supported Pages input → configured document outputs | LibreOffice | Depends on the input document and installed fonts |
| PPT, PPTX, ODP → PDF, PPTX, ODP | LibreOffice | Layout may change |
| XLS, XLSX, ODS, CSV, TSV → XLSX, ODS, CSV, TSV, PDF | LibreOffice, except CSV ↔ TSV | Layout, formulas, and sheet handling depend on the output |
| CSV ↔ TSV | Built in | Preserves quoted delimiters and multiline fields |
| Word count | Built in for basic text; Pandoc or LibreOffice for other documents | Reports a count in Activity |

Basic Markdown conversion to PDF, RTF, or TXT preserves text. It does not render a full Markdown layout. Exporting an Office document as Markdown also produces plain text in a Markdown file. EPUB → PDF currently renders extracted text, not a reproduction of the ebook's layout.

Conversion does not fetch linked images, included local files, or remote resources. Linked content can be omitted. Office conversions run with macros disabled.

CSV and TSV output from a workbook contains the active sheet and loses formulas and formatting. It is unsuitable for preserving a multi-sheet workbook.

Pages, Keynote, and Numbers export is not implemented. Apple document-package and legacy import support depends on the local engine and is not guaranteed. RTFD packages and text clippings are recognized but do not have guaranteed conversion routes.

Use the [official Pandoc installer](https://pandoc.org/installing.html). Freewheel enables Pandoc's [sandbox](https://pandoc.org/MANUAL.html#option--sandbox); EPUB, DOCX, and ODT routes need an installed build with embedded templates.

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

## File and resource limits

There are no paid tiers or daily conversion quotas. The implementation does enforce limits to keep jobs bounded:

- Up to 1,000 input files per conversion job.
- Native PDF and image-frame operations allow up to 1,000 pages or frames, with a separate cap on output count.
- Native image input is limited to 150 megapixels. Rendered images are limited to 40 megapixels and a maximum dimension of 16,384 pixels.
- Native text processing is limited to 32 MiB.
- Archive and optional-engine operations have their own size, time, and resource limits.

Files that exceed a limit fail with an error. Freewheel does not silently omit pages to fit a limit. Try a smaller selection or lower image dimensions when appropriate.
