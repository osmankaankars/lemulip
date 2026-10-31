"""Fail closed when native coverage stops being an exact-source release prerequisite."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parent.parent


def job(text, name):
    match = re.search(r'^  ' + re.escape(name) + r':\n(.*?)(?=^  [\w-]+:|\Z)', text, re.M | re.S)
    if match is None:
        raise AssertionError('Missing required job: ' + name)
    return match.group(1)


class NativeReleaseGateTests(unittest.TestCase):
    def setUp(self):
        self.build = (ROOT / '.github/workflows/build.yml').read_text()
        self.native = (ROOT / '.github/workflows/native-ui-review.yml').read_text()

    def test_every_build_invokes_the_same_commit_native_workflow(self):
        native_job = job(self.build, 'native-ui')
        self.assertIn('uses: ./.github/workflows/native-ui-review.yml', native_job)
        self.assertNotRegex(native_job, r'(?m)^    if:', 'The gate must run on PR, main and tags')
        self.assertIn('  workflow_call:', self.native)
        self.assertNotIn('  pull_request:', self.native, 'Do not run two competing copies')
        self.assertIn('test "$(git rev-parse HEAD)" = "$GITHUB_SHA"', self.native)

    def test_package_waits_for_both_native_hosts_without_a_bypass(self):
        package = job(self.build, 'package')
        needs = re.search(r'needs: \[([^\]]+)\]', package)
        self.assertIsNotNone(needs)
        self.assertTrue({'test', 'native-engines', 'native-ui'} <= set(x.strip() for x in needs[1].split(',')))
        self.assertNotIn('always()', package)
        self.assertNotIn('continue-on-error:', self.build + self.native)
        self.assertNotRegex(job(self.native, 'review'), r'(?m)^    if:', 'Neither native host may be optional')
        self.assertNotIn('|| true', self.native)
        self.assertIn('arch: arm64', self.native)
        self.assertIn('arch: x86_64', self.native)
        self.assertNotIn('-only-testing:', self.native)
        self.assertNotIn('-skip-testing:', self.native)

    def test_legacy_diagnostics_remain_runnable_but_are_not_the_release_host(self):
        self.assertNotIn('--filter OperationOptionsAccessibilityTests', self.build)
        self.assertNotIn('run: python3 script/review_pdf_pointer.py', self.build)
        legacy_path = ROOT / '.github/workflows/legacy-native-diagnostics.yml'
        self.assertTrue(legacy_path.is_file(), 'Keep failures inspectable in an opt-in workflow')
        legacy = legacy_path.read_text()
        self.assertIn('  workflow_dispatch:', legacy)
        self.assertNotIn('  push:', legacy)
        self.assertNotIn('  pull_request:', legacy)
        self.assertIn('--filter OperationOptionsAccessibilityTests', legacy)
        self.assertIn('python3 script/review_pdf_pointer.py', legacy)
        self.assertNotIn('continue-on-error:', legacy)


if __name__ == '__main__':
    unittest.main()
