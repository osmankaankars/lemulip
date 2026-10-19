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

App downloads run without Xcode or Swift. See [Signing and First Launch](#signing-and-first-launch)
before opening a preview for the first time.

### Verify a Download

Release assets include `SHA256SUMS.txt`. To check all three archives, put them
and the checksum file in the same folder, then run:

```bash
shasum -a 256 -c SHA256SUMS.txt
```

If you downloaded only the DMG or app ZIP, calculate that file's SHA-256 with
`shasum -a 256` and compare it with the matching line in `SHA256SUMS.txt`.
Checksums detect a mismatch with the published files; they do not provide Apple
notarization.

## Build From Source

You need **Swift 5.9 or later** from compatible Xcode Command Line Tools or full Xcode.

1. Download the source ZIP from the repository or a source release.
2. Extract it into its own folder.
3. Open Terminal in that folder and run:

```bash
./Build-and-Install.command
```

You can also double-click the command file in Finder.

The script builds the app, checks its bundle, applies an ad hoc signature, and installs it in your account's `Applications` folder. It opens the new installation when no existing Lemulip or Freewheel instance is running.

If Lemulip is already installed there, the script preserves it. The new app is at `dist/Lemulip.app`. Quit the current app before replacing it with the new build. Your preferences are stored separately from the app bundle.

### Upgrading From Freewheel

Freewheel was the app's original name. Finish any jobs and quit it before opening
Lemulip, which uses the same saved settings. The installer leaves `Freewheel.app`
in place; remove that old copy after checking the new app. Update shortcuts that
invoke the old `freewheel` CLI to use `lemulip`.

### Developer Tools

If developer tools are missing, run Apple's installer:

```bash
xcode-select --install
```

To use a full Xcode installation for this build:

```bash
DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" \
PATH="/usr/bin:/bin:/usr/sbin:/sbin" ./Build-and-Install.command
```

Replace the path if Xcode is installed elsewhere. This selects tools for one command; a later plain invocation or Finder launch uses the system's selected developer tools. See Apple's [command-line tools settings guide](https://developer.apple.com/documentation/xcode/configuring-command-line-tools-settings).

Lemulip supplies the archive declarations and links to the macOS libarchive library. A separate Homebrew libarchive installation is not required.

### Build Without Installing

```bash
./script/build_app.sh
```

The outputs are `dist/Lemulip.app` and `dist/lemulip`. For Apple Silicon and Intel binaries in one app:

```bash
./script/build_app.sh --universal
```

## Signing and First Launch

Current packages are **ad hoc signed**, without Apple Developer ID signing or notarization. macOS may block a downloaded app on first launch. Review its source and origin before opening it.

Apple's [guide to safely opening apps](https://support.apple.com/en-us/102445) explains first-launch controls. Lemulip does not disable Gatekeeper, remove quarantine attributes, or change system security settings.

After launch, start with a small image in the workspace. Add it with **⌘O**, select a different format, and check the result in Activity. Then try the drag wheel using the [User Guide](USER_GUIDE.md#the-drag-wheel).

## Optional Engines

Image, PDF, OCR, archive, subtitle, and basic text tools cover many tasks without
extra software. TXT and basic RTF → DOCX, plus CSV/TSV → XLSX, are also built in.
Install only the engines needed for your other [formats](FORMATS.md).

| Engine | Adds | Install |
| --- | --- | --- |
| FFmpeg | More audio/video formats and media tools | `brew install ffmpeg` |
| ImageMagick | WebP, AVIF, and additional image codecs | `brew install imagemagick` |
| LibreOffice | HTML → DOCX, complex RTF, existing Office documents, workbooks, and slides | `brew install --cask libreoffice` |
| Pandoc | EPUB and structured document routes | [Official macOS installer](https://pandoc.org/installing.html) |

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
the `DEVELOPER_DIR` example above. The compiler path in the error identifies the
toolchain in use. Keep source backups outside `Sources` and use a complete,
fresh checkout when updating from an old development build.

### A Conversion Fails or the Wheel Stays Hidden

Check Activity for the error, then follow the [FAQ](FAQ.md). Install a named engine if needed, use local files, or try the workspace.

## Uninstall

Quit Lemulip and remove `Lemulip.app`. Converted files remain in their output folders. Optional engines are separate installations and should be managed with their own uninstall methods.
