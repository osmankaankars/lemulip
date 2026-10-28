#!/usr/bin/env python3
"""Small source contracts for the native UI; rendered checks run on macOS."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / 'Sources/Lemulip'

class InterfaceTests(unittest.TestCase):
    def test_workspace_uses_compact_adaptive_navigation(self):
        source = (APP/'DashboardView.swift').read_text()
        self.assertIn('GeometryReader', source)
        self.assertIn('compact: geometry.size.width < 880', source)
        self.assertIn('minWidth: 720, minHeight: 560', source)
        self.assertNotIn('A Fresh Spin On Your Files.', source)
        self.assertNotIn('Free Forever', source)
        self.assertNotIn('Your Files.\\nYour Mac. Your Control.', source)
        self.assertIn('model.chooseFiles()', source)
        self.assertIn('model.showWheel()', source)
        self.assertIn('loadDrop', source)

    def test_native_window_agrees_with_compact_layout(self):
        source = (APP/'AppController.swift').read_text()
        self.assertIn('NSSize(width: 720, height: 560)', source)
        self.assertIn('FreewheelMainWindow', source)  # Existing preference migration stays intact.

    def test_activity_prioritizes_results_without_a_fake_upload_statistic(self):
        source = (APP/'ActivityView.swift').read_text()
        self.assertNotIn('Files Uploaded', source)
        self.assertNotIn('A Little Less Busywork.', source)
        self.assertIn('model.cancelJob(item.id)', source)
        self.assertIn('model.retryJob(item.id)', source)
        self.assertIn('progress.fractionCompleted', source)
        self.assertIn('OutputActions', source)
        self.assertIn('.onDrag', source)

    def test_editor_controls_use_one_shared_footer(self):
        for name in ('ImageCropView', 'VideoCropView', 'AudioTrimView', 'VideoTrimView',
                     'PDFOrganizeView', 'PDFMergeView', 'OperationOptionsView'):
            with self.subTest(view=name):
                self.assertIn('EditorFooter(', (APP/(name+'.swift')).read_text())
        shared = APP/'InterfaceComponents.swift'
        self.assertTrue(shared.exists())
        if shared.exists():
            source = shared.read_text()
            self.assertIn('.keyboardShortcut(.defaultAction)', source)
            self.assertIn('.keyboardShortcut(.cancelAction)', source)
            self.assertIn('Palette.primaryAction', source)

    def test_engine_paths_and_help_are_progressively_disclosed(self):
        source = (APP/'SettingsView.swift').read_text()
        self.assertNotIn('Small App. Your Rules.', source)
        self.assertIn('DisclosureGroup', source)
        self.assertIn('Format Support', source)
        self.assertIn('EngineLocator.find', source)
        self.assertIn('PandocInstallButton', source)
        self.assertIn('engineStatus(report)', source)

    def test_result_card_is_opt_in_and_never_activates_on_completion(self):
        source = (APP/'AppController.swift').read_text()
        body = source.split('private func showResultCard(', 1)[1].split('private func placeResultPanel', 1)[0]
        self.assertIn('.nonactivatingPanel', body)
        self.assertNotIn('makeKeyAndOrderFront', body)
        self.assertNotIn('NSApp.activate', body)
        self.assertIn('legacyReveal:', source)
        self.assertIn('case .card:', source)
        self.assertIn('guard validateOutputs(urls)', source)
        settings = (APP/'SettingsView.swift').read_text()
        self.assertIn('$model.completionPresentation', settings)

    def test_search_request_survives_navigation_and_practice_image_is_checked(self):
        source = (APP/'OperationBrowser.swift').read_text()
        self.assertIn('.onAppear', source)
        self.assertIn('consumeSearchRequest', source)
        controller = (APP/'AppController.swift').read_text()
        self.assertNotIn('NSApp.applicationIconImage!', controller)
        self.assertIn('pinnedOperationIDs', controller)
        self.assertIn('OperationDiscovery.normalizedPins', controller)
        self.assertIn('posixPermissions: 0o700', controller)

    def test_generic_editor_preserves_flatten_confirmation(self):
        source = (APP/'OperationOptionsView.swift').read_text()
        self.assertIn('!flattenAcknowledged', source)
        self.assertIn('flattenAcknowledged', source)
        self.assertIn('16...16000', source)
        self.assertIn('accessibility tags', source)

    def test_user_guide_matches_the_refined_interface(self):
        guide = (ROOT/'docs/USER_GUIDE.md').read_text()
        for label in ('⌘F', 'Pinned', 'When Finished', 'Show Result Card', 'Stay Quiet',
                      'Try With A Sample', 'Settings → Format Support', 'Save Beside The Original'):
            self.assertIn(label, guide)
        self.assertNotIn('Settings → Local Engines', guide)
        self.assertNotIn("Save in the First File's Folder", guide)

    def test_missing_support_points_to_current_settings_section(self):
        source = (APP/'AppController.swift').read_text()
        self.assertNotIn('Settings → Engines', source)
        self.assertNotIn('Ayarlar → Motorlar', source)
        self.assertIn('Settings → Format Support', source)
        self.assertIn('Ayarlar → Biçim Desteği', source)

    def test_output_free_success_does_not_present_a_missing_file(self):
        source = (APP/'AppController.swift').read_text()
        completion = source.split('self.update(id) { $0.state = .succeeded;', 1)[1].split('} catch {', 1)[0]
        self.assertIn('if !result.outputs.isEmpty {', completion)
        before, guarded = completion.split('if !result.outputs.isEmpty {', 1)
        self.assertNotIn('self.reveal(', before)
        self.assertIn('case .finder: self.reveal(result.outputs)', guarded)
        self.assertIn('case .card: self.showResultCard(result.outputs)', guarded)
        # Skipping presentation must not return before queue cleanup/startNextJob.
        self.assertNotIn('return', completion)

    def test_new_contract_runs_in_mac_ci(self):
        source = (ROOT/'.github/workflows/build.yml').read_text()
        self.assertIn('python3 script/test_interface.py', source)

if __name__ == '__main__':
    unittest.main()
