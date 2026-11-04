import copy
import tempfile
import unittest
from pathlib import Path

from prepare_native_ui import (isolated_info, prepare_pdf_result_fixtures,
                               prepare_product_language_fixtures, prepare_finder_drop_fixtures, write_project)


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

    def test_pdf_results_are_staged_as_isolated_input_only_cases(self):
        with tempfile.TemporaryDirectory() as temporary:
            fixtures = Path(temporary) / "Fixtures"
            source = fixtures / "Organize/Page-Order.pdf"
            source.parent.mkdir(parents=True)
            # A byte marker is enough here: the existing Swift generator owns
            # the real PDF. This check independently verifies staging fidelity.
            original = b"%PDF-1.4\nsynthetic four-page source marker\n%%EOF\n"
            source.write_bytes(original)
            prepare_pdf_result_fixtures(fixtures)
            root = fixtures / "PDFResults"
            scenarios = {"EnglishInvalid", "TurkishInvalid", "FinderHandoff", "DestinationCancel",
                         "AccessibilityMotion", "AccessibilityTransparency"}
            self.assertEqual({path.name for path in root.iterdir()}, scenarios)
            inputs = []
            for scenario in scenarios:
                files = list((root / scenario).iterdir())
                self.assertEqual(len(files), 1, "No output or shared case input may be precreated")
                path = files[0]
                self.assertEqual(path.suffix, ".pdf")
                self.assertRegex(path.stem, r"^" + scenario + r"-[0-9a-f]{32}$")
                expected = (b"This is a deliberately invalid PDF fixture.\n"
                            if scenario.endswith("Invalid") else original)
                self.assertEqual(path.read_bytes(), expected)
                inputs.append(path)
            self.assertEqual(len({path.name for path in inputs}), 6)
            self.assertEqual(len({path.parent for path in inputs}), 6)
            self.assertEqual(source.read_bytes(), original)
            before = {path: path.read_bytes() for path in inputs}
            with self.assertRaises(FileExistsError):
                prepare_pdf_result_fixtures(fixtures)
            self.assertEqual({path: path.read_bytes() for path in inputs}, before,
                             "Reusing staging must fail without replacing the inputs")

    def test_product_language_stages_independent_inputs_and_an_empty_move_destination(self):
        with tempfile.TemporaryDirectory() as temporary:
            fixtures = Path(temporary) / "Fixtures"
            source = fixtures / "Organize/Page-Order.pdf"
            source.parent.mkdir(parents=True)
            original = b"%PDF-1.4\nsynthetic source marker\n%%EOF\n"
            source.write_bytes(original)
            prepare_product_language_fixtures(fixtures)
            root = fixtures / "ProductLanguage"
            self.assertEqual({p.name for p in root.iterdir()},
                             {f"{scenario}-{language}" for language in ("en", "tr")
                              for scenario in ("Merge", "Audio", "Video", "Count", "Move")})
            for language in ("en", "tr"):
                merge = root / f"Merge-{language}"
                self.assertEqual((merge / "Companion.pdf").read_bytes(), original)
                malformed = [p for p in merge.iterdir() if p.name != "Companion.pdf"]
                self.assertEqual(len(malformed), 1)
                self.assertIn("Örnek: uzun dosya adı", malformed[0].name)
                self.assertLess(len(malformed[0].name.encode("utf-8")), 255)
                self.assertEqual(malformed[0].read_bytes(), b"This is a deliberately invalid PDF fixture.\n")
                for scenario, extension in (("Audio", ".wav"), ("Video", ".mp4")):
                    inputs = list((root / f"{scenario}-{language}").iterdir())
                    self.assertEqual(len(inputs), 1)
                    self.assertEqual(inputs[0].suffix, extension)
                    self.assertEqual(inputs[0].read_bytes(), b"")
                count = list((root / f"Count-{language}").iterdir())
                self.assertEqual(len(count), 1)
                self.assertTrue(count[0].name.startswith("words: Örnek characters lines-"))
                self.assertEqual(count[0].read_bytes(), b"one two\nthree")
                move = root / f"Move-{language}"
                self.assertEqual({p.name for p in move.iterdir()}, {"Source", "Destination"})
                moving = list((move / "Source").iterdir())
                self.assertEqual(len(moving), 1)
                self.assertEqual(moving[0].read_bytes(), b"Keep these bytes when moving the file.\n")
                self.assertEqual(list((move / "Destination").iterdir()), [])
            before = {p: p.read_bytes() for p in root.rglob("*") if p.is_file()}
            with self.assertRaises(FileExistsError):
                prepare_product_language_fixtures(fixtures)
            self.assertEqual({p: p.read_bytes() for p in root.rglob("*") if p.is_file()}, before)
            self.assertEqual(source.read_bytes(), original)

    def test_finder_drop_stages_unique_inputs_without_outputs_or_replacement(self):
        with tempfile.TemporaryDirectory() as temporary:
            fixtures = Path(temporary)
            prepare_finder_drop_fixtures(fixtures)
            root = fixtures / "FinderDrop"
            self.assertEqual({p.name for p in root.iterdir()}, {"orchard", "pistachio", "lemonade"})
            before = {}
            for folder in root.iterdir():
                files = list(folder.iterdir())
                self.assertEqual(len(files), 4)
                for role in ("Existing", "Single", "Multi-A", "Multi-B"):
                    matches = [p for p in files if p.name.startswith(role + "-")]
                    self.assertEqual(len(matches), 1)
                    self.assertRegex(matches[0].name, r"^" + role + r"-[0-9a-f]{32}\.txt$")
                    expected = f"Synthetic Finder input: {folder.name}, {role}. Preserve these bytes.\n".encode()
                    self.assertEqual(matches[0].read_bytes(), expected)
                    before[matches[0]] = expected
            with self.assertRaises(FileExistsError):
                prepare_finder_drop_fixtures(fixtures)
            self.assertEqual({p: p.read_bytes() for p in root.rglob("*") if p.is_file()}, before)


if __name__ == "__main__":
    unittest.main()
