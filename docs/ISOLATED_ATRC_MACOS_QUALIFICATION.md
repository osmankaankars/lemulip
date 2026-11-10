# D30 — Intel macOS qualification of the isolated output observer

D30 performs one finite platform qualification of the
[D29 isolated observer](NATIVE_RETAINED_ATRC_ISOLATED_OBSERVER.md) with
disposable synthetic output and actual macOS child/process-group APIs.
It supplies no existing trace and invokes no Apple import, export, recording,
sampler or GUI-input command.

## Recorded D30 result — qualification NOT RUN

The harness and portable verification are complete, but **the Intel macOS
qualification did not execute**. GitHub rejected the single job before
runner allocation because of an account-level job-start restriction.
The complete account-specific annotation is retained in private tracking
notes; the public evidence below records its retrieval and normalized cause.

| Evidence | Result |
| --- | --- |
| Source commit / tree | 7e85c070ba21810b3a2cc8c61943e083eba1d7c2 / 7510e367d048bbbf0e93a52323ecbc9ea5a17e74 |
| Workflow run / attempt | [42728821819](https://github.com/osmankaankars/lemulip/actions/runs/42728821819) / 1 |
| Job | [129541298010](https://github.com/osmankaankars/lemulip/actions/runs/42728821819/job/129541298010) |
| GitHub conclusion | failure; before runner allocation and before recorded steps |
| Job created / completed | 2026-11-10 00:30:29 / 00:30:33 UTC; scheduler metadata, not workload duration |
| Runner / recorded steps / artifact count | Unassigned / 0 / 0 |
| Native collector / macOS cases executed | 0 / 0; all six cases **NOT RUN** |
| Final local portable suite | **192 unique tests PASS**, zero failures/errors/skips |
| Before/after source identity | **113 files**, unchanged and matched to the published Git blobs |
| Overall platform result | **diagnostic-incomplete** |

The job log endpoint returned 404 BlobNotFound. No macOS interpreter
fingerprint, WNOWAIT/group preflight, case receipt, qualification report or
artifact ZIP exists for this attempt. There is therefore no native archive
or classification result to revalidate. A failed GitHub job and an
unexecuted qualification case are distinct outcomes.

The final 192 portable tests contain the existing 145 D29 tests and 47 D30
tests: 11 fixture, 7 pressure and 29 classifier methods. The same final
classifier suite rejected the retained earlier harness with 11 assertion
failures, then passed against the frozen published harness. Those repeated
subset executions are not added to the 192 total. One additional real
Python capture glue check passed with explicitly synthetic direct-child
process inventory; its archive payload/CRC/SHA and probe-construction
checks remain portable evidence only.

See [the retained CI result](evidence/D30-isolated-atrc-macos.json) and
[portable proof, source identities and classifier regression records](evidence/D30-verification.json).
Only this document and those two evidence files are changed by the result
follow-up; they are excluded from the workflow push paths.

**Next continuation: D31.** Resolve the evidenced account-level job-start
restriction, then run the same frozen source commit, Intel label, Python
selection, six cases and budgets once. Preserve this D30 failure and inspect
the resulting exact run/artifact before deciding whether platform
qualification is complete. This result supplies no reason to alter action
pins, runner architecture, budgets or qualification logic. No rerun or
account setting change was performed during D30.

## Frozen source and execution scope

- D29 base: **35e83645c036f90aa1678aca51ad2323d33044e4**
- D29 tree: **e147d3d924f644615dac7571599166746020b46d**
- D30 branch: **codex/isolated-atrc-macos-07**
- One **macos-15-intel** job, Python **3.13**, outer job limit eight minutes.
- D29 runtime, existing diagnostic workflows and product files remain frozen.
- C12/task 07/PR #45 remain HOLD; task 08's final dependency remains open.

The Intel label follows the D26/D27 environment and GitHub's current
[runner-label documentation](https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job).
No ARM result is implied. The dedicated workflow uses only its exact branch
and eight workflow/harness/fixture/test paths as push filters. Documentation
and evidence paths are excluded from subsequent runs. GitHub's
[trigger documentation](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow)
describes the combined branch/path filtering.

## Preflight and evidence boundaries

Before importing project dependencies, the collector binds the checkout
commit/tree, the D29 ancestor, an explicit new-path allowlist, all Python
source bytes and the selected interpreter executable. It requires a clean
checkout, non-root Intel Darwin and Python 3.13 or later. Source and interpreter
hashes are repeated at completion. The executable/version record does not
claim to pin every Python standard-library or framework byte.

The existing non-reaping preflight starts one tiny owned child, peeks at its
exit-23 status twice with WNOWAIT, then deliberately collects it. A real
**/bin/ps -A -o pid=,pgid=,stat=** preflight must parse, show the collector's real
PID/PGID, and complete its own retained-child/group cleanup. No synthetic
process inventory or fallback is permitted in the macOS qualification.

Each adapter case uses the unchanged D29 implementation. Constructor
instrumentation retains references to the actual OwnedCommand objects; it
does not replace OS transports, child-status calls, reports or group output.
At real group-probe construction, it records the existing owned-command
non-reaping terminal witness, retained Popen status and actual PGID. It does
not add a second wait-status consumer. Those observations must precede child
collection and fall inside the matching probe's spawn interval.

Qualification independently checks the **latest** real group snapshot. Each
held leader must appear exactly once with pid equal to pgid, a zombie state,
and no live same-group member. The raw group rows must match the retained
group receipt. An empty member list or an earlier safe snapshot cannot
substitute for this evidence.

Mutable observed roots and control files live in a separate fixture-work
directory outside the uploaded evidence directory. Only positively permitted
stable output is archived. Capture receipts and bounded streams are saved
before marker reading, retention or classification can fail. Unsafe output
roots are not recursively uploaded as evidence.

## Fixed case schedule

All six cases run at most once, in this order. An unexpected failure stops
the sequence and leaves later cases NOT RUN.

| Case | Controlled workload | Required platform evidence |
| --- | --- | --- |
| Success | Four fixed sub-kilobyte payloads in a small nested tree; 150 ms pause | Bound ready and empty initial census, an intervening census, a new post-operation final census, both retained leases/real groups, exact archive payload/CRC/SHA and preserved originals |
| Pending metadata / exit | Real worker emits operation-start; its fixture callback waits two seconds at stall.bin stat; target prints and exits zero after the marker | Target stdout and terminal observation occur inside the pending interval and before its 250 ms deadline; first failure remains, owned TERM/KILL-consistent worker termination and safe cleanup are recorded; retention is denied |
| Target deadline | Same pending metadata fixture; target has a fixed shortened test budget | Command-budget stop is observed inside the pending interval, with actual clocks/overshoot preserved; the observer cannot extend the target budget |
| Unsuccessful worker shutdown | Target finishes; worker acknowledges stopped, then returns seven | A completed final census and target exit zero do not authorize observation/retention after worker failure |
| Surviving descendant | Exactly one same-PGID child ignores TERM and closes inherited streams; leader exits zero after child readiness | Initial real ps contains the held zombie leader and live child; owned-group TERM then KILL, a safe latest group snapshot and collection follow; the original failed qualification remains sticky |
| Real report backpressure | Standalone unchanged worker scans 128 one-byte files using a deliberately small real socket buffer; parent withholds report reads after ready/request | One census request, actual required-write failure, natural exit two, ordered incomplete prefix and no completed scan; positive real owned-group cleanup |

The descendant never calls setsid, has a three-second natural lifetime and
is never addressed by an unleased numeric PID. Cleanup acts only through
the original directly owned leader's retained process group.

The pressure case starts with a populated root because it tests the worker
in isolation, not the adapter's initial-empty gate. Its ready message is
validated only after the existing OwnedCommand owns the child. Postmortem
prefix parsing does not claim that records were received before their live
deadline. The actual socket capacity, single request attempt and withheld
live-read count are retained.

## Budgets and stop conditions

| Boundary | Value |
| --- | --- |
| Ordinary synthetic target normal / total | 3 / 5 seconds |
| Deadline fixture normal / total | 0.15 / 0.5 seconds |
| Standalone pressure worker normal / total | 3 / 5 seconds |
| Worker startup / cleanup accounting | Unchanged 2 / 2 seconds |
| Census / requested cadence / poll / TERM grace | Unchanged 250 / 50 / 5 / 250 ms |
| Group probe / combined stream cap | Unchanged 2 seconds / 65,536 bytes |
| Message / undecoded buffer / parsed messages per tick | Unchanged 4,096 bytes / 65,536 bytes / 16 |
| Worker evidence / output accounting / final retention | Unchanged 8 MiB / 512 MiB logical and allocated / 30 seconds |
| Source snapshot | At most 256 files, 2 MiB per file and 16 MiB total |
| Pressure report retained bytes | At most 65,536 |
| Outer workflow | Eight minutes, one job, no automatic cancellation/retry |

Shortened target budgets are explicit synthetic test controls; the inherited
90/95-second native defaults are not changed. The finite target/worker/group
budget components fit well inside the outer job ceiling, while requested
polling and cooperative checks remain distinct from hard scheduler/kernel
guarantees.

A case's expected negative observation can be a passing **qualification case**
only when its precise negative classification and required cleanup evidence
are established. It never becomes a successful capture/import. Unexpected
child outcomes, missing or contradictory ownership, real ps failure, startup
failure, source/interpreter change or failed cleanup prevent qualification.
No retry-to-green loop, timeout increase or replacement inventory is part of
D30. A job timeout, missing result or missing artifact is incomplete evidence.

## Reproduction and retained records

The workflow runs the affected D29 suites and D30 focused tests before the
single collector invocation:

    python3 -B script/run_isolated_atrc_macos_qualification.py \
      --output /absolute/existing-parent/evidence \
      --experiment-commit EXACT_CHECKED_OUT_COMMIT

The evidence directory contains qualification.json, bounded per-case command
and cleanup receipts/streams, pressure report bytes, the permitted successful
output archive, and exact source copies. Preflight/test logs and source
commit/tree records are uploaded on both success and failure. Hidden files
and the mutable fixture-work sibling are excluded.

The source artifact, job/run metadata, source hashes, ZIP member bounds/CRC,
classification and final identities must be checked after the run before
writing the result. A docs/evidence-only follow-up records that result
without starting another qualification.

## What D30 can establish

A completed result can qualify the recorded Intel macOS/interpreter/synthetic
workload behavior. It cannot establish a native ATRC import, the cause of
D27's 0.592-second native scan, or the Finder cancellation acceptance.

D27 remains diagnostic-incomplete. The original full Finder
enter → exit → reenter → Escape → release → distinct fresh drop across
Orchard/Pistachio/Lemonade and ARM/Intel remains the task 07 acceptance gate.
Completed user physical/v4 checks are not repeated.
