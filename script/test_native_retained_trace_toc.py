#!/usr/bin/env python3
"""Synthetic-only adversarial checks for D25 retained TOC inspection."""

import hashlib
import unittest

import native_retained_trace_toc as subject


class RetainedTraceTOCTests(unittest.TestCase):
    def test_multiple_actual_runs_and_unknown_schema_attributes_are_preserved(self):
        raw = b'''<?xml version="1.0" encoding="UTF-8"?>
<trace-toc version="synthetic">
  <run number="3" name="synthetic retained run">
    <info><summary><duration unit="display-only">00:00.500</duration></summary></info>
    <data vendor="unknown"><table schema="observed-v37" subtype="uninterpreted"/></data>
  </run>
  <run number="19"><data/></run>
</trace-toc>'''
        result = subject.inspect_toc(raw)
        self.assertTrue(result["recognizedTOC"])
        self.assertEqual(result["inputSHA256"], hashlib.sha256(raw).hexdigest())
        self.assertEqual(result["runCount"], 2)
        self.assertEqual(result["tableCount"], 1)
        self.assertEqual([run["number"] for run in result["runs"]], [3, 19])
        self.assertEqual(result["runs"][0]["observedTables"],
                         [{"schema": "observed-v37", "subtype": "uninterpreted"}])
        self.assertEqual(result["runs"][1]["observedTables"], [])
        self.assertEqual(result["runs"][0]["dataAttributes"], {"vendor": "unknown"})

    def test_displayed_time_and_metadata_do_not_establish_a_clock_or_coverage(self):
        raw = b'''<trace-toc><format version="synthetic"/><run number="1">
<info><start-date>2026-11-09T00:00:00Z</start-date><duration>15.0 seconds</duration>
<target><name>synthetic-target</name><pid>2147</pid></target></info>
<data><table schema="synthetic-clock-map"/></data></run></trace-toc>'''
        result = subject.inspect_toc(raw)
        metadata = result["runs"][0]["metadata"][0]
        self.assertEqual(metadata["children"][0]["text"], "2026-11-09T00:00:00Z")
        self.assertEqual(metadata["children"][1]["text"], "15.0 seconds")
        self.assertEqual(result["rootMetadata"][0]["attributes"], {"version": "synthetic"})
        for flag in ("toolExecutionValidatedByParser", "metadataSemanticsQualified",
                     "traceEpochEstablished", "usableClockMappingEstablished",
                     "eventTimeRangeEstablished", "samplerWindowCoverageEstablished",
                     "recordingCompletionEstablished", "activationRouteCoverageEstablished",
                     "ipcRequestChainEstablished"):
            self.assertIs(result[flag], False, flag)

    def test_schema_text_is_literal_data_and_does_not_generate_a_selector(self):
        raw = b'''<trace-toc><run number="1"><data>
<table schema="x' or @schema='other" output="$(touch forbidden)"/>
</data></run></trace-toc>'''
        result = subject.inspect_toc(raw)
        table = result["runs"][0]["observedTables"][0]
        self.assertEqual(table, {"schema": "x' or @schema='other", "output": "$(touch forbidden)"})
        self.assertIs(result["attributeStringsExecuted"], False)
        self.assertNotIn("xpath", result)
        self.assertNotIn("xpath", result["runs"][0])

    def test_run_without_data_is_a_recognized_empty_toc(self):
        result = subject.inspect_toc(b'\xef\xbb\xbf<trace-toc><run number="2"/></trace-toc>')
        self.assertEqual(result["runs"][0]["number"], 2)
        self.assertEqual(result["tableCount"], 0)
        self.assertIsNone(result["runs"][0]["dataAttributes"])
        self.assertIs(result["samplerWindowCoverageEstablished"], False)

    def test_run_number_spelling_is_retained_without_aliasing_duplicate_identity(self):
        result = subject.inspect_toc(b'<trace-toc><run number="0002"/></trace-toc>')
        self.assertEqual(result["runs"][0]["number"], 2)
        self.assertEqual(result["runs"][0]["numberText"], "0002")
        with self.assertRaisesRegex(subject.EvidenceError, "duplicate"):
            subject.inspect_toc(b'<trace-toc><run number="1"/><run number="01"/></trace-toc>')

    def test_missing_nonpositive_or_unbounded_run_identities_are_rejected(self):
        for attribute in ('', 'number=""', 'number="0"', 'number="-1"',
                          'number=" 1"', 'number="1.0"', 'number="one"',
                          'number="' + '9' * 21 + '"'):
            with self.subTest(attribute=attribute), self.assertRaises(subject.EvidenceError):
                subject.inspect_toc(('<trace-toc><run ' + attribute + '/></trace-toc>').encode())

    def test_nested_or_namespaced_run_is_not_silently_ignored(self):
        cases = (
            b'<trace-toc><wrapper><run number="1"/></wrapper></trace-toc>',
            b'<trace-toc><run number="1"><run number="2"/></run></trace-toc>',
            b'<trace-toc xmlns:q="urn:synthetic"><run number="1"/><q:run number="2"/></trace-toc>',
        )
        for raw in cases:
            with self.subTest(raw=raw), self.assertRaisesRegex(subject.EvidenceError, "run"):
                subject.inspect_toc(raw)

    def test_duplicate_run_and_ambiguous_table_containers_are_rejected(self):
        cases = (
            b'<trace-toc><run number="1"/><run number="1"/></trace-toc>',
            b'<trace-toc><run number="1"><data/><data/></run></trace-toc>',
            b'<trace-toc><run number="1" number="2"/></trace-toc>',
        )
        for raw in cases:
            with self.subTest(raw=raw), self.assertRaises(subject.EvidenceError):
                subject.inspect_toc(raw)

    def test_unrecognized_or_incomplete_envelopes_cannot_qualify(self):
        for raw in (b'<trace-query-result/>', b'<trace-toc/>', b'<error>refused</error>',
                    b'<trace-toc><run number="1">',
                    b'<trace-toc><run number="1"/></trace-toc>trailing',
                    b'<trace-toc><run number="1"/></trace-toc><other/>'):
            with self.subTest(raw=raw), self.assertRaises(subject.EvidenceError):
                subject.inspect_toc(raw)

    def test_error_elements_cannot_qualify_an_otherwise_recognized_toc(self):
        cases = (
            b'<trace-toc><run number="1"/><error>refused</error></trace-toc>',
            b'<trace-toc><run number="1"><info><error>partial</error></info></run></trace-toc>',
            b'<trace-toc xmlns:q="urn:synthetic"><run number="1"><data><q:error>refused</q:error></data></run></trace-toc>',
        )
        for raw in cases:
            with self.subTest(raw=raw), self.assertRaisesRegex(subject.EvidenceError, "tool error"):
                subject.inspect_toc(raw)

    def test_entities_and_external_document_types_are_rejected(self):
        cases = (
            b'<!DOCTYPE trace-toc SYSTEM "file:///tmp/forbidden"><trace-toc><run number="1"/></trace-toc>',
            b'<!DOCTYPE trace-toc [<!ENTITY x "expansion">]><trace-toc><run number="1">&x;</run></trace-toc>',
            b'<!ENTITY x SYSTEM "https://example.invalid/forbidden"><trace-toc><run number="1"/></trace-toc>',
        )
        for raw in cases:
            with self.subTest(raw=raw), self.assertRaisesRegex(subject.EvidenceError, "declaration"):
                subject.inspect_toc(raw)

    def test_only_utf8_without_nuls_is_accepted(self):
        xml = '<trace-toc><run number="1"/></trace-toc>'
        cases = (xml.encode('utf-16'), xml.encode() + b'\x00',
                 b'<trace-toc><run number="1">\xff</run></trace-toc>',
                 b'<?xml version="1.0" encoding="ISO-8859-1"?>' + xml.encode())
        for raw in cases:
            with self.subTest(raw=raw[:80]), self.assertRaises(subject.EvidenceError):
                subject.inspect_toc(raw)

    def test_byte_bound_is_enforced_before_xml_construction(self):
        for raw in (b'', b' ' * (subject.MAX_BYTES + 1)):
            with self.subTest(size=len(raw)), self.assertRaisesRegex(subject.EvidenceError, "byte bound"):
                subject.inspect_toc(raw)
        with self.assertRaisesRegex(subject.EvidenceError, "must be bytes"):
            subject.inspect_toc('<trace-toc><run number="1"/></trace-toc>')

    def test_depth_is_bounded_during_parsing(self):
        prefix = b'<trace-toc><run number="1">'
        suffix = b'</run></trace-toc>'
        accepted = prefix + b'<n>' * 62 + b'</n>' * 62 + suffix
        self.assertEqual(subject.inspect_toc(accepted)["observedMaximumDepth"], 64)
        rejected = prefix + b'<n>' * 63 + b'</n>' * 63 + suffix
        with self.assertRaisesRegex(subject.EvidenceError, "depth bound"):
            subject.inspect_toc(rejected)

    def test_element_count_is_bounded_during_parsing(self):
        raw = b'<trace-toc><run number="1">' + b'<n/>' * 99999 + b'</run></trace-toc>'
        with self.assertRaisesRegex(subject.EvidenceError, "element bound"):
            subject.inspect_toc(raw)


if __name__ == "__main__":
    unittest.main()
