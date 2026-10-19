# Release Notes

File tools, right where you drag.

Lemulip is a free, open-source file converter for macOS. Drag local files,
tap a modifier key, and choose a format or tool from the wheel. Use the workspace
when you need a queue, conversion options, or a closer look at the result.

## 0.1.14 · HTML Notes, Ready for Word

- Fix HTML and HTM → DOCX when LibreOffice opens the input as a web document
  and cannot choose a Word export filter. Import these files as Writer
  documents and explicitly select the Word document exporter.
- Check real HTML and Markdown conversions separately. Verify a heading,
  bold and italic text, Unicode, and a small table in document order. Markdown
  also checks bulleted and numbered lists and literal code spacing.
- Resolve Word formatting through its styles and numbering definitions so
  the checks do not depend on a particular engine's style names or text-run
  boundaries. Include deliberate damaged-output cases in the existing test file.
- Extend the separate Office review artifact from six to eight generated
  comparisons, with HTML and Markdown sources and a matching review guide.
- Keep the existing local engines, source-preservation behavior, and file
  sandbox. Add no app dependency, test file, or committed binary sample.

Version **0.1.14**, build **17**, continues
[Easier Office Conversion](ROADMAP.md#5-easier-office-conversion). HTML → DOCX
uses LibreOffice; Markdown → DOCX uses Pandoc. This version needs its own
Mac, security, and downloaded-package checks before its release is available.
Microsoft Office rendering acceptance remains **Not Reviewed**; see
[Office Review](OFFICE_REVIEW.md) for the eight examples.

The initial [0.1.14 Mac run](https://github.com/osmankaankars/lemulip/actions/runs/39241783897)
passed 127 built-in tests on each architecture and 16 of 17 Apple silicon
integration cases. HTML Word export passed; the Markdown verifier reported
missing single-space text runs. Its repair promotes significant whitespace
when reading Office XML and checks separate word-separator and code-indentation
runs through the same loader. Actual missing spaces still fail the checks.
[CodeQL](https://github.com/osmankaankars/lemulip/actions/runs/39241784028)
passed for the initial source. The repaired commit needs its own Mac,
security, and package results; no 0.1.14 download is claimed from the failed run.

## 0.1.13 · Ready for an Office Review

- Prepare six small sets of actual conversion outputs for inspection in
  Microsoft Word, Excel, and PowerPoint. Include their generated sources,
  intermediate Office files, and a concise review guide.
- Check a deliberate page break in the rich Word example, alongside its table
  and font formatting. Explain how to inspect pagination and how to edit an
  Excel value to check real formula recalculation.
- Record the source commit, platform, file sizes, and checksums. Review sample
  contents and metadata before packaging, and start every manual result as
  **Not Reviewed**.
- Upload the review ZIP as a separate GitHub Actions artifact after the Apple
  silicon integration checks pass. Keep binary examples outside the source
  repository and installed app; add no test file or runtime dependency.
- Accept the standard starred company metadata group in basic RTF input.
  Keep document metadata out of the exported Word copy and retain the existing
  rejection of unknown destinations and unsupported rich content.
- Correct the Mac RTF alignment check for the fixed left-to-right example.
  Accept AppKit's equivalent natural alignment while checking paragraph and
  character writing direction. Keep the font, spacing, indent, and color checks.
- Read the rich Word example's page boundary from its ordered body elements.
  Require one matching heading after its table and an explicit page break;
  cover disabled, misplaced, and wrong-type breaks in the existing test file.

Version **0.1.13**, build **16**, includes the native RTF export and Office
verification repair from 0.1.12, with a narrow RTF metadata compatibility fix.
Its supported document-content scope is unchanged. This step
makes [Office Review](OFFICE_REVIEW.md) ready to perform; it does not establish
that Microsoft Office has rendered or recalculated these files correctly.
The completed [source Mac run](https://github.com/osmankaankars/lemulip/actions/runs/39230109601)
passed all 127 built-in tests on both architectures and all 14 integration
cases on Apple silicon. [CodeQL](https://github.com/osmankaankars/lemulip/actions/runs/39230109655)
and the [tagged build and package checks](https://github.com/osmankaankars/lemulip/actions/runs/39232673004)
also passed. The four expected release assets are published under
[`v0.1.13`](https://github.com/osmankaankars/lemulip/releases/tag/v0.1.13).
See [Build and Verify](https://github.com/osmankaankars/lemulip/actions/workflows/build.yml)
for the review artifact and [Releases](https://github.com/osmankaankars/lemulip/releases)
for installable downloads.

## 0.1.12 · Keep the Formatting

- Convert basic **RTF → DOCX** with native macOS tools. Keep supported font
  families and sizes, bold and italic text, and paragraph alignment, spacing,
  and indents without installing another engine.
- Check native RTF eligibility before export. Images, objects, tables, lists,
  fields, hyperlinks, headers, footers, and unsupported RTF structures retain
  the existing LibreOffice route for the whole selection. Malformed basic RTF
  receives an error; the optional engine validates documents assigned to it.
- Keep a 32 MiB input limit per native Word source, preserve originals, and
  set DOCX author and editor metadata to Lemulip. Input document metadata is
  not copied.
- Repair the shared relationship lookup in the workbook and presentation
  verifiers. Read attributes by local name and namespace URI, retain the
  document through lookup, and keep the formatting and data assertions.
- Extend the existing test files with generated examples. Add no package
  dependency, bundled engine, or binary fixture collection.

Version **0.1.12**, build **15**, continues
[Easier Office Conversion](ROADMAP.md#5-easier-office-conversion). Its
[Mac build](https://github.com/osmankaankars/lemulip/actions/runs/39175991662)
compiled on both architectures; each passed 126 of 127 built-in tests. The
AppKit-generated RTF formatting example was rejected by native preflight.
The run stopped before external integrations and release packaging. Source
0.1.13 repairs a valid metadata form rejected by that preflight; its own Mac
checks must confirm the full example and Office integrations. See
[Build and Verify](https://github.com/osmankaankars/lemulip/actions/workflows/build.yml)
and [Releases](https://github.com/osmankaankars/lemulip/releases).

Read [Create a Word Document](USER_GUIDE.md#create-a-word-document) for the
workflow and [Basic Word Export](FORMATS.md#basic-word-export) for the native
RTF boundary. The next Office task is to inspect representative outputs in
Word, Excel, and PowerPoint for rendering, pagination, calculations, and slide
appearance. The full milestone remains open.

## 0.1.11 · Check the Details

- Repair the Mac workbook-package verifier. It now compares directory-relative
  filenames, with a symbolic-link case to guard against different spellings of
  the same temporary folder. The exact package-content checks remain required.
- Exercise richer Office conversions through the existing local engine:
  DOCX → ODT → DOCX, XLSX → ODS → XLSX, and PPTX → ODP → PPTX.
- Check document tables and stored font formatting, ordered worksheets and
  typed values, simple formulas with cached results, and slide text and geometry.
- Explain the limits of those examples. Stored formatting is separate from
  actual font rendering and pagination; complex formulas, charts, pivot tables,
  macros, and animations are not covered.
- Keep basic TXT → DOCX and CSV/TSV → XLSX exports, their input limits, and their
  engine requirements unchanged. Add no runtime dependency or binary fixtures.

Version **0.1.11**, build **14**, continues
[Easier Office Conversion](ROADMAP.md#5-easier-office-conversion). The three new
rich Office round trips passed with LibreOffice on Linux. Its
[Mac run](https://github.com/osmankaankars/lemulip/actions/runs/39170976554)
passed all 123 built-in tests on both architectures, including the repaired
workbook-package check. Apple silicon ran ten integrations: native TXT → DOCX
through LibreOffice and the rich Word example passed, while workbook and
presentation verification failed at their shared relationship lookup.
Packaging and release publication were not reached. Source 0.1.12 repairs that
verifier and retains its output assertions.

Read [Rich Office Conversion](FORMATS.md#rich-office-conversion) and
[Convert Existing Office Files](USER_GUIDE.md#convert-existing-office-files)
for supported routes and output checks. Basic native RTF → DOCX follows in
source 0.1.12.

## 0.1.10 · Simple Files, Ready for Office

- Convert TXT files into basic **Word documents (DOCX)** with native macOS
  tools. Keep plain text, paragraphs, tabs, and Unicode without installing
  LibreOffice or Microsoft Office.
- Convert CSV and TSV files into **Excel workbooks (XLSX)** with one worksheet
  named **Sheet1** per input. Quoted delimiters and multiline fields stay in
  their cells.
- Store spreadsheet values as text. Preserve leading zeros and identifiers;
  do not guess numbers or dates, or turn formula-looking text into executable
  spreadsheet formulas.
- Explain the basic export scope and optional engine requirements before a
  job starts. Rich document and existing-workbook routes retain their engines;
  Markdown → DOCX still uses Pandoc.
- Enforce explicit input, row, column, cell, and text limits. Create copies
  through the existing output pipeline and preserve the originals.
- Keep the native app small: no new package dependency, bundled Office engine,
  or committed binary fixture collection.

Version **0.1.10**, build **13**, begins the
[Easier Office Conversion](ROADMAP.md#5-easier-office-conversion) milestone.
Commit `a87bdae` compiled on both Mac architectures, and all 53 native tests on
each runner passed, including the new DOCX cases. One workbook-package
verification test failed because its relative-path calculation depended on
temporary-folder spelling. That
[build run](https://github.com/osmankaankars/lemulip/actions/runs/39167326568)
stopped before external integrations, packaging, and release publication.
Source 0.1.11 repairs the verifier while retaining its assertions.

Read [Basic Office Exports](USER_GUIDE.md#basic-office-exports) for the workflow
and [Office Formats](FORMATS.md#documents-slides-and-spreadsheets) for exact limits.
The richer Office route checks follow in 0.1.11; basic native RTF export follows
in 0.1.12.

## 0.1.9 · A Brighter First Impression

- Place the vivid green and cream ribbon on a warm white icon tile, giving the
  mark a clear edge against all three appearances.
- Use shared rounded branding in the workspace, Settings, and website. The app
  uses native system type; the website uses a small original path wordmark.
- Remove the idle green wash over the workspace drop area. An active drop
  highlight sits behind the icon and controls, keeping their colors intact.
- Improve the **Choose Files** keyboard hint and the website's Appearance
  control, small-screen layout, and high-contrast wordmark fallback.
- Refresh the product page and browser walkthrough image. Describe the native
  image, audio, video, and PDF editors without presenting a simulation as a Mac
  screenshot.
- Include a separate Icon Composer design source and an explicit compile check
  for development. The app continues to ship its static ICNS icon until that
  composition passes native compilation and appearance review.
- Keep Orchard Night as the default, preserve saved settings, and add no
  package, font, or runtime rendering dependency.

Version **0.1.9**, build **12**, uses the required Mac build, package, and
security checks. [Build and Verify](https://github.com/osmankaankars/lemulip/actions/workflows/build.yml)
records the exact commit's result; [Releases](https://github.com/osmankaankars/lemulip/releases)
lists available downloads. Native Finder, Dock, and accessibility appearance
acceptance remains separate from browser and source checks.

Read [Design](DESIGN.md) for icon, typography, color, and accessibility guidance.
The next development milestone is [Easier Office Conversion](ROADMAP.md#5-easier-office-conversion).

## 0.1.8 · Bring Your PDFs Together

- Review several PDFs before merging. Each row shows a first-page preview,
  the document's page count, and its page range in the output.
- Drag documents into order or use **Move Earlier / Move Later**. Page ranges
  and the total page count follow the displayed arrangement.
- Remove documents from the pending copy and revise the arrangement with
  **Undo**, **Redo**, and **Reset**.
- Use **Create Copy** to combine every page from the retained documents through
  native macOS tools. Text and vector content remain PDF content, and the source
  files stay in place.
- Validate that exported documents match the preview sources. Keep thumbnails
  and temporary source copies bounded, and release them when their work ends.
- Use the same three saved appearances and existing conversion queue without
  adding an engine or package dependency.

Version **0.1.8**, build **11**, uses the required Mac build, native export,
package, and security checks. See
[Build and Verify](https://github.com/osmankaankars/lemulip/actions/workflows/build.yml)
for each commit's result and [Releases](https://github.com/osmankaankars/lemulip/releases)
for available downloads. Hands-on editor acceptance remains separate from CI.

Read [Merge PDF](USER_GUIDE.md#merge-pdf) for controls and document limits.
The four planned video and PDF editors are implemented in source. The
[Warm Visual Identity](ROADMAP.md#4-warm-visual-identity) refresh follows in 0.1.9.

## 0.1.7 · Put Every Page in Place

- Open one PDF in a thumbnail organizer. Reorder pages by dragging or using
  **Move Earlier** and **Move Later**.
- Select several pages, rotate them together, or remove them from the copy.
  **Undo** and **Reset** let you revise the arrangement before exporting.
- Use **Extract Selected** to save the selected pages in their displayed order,
  or **Create Copy** to save the whole arrangement as a new PDF.
- Copy the original PDF pages through native macOS tools, retaining text and
  vector content. Thumbnail images are used only for the editor.
- Load small previews as pages come into view, keep a bounded thumbnail cache,
  and release the editor's temporary resources when it closes. No extra engine
  or package dependency is added.
- Match the three saved themes and keep the original file unchanged.

Version **0.1.7**, build **10**, uses the same required Mac build, native export,
package, and security checks as earlier previews. See
[Build and Verify](https://github.com/osmankaankars/lemulip/actions/workflows/build.yml)
for each commit's result and [Releases](https://github.com/osmankaankars/lemulip/releases)
for available downloads. Hands-on editor acceptance remains separate from CI.

Read [Organize PDF](USER_GUIDE.md#organize-pdf) for controls and document limits.
PDF merge preview starts with source 0.1.8.

## 0.1.6 · Frame It Your Way

- Crop one video with a movable selection over the native preview, familiar
  aspect ratios, and visible output dimensions.
- Apply the chosen crop to the whole clip. This operation changes the frame;
  use Trim separately when you want to shorten the video.
- Create a new **MP4** or **MOV** with native macOS tools, retaining the clip's
  audio and leaving the original file in place.
- Prepare one upright preview frame at a bounded size. Export uses the source
  video, with no added conversion engine or package dependency.
- Keep crop controls, keyboard movement, and the three saved appearances
  consistent with the image editor.

Version **0.1.6**, build **9**, adds visual video crop. Its download assets
are published only after the required Mac build, export, package, and security
checks pass. See [Build and Verify](https://github.com/osmankaankars/lemulip/actions/workflows/build.yml)
for each commit's result and [Releases](https://github.com/osmankaankars/lemulip/releases)
for available archives. Native interaction acceptance remains separate from CI.
Existing tags and downloads are preserved.

Read [Visual Video Crop](USER_GUIDE.md#visual-video-crop) for controls, supported
inputs, and output limits. PDF page organization starts with source 0.1.7.

## 0.1.5 · Watch What You Keep

- Open one video in a native preview with a small thumbnail strip, start and
  end handles, editable timestamps, and a visible selected duration.
- Seek through the clip and use **Play Selection** to watch the range before
  saving. Changing the range pauses playback; closing the editor releases the
  player and cancels unfinished preview work.
- Export a new **MP4** or **MOV** through native macOS tools, preserving the
  source orientation and leaving the original file in place. Export re-encodes
  the range; frame and audio-codec boundaries can affect its exact duration.
- Request only 12 small thumbnails for the editor, with a core limit of 24 at
  192 pixels on the longest edge. No extra conversion engine or package
  dependency is added.
- Keep range editing, keyboard controls, output handling, and the three saved
  appearances consistent with the existing editors.
- Link the website's main download action to the published Mac releases.

Version **0.1.5**, build **8**, adds native video trim. Download assets are
published only after its source and tagged commits pass the required Mac build,
export, package, and security checks. See [Build and Verify](https://github.com/osmankaankars/lemulip/actions/workflows/build.yml)
for the exact commit's result and [Releases](https://github.com/osmankaankars/lemulip/releases)
for available archives. Hands-on playback acceptance remains separate from CI.
Existing tags and releases are preserved.

Read [Visual Video Trim](USER_GUIDE.md#visual-video-trim) for the controls,
supported inputs, and encoding limits. Version 0.1.5 adds video trim;
visual video crop starts with source 0.1.6 and PDF page organization with 0.1.7.

## 0.1.4 · Hear What You Keep

- Open one audio file in a native waveform editor with start and end handles,
  editable timestamps, and the selected duration always visible.
- Use **Play Selection** and **Pause** to listen before creating a copy. Playback
  stops when the editor closes or the selection changes.
- Export the selected range as **M4A**, **WAV**, or **AIFF** with native macOS
  tools. Optional FFmpeg remains available for other conversion routes.
- Prepare the waveform in bounded chunks in the background. Canceling the
  editor cancels its preview request and stops playback.
- Use the same three saved themes and keyboard controls throughout the editor.
- Include the visual crop editor and three appearances from source 0.1.3 below.
- Fix the Swift compiler timeout in the selected-audio sample check without
  removing the check or changing its tolerance.
- Sample crop verification pixels in an explicit sRGB bitmap and check the
  untouched fixtures before conversion. Keep the existing orientation,
  transparency, source-integrity, and color-tolerance checks.
- Create the preview tag automatically after the same source commit passes
  the required Mac build, package, and CodeQL checks, then start its tagged build.
- Publish download assets from a verified draft so an interrupted upload can
  resume without replacing existing releases or files.

Version **0.1.4**, build **7**, is a published public preview at `17bb81a`.
[The tagged build](https://github.com/osmankaankars/lemulip/actions/runs/39141454481)
passed 77 core and native tests on each Mac architecture, five optional-engine
integration tests on Apple silicon, universal packaging, and both downloaded
package checks. [CodeQL](https://github.com/osmankaankars/lemulip/actions/runs/39139842808)
also passed. DMG, app ZIP, source ZIP, and checksum assets are available on
[the release page](https://github.com/osmankaankars/lemulip/releases/tag/v0.1.4).
Hands-on acceptance of native editor interactions remains separate from CI.

Read [Audio Waveform Trim](USER_GUIDE.md#audio-waveform-trim) for controls,
supported inputs, and output precision. In this release, video trimming uses
the numeric FFmpeg panel; the native video editor starts with source 0.1.5.

## Included From Source 0.1.3 · Three Themes and Visual Crop

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
These changes are included in the verified 0.1.4 release; source 0.1.3 did not
create a download release. Hands-on image and audio editor acceptance remains
open.

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
