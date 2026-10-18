# Freewheel 0.1.2 · Public preview

File tools, right where you drag.

Freewheel is a free, open-source file converter for macOS. Drag local files,
tap a modifier key, and choose a format or tool from the wheel. Use the workspace
when you need a queue, conversion options, or a closer look at the result.

## In this preview

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

When this release's Mac checks pass, the workflow attaches:

| File | Contents |
| --- | --- |
| `Freewheel-0.1.2-macOS-universal.zip` | App, CLI, installation guide, and license notices |
| `Freewheel-0.1.2-macOS-universal.dmg` | Drag-to-Applications installer |
| `Freewheel-0.1.2-Source.zip` | Reviewed source, docs, and build scripts |
| `SHA256SUMS.txt` | Checksums for the downloadable files |

Universal packages contain Apple silicon and Intel executables. Optional
conversion engines are installed separately. Read the [installation guide](INSTALL.md)
before downloading or building.

## What has been verified

A release build on an Apple silicon Mac completed with Xcode 26.3 and Swift
6.2.4. The generated bundle passed property-list and ad hoc signature checks.
Portable engine, archive, output-safety, process, and wheel-geometry tests have
also passed. See [Development](DEVELOPMENT.md) for the scope of that evidence.

GitHub release packages are published only after the workflow's Mac tests and
checks of the downloaded packages succeed. Check the run for the exact release
commit. A successful source build alone does not establish the result of those
checks.

## Preview limits

Packages are ad hoc signed and are **not Developer ID signed or notarized**.
macOS may block a downloaded copy. Building from source is available.

Native Finder drag behavior, multiple displays, and clean-machine installation
still need broader hands-on feedback. Document layout, supported media codecs,
OCR results, and optional-engine behavior vary with the input and installed
tools. The [format reference](FORMATS.md) explains the limits.

The project uses Swift 5 language mode. AVFoundation Sendable-capture warnings
and selector-style warnings remain with newer SDKs; they did not block the
verified source build. This is not a complete Swift 6 language-mode migration.

## Fixes included

- An explicit main-actor application entry point fixes desktop startup compilation.
- Private, pinned libarchive headers allow builds with SDKs that omit those headers.
- Executable build helpers are preserved in source packages.

Freewheel is MIT licensed. Please report a reproducible issue with a small,
non-sensitive sample if a conversion fails.
