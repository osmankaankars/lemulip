#!/usr/bin/env python3
"""D25: bounded structural inspection of retained xctrace TOC XML.

The caller must separately qualify the installed tool, command exit, cleanup,
and unchanged trace input. A parsed TOC is not evidence of a complete recording
or of a usable mapping between any of its displayed timestamps and another clock.
"""

from __future__ import annotations

import hashlib
import re
import xml.etree.ElementTree as ET


MAX_BYTES = 8 * 1024 * 1024
MAX_ELEMENTS = 100000
MAX_DEPTH = 64
MAX_RUN_NUMBER_DIGITS = 20


class EvidenceError(ValueError):
    pass


class _BoundedTreeBuilder(ET.TreeBuilder):
    """Reject excessive nesting/count while parsing, before building that node."""

    def __init__(self):
        super().__init__()
        self.element_count = 0
        self.depth = 0
        self.maximum_depth = 0

    def start(self, tag, attrs):
        if self.element_count >= MAX_ELEMENTS:
            raise EvidenceError("TOC XML element bound exceeded")
        if self.depth >= MAX_DEPTH:
            raise EvidenceError("TOC XML depth bound exceeded")
        self.element_count += 1
        self.depth += 1
        self.maximum_depth = max(self.maximum_depth, self.depth)
        return super().start(tag, attrs)

    def end(self, tag):
        node = super().end(tag)
        self.depth -= 1
        return node


def _primitive_node(node: ET.Element) -> dict:
    """Preserve XML-parsed strings as uninterpreted metadata, including tails."""
    return {
        "tag": node.tag,
        "attributes": dict(sorted(node.attrib.items())),
        "text": node.text,
        "tail": node.tail,
        "children": [_primitive_node(child) for child in node],
    }


def inspect_toc(data: bytes) -> dict:
    """Inspect a complete UTF-8 trace-toc; return facts or raise EvidenceError.

    Multiple actual runs and empty table containers are supported. Run number
    text is retained separately from its integer identity. Attribute strings
    are never interpreted as XPath, shell text, schemas with known semantics,
    paths to open, native timestamps, or executable instructions.
    """
    if not isinstance(data, bytes):
        raise EvidenceError("TOC input must be bytes")
    if not data or len(data) > MAX_BYTES:
        raise EvidenceError("TOC input is empty or exceeds its byte bound")
    try:
        text = data.decode("utf-8-sig")
    except UnicodeDecodeError as error:
        raise EvidenceError("TOC XML is not UTF-8") from error
    if "\x00" in text or re.search(r"<!\s*(?:DOCTYPE|ENTITY)\b", text, re.IGNORECASE):
        raise EvidenceError("TOC XML contains a NUL, document type or entity declaration")
    declaration = re.match(r"<\?xml\s+[^?]*\?>", text)
    if declaration is not None:
        encoding = re.search(r"\bencoding\s*=\s*(['\"])([^'\"]+)\1", declaration.group())
        if encoding is not None and encoding.group(2).lower() != "utf-8":
            raise EvidenceError("TOC XML declares an encoding other than UTF-8")
    target = _BoundedTreeBuilder()
    parser = ET.XMLParser(target=target)
    try:
        # Chunked feeding lets the count/depth guard act during construction.
        for offset in range(0, len(text), 65536):
            parser.feed(text[offset:offset + 65536])
        root = parser.close()
    except (ET.ParseError, LookupError) as error:
        raise EvidenceError("TOC export is not complete, well-formed XML") from error
    if root.tag != "trace-toc":
        raise EvidenceError("TOC export has an unrecognized root")
    if any(node.tag.rsplit("}", 1)[-1] == "error" for node in root.iter()):
        raise EvidenceError("TOC export contains a tool error element")
    direct_runs = root.findall("run")
    all_run_shapes = [node for node in root.iter()
                      if node.tag.rsplit("}", 1)[-1] == "run"]
    if not direct_runs or all_run_shapes != direct_runs:
        raise EvidenceError("TOC has no direct run or has an unexpected/nested run")
    identities = set()
    runs = []
    for run in direct_runs:
        number_text = run.get("number")
        if (not isinstance(number_text, str)
                or not re.fullmatch(r"[0-9]{1," + str(MAX_RUN_NUMBER_DIGITS) + r"}", number_text)):
            raise EvidenceError("TOC run lacks a bounded positive decimal identity")
        number = int(number_text)
        if number <= 0 or number in identities:
            raise EvidenceError("TOC has a non-positive or duplicate run identity")
        identities.add(number)
        data_nodes = run.findall("data")
        if len(data_nodes) > 1:
            raise EvidenceError("TOC run has ambiguous table containers")
        data_node = data_nodes[0] if data_nodes else None
        tables = [] if data_node is None else data_node.findall("table")
        runs.append({
            "number": number,
            "numberText": number_text,
            "attributes": dict(sorted(run.attrib.items())),
            "tableCount": len(tables),
            "observedTables": [dict(sorted(table.attrib.items())) for table in tables],
            "tableChildrenObserved": any(len(table) > 0 or bool(table.text) for table in tables),
            "metadata": [_primitive_node(child) for child in run if child.tag != "data"],
            "dataAttributes": None if data_node is None else dict(sorted(data_node.attrib.items())),
            "dataMetadata": [] if data_node is None else
                            [_primitive_node(child) for child in data_node if child.tag != "table"],
        })
    return {
        "schema": 1,
        "kind": "D25-retained-trace-toc-structure",
        "recognizedTOC": True,
        "inputBytes": len(data),
        "inputSHA256": hashlib.sha256(data).hexdigest(),
        "rootAttributes": dict(sorted(root.attrib.items())),
        "rootMetadata": [_primitive_node(child) for child in root if child.tag != "run"],
        "runCount": len(runs),
        "tableCount": sum(run["tableCount"] for run in runs),
        "runs": runs,
        "parserBounds": {"maximumBytes": MAX_BYTES, "maximumElements": MAX_ELEMENTS,
                         "maximumDepth": MAX_DEPTH, "maximumRunNumberDigits": MAX_RUN_NUMBER_DIGITS},
        "observedElementCount": target.element_count,
        "observedMaximumDepth": target.maximum_depth,
        "projectionScope": "Direct run/data/table attributes; other container metadata is uninterpreted XML. Table children remain in the retained raw XML.",
        "attributeStringsExecuted": False,
        "toolExecutionValidatedByParser": False,
        "metadataSemanticsQualified": False,
        "traceEpochEstablished": False,
        "usableClockMappingEstablished": False,
        "eventTimeRangeEstablished": False,
        "samplerWindowCoverageEstablished": False,
        "recordingCompletionEstablished": False,
        "activationRouteCoverageEstablished": False,
        "ipcRequestChainEstablished": False,
    }
