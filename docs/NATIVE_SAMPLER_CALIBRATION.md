# Controlled native sampler calibration (D22)

## Question and fixed scope

[D21 R2](NATIVE_RECORDER_STARTUP_OBSERVATION.md#r2-process-metadata-retained-bounded-sample-did-not-complete)
retained exact-recorder process metadata on both architectures. Each sampler
was stopped at the unchanged command budget without producing a report. Its
initial message did not establish attachment, a loaded image, a sampled stack,
or a permission denial. This prerequisite asks whether that same bounded
sampling method can produce a complete, identity-bound report for a small owned
native child with a known waiting frame.

D22 is standalone. It starts no recorder, source/control application or product
process. It sends no native input and changes no permission, entitlement,
security setting or preference. There is one sampling attempt per architecture,
with no automatic retry, alternative arguments, timing sweep or longer budget.
The C12 candidate remains `d821d7343675e2850705d141ef9b3b93a6aee945`, tree
`425baa28f00ec24551dd70c0cc874a75fa3be0c1`; PR #45 remains draft, unmerged and
HOLD. The original Finder acceptance condition and task 08 dependency remain.

## Known native control and identity

The workflow compiles `script/native_ui/NativeSamplerCalibration.c` with the
selected Xcode 26.3 toolchain, debug information, frame pointers, disabled
optimization and disabled sibling-call optimization. The expected global frame
is `lemulip_d22_wait_for_release`. The helper's C source SHA-256 is embedded by
the compiler and checked against the execution identity. The binary and dSYM,
their matching UUIDs, native architecture, source copies, build outputs and
loaded-library declarations are retained before execution. A translation probe
rejects a translated runner process.

The helper is a directly owned child in a new process group. It validates its
actual executable path, file hash, loaded Mach-O UUID and compiled architecture
against the expected build identity. Its exclusive ready receipt binds these
values to its PID, parent PID, process group, effective UID, nonce, source digest
and diagnostic commit/tree. Native clock brackets accompany the receipt.

The helper publishes readiness from inside the named function, then waits for
cooperative release through its stdin pipe. The source uses a fixed fifteen-second
safety deadline measured from its first native clock in `main`; a timeout is a
failure, not normal completion. Readiness alone does
not prove that a stack sample saw the waiting frame. The complete sample's
actual call tree must supply that separate positive witness.

## Unchanged sampling boundary

The installed `sample(1)` and `ps(1)` manuals are checked using D21's unchanged
semantic validator before the control child starts. Each manual capture has a
20-second execution deadline plus bounded cleanup and a 2-MiB combined stream
limit. Raw and normalized manuals, command receipts and semantic checks are
retained. Unknown, failed or truncated documentation ends the diagnostic before
the child or sampler starts.

The observation opportunity is fixed at child creation plus three seconds. A
conservative cutoff is set fourteen seconds after the parent begins creating
the child. At least eight seconds must remain when the opportunity is taken;
readiness or scheduling delay does not move that opportunity or extend the
cutoff. An unready, exited or unqualified child cannot be sampled.

The metadata command selects only the exact owned numeric PID:

```text
/bin/ps -ww -p <owned-child-pid> \
  -o pid=,ppid=,pgid=,uid=,lstart=,stat=,comm=,args=
```

There is exactly one permitted sampling command:

```text
/usr/bin/sample <owned-child-pid> 1 10 -mayDie \
  -file <exclusive-work-directory>/controlled-sample.txt
```

| Bound | Fixed value |
| --- | --- |
| Sampling duration argument | 1 second |
| Sampling interval argument | 10 milliseconds |
| Whole sampler command | 4 seconds, including cleanup reserve |
| Normal sampler operation | 3.5 seconds |
| Reserved sampler cleanup | 0.5 seconds |
| Metadata/group command | 1 second each |
| Combined sampler stdout/stderr | 2 MiB |
| Report retention and qualification | 8 MiB |

The nominal one-second duration does not bound symbol acquisition or report
production. Report growth is checked during polling; the limit is not an
operating-system file quota. Final reads require a bounded regular file and
reject symlinks or a changing file. The same D21 nonblocking command transport,
TERM/KILL reserve and final positive group-check principle are reused without
editing D19, D20 or D21 runtime sources.

## Qualification and cleanup

A positive calibration requires all of the following:

1. Native build/source identity and the installed command contract pass before
   execution. Exactly one ready receipt matches the owned child and nonce.
2. Before and after metadata agree on PID, parent PID, process group, effective
   UID and start time, with recognized live states. Command text is advisory.
3. The sampler completes with exit zero, no stop request, stream failure,
   truncation, unresolved cleanup or budget overrun.
4. A complete bounded report binds the same PID and canonical executable path
   to exactly one matching Binary Images entry with the expected UUID and native
   architecture. A symbol name elsewhere in the report is insufficient.
5. The actual call tree contains the exact named frame in the control's image
   with a positive sample count. A zero count, summary-only mention, unrelated
   image, malformed report or missing frame cannot qualify.
6. Observer process groups are positively resolved before releasing the target
   PID reservation. The control child then finishes normally through the
   cooperative release mechanism, with matching completion evidence, closed
   streams and complete owned cleanup. Forced termination cannot produce PASS.

The exact child remains unreaped until every PID-directed sampler/metadata
command and its full owned-group cleanup have finished. A single owner controls
polling and reaping. After normal EOF and exit collection, one final read-only
`ps -A` inventory checks the target's former process group. It cannot attach to
or signal a reused PID; a recycled group number can only conservatively fail
this cleanup check. Target
completion, missing evidence, parse failure, output bounds or the fixed cutoff
stop further observation. Exceptions still receive bounded cleanup; unresolved
ownership, inherited streams or signal failures remain explicit failures.

Raw receipts, reports, streams and clocks remain available even when a gate
fails. Successful cleanup does not erase an interrupted sampler's outcome.
No target discovery, fallback process, second sample or recorder invocation is
part of failure handling.

## Reproduction and provenance

The [workflow](../.github/workflows/native-sampler-calibration.yml) is the full
recipe. It runs the existing portable transport/manual suites and the new D22
contracts, builds the native control, captures provenance, then invokes:

```text
python3 script/run_native_sampler_calibration.py \
  --helper <canonical-evidence-path>/build/NativeSamplerCalibration \
  --output <canonical-evidence-path> \
  --provenance <canonical-evidence-path>/build-provenance.json
```

The executable, output directory, provenance file and retained source/build
directories must already exist at canonical absolute paths. Work and receipt
paths are exclusive. This recipe does not grant a retry after an unsuccessful
attempt.

The workflow fixes all pre-existing tracked sources against D21 result commit
`d20b6b59430856b4bf0dd46dc7220fc1492186b6`; only the five new D22 workflow,
control, Python module, test and protocol files may differ at execution.
Production, input generators, acceptance comparator and prior diagnostics are
unchanged. Build/source inventories are compared before and after the single
attempt. Evidence is uploaded even after failure, with fourteen-day artifact
retention; executed source and the eventual public evidence projection remain
in Git.

## Decision boundary

A positive result qualifies only this controlled child's bounded tool/report
path on that architecture. It does not identify D21's recorder state, explain
recorder noncompletion, establish activation-request coverage or satisfy the
held-drag acceptance gate. A further recorder observation would need a concrete
proposal naming the new recorder-specific evidence and its discriminating
value.

A timeout, access error, missing report/frame, identity mismatch or unresolved
cleanup ends the single attempt and leaves the method unqualified on that
architecture. It supplies no basis for extending time limits, changing
arguments, launching another recorder or rerunning the original held gesture.

## Native results

The first native attempt has not run at this source revision. The portable
fixtures test parsing and process ownership; they are not native sampling
evidence. The executed revision, per-architecture outcome, complete raw-artifact
identities and independently checked public projection will be appended after
the single native attempt.
