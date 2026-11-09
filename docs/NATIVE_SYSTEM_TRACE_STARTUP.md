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

The protocol permits **one recording-command invocation per architecture, with
no drag, keyboard, mouse, AX or directed Escape input**. There is no C interposition library, runtime hook,
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

D20 R2 has completed with **evidence-incomplete on both architectures**. The
helper compiled, registered its notification and published its prepared receipt,
but received no recording-start callback within its fixed wait. Neither original
app was launched; no trace package or export was produced. The exact result and
its limits follow below. Local checks verify bounded orchestration and parsing;
the native result determines whether the recording/startup prerequisite occurred.

The later [D24 recorder-progress result](NATIVE_RECORDER_PROGRESS_OBSERVATION.md)
does not reclassify D20: it retained an Intel callback and partial trace, but
neither a qualified sampler stack nor normal recording completion. D25's
bounded read-only TOC export of an exact retained copy is the next step and has
not run. The subsequent result and its refusal boundary are recorded below.

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

R1 produced no completed recording to retry. R2 was the first run that passed
helper compilation and issued the specified recording command after the header
import fix.

### R2: recording-start notification not observed

[Run 42567849171](https://github.com/osmankaankars/lemulip/actions/runs/42567849171),
attempt 1, executed `1462bf597c52727ede7ee20991c65016e8b3086a`, tree
`071467586f6b95d1b5ad5ab57ac5c97349a3526f`, on 9 November 2026,
05:31:57–05:35:12 UTC. ARM job `128998197463` and Intel job `128998197228`
both passed source/privacy checks, all six bounded-command and ten orchestration
tests, original app compilation, the corrected helper build and provenance
collection. The recording/orchestration step returned `evidence-incomplete` on
both; input preservation, staged archiving, source checks and artifact upload
then completed. The [machine-readable D20 evidence](evidence/D20-system-trace-startup.json)
binds these results to the executed sources and retained artifacts.

| Retained observation | ARM64 | Intel |
| --- | ---: | ---: |
| Helper PID | 3942 | 11445 |
| Recorder PID | 3943 | 11450 |
| Notification registration status | 0 | 0 |
| Received callback count | 0 | 0 |
| Observed notification wait, seconds | 15.002533 | 15.106861 |
| Notification cancellation status | 0 | 0 |
| Control/source launch requests | 0 / 0 | 0 / 0 |
| Recorder stdout / stderr bytes | 0 / 0 | 0 / 0 |
| Recorder exit status after direct SIGINT | -2 | -2 |
| Unchanged staged input entries | 124 | 124 |

Each helper reports `startupNeverRan=true`,
`startupSkipReason=recording-notification-timeout`, and exit code 1. Both
process entries retain `launchRequested=false`, null PIDs and empty readiness
records. Source, receiver and activation journals are absent. These are
unlaunched applications; this run did not observe their natural activation or
their drag-session lifecycle.

The orchestrator sent one SIGINT to its exact recorder process after the helper
returned the timeout error. Both recorder processes exited with status -2. No
recording-start callback was observed before this interruption; the command's
nominal 30-second recording cap was not reached. No
helper signal, forced recorder group cleanup, signal error or stream error was
recorded. The final bounded group snapshots contain no live members, inherited
streams are closed, and `cleanupComplete=true`. There were no owned application
launches requiring termination. The 80-second helper abort path and its
45-second cleanup grace were not used.

No `recording.trace` package existed at packaging time; its failure receipt
records that absence. No TOC, process or table export was invoked. Recording,
startup, export and trace-package completion are all false, and activation
calibration remains `unproven`. Both 124-entry input inventories remain
unchanged. No drag, keyboard, mouse or AX input, settings change, permission
change, hook or held-gesture extension occurred.

#### Retained R2 evidence and verification

| Architecture | Artifact | ZIP bytes | ZIP SHA-256 |
| --- | ---: | ---: | --- |
| ARM64 | `13652345999` | 9,156,312 | `79e754abbeb815dd8dd397411874c74e44aa6420f2722b274786236e73f01f54` |
| Intel | `13652471388` | 9,253,033 | `8f382e26c9421a8e75c6def98a95c2b8f057eae208a95aaad488f1ef0c3531fe` |

Each R2 archive contains 62 files. Its nested staged archive contains 127 entries
(75 files and 52 directories), including the original empty fixture directories
and the helper's empty evidence directories. All outer ZIP digests, CRCs and
extracted bytes, all ten retained sources per architecture against the executed
Git revision, and all 124 immutable input entries against the actual staged
archive were checked. Helper/app binary hashes, Mach-O UUIDs, provenance and
receipt/stream bindings were also independently verified without executing the
archived binaries. R1's two 14-file bootstrap/build archives were checked
separately; they contain no completed helper or recording evidence.

The public projection indexes all 152 outer-archive files across R1 and R2 and
every R2 staged entry. It retains all twelve top-level R2 JSON receipts per
architecture as parsed objects, with runner-local path strings or maps keyed by
those paths replaced with null. Every such replacement has an exact JSON
pointer and a hash of the original value's explicitly defined canonical JSON;
the original files also retain their separate raw-byte hashes. All other JSON
values and the selected UTF-8 text bodies are preserved exactly. Binary,
source-body and local-path text omissions are enumerated. Executed source
bodies remain available through immutable Git links. Original artifacts have
14-day retention; the result, identities and public projection persist in Git.

#### Interpretation and next prerequisite

The observation is precise but limited: the recorder command was invoked and
remained running until the helper failed, while the registered helper observed
no start callback and the retained recorder streams stayed empty. These bytes
do not establish why the recorder was silent before that boundary. They do not
demonstrate a tracing permission denial, a broken notification channel, a
particular initialization wait, or an activation-path failure. A completed
System Trace recording and its actual export schema remain unqualified.

The next prerequisite is a supported observation of the recorder's initial
tool-start state and start-notification path that can distinguish those missing
states. A concrete observation and stopping condition are needed before another
qualification attempt. This result supplies no basis for widening the timeout,
blindly repeating the command, changing permissions, or treating empty output as
proof of a particular cause. The original Finder acceptance gate, C12/PR #45
HOLD, task 08's dependency and the completed physical/v4 evidence are unchanged.

The next researched observation is one bounded sample of the exact still-owned
recorder PID, paired with process metadata, within the existing notification
window. Apple's archived [sampling guide](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/CodeSpeed/Articles/DiagnosingSlowness.html)
and [launch-metrics guide](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/LaunchTime/Articles/MeasuringLaunch.html)
document PID-targeted stack sampling; the published
[`ps` manual](https://github.com/apple-oss-distributions/adv_cmds/blob/main/ps/ps.1)
describes process selection and identity fields. The installed manuals must
confirm the current arguments before execution. This observation has not
been implemented or run in D20. The subsequent
[D21 protocol](NATIVE_RECORDER_STARTUP_OBSERVATION.md) implements that check as
a fail-closed installed-manual preflight before creating its helper or recorder.
The observation needs its own finite sampler deadline,
output bounds, exact PID/instance binding and an explicit account of timing
perturbation. A sample can expose observed initialization or request callers;
a generic IPC wait cannot establish authorization denial, deadlock or the
missing drag requester. Sampling access to this Apple-signed process is also
unproven. No elevated fallback follows from a failure to obtain a sample.

### Subsequent D21 observation

[D21 R2](NATIVE_RECORDER_STARTUP_OBSERVATION.md#r2-process-metadata-retained-bounded-sample-did-not-complete)
executed that bounded observation in
[run 42583779680](https://github.com/osmankaankars/lemulip/actions/runs/42583779680),
at `72e59791f59ae0b6e1de367639f43e161303a828`. Both architectures retained exact
owned-recorder metadata. Each single sampler attempt reached its fixed command
budget and exited -15 after TERM without a report; no stack or loaded image was
qualified. Both unchanged helpers again received zero callbacks and launched no
apps. Final observer/recorder cleanup resolved, inputs stayed unchanged, and no
trace/export followed. The sampler's cleanup EPERM is not a target-inspection
access error. The proposed next prerequisite was standalone positive sampler calibration
on a small owned child under the same budget, without another recorder run.
D20's pre-start cause and the original acceptance gate remain unresolved.

[D22](NATIVE_SAMPLER_CALIBRATION.md) has now run that control once per
architecture. Both samplers completed in about 1.47 seconds and retained the
known frame, but the strict identity parser rejected unequal masked display
paths before a post-sample identity snapshot. The full control gate remains
incomplete; the new report/UUID/address witnesses are retained separately.
[D23's offline identity/frame review](NATIVE_SAMPLER_IDENTITY_REVIEW.md) now
verifies that narrow witness on both unchanged archives with 39 portable tests
and independent reconstruction. The original D22 full gate stays incomplete.
No new recording, input or budget change occurred; D20's cause remains unresolved.

### Subsequent D24 partial-recording evidence

[D24 R2](NATIVE_RECORDER_PROGRESS_OBSERVATION.md) completed in
[run 42609635410](https://github.com/osmankaankars/lemulip/actions/runs/42609635410),
with 81 passing tests on each macOS architecture. All four primary/secondary
samplers retained only their 84-byte initial banners; none produced a report or
qualified internal phase. ARM received zero callbacks and retained no trace.

Intel received one callback at helper-native +14.109752 seconds. Its first
recorder output was observed at parent recorder-relative +11.31 seconds, after
both sampler operations had ended. These clock domains remain separate. The
recorder exited -11 after stopping/escalation, so normal completion is unproven.
The retained partial trace contains 115,835,304 expanded bytes. Read-only
inspection verifies those bytes and one literal `Data stream: Time Mapping`
issue; it does not establish the issue's semantics or event-time coverage.

D25 will ask only whether a bounded read-only installed
`xctrace export --input … --toc` can read an exact retained copy. This export
has not been performed; preserve refusal without package repair or a new
recording if the input is rejected. No natural source/control startup,
activation path or original Finder acceptance is qualified by D24. C12/HOLD
and task 08's dependency remain unchanged.
