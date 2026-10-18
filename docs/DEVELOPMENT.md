# Development

Freewheel is a Swift package with a native macOS app and a CLI. It requires
macOS 13 or later and Swift 5.9 or later. A recent full Xcode installation is the
most straightforward build environment; see [Installation](INSTALL.md).

## Build and check

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

## Where things live

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

## Verification so far

The following results were observed while preparing the public preview. They
describe their stated environment and scope; the current commit's Actions run
is the place to check later results.

| Check | Observed result |
| --- | --- |
| Apple silicon source release build | Completed with Xcode 26.3, Swift 6.2.4, and macOS SDK 26.2 |
| Generated Mac app bundle | Property list validated; ad hoc signature verification passed |
| Portable engine and integration checks | 29 tests passed on Linux, including actual optional-engine conversions |
| Wheel geometry | 8 tests passed on Linux |
| Vendored archive-header repair | Focused rerun: 5 existing archive tests passed without external include flags |
| Application entry repair | Swift isolation/lifetime reproduction and Linux executable build passed; subsequent native release build completed |

The portable checks used Swift 6.0.3 in Swift 5 language mode on Ubuntu 24.04.
macOS-only code is excluded from a Linux build. The archive rerun is part of the
earlier test set, not five additional tests. The initial optional-engine checks
used FFmpeg 6.1.1, ImageMagick 6.9.12, official Pandoc 3.12.1, and a LibreOffice
26.8 development build; those results do not guarantee every engine version.

## Mac checks that matter

CI runs the core and native-converter tests and package checks on Apple silicon
and Intel. Optional-engine integration tests run on Apple silicon. Universal
artifacts are built once, downloaded again, verified, and then reused for a
tagged prerelease. Consult the workflow
for the exact checks and inspect its result before relying on a package.

Human verification still matters for Finder drag sessions, multiple displays,
wheel paging, dropping into the safe center, menu-bar behavior, keyboard access,
quitting during a job, and installing a quarantined download on a clean Mac.
A process that launches successfully is not proof of those interactions.

## Prepare a release

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
