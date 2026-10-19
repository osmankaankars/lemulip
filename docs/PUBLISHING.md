# Publish and Maintain Lemulip

The existing [Lemulip repository](https://github.com/osmankaankars/lemulip) prepares
preview releases automatically after reviewed source reaches `main` and its
required checks pass. Publishing source does not reinstall the Mac app; download
the verified DMG or app ZIP when the tagged release finishes.

## Automatic Preview Releases

1. **Build and Verify** tests the code on Apple silicon and Intel, builds the
   universal package, and verifies the exact downloaded archives on both
   architectures. **CodeQL** runs independently on the same commit.
2. **Preview Release** checks that both latest workflow runs passed for the same
   commit, including the latest execution of all five required build jobs and
   the CodeQL analysis job. A partial rerun can retain earlier successes within
   the same run. It verifies the repository identity and confirms that the
   commit is still `main` before checking out any source.
3. After repeating those checks, it creates an annotated `vMAJOR.MINOR.PATCH` tag
   matching `Resources/Info.plist`. The tagger is explicitly
   `Kaan Kars <56635935+osmankaankars@users.noreply.github.com>`.
4. It explicitly starts **Build and Verify** at that tag. The tagged pipeline
   builds the release archives, verifies their downloads again, and publishes
   the complete preview release with its DMG, app ZIP, source ZIP, and checksums.

Source checks and tagged builds are separate runs. A successful Pages deployment
does not satisfy the native build gate. A successful source build alone does not
mean the release files have been published yet.

The workflow needs no personal access token or signing identity in the source.
Its first job has read permissions; only the second job has the repository
contents and Actions write permissions needed to create the tag and dispatch
the build. GitHub's built-in token creates the annotation with the approved
public tagger. Its tag creation does not trigger a push workflow, so the explicit
dispatch is necessary. See [GitHub's workflow-triggering rules](https://docs.github.com/en/actions/concepts/security/github_token).

The coordinator never moves an existing tag, changes release contents, or reruns
a failed tagged build automatically. If the matching tag already exists, it
checks the target, tagger, and exact annotation. An active or successful tagged
build prevents a duplicate dispatch. Historical tags and releases stay intact.

### Resume a Missing Tag or Build

After the commit's source checks pass, open **Actions → Preview Release → Run
Workflow**, choose `main`, and run it. This resumes an interrupted tag or dispatch
step without rewriting history. A queued or failed source check still blocks a
new tag; fix the source failure first.

If a tagged build fails, inspect its failed job and rerun that build only after
resolving the cause. **Preview Release** leaves the failed run and existing tag
in place for review. The final publisher can resume a matching incomplete draft:
it preserves verified uploaded files and adds only missing files. It preserves
conflicting tags, assets, and published releases, and publishes the draft only
after all four expected assets match. If a GitHub 502 response left an empty
asset with `state=starter`, inspect and remove only that empty draft placeholder
before rerunning the failed publisher job; an ordinary rerun will not replace it.

If the version tag belongs to a different commit, update the app version and
release notes for a new release. Do not delete or move the existing tag to make
the automation pass.

## Write Release Notes

Keep the public changelog in [Release Notes](RELEASE_NOTES.md). Add one section
headed `## MAJOR.MINOR.PATCH · Title`, with a few short bullets about that
release's changes and any relevant guide links. Use Title Case for headings.
When several development versions never produced downloads, summarize their
new features in the next published release.

The publisher selects only the section matching the release tag and appends
the shared `## Installation` section. It converts relative documentation links
to links at that exact tag. Missing, repeated, or empty sections stop publication;
the full changelog is never used as a fallback release description.

Keep CI logs, repair chronology, implementation details, and future plans out of
release descriptions. Link to the guides or development history when needed.
The full source changelog still travels with the download, and the publisher
still requires it to match the tagged source byte for byte.

Editing a published release description changes its text only. Preserve its
tag, title, preview status, download files, and checksums. An old publisher retry
deliberately refuses metadata that has since been edited; do not rerun a
successful old release just to update its description.

## Publish a Fresh Repository

The included `Publish-to-GitHub.command` is a legacy initialization helper. It
creates a new public repository named `lemulip` under the GitHub account already
authenticated in your terminal, publishes an initial source package and preview
tag, and configures repository settings. Use the reviewed update workflow for
the existing project.

Both release scripts deliberately verify the existing project's repository ID,
owner ID, public tagger, and exact annotation. The helper's initial annotation
uses an older format. Before tagged publication can succeed in a fork or new
repository, its maintainer must adapt and review **both**
`script/publish_preview.py` and `script/publish_release.py`, their release
workflows, and the initial tag creation step for that repository. Running the
legacy helper alone does not complete this release setup.

You do not need to rerun `Build-and-Install.command` before source publication;
GitHub Actions handles the release build.

## Before Running It

Install Git, Python 3, and [GitHub CLI](https://cli.github.com). On a Mac with Homebrew, GitHub CLI can be installed with:

```bash
brew install gh
```

Check that GitHub CLI is already signed in to the intended account:

```bash
gh auth status --active --hostname github.com
```

If sign-in is needed, complete it separately using GitHub CLI's normal authentication flow. The publisher does not open login pages, collect a token, or request broader scopes.

Review the source folder before making it public. The intended contents are the application, focused tests used by CI, build scripts, guides, artwork, and browser walkthrough. Keep private documents and personal screenshots outside it.

## Run the Publisher

Extract the source into its own folder, open Terminal there, and run:

```bash
./Publish-to-GitHub.command
```

If the download lost its execute permission:

```bash
chmod u+x ./Publish-to-GitHub.command
./Publish-to-GitHub.command
```

The helper uses the authenticated account's GitHub login to choose the owner and
the public commit name. Commit and tag attribution uses that account's ID-based
GitHub `noreply` address. It ignores your personal Git name and private email.

This lets GitHub associate the contribution with the account while keeping its
private email out of public history. See GitHub's [commit email reference](https://docs.github.com/en/account-and-profile/reference/email-addresses-reference).

If you use more than one GitHub account, bind this run to the expected login. Replace the example value with your GitHub username:

```bash
LEMULIP_GITHUB_OWNER="your-github-login" ./Publish-to-GitHub.command
```

A mismatch stops before editing the source or creating a repository.

On the first run, it checks the working source, fills the marked README demo-link paragraph with the account's Pages address, and checks the source again before committing. The paragraph says the link becomes available after deployment and identifies the demo as a simulation. If that marked block is absent, the README is left untouched.

### What the Command Sets Up

| Item | Result |
| --- | --- |
| Repository | A new public `lemulip` repository |
| Source | One initial commit containing the exact privacy-checked file list |
| Tag | An annotated preview tag matching `Info.plist`, such as `v0.1.4` |
| About | Description, relevant topics, Issues and Discussions enabled, Wiki disabled |
| Website | GitHub Pages configured to use the included Actions workflow |
| Homepage | The repository's Pages address after Pages configuration succeeds |
| Security | Attempts private vulnerability reporting, secret scanning, push protection, and Dependabot settings where available |
| Downloads | Built and verified by CI; publication requires the reviewed release setup above |

The source check runs against the working files and the entire staged index. An unrelated staged file blocks publication. Build products, local Git metadata, downloaded source ZIPs, private files, and credentials are not part of the source commit.

Only `main` and the matching annotated preview tag are pushed. The helper does not force-push, delete a repository, reset history, or overwrite an existing remote project.

## What to Expect Afterward

The command prints repository, Actions, and Releases links. It lists workflow status once and exits; it does not wait indefinitely for a build.

The **Build and Verify** workflow tests the native code on Apple silicon and
Intel, builds universal packages, and verifies the exact downloads on both
architectures. Once the release setup matches the repository and annotated tag,
a successful tagged run publishes a prerelease with:

- The universal macOS ZIP, including the app and CLI.
- The universal macOS DMG.
- A source ZIP.
- `SHA256SUMS.txt`.

The preview is ad-hoc signed, without Developer ID signing or notarization. Do not describe a binary as verified until its workflow has succeeded.

**Website and Interactive Demo** publishes `site/` through Pages. Its address becomes usable after deployment succeeds. The browser walkthrough is a simulation, not the macOS conversion engine.

## Rerun After an Interruption

Rerun the same command from the same unchanged folder. A local marker in `.git/config` records the owner, source tree, account-attributed commit, version, and remote repository ID. It is never published.

A retry checks those values, the origin URL, local branch and tag, and remote references before continuing. It can retry missing setup after a completed source push. Existing matching references are left in place.

If source files, history, the account, remote URL, or repository identity changed, the helper stops. Use the normal contribution workflow for later development.

If repository creation returned an uncertain result and a repository now exists, the helper also stops rather than assuming ownership of it. Inspect the repository and its history manually. Do not erase the local marker to bypass this check.

### Common Setup Failures

| Message | Next Step |
| --- | --- |
| `lemulip` already exists | Review the existing repository; this helper will not replace it |
| Public source check failed | Remove the reported private or unexpected content from the intended public set, then inspect the staged diff |
| Existing history or remotes | Use a fresh extracted source package, or manage the existing repository manually |
| Push failed | Check connectivity and the authenticated account's permission to push code and workflow files; GitHub may require explicit workflow permission for the existing credential |
| Optional setting needs attention | Open the repository's Settings or Security area; review feature availability and existing account permissions |
| Pages dispatch failed | After Pages is configured, run **Website and Interactive Demo** from Actions |
| Build failed | Inspect the failed job; the workflow will not publish its packages as a release |

The helper reports API failures without printing credentials or raw response bodies. It does not change token scopes or bypass GitHub push protection. Review GitHub's [repository API permissions](https://docs.github.com/en/rest/repos/repos#update-a-repository) and [Pages permissions](https://docs.github.com/en/rest/pages/pages#create-a-github-pages-site) if settings are unavailable.

## Later Releases

Use branches and reviewed pull requests for subsequent changes. Keep only tests that exercise meaningful behavior and generate their fixtures at runtime.

Update the app version and release notes together, run the relevant checks, and
review the staged source. For the existing project, push the reviewed changes to
`main`; **Preview Release** creates the matching tag after the required source
checks pass. Keep signing identities, notarization credentials, and all personal
configuration outside the repository.

For local packaging, use:

```bash
./script/package_release.sh
./script/package_release.sh --verify dist
```

These scripts preserve existing release downloads. They require a clean reviewed source checkout. For public releases, the CI workflow remains the publication gate.

Before announcing a release, check the actual download links, the Pages deployment, a fresh Mac launch, and the main drag workflow. Add a native screen recording once it has been captured and reviewed for private content. The current illustrations and browser walkthrough should remain labeled as such.

If your source package did not include the marked demo-link paragraph, replace its local walkthrough link with the verified Pages address after deployment.

## Renaming an Existing Freewheel Repository

Rename the existing repository to `lemulip` instead of creating a second
repository or rerunning the fresh-source publisher. Keep its repository ID,
commit history, contributors, issues, stars, and historical tags. Publish the
reviewed naming update with a normal fast-forward push.

GitHub redirects repository and Git URLs after a rename, but project Pages URLs
do not redirect automatically. Update the homepage and documentation links to
the new Pages path, then deploy **Website and Interactive Demo** again. See
[GitHub's repository rename guide](https://docs.github.com/en/repositories/creating-and-managing-repositories/renaming-a-repository).

Update local checkouts to the new remote:

```bash
git remote set-url origin https://github.com/osmankaankars/lemulip.git
```

Do not create a new repository at the old name; that would replace GitHub's
redirect. Existing tags keep their original contents. Use a new version and tag
for the first verified Lemulip release.

## GitHub References

- [Create a repository with GitHub CLI](https://cli.github.com/manual/gh_repo_create)
- [Edit repository settings with GitHub CLI](https://cli.github.com/manual/gh_repo_edit)
- [Repository topics and security settings](https://docs.github.com/en/rest/repos/repos)
- [GitHub Pages configuration](https://docs.github.com/en/rest/pages/pages)
- [Workflow completion triggers](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#workflow_run)
- [Workflow dispatch API](https://docs.github.com/en/rest/actions/workflows#create-a-workflow-dispatch-event)
