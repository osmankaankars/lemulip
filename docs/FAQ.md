# Frequently asked questions

## Is Freewheel free?

Yes. The source is released under the [MIT license](../LICENSE). There is no subscription, account requirement, or paid conversion tier. Optional engines are separate open-source tools with their own licenses.

## Does it upload my files?

Conversions run locally. Freewheel has no file-upload service, analytics SDK, or automatic update service. It saves preferences, while Activity is held only for the current session.

AirDrop is a separate action that shares files when you choose it. Installing optional engines requires internet access.

## Which Macs can run it?

The app targets macOS 13 or later and supports building for Apple silicon and Intel. Source builds require Swift 5.9 or later from compatible Xcode or Command Line Tools.

An Apple silicon source build has completed on macOS. That does not establish compatibility with every supported OS or Intel Mac. The current release is an early preview, and Finder drag behavior still needs broader hands-on testing.

## Is there a ready-to-use download?

Release packaging is configured to produce a universal app, ZIP, and DMG. Use only assets attached to a release or a successful workflow run; a source checkout by itself is not a built app.

If a release has no binary assets, [build from source](INSTALL.md#build-from-source). Current packages are ad-hoc signed and are not Apple Developer ID signed or notarized.

## Why does macOS show a warning when opening a download?

The current distribution does not have Developer ID signing and notarization. macOS may block a downloaded app on first launch.

Review the source and release origin before opening it. Apple's [guide to safely opening apps](https://support.apple.com/en-us/102445) explains the available controls. Freewheel does not disable Gatekeeper or change the Mac's security settings.

## Why does an operation ask for FFmpeg or another engine?

Some formats need an optional local converter. Install FFmpeg for broader media support, ImageMagick for additional image codecs, LibreOffice for Office files, or Pandoc for EPUB and structured document routes.

See [Optional engines](INSTALL.md#optional-engines), then click **Refresh** under **Settings → Local Engines**. Freewheel does not install a helper automatically.

## Why is Pandoc reporting a missing template?

Freewheel runs Pandoc with `--sandbox`. The installed binary needs embedded data files for some formats, including EPUB, DOCX, and ODT. Install the [official Pandoc package](https://pandoc.org/installing.html), then refresh engine detection.

Pandoc documents the requirement in its [sandbox option](https://pandoc.org/MANUAL.html#option--sandbox).

## Why does the wheel not appear?

Keep Freewheel running and make sure **Drag wheel enabled** is checked in the menu bar. Start dragging before tapping Shift, Command, or Control. The wheel recognizes local file drags, not copied text or web links.

If the source application does not work with the wheel, add the files to the workspace and choose an operation there. You can also use **Open wheel** for the clickable version.

## Do I have to hold the modifier key?

No. Tap the key after the drag begins. The wheel stays open while you continue dragging. Drop onto an operation to select it. Dropping in the center or outside the wheel submits no conversion.

The current modifier keys cannot be reassigned.

## Where did the converted files go?

By default, every output from a job goes into the first input's folder, including when the inputs came from different folders. In **Activity**, click an output to reveal it in Finder.

Turn off **Save in the first file's folder** in Settings to choose a destination for each job.

## Can it overwrite or move an original?

Conversions create new files and choose unused names. **Move to…** is an explicit file action that relocates the selected originals.

If a copy or move operation fails halfway through, completed transfers remain in place. Activity lists the completed outputs.

## Why did a PDF lose its text, links, or forms?

PDF compression flattens pages to images. That removes searchable text, links, forms, signatures, and accessibility structure in the new copy. The app explains this before the job starts and preserves the original.

Use another PDF operation when you need to retain that structure. PDF → editable Office documents is not implemented.

## Why is my compressed file larger?

Compression depends on the source, codec, resolution, and selected quality. An already optimized file can become larger when re-encoded. Compare the result before deciding which copy to keep.

## Can it convert locked PDFs or encrypted archives?

The app and CLI do not offer PDF password entry. Open a protected PDF with its password and save an unlocked copy first. Encrypted archives are rejected.

## Is the browser demo the real app?

The browser walkthrough uses sample data to explain the interaction. It does not run the macOS conversion engine. Open `site/index.html` from a downloaded checkout to try it locally.

## How can I report a problem?

Follow [Contributing](../CONTRIBUTING.md). Include the input format, selected operation, app and macOS versions, and the error text. A small synthetic example is more useful than a private document.

Remove personal paths, account details, and file contents from any public log. Security reports should follow [Security](../SECURITY.md).
