# Native App Refinement Brief

Updated 4 November 2026.

**Status:** unreleased interaction-feedback refinement based on `d3063cb`, following the product-language changes in [PR #42](https://github.com/osmankaankars/lemulip/pull/42). The public app reference is **0.1.20, build 23**. Fresh candidate checks and native captures are required; existing public screenshots do not establish this refinement's appearance or behavior.

Read this with [DESIGN.md](DESIGN.md) for the shared identity and [WEBSITE.md](WEBSITE.md) for the separately scoped website. This brief records the current native refinement so later work can continue from the same decisions.

## Purpose And Protected Behavior

The app is **Operate**: help someone finish a file task with familiar Mac controls. Use precise labels, useful defaults and short explanations at the moment they matter. Keep the genuine icon, platform typography, Orchard/Pistachio/Lemonade themes and operation wheel. Preserve stable operation and accessibility identifiers, keyboard behavior, selection identity, undo, output-copy behavior and support-installation paths.

Use the pinned research snapshots in [Website Reference Roles](WEBSITE.md#reference-roles): **UI/UX Pro Max** informs task planning and hierarchy; **Taste** informs composition within Lemulip's established identity; **Impeccable** directs clarity and a bounded native quality review; **Jakub Krehel** informs labels, wrapping, focus and final interaction details. These roles guide the work without changing its native stack or introducing new runtime dependencies.

## Current Candidate

### File acceptance and native motion

Both empty and populated workspaces identify the file-drop target. While a file drag targets the populated selection, show the same accent dashed outline used by the empty drop zone. Keep the selected count, filenames, controls and layout stable. The outline is decorative and must not intercept input or appear as a separate accessibility element. It clears when the native targeting state ends; loading URLs, append order and duplicate handling retain the existing path.

This feedback is immediate, with no added animation. Keep existing native progress controls and the shared panel appearance behavior: the wheel and result panel use short opacity-only entrances, with controls available immediately. Reduce Motion or Reduce Transparency makes those entrances immediate, including when a preference changes during a fade. Result presentation must preserve the current key window; repeated presentation and dismissal must not restart or revive an old fade.

Use the existing appearance, panel reuse and native interaction checks. A normal-state screenshot can establish content and geometry, but cannot prove drag hover, exit or cancellation feedback. A continuous native drag observation is required before claiming those transitions were visually reviewed. Source review and injected-preference tests likewise do not establish the full System Settings or audible VoiceOver path.

### Workspace file order

When several files are selected, explain the available control: **“Use the arrows to reorder files.” / “Dosyaları oklarla sırala.”** Merging is described only by operations that actually combine inputs. File ordering, available operations and wheel ordering stay unchanged.

### Output choices and support

Replace generic descriptions with these source-verified distinctions for the relevant input family:

| Route | English | Turkish |
| --- | --- | --- |
| Image → PNG | Supports transparency | Saydamlığı destekler |
| Image → JPG/BMP | Transparent areas become white | Saydam alanlar beyaz olur |
| Audio → M4A | AAC audio | AAC ses |
| Audio → WAV/AIFF | 16-bit PCM audio | 16 bit PCM ses |

Keep more specific route information first: PDF page exports remain **300 DPI**, PDF text conversion extracts the existing selectable text, and multiple images can be combined into a PDF in the displayed order. Preserve the EPUB, Word and Excel distinctions. Turkish descriptions must distinguish basic Markdown, basic formatting and plain text, and must retain the native spreadsheet route's text-cell limit.

The existing **Add Support / Destek Ekle** state remains visible when a declared engine is missing. Shared help text exposes the engine or its requirement to pointer and accessibility users; search includes the useful output description and the declared engine name. A capability description does not identify which engine will execute a conversion. Operation IDs, dependencies and conversion capabilities are unchanged.

### PDF page positions

Label the editable output order **Position / Sıra**, with **Original Page / Orijinal sayfa** as secondary information. Keep the idle instruction short: drag pages or edit their position. Put the longer ⌘-click, Shift-click and grouped dragging explanation in the existing **Keyboard & Tips** disclosure.

During number editing, keep the valid range, Enter-to-move, Esc-to-cancel and grouped movement guidance visible. Preserve position field identifiers, original-page identity, invalid-value recovery, selection, keyboard focus, drag behavior and undo. The disclosure must fit the fixed native sheet and leave the page grid usable when expanded.

### Audio trim default

Prefer the source format when it is among the preview's supported outputs. Normalize the extension, including **AIF → AIFF** and letter case. When the source format is unavailable, retain the first supported output as the fallback. The user can still choose another available format before saving, or cancel the edit.

Matching the source extension does not preserve the original encoding or bit depth. Keep the existing limits explicit: **M4A is re-encoded as AAC; WAV and AIFF are uncompressed 16-bit PCM copies.** Preserve the preview's capability filtering and unsupported-format handling.

### Common editor controls

All four editors retain the shared **Original Kept / Cancel / Create Copy** footer. Keep validation and the PDF position field's own Enter/Escape behavior at their call sites. The different page grid, file list, waveform and video timeline still determine each editor's layout and directional controls.

The PDF merge editor follows the organizer's concise idle instruction and existing **Keyboard & Tips** disclosure. Keep the valid position range and Enter/Escape guidance visible while a position draft is active. Use **Sıra / sıra numarası** consistently in Turkish field help, active guidance and the context menu. Expanded help must leave the file list and footer usable.

Audio's range-only reset is **Reset Selection / Seçimi sıfırla**, matching video. It restores the full valid range while retaining the selected output format. Both media editors keep their existing time parsing, range validation and disabled playback/export states for invalid text.

Audio playback resumes from its paused position inside the current selection, matching video. Reaching the selection's end makes the next Play start at its beginning. Changing the range starts at the new beginning; a stale player clock or canceled seek must not replace that position. Preserve seek generation guards, end bounds, timeouts and cleanup on dismissal.

In both media editors, committing an unchanged valid time field while moving focus preserves playback state and position. Invalid text still pauses; a genuine range change follows the existing audio-start or video-edge preview behavior. Explicit Reset remains a separate action.

Verify audio pause/resume and invalid-range reset through real production controls in English and Turkish, with a separate long WAV fixture staged before XCTest. Check the actual playback position, retained output format, source bytes and absence of published output after cancellation. Real-player model tests cover end restart, range changes, canceled seeks and reuse; no production test hook is needed.

### Product language and result messages

Keep ordinary explanations in sentence case and use the existing action vocabulary. Empty states explain the next available action. A sample image is shown in Finder; do not describe that action as opening the image itself. Routine guidance stays concise and keeps its actual limits and recovery steps.

Known merge and trim failures are presented in the selected application language. Match a complete controlled diagnostic and its error category. A merge filename must belong to the actual request, including a resolved source name when applicable; names containing colons or Turkish characters remain intact. Preserve unknown, extended and system diagnostics, and keep core/CLI error contracts unchanged.

Playback failures distinguish controlled app messages from actual AVFoundation diagnostics. Render the controlled failure in the current language without changing playback, timeouts, generation checks or seek cleanup. The shared video-crop playback consumer uses the same presentation.

Activity describes the actual result: moved/copied **items** for transfers, **new files** for conversion outputs, and plain **Completed / Tamamlandı** for report-only work. Word-count reports retain their complete filenames and measured counts. Localize only a complete known report in input order; never replace unit words inside arbitrary report text or filenames. Use the selected locale for counts and preserve the English fallback for other language values.

Known PDF and media completion notes retain password-removal, links/bookmarks/forms/signatures, PCM/AAC encoding and timing qualifications. Match these notes only within their corresponding editor options. Activity messages remain stored as rendered text; changing language later does not rewrite historical messages.

## Verification Before Release

Run the current **48-case native suite** for this candidate. It retains the WAV source default, manual output-format choice and cancellation path. The PDF cancellation cases capture the organizer and English/Turkish merge editor with help collapsed and expanded; those must be genuine captures of the running candidate. The video field-focus case verifies that transferring focus between unchanged time fields preserves a paused preview.

The ten language cases cover English/Turkish malformed merge recovery with a long filename, empty audio/video recovery, a real word-count report and a real file move. Require the observed localized text, usable cancellation, retained input bytes or the intended move, and the absence of unintended output. Inspect the corresponding screenshots and accessibility trees. Model checks exercise controlled error contracts, filename-safe fallback, source changes, real PDF completion warnings and report-only results.

The expanded-help capture requires the explanation to be visible and hittable before checking the page positions and footer. Keep accessibility snapshots from before and after the disclosure click. A screenshot's attachment name or reachable footer alone does not establish that help expanded.

Review the changed flows in English and Turkish, including long conversion descriptions, engine-required help and format/engine search. Confirm PDF position edits, invalid values, Enter/Esc, selection and cancellation retain their established behavior. Inspect the native captures at their intended size, with attention to the expanded disclosure and two-line operation descriptions.

Record actual CI results and candidate capture provenance when available. Public screenshots and download references continue to describe the verified public app until their replacements have been checked.

## PDF Failure Messages And Output Actions

Known PDF organizer failures show their cause and recovery advice in the selected application language. Match the controlled diagnostics exactly in the app presentation layer; preserve core/CLI error cases, unknown diagnostics and cancellation behavior. A malformed PDF should not expose the private preview filename as the user's document. Keep unreadable, oversized, password-protected, permission-restricted and changed-source failures distinct.

Result-card and Activity filename buttons retain their Finder reveal behavior. Their localized help and accessibility labels include the full filename and the action, following the existing file shelf. Preserve the visible filename, drag support and layout. The organizer's Turkish context menu uses **Sıra numarasını değiştir…** alongside its **Sıra** field.

The PDF-result native cases cover English/Turkish malformed-PDF recovery, destination-picker cancellation with order and undo history retained, and a Turkish edit/export/result-card/Finder flow. The Finder case requires the exact UUID-named output image to be selected, its original sibling to remain unselected, and exactly one file image selected in the expected folder window. Only the production result action may reveal or select the file. Retain result/error/editor screenshots, a full-screen Finder capture, accessibility trees and a receipt separating the expected output path from the observed Finder selection identity. This verifies Finder selection, not clipboard transfer. Model tests also exercise real missing, oversized, locked and copying-restricted PDF failures and source-fingerprint validation.
