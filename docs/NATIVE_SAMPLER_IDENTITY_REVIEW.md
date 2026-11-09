# D23 — Offline review of the retained sampler identity witnesses

**Completed, 9 November 2026 Europe/Istanbul:** both original archives pass the
new narrow consistency review. All 39 portable tests passed; independent
reconstruction matched every output value. The [derived review](evidence/D23-native-sampler-identity-review.json)
and [verification receipt](evidence/D23-verification.json) retain the exact
input, source and result identities.

This unit reviews the two immutable [D22 artifacts](NATIVE_SAMPLER_CALIBRATION.md)
without executing an archived program or making another native measurement.
Its question is deliberately narrow: do the retained reports contain counted
samples of the expected wait frame, consistently bound to the controlled native
image and the retained process-lifecycle records?

The original D22 result remains `calibration-incomplete`. Its strict path gate
rejected unequal masked display paths before the post-sample `ps` query. D23
does not supply that missing query, reconstruct an unmasked path, or change the
D22 parser or acceptance conditions. Task 07, C12 and PR #45 remain **HOLD**.

## Why this is a separate review

Both D22 samplers exited zero and produced reports within the original budget.
The report header displays `/Users/USER/*/NativeSamplerCalibration`; the main
Binary Images entry displays `/Users/*/NativeSamplerCalibration`. These literal
strings are unequal and are not canonical executable-path observations. The
strict executed parser therefore stopped before completing the original gate.

The retained artifacts also contain independently useful evidence: executable
and dSYM bytes, native self-identity receipts, source/build bindings, command
streams, counted call-graph entries, loaded image UUIDs and sampled addresses.
D23 checks the consistency of those records under a separately versioned
contract. A positive result means the narrow witness is consistent; it is not
an assertion that the omitted part of D22 ran or passed.

## Trusted inputs and bounded reading

The [fixed trust manifest](../script/fixtures/native_sampler_identity/D22-trust.json)
records the two original archive identities and every retained member's byte
length and SHA-256. It also records the twelve source paths, byte identities and
Git blob IDs at the exact executed revision. The verifier has no command-line
option to replace this manifest or bypass archive identity verification.

| Binding | Expected value |
| --- | --- |
| Original run / attempt | [42588874357](https://github.com/osmankaankars/lemulip/actions/runs/42588874357) / 1 |
| Executed D22 commit | `10ececdd145ca4c857c5844a83cee0b0b3a5d8e2` |
| Executed D22 tree | `6219e264ff2df60c16b1be5063643808569a09eb` |
| Published D22 result commit | `e7fd68c542c7dea98ba560a783c02d69798fe96b` |
| Dependency base | `d20b6b59430856b4bf0dd46dc7220fc1492186b6` |
| Frozen C12 commit | `d821d7343675e2850705d141ef9b3b93a6aee945` |
| Frozen C12 tree | `425baa28f00ec24551dd70c0cc874a75fa3be0c1` |

| Architecture | Artifact | ZIP bytes | ZIP SHA-256 |
| --- | ---: | ---: | --- |
| ARM64 | `13660037756` | 142,346 | `e198ea29cfef5a59b3bc07a16f1af840e77cbb6a524b41cf9f57dfebdd648c51` |
| Intel | `13660187867` | 141,781 | `1b53e3d87e3192922f53e1e7d362158cd0569ae0c7fb5eb70aa1ba4ee1d618a5` |

Each archive contains 78 files. Manifest creation independently compared all
twelve source files in each archive against Git objects in the executed tree.
The immutable input snapshots bind 51 build/source entries per architecture.
The checked-in manifest is an explicit trust anchor, not a claim that a hash
alone proves the provenance of arbitrary bytes supplied by a caller.

The verifier reads ZIP members into bounded memory without extraction. It
rejects ambiguous paths, duplicate members, unsafe member types and byte
identity mismatches. JSON objects with duplicate keys or non-finite numbers
cannot qualify. Neither retained Python code nor either Mach-O executable is
imported or executed. Reading Mach-O headers and symbol tables works on Linux;
Apple tools and a signed-in macOS session are unnecessary for this review.

## Identity and frame contract

The review requires all of the following bindings to agree:

1. Archive identity, exact file inventory, every file's bytes, source commit and
   tree, source Git blob IDs, build provenance and before/after input snapshots.
2. The executable and dSYM's native CPU and UUID, the build records, the native
   ready/completion records, and the retained command arguments and streams.
3. One controlled process instance: nonce, PID, parent PID, process group,
   effective UID, source/build identity, boot UUID and clock timebase. The
   pre-sample `ps` output is parsed again; command text remains advisory.
4. Ordered lifecycle and observation clocks, the reserved target PID through
   observer cleanup, normal stdin EOF, zero native exit without forced cleanup,
   and the final observer/target group inventories. Native completion binds the
   exact ready-receipt bytes. It does not replace the missing post-sample `ps`.
5. Exactly one expected-UUID image entry, named `NativeSamplerCalibration`,
   with the native Code Type and a range starting at the report's main Load
   Address. A sampled PC cannot also map to another reported image. The report
   PID and parent must agree with the controlled instance.
6. An exact `lemulip_d22_wait_for_release` frame in the actual `Call graph`, in
   the expected image, with a positive sample count and a PC inside that image's
   address range. A frame mentioned only in a summary is insufficient.
7. A defined external wait symbol and executable-header symbol in the retained
   Mach-O symbol table, agreeing with the retained `nm` output and the preferred
   text address. The wait function's retained `N_FUN` start/size pair and next
   defined text symbol also bound its address extent; a PC elsewhere in the
   text section is insufficient. Every accepted frame must satisfy:

   `sampled PC = retained symbol address + observed load slide + reported displacement`

The displayed header and image paths are retained verbatim as advisory text.
The verifier never interprets `*` as a wildcard, substitutes the native path
into a report, or describes a masked path as an observed canonical path.

## Running the review

The verifier and its tests use only Python's standard library:

```bash
python3 script/test_review_native_sampler_identity.py
python3 script/test_privacy_masked_sampler_paths.py
python3 script/review_native_sampler_identity.py \
  --arm64 /path/to/D22-R1-arm64.zip \
  --x86-64 /path/to/D22-R1-x86_64.zip \
  --output /path/to/new-D23-review.json
```

The artifact filenames are local choices; their exact byte identities determine
whether they qualify. The output destination must be new. Omitting `--output`
writes the deterministic JSON result to standard output. The original artifacts
must already be available; the review performs no downloads, native launches,
sampling, recording, input injection or settings changes.

The public archive-review entry point uses the fixed manifest. The lower-level
semantic validator is also exercised using explicitly synthetic fixtures whose
bindings are rebuilt after selected mutations. Its output must identify that
archive authenticity was not checked. This permits meaningful negative tests
of a wrong UUID or bad lifecycle order instead of stopping every case at an
outer ZIP hash mismatch.

### Publication privacy check

The existing publication scanner classified the report's exact anonymous
`/Users/USER/*/NativeSamplerCalibration` display token as a literal home path.
D23 must preserve that token verbatim, so the scanner now recognizes only this
complete, already-masked token in eight explicitly named D23 source, test and
evidence files. Token boundaries prevent a different owner, prefix or suffix
from acquiring the same exception. All other home-path matches and every other
privacy rule continue to inspect the original bytes. Dedicated regression tests
cover the approved token, unlisted files, extended paths and adjacent secrets.

This is a publication false-positive correction. The original D22 identity gate,
its executed source copies and the Finder acceptance criteria retain their
existing meaning. The exact displayed-path comparison in D23 remains false.

## Required interpretation of the output

These facts remain false even when the narrow identity/frame witness succeeds:

| Field | Value | Reason |
| --- | --- | --- |
| `originalD22Complete` | `false` | The executed D22 calibration did not pass its original gate. |
| `exactReportPathMatched` | `false` | The original displayed paths are masked and unequal. |
| `postSamplePSAvailable` | `false` | The original run never made the post-sample identity query. |

No result establishes recorder inspection access, explains D21's sampler
timeout, identifies the activation requester or Escape consumer, or satisfies
the original Finder enter → exit → reenter → Escape → release → distinct fresh
drop acceptance sequence. Orchard, Pistachio and Lemonade on ARM and Intel
remain the unchanged final matrix. Task 08 final acceptance still depends on 07.

## Stop condition

This unit ends after both unchanged original archives have unambiguous derived
results, meaningful negative fixtures reject inconsistent evidence, and an
independent review has checked the resulting claims. No native retry follows
automatically. A later live recorder measurement needs a concrete evidence
question that this controlled-child result cannot answer; the original time
budget and acceptance conditions remain in force.

## Completed verification

The executed D23 revision is
[`088180b54eb2095f9a634ad0c83f7911821a095f`](https://github.com/osmankaankars/lemulip/commit/088180b54eb2095f9a634ad0c83f7911821a095f),
tree `c56a7151beb84f7644107720032707a7180d0e3d`. Verification finished on
9 November 2026 at 10:30:26 UTC / 13:30:26 Europe/Istanbul using CPython
3.12.14 on Linux x86_64. The two native artifact sets remain those produced by
the single earlier D22 run; this verification executes no native program.

| Check | Result |
| --- | --- |
| Identity/frame negative-test suite | 32 methods passed; synthetic ARM and Intel baselines remain semantic-only. |
| Masked-path publication privacy suite | 7 methods passed, including real-path and adjacent-secret rejection. |
| Original archive review | Both immutable ZIPs accepted; all 156 member byte identities and 24 retained source copies verified. |
| Immutable inputs | All 102 before/after build/source entries agree. |
| Independent reconstruction | Every derived JSON value matched a separate parser and lifecycle reconstruction. |
| Input preservation | Both complete ZIP byte lengths and SHA-256 values remained unchanged after review. |

The negative fixtures rebuild the relevant outer and internal hashes before
introducing a semantic inconsistency. They cover swapped/duplicate UUIDs,
foreign identities and architectures, wrong/summary-only frames, zero counts,
changed bytes, ambiguous records, incorrect symbol or image addresses, mixed
receipt instances, contradictory clocks and invalid cleanup order.

Review found and fixed specific false-positive paths before publication: a
coherently displaced PC in another function, overlapping image ownership,
contradictory spawn/elapsed clocks, an unchecked dot ZIP name, hidden NUL names,
JSON exponent overflow, and contradictory Mach-O section metadata. The exact
original archives continue to pass after those rejection rules were added.

| Retained witness | ARM64 | Intel |
| --- | --- | --- |
| UUID | `DA0DE39D-199B-426C-938A-D111DA3D942E` | `5CA00F5F-6107-4C8C-B368-BF38515252AD` |
| Counted wait-frame samples | 82 | 97 |
| Preferred wait symbol address | `0x1000004b0` | `0x1000004c0` |
| Wait function size / exclusive end | `0x60c` / `0x100000abc` | `0x640` / `0x100000b00` |
| Report main load address | `0x102c90000` | `0x10b87a000` |
| Sampled PC / reported displacement | `0x102c90674` / 452 | `0x10b87a69c` / 476 |
| Native normal EOF / exit | Verified / 0 | Verified / 0 |
| Original full D22 complete | false | false |

The retained function ends agree with the next defined text symbol,
`_capture_clock`. Each sampled PC lies inside the wait function's extent and
belongs uniquely to the expected reported image.

The exact derived review is 17,541 bytes, SHA-256
`733f737168f1481acde1f816d2e5a74b9c75cf14c96018e94cc846fc17d68e85`.
The independent audit is 5,445 bytes, SHA-256
`955463a218591ae15f89f9ad989d62e2a635d2c478e27e24c28ce3c25a2dd67b`;
its full parsed result and source identities are retained in the verification
receipt. This is a consistency review, not a reproducible-build proof of
source-to-instruction equivalence.

### Decision after D23

The offline identity/frame witness unit is complete. The remaining concrete
recorder question is **which startup stage prevents the recording-start
notification, and whether bounded sampling stalls before capture or during
report/symbol processing**. D21's retained initial banner cannot distinguish
those stages. A subsequent recorder-specific observation needs to answer that
question while preserving the existing ownership and time bounds. D23 itself
ends here, without another sampler/recorder run or a changed task 07 gate.
