# Development

Lemulip is a Swift package with a native macOS app and a CLI. Use macOS 13+
and Swift 5.9+ from compatible Xcode tools. See [Installation](INSTALL.md) for
setup and [Contributing](../CONTRIBUTING.md) for reporting and change scope.

## Build and Check

```bash
swift build
swift test --jobs 2 --skip EngineIntegrationTests
python3 script/privacy_check.py
./script/build_and_run.sh --verify
```

Install the [optional engines](INSTALL.md#optional-engines), then run
`swift test --jobs 2` to include integration checks. Tests create small temporary
inputs; do not commit generated documents, screenshots with private content,
or build products. Linux covers portable code only; AppKit, SwiftUI, and native
converters need macOS.

## Where Things Live

| Path | Responsibility |
| --- | --- |
| `Sources/Freewheel` | AppKit lifecycle, drag wheel, SwiftUI workspace and editors |
| `Sources/FreewheelCore` | Catalog, conversions, previews, process isolation, safe output |
| `Sources/CFreewheelArchive` | Bounded libarchive creation and extraction |
| `Sources/FreewheelCLI` | Command-line interface to the same engine |
| `Tests/FreewheelCoreTests` | Core, native, integration, output-safety, and geometry checks |
| `site` | Static browser walkthrough, separate from the Mac app |
| `script` | Build, packaging, publishing, and public-source checks |

There are no third-party Swift package dependencies. macOS provides the native
frameworks and libarchive runtime. The bundled declaration headers are required
for SDKs that omit them; preserve their [upstream notices](../THIRD_PARTY_NOTICES.md).

## Product and Internal Names

The installed app is `Lemulip.app`, with executable `Lemulip`. SwiftPM builds it
as **LemulipApp**; the CLI product is **lemulip**. Keep the build product names
distinct on case-insensitive filesystems.

`FreewheelCore`, `CFreewheelArchive`, source-folder names, the bundle identifier
`app.freewheel.Freewheel`, preference keys, and saved-window key are retained
for compatibility. They are internal identifiers, not public branding. Renaming
them as a cosmetic change can break imports or existing settings.

## Appearance State

`Sources/Freewheel/Theme.swift` defines all three themes. The native `theme`
preference accepts `orchard`, `pistachio`, and `lemonade`; missing or unknown
values select Orchard Night. The website independently stores the same values
under `lemulip.appearance`. Browser storage failure must leave the selector usable.

Use the shared `Palette` roles from [Design](DESIGN.md#color-system). Read current
colors instead of caching by system appearance: both light themes use Aqua.
Pass the theme into AppKit-backed views and invalidate drawing when it changes,
without replacing editor identity, selections, or jobs. Preserve opaque
fallbacks for Reduce Transparency and Increase Contrast.

## Icon and Wordmark Sources

`Resources/AppIcon.png` is the reviewed icon master. `script/make_icon.swift`
creates the ICNS during the app build. Native `AppMark` keeps its original colors;
`AppWordmark` uses the system rounded font. The website uses
`site/assets/lemulip-wordmark.svg` with a forced-colors text fallback.

The app ships the static white-tile icon. A future layered icon needs its own
Apple compiler and Finder/Dock review before activation. Keep the macOS 13
fallback. See [Design](DESIGN.md) for proportions and shared visual rules.

The README image is a browser simulation using public sample files. Actual app
screenshots must come from a running Mac app. Review artwork visually and check
its metadata before updating a specific digest in `script/privacy_check.py`.
Do not broaden the allowed file types or metadata to admit an unreviewed asset.

## Verification in CI

| Check | Scope |
| --- | --- |
| Core and native conversions | Apple silicon and Intel macOS runners |
| Optional-engine integration | Apple silicon with FFmpeg, ImageMagick, LibreOffice, and official Pandoc |
| Universal package | App and CLI for both architectures |
| Download verification | Exact ZIP and DMG checked on both architectures before release |
| Public source | Allowlisted files, metadata rules, and approved artwork hashes |
| Static analysis | Swift and the C archive bridge through CodeQL |

[Build and Verify](https://github.com/osmankaankars/lemulip/actions/workflows/build.yml)
and [CodeQL](https://github.com/osmankaankars/lemulip/actions/workflows/codeql.yml)
record each commit's results. Workflow files contain the current tool and action
pins. A source check, a tagged package build, and a Pages deployment have different
purposes; one does not substitute for another.

Tests are a separate SwiftPM target and are not installed in the app. Keep
meaningful checks for conversion fidelity, originals, cancellation, archives,
and geometry. Use generated inputs; keep local acceptance reports outside Git.

## Mac Checks That Matter

Automated exports do not establish interactive acceptance. Record the Mac,
macOS version, build, actions, and results when checking these areas:

| Area | Hands-On Checks |
| --- | --- |
| Finder and workspace | Drag sessions, modifier keys, multiple displays, wheel paging, safe center, outside drops, file ordering, menu bar, quit during work |
| Image crop | Landscape, portrait, orientation, transparency, every handle, ratios, numeric dimensions, keyboard movement; compare selection with exported pixels |
| Audio trim | Audible selection and PCM output, silence, mono/stereo, nonzero ranges, seek and close during playback or waveform loading |
| Video trim and crop | Portrait transforms, silent clips, edges and aspect ratios, MP4/MOV, selected duration, retained audio, decoded output geometry |
| PDF editors | Mixed sizes and rotations, text/annotations, drag and button ordering, multi-selection, Undo/Redo/Reset, changed sources, long documents |
| Appearance | All themes, VoiceOver, keyboard focus, reduced motion/transparency, contrast, Finder/Dock icon, first launch of a quarantined download |

For every editor, cancel while loading and exporting, close and reopen with a
different file, and check that old requests cannot update the new session.
Original bytes must be preserved; failed or cancelled work must publish no file.
Use the [Roadmap targets](ROADMAP.md#keep-it-lightweight) for measurements rather
than inferring CPU or memory use from preview limits.

For the 0.1.16 interaction changes, recheck these specific paths on a Mac:

- **Manual wheel:** With VoiceOver, inspect mode, page, and selection; use named
  selection actions, choose an operation, change mode/page, and cancel. Check
  Tab and Shift-Tab. A real Finder drag into the manual wheel must still require
  a drop; accessibility actions must not submit a pending drag.
- **Audio trim:** On the active keyboard layout, use S/E to select handles.
  Hold Space and confirm only one playback change. Arrow repeat and Shift-arrow
  movement should continue; Command, Control, and Option shortcuts pass through.
- **File shelf:** Inspect each Finder button's purpose and file name.
- **Workspace:** Move and resize, quit and reopen, then disconnect a display.
  Check negative display origins, mixed scaling, minimized windows, full screen,
  and a window spanning displays. A usable placement should remain unchanged.

Window-placement unit checks cover recovery geometry. They do not establish
native window restoration, keyboard interaction, or VoiceOver acceptance.

### Measure on a Mac

Inspect the installed app and local signing readiness with:

```bash
python3 script/review_mac.py --output "$HOME/Desktop/Lemulip-Mac-Review"
```

The default app is `/Applications/Lemulip.app`; use `--app PATH` for another
installation. The report records the app version, generic hardware model,
macOS version, installed logical and allocated bytes, and summarized signing
checks. It omits usernames, computer names, volume paths, serial numbers,
certificate identity names, and credentials. Nothing is uploaded.

For idle measurements, open the selected app, keep the workspace visible and
the drag wheel enabled, and finish all jobs and playback. Close editors, then
run with a new output folder:

```bash
/usr/bin/open "/Applications/Lemulip.app"
```

Wait for the workspace to appear, then start the collector:

```bash
python3 script/review_mac.py --measure-idle \
  --output "$HOME/Desktop/Lemulip-Idle-Review"
```

The collector verifies the running executable before asking for **IDLE**.
It distinguishes a closed app, a different running installation, and multiple
matching processes. If several instances of the selected app are running,
finish any work and quit the extra instances, or pass `--pid` with the selected
process ID from Activity Monitor. Another installation requires its actual
app path with `--app`; do not copy an example placeholder as a path.

After confirmation, the collector waits 60 seconds and samples for another
60 seconds. It attaches only to the matching running app and does not launch or
quit it. If idle measurement cannot start or is interrupted, completed readiness
checks are still saved with idle status **Not Measured**, without partial
measurements. Each attempt needs a new output folder; existing reports are
preserved.

The report gives mean and peak sampled resident memory for the main process
and interval CPU usage as a percentage of one logical CPU. It also reads the
kernel's per-process interrupt and platform-idle wakeup counters at the start
and end of the observation period. Counts and rates use their own measured
interval, and the native process-start value must match at both endpoints.

The wakeup counters describe different kernel events. Report them separately;
do not add them, infer them from a timer interval, or interpret them as a
battery-use measurement. The collector uses `proc_pid_rusage` with
`RUSAGE_INFO_V0` for the selected, current-user app. It requests no elevated
privileges. If the counters are unavailable, denied, reset, or inconsistent,
wakeups stay **Not Measured** while valid memory and CPU results are retained.
Apple's [V0 counter layout](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/sys/resource.h)
and [task-counter mapping](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/osfmk/kern/bsd_kern.c)
define the collected fields. Optional engines and interactive startup time
remain outside this collection.

Report the median of ten interactive warm launches separately. A local XCTest
UI-test target can use
[`XCTApplicationLaunchMetric(waitUntilResponsive: true)`](https://developer.apple.com/documentation/xctest/xctapplicationlaunchmetric/init(waituntilresponsive:))
for the installed app. Record the ten individual durations and their median,
then check a real workspace or menu action separately. Finish all work and
quit the app normally before this repeated-launch review; the test can
terminate the app between iterations. Keep the local test project and raw
results outside the repository.

If the native launch metric is absent or has too few samples, keep warm launch
**Not Measured**. A passed XCTest, its total duration, or a Clock Monotonic Time
measurement does not replace the missing first-frame/responsiveness metric.

Use an actual first-frame/responsiveness measurement, not the return time of
`open` or the appearance of a process ID. See Apple's
[launch-time guidance](https://developer.apple.com/documentation/xcode/reducing-your-app-s-launch-time).

Signing readiness is diagnostic. A valid local signature or an available
Developer ID identity does not prove notarization or a successful first launch
from a browser download. Complete the [distribution checks](PUBLISHING.md#signing)
on a Mac before closing that roadmap item. Keep local reports outside Git.

## Converter Constraints

Use native frameworks for supported formats and keep external engines optional.
Document input limits in [Formats](FORMATS.md); controls belong in the
[User Guide](USER_GUIDE.md). Shared invariants are:

- Preflight the whole batch before output. Unsupported RTF or Markdown may select the
  optional route, but malformed input, cancellation, or a failed native writer
  must not be hidden by an engine retry after partial output.
- Stage outputs privately, use unused final names, and clean temporary output on
  failure or cancellation. External converters receive argument arrays and a
  restricted environment, as described in [Security](../SECURITY.md).
- Downsample previews; export from original source data. Bound caches and edit
  history, cancel obsolete tasks, and release players and observations on close.
- Serialize PDFKit preview access. Bind edits to source snapshots/fingerprints;
  reject replaced or restricted inputs before copying original PDF pages.
- A visual merge plan applies only to `pdf.merge` with PDF output. Keep the
  selected order and omissions; the CLI uses argument order.

### Video Trim Constraints

Request 12 thumbnails by default, at most 24, with a 192-pixel longest edge.
Accept one local native video track and at most one audio track. Exports
re-encode; compare boundaries using the documented frame/codec precision.
Keep playback scoped to the editor and remove its observers on close.

### Video Crop Constraints

Use one upright preview frame of at most 1,280 pixels on its longest edge.
Apply one spatial rectangle across the full timeline, retain audio, and reject
combined trim/crop options. Validate upright geometry and even output dimensions
before safe publication.

### PDF Organization Constraints

Preserve original page identity through reordering, rotation, removal, and
extraction. Retain at most 24 thumbnails with a 320-pixel longest edge, plus
40 undo and 40 redo snapshots. Keep input, page, permission, and output limits
in the format guide. Application cache limits do not bound all PDFKit memory.

### PDF Merge Preview Constraints

Reuse the organizer's snapshots and rendering. Inspect documents sequentially,
retain small summaries, and copy original pages in the chosen document order.
Validate retained fingerprints, page counts, and permissions again before export;
remove temporary snapshots on success, failure, and cancellation.

## Basic Office Export Constraints

TXT and supported basic RTF use AppKit's DOCX writer. CSV/TSV use the built-in
XLSX writer and archive bridge. Native Word metadata identifies Lemulip and
clears imported company/manager fields; never copy user or source-path metadata.

Basic Markdown uses a portable OOXML writer and the same archive bridge. Its
preflight validates every file before choosing the native writer or Pandoc for
the whole Markdown selection. Invalid text and XML controls fail directly;
unsupported syntax may select Pandoc only before native export starts. Keep
real numbering, local package relationships, and fixed Lemulip metadata. The
existing `word-markdown` review case covers this writer; external-engine checks
continue to exercise Pandoc independently.

RTF uses an explicit control/destination allowlist before AppKit import.
Unsupported rich structures select LibreOffice before output. Retain bounds for
nesting and formatting commands, and revalidate changed inputs during export.
The native route does not reconstruct rich page layout or unavailable fonts.

XLSX has one **Sheet1**, with explicit text cells. Preserve leading zeros,
formula-like text, quoted delimiters, blank rows, multiline cells, and OOXML
string escapes. Reject malformed quoting, unsupported controls, and oversized
input while parsing. Detailed limits are in [Office Formats](FORMATS.md#documents-slides-and-spreadsheets).

## Rich Office Conversion Checks

Integration tests generate small Office documents, round-trip them through
LibreOffice, and inspect the resulting packages:

| Round Trip | Checked Content |
| --- | --- |
| DOCX → ODT → DOCX | Table/text order, Unicode, stored font traits, explicit page boundary |
| XLSX → ODS → XLSX | Two ordered sheets, typed cells, text identifiers, two formula expressions and cached values |
| PPTX → ODP → PPTX | Two ordered slides, text, stored fonts, dimensions, and shape bounds |

Keep namespace handling explicit, retain the XML document while inspecting its
nodes, and reject duplicate or misplaced elements. Word page-boundary checks
accept a paragraph page break or a leading inline break; later breaks and
visible content before the boundary must still fail.

Package assertions do not establish font availability, Office rendering, or
general formula recalculation. Macros, charts, pivot tables, embedded objects,
and animations remain outside these representative checks.

### HTML and Markdown Word Checks

HTML → DOCX uses LibreOffice's Writer HTML importer and Word exporter. The
basic Markdown review example uses Lemulip's built-in writer; separate advanced
Markdown checks exercise Pandoc. Check headings, emphasis, Unicode, and tables;
Markdown also checks list definitions and literal code spacing.

The Mac XML loader combines `nodePromoteSignificantWhitespace` with
`nodeLoadExternalEntitiesNever` so space-only Word text runs are read as content.
Do not also set `nodePreserveWhitespace`, which disables that promotion. Keep
positive and negative checks for separate word separators and code indentation.
See [Apple's whitespace option](https://developer.apple.com/documentation/foundation/xmlnode/options/nodepromotesignificantwhitespace).

### Prepare the Office Review

The integration tests can retain eight generated input/output comparisons for
[Office Review](OFFICE_REVIEW.md). Normal runs remove their temporary files.
On a Mac with the optional engines installed, use a clean source checkout:

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

The packager checks the capture's source commit, requires all cases, and creates
a new ZIP with checksums and an unfilled results template. Apple silicon CI
uploads **Lemulip-Office-Review-arm64** separately from the four release assets.
Both routes prepare files; actual Microsoft Office acceptance stays
**Not Reviewed** until the comparisons are inspected.

## Prepare a Release

```bash
./script/package_release.sh
./script/package_release.sh --verify dist
```

Use a clean checkout and a new app version for a new release. Packaging preserves
existing archives. For a source-only ZIP, use `python3 script/package_source.py`;
`--output` selects a new filename. See [Publishing](PUBLISHING.md) for the
release workflow and keep signing credentials outside the repository.
