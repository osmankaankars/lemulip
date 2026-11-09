# D24 — Observe the recorder's primary sampler

**D24 completed: the bounded diagnostic passed on ARM64 and Intel, but neither
architecture produced a qualified sampler stack.** Both primary and secondary
samplers retained only their initial banners. Intel additionally retained late
recorder progress, one notification callback and a partial trace package; its
recorder subsequently exited on signal 11. The internal waiting phase remains
unidentified. The subsequent [D25 read-only export](NATIVE_RETAINED_TRACE_EXPORT.md)
refused that exact retained Intel package with `Document Missing Template Error`.
No table of contents or time coverage was established. The next D26 step is an
offline review of the retained reader/import/template contracts.

This diagnostic follows the [D23 retained identity review](NATIVE_SAMPLER_IDENTITY_REVIEW.md).
It asks whether a bounded stack observation of the primary sampler can distinguish
the stage that has not completed while it observes the recorder.
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

## Executed result — 9 November 2026

[R2, attempt 1](https://github.com/osmankaankars/lemulip/actions/runs/42609635410)
completed both native jobs successfully. Each architecture ran **one recorder,
one primary sampler and one secondary sampler**. The earlier R1 failure above
occurred before any native measurement. There was no additional recording or
export during the retained-byte review.

The public [result projection](evidence/D24-recorder-progress-observation.json)
preserves the original classifications, command clocks, helper receipts, tool
identities and observed output milestones. The [verification record](evidence/D24-verification.json)
binds the raw artifacts, exact Git source objects, tests and independent audits.
Private absolute paths and full installed manuals are omitted from these public
projections; the raw artifact bytes were not rewritten.

| Run identity | Value |
| --- | --- |
| Executed source commit | `73464e30f278203cbd129025f1db814b6c549b2b` |
| Executed source tree | `0d0b8c476fb052cd7b3a5b7ac98d0c6977069bf5` |
| Native run / attempt | `42609635410` / `1` |
| ARM64 / Intel job | `129134432522` / `129134432671` |
| Native tests | 81 passed per architecture: 6 bounded command + 10 transport + 15 D21 observer + 50 D24 |
| Final portable D24 tests | 50 passed, Linux x86_64, CPython 3.12.14; 35.306 seconds wall time |
| Native Python | ARM64 3.13.17; Intel 3.13.15 |
| Native compiler gate | Helper compiled with `-Wall -Wextra -Werror` on each architecture |
| Input preservation / worktree diff | Passed on both jobs |

| Retained artifact | ARM64 | Intel |
| --- | --- | --- |
| Artifact ID | `13668694448` | `13669502448` |
| ZIP bytes | 226,836 | 12,948,336 |
| ZIP SHA-256 | `44b9438155713c42bcadee75d3359a4a6659bf3027e9f2056fb1f115dd58041f` | `5e80502e00e9da7cd857ab45b5324d637c4c09195dfe6e70b2d5569976e7b041` |
| Files / expanded bytes | 94 / 803,311 | 95 / 14,067,380 |

Artifacts use the workflow's 14-day retention and are scheduled to expire on
23 November 2026. Archive size, digest, safe relative names, types, bounds and
CRC were checked independently. All **189 retained files**, **26 source copies**,
**126 immutable build/source entries** and **32 runtime input bindings** matched.
An independent native receipt, ownership, timing and cleanup audit passed
**195 cross-checks**. These checks validate the evidence and execution contract;
they do not turn missing sampler reports into a positive witness.

### Sampler and notification observations

| Observation | ARM64 | Intel |
| --- | --- | --- |
| Original status | `diagnostic-complete-stack-unqualified` | `diagnostic-complete-stack-unqualified` |
| Diagnostic / cleanup complete | true / true | true / true |
| Qualified sampler stack / native evidence established | false / false | false / false |
| Recorder / primary / secondary PID | 2105 / 2121 / 2128 | 2040 / 2147 / 2149 |
| Primary-before state | `S<s` | `S<s` |
| Primary stderr / report | 84-byte initial banner / absent | 84-byte initial banner / absent |
| Secondary stderr / report | 84-byte initial banner / absent | 84-byte initial banner / absent |
| Primary TERM after its start | 3.529332 s | 3.508390 s |
| Primary operation completion | 3.785431 s | 3.766950 s |
| Secondary operation completion | 3.196441 s | 3.373116 s |
| Secondary stopping reason | `primary-operation-boundary` | `primary-operation-boundary` |
| Native helper elapsed time | 15.015727 s | 15.001779 s |
| Notification callbacks | 0 | 1 |
| Recorder observed exit | −2, SIGINT | −11, SIGSEGV |
| Trace package | absent | retained; successful recording completion unestablished |

All four sampler stdout streams are empty. No sampler retained a completion /
symbol-processing marker, report-written marker, report-file progress or final
report. Neither architecture obtained a primary-after snapshot. The original
reason remains `secondary-ended-without-admissible-after-snapshot`; there is no
qualified stack or identified phase to substitute for it.

The primary normal-operation boundary was 3.5 seconds; the actual TERM times in
the table retain its scheduling overshoot. Direct-child and stream operations
completed within their effective total budgets. At the later final group
inventory, each of the six targeted groups contained only its unreaped zombie
leader. This establishes no live members **at that snapshot**; it does not
retrospectively timestamp every possible descendant's exit at the four-second
sampler boundary. Recorded group `SIGKILL` attempts returning `EPERM` were
resolved by that positive cleanup evidence. They do not establish a sampler
authorization denial.

### Intel's later recorder progress

Within the **parent monotonic clock**, relative to recorder transport start,
the primary sampler launched at approximately +3.045 seconds and completed at
+6.812162–6.812163 seconds. The secondary completed at +6.798458 seconds. The
first recorder stdout increment was observed at +11.310643–11.310644 seconds,
**at least 4.498480 seconds after both sampler operations ended**. It announced
recording startup; subsequent output offered Ctrl-C and then reported stopping.
There was no recording-complete or saved-trace announcement.

Separately, within the **helper native continuous-clock domain**, the one
callback was bracketed at helper start +14.109751453–14.109751944 seconds. Its
token matched the registration. A notification does not authenticate its sender
or establish a trace epoch. Parent observations and native callback clocks are
not equated, and the callback is not used to backdate event coverage.

The recorder received SIGINT at +15.043194 seconds and SIGTERM at +25.059166
seconds. Exit −11 was observed at +25.188957 seconds. This establishes sequence,
not that SIGTERM caused the fault. The 27.060267-second recorder operation time
includes cleanup/escalation; it does not extend the helper's 15-second native
window. ARM64 retained no recorder output, notification callback or trace.

### Retained Intel trace: integrity established, coverage unresolved

The inner `recording.trace.zip` is **13,283,084 bytes**, SHA-256
`d4a6e955f18b79d99530ec92690fad043422cb4897c0fb303f3066150cfb4bde`.
Its five entries contain three directories and two files totaling
**115,835,304 expanded bytes**. Streaming hash/CRC checks matched the retained
packaging receipt under the original 256 MiB aggregate and 16,384-entry limits.

| Inner file | Bytes | SHA-256 |
| --- | --- | --- |
| `Trace1.run/Attachments/trace-data.atrc` | 115,782,056 | `dd55ca66c46a4651df145287d2db8573e6dcf5f9387dcea73bec21a7a37719f0` |
| `Trace1.run/RunIssues.storedata` | 53,248 | `50e5b458ca4dcfa54f0186c41195fb90ee85ed733eb55e5f64017251182593e0` |

A bounded primitive-only header read found OS 15.7.9 / build 24G830 and a boot
identity matching the helper. No event payload or trace timing was decoded.
A bounded read-only SQLite query found one issue row whose message is
`Data stream: Time Mapping`, with `ZTYPE=2` and `ZRELATIVETIMESTAMP=0`.
Neither the severity meaning of 2 nor an epoch meaning for 0 is established.
Archived objects and executables were not loaded. The temporary database copy
was unchanged and removed after inspection.

The package's byte integrity does **not** establish normal recording completion,
exportability, usable clock mapping, event range, sampler-window coverage,
activation routing or an IPC request chain. All those qualifications remain
false or unestablished in the public result.

### Decision after D24 and subsequent D25 result

D24 proposed one bounded read-only export of a table of contents from the
**exact retained Intel trace**, using a version-recorded installed Xcode tool:

```text
/usr/bin/xcrun xctrace export --input <bounded-retained-copy>/recording.trace --toc
```

[D25 R2](NATIVE_RETAINED_TRACE_EXPORT.md) completed that step in
[run 42616711092](https://github.com/osmankaankars/lemulip/actions/runs/42616711092),
attempt 1, at `e537fb774768747c144ba7c57c1d8d4a097683e9`, tree
`8b073dc3cafb004d4fe4dc8dd99e5fdd9ce42e04`. All 91 tests passed. Its single export
exited **10 after 1.734828604 seconds**, with empty stdout and exactly 47 stderr
bytes: `Export failed: Document Missing Template Error` followed by a newline.
Input, source and installed-tool identities remained unchanged. The finite
refusal is preserved in the [D25 result](evidence/D25-retained-trace-export.json)
and [verification record](evidence/D25-verification.json); it establishes no TOC,
usable clock mapping, event range or sampler-window coverage. The error text
does not by itself identify a particular missing metadata field or prove a
repair route.

The next D26 task first reviews the retained Xcode 26.3 reader, import and
template contracts offline. Any actual metadata gap must be identified before
proposing another native collection or derived-data attempt. D24 itself
performed **no trace export**; D25's subsequent refusal does not resolve the
sampler phase, D21 causality, the original drag route or C12 acceptance.

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
metadata, available report bytes and cleanup evidence. The executed-result
section above and its two linked data files record the run, attempt, exact
source revision, artifact hashes and observed outcome.

Production, the original D20/D21/D22 diagnostics and acceptance comparator stay
at the [D23 result base](https://github.com/osmankaankars/lemulip/commit/c1844a1ecb1650336d2cd584d23e2c3c6ed33a29).
The frozen product candidate is `d821d7343675e2850705d141ef9b3b93a6aee945`, tree
`425baa28f00ec24551dd70c0cc874a75fa3be0c1`. Original acceptance remains the complete
Finder enter, exit, reenter, Escape, release and distinct fresh-drop sequence
for Orchard, Pistachio and Lemonade on ARM64 and Intel.
