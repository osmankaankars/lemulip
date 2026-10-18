<p align="center"><img src="Resources/AppIcon.png" width="132" height="132" alt="Lemulip’s green folded-ribbon app icon"></p>

# Lemulip

**File Tools, Right Where You Drag.**

Lemulip is a free, open-source file converter for macOS. Start dragging a file, tap a key, and drop it onto a format or tool. Convert a photo, merge PDFs, trim a clip, or make a ZIP without opening a different app for each job.

Files are processed on your Mac. No account, subscription, uploads, or analytics.

[Get Started](#get-started) · [User Guide](docs/USER_GUIDE.md) · [Formats](docs/FORMATS.md) · [FAQ](docs/FAQ.md) · [Roadmap](docs/ROADMAP.md) · [Design](docs/DESIGN.md)

## Get Started

**Lemulip is an early public preview.** Check [Releases](https://github.com/osmankaankars/lemulip/releases) for verified Mac downloads. If the current release has no app assets, build from source below. [Build and Verify](https://github.com/osmankaankars/lemulip/actions/workflows/build.yml) tests Apple silicon and Intel and checks the exact universal packages before publishing. Finder drag compatibility and the full desktop workflow still need hands-on testing. Preview packages use ad-hoc signing, without Apple Developer ID signing or notarization.

You need **macOS 13 or later** and **Swift 5.9 or later** from Xcode or Command Line Tools.

Download the source, extract it, and run this in the Lemulip folder:

```bash
./Build-and-Install.command
```

The script builds Lemulip and installs it in your account's `Applications` folder. If an app is already there, it keeps that installation and puts the new build in `dist/Lemulip.app`.

Missing developer tools? Run `xcode-select --install` first. For full Xcode selection, release packages, and first-launch help, see [Installation](docs/INSTALL.md).

## A Wheel for the Files in Your Hand

1. Start dragging one or more local files.
2. Tap **⇧ Shift** for formats, **⌘ Command** for tools, or **⌃ Control** for file actions.
3. Drop onto the operation you want.

You can release the modifier key while you keep dragging. The center cancels; a drop outside the wheel submits no conversion. Tools with options open an editor or settings panel before the job starts.

![Interactive browser preview with a sample file and conversion wheel.](docs/assets/demo-preview.png)

<!-- LEMULIP_DEMO_LINK_START -->
[Open the Browser Walkthrough](https://osmankaankars.github.io/lemulip/) · This is an interactive simulation with sample files; the Mac app performs conversions.
<!-- LEMULIP_DEMO_LINK_END -->

Prefer a window? Add files with **⌘O**, drop them into the workspace, or choose **Open With → Lemulip**. Reorder a selection before merging PDFs or combining images into a PDF. The same tools are available there, alongside a job queue, Activity, and a floating file shelf.

## What Can It Do?

| Work With | Examples |
| --- | --- |
| Images | PNG, JPEG, HEIC, TIFF and BMP; visual crop, resize, rotate, remove metadata; images to PDF |
| PDFs | Merge, split, extract pages, rotate, export pages as images, extract text, offline OCR |
| Audio and video | Native media conversion where macOS codecs allow it; more formats, trimming and compression with FFmpeg |
| Documents and tables | Microsoft Word (DOCX), Excel (XLSX), PowerPoint (PPTX), text, CSV ↔ TSV, and subtitles; some routes need an optional local engine |
| Archives | Create ZIP and TAR, GZIP individual files, extract supported archives into a new folder |
| File actions | AirDrop, floating shelf, copy, move, copy path, open the containing folder in Terminal |

Formats depend on the input, installed engines, and available codecs. [The format guide](docs/FORMATS.md) lists supported routes and fidelity limits.

## See What You Keep

Open **Tools → Crop** with a single image. Move the selection, drag any of its
eight handles, or choose an aspect ratio. Exact pixel dimensions and keyboard
movement help with the last adjustment. **Create Copy** crops the original
resolution and leaves your source file in place.

The editor prepares a bounded preview in the background. Its first version
supports one still raster image at a time, up to 40 megapixels and 16,384 pixels
per side. See [Visual Image Crop](docs/USER_GUIDE.md#visual-image-crop) for controls
and format limits. Media trimming still uses start and end times; an audio
waveform editor is [the next feature milestone](docs/ROADMAP.md#2-audio-waveform-trim).

## Make It Yours

Choose **Orchard Night**, **Vivid Pistachio**, or **Lemon Drop** in
**Settings → Appearance → Theme**. Orchard Night is the default. Lemulip remembers
your choice and applies it across the workspace, wheel, and editors.

Try the same three appearances in the browser walkthrough. The walkthrough
uses sample files; it does not perform conversions or run the native crop editor.

## Start With What Is Built In

Common image tools, PDF tools, OCR, archives, subtitles, and basic text conversion work without extra engines.

For more formats, install only what you need:

```bash
brew install ffmpeg imagemagick
brew install --cask libreoffice
```

These commands require [Homebrew](https://brew.sh). For Pandoc, use its [official macOS installer](https://pandoc.org/installing.html), which includes the templates needed by Lemulip's restricted document conversion.

Open **Settings → Local Engines → Refresh** afterward. Lemulip does not download helpers automatically. Installing engines needs internet access; conversion runs locally.

DOCX, XLSX, and PPTX are Microsoft Office file formats. LibreOffice handles some of these conversions in the background; you can open the results in Word, Excel, or PowerPoint. Microsoft Office does not need to be installed for those routes. See [Office Formats](docs/FORMATS.md#documents-slides-and-spreadsheets) for the supported input and output combinations.

## Your Originals Stay Yours

Conversions create new files. Existing names get an unused suffix, such as `photo (2).png`. By default, a job saves every output beside the first selected file. Turn off **Save in the First File's Folder** to choose a destination each time.

**Move To…** deliberately moves the selected originals. PDF compression creates a flattened copy and removes searchable text, links, forms, and other PDF structure from that copy. The app asks you to acknowledge this before proceeding.

Activity lasts for the current session. Only preferences are saved. AirDrop shares files when you choose it.

## Use the Same Engine in Terminal

```bash
swift run lemulip convert png photo.heic
swift run lemulip run pdf.merge first.pdf second.pdf
swift run lemulip run media.trim clip.mp4 --start 5 --end 25
swift run lemulip engines
```

Use `swift run lemulip --help` for options, or see the [CLI Guide](docs/USER_GUIDE.md#command-line-use).

## Help Shape the Next Release

Try a small, non-sensitive file and tell us what worked or failed. Good reports include the input format, chosen operation, macOS version, and exact error. [Contributing](CONTRIBUTING.md) covers bug reports and focused changes.

The [roadmap](docs/ROADMAP.md) prioritizes reliable releases, visual editing, a warmer interface, and measurable limits on app size and idle resource use.

## Contributors

Created and maintained by **[Kaan Kars](https://github.com/osmankaankars)**.

Contributions are welcome. See [Contributing](CONTRIBUTING.md) for bug reports, improvements, and development guidance.

Lemulip is MIT licensed. Its drag-wheel workflow was inspired by [Tangerine](https://tangerineformac.com).

[License](LICENSE) · [Third-Party Notices](THIRD_PARTY_NOTICES.md) · [Security](SECURITY.md) · [Release Notes](docs/RELEASE_NOTES.md)
