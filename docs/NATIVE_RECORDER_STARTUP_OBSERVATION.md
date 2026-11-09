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

## R1: installed-manual recognition stopped before runtime observation

[Run 42583070469](https://github.com/osmankaankars/lemulip/actions/runs/42583070469),
attempt 1, ran on 9 November 2026, 08:02:01–08:05:58 UTC, at
`ea57f66f50ec170caeb097f702e093a31bbbb1d3`, tree
`8c7f57d903a9f7af3e78181026eb42a6c0f90e76`. ARM job `129046216128` and
Intel job `129046216378` both passed the six bounded-command, ten original
orchestration and fourteen observer tests, all builds and source/provenance
checks. Input preservation and artifact upload completed after the observation
step stopped at its manual preflight.

Both installed-man commands exited zero with complete bounded captures.
All `ps` semantic checks and the sample synopsis check passed. Five sample
checks failed: PID definition, duration units, interval units, `-mayDie` and
`-file`. The retained manuals explain the false rejection: those definitions
and option paragraphs are under **ARGUMENTS**, while R1 searched DESCRIPTION
and OPTIONS. The argument paragraph also defines seconds and milliseconds in
separate clauses of one sentence, which R1's whole-sentence unit exclusion did
not recognise.

The gate stopped before helper, recorder or sample creation. No startup,
recording, application launch or input occurred. This run therefore supplies
installed documentation, not a failed runtime sampling attempt.

| R1 architecture | Artifact | ZIP bytes | ZIP SHA-256 |
| --- | ---: | ---: | --- |
| ARM64 | `13658136399` | 9,193,557 | `3193ae75ffcc367e1f4a1bdf79668bec56c8d72890165487cf822742e16d755d` |
| Intel | `13657654327` | 9,290,455 | `1103e145792c094a3bcae9a3ce0d0beff7d9c82b2214dbd7358c9230fd47fdc2` |

Each archive contains 66 files. Both raw sample manuals are 4,490 bytes; their
SHA-256 identities are
`253f16336d7cc4b1441e34358ee8220c57bdd5a1c5fd0a5fd835e96292617cf6`
(ARM) and
`04221ddc0cfed094820524f54e5dc4e018002fbb84a17e7603c18356cea4e615`
(Intel). The relevant normalized synopsis and argument sections agree.

The narrow R2 correction recognises ARGUMENTS explicitly and checks the ordered
parameter definitions and their individual unit clauses. Missing definitions or
swapped units still fail. Both retained native manual pairs pass all twenty
checks when replayed through the corrected validator. A focused regression
fixture binds its source-manual identities without copying the complete manual.
The observer runtime, command arguments, process ownership and all time/output
bounds are unchanged. R2 is the first runtime-observation attempt after that
pre-execution parser correction.

## R2: process metadata retained; bounded sample did not complete

[Run 42583779680](https://github.com/osmankaankars/lemulip/actions/runs/42583779680),
attempt 1, ran on 9 November 2026, 08:08:17–08:12:10 UTC, at
`72e59791f59ae0b6e1de367639f43e161303a828`, tree
`338e5dd9aabbe9c861c4dba49b2b7cdbb6fe4671`. ARM job `129048547705` and
Intel job `129048547948` both passed all thirty-one portable checks
(6 + 10 + 15), source/privacy checks, builds, provenance and all twenty installed
manual checks. The observation step returned `observation-incomplete` and the
original transport returned `evidence-incomplete` on both. Subsequent input
preservation, archiving, source checks and artifact upload completed.

The [retained D21 evidence](evidence/D21-recorder-startup-observation.json)
binds both runs to their sources, actual receipts and original artifact hashes.

| R2 observation | ARM64 | Intel |
| --- | ---: | ---: |
| Native helper PID | 3633 | 8861 |
| Recorder PID / parent PID | 3636 / 3593 | 8866 / 8808 |
| Recorder PGID / effective UID | 3636 / 501 | 8866 / 501 |
| Pre-sample process state, exact text | `U<s` | `R<s` |
| Sample invocations | 1 | 1 |
| Sampler PID | 3659 | 9011 |
| Sampler TERM after creation, seconds | 3.513134 | 3.525102 |
| Sampler elapsed time, seconds | 3.805801 | 3.795072 |
| Sampler exit status | -15 | -15 |
| Sampler stdout / stderr bytes | 0 / 84 | 0 / 84 |
| Received recording-start callbacks | 0 | 0 |
| Native notification wait, seconds | 15.005476 | 15.037163 |
| Original recorder exit after direct SIGINT | -2 | -2 |
| Unchanged staged input entries | 124 | 124 |

Both first identity snapshots select the exact still-owned recorder instance,
with matching parent, group and effective UID. Their argument text describes
the installed Xcode 26.3 `xctrace record` command. This is advisory process
metadata; it does not qualify the loaded executable image. The leading process
states differ: the installed `ps` manual describes U as uninterruptible wait and
R as runnable. These are single snapshots without a waiting call, stack or
duration. The ARM state cannot establish a common cause across both runs.

Each sampler's only retained output is its 84-byte stderr announcement of the
selected PID, one-second sampling duration and ten-millisecond interval. The
announcement does not prove target attachment or completed sampling. Neither
command finished within the 3.5-second operation allowance of its unchanged
four-second total budget. The orchestrator then sent TERM and observed exit
status -15. No sample report was retained; the post-sample identity command was
not reached. There is no observed stack or qualified binary-image/UUID witness.
The one-second sampling argument does not establish a whole-command runtime
bound for symbol acquisition and report production.

### Cleanup and original notification boundary

The subsequent owned sampler-group KILL attempt returned EPERM on both
architectures. These errors belong to cleanup after TERM; they are not
target-inspection access-denial results. The final bounded raw group snapshots
contain no surviving members of the observed groups. Exited direct children,
closed streams and absence of other cleanup faults allow the narrowly specified
group proof to resolve cleanup while retaining the original signal errors and
`command-budget` result. The earlier `observer-sample: cleanup-incomplete`
message remains in the error history; final observer cleanup is true. No
interrupted sample is promoted to success.

Both target PID reservations were acquired before identity/sampling and released
only after this cleanup proof, before the conservative fourteen-second cutoff.
Observer clocks preserve identity, sample, group check and release ordering.
The original recorder SIGINT followed observation of helper exit by approximately
9.990 ms on ARM and 1.688 ms on Intel. The observer did not extend that stop
boundary, force the recorder's group or send signals to the native applications.

Both native helpers registered and cancelled the notification successfully, with
zero callbacks throughout their fixed wait. They returned
`recording-notification-timeout` and `startupNeverRan=true`. Neither original app
was launched: request flags are false, app PIDs are null and native journals
are absent. Recorder stdout/stderr remain empty. No trace package or export was
produced; all recording/startup/export qualification flags remain false. Both
original transports report complete cleanup. Sampling can perturb timing, so
these instrumented results do not retrospectively identify D20's process image
or explain its pre-start silence.

### Artifact identities and independent verification

| R2 architecture | Artifact | ZIP bytes | ZIP SHA-256 |
| --- | ---: | ---: | --- |
| ARM64 | `13657739461` | 9,216,861 | `e10b353cc93d5ef64a0ba9039e8bbdc64f485aa6465df2765641387666e6dad3` |
| Intel | `13657919122` | 9,313,374 | `4285c46481aa8b930edb3bb1c41f95cf6941799645c5604455fa6b1b104f092a` |

Each R2 archive contains 87 files and a 127-entry staged ZIP (75 files and 52
directories). R1's corresponding staged archives contain 125 entries (75 files
and 50 directories), because its helper never created the two empty evidence
directories. The complete four-archive audit verified API size/digest identities,
ZIP CRCs, every extracted byte, all 56 retained source copies against their
executed Git revisions, all 504 staged entries and 496 immutable-input checks.
The twelve diagnostic executable/dSYM UUID pairs, binary hashes, architecture,
provenance, command streams and helper receipt bindings also agree. Archived
code and binaries were not executed during this audit.

The public projection indexes all 306 original files, preserves 54 parsed JSON
receipts except 136 individually enumerated omissions, and retains 88 complete
UTF-8 text bodies. Forty additional text bodies preserve exact lines and line
endings except forty runner-local path lines, each separately size/hash bound.
JSON omissions have exact pointers and hashes of explicitly defined canonical
values. They cover runner-local path values/maps and installed-manual passage
bodies; all other values remain exact. All sixteen full raw/normalized manual
bodies are omitted from the public projection but retain their raw identities,
semantic-check results and original-artifact availability. Executed source
bodies are linked at immutable revisions. Artifact retention is fourteen days;
the report, projection and source revisions persist in Git.

### Decision and next discriminating prerequisite

D21 obtained new exact-process metadata and established that the specified
bounded sampling attempt did not produce a report on either architecture. It
does not explain recorder startup, establish a tracing/sampling permission
denial, or identify the activation requester or Escape consumer. The original
Finder acceptance requirement, C12/PR #45 HOLD and task 08 dependency remain.

The next prerequisite is a **standalone positive sampler calibration on a small,
owned native child**. It needs one attempt per architecture using the same fixed
observation timing, `1 10 -mayDie -file` arguments and four-second total budget,
including the existing cleanup reserve. The child should publish a bound ready
receipt while remaining in a known, named waiting frame. No new `xctrace record`
invocation is needed for this prerequisite.

A positive result requires exact child ownership, a complete bounded report,
successful sampler exit without interruption, matching report PID/path and
binary-image/UUID evidence, the expected named frame with a positive sample
count, and resolved cleanup. A timeout, access error, missing report/frame or
identity mismatch ends that single attempt and leaves the bounded method
unqualified; it supplies no basis for a longer timeout or another recorder run.
A pass qualifies only the controlled child's sampler/report path. A further
recorder observation would still need a concrete proposal for new
recorder-specific evidence. No held gesture or security change follows from
this result.
