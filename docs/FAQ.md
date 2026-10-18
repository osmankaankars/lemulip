# Frequently Asked Questions

## Is Lemulip Free?

Yes. The source is released under the [MIT license](../LICENSE). There is no subscription, account requirement, or paid conversion tier. Optional engines are separate open-source tools with their own licenses.

## Does It Upload My Files?

Conversions run locally. Lemulip has no file-upload service, analytics SDK, or automatic update service. It saves preferences, while Activity is held only for the current session.

AirDrop is a separate action that shares files when you choose it. Installing optional engines requires internet access.

## Which Macs Can Run It?

The app targets macOS 13 or later and supports building for Apple silicon and Intel. Source builds require Swift 5.9 or later from compatible Xcode or Command Line Tools.

An Apple silicon source build has completed on macOS. That does not establish compatibility with every supported OS or Intel Mac. The current release is an early preview, and Finder drag behavior still needs broader hands-on testing.

## Is There a Ready-to-Use Download?

Release packaging is configured to produce a universal app, ZIP, and DMG. Use only assets attached to a release or a successful workflow run; a source checkout by itself is not a built app.

If a release has no binary assets, [build from source](INSTALL.md#build-from-source). Current packages are ad-hoc signed and are not Apple Developer ID signed or notarized.

## Why Does macOS Show a Warning When Opening a Download?

The current distribution does not have Developer ID signing and notarization. macOS may block a downloaded app on first launch.

Review the source and release origin before opening it. Apple's [guide to safely opening apps](https://support.apple.com/en-us/102445) explains the available controls. Lemulip does not disable Gatekeeper or change the Mac's security settings.

## Why Does an Operation Ask for FFmpeg or Another Engine?

Some formats need an optional local converter. Install FFmpeg for broader media support, ImageMagick for additional image codecs, LibreOffice for Office files, or Pandoc for EPUB and structured document routes.

See [Optional engines](INSTALL.md#optional-engines), then click **Refresh** under **Settings → Local Engines**. Lemulip does not install a helper automatically.

## Can I Create Word, Excel, and PowerPoint Files?

Yes. Supported routes can create **DOCX** documents, **XLSX** workbooks, and
**PPTX** presentations. These are Microsoft Office file formats, and the results
can be opened in Word, Excel, and PowerPoint.

LibreOffice is the optional local conversion engine for many of these routes.
Lemulip calls it in the background without opening its editor. Microsoft Office
does not need to be installed. Markdown-to-DOCX uses Pandoc instead.

Installing LibreOffice adds a separate application to your Mac. It is optional
and is not bundled into Lemulip. Common image, PDF, archive, subtitle, and
basic text tools work without it.

Complex formatting can change between formats. PDF-to-editable-Office conversion
is planned, not currently implemented. See [Formats](FORMATS.md#documents-slides-and-spreadsheets)
for the exact routes.

## Why Is Pandoc Reporting a Missing Template?

Lemulip runs Pandoc with `--sandbox`. The installed binary needs embedded data files for some formats, including EPUB, DOCX, and ODT. Install the [official Pandoc package](https://pandoc.org/installing.html), then refresh engine detection.

Pandoc documents the requirement in its [sandbox option](https://pandoc.org/MANUAL.html#option--sandbox).

## Why Does the Wheel Not Appear?

Keep Lemulip running and make sure **Drag Wheel Enabled** is checked in the menu bar. Start dragging before tapping Shift, Command, or Control. The wheel recognizes local file drags, not copied text or web links.

If the source application does not work with the wheel, add the files to the workspace and choose an operation there. You can also use **Open Wheel** for the clickable version.

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

The browser walkthrough uses sample data to explain the interaction. It does not run the macOS conversion engine. Open `site/index.html` from a downloaded checkout to try it locally.

## How Can I Report a Problem?

Follow [Contributing](../CONTRIBUTING.md). Include the input format, selected operation, app and macOS versions, and the error text. A small synthetic example is more useful than a private document.

Remove personal paths, account details, and file contents from any public log. Security reports should follow [Security](../SECURITY.md).
