import copy
import tempfile
import unittest
from pathlib import Path

from prepare_native_ui import isolated_info, write_project


class NativeUIPreparationTests(unittest.TestCase):
    def test_identity_changes_only_in_the_staged_copy(self):
        original = {"CFBundleIdentifier": "app.freewheel.Freewheel", "CFBundleExecutable": "Lemulip",
                    "CFBundleName": "Lemulip", "CFBundleDisplayName": "Lemulip", "CFBundleVersion": "23",
                    "CFBundleShortVersionString": "0.1.20", "CFBundleDocumentTypes": [{"CFBundleTypeRole": "Viewer"}]}
        frozen = copy.deepcopy(original)
        result = isolated_info(original)
        self.assertEqual(original, frozen)
        self.assertEqual(result["CFBundleIdentifier"], "app.lemulip.NativeUIReview")
        self.assertEqual(result["CFBundleExecutable"], "Lemulip")
        self.assertEqual(result["CFBundleVersion"], "23")
        self.assertEqual(result["CFBundleDocumentTypes"], original["CFBundleDocumentTypes"])

    def test_an_unrelated_app_is_not_reidentified(self):
        with self.assertRaises(ValueError):
            isolated_info({"CFBundleIdentifier": "other.app", "CFBundleExecutable": "Other"})

    def test_project_preserves_test_source_and_rejects_reuse(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            suite = root / "suite.swift"
            suite.write_text("import XCTest\n")
            output = root / "generated"
            project = write_project(output, suite, root / 'A "Quoted" App.app', root / "Fixtures")
            self.assertEqual((output / "QualityUITests.swift").read_text(), suite.read_text())
            self.assertIn("com.apple.product-type.bundle.ui-testing", (project / "project.pbxproj").read_text())
            self.assertIn('A \\"Quoted\\" App.app', (output / "ReviewConfiguration.swift").read_text())
            self.assertTrue((project / "xcshareddata/xcschemes/QualityReview.xcscheme").is_file())
            with self.assertRaises(FileExistsError):
                write_project(output, suite, root / "Other.app", root / "OtherFixtures")


if __name__ == "__main__":
    unittest.main()
