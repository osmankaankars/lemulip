#!/usr/bin/env python3
"""Exercise review identity isolation and exact-archive evidence without native mocks."""
import json
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import package_ui_review as review


class ReviewPackagingTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.commit = 'a' * 40

    def archive(self, entries=None):
        with zipfile.ZipFile(self.root / review.ARCHIVE, 'w') as zipped:
            for name, data in entries or [(review.FOLDER + '/readme.txt', b'UI review')]:
                zipped.writestr(name, data)
        digest = review.sha256(self.root / review.ARCHIVE)
        (self.root / (review.ARCHIVE + '.sha256')).write_text(f'{digest}  {review.ARCHIVE}\n')
        return digest

    def receipts(self):
        digest = self.archive()
        for architecture in review.ARCHES:
            report = {'status': review.STATUS, 'result': 'PASS', 'commit': self.commit,
                      'architecture': architecture, 'archiveSHA256': digest}
            (self.root / ('native-' + architecture + '.json')).write_text(json.dumps(report))

    def payload(self):
        payload = self.root / review.FOLDER
        payload.mkdir()
        (payload / 'fixture.srt').write_text('Synthetic source\n')
        (payload / 'REVIEW-INFO.json').write_text(json.dumps({
            'status': review.STATUS, 'releaseReady': False, 'bundledEngines': []}))
        hashes = review.file_hashes(payload)
        (payload / 'SHA256SUMS.txt').write_text(''.join(f'{value}  {name}\n' for name, value in hashes.items()))
        return payload

    def test_identity_override_preserves_source_and_version(self):
        original = {'CFBundleIdentifier': 'app.freewheel.Freewheel', 'CFBundleExecutable': 'Lemulip',
                    'CFBundleName': 'Lemulip', 'CFBundleDisplayName': 'Lemulip',
                    'CFBundleShortVersionString': '0.1.20', 'CFBundleVersion': '23',
                    'CFBundleDocumentTypes': [{'CFBundleTypeRole': 'Viewer'}]}
        snapshot = json.loads(json.dumps(original))
        staged, changes = review.review_plist(original)
        self.assertEqual(original, snapshot)
        self.assertNotEqual(staged['CFBundleIdentifier'], original['CFBundleIdentifier'])
        self.assertEqual({k for k in original if original[k] != staged[k]}, set(review.OVERRIDES))
        for key, change in changes.items():
            self.assertEqual(change, {'original': original[key], 'review': staged[key]})
        with self.assertRaisesRegex(ValueError, 'identity'):
            review.review_plist({**original, 'CFBundleIdentifier': 'different.app'})

    def test_dirty_or_wrong_commit_cannot_be_packaged(self):
        for actual, clean in [(self.commit, False), ('b' * 40, True)]:
            with self.subTest(actual=actual, clean=clean), patch.object(
                    review, 'source_identity', return_value={'commit': actual, 'worktreeClean': clean}):
                with self.assertRaisesRegex(ValueError, 'exact clean source'):
                    review.checked_source(self.commit)

    def test_content_manifest_detects_changed_original_missing_and_added_files(self):
        payload = self.payload()
        review.verify_contents(payload)
        source = payload / 'fixture.srt'
        source.write_text('Changed source\n')
        with self.assertRaisesRegex(ValueError, 'checksum mismatch'):
            review.verify_contents(payload)
        source.unlink()
        with self.assertRaisesRegex(ValueError, 'checksum mismatch'):
            review.verify_contents(payload)
        source.write_text('Synthetic source\n')
        (payload / 'unrecorded.txt').write_text('Unexpected')
        with self.assertRaisesRegex(ValueError, 'checksum mismatch'):
            review.verify_contents(payload)

    def test_content_symlink_is_rejected(self):
        payload = self.payload()
        (payload / 'link').symlink_to(payload / 'fixture.srt')
        with self.assertRaisesRegex(ValueError, 'regular files'):
            review.verify_contents(payload)

    def test_archive_change_after_checksum_fails(self):
        self.archive()
        with (self.root / review.ARCHIVE).open('ab') as archive:
            archive.write(b'changed')
        with self.assertRaisesRegex(ValueError, 'ZIP checksum mismatch'):
            review.checked_archive(self.root)

    def test_unsafe_archive_paths_and_symlinks_are_rejected_before_extraction(self):
        for name in [review.FOLDER + '/../outside', '/absolute', 'DifferentRoot/file',
                     review.FOLDER + '/bad\\name']:
            with self.subTest(name=name):
                self.archive([(name, b'fixture')])
                with self.assertRaisesRegex(ValueError, 'ZIP entry'):
                    review.checked_archive(self.root)
        link = zipfile.ZipInfo(review.FOLDER + '/link')
        link.create_system = 3
        link.external_attr = (stat.S_IFLNK | 0o777) << 16
        self.archive([(link, b'../outside')])
        with self.assertRaisesRegex(ValueError, 'ZIP entry'):
            review.checked_archive(self.root)

    def test_final_artifact_requires_both_passes_for_same_source_and_archive(self):
        self.receipts()
        review.evidence(self.root, self.commit)
        path = self.root / 'native-x86_64.json'
        original = json.loads(path.read_text())
        for key, value in [('result', 'FAIL'), ('commit', 'b' * 40),
                           ('architecture', 'arm64'), ('archiveSHA256', 'c' * 64)]:
            with self.subTest(key=key):
                path.write_text(json.dumps({**original, key: value}))
                with self.assertRaisesRegex(ValueError, 'Both native receipts'):
                    review.evidence(self.root, self.commit)
        path.unlink()
        with self.assertRaises(FileNotFoundError):
            review.evidence(self.root, self.commit)


if __name__ == '__main__':
    unittest.main()
