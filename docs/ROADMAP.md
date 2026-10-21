# Roadmap

Lemulip's core visual editors are released. The next work focuses on Office
fidelity, native Mac interaction, and measured resource use. Open items below
remain open until their stated checks are complete.

## Current Release

[**0.1.15 · Public Preview**](https://github.com/osmankaankars/lemulip/releases/tag/v0.1.15)
is available for macOS 13+ on Apple silicon and Intel. Its source and tagged
Mac builds, package verification, and CodeQL checks passed. Downloads are ad hoc
signed and are not yet notarized by Apple.

The [browser walkthrough](https://osmankaankars.github.io/lemulip/) uses sample
files. It demonstrates the workflow and does not run the native editors or
convert files.

## Released

| Capability | First Downloadable Release |
| --- | --- |
| Orchard Night, Vivid Pistachio, and Lemon Drop themes | 0.1.4 |
| Visual image crop and audio waveform trim | 0.1.4 |
| Native video trim with selection playback | 0.1.5 |
| Visual video crop | 0.1.6 |
| PDF page organization | 0.1.7 |
| PDF merge preview | 0.1.8 |
| Warm white icon and shared wordmark | 0.1.9 |
| Built-in TXT/basic RTF → DOCX and CSV/TSV → XLSX | 0.1.13 |
| HTML Word export fix and expanded markup checks | 0.1.14 |
| Built-in basic Markdown → DOCX | 0.1.15 |

The [User Guide](USER_GUIDE.md) covers controls; [Formats](FORMATS.md) records
supported routes and limits. Development versions that did not produce a
separate download are grouped into the release that delivered their changes.

## Next

Work through these in order; release signing also depends on an available
Developer ID identity.

**Prepared for 0.1.16:** Manual-wheel accessibility actions, layout-aware audio
shortcuts, a Finder action label, and workspace position recovery. Native CI and
hands-on Mac review are still required; this work does not close the interaction
and accessibility item below.

| Order | Open Work | Complete When |
| --- | --- | --- |
| 1 | **Office Review** | Use the [guided review](OFFICE_REVIEW.md#run-the-guided-review) to inspect the eight comparisons in Word, Excel, and PowerPoint. Record actual app versions, fonts, pagination, literal cell values, formula recalculation, and slide appearance. Current manual status: **Not Reviewed**. |
| 2 | **Mac Interaction and Accessibility** | Check Finder dragging, multiple displays, each editor's pointer/keyboard controls, playback, cancellation, reopening, VoiceOver, and accessibility settings. Review Finder/Dock appearance and capture actual app screenshots. |
| 3 | **Lightweight Performance** | Run the [local Mac collector](DEVELOPMENT.md#measure-on-a-mac) for installed size, idle memory/CPU, and wakeups, then measure ten interactive warm launches on a stated Mac/OS baseline. Investigate the current 40 ms drag polling interval if measurements show unnecessary idle cost. |
| 4 | **Signed Distribution** | Check local signing readiness, add Developer ID signing and notarization when credentials are available, then verify a quarantined download's installation and first launch on a clean Mac. |

Automated conversion checks do not complete hands-on interaction or Microsoft
Office review. Keep observed results separate from plans and engineering targets.
The [Development Guide](DEVELOPMENT.md#mac-checks-that-matter) records the checks
that contributors should run. The review tools write local reports; preparing
them does not complete any acceptance gate or publish personal machine data.

## Later

- PDF → editable DOCX and slide → image export, with explicit layout and page-selection limits.
- File references for Finder paste and improvements to the floating shelf. Current **Copy To…** chooses a destination; **Copy Path** copies text.
- Photo adjustments, metadata editing, canvas/collage tools, and richer media tools, prioritized by repeated user needs.
- Evaluate a native layered icon after the current icon's Finder and Dock review. The released app uses the reviewed static white-tile master.

These are future directions, not current menu features or promised release dates.

## Keep It Lightweight

The app uses AppKit and SwiftUI with no third-party Swift package dependencies.
Optional engines are separate installations. The website, tests, and design
sources are not bundled into the installed app.

The verified [0.1.15 release](https://github.com/osmankaankars/lemulip/releases/tag/v0.1.15)
has a **6.06 MB DMG** (6,058,955 bytes) and **6.47 MB universal ZIP**
(6,473,694 bytes). These are decimal download sizes, not installed size or memory use.
The following remain targets until measured:

| Metric | Target | Method |
| --- | --- | --- |
| Universal Download and Installed App | ≤30 MB compressed; ≤60 MB installed | Measure the app package and installed bundle, excluding optional engines |
| Idle Memory | ≤100 MB resident memory | No jobs or editors, after a 60-second settling period |
| Idle CPU | <0.5% of one logical CPU on average | Observe 60 seconds with the wheel enabled and no drag; record wakeups |
| Warm Launch | Interactive workspace within 1 second | Median of 10 launches on an Apple silicon baseline; record Mac and macOS versions |

Measure Intel separately. Keep previews bounded, prepare them off the main
thread, cancel obsolete work, and release editor resources on close. A smaller
repository or bounded thumbnail count is not a measurement of app memory.
