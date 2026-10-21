#!/usr/bin/env python3
"""Guard the source rename without losing existing Mac preferences."""
import plistlib
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

class BrandingTests(unittest.TestCase):
    def test_source_and_test_paths_use_current_name(self):
        for name in ('Sources/Lemulip', 'Sources/LemulipCore', 'Sources/LemulipCLI',
                     'Sources/CLemulipArchive', 'Tests/LemulipCoreTests'):
            self.assertTrue((ROOT / name).is_dir(), name)
        for folder in ('Sources', 'Tests'):
            self.assertEqual([], [str(p.relative_to(ROOT)) for p in (ROOT / folder).rglob('*')
                                  if 'freewheel' in p.name.lower()])

    def test_package_products_are_distinct_and_current(self):
        package = (ROOT / 'Package.swift').read_text()
        self.assertNotIn('Freewheel', package)
        for name in ('LemulipCore', 'CLemulipArchive', 'LemulipApp', 'LemulipCLI', 'LemulipCoreTests'):
            self.assertIn('"' + name + '"', package)
        self.assertIn('.executable(name: "lemulip"', package)

    def test_only_the_saved_window_key_keeps_legacy_spelling_in_sources(self):
        unexpected = []
        for folder in ('Sources', 'Tests'):
            for path in (ROOT / folder).rglob('*'):
                if not path.is_file():
                    continue
                text = path.read_text()
                if path.name == 'AppController.swift':
                    text = text.replace('"FreewheelMainWindow"', '"preserved-window-key"')
                if re.search('freewheel', text, re.IGNORECASE):
                    unexpected.append(str(path.relative_to(ROOT)))
        self.assertEqual([], unexpected)

    def test_existing_bundle_and_preferences_are_preserved(self):
        with (ROOT / 'Resources/Info.plist').open('rb') as source:
            info = plistlib.load(source)
        self.assertEqual('app.freewheel.Freewheel', info['CFBundleIdentifier'])
        self.assertEqual('Lemulip', info['CFBundleExecutable'])
        app = ROOT / 'Sources/Lemulip/AppController.swift'
        self.assertTrue(app.exists())
        self.assertEqual(2, app.read_text().count('"FreewheelMainWindow"'))

if __name__ == '__main__':
    unittest.main()
