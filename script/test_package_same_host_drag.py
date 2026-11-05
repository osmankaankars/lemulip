import copy
import tempfile
import unittest
from pathlib import Path
import stat
import zipfile

from package_same_host_drag import (APPLICATION_COMMIT, APPLICATION_TREE, ARCHIVE,
    ESCAPE_FAILURE, FOLDER, LIMITS, checked_archive, inventory, sha256,
    validate_observation, verify_contents, write_json)


class SameHostDragPackageTests(unittest.TestCase):
    def test_sealed_inventory_rejects_payload_or_executable_changes(self):
        for change in ("bytes", "mode", "extra", "missing", "symlink", "scope"):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as temporary:
                folder = Path(temporary) / FOLDER
                folder.mkdir()
                executable = folder / "LemulipInputCheck"
                executable.write_bytes(b"test executable")
                executable.chmod(0o755)
                write_json(folder / "provenance.json", LIMITS)
                write_json(folder / "inventory.json", inventory(folder))
                self.assertEqual(verify_contents(folder), LIMITS)
                if change == "bytes":
                    executable.write_bytes(b"changed")
                elif change == "mode":
                    executable.chmod(0o644)
                elif change == "extra":
                    (folder / "extra").write_text("unexpected")
                elif change == "missing":
                    executable.unlink()
                elif change == "symlink":
                    (folder / "link").symlink_to(executable)
                else:
                    write_json(folder / "provenance.json", {**LIMITS, "releaseReady": True})
                    (folder / "inventory.json").unlink()
                    write_json(folder / "inventory.json", inventory(folder))
                with self.assertRaises(ValueError):
                    verify_contents(folder)

    def test_zip_digest_and_unsafe_members(self):
        for kind in ("valid", "digest", "parent", "absolute", "backslash", "symlink", "duplicate"):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as temporary:
                output = Path(temporary)
                with zipfile.ZipFile(output / ARCHIVE, "w", zipfile.ZIP_DEFLATED) as zipped:
                    zipped.writestr(FOLDER + "/fixture.txt", "synthetic")
                    if kind in ("parent", "absolute", "backslash"):
                        name = {"parent": FOLDER + "/../outside", "absolute": "/outside",
                                "backslash": FOLDER + "/..\\outside"}[kind]
                        zipped.writestr(name, "outside")
                    elif kind == "symlink":
                        entry = zipfile.ZipInfo(FOLDER + "/link")
                        entry.create_system = 3
                        entry.external_attr = (stat.S_IFLNK | 0o777) << 16
                        zipped.writestr(entry, "../outside")
                    elif kind == "duplicate":
                        zipped.writestr(FOLDER + "/duplicate/", "")
                        zipped.writestr(FOLDER + "/duplicate", "conflicting file")
                digest = sha256(output / ARCHIVE)
                (output / "SHA256SUMS.txt").write_text(f"{'0' * 64 if kind == 'digest' else digest}  {ARCHIVE}\n")
                if kind == "valid":
                    self.assertEqual(checked_archive(output), digest)
                else:
                    with self.assertRaises(ValueError):
                        checked_archive(output)

    def receipt(self, mode):
        manifest = {"stagedGUI_SHA256": "a" * 64, "helperCommit": "b" * 40,
                    "observerSourceSHA256": "c" * 64, "helperSourceSHA256": "d" * 64}
        case = {"sourceCommit": APPLICATION_COMMIT, "sourceTree": APPLICATION_TREE, **manifest,
                "theme": "orchard", "targetKind": "production", "inputDriver": "CGEvent", "permissionRequested": False,
                "cleanup": {"completed": True, "errors": [], "leftButtonReportedDown": False,
                            "applicationStopped": True, "fixtureFinderWindowClosed": True, "fixedBundleRegistryEmpty": True},
                "sameHost": {"imagesCaptured": False, "screenCaptureRequired": False, "captureKind": "target-ax-and-input-state"},
                "preflight": {"accessibility": True, "postEvents": True},
                "escapeObservations": [{"phase": "before-key", "workspace": {
                    "observedFilenames": ["Existing-" + "e" * 32 + ".txt"],
                    "matchesExpectedWorkspace": True, "selectedCountLabels": ["1 Selected"]}}]}
        if mode == "ci-baseline":
            case.update(status="failed", reason=ESCAPE_FAILURE, gestureOutcomesVerified=False,
                        escapeCancellation={"matchesExpectedWorkspace": False},
                        sameHostEscape={"mode": "automatic", "syntheticEscapePosts": 2})
        else:
            case.update(status="blocked", sameHostEscape={"mode": "external", "status": "timed-out-waiting-down", "syntheticEscapePosts": 0})
        case["sameHostEscape"].update(leadInSeconds=0, dwellSeconds=0.15,
                                      externalDownTimeoutSeconds=12, externalUpTimeoutSeconds=4)
        return {"schema": 1, "mode": mode, "diagnosticOnly": True, "releaseReady": False,
                "physicalInputVerified": False, "reportRetained": True, "case": case}, manifest

    def test_expected_cancellation_failure_is_only_execution_evidence(self):
        receipt, manifest = self.receipt("ci-baseline")
        valid = validate_observation(receipt, "ci-baseline", manifest)
        self.assertTrue(valid["executionValidated"])
        self.assertFalse(valid["cancellationAcceptedByThisCheck"])
        self.assertFalse(valid["physicalInputVerified"])
        for change in ("startup", "permission", "cleanup", "identity", "initial", "missing-cancellation", "screen", "timing"):
            with self.subTest(change=change):
                altered = copy.deepcopy(receipt)
                case = altered["case"]
                if change == "startup": case["reason"] = "Target failed to start"
                elif change == "permission": case["preflight"]["accessibility"] = False
                elif change == "cleanup": case["cleanup"]["completed"] = False
                elif change == "identity": case["helperCommit"] = "f" * 40
                elif change == "initial": case["escapeObservations"][0]["workspace"]["selectedCountLabels"] = ["2 Selected"]
                elif change == "missing-cancellation": del case["escapeCancellation"]
                elif change == "screen": case["sameHost"]["imagesCaptured"] = True
                else: case["sameHostEscape"]["externalDownTimeoutSeconds"] = 120
                with self.assertRaises(ValueError):
                    validate_observation(altered, "ci-baseline", manifest)

    def test_timeout_must_be_blocked_without_synthetic_escape(self):
        receipt, manifest = self.receipt("ci-human-timeout")
        self.assertTrue(validate_observation(receipt, "ci-human-timeout", manifest)["executionValidated"])
        for key, value in (("status", "key-released"), ("syntheticEscapePosts", 1), ("mode", "automatic")):
            with self.subTest(key=key):
                altered = copy.deepcopy(receipt)
                altered["case"]["sameHostEscape"][key] = value
                with self.assertRaises(ValueError):
                    validate_observation(altered, "ci-human-timeout", manifest)


if __name__ == "__main__":
    unittest.main()
