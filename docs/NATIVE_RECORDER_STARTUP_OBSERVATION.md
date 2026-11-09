# Recorder startup observation (D21)

## Question and fixed scope

[D20 R2](NATIVE_SYSTEM_TRACE_STARTUP.md#r2-recording-start-notification-not-observed)
invoked one recorder per architecture. Both helpers registered their Darwin
notification successfully, then received zero callbacks during the fixed
15-second wait. No source/control app launched. The recorder streams remained
empty until the helper failed and the orchestrator interrupted its recorder.
Those observations do not identify the recorder's loaded image or initial
call stack, and do not establish a permission denial.

D21 adds one bounded observation of that owned process instance. It asks which
image and sampled call path are observable at one fixed point in startup. It
does not change the original recording command, the native helper's 15-second
notification barrier, source/control launch code, or acceptance requirement.
Sampling can affect timing. Any change in this instrumented run's behavior must
remain attributed to this run; it cannot establish a repair of D20's failure.

The production candidate remains C12
`d821d7343675e2850705d141ef9b3b93a6aee945`, tree
`425baa28f00ec24551dd70c0cc874a75fa3be0c1`. PR #45 remains draft, unmerged and
HOLD. The workflow freezes production, staging, the original native applications,
input producers and acceptance comparator against D19's executed revision, and
the native startup helper/header against D20 result revision
`93c8a8f3a65df385d77876beffafc55bdf4a2d5f`. Its only runtime addition is the
bounded recorder observer. No drag, keyboard, mouse or AX input, activation
repair, permission/settings change, elevated fallback or repeated recording is
part of this protocol.

## Installed contract gate

Before starting the helper or recorder, the D21 CLI captures the installed
`sample(1)` and `ps(1)` manuals with noninteractive pager settings and the C
locale. Each command has a 20-second execution deadline plus bounded cleanup,
and a 2-MiB combined stream cap.
The raw stdout/stderr, argv, status, hashes and byte counts are retained.
Formatting normalization is only for matching; the original manual bytes are
not replaced by the normalized text.

The gate requires the applicable synopsis and descriptive passages: exact PID
selection; sample duration in seconds and interval in milliseconds; `-mayDie`
symbol acquisition; `-file` output-path syntax; and the selected `ps` options
and fields, including the cleanup-only `ps -A` process-group inventory. Missing,
truncated, failed or unrecognised documentation stops the
diagnostic before helper/recorder creation. Matched passages and individual
checks are preserved. There is no alternate flag guess or privileged retry.

This is an explicit pre-execution contract check in the same native CI run.
Apple's archived [sampling guide](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/CodeSpeed/Articles/DiagnosingSlowness.html)
and [launch-metrics guide](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/LaunchTime/Articles/MeasuringLaunch.html)
support PID sampling, duration/interval and `-mayDie`; they do not replace
verification of the installed tool. The public Apple
[`ps` manual source](https://github.com/apple-oss-distributions/adv_cmds/blob/main/ps/ps.1)
describes PID selection and process metadata, including the limitations of
command/argument reporting.

## One observation within the original window

The original helper registers and publishes its prepared receipt before the
original recorder command starts. At the single scheduled point three seconds
after recorder creation, the observer may begin only if the recorder is still
owned, the helper has not finished, and sufficient observation budget remains.
There is no second observation if that opportunity is missed or fails.

Target observation has a conservative stop boundary fourteen seconds after
helper process creation. This precedes the native wait's own deadline because
the helper starts that wait after its preparation and notification registration.
The observer requires at least eight seconds of remaining budget at its trigger;
otherwise it records a skip. No new target observation starts after that boundary;
bounded observer cleanup may finish afterwards without extending helper or
recorder stopping. Actual timestamps and any boundary overrun remain explicit.

The metadata command selects precisely the owned recorder PID:

```text
/bin/ps -ww -p <owned-recorder-pid> \
  -o pid=,ppid=,pgid=,uid=,lstart=,stat=,comm=,args=
```

The single sampling command is conditional on the installed contract and the
pre-sample identity check:

```text
/usr/bin/sample <owned-recorder-pid> 1 10 -mayDie \
  -file <exclusive-work-directory>/recorder-sample.txt
```

A second metadata snapshot follows the sampling attempt when the remaining
budget permits. Both metadata commands have one-second bounds. The sampler's
four-second whole-command budget includes its cleanup allowance; the nominal
one-second sampling duration alone does not bound symbol acquisition or report
production. Its retained stdout/stderr are capped at 2 MiB combined; the retained
report and qualification limit is 8 MiB. File growth is checked during polling,
so this is not an operating-system file-size quota. Output paths, file types,
sizes and final reads are checked; oversized or partial output cannot qualify
as a completed observation.

All active observation steps run through a nonblocking state machine alongside
the original orchestration. Helper completion still requests the original direct
recorder SIGINT in that iteration, then cancels remaining observation work. An
observation deadline, output bound, spawn/read error or early termination is
retained with bounded cleanup. No observer failure postpones recorder stopping
to obtain a better sample.

One final bounded `ps -A -o pid=,pgid=,stat=` snapshot checks the observer's
owned process groups for surviving members. It is cleanup evidence only; it
never selects another sampling target. An unresolved observer or inherited
stream keeps the target PID reserved and the cleanup result incomplete.
An unexpected observer-state failure still gets up to two seconds of ordinary
final cleanup and a separate one-second transport-only fallback. This follows
the original recorder stop request and does not wait for report parsing to
succeed. A retained Darwin EPERM during group escalation can be resolved only
by the final positive group snapshot, an exited direct child, closed streams
and absence of other cleanup faults; the original cancellation/error stays recorded.

## Process ownership, image identity and clocks

The target comes only from the original recorder `Popen`, never a name search,
an inferred child PID or a newly discovered process. The pre-sample row must
match that PID, the orchestrator's parent PID, the recorder's owned process
group, the expected UID and a live state. Raw metadata remains available.
The target child is kept unreaped while an observer could still resolve its
numeric PID, so another process cannot reuse that PID during attachment. One
owner controls all recorder polling and reaping paths, including failure cleanup.

The `ps` command/arguments describe observed metadata and do not prove a loaded
executable. The sample's own process identifier, path and binary-image evidence
must support any runtime-image statement. If the owned process is still
`xcrun`, that is the result; D21 does not follow another process to obtain an
`xctrace` sample. Before/after mismatches, zombie states, access failures and
missing report fields remain explicit incomplete states.

Observer clocks and elapsed times are retained with the command receipts.
The native helper separately retains its Mach absolute/continuous brackets,
system uptime, boot UUID, timebase and first notification callback. The actual
ordering must be inspected before describing a sample as pre-notification.
A scheduled time does not prove that a callback had not already occurred.
The notification is not a trace epoch or an authenticated sender identity.

Apple documents [runtime protections](https://developer.apple.com/library/archive/documentation/Security/Conceptual/System_Integrity_Protection_Guide/RuntimeProtections/RuntimeProtections.html)
that can restrict process inspection. Same-user ownership does not prove this
particular executable can be sampled. An observed access error is preserved
without changing SIP/TCC, entitlements, privileges or the target.

## Evidence and decision rules

Portable checks exercise real owned child-process lifetimes, output bounds and
failure cleanup. Their metadata/report fixtures are synthetic and establish no
Apple-tool access or activation evidence. Installed-man recognition, actual
`ps` metadata and sampling of the real recorder remain native CI gates.

The two native jobs use Xcode 26.3 on `macos-15` ARM64 and `macos-15-intel`.
They retain the original staging/binary/source identities, input inventories,
manual contracts, recorder observation, original helper/recording receipts and
any bounded trace/export evidence. The workflow preserves fourteen exact source
files and publishes only the evidence directory, with 14-day artifact retention.
The durable result must bind those bytes to the executed commit and artifact
digests, with any public-projection omissions enumerated.

An observation may expose a specific initialization or request call path.
A generic IPC wait, a symbol's presence or a nearby timestamp does not prove
authorization denial, deadlock, an OS defect or the missing drag requester.
Statistical sampling can miss calls. Even an authorization-related frame does
not establish that authorization was denied.

Observation completion and the unchanged D20 recording/export qualification
are separate results. Neither closes the original Finder
**enter → exit → reenter → Escape → release → distinct fresh drop** gate across
three themes and two architectures. Task 08's completed C12 source and twelve
original screenshots remain valid; final closure still depends on task 07.
The physical check and v4 evidence remain complete.

After this one observation, inspect the retained image, frames, identity and
notification ordering. A further change requires a concrete new boundary
supported by those results. A timeout, access error or generic wait supplies no
basis for longer waits, blind repetition, security changes or a held gesture.
