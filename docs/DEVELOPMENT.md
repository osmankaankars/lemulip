# Development

macOS 13+ and Swift 5.9+ are required for the app. Linux tests cover portable code, not AppKit, SwiftUI, or Apple converters.

## Build and Check

```bash
swift build
swift test --jobs 2 --skip EngineIntegrationTests
python3 script/privacy_check.py
./script/build_and_run.sh --verify
```

With the optional engines installed, `swift test --jobs 2` also runs integration checks. `./Build-and-Install.command` builds and installs without replacing an existing app. `./script/build_app.sh --universal` creates Apple Silicon and Intel binaries.

## Where Things Live

| Path | Responsibility |
| --- | --- |
| `Sources/Lemulip` | App lifecycle, wheel, workspace and editors |
| `Sources/LemulipCore` | Catalog, conversions, process isolation and safe output |
| `Sources/CLemulipArchive` | Bounded libarchive bridge |
| `Sources/LemulipCLI` | CLI using the shared engine |
| `Tests/LemulipCoreTests` | Core, native, integration and geometry tests |
| `site` | Static product page and sample wheel |
| `script` | Build, packaging, publishing and checks |

## Product and Internal Names

SwiftPM products are **LemulipApp** and **lemulip**. Keep their names distinct on case-insensitive filesystems. Source imports use `LemulipCore`.

The bundle ID `app.freewheel.Freewheel`, existing preference keys, and `FreewheelMainWindow` autosave key preserve installed users' settings. They are deliberate compatibility identifiers. Run `python3 script/test_branding.py` after naming changes.

## Appearance and Branding

`Sources/Lemulip/Theme.swift` owns the three themes and shared Palette roles. Native settings use `theme`; the website uses `lemulip.appearance`. Both accept `orchard`, `pistachio`, and `lemonade`, with Orchard Night as fallback.

Update AppKit drawing on theme changes without recreating editors or jobs. Preserve Reduce Transparency, Increase Contrast, keyboard navigation, and forced-colors fallbacks.

`Resources/AppIcon.png` is the icon master; `script/make_icon.swift` generates the app's ICNS. Keep artwork provenance intact. Native screenshots must come from the running app, not a browser mockup.

## Safety and Verification

Conversions preserve originals, use unused output names, and clean up failures and cancellation. Explicit Move is the exception. Optional engines use argument arrays, restricted environments, and existing process-isolation limits, never shell command strings.

Keep generated fixtures and local logs out of the repository. Test real outputs, not just file existence. Changes to editors need a macOS build and interaction review; package/XML tests do not establish Office rendering or formula recalculation. The [Office Review](OFFICE_REVIEW.md) kit records those comparisons.

### Rich Office Conversion Checks

Integration checks cover generated DOCX/ODT, XLSX/ODS, and PPTX/ODP round-trips, plus HTML and Markdown exports. They inspect document structure and representative values. Target-app layout and recalculation remain separate [Office Review](OFFICE_REVIEW.md) checks.

Format and converter constraints are documented in [Formats](FORMATS.md). The libarchive declarations and their upstream notices must remain in distributions.

## Website Checks

```bash
python3 script/test_site.py
python3 script/test_public_images.py
node --check site/catalog.js
node --check site/product.js
python3 script/test_site_browser.py --engine chromium --output /tmp/lemulip-site-review
```

Playwright is a test-only dependency. CI also runs WebKit and checks the public URL after Pages deployment. Keep the nine sample files, keyboard and pointer interactions, themes, reduced motion, and mobile layout covered. The demo never reads user files.

## Prepare a Release

Update both version fields in `Resources/Info.plist` and add one matching `## MAJOR.MINOR.PATCH · Title` section in [Release Notes](RELEASE_NOTES.md). Preserve the shared `## Installation` section used by the publisher.

Build and Verify plus CodeQL must pass on the exact source commit. The release coordinator validates the repository and current main, creates an annotated version tag, and explicitly dispatches a tagged build. Tagged checks verify DMG, app ZIP, source ZIP, and checksums before publication. Existing tags and conflicting assets are not overwritten.

For an interrupted release, inspect the failed stage. The coordinator does not automatically retry failed tagged builds. Matching incomplete drafts retain verified assets; conflicting tags or metadata need review rather than replacement.

```bash
./script/package_release.sh
./script/package_release.sh --verify dist
```

Source-only packaging uses `python3 script/package_source.py --output PATH`. Website and documentation edits do not require a version bump or replacement app downloads. Keep credentials and personal data outside the source; run `python3 script/privacy_check.py --staged` before publishing.
