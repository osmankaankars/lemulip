# Held-drag accessibility observation diagnostic (D12)

D12 tests whether the observer's accessibility reads while a drag is held are
necessary for the target activation and Escape cancellation failure. It uses
the existing native AppKit source and plain `NSWindow` control destination.
It does not change Lemulip or satisfy PR #45's production acceptance gate.

**Executed on 2026-11-06:** the fixed four-case sequence completed on Apple
Silicon and Intel. All eight cases failed Escape cancellation, including all
four quiet cases with zero observer AX reads while the mouse was held. The
failure therefore does not require those reads under D12's schedule. This is
a diagnostic finding, not a repair. PR #45 remains **C12 HOLD**.

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

The local Linux executor cannot run AppKit. The native outcomes below come from
the retained macOS run and its verified case bindings. `diagnosticOnly` remains
true; `releaseReady`,
`nativeAcceptanceXCTestExecuted` and `physicalInputVerified` remain false.
PR #45 remains **C12 HOLD**. The owner's completed physical and v4 automated
checks are preserved; this experiment requires no new owner repetition.

## Executed results and retained evidence

The sole D12 run is
[42285379647](https://github.com/osmankaankars/lemulip/actions/runs/42285379647).
It executed commit
[`7c52f7b102ba7160622a8fba742c1d832b7e1af1`](https://github.com/osmankaankars/lemulip/commit/7c52f7b102ba7160622a8fba742c1d832b7e1af1),
tree `e7abbe9793c313165ded360c64cd3179e1abc536`. Subsequent documentation commits
are not the tested executable revision.

Both jobs built the unchanged C12 application and the observer, native control
and native source successfully. Their portable checks passed: 49 comparison
tests, 12 release/coverage/staging checks and the privacy check. Each job failed
only at the four-case native comparison step; source-preservation and evidence
upload steps completed successfully. There were no replacement trials.

| Fixed case order | Held AX reads, ARM / Intel | ARM cancellation | Intel cancellation |
| --- | --- | --- | --- |
| `ax-read-first` | 404 / 404 | Failed | Failed |
| `ax-quiet-first` | 0 / 0 | Failed | Failed |
| `ax-quiet-second` | 0 / 0 | Failed | Failed |
| `ax-read-second` | 404 / 404 | Failed | Failed |

All eight cases have `escape-cancellation-failed`, with the first source
session classified as `accepted-after-release`. Each target became active
while the drag was held, received Escape, and then accepted that same first
session after mouse release. The source recorded `.copy`. The postrelease
workspace contained `Existing` and `Single`, violating the requirement that
only `Existing` remain. All four quiet cases have empty held-read journals,
zero guard violations, and explicit omissions for held AX snapshots and focus
observations. No case reached the separate fresh-drop stage, because its
preceding cancellation assertion failed.

Both reports have `comparisonComplete=true`, unchanged recorded input
inventories and complete cleanup in all four cases. No case was incomplete,
incomparable or skipped. Operation time remained within the declared 250 ms
budget in all 48 slots. Actual scheduling overshoot was retained separately:

| Timing measurement | Apple Silicon (`arm64`) | Intel (`x86_64`) |
| --- | --- | --- |
| Largest observation operation | 19.161 ms | 63.372 ms |
| Actual slot duration range | 250.769–263.144 ms | 250.706–323.811 ms |
| Largest wake overshoot beyond 250 ms | 13.144 ms | 73.811 ms |

The nominal slot budget was common; actual elapsed timings were not identical.
In particular, these results must not be presented as timing equivalence with
D11 or as evidence for a particular hover threshold.

### Artifact identity and replay

| Architecture | Job | Artifact ID | ZIP bytes | Uncompressed files / bytes |
| --- | --- | --- | --- | --- |
| `arm64` | [128124716644](https://github.com/osmankaankars/lemulip/actions/runs/42285379647/job/128124716644) | `13537207194` | 181,125 | 56 / 1,878,089 |
| `x86_64` | [128124716153](https://github.com/osmankaankars/lemulip/actions/runs/42285379647/job/128124716153) | `13537497128` | 188,563 | 56 / 2,010,370 |

Downloaded ZIP SHA-256 values, verified against GitHub's artifact metadata:

- `arm64`: `dd6a6e251449f8c8fd90fbf5cc5ab7efc492d5948197b592e92c05790a132455`
- `x86_64`: `5e9a79ce732ff22920974e8308e6fcb3163d870c388881ad14de2560dd44e89d`

A read-only local audit loaded the exact published classifiers from the tested
commit and replayed all eight cases with exact classification-field equality.
Aggregate interpretations also matched. For each architecture, the audit
verified the three Swift source hashes and comparator hash, five recorded
executable inventory links, 118 matching before/after inventory entries, and
28 standalone snapshots against their embedded report copies. All 56 extracted
files per architecture remained byte-for-byte unchanged during the audit.
ZIP sizes, digests, CRCs and safe extraction paths were also checked.

The archives retain binary and fixture hashes, not the corresponding binary
and fixture bytes. Those preservation checks are therefore limited to the
recorded inventory links and receipts. Replay did not rerun native input,
permissions or the original live preflight. An audit pass means agreement with
the retained evidence; it does not mean the native cancellation gate passed.

### Decision and remaining question

The four verified quiet-case failures falsify the claim that observer AX reads
while the drag is held are necessary for the activation and cancellation
failure **under D12's fixed schedule**. They do not establish that these reads
had no effect at D11's original timing, nor do they identify the operating
system's activation initiator. Pre-drag AX work, the common target raise,
source/receiver instrumentation and the global synthetic input route remain
part of this experiment.

The unresolved question is why global synthetic Escape reaches the activated
destination while the source drag remains live and is accepted on release.
The receipts establish that sequence, not its internal cause. There is no
supported product correction in D12, and no basis to waive the existing
cancellation assertion, force focus, target Escape to a process, or retune the
timing until a run passes.

PR #45 stays draft/open at C12 commit
`d821d7343675e2850705d141ef9b3b93a6aee945`; `main` remains
`ade8b1673de0c2dff930430564c17f100f5e807b`. The unpublished C13 worktree was not
modified. The completed owner tests remain valid evidence and need no repeat.
