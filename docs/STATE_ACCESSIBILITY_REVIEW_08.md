# State And Accessibility Final Review: Open

## Evidence reviewed on 6 November 2026 UTC

Task 08 remains open because task 07's held Finder drag cancellation gate has
not passed. This review completes a bounded, independent check of retained C12
visual evidence. It does not approve a merge or release.

The candidate is [PR #45](https://github.com/osmankaankars/lemulip/pull/45), head
`d821d7343675e2850705d141ef9b3b93a6aee945`, tree
`425baa28f00ec24551dd70c0cc874a75fa3be0c1`. The reviewed artifacts come from
[run 41803346911](https://github.com/osmankaankars/lemulip/actions/runs/41803346911).
Their provenance records the CI merge commit
`3736b791f48b5a7bdaa2a752297c9cebeab64cce` and the same candidate tree.
The StateAccessibilityUITests, DisplayAccessibilityUITests and NativeDragReview
source hashes match the pinned C12 source files.

Both downloaded archives passed their advertised byte count, SHA-256 and ZIP
CRC checks. Extraction rejected absolute paths, traversal and symlinks. Each
archive contains 1,599 entries. Each retained XCResult database contains exactly
58 test-case runs, all with result `Success`.

| Architecture | Artifact ID | ZIP bytes | SHA-256 |
| --- | --- | ---: | --- |
| arm64 | 13310237143 | 59,800,674 | `296450189a018761fbd53eb181aedfb3140874d0f609d661f7c31d14946120ca` |
| x86_64 | 13310193645 | 82,837,525 | `f4954bbc586f402b2193226b2535871c951e6ea9aabb693426a01c22b9202c64` |

## Production source review

The C12 production diff against main
`ade8b1673de0c2dff930430564c17f100f5e807b` contains three focused changes:

- The visible result panel is repositioned after content resizing to fit its
  current display's visible area. This path does not activate the application or
  take keyboard focus.
- The interactive audio waveform and video timeline explicitly report their
  enabled state through accessibility.
- Video timeline S/E/P selection commands ignore key-repeat events; arrow-key
  adjustment still repeats.

The independent source review found no additional concrete blocker in that
production diff. It is separate from native execution and from the still-open
drag observer failure. D13 and D14 change only diagnostic infrastructure and leave
these production sources byte-for-byte equal to C12.

## Selected visual observations

The following twelve original PNG attachments were opened individually. The
names and UUIDs were joined through the retained XCResult database, rather
than inferred from the screenshot contents. The images themselves were not
edited or regenerated.

| Architecture | Retained state | Attachment UUID | Observation |
| --- | --- | --- | --- |
| arm64 | Orchard TR minimum workspace | `EF9A37C4-1FE8-4417-A571-34FD68CDF648` | Two selected files, long-name truncation, row actions and workspace controls fit the narrow window. |
| arm64 | Pistachio EN audio keyboard and focus | `0BEEA993-288F-4697-9E68-2BF5D9E77F41` | Waveform focus outline, selected range, time fields and footer actions are visible. |
| arm64 | Lemonade TR video keyboard and focus | `B25FF976-A98D-4244-8E8F-CCA37058D4DD` | Timeline focus outline, selection handles, time fields and primary action are visible above the Dock. |
| arm64 | AccessibilityMotion result card | `10061F34-237B-4657-9D8D-EEF1A2E4174C` | The complete card, wrapped output filename and three output actions fit above the Dock. |
| arm64 | Lemonade EN minimum workspace | `EC728D79-636D-4B08-9CD1-11F829796DF4` | The light theme preserves the same narrow-window file-row controls and long-name truncation. |
| arm64 | Pistachio TR long PDF recovery | `910AC512-482C-46FF-926B-15C2ECB69049` | The full recovery message and long filename wrap within the editor; Cancel remains visible and Create Copy is disabled. |
| arm64 | Orchard TR PDF field Escape restores position | `5B445697-16EA-4E77-ACCA-7AFBB8FEE9A0` | Position 1, selected page, collection focus indication and footer actions are visible. Behavior is established by the corresponding test, not by the still image alone. |
| arm64 | Turkish result card before Finder action | `1D2687A7-C148-46E0-97E8-E42FCB6D1AA4` | Turkish result text, wrapped filename and Finder/Copy/Float actions fit above the Dock. |
| x86_64 | Orchard EN PDF invalid position | `4207539F-E2B6-4018-AF87-63D34888DE5F` | The invalid position value has focus and a warning indicator; Create Copy is disabled and Cancel remains available. |
| x86_64 | Pistachio TR audio keyboard and focus | `0834F69E-7E5A-4593-ABC8-27C8F29C1732` | The Turkish audio editor preserves the focus outline, selected range, time fields and footer controls. |
| x86_64 | Lemonade EN video keyboard and focus | `4DCC0F8D-F2DF-433E-9872-D67E6AABF450` | The English video editor preserves the focused timeline, selection and output controls. |
| x86_64 | AccessibilityTransparency result card | `F07716BF-9FB2-46C4-B83B-6F469CC1EBAF` | The complete result card and output actions remain visible above the Dock at the Intel runner's display size. |

No new blocking visual defect was identified in these selected frames. This is
not an exhaustive review of every retained attachment. The static images do
not establish animation quality, audio playback quality, VoiceOver behavior or
the timing of an in-flight drag.

## Remaining acceptance work

The native drag recording step in the same C12 run failed cancellation in all
three themes on both architectures: `Escape did not cancel the actual Finder
drag`. The 58 successful XCTest cases do not override that separate failure.

The [D12 held AX comparison](NATIVE_DRAG_HELD_AX_DIAGNOSTIC.md),
[D13 mouse producer comparison](NATIVE_DRAG_MOUSE_DRIVER_DIAGNOSTIC.md) and
[D14 event-origin observations](NATIVE_DRAG_EVENT_ORIGIN_DIAGNOSTIC.md) are
diagnostic work. Their scope and results must remain separate from the original
enter, exit, reenter, Escape, release and fresh-drop acceptance sequence.

D14 R2 added no production change. ARM had four comparable cancellation failures;
Intel had one strict diagnostic pass, one incomplete cleanup and two unrun cases.
The added event metadata and selected system logs did not establish the upstream
held-activation request. These results do not close the original gate.

To complete task 08, close or explicitly resolve task 07's remaining CI gate on
the final candidate, review any resulting production changes, and retain the
final source/run/artifact identity. The candidate is still on hold.
