#!/usr/bin/env python3
"""Publish a verified preview through a resumable draft, without replacing assets.

Run only in the tagged Build and Verify workflow after both downloaded-package
checks pass. A retry can complete a matching draft or verify an already complete
published release. Conflicting releases, tags, and assets are always preserved.
"""
from __future__ import annotations

import hashlib
import http.client
import json
import os
from pathlib import Path
import plistlib
import posixpath
import re
import stat
import subprocess
import sys
from dataclasses import dataclass
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener
import zipfile


ROOT = Path(__file__).resolve().parent.parent
REPOSITORY = "osmankaankars/lemulip"
REPOSITORY_ID = 1424213526
OWNER_ID = 56635935
TAGGER_NAME = "Kaan Kars"
TAGGER_EMAIL = "56635935+osmankaankars@users.noreply.github.com"
REQUIRED_JOBS = {
    "macOS Tests (arm64)", "macOS Tests (x86_64)", "Universal macOS Package",
    "Verify Release Download (arm64)", "Verify Release Download (x86_64)",
}
API_VERSION = "2026-03-10"
MAX_JSON_BYTES = 8 * 1024 * 1024
MAX_ASSET_BYTES = 2 * 1024 * 1024 * 1024


class ReleaseError(Exception):
    pass


class APIError(ReleaseError):
    def __init__(self, status: int):
        self.status = status
        super().__init__(f"GitHub returned HTTP {status}. Existing release data is preserved; retry the same workflow after resolving the error.")


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, new_url):
        return None


@dataclass(frozen=True)
class Asset:
    path: Path
    size: int
    sha256: str
    content_type: str


@dataclass(frozen=True)
class Context:
    tag: str
    version: str
    head: str
    run_id: int
    run_attempt: int
    body: str
    assets: dict[str, Asset]

    @property
    def title(self) -> str:
        return f"Lemulip {self.tag} · Public Preview"

    @property
    def annotation(self) -> str:
        return (f"Lemulip {self.tag}\n\n"
                f"Source: https://github.com/{REPOSITORY}/commit/{self.head}\n"
                "Verified on main: Build and Verify, both release download checks, and CodeQL.\n")


class GitHub:
    def __init__(self, token: str):
        if not token:
            raise ReleaseError("The workflow's GitHub token is missing.")
        self.token = token
        self.opener = build_opener(NoRedirect())

    def headers(self, accept: str = "application/vnd.github+json") -> dict[str, str]:
        return {"Authorization": f"Bearer {self.token}", "Accept": accept,
                "X-GitHub-Api-Version": API_VERSION, "User-Agent": "Lemulip-Release-Publisher",
                "Cache-Control": "no-cache"}

    def api(self, route: str, method: str = "GET", payload: dict | None = None):
        if not (route == f"/repos/{REPOSITORY}" or route.startswith(f"/repos/{REPOSITORY}/")):
            raise ReleaseError("Refusing a request outside the release repository.")
        data = None if payload is None else json.dumps(payload).encode("utf-8")
        headers = self.headers()
        if data is not None:
            headers["Content-Type"] = "application/json"
        try:
            with self.opener.open(Request("https://api.github.com" + route, data=data, headers=headers, method=method), timeout=60) as response:
                return read_json(response)
        except HTTPError as error:
            status = error.code
            error.close()
            raise APIError(status) from None

    def upload(self, release_id: int, name: str, asset: Asset):
        connection = http.client.HTTPSConnection("uploads.github.com", timeout=60)
        route = f"/repos/{REPOSITORY}/releases/{release_id}/assets?" + urlencode({"name": name})
        headers = self.headers()
        headers.update({"Content-Type": asset.content_type, "Content-Length": str(asset.size)})
        try:
            with asset.path.open("rb") as stream:
                connection.request("POST", route, body=stream, headers=headers)
                response = connection.getresponse()
                if response.status != 201:
                    raise APIError(response.status)
                return read_json(response)
        finally:
            connection.close()

    def download_digest(self, asset_id: int, expected_size: int) -> str:
        # Draft downloads require authentication at the API endpoint. Signed
        # download redirects never receive the GitHub Authorization header.
        url = f"https://api.github.com/repos/{REPOSITORY}/releases/assets/{asset_id}"
        headers = self.headers("application/octet-stream")
        for _ in range(6):
            try:
                response = self.opener.open(Request(url, headers=headers), timeout=60)
            except HTTPError as error:
                status = error.code
                location = error.headers.get("Location", "")
                error.close()
                if status not in {301, 302, 303, 307, 308}:
                    raise APIError(status) from None
                parsed = urlsplit(location)
                if (parsed.scheme != "https" or parsed.username or parsed.password or parsed.fragment
                        or parsed.port not in {None, 443}
                        or not (parsed.hostname == "github.com" or (parsed.hostname or "").endswith(".githubusercontent.com"))):
                    raise ReleaseError("GitHub returned an unexpected asset download redirect.")
                url = location
                headers = {"User-Agent": "Lemulip-Release-Publisher", "Accept-Encoding": "identity"}
                continue
            with response:
                digest = hashlib.sha256()
                size = 0
                for chunk in iter(lambda: response.read(1024 * 1024), b""):
                    size += len(chunk)
                    if size > expected_size:
                        raise ReleaseError("A downloaded release asset exceeds its expected size.")
                    digest.update(chunk)
                if size != expected_size:
                    raise ReleaseError("A downloaded release asset has an unexpected size.")
                return digest.hexdigest()
        raise ReleaseError("Too many asset download redirects.")


def read_json(response):
    body = response.read(MAX_JSON_BYTES + 1)
    if len(body) > MAX_JSON_BYTES:
        raise ReleaseError("GitHub returned an unexpectedly large response.")
    return json.loads(body)


def git(root: Path, *arguments: str) -> bytes:
    environment = {"PATH": os.defpath, "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull,
                   "GIT_NO_REPLACE_OBJECTS": "1", "GIT_OPTIONAL_LOCKS": "0", "GIT_TERMINAL_PROMPT": "0"}
    return subprocess.check_output(
        ["git", "--literal-pathspecs", "-c", "core.hooksPath=" + os.devnull,
         "-c", "core.fsmonitor=false", *arguments], cwd=root, env=environment,
        stdin=subprocess.DEVNULL, stderr=subprocess.PIPE)


def file_digest(path: Path) -> tuple[int, str]:
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(descriptor, "rb") as stream:
        information = os.fstat(stream.fileno())
        if not stat.S_ISREG(information.st_mode) or not 0 < information.st_size <= MAX_ASSET_BYTES:
            raise ReleaseError("A release artifact is not a supported regular file.")
        digest = hashlib.sha256()
        size = 0
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            size += len(chunk)
            if size > MAX_ASSET_BYTES:
                raise ReleaseError("A release artifact changed while being checked.")
            digest.update(chunk)
        if size != information.st_size:
            raise ReleaseError("A release artifact changed while being checked.")
        return size, digest.hexdigest()


def small_file(path: Path, limit: int) -> bytes:
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(descriptor, "rb") as stream:
        data = stream.read(limit + 1)
    if not data or len(data) > limit:
        raise ReleaseError("A release metadata file is empty or unexpectedly large.")
    return data


def public_notes(notes: str, tag: str) -> str:
    if not re.fullmatch(r"v(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)", tag):
        raise ReleaseError("Release notes require a tag in vMAJOR.MINOR.PATCH format.")
    headings = list(re.finditer(r"^##[ \t]+([^\r\n]+)\r?$", notes, re.MULTILINE))

    def section(pattern: str, description: str) -> tuple[str, str]:
        matches = [(index, heading) for index, heading in enumerate(headings)
                   if re.fullmatch(pattern, heading[1].strip())]
        if len(matches) != 1:
            raise ReleaseError(f"Release notes require exactly one {description}.")
        index, heading = matches[0]
        end = headings[index + 1].start() if index + 1 < len(headings) else len(notes)
        body = notes[heading.end():end].strip()
        if not body:
            raise ReleaseError(f"The release notes {description} is empty.")
        return heading[1].strip(), body

    title, body = section(re.escape(tag[1:]) + r"(?: · .+)?", f"section for {tag}")
    _, installation = section(r"Installation", "Installation section")
    notes = f"## {title}\n\n{body}\n\n### Installation\n\n{installation}\n"

    def tagged_link(match):
        target = urlsplit(match[1])
        if target.scheme or target.netloc or target.path.startswith("/"):
            return match[0]
        path = posixpath.normpath("docs/" + target.path)
        if path == ".." or path.startswith("../") or target.query:
            raise ReleaseError("A release note has an invalid relative documentation link.")
        fragment = "#" + quote(target.fragment, safe="-_.") if target.fragment else ""
        return "](" + f"https://github.com/{REPOSITORY}/blob/{tag}/" + quote(path, safe="/") + fragment + ")"
    return re.sub(r"\]\(([^()\s]+\.md(?:#[^()\s]*)?)\)", tagged_link, notes)


def verify_source_archive(root: Path, archive_path: Path) -> None:
    expected = {}
    for item in git(root, "ls-tree", "-rz", "--full-tree", "HEAD").split(b"\0"):
        if not item:
            continue
        metadata, filename = item.split(b"\t", 1)
        mode, kind, blob = metadata.decode("ascii").split()
        if kind != "blob" or mode not in {"100644", "100755"}:
            raise ReleaseError("The tagged source contains an unsupported file type.")
        expected["Lemulip/" + filename.decode("utf-8")] = (mode, blob)
    with zipfile.ZipFile(archive_path) as archive:
        entries = archive.infolist()
        if len(entries) != len(expected) or {entry.filename for entry in entries} != set(expected):
            raise ReleaseError("The source archive does not contain the exact tagged file list.")
        if sum(entry.file_size for entry in entries) > 256 * 1024 * 1024:
            raise ReleaseError("The source archive is unexpectedly large.")
        for entry in entries:
            mode, expected_blob = expected[entry.filename]
            unix_mode = entry.external_attr >> 16
            if (not stat.S_ISREG(unix_mode) or bool(unix_mode & 0o111) != (mode == "100755")
                    or not 0 <= entry.file_size <= 8 * 1024 * 1024):
                raise ReleaseError("The source archive contains an unexpected file type, mode, or size.")
            data = archive.read(entry)
            # Git uses SHA-1 object identities; the downloadable archive itself
            # is authenticated with SHA-256 in the artifact manifest.
            blob = hashlib.sha1(b"blob " + str(len(data)).encode("ascii") + b"\0" + data, usedforsecurity=False).hexdigest()
            if blob != expected_blob:
                raise ReleaseError("The source archive differs from the exact tagged commit.")


def local_context(environment: dict[str, str], root: Path = ROOT, directory: Path | None = None) -> Context:
    tag = environment.get("RELEASE_TAG", "")
    version = environment.get("RELEASE_VERSION", "")
    head = environment.get("GITHUB_SHA", "")
    if (environment.get("GITHUB_ACTIONS") != "true" or environment.get("GITHUB_SERVER_URL") != "https://github.com"
            or environment.get("GITHUB_API_URL") != "https://api.github.com"
            or environment.get("RELEASE_REPO") != REPOSITORY or environment.get("GITHUB_REPOSITORY") != REPOSITORY
            or environment.get("GITHUB_REPOSITORY_ID") != str(REPOSITORY_ID)
            or environment.get("GITHUB_REF") != "refs/tags/" + tag
            or environment.get("GITHUB_REF_TYPE") != "tag"
            or environment.get("GITHUB_EVENT_NAME") not in {"push", "workflow_dispatch"}
            or not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", tag) or tag != "v" + version
            or not re.fullmatch(r"[0-9a-f]{40}", head)):
        raise ReleaseError("Publication requires the matching tagged GitHub Actions run in the Lemulip repository.")
    run_id = environment.get("GITHUB_RUN_ID", "")
    attempt = environment.get("GITHUB_RUN_ATTEMPT", "")
    if not re.fullmatch(r"[1-9][0-9]*", run_id) or not re.fullmatch(r"[1-9][0-9]*", attempt):
        raise ReleaseError("The release workflow run or attempt is invalid.")
    if git(root, "rev-parse", "HEAD").decode("ascii").strip() != head:
        raise ReleaseError("The checked-out commit does not match the tagged workflow commit.")
    if git(root, "diff", "--name-only", "HEAD", "--"):
        raise ReleaseError("The checked-out source changed after verification.")
    plist_bytes = small_file(root / "Resources/Info.plist", 65536)
    if plistlib.loads(plist_bytes).get("CFBundleShortVersionString") != version:
        raise ReleaseError("The release tag and application version differ.")

    directory = directory if directory is not None else root / "dist"
    package = f"Lemulip-{version}-macOS-universal"
    source = f"Lemulip-{version}-Source.zip"
    archives = {package + ".zip", package + ".dmg", source}
    expected = archives | {"SHA256SUMS.txt", "RELEASE_NOTES.md"}
    if (directory.is_symlink() or not directory.is_dir()
            or {path.name for path in directory.iterdir()} != expected
            or any(path.is_symlink() or not path.is_file() for path in directory.iterdir())):
        raise ReleaseError("The downloaded artifact must contain exactly the three archives, checksums, and release notes.")
    checksums = small_file(directory / "SHA256SUMS.txt", 4096)
    manifest = {}
    for line in checksums.decode("ascii").splitlines():
        match = re.fullmatch(r"([0-9a-f]{64})  ([A-Za-z0-9.-]+)", line)
        if not match or match[2] not in archives or match[2] in manifest:
            raise ReleaseError("The checksum manifest has an unexpected, duplicate, or malformed entry.")
        manifest[match[2]] = match[1]
    if set(manifest) != archives:
        raise ReleaseError("The checksum manifest is incomplete.")
    assets = {}
    for name in sorted(archives | {"SHA256SUMS.txt"}):
        path = directory / name
        size, digest = file_digest(path)
        if name in manifest and manifest[name] != digest:
            raise ReleaseError(f"Checksum mismatch for {name}.")
        content_type = "application/zip" if name.endswith(".zip") else "application/x-apple-diskimage" if name.endswith(".dmg") else "text/plain"
        assets[name] = Asset(path, size, digest, content_type)
    notes = small_file(directory / "RELEASE_NOTES.md", 125_000)
    if notes != small_file(root / "docs/RELEASE_NOTES.md", 125_000):
        raise ReleaseError("The release notes do not match the tagged source.")
    verify_source_archive(root, directory / source)
    with zipfile.ZipFile(directory / (package + ".zip")) as archive:
        name = package + "/Lemulip.app/Contents/Info.plist"
        if archive.namelist().count(name) != 1 or archive.getinfo(name).file_size > 65536 or archive.read(name) != plist_bytes:
            raise ReleaseError("The application archive has a different version or bundle configuration.")
    return Context(tag, version, head, int(run_id), int(attempt), public_notes(notes.decode("utf-8"), tag), assets)


def verify_repository_and_tag(client: GitHub, context: Context) -> None:
    repo = client.api(f"/repos/{REPOSITORY}")
    if (repo.get("id") != REPOSITORY_ID or repo.get("full_name") != REPOSITORY
            or repo.get("owner", {}).get("id") != OWNER_ID or repo.get("private") is not False
            or repo.get("archived") is not False):
        raise ReleaseError("The repository identity or public status changed.")
    reference = client.api(f"/repos/{REPOSITORY}/git/ref/tags/{context.tag}")
    obj = reference.get("object", {})
    if reference.get("ref") != "refs/tags/" + context.tag or obj.get("type") != "tag" or not re.fullmatch(r"[0-9a-f]{40}", obj.get("sha", "")):
        raise ReleaseError("The release requires the expected annotated tag.")
    tag = client.api(f"/repos/{REPOSITORY}/git/tags/{obj['sha']}")
    if (tag.get("sha") != obj["sha"] or tag.get("tag") != context.tag
            or tag.get("object", {}).get("type") != "commit" or tag.get("object", {}).get("sha") != context.head
            or tag.get("message") != context.annotation or tag.get("tagger", {}).get("name") != TAGGER_NAME
            or tag.get("tagger", {}).get("email") != TAGGER_EMAIL):
        raise ReleaseError("The existing release tag differs from the reviewed commit or public tagger contract.")


def verify_workflow(client: GitHub, context: Context) -> None:
    run = client.api(f"/repos/{REPOSITORY}/actions/runs/{context.run_id}")
    if (run.get("head_sha") != context.head or run.get("run_attempt") != context.run_attempt
            or run.get("path") != ".github/workflows/build.yml" or run.get("event") not in {"push", "workflow_dispatch"}
            or run.get("repository", {}).get("id") != REPOSITORY_ID
            or run.get("status") != "in_progress"):
        raise ReleaseError("The release workflow does not match the active tagged build attempt.")
    if context.run_attempt > 20:
        raise ReleaseError("The workflow exceeds this publisher's attempt review limit.")
    unresolved = set(REQUIRED_JOBS)
    # Rerunning only a failed release job reuses successful prerequisites from
    # the same run. Walk attempts newest first; a later failure or skipped job
    # must never be replaced by an older success. Explicit attempt endpoints
    # avoid depending on an optional run_attempt field in individual jobs.
    for attempt in range(context.run_attempt, 0, -1):
        response = client.api(f"/repos/{REPOSITORY}/actions/runs/{context.run_id}/attempts/{attempt}/jobs?per_page=100")
        jobs = response.get("jobs", [])
        if not isinstance(jobs, list) or response.get("total_count") != len(jobs) or len(jobs) > 100:
            raise ReleaseError("The build job inventory is incomplete.")
        for name in tuple(unresolved):
            matches = [job for job in jobs if job.get("name") == name]
            if not matches:
                continue
            if (len(matches) != 1 or matches[0].get("head_sha") != context.head
                    or matches[0].get("run_id") != context.run_id
                    or ("run_attempt" in matches[0] and matches[0]["run_attempt"] != attempt)
                    or (matches[0].get("head_branch") is not None and matches[0]["head_branch"] != run.get("head_branch"))
                    or matches[0].get("status") != "completed" or matches[0].get("conclusion") != "success"):
                raise ReleaseError(f"The latest execution of a required job has not passed: {name}.")
            unresolved.remove(name)
        if not unresolved:
            return
    raise ReleaseError("The workflow has missing prerequisite jobs.")


def find_release(client: GitHub, context: Context):
    matches = []
    # Listing includes drafts visible to this repository token. The public
    # release-by-tag endpoint alone cannot reliably find an interrupted draft.
    for page in range(1, 11):
        releases = client.api(f"/repos/{REPOSITORY}/releases?per_page=100&page={page}")
        if not isinstance(releases, list):
            raise ReleaseError("GitHub returned an invalid release inventory.")
        matches.extend(release for release in releases if release.get("tag_name") == context.tag)
        if len(releases) < 100:
            if len(matches) > 1:
                raise ReleaseError("Multiple releases use this tag; all have been preserved.")
            return matches[0] if matches else None
    raise ReleaseError("The release inventory exceeds this publisher's review limit.")


def validate_release(release: dict, context: Context) -> int:
    release_id = release.get("id")
    if (type(release_id) is not int or release_id <= 0 or release.get("tag_name") != context.tag
            or release.get("target_commitish") != context.head or release.get("name") != context.title
            or release.get("body") != context.body or release.get("prerelease") is not True
            or type(release.get("draft")) is not bool):
        raise ReleaseError("An existing release differs from the expected preview metadata; it has been preserved.")
    return release_id


def release_assets(client: GitHub, release_id: int, context: Context) -> dict[str, dict]:
    assets = client.api(f"/repos/{REPOSITORY}/releases/{release_id}/assets?per_page=100")
    if not isinstance(assets, list) or len(assets) > len(context.assets):
        raise ReleaseError("The release contains unexpected assets; none were changed.")
    by_name = {}
    for asset in assets:
        name = asset.get("name")
        if name not in context.assets or name in by_name:
            raise ReleaseError("The release contains an unexpected or duplicate asset; none were changed.")
        by_name[name] = asset
    return by_name


def verify_asset(client: GitHub, remote: dict, name: str, expected: Asset, *, draft: bool) -> None:
    if remote.get("state") == "starter" and remote.get("size") == 0:
        if draft:
            raise ReleaseError(f"GitHub left an empty interrupted upload for {name}. Retrying cannot replace it. Review and remove only that zero-byte asset from the matching draft, then rerun this workflow's failed jobs. Nothing was deleted automatically.")
        raise ReleaseError("The published release contains an empty unfinished upload and requires review. Nothing was changed.")
    if (remote.get("name") != name or remote.get("size") != expected.size or remote.get("state") != "uploaded"
            or type(remote.get("id")) is not int or remote["id"] <= 0):
        raise ReleaseError(f"The existing {name} asset is incomplete or differs in size; it has been preserved.")
    digest = remote.get("digest")
    if digest:
        if not isinstance(digest, str) or not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
            raise ReleaseError(f"GitHub returned an invalid SHA-256 digest for {name}.")
        actual = digest.removeprefix("sha256:")
    else:
        actual = client.download_digest(remote["id"], expected.size)
    if actual != expected.sha256:
        raise ReleaseError(f"The existing {name} asset has different bytes; it has been preserved.")


def publish(client: GitHub, context: Context) -> None:
    verify_repository_and_tag(client, context)
    verify_workflow(client, context)
    release = find_release(client, context)
    if release is None:
        payload = {"tag_name": context.tag, "target_commitish": context.head, "name": context.title,
                   "body": context.body, "draft": True, "prerelease": True, "make_latest": "false",
                   "generate_release_notes": False}
        try:
            release = client.api(f"/repos/{REPOSITORY}/releases", method="POST", payload=payload)
        except APIError as error:
            # A concurrent creator may have won; accept only the exact same
            # draft contract. Other HTTP failures remain visible for a retry.
            if error.status != 422:
                raise
            release = find_release(client, context)
            if release is None:
                raise
    release_id = validate_release(release, context)
    existing = release_assets(client, release_id, context)
    for name, remote in existing.items():
        verify_asset(client, remote, name, context.assets[name], draft=release["draft"])
    if release["draft"] is False:
        if set(existing) != set(context.assets):
            raise ReleaseError("The published release is incomplete. It was preserved and requires review.")
        print(f"Verified the existing complete release: https://github.com/{REPOSITORY}/releases/tag/{context.tag}")
        return

    for name, asset in context.assets.items():
        if name in existing:
            continue
        # Recheck local bytes immediately before upload, without loading the
        # archives into memory or permitting an overwrite of a remote asset.
        if file_digest(asset.path) != (asset.size, asset.sha256):
            raise ReleaseError("A local artifact changed before upload.")
        try:
            remote = client.upload(release_id, name, asset)
        except APIError as error:
            if error.status != 422:
                raise
            remote = release_assets(client, release_id, context).get(name)
            if remote is None:
                raise
        verify_asset(client, remote, name, asset, draft=True)
        print(f"Verified upload: {name}")

    # Check the complete server-side set and the tag again before making the
    # draft public. Never publish a partially uploaded collection of files.
    release = client.api(f"/repos/{REPOSITORY}/releases/{release_id}")
    validate_release(release, context)
    existing = release_assets(client, release_id, context)
    if set(existing) != set(context.assets):
        raise ReleaseError("The draft is incomplete and remains unpublished.")
    for name, remote in existing.items():
        verify_asset(client, remote, name, context.assets[name], draft=release["draft"])
    verify_repository_and_tag(client, context)
    if release["draft"]:
        release = client.api(f"/repos/{REPOSITORY}/releases/{release_id}", method="PATCH",
                             payload={"draft": False, "make_latest": "false"})
        validate_release(release, context)
    if release["draft"] is not False:
        raise ReleaseError("GitHub has not confirmed publication; the existing release is preserved.")
    print(f"Published all four verified downloads: https://github.com/{REPOSITORY}/releases/tag/{context.tag}")


def main() -> int:
    context = local_context(dict(os.environ))
    print("Verified artifact filenames, checksums, source bytes, version, and workflow context.")
    client = GitHub(os.environ.get("GH_TOKEN", ""))
    publish(client, context)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ReleaseError as error:
        print("Release publication stopped: " + str(error), file=sys.stderr)
        raise SystemExit(1)
    except (OSError, URLError, ValueError, KeyError, TypeError, AttributeError, zipfile.BadZipFile, subprocess.CalledProcessError, http.client.HTTPException):
        # API response bodies and transport exceptions can contain signed URLs
        # or other private data. Keep them out of public workflow logs.
        print("Release publication stopped during a file, API, or transport check. Existing releases and assets were preserved; retry the same workflow after resolving the failure.", file=sys.stderr)
        raise SystemExit(1)
