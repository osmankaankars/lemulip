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
targets. Record 0.1.5 measurements only after its exact packages exist; bounded
thumbnail storage alone does not establish a process-memory result.

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
