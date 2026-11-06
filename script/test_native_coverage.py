"""Guard the real-app baseline and bounded editor/control/language coverage."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parent.parent


class NativeCoverageTests(unittest.TestCase):
    def test_real_app_has_all_ten_bilingual_options_and_first_click_cancel(self):
        # The keyboard and mouse reference controls have separate runners and
        # are not production acceptance. Keep the exact 58-case gate intact.
        diagnostics = {'NativeDragKeyboardTests.swift', 'NativeDragMouseTests.swift'}
        workflow = (ROOT / '.github/workflows/native-ui-review.yml').read_text()
        for diagnostic in diagnostics:
            self.assertNotIn('script/native_ui/' + diagnostic, workflow)
        sources = '\n'.join(p.read_text() for p in (ROOT / 'script/native_ui').glob('*Tests.swift')
                            if p.name not in diagnostics)
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
                     'testTurkishAudioResetSelectionAndPlaybackResume',
                     'testEnglishVideoFieldFocusPreservesPausedPosition'}
        required |= {f'test{language}{scenario}' for language in ('English', 'Turkish')
                     for scenario in ('MergeErrorPreservesTheLongFilename',
                                      'EmptyAudioExplainsRecovery',
                                      'EmptyVideoExplainsRecovery',
                                      'WordCountReportsTheActualCounts',
                                      'MoveReportsTheActualFileTransfer')}
        required |= {f'testState{theme}{language}MinimumWorkspaceAnd{editor}Keyboard'
                     for theme, editor in (('Orchard', 'PDF'), ('Pistachio', 'Audio'), ('Lemonade', 'Video'))
                     for language in ('English', 'Turkish')}
        required |= {f'test{theme}FinderDropsPreserveInputsAndRejectDuplicates'
                     for theme in ('Orchard', 'Pistachio', 'Lemonade')}
        required.add('testRealDisplayPreferencesKeepWheelAndPDFResultsUsable')
        present = set(re.findall(r'func (test\w+)\(', sources))
        self.assertFalse(required - present, f'Missing native coverage: {sorted(required - present)}')
        self.assertTrue({'testEnglishWheelPointerKeyboardAndVisualReview',
                         'testTurkishWheelPointerKeyboardAndVisualReview'} <= present)
        self.assertEqual(len(present), 58,
                         'Keep all 48 existing cases plus the ten bounded state/accessibility cases')

    def test_workflow_assembles_and_records_the_new_cases(self):
        workflow = (ROOT / '.github/workflows/native-ui-review.yml').read_text()
        self.assertIn('script/native_ui/OptionsParityTests.swift', workflow)
        self.assertIn("record['optionsParitySourceSHA256']", workflow)
        self.assertIn('suite.read_bytes()+fragment+position+options', workflow)
        self.assertIn('script/native_ui/PDFResultUITests.swift', workflow)
        self.assertIn("record['pdfResultSourceSHA256']", workflow)
        self.assertIn('script/native_ui/EditorControlsUITests.swift', workflow)
        self.assertIn("record['editorControlsSourceSHA256']", workflow)
        self.assertIn('script/native_ui/ProductLanguageUITests.swift', workflow)
        self.assertIn("record['productLanguageSourceSHA256']", workflow)
        self.assertIn('+sound+wheel+result+controls+language+states+finder+display)', workflow)
        for filename, receipt in [('StateAccessibilityUITests.swift', 'stateAccessibilitySourceSHA256'),
                                  ('FinderDropUITests.swift', 'finderDropSourceSHA256'),
                                  ('DisplayAccessibilityUITests.swift', 'displayAccessibilitySourceSHA256')]:
            self.assertIn('script/native_ui/' + filename, workflow)
            self.assertIn("record['" + receipt + "']", workflow)
        preparation = (ROOT / 'script/prepare_native_ui.py').read_text()
        self.assertLess(preparation.index('    prepare_product_language_fixtures(fixtures)'),
                        preparation.index('    write_project(output / "Runner"'))
        self.assertLess(preparation.index('    prepare_finder_drop_fixtures(fixtures)'),
                        preparation.index('    write_project(output / "Runner"'))

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
        video_fixture = '"$RUNNER_TEMP/lemulip-native-ui/Fixtures/VideoControls/Playback.mp4"'
        self.assertIn('mkdir "$RUNNER_TEMP/lemulip-native-ui/Fixtures/VideoControls"', workflow)
        self.assertIn('testsrc2=size=320x180:rate=24:duration=20', workflow)
        self.assertIn('-c:v libx264', workflow)
        self.assertIn('-pix_fmt yuv420p', workflow)
        self.assertIn('ffmpeg -v error -i ' + video_fixture + ' -f null -', workflow)
        self.assertLess(workflow.index(video_fixture), workflow.index('xcrun xcodebuild test'),
                        'The video fixture must also be staged before XCTest starts')
        self.assertIn('appendingPathComponent("VideoControls/Playback.mp4")', controls)


if __name__ == '__main__':
    unittest.main()
