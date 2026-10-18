# Install Lemulip

Lemulip is an early public preview for **macOS 13 or later**, with universal
packages for Apple silicon and Intel. The full desktop workflow and compatibility
across supported Macs are still being tested.

## Install From a Release

Open [Releases](https://github.com/osmankaankars/lemulip/releases) and expand the
preview's **Assets**. Downloads appear after that version passes its Mac build
and package checks. If no app download is listed yet, use [Build From Source](#build-from-source).

A successful **Preview Release** workflow may only mean its prerequisite check
finished. Downloads are ready when that version's release lists its DMG or app
ZIP under **Assets**. A failed **Build and Verify** run blocks package publication.

| Download | Includes | Install |
| --- | --- | --- |
| `Lemulip-<version>-macOS-universal.dmg` | Mac app and guides | Open the DMG and drag **Lemulip** into **Applications** |
| `Lemulip-<version>-macOS-universal.zip` | Mac app, `lemulip` CLI, and guides | Extract the ZIP and move **Lemulip.app** into **Applications** |
| `Lemulip-<version>-Source.zip` | Source code | Follow the source-build instructions below |

The app downloads run without installing Xcode or Swift. Keep the CLI somewhere
convenient if you plan to use it. See [Signing and First Launch](#signing-and-first-launch)
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

The script builds the app, checks its bundle, applies an ad-hoc signature, and installs it in your account's `Applications` folder. It opens a new installation when no Lemulip or previous Freewheel instance is running.

If Lemulip is already installed there, the script preserves it. The new app is at `dist/Lemulip.app`. Quit the current app before replacing it with the new build. Your preferences are stored separately from the app bundle.

### Upgrading From Freewheel

Lemulip is the new product name. Let any running jobs finish, then quit the
previous Freewheel app before opening Lemulip. The bundle identifier and existing
preference keys are unchanged, so the new app uses the same saved settings.

The installer creates `Lemulip.app` and leaves an older `Freewheel.app` in place.
After verifying the new app, you can remove the old app copy yourself. Converted
files remain where you saved them. The CLI is now `lemulip`; update any commands
or shortcuts that invoke `freewheel`.

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

Replace the path if Xcode is installed elsewhere. This command selects tools for one build without changing the system-wide developer directory. See Apple's [command-line tools settings guide](https://developer.apple.com/documentation/xcode/configuring-command-line-tools-settings).

The `DEVELOPER_DIR` setting applies only to that command. A plain `./Build-and-Install.command`, or a double-click in Finder, uses the currently selected developer tools.

Lemulip supplies the archive declarations and links to the macOS libarchive library. A separate Homebrew libarchive installation is not required.

### Build Without Installing

```bash
./script/build_app.sh
```

The outputs are `dist/Lemulip.app` and `dist/lemulip`. For Apple silicon and Intel binaries in one app:

```bash
./script/build_app.sh --universal
```

## Signing and First Launch

Current packages are **ad-hoc signed**, without Apple Developer ID signing or notarization. macOS may block a downloaded app on first launch. Review its source and origin before opening it.

Apple's [guide to safely opening apps](https://support.apple.com/en-us/102445) explains first-launch controls. Lemulip does not disable Gatekeeper, remove quarantine attributes, or change system security settings.

After launch, start with a small image in the workspace. Add it with **⌘O**, select a different format, and check the result in Activity. Then try the drag wheel using the [User Guide](USER_GUIDE.md#the-drag-wheel).

## Optional Engines

Many image, PDF, OCR, archive, subtitle, and basic text tools are built in.
TXT → DOCX on macOS and CSV/TSV → XLSX also need no extra engine. The XLSX
route creates one worksheet with all values kept as text. Install only the
extra engines required for your other formats.

| Engine | Adds | Install |
| --- | --- | --- |
| FFmpeg | More audio/video formats and media tools | `brew install ffmpeg` |
| ImageMagick | WebP, AVIF, and additional image codecs | `brew install imagemagick` |
| LibreOffice | Rich documents, existing workbooks, and slides | `brew install --cask libreoffice` |
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

If the active Command Line Tools installation fails before source compilation, try a compatible full Xcode installation using the per-command `DEVELOPER_DIR` example above.

Check the compiler path printed in the error. A path under `/Library/Developer/CommandLineTools` identifies the standalone Command Line Tools installation. Use the per-command Xcode selection above to choose a different compatible toolchain.

### Missing `archive.h`

Use source 0.1.1 or later. Keep `Sources/CFreewheelArchive/LibarchiveHeaders` and its matching `Package.swift` settings together. No manual SDK edits are needed.

### MainActor Startup Error

Use source 0.1.2 or later. The GUI target uses `FreewheelApplication.swift` as its entry point. An old `Sources/Freewheel/main.swift` must not remain beside it; keep backups outside `Sources`. The CLI's separate `main.swift` is still required.

Recent SDKs may also print AVFoundation Sendable-capture and selector-style warnings. The project currently uses Swift 5 language mode; a complete Swift 6 language-mode migration is separate work.

### A Conversion Fails or the Wheel Stays Hidden

Check Activity for the error, then follow the [FAQ](FAQ.md). Install a named engine if needed, use local files, or try the workspace.

## Uninstall

Quit Lemulip and remove `Lemulip.app`. Converted files remain in their output folders. Optional engines are separate installations and should be managed with their own uninstall methods.
