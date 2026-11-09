# D26 — Qualify the retained ATRC analysis contract

**D26 completed: the same reader supplied its import-specific help in one finite
request. The exact retained ATRC route remains unestablished.** The help clarifies
selection options and version-dependent default templates, but does not name
ATRC or enumerate all accepted formats. The general Apple Trace input family is
documented; D26 itself did not test this exact partial payload. The subsequent
[D27 attempt](NATIVE_RETAINED_ATRC_IMPORT.md) remains `diagnostic-incomplete`
after its output observer stopped the importer; neither accepted input nor
unsupported input is established. C12, task 07 and draft/unmerged
[PR #45](https://github.com/osmankaankars/lemulip/pull/45) remain **HOLD**.

## Executed result — 9 November 2026

[R1, attempt 1](https://github.com/osmankaankars/lemulip/actions/runs/42629940773)
passed all **45 tests** and completed the single documented help request. No
trace input was downloaded or supplied, and no import conversion, export,
recording or sampler was executed. The public
[result projection](evidence/D26-retained-atrc-contract.json) and
[verification record](evidence/D26-verification.json) bind the offline review,
exact executed code, retained native artifact and interpretation limits.

| Execution identity | Value |
| --- | --- |
| Executed source commit | `e8e0cbe351c82f3804a8f5bfa2c0b22ab54f69b4` |
| Executed source tree | `9b9ffd59df1bb7848e24ecbe82d252c0b47a1d72` |
| Native run / attempt / Intel job | `42629940773` / `1` / `129203323310` |
| Artifact ID | `13680745675` |
| Artifact bytes / files / expanded bytes | 135,565 / 54 / 534,934 |
| Artifact SHA-256 | `935d9c54ab0e489c9f7e6eff1ff00f57e14803cc6b36372b8174329245f9f17f` |
| Artifact expiration | 23 November 2026, 13:58:13 UTC |
| Native tests | 19 used D24 primitives + 9 D25 adapter + 17 D26 = 45 passed |
| New portable tests | 17 passed on Linux x86_64 / Python 3.12.14; exact executed Python source hashes matched |

The native classification is `help-collected`, with diagnostic execution,
transport, cleanup and source/tool preservation complete. The help command
exited **0 after 1.290658711 seconds**, with **1,512 stdout bytes and empty
stderr**. No termination signal was sent. The stdout SHA-256 is
`4c303ff573648b3acf5db1b647194036565257617779b9a2e81195643b0de340`.
All 13 declared source copies, including the explicitly mapped workflow, are
present in this artifact. The original D25 archive's separate 19/20 retention
limitation remains unchanged.

The independent provenance audit passed **213 checks**, including all 54 ZIP
members, the 13 source copies against exact Git objects and the reader's binary
identity/Apple UUID witnesses. The independent command audit passed **416
checks** across five targets, five group inventories, preserved clocks/streams
and all 45 native test cases. Each final target group contained only its
unreaped zombie leader, with collection afterward. The additional Python
non-reaping capability probe is separate from those ten command receipts.
These are consistency checks; they do not qualify payload compatibility.

### What the actual help added

| Observed help contract | Evidence lines | What remains open |
| --- | --- | --- |
| `--input` and `--output` create a new analysis document from a supported input. | 4–9 | No accepted-format enumeration or ATRC recognition rule. |
| `--template`, `--instrument` and `--package` are available import selectors. | 10–12 | A selector's existence does not establish appropriate instrument membership or preserved event coverage. |
| Omitted or directory output paths create a uniquely named file. | 18–20 | No output was requested or created by D26. |
| Some importable file types have a default template; only in those cases is explicit template selection optional. | 22–23 | The default for this exact input type is not identified. |
| Default-template selection is keyed to the import file UTI and may vary by release. | 23 | No UTI-to-template map or registered importer inventory is supplied. |
| Examples use `.logarchive` and `.ktrace`. | 26–29 | Examples are not an exhaustive exclusion of other formats. |

UTI here is the file type identifier used by the import contract. D26 does not
derive that identifier from a filename and treat it as proof of an accepted
payload. The new help also does not explain D25's missing-template error.

**Decision:** the command-specific grammar/default-selection gap is now
measured. Format recognition for the retained representation, suitable analysis
selection and actual payload acceptance remain distinct unresolved questions.
The predeclared generic-help stop condition applies: D26 ends without a
conversion or another metadata/recording retry. No trace rows, time mapping,
sampler-window coverage or product acceptance are added.

### Historical D27 proposal at D26 completion

The proposed next finite question was whether this same selected reader accepts one
unchanged copy of the retained raw payload with an explicit System Trace
selection and creates a separately identified analysis document within fixed
bounds. This was a proposed hypothesis test, **not a claim that the exact ATRC
payload was already qualified**. D26 performed no such conversion. The proposal
below records its original prerequisites; the subsequent outcome follows it.

The basis is the documented general Apple Trace family, the actual installed
import grammar and its explicit System Trace example for a ktrace input. The
observed prefix/magic is not used as format-compatibility proof. Metadata cannot
prove whole-payload acceptance in advance; the proposed experiment would measure
that remaining uncertainty directly. This clarifies the earlier plan's format
precondition while preserving its requirement for a documented command shape,
explicit selection and protected original bytes.

The proposal required a finite protocol that pins the exact input
member/hash and reader, obtains fresh same-run System Trace availability using
the documented template listing, preserves a protected disposable input copy,
and writes only to a separate new output path. Bound time, streams, output
growth and owned-process cleanup. Retain rejection or incompletion without
changing suffix, flags, template or input bytes. Do not automatically export
the derivative. Any successful import would establish only acceptance under
those conditions; normal D24 completion, all-event preservation and usable
clock/activation coverage would remain separate questions.

If that bounded experiment cannot be justified or executed under those
conditions, keep the route unestablished and carry the precise raw-input and
selection question into the existing upstream evidence packet. No documented
importer-registry query was identified, so another generic inventory is not
the next prescribed step.

### Subsequent D27 result and proposed offline D28 review

[D27 R2](NATIVE_RETAINED_ATRC_IMPORT.md) passed **99 native tests** and made one
import with the same reader, exact protected input and fresh System Trace
availability. Stdout reported import completion and saving. An output census
took **0.591878661 seconds**, exceeding its **0.25-second** observation budget;
the parent then sent TERM/KILL. The importer exited **-9 after 19.594917998
seconds**, before its 90-second normal-operation deadline. Cleanup completed,
and input/source/tool identities plus all **19 source copies** were preserved.
CI did not pass; the diagnostic remains `diagnostic-incomplete`, with no qualified derivative/archive.
The [D27 result](evidence/D27-retained-atrc-import.json) and
[verification](evidence/D27-verification.json) preserve this outcome. It proves
neither unsupported input nor an importer hang or root cause; no export or new
recording followed. R2's fixture correction is separate from the unresolved
historical full D24 test failure.

The proposed **D28 is offline observer review**: locate what the retained
observations and code can establish about the census failure, classification
and omitted-observation counter. Exact per-call timing was not retained. Any
further native proposal must follow that review; no automatic threshold
increase or retry is prescribed.

## Question and retained failure

Can the existing `trace-data.atrc` supply a supported, separately derived
analysis document under the selected Xcode 26.3 reader? This is distinct from
repairing the original `.trace` document or declaring D24 complete.

[D25](NATIVE_RETAINED_TRACE_EXPORT.md) made one document TOC export in
[run 42616711092](https://github.com/osmankaankars/lemulip/actions/runs/42616711092),
attempt 1, at `e537fb774768747c144ba7c57c1d8d4a097683e9`, tree
`8b073dc3cafb004d4fe4dc8dd99e5fdd9ce42e04`. It returned exit 10 in
1.734828604 seconds, with empty stdout and exactly 47 stderr bytes:

```text
Export failed: Document Missing Template Error
```

Its transport, cleanup and input/source/tool preservation gates completed.
This does not identify a required member, template identifier or serialization
rule, nor establish why D24 exited on signal 11. It does not prove that the
globally installed System Trace template is absent or that the raw payload
contains no useful events.

## Offline evidence before the help request

The retained D25 manual and dedicated export help are bound to Xcode 26.3,
build 17C529. D19's general, record, export and list help, template lists and
instrument lists supply earlier, separate-run evidence. The review checked
22 retained command receipts and 16 text bodies against their archived bytes.

| Contract question | Already retained evidence | Remaining limit |
| --- | --- | --- |
| Does export document a `.trace` input and TOC mode? | D25 dedicated export help, lines 1–18 | Its original document export was refused; no TOC schema is available. |
| Can import create a new analysis document? | D25 manual, lines 107–116, describes supported input and a new `.trace` output. | No enumeration of the supported input formats or ATRC variant recognition rule. |
| Does selection affect retained data? | Manual, lines 118–127, describes template/instrument selection and data needed by selected instruments. | No proof that a particular selection preserves the process/scheduling/time-map evidence needed here. |
| Which example formats appear? | Manual examples name `.logarchive` and `.ktrace`. | Examples do not constitute an exhaustive accepted-format list or disprove ATRC support. |
| Was System Trace available? | Both D19 template lists include it. | D19 run `42565052135` is not the D25 reader run and does not identify document metadata or importer registration. |
| Was import-specific help retained before D26? | No; general/record/export/list help were retained. | This concrete gap justified D26's subsequent single help request. |
| Is an importer registry query documented? | General/list help names only devices, templates and instruments. | No `list importers` or `list formats` command is established by this corpus. |

The D19 and D25 dedicated export-help bytes are identical. Their manuals differ
only at raw line 4, where D19 has an en dash and D25 an ASCII hyphen; the
import/export contract lines match. Their version/build text matches, but
equality of all installed frameworks, plugins and template bytes is unproven.

### Input identity is separate from input compatibility

The retained inner ZIP remains byte-for-byte equal to D24's original: 13,283,084
bytes, SHA-256
`d4a6e955f18b79d99530ec92690fad043422cb4897c0fb303f3066150cfb4bde`.
Its five entries comprise two files and three directories. The regular files
are `Trace1.run/Attachments/trace-data.atrc` and `Trace1.run/RunIssues.storedata`.

A fresh bounded 65,536-byte ATRC prefix read reproduces the first four bytes
`0003aa55` and the 1,057-byte primitive plist at offset 72. The plist SHA-256 is
`3c19922da8d12231e7cd6465e139da23bf441c6876a3d94873aab9c03a27cca3`;
selected OS fields are 15.7.9 / 24G830. Host, device and boot identifiers are
excluded. This audit did not extract or rehash the full 115,782,056-byte payload;
its full identity remains supported by the earlier full-stream audits and
current exact ZIP-byte equality.

These bounded header observations do not establish complete payload validity,
importer compatibility, missing document members, decoded events or clock
semantics. The 78 targeted input/provenance checks are evidence checks, not new
native execution or product tests. D25's retention limitation remains explicit:
20 source identities were bound, with 19 source byte copies; its workflow copy
was hash-bound to Git but absent from that artifact.

### Apple's version-specific documentation

[Xcode 26 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-26-release-notes)
describe opening on-device Power Profiler `.atrc` files in Instruments and
attaching underlying Apple Trace files within `.trace` containers. This
supports the general input family; it does not specify the 26.3 CLI contract
for this partial System Trace payload.

[Xcode 26.4 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-26_4-release-notes)
name `.atrc` among imported formats and add Import As Run and `--append-run`.
[Xcode 27 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes)
add direct raw-file export in place of the import-then-export sequence. Those
later additions are not substituted for the selected 26.3 command contract.

The bounded primary-source search found no definition of the exact D25 error.
This is a limit of the retrieved evidence, not a universal absence claim.
Official indexed excerpts supplied the relevant statements; full-page reads
were constrained by JavaScript shells and unavailable Markdown retrieval.

## Why the one additional metadata command was justified

The missing import-specific help was an actual uncollected primary surface. The
manual's import synopsis omits `--instrument`, while its option section includes
it, so command-specific grammar may also clarify selection behavior. The
retained general help explicitly documents this spelling:

```text
/usr/bin/xcrun xctrace help import
```

The collection asks only whether this selected reader advertises a relevant
format or selection contract. It passes no trace input and performs no
conversion. It does not recollect existing manuals or template lists merely
to duplicate them. There is no undocumented registry command, alternate flag,
automatic conversion or retry path.

## Executed fixed native collection protocol

Use native Intel macOS, non-root execution and Python 3.13 or later. Require
the exact Xcode version/build and selected developer directory used in D25.
Read and retain the installed xctrace executable; its 121,520 bytes must match
D25 SHA-256 `abf89e498e0bdb43dd48a3ccb545313a83b413a8d329503401ade7fa4e1a5674`.
The native Intel UUID is `98781736-C05A-3140-9BCF-279C288AEE66`.
Matching this CLI executable and version text does not establish equality of
every linked framework or registered plugin.

Exactly five fixed targets are allowed: OS version, Xcode version, resolved
xctrace path, Apple UUID output and the one import-help request. Each uses the
frozen D25 owned-command adapter, with 17 seconds normal operation, 20 seconds
total, 2 MiB combined streams and a 2-second/65,536-byte final group inventory.
PID leases, non-reaping status and emergency-cleanup failure semantics remain
enforced. A final group snapshot describes its observation time, not every
descendant's exit time at the operation deadline.

The gate runs **45 tests**: the 19 actually used D24 primitive tests, nine D25
adapter tests and 17 new D26 classification/source-retention tests.
D25 R1's old full-D24-suite failure remains
unresolved; these gates do not reclassify or fix it. No product source or old
test changes are included.

Require clean exact Git commit/tree and a four-file allowlist over D25 result
commit `6102d5d209d5918bc6ae61056917fbb9e3b16987`. Retain before/after source and
tool identities, explicit source copies, raw command streams and receipts,
group inventories, test logs and the outcome. An explicit source-to-copy map
places the workflow at `sources/workflows/native-atrc-import-contract.yml` so
its source bytes do not depend on hidden-file upload behavior. Source identities
remain keyed by the actual Git paths. The original trace archive is not
downloaded or passed to a tool.

## Decision and stop condition

| Actual help result | Permitted conclusion |
| --- | --- |
| Qualified help explicitly describes ATRC/Apple Trace acceptance | The advertised format route may be qualified to that exact wording/version; actual payload acceptance and data coverage remain open. |
| Qualified help remains generic about supported formats | Record that the exact format route remains unestablished and end D26 without conversion. |
| Help is refused, truncated, unrecognized or execution is incomplete | Preserve the measured collection outcome; make no format-support inference. |

The collector does not turn a keyword occurrence into a positive format claim.
Raw help and any stderr require separate interpretation. A future derived
document would need its own finite protocol, input/output provenance and data
selection decision; it would not retroactively complete D24 or repair the
original package. Metadata cannot prove full payload validity or usable time
mapping. No D26 outcome alone qualifies the sampler phase, activation route,
IPC chain, original Finder acceptance sequence or task 08's final acceptance.
