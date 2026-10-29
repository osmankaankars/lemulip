# Native Editor Review

Q1 review, 29 October 2026. Lemulip's editor should keep the source and pending copy easy to distinguish: choose a range, crop or order, review it, then create one new copy. A cancelled destination choice must return to that same work. The shared footer, compact preview/inspector layout, theme roles and direct keyboard controls remain the basis of the interface.

## First Patch: Destination Continuity

When **Save Beside The Original** is off, **Create Copy** resolves the destination before dismissing the editor. Cancelling the folder picker keeps the pending operation, inputs and selection-sound choice. It creates no Activity item or cue. Confirming a later choice queues one job and emits at most one optional cue. A repeated confirmation cannot open a second picker or submit an editor that was cancelled during the modal interaction.

Audio and video pause while choosing a destination. Their previews and selections remain available on return. Crop, trim and PDF editors release their resources when their view disappears after final acceptance or editor cancellation.

## Scenario Matrix

Run keyboard and content checks in English and Turkish. Review Orchard Night, Vivid Pistachio and Lemon Drop at normal window size and on the smallest supported desktop that can contain the editor. A successful build alone does not establish these visual and interaction results.

| Scenario | Expected result | Evidence required |
| --- | --- | --- |
| Image crop → Create Copy → cancel destination → arrow adjustment → accept | Same native canvas and crop remain; arrow adjustment is exported once; source bytes unchanged | Controller/output regression and hosted production-crop test; exact-head capture |
| Resize/options → cancel destination → cancel editor | Pending operation clears only on the final Cancel; no job or sound | Controller regression; native keyboard check |
| Audio trim with a non-default range → cancel destination | Playback pauses, range and output format remain; Play Selection works again | Native interaction check with a real decoded audio fixture |
| Video trim and video crop → cancel destination | Preview, crop/range and format remain; playback can resume; acceptance uses retained values | Native interaction check with a decoded video fixture |
| Organize PDF after move/rotate/remove; Extract Selected | Destination cancellation retains arrangement, selection and undo history; later export matches displayed order | PDF branch ordering tests plus native destination-cancel check |
| Merge PDF after moving multiple documents | Retained documents, page ranges and undo history remain after destination cancellation | PDF branch ordering tests plus native destination-cancel check |
| Cancel during preview loading; reopen a different input | Old worker/playback stops; no old preview replaces the new input | Native loading/cancellation check |
| Unsupported, empty, encrypted or failed preview | An actionable message is visible; Create Copy is unavailable when required; Cancel remains reachable | Actual error-state captures |
| Invalid dimensions/times/position, then correction | Error explains the accepted range; no export while invalid; corrected controls work | Native field/keyboard check; PDF position tests |
| Tab/Shift-Tab, arrows, Return, Escape | Visible focus follows the control; text entry keeps its own editing keys; default/cancel actions have the stated effect | Native keyboard checks and PDF interaction tests |
| Options field and slider labels | Assistive technology names Quality, Playback Speed, Volume and text fields, with meaningful values | Accessibility review; follow-up patch |
| Wheel/result appearance with Reduce Motion and Reduce Transparency | Stable hit targets, no input delay, immediate dismissal, fully visible reused panel; accessibility preferences suppress optional fade | Separate motion patch and native panel reuse tests/capture |

## Evidence Boundaries

The four checked-in native website captures come from commit `f9496dd2c040a3a538bb4fea650355defcb7058d`, as recorded in `site/assets/screenshots.json`. They show the baseline Workspace, video crop, audio trim and Activity layouts. They do not establish the new PDF controls, current error states or new motion behavior.

`SelectionFeedbackTests` exercises the actual controller's destination responses, cancellation, exactly-once commitment and real image output. Its hosted crop test renders the production SwiftUI editor in a native AppKit window, seeds a synthetic crop through the canvas binding, then routes Return and arrow events only to that test window. The destination response is injected; the test does not automate the system folder chooser or establish physical drag usability.

When `LEMULIP_EDITOR_REVIEW_DIR` is set, the hosted test retains an unresized PNG and provenance containing the source commit, workflow run, native dimensions and backing scale. Build and Verify uploads these as `Lemulip-Editor-Review-<architecture>`. Inspect the exact-head artifact before marking the visual scenario passed. These fixtures are verification evidence, not promotional captures.
