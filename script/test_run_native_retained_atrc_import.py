#!/usr/bin/env python3
"""Portable D27 gates; synthetic fixtures never run native import or decode trace data."""

from __future__ import annotations

import copy
from pathlib import Path
import tempfile
import unittest
from unittest import mock

import run_native_retained_atrc_import as subject


TEMPLATES = b"== Standard Templates ==\nAudio System Trace\nSystem Trace\nTime Profiler\n"


class ImportClassificationTests(unittest.TestCase):
    def classify(self, *, code=0, stderr=b"", receipt_overrides=None, output_overrides=None, **gates):
        receipt = {"exitCode": code, "transportComplete": True, "cleanupComplete": True,
                   "outputBoundsPass": True}
        receipt.update(receipt_overrides or {})
        output = {"retentionComplete": True, "inventoryComplete": True,
                  "outputBoundsPass": True, "newAnalysisDocumentObserved": True,
                  "archive": {"name": "derived.trace.zip", "bytes": 100,
                              "sha256": "a" * 64, "crcAndSHA256Verified": True}}
        output.update(output_overrides or {})
        options = dict(input_unchanged=True, source_unchanged=True, tool_unchanged=True,
                       preflight_complete=True, synthetic=True)
        options.update(gates)
        return subject.classify_import(receipt, {"stdout": b"synthetic import result\n", "stderr": stderr},
                                       output, **options)

    def assert_no_extended_claims(self, result):
        for key in ("retainedPayloadAcceptanceEstablished", "nativeImportEvidenceEstablished",
                    "ATRCFormatAcceptanceEstablished", "importSelectionSemanticsEstablished",
                    "derivedDocumentReadableEstablished", "recordingCompletionEstablished",
                    "traceTableDataExportEstablished", "usableClockMappingEstablished",
                    "eventTimeRangeEstablished", "samplerWindowCoverageEstablished", "phaseEstablished",
                    "activationRouteCoverageEstablished", "ipcRequestChainEstablished"):
            self.assertFalse(result[key], key)

    def test_success_requires_a_retained_document_but_never_qualifies_events_or_native_fixture(self):
        result = self.classify()
        self.assertEqual(result["status"], "import-accepted")
        self.assertTrue(result["diagnosticExecutionComplete"])
        self.assertTrue(result["importAcceptedWithSelection"])
        self.assertTrue(result["derivedAnalysisDocumentObserved"])
        self.assert_no_extended_claims(result)

    def test_zero_exit_without_nonempty_document_remains_unqualified(self):
        result = self.classify(output_overrides={"newAnalysisDocumentObserved": False, "archive": None})
        self.assertEqual(result["status"], "import-output-unqualified")
        self.assertTrue(result["diagnosticExecutionComplete"])
        self.assertFalse(result["importAcceptedWithSelection"])
        self.assert_no_extended_claims(result)

    def test_nonzero_with_a_new_document_is_still_a_refusal(self):
        result = self.classify(code=10, stderr=b"synthetic rejection\n")
        self.assertEqual(result["status"], "import-refused")
        self.assertTrue(result["diagnosticExecutionComplete"])
        self.assertFalse(result["importAcceptedWithSelection"])
        self.assert_no_extended_claims(result)

    def test_document_flag_without_a_verified_retained_archive_is_unqualified(self):
        good = {"name": "derived.trace.zip", "bytes": 100, "sha256": "a" * 64,
                "crcAndSHA256Verified": True}
        variants = [None, {}, {**good, "bytes": True}, {**good, "bytes": 0},
                    {**good, "sha256": "not-a-digest"}, {**good, "name": "other.zip"},
                    {**good, "crcAndSHA256Verified": False}]
        for archive in variants:
            with self.subTest(archive=archive):
                result = self.classify(output_overrides={"archive": archive})
                self.assertEqual(result["status"], "import-output-unqualified")
                self.assertTrue(result["diagnosticExecutionComplete"])
                self.assertFalse(result["importAcceptedWithSelection"])

    def test_refusal_without_output_is_a_finite_result(self):
        result = self.classify(code=1, output_overrides={"newAnalysisDocumentObserved": False, "archive": None})
        self.assertEqual(result["status"], "import-refused")
        self.assertTrue(result["diagnosticExecutionComplete"])
        self.assert_no_extended_claims(result)

    def test_signal_exit_does_not_infer_the_failure_cause(self):
        result = self.classify(code=-11)
        self.assertEqual(result["status"], "import-terminated-by-signal")
        self.assertTrue(result["diagnosticExecutionComplete"])
        self.assertFalse(result["commandExitedSuccessfully"])
        self.assert_no_extended_claims(result)

    def test_warning_stderr_is_retained_without_erasing_a_completed_import(self):
        result = self.classify(stderr=b"synthetic partial-input warning\n")
        self.assertEqual(result["status"], "import-accepted-with-stderr")
        self.assertTrue(result["stderrPresent"])
        self.assert_no_extended_claims(result)

    def test_missing_or_noninteger_exit_cannot_complete(self):
        for code in (None, False, True, "0", 0.0):
            with self.subTest(code=code):
                result = self.classify(code=code)
                self.assertEqual(result["status"], "diagnostic-incomplete")
                self.assertFalse(result["diagnosticExecutionComplete"])
                self.assertFalse(result["commandExitedSuccessfully"])

    def test_every_immutable_gate_is_required(self):
        for key in ("input_unchanged", "source_unchanged", "tool_unchanged", "preflight_complete"):
            with self.subTest(key=key):
                result = self.classify(**{key: False})
                self.assertFalse(result["diagnosticExecutionComplete"])
                self.assertFalse(result["importAcceptedWithSelection"])

    def test_failed_transport_cleanup_or_observed_output_bound_cannot_be_promoted(self):
        for key in ("transportComplete", "cleanupComplete", "outputBoundsPass"):
            with self.subTest(key=key):
                result = self.classify(receipt_overrides={key: False})
                self.assertEqual(result["status"], "diagnostic-incomplete")
                self.assertFalse(result["importAcceptedWithSelection"])

    def test_incomplete_final_inventory_retention_or_bound_cannot_be_promoted(self):
        for key in ("retentionComplete", "inventoryComplete", "outputBoundsPass"):
            with self.subTest(key=key):
                result = self.classify(output_overrides={key: False})
                self.assertFalse(result["diagnosticExecutionComplete"])
                self.assertFalse(result["importAcceptedWithSelection"])

    def test_truthy_nonboolean_gate_does_not_count_as_positive_evidence(self):
        for value in (1, "true", {"passed": True}):
            with self.subTest(value=value):
                result = self.classify(output_overrides={"retentionComplete": value})
                self.assertFalse(result["diagnosticExecutionComplete"])


class TemplateAvailabilityTests(unittest.TestCase):
    def test_exact_name_is_bound_to_the_standard_section_and_raw_identity(self):
        result = subject.inspect_templates(TEMPLATES)
        self.assertTrue(result["freshSameRunAvailabilityEstablished"])
        self.assertEqual(result["selectedTemplate"], "System Trace")
        self.assertEqual(result["matchingLine"], 3)
        self.assertEqual(result["identity"], subject.byte_identity(TEMPLATES))
        self.assertFalse(result["templateBytesOrInstrumentMembershipEstablished"])

    def test_related_names_or_prose_cannot_substitute_for_the_exact_template(self):
        variants = (TEMPLATES.replace(b"System Trace\nTime", b"Metal System Trace\nTime"),
                    b"== Standard Templates ==\nSystem Trace is available\n",
                    b"== Standard Templates ==\n System Trace\n",
                    b"== Standard Templates ==\nsystem trace\n")
        for raw in variants:
            with self.subTest(raw=raw):
                with self.assertRaises(ValueError):
                    subject.inspect_templates(raw)

    def test_missing_duplicate_or_nonstandard_section_is_not_unambiguous_availability(self):
        variants = (b"System Trace\n", TEMPLATES + b"System Trace\n",
                    TEMPLATES + b"== Standard Templates ==\n",
                    b"== Standard Templates ==\nTime Profiler\n== Custom Templates ==\nSystem Trace\n")
        for raw in variants:
            with self.subTest(raw=raw):
                with self.assertRaises(ValueError):
                    subject.inspect_templates(raw)

    def test_binary_control_error_or_empty_listing_is_rejected(self):
        variants = (b"", b"\xff" + TEMPLATES, b"\x00" + TEMPLATES, b"\x1b[31m" + TEMPLATES,
                    b"error: synthetic failure\n" + TEMPLATES)
        for raw in variants:
            with self.subTest(raw=raw):
                with self.assertRaises((ValueError, UnicodeError)):
                    subject.inspect_templates(raw)


class ProtectedInputTests(unittest.TestCase):
    def fixture(self, root):
        # Match prepare_input's canonical existing-parent contract even when
        # the host temporary directory is reached through a filesystem alias.
        trace = root.resolve(strict=True) / "recording.trace"
        raw = trace / subject.RAW_MEMBER
        raw.parent.mkdir(parents=True)
        # This tests the contract between the frozen full-hash preparer and the
        # raw-member selector. No fixture represents a real accepted payload.
        raw.write_bytes(b"synthetic path fixture")
        entries = [{"path": ".", "kind": "directory", "mode": 0o500},
                   {"path": "Trace1.run", "kind": "directory", "mode": 0o500},
                   {"path": "Trace1.run/Attachments", "kind": "directory", "mode": 0o500},
                   {"path": subject.RAW_MEMBER, "kind": "file", "mode": 0o400, **subject.RAW_IDENTITY},
                   {"path": "Trace1.run/RunIssues.storedata", "kind": "file", "mode": 0o400}]
        return {"tracePath": str(trace), "manifest": {"entries": entries, "fileCount": 2,
                "directoryCount": 3, "expandedBytes": subject.INNER_IDENTITY["expandedBytes"]}}

    def test_selects_only_the_pinned_raw_member_from_a_full_preparer_manifest(self):
        with tempfile.TemporaryDirectory() as directory:
            prepared = self.fixture(Path(directory))
            selected = subject.inspect_prepared_input(prepared)
            self.assertEqual(selected["path"], str(Path(prepared["tracePath"]) / subject.RAW_MEMBER))
            self.assertEqual(selected["sha256"], subject.RAW_IDENTITY["sha256"])
            self.assertEqual(selected["mode"], 0o400)
            self.assertFalse(selected["retainedCodeExecuted"])

    def test_directory_alias_fixture_matches_the_preparers_canonical_parent_contract(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve(strict=True)
            actual = root / "actual"
            actual.mkdir()
            alias = root / "alias"
            alias.symlink_to(actual, target_is_directory=True)
            prepared = self.fixture(alias)
            selected = subject.inspect_prepared_input(prepared)
            self.assertEqual(Path(prepared["tracePath"]), actual / "recording.trace")
            self.assertEqual(Path(selected["path"]), actual / "recording.trace" / subject.RAW_MEMBER)
            # The preparer normalizes existing parent aliases. The production
            # selector must still reject a manifest that violates that contract.
            noncanonical = copy.deepcopy(prepared)
            noncanonical["tracePath"] = str(alias / "recording.trace")
            with self.assertRaisesRegex(ValueError, "canonical regular-file location"):
                subject.inspect_prepared_input(noncanonical)

    def test_changed_raw_identity_or_missing_member_prevents_selection(self):
        with tempfile.TemporaryDirectory() as directory:
            original = self.fixture(Path(directory))
            for field, value in (("bytes", 1), ("sha256", "0" * 64), ("path", "renamed.atrc")):
                with self.subTest(field=field):
                    prepared = copy.deepcopy(original)
                    prepared["manifest"]["entries"][3][field] = value
                    with self.assertRaises(ValueError):
                        subject.inspect_prepared_input(prepared)

    def test_any_writable_member_or_directory_prevents_selection(self):
        with tempfile.TemporaryDirectory() as directory:
            original = self.fixture(Path(directory))
            for index in range(len(original["manifest"]["entries"])):
                with self.subTest(index=index):
                    prepared = copy.deepcopy(original)
                    prepared["manifest"]["entries"][index]["mode"] |= 0o200
                    with self.assertRaises(ValueError):
                        subject.inspect_prepared_input(prepared)

    def test_symlink_replacement_cannot_substitute_for_the_canonical_raw_path(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            prepared = self.fixture(root)
            raw = Path(prepared["tracePath"]) / subject.RAW_MEMBER
            alternative = root / "other.atrc"
            alternative.write_bytes(b"synthetic other")
            raw.unlink()
            raw.symlink_to(alternative)
            with self.assertRaises(ValueError):
                subject.inspect_prepared_input(prepared)


class SourceRetentionTests(unittest.TestCase):
    def test_workflow_is_retained_visibly_with_its_original_git_path_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            repo, artifact = root / "repo", root / "artifact"
            relative = ".github/workflows/fixture.yml"
            source = repo / relative
            source.parent.mkdir(parents=True)
            source.write_bytes(b"name: synthetic D27 workflow\n")
            with mock.patch.object(subject, "SOURCE_PATHS", (relative,)):
                before = subject.source_snapshot(repo, artifact)
                after = subject.source_snapshot(repo)
            self.assertEqual(before, after)
            self.assertEqual(before[relative], subject.byte_identity(source.read_bytes()))
            copy_path = artifact / subject.retained_source_path(relative)
            self.assertEqual(copy_path.read_bytes(), source.read_bytes())
            self.assertFalse(any(part.startswith(".") for part in copy_path.relative_to(artifact).parts))

    def test_source_change_is_detected_and_existing_copy_cannot_be_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "fixture.py"
            source.write_bytes(b"original\n")
            with mock.patch.object(subject, "SOURCE_PATHS", ("fixture.py",)):
                before = subject.source_snapshot(root, root / "retained")
                source.write_bytes(b"changed\n")
                self.assertNotEqual(before, subject.source_snapshot(root))
                with self.assertRaises(FileExistsError):
                    subject.source_snapshot(root, root / "retained")

    def test_ambiguous_visible_copy_mapping_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            with mock.patch.object(subject, "SOURCE_PATHS", (".github/workflows/x.yml", "workflows/x.yml")):
                with self.assertRaises(ValueError):
                    subject.source_snapshot(Path(directory))


if __name__ == "__main__":
    unittest.main()
