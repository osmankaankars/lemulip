#!/usr/bin/env python3
"""Exercise the actual Pages transform and its reviewed share-image contract."""
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import shutil
import struct
import tempfile
import unittest
from unittest.mock import patch
from urllib.parse import urlsplit
import zlib

from prepare_site import (ROOT, GENERATED_KEYS, HeadTags, PUBLIC_IMAGES, SHARE_ALT,
                          SHARE_FILE, SHARE_PATH, SiteError, prepare_site)


class References(HTMLParser):
    def __init__(self):
        super().__init__()
        self.local = []

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        value = attributes.get("src")
        if tag == "link" and attributes.get("rel") == "stylesheet":
            value = attributes.get("href")
        if value and not urlsplit(value).scheme:
            self.local.append(urlsplit(value).path)


def snapshot(folder):
    return {str(path.relative_to(folder)): path.read_bytes()
            for path in folder.rglob("*") if path.is_file()}


class PreparedSiteTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="lemulip-prepared-site-")
        self.addCleanup(self.temporary.cleanup)
        self.folder = Path(self.temporary.name)
        self.root = self.folder / "source"
        shutil.copytree(ROOT / "site", self.root / "site")
        (self.root / "Resources").mkdir()
        shutil.copyfile(ROOT / "Resources/AppIcon.png", self.root / "Resources/AppIcon.png")
        self.destination = self.folder / "prepared"
        self.record_path = self.root / "site/assets/social-preview.json"
        self.image_path = self.root / SHARE_PATH
        self.canonical = "https://preview.example.invalid/lemulip/"

    def prepare(self, repository="osmankaankars/lemulip", pages_url=None, destination=None):
        return prepare_site(self.root, destination or self.destination, repository,
                            self.canonical if pages_url is None else pages_url)

    def read_tags(self):
        parser = HeadTags()
        parser.feed((self.destination / "index.html").read_text())
        return parser.values

    def write_record(self, **changes):
        record = json.loads(self.record_path.read_text())
        record.update(changes)
        self.record_path.write_text(json.dumps(record))

    def test_exact_prepared_metadata_and_every_local_reference(self):
        before = snapshot(self.root)
        self.prepare()
        values = self.read_tags()
        expected = {
            "canonical": self.canonical,
            "og:url": self.canonical,
            "og:image": self.canonical + "assets/social-preview.png",
            "og:image:type": "image/png", "og:image:width": "1200", "og:image:height": "630",
            "og:image:alt": SHARE_ALT, "twitter:card": "summary_large_image",
            "twitter:image": self.canonical + "assets/social-preview.png",
            "twitter:image:alt": SHARE_ALT,
            "twitter:title": "Lemulip · File tools, right where you drag.",
            "twitter:description": "35 conversion output formats. 26 tools. 6 file actions. Free, open source, and local to your Mac.",
        }
        self.assertEqual(GENERATED_KEYS, set(expected))
        for key, value in expected.items():
            self.assertEqual([value], values.get(key), key)
        page = (self.destination / "index.html").read_text()
        references = References()
        references.feed(page)
        for asset in references.local:
            self.assertTrue((self.destination / asset).is_file(), asset)
        self.assertIn('data-repository="https://github.com/osmankaankars/lemulip"', page)
        self.assertNotIn("../Resources/", page)
        self.assertNotIn("demo-preview.png", page)
        self.assertFalse((self.destination / "assets/demo-preview.png").exists())
        self.assertEqual(self.image_path.read_bytes(), (self.destination / "assets" / SHARE_FILE).read_bytes())
        self.assertEqual((self.root / "Resources/AppIcon.png").read_bytes(), (self.destination / "app-icon.png").read_bytes())
        self.assertEqual(before, snapshot(self.root), "Preparing deployment must not alter source files")

    def test_root_custom_domain_subpaths_and_trailing_slash(self):
        for index, base in enumerate(("https://lemulip.example", "https://lemulip.example/",
                                      "https://pages.example/projects/lemulip", "https://pages.example/projects/lemulip/")):
            with self.subTest(base=base):
                destination = self.folder / ("output-" + str(index))
                self.prepare(pages_url=base, destination=destination)
                parser = HeadTags(); parser.feed((destination / "index.html").read_text())
                expected = base.rstrip("/") + "/"
                self.assertEqual([expected], parser.values["canonical"])
                self.assertEqual([expected + "assets/social-preview.png"], parser.values["og:image"])

    def test_unsafe_or_ambiguous_urls_fail_before_output(self):
        base = "https://preview.example.invalid/lemulip"
        invalid = ("", "http://preview.example.invalid/lemulip", "//preview.example.invalid/lemulip",
                   base + "?query=1", base + "#part", base + "/../other", base + "/./other",
                   base + "//other", base + "/%2e%2e/other", base + "\n", "\x00" + base,
                   "https://.../lemulip", "https://preview.example.invalid:8443/lemulip",
                   base.replace("://", "://reader@"), base.replace("://", "://reader:secret@"))
        for value in invalid:
            with self.subTest(url=value):
                with self.assertRaises(SiteError): self.prepare(pages_url=value)
                self.assertFalse(self.destination.exists())

    def test_invalid_repository_fails_before_output(self):
        for value in ("", "owner", "owner/repo/extra", "owner/..", "owner/repo?query", 'owner/repo"'):
            with self.subTest(repository=value):
                with self.assertRaises(SiteError): self.prepare(repository=value)
                self.assertFalse(self.destination.exists())

    def test_missing_image_or_manifest_fails_before_output(self):
        for path in (self.image_path, self.record_path):
            with self.subTest(path=path.name):
                original = path.read_bytes()
                path.unlink()
                with self.assertRaises(OSError): self.prepare()
                self.assertFalse(self.destination.exists())
                path.write_bytes(original)

    def test_manifest_dimensions_filename_alt_and_digest_are_required(self):
        original = self.record_path.read_bytes()
        for changes in ({"width": 1199}, {"height": 0}, {"file": "../other.png"},
                        {"alt": "Unreviewed copy"}, {"sha256": "0" * 64}):
            with self.subTest(changes=changes):
                self.record_path.write_bytes(original)
                self.write_record(**changes)
                with self.assertRaises(SiteError): self.prepare()
                self.assertFalse(self.destination.exists())

    def test_corrupt_image_is_rejected_even_with_a_matching_fixture_digest(self):
        # Isolate format validation from the independent digest guard.
        data = self.image_path.read_bytes()[:-2]
        digest = hashlib.sha256(data).hexdigest()
        self.image_path.write_bytes(data)
        self.write_record(sha256=digest)
        with patch.dict(PUBLIC_IMAGES, {SHARE_PATH: digest}):
            with self.assertRaisesRegex(SiteError, "approved metadata-free PNG"):
                self.prepare()
        self.assertFalse(self.destination.exists())

    def test_actual_frame_dimensions_must_match_manifest(self):
        data = bytearray(self.image_path.read_bytes())
        struct.pack_into(">I", data, 16, 1199)
        struct.pack_into(">I", data, 29, zlib.crc32(data[12:29]) & 0xffffffff)
        digest = hashlib.sha256(data).hexdigest()
        self.image_path.write_bytes(data)
        self.write_record(sha256=digest)
        with patch.dict(PUBLIC_IMAGES, {SHARE_PATH: digest}):
            with self.assertRaisesRegex(SiteError, "dimensions do not match"):
                self.prepare()
        self.assertFalse(self.destination.exists())

    def test_duplicate_metadata_is_rejected_instead_of_silently_published(self):
        source = self.root / "site/index.html"
        original = source.read_text()
        for added in ('<meta property="og:image" content="https://old.example/image.png">',
                      '<link rel="canonical" href="https://old.example/">',
                      '<meta property="og:title" content="Second title">'):
            with self.subTest(added=added):
                source.write_text(original.replace("</head>", added + "</head>"))
                with self.assertRaises(SiteError): self.prepare()
                self.assertFalse(self.destination.exists())

    def test_existing_destination_and_source_tree_are_preserved(self):
        self.destination.mkdir()
        marker = self.destination / "existing.txt"
        marker.write_text("keep")
        with self.assertRaises(SiteError): self.prepare()
        self.assertEqual("keep", marker.read_text())
        before = snapshot(self.root)
        with self.assertRaises(SiteError): self.prepare(destination=self.root / "generated")
        self.assertEqual(before, snapshot(self.root))

    def test_symlinked_site_input_is_rejected(self):
        (self.root / "site/linked.txt").symlink_to(self.root / "Resources/AppIcon.png")
        with self.assertRaisesRegex(SiteError, "symbolic links"): self.prepare()
        self.assertFalse(self.destination.exists())

    def test_deployment_and_browser_checks_include_builder_and_image_changes(self):
        for name in ("pages.yml", "site-review.yml"):
            workflow = (ROOT / ".github/workflows" / name).read_text()
            filters = re.findall(r"^    paths: (.+)$", workflow, re.M)
            self.assertEqual(2, len(filters))
            for paths in filters:
                for required in ("'site/**'", "'script/prepare_site.py'", "'script/test_prepare_site.py'",
                                 "'.github/workflows/pages.yml'", "'Resources/AppIcon.png'"):
                    self.assertIn(required, paths)


if __name__ == "__main__":
    unittest.main()
