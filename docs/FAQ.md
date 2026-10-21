# Frequently Asked Questions

## Is Lemulip Free?

Yes. Lemulip is [MIT licensed](../LICENSE), with no subscription, account, or paid conversion tier. Optional engines are separate tools with their own licenses.

## Does It Upload My Files?

Conversions run locally. Lemulip has no file-upload service, analytics SDK, or automatic update service. It saves preferences, while Activity is held only for the current session.

AirDrop is a separate action that shares files when you choose it. Installing optional engines requires internet access.

## Which Macs Can Run It?

Lemulip requires **macOS 13 or later**. Release downloads include both Apple Silicon and Intel binaries. Source builds require Swift 5.9 or later from compatible Xcode or Command Line Tools.

This is a public preview. Compatibility and Finder drag behavior still need broader hands-on testing across supported Macs.

## Is There a Ready-to-Use Download?

Yes. Download the universal DMG or app ZIP from [Releases](https://github.com/osmankaankars/lemulip/releases). You do not need Xcode or Swift to run it. See [Installation](INSTALL.md) for download verification, first launch, and source builds.

## Why Does macOS Show a Warning When Opening a Download?

Check that your download came from this repository, then follow
[First Launch](INSTALL.md#first-launch). Do not ignore a warning for a download
from an unknown source.

## Why Does an Operation Ask for FFmpeg or Another Engine?

Some formats need an optional local converter. Install FFmpeg for broader media support, ImageMagick for additional image codecs, LibreOffice for rich documents, existing workbooks and slides, or Pandoc for EPUB and structured document routes.

See [Optional Engines](INSTALL.md#optional-engines), then click **Refresh** under **Settings → Local Engines**. Lemulip does not install a helper automatically.

## Can I Create Word, Excel, and PowerPoint Files?

Yes. Supported routes create **DOCX**, **XLSX**, and **PPTX** files. Microsoft Office is not required for conversion.

| Input → Output | Engine |
| --- | --- |
| TXT and basic RTF → DOCX | Built into macOS |
| CSV/TSV → XLSX | Built in; one worksheet, with every cell stored as text |
| Basic Markdown → DOCX | Built in; Pandoc for richer Markdown |
| HTML, complex RTF, and existing Office files → supported Office formats | LibreOffice |

LibreOffice runs in the background and is installed separately. It is not an output format. Rich formatting can change during conversion, and visual acceptance in Microsoft Office remains **Not Reviewed**. PDF → editable Office conversion is not implemented. See [Formats](FORMATS.md#documents-slides-and-spreadsheets) for the exact routes and limits.

Basic Markdown supports headings, simple lists, emphasis, code, and pipe tables.
If a Markdown file needs Pandoc, the whole Markdown selection uses it. Mixing
Markdown with other document types also uses Pandoc.

## Why Is Pandoc Reporting a Missing Template?

Lemulip runs Pandoc with `--sandbox`. The installed binary needs embedded data files for some formats, including EPUB, DOCX, and ODT. Install the [official Pandoc package](https://pandoc.org/installing.html), then refresh engine detection.

Pandoc documents the requirement in its [sandbox option](https://pandoc.org/MANUAL.html#option--sandbox).

## Why Does the Wheel Not Appear?

Keep Lemulip running and make sure **Drag Wheel Enabled** is checked in the menu bar. Start dragging before tapping Shift, Command, or Control. The wheel recognizes local file drags, not copied text or web links.

If the source application does not work with the wheel, add the files to the workspace and choose an operation there. You can also use **Open Wheel** for the clickable version.

## Can I Change the Theme?

Yes. Open **Settings → Appearance → Theme** and choose **Orchard Night**, **Vivid
Pistachio**, or **Lemon Drop**. Orchard Night is the default. The app remembers
your selection and applies it across its windows, wheel, and controls.

The light themes also work when macOS uses Dark Mode. See [Choose a Theme](USER_GUIDE.md#choose-a-theme).

## Do I Have to Hold the Modifier Key?

No. Tap the key after the drag begins. The wheel stays open while you continue dragging. Drop onto an operation to select it. Dropping in the center or outside the wheel submits no conversion.

The current modifier keys cannot be reassigned.

## Where Did the Converted Files Go?

By default, every output from a job goes into the first input's folder, including when the inputs came from different folders. In **Activity**, click an output to reveal it in Finder.

Turn off **Save in the First File's Folder** in Settings to choose a destination for each job.

## Can It Overwrite or Move an Original?

Conversions create new files and choose unused names. **Move To…** is an explicit file action that relocates the selected originals.

If a copy or move operation fails halfway through, completed transfers remain in place. Activity lists the completed outputs.

## Why Did a PDF Lose Its Text, Links, or Forms?

PDF compression flattens pages to images. That removes searchable text, links, forms, signatures, and accessibility structure in the new copy. The app explains this before the job starts and preserves the original.

Use another PDF operation when you need to retain that structure. PDF → editable Office documents is not implemented.

## Why Is My Compressed File Larger?

Compression depends on the source, codec, resolution, and selected quality. An already optimized file can become larger when re-encoded. Compare the result before deciding which copy to keep.

## Can It Convert Locked PDFs or Encrypted Archives?

The app and CLI do not offer PDF password entry. Open a protected PDF with its password and save an unlocked copy first. Encrypted archives are rejected.

## Is the Browser Demo the Real App?

The [interactive walkthrough](https://osmankaankars.github.io/lemulip/) uses sample data to explain the interaction; it does not convert files. You can also open `site/index.html` from a downloaded checkout.

It remembers the selected theme when browser storage is available. Sample files and activity last only for the current page session.

## How Can I Report a Problem?

Follow [Contributing](../CONTRIBUTING.md). Include the input format, selected operation, app and macOS versions, and the error text. A small synthetic example is more useful than a private document.

Remove personal paths, account details, and file contents from any public log. Security reports should follow [Security](../SECURITY.md).
