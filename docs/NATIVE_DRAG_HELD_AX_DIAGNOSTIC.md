# Held-drag accessibility observation diagnostic (D12)

D12 tests whether the observer's accessibility reads while a drag is held are
necessary for the target activation and Escape cancellation failure. It uses
the existing native AppKit source and plain `NSWindow` control destination.
It does not change Lemulip or satisfy PR #45's production acceptance gate.

## Evidence and question

[D11 R4](https://github.com/osmankaankars/lemulip/actions/runs/42119583755)
completed four fixed cases on each architecture. ARM passed all four; Intel
passed two and failed cancellation in two. The failed Intel `no-raise-first`
case made no observer target AXRaise requests, yet the target became active/key,
received Escape and accepted the first session after release. The source ended
that session with `.copy`. Removing target AXRaise was not a reliable remedy.

In those two Intel failures, the target's activation receipts overlap the
`02-leave-file-area` AX observation. This is a reason to isolate observation,
not evidence that an attribute getter initiated activation. Earlier
[D11 R2 ARM evidence](https://github.com/osmankaankars/lemulip/actions/runs/42116433788)
also includes activation during a pause. No particular AX attribute,
AppKit hover mechanism or operating-system defect is established.

The narrow hypothesis is:

> Observer AX reads between mouse-down and mouse-up are necessary for the
> activation and first-session acceptance after Escape in this protocol.

A quiet-arm activation and cancellation failure would falsify that necessity
claim. A clean contrast would support dependence on this observation protocol,
but would not identify the internal activation path or justify a product fix.
Any necessity conclusion is limited to D12's fixed observation schedule. A
failure without held AX reads here would not establish that those reads were
irrelevant at D11's original timing.

## Fixed comparison

| Order | Case | AX reads while the mouse is held | Target AXRaise |
| --- | --- | --- | --- |
| 1 | `ax-read-first` | Performed | Present |
| 2 | `ax-quiet-first` | Omitted and recorded | Present |
| 3 | `ax-quiet-second` | Omitted and recorded | Present |
| 4 | `ax-read-second` | Performed | Present |

All four cases use one staged observer, source, control, fixture set and path
layout in the same CI session. Each architecture runs its own fixed sequence.
The source is the native copy-only AppKit source; the destination remains the
plain window without an accessibility override. Both arms retain the existing
setup raises, source activation, global input route, flags, coordinates and
Escape protocol. There is no focus correction while the mouse is held.

The intervention covers intermediate captures and Escape observations, including
workspace and focused-element AX queries. Explicit observer guards and a read
ledger distinguish performed reads from deliberate omissions. Quiet records
are observation omissions, never fabricated workspace or focus values. Initial
identity, geometry and hit checks still run before input, and strict workspace
checks resume after release. Non-AX process ownership checks remain required.

Both arms allocate the same **0.25-second observation slots** and retain the
same record-writing steps. Retained D11 measurements of individual observation
work and combined post-key work peaked at approximately **0.169 seconds**.
The 0.25-second budget provides bounded headroom, declared before new execution;
there is no duration sweep or retry to optimize the outcome.

A read or write that exceeds its work budget makes the comparison incomplete
and stops further input; a later phase is not shortened to conceal an overrun.
Actual slot completion overshoot is reported separately from operation time,
with start, scheduled-end, finish and input-post clocks retained. The common
nominal budget does not imply exactly equal elapsed schedules. This schedule
is a new diagnostic control, not timing equivalence with D11. No screenshots
are taken. Existing AX, event-post and screen-capture permission preflights
remain unchanged; no permission is requested, granted or bypassed.

## Evidence and strict outcomes

Buffered source and target activation journals, receiver callbacks and the
observer's post receipts remain separate evidence sources. The comparator must
bind them to the same application identities, fixtures, case, source hashes
and session numbers. A foreground snapshot is not substituted for a local
Escape-delivery receipt, and a later `currentEvent` is not a causal trace.

The following requirements apply equally to both arms:

- Start with exactly `Existing`, selected, and unchanged original fixture bytes.
- Establish a real native source session; retain destination entry, exit and
  reentry evidence for the same session before Escape.
- After Escape and release, require only `Existing`. First-session acceptance
  remains a cancellation failure even if activation was observed as predicted.
- After successful cancellation, perform a separate fresh drag. It must add
  `Single` exactly once and match the receiver acceptance and source `.copy`
  completion for that new session.
- Preserve original bytes, input inventories, source/target ownership and
  geometry. Finish cleanup, release the button and empty owned application
  registries before proceeding to another case.

A source `.none` completion after release leaves the exact cancellation time
indeterminate; it does not replace the workspace and fresh-drop assertions.
Missing held AX snapshots in the quiet arm are intentional coverage omissions,
not proof of the intermediate selection state. Passive receipts and the strict
postrelease checks provide that arm's independent gesture evidence.

| Observed result | Permitted conclusion |
| --- | --- |
| A verified quiet arm activates and accepts the first session | Held-drag observer AX reads are not necessary for that failure under D12's schedule; their role at D11's timing remains unresolved |
| Read arms activate/fail and quiet arms remain source-active and pass both gestures | Supports dependence on the observation protocol in these fixed cases; does not identify a particular read or system mechanism |
| Mixed results or no activation contrast | Preserve each result; the mechanism remains unresolved |
| An unexpected quiet-arm AX read, slot overrun, invalid ownership, changed input or incomplete cleanup | Comparison is incomplete; stop further input and retain the failure |

The workflow still fails for a native cancellation failure, even when that
failure usefully falsifies the hypothesis. There are exactly four serial cases
per architecture and no replacement trials or retries to obtain a green run.

## Isolation and verification

The experiment starts from D11 R4 commit
`4f894c73979a3edab0ea067064cf1f2988f32b6f` on the separate
`codex/drag-held-ax-comparison-07` branch. Product `Sources`, `Resources`,
`Package.swift`, build/staging scripts and the unpublished C13 candidate remain
outside this change. C12 is built only to prepare the existing staging layout:

- Commit: `d821d7343675e2850705d141ef9b3b93a6aee945`.
- Tree: `425baa28f00ec24551dd70c0cc874a75fa3be0c1`.

The dedicated `native-drag-held-ax-comparison.yml` workflow runs portable
comparison checks, builds the observer/control/source on Apple Silicon and
Intel, and executes the bounded cases. It retains source and executable hashes,
the comparator hash, provenance, raw reports, journals, inventories and logs.
The unchanged C12 full acceptance suite is not rerun for this diagnostic, and
no input is sent to the production application.

Local verification commands:

```bash
python3 -m unittest discover -s script -p 'test_compare_native_drag*.py'
python3 script/privacy_check.py --staged
git diff --check
```

The local Linux executor cannot run AppKit. A native outcome must come from the
retained macOS run and its verified case bindings. Until then, D12 is a prepared
experiment. `diagnosticOnly` remains true; `releaseReady`,
`nativeAcceptanceXCTestExecuted` and `physicalInputVerified` remain false.
PR #45 remains **C12 HOLD**. The owner's completed physical and v4 automated
checks are preserved; this experiment requires no new owner repetition.
