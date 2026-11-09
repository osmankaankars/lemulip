#!/usr/bin/env python3
"""Synthetic interpretation gates for the retained-input D25 export."""

import unittest

from run_native_retained_trace_export import classify_export, validate_export_help


class ExportClassificationTests(unittest.TestCase):
    def classify(self, code=0, stdout=b'<trace-toc><run number="1"><data/></run></trace-toc>',
                 stderr=b"", **overrides):
        options = dict(input_unchanged=True, source_unchanged=True, tool_unchanged=True,
                       preflight_complete=True, synthetic=True)
        options.update(overrides)
        return classify_export({"exitCode": code, "transportComplete": True, "cleanupComplete": True},
                               {"stdout": stdout, "stderr": stderr}, **options)

    def test_nonzero_with_valid_xml_is_still_a_refusal(self):
        result = self.classify(code=1, stderr=b"Unable to open document")
        self.assertEqual(result["status"], "export-refused")
        self.assertTrue(result["diagnosticExecutionComplete"])
        self.assertFalse(result["tocExportEstablished"])
        self.assertIsNone(result["toc"])

    def test_successful_xml_does_not_establish_clock_or_event_coverage(self):
        result = self.classify()
        self.assertEqual(result["status"], "toc-exported")
        self.assertTrue(result["tocExportEstablished"])
        for field in ("nativeTOCEvidenceEstablished", "traceTableDataExportEstablished",
                      "usableClockMappingEstablished", "eventTimeRangeEstablished",
                      "samplerWindowCoverageEstablished", "phaseEstablished"):
            self.assertFalse(result[field], field)

    def test_signal_exit_is_distinguished_from_an_ordinary_tool_refusal(self):
        result = self.classify(code=-11, stderr=b"")
        self.assertEqual(result["status"], "export-terminated-by-signal")
        self.assertTrue(result["diagnosticExecutionComplete"])
        self.assertFalse(result["tocExportEstablished"])

    def test_stderr_is_preserved_as_a_warning_not_erased_or_automatic_failure(self):
        result = self.classify(stderr=b"warning: partial run")
        self.assertEqual(result["status"], "toc-exported-with-stderr")
        self.assertTrue(result["stderrPresent"])
        self.assertTrue(result["tocExportEstablished"])
        self.assertFalse(result["eventTimeRangeEstablished"])

    def test_zero_exit_with_truncated_xml_is_unqualified(self):
        result = self.classify(stdout=b'<trace-toc><run number="1">')
        self.assertEqual(result["status"], "export-output-unqualified")
        self.assertTrue(result["diagnosticExecutionComplete"])
        self.assertFalse(result["tocExportEstablished"])
        self.assertTrue(result["interpretationErrors"])

    def test_every_immutable_precondition_is_required(self):
        for key in ("input_unchanged", "source_unchanged", "tool_unchanged", "preflight_complete"):
            with self.subTest(key=key):
                result = self.classify(**{key: False})
                self.assertEqual(result["status"], "diagnostic-incomplete")
                self.assertFalse(result["tocExportEstablished"])
                self.assertFalse(result["diagnosticExecutionComplete"])

    def test_unresolved_transport_or_cleanup_cannot_qualify_even_valid_xml(self):
        for key in ("transportComplete", "cleanupComplete"):
            with self.subTest(key=key):
                receipt = {"exitCode": 0, "transportComplete": True, "cleanupComplete": True}
                receipt[key] = False
                result = classify_export(receipt,
                    {"stdout": b'<trace-toc><run number="1"/></trace-toc>', "stderr": b""},
                    input_unchanged=True, source_unchanged=True, tool_unchanged=True,
                    preflight_complete=True, synthetic=True)
                self.assertFalse(result["diagnosticExecutionComplete"])
                self.assertFalse(result["tocExportEstablished"])


class ExportHelpTests(unittest.TestCase):
    HELP = b'''usage: xctrace export [<options>] [--toc | --xpath expression]
description:
 Export given .trace using supplied query to the XML file format
options:
 --input <file> Export data from the given .trace file
 --toc Present entities to export in the table of contents form
notes:
 If output path is not specified, the export operation output will be written to the standard output.
 Table of Contents and XPath query are two separate modes and they cannot be specified together.
'''

    def test_explicit_export_contract_is_recognized(self):
        self.assertTrue(validate_export_help(self.HELP)["passed"])

    def test_record_help_or_missing_stdout_contract_cannot_authorize_export(self):
        for value in (b"usage: xctrace record --toc --input",
                      self.HELP.replace(b"standard output", b"unspecified destination"),
                      self.HELP.replace(b"--toc Present", b"example: --toc Present")):
            with self.subTest(value=value[:40]):
                with self.assertRaises(ValueError):
                    validate_export_help(value)


if __name__ == "__main__":
    unittest.main()
