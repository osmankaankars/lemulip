# D27 — One bounded import of the retained ATRC

**Prepared protocol; the native experiment has not yet run.** D27 tests one
remaining compatibility hypothesis from [D26](NATIVE_RETAINED_ATRC_CONTRACT.md):
can the same selected reader accept the exact retained raw payload with an
explicit System Trace selection and create a separately identified analysis
document? The exact payload is not prequalified by its suffix, prefix, or
general file family. C12, task 07 and draft/unmerged
[PR #45](https://github.com/osmankaankars/lemulip/pull/45) remain **HOLD**.

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

## Finite execution protocol

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
guard plus 23 collector tests added for D27: 98 expected native cases. The old
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
