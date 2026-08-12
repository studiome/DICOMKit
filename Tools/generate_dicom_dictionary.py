#!/usr/bin/env python3
"""Generate the fixed-VM DICOM VR dictionary from an official PS3.6 XML file.

Usage:
  python3 Tools/generate_dicom_dictionary.py part06.xml DICOMKit/DICOMDictionary.generated.swift

The output deliberately contains only exact public tags with one unambiguous
VR. Entries such as ``OB or OW`` and repeating ``xx`` tags require context and
remain in DICOMDictionary's hand-maintained overrides.
"""

import re
import sys
import xml.etree.ElementTree as etree
from pathlib import Path


VALID_VRS = {
    "AE", "AS", "AT", "CS", "DA", "DS", "DT", "FD", "FL", "IS", "LO", "LT",
    "OB", "OD", "OF", "OL", "OV", "OW", "PN", "SH", "SL", "SQ", "SS", "ST",
    "SV", "TM", "UC", "UI", "UL", "UN", "UR", "US", "UT", "UV",
}
TAG = re.compile(r"^\(([0-9A-F]{4}),([0-9A-F]{4})\)$")


def text(element):
    return "".join(element.itertext()).replace("\u200b", "").strip()


def main(source, destination):
    root = etree.parse(source).getroot()
    table = next(element for element in root.iter() if element.tag.endswith("table") and element.attrib.get("{http://www.w3.org/XML/1998/namespace}id") == "table_6-1")
    entries = []
    for row in table.iter():
        if not row.tag.endswith("tr"):
            continue
        cells = [text(cell) for cell in row if cell.tag.endswith("td")]
        if len(cells) < 4:
            continue
        match = TAG.fullmatch(cells[0])
        vr = cells[3]
        if match and vr in VALID_VRS:
            entries.append((int(match.group(1), 16), int(match.group(2), 16), vr))

    entries.sort()
    output = [
        "// Generated from DICOM PS3.6 2025a Table 6-1 by Tools/generate_dicom_dictionary.py.",
        "// Do not edit manually; regenerate from the pinned PS3.6 source XML.",
        "extension DICOMDictionary {",
        "    static let generatedEntries: [DICOMTag: DICOMVR] = {",
        "        var entries: [DICOMTag: DICOMVR] = [:]",
        "        entries.reserveCapacity(5_100)",
        '        for row in generatedTable.split(separator: "\\n") {',
        '            let columns = row.split(separator: " ")',
        "            guard columns.count == 2, let rawTag = UInt32(columns[0], radix: 16), let vr = DICOMVR(rawValue: String(columns[1])) else { continue }",
        "            entries[DICOMTag(group: UInt16(rawTag >> 16), element: UInt16(rawTag & 0xFFFF))] = vr",
        "        }",
        "        return entries",
        "    }()",
        "",
        '    private static let generatedTable = """',
    ]
    output.extend(f"{group:04X}{element:04X} {vr}" for group, element, vr in entries)
    output.extend(['"""', "}", ""])
    Path(destination).write_text("\n".join(output), encoding="utf-8")
    print(f"wrote {len(entries)} entries to {destination}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: generate_dicom_dictionary.py part06.xml output.swift")
    main(sys.argv[1], sys.argv[2])
