<p align="center"><img src="Resources/AppIcon.png" width="132" height="132" alt="Lemulip’s green folded ribbon on a warm white app icon"></p>

# Lemulip

**File Tools, Right Where You Drag.**

Lemulip is a free, open-source file utility for macOS. Drag a file, tap a key,
and choose a format or tool. Crop a photo, trim a clip, arrange PDFs, or turn a
simple table into an Excel workbook.

Files are processed on your Mac. No account, subscription, uploads, or analytics.

[Download for Mac](https://github.com/osmankaankars/lemulip/releases) · [Try the Wheel](https://osmankaankars.github.io/lemulip/) · [User Guide](docs/USER_GUIDE.md) · [Formats](docs/FORMATS.md)

## Get Started

**Public Preview · macOS 13+ · Apple Silicon and Intel**

Download the **macOS universal DMG** from [Releases](https://github.com/osmankaankars/lemulip/releases),
open it, and drag **Lemulip** into **Applications**. The app ZIP also includes
the `lemulip` command-line tool. Neither download requires Xcode.

Preview downloads are ad hoc signed and are not yet notarized by Apple.
Follow [First Launch](docs/INSTALL.md#signing-and-first-launch) if macOS blocks
opening the app. Native interaction and accessibility reviews are still open
in the [Roadmap](docs/ROADMAP.md).

## A Wheel for Your Files

1. Start dragging one or more local files.
2. Tap **⇧ Shift** for formats, **⌘ Command** for tools, or **⌃ Control** for file actions.
3. Drop onto an operation. Editors and option panels open when needed.

The center cancels; dropping outside the wheel submits no conversion.
Prefer a window? Add files with **⌘O**, drop them into Workspace, or choose
**Open With → Lemulip**. A job queue, Activity, and floating file shelf keep
related work together.

![Browser walkthrough showing a sample file and conversion wheel. This is a simulation.](docs/assets/demo-preview.png)

[Open the Browser Walkthrough](https://osmankaankars.github.io/lemulip/) — an
interactive simulation with sample files. The macOS app performs conversions.

## What Can It Do?

| Work With | Tools |
| --- | --- |
| Images | Convert PNG, JPEG, HEIC, TIFF and BMP; visual crop, resize, rotate, remove metadata; images to PDF |
| PDFs | Preview, reorder, rotate, remove and extract pages; arrange documents before merging; split, export page images, extract text, offline OCR |
| Audio | Waveform trim with selection playback; M4A, WAV and AIFF export |
| Video | Native preview, visual trim and crop, MP4/MOV export |
| Documents and Tables | Built-in TXT, basic RTF, and basic Markdown → DOCX; CSV/TSV → XLSX; CSV ↔ TSV; subtitles |
| Archives | Create ZIP and TAR, GZIP individual files, extract supported archives into a new folder |
| File Actions | AirDrop, floating shelf, copy, move, copy path, open the containing folder in Terminal |

The visual editors let you review the crop, selection, or page order before
choosing **Create Copy**. See the [User Guide](docs/USER_GUIDE.md) for each tool's
controls and the [Formats](docs/FORMATS.md) guide for input and export limits.

## Start With What Is Built In

Common image, PDF, OCR, archive, subtitle, and basic Office tools work without
extra engines. Basic RTF export keeps supported font and paragraph formatting.
Markdown notes can become Word documents with headings, simple lists, emphasis,
code, and tables. CSV/TSV export creates one Excel worksheet and keeps every
value as text, including leading zeros and formula-like content.

Add optional local engines only for the formats you need:

| Engine | Adds |
| --- | --- |
| FFmpeg | Additional audio and video formats and tools |
| ImageMagick | Additional image formats |
| LibreOffice | Richer Office documents, workbooks and presentations; complex RTF and HTML → DOCX |
| Pandoc | Richer Markdown → DOCX, EPUB, and other supported document routes |

Install instructions are in [Optional Engines](docs/INSTALL.md#optional-engines).
Refresh detection in **Settings → Local Engines** afterward. Lemulip does not
download engines automatically. Markdown outside the [built-in subset](docs/FORMATS.md#html-and-markdown-word-export)
uses Pandoc for the whole selection. Microsoft Office is not required for
conversion; visual review of generated files in Office is tracked separately.

## Make It Yours

Choose **Orchard Night**, **Vivid Pistachio**, or **Lemon Drop** in
**Settings → Appearance → Theme**. Orchard Night is the default. Your choice is
remembered across the workspace, wheel, and editors. Every theme shares the
warm white icon tile and vivid green ribbon.

## Your Originals Stay Yours

Conversions create new files under unused names. By default, a job saves output
beside its first file; PDF merge follows the first retained document in the
arranged list. Change **Save in the First File's Folder** to choose a destination.

**Move To…** moves the selected originals. **Compress PDF** creates a flattened
copy, removing searchable text, links, forms, and other PDF structure from that
copy; the app asks you to acknowledge this first. Activity lasts for the current
session. Only preferences are saved.

## Build From Source

Use **Swift 5.9+** from compatible Xcode Command Line Tools or full Xcode.
From the extracted source folder, run:

```bash
./Build-and-Install.command
```

The script installs to your account's `Applications` folder. If Lemulip is
already installed there, it keeps that copy and places the new build in
`dist/Lemulip.app`. See [Installation](docs/INSTALL.md) for developer-tool setup
and [Development](docs/DEVELOPMENT.md) for checks and packaging.

The CLI uses the same conversion engine:

```bash
swift run lemulip convert png photo.heic
swift run lemulip run pdf.merge first.pdf second.pdf
swift run lemulip engines
```

More examples: [CLI Guide](docs/USER_GUIDE.md#command-line-use).

## Contributors

Created and maintained by **[Kaan Kars](https://github.com/osmankaankars)**.
Bug reports and focused improvements are welcome; see [Contributing](CONTRIBUTING.md)
and the [Roadmap](docs/ROADMAP.md).

Lemulip is MIT licensed. Its drag-wheel workflow was inspired by [Tangerine](https://tangerineformac.com).

[License](LICENSE) · [Third-Party Notices](THIRD_PARTY_NOTICES.md) · [Security](SECURITY.md) · [FAQ](docs/FAQ.md) · [Design](docs/DESIGN.md) · [Release Notes](docs/RELEASE_NOTES.md)
