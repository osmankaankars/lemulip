#!/usr/bin/env python3
"""Portable classification checks; no native help command or trace input runs."""

from __future__ import annotations

from pathlib import Path
import tempfile
import unittest
from unittest import mock

import collect_native_atrc_import_contract as subject


HELP = b"""usage: xctrace import [<options>]

description:
    Synthetic help fixture for classification tests.
options:
    --input <file>       Import a supported file.
    --output <path>      Create a separate trace.
    --template <name>    Select a template.
"""


class ImportHelpClassificationTests(unittest.TestCase):
    def classify(self, *, stdout=HELP, stderr=b"", code=0, transport=True,
                 cleanup=True, source=True, tool=True, preflight=True):
        return subject.classify_help(
            {"exitCode": code, "transportComplete": transport, "cleanupComplete": cleanup},
            {"stdout": stdout, "stderr": stderr}, source_unchanged=source,
            tool_unchanged=tool, preflight_complete=preflight, synthetic=True,
        )

    def assert_no_data_claims(self, result):
        for key in ("ATRCFormatAcceptanceEstablished", "retainedPayloadAcceptanceEstablished",
                    "importSelectionSemanticsEstablished", "recordingCompletionEstablished",
                    "usableClockMappingEstablished", "eventTimeRangeEstablished",
                    "samplerWindowCoverageEstablished", "phaseEstablished",
                    "activationRouteCoverageEstablished", "ipcRequestChainEstablished"):
            self.assertFalse(result[key], key)

    def test_recognized_help_is_separate_from_payload_and_native_test_evidence(self):
        result = self.classify()
        self.assertEqual(result["status"], "help-collected")
        self.assertTrue(result["diagnosticExecutionComplete"])
        self.assertTrue(result["helpGrammarRecognized"])
        self.assertFalse(result["nativeHelpEvidenceEstablished"])
        self.assert_no_data_claims(result)

    def test_stderr_is_retained_without_silently_discarding_valid_help(self):
        result = self.classify(stderr=b"synthetic warning\n")
        self.assertEqual(result["status"], "help-collected")
        self.assertTrue(result["stderrPresent"])
        self.assert_no_data_claims(result)

    def test_finite_nonzero_does_not_qualify_even_recognizable_stdout(self):
        result = self.classify(code=10, stderr=b"synthetic refusal\n")
        self.assertEqual(result["status"], "help-refused")
        self.assertTrue(result["diagnosticExecutionComplete"])
        self.assertFalse(result["helpGrammarRecognized"])
        self.assertIsNone(result["helpText"])
        self.assert_no_data_claims(result)

    def test_signal_exit_is_preserved_without_cause_inference(self):
        result = self.classify(code=-11)
        self.assertEqual(result["status"], "help-terminated-by-signal")
        self.assertTrue(result["diagnosticExecutionComplete"])
        self.assertFalse(result["commandExitedSuccessfully"])

    def test_absent_or_noninteger_exit_cannot_complete(self):
        for code in (None, False, True, "0", 0.0):
            with self.subTest(code=code):
                result = self.classify(code=code)
                self.assertEqual(result["status"], "diagnostic-incomplete")
                self.assertFalse(result["diagnosticExecutionComplete"])

    def test_failed_transport_cannot_be_repaired_by_successful_help_or_cleanup(self):
        result = self.classify(transport=False)
        self.assertFalse(result["diagnosticExecutionComplete"])
        self.assertFalse(result["helpGrammarRecognized"])

    def test_failed_cleanup_prevents_completion(self):
        result = self.classify(cleanup=False)
        self.assertEqual(result["status"], "diagnostic-incomplete")
        self.assertFalse(result["helpGrammarRecognized"])

    def test_changed_tool_prevents_completion(self):
        result = self.classify(tool=False)
        self.assertFalse(result["diagnosticExecutionComplete"])
        self.assertFalse(result["helpGrammarRecognized"])

    def test_preflight_failure_prevents_later_help_qualification(self):
        result = self.classify(preflight=False)
        self.assertFalse(result["diagnosticExecutionComplete"])
        self.assertFalse(result["helpGrammarRecognized"])

    def test_invalid_utf8_is_finite_but_unqualified(self):
        result = self.classify(stdout=b"\xff" + HELP)
        self.assertEqual(result["status"], "help-output-unqualified")
        self.assertTrue(result["diagnosticExecutionComplete"])
        self.assertTrue(result["interpretationErrors"])

    def test_binary_or_terminal_control_sequences_are_unqualified(self):
        for extra in (b"\x00", b"\x1b[31m", b"\b"):
            with self.subTest(extra=extra):
                result = self.classify(stdout=HELP + extra)
                self.assertEqual(result["status"], "help-output-unqualified")

    def test_multiple_usage_blocks_are_ambiguous(self):
        for extra in (b"usage: xctrace export [<options>]\n", b"usage: xctrace import [<options>]\n"):
            with self.subTest(extra=extra):
                result = self.classify(stdout=HELP + extra)
                self.assertEqual(result["status"], "help-output-unqualified")

    def test_duplicate_option_definition_is_ambiguous(self):
        for extra in (b"--input <path> alternative\n", b"--output <file> alternative\n"):
            with self.subTest(extra=extra):
                result = self.classify(stdout=HELP + extra)
                self.assertEqual(result["status"], "help-output-unqualified")

    def test_wrong_command_missing_option_or_error_envelope_is_unqualified(self):
        variants = (b"", HELP.replace(b"xctrace import", b"xctrace export"),
                    HELP.replace(b"--input <file>", b"--other <file>"),
                    HELP.replace(b"--output <path>", b"--other <path>"),
                    b"error: synthetic failure\n" + HELP)
        for raw in variants:
            with self.subTest(raw=raw):
                result = self.classify(stdout=raw)
                self.assertEqual(result["status"], "help-output-unqualified")

    def test_literal_atrc_lines_never_automatically_qualify_acceptance(self):
        for sentence in (b"ATRC is supported by this synthetic fixture.\n",
                         b"ATRC is not supported by this synthetic fixture.\n"):
            with self.subTest(sentence=sentence):
                result = self.classify(stdout=HELP + sentence)
                self.assertEqual(result["status"], "help-collected")
                literal = result["helpText"]["literalObservations"]["ATRC"]
                self.assertEqual(literal["matchingLineCount"], 1)
                self.assertEqual(literal["retainedLines"][0]["text"], sentence.decode().rstrip())
                self.assert_no_data_claims(result)

    def test_real_source_byte_change_blocks_help_qualification(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            source = repo / "fixture.py"
            source.write_bytes(b"before\n")
            with mock.patch.object(subject, "SOURCE_PATHS", ("fixture.py",)):
                before = subject.source_snapshot(repo)
                source.write_bytes(b"after\n")
                after = subject.source_snapshot(repo)
            result = self.classify(source=before == after)
            self.assertEqual(result["status"], "diagnostic-incomplete")
            self.assertFalse(result["diagnosticExecutionComplete"])

    def test_workflow_copy_is_retained_visibly_under_original_source_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            repo, artifact = root / "repo", root / "artifact"
            relative = ".github/workflows/fixture.yml"
            source = repo / relative
            source.parent.mkdir(parents=True)
            source.write_bytes(b"name: synthetic workflow\n")
            with mock.patch.object(subject, "SOURCE_PATHS", (relative,)):
                before = subject.source_snapshot(repo, artifact)
                after = subject.source_snapshot(repo)
            self.assertEqual(before, after)
            self.assertIn(relative, before)
            copies = [p for p in artifact.rglob("*") if p.is_file()]
            self.assertEqual(len(copies), 1)
            self.assertFalse(any(part.startswith(".") for part in copies[0].relative_to(artifact).parts))
            self.assertEqual(copies[0].read_bytes(), source.read_bytes())


if __name__ == "__main__":
    unittest.main()
