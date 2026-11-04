import tempfile
import unittest
from pathlib import Path
import stat
import zipfile

from package_drag_repro import (ARCHIVE, FOLDER, LIMITS, checked_archive, inventory,
                                sha256, verify_contents, write_json)


class DragReproPackageTests(unittest.TestCase):
    def test_inventory_detects_bytes_modes_membership_and_links(self):
        for change in ("bytes", "mode", "extra", "missing", "symlink"):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as temporary:
                payload = Path(temporary) / FOLDER
                payload.mkdir()
                launcher = payload / "Kontrolu-Baslat.command"
                launcher.write_text("#!/bin/bash\nexit 0\n")
                launcher.chmod(0o755)
                write_json(payload / "provenance.json", LIMITS)
                write_json(payload / "inventory.json", inventory(payload))
                self.assertEqual(verify_contents(payload), LIMITS)
                if change == "bytes":
                    launcher.write_text("#!/bin/bash\nexit 1\n")
                elif change == "mode":
                    launcher.chmod(0o644)
                elif change == "extra":
                    (payload / "unexpected.txt").write_text("extra")
                elif change == "missing":
                    launcher.unlink()
                else:
                    (payload / "linked").symlink_to(launcher)
                with self.assertRaises(ValueError):
                    verify_contents(payload)

    def test_inventory_cannot_claim_acceptance_or_physical_escape_passed(self):
        for key, value in (("diagnosticOnly", False), ("acceptanceXCTestExecuted", True),
                           ("physicalEscape", "PASS"), ("C12", "PASS")):
            with self.subTest(key=key), tempfile.TemporaryDirectory() as temporary:
                payload = Path(temporary)
                write_json(payload / "provenance.json", {**LIMITS, key: value})
                write_json(payload / "inventory.json", inventory(payload))
                with self.assertRaisesRegex(ValueError, "Diagnostic-only"):
                    verify_contents(payload)

    def test_archive_checks_digest_and_rejects_entries_outside_regular_payload(self):
        for kind in ("valid", "digest", "parent", "absolute", "backslash", "symlink", "duplicate"):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as temporary:
                output = Path(temporary)
                with zipfile.ZipFile(output / ARCHIVE, "w") as zipped:
                    zipped.writestr(FOLDER + "/fixture.txt", "synthetic fixture")
                    if kind == "parent":
                        zipped.writestr(FOLDER + "/../outside.txt", "outside")
                    elif kind == "absolute":
                        zipped.writestr("/outside.txt", "outside")
                    elif kind == "backslash":
                        zipped.writestr(FOLDER + "/..\\outside.txt", "outside")
                    elif kind == "symlink":
                        link = zipfile.ZipInfo(FOLDER + "/linked")
                        link.create_system = 3
                        link.external_attr = (stat.S_IFLNK | 0o777) << 16
                        zipped.writestr(link, "../outside.txt")
                    elif kind == "duplicate":
                        zipped.writestr(FOLDER + "/duplicate/", "")
                        zipped.writestr(FOLDER + "/duplicate", "conflicting file")
                digest = sha256(output / ARCHIVE)
                (output / "SHA256SUMS.txt").write_text(
                    f"{'0' * 64 if kind == 'digest' else digest}  {ARCHIVE}\n")
                if kind == "valid":
                    self.assertEqual(checked_archive(output), digest)
                else:
                    with self.assertRaises(ValueError):
                        checked_archive(output)


if __name__ == "__main__":
    unittest.main()
