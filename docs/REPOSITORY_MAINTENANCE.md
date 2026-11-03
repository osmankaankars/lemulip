# Repository Maintenance

Snapshot: **2 November 2026 (Europe/Istanbul)**, before the app and maintenance
follow-up branches. Checked `main` at
[`6198eb469851a3a10a0f4d799f3ab9c3a3fb6907`](https://github.com/osmankaankars/lemulip/commit/6198eb469851a3a10a0f4d799f3ab9c3a3fb6907).
This records findings and candidates. **No remote branches, issues, releases or
artifacts were deleted by this maintenance pass.**

## Branch And Pull Request Inventory

The snapshot contained 50 remote branches including `main`, one open pull
request and no open issues. Comparing each of the 49 other tips against the
checked main commit found 27 exact ancestors and 22 tips with distinct commits.
Ten of those 22 already have merged pull requests, so distinct commits alone do
not prove their changes are missing from main.

The first two candidates for later branch cleanup are fully included in main:

| Branch | Checked tip | Evidence |
| --- | --- | --- |
| `codex/website-human-finish` | `954150b5b39d66a297b0f8d7c19922d616c39fc3` | [Merged PR #36](https://github.com/osmankaankars/lemulip/pull/36); tip is an ancestor of checked main. |
| `codex/website-replay-visibility` | `455575b67e21f24e2fc1f4e6947ca48d3c2c7c3d` | [Merged PR #37](https://github.com/osmankaankars/lemulip/pull/37); tip is an ancestor of checked main. |

Preserve these references and work pending their own review:

- `dependabot/github_actions/github-actions-271845e79b`: active [PR #35](https://github.com/osmankaankars/lemulip/pull/35), updating the pinned CodeQL actions. Keep the dependency change separate from app work.
- `media/film-motion-20261101`: one distinct commit, `281bb396ea327bc797ce2eda73dba5aa21b075dc`, adding a music-research workflow. This is not evidence that the approved final MP4 is archived there.
- `review/quality-020`, `fix/quality-020-followup-20261031` and `measure/binary-symbols`: ancestor tips still named in workflow conditions. Resolve their historical/manual workflow role before pruning them.
- The remaining tips with distinct commits: compare their content and merged PR history before deciding whether work has been superseded. An old date or a closed PR is insufficient evidence for deletion.

Recheck the current branch tip, ancestry, open pull requests and repository
references immediately before any future pruning. The counts above describe this
snapshot, not a standing deletion policy. Release tags, downloadable assets and
historical delivery records remain separate from branch housekeeping.

## CI Fixture And Review Workflow

On checked main, [Build and Verify run 41465338274](https://github.com/osmankaankars/lemulip/actions/runs/41465338274)
failed in [Bundled Engines (x86_64)](https://github.com/osmankaankars/lemulip/actions/runs/41465338274/job/125344594370).
The compressed Git-source manifest test timed out after ten seconds while
creating its fixture with `/usr/bin/git init`, before its archive or manifest
assertions. Checkout earlier in the same job used `/usr/local/bin/git`.
A selected-path or first-start delay is plausible; the logs do not establish
the root cause.

The fixture now resolves Git through the runner's `PATH`, retains its sanitized
`GIT_*` environment and disabled hooks, and allows 30 seconds for `init` while
keeping subsequent commands bounded at ten seconds. Real repository creation,
archive compression, metadata and manifest assertions remain in place. The
fixture suite also runs in the ordinary PR guardrails on both native hosts, so
this change is exercised before merge. Those runs must confirm whether it
addresses the observed timeout; a local pass alone cannot establish that.

The historical 0.1.20 UI review workflow is manual-only and remains restricted
to `review/quality-020`. Its build, exact-ZIP checks and evidence retention are
preserved. Release, native review and current review gates are unchanged by this
maintenance pass. Current product and film status lives in [ROADMAP.md](ROADMAP.md)
and [MARKETING.md](MARKETING.md); historical delivery documents retain their
original context.
