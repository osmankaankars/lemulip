# Native drag activation diagnostic (D11)

This experiment investigates the activation observed in D10. It does not change
the product or provide release acceptance. PR #45 remains **C12 HOLD** until its
actual production acceptance requirements are satisfied.

## Evidence and hypothesis

[D10 run 42098162755](https://github.com/osmankaankars/lemulip/actions/runs/42098162755)
used a standard AppKit destination and compared Finder with a copy-only native
AppKit source. Both native-source Intel cases and the second native-source ARM
case accepted the first drag after Escape and mouse release. The first native
ARM case passed cancellation and a separate normal drop. Target-local receipts
showed activation and Escape delivery in the failed cases. The native source
also reported a `.copy` completion matching the accepted destination sequence.

Those records establish a meaningful failure before this change. They do not
identify the activation's cause. In particular, one observer foreground sample
still named the source after the source and target had locally reported the
activation transfer. A `currentEvent` value in a later callback can also be
stale; it is not a causal stack trace.

The observer raises its verified target window at four setup points before the
first native drag. Apple's
[accessibilityPerformRaise documentation](https://developer.apple.com/documentation/appkit/nsaccessibilityprotocol/accessibilityperformraise())
describes title-bar-click behavior and says the return value acknowledges that
the action was triggered, rather than proving completion. The falsifiable
hypothesis is therefore:

> The observer's target-window AXRaise requests are necessary for the later
> target activation and cancellation failure in this fixed native-source
> protocol.

The alternative is that the activation and failure can occur without those
requests. Target startup activation and initial fixture opening are common to
both arms; this is not a test that removes every possible activation request.

## Fixed intervention

| Order | Case | Observer target AXRaise | Source |
| --- | --- | --- | --- |
| 1 | `raise-first` | Present | Native AppKit |
| 2 | `no-raise-first` | Omitted at every target call site | Native AppKit |
| 3 | `no-raise-second` | Omitted at every target call site | Native AppKit |
| 4 | `raise-second` | Present | Native AppKit |

All four cases use the same built control window and drop view, source,
observer, fixtures, permissions, geometry and nominal input sequence. The
target remains a normal `NSWindow`; no panel policy is introduced. Both arms
receive the same passive instrumentation. Source activation and source-window
AXRaise remain at their original setup call sites. No focus correction occurs
while the drag is held.

The observer records all target-raise decisions, including omissions. The first
gesture requires three `focus-finder` decisions followed by one
`focus-native-source` decision. A successful cancellation and its fresh-drop
continuation add one further `focus-native-source` decision. Each record binds
the target PID and window title, phase, index, policy, actual action status,
entry/return clocks and the absence of an observer-held mouse button. An
omission is represented by `performed: false` and a null action status, not by
a missing record.

Existing source foreground, window identity, geometry and pointer-hit checks
remain required. An occluded target or changed geometry blocks the comparison;
the no-raise arm must not repair that condition by raising the target.

## Passive evidence and its limits

The target keeps its existing receiver trace and adds a bounded, exclusively
created `activation.jsonl` journal. New activation evidence is buffered during
the interaction and flushed at lifecycle boundaries. It records target AXRaise
handler entry/return, AppKit-defined event dispatch, local application active
state, key/main-window changes and narrowly scoped delivered mouse metadata.
Overrides always forward to AppKit. Event subtype is read only for
`.appKitDefined`, never indiscriminately for keyboard or mouse events.

The source adds local key/main-window receipts to its existing buffered trace.
The observer's target-raise ledger also stays in memory until the normal report
write. No global input monitor, new keyboard handler, screenshot capture,
spring-loading conformance or private activation API is introduced.

The target's `accessibilityPerformRaise` override is an observation point, not
a guarantee that every system raise or activation passes through that method.
An absent callback cannot prove nondelivery. An unexpected callback in an
omitted arm must remain visible in the interpretation. AppKit-defined event
metadata and activation notifications do not identify an external requesting
process. Neither a stale `currentEvent` nor a foreground snapshot is used as
proof of origin.

## Acceptance and interpretation

Strict native outcomes remain separate from the activation hypothesis:

- Exact original fixture bytes and initial `Existing` selection are required.
- The native source must begin a real session matching the destination sequence.
- The same held gesture must enter, exit and reenter with copy eligibility
  before Escape. Posted input types, flags, coordinates and clocks are retained.
- A cancellation PASS must leave only `Existing`, then complete a distinct
  fresh drag that adds `Single`, with matching receiver acceptance and source
  `.copy` completion.
- A `.none` source completion after release remains indeterminate about the
  precise cancellation time. It does not override the strict AX outcome.
- Inventories, fixture bytes, source/target identities and geometry remain
  checked. Complete cleanup and empty owned application registries are required
  before any subsequent case.

| Observed pattern | Supported interpretation |
| --- | --- |
| Raised arms activate/fail; omitted arms stay source-active and cancel, then pass fresh drop | Supports dependence on observer target-raise behavior in this protocol; does not identify an internal macOS delay mechanism |
| An omitted arm still activates and accepts the first session after Escape/release | Observer target AXRaise is not necessary for that observed failure |
| Omitted arms fail while target application activation is absent | Activation alone is insufficient to explain the result; key ownership still needs examination |
| Mixed outcomes, missing activation contrast, or incomplete passive receipts | Preserve each native result and state the remaining uncertainty |
| Changed geometry, invalid ownership, changed inputs or incomplete cleanup | Stop further input and report the comparison as incomplete |

Actual elapsed times can vary with scheduling. The experiment preserves the
requested protocol and reports actual clocks; it does not claim identical
timing. There are exactly four serial cases per architecture, with no
activation-dependent waiting, timing tuning or retry for a passing result.

## Isolation and verification record

The diagnostic starts from D10 commit
`c4028f24af2af5693c8609dc71dc31a38276c6d1` in a clean, separate worktree and branch.
There were no dirty paths in that worktree before mutation. Planned changes are
restricted to the diagnostic observer/control/source, explicit comparator
allowlist reuse, the new comparator/tests/workflow and this document. Product
`Sources`, `Resources`, `Package.swift`, build/staging scripts and the unpublished
C13 candidate are outside the change scope.

The local executor cannot execute AppKit. D10 supplies the observed red signal;
the proof plan is targeted portable validation followed by one fixed ARM64 and
Intel native CI comparison, retaining every result. CI builds the pinned C12
product solely to prepare the existing stage; it sends no input to the product.
The product baseline remains commit
`d821d7343675e2850705d141ef9b3b93a6aee945`, tree
`425baa28f00ec24551dd70c0cc874a75fa3be0c1`.

Run the portable diagnostic checks before publication:

```bash
python3 -m unittest discover -s script -p 'test_compare_native_drag*.py'
python3 script/privacy_check.py --staged
git diff --check
```

The dedicated `native-drag-activation-comparison.yml` workflow builds both
architectures, runs the fixed cases and uploads reports, traces, inventories,
provenance and logs. It fails if a required native case fails, even when that
failure usefully falsifies the hypothesis. `diagnosticOnly` stays true;
`releaseReady`, `nativeAcceptanceXCTestExecuted` and `physicalInputVerified`
stay false.

Next evidence checkpoint: independently verify artifact hashes and native
case/trace bindings, compare the two arms, and update the investigation record
with the observed result and its limits. A diagnostic result alone does not
authorize a production fix or PR merge.
