#!/usr/bin/env python3
"""The D23 public-path exception accepts one already-masked display token only."""
from __future__ import annotations

import unittest

from privacy_check import content_failures


MASKED_PATH = b'/Users/USER/*/NativeSamplerCalibration'
APPROVED_FILES = (
    'script/privacy_check.py',
    'script/test_privacy_masked_sampler_paths.py',
    'script/review_native_sampler_identity.py',
    'script/test_review_native_sampler_identity.py',
    'script/native_sampler_identity_fixture.py',
    'docs/NATIVE_SAMPLER_IDENTITY_REVIEW.md',
    'docs/evidence/D23-native-sampler-identity-review.json',
    'docs/evidence/D23-verification.json',
)


class MaskedSamplerPathPrivacyTests(unittest.TestCase):
    def test_exact_display_token_is_allowed_only_in_reviewed_files(self):
        for name in APPROVED_FILES:
            with self.subTest(name=name):
                self.assertEqual(content_failures(name, MASKED_PATH), [])

    def test_token_boundaries_allow_start_end_ascii_whitespace_and_quotes(self):
        for before in (b'', b' ', b'\t', b'\r', b'\n', b'\v', b'\f', b"'", b'"', b'`'):
            for after in (b'', b' ', b'\t', b'\r', b'\n', b'\v', b'\f', b"'", b'"', b'`'):
                with self.subTest(before=before, after=after):
                    self.assertEqual(content_failures(APPROVED_FILES[0], before + MASKED_PATH + after), [])

    def test_an_unlisted_or_similarly_named_file_is_not_exempt(self):
        for name in ('docs/unapproved.md', 'script/another_test.py',
                     'docs/NATIVE_SAMPLER_IDENTITY_REVIEW.md.extra',
                     'prefix/script/privacy_check.py', 'SCRIPT/privacy_check.py'):
            with self.subTest(name=name):
                self.assertIn('literal-home-path', content_failures(name, MASKED_PATH))

    def test_mutated_owner_prefix_suffix_and_unicode_boundaries_are_rejected(self):
        variants = [MASKED_PATH.replace(b'USER', b'ANOTHER'),
                    MASKED_PATH.replace(b'USER', b'USER.extra'),
                    MASKED_PATH.replace(b'USER', b'user'),
                    MASKED_PATH.replace(b'*', b'folder')]
        # Construct invalid paths from the reviewed token, without retaining a
        # real user's home path in this public test source.
        for affix in (b'/private', b'.bak', b'?foo', b'_', b'-', b'(', b')', b'[', b']',
                      'é'.encode(), '\u200b'.encode(), '\u00a0'.encode()):
            variants += [affix + MASKED_PATH, MASKED_PATH + affix]
        for data in variants:
            with self.subTest(data=data):
                self.assertIn('literal-home-path', content_failures(APPROVED_FILES[0], data))

    def test_a_second_unmasked_home_path_still_fails(self):
        unmasked = MASKED_PATH.replace(b'USER/*/NativeSamplerCalibration', b'synthetic-owner/file.txt')
        for data in (MASKED_PATH + b'\n' + unmasked, unmasked + b'\n' + MASKED_PATH):
            with self.subTest(data=data):
                self.assertIn('literal-home-path', content_failures(APPROVED_FILES[0], data))

    def test_all_other_secret_rules_still_scan_the_original_bytes(self):
        examples = {
            'github-token': b'gh' + b'p_' + b'A' * 36,
            'private-key': b'-----BEGIN ' + b'PRIVATE KEY-----',
            'embedded-email': b'synthetic' + b'@' + b'example.invalid',
            'aws-access-id': b'AK' + b'IA' + b'A' * 16,
            'openai-key': b'sk' + b'-' + b'A' * 30,
            'slack-token': b'xox' + b'b-' + b'A' * 25,
            'credential-in-url': b'https://' + b'username:password' + b'@example.invalid',
        }
        for rule, marker in examples.items():
            with self.subTest(rule=rule):
                failures = content_failures(APPROVED_FILES[0], MASKED_PATH + b'\n' + marker)
                self.assertIn(rule, failures)
                self.assertNotIn('literal-home-path', failures)

    def test_repeated_reviewed_tokens_do_not_exempt_an_adjacent_extension(self):
        approved = b'"' + MASKED_PATH + b'"\n`' + MASKED_PATH + b'`'
        self.assertEqual(content_failures(APPROVED_FILES[0], approved), [])
        self.assertIn('literal-home-path', content_failures(
            APPROVED_FILES[0], approved + b'\n' + MASKED_PATH + b'/private'))


if __name__ == '__main__':
    unittest.main()
