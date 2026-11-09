# Natural-startup System Trace prerequisite (D20)

## Question and fixed scope

[D19](NATIVE_TRACE_CAPABILITIES.md) established that both native CI architectures
have Xcode 26.3's **System Trace** template and its bounded recording, Darwin
start-notification and XML export contracts. It did not record anything. D20
asks whether one ordinary startup of each unchanged owned AppKit source/control
can be recorded and exported, and whether that evidence contains an actual
activation-request call stack. Recording success alone does not answer the
second question.

The production candidate remains C12
`d821d7343675e2850705d141ef9b3b93a6aee945`, tree
`425baa28f00ec24551dd70c0cc874a75fa3be0c1`. It is built for the existing staging
fixture and is not launched. Original `NativeDragControl.swift` and
`NativeDragSource.swift`, staging code, fixture contents, native input producers,
and the acceptance comparator remain byte-identical to D19's executed revision
`daf90a14cbe0e5855e2e4a3e69dc8c170700635d`. The source/control are compiled with
debug information and normal ad-hoc signatures; their exact binaries, UUIDs,
architecture, load commands, dependencies and source hashes are retained.

This is **one recording per architecture, with no drag, keyboard, mouse, AX or
directed Escape input**. There is no C interposition library, runtime hook,
injected activation, debugger attachment, global preference change, authorization
change, privilege escalation or recording retry. D18's uncalibrated C-entry route
remains closed. The owned applications follow their existing natural launch and
activation code, including normal `NSWorkspace` launch behavior. The helper's
own PID and executable identity are retained because an activation request may
originate in the launcher rather than the child application's explicit call.

## Recording sequence

The Swift helper validates the original staging inputs, executable identities,
architecture and C12 provenance. It uses a prohibited activation policy. It
registers one unique `app.lemulip.d20.recording.<UUID>` Darwin notification on a
private serial dispatch queue, then exclusively publishes an atomic
`helper-prepared.json` receipt. The Python orchestrator validates that receipt
against the exact helper process, nonce and executable before starting the
recorder.

The sole recording invocation is:

```text
xcrun xctrace record --template "System Trace" --all-processes \
  --time-limit 30s --no-prompt \
  --notify-tracing-started app.lemulip.d20.recording.<UUID> \
  --output <exclusive-work-directory>/recording.trace
```

The helper waits at most 15 seconds for the real notification. It launches no
application if notification registration or that wait fails. After receipt, it
launches the original control and then source once each, waits for their normal
ready/active lifecycle evidence, and performs the existing owned cleanup. It
records launched PIDs, launch callbacks, native journals, zero drag-session
checks, input preservation and cleanup outcomes. Notification receipt is a start
barrier; it neither authenticates the notification sender nor identifies the
trace's timestamp epoch.

The orchestrator observes helper and recorder concurrently. After helper exit it
requests recorder finalization with SIGINT. An earlier recorder exit, including
the fixed 30-second recording cap while the helper is still running, makes the
recording incomplete. Startup/readiness bounds are not shortened to fit that cap.
If the helper exceeds its 80-second wall bound, the orchestrator sends one
cooperative SIGTERM to that exact helper and allows 45 seconds for its normal
owned cleanup. It never sends signals to application PIDs or the helper's process
group. The helper's dispatch signal handler sets a cancellation latch checked by
its wait loops; cleanup remains bounded and runs independently of that latch.
Any unresolved cleanup blocks subsequent export work and is retained as failure
evidence.

## Export and resource bounds

The recording is created in a fresh work directory outside the uploaded evidence
directory. Helper and recorder streams have bounded retention, deadlines and
explicit stop receipts. Finalization or cleanup signals, output truncation,
nonzero exits and missing files are recorded; they cannot become a complete
recording merely because an archive exists.

After complete recording and helper cleanup, the orchestrator exports the
actual table of contents with `xctrace export --toc`. It requires exactly one
run, then requests the installed manual's documented processes entity. It
constructs a table selection from the observed run's actual table nodes; no
invented schema name or later-Xcode recording option is used. TOC export has a
30-second deadline and 2-MiB output cap. The process and table exports each have
a 45-second deadline and respective 32-MiB and 64-MiB output caps. Raw XML, command argv, exact
stream hashes, statuses and byte counts are retained. Invalid, truncated or
unsupported output stops qualification rather than being treated as an empty
successful table.

The original `.trace` bundle is separately packaged with a 256-MiB expanded-byte
limit and 16,384-entry limit; symlinks and unsupported entry types are rejected.
The ZIP is published exclusively only after completion and CRC verification.
Exceeding a package bound produces a failure receipt and no unbounded trace
upload. The workflow separately preserves the staged fixture and journals, all
diagnostic sources, build provenance, binaries and input inventories. It uploads
only the evidence directory. Available bootstrap/build receipts survive a
pre-recording failure. GitHub artifact retention is 14 days; durable public
results must identify executed sources and explicitly disclose any body omitted
from their evidence projection.

## Clocks, identity and positive-evidence gate

The helper retains bracketed `mach_absolute_time`, `mach_continuous_time` and
system-uptime observations, the Mach timebase and boot-session UUID. A recording
notification clock is not assumed to equal trace time zero. Any later
cross-stream ordering must first establish the trace's actual clock/epoch from
retained metadata, or use a justified bracket with its uncertainty stated.

Before declaring natural activation calibrated, inspect the actual exported
schema, event type, process/thread identity, timestamp meaning and frame chain.
A qualifying witness must identify a real outbound activation request on this
natural path in an event-specific syscall/thread-state stack. A generic
`mach_msg` receive wait, a sampled nearby stack, application-active callback,
symbol's presence, startup success, or a daemon message at a nearby time does not
establish that witness. Frame UUID/load-address/symbol relationships must agree
with the retained binary identity where applicable. Missing stacks remain
inconclusive; they do not establish absence of a request.

Pairing a client event with a daemon action additionally requires actual
request/message identity and operation evidence. A message ID, PID, timestamp,
thread wakeup or previous-frontmost PID alone is insufficient. Object reuse and
capture loss must be considered if a kernel message identity is available.
The exported fields, not a different kernel source revision, determine what this
recording can support.

Even a positive natural-startup witness covers that observed route only. It does
not establish coverage of a held-drag automatic window decision or of the
source's Escape consumer. A later extension requires a separately specified
boundary and coverage argument. No held gesture follows automatically from
recording/export success.

## Interpretation and current status

At initial protocol preparation, D20 had **not run**. Local checks can verify bounded
orchestration, process handling, archive parsing and command selection; this
Linux workspace cannot compile AppKit or establish native tracing access. The
native matrix is the compile, recording and export gate.

Results must distinguish: build/infrastructure failure; recording/access failure;
incomplete startup or cleanup; export/packaging failure; complete recording/export
with activation coverage unproven; and an independently inspected positive
natural-path witness. The orchestrator defaults to **activation calibration
unproven**, even after a complete recording/export. Only inspected evidence can
support a stronger interpretation.

C12, task 07 and draft PR #45 remain **HOLD**. The original Finder
enter → exit → reenter → Escape → release → distinct fresh-drop acceptance across
three themes and both architectures is unchanged. Task 08's source/screenshot
review and the owner's completed physical/v4 evidence remain valid; its final
closure still depends on task 07. This prerequisite adds no acceptance case.

### R1: native helper compilation stopped before recording

[Run 42567416345](https://github.com/osmankaankars/lemulip/actions/runs/42567416345),
attempt 1, executed `f1c29401fcf747bbe96a97d938a4c02b534ca0ca`, tree
`98f82088ea4ef0bd224aee7a881ce0a5fcfa76ae`, on 9 November 2026,
05:27:23–05:30:32 UTC. ARM job `128996858327` and Intel job `128996858546`
both passed source/privacy checks, the six bounded-command tests and ten
orchestration tests, C12 build/staging, and original source/control compilation.
The new helper then failed to compile: `notify_register_dispatch`, `notify_cancel`
and `NOTIFY_STATUS_OK` were not visible through its Swift imports. Preparation,
recording, export and source/control startup did not run. This is a build result,
not a native behavior or tracing-access result.

Apple's public [Libnotify header](https://github.com/apple-oss-distributions/Libnotify/blob/main/notify.h)
declares these APIs; its [manual synopsis](https://github.com/apple-oss-distributions/Libnotify/blob/main/notify.3)
specifies `#include <notify.h>`, and its
[module map](https://github.com/apple-oss-distributions/Libnotify/blob/main/notify.modulemap)
defines a separate `notify` module. The narrow R2 correction exposes the actual
installed SDK headers to this helper with Swift's `-import-objc-header` option.
It includes `<dispatch/dispatch.h>` and `<notify.h>` without handwritten ABI
declarations. The Swift behavior, notification mechanism, original applications,
recording command, resource bounds and qualification gates are unchanged. The
bridge header is retained with the diagnostic sources and triggers the same
isolated workflow when edited. Actual compilation remains the native SDK gate.

R1 retained bootstrap test outputs and the two original app build products;
job logs retain the compiler diagnostics. Its artifact identities are:

| Architecture | Artifact | ZIP bytes | ZIP SHA-256 |
| --- | ---: | ---: | --- |
| ARM64 | `13652485177` | 2,225,064 | `5f6bdf4af84d24a29079d59649980a8d3981b39242008497ef551ee8660467f9` |
| Intel | `13652191507` | 2,242,987 | `33370c9e4b47d3b1bc961a48fc801896c459617b7e9f40e3666dda37a906d768` |

R1 produced no completed recording to retry. R2 is the first opportunity for the
specified notification-gated recording to execute after the header import fix.
