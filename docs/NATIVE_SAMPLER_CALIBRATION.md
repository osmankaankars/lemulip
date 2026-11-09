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

## R1: reports produced; strict path identity remained incomplete

[Run 42588874357](https://github.com/osmankaankars/lemulip/actions/runs/42588874357),
attempt 1, executed on 9 November 2026 from 08:50:34 to 08:51:39 UTC
(11:50:34–11:51:39 Europe/Istanbul). The executed source is
`10ececdd145ca4c857c5844a83cee0b0b3a5d8e2`, tree
`6219e264ff2df60c16b1be5063643808569a09eb`. ARM job `129065269816` and Intel job
`129065269387` both ended in failure at the calibration step. Their 43 portable
tests (6 + 10 + 15 + 12), native C compilation, build/source provenance,
twenty installed-manual checks, immutable-input comparison and artifact upload
all passed.

The original execution results are retained without promotion:
`status=calibration-incomplete` and `controlledSamplerCalibrationComplete=false`
on both architectures. The [public evidence projection](evidence/D22-native-sampler-calibration.json)
preserves all retained receipts and text, subject to individually enumerated
privacy/manual-body omissions, together with the original archive identities.

### New positive observations

| Observation | ARM64 | Intel |
| --- | ---: | ---: |
| Owned target PID / parent PID | 2421 / 2381 | 1972 / 1932 |
| Initial process state / effective UID | `S<s` / 501 | `S<s` / 501 |
| Sampler PID / invocation count | 2433 / 1 | 1985 / 1 |
| Observed sampler elapsed time | 1.470622 s | 1.470460 s |
| Sampler exit / stop request | 0 / none | 0 / none |
| Retained report bytes | 7,988 | 7,983 |
| Expected waiting-frame sample count | 82 | 97 |
| Native child elapsed time | 4.615102 s | 4.610197 s |
| Native child completion | stdin EOF, exit 0 | stdin EOF, exit 0 |
| Forced termination / signal errors | none / none | none / none |
| Immutable build/source entries | 51 unchanged | 51 unchanged |

Both single commands completed comfortably within the unchanged 3.5-second
normal-operation allowance and four-second total budget. Their stderr includes
completion and report-written messages, and the actual report files are
retained. The result is stronger than D21's announcement-only output.

Both reports identify the exact owned numeric PID and expected parent PID,
the ten-millisecond interval, native architecture and `/usr/bin/sample` as the
analysis tool. Their actual call graphs contain `main` →
`lemulip_d22_wait_for_release` → `poll`, with the positive counts shown above.
The matching image UUID is the same as the built executable, dSYM and native
ready/completion receipts. The sampled frame address is inside that image's
reported address range, whose start agrees with the report's main load address.
These are limited observations audited from the original bytes; they do not
turn the full execution gate into PASS.

| Retained identity | ARM64 | Intel |
| --- | --- | --- |
| Mach-O UUID | `DA0DE39D-199B-426C-938A-D111DA3D942E` | `5CA00F5F-6107-4C8C-B368-BF38515252AD` |
| Main load address / image range start | `0x102c90000` | `0x10b87a000` |
| Image range end | `0x102c93bfb` | `0x10b87d907` |
| Expected-frame program counter | `0x102c90674` | `0x10b87a69c` |
| Report SHA-256 | `b3cf4841c437a03a94b56354f9fa946f64a51ec6792d385a61cb4150102087d7` | `16c03839ed3b965b3c48ad94b1c0f01f846e2c0dac792cc310aa1289928b106c` |
| Executable SHA-256 | `fd510699e739318f70e372da93096df279a5b06fc5cfcf8637cd21542f4356ad` | `d9cda95090a7765f55c0191bcac238b0a8d4694a181b0cdf01b2ef11e953598f` |

### Why CI stopped

The native reports mask the executable path. The header has a `USER` owner
placeholder followed by a wildcard segment, whereas its Binary Images row has
one wildcard segment without that owner placeholder. Both retain the expected
executable basename, but the two strings differ from each other and from the
canonical owned path in the native receipt.

The unchanged D21 image parser first requires one Binary Images path identical
to the report header path. It therefore raises:

```text
Reported process path lacks one matching loaded binary-image entry
```

D22's additional canonical-path equality check was not reached. The strict
parser failure also prevented the post-sample `ps` identity command. There is
no `identity-after.json`, no successful `sampleQualification`, and no established
before/after start-time comparison. A normal native completion receipt is
retained separately; it is not silently substituted for the omitted snapshot.

Offline replay of the trusted executed parser against both unchanged reports
reproduces this exact error. A separately labelled synthetic counterfactual
replaced only the two masked path strings in memory with the known owned path;
the remaining image/frame parser then passed. This isolates the parser's path
assumption. Those invented report bytes are not native evidence, no artifact
was modified, and no original qualification requirement was waived.

### Ownership and cleanup

The first metadata commands were created about 3.010143 and 3.007360 seconds
after target transport creation; sampler commands followed at about 3.087100
and 3.086533 seconds. Those timestamps include command creation overhead and
do not claim a zero-jitter trigger. The original +3-second schedule, +14-second
cutoff and required remaining window were preserved.

The target PID remained reserved through the single sampler and the final
observer-group proof. Both observer inventories contained no live owned group
members. Only then did the parent close stdin. Native completion binds the
unchanged ready-receipt bytes, source/build identity, boot/timebase and ordered
start/readiness/release/completion clocks; both children exited zero without
signals. The separate final target-group inventories were also empty, all
streams closed, and both cleanup results are complete. There was no EPERM in
this run. Successful cleanup does not repair the missing path/after-identity
evidence.

### Artifact and projection verification

| Architecture | Artifact | ZIP bytes | ZIP SHA-256 |
| --- | ---: | ---: | --- |
| ARM64 | `13660037756` | 142,346 | `e198ea29cfef5a59b3bc07a16f1af840e77cbb6a524b41cf9f57dfebdd648c51` |
| Intel | `13660187867` | 141,781 | `1b53e3d87e3192922f53e1e7d362158cd0569ae0c7fb5eb70aa1ba4ee1d618a5` |

Each archive has 78 files. Verification covers API size/digest identities, ZIP
CRCs, all 156 extracted files, all 24 retained source copies against the executed
Git revision, the 102 immutable build/source entries, both executable/dSYM UUID
pairs, raw command streams and native receipt bindings. Archived code and
binaries were not executed during the artifact audit.

The public projection retains 32 parsed JSON receipts with 40 exact value
omissions, 70 whole UTF-8 text bodies and 14 text bodies split into exact lines
with private-path lines separately hash-bound. Full installed-manual bodies are
explicitly omitted. Its offline-analysis objects distinguish original report
witnesses from the synthetic parser counterfactual. The original failure and
missing post-sample snapshot remain explicit.

### Decision and next work

D22 establishes that these two controlled native processes produced genuine
counted stack reports using the fixed bounded method. **The original full
calibration remains incomplete.** This result does not explain D21's recorder
sampler timeout, establish recorder inspection access, identify the activation
requester or Escape consumer, or satisfy the original Finder acceptance gate.
No native retry or new recorder was launched after this result.

The next work is an **offline identity-witness contract over the retained D22
bytes**. It should distinguish advisory privacy-masked display paths from
independently measured executable identity; require the owned PID/parent,
expected UUID, main load address, unique matching image range and counted
frame-address/symbol-offset relationship; and bind these to the native
ready/completion, file hashes and immutable source/build evidence. A masked
path must never be treated as a glob or reconstructed as an observed path.

That offline unit needs explicit negative cases for wrong or duplicate UUIDs,
foreign PID/parent, inconsistent load address, out-of-range or wrong-symbol
frame addresses, wrong architecture and changed receipt/report bytes. It must
continue to report the missing after-identity snapshot and leave D22's original
full gate incomplete. No native rerun or recorder invocation is needed for this
work. A subsequent live measurement still needs its own concrete evidence
question; neither the time budget nor the original task 07 acceptance condition
changes as a consequence of these control reports.
