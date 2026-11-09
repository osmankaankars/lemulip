# D24 — Observe the recorder's primary sampler

**Protocol prepared; no D24 native result is asserted in this revision.** This
diagnostic follows the [D23 retained identity review](NATIVE_SAMPLER_IDENTITY_REVIEW.md).
Its question is whether a bounded stack observation of the primary sampler can
distinguish the stage that has not completed while it observes the recorder.
Task 07, C12 and [PR #45](https://github.com/osmankaankars/lemulip/pull/45) remain
**HOLD**. This diagnostic supplies neither a product fix nor a release gate.

### Pre-execution CI correction

[The first CI run](https://github.com/osmankaankars/lemulip/actions/runs/42608920236)
at `dc877e28778a24c0a36a509ddc0bc107322b8dde` stopped in the portable test gate on
both architectures. The unchanged command/transport/D21 suites passed all 31
tests per architecture. The new 49-test suite had 15 failures and one error:
synthetic orchestration was rejected before any child launch because its helper
provenance stored an unresolved temporary-directory path while the orchestrator
compared the canonical path. Helper compilation, tool preflight and the native
observation steps were skipped. This run made **zero recorder or native sampler
invocations**.

The same precondition failure was reproduced on Linux using a symbolic-link
parent and the exact original test bytes. The fixture now resolves its root
before deriving helper, output and provenance paths, and an explicit alias-parent
regression checks that binding. Runtime identity checks and sampling bounds
remain as defined below. This corrects test setup before the first native
measurement; it does not repeat or reinterpret a recorder observation.

## Evidence motivating this observation

The [D21 recorder observation](NATIVE_RECORDER_STARTUP_OBSERVATION.md) retained
only the primary sampler's initial 84-byte banner on ARM64 and Intel. Neither
run retained a report or a later completion marker. Both primary samplers had
their full normal-operation budget before TERM; their elapsed times were about
3.8 seconds including cleanup. The recorder stayed owned until the helper's
original 15-second wait ended. This evidence does not show an early orchestrator
stop that explains the missing reports.

The [D22 control](NATIVE_SAMPLER_CALIBRATION.md) used the same sampling arguments
against a different owned native target. It produced reports in about 1.47
seconds on both architectures. D23 subsequently established a narrow retained
image/frame consistency witness for those reports. D22's original calibration
remains incomplete because its strict path gate stopped before post-sample
metadata; D23 does not replace that missing observation.

The installed `sample(1)` documentation retained by D21 and D22 describes
`-mayDie` acquiring symbol locations before sampling. Thus the initial banner
is an output milestone, not proof that stack capture has started. Missing later
markers alone cannot distinguish task acquisition, early image/symbol work,
capture, later processing, and report publication. The installed documentation
does not provide a progress or no-symbol flag that resolves this question.

## Fixed experiment

The workflow runs once on native ARM64 and once on native Intel. Each job checks
the installed manuals, native architecture, child-status capability, frozen
source ancestry, helper identity and installed sampler bytes before the native
helper and recorder start. There is no attempt loop or alternative flag set.

The new C helper registers one unique Darwin notification, publishes its own
identity receipt and waits for a fixed 15-second native window. It counts
callbacks without launching applications. A callback cannot initiate a drag,
source/control app or input sequence. Registration is cancelled and the serial
callback queue is drained before completion is published. This helper is a new
diagnostic component; the run is not an identical replay of D21's helper.

After the ready receipt is qualified, the parent starts the unchanged recorder
command from D20/D21:

```text
/usr/bin/xcrun xctrace record --template "System Trace" --all-processes \
  --time-limit 30s --no-prompt --notify-tracing-started <unique-name> \
  --output <exclusive-trace-path>
```

At recorder creation plus three seconds, a bounded exact-PID `ps` snapshot must
qualify the still-owned recorder instance. One primary sampler then starts:

```text
/usr/bin/sample <owned-recorder-pid> 1 10 -mayDie -file <primary-report>
```

The first complete expected-PID banner permits one pre-sample metadata query
of that primary sampler. If its instance and remaining window qualify, one
secondary sampler observes the primary:

```text
/usr/bin/sample <owned-primary-sampler-pid> 1 10 -mayDie -file <secondary-report>
```

There is no third nesting. Duplicate, wrong-PID, incomplete or ambiguous banners
cannot authorize another observation. A final primary-sampler metadata query
qualifies the process instance only if it remains live when that query occurs.
A partial report is retained separately from a fully qualified instance witness.

| Boundary | Fixed value and meaning |
| --- | --- |
| Recorder observation trigger | 3 seconds after recorder transport starts |
| Overall observation cutoff | 14 seconds after helper transport starts |
| Native notification window | 15 seconds from helper native start |
| Helper transport hard end | 17 seconds, including finite shutdown allowance |
| Exact-PID metadata command | 1-second total bound |
| Cleanup-only group inventory | 2-second total bound, using the D20 cleanup policy |
| Primary sampler | 3.5 seconds normal operation; 4 seconds including cleanup |
| Secondary sampler | At most the same bound; cancelled at the primary stopping boundary or overall cutoff |
| TERM escalation interval | 0.25 seconds within the original command budget |
| Sampler combined stream retention | 2 MiB |
| Individual report retention | 8 MiB; checked during polling and final bounded read |
| Installed executable parsing | 64 MiB, at most 32 Mach-O slices and 4,096 commands per slice |
| Optional trace archive | At most 256 MiB uncompressed and 16,384 entries, using the existing bounded packager |

The one-second nominal sample duration is not a wall-time bound for symbol work
or report production. The secondary observer cannot extend the primary budget.
Progress records bracket parent-observed stream and file changes; they do not
claim exact internal tool event times. Polling file growth is not a kernel file
size quota.

Producer work files are outside the uploaded evidence directory. Only bounded,
regular report copies and a successfully verified optional trace archive enter
the retained artifact. A rejected producer file cannot bypass this bound through
the artifact uploader. Receipt/report readers use nonblocking, no-follow opens
before validating file type and length.

## Ownership and termination

The recorder and primary sampler remain unreaped while other owned commands
can refer to their PIDs. Operation completion, stream closure, non-reaping exit
observation and eventual child collection are separate recorded events. A
process can exit before its PID lease is released. Group checks and cleanup
finish before that release; subsequent signals cannot target a recycled PID.

Python's documented `os.waitid(..., WNOWAIT)` leaves an exited child waitable.
Its macOS availability was added in Python 3.13, so this workflow explicitly
selects Python 3.13 and runs a peek-twice-then-wait capability check before the
native experiment. See the [Python 3.13 operating-system documentation](https://docs.python.org/3.13/library/os.html#os.waitid).
An unsupported runtime fails before helper/recorder creation.

Native helper completion or failure does not defer recorder shutdown for an
observer. Recorder SIGINT and finite escalation use the established recording
transport policy. Cleanup failures remain explicit and prevent a complete
diagnostic. Generic stale error text is not interpreted as a permission denial.

## Identity and interpretation contract

The retained source copies, exact Git commit/tree, native helper bytes and UUID,
helper self-receipts and installed `/usr/bin/sample` bytes bind the new run.
The sampler is invoked at its installed path. Its archived Mach-O copy is data
for independent parsing and is never executed. The before/after installed file
digest and immutable build/source inventories must agree.

Mach-O parsing distinguishes CPU family from subtype. An `arm64e` slice can
belong to a native ARM64-family tool; it must still have the expected slice UUID.
Thin and FAT images have bounded command/slice checks. Native report Code Type,
PID, parent PID, unique main image UUID, load address and counted call-graph
addresses must agree. A counted frame must belong to exactly one reported
image range. Display paths remain advisory literal text. No wildcard matching,
path reconstruction or D23 controlled-source wait-function claim is used.

A fully qualified secondary report establishes a sampled stack of this owned
primary sampler during this instrumented run. Phase interpretation requires
specific frames and their call context; a generic wait syscall cannot by itself
name a peer, prove an authorization denial, or identify recorder failure. Image
or symbol discovery before capture must remain distinguishable from processing
after capture when interpreting any result.

Sampling the sampler can perturb it and may indirectly affect the recorder.
This observation therefore cannot establish an unperturbed D21 timeline. A
missing or partial secondary report does not license another sampler, a longer
budget, a privilege change or an inference that a particular phase was reached.

## Verification and retained outputs

The portable test suite uses explicitly synthetic reports and real POSIX child
processes to check PID retention, non-reaping status, independent deadlines,
bounded streams, malformed reports, native image identity and negative gates.
Synthetic orchestration is labeled as such and cannot produce native evidence.
The native CI also runs the unchanged command, transport and D21 observer suites.

`diagnosticExecutionComplete` records whether the bounded protocol, native
helper completion, cleanup and input-preservation checks completed correctly.
`samplerStackQualified` independently records whether the secondary report and
both live process-instance snapshots qualify. A missing secondary report is a
possible negative observation, not a positive stack witness. CLI success means
the former field is true; it never means the product or recorder problem passed.

```bash
python3 script/test_run_native_recorder_progress_observation.py
```

The branch-specific [workflow](../.github/workflows/native-recorder-progress-observation.yml)
retains compiler/test output, runtime versions, installed manual bytes, executable
identity, source copies, native receipts, command records, progress observations,
metadata, available report bytes and cleanup evidence. A follow-up result entry
must record the exact run, attempt, source revision, artifact hashes and observed
outcome before describing this protocol as executed.

Production, the original D20/D21/D22 diagnostics and acceptance comparator stay
at the [D23 result base](https://github.com/osmankaankars/lemulip/commit/c1844a1ecb1650336d2cd584d23e2c3c6ed33a29).
The frozen product candidate is `d821d7343675e2850705d141ef9b3b93a6aee945`, tree
`425baa28f00ec24551dd70c0cc874a75fa3be0c1`. Original acceptance remains the complete
Finder enter, exit, reenter, Escape, release and distinct fresh-drop sequence
for Orchard, Pistachio and Lemonade on ARM64 and Intel.
