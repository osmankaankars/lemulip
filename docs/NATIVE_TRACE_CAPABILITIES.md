# Native tracing capabilities (D19)

## Question and fixed scope

D18 completed with valid zero-call receipts and no natural C-entry calibration.
Its proposed interposition route remains closed. D19 R2 completed the inventory
of installed tracing-tool contracts on the unchanged ARM and Intel CI runner
labels with Xcode 26.3. Both results are **`inventory-complete`**. This is **tool
discovery, not a trace recording, activation calibration, or drag acceptance
test**. No source/control application was launched.

The exact missing evidence remains the earlier activation request/client context
or the source drag-tracking consumer's disposition of Escape, described in the
[investigation packet](NATIVE_DRAG_UPSTREAM_INVESTIGATION.md). Production C12,
PR #45, the original Finder gate, and completed physical/v4 evidence are unchanged.

## New primary-source evidence

Apple's historical [AppKit release notes](https://developer.apple.com/library/archive/releasenotes/AppKit/RN-AppKitOlderNotes/),
under **OS X 10.10.3 → Spring Loaded Drag & Drop**, state: “All application windows
will spring forward automatically.” The notes distinguish that window behavior
from optional spring-loaded controls. An absent owned
`NSSpringLoadingDestination` handler therefore does not exclude automatic window
behavior. These are historical release notes, which explicitly caution that later
releases may supersede them. They do not identify the initiating process, public
entry, IPC relationship, or modern macOS 15 implementation behind D17's transition.
Window ordering and a global `SETFRONT` request also require an observed connection.
This finding narrows the question without establishing the cancellation cause;
the retained timing counterexamples still apply.

Apple's [Analyze hangs with Instruments, WWDC23](https://developer.apple.com/videos/play/wwdc2023/10248/),
at 37:57, demonstrates an event-specific blocked `mach_msg2_trap` backtrace in
**Thread State Trace**. This differs from a statistical Time Profiler sample.
It supports investigating an earlier IPC call stack but does not promise that
every activation request blocks, every syscall has a stack, or an exported trace
contains a sender-to-receiver transaction. The actual installed instruments,
templates and export options must be established before designing such a capture.

Apple's [Processor Trace requirements](https://developer.apple.com/documentation/xcode/analyzing-cpu-usage-with-processor-trace)
include M4-or-later Mac hardware and macOS 15.4 or later; the [Xcode 16.3 release
notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-16_3-release-notes)
also specify device configuration. An ARM label alone is not hardware or access
proof. D19 reads model/CPU metadata; it does not change that configuration.

## Commands and evidence

`script/collect_native_trace_capabilities.py` runs fifteen fixed, read-only
commands once each: OS/kernel/model/CPU/virtualization metadata;
`DevToolsSecurity -status`; `xcodebuild -version`; `xcrun --find xctrace`;
`xctrace help`, `help record`, `help export`, `help list`; `list templates`,
`list instruments`; and the locally installed `xctrace` manual. The words
`record` and `export` are arguments to **help**, never recording/export operations.

Each command has a 20-second deadline and a combined stdout/stderr limit of
2 MiB. The collector creates each command in its own process group and terminates
only that group on a deadline or overflow. It retains exact stdout/stderr bytes,
hashes, argv, status, exit code, elapsed time and cleanup receipts. Unsupported
optional metadata is preserved as nonzero or spawn-error evidence. Required-tool
failures make the inventory incomplete; no fallback, retry, privilege escalation,
authorization request or settings change follows.

The output directory must not exist. A scope receipt and the four exact source
files precede command execution; individual receipts survive a later failure.
The final `capabilities.json` binds results to the executed commit/tree and native
architecture. The workflow uploads available evidence on either outcome.

Six focused subprocess checks exercise nonzero stream retention, output limits,
deadlines, and a leader that exits on termination while its same-group descendant
ignores that signal. Review reproduced the last cleanup gap before publication;
the collector now escalates the owned group independently of leader/pipe state.
They also cover a final-signal EPERM with independently observed exited-group
evidence and reject live, malformed, truncated or failed snapshots. These checks
do not launch the source/control apps or invoke the tracing tools.

An EPERM is always recorded. One bounded `ps -A -o pid=,pgid=,stat=` snapshot may
establish that the direct child exited and no non-zombie member of its exact
group was observed. Only matching-group rows are retained. The snapshot has a
two-second deadline and 64-KiB output cap, and cannot recursively request another
snapshot. No further signal is sent to that numeric group after the EPERM/leader
reap. Any unresolved group stops subsequent inventory commands; independent exit
evidence preserves the original timeout/output-limit outcome rather than turning
the command into success.

## Interpretation and stop condition

`inventory-complete` means the required metadata commands completed. It does not
mean tracing access, a usable export schema, or activation/Escape coverage was
established. A template's presence is not proof it can record. Developer-tools
status is not per-tool TCC authorization. Kernel build metadata alone is not a
verified match to a particular published XNU implementation.

Before any later natural-startup qualification, specify the installed recording
mechanism, exact target and event identity, trace clock relationship, actual
exported event/stack fields, access requirements and bounds. A qualifying witness
must be a real activation caller in an event-specific stack; a generic event-pump
wait is insufficient. Any claimed daemon pairing additionally needs a real
request/message relationship and operation evidence, not temporal proximity.
Absent or partial stacks remain inconclusive. No held gesture is authorized by
inventory success alone.

## Status

### R1: subprocess tests stopped before tool inventory

[Run 42564449289](https://github.com/osmankaankars/lemulip/actions/runs/42564449289),
attempt 1, tested `c267498adf1013d3ed6b8d78990696028ecd9455` / tree
`638771b5c4e4f773c0045d9e8792404c9baa2abe`. Both architectures passed source
scope/privacy checks, then two of four subprocess tests raised EPERM at the
post-termination group SIGKILL. Nonzero retention and the live stubborn-descendant
test passed. No inventory command, trace recording, or source/control startup ran;
artifact upload found no output. Job logs retain this infrastructure result.

Apple's published [XNU group-signal implementation](https://github.com/apple-oss-distributions/xnu/blob/xnu-11417.140.69/bsd/kern/kern_sig.c)
excludes zombie members and can return POSIX EPERM for an existing group with no
eligible members. This is consistent with the observed failure, but R1 did not
retain process states and does not prove that its groups were zombie-only. R2
adds the independent bounded state check above, keeps the real cleanup tests,
and preserves their output before inventory starts. No tracing permission is
inferred from this subprocess-signaling result.

### R2: completed tool inventory

[Run 42565052135](https://github.com/osmankaankars/lemulip/actions/runs/42565052135)
completed successfully on both architectures on **9 November 2026,
05:03:00–05:03:38 UTC**. It executed
`daf90a14cbe0e5855e2e4a3e69dc8c170700635d`, tree
`7b3cf73162aff5612fa7f5b97bf2729df6f68d55`. The executed
[workflow](https://github.com/osmankaankars/lemulip/blob/daf90a14cbe0e5855e2e4a3e69dc8c170700635d/.github/workflows/native-trace-capabilities.yml)
and four retained source copies bind the protocol to that revision; this completed
report was written afterward.

| Observation | ARM64 | Intel |
| --- | --- | --- |
| Job | `128989654018` | `128989654392` |
| Inventory result | `inventory-complete` | `inventory-complete` |
| Fixed commands | 15 completed, all exit 0 | 15 completed, all exit 0 |
| Subprocess checks | 6 PASS | 6 PASS |
| macOS | 15.8.2 (`24H232`) | 15.7.9 (`24G830`) |
| Reported model | `VirtualMac2,1` | `Macmini6,2` |
| Reported CPU | Apple M1 (Virtual) | Intel Core i7-8700B, 3.20 GHz |
| `kern.hv_vmm_present` | `1` | `1` |
| Xcode | 26.3 (`17C529`) | 26.3 (`17C529`) |
| `DevToolsSecurity -status` | Developer mode enabled | Developer mode enabled |

No command timed out, reached its output cap, returned an error, or required
cleanup escalation. The R1 EPERM was a subprocess-test infrastructure failure;
R2's successful metadata commands neither erase that result nor establish tracing
authorization. The reported model and CPU are retained independently, including
the Intel virtual machine's model/CPU combination.

Both installed lists include the **System Trace** template and the **Thread State
Trace** and **System Call Trace** instruments. The command help is identical on
the two architectures and documents these relevant operations:

| Installed contract | What the retained output establishes | What remains unobserved |
| --- | --- | --- |
| `record --template`, `--instrument` | A named template and an added instrument are supported CLI arguments | Which tables and stack fields a recording actually produces |
| `record --all-processes`, `--time-limit`, `--no-prompt` | A bounded capture can be requested without interactive prompts | Successful recording access on either runner; prompt suppression grants no access |
| `export --toc` | Export can enumerate a trace's available entities | The actual table of contents for a captured System Trace |
| `export --xpath` | A selected entity can be requested as XML | Actual schemas, event identities, timestamps, frames, and missing-data behavior |

The installed 26.3 help does **not** advertise `--show-recording-options` or
`--recording-options`. Apple's
[Xcode 27 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes)
introduce those CLI options in the later release. A capture design for this
inventory must use its observed 26.3 contract, rather than assume later options
or an unobserved stack configuration.

**Processor Trace** appears in both lists, but the reported M1 and Intel CPUs do
not meet Apple's [M4-or-later Mac hardware requirement](https://developer.apple.com/documentation/xcode/analyzing-cpu-usage-with-processor-trace).
Its presence is not a usable hardware capability on these observed hosts.
No Processor Trace recording or configuration change was attempted.

### Retained evidence and independent checks

The [public D19 evidence](evidence/D19-trace-capabilities.json) preserves each
complete original `capabilities.json` object, the exact UTF-8 bytes of selected
command and bootstrap streams, and byte counts/SHA-256 identities for **all 54
archive files per architecture**. Both ZIP digests, all extracted file bytes, and
all four retained source copies per architecture were independently checked
against the downloaded archives and exact executed Git revision.

| Architecture | API artifact | ZIP bytes | ZIP SHA-256 |
| --- | ---: | ---: | --- |
| ARM64 | `13651171058` | 38,289 | `a19ba873757d42146ae43b1b984b7dad1f650d422afe4c9a6cd3c6a284a663da` |
| Intel | `13650748741` | 38,343 | `5467a0bc0d801e93281bf79f7335362efeab1996c748ae6479e6ff1c37665240` |

The original archive directories are `drag-trace-capabilities/` and
`drag-trace-capabilities-bootstrap/`. Each public projection explicitly lists
which file bodies it omits: duplicated command receipts and scope, retained
source bodies available at immutable Git URLs, and the manual's raw streams
(its stdout contains terminal overstrike characters). Their original hashes and
sizes remain in the index. Included text is decoded strictly as UTF-8, without
trimming, normalization, substitution, or runner-home paths. Complete manual and
receipt bytes remain in the original artifacts. The workflow retains artifacts
for 14 days; the report and public projection remain in Git.

### Remaining prerequisite

D19 closes **installed tool discovery only**. Recording access, actual exported
schemas and event stacks, activation-route coverage, and an IPC request chain are
still unobserved. No trace, source/control startup, drag, keyboard input, or settings
change occurred in this run. D18's uncalibrated C-entry route remains closed.

The next separate prerequisite is a bounded, input-free **System Trace recording
and export qualification** using the installed contract, with exact receipts and
an inspected table of contents. That prerequisite has not run as part of D19.
Even a successful recording/export would require a positive natural-path witness
before it could support an activation/consumer claim or a held-drag extension.
C12, task 07 and PR #45 remain HOLD; task 08 still depends on 07. The owner's
completed physical and v4 results remain valid.
