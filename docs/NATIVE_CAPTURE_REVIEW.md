# Native Capture Density Review

W3 is a bounded rendering experiment, not a new set of approved website assets. It hosts the actual production SwiftUI and AppKit views and asks AppKit to redraw them into a bitmap with two pixels per logical point. The runner's screen can remain at 1×. An offscreen render is recorded as an **offscreen native view rendering**, never as an actual 2× screen or window screenshot.

## Current Decision

**The bitmap, SwiftUI `displayScale`, and native PDF probes are closed without asset approval.** The bitmap paths retained blurred SwiftUI text. The PDF path retained real text but omitted SwiftUI graphics, and its preview achieved a 1× transform despite requesting 2×. None provides a faithful 2× capture of the whole view.

Real Retina captures of the final integrated app are still needed for the website and promotional material. Retain the actual window backing scale, logical and pixel dimensions, source commit and unmodified capture files. The diagnostic artifacts below remain unchanged as evidence of the observed limitations.

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

`calibration.json` retains the observed draw CTMs, stripe samples, text metrics, logical/pixel dimensions, window backing scale, requested offscreen scales and pass/fail result. A rendering/setup failure gets `calibration-failure.json`. Numerical failure prevents production 2× candidates. A numerical pass still requires visual approval; observed mixed rendering rejects the resulting candidates even when the numerical status says pass. The raw diagnostics remain available. Do not loosen the thresholds to approve a cached or incomplete image.

Even after this gate passes, inspect the original-pixel calibration PNGs, particularly both text regions and the retained native control. Then inspect the exact production PNGs for complete content, sharp type, correct proportions, and fidelity to the real views. An automated difference metric cannot approve a marketing image.

### Observed Mixed Rendering and Follow-up

The Intel capture in [run 40891899407](https://github.com/osmankaankars/lemulip/actions/runs/40891899407), artifact `12906565513`, passed the numerical checks but **failed visual approval**. Native text and half-point vector detail were sharp at 2×; the SwiftUI text remained visibly blurred. The Settings image also showed mixed text density. These files are review evidence and must not become website or marketing assets.

A separate calibration-only test supplied the documented SwiftUI [`displayScale`](https://developer.apple.com/documentation/swiftui/environmentvalues/displayscale) environment value of 2 to a fresh host. It recorded the actual observed environment value, kept the same logical dimensions, rendered both raw sizes and applied the unchanged numerical checks. Its output is retained under `high-density-explicit-environment`. The test changed no production views, system display configuration or layer scales.

The follow-up in [run 40895627758](https://github.com/osmankaankars/lemulip/actions/runs/40895627758) observed environment scale 2 on both architectures, but its 1× and 2× PNG bytes were identical to the corresponding baseline images. Original-pixel review still found mixed text resolution. Both bitmap/environment probes are closed and their outputs are not approved for website assets.

### Separate Native PDF Probe

`testNativePDFExportCalibrationArtifacts` used [`NSView.dataWithPDF(inside:)`](https://developer.apple.com/documentation/appkit/nsview/datawithpdf(inside:)) on the same synthetic 320 × 240 point host. It retained the unmodified PDF, source provenance, PDF SHA-256 and native draw CTMs under `native-pdf-calibration/`. The probe requested a PDF-page transform into a 640 × 480 pixel context and drew the PDF once. The PNG record retained the returned transform, page box, rotation, dimensions and hashes.

The Intel artifact `12907654772` from [run 40899602333](https://github.com/osmankaankars/lemulip/actions/runs/40899602333) came from source `80a83d689c0c47993d4403aaa1830381b2bd1acd`, whose tree exactly matches reviewed head `31cbbd3bc8791b6d8aaf7ecef31b71729bb7f9aa`. Archive, PDF and PNG hashes were verified before two independent reviews of the raw PDF contents and original-pixel PNG.

Both strings are genuine 12 pt SFNS TrueType text and the PDF contains no embedded raster images. However, all 131 vector drawings lie in the lower native half of the page. The upper SwiftUI half is missing its red marker, both stripe fields, diagonal and circle. Those graphics are absent from the raw PDF as well as the PNG. The export is therefore incomplete independently of its rasterization scale.

The PDF media box is 320 × 240 points and the PNG is 640 × 480 pixels, but both recorded `pdfToPixelTransform` and `drawingCTM` are `[1, 0, 0, 1, 160, 120]`. The preview centers 1× content in the larger bitmap. Its `requestedPDFRasterScale: 2`, `-2x.png` filename and `captureKind` wording describe the intended scale, **not the achieved scale**. Preserve those original records; the measured transform and visible placement take precedence over their wording.

The native PDF probe is closed. Its passing artifact-generation test established only that export and rasterization completed; it did not establish completeness or 2× density. This probe granted no eligibility for production assets and made no changes to production views, the environment, layers or display configuration.

## Production Review Content

The same renderer retains the real `DashboardView` workspace and `ImageCropView` with its native `ImageCropCanvas`. The only input is a synthetic 640 × 400 orchard-colored grid PNG. The crop is seeded through the existing canvas binding and its source file hash must remain unchanged. No keyboard, pointer or drag event is sent, and no UI element is rebuilt in a drawing script.

The A1 review hosts the actual `SettingsContent` through `DashboardView`, in English/Orchard Night and Turkish/Vivid Pistachio. It attempts to read the Preview button and Selection Sounds toggle from the actual accessibility hierarchy with the preference both off and on: role, localized name, hint, value, enabled state and frame. It retains English/off and Turkish/on renders, with 1× evidence still available if 2× calibration fails. The preference is set through the isolated model/defaults fixture; no accessibility action is dispatched and the injected sound player must receive no playback request.

The review on both architectures in run 40895627758 produced none of the eight required Settings control records. Each bounded walk retained 175 objects without truncation, while the SwiftUI host exposed zero ordinary or navigation accessibility children. The raw renders establish visible content; they do not verify the intended accessible names, values or hints. Physical keyboard navigation, actual VoiceOver narration, audible playback, hardware mute behavior and animation quality remain outside this capture evidence. Existing interaction tests retain their own strict key-window prerequisites.

## Artifacts and Provenance

The archived harness uses `LEMULIP_EDITOR_REVIEW_DIR` to opt into `HighDensityNativeReviewTests`. The existing Build and Verify job sets it and retains the experiment directories inside `Lemulip-Editor-Review-<architecture>`.

Every PNG has a JSON record containing the source commit, workflow run/attempt, runner architecture, OS version, logical and pixel dimensions, window backing scale separately from requested render scale, encoded PNG SHA-256 and byte count, raw pixel SHA-256 and row stride, view/state/fixture identity, and explicit no-resize/no-input-event provenance. Preserve the exact artifacts and their advertised archive digests. These closed experiments do not replace or amend `site/assets/screenshots.json`.
