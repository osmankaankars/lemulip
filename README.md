<p align="center"><img src="Resources/AppIcon.png" width="132" height="132" alt="Freewheel’s green folded-ribbon app icon"></p>

# Freewheel

**File Tools, Right Where You Drag.**

Freewheel is a free, open-source file converter for macOS. Start dragging a file, tap a key, and drop it onto a format or tool. Convert a photo, merge PDFs, trim a clip, or make a ZIP without opening a different app for each job.

Files are processed on your Mac. No account, subscription, uploads, or analytics.

[Get Started](#get-started) · [User Guide](docs/USER_GUIDE.md) · [Formats](docs/FORMATS.md) · [FAQ](docs/FAQ.md) · [Roadmap](docs/ROADMAP.md) · [Design](docs/DESIGN.md)

## Get Started

**Freewheel is an early source preview.** A downloadable Mac release is not available yet. Check [Build and Verify](https://github.com/osmankaankars/freewheel/actions/workflows/build.yml) for the current build result. Finder drag compatibility and the full desktop workflow still need hands-on testing. Preview packages use ad-hoc signing, without Apple Developer ID signing or notarization.

You need **macOS 13 or later** and **Swift 5.9 or later** from Xcode or Command Line Tools.

Download the source, extract it, and run this in the Freewheel folder:

```bash
./Build-and-Install.command
```

The script builds Freewheel and installs it in your account's `Applications` folder. If an app is already there, it keeps that installation and puts the new build in `dist/Freewheel.app`.

Missing developer tools? Run `xcode-select --install` first. For full Xcode selection, release packages, and first-launch help, see [Installation](docs/INSTALL.md).

## A Wheel for the Files in Your Hand

1. Start dragging one or more local files.
2. Tap **⇧ Shift** for formats, **⌘ Command** for tools, or **⌃ Control** for file actions.
3. Drop onto the operation you want.

You can release the modifier key while you keep dragging. The center cancels; a drop outside the wheel submits no conversion. Tools with options, such as crop or trim, open a small settings panel before the job starts.

![Interactive browser preview with a sample file and conversion wheel.](docs/assets/demo-preview.png)

<!-- FREEWHEEL_DEMO_LINK_START -->
[Open the Browser Walkthrough](https://osmankaankars.github.io/freewheel/) · This is an interactive simulation with sample files; the Mac app performs conversions.
<!-- FREEWHEEL_DEMO_LINK_END -->

Prefer a window? Add files with **⌘O**, drop them into the workspace, or choose **Open With → Freewheel**. Reorder a selection before merging PDFs or combining images into a PDF. The same tools are available there, alongside a job queue, Activity, and a floating file shelf.

## What Can It Do?

| Work With | Examples |
| --- | --- |
| Images | PNG, JPEG, HEIC, TIFF and BMP; resize, crop, rotate, remove metadata; images to PDF |
| PDFs | Merge, split, extract pages, rotate, export pages as images, extract text, offline OCR |
| Audio and video | Native media conversion where macOS codecs allow it; more formats, trimming and compression with FFmpeg |
| Documents and tables | Basic text formats, CSV ↔ TSV and SRT ↔ VTT; Office formats with LibreOffice; EPUB and structured Markdown with Pandoc |
| Archives | Create ZIP and TAR, GZIP individual files, extract supported archives into a new folder |
| File actions | AirDrop, floating shelf, copy, move, copy path, open the containing folder in Terminal |

Formats depend on the input, installed engines, and available codecs. [The format guide](docs/FORMATS.md) lists supported routes and fidelity limits.

Image cropping currently uses centered dimensions, and media trimming uses start and end times. Visual crop handles and an audio waveform editor are [planned next](docs/ROADMAP.md#1-visual-image-crop); the browser walkthrough does not include those editors.

## Start With What Is Built In

Common image tools, PDF tools, OCR, archives, subtitles, and basic text conversion work without extra engines.

For more formats, install only what you need:

```bash
brew install ffmpeg imagemagick
brew install --cask libreoffice
```

These commands require [Homebrew](https://brew.sh). For Pandoc, use its [official macOS installer](https://pandoc.org/installing.html), which includes the templates needed by Freewheel's restricted document conversion.

Open **Settings → Local Engines → Refresh** afterward. Freewheel does not download helpers automatically. Installing engines needs internet access; conversion runs locally.

## Your Originals Stay Yours

Conversions create new files. Existing names get an unused suffix, such as `photo (2).png`. By default, a job saves every output beside the first selected file. Turn off **Save in the First File's Folder** to choose a destination each time.

**Move To…** deliberately moves the selected originals. PDF compression creates a flattened copy and removes searchable text, links, forms, and other PDF structure from that copy. The app asks you to acknowledge this before proceeding.

Activity lasts for the current session. Only preferences are saved. AirDrop shares files when you choose it.

## Use the Same Engine in Terminal

```bash
swift run freewheel convert png photo.heic
swift run freewheel run pdf.merge first.pdf second.pdf
swift run freewheel run media.trim clip.mp4 --start 5 --end 25
swift run freewheel engines
```

Use `swift run freewheel --help` for options, or see the [CLI Guide](docs/USER_GUIDE.md#command-line-use).

## Help Shape the Next Release

Try a small, non-sensitive file and tell us what worked or failed. Good reports include the input format, chosen operation, macOS version, and exact error. [Contributing](CONTRIBUTING.md) covers bug reports and focused changes.

The [roadmap](docs/ROADMAP.md) prioritizes reliable releases, visual editing, a warmer interface, and measurable limits on app size and idle resource use.

Freewheel is MIT licensed. It is an original implementation inspired by the drag-wheel workflow of [Tangerine](https://tangerineformac.com), with its own code and visual identity. It is not affiliated with Tangerine.

[License](LICENSE) · [Third-Party Notices](THIRD_PARTY_NOTICES.md) · [Security](SECURITY.md) · [Release Notes](docs/RELEASE_NOTES.md)
