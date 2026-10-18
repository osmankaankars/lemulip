# Publish and Maintain a Lemulip Repository

The included publisher creates a new public repository named `lemulip` under the GitHub account already authenticated in your terminal. It publishes the reviewed source and preview tag, configures the project, and lets GitHub Actions build the downloads.

Use this helper for a fresh source package. It is not an updater for an existing project with development history.

For the existing project, preserve its repository and history during the
[Freewheel-to-Lemulip transition](#renaming-an-existing-freewheel-repository).

Publishing the source does not build or reinstall the Mac app. You do not need to rerun `Build-and-Install.command` before using the publisher; GitHub Actions handles the release build after publication.

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
| Downloads | Produced by CI after build, test, and package verification |

The source check runs against the working files and the entire staged index. An unrelated staged file blocks publication. Build products, local Git metadata, downloaded source ZIPs, private files, and credentials are not part of the source commit.

Only `main` and the matching annotated preview tag are pushed. The helper does not force-push, delete a repository, reset history, or overwrite an existing remote project.

## What to Expect Afterward

The command prints repository, Actions, and Releases links. It lists workflow status once and exits; it does not wait indefinitely for a build.

The **Build and Verify** workflow tests the native code on Apple silicon and Intel, builds universal packages, and verifies the exact downloads on both architectures. Only a successful tagged run publishes a prerelease with:

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

Update the app version and release notes together, run the relevant checks, and review the staged source. Tag the reviewed commit with the matching `vMAJOR.MINOR.PATCH` version. Keep signing identities, notarization credentials, and all personal configuration outside the repository.

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
