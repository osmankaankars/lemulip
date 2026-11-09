# D25 — Read the retained Intel trace

**Protocol prepared; no D25 native export result is asserted in this revision.**
The [D24 observation](NATIVE_RECORDER_PROGRESS_OBSERVATION.md) retained a partial
Intel trace after its recorder exited on signal 11. This diagnostic asks whether
the exact package can supply a recognizable table of contents through the
installed Xcode export tool. C12, task 07 and draft/unmerged
[PR #45](https://github.com/osmankaankars/lemulip/pull/45) remain **HOLD**.

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

If the TOC qualifies, subsequent queries may use only observed entities and
schemas. The next questions are decoded time range, usable clock mapping and
process/scheduling rows. Only then can evidence be compared to D24's
recorder-relative approximately +3.045–6.812-second window and PIDs 2040, 2147
and 2149. A displayed date, duration or PID does not supply that mapping alone.

No TOC result establishes normal completion of D24's recording, a sampler
phase, activation routing, an IPC request chain or product acceptance. The
original Finder enter → exit → reenter → Escape → release → distinct fresh-drop
sequence remains required for Orchard/Pistachio/Lemonade on both architectures.
Task 08's final acceptance remains dependent on task 07.

## Verification and retained evidence

Portable tests cover unsafe/corrupt input rejection, read-only extraction and
input changes, bounded XML and ambiguous/error envelopes, leased-child command
cleanup and interpretation gates. Synthetic tests cannot produce native trace
evidence. The unchanged D19 bounded-command, D20 transport and D24 ownership
suites also run before native export.

The workflow retains exact source copies, commit/tree, test output, installed
tool/version/help/manual evidence, raw command streams and receipts, input
manifests, the unchanged inner input ZIP and final classification. Producer work
directories stay outside the uploaded evidence directory.

A result entry must bind the exact executed revision, run/attempt, artifact
hashes and actual outcome before describing D25 as executed. The source base is
the [D24 result commit](https://github.com/osmankaankars/lemulip/commit/ee4ceaecee43d7f982e0523a52236799b5f2a603).
