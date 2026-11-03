"""Guard that the real-app suite retains its baseline and bounded editor-control coverage."""
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
                     'testOrganizerFirstCancelClickDiscardsActivePositionDraft',
                     'testWAVTrimDefaultsToSourceFormatAndKeepsManualChoice',
                     'testEnglishInvalidPDFExplainsRecoveryAndCanCancel',
                     'testTurkishInvalidPDFExplainsRecoveryAndCanCancel',
                     'testTurkishOrganizerResultRevealsTheProducedCopyInFinder',
                     'testOrganizerDestinationCancelPreservesTheEditedOrder',
                     'testTurkishMergeFirstCancelClickDiscardsActivePositionDraft',
                     'testEnglishAudioResetSelectionAndPlaybackResume',
                     'testTurkishAudioResetSelectionAndPlaybackResume'}
        present = set(re.findall(r'func (test\w+)\(', sources))
        self.assertFalse(required - present, f'Missing native coverage: {sorted(required - present)}')
        self.assertTrue({'testEnglishWheelPointerKeyboardAndVisualReview',
                         'testTurkishWheelPointerKeyboardAndVisualReview'} <= present)
        self.assertEqual(len(present), 37,
                         'Keep all 34 existing cases, Turkish merge controls and two audio control flows')

    def test_workflow_assembles_and_records_the_new_cases(self):
        workflow = (ROOT / '.github/workflows/native-ui-review.yml').read_text()
        self.assertIn('script/native_ui/OptionsParityTests.swift', workflow)
        self.assertIn("record['optionsParitySourceSHA256']", workflow)
        self.assertIn('suite.read_bytes()+fragment+position+options', workflow)
        self.assertIn('script/native_ui/PDFResultUITests.swift', workflow)
        self.assertIn("record['pdfResultSourceSHA256']", workflow)
        self.assertIn('script/native_ui/EditorControlsUITests.swift', workflow)
        self.assertIn("record['editorControlsSourceSHA256']", workflow)
        self.assertIn('+sound+wheel+result+controls)', workflow)

    def test_media_uses_real_ffmpeg_and_retains_its_version(self):
        workflow = (ROOT / '.github/workflows/native-ui-review.yml').read_text()
        self.assertIn('brew install ffmpeg', workflow)
        self.assertIn('ffmpeg -version', workflow)
        self.assertIn('Quality.wav', workflow)
        self.assertIn('ffmpeg-version.txt', workflow)
        self.assertIn("sine=frequency=440:duration=0.25", workflow,
                      'Keep the existing options fixture unchanged')
        self.assertIn("sine=frequency=440:duration=20", workflow)
        long_fixture = '"$RUNNER_TEMP/lemulip-native-ui/Fixtures/AudioControls/Playback.wav"'
        self.assertIn('mkdir "$RUNNER_TEMP/lemulip-native-ui/Fixtures/AudioControls"', workflow)
        self.assertIn('ffmpeg -v error -i ' + long_fixture + ' -f null -', workflow)
        self.assertLess(workflow.index(long_fixture), workflow.index('xcrun xcodebuild test'),
                        'The long fixture must be staged before the sandboxed XCTest runner starts')
        controls = (ROOT / 'script/native_ui/EditorControlsUITests.swift').read_text()
        self.assertIn('appendingPathComponent("AudioControls/Playback.wav")', controls)


if __name__ == '__main__':
    unittest.main()
