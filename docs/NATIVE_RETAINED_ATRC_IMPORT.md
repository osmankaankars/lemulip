# D27 — One bounded import of the retained ATRC

**D27 executed one import; its native result is `diagnostic-incomplete`.** The
reader reported completion of its import phase and the start of saving, then
the output observer exceeded its per-census work budget and stopped the owned
process. No qualified derivative archive was retained. Exact payload acceptance
and saved-document readability remain unestablished. C12, task 07 and draft/unmerged
[PR #45](https://github.com/osmankaankars/lemulip/pull/45) remain **HOLD**.

## Executed result — 9 November 2026

[R2, attempt 1](https://github.com/osmankaankars/lemulip/actions/runs/42639700185)
passed all **99 native tests**, fetched the exact existing input, and made one
import invocation. The import step and CI conclusion are **failure**, because
the collector correctly retains an incomplete outcome when an observation gate
fails. There was no export, recording, sampler, alternate selection or second
native import. The [public result](evidence/D27-retained-atrc-import.json) and
[verification record](evidence/D27-verification.json) preserve the exact source,
input, execution, audit and interpretation bindings.

| Execution identity | Value |
| --- | --- |
| Actual import source commit | `50b34b215e1372a46add0f6c67fc8a2b9dc95e06` |
| Actual import source tree | `1d7db69e5778be3d909188daf8ab0604a4db1a4f` |
| R2 run / attempt / Intel job | `42639700185` / 1 / `129237191513` |
| Native artifact | `13685495111` |
| Artifact bytes / files / expanded bytes | 12,940,445 / 75 / 14,339,706 |
| Artifact SHA-256 | `03fe68b01b0818d660d4c493ffcf68dc81878046e866b36fbcfc2e9a7115b3a8` |
| Artifact expiration | 23 November 2026, 14:59:13 UTC |
| Native tests | 19 D24 primitives + 9 D25 adapter + 23 D25 input + 24 D27 output + 24 D27 collector = 99 passed |
| Physically retained source copies | 19 / 19, including the visible workflow copy |

The source/reader/input preservation checks passed. The retained inner ZIP and
the entire 115,782,056-byte ATRC stream still match their pinned identities.
The independent provenance audit passed **377 checks** over all 75 archive
members, all source copies, exact Git history, binary/UUID witnesses and the
retained input. These integrity checks do not qualify import completion.

### What the reader reported, and what stopped the attempt

The command used the freshly listed exact System Trace template. Its 106 stdout
bytes first announce that selection, then report:

```text
Import completed. Saving output file...
```

Stderr is empty. The stdout SHA-256 is
`420a72529441bd36ffab94479e0b86dd97626f350b6422bd8ba3582b89638415`.
This is a retained progress message; it does not replace final successful
process exit, a complete output inventory or a verified saved document.

| Observed event | Measured result |
| --- | --- |
| Live census work budget | 0.25 seconds |
| Failed live census duration / overshoot | 0.591878661 / 0.341878661 seconds |
| Owned-group TERM request | 19.297913152 seconds after command start |
| Owned-group KILL request | 19.558746246 seconds after command start |
| Import operation elapsed / exit | 19.594917998 seconds / -9 |
| Normal / total import budget | 90 / 95 seconds; neither triggered the stop |
| Transport / cleanup | incomplete / complete |
| Emergency cleanup / signal errors | none / none |
| Final derivative retention | skipped because output observation had failed |

The parent-issued signals explain the observed -9 exit. It is not evidence of a
spontaneous reader crash, unsupported input, an import deadlock or exhaustion of
the 90-second import budget. The retained evidence does not identify which
filesystem operation or scheduling interval caused the slow census. The
30-second archive-retention budget did not expire: finalization immediately
skipped reading the unqualified output.

### Observed output growth and evidence limits

The last completed retained census counted **244 entries**, depth **7**,
**1,569,293 logical bytes** and **2,142,208 allocated bytes** inside the exclusive
output parent. The independently maintained high-water counters reached
**1,686,939 logical bytes** and **2,232,320 allocated bytes**, including partial
work from the failed census. These are observed counters, not a final complete
inventory or a guarantee about unobserved transient/off-root writes. No measured
byte, entry or depth threshold caused this stop.

Output growth was therefore observed. The absence of `derived.trace.zip` does
not mean no files were created. Because the guard failed, no stable final named
inventory or derivative archive was retained; even the intended document's
structural qualification remains false. D27 cannot inspect that partial output
offline from this artifact.

One separate summary-counter defect was found during the audit. The native
record reports 324 completed scans, retains 256 observations comprising 255
completed and one failed observation, and reports 68 omitted completed scans.
The correct derived omitted-completed count is **69**. The source formula
subtracts the failed retained observation from the completed-scan count too.
The public record preserves the original 68 and separately annotates the
derived 69; it does not rewrite executed evidence. This accounting defect did
not cause the census timeout and does not restore import acceptance.

The independent command/output audit completed **575 checks: 574 passed and
one failed on this disclosed counter discrepancy**. Its original
`allChecksPassed=false` remains visible in the verification record. The separate
semantic review passed all **31 checks** while preserving the incomplete result.

## D28 follow-up — output-observer review completed offline

[D28's completed review](NATIVE_RETAINED_ATRC_OBSERVER_REVIEW.md) corrects the
isolated omitted-completed counter, passes 56 portable tests and characterizes
the synchronous supervision boundary with five deterministic cases. It
preserves both original D27 JSON files and this incomplete native outcome.
Its candidate D29 contract separates census work from command supervision;
that worker is not implemented or executed in D28. No native retry occurred.

The following was the proposed scope at D27's conclusion:

D28 should use the retained receipts, frozen source and controlled synthetic
fixtures to examine the live census's time accounting and responsiveness. The
missing per-operation timing witnesses prevent attributing the 0.592-second
census to a particular filesystem call or scheduler event. The next work must
make that boundary measurable before proposing another native experiment.

Reproduce delayed census work and history truncation in synthetic tests, correct
the omitted-completed counter, and assess an observation design that preserves
the command's cleanup/deadline handling while retaining bounded progress evidence.
Any change needs its own explicit timing, storage and retention contract. A
larger timeout or a repeated import is not automatically prescribed. **At D27's
conclusion, D28 had not been executed.** D27 ends with this one retained incomplete
attempt; no useful trace rows, clock mapping or task 07 acceptance are added.

## Pre-import test failure and fixture correction

[R1, attempt 1](https://github.com/osmankaankars/lemulip/actions/runs/42638786998)
at `8d02338e9248af73518c68eb53f2bfb01b27b939`, tree
`0b68ce8086fc2a4ffd44b88836b7ea5135951198`, stopped in its test gate.
The first 75 cases passed; the collector suite then reported 22 passes and one
error in its positive protected-input fixture. The source-artifact download
and actual import steps were skipped: **zero native import invocations**.
Artifact `13683238109` retains the 12 build-evidence files and exact failing
stderr; it is not a native import result.

The fixture passed its temporary parent spelling directly to the selector,
whereas the frozen input preparer resolves the existing parent before returning
the protected trace path. An explicit directory-alias regression reproduced the
same canonical-path exception on Linux with the original fixture. Changing only
the fixture to resolve that parent made all 24 collector tests pass. The new
test also deliberately restores an alias spelling and confirms that the
production selector still rejects it. No runtime path check was weakened,
test skipped, input renamed, or import attempted by this correction.

The exact native temporary alias was not recorded in R1, so a particular host
path mapping is not claimed as directly observed. The controlled reproduction
establishes the fixture defect. R2 verified the prediction: the corrected case
and the new alias regression passed in its 99-case native test gate. All other
Python sources and tests remain byte-identical to R1.

## Question and fixed command

D25's single document TOC export ended with exit 10 and
`Document Missing Template Error`. D26 collected the installed import help;
it established input/output syntax, explicit template selection, and conditional
defaults keyed to an input UTI that may vary between releases. It did not
establish acceptance of this retained partial payload or identify a missing
document member.

The D26 help's explicit System Trace example supplies a command-shape basis.
D19's retained list help and command receipt document template listing. D27
uses a **fresh** same-run listing as an availability prerequisite; D19's old
list is not current availability evidence.

Exactly one import attempt is permitted:

```text
/usr/bin/xcrun xctrace import --input <protected-exact-raw-member> --template 'System Trace' --output <exclusive-new-parent>/derived.trace
```

The raw member keeps its original `trace-data.atrc` suffix and bytes. There is
no alternate template, instrument/package option, suffix change, original
document repair, second attempt or automatic export. A finite refusal is an
experiment result. A bound or observation failure leaves the attempt incomplete
under this protocol.

## Pinned input and reader

| Identity | Fixed value |
| --- | --- |
| D26 result/base commit | `71909054ccf9d3a174e4de13fdb7c9559387baef` |
| D26 result/base tree | `c28cd466335ec2e2f303a14cc158bd54f45eb217` |
| Original D24 source run / attempt | `42609635410` / 1 |
| Original D24 source artifact | `13669502448` |
| Source artifact bytes / SHA-256 | 12,948,336 / `5e80502e00e9da7cd857ab45b5324d637c4c09195dfe6e70b2d5569976e7b041` |
| Selected inner archive | `recording.trace.zip` |
| Inner bytes / SHA-256 | 13,283,084 / `d4a6e955f18b79d99530ec92690fad043422cb4897c0fb303f3066150cfb4bde` |
| Raw member | `recording.trace/Trace1.run/Attachments/trace-data.atrc` |
| Raw bytes / SHA-256 | 115,782,056 / `dd55ca66c46a4651df145287d2db8573e6dcf5f9387dcea73bec21a7a37719f0` |
| Xcode / build | 26.3 / 17C529 |
| Selected developer directory | `/Applications/Xcode_26.3.app/Contents/Developer` |
| xctrace bytes / SHA-256 | 121,520 / `abf89e498e0bdb43dd48a3ccb545313a83b413a8d329503401ade7fa4e1a5674` |
| Native Intel UUID | `98781736-C05A-3140-9BCF-279C288AEE66` |

The unchanged D25 input preparer verifies both archive identities, inventories,
member CRCs and full extracted-file hashes. It creates an exclusive disposable
input workspace using descriptor-relative no-follow opens. Files are mode 0400,
directories mode 0500. D27 binds the exact raw member before import and compares
full trace snapshots and the retained inner archive afterward.

Mode bits and final hash equality do not establish that no write was attempted
or no cache was created elsewhere. Equality of the reader binary and version
text does not establish equality of every linked framework or plugin.

## Executed finite protocol

Require native Intel macOS, a non-root account, Python 3.13 or later with a
successful non-reaping child-status probe, exact Xcode selection, a clean
immutable source checkout, the six-path D27 change allowlist and at least 2 GiB
free space at the evidence parent before the import attempt. Free space is an
eligibility observation, not a reserved quota.

The five metadata targets are:

1. `/usr/bin/sw_vers`
2. `/usr/bin/xcodebuild -version`
3. `/usr/bin/xcrun --find xctrace`
4. `/usr/bin/xcrun dwarfdump --uuid <validated-xctrace-path>`
5. `/usr/bin/xcrun xctrace list templates`

Require one exact `System Trace` entry in the recognized standard-template
section. Similar names, substrings and an older list cannot satisfy this gate.
The already retained D26 help is not collected again.

| Bound | Fixed policy |
| --- | --- |
| Metadata target | 17 seconds normal operation / 20 seconds total; 2 MiB combined streams |
| Import target | 90 seconds normal operation / 95 seconds total; 8 MiB combined streams |
| Owned-group inventory | 2 seconds / 65,536 bytes per inventory |
| TERM grace | 0.25 seconds before owned-group KILL if needed |
| Output growth thresholds | 512 MiB logical bytes and 512 MiB allocated bytes |
| Output inventory | At most 16,384 entries; depth 32 |
| Output scan scheduling / scan budget | 50 ms sampling interval; 250 ms census work budget, with actual delays retained |
| Final derivative retention | 30-second budget with bounded chunked reads and archive verification |
| Source artifact download | HTTPS only, 10-second connection / 60-second total, at most 3 redirects and 12,948,337 bytes |
| Outer native job | 15 minutes |

Each command keeps its direct child unreaped until owned-group inspection is
complete. The output observer runs in the same finite capture loop and requests
termination through that retained ownership lease. Its failure or limit breach
cannot be converted into a completed successful import by a later exit 0.
Cleanup records and actual deadline overshoots are retained. Synchronous
filesystem calls have no hard per-call deadline; the observer checks elapsed
time between calls and records any overshoot. The nominal adapter budget and
per-scan work budget are reported separately from measured elapsed time.

The new D27 adapter copies the existing D25 ownership/cleanup design and adds
only the output observation needed by this import experiment. The inherited
D24 and D25 runtime files remain unchanged. A final group snapshot establishes
that no live member was seen at that observation; it does not retroactively
timestamp every descendant's exit.

## Separate output and bounded retention

Create a fresh private mode-0700 output parent and require the intended
`derived.trace` child to be absent. The original input and original document
are outside this output tree. Observe the whole new parent, including temporary
siblings, with descriptor-relative no-follow traversal. Reject links, special
files, hard-linked regular files, cross-device traversal, unsafe names, and
entry/depth/byte or observation-time excesses.

The size thresholds are **sampled growth stops**, not operating-system disk
quotas. Actual growth may exceed a threshold between observations or during
termination; actual observed high-water values and scan timing are retained.
Off-root writes and unobserved transient growth are not ruled out.

Only after positive owned-process cleanup may D27 take a stable final output
inventory, stream full file hashes and retain a separately identified derivative
archive. Reads, entry counts, byte totals and retention elapsed time are bounded.
A failed or oversized retention cannot turn into a qualified output. The raw
partial output directory is outside the uploaded evidence tree.

A structurally retained derivative requires a nonempty ordinary `.trace`
directory at the exact intended new path and no unexpected final siblings.
Archive stability and CRC/hash verification establish retained bytes, not
Instruments document semantics, useful trace rows or event completeness.

## Classification and interpretation

- **Accepted with retained derivative:** exit 0, complete transport and owned
  cleanup, unchanged source/reader/input, all preconditions, complete output
  observation and stable bounded retention of the new document.
- **Refused or terminated:** a natural nonzero or signal exit with preserved
  evidence. Any bounded output can be retained, but does not establish acceptance.
- **Output unqualified:** exit 0 without a qualifying newly retained document.
- **Incomplete:** a preflight, time/stream/growth/observation/cleanup/identity or
  retention gate cannot be established.

Even an accepted derivative does not establish normal D24 recording completion,
all-event preservation, a usable clock mapping, sampler-window coverage,
activation or IPC causality, or product acceptance. No TOC or data-row export is
part of D27. Any later analysis must start from the actual retained outcome and
its exact new identity.

## Verification and retained evidence

The native workflow runs the 19 D24 primitives actually used here, the 9 D25
owned-command adapter tests, the 23 D25 pinned-input tests, and the 24 output
guard plus 24 collector tests added for D27: 99 expected native cases. The old
full D24 synthetic-suite failure remains open; selecting
the used primitives does not repair or reclassify it.

Retain exact command streams and receipts, owned-group inventories, source
before/after identities and physical source copies, the reader binary/UUID
witness, input before/after snapshots and inner archive, output observations,
any qualified derivative archive, and raw test/privacy output. The workflow
source copy is explicitly mapped to a visible `sources/workflows/` path so
hidden-file exclusion does not omit it.

The branch-only workflow is
[`native-retained-atrc-import.yml`](../.github/workflows/native-retained-atrc-import.yml).
Only executable/workflow paths trigger it. Results-only documentation/data
commits do not request another native attempt.

D24's abnormal recorder exit, D25's missing-template refusal, D26's measured
help contract, original task 07 acceptance sequence, and task 08's dependency
remain preserved. No production code or acceptance criterion is changed.
