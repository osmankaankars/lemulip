# 0.1.20 Release Delivery

Verified **1 November 2026 (Europe/Istanbul)**. This closes the approved release,
visual-review, capture and website tasks. It does not claim physical listening
or start the promotional film.

## Delivered Scope

| Owner task | Outcome |
| --- | --- |
| 1: Final full release | Public v0.1.20 / build 23, including the wheel-navigation sound correction and both bundled engine architectures. |
| 3: Native visual pass | Seven full-app scenarios passed; reviewed real captured states. No new blocking visual defect observed in this bounded pass. |
| 4: Fresh product images | Four genuine native 2x captures, not enlarged 1x bitmaps. Workspace, PDF Pages, Crop Video and Trim Audio. |
| 5: Website and story | PR #34 merged; public 0.1.20 links, task-led gallery copy and refreshed sharing card passed deployed Chromium/WebKit checks. |
| Tracking | Current roadmap and delivery state separated from the complete unchanged historical roadmap; detailed native/marketing notes retained. |
| 2: Daily-use feedback | Completed by owner acceptance on 1 November 2026. Kaan reported no issues and explicitly requested closing this stage, including the previously delegated sound/system-mute and VoiceOver follow-up. No automated acoustic or narration certification is claimed. |
| 6: Film | Not started; reserved for a later joint discussion. |

## Owner Acceptance

On **1 November 2026**, Kaan confirmed that there were no issues and asked for the
"Daily-use feedback" stage to be considered complete. This closes the owner
follow-up; it is not a new automated test run or a claim about individual device,
mute or narration scenarios. Earlier handoff notes describe the state before this
acceptance. The promotional film remains the only deferred item in the approved
delivery scope. Future issue reports and candidate features are separate work.

## Exact Published Package

Tagged source: `eaa783c949a1814130a6618395269ba17c1baa6f`.
[Tagged run 41251798521](https://github.com/osmankaankars/lemulip/actions/runs/41251798521)
completed native gates, both engine builds, universal packaging, both exact-archive
checks and publication. GitHub published the preview on **1 November 2026 at
03:11:52 Europe/Istanbul**. It remains a public preview; archive checks do not establish all platform trust-policy requirements.

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| App ZIP | 144,331,845 | `bad63ed87bfb9756c017c061c5811ad168382ec1648034c637175ddfce4436c6` |
| DMG | 149,992,570 | `b170c6bf8f1d0bf7dd239ebcd39d4a7fb67b71963836850142791d62bba31358` |
| Source ZIP | 2,522,841 | `3feea3d4a2ca72c5ba4ba3cde162324f2fbffd366a27292316095abc180bac1c` |

Downloaded tagged-run artifact **13063255213**, SHA-256
`79408b4b8bcd4d5500de94dacc4b99207a8214f6f91f5c7e1293422c63beefca`,
matched its advertised 296,857,124 bytes and ZIP CRC. All three inner checksums
and SHA256SUMS.txt matched the public release asset size/digest metadata. This
is artifact-to-public-digest verification; the continuation sandbox could not
directly fetch the public URLs. Actual plist is 0.1.20/build 23; the GUI, FFmpeg,
FFprobe and ImageMagick have arm64 and x86_64 slices. Logical app payload is
237,418,447 bytes. Older candidates and published 0.1.19 assets were not replaced.

The first tagged attempt's Intel PDF group-drag failure remains in the run
history. The unchanged retry passed; a retry is not represented as a product
repair or evidence of every physical interaction.

## Native Visuals

Capture run **41252452759**, artifact **13061981222**, was downloaded and checked
against SHA-256 `ab58b67460ee90521a53d43cdb9175469188da8305aaa763163b65c5b704a0b8`.
Actual XCTest logs report seven tests with zero failures. The approved exporter
reproduced all four committed WebP hashes exactly from those originals.
[VISUAL_REVIEW.md](VISUAL_REVIEW.md) records full-app provenance and the boundaries:
1020 x 700 logical windows, 2040 x 1400 native pixels on a temporary Mac HiDPI
test display; not a physical Retina panel or generated/repainted interface.

## Website Verification

PR #34 merged as `f05db25a93869e717e56cf93f51a255c11303c36` with exact tested tree
`c830b1c118f7858930ef90b1eede1c0e83cc93d5`. No native Sources, Resources, Tests or
Package.swift differ from the released source. All exact-head PR checks passed:
Build **41254975770**, CodeQL **41254975731**, browser **41254975771** and Pages
preparation **41254975841**. Fresh local checks passed 190 Python tests and the
220-file privacy scan.

[Live browser run 41297482917](https://github.com/osmankaankars/lemulip/actions/runs/41297482917)
completed against **https://osmankaankars.github.io/lemulip/** after deployment.
Both browser reports identify that public URL and pass 1440, 1280, 768, 390 and
320-pixel widths: gallery tabs/focus, themes, sample wheel, catalog/direct links,
download target, metadata/image decoding, reduced motion and no-JavaScript paths.
Both report empty page-error and HTTP-failure lists and no overflow.

Live artifact **13079788356**, 13,040,956 bytes, SHA-256
`7cf2cce80f9add5bd91c16aa0e770806e46f660a906b7252337a275787b7b09b`,
passed download hash/CRC checks; both result JSON files and selected desktop/mobile
captures were inspected. The Browser plugin/local browser binaries were unavailable
in the continuation sandbox; the existing GitHub-hosted Playwright gates performed
the browser runs. No local interactive-browser claim is made.

Documentation-only delivery updates do not change this deployed site tree,
application code, release tag or published binaries. Future broader workload,
physical-device and audio observations remain distinct from this delivered scope.
