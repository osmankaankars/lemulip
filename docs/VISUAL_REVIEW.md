# Native Visual Review — 0.1.20

Reviewed 1 November 2026 (Europe/Istanbul). This is a bounded review, not a claim
that every file, display and interaction was exercised.

## Exact Application and Capture

The unchanged full app came from main build **41248606579**, artifact
**13060974116**, source **eaa783c949a1814130a6618395269ba17c1baa6f**.
App ZIP SHA-256: `1c31268279a094d64dbf8edc1680112705ee1152ad6b2a9c98e782b29aae8523`.
The GUI hash was checked before staging a separate review identity. The original
package was not overwritten. Bundled FFmpeg/ImageMagick remained present.

Capture harness **a45a19cf48310a8d5a3b87ad78d6b7253b3e6213**;
[run 41252452759](https://github.com/osmankaankars/lemulip/actions/runs/41252452759),
artifact **13061981222**, SHA-256
`ab58b67460ee90521a53d43cdb9175469188da8305aaa763163b65c5b704a0b8`.
Actual XCTest logs report **seven tests, zero failures**. The staging receipt's
`NOT RUN` field is not the outcome; the subsequent logs establish that result.

The hosted Mac initially offered only 1x modes. A bounded, development-only
virtual-display fixture produced 1280 x 900 logical / 2560 x 1800 pixel mode.
Independent screenshots measure **2040 x 1400** for a **1020 x 700** app window.
The temporary display was restored. The helper is not linked into Lemulip; no
privacy grant, entitlement, root or system-protection change was made. These are
native 2x renders, not physical Retina-panel captures or enlarged bitmaps.

## Scenarios and Observations

| Scenario | Observed evidence |
| --- | --- |
| Workspace in three themes | Empty, selected-file and no-result states captured. File list, tool grid and primary actions are distinct; no overlap or clipped controls observed in these windows. Escape clears the unsuccessful query. |
| Turkish Workspace and Settings | Labels and sound preview visible and readable; semantic controls present. Not a VoiceOver audition. |
| PDF arrangement | First page moved to position 3 through its actual field. Selection, original-page label, drag handle, Undo and copy action visible. Real four-page PDF export has the expected order; original bytes preserved. |
| Invalid PDF range | `3-1` disables submission and retains the form; correcting to `1,3` enables Create Copy. Turkish error and focused field visible. |
| Video crop | Actual synthetic six-second video loaded; crop canvas, grid, dimensions and save controls visible; output action enabled after preparation. |
| Audio trim | Actual synthetic audio loaded; waveform, handles, start/end and output action visible after preparation. |
| Activity | Real JPG-to-PNG output decodes; Activity reports `1 Completed`; original unchanged. |

Selected screenshots were visually inspected at their real dimensions. No new
blocking native visual defect was observed in this pass, so production UI code
was deliberately left unchanged. The initial Activity test used the wrong AX
property; its locator was corrected to the observed value without weakening the
real output requirement. Historical failed capture attempts remain recorded.

## Web Derivatives

The four approved originals show Workspace, Organize PDF, Crop Video and Trim Audio.
No resampling occurs. Only **290 border-connected pure-black pixels** in the
14-pixel exterior corner boxes become transparent. The native border,
antialiasing and all UI pixels remain intact before metadata-free WebP quality-96
encoding. Original hashes, geometry and processing are recorded in
`site/assets/screenshots.json`. The exporter rejects different source bytes,
dimensions or corner geometry. Website width remains at most 510 CSS pixels.

The historical Activity asset remains preserved but is not a fifth panel. The
existing actual Finder recording and its provenance are unchanged.

## Owner Follow-up and Limits

Kaan explicitly owns speaker/headphone/system-mute and VoiceOver listening during
normal use and will report issues. Those observations are not claimed passed and
are not a release blocker. This review does not establish continuous edge
scrolling, every window size/language/codec, or physical touchpad feel. Existing
29-case two-architecture native regression gates remain separate. Promotional
video work is deferred for a joint discussion after release delivery.
