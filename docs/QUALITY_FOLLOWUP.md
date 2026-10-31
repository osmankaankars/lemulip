# 0.1.20 Integration Follow-Up

31 October 2026. This is a development candidate, not a published download.

## Source

The candidate preserves the frozen UI review source `f402dabbdbd34ba9ea80ac38495caffb2bdf29d1` and current main `4d97ea785ddd2920532587444c94a19a35563191` as commit parents. The original review branch and its artifact remain unchanged. The integration includes the current installation/sharing work and PDF page-range validation from PRs #31 and #32.

The options form retains both localized accessibility names/units and the guarded PDF range submission. No existing interaction test or success assertion is removed.

## Independent Native Checks

The native workflow compiles once, then runs general tests, PDF editor keyboard interactions, selection feedback/editor continuity, exact options accessibility and PDF range correction in separate processes. The ARM pointer review also runs after a successful compile even if another review failed. Every failed step still fails the job and blocks normal release packaging. A failed accessibility lookup must no longer hide the pointer and range results.

The workflow retains checked public source, the exact commit/tree and checksums separately from any application package. This supports inspection of the source actually tested without suggesting a source archive is an app release.

## Still Open

At the start of this follow-up, the frozen review's own-process accessibility lookup and pointer reorder assertions were failing. Integration alone does not fix or approve them. Physical dragging, audible/system-muted sound, VoiceOver narration and real Retina captures remain unverified. Native and security checks of this combined candidate must be read before any merge; full-engine packaging and both architecture checks remain necessary before publishing a new release.

The public website download remains 0.1.19. The promotional film remains last.
