# Publishing

The existing [Lemulip repository](https://github.com/osmankaankars/lemulip)
publishes preview downloads after the matching source and tagged checks pass.
Source publication does not update the installed app; install the release DMG
or app ZIP when the downloads are ready.

## Prepare a Version

1. Update `CFBundleShortVersionString` and `CFBundleVersion` in
   `Resources/Info.plist`, and add the matching release-note section.
2. Run relevant [development checks](DEVELOPMENT.md) and review the exact diff.
   Run `python3 script/privacy_check.py --staged` after staging only intended files.
3. Publish the reviewed change to `main` through the normal contribution workflow.
4. Follow [Actions](https://github.com/osmankaankars/lemulip/actions), then verify
   all four download assets under [Releases](https://github.com/osmankaankars/lemulip/releases).

Keep the approved public contributor identity. Never include private
configuration, credentials, or personal documents in the source.

## Automatic Preview Releases

| Stage | What It Verifies or Publishes |
| --- | --- |
| **Build and Verify** on `main` | Core/native tests on Apple silicon and Intel, optional-engine integrations on Apple silicon, universal packages, and their exact downloads on both architectures |
| **CodeQL** | Swift and C analysis for the same source commit |
| **Preview Release** | Latest successful required jobs, repository identity, and current `main`; then an annotated version tag and explicit tagged-build dispatch |
| **Build and Verify** at the tag | Rebuild and download verification, followed by DMG, app ZIP, source ZIP, and `SHA256SUMS.txt` publication |

The coordinator checks all five required build jobs and the CodeQL analysis job.
A partial rerun may retain successful jobs within the same workflow run. Source
checks and tagged builds are separate; a successful website deployment does not
satisfy either native stage.

The workflow uses GitHub's built-in token. The planning job is read-only; the
publication job has the contents and Actions permissions needed to create a tag
and dispatch its build. Because tags created with that token do not start a
push workflow, the coordinator dispatches the tagged build explicitly. See
[GitHub's triggering rules](https://docs.github.com/en/actions/concepts/security/github_token).

Existing tags are never moved. The coordinator checks their target, public
tagger, and annotation; an active or successful tagged run prevents duplicate
dispatch. A conflicting tag requires a new app version, not a rewritten tag.

## Write Release Notes

Use one `## MAJOR.MINOR.PATCH · Title` section per published version in
[Release Notes](RELEASE_NOTES.md). Keep a few user-facing bullets, relevant
limits, and guide links. Use Title Case for headings. Consolidate changes from
unpublished development versions into the release that delivers them.

The publisher selects only the matching section and appends the shared
`## Installation` section. Missing, duplicate, or empty required sections stop
publication. Relative guide links are pinned to the version tag. The complete
source changelog still travels with the package and must match the tagged file.

Leave CI logs, repair chronology, and future plans out of public release bodies.
When editing an existing description, preserve its title, tag, preview status,
assets, and checksums. An old publisher retry intentionally rejects metadata
that has been edited; do not rerun a completed release to change its description.

## Recover an Interrupted Release

| Situation | Action |
| --- | --- |
| Source build or CodeQL failed | Inspect the failed job and resolve the cause. No new tag is published while required checks fail. |
| Source checks passed, but no tag/build appeared | Run **Actions → Preview Release → Run Workflow** on `main`. |
| Tagged build failed | Inspect and resolve its failure before rerunning that build. The coordinator does not rerun it automatically. |
| Incomplete matching draft | Rerun the publisher job; it retains verified uploaded assets and adds missing ones. |
| Empty draft asset after an uncertain upload | Inspect it and remove only a confirmed empty `state=starter` placeholder before retrying. |
| Conflicting tag, release text, or asset | Stop and review the difference. The publisher will not overwrite it. |

Before announcing a version, check download links and a clean Mac installation.

## Website and Repository Maintenance

**Website and Interactive Demo** deploys `site/` through GitHub Pages. It copies
the reviewed icon and browser-preview image, then supplies repository and
canonical links. Check the workflow result before claiming a new page is live.
The demo remains a simulation using sample files.

For a reviewed documentation-only maintenance commit with no app change, avoid
creating another release at the existing version. An explicit `[skip ci]`
commit can skip automatic push workflows; if website content changed, dispatch
**Website and Interactive Demo** separately on the new `main` commit. This
exception is for text and inactive-file maintenance, not app or workflow changes.
Do not bypass branch protection or claim skipped native checks passed. See
[GitHub's skip instructions](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/skip-workflow-runs).

## Local Packages and Forks

```bash
./script/package_release.sh
./script/package_release.sh --verify dist
```

Use a clean checkout and a new output location. Source-only packaging is available
through `python3 script/package_source.py --output PATH`. These commands preserve
existing archives.

A fork can build locally without a repository setup helper. Before enabling
public releases from a different repository, review the pinned repository/owner
identity and tag annotation in **both** `script/publish_preview.py` and
`script/publish_release.py`, plus their workflows. The current publication
contract belongs to this repository; creating an initial tag alone is not enough.
