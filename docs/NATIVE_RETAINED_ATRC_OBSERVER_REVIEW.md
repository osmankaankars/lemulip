# D28 — Offline review of the retained ATRC output observer

**D28 fixes the demonstrated observation-counter defect and examines the
synchronous observer boundary offline.** It does not repeat D27's import or
change its `diagnostic-incomplete` outcome. The original result still reports
68 omitted completed observations; the corrected accounting produces 69 for
that retained history. The particular operation or scheduling delay behind
D27's 0.592-second census remains unidentified.

This work follows [D27's one import](NATIVE_RETAINED_ATRC_IMPORT.md), using its
retained receipts and frozen source, deterministic clock/filesystem fixtures,
and a narrow source correction. C12, task 07 and draft/unmerged
[PR #45](https://github.com/osmankaankars/lemulip/pull/45) remain **HOLD**. Task
08's final dependency and the completed physical/v4 evidence remain unchanged.

## Result and scope — 10 November 2026 (Europe/Istanbul)

| Question | D28 result |
| --- | --- |
| Why is the native omission count one too small? | The summary subtracts a retained failed observation from a count that includes only completed scans. The cause is reproduced and narrowly fixed. |
| Can a synchronous census postpone process supervision? | The source calls the census in the same loop as child status, stream draining and deadline handling. Deterministic fixtures exercise that coupling; see the verification section. |
| Which native filesystem call or scheduling interval took too long? | Unestablished. D27 retained aggregate scan clocks, not per-operation timing or scheduler attribution. |
| Did D27 qualify a saved analysis document? | No. Its failed observation gate and missing retained derivative are unchanged. |
| Was a new native operation performed? | No import, export, recording, sampler, native tool query or CI execution is part of D28. |
| What follows? | A separately scoped offline implementation and verification of an isolated observer, before proposing another native import. |

The [D28 evidence record](evidence/D28-retained-atrc-observer-review.json)
binds retained-input identities, reconstruction, failing-before/passing-after
proof, source hashes and final portable verification. D28's changed source is
separate from the exact source that produced the native D27 artifact.

| Retained identity | Value |
| --- | --- |
| D28 base / D27 result commit | `34e74c055f55cd3f8f4181d9b67edee1140a706f` |
| D28 base tree | `9b5fda62a00350136d8030fddd5c2f3e0346ac91` |
| Actual D27 import source / tree | `50b34b215e1372a46add0f6c67fc8a2b9dc95e06` / `1d7db69e5778be3d909188daf8ab0604a4db1a4f` |
| D27 run / attempt / job | [42639700185](https://github.com/osmankaankars/lemulip/actions/runs/42639700185) / 1 / `129237191513` |
| D27 artifact / bytes / files | `13685495111` / 12,940,445 / 75 |
| D27 artifact SHA-256 | `03fe68b01b0818d660d4c493ffcf68dc81878046e866b36fbcfc2e9a7115b3a8` |
| Original public D27 result SHA-256 | `4fb53201ccb6373a01b64c67535288a4a12f27bad3ce4b54251b8d2c34b2dff1` |
| Original public D27 verification SHA-256 | `5c6e7aa256ae062fa551c3f5d2f54ad59b11b715346345778ae62ee663c20356` |

Both original public JSON files remain byte-identical. The full original raw
ATRC was not decoded or edited during D28. Native progress text, exit status,
clock samples, false acceptance flags and the original accounting discrepancy
remain historical evidence.

## Retained chronology and what it can establish

D27's reader emitted `Import completed. Saving output file...`. Its stdout
was 106 bytes and stderr was empty. Output growth was observed, but that
progress text did not establish a successful final process exit or readable
saved document.

| Retained event | Observation |
| --- | --- |
| Failing census | 0.591878661 seconds against a 0.25-second work budget |
| Recorded overshoot | 0.341878661 seconds |
| Stop reason | `derived-output-observation-failed` |
| TERM / KILL signal offsets | 19.297913152 / 19.558746246 seconds after command start |
| Exit observation | -9 at 19.594896554 seconds after command start |
| Operation / adapter elapsed | 19.594917998 / 19.651000824 seconds |
| Final owned group | Only the unreaped zombie leader; the PID lease was held during inspection and then released |
| Cleanup / transport | complete / incomplete |
| Retention | `skipped-output-observation-failed`; no derivative archive retained |

The scan, failure, stop-request, terminal-observation, group-probe and
collection receipts include integer clock samples. Signal entries retain
floating `afterSeconds` offsets rather than integer signal timestamps.
Retention records elapsed duration but no absolute start/end clock samples.
The reconstruction preserves those precision limits; it does not manufacture
missing nanosecond timestamps or a measured delay between collection and
retention. Source control flow establishes that retention follows capture.

The last completed retained census saw 244 entries, depth 7, 1,569,293 logical
bytes and 2,142,208 allocated bytes. High-water counters reached 1,686,939
logical and 2,232,320 allocated bytes, including partial work during the failed
scan. The failed observation does not supply a complete named tree or its own
complete totals. High-water values are neither a final inventory nor a bound
on transient or off-root writes.

The 90/95-second command deadlines and the size/entry/depth thresholds did not
trigger this native stop. The 30-second retention budget did not expire:
`finalize()` saw the existing observer failure and immediately skipped reading
the output. D28 cannot inspect partial derived files that were never archived.

## Confirmed defect: completed-observation accounting

`sample()` increments `scan_count` only after `_scan()` returns successfully.
Its `finally` block retains an observation for both a successful and a failed
scan. The first 128 observations and the last 128 are retained; a failed scan
can therefore displace a completed record from the bounded tail.

The old `summary()` subtracted the length of the entire retained history from
the completed-scan count. Those quantities count different populations:

| Quantity | Original D27 value |
| --- | ---: |
| Completed scans | 324 |
| Retained completed observations | 255 |
| Retained failed observations | 1 |
| All retained observations | 256 |
| Original reported omitted completed count | 68 |
| Correct independently derived count: 324 - 255 | 69 |

The correction in
[`native_retained_atrc_output.py`](../script/native_retained_atrc_output.py)
subtracts only retained observations whose `completed` flag is true. The
history cap, scan count, failure flag, thresholds, traversal, capture loop and
retention behavior are unchanged. There is no schema change: the field again
counts the population its existing name specifies.

### Failing-before / passing-after proof

The same four focused cases were executed before and after the runtime edit;
the test source was identical between those runs.

| Case | Before correction | After correction |
| --- | --- | --- |
| Completed-only history, existing control | PASS | PASS |
| Failed scan without history eviction | PASS | PASS |
| Failed scan causes the first completed-record omission from the rolling tail | FAIL: 0 instead of 1 | PASS: 1 |
| D27-shaped history: 324 completed scans and one failed scan | FAIL: 68 instead of 69 | PASS: 69 |

The three new regression cases are in
[`test_native_retained_atrc_output.py`](../script/test_native_retained_atrc_output.py).
They exercise actual `sample()` history management; only the final controlled
scan failure is injected. The accounting change cannot explain the native
census delay: `summary()` runs after that observation/termination path. It also
cannot change whether D27 retained a qualified document.

## Synchronous observation: mechanism and deterministic evidence

The capture adapter's `tick_all()` first ticks the owned commands, then calls
the output observer synchronously. A command tick drains streams, peeks at
child status without reaping, checks its deadlines and performs any due signal
actions. These operations cannot run again while the observer is inside a
blocking filesystem call on that same thread.

`_clock_check()` checks elapsed monotonic time between operations. It cannot
interrupt an outstanding `stat`, `scandir`, directory open or other synchronous
call. The 250 ms value is a detected work-budget breach, not a hard operating
system deadline on every call. The original D27 receipts already state
`synchronousFilesystemCallsHaveHardDeadline=false`; D28 does not relabel that
limitation as a newly established native importer fault.

All five deterministic cases passed. Their injected delays use a virtual
clock over a real disposable filesystem. The capture cases retain the actual
`OutputGuard`, capture loop, `OwnedCommand` and group-inventory parser; the
transport and non-reaping child-status boundary are synthetic.

| Controlled case | Observed synthetic result |
| --- | --- |
| Metadata call returns after 600 ms | The 250 ms census budget is exceeded by 350 ms. Partial high-water counters survive, the previous complete snapshot remains, and retention is skipped without another scan. |
| Same elapsed time inside a metadata call or between calls | Both produce identical aggregate scan witnesses. Aggregate timing cannot distinguish these two injected causes. |
| Census occupies 0.050–0.650 s; target normal/total budgets 1.5/2.0 s | No target drain/status service occurs inside the occupied interval. TERM is requested at 0.650 s; the next drain runs at 0.655 s. Owned cleanup completes; transport remains incomplete. |
| Same census with target normal/total budgets 0.4/0.5 s | The recorded normal/total overshoots are 0.250/0.155 s. Late collection does not restore a timely-completion or cleanup pass; emergency cleanup evidence remains. |
| Synthetic child exits 0 at 0.100 s while the census is pending | Exit is first observed at 0.655 s. The observation failure and failed output gate remain even though the recorded exit is 0. |

These smaller command budgets exist only in the test factory. Native
90/95-second limits are unchanged. The five executed witnesses and exact
test-source identity are in the
[D28 result record](evidence/D28-retained-atrc-observer-review.json).

The controlled fixtures establish a mechanism and its predicted response.
They do not reconstruct the native output tree, identify a real slow syscall,
measure native filesystem performance, or establish that the importer would
have succeeded if observation had continued.

## Decision: separate census work from command supervision

The next observer must allow command supervision to keep servicing streams,
child status and due cleanup actions while a census is pending. Raising a
single timeout leaves the same synchronous coupling in place and cannot be
justified from one unlocalized 0.592-second observation.

For a separately scoped **D29 offline implementation**, use an independently
owned observer process with a bounded nonblocking report channel. A process
gives the supervisor an explicit lifetime and cleanup boundary for pending
filesystem work. A thread alone has no corresponding forceful cleanup
boundary. This is a design decision for D29, not an implementation or native
success claim in D28.

The implementation must make these guarantees reviewable:

| Boundary | Required behavior and evidence |
| --- | --- |
| Process supervision | The parent performs no directory census in its command tick path. It services target status/streams and its existing deadlines while observer work is pending. Record actual tick gaps and overshoots; do not claim a hard scheduler guarantee. |
| Ownership | Hold separate non-reaping child/PID leases for the importer and observer until their respective cleanup evidence is complete. Lost ownership forbids later numeric-PID actions. |
| Filesystem anchoring | Retain the exclusive 0700 output parent and descriptor/no-follow identity checks. Pending scan results must bind to the intended root and scan generation. |
| Scan protocol | Permit at most one outstanding census. Use sequenced, bounded messages and explicit started/completed/failed states; missing, malformed, duplicate, stale or oversized records fail the observation gate. |
| Timing witnesses | Record scan sequence, operation category, relative location, monotonic start/end samples and actual elapsed time. Distinguish an outstanding operation interval from a completed one; elapsed wall time alone does not isolate filesystem latency from scheduling delay. |
| Observation budgets | Keep command, scan, report-freshness and worker-cleanup budgets separate and explicit. A pending scan never silently extends the importer's budget. The candidate constants below must be implemented and verified offline before any native proposal. |
| Storage and history | Continue bounded entry/depth/logical/allocated accounting and bounded history. Identify incomplete scans and partial totals explicitly. Sampled stops remain distinct from filesystem quotas. |
| Failure and cleanup | Preserve the first failure and all termination evidence. A later exit 0 cannot erase a failed observation. Account for the observer as well as the importer; do not read unstable output while a writer or observer is unaccounted for. |
| Retention | Require positive cleanup, fresh complete inventory, stable hashes and a verified bounded archive before qualifying a derived document. Observer isolation alone does not validate trace semantics. |

An observer process still cannot provide an absolute hard bound for an
uninterruptible kernel operation or a parent that is not scheduled. Those
conditions must remain incomplete outcomes with actual elapsed times and
cleanup status reported. Likewise, an operation timing interval can localize
where wall time accumulated without proving why the kernel or scheduler took
that time.

### Candidate D29 time, storage and evidence contract

The following inherited constants are read from the unchanged D27 runtime.
They remain the starting contract, including the existing 250 ms census
budget. Cadence and polling are requested intervals; actual delays and
overshoots must be recorded.

| Inherited boundary | Fixed value |
| --- | --- |
| Target normal / total budget | 90 / 95 seconds |
| Census / requested cadence / parent poll | 250 / 50 / 5 milliseconds |
| TERM grace | 250 milliseconds |
| Owned-group probe time / stream cap | 2 seconds / 65,536 bytes |
| Target stdout + stderr cap | 8 MiB combined |
| Observed output logical / allocated cap | 512 MiB each |
| Output entries / depth / relative path | 16,384 / 32 / 1,024 UTF-8 bytes |
| Census history | First 128 plus rolling last 128 observations; completed and failed populations counted separately |
| Final stable retention / chunk size | 30 seconds / 65,536 bytes |

The new numbers below are **proposed engineering budgets for D29's offline
implementation**, not measurements from D27 or verified native parameters.

| New boundary | Candidate value and required behavior |
| --- | --- |
| Worker startup | 2 seconds before target launch; require a ready receipt bound to the intended output root and owned worker. Startup failure prevents import. |
| Outstanding census and report freshness | One request at a time; completion must be observed within 250 ms of the parent's dispatch. Worker timestamps supplement that deadline; progress never resets it. Missing completion fails the gate even if a late success arrives. |
| Nonblocking message channel | Maximum 4,096 bytes per framed record and 65,536 bytes of parent-side undecoded data. Parse at most 16 records and 65,536 bytes per parent tick before servicing commands again. Reject oversized/malformed/stale/duplicate records. |
| Backpressure | No blocking worker writes or parent reads. Failure to emit a required sequenced record invalidates the observation and initiates owned cleanup; no silent message loss or retry that resets a deadline. |
| Worker diagnostic retention | At most 8 MiB retained in total. Retain first 128 plus last 128 operation witnesses, plus the pending operation, first failure and cleanup receipts. Track omitted completed/failed records separately; reaching a cap cannot erase the first failure. Live reports carry relative paths and counters, not complete file payloads. |
| Worker cleanup | Separate 2-second budget from the first stop request with 250 ms TERM grace, while target supervision continues. A worker still unaccounted for produces an incomplete outcome and forbids final output reading. The target's original deadlines never move. |
| Final evidence qualification | Both owned processes accounted for; no failed/missing scan; fresh complete stable inventory, hashes and verified bounded archive under the inherited retention contract. Observation timestamps and partial counters alone never qualify a saved document. |

These values define a reviewable candidate contract. D29 must implement and
verify it, including channel saturation and pending-operation cleanup, before
any separately scoped native proposal. D28 neither changes the importer
limits nor executes an isolated observer. The 8 MiB worker evidence budget is
separate from the inherited 8 MiB target stream cap and 512 MiB output bounds.

D29's portable cases must include a stalled metadata operation, child exit and
stream progress during a pending scan, importer normal/total deadlines,
observer loss or malformed messages, first-failure preservation, bounded
history/backpressure and owned cleanup. The implementation and those cases
must be reviewed before any separate native experiment. No workflow dispatch,
larger native threshold, alternate template or import retry follows from D28.

## Verification and remaining limits

Fresh final portable verification passed **56/56 tests**, with no skips:

| Suite | Result |
| --- | --- |
| Output bounds, stable retention, owned-command handling and counter regressions | 27 passed |
| Import collector and precondition/classification regressions | 24 passed |
| Deterministic observer-boundary characterization | 5 passed |

The four focused counter cases are included in the output suite, not four
additional distinct tests. Their historical red/green executions show two
failures before the correction and four passes afterward. The five timing
cases were also executed to retain their synthetic witnesses; those executions
do not increase the distinct final-test count.

Retained-evidence reconstruction passed 85 checks and reproduced the prior
analysis output byte-for-byte. A separately authored material-fact audit passed
40 checks, including ZIP identity/CRC, 19 frozen source copies, counter
accounting, clock ordering and owned cleanup. These are evidence checks,
separate from the 56 software tests. Historical run/job/artifact IDs were
reused; these offline audits did not refresh them through the GitHub API.
Unchanged-input/reader assertions are preserved from the native receipt;
the 19 source-copy byte matches were freshly checked against Git objects.

The [verification record](evidence/D28-verification.json) retains commands,
exit statuses, case identities, before/after source hashes, red/green proof,
raw-stream identities and the independent audit. The original two public D27
JSON records are still byte-identical to the pinned base. This Linux portable
verification supplies no new macOS/native acceptance result.

The runtime delta is limited to summary accounting; the new timing tests
characterize existing behavior. The source identities captured before and
after verification bind the exact files under test. Original D27 result and
verification bytes are checked against the pinned base and preserved.

D27's R1 fixture-path defect was corrected in D27 and is distinct from this
counter defect. The older full D24 synthetic-suite failure remains open; D28
does not rerun or repair it. D24's abnormal recorder exit, D25's missing-template
export refusal, original drag-cancellation acceptance and task 08's dependency
remain unchanged. No application production code or acceptance criterion is
changed.

**D28 stop condition:** the demonstrated counter cause is fixed and covered;
the synchronous observation mechanism is characterized; native low-level
attribution remains limited by missing witnesses. **D29 is proposed and has
not been executed.**
