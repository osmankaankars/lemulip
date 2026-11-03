# Native App Refinement Brief

Updated 3 November 2026.

**Status:** unreleased PDF feedback refinement based on `17e1b7d`, following [PR #39](https://github.com/osmankaankars/lemulip/pull/39). The public app reference is **0.1.20, build 23**. Candidate checks and native captures establish the new behavior; existing public screenshots do not establish this refinement's appearance or behavior.

Read this with [DESIGN.md](DESIGN.md) for the shared identity and [WEBSITE.md](WEBSITE.md) for the separately scoped website. This brief records the current native refinement so later work can continue from the same decisions.

## Purpose And Protected Behavior

The app is **Operate**: help someone finish a file task with familiar Mac controls. Use precise labels, useful defaults and short explanations at the moment they matter. Keep the genuine icon, platform typography, Orchard/Pistachio/Lemonade themes and operation wheel. Preserve stable operation and accessibility identifiers, keyboard behavior, selection identity, undo, output-copy behavior and support-installation paths.

Use the pinned research snapshots in [Website Reference Roles](WEBSITE.md#reference-roles): **UI/UX Pro Max** informs task planning and hierarchy; **Taste** informs composition within Lemulip's established identity; **Impeccable** directs clarity and a bounded native quality review; **Jakub Krehel** informs labels, wrapping, focus and final interaction details. These roles guide the work without changing its native stack or introducing new runtime dependencies.

## Current Candidate

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

## Verification Before Release

Run the current **34-case native suite** for this candidate. It retains the WAV source default, manual output-format choice and cancellation path. The existing PDF cancellation case captures the organizer with help collapsed and expanded; those must be genuine captures of the running candidate.

The expanded-help capture requires the explanation to be visible and hittable before checking the page positions and footer. Keep accessibility snapshots from before and after the disclosure click. A screenshot's attachment name or reachable footer alone does not establish that help expanded.

Review the changed flows in English and Turkish, including long conversion descriptions, engine-required help and format/engine search. Confirm PDF position edits, invalid values, Enter/Esc, selection and cancellation retain their established behavior. Inspect the native captures at their intended size, with attention to the expanded disclosure and two-line operation descriptions.

Record actual CI results and candidate capture provenance when available. Public screenshots and download references continue to describe the verified public app until their replacements have been checked.

## PDF Failure Messages And Output Actions

Known PDF organizer failures show their cause and recovery advice in the selected application language. Match the controlled diagnostics exactly in the app presentation layer; preserve core/CLI error cases, unknown diagnostics and cancellation behavior. A malformed PDF should not expose the private preview filename as the user's document. Keep unreadable, oversized, password-protected, permission-restricted and changed-source failures distinct.

Result-card and Activity filename buttons retain their Finder reveal behavior. Their localized help and accessibility labels include the full filename and the action, following the existing file shelf. Preserve the visible filename, drag support and layout. The organizer's Turkish context menu uses **Sıra numarasını değiştir…** alongside its **Sıra** field.

The four added native cases cover English/Turkish malformed-PDF recovery, destination-picker cancellation with order and undo history retained, and a Turkish edit/export/result-card/Finder flow. The Finder case requires the exact UUID-named output image to be selected, its original sibling to remain unselected, and exactly one file image selected in the expected folder window. Only the production result action may reveal or select the file. Retain result/error/editor screenshots, a full-screen Finder capture, accessibility trees and a receipt separating the expected output path from the observed Finder selection identity. This verifies Finder selection, not clipboard transfer. Model tests also exercise real missing, oversized, locked and copying-restricted PDF failures and source-fingerprint validation.
