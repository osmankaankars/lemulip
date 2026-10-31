"""Guard that the real-app suite retains the legacy options and Cancel coverage."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parent.parent


class NativeCoverageTests(unittest.TestCase):
    def test_real_app_has_all_ten_bilingual_options_and_first_click_cancel(self):
        sources = '\n'.join(p.read_text() for p in (ROOT / 'script/native_ui').glob('*Tests.swift'))
        required = {f'test{language}{control}Control' for language in ('English', 'Turkish')
                    for control in ('Quality', 'Dimension', 'Speed', 'Volume', 'PageRange')}
        required |= {'testMergeFirstCancelClickDiscardsActivePositionDraft',
                     'testOrganizerFirstCancelClickDiscardsActivePositionDraft'}
        present = set(re.findall(r'func (test\w+)\(', sources))
        self.assertFalse(required - present, f'Missing native coverage: {sorted(required - present)}')
        self.assertTrue({'testEnglishWheelPointerKeyboardAndVisualReview',
                         'testTurkishWheelPointerKeyboardAndVisualReview'} <= present)
        self.assertEqual(len(present), 29, 'Keep all 27 cases plus both native wheel reviews')

    def test_workflow_assembles_and_records_the_new_cases(self):
        workflow = (ROOT / '.github/workflows/native-ui-review.yml').read_text()
        self.assertIn('script/native_ui/OptionsParityTests.swift', workflow)
        self.assertIn("record['optionsParitySourceSHA256']", workflow)
        self.assertIn('suite.read_bytes()+fragment+position+options', workflow)

    def test_media_uses_real_ffmpeg_and_retains_its_version(self):
        workflow = (ROOT / '.github/workflows/native-ui-review.yml').read_text()
        self.assertIn('brew install ffmpeg', workflow)
        self.assertIn('ffmpeg -version', workflow)
        self.assertIn('Quality.wav', workflow)
        self.assertIn('ffmpeg-version.txt', workflow)


if __name__ == '__main__':
    unittest.main()
