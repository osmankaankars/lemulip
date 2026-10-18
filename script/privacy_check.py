#!/usr/bin/env python3
"""Check the exact source files intended for a public repository.

This is a focused guardrail, not a substitute for reviewing a release diff.
It prints only file names and rule names, never matched secret values.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import re
import stat
import subprocess
import struct
import sys
import zlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
DIRECTORIES = {"Sources", "Tests", "Resources", "script", "docs", ".github", "site"}
ROOT_FILES = {"Package.swift", "Package.resolved", "LICENSE", "README.md",
              "THIRD_PARTY_NOTICES.md", "SECURITY.md", "CONTRIBUTING.md", ".gitignore",
              "Build-and-Install.command", "Publish-to-GitHub.command"}
FORBIDDEN_PARTS = {
    "private", "secrets", "credentials", "passwords", "node_modules", "__pycache__", "dist",
    "build", "test-output", "xcuserdata", "deriveddata", "venv", "logs", "backups",
    "id_rsa", "id_dsa", "id_ecdsa", "id_ed25519",
}
FORBIDDEN_SUFFIXES = {
    ".pem", ".key", ".p12", ".pfx", ".crt", ".cer", ".der", ".keystore", ".jks",
    ".mobileprovision", ".provisionprofile", ".gpg", ".asc",
    ".log", ".local", ".bak", ".backup", ".orig", ".swp", ".swo", ".tmp",
    ".dmg", ".app", ".zip", ".tar", ".gz", ".bz2", ".xz", ".7z", ".rar",
    ".db", ".sqlite", ".sqlite3", ".xcuserstate",
}
RULES = {
    "private-key": rb"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----",
    "github-token": rb"\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})\b",
    "aws-access-id": rb"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b",
    "openai-key": rb"\bsk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{24,}\b",
    "slack-token": rb"\bxox[baprs]-[A-Za-z0-9-]{20,}\b",
    "literal-home-path": rb"/(?:Users|home)/[A-Za-z0-9_.-]+/",
    "credential-in-url": rb"https?://[^\s/:]+:[^\s/@]+@",
    "embedded-email": rb"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+\b",
}
ALLOWED_EMAILS = {b"contributors@lemulip.invalid"}

# Only these visually reviewed illustrations may be binary. Generated artwork
# retains its provenance; no image may carry private metadata.
# Update a digest only after reviewing the new image and its metadata.
PUBLIC_IMAGES = {
    "Resources/AppIcon.png": "141333d6fbca0f0e3bc27bc4b3afbff1d2e46e74c15f9e972da87ef263a1478a",
    "docs/assets/demo-preview.png": "9220fe812177c52c901ff30e8ae23c12df210e48189ee4677a0610e3a479c57a",
}
TEXT_SIZE_LIMIT = 2_000_000
IMAGE_SIZE_LIMIT = 8_000_000


def size_limit(name: str) -> int:
    return IMAGE_SIZE_LIMIT if name in PUBLIC_IMAGES else TEXT_SIZE_LIMIT


def image_is_public(name: str, data: bytes) -> bool:
    """Require approved bytes and a PNG without text, EXIF or trailing data."""
    if hashlib.sha256(data).hexdigest() != PUBLIC_IMAGES[name]:
        return False
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        return False
    position = 8
    seen_header = False
    seen_pixels = False
    while position + 12 <= len(data):
        length = struct.unpack_from(">I", data, position)[0]
        kind = data[position + 4:position + 8]
        end = position + 12 + length
        allowed_chunks = {
            b"IHDR", b"PLTE", b"tRNS", b"IDAT", b"IEND", b"sRGB", b"gAMA", b"cHRM",
        }
        if name == "Resources/AppIcon.png":
            allowed_chunks.add(b"caBX")  # Reviewed C2PA origin provenance, covered by the digest.
        if end > len(data) or kind not in allowed_chunks:
            return False
        payload = data[position + 8:end - 4]
        checksum = struct.unpack_from(">I", data, end - 4)[0]
        if zlib.crc32(kind + payload) & 0xffffffff != checksum:
            return False
        if not seen_header:
            if kind != b"IHDR" or length != 13:
                return False
            width, height = struct.unpack_from(">II", payload)
            if not (1 <= width <= 4096 and 1 <= height <= 4096):
                return False
            seen_header = True
        elif kind == b"IHDR":
            return False
        if kind == b"IDAT":
            seen_pixels = True
        if kind == b"IEND":
            return length == 0 and seen_pixels and end == len(data)
        position = end
    return False


def content_failures(name: str, data: bytes) -> list[str]:
    if len(data) > size_limit(name):
        return ["unexpected-large-file"]
    if name in PUBLIC_IMAGES:
        return [] if image_is_public(name, data) else ["unreviewed-or-invalid-public-image"]
    failures = []
    try:
        data.decode("utf-8")
    except UnicodeDecodeError:
        failures.append("non-utf8-source-file")
    if b"\x00" in data:
        failures.append("unexpected-binary-file")
    for rule, pattern in RULES.items():
        matches = re.findall(pattern, data)
        if rule == "embedded-email":
            matches = [match for match in matches if match not in ALLOWED_EMAILS]
        if matches:
            failures.append(rule)
    return failures

def allowed(path: pathlib.PurePosixPath) -> bool:
    name = path.as_posix()
    if path.is_absolute() or "\\" in name or any(ord(c) < 32 or ord(c) == 127 for c in name):
        return False
    if len(path.parts) == 1:
        return path.name in ROOT_FILES
    if not path.parts or path.parts[0] not in DIRECTORIES:
        return False
    for index, part in enumerate(path.parts):
        lower = part.casefold()
        # Only the public .github root may be hidden. This also excludes .env.*,
        # .secrets, .codex, .git, .swiftpm, editor state, and nested copies of them.
        if (part.startswith(".") and not (index == 0 and part == ".github")):
            return False
        if lower in FORBIDDEN_PARTS or lower.startswith(
            ("credentials.", "secrets.", "passwords.", "id_rsa.", "id_dsa.", "id_ecdsa.", "id_ed25519.")
        ):
            return False
        if lower.endswith("~") or pathlib.PurePosixPath(lower).suffix in FORBIDDEN_SUFFIXES:
            return False
    return True

def git(*args: str) -> bytes:
    # Never follow an inherited GIT_DIR/GIT_INDEX_FILE or read a user's global
    # Git configuration while checking this project's index.
    environment = {
        "PATH": os.defpath,
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": os.devnull,
        "GIT_OPTIONAL_LOCKS": "0",
        "GIT_TERMINAL_PROMPT": "0",
        "GIT_NO_REPLACE_OBJECTS": "1",
    }
    return subprocess.check_output(
        ["git", "--literal-pathspecs", "-c", "core.hooksPath=" + os.devnull,
         "-c", "core.fsmonitor=false", *args],
        cwd=ROOT, env=environment, stdin=subprocess.DEVNULL, stderr=subprocess.PIPE,
    )

def working_names() -> list[str]:
    names = [name for name in ROOT_FILES if (ROOT / name).exists() or (ROOT / name).is_symlink()]
    for directory in sorted(DIRECTORIES):
        parent = ROOT / directory
        if parent.is_symlink():
            names.append(directory)  # Report it without following its target.
            continue
        if not parent.is_dir():
            continue
        for current, directories, files in os.walk(parent, followlinks=False):
            keep = []
            for name in sorted(directories):
                child = pathlib.Path(current) / name
                relative = child.relative_to(ROOT).as_posix()
                if not allowed(pathlib.PurePosixPath(relative)):
                    continue
                if child.is_symlink():
                    names.append(relative)
                else:
                    keep.append(name)
            directories[:] = keep
            for name in files:
                relative = (pathlib.Path(current) / name).relative_to(ROOT).as_posix()
                if allowed(pathlib.PurePosixPath(relative)):
                    names.append(relative)
    return sorted(names)

def safe_label(name: str) -> str:
    encoded = name.encode("utf-8", errors="replace")
    if any(re.search(pattern, encoded) for pattern in RULES.values()):
        return "<redacted filename>"
    return json.dumps(name, ensure_ascii=True)

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--staged", action="store_true", help="Check the index, not working files")
    parser.add_argument("--list-files", action="store_true",
                        help="Print the validated public file list as JSON for source archives")
    options = parser.parse_args()
    try:
        if options.staged:
            names = sorted({name.decode("utf-8") for name in git("ls-files", "-z").split(b"\0") if name})
        else:
            names = working_names()
    except (OSError, UnicodeError, subprocess.CalledProcessError):
        print("FAIL: Could not enumerate this project's public source files.", file=sys.stderr)
        return 1
    failures: list[tuple[str, str]] = []
    for name in names:
        relative = pathlib.PurePosixPath(name)
        if not allowed(relative):
            failures.append((name, "outside-public-allowlist")); continue
        if any(re.search(pattern, name.encode("utf-8")) for pattern in RULES.values()):
            failures.append((name, "sensitive-filename")); continue
        path = ROOT / name
        try:
            if options.staged:
                entry = git("ls-files", "--stage", "-z", "--", name)
                mode = entry.split(b" ", 1)[0]
                if mode == b"120000": failures.append((name, "symbolic-link")); continue
                if mode not in {b"100644", b"100755"}:
                    failures.append((name, "non-regular-file")); continue
                if int(git("cat-file", "-s", ":" + name)) > size_limit(name):
                    failures.append((name, "unexpected-large-file")); continue
                data = git("show", ":" + name)
            else:
                info = path.lstat()
                if stat.S_ISLNK(info.st_mode): failures.append((name, "symbolic-link")); continue
                if not stat.S_ISREG(info.st_mode): failures.append((name, "non-regular-file")); continue
                if any((ROOT / pathlib.Path(*relative.parts[:i])).is_symlink()
                       for i in range(1, len(relative.parts))):
                    failures.append((name, "symbolic-link-parent")); continue
                if info.st_size > size_limit(name):
                    failures.append((name, "unexpected-large-file")); continue
                data = path.read_bytes()
        except (OSError, ValueError, subprocess.CalledProcessError):
            failures.append((name, "unreadable-source-file")); continue
        failures.extend((name, rule) for rule in content_failures(name, data))
    if not names:
        print("FAIL: No public source files were found.", file=sys.stderr); return 1
    if failures:
        for name, rule in failures: print(f"FAIL {safe_label(name)}: {rule}", file=sys.stderr)
        return 1
    if options.list_files:
        print(json.dumps(names, ensure_ascii=True))
    else:
        print(f"PASS: {len(names)} public source files checked; no matching secrets, private home paths, or personal emails.")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
