![Freewheel. File tools, right where you drag.](docs/assets/cover.png)

# Freewheel

**File tools, right where you drag.**

Freewheel is a free, open-source file converter for macOS. Start dragging a file, tap a key, and drop it onto a format or tool. Convert a photo, merge PDFs, trim a clip, or make a ZIP without opening a different app for each job.

Files are processed on your Mac. No account, subscription, uploads, or analytics.

[Get started](#get-started) · [User guide](docs/USER_GUIDE.md) · [Formats](docs/FORMATS.md) · [FAQ](docs/FAQ.md)

## Get started

**0.1.2 is an early preview.** A source build has completed on Apple silicon. Finder drag compatibility and the full desktop workflow still need hands-on testing. Downloaded packages are ad-hoc signed, without Apple Developer ID signing or notarization.

You need **macOS 13 or later** and **Swift 5.9 or later** from Xcode or Command Line Tools.

Download the source, extract it, and run this in the Freewheel folder:

```bash
./Build-and-Install.command
```

The script builds Freewheel and installs it in your account's `Applications` folder. If an app is already there, it keeps that installation and puts the new build in `dist/Freewheel.app`.

Missing developer tools? Run `xcode-select --install` first. For full Xcode selection, release packages, and first-launch help, see [Installation](docs/INSTALL.md).

If a previous build needed `DEVELOPER_DIR` to select another Xcode installation, include that setting again each time you build. Running the plain command above uses your currently selected developer tools.

## A wheel for the files in your hand

1. Start dragging one or more local files.
2. Tap **⇧ Shift** for formats, **⌘ Command** for tools, or **⌃ Control** for file actions.
3. Drop onto the operation you want.

You can release the modifier key while you keep dragging. The center cancels; a drop outside the wheel submits no conversion. Tools with options, such as crop or trim, open a small settings panel before the job starts.

![Interactive browser preview with a sample file and conversion wheel.](docs/assets/demo-preview.png)

<!-- FREEWHEEL_DEMO_LINK_START -->
[Open the browser walkthrough](https://osmankaankars.github.io/freewheel/) · Available after the Pages deployment succeeds. This is a simulation; the Mac app performs conversions.
<!-- FREEWHEEL_DEMO_LINK_END -->

Prefer a window? Add files with **⌘O**, drop them into the workspace, or choose **Open With → Freewheel**. Reorder a selection before merging PDFs or combining images into a PDF. The same tools are available there, alongside a job queue, Activity, and a floating file shelf.

## What can it do?

| Work with | Examples |
| --- | --- |
| Images | PNG, JPEG, HEIC, TIFF and BMP; resize, crop, rotate, remove metadata; images to PDF |
| PDFs | Merge, split, extract pages, rotate, export pages as images, extract text, offline OCR |
| Audio and video | Native media conversion where macOS codecs allow it; more formats, trimming and compression with FFmpeg |
| Documents and tables | Basic text formats, CSV ↔ TSV and SRT ↔ VTT; Office formats with LibreOffice; EPUB and structured Markdown with Pandoc |
| Archives | Create ZIP and TAR, GZIP individual files, extract supported archives into a new folder |
| File actions | AirDrop, floating shelf, copy, move, copy path, open the containing folder in Terminal |

Formats depend on the input, installed engines, and available codecs. [The format guide](docs/FORMATS.md) lists supported routes and fidelity limits.

## Start with what is built in

Common image tools, PDF tools, OCR, archives, subtitles, and basic text conversion work without extra engines.

For more formats, install only what you need:

```bash
brew install ffmpeg imagemagick
brew install --cask libreoffice
```

These commands require [Homebrew](https://brew.sh). For Pandoc, use its [official macOS installer](https://pandoc.org/installing.html), which includes the templates needed by Freewheel's restricted document conversion.

Open **Settings → Local Engines → Refresh** afterward. Freewheel does not download helpers automatically. Installing engines needs internet access; conversion runs locally.

## Your originals stay yours

Conversions create new files. Existing names get an unused suffix, such as `photo (2).png`. By default, a job saves every output beside the first selected file. Turn off **Save in the first file's folder** to choose a destination each time.

**Move to…** deliberately moves the selected originals. PDF compression creates a flattened copy and removes searchable text, links, forms, and other PDF structure from that copy. The app asks you to acknowledge this before proceeding.

Activity lasts for the current session. Only preferences are saved. AirDrop shares files when you choose it.

## Use the same engine in Terminal

```bash
swift run freewheel convert png photo.heic
swift run freewheel run pdf.merge first.pdf second.pdf
swift run freewheel run media.trim clip.mp4 --start 5 --end 25
swift run freewheel engines
```

Use `swift run freewheel --help` for options, or see the [CLI guide](docs/USER_GUIDE.md#command-line-use).

## Help shape the next release

Try a small, non-sensitive file and tell us what worked or failed. Good reports include the input format, chosen operation, macOS version, and exact error. [Contributing](CONTRIBUTING.md) covers bug reports and focused changes.

Freewheel is MIT licensed. It is an original implementation inspired by the drag-wheel workflow of [Tangerine](https://tangerineformac.com), with its own code and visual identity. It is not affiliated with Tangerine.

[License](LICENSE) · [Third-party notices](THIRD_PARTY_NOTICES.md) · [Security](SECURITY.md) · [Release notes](docs/RELEASE_NOTES.md)
