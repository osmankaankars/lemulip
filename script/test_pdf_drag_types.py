"""Contract for the two in-process PDF reorder payloads in the shipped bundle."""
import plistlib
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parent.parent


class PDFDragTypeTests(unittest.TestCase):
    def test_custom_drag_payloads_are_declared_as_data(self):
        info = plistlib.loads((ROOT / 'Resources/Info.plist').read_bytes())
        declarations = info.get('UTExportedTypeDeclarations', [])
        exported = {item['UTTypeIdentifier']: item for item in declarations}
        self.assertEqual(len(exported), len(declarations), 'Do not declare a type twice')
        for filename in ('PDFMergeEditor.swift', 'PDFOrganizeEditor.swift'):
            source = (ROOT / 'Sources/Lemulip' / filename).read_text()
            identifier = re.search(r'static let dragType = "([^"]+)"', source).group(1)
            with self.subTest(identifier=identifier):
                self.assertIn(identifier, exported, 'SwiftUI must resolve the custom pasteboard type')
                self.assertIn('public.data', exported[identifier]['UTTypeConformsTo'])
                self.assertNotIn('UTTypeTagSpecification', exported[identifier],
                                 'Internal reorder tokens must not claim file extensions')


if __name__ == '__main__':
    unittest.main()
