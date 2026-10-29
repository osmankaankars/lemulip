# Native Capture Density Review

W3 is a bounded rendering experiment, not a new set of approved website assets. It hosts the actual production SwiftUI and AppKit views and asks AppKit to redraw them into a bitmap with two pixels per logical point. The runner's screen can remain at 1×. An offscreen render is recorded as an **offscreen native view rendering**, never as an actual 2× screen or window screenshot.

## Drawing Method

`NativeReviewBitmap` allocates an `NSBitmapImageRep` at `2W × 2H` pixels, sets its user size to `W × H` points, creates `NSGraphicsContext(bitmapImageRep:)`, and calls `NSView.displayIgnoringOpacity(_:in:)` on the real host. It does not add a second CGContext scale transform, change layer scales, resize an existing capture, use `ImageRenderer`, repaint the interface, or change a system display or security setting.

This follows [Apple's High Resolution Guidelines, listing 3-3](https://developer.apple.com/library/archive/documentation/GraphicsAnimation/Conceptual/HighResolutionOSX/CapturingScreenContents/CapturingScreenContents.html) and the documented [view redraw into a graphics context](https://developer.apple.com/documentation/appkit/nsview/displayignoringopacity(_:in:)). Those APIs alone do not prove that every modern SwiftUI layer was freshly rendered. The following calibration must pass on the actual SDK and runner.

## Calibration Gate

A separate 320 × 240 point calibration host contains SwiftUI `Text` and `Path`, a real editable `NSTextField`, and a native drawing probe. It contains 12 pt `Il1MW 0123456789` glyphs, thin diagonals/circles, and two half-point stripe fields in **each** rendering system. One stripe field is shifted by half a point. Its raw 1× and 2× PNGs are retained unchanged.

The numerical gate requires all of these:

- Identical logical dimensions and exactly 320 × 240 / 640 × 480 pixel outputs.
- Fresh native vector and `NSTextField.draw` calls during the 2× render, with both measured CGContext scale axes equal to 2.
- Alternating single-pixel dark/light columns in both SwiftUI and native stripe regions, including the shifted phase. Sampled dark means must be below 0.2, light means above 0.8, and their difference above 0.7. A cached 1× raster cannot recover that missing half-point detail when enlarged.
- Detail inside both glyph regions: at least 100 ink samples and 12 nonuniform 2 × 2 blocks, plus mean differences above 0.03 from nearest-neighbor and 0.02 from bilinear samples of the corresponding 1× region. These comparisons compute sample values only; they do not create or retain an enlarged image. They support the stripe and fresh-draw evidence rather than replacing it.

`calibration.json` retains the observed draw CTMs, stripe samples, text metrics, logical/pixel dimensions, window backing scale, requested offscreen scales and pass/fail result. A rendering/setup failure gets `calibration-failure.json`. Failure or mixed rendering fails the experiment and prevents all production 2× candidates. The raw diagnostics remain available. Do not loosen the thresholds to approve a cached or incomplete image.

Even after this gate passes, inspect the original-pixel calibration PNGs, particularly both text regions and the retained native control. Then inspect the exact production PNGs for complete content, sharp type, correct proportions, and fidelity to the real views. An automated difference metric cannot approve a marketing image.

### Observed Mixed Rendering and Follow-up

The Intel capture in [run 40891899407](https://github.com/osmankaankars/lemulip/actions/runs/40891899407), artifact `12906565513`, passed the numerical checks but **failed visual approval**. Native text and half-point vector detail were sharp at 2×; the SwiftUI text remained visibly blurred. The Settings image also showed mixed text density. These files are review evidence and must not become website or marketing assets.

A separate calibration-only test now supplies the documented SwiftUI [`displayScale`](https://developer.apple.com/documentation/swiftui/environmentvalues/displayscale) environment value of 2 to a fresh host. It records the actual observed environment value, keeps the same logical dimensions, renders both raw sizes and applies the unchanged numerical checks. Its output is retained under `high-density-explicit-environment`. This is a hypothesis test for SwiftUI's text-rendering environment, not an established fix; it does not change production views, system display configuration or layer scales. Original-pixel review must establish whether it improves the text before the method is considered for product captures.

The follow-up in [run 40895627758](https://github.com/osmankaankars/lemulip/actions/runs/40895627758) observed environment scale 2 on both architectures, but its 1× and 2× PNG bytes were identical to the corresponding baseline images. Original-pixel review still found mixed text resolution. The bitmap/environment path is not approved for website assets.

### Separate Native PDF Probe

`testNativePDFExportCalibrationArtifacts` uses [`NSView.dataWithPDF(inside:)`](https://developer.apple.com/documentation/appkit/nsview/datawithpdf(inside:)) on the same synthetic 320 × 240 point host. It retains the unmodified PDF, source provenance, PDF SHA-256 and native draw CTMs under `native-pdf-calibration/`. A Core Graphics PDF-page transform then maps the page directly to a 640 × 480 pixel context and draws the PDF once. The PNG record retains the page box, rotation, transform, dimensions and hashes. This is a **native view PDF export rasterized at two pixels per point**, not a Retina screenshot.

A passing artifact-generation test establishes only that this export and rasterization completed. Inspect the raw PDF's font/text/vector operators and embedded images together with the PNG at original pixels. If SwiftUI glyphs are still embedded at 1×, stop this route. This probe never captures production views, grants production-asset eligibility, reconstructs controls, or changes the environment, layers or display configuration.

## Production Review Content

The same renderer retains the real `DashboardView` workspace and `ImageCropView` with its native `ImageCropCanvas`. The only input is a synthetic 640 × 400 orchard-colored grid PNG. The crop is seeded through the existing canvas binding and its source file hash must remain unchanged. No keyboard, pointer or drag event is sent, and no UI element is rebuilt in a drawing script.

The A1 review hosts the actual `SettingsContent` through `DashboardView`, in English/Orchard Night and Turkish/Vivid Pistachio. It reads the Preview button and Selection Sounds toggle from the actual accessibility hierarchy with the preference both off and on: role, localized name, hint, value, enabled state and frame. It retains English/off and Turkish/on renders, with 1× evidence still available if 2× calibration fails. The preference is set through the isolated model/defaults fixture; no accessibility action is dispatched and the injected sound player must receive no playback request.

These checks establish displayed content and accessible-node data only. They do not establish physical keyboard navigation, actual VoiceOver narration, audible playback, hardware mute behavior, or animation quality. Existing interaction tests retain their own strict key-window prerequisites.

## Artifacts and Provenance

Set `LEMULIP_EDITOR_REVIEW_DIR` to opt into `HighDensityNativeReviewTests`. The existing Build and Verify job already sets it and retains `high-density/` inside `Lemulip-Editor-Review-<architecture>`. No new workflow, external automation, permission or OS configuration is needed.

Every PNG has a JSON record containing the source commit, workflow run/attempt, runner architecture, OS version, logical and pixel dimensions, window backing scale separately from requested offscreen render scale, encoded PNG SHA-256 and byte count, raw pixel SHA-256 and row stride, view/state/fixture identity, and explicit no-resize/no-input-event provenance. Review the exact-head artifact and its advertised archive digest before using it. A passing experiment permits review candidates only; it does not replace or amend `site/assets/screenshots.json`.
