# Release Notes

File tools, right where you drag.

Lemulip is a free, open-source file converter for macOS. Drag local files,
tap a modifier key, and choose a format or tool from the wheel. Use the workspace
when you need a queue, conversion options, or a closer look at the result.

## 0.1.3 · Three Themes and Visual Crop

- Choose **Orchard Night**, **Vivid Pistachio**, or **Lemon Drop** in Settings.
  Orchard Night stays the default; the app remembers your selection.
- Change appearance across the workspace, wheel, editors, and file shelf while
  keeping the current selection and job state.
- Crop one image on a native canvas with eight handles, preset aspect ratios,
  exact pixel dimensions, an optional thirds grid, and keyboard movement.
- Preview images in the background at a bounded resolution. Export the selected
  area from the original pixels with matching image orientation.
- Explain unsupported multi-file, animated, SVG, or codec inputs before a crop
  runs. The CLI keeps its existing centered-crop behavior.
- Try all three appearances in the browser walkthrough. The page remembers
  only the selected appearance when local storage is available.

The crop editor supports one still raster up to 40 megapixels and 16,384 pixels
per side. Its preview is capped at 1,600 pixels on the longest edge. Read
[Visual Image Crop](USER_GUIDE.md#visual-image-crop) for the controls and limits.
Audio waveform trimming remains the next planned editor.

This is a public preview candidate. Its source version is **0.1.3**; an existing
tag is never reused. Download assets appear only after the exact tagged commit
passes the Mac build and package checks described below.

## Naming and Packaging Foundation

- Lemulip is the product name across the app, CLI, website, guides, and packaging.
- Orchard Night remains the default appearance, with the approved green and
  cream folded-ribbon icon.
- Existing preferences are retained through the original bundle identifier and
  settings keys. The installer preserves older Freewheel app copies.
- The app build product is `LemulipApp`; the installed app is `Lemulip.app` and
  the CLI is `lemulip`.
- Repository links use the Lemulip name. Historical commits and tags are preserved.
- Universal packaging passes the input binary before `lipo -verify_arch`, fixing
  the argument-order error that stopped architecture verification.

The previous naming update at `46cb4dc` passed both Mac test jobs, universal
packaging, both downloaded-package verification jobs, and CodeQL. That baseline
does not establish the result for a newer commit.

## In This Preview

- A drag wheel with formats, tools, and file actions, plus a floating file shelf.
- Native image conversion, PDF tools, OCR, subtitles, delimited text, and archives.
- Optional FFmpeg, ImageMagick, LibreOffice, and Pandoc integrations.
- Conversion jobs with cancellation, Finder reveal, and outputs saved under unused names.
- A command-line interface that uses the same conversion engine.
- English and Turkish app interfaces. Public documentation is in English.
- An English user guide, format reference, and interactive browser walkthrough.

The browser walkthrough is a simulation using sample files. It does not convert
files or show a recording of the native app.

## Downloads

For a verified tagged release, the workflow attaches files in this layout,
with `<version>` matching the release version:

| File | Contents |
| --- | --- |
| `Lemulip-<version>-macOS-universal.zip` | App, CLI, installation guide, and license notices |
| `Lemulip-<version>-macOS-universal.dmg` | Drag-to-Applications installer |
| `Lemulip-<version>-Source.zip` | Reviewed source, docs, and build scripts |
| `SHA256SUMS.txt` | Checksums for the downloadable files |

Universal packages contain Apple silicon and Intel executables. Optional
conversion engines are installed separately. Read the [Installation Guide](INSTALL.md)
before downloading or building.

## What Has Been Verified

GitHub release packages are published only after the workflow's Mac tests and
checks of the downloaded packages succeed. Check the run for the exact release
commit. A successful source build alone does not establish the result of those
checks. See [Development](DEVELOPMENT.md) for the checks and their scope.

## Preview Limits

Packages are ad hoc signed and are **not Developer ID signed or notarized**.
macOS may block a downloaded copy. Building from source is available.

Native Finder drag behavior, multiple displays, and clean-machine installation
still need broader hands-on feedback. Document layout, supported media codecs,
OCR results, and optional-engine behavior vary with the input and installed
tools. The [format reference](FORMATS.md) explains the limits.

The project uses Swift 5 language mode. AVFoundation Sendable-capture warnings
and selector-style warnings may appear with newer SDKs. A complete Swift 6
language-mode migration is separate work.

## Fixes Included

- An explicit main-actor application entry point fixes desktop startup compilation.
- Private, pinned libarchive headers allow builds with SDKs that omit those headers.
- Executable build helpers are preserved in source packages.

Lemulip is MIT licensed. Please report a reproducible issue with a small,
non-sensitive sample if a conversion fails.
