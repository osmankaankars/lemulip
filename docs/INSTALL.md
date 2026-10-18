# Install Freewheel

Freewheel is an early preview for **macOS 13 or later**. A source build has completed on Apple silicon. The full desktop workflow and compatibility across supported Macs are still being tested.

## Build from source

You need **Swift 5.9 or later** from compatible Xcode Command Line Tools or full Xcode.

1. Download the source ZIP from the repository or a source release.
2. Extract it into its own folder.
3. Open Terminal in that folder and run:

```bash
./Build-and-Install.command
```

You can also double-click the command file in Finder.

The script builds the app, checks its bundle, applies an ad-hoc signature, and installs it in your account's `Applications` folder. It opens the app after a new installation.

If Freewheel is already installed there, the script preserves it. The new app is at `dist/Freewheel.app`. Quit the current app before replacing it with the new build. Your preferences are stored separately from the app bundle.

### Developer tools

If developer tools are missing, run Apple's installer:

```bash
xcode-select --install
```

To use a full Xcode installation for this build:

```bash
DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" \
PATH="/usr/bin:/bin:/usr/sbin:/sbin" ./Build-and-Install.command
```

Replace the path if Xcode lives elsewhere, including on an external drive. This command selects tools for one build without changing the system-wide developer directory. See Apple's [command-line tools settings guide](https://developer.apple.com/documentation/xcode/configuring-command-line-tools-settings).

Repeat the `DEVELOPER_DIR` setting each time you use this Xcode installation. A later plain `./Build-and-Install.command`, or a double-click in Finder, does not retain the earlier command's setting. If Xcode is on an external drive, keep that drive connected while building.

Freewheel does not require a particular Command Line Tools 16.4 release. It also does not require a Homebrew libarchive installation; the source supplies the archive declarations and links to the macOS library.

### Build without installing

```bash
./script/build_app.sh
```

The outputs are `dist/Freewheel.app` and `dist/freewheel`. For Apple silicon and Intel binaries in one app:

```bash
./script/build_app.sh --universal
```

## Release packages

When a release contains binary assets, choose the **macOS universal DMG** for the app, or the **ZIP** for the app plus command-line executable.

Open the DMG and drag Freewheel into Applications. For the ZIP, extract it and move the app into Applications. Keep the CLI somewhere convenient if you plan to use it.

The **Build and verify** workflow is configured to produce a `Freewheel-macOS-universal` artifact after its checks succeed. Download only from a successful run. A workflow file in the source is not evidence of a completed build.

Release assets include `SHA256SUMS.txt`. With the listed packages and checksum file in the same folder, check them using:

```bash
shasum -a 256 -c SHA256SUMS.txt
```

The checksum detects a mismatch with the published package. It does not provide Apple notarization.

## Signing and first launch

Current packages are **ad-hoc signed**, without Apple Developer ID signing or notarization. macOS may block a downloaded app on first launch. Review its source and origin before opening it.

Apple's [guide to safely opening apps](https://support.apple.com/en-us/102445) explains first-launch controls. Freewheel does not disable Gatekeeper, remove quarantine attributes, or change system security settings.

After launch, start with a small image in the workspace. Add it with **⌘O**, select a different format, and check the result in Activity. Then try the drag wheel using the [user guide](USER_GUIDE.md#the-drag-wheel).

## Optional engines

Many image, PDF, OCR, archive, subtitle, and basic text tools are built in. Install only the extra engines you need.

| Engine | Adds | Install |
| --- | --- | --- |
| FFmpeg | More audio/video formats and media tools | `brew install ffmpeg` |
| ImageMagick | WebP, AVIF, and additional image codecs | `brew install imagemagick` |
| LibreOffice | Office documents, slides, and spreadsheets | `brew install --cask libreoffice` |
| Pandoc | EPUB and structured document routes | [Official macOS installer](https://pandoc.org/installing.html) |

The `brew` commands require [Homebrew](https://brew.sh). Each engine has its own OS requirements. Installers need internet access; Freewheel's conversions run locally.

For Pandoc, use a build with embedded data files, such as its official installer. Freewheel keeps [Pandoc's sandbox](https://pandoc.org/MANUAL.html#option--sandbox) enabled. A missing EPUB, DOCX, or ODT template usually means the installed binary lacks the needed embedded files.

Open **Settings → Local Engines** and click **Refresh** after installation. The app checks standard Homebrew and system locations, its process PATH, and LibreOffice's application bundle. It does not install helpers automatically.

## Troubleshooting

### Permission denied for a build script

From the extracted source folder:

```bash
chmod u+x ./Build-and-Install.command ./script/build_app.sh
./Build-and-Install.command
```

### Invalid manifest or PackageDescription linker error

Check which developer tools are selected:

```bash
xcode-select --print-path
xcrun --sdk macosx swift --version
xcrun --sdk macosx swift package dump-package
```

If the active Command Line Tools installation fails before source compilation, try a compatible full Xcode installation using the per-command `DEVELOPER_DIR` example above.

If that full Xcode build previously succeeded and this error returns after running the plain build command, check the compiler path printed in the error. A path under `/Library/Developer/CommandLineTools` means this attempt selected that toolchain again. Repeat the working Xcode selection for the build.

### Missing archive.h

Use source 0.1.1 or later. Keep `Sources/CFreewheelArchive/LibarchiveHeaders` and its matching `Package.swift` settings together. No manual SDK edits are needed.

### MainActor startup error

Use source 0.1.2 or later. The GUI target uses `FreewheelApplication.swift` as its entry point. An old `Sources/Freewheel/main.swift` must not remain beside it; keep backups outside `Sources`. The CLI's separate `main.swift` is still required.

Recent SDKs may also print AVFoundation Sendable-capture and selector-style warnings. Those warnings were present in a completed build and are separate from the corrected startup error.

### A conversion fails or the wheel stays hidden

Check Activity for the error, then follow the [FAQ](FAQ.md). Install a named engine if needed, use local files, or try the workspace.

## Uninstall

Quit Freewheel and remove `Freewheel.app`. Converted files remain in their output folders. Optional engines are separate installations and should be managed with their own uninstall methods.
