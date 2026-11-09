# D25 — Read the retained Intel trace

**D25 completed: the installed Xcode 26.3 reader refused the unchanged Intel
package with `Document Missing Template Error`. No table of contents was produced.**
The [D24 observation](NATIVE_RECORDER_PROGRESS_OBSERVATION.md) retained this partial
trace after its recorder exited on signal 11. The one D25 export exited normally
with code 10 after 1.734828604 seconds, without a deadline or cleanup failure.
The diagnostic execution completed; trace exportability and usable event timing
remain unestablished. C12, task 07 and draft/unmerged
[PR #45](https://github.com/osmankaankars/lemulip/pull/45) remain **HOLD**.

## Executed result — 9 November 2026

[R2, attempt 1](https://github.com/osmankaankars/lemulip/actions/runs/42616711092)
passed its 91-test dependency gate and completed the single native Intel export
attempt. The earlier R1 stopped before any native export, as detailed below.
The public [result projection](evidence/D25-retained-trace-export.json) preserves
the native classification, exact command clocks, input manifests, tool identity
and raw stream identities. The [verification record](evidence/D25-verification.json)
binds the artifacts, Git objects, native and portable tests, and independent
audits. Private runner paths and full installed manual bytes are omitted from
the public projection; the original artifacts were not rewritten.

| Execution identity | Value |
| --- | --- |
| Executed source commit | `e537fb774768747c144ba7c57c1d8d4a097683e9` |
| Executed source tree | `8b073dc3cafb004d4fe4dc8dd99e5fdd9ce42e04` |
| Native run / attempt / Intel job | `42616711092` / `1` / `129158262959` |
| Architecture / Python | x86_64 / 3.13.15 |
| Reader Xcode | 26.3, build 17C529; exact producer-version match |
| Reader OS | macOS 15.7.9, build 24G830 |
| Artifact ID | `13672758368` |
| Artifact bytes / files / expanded bytes | 12,928,357 / 85 / 14,161,297 |
| Artifact SHA-256 | `2f4eb0d06b15985baf3a2584994488363c2cf018d66ddd2a9aa0cd48b0916ecf` |
| Artifact expiration | 23 November 2026, 12:25:44 UTC |

### Reader refusal

The exact retained 47-byte stderr, including its terminal newline, is:

```text
Export failed: Document Missing Template Error
```

Its SHA-256 is
`28c3ee1d8e3698496c540c01ccbb9d79fed962accf4e675fd0f33a6af02fdef5`.
The XML stdout file is empty. There are no observed run IDs, table schemas or
exported rows to query.

| Observation | Retained result |
| --- | --- |
| Original classification | `export-refused` |
| Diagnostic / transport / cleanup complete | true / true / true |
| TOC export / table data / usable clock mapping established | false / false / false |
| Export invocations / PID / exit code | 1 / 6621 / 10 |
| Command operation time | 1.734828604 seconds |
| Adapter time, including final group inventory and collection | 1.843466875 seconds |
| Signals / emergency cleanup | none / false |
| New recordings / samplers / application launches | 0 / 0 / 0 |
| Input package / source / installed tool unchanged | true / true / true |

All seven fixed commands and their seven final group probes completed within
their operation budgets. Each target's final group snapshot contained only its
unreaped zombie leader; collection released the PID lease afterward. This is
positive cleanup evidence at the snapshots, not a timestamp for every possible
descendant's exit.

The error identifies this reader's refusal, but does not identify a particular
missing file, object or template name. It does not prove why D24 exited on
signal 11, that signal 11 caused this refusal, or that the raw ATRC bytes cannot
support any separately qualified analysis. Incomplete document finalization is
an interpretation to investigate, not an established mechanism. No permission
denial, internal sampler phase, activation route or IPC chain follows from the
error text. CI success records completion of this finite diagnostic; it does
not establish successful trace export or product acceptance.

### Input, source and tool preservation

The retained input ZIP is byte-for-byte equal to D24's original inner archive.
Both native manifests contain the exact two files and three directories, with
unchanged hashes and expected file/directory modes `0400`/`0500`. The independent
offline audit validates these retained receipts and bytes; it cannot re-observe
the runner's filesystem after the job ends.

The installed xctrace executable remained 121,520 bytes with SHA-256
`abf89e498e0bdb43dd48a3ccb545313a83b413a8d329503401ade7fa4e1a5674`.
Its Intel Mach-O UUID is `98781736-C05A-3140-9BCF-279C288AEE66`.
An independently implemented binary parse agreed with both retained slice
UUIDs and Apple's `dwarfdump` output.

All **20 before/after source identities** match the exact executed Git objects.
There are **19 physically retained source copies**. The hidden workflow path
`.github/workflows/native-retained-trace-export.yml` is absent from the uploaded
artifact. Its 6,050-byte identity is recorded in both native snapshots and
matches the immutable Git blob, SHA-256
`2cf342900903b33c6a67e2668ff8d65ac78b5f246bdaf414cb58477e9999dd04`.
This is a hash binding to Git, not an archived byte copy. The retention omission
does not justify another export.

Independent input/source/tool and command/ownership audits passed **238** and
**375** checks respectively. These are evidence consistency checks, separate
from the **91 native tests**: 6 D19, 10 D20, 19 selected D24 primitives and
56 D25 tests. The four D25 suites also passed all 56 tests locally; the final
D24 selector passed 19 locally. All eight D25 Python source/test files were
unchanged between that local 56-test execution and R2. Only the workflow test
selection and this protocol document changed from R1 to R2.

### R1 pre-export gate failure and dependency scope

[R1, attempt 1](https://github.com/osmankaankars/lemulip/actions/runs/42615911091)
at `320d06576b2c2ac5cd3352704598082147fe10c8` stopped before artifact download or
native export. The D19/D20 suites passed 6 and 10 tests. The unchanged full D24
suite ran 50 tests and reported 10 failures and 4 errors, all within its
multi-role `SyntheticOrchestrationTests`. It retained final-group snapshot,
helper-completion, expected-role and teardown `EPERM` failures. Per-case raw
receipts were not retained, so their internal cause remains unproven; the run
does not establish flakiness or native sampler permission denial. The new D25
suites had not yet run, and **zero exports or recordings occurred**.

D25 never calls D24's `run()`, notification-helper validation, banner-triggered
nested sampling or report qualification. Its dependency gate now explicitly
selects the **19 unchanged D24 tests** for `OwnedCommand`, non-reaping capability,
bounded file reads and installed Mach-O identity. Together with the 16 D19/D20
tests and 56 D25 tests, this gives a 91-test gate for the actual call path.
The nine new adapter tests exercise its own cleanup composition. Every native
metadata command must additionally pass actual leased-group/stream cleanup
before the TOC attempt can start.

This is a test-scope correction, **not a fix or reclassification of the failed
full D24 suite**. Its source and tests are unchanged. Shared cleanup risk remains
an enforced D25 gate; no failure is converted to success. R1's eight-file
artifact is `13671828280`, 5,005 bytes, SHA-256
`2a7ce57cb0778ef39e67c44544906563de1eca278cd5990ffc451b027b25f794`.

## Evidence question and fixed input

D24 did not obtain a qualified primary or secondary sampler stack. In the
parent monotonic clock, both sampler operations had ended by recorder-relative
approximately +6.812 seconds; recorder output was first observed at +11.311
seconds. Its one notification callback uses a separate helper-native clock.
None of those observations establishes trace timing or the earlier event range.

The retained inner package has two files: `trace-data.atrc` and
`RunIssues.storedata`. The latter contains one literal issue message,
`Data stream: Time Mapping`. Its issue enum, timestamp and clock semantics are
unqualified. No complete recording, event table or sampler-window overlap is
inferred from package presence. See the exact D24
[result](evidence/D24-recorder-progress-observation.json) and
[verification](evidence/D24-verification.json).

| Input identity | Pinned value |
| --- | --- |
| Original native run / attempt | `42609635410` / `1` |
| Original Intel artifact | `13669502448` |
| Original source commit / tree | `73464e30f278203cbd129025f1db814b6c549b2b` / `0d0b8c476fb052cd7b3a5b7ac98d0c6977069bf5` |
| Outer artifact bytes | 12,948,336 |
| Outer SHA-256 | `5e80502e00e9da7cd857ab45b5324d637c4c09195dfe6e70b2d5569976e7b041` |
| Selected outer member | `recording.trace.zip` |
| Inner archive bytes | 13,283,084 |
| Inner SHA-256 | `d4a6e955f18b79d99530ec92690fad043422cb4897c0fb303f3066150cfb4bde` |
| Inner inventory | 3 directories, 2 files, 115,835,304 expanded file bytes |
| Producer Xcode | 26.3, build 17C529 |
| Producer OS | macOS 15.7.9, build 24G830 |

The branch-specific workflow downloads that single existing artifact over HTTPS
with a finite time and byte limit. It does not select the latest artifact by
name. The outer size and SHA-256 must match before any member is extracted.
Only the selected inner ZIP is copied; its digest, complete inventory, CRCs and
file hashes must also match. No archived code or executable is run.

Extraction uses a new exclusive directory, bounded streaming reads, safe unique
relative names, descriptor-relative traversal, and no-follow regular-file opens.
Links, special files, path aliases, duplicate entries and unexpected inventory
are rejected. The original 256 MiB aggregate and 16,384-entry limits remain.
The two exact file sizes are enforced, including the 115,782,056-byte ATRC file.

Extracted files receive mode `0400` and directories `0500`. The native job must
run without root privileges. Before/after manifests compare relative names,
types, permission modes, sizes and SHA-256 values. The retained inner ZIP and
reader executable are also compared before/after. These checks establish input
protection and final byte equality; they do not prove that the tool attempted
no writes or made no caches elsewhere.

## One installed-tool export

The job uses native Intel macOS with the original Xcode 26.3 selection. Fresh
OS version, exact Xcode version, resolved xctrace path, installed Mach-O byte
identity/UUID, export help and manual are retained. The reader's Xcode version
must equal the producer's recorded version. OS identity is reported, not assumed.
The tool's current path must belong to the selected developer directory.

The explicit installed export-help contract must establish `--input`, `--toc`,
XML output, stdout when `--output` is omitted, and separate TOC/XPath modes.
The retained D19 manual's introductory export paragraph repeats the recording
description, so that paragraph is not used to authorize this command.

```text
/usr/bin/xcrun xctrace export --input <exact-read-only-copy>/recording.trace --toc
```

There is one TOC attempt and no alternate export flags. It starts no recording,
sampler, drag application or input sequence, and requests no import, remodeling,
repair, setting change or elevated privilege. A refused package remains a
refused package; it is not silently reconstructed to make export succeed.

| Boundary | Fixed value |
| --- | --- |
| Export normal operation | 30 seconds |
| Export total operation, including termination reserve | 33 seconds |
| Export combined stdout/stderr retention | 8 MiB |
| Each metadata command | 17 seconds normal / 20 seconds total; 2 MiB streams |
| Final owned-group inventory | 2 seconds; 65,536 bytes |
| TERM escalation interval | 0.25 seconds |
| Conditional emergency cleanup | One TERM/KILL sequence and one additional 2-second group inventory; original operation remains incomplete |
| XML parser | 8 MiB, 100,000 elements, 64 levels |
| Artifact retention | 14 days |

Python 3.13 and D24's non-reaping `waitid(WNOWAIT)` capability check are used.
The export's direct-child PID stays reserved through the final group inventory.
Only owned groups may receive termination signals. Target and metadata records
are collected only after terminal status, closed streams and the applicable
cleanup evidence; late close/stream errors remain failures.

The final group snapshot proves absence of live members at its observation
time. It does not retrospectively place every descendant exit before the
33-second deadline. If a live descendant requires emergency cleanup, successful
later cleanup cannot restore the original operation's completion status.

## Classification and follow-up

Command execution, XML structure and trace semantics are separate gates:

- A clean finite positive nonzero exit is an `export-refused` result.
- An unrequested signal exit is `export-terminated-by-signal`; its cause is not
  inferred from the exit code.
- A zero exit with truncated, malformed or unrecognized XML is
  `export-output-unqualified`.
- A zero exit and recognized TOC establish TOC exportability. Stderr is retained
  and explicitly labeled; it is not discarded or automatically treated as a
  failure merely because a warning is present.
- Timeout, output-limit, cleanup failure or changed inputs prevent complete
  diagnostic execution, regardless of any partial XML.

The XML parser rejects document types/entities, invalid encoding, error
envelopes, ambiguous run identifiers, nested runs and excessive structure. It
enumerates actual direct runs and literal table attributes rather than assuming
a fresh run numbered 1. Empty tables remain empty. Other metadata remains
uninterpreted, and no attribute is executed as an XPath or command.

D25 did not qualify a TOC, so there is no observed schema for a follow-up XPath
query. **D26's next finite question is an offline review of the retained Xcode
26.3 reader, import and template contracts:** is there a supported, separately
derived analysis route for this exact ATRC input, and which preconditions would
it require? Start with the existing version-bound manual/help, tool identity
and package inventory. Identify any concrete documentation gap before another
native metadata collection. Do not assume a filename from the error text,
repair the original package, substitute a different Xcode contract, or repeat
the failed export or recording merely to obtain a different result.

Any later derived-data attempt would need its own provenance and finite
protocol; it would not retroactively complete D24. Only qualified decoded time
range, usable clock mapping and process/scheduling rows could support a later
comparison with D24's recorder-relative approximately +3.045–6.812-second window
and PIDs 2040, 2147 and 2149. A displayed date, duration or PID does not supply
that mapping alone. No such attempt occurred in D25.

No TOC result establishes normal completion of D24's recording, a sampler
phase, activation routing, an IPC request chain or product acceptance. The
original Finder enter → exit → reenter → Escape → release → distinct fresh-drop
sequence remains required for Orchard/Pistachio/Lemonade on both architectures.
Task 08's final acceptance remains dependent on task 07.

## Verification and retained evidence

Portable tests cover unsafe/corrupt input rejection, read-only extraction and
input changes, bounded XML and ambiguous/error envelopes, leased-child command
cleanup and interpretation gates. Synthetic tests cannot produce native trace
evidence. The unchanged D19 bounded-command and D20 transport suites and the
19 explicitly selected D24 primitive tests also run before native export.

The artifact retains 19 exact source copies and all 20 source hash bindings,
commit/tree, test output, installed tool/version/help/manual evidence, raw
command streams and receipts, input manifests, the unchanged inner input ZIP
and final classification. The missing workflow copy is described above.
Producer work directories stayed outside the uploaded evidence directory.

The result and verification entries bind the executed revision, run/attempt,
artifact hashes and refusal. The source base is
the [D24 result commit](https://github.com/osmankaankars/lemulip/commit/ee4ceaecee43d7f982e0523a52236799b5f2a603).
