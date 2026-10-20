# Formats and Conversion Limits

Lemulip selects operations from the file extensions in your selection. A listed format is a supported route, not a promise that every codec or document feature will survive conversion.

See [Installation](INSTALL.md#optional-engines) for optional engines and
[User Guide](USER_GUIDE.md) for controls. Broader hands-on macOS testing and
[Microsoft Office review](OFFICE_REVIEW.md) remain open.

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

Visual crop requires one still raster image that macOS can decode and encode,
up to **40 megapixels** and **16,384 pixels per side**. It uses the original
resolution and the orientation shown in the preview. SVG, multi-frame images,
multiple inputs, and unsupported codecs receive an error. See
[Visual Image Crop](USER_GUIDE.md#visual-image-crop).

Transparency is flattened onto white for formats such as JPEG and BMP. Image conversions remove metadata by default.

## PDF

| Operation | Output | Notes |
| --- | --- | --- |
| Export pages | PNG or JPEG | Every page at 300 DPI, within rendering limits |
| Extract selectable text | TXT or Markdown | Text extraction; does not recreate the original layout |
| Recognize text | TXT | Offline OCR using macOS Vision |
| Organize | PDF | Reorder, rotate, remove, or extract pages from one PDF using page thumbnails |
| Merge | PDF | Review first-page previews, document order, page counts, and output page ranges before combining whole documents |
| Split | PDF files | One output per page |
| Extract pages | PDF | Page numbers and ranges, starting at 1 |
| Rotate pages | PDF | Rotates every page in the selected document |
| Compress | PDF | Flattens each page into an image |

PDF tools use the built-in macOS frameworks. OCR results depend on scan quality and the languages supported by the installed system.

**Visual PDF organization** copies original pages through PDFKit, preserving
their text, vector content, and page annotations while applying the chosen
order and quarter-turn rotations. Extraction keeps selected pages in the editor's displayed order.
It does not provide text editing or combine separate source documents.

Page reassembly is not a guarantee that document-level features survive.
Bookmarks, links between pages, form relationships, signatures, and accessibility
structure may no longer be valid. Keep the original when those features matter.
Read [Organize PDF](USER_GUIDE.md#organize-pdf) for controls and source limits.

**Visual PDF merge** shows the first page of each source document, its page
count, and its resulting page range. Reordering or removing documents updates
the output summary. Every page from the retained files is copied in document
order, preserving its source orientation, text, vector content, and page
annotations. The document-level limitations above also apply to merged files.
Read [Merge PDF](USER_GUIDE.md#merge-pdf) for controls and limits. The CLI merges
documents in argument order without opening this editor.

The organizer and merge preview require permission to assemble and copy pages.
Locked PDFs are rejected. An encrypted PDF that is already readable can be used
when those permissions allow it, with a visible explanation that the new copy
is not password protected. Source encryption is unchanged.

**Flattening changes the document.** PDF compression removes searchable text, links, forms, signatures, and accessibility structure from the new copy. It may increase the file size.

PDF → editable DOCX, Pages, PowerPoint, or spreadsheet output is not implemented. The app and CLI do not provide PDF password entry. Unlock a locked PDF and save a readable copy before converting it. PDFs that disallow text copying are rejected by the text extraction and OCR routes.

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

**Visual video trim** uses native macOS preview and export
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

**Visual video crop** applies one rectangle to the whole
clip and exports MP4 or MOV through native macOS tools. It keeps the clip's
audio and full source timeline; it does not combine a time trim with the crop. The source
file remains unchanged.

The crop is defined on the upright frame in source pixels. Output dimensions
are even numbers, at least 2 × 2 pixels. Odd requested dimensions round inward
by at most one pixel at the right or bottom; the image is not stretched to make
them fit. Export re-encodes H.264 video with AAC audio where present, so codec
and color representation can change. Frame timing follows the source track;
video-frame and audio-codec boundaries can still affect the output duration.

The crop editor uses the same one-video / at-most-one-audio input scope
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
| Basic Markdown → DOCX | Built in; Pandoc fallback | Headings, simple lists, emphasis, code, and pipe tables within the subset below |
| Markdown → HTML, ODT | Pandoc | Uses Pandoc's Markdown dialect |
| TXT → DOCX | Built into macOS | Basic text, paragraphs, tabs, and Unicode; no rich document layout |
| Basic RTF → DOCX | Built into macOS | Supported fonts and paragraph formatting; see the basic export boundary below |
| Complex RTF → DOCX | LibreOffice | Creates a Word document; complex formatting may change |
| HTML, HTM → DOCX | LibreOffice | Structured document conversion; does not reproduce a browser page |
| EPUB input or EPUB output | Pandoc; some source formats also need LibreOffice | Reflowable document conversion |
| DOC, DOCX, ODT and supported Pages input → configured document outputs | LibreOffice | Depends on the input document and installed fonts |
| PPT, PPTX, ODP → PDF, PPTX, ODP | LibreOffice | Layout may change |
| CSV, TSV → XLSX | Built in | One worksheet named Sheet1; every field is stored as text |
| XLS, XLSX, ODS → XLSX, ODS, CSV, TSV, PDF | LibreOffice | Layout, formulas, and sheet handling depend on the output |
| CSV, TSV → ODS, PDF | LibreOffice | Sheet layout depends on the output |
| CSV ↔ TSV | Built in | Preserves quoted delimiters and multiline fields |
| Word count | Built in for basic text; Pandoc or LibreOffice for other documents | Reports a count in Activity |

LibreOffice documents its [Microsoft Office format support](https://help.libreoffice.org/latest/en-US/text/shared/guide/ms_user.html)
and [background conversion options](https://help.libreoffice.org/latest/en-US/text/shared/guide/start_parameters.html).

Basic Markdown conversion to PDF, RTF, or TXT preserves text. It does not render a full Markdown layout. Exporting an Office document as Markdown also produces plain text in a Markdown file. EPUB → PDF currently renders extracted text, not a reproduction of the ebook's layout.

### Basic Word Export

Native DOCX export accepts **TXT and basic RTF** on macOS. Each input creates
a separate document, with its source bytes unchanged.

**TXT** keeps source text, paragraph breaks, tabs, and Unicode. Plain text has
no fonts, tables, images, or page layout to preserve. Markdown syntax remains
literal text when it is in a TXT file; use a `.md` or `.markdown` file for
structured Markdown conversion.

TXT files must be between **1 byte and 32 MiB**, encoded as UTF-8 with an optional
byte-order mark, or UTF-16 with a byte-order mark. Line endings become logical
paragraph breaks. Empty text and unsupported control characters receive an
error instead of silently losing content.

**Basic RTF** keeps text and supported character and paragraph formatting:

| Formatting | Native Export Scope |
| --- | --- |
| Text | Characters, paragraph breaks, tabs, and Unicode |
| Fonts | Font families and sizes; bold and italic traits |
| Paragraphs | Alignment, spacing, and indents |
| Document metadata | Author and editor set to Lemulip; company and manager empty; source metadata is not copied |

RTF input must be between **1 byte and 32 MiB** and contain text. The native
scope allows at most **128 nested groups** and **250,000 formatting commands**.
Excessive nesting is rejected; excessive formatting complexity uses the
optional-engine route. The file is checked before native export. Images,
embedded objects, tables, lists, fields, hyperlinks,
headers, footers, and other unsupported RTF structures require the
LibreOffice route. If a selection includes such an RTF file, the whole batch
uses that route before any native output is created. A missing engine is
reported. Malformed basic RTF fails instead of being partially imported;
LibreOffice validates documents assigned to its route.

Page layout and margins are not reconstructed. Unavailable fonts may be
substituted, and the target application's layout engine can change line breaks
and pagination. Review the new document in Word or another compatible reader when
appearance matters. Native export sets the public metadata above for TXT too.

On other core platforms, TXT and RTF → DOCX use optional engines. PDF-to-editable-Word
conversion is not implemented.

### HTML and Markdown Word Export

Markdown (`.md` or `.markdown`) has a small built-in DOCX writer. HTML (`.html`
or `.htm`) uses LibreOffice.

#### Built-In Markdown

| Content | Supported Syntax |
| --- | --- |
| Headings | Unindented ATX headings, using one to six `#` characters |
| Text | Paragraphs, Unicode, simple nonnested bold and italic text |
| Inline code | One pair of backticks on a single line |
| Lists | Flat, one-line items with `-`, `+`, or `*` bullets, or decimal numbering with `.` or `)`; the starting number is retained |
| Code blocks | Backtick or tilde fences with an optional simple language name; literal spaces, tabs, blank lines, and symbols are preserved without syntax highlighting |
| Tables | Pipe tables with a header, matching column counts, and left, center, or right column alignment |

Save Markdown as valid UTF-8 or BOM-marked UTF-16. An empty input creates a
blank Word document. The writer sets creator and editor metadata to **Lemulip**
and adds no external resources or source paths to the package.

| Native Limit | Per Input |
| --- | --- |
| Size | 4 MiB for both encoded source bytes and decoded UTF-8 text |
| Lines | 50,000 normalized lines; 16 KiB of UTF-8 per line |
| Paragraph | 64 KiB of UTF-8 text |
| Structure | 10,000 blocks or list items; 100,000 text runs |
| Tables | 32 columns per table; 10,000 cells across all tables |

Links, images, raw HTML or entities, nested or multiline lists, blank lines
between list items, alphabetic, Roman, or parenthesized numbering such as `(1)`,
block quotes, Setext headings, rules, front matter, math, footnotes, complex
emphasis, explicit hard breaks, and escaped or uneven tables
use **Pandoc**. Inputs exceeding a native limit also use that route. If any
Markdown input needs it, the whole Markdown batch selects Pandoc before output
is created. Mixing Markdown with other document types retains the Pandoc route.

For batches containing only Markdown, Lemulip prepares accepted UTF-16 input as
UTF-8 for Pandoc automatically and keeps the originals. Use UTF-8 Markdown when
combining document types.

Pandoc must be installed for those conversions. Invalid encoding, unsupported
XML control characters, and files larger than the existing **32 MiB** input
limit receive an error. A file that changes beyond native support during export
also fails; start a new conversion to select its appropriate route.

The fallback uses [Pandoc's Markdown](https://pandoc.org/MANUAL.html#pandocs-markdown)
with its sandbox enabled. Linked resources are not fetched, and supported
formatting can differ across Markdown dialects. Neither route guarantees an
identical page layout in Word.

#### HTML and Visual Review

The HTML example checks a heading, paragraphs, emphasis, Unicode, character
entities, and a simple table. Complex CSS, responsive layouts, scripts, web
fonts, and linked media are outside its scope. Basic native HTML conversion to
text remains text-only.

The HTML and native Markdown examples contain no images or hyperlinks.
Automated checks inspect DOCX structure; visual acceptance in Microsoft Word
remains **Not Reviewed**. See [Office Review](OFFICE_REVIEW.md) for the comparisons.

### Basic Excel Export

Each CSV or TSV input produces its own XLSX workbook with one worksheet named
**Sheet1**. Commas separate CSV fields; tabs separate TSV fields. Quoted
delimiters, escaped quotes, and multiline fields stay within their cells.
UTF-8, with an optional byte-order mark, and BOM-marked UTF-16 are supported.
Blank rows remain in place; a final row separator does not create an extra row.
An empty file creates a blank sheet.

**Every cell is text.** Leading zeros, long identifiers, date-looking strings,
and formula-looking strings keep their text values. For example, `00123`,
`01/02/2026`, and `=SUM(A1:A2)` are not converted into numbers, dates, or formulas.
The export does not infer a header row, add charts, or combine inputs into a
multi-sheet workbook. You can explicitly change cell types in a spreadsheet
application afterward when you need calculations.

| Limit | Per Input Workbook |
| --- | --- |
| Source file | At most 32 MiB |
| Rows | At most 100,000 |
| Columns | At most 16,384 |
| Input fields, including empty fields | At most 500,000 |
| Cell text | At most 32,767 UTF-16 code units; some Unicode characters use two |
| Line feeds in one cell | At most 253 |

Files outside these limits fail with an explanation; the exporter does not
truncate rows or cell text. Malformed quoting and characters that cannot be
represented in XML receive an explicit error. Existing XLS, XLSX, and ODS workbooks still use
LibreOffice, including exports that need formula or multi-sheet handling.
See [Basic Office Exports](USER_GUIDE.md#basic-office-exports) for the app and CLI
workflow.

### Rich Office Conversion

Existing Office files use optional LibreOffice. Three generated examples pass
through OpenDocument and back to their original Office format:

| Route | Checked in the Returned Office File |
| --- | --- |
| DOCX → ODT → DOCX | A two-by-two table, Unicode paragraphs, bold and italic text, a stored font name, and its size |
| XLSX → ODS → XLSX | Two named sheets in order; text identifiers, numbers, booleans, a number format, and two simple formulas with their cached values |
| PPTX → ODP → PPTX | Two slides in order, their text, stored font attributes, widescreen dimensions, and the positions and sizes of two shapes per slide |

A stored font name does not ensure that font is installed or that the target
application renders identical line breaks or pagination. Formula text and
cached values in these examples do not establish general recalculation support.
Charts, pivot tables, macros, embedded objects, and presentation animations are
outside this coverage. Review the result in its target application before
relying on complex formatting or calculations. [Office Review](OFFICE_REVIEW.md)
provides the manual checklist; [Development](DEVELOPMENT.md#rich-office-conversion-checks)
describes automated coverage.

### Other Document Routes

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

There are no paid tiers or daily quotas. These limits keep individual jobs bounded:

| Operation | Limit |
| --- | --- |
| Conversion job | 1,000 input files |
| Native PDF and image-frame operations | 1,000 pages or frames, with a separate output-count cap |
| PDF organizer | One PDF; 1,000 pages; 512 MiB |
| Visual PDF merge | 2–100 source PDFs; 512 MiB total; 1,000 pages per source. The final arrangement must retain at least two documents and at most 1,000 pages. |
| Native image input | 150 megapixels; visual crop has the lower limit listed above |
| Rendered images | 40 megapixels; 16,384 pixels per side |
| Native text processing | 32 MiB |
| Native video trim source | Finite duration up to 365 days; 16,384 pixels per side; 150 megapixels per frame |
| Native video crop output | 40 megapixels; 16,384 pixels per side; even dimensions of at least 2 × 2 |

Preview storage is also bounded. PDF editors cache at most 24 thumbnails, audio
waveforms use a summary rather than a full decoded recording, and video editors
keep small preview images. Temporary PDF source copies are removed after their
work ends. These bounds do not measure the total memory used by macOS frameworks.

Archive and optional-engine operations have additional limits. Files that
exceed a limit receive an error without silently omitting content. Try a smaller
selection or lower image dimensions when appropriate.
