#!/usr/bin/env bash
# Publish a reviewed source package using an already authenticated GitHub CLI.
set +x
set +v
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$PROJECT_DIR"
if ! command -v python3 >/dev/null; then
  echo "Python 3 is required. Install it before running this helper." >&2
  exit 1
fi
exec python3 - "$PROJECT_DIR" <<'FREEWHEEL_PUBLISH'
import json
import os
from pathlib import Path
import plistlib
import re
import shlex
import shutil
import stat
import subprocess
import sys
import time
import uuid

ROOT = Path(sys.argv[1]).resolve()
REPO_NAME = "freewheel"
BRANCH = "main"
STATE_KEY = "freewheel.publishState"
AUTHOR = "Freewheel contributors"
EMAIL = "freewheel@users.noreply.github.com"
COMMIT_MESSAGE = "Add Freewheel local macOS file converter"
DESCRIPTION = "File tools, right where you drag. Free, local file conversion for macOS."
TOPICS = ["macos", "swift", "swiftui", "file-converter", "drag-and-drop",
          "productivity", "offline", "privacy", "open-source", "pdf-tools",
          "image-converter", "ffmpeg"]
ENV = {k: v for k, v in os.environ.items()
       if not k.startswith("GIT_") and k not in {"GH_DEBUG", "GH_REPO", "GH_HOST", "GH_FORCE_TTY"}}
ENV.update(GH_HOST="github.com", GH_PROMPT_DISABLED="1", NO_COLOR="1",
           GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1",
           GIT_ATTR_NOSYSTEM="1", GIT_TERMINAL_PROMPT="0",
           GIT_NO_REPLACE_OBJECTS="1", GCM_INTERACTIVE="never",
           GH_PAGER="cat", PAGER="cat")
GIT = shutil.which("git")
GH = shutil.which("gh")


class PublishError(Exception):
    pass


def stop(message):
    raise PublishError(message)


def invoke(arguments, *, data=None, allow_failure=False, timeout=60, label="Command"):
    try:
        result = subprocess.run(arguments, cwd=ROOT, env=ENV, input=data,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                timeout=timeout)
    except subprocess.TimeoutExpired:
        stop(label + " timed out. State was preserved; rerun this helper to check and resume.")
    if result.returncode and not allow_failure:
        match = re.search(rb"HTTP (\d{3})", result.stderr)
        detail = " (HTTP " + match.group(1).decode() + ")" if match else ""
        stop(label + " failed" + detail + ". See docs/PUBLISHING.md; no credentials or raw logs were printed.")
    return result


def git(*arguments, **options):
    # Ignore personal config. Disable hooks, signing, attributes, replacements,
    # implicit tags, redirects, and interactive credential prompts for each call.
    controls = [
        "core.hooksPath=" + os.devnull, "core.fsmonitor=false",
        "core.attributesFile=" + os.devnull, "commit.gpgSign=false",
        "tag.gpgSign=false", "push.gpgSign=false", "push.followTags=false",
        "i18n.commitEncoding=UTF-8", "http.followRedirects=false",
        "protocol.allow=never", "protocol.https.allow=always",
        "credential.helper=", "credential.helper=!" + shlex.quote(GH or "gh") + " auth git-credential",
    ]
    prefix = [GIT, "--literal-pathspecs"]
    for setting in controls:
        prefix += ["-c", setting]
    return invoke(prefix + list(arguments), **options)


def value(*arguments):
    return git(*arguments).stdout.decode("utf-8").strip()


def api(method, endpoint, payload=None, *, missing_ok=False, optional=False):
    arguments = [GH, "api", "--hostname", "github.com", "--method", method,
                 "-H", "Accept: application/vnd.github+json",
                 "-H", "X-GitHub-Api-Version: 2026-03-10", endpoint]
    data = None
    if payload is not None:
        arguments += ["--input", "-"]
        data = json.dumps(payload, separators=(",", ":")).encode()
    try:
        result = invoke(arguments, data=data, allow_failure=True, label="GitHub API")
    except PublishError:
        if optional:
            return False, "unavailable"
        raise
    if result.returncode:
        match = re.search(rb"HTTP (\d{3})", result.stderr)
        code = match.group(1).decode() if match else "unavailable"
        if missing_ok and code == "404":
            return None
        if optional:
            return False, code
        stop("GitHub API request failed (" + code + "). Check the existing account's access, network, and repository settings.")
    if optional:
        return True, None
    try:
        return json.loads(result.stdout) if result.stdout.strip() else {}
    except json.JSONDecodeError:
        stop("GitHub returned an unreadable response. No further action was taken.")


def save(state):
    git("config", "--local", STATE_KEY, json.dumps(state, sort_keys=True, separators=(",", ":")))


def privacy(*arguments):
    result = invoke([sys.executable, "script/privacy_check.py", *arguments],
                    allow_failure=True, label="Public source check")
    if result.returncode:
        # The checker reports filenames/rule names, never matching secret values.
        sys.stderr.write(result.stderr.decode("utf-8", errors="replace"))
        stop("Public source check failed. Nothing will be pushed. Review the reported files.")
    return result.stdout


def update_demo_link(owner):
    # Read without following a symlink, then atomically replace only this
    # project's directory entry. A changed path cannot redirect the write.
    directory = os.open(ROOT, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    temporary = None
    try:
        descriptor = os.open("README.md", os.O_RDONLY | os.O_NOFOLLOW, dir_fd=directory)
        with os.fdopen(descriptor, "rb") as handle:
            original = os.fstat(handle.fileno())
            if not stat.S_ISREG(original.st_mode) or original.st_size > 2_000_000:
                stop("README must be a regular source file smaller than 2 MB.")
            raw = handle.read(2_000_001)
        if len(raw) > 2_000_000:
            stop("README changed beyond the source size limit.")
        readme = raw.decode("utf-8")
        start = "<!-- FREEWHEEL_DEMO_LINK_START -->"
        end = "<!-- FREEWHEEL_DEMO_LINK_END -->"
        if start not in readme and end not in readme:
            return
        if readme.count(start) != 1 or readme.count(end) != 1 or readme.index(start) >= readme.index(end):
            stop("The README demo-link block is malformed. Review it before publishing.")
        homepage = "https://" + owner.lower() + ".github.io/" + REPO_NAME + "/"
        block = (start + "\n[Open the browser walkthrough](" + homepage +
                 ") · Available after the Pages deployment succeeds. This is a simulation; the Mac app performs conversions.\n" + end)
        updated = (readme[:readme.index(start)] + block +
                   readme[readme.index(end) + len(end):]).encode("utf-8")
        if updated == raw:
            return
        temporary = ".freewheel-readme-" + uuid.uuid4().hex
        descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                             0o600, dir_fd=directory)
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(updated)
            handle.flush()
            os.fchmod(handle.fileno(), original.st_mode & 0o777)
        current = os.stat("README.md", dir_fd=directory, follow_symlinks=False)
        fields = ("st_dev", "st_ino", "st_size", "st_mtime_ns")
        if not stat.S_ISREG(current.st_mode) or any(getattr(current, field) != getattr(original, field) for field in fields):
            stop("README changed during publishing. Its new contents were not overwritten.")
        os.replace(temporary, "README.md", src_dir_fd=directory, dst_dir_fd=directory)
        temporary = None
    finally:
        if temporary is not None:
            try:
                os.unlink(temporary, dir_fd=directory)
            except FileNotFoundError:
                pass
        os.close(directory)


def verify_repository(repository, owner, owner_id):
    if not isinstance(repository, dict) or (
        repository.get("full_name", "").lower() != (owner + "/" + REPO_NAME).lower()
        or repository.get("owner", {}).get("id") != owner_id
        or repository.get("private") is not False
        or repository.get("archived") is True
        or not isinstance(repository.get("id"), int)
    ):
        stop("The remote repository does not match this helper's expected public repository. It was not modified.")


def remote_refs(origin):
    output = git("ls-remote", "--heads", "--tags", origin, label="Read remote references").stdout
    references = {}
    for line in output.decode("utf-8").splitlines():
        sha, name = line.split("\t", 1)
        references[name] = sha
    return references


def verify_refs(references, commit, tag, tag_object, *, require=False):
    expected = {"refs/heads/" + BRANCH: commit, "refs/tags/" + tag: tag_object,
                "refs/tags/" + tag + "^{}": commit}
    if any(name not in expected or expected[name] != sha for name, sha in references.items()):
        stop("Remote history or tags differ from this helper's recorded preview. No overwrite or force push was attempted.")
    if require and references != expected:
        stop("The expected branch and annotated tag could not both be verified. Rerun to check the preserved state.")


def main():
    if not GIT or not GH:
        stop("Git and GitHub CLI are required. Install GitHub CLI with 'brew install gh'.")
    required = ["README.md", "Package.swift", "Resources/Info.plist", "script/privacy_check.py",
                "Sources/Freewheel/FreewheelApplication.swift",
                ".github/workflows/build.yml", ".github/workflows/pages.yml", "site/index.html"]
    if any(not (ROOT / name).is_file() or (ROOT / name).is_symlink() for name in required):
        stop("Run this helper from a complete, reviewed Freewheel source package.")
    top = git("rev-parse", "--show-toplevel", allow_failure=True)
    if top.returncode == 0 and Path(top.stdout.decode().strip()).resolve() != ROOT:
        stop("This folder is inside another repository. Extract Freewheel into its own folder.")
    git_dir = ROOT / ".git"
    if git_dir.exists() and (git_dir.is_symlink() or not git_dir.is_dir()):
        stop("Linked worktrees and external Git directories are not supported. Use a fresh source package.")
    if not git_dir.exists():
        git("init", "--initial-branch=" + BRANCH, "--template=", label="Initialize source repository")
    for current, directories, files in os.walk(git_dir, followlinks=False):
        if any((Path(current) / name).is_symlink() for name in directories + files):
            stop("This Git directory contains a symbolic link. Use a fresh source package.")
    if any((git_dir / relative).exists() for relative in ["objects/info/alternates", "objects/info/http-alternates"]):
        stop("This Git directory shares external objects. Use a fresh source package.")
    config_keys = value("config", "--local", "--name-only", "--list").lower().splitlines()
    blocked = ("include.", "includeif.", "url.", "filter.", "credential.", "http.", "protocol.", "extensions.")
    if any(key.startswith(blocked) or key in {"core.worktree", "core.bare"} and
           value("config", "--local", key) not in {"false", ""} for key in config_keys):
        stop("This Git directory has custom routing or object settings. Use a fresh source package; no settings were removed.")
    if any(key.startswith("remote.") and key not in {"remote.origin.url", "remote.origin.fetch"} for key in config_keys):
        stop("This Git directory has custom remote settings. Review them manually.")
    if (git_dir / "info/attributes").exists() or (git_dir / "shallow").exists():
        stop("Custom Git attributes or shallow history are present. Use a fresh source package.")

    marker = git("config", "--local", "--get", STATE_KEY, allow_failure=True)
    try:
        state = json.loads(marker.stdout) if marker.returncode == 0 else None
    except json.JSONDecodeError:
        stop("The local publishing marker is invalid. Review this repository manually.")
    head = git("rev-parse", "--verify", "HEAD", allow_failure=True)
    refs = value("for-each-ref", "--format=%(refname)", "refs/heads", "refs/tags").splitlines()
    remotes = value("remote").splitlines()
    if state is None:
        if head.returncode == 0 or refs or remotes:
            stop("This helper publishes fresh source only. Existing history or remotes were found and will not be uploaded.")
        git("symbolic-ref", "HEAD", "refs/heads/" + BRANCH)
    elif not isinstance(state, dict) or state.get("schema") != 2:
        stop("This repository was not initialized by this publisher version. Review it manually.")
    if value("symbolic-ref", "--short", "HEAD") != BRANCH:
        stop("The current branch is not the helper's recorded main branch.")

    auth = invoke([GH, "auth", "status", "--active", "--hostname", "github.com"], allow_failure=True)
    if auth.returncode:
        stop("GitHub CLI is not already authenticated. Complete its normal sign-in separately, then rerun. This helper does not open login pages or collect tokens.")
    user = api("GET", "user")
    owner, owner_id = user.get("login"), user.get("id")
    if not isinstance(owner, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9-]{0,38}", owner) or not isinstance(owner_id, int) or owner_id <= 0:
        stop("Could not establish the authenticated GitHub account.")
    expected_owner = ENV.get("FREEWHEEL_GITHUB_OWNER")
    if expected_owner is not None and (
        not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9-]{0,38}", expected_owner)
        or expected_owner.lower() != owner.lower()
    ):
        stop("The authenticated GitHub account does not match FREEWHEEL_GITHUB_OWNER. No source edit or repository creation was made. Check the active account separately.")
    slug = owner + "/" + REPO_NAME
    origin = "https://github.com/" + slug + ".git"
    repo_endpoint = "repos/" + slug
    if state is None:
        privacy()
        update_demo_link(owner)

    # Refuse an unrelated staged file before adding the reviewed source list.
    if git("ls-files", "-z").stdout:
        privacy("--staged")
    try:
        names = json.loads(privacy("--list-files"))
    except json.JSONDecodeError:
        stop("Could not read the validated public file list.")
    if not names or not all(isinstance(name, str) for name in names) or len(set(names)) != len(names):
        stop("The public file list is invalid.")
    for name in names:
        for parent in (ROOT / name).parents:
            if parent == ROOT.parent:
                break
            if (parent / ".gitattributes").exists():
                stop("Git attribute overrides were found. Use a fresh source package.")
    git("add", "--", *names, label="Stage reviewed public sources")
    privacy("--staged")
    staged = sorted(n.decode("utf-8") for n in git("ls-files", "-z").stdout.split(b"\0") if n)
    if staged != sorted(names):
        stop("The full index differs from the reviewed file list. No commit or upload was made.")
    tree = value("write-tree")
    with (ROOT / "Resources/Info.plist").open("rb") as handle:
        version = plistlib.load(handle).get("CFBundleShortVersionString", "")
    if not isinstance(version, str) or not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        stop("The source version is invalid.")
    tag = "v" + version

    repository = api("GET", repo_endpoint, missing_ok=True)
    if state is None:
        if repository is not None:
            stop("A repository named freewheel already exists for this account. It was not modified. Use a different fresh project or review the existing repository manually.")
        state = {"schema": 2, "owner": owner, "owner_id": owner_id, "origin": origin,
                 "branch": BRANCH, "version": version, "tree": tree, "date": str(int(time.time())) + " +0000",
                 "commit": None, "repo_id": None, "creation_started": False,
                 "creation_succeeded": False, "pages_dispatched": False}
        save(state)
    else:
        expected = {"owner": owner, "owner_id": owner_id, "origin": origin,
                    "branch": BRANCH, "version": version, "tree": tree}
        if any(state.get(key) != entry for key, entry in expected.items()) or not re.fullmatch(r"[0-9]+ \+0000", str(state.get("date", ""))):
            stop("The account, source tree, version, or local marker changed. This helper will not publish different history on a retry.")
        if remotes and (remotes != ["origin"] or value("config", "--local", "--get-all", "remote.origin.url") != origin):
            stop("The origin remote changed. Review it manually; no remote was rewritten.")
        if any(key.startswith("remote.") and key.endswith(".pushurl") for key in config_keys):
            stop("A separate push URL is configured. Review it manually.")
        if state.get("repo_id") is not None:
            verify_repository(repository, owner, owner_id)
            if repository["id"] != state["repo_id"]:
                stop("The remote repository identity changed. It was not modified.")
        elif repository is not None and state.get("creation_succeeded") is not True:
            stop("A repository now exists, but its creation was not confirmed by this helper. Review it manually before publishing.")

    ENV.update(GIT_AUTHOR_NAME=AUTHOR, GIT_AUTHOR_EMAIL=EMAIL,
               GIT_COMMITTER_NAME=AUTHOR, GIT_COMMITTER_EMAIL=EMAIL,
               GIT_AUTHOR_DATE=state["date"], GIT_COMMITTER_DATE=state["date"])
    if head.returncode:
        git("-c", "user.name=" + AUTHOR, "-c", "user.email=" + EMAIL,
            "-c", "commit.cleanup=verbatim", "commit", "--no-gpg-sign", "-m", COMMIT_MESSAGE,
            label="Create public source commit")
    commit = value("rev-parse", "HEAD")
    expected_commit = ("tree " + tree + "\nauthor " + AUTHOR + " <" + EMAIL + "> " + state["date"] +
                       "\ncommitter " + AUTHOR + " <" + EMAIL + "> " + state["date"] +
                       "\n\n" + COMMIT_MESSAGE + "\n")
    if git("cat-file", "commit", commit).stdout.decode() != expected_commit or (
        state.get("commit") is not None and state["commit"] != commit
    ):
        stop("The local commit is not the exact anonymous initial commit recorded by this helper.")
    state["commit"] = commit
    save(state)
    permitted = {"refs/heads/" + BRANCH, "refs/tags/" + tag}
    if any(ref not in permitted for ref in refs):
        stop("Additional local branches or tags were found. They will not be published by this helper.")
    tag_ref = "refs/tags/" + tag
    tag_message = "Freewheel " + version + " public preview"
    if git("show-ref", "--verify", "--quiet", tag_ref, allow_failure=True).returncode:
        git("-c", "user.name=" + AUTHOR, "-c", "user.email=" + EMAIL,
            "tag", "-a", tag, commit, "-m", tag_message, label="Create annotated preview tag")
    expected_tag = ("object " + commit + "\ntype commit\ntag " + tag + "\ntagger " + AUTHOR +
                    " <" + EMAIL + "> " + state["date"] + "\n\n" + tag_message + "\n")
    if git("cat-file", "tag", tag_ref).stdout.decode() != expected_tag:
        stop("The local preview tag has a different target or annotation. It was not overwritten.")
    tag_object = value("rev-parse", tag_ref)
    print("Checked " + str(len(names)) + " source files. Public identity: " + AUTHOR + ".", flush=True)

    if repository is None:
        if state.get("creation_succeeded") or state.get("repo_id") is not None:
            stop("The previously created repository is no longer available. The helper will not create a replacement.")
        state["creation_started"] = True
        save(state)
        invoke([GH, "repo", "create", slug, "--public", "--description", DESCRIPTION],
               label="Create public GitHub repository")
        state["creation_succeeded"] = True
        save(state)
        repository = api("GET", repo_endpoint)
    verify_repository(repository, owner, owner_id)
    if state.get("repo_id") not in {None, repository["id"]}:
        stop("Remote repository identity mismatch.")
    state["repo_id"] = repository["id"]
    save(state)
    if not remotes:
        git("remote", "add", "origin", origin, label="Record public origin")
    verify_refs(remote_refs(origin), commit, tag, tag_object)

    warnings = []
    def optional_api(label, method, endpoint, payload=None):
        ok, code = api(method, endpoint, payload, optional=True)
        if not ok:
            warnings.append(label + " (" + code + ")")
            print("Needs attention: " + label + ". Check repository settings and existing account permissions.", flush=True)
        return ok

    # These repository settings do not change authentication scopes or enable
    # a paid Advanced Security product. Unsupported settings are reported.
    optional_api("Private vulnerability reporting", "PUT", repo_endpoint + "/private-vulnerability-reporting")
    for feature, label in [("secret_scanning", "Secret scanning"),
                           ("secret_scanning_push_protection", "Secret scanning push protection")]:
        optional_api(label, "PATCH", repo_endpoint, {"security_and_analysis": {feature: {"status": "enabled"}}})
    optional_api("Dependabot alerts", "PUT", repo_endpoint + "/vulnerability-alerts")
    optional_api("Dependabot security updates", "PUT", repo_endpoint + "/automated-security-fixes")

    privacy("--staged")
    if value("write-tree") != tree:
        stop("The index changed during publishing. No push was attempted.")
    print("Publishing main and " + tag + " to https://github.com/" + slug + " ...", flush=True)
    git("push", "--atomic", origin, commit + ":refs/heads/" + BRANCH, tag_object + ":" + tag_ref,
        timeout=120, label="Push reviewed branch and preview tag")
    verify_refs(remote_refs(origin), commit, tag, tag_object, require=True)
    git("config", "--local", "branch.main.remote", "origin")
    git("config", "--local", "branch.main.merge", "refs/heads/main")

    metadata = invoke([GH, "repo", "edit", slug, "--description", DESCRIPTION,
                       "--enable-issues", "--enable-discussions", "--enable-wiki=false",
                       "--default-branch", BRANCH], allow_failure=True, label="Configure repository")
    if metadata.returncode:
        warnings.append("Repository description / issues / discussions / wiki")
    optional_api("Repository topics", "PUT", repo_endpoint + "/topics", {"names": TOPICS})
    pages = api("GET", repo_endpoint + "/pages", missing_ok=True, optional=True)
    if pages is not None and not pages[0]:
        warnings.append("Read Pages settings (" + pages[1] + ")")
        pages_ok = False
    else:
        pages_ok = optional_api("GitHub Pages using Actions", "POST" if pages is None else "PUT",
                               repo_endpoint + "/pages", {"build_type": "workflow"})
    if pages_ok:
        homepage = "https://" + owner.lower() + ".github.io/" + REPO_NAME + "/"
        optional_api("Repository homepage", "PATCH", repo_endpoint, {"homepage": homepage})
        if not state.get("pages_dispatched"):
            dispatch = invoke([GH, "workflow", "run", "pages.yml", "--repo", slug, "--ref", BRANCH],
                              allow_failure=True, label="Start Pages workflow")
            if dispatch.returncode:
                warnings.append("Pages workflow dispatch; run Website and interactive demo in Actions")
            else:
                state["pages_dispatched"] = True
                save(state)
        print("Pages is configured. Its URL becomes available after deployment: " + homepage)

    print("\nSource and annotated tag are published:")
    print("Repository: https://github.com/" + slug)
    print("Builds:     https://github.com/" + slug + "/actions")
    print("Releases:   https://github.com/" + slug + "/releases")
    print("CI must pass before it publishes preview ZIP, DMG, source, and checksum assets.")
    print("No build, release, or website success is assumed by this helper.")
    if warnings:
        print("\nSource publication succeeded; these settings still need attention:")
        for warning in warnings:
            print("- " + warning)
        print("Review Settings, then rerun this unchanged folder to retry setup. No token scopes were changed.")
    runs = invoke([GH, "run", "list", "--repo", slug, "--limit", "5", "--commit", commit,
                   "--json", "workflowName,status,conclusion"],
                  allow_failure=True, timeout=30, label="Read workflow status")
    if not runs.returncode:
        try:
            for run in json.loads(runs.stdout):
                print(str(run.get("workflowName", "Workflow")) + ": " +
                      str(run.get("conclusion") or run.get("status") or "pending"))
        except (json.JSONDecodeError, TypeError):
            pass


try:
    main()
except (PublishError, OSError, ValueError, plistlib.InvalidFileException) as error:
    message = str(error) if isinstance(error, PublishError) else "A local file or tool could not be read safely. Review the source folder and rerun."
    print("Freewheel: " + message, file=sys.stderr)
    sys.exit(1)
FREEWHEEL_PUBLISH
