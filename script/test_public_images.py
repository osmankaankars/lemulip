#!/usr/bin/env python3
"""Regression checks for the public-image allowlist and metadata guard."""
import unittest
from privacy_check import ROOT, PUBLIC_IMAGES, image_is_public, jpeg_without_metadata, content_failures
class PublicImageTests(unittest.TestCase):
    def test_reviewed_assets_match_their_digests(self):
        for name in PUBLIC_IMAGES:
            self.assertTrue(image_is_public(name,(ROOT/name).read_bytes()),name)
    def test_changed_or_appended_image_bytes_are_rejected(self):
        for name in PUBLIC_IMAGES:
            data=(ROOT/name).read_bytes()
            self.assertFalse(image_is_public(name,data+b'x'),name)
    def test_jpeg_exif_and_comment_segments_are_rejected(self):
        data=(ROOT/'site/assets/morning-light.jpg').read_bytes()
        for marker in (b'\xff\xe1',b'\xff\xfe'):
            injected=data[:2]+marker+b'\x00\x08Exif\x00\x00'+data[2:]
            self.assertFalse(jpeg_without_metadata(injected))
    def test_truncated_jpeg_is_rejected(self):
        data=(ROOT/'site/assets/morning-light.jpg').read_bytes()
        self.assertFalse(jpeg_without_metadata(data[:-2]))
    def test_unapproved_binary_media_is_rejected(self):
        data = b'\x00\x00\x00\x18ftypmp42'
        self.assertIn('unexpected-binary-file', content_failures('site/assets/unapproved.mp4',data))
if __name__=='__main__': unittest.main()
