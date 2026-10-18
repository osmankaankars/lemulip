#!/usr/bin/env python3
"""Create a reviewed preview tag, then dispatch the existing macOS pipeline.

The Preview Release workflow checks the complete prerequisites before checkout.
This coordinator repeats them immediately before writes. It never edits source,
overwrites a tag, changes a release, or automatically reruns a failed tag build.
"""

import datetime
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


REPOSITORY = "osmankaankars/lemulip"
REPOSITORY_ID = 1424213526
OWNER = "osmankaankars"
OWNER_ID = 56635935
REPO_URL = "https://github.com/" + REPOSITORY
PUBLIC_NAME = "Kaan Kars"
PUBLIC_EMAIL = "56635935+osmankaankars@users.noreply.github.com"
ACTIVE = {"queued", "in_progress", "requested", "waiting", "pending"}
BUILD_JOBS = ("macOS Tests (arm64)", "macOS Tests (x86_64)",
              "Universal macOS Package", "Verify Release Download (arm64)",
              "Verify Release Download (x86_64)")
CODEQL_JOBS = ("Scan Swift and the C Archive Bridge",)
MAX_RESPONSE = 4 * 1024 * 1024
MAX_ATTEMPTS = 20


class PreviewError(Exception):
    """A safe, actionable message without raw API responses or credentials."""


def require(condition, message):
    if not condition:
        raise PreviewError(message)


def positive_integer(value):
    return type(value) is int and value > 0


def tag_message(tag, sha):
    return ("Lemulip " + tag + "\n\nSource: " + REPO_URL + "/commit/" + sha + "\n"
            "Verified on main: Build and Verify, both release download checks, and CodeQL.\n")


class GitHub:
    def __init__(self, token):
        require(bool(token), "The workflow's GitHub token is unavailable.")
        self.token = token

    def request(self, method, endpoint, payload=None, missing_ok=False):
        require(method in {"GET", "POST"} and endpoint.startswith("repos/" + REPOSITORY + "/")
                or method == "GET" and endpoint == "repos/" + REPOSITORY,
                "An unexpected GitHub API operation was blocked.")
        data = json.dumps(payload, separators=(",", ":")).encode() if payload is not None else None
        request = Request("https://api.github.com/" + endpoint, data=data, method=method,
                          headers={"Authorization": "Bearer " + self.token,
                                   "Accept": "application/vnd.github+json",
                                   "Content-Type": "application/json",
                                   "X-GitHub-Api-Version": "2026-03-10",
                                   "User-Agent": "Lemulip-Preview-Release"})
        try:
            with urlopen(request, timeout=30) as response:
                body = response.read(MAX_RESPONSE + 1)
        except HTTPError as error:
            if method == "GET" and missing_ok and error.code == 404:
                return None
            raise PreviewError("GitHub could not confirm an API request (HTTP " + str(error.code)
                               + "). Review this run before resuming Preview Release.") from None
        except (URLError, TimeoutError, OSError):
            raise PreviewError("GitHub could not confirm an API request. Existing changes were preserved; "
                               "resume Preview Release after checking connectivity.") from None
        require(len(body) <= MAX_RESPONSE, "A GitHub response exceeded the verification size limit.")
        if not body:
            return None
        value = json.loads(body)
        require(isinstance(value, dict), "A GitHub response had an unexpected shape.")
        return value


class PreviewPublisher:
    def __init__(self, api, sha, version):
        require(bool(re.fullmatch(r"[0-9a-f]{40}", sha)), "The reviewed source commit is invalid.")
        require(bool(re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version)), "The app version is invalid.")
        self.api = api
        self.sha = sha
        self.tag = "v" + version
        self.prefix = "repos/" + REPOSITORY

    def repository_and_main(self):
        repo = self.api.request("GET", self.prefix)
        owner = repo.get("owner", {})
        require(repo.get("id") == REPOSITORY_ID and repo.get("full_name") == REPOSITORY
                and repo.get("private") is False and repo.get("archived") is False
                and repo.get("default_branch") == "main" and owner.get("id") == OWNER_ID
                and owner.get("login") == OWNER, "The public repository identity does not match.")
        branch = self.api.request("GET", self.prefix + "/git/ref/heads/main")
        target = branch.get("object", {})
        require(branch.get("ref") == "refs/heads/main" and target.get("type") == "commit"
                and target.get("sha") == self.sha,
                "Main changed after source verification. No further release action was taken.")

    def latest_run(self, filename, branch):
        query = urlencode({"head_sha": self.sha, "branch": branch,
                           "exclude_pull_requests": "true", "per_page": 100})
        result = self.api.request("GET", self.prefix + "/actions/workflows/" + filename + "/runs?" + query)
        items, count = result.get("workflow_runs"), result.get("total_count")
        require(isinstance(items, list) and type(count) is int and count == len(items)
                and count <= 100 and all(isinstance(item, dict) for item in items),
                "Workflow results could not be checked completely.")
        matching = [item for item in items
                    if positive_integer(item.get("id")) and positive_integer(item.get("run_number"))
                    and positive_integer(item.get("run_attempt")) and item.get("head_sha") == self.sha
                    and item.get("head_branch") == branch and item.get("event") in {"push", "workflow_dispatch"}
                    and str(item.get("path", "")).split("@", 1)[0] == ".github/workflows/" + filename
                    and isinstance(item.get("repository"), dict) and item["repository"].get("id") == REPOSITORY_ID
                    and isinstance(item.get("head_repository"), dict) and item["head_repository"].get("id") == REPOSITORY_ID]
        return max(matching, key=lambda item: (item["run_number"], item["run_attempt"])) if matching else None

    def successful_jobs(self, run, expected, branch):
        require(run is not None and run.get("status") == "completed" and run.get("conclusion") == "success",
                "A required workflow has not passed for the reviewed commit.")
        require(positive_integer(run.get("id")) and positive_integer(run.get("run_attempt")),
                "The required workflow attempt is invalid.")
        require(run["run_attempt"] <= MAX_ATTEMPTS, "The workflow exceeds the bounded attempt review limit.")
        remaining = set(expected)
        latest = run["run_attempt"]
        # A failed-job rerun retains earlier successful jobs in the same run.
        # The newest execution of each name wins, even when it failed or skipped.
        for attempt in range(latest, max(0, latest - MAX_ATTEMPTS), -1):
            endpoint = (self.prefix + "/actions/runs/" + str(run["id"]) + "/attempts/"
                        + str(attempt) + "/jobs?per_page=100")
            result = self.api.request("GET", endpoint)
            jobs, count = result.get("jobs"), result.get("total_count")
            require(isinstance(jobs, list) and type(count) is int and count == len(jobs) and count <= 100
                    and all(isinstance(job, dict) for job in jobs), "Required job results could not be checked completely.")
            for name in expected:
                if name not in remaining:
                    continue
                found = [job for job in jobs if job.get("name") == name]
                require(len(found) <= 1, "A required job is duplicated in one attempt: " + name)
                if not found:
                    continue
                job = found[0]
                require(job.get("run_id") == run["id"] and job.get("head_sha") == self.sha
                        and (job.get("head_branch") is None or job["head_branch"] == branch)
                        and job.get("run_attempt", attempt) == attempt
                        and job.get("status") == "completed" and job.get("conclusion") == "success",
                        "The latest execution of a required job has not passed for this commit: " + name)
                remaining.remove(name)
            if not remaining:
                return
        raise PreviewError("Required jobs are missing from the bounded run history: " + ", ".join(sorted(remaining)))

    def prerequisites(self):
        self.repository_and_main()
        build = self.latest_run("build.yml", "main")
        codeql = self.latest_run("codeql.yml", "main")
        self.successful_jobs(build, BUILD_JOBS, "main")
        self.successful_jobs(codeql, CODEQL_JOBS, "main")
        return build, codeql

    def recheck_prerequisites(self, original):
        current = self.prerequisites()
        require(all((before["id"], before["run_attempt"]) == (after["id"], after["run_attempt"])
                    for before, after in zip(original, current)),
                "Required CI changed during verification. Resume after the latest runs finish.")

    def existing_tag(self):
        reference = self.api.request("GET", self.prefix + "/git/ref/tags/" + self.tag, missing_ok=True)
        if reference is None:
            return None
        obj = reference.get("object", {})
        require(reference.get("ref") == "refs/tags/" + self.tag and obj.get("type") == "tag"
                and bool(re.fullmatch(r"[0-9a-f]{40}", str(obj.get("sha", "")))),
                "The existing version tag is not the expected annotated tag. It was preserved.")
        tag = self.api.request("GET", self.prefix + "/git/tags/" + obj["sha"])
        target, tagger = tag.get("object", {}), tag.get("tagger", {})
        require(tag.get("sha") == obj["sha"] and tag.get("tag") == self.tag
                and target.get("type") == "commit" and target.get("sha") == self.sha
                and tagger.get("name") == PUBLIC_NAME and tagger.get("email") == PUBLIC_EMAIL
                and tag.get("message") == tag_message(self.tag, self.sha),
                "The existing version tag has a different target, tagger, or annotation. It was preserved.")
        return obj["sha"]

    def release_without_tag(self):
        require(self.api.request("GET", self.prefix + "/releases/tags/" + self.tag, missing_ok=True) is None,
                "A release already uses this version without the expected tag. It was preserved for review.")

    def run(self):
        checks = self.prerequisites()
        existing = self.existing_tag()
        if existing is None:
            self.release_without_tag()
            self.recheck_prerequisites(checks)
            # A simultaneous matching publisher may have completed this stage.
            existing = self.existing_tag()
            if existing is None:
                self.release_without_tag()
                tag = self.api.request("POST", self.prefix + "/git/tags", {
                    "tag": self.tag, "message": tag_message(self.tag, self.sha),
                    "object": self.sha, "type": "commit",
                    "tagger": {"name": PUBLIC_NAME, "email": PUBLIC_EMAIL,
                               "date": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")}})
                require(isinstance(tag, dict) and bool(re.fullmatch(r"[0-9a-f]{40}", str(tag.get("sha", "")))),
                        "The new annotated tag object could not be confirmed.")
                self.recheck_prerequisites(checks)
                self.api.request("POST", self.prefix + "/git/refs", {"ref": "refs/tags/" + self.tag, "sha": tag["sha"]})
                require(self.existing_tag() == tag["sha"], "The new tag reference could not be confirmed. Resume Preview Release to check it.")
                print("Created " + self.tag + " for the verified source commit.", flush=True)
        else:
            print("The matching annotated " + self.tag + " tag is already present and was preserved.", flush=True)

        tagged = self.latest_run("build.yml", self.tag)
        if tagged is not None:
            link = REPO_URL + "/actions/runs/" + str(tagged["id"])
            if tagged.get("status") in ACTIVE:
                print("Tagged Build and Verify is already pending; no duplicate dispatch was sent.\n" + link, flush=True)
                return
            if tagged.get("status") == "completed" and tagged.get("conclusion") == "success":
                self.successful_jobs(tagged, BUILD_JOBS + ("Publish Tagged Release",), self.tag)
                print("Tagged Build and Verify already passed. Release contents were left unchanged.\n" + link, flush=True)
                print(REPO_URL + "/releases/tag/" + self.tag, flush=True)
                return
            raise PreviewError("The tagged build needs review and was not rerun automatically. " + link)

        self.recheck_prerequisites(checks)
        require(self.existing_tag() is not None, "The reviewed tag disappeared before dispatch.")
        # GITHUB_TOKEN-created tags do not trigger push workflows. Dispatch is
        # explicit, and only sent when this exact tag has no matching run.
        require(self.latest_run("build.yml", self.tag) is None,
                "A tagged workflow appeared during verification. Resume to inspect the existing run.")
        self.api.request("POST", self.prefix + "/actions/workflows/build.yml/dispatches", {"ref": self.tag})
        print("Dispatched Build and Verify at " + self.tag + ". Its jobs will build and verify the downloads before publishing.", flush=True)
        print(REPO_URL + "/actions/workflows/build.yml", flush=True)


def reviewed_version(root, sha):
    env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
    env.update(GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1", GIT_NO_REPLACE_OBJECTS="1")
    result = subprocess.run(["git", "-c", "core.hooksPath=" + os.devnull, "rev-parse", "HEAD"],
                            cwd=root, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
    require(result.returncode == 0 and result.stdout.decode().strip() == sha,
            "The checked-out source does not match the reviewed commit.")
    path = root / "Resources/Info.plist"
    require(path.is_file() and not path.is_symlink() and path.stat().st_size <= 65_536,
            "The reviewed app version file is invalid.")
    info = plistlib.loads(path.read_bytes())
    version = info.get("CFBundleShortVersionString")
    require(isinstance(version, str), "The reviewed app version is missing.")
    return version


def main():
    require(os.environ.get("GITHUB_ACTIONS") == "true"
            and os.environ.get("GITHUB_REPOSITORY") == REPOSITORY
            and os.environ.get("GITHUB_REPOSITORY_ID") == str(REPOSITORY_ID)
            and os.environ.get("GITHUB_REPOSITORY_OWNER_ID") == str(OWNER_ID),
            "Run this coordinator through the existing repository's Preview Release workflow.")
    sha = os.environ.get("LEMULIP_REVIEWED_SHA", "")
    require(bool(re.fullmatch(r"[0-9a-f]{40}", sha)), "The validated source commit is missing.")
    root = Path(__file__).resolve().parent.parent
    version = reviewed_version(root, sha)
    PreviewPublisher(GitHub(os.environ.get("GH_TOKEN")), sha, version).run()


if __name__ == "__main__":
    try:
        main()
    except PreviewError as error:
        print("Lemulip: " + str(error), file=sys.stderr)
        raise SystemExit(1)
    except (OSError, ValueError, TypeError, KeyError, AttributeError, subprocess.TimeoutExpired):
        print("Lemulip: A required file or API response could not be verified. Existing tags and releases were preserved.", file=sys.stderr)
        raise SystemExit(1)
