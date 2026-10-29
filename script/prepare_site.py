#!/usr/bin/env python3
"""Prepare the exact static Pages directory and its reviewed sharing metadata."""
from __future__ import annotations

import argparse
import hashlib
import html
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import shutil
import struct
from urllib.parse import urlsplit

from privacy_check import PUBLIC_IMAGES, image_is_public

ROOT = Path(__file__).resolve().parent.parent
SHARE_FILE = "social-preview.png"
SHARE_PATH = "site/assets/" + SHARE_FILE
SHARE_SIZE = (1200, 630)
SHARE_ALT = ("Lemulip Workspace with selected files and tools, beside the words "
             "File tools, right where you drag.")
GENERATED_KEYS = {"canonical", "og:url", "og:image", "og:image:type", "og:image:width",
                  "og:image:height", "og:image:alt", "twitter:card", "twitter:image",
                  "twitter:image:alt", "twitter:title", "twitter:description"}


class SiteError(ValueError):
    """A source or deployment setting cannot produce the reviewed public site."""


class HeadTags(HTMLParser):
    def __init__(self):
        super().__init__()
        self.values: dict[str, list[str]] = {}

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        if tag == "meta":
            key = attributes.get("property") or attributes.get("name")
            if key:
                self.values.setdefault(key, []).append(attributes.get("content", ""))
        elif tag == "link" and attributes.get("rel") == "canonical":
            self.values.setdefault("canonical", []).append(attributes.get("href", ""))


def canonical_url(value: str) -> str:
    """Keep the configured project subpath; reject ambiguous or unsafe URLs."""
    try:
        url = urlsplit(value)
        valid = (url.scheme == "https" and url.hostname and not url.username
                 and not url.password and not url.query and not url.fragment
                 and url.port in (None, 443)
                 and re.fullmatch(r"[A-Za-z0-9.-]+(?::443)?", url.netloc)
                 and all(re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?", label)
                         for label in url.hostname.split("."))
                 and re.fullmatch(r"(?:/[A-Za-z0-9._~-]+)*/?", url.path)
                 and all(part not in {".", ".."} for part in url.path.split("/"))
                 and not any(ord(character) <= 32 or ord(character) == 127 for character in value))
    except ValueError:
        valid = False
    if not valid:
        raise SiteError("Pages URL must be an absolute HTTPS site URL without credentials, query or fragment.")
    return value.rstrip("/") + "/"


def reviewed_share(root: Path) -> dict:
    record = json.loads((root / "site/assets/social-preview.json").read_text())
    if (not isinstance(record, dict) or record.get("file") != SHARE_FILE
            or (record.get("width"), record.get("height")) != SHARE_SIZE
            or record.get("alt") != SHARE_ALT
            or not re.fullmatch(r"[0-9a-f]{64}", str(record.get("sha256", "")))):
        raise SiteError("Social preview manifest does not describe the reviewed 1200 by 630 image.")
    data = (root / SHARE_PATH).read_bytes()
    if hashlib.sha256(data).hexdigest() != record["sha256"]:
        raise SiteError("Social preview bytes do not match the manifest digest.")
    if SHARE_PATH not in PUBLIC_IMAGES or not image_is_public(SHARE_PATH, data):
        raise SiteError("Social preview is not the approved metadata-free PNG.")
    if struct.unpack_from(">II", data, 16) != SHARE_SIZE:
        raise SiteError("Social preview PNG dimensions do not match its manifest.")
    return record


def prepare_site(root: Path, destination: Path, repository: str, pages_url: str) -> Path:
    root = root.resolve()
    destination = destination.resolve()
    if (not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+", repository)
            or repository.split("/")[-1] in {".", ".."}):
        raise SiteError("Invalid Pages repository.")
    canonical = canonical_url(pages_url)
    if destination.exists() or destination.is_relative_to(root):
        raise SiteError("The output must be a new directory outside the source tree.")
    source = root / "site"
    icon = root / "Resources/AppIcon.png"
    if source.is_symlink() or icon.is_symlink() or any(path.is_symlink() for path in source.rglob("*")):
        raise SiteError("Site inputs must not contain symbolic links.")
    if not icon.is_file():
        raise SiteError("The app icon is missing.")
    record = reviewed_share(root)
    page = (source / "index.html").read_text()
    tags = HeadTags()
    tags.feed(page)
    if any(tags.values.get(key) for key in GENERATED_KEYS):
        raise SiteError("Source page already contains generated sharing metadata.")
    for key in ("og:title", "og:description"):
        if len(tags.values.get(key, [])) != 1 or not tags.values[key][0].strip():
            raise SiteError("Source page needs exactly one non-empty " + key + ".")
    if page.count('data-repository=""') != 1 or page.count("</head>") != 1:
        raise SiteError("Source page needs one repository placeholder and head closing tag.")
    image = canonical + "assets/" + SHARE_FILE
    metadata = {
        "og:url": canonical,
        "og:image": image,
        "og:image:type": "image/png",
        "og:image:width": str(record["width"]),
        "og:image:height": str(record["height"]),
        "og:image:alt": record["alt"],
        "twitter:card": "summary_large_image",
        "twitter:image": image,
        "twitter:image:alt": record["alt"],
        "twitter:title": tags.values["og:title"][0],
        "twitter:description": tags.values["og:description"][0],
    }
    additions = '  <link rel="canonical" href="' + html.escape(canonical, quote=True) + '">\n'
    for key, value in metadata.items():
        attribute = "property" if key.startswith("og:") else "name"
        additions += f'  <meta {attribute}="{key}" content="{html.escape(value, quote=True)}">\n'
    page = page.replace("../Resources/AppIcon.png", "./app-icon.png")
    page = page.replace('data-repository=""', 'data-repository="https://github.com/' + repository + '"', 1)
    page = page.replace("</head>", additions + "</head>", 1)
    shutil.copytree(source, destination)
    shutil.copyfile(icon, destination / "app-icon.png")
    (destination / "index.html").write_text(page)
    return destination


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--destination", type=Path, required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--pages-url", required=True)
    args = parser.parse_args()
    try:
        prepare_site(ROOT, args.destination, args.repository, args.pages_url)
    except (SiteError, OSError, json.JSONDecodeError) as error:
        parser.exit(1, "Site preparation failed: " + str(error) + "\n")
    print("Prepared static site with its reviewed social preview and complete sharing metadata.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
