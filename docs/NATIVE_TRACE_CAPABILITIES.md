# Native tracing capabilities (D19)

## Question and fixed scope

D18 completed with valid zero-call receipts and no natural C-entry calibration.
Its proposed interposition route remains closed. D19 first obtains the actual
installed tracing-tool contracts on the unchanged ARM and Intel CI runner labels
with Xcode 26.3. This is **tool discovery, not a trace recording, activation
calibration, or drag acceptance test**. No source/control application is launched.

The exact missing evidence remains the earlier activation request/client context
or the source drag-tracking consumer's disposition of Escape, described in the
[investigation packet](NATIVE_DRAG_UPSTREAM_INVESTIGATION.md). Production C12,
PR #45, the original Finder gate, and completed physical/v4 evidence are unchanged.

## New primary-source evidence

Apple's historical [AppKit release notes](https://developer.apple.com/library/archive/releasenotes/AppKit/RN-AppKitOlderNotes/),
under **Spring Loaded Drag & Drop**, describe automatic window spring-forward
on hover separately from an application's optional custom spring-loading controls.
An absent owned `NSSpringLoadingDestination` handler therefore does not exclude
that automatic window behavior. This narrows the semantic question; it does not
prove that the same implementation caused D17's macOS 15 transitions or explain
the failed cancellation. The retained timing counterexamples still apply.

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

Four focused subprocess checks exercise nonzero stream retention, output limits,
deadlines, and a leader that exits on termination while its same-group descendant
ignores that signal. Review reproduced the last cleanup gap before publication;
the collector now escalates the owned group independently of leader/pipe state.

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

Prepared on 9 November 2026 Europe/Istanbul. Native inventory has not run at this
protocol revision. Results will retain their exact executed revision and separate
tool availability, recording access, exported data and causal coverage.
