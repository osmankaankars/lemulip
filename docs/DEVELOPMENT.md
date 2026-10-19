# Development

Lemulip is a Swift package with a native macOS app and a CLI. It requires
macOS 13 or later and Swift 5.9 or later. A recent full Xcode installation is the
most straightforward build environment; see [Installation](INSTALL.md).

## Build and Check

```bash
swift build
swift test --jobs 2 --skip EngineIntegrationTests
python3 script/privacy_check.py
./script/build_and_run.sh --verify
```

The first test command covers the core and, on macOS, native converters. Install
the optional engines described in the installation guide, then run
`swift test --jobs 2` to include their integration tests. Those tests generate
small temporary inputs. No private documents or binary fixture collections are
part of the repository.

## Where Things Live

| Path | Responsibility |
| --- | --- |
| `Sources/Freewheel` | AppKit lifecycle, drag wheel, SwiftUI workspace and settings |
| `Sources/FreewheelCore` | Operation catalog, converters, processes, and safe output publication |
| `Sources/CFreewheelArchive` | Bounded libarchive creation and extraction |
| `Sources/FreewheelCLI` | Command-line interface to the same engine |
| `Tests/FreewheelCoreTests` | Focused core, native, integration, and geometry checks |
| `site` | Static browser walkthrough, separate from the native app |
| `script` | Build, packaging, and public-source checks |

There are no third-party Swift package dependencies. macOS supplies the native
frameworks and the runtime libarchive library. The declaration headers under
`LibarchiveHeaders` are unchanged upstream files with the pins and notices in
[THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).

## Product and Internal Names

The installed app is `Lemulip.app`, with an executable named `Lemulip`. SwiftPM
builds it as the **`LemulipApp`** product. The CLI product is **`lemulip`**. Keep
these product names distinct even on a case-insensitive filesystem.

The existing `FreewheelCore`, `CFreewheelArchive`, GUI and CLI target names, and
source folders remain internal implementation identifiers. The bundle identifier
`app.freewheel.Freewheel`, preference keys, and saved-window key are retained so
existing installations use the same settings. These compatibility identifiers
are not public product names and should not be changed as a cosmetic cleanup.
Apple documents this relationship in
[The Application Domain](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/UserDefaults/AboutPreferenceDomains/AboutPreferenceDomains.html).

## Appearance State

The native theme definitions live in `Sources/Freewheel/Theme.swift`. **Orchard
Night** is the default, with **Vivid Pistachio** and **Lemon Drop** available in
**Settings → Appearance → Theme**. The existing preferences domain stores the
selection under `theme`, with only `orchard`, `pistachio`, or `lemonade` accepted.
Missing or unknown values fall back to Orchard Night. Existing preference keys
and saved-window state stay compatible.

`AppController.theme` publishes selection changes. `Palette` returns current
color values instead of caching them by system appearance, since both light
themes use Aqua. Use `Palette.primaryAction` and `Palette.onPrimary` for primary
buttons, and `Palette.ink`, `muted`, `accent`, `background`, and `panel` for their
respective roles. Exact tokens are listed in [Design](DESIGN.md#color-system).

Native views must redraw when the theme changes, including when switching
between the two light themes. Pass the theme into an `NSViewRepresentable` as an
explicit value and invalidate its drawing in `updateNSView`. Preserve view
identity, selected files, pending editor state, and running jobs during a theme
change. AppKit derives the accessibility appearance from Aqua or Dark Aqua;
the navigation material uses an opaque fallback for Reduce Transparency and
Increase Contrast.

The website stores the same three finite values under the local browser key
`lemulip.appearance`. Its selection is independent of the native app. Invalid
values use Orchard Night, and unavailable browser storage leaves theme selection
working for the current page. Sample files and activity history are not saved.

## Icon and Wordmark Sources

`Resources/AppIcon.png` is the reviewed white-tile icon master. The existing
AppKit build script generates the standard icon sizes and `AppIcon.icns`; only
that compiled ICNS is installed in the app. `AppMark` renders its original
colors. Keep target highlights behind it instead of tinting the artwork.

Native views share `AppWordmark` and the system's rounded font. The website
shares `site/assets/lemulip-wordmark.svg` across its header, walkthrough, and
footer, with a forced-colors text fallback. No custom font or runtime image
library is required. [Design](DESIGN.md) records usage, clear space, and colors.

`Resources/Lemulip.icon` is a separate, source-only Icon Composer composition.
It contains a transparent ribbon foreground and an opaque warm white background.
To validate it with a selected full Xcode 26 or later on a Mac, run:

```bash
./script/compile_layered_icon.sh --verify
```

The command respects `DEVELOPER_DIR`, compiles into a private temporary directory,
requires `Assets.car` and a matching icon name in the generated plist, and
removes its output afterward. It fails if the required compiler or artwork is
unavailable. It does not change the app's Info.plist, installed icon, selected
developer tools, or signing configuration. JSON validation on Linux does not
establish Apple compiler compatibility.

The source-only variant is not part of the default app build or release gate.
Before activation, pass the compiler check and inspect the result at Finder and
Dock sizes on a Mac. Retain the existing macOS 13 ICNS route and verify the
older-system fallback. Current release packages continue to use the static
white-tile master.

Refresh `docs/assets/demo-preview.png` only from the actual browser walkthrough
with its public sample files. It must remain labeled as a simulation. Native
editor screenshots must come from the running Mac app and use non-sensitive
sample files. Review all image metadata and update only the specific image
digest in `script/privacy_check.py`; never widen the artwork allowlist to bypass
that review.

## Verification in CI

The current commit's [Build and Verify run](https://github.com/osmankaankars/lemulip/actions/workflows/build.yml)
is the source of truth for build and package status. A configured check is not
evidence that it has passed.

| Check | Environment and Scope |
| --- | --- |
| Core and native conversion tests | Apple silicon and Intel macOS runners |
| Optional-engine integrations | Apple silicon with FFmpeg, ImageMagick, LibreOffice, and official Pandoc |
| Universal package | App and CLI binaries for both architectures, built after tests pass |
| Downloaded package verification | The exact ZIP and DMG, checked on both architectures before release |
| Public-source review | Allowlisted source files, metadata checks, and approved artwork hashes |
| Static analysis | Swift and the C archive bridge through CodeQL |

The workflows pin their developer tools and actions. See those files for exact
versions. Linux checks can verify portable code, but exclude macOS frameworks
and do not establish that the desktop app compiles or behaves correctly.

Tests are a separate SwiftPM target. They generate small temporary inputs and
are not copied into the installed app. Keep checks that catch conversion,
original-file preservation, archive, or interface-geometry defects; avoid
redundant test files and committed binary fixtures.

## Mac Checks That Matter

CI runs the core and native-converter tests and package checks on Apple silicon
and Intel. Optional-engine integration tests run on Apple silicon. Universal
artifacts are built once, downloaded again, verified, and then reused for a
tagged prerelease. Consult the workflow
for the exact checks and inspect its result before relying on a package.

Human verification still matters for Finder drag sessions, multiple displays,
wheel paging, dropping into the safe center, menu-bar behavior, keyboard access,
quitting during a job, and installing a quarantined download on a clean Mac.
A process that launches successfully is not proof of those interactions.

For audio trimming, verify the selected range against audible playback and
exported PCM samples. Include mono and opposite-phase stereo, silence, very
short clips, a nonzero selection, and a full recording whose duration is not an
exact millisecond. Cancel during waveform preparation, change the range during
playback, close while seeking, and reopen with a different file. None of those
steps should resume an old player or apply a stale selection.

`AudioTrim.swift` holds portable selection and waveform reduction logic.
`AudioWaveform.swift` streams native sample buffers into the bounded summary.
The UI keeps playback separate from export, shares the selection between
handles and numeric fields, and passes the selected output format through the
existing queued operation. The waveform path is cached until its view size
changes. Playback observations must be removed when playback stops; see Apple's
[playback progress guidance](https://developer.apple.com/documentation/avfoundation/monitoring-playback-progress-in-your-app).

For native video trimming, check a landscape clip, a portrait clip with a display
transform, silent video, a nonzero range, and a full clip whose duration falls
between displayed milliseconds. Compare the previewed range with decoded output
frames and audio, allowing only the documented frame or codec boundary behavior.
Check both MP4 and MOV when supported. The original must remain unchanged and a
cancelled export must leave no published file.

Open and close the editor while thumbnails load, change the range during
playback, close while seeking, and reopen with a different file. Old thumbnail
requests or seek completions must not update the new editor. Verify pointer,
keyboard, and accessible range controls agree in all three themes. The
application's thumbnail count and dimensions are bounded; this does not establish
a measurement of AVFoundation's process memory or prove hands-on playback
acceptance. Keep those results separate from automated export tests.

### Video Trim Constraints

The 0.1.5 editor is developed within these limits. Extend the existing focused
test files with small generated inputs; do not add a fixture collection or a
parallel test suite for the feature.

| Constraint | Implementation Boundary |
| --- | --- |
| No new runtime dependency | Native macOS preview, playback, and MP4/MOV export |
| Bounded thumbnail storage | Default 12, maximum 24; longest edge at most 192 pixels |
| Editor-scoped playback | Create the player only while the editor is open; cancel pending seeks and preview work and remove playback observations on close |
| Explicit input scope | One complete local video file containing its own media, with one video track and at most one audio track |
| Verified publication | A failed required Mac build, package check, or CodeQL check prevents the release |

The [roadmap's size baseline](ROADMAP.md#keep-it-lightweight) records measured
0.1.4 archives separately from future app-size, memory, CPU, and launch-time
targets. Record each version's measurements only after its exact packages exist;
bounded thumbnail storage alone does not establish a process-memory result.

### Video Crop Constraints

The 0.1.6 editor extends the existing crop and native video components. Keep
the implementation within these limits and add focused coverage to the existing
test files using small generated clips.

| Constraint | Implementation Boundary |
| --- | --- |
| No new runtime dependency | Existing crop interaction, AVFoundation playback, and native MP4/MOV export |
| One still preview | One upright frame, at most 1,280 pixels on the longest edge; no persistent frame cache |
| Spatial crop only | One rectangle for the full source timeline, retaining its audio; reject combined trim/crop options |
| Explicit frame geometry | Upright source coordinates, square pixels, full clean aperture, and standard quarter-turn rotations |
| Bounded output | Even dimensions from 2 pixels per side, at most 40 megapixels and 16,384 pixels per side |
| Editor-scoped resources | Pause on crop edits; cancel pending work and release player observations, frame storage, and seeks on close |
| Safe publication | Verify rendered output dimensions, then use the existing staging and unused-name output flow |

Check off-center crops, crops touching each source edge, portrait transforms,
odd requested dimensions, and aspect-ratio changes. Compare the visible crop
with decoded output pixels using generated regions that are easy to distinguish.
Check that the full source timeline and audio are retained, the original bytes
do not change, and failed or cancelled work leaves no published output.

Hands-on checks should cover dragging every handle, numeric dimensions, keyboard
movement, seeking, and playback in all three themes. Close while a still frame
or a seek is pending, then open another video; the previous request must not
update the new editor. A passing export test does not establish these UI results.
The same Mac build, package, and security gates apply before publication.

### PDF Organization Constraints

The 0.1.7 organizer uses PDFKit and the existing queued output flow. Extend the
existing core and native test files with small PDFs generated during each test;
do not add a fixture collection or another PDF engine.

| Constraint | Implementation Boundary |
| --- | --- |
| Stable page identity | Edits refer to original page indices; output order follows the plan, and rotations add to each page's source rotation |
| Source consistency | One PDF, up to 1,000 pages and 512 MiB; a streamed private snapshot and content fingerprint bind edits to their preview source |
| Page content | Copy PDF pages, preserving text and vector content; never build export from preview images |
| Document permissions | Reject locked files; require assembly and copying permission, and disclose unprotected output for an already-readable encrypted source |
| Bounded preview storage | At most 24 cached thumbnails, each at most 320 pixels on its longest edge; retain only visible and nearby previews in the UI |
| Bounded editing history | At most 40 undo snapshots and 40 redo snapshots |
| Non-destructive output | Keep at least one page, reject invalid plans, and use staging with unused output names |

Serialize PDFKit access inside the preview session. Release its document,
thumbnails, and private source snapshot on close. Export takes its own bounded
snapshot and compares the source fingerprint before copying pages; temporary
snapshots must be removed on success, failure, and cancellation.

Check reordered nonadjacent pages, subset extraction, all four quarter-turn
rotations, already-rotated pages, mixed page sizes, crop boxes, visible
annotations, and selectable text in the saved PDF. Verify that a replaced
source is rejected and that the original bytes remain unchanged. Failed or
cancelled work must leave no published output.

Hands-on checks should cover single and range selection, dragging and button
reordering, Undo/Redo/Reset, keyboard and VoiceOver access, and all three themes.
Scroll through a long document, close during loading, and reopen a different
PDF; stale previews must not appear in the new editor. Thumbnail limits bound
application-owned images, not PDFKit's total memory. Keep UI acceptance and
memory measurements separate from passing native export tests.

### PDF Merge Preview Constraints

The 0.1.8 merge preview reuses PDFKit, the organizer's bounded source snapshots
and thumbnail rendering, and the existing output queue. Extend the two existing
core and native converter test files with generated documents; add no PDF
engine, binary fixtures, or test file collection.

| Constraint | Implementation Boundary |
| --- | --- |
| Stable document identity | Refer to each file's original input index through reorder, removal, undo, and export; copy its pages in source order |
| Bounded input | 2–100 original PDFs, up to 1,000 pages each, totaling at most 512 MiB |
| Bounded output | Keep at least two documents; the retained arrangement must total at most 1,000 pages |
| Source consistency | Bind each retained document to its preview fingerprint, page count, byte count, and encryption state; reject changed sources before copying pages |
| Document permissions | Reject locked or restricted documents; require assembly and copying permission and disclose unprotected output when a retained source is already-readable and encrypted |
| Bounded previews | One serialized PDFKit session with at most 24 first-page thumbnails, each at most 320 pixels on its longest edge |
| Bounded history | At most 40 undo snapshots and 40 redo snapshots; retain only document identities and selection state |
| Non-destructive output | Copy actual PDF pages into staging, preserve originals, and publish under an unused name only after successful completion |

Inspect sources sequentially and report progress. Release the document and its
temporary snapshot after a source summary or first-page render; retain only
small metadata and the bounded thumbnail cache between requests. Cancel stale
loads when the editor closes and prevent their results from reaching a new
editor session. Export keeps the retained documents and their snapshots alive
through PDFKit's write, then removes temporary copies on success, failure, and
cancellation. PDFKit may allocate beyond the application-owned thumbnail cache;
the cache limit is not a claim about total memory.

Keep a selected merge plan exclusive to `pdf.merge` with PDF output. Never
fall through to a generic converter that ignores the chosen order or omissions.
The direct CLI merge retains its existing argument-order contract.

Check reversed and nonadjacent document orders, removal followed by undo,
mixed page sizes and source rotations, visible annotations, and selectable text
in the output. Verify original bytes are unchanged, retained source changes
are rejected, and failed or cancelled export publishes nothing. Exercise page,
file, byte, and permission limits without checking private documents into git.

Hands-on checks should cover group dragging, keyboard and button reordering,
range selection, output page ranges, Undo/Redo/Reset, VoiceOver, and all three
themes. Close during source inspection and during a thumbnail request, then
open another selection; no stale row or image should reappear. Native export
tests and source inspection do not establish these UI acceptance results.

## Basic Office Export Constraints

Source 0.1.10 adds two bounded routes before optional engine selection:
**TXT → DOCX on macOS** and **CSV/TSV → XLSX on all supported core platforms**.
Source 0.1.12 adds **basic RTF → DOCX on macOS**. Keep their scope explicit in
the catalog, job notes, and format guide. Preserve existing LibreOffice routes
for complex RTF, HTML, Office documents, workbooks, and presentations, and
Pandoc for Markdown → DOCX. Unsupported RTF structure may select LibreOffice
for the whole batch before native output. Malformed basic RTF, cancellation,
and writer failures must not be hidden by trying another engine. The optional
engine validates complex RTF assigned to its route.

| Constraint | Implementation Boundary |
| --- | --- |
| No new runtime dependency | AppKit's DOCX writer; a small XLSX package writer using the existing archive bridge |
| Plain Word input | TXT, 1 byte–32 MiB; UTF-8 with an optional BOM or BOM-marked UTF-16; reject empty decoded text and unsupported controls |
| Plain Word content | Basic paragraphs, tabs, and Unicode; normalize CRLF/CR to logical line breaks; no HTML or Markdown interpretation |
| Formatted Word input | Basic RTF with text, 1 byte–32 MiB; inspect RTF structure before AppKit import; reject malformed basic RTF and route unsupported structure to the existing optional engine |
| Formatted Word content | Supported font families, sizes, bold and italic traits, plus paragraph alignment, spacing, and indents; no images, objects, tables, lists, fields, hyperlinks, headers, or footers in the native route |
| RTF parsing limits | At most 128 nested groups; reject deeper input. More than 250,000 formatting commands selects the optional-engine route |
| Whole-batch route | Complete native eligibility checks before publishing output; do not mix partial native output with an optional-engine retry |
| Spreadsheet input | CSV or TSV, at most 32 MiB of actual input bytes; UTF-8 or BOM-marked UTF-16; strict quoted-field parsing |
| Spreadsheet content | One Sheet1 per input; every field stored as text, including empty fields; no inferred headers, dates, numeric types, formulas, charts, or external references |
| Bounded worksheet | At most 100,000 rows, 16,384 columns, and 500,000 fields; at most 32,767 UTF-16 code units and 253 line feeds per cell |
| Public metadata | Set DOCX author/editor explicitly to Lemulip and keep company/manager empty; include no user identity, device name, or source path in generated package metadata |
| Safe publication | Preserve source bytes, build in staging, choose an unused output name, and remove unpublished output on failure or cancellation |

The native TXT and basic RTF routes use
[`NSAttributedString.DocumentType.officeOpenXML`](https://developer.apple.com/documentation/foundation/nsattributedstring/documenttype/officeopenxml)
and AppKit's document-data export. Apple's
[formatted-document guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/AttributedStrings/Articles/HTMLFilesandAttributedStrings.html)
describes the writer and its document attributes. API support alone is not a
formatting guarantee. Basic RTF needs its own native import/export checks for
font traits and paragraph properties, with separate acceptance of the output
in Word. Page layout and margins are not reconstructed, and unavailable fonts
may be substituted. Do not copy imported document attributes into DOCX metadata.

RTF uses an explicit control and destination allowlist before AppKit import.
Unknown instructions select the existing optional engine instead of being
silently ignored by the native importer. Escaped command-looking text remains
literal text. Inspect one bounded document at a time during batch preflight,
then revalidate during export so a changed input cannot trigger an engine retry
after native files have been staged.

The XLSX writer stores explicit text cells and preserves whitespace. Retain
quoted delimiters and doubled quotes, blank rows, and multiline cells. A final
row separator adds no extra row; empty input creates a blank Sheet1. Escape
literal `_xHHHH_` sequences and carriage returns according to Microsoft's
[Office escaped-string rules](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-oi29500/d34ae755-c53f-4a44-a363-c6dd3ee018a4).
Reject unsupported XML controls instead of replacing them. The worksheet's
column, cell-length, and line-feed constraints stay within Microsoft's
[Excel limits](https://support.microsoft.com/en-us/excel/excel-specifications-and-limits?content_language=English);
the lower row and total-field limits are Lemulip's resource policy. Check bounds
while parsing and writing, before an oversized table accumulates in memory.

Extend the existing tests using small generated documents. For DOCX, inspect
package structure, extracted text, logical line breaks, tabs, Unicode, public
metadata, invalid input, cancellation, and original preservation on macOS. For
RTF, check supported formatting after reopening the output, unsupported
structures before output, mixed TXT/RTF batches, malformed input, and limits.
Use small inline RTF examples; keep personal documents and binary fixtures out
of the repository. For
XLSX, verify relationships and content types, one named sheet, explicit text
cells, leading zeros, long identifiers, formula-looking strings, whitespace,
OOXML escapes, malformed quoting, and boundary failures. Keep the optional
LibreOffice integration check exercising that engine directly; a built-in
route should not accidentally replace external-engine coverage.

The existing optional-engine integration tests read generated DOCX and XLSX
exports through LibreOffice, alongside explicit LibreOffice conversion cases.
In the source 0.1.11
[Mac build](https://github.com/osmankaankars/lemulip/actions/runs/39170976554),
both architectures passed all **123** built-in tests, including **53** native
tests each. The repaired workbook-package test passed on both. Apple silicon
also passed native TXT → DOCX → LibreOffice and built-in CSV → XLSX →
LibreOffice checks. Its two failures were in the separate rich Office verifier
described below.

Keep the workbook verifier's exact five-part assertion and symbolic-link
case. Enumerate relative filenames from the resolved directory; never slice
an absolute child path using a potentially different spelling of its parent.

Opening generated files with an independent reader helps catch packaging and
text interpretation errors. Release acceptance also needs real Word and Excel
checks: inspect paragraphs, tabs, Unicode, cell values, and text typing without
repair prompts. Distinguish portable tests, Mac CI, external-reader checks, and
hands-on target-application acceptance in reports. A passing parser or native
writer round trip does not establish all four.

## Rich Office Conversion Checks

Source 0.1.11 extends the existing
[integration tests](../Tests/FreewheelCoreTests/EngineIntegrationTests.swift)
with three small OOXML packages created during the test run. Each uses the
normal conversion engine to export an OpenDocument copy and then return to the
original Office format. Inspect the returned package and preserve the source
bytes; do not commit binary fixtures or bundle another engine.

| Round Trip | Required Assertions |
| --- | --- |
| DOCX → ODT → DOCX | Two-by-two table and text, Unicode paragraph, inline bold and italic, stored Arial name and 14-point size, explicit page break with second-page content |
| XLSX → ODS → XLSX | Budget and Summary sheets in order; text identifiers including leading zeros and 20 digits; numeric and boolean types; a two-decimal format; SUM and cross-sheet expressions with expected cached values |
| PPTX → ODP → PPTX | Two ordered slides, titles and panel text, stored Arial name and 24-point size, widescreen dimensions, and two shape bounds per slide within 0.01 inch |

The review preparation extends the Word example with an explicit page break
and second-page content. Its actual pagination still needs inspection in Word.

These three tests passed with **LibreOfficeDev 26.8.0.0.alpha0 on Linux**. The
source 0.1.11 [Apple silicon job](https://github.com/osmankaankars/lemulip/actions/runs/39170976554/job/117803763548)
used LibreOffice 26.8.0 and ran ten integration tests: eight passed, including
the rich Word example. Workbook and presentation verification stopped at the
same namespaced relationship-identifier lookup. That run did not reach
packaging or release publication.

Source 0.1.12 changes the verifier to read relationship attributes by local
name and namespace URI, while retaining the source XML document through the
lookup. It adds an inherited and alternate-prefix case, including a conflicting
namespace, and retains the sheet, formula, slide, and geometry assertions.
For source 0.1.12, **69 portable tests** and **five focused Office checks**
passed on Linux. The Office checks include four real LibreOffice conversion
cases and the namespace/order regression. An isolated check of the production
RTF preflight code passed 22 valid, complex, malformed, and bounded-input cases.
These local checks do not execute AppKit.

The source 0.1.12
[Mac build](https://github.com/osmankaankars/lemulip/actions/runs/39175991662)
compiled both architectures; each passed 126 of 127 built-in tests. The one
failure rejected the AppKit-generated basic RTF formatting example. Its
generic error did not identify the rejected control or imported attribute.
External integrations, including the relationship repair, were not reached.

Source 0.1.13 accepts the standard starred company destination only inside an
opening metadata subgroup. The
[RTF 1.9.1 specification](https://officeprotocoldoc.z19.web.core.windows.net/files/Archive_References/%5BMSFT-RTF%5D.pdf)
uses this spelling in its information-group example. The earlier scanner
rejected it even though company metadata was already recognized without the
star. Keep the generated formatting test and public-output-metadata assertions;
unknown starred metadata and rich content must still use the optional engine.
An isolated comparison exercised 28 inputs against the exact scanner before
and after the repair. Only the standard starred company case changed from
unsupported to accepted; numeric, misplaced, unknown, and rich-content cases
retained their rejection. These checks do not execute AppKit.

The initial source 0.1.13
[Mac run](https://github.com/osmankaankars/lemulip/actions/runs/39219132871)
compiled both architectures and passed 126 of 127 built-in tests on each.
The RTF example converted successfully. Its remaining failure compared
`NSTextAlignment.natural` with `.left`; the other text, font, centered-heading,
indentation, spacing, and color checks passed. The repair checks equivalent
left alignment only for that exact Latin body and rejects RTL paragraph or
character direction. Apple documents
[natural paragraph alignment](https://developer.apple.com/documentation/appkit/nsparagraphstyle/alignment)
and the supported [writing-direction attributes](https://developer.apple.com/documentation/foundation/nsattributedstring/key/writingdirection).
That initial run did not reach external integrations or packaging.

The alignment repair's [Mac run](https://github.com/osmankaankars/lemulip/actions/runs/39223770087)
passed all **127 built-in tests on both architectures**. Apple silicon passed
12 of 13 external integration cases, including native TXT and RTF Word exports,
complex RTF fallback, rich Excel and PowerPoint round trips, and the repaired
relationship lookup. The rich Word case failed two assertions: an explicit
page boundary before its second-page heading and one preceding table. The
log did not include the selected paragraph or converted document, so it does
not establish a Mac-specific XPath defect or a loss of pagination.

Repeating the exact generated Word fixture with LibreOfficeDev
26.8.0.0.alpha0 on Linux retained a leading inline page break and the table's
position. The source and returned DOCX both rendered as two A4 pages with
identical text by page: table on page one, new heading and following paragraph
on page two. This is local LibreOffice evidence, not Mac Foundation execution
or Microsoft Word acceptance.

The 0.1.13 page-boundary repair enumerates Word body elements directly, matches the joined
heading text exactly, and requires unique heading and table positions in the
correct order. It retains the XML document and resolves element and attribute
namespaces explicitly. Only the existing two boundary forms are accepted:
an enabled [paragraph page break](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.pagebreakbefore)
or a leading [inline page break](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.break).
Visible text, a tab, a drawing, or a hyperlink before a later break cannot
qualify. Disabled properties, line or column breaks, duplicate headings, and
a heading inside the table are covered in the existing integration test file.
If the real conversion still fails, the assertion includes its generated Word
body for diagnosis. All table, font, Unicode, and source-preservation checks
remain required. Its [source build](https://github.com/osmankaankars/lemulip/actions/runs/39230109601)
passed all **127 built-in tests on both Mac architectures** and **14 external
integration cases on Apple silicon**. [CodeQL](https://github.com/osmankaankars/lemulip/actions/runs/39230109655)
and the [tagged package build](https://github.com/osmankaankars/lemulip/actions/runs/39232673004)
also passed; [v0.1.13](https://github.com/osmankaankars/lemulip/releases/tag/v0.1.13)
has the four expected release assets. These results belong to 0.1.13, not to a
later source commit.

Do not infer font availability, Word pagination, Excel recalculation, or
PowerPoint rendering from stored attributes alone. The formula cases check
two expressions and their cached results; they are not a general calculation
suite. Macros, charts, pivot tables, embedded objects, and animations are not
covered. Keep native RTF formatting checks separate from these richer
LibreOffice round trips and from hands-on target-application acceptance.

### HTML and Markdown Word Checks

Source 0.1.14 assesses HTML and Markdown separately in the existing integration
test file. Both fixtures check a real first-level heading, inline bold and
italic, Unicode text, a two-by-two table, body order, and unchanged source
bytes. The Markdown fixture also checks bullet and numbered list definitions,
numbering from one, and exact code-block spaces and line breaks. These small
inline examples contain no images, hyperlinks, or personal content.

The public-engine HTML test first failed with LibreOffice's automatic filter:
Writer/Web could not select a DOCX export filter. The repair supplies
`--infilter=HTML (StarWriter)` and `docx:Office Open XML Text` only for HTML or
HTM input with a DOCX target. Selecting only the export filter produced a file
in the local probe but did not retain the required heading outline level.
Both lowercase HTML and uppercase HTM now pass through the normal engine.
The [LibreOffice filter guide](https://help.libreoffice.org/latest/en-US/text/shared/guide/convertfilters.html)
documents the input and output filter arguments. Other routes retain their
existing selection, including Pandoc for Markdown.

The fixture verifier reads actual WordprocessingML namespaces, paragraph and
character styles, and numbering definitions. Keep direct formatting overrides,
inherited styles, XML object lifetimes, document order, and code whitespace
checks intact. Thirteen corruptions exercise missing or disabled formatting,
wrong namespaces, invalid numbering, moved content, and lost whitespace. This
is a verifier for these examples, not a general Word renderer.

The complete available Linux suite passed **84 tests with zero failures** using
Swift 6.1.2, official Pandoc 3.12.1, and LibreOfficeDev 26.8.0.0.alpha0. This
includes the real HTML and Markdown conversions and the negative verifier
cases. The generated source and DOCX files for both new comparisons also passed
the review packager's content and metadata checks. The 0.1.14 Mac builds, full
eight-case review artifact, and Microsoft Office acceptance still need their
own results. Keep Office acceptance **Not Reviewed** until observed in the
target applications.

### Prepare the Office Review

The existing integration cases can retain eight small generated input/output
comparisons for the [Office Review](OFFICE_REVIEW.md). Capture is opt-in through
`LEMULIP_OFFICE_REVIEW_DIR`; ordinary test runs keep their temporary-file cleanup.
The review files are not bundled with the app or committed as binary fixtures.
The 0.1.13 artifact has six cases; 0.1.14 adds `word-html` and `word-markdown`.

On a Mac, start in the repository with a working Xcode selection and the
optional integration engines installed. Use a clean checkout of the commit
you intend to review. This block stops if any check fails:

```bash
(
  set -e
  LEMULIP_REVIEW_WORK="$(mktemp -d "${TMPDIR:-/tmp}/lemulip-office-review.XXXXXX")"
  mkdir -m 700 "$LEMULIP_REVIEW_WORK/captured"
  git rev-parse HEAD > "$LEMULIP_REVIEW_WORK/captured/source-commit.txt"
  env LEMULIP_OFFICE_REVIEW_DIR="$LEMULIP_REVIEW_WORK/captured" /usr/bin/xcrun --sdk macosx swift test --jobs 2 --filter EngineIntegrationTests
  python3 script/prepare_office_review.py "$LEMULIP_REVIEW_WORK/captured" --output "$LEMULIP_REVIEW_WORK/Lemulip-Office-Review.zip"
  printf 'Office Review: %s\n' "$LEMULIP_REVIEW_WORK/Lemulip-Office-Review.zip"
)
```

The packager checks the capture's commit against the clean source checkout,
requires the expected cases, and writes a new ZIP; it does not
overwrite an existing archive. It includes the source version and commit,
checksums, this review's guide, and an unfilled results template. Capture and
packaging do not run Microsoft Office, update the installed app, or send local
files anywhere. The full archive requires macOS for its two native Word cases.

The Apple silicon CI job uploads **Lemulip-Office-Review-arm64** separately from
the four release assets. Inspect its run and manifest before reviewing the
files. A prepared artifact or successful XML check is not a manual pass; record
the target app versions and results using the guide. Keep the Office milestone
open until those observations are available.

## Prepare a Release

```bash
./script/package_release.sh
./script/package_release.sh --verify dist
```

Packaging preserves existing release files. Use a fresh checkout for a new
candidate. Source-only packaging is available with
`python3 script/package_source.py`; `--output` can select a new ZIP filename.

Keep a tag's version equal to `CFBundleShortVersionString`. Use the repository's
tag workflow for public packages, and keep every signing credential outside the
repository. The current preview uses ad hoc signing and no notarization.

For repository setup and publishing, see [Publishing](PUBLISHING.md).
