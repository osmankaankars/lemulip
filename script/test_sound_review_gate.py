"""Require real-app sound preference coverage and a gated, unpublished review copy."""
from pathlib import Path
import re
import unittest
from test_native_release_gate import job

ROOT = Path(__file__).resolve().parent.parent


class SoundReviewGateTests(unittest.TestCase):
    def test_both_language_lifecycles_are_compiled_and_fingerprinted(self):
        path = ROOT / 'script/native_ui/SelectionSoundUITests.swift'
        self.assertTrue(path.is_file(), 'Add real-app sound preference lifecycle cases')
        source = path.read_text()
        for language in ('English', 'Turkish'):
            self.assertIn(f'func test{language}SelectionSoundPreferenceSurvivesRelaunch(', source)
        self.assertNotIn('defaults write', source)
        self.assertNotIn('-selectionSoundsEnabled', source, 'A launch override would mask persistence')
        self.assertIn('settings.selection-sounds.preview', source)
        self.assertIn('settings.selection-sounds', source)
        self.assertIn('app.terminate()', source)
        self.assertIn('app.launch()', source)
        workflow = (ROOT / '.github/workflows/native-ui-review.yml').read_text()
        self.assertIn('script/native_ui/SelectionSoundUITests.swift', workflow)
        self.assertIn("record['selectionSoundSourceSHA256']", workflow)
        self.assertIn('suite.read_bytes()+fragment+position+options+sound', workflow)

    def test_candidate_is_gated_and_never_a_release(self):
        build = (ROOT / '.github/workflows/build.yml').read_text()
        candidate = job(build, 'review-copy')
        self.assertIn('needs: [test, native-ui]', candidate)
        self.assertIn("github.event_name == 'pull_request'", candidate)
        self.assertIn('github.event.pull_request.head.repo.full_name == github.repository', candidate)
        self.assertIn('uses: ./.github/workflows/current-ui-review.yml', candidate)
        self.assertNotIn('always()', candidate)
        path = ROOT / '.github/workflows/current-ui-review.yml'
        self.assertTrue(path.is_file())
        workflow = path.read_text()
        self.assertIn('  workflow_call:', workflow)
        self.assertIn('REVIEW_SOURCE_COMMIT: ${{ github.sha }}', workflow)
        self.assertIn('test "$(git rev-parse HEAD)" = "$GITHUB_SHA"', workflow)
        self.assertIn('needs: [build, verify]', workflow)
        self.assertIn('arch: arm64', workflow)
        self.assertIn('arch: x86_64', workflow)
        self.assertIn('digest-mismatch: error', workflow)
        self.assertIn('package_ui_review.py evidence', workflow)
        self.assertIn('UNRELEASED-CURRENT-UI-REVIEW-', workflow)
        self.assertNotIn('contents: write', workflow)
        self.assertNotIn('publish_release', workflow)
        self.assertNotIn('continue-on-error:', workflow)
        self.assertNotIn('refs/heads/review/quality-020', workflow)


if __name__ == '__main__':
    unittest.main()
