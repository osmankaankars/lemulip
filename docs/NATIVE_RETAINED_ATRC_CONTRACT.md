# D26 — Qualify the retained ATRC analysis contract

**Offline review completed; one missing command-specific help collection is
prepared. No D26 native result is asserted in this revision.** The general Apple
Trace input family is documented, but a version-bound CLI route and acceptance
of this exact retained partial payload remain unestablished. Unsupported input
is also unproven. C12, task 07 and draft/unmerged
[PR #45](https://github.com/osmankaankars/lemulip/pull/45) remain **HOLD**.

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

## Offline evidence and exact limits

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
| Was import-specific help retained? | No; general/record/export/list help were retained. | The current command-specific grammar, defaults and possible format descriptions are missing. |
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

## Why one additional metadata command is justified

The missing import-specific help is an actual uncollected primary surface. The
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

## Fixed native collection protocol

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
