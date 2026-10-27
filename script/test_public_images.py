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
    def test_native_screenshots_are_individually_reviewed(self):
        import json
        for row in json.loads((ROOT/'site/assets/screenshots.json').read_text()):
            name='site/assets/'+row['file']
            self.assertIn(name,PUBLIC_IMAGES)
            self.assertEqual(row['sha256'],PUBLIC_IMAGES[name])
            self.assertTrue(image_is_public(name,(ROOT/name).read_bytes()))
    def test_webp_rejects_metadata_truncation_and_unknown_chunks(self):
        import privacy_check,struct
        validator=getattr(privacy_check,'webp_without_metadata',None)
        self.assertTrue(callable(validator),'Missing metadata-free WebP validator')
        data=(ROOT/'site/assets/app-workspace.webp').read_bytes()
        self.assertTrue(validator(data))
        for bad in (b'',data[:-1],data+b'x',b'NOPE'+data[4:]):
            self.assertFalse(validator(bad))
        for kind in (b'EXIF',b'XMP ',b'ICCP',b'ANIM',b'JUNK'):
            altered=data+kind+struct.pack('<I',4)+b'test'
            altered=altered[:4]+struct.pack('<I',len(altered)-8)+altered[8:]
            self.assertFalse(validator(altered))
        # Even a single forged VP8 chunk must have a key-frame and valid dimensions.
        altered=bytearray(data);start=data.index(b'VP8 ')+8;altered[start+3:start+6]=b'bad'
        self.assertFalse(validator(bytes(altered)))
    def test_screenshots_record_window_only_crops(self):
        import json
        for row in json.loads((ROOT/'site/assets/screenshots.json').read_text()):
            left, top, right, bottom = row['cropBox']
            width, height = row['sourceSize']
            self.assertTrue(0 < left < right < width)
            self.assertTrue(0 < top < bottom < height)
            self.assertIn('Window-only crop', row['processing'])
            self.assertEqual(round((bottom-top)*row['width']/(right-left)), row['height'])

    def test_alpha_webp_checks_order_flags_and_canvas(self):
        import privacy_check, struct
        data=(ROOT/'site/assets/app-workspace.webp').read_bytes()
        validator=privacy_check.webp_without_metadata
        self.assertTrue(validator(data))
        self.assertEqual(data[12:16],b'VP8X')
        chunks=[]; offset=12
        while offset<len(data):
            size=struct.unpack_from('<I',data,offset+4)[0]
            end=offset+8+size+(size&1)
            chunks.append(data[offset:end]);offset=end
        self.assertEqual([c[:4] for c in chunks],[b'VP8X',b'ALPH',b'VP8 '])
        def riff(items):
            body=b'WEBP'+b''.join(items)
            return b'RIFF'+struct.pack('<I',len(body))+body
        for items in ([chunks[0],chunks[2]], [chunks[1],chunks[0],chunks[2]],
                      [chunks[0],chunks[1],chunks[1],chunks[2]]):
            self.assertFalse(validator(riff(items)))
        for offset,value in ((20,0x02),(21,1),(24,0)):
            altered=bytearray(data);altered[offset]=value
            self.assertFalse(validator(bytes(altered)))

    def test_unapproved_binary_media_is_rejected(self):
        data = b'\x00\x00\x00\x18ftypmp42'
        self.assertIn('unexpected-binary-file', content_failures('site/assets/unapproved.mp4',data))
if __name__=='__main__': unittest.main()
