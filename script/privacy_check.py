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
              "Build-and-Install.command"}
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
# The release tagger uses the creator's explicitly approved public GitHub
# noreply address. Personal email addresses remain blocked.
ALLOWED_EMAILS = {
    b"contributors@lemulip.invalid",
    b"56635935+osmankaankars@users.noreply.github.com",
}

# Only these visually reviewed illustrations and screenshots may be binary. Generated artwork
# retains its provenance; no image may carry private metadata.
# Update a digest only after reviewing the new image and its metadata.
PUBLIC_IMAGES = {
    "site/assets/social-preview.png": "afa315675e7c98e711f4d9beb9fd1b72ea093f573cdf4ee264a72af22b5a22c5",
    "site/assets/morning-light.jpg": "e79abf44c036845255ecfd5e62ec378ec142b5b731fcc900759a7c8931ec5652",
    "Resources/AppIcon.png": "f68b17dc79d0e13246fc425218031a3bc35db2d1e27d845ee657f17f423d8a45",
    "site/assets/app-workspace.webp": "573edfebb566202c51d0fe448ee3805e8e7d48a589a7b28677917ce5cb3e1393",
    "site/assets/app-crop-video.webp": "907260940370ef8683bde30182a847a3e99fdcb3824584a981c19f43747e9b35",
    "site/assets/app-trim-audio.webp": "eaa7b154c0e28b4394cf7194495adf5300f9387b265b66658a0b9b3a48cf7a88",
    "site/assets/app-activity.webp": "bd06c66d98f0591abb5aa43d7441e181fbf7f65b3f9893712deecd5a23028f47",
    "site/assets/finder-conversion.webp": "5dbdf9202eb3c1f9d0fea0e9ca0025df30a6193afcc8d85c13d6f0d1c4cafca3",
}
# A single visually reviewed, silent native recording. Any byte change requires
# a new review; this is an exact allowlist, not a general video upload exemption.
PUBLIC_MEDIA = {
    "site/assets/finder-conversion.mp4": "16a9e5286b793c01e7378a3ab18b850f6a87d3f34d63bafae07a84ad9e709275",
}
TEXT_SIZE_LIMIT = 2_000_000
IMAGE_SIZE_LIMIT = 8_000_000


def size_limit(name: str) -> int:
    return IMAGE_SIZE_LIMIT if name in PUBLIC_IMAGES or name in PUBLIC_MEDIA else TEXT_SIZE_LIMIT


def jpeg_without_metadata(data: bytes) -> bool:
    """Accept a baseline JPEG with only JFIF and coding segments, not EXIF/COM."""
    if not data.startswith(b"\xff\xd8") or not data.endswith(b"\xff\xd9"):
        return False
    position = 2
    seen_frame = False
    while position + 4 <= len(data):
        if data[position] != 0xFF:
            return False
        marker = data[position + 1]
        size = int.from_bytes(data[position + 2:position + 4], "big")
        end = position + 2 + size
        if size < 2 or end > len(data) or marker not in {0xE0, 0xDB, 0xC0, 0xC4, 0xDA}:
            return False
        payload = data[position + 4:end]
        if marker == 0xE0 and not payload.startswith(b"JFIF\x00"):
            return False
        if marker == 0xC0:
            if len(payload) < 6:
                return False
            height = int.from_bytes(payload[1:3], "big")
            width = int.from_bytes(payload[3:5], "big")
            if not (1 <= width <= 4096 and 1 <= height <= 4096):
                return False
            seen_frame = True
        if marker == 0xDA:
            # A baseline image has a single entropy stream. Only escaped FF and
            # restart markers are permitted before the final EOI marker.
            scan = end
            while scan < len(data) - 2:
                if data[scan] == 0xFF:
                    if scan + 1 >= len(data) - 2 or data[scan + 1] not in {0x00, *range(0xD0, 0xD8)}:
                        return False
                    scan += 1
                scan += 1
            return seen_frame and scan == len(data) - 2
        position = end
    return False


def webp_without_metadata(data: bytes) -> bool:
    """Accept reviewed static VP8 images, optionally with transparent corners.

    Only VP8 or VP8X/ALPH/VP8 in order is accepted. No profiles, metadata,
    animation, unknown chunks or trailing bytes. Approved hashes are also required.
    Container layout: https://developers.google.com/speed/webp/docs/riff_container
    """
    if len(data) < 30 or data[:4] != b"RIFF" or data[8:12] != b"WEBP":
        return False
    if struct.unpack_from("<I", data, 4)[0] + 8 != len(data):
        return False
    chunks = []
    offset = 12
    while offset < len(data):
        if offset + 8 > len(data) or len(chunks) >= 3:
            return False
        kind = data[offset:offset + 4]
        size = struct.unpack_from("<I", data, offset + 4)[0]
        end = offset + 8 + size
        padded = end + (size & 1)
        if padded > len(data) or (size & 1 and data[end] != 0):
            return False
        chunks.append((kind, data[offset + 8:end]))
        offset = padded
    kinds = [kind for kind, _ in chunks]
    canvas = None
    if kinds == [b"VP8X", b"ALPH", b"VP8 "]:
        header, alpha = chunks[0][1], chunks[1][1]
        if len(header) != 10 or header[:4] != b"\x10\x00\x00\x00":
            return False
        canvas = (1 + int.from_bytes(header[4:7], "little"),
                  1 + int.from_bytes(header[7:10], "little"))
        if len(alpha) < 2 or alpha[0] & 0xc0 or (alpha[0] & 3) > 1 or ((alpha[0] >> 4) & 3) > 1:
            return False
    elif kinds != [b"VP8 "]:
        return False
    pixels = chunks[-1][1]
    if len(pixels) < 10 or pixels[0] & 1 or pixels[3:6] != b"\x9d\x01\x2a":
        return False
    width, height = struct.unpack_from("<HH", pixels, 6)
    width, height = width & 0x3fff, height & 0x3fff
    return (1 <= width <= 4096 and 1 <= height <= 4096
            and (canvas is None or canvas == (width, height)))


def image_is_public(name: str, data: bytes) -> bool:
    """Require approved bytes and a metadata-free reviewed image."""
    if hashlib.sha256(data).hexdigest() != PUBLIC_IMAGES[name]:
        return False
    if name.endswith(".webp"):
        return webp_without_metadata(data)
    if name.endswith(".jpg"):
        return jpeg_without_metadata(data)
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
    if name in PUBLIC_MEDIA:
        reviewed = (len(data) >= 24 and data[4:8] == b"ftyp"
                    and hashlib.sha256(data).hexdigest() == PUBLIC_MEDIA[name])
        return [] if reviewed else ["unreviewed-or-invalid-public-media"]
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
