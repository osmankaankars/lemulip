# Install Lemulip

Lemulip is a public preview for **macOS 13 or later**, with universal packages for
Apple Silicon and Intel. Broader hands-on testing across supported Macs is ongoing.

## Install From a Release

Open [Releases](https://github.com/osmankaankars/lemulip/releases) and expand the
latest preview's **Assets**. Choose the DMG for a regular installation or the app
ZIP if you also want the command-line tool.

| Download | Includes | Install |
| --- | --- | --- |
| `Lemulip-<version>-macOS-universal.dmg` | Mac app and guides | Open the DMG and drag **Lemulip** into **Applications** |
| `Lemulip-<version>-macOS-universal.zip` | Mac app, `lemulip` CLI, and guides | Extract the ZIP and move **Lemulip.app** into **Applications** |
| `Lemulip-<version>-Source.zip` | Source code | Follow the source-build instructions below |

App downloads run without Xcode or Swift. See [First Launch](#first-launch)
before opening a preview for the first time.

### Verify a Download

Release assets include `SHA256SUMS.txt`. To check all three archives, put them
and the checksum file in the same folder, then run:

```bash
shasum -a 256 -c SHA256SUMS.txt
```

If you downloaded only the DMG or app ZIP, calculate that file's SHA-256 with
`shasum -a 256` and compare it with the matching line in `SHA256SUMS.txt`.
Checksums help detect a mismatch with the published files. Verify that the
release comes from this repository before opening a download.

## Build From Source

Use Swift 5.9+ from compatible Xcode tools, then run `./Build-and-Install.command`.
See [Development](DEVELOPMENT.md#build-and-check) for build and verification commands.
The installer preserves an existing app; a separate build remains in `dist`.

### Upgrading From Freewheel

Quit the old app before opening Lemulip. Saved settings are retained; the installer leaves the old application in place. Update CLI shortcuts to `lemulip`.

## First Launch

macOS may ask you to confirm a downloaded app on first launch. Check that your
download came from this repository before opening it.

Apple's [guide to safely opening apps](https://support.apple.com/en-us/102445) explains first-launch controls. Lemulip does not disable Gatekeeper, remove quarantine attributes, or change system security settings.


## Optional Engines

Image, PDF, OCR, archive, subtitle, and basic text tools cover many tasks without
extra software. TXT, basic RTF, and basic Markdown → DOCX, plus CSV/TSV → XLSX,
are also built in.
Install only the engines needed for your other [formats](FORMATS.md).

| Engine | Adds | Install |
| --- | --- | --- |
| FFmpeg | More audio/video formats and media tools | `brew install ffmpeg` |
| ImageMagick | WebP, AVIF, and additional image codecs | `brew install imagemagick` |
| LibreOffice | HTML → DOCX, complex RTF, existing Office documents, workbooks, and slides | `brew install --cask libreoffice` |
| Pandoc | Richer Markdown → DOCX, Markdown → HTML/ODT, and EPUB | [Official macOS installer](https://pandoc.org/installing.html) |

The `brew` commands require [Homebrew](https://brew.sh). Each engine has its own OS requirements. Installers need internet access; Lemulip's conversions run locally.

For Pandoc, use a build with embedded data files, such as its official installer. Lemulip keeps [Pandoc's sandbox](https://pandoc.org/MANUAL.html#option--sandbox) enabled. A missing EPUB, DOCX, or ODT template usually means the installed binary lacks the needed embedded files.

Open **Settings → Local Engines** and click **Refresh** after installation. The app checks standard Homebrew and system locations, its process PATH, and LibreOffice's application bundle. It does not install helpers automatically.

## Troubleshooting

### Permission Denied for a Build Script

From the extracted source folder:

```bash
chmod u+x ./Build-and-Install.command ./script/build_app.sh
./Build-and-Install.command
```

### Invalid Manifest or PackageDescription Linker Error

Check which developer tools are selected:

```bash
xcode-select --print-path
xcrun --sdk macosx swift --version
xcrun --sdk macosx swift package dump-package
```

If the failure occurs before source compilation, try compatible full Xcode using
a `DEVELOPER_DIR` pointing at compatible full Xcode. The compiler path in the error identifies the
toolchain in use. Keep source backups outside `Sources` and use a complete,
fresh checkout when updating from an old development build.

### A Conversion Fails or the Wheel Stays Hidden

Check Activity for the error, then follow the [User Guide](USER_GUIDE.md#if-something-fails). Install a named engine if needed, use local files, or try the workspace.

## Uninstall

Quit Lemulip and remove `Lemulip.app`. Converted files remain in their output folders. Optional engines are separate installations and should be managed with their own uninstall methods.
