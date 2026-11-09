# D29 — Isolated retained-output observer, implemented and verified offline

**D29 implements the independently owned census worker proposed in D28.**
The parent continues servicing the target's streams, non-reaping child status
and deadlines while a separate Python process performs filesystem census
work. This is a separately callable diagnostic adapter; the frozen D27
collector and its workflows continue to use their existing path.

The implementation and its portable verification are complete. The affected
suites passed **145 distinct tests, with no skips**. These are
offline software results, including disposable real Python processes. They
do not establish a successful native ATRC import, identify D27's slow native
operation, or satisfy the original Finder drag-cancellation acceptance gate.

C12, task 07 and draft/unmerged [PR #45](https://github.com/osmankaankars/lemulip/pull/45)
remain **HOLD**. Task 08's final dependency and the completed physical/v4
evidence remain unchanged.

## Scope and immutable starting point

D29 starts at D28 commit `1c1c296e02a5b7866d14fa44d41863947271e086`,
tree `ea8468793f0402a9dc6d71bc385b048c4a40013d`. Its branch is
`codex/isolated-atrc-observer-07`.

The [D28 design and counter correction](NATIVE_RETAINED_ATRC_OBSERVER_REVIEW.md),
[D27 import result](NATIVE_RETAINED_ATRC_IMPORT.md), original public D27
evidence, product sources, resources, package configuration and all workflows
remain unchanged. No native import, export, recording, sampler, Apple tool
query or CI dispatch was performed for D29.

| Deliverable | Role |
| --- | --- |
| [Parent adapter](../script/native_retained_atrc_isolated.py) | Owns target and observer lifetimes, bounded IPC, generation/deadline checks, final qualification and retention permission |
| [Census worker](../script/native_retained_atrc_worker.py) | Reuses the existing no-follow, descriptor-bound census in its own process and emits operation witnesses |
| [Result evidence](evidence/D29-isolated-atrc-observer.json) | Executed integration observations, failure history, evidence scope and unchanged acceptance status |
| [Verification evidence](evidence/D29-verification.json) | Exact tested source identities, test outcomes, red/green proofs and preservation checks |

## Lifecycle and evidence gates

The parent creates the exclusive 0700 output root through the existing
`OutputGuard`. That initial root setup and synchronous empty scan occur
before the worker and target start. D29 does not describe those calls as
interruptible or subject to the worker-startup deadline.

The parent creates a nonblocking request pipe and report socket pair before
launching the worker. It passes only the explicitly inherited root and IPC
descriptors. The worker checks the descriptor, canonical path, device/inode,
directory mode, limits and session nonce. The parent requires both a bound
`ready` report and a completed empty initial census before starting the
target. A ready message alone cannot authorize the command.

Each live supervisor tick services the target first, then the worker and any
owned group probes, followed by bounded report processing. There is no
directory census in this live parent path. The worker calls the existing
census implementation through a process-local timing proxy, recording
`stat`, `fstat`, `open`, `close`, `scandir`, iterator advancement and
iterator closure with relative locations.

A report binds the session nonce, global sequence, census generation and
monotonic clock. Operation completions must match their starts exactly,
including category, path and elapsed nanoseconds. A failed operation cannot
be overwritten by a later successful census summary. Completed totals and
high-water values must stay within the inherited limits; high-water values
cannot decrease. Duplicate keys, invalid UTF-8, nonfinite values, stale
generations, out-of-order messages, unmatched operations and late completion
all fail observation.

Only one census may be outstanding. Its 250 ms deadline begins when the parent
dispatches it. Intermediate progress does not extend that deadline, and a
queued success first received after the deadline cannot restore acceptance.
Pending operation and first-failure snapshots remain available after cleanup.

After the target's operation ends, the parent finishes any earlier pending
generation and requires a **new post-operation census**. A completed
pre-exit scan cannot satisfy this barrier. It then requires acknowledged
observer shutdown and successful worker exit, positive group evidence for
both owned processes, and collection under the retained child leases.

`IsolatedResult.finalize(archive_path)` carries that combined permission
internally. It reuses the original stable inventory/hash/archive verifier
only after the combined gate permits final reading. Exit zero alone cannot
authorize retention. A naturally nonzero target result may still be retained
as diagnostic output if its observation and cleanup are sound; it is not
reclassified as a successful import.

## Fixed limits

D29 preserves the D28 candidate values and inherited output/command limits.

| Boundary | Value and enforcement |
| --- | --- |
| Target normal / total budget | 90 / 95 seconds; shortened values require an explicitly marked test factory |
| Census / requested cadence / polling | 250 / 50 / 5 ms; actual tick gaps and deadline overshoots are recorded |
| Worker startup | 2 seconds before target launch, including ready and complete empty initial census |
| Worker cleanup | 2 seconds from the first stop request to positive collection; an overrun denies qualification |
| TERM grace | 250 ms; at most one KILL escalation per owned lease |
| Owned group probe | 2 seconds and 65,536 bytes per probe |
| Target stdout + stderr | 8 MiB combined |
| One framed report | 4,096 UTF-8 bytes including newline |
| Parent undecoded buffer / read per tick | At most 65,536 bytes |
| Parsed reports per tick | At most 16 before servicing commands again |
| Backpressure | Required partial or blocked writes fail; no blocking retry or silent message loss |
| Retained worker/probe evidence | 8 MiB, including histories, pending/first-failure records, worker/probe receipts, raw bounded streams and parsed group evidence |
| Histories | First 128 plus rolling last 128 census and operation records, with separate completed/failed omission counts |
| Output logical / allocated size | 512 MiB each |
| Entries / depth / relative path | 16,384 / 32 / 1,024 UTF-8 bytes |
| Stable final retention / chunk | 30 seconds / 65,536 bytes |

The evidence accounting uses compact UTF-8 metadata plus the raw retained
worker/probe stream bytes. It counts the worker receipt in both exposed
locations. Histories reserve 3 MiB for cleanup and fixed metadata; a further
4 KiB covers the small final accounting/gate/clock fields. The final combined
size is checked again. A byte-limit failure denies observation/retention and
may omit history records with explicit adjusted omission counts; it preserves
the pending operation, first failure, cleanup receipts and bounded raw cleanup
streams. The normal first/tail retention policy remains unchanged below the
cap.

Kernel socket buffers are reported separately: they are not the 65,536-byte
application undecoded buffer. Socket buffering accommodates small bursts;
saturation still fails the required-report contract.

The 2-second cleanup value is an **accounting qualification deadline**, not a
guaranteed function-return duration. Group probes and final accounting may
finish later, and that actual elapsed time/overshoot is reported as failure.
A scheduler that does not run the parent, or an uninterruptible kernel
operation, has no hard deadline guarantee here. Observed sampled output
limits are also not filesystem quotas or a bound on off-root/transient writes.

## Verification and what the tests establish

| Suite | Distinct tests |
| --- | ---: |
| Existing output/retention and D28 counter cases | 27 |
| Existing import collector prerequisites/classification | 24 |
| D28 deterministic synchronous-observer cases | 5 |
| Worker protocol, traversal, paths, limits and backpressure | 18 |
| Parent report semantics, timing and bounded histories | 35 |
| Nonblocking channel fragmentation, framing, EOF and per-tick limits | 8 |
| Real Python target/worker integration | 15 |
| Real resource and lifecycle failure paths | 7 |
| Deterministic post-failure cleanup and complete evidence bounds | 6 |
| **Total** | **145** |

The real-process delayed-metadata fixture blocks in a Python callback after
the real worker has emitted the operation-start witness. The target writes
stdout and exits zero while that operation remains pending. The parent sees
both events before the census expires, then retains the failed observation
and cleans up its owned processes. This directly exercises process
separation; it does not simulate a measured kernel stall or reproduce D27.

Other integration cases cover normal/total target deadline handling, missing
initial census, nonempty startup, wrong root identity, malformed/lost worker
reports, a pending fresh final scan, missing group qualification, acknowledged
shutdown followed by nonzero/forced worker exit, and a forbidden second
capture attempt. The positive output case verifies exact ZIP payload, CRC,
SHA-256 and preservation of the original file.

Lifecycle cases inject failures during pipe/socket setup, report setup,
post-spawn writer closure, group-probe creation, transport closure and one
transient supervision tick. They check actual descriptor/stream closure and
child collection before fixture teardown. A supervision failure stays a
failure even if later cleanup ticks can safely account for the child. An
`ECHILD` lease loss still forbids later actions on that numeric PID.

The deterministic cleanup test exercises an unaccounted worker and a failed
channel with buffered complete reports. It checks that failed backlog does
not cause a busy loop and that cleanup does not append repeated KILL records.
This fixture is virtual; it is not a real uninterruptible-process experiment.

### Test-environment limitation

The actual `/bin/ps -A -o pid=,pgid=,stat=` command in this environment failed
with `fatal library error, lookup self`. The production adapter rejected that
missing group evidence. Integration and lifecycle fixtures therefore use
**explicit synthetic direct-child group rows**, generated from retained real
Python child objects, their real `waitid(WNOWAIT)` status and `getpgid()`
identity. They verify separate child leases and collection order, not
OS-wide descendant enumeration. No production fallback was added.

A separate early real-process attempt produced no worker report within the
2-second startup budget and was rejected before target launch. Its incomplete
receipt is retained as history. The available record does not identify the
cause; later passing fixtures do not erase it or establish a native startup
reliability rate.

### Independent review and failing-before/passing-after evidence

Independent protocol tests exposed acceptance of an operation error followed
by successful completion, and out-of-bounds high-water values. With the same
35-test source, two failing test methods produced five failing assertions
before the correction; all 35 then passed. A separate two-case real-process
proof showed that a valid `stopped` report followed by exit 7 or forced TERM
was incorrectly accepted. Both cases passed after requiring successful worker
termination. The protocol proof binds stable before/after source identities.
The shutdown red record has a narrower provenance: its on-disk fingerprint
was taken after module import, without a post-run identity check, so it does
not conclusively bind the loaded red implementation. Its assertion failures
and receipts are retained with that limitation. The final 145-test execution
hashes every Python source before importing suites and afterward, separately
binding the completed implementation.

Review also closed setup/finalization resource leaks, transient-supervision
cleanup suppression, repeated emergency signal receipts and failed-backlog
spinning. Focused and repeated runs are not added to the distinct final test
count. No claim is made that the historical full D24 suite or native
macOS/ARM/Intel acceptance suite passed in D29.

## Next separately scoped work

**D30 is macOS qualification of this isolated observer using disposable
synthetic output, before another native import is proposed.** The concrete
scope must bind the tested source/interpreter and exercise the real
non-reaping process/group APIs, worker startup, operation reports,
backpressure and cleanup on the intended macOS environment. This Linux
fixture result cannot substitute for that platform qualification.

D29 does not start D30, dispatch CI, alter a native threshold, or authorize
another import/record/export/sample. The original full Finder
enter → exit → reenter → Escape → release → distinct fresh-drop acceptance
still applies across Orchard, Pistachio and Lemonade on ARM and Intel.
D27 remains `diagnostic-incomplete`; its particular slow native operation
remains unidentified.
