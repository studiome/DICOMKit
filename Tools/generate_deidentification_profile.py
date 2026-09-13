#!/usr/bin/env python3
"""Generate the PS3.15 Basic Application Level Confidentiality Profile table
(Table E.1-1) from an official PS3.15 DocBook XML file.

Usage:
  python3 Tools/generate_deidentification_profile.py part15.xml DICOMKit/DICOMDeidentification.generated.swift

Table E.1-1 has 15 columns: Attribute Name, Tag, Retd., In Std. Comp. IOD,
Basic Prof., and ten confidentiality-option columns (Rtn. Safe Priv. Opt.,
Rtn. UIDs Opt., Rtn. Dev. Id. Opt., Rtn. Inst. Id. Opt., Rtn. Pat. Chars.
Opt., Rtn. Long. Full Dates Opt., Rtn. Long. Modif. Dates Opt., Clean Desc.
Opt., Clean Struct. Cont. Opt., Clean Graph. Opt.), in that order. Each row
is emitted as the tag plus the raw Basic Profile action code (`D`, `Z`,
`X`, `K`, `C`, `U`, or a slashed combination such as `X/Z/D`) plus, for
every non-empty option column, that column's override code keyed by its
0-based index in the list above (0 = Rtn. Safe Priv. Opt. ... 9 = Clean
Graph. Opt.). Interpreting those codes into ``DICOMDeidentificationAction``
values is left to DICOMKit's Swift model (``DICOMConfidentialityProfile``),
not to this generator, so this script stays a straight transcription of
the table.

Two kinds of rows do not fit a plain `DICOMTag` key:

* Repeating-group ("xx") tags, e.g. ``(50xx,xxxx)`` Curve Data. There are
  exactly three of these in the 2025a table. Each is emitted as a
  `MaskedEntry` (a group/element mask and value, matched by nibble) rather
  than being dropped.
* The single "Private Attributes" row, whose Tag column is the prose
  placeholder ``(gggg,eeee) where gggg is odd`` rather than a concrete or
  maskable tag. This one row is dropped; the count of dropped rows is
  printed so the omission is never silent. (DICOMAnonymizer's
  `removePrivateTags` flag, on by default, already removes every private
  (odd-group) element independently of this table, which is the Basic
  Profile's `X` action for this row in all but the Retain Safe Private
  case — and DICOMKit maps that case's `C` action conservatively, see
  DICOMDeidentificationModel.swift, so the net behavior matches anyway.)
"""

import re
import sys
import xml.etree.ElementTree as etree
from pathlib import Path

TAG = re.compile(r"^\(([0-9A-Fa-fx]{4}),([0-9A-Fa-fx]{4})\)$")

# Column order matches Table E.1-1's ten option columns, left to right.
OPTION_COLUMN_NAMES = [
    "Rtn. Safe Priv. Opt.",
    "Rtn. UIDs Opt.",
    "Rtn. Dev. Id. Opt.",
    "Rtn. Inst. Id. Opt.",
    "Rtn. Pat. Chars. Opt.",
    "Rtn. Long. Full Dates Opt.",
    "Rtn. Long. Modif. Dates Opt.",
    "Clean Desc. Opt.",
    "Clean Struct. Cont. Opt.",
    "Clean Graph. Opt.",
]


def text(element):
    return "".join(element.itertext()).replace("​", "").strip()


def nibble_mask_value(pattern):
    """Returns (mask, value) for a 4-hex-digit pattern where 'x' is a wildcard nibble."""
    mask = 0
    value = 0
    for index, ch in enumerate(pattern):
        shift = (3 - index) * 4
        if ch.lower() == "x":
            continue
        mask |= 0xF << shift
        value |= int(ch, 16) << shift
    return mask, value


def overrides_token(overrides):
    return "".join(f"{index}{code}" for index, code in overrides)


def main(source, destination):
    root = etree.parse(source).getroot()
    table = next(
        element for element in root.iter()
        if element.tag.endswith("table")
        and element.attrib.get("{http://www.w3.org/XML/1998/namespace}id") == "table_E.1-1"
    )
    rows = [row for row in table.iter() if row.tag.endswith("tr")]
    data_rows = rows[1:]  # skip the header row

    exact_entries = []   # (tagHex8, basicCode, overridesToken)
    masked_entries = []  # (groupMask, groupValue, elementMask, elementValue, basicCode, overrides)
    dropped = []

    for row in data_rows:
        cells = [text(cell) for cell in row if cell.tag.endswith(("td", "th"))]
        if len(cells) != 15:
            dropped.append(cells[0] if cells else "<empty row>")
            continue
        name, tag_text, basic = cells[0], cells[1], cells[4].rstrip("*").strip()
        match = TAG.fullmatch(tag_text)
        if not match:
            dropped.append(f"{name} {tag_text}")
            continue
        overrides = [(i, code) for i, code in enumerate(cells[5:15]) if code]
        group_text, element_text = match.group(1), match.group(2)
        if "x" in group_text.lower() or "x" in element_text.lower():
            group_mask, group_value = nibble_mask_value(group_text)
            element_mask, element_value = nibble_mask_value(element_text)
            masked_entries.append((group_mask, group_value, element_mask, element_value, basic, overrides))
        else:
            tag_hex = f"{int(group_text, 16):04X}{int(element_text, 16):04X}"
            exact_entries.append((tag_hex, basic, overrides_token(overrides)))

    exact_entries.sort()

    output = [
        "// Generated from DICOM PS3.15 2025a Table E.1-1 by",
        "// Tools/generate_deidentification_profile.py. Do not edit manually;",
        "// regenerate from the pinned PS3.15 source XML.",
        "//",
        f"// Table E.1-1 has {len(data_rows)} attribute rows. {len(exact_entries)} are exact",
        f"// tags in `entries` below. {len(masked_entries)} repeating-group (\"xx\") tags are",
        "// masked entries in `maskedEntries`, matched by group/element nibble",
        f"// mask rather than dropped. {len(dropped)} row(s) could not be represented as",
        "// a concrete or maskable tag and were dropped (see the generator's",
        "// module docstring for why this is safe):",
    ]
    output.extend(f"//   - {name}" for name in dropped)
    output.extend([
        "enum DICOMDeidentificationTable {",
        "    /// One row of PS3.15 Table E.1-1: the raw Basic Profile action code",
        "    /// (e.g. \"Z\", \"X/Z/D\") plus each selected option's override code,",
        "    /// keyed by that option's 0-based column index (0 = Rtn. Safe Priv.",
        "    /// Opt. ... 9 = Clean Graph. Opt.). Raw codes are interpreted by",
        "    /// `DICOMConfidentialityProfile`, not here.",
        "    struct Entry: Equatable {",
        "        let basic: String",
        "        let overrides: [Int: String]",
        "    }",
        "",
        "    /// A repeating-group (\"xx\") tag from Table E.1-1, matched by masking",
        "    /// each nibble the table leaves as \"x\".",
        "    struct MaskedEntry: Equatable {",
        "        let groupMask: UInt16",
        "        let groupValue: UInt16",
        "        let elementMask: UInt16",
        "        let elementValue: UInt16",
        "        let basic: String",
        "        let overrides: [Int: String]",
        "",
        "        func matches(_ tag: DICOMTag) -> Bool {",
        "            tag.group & groupMask == groupValue && tag.element & elementMask == elementValue",
        "        }",
        "    }",
        "",
        f"    static let entries: [DICOMTag: Entry] = {{",
        "        var entries: [DICOMTag: Entry] = [:]",
        f"        entries.reserveCapacity({len(exact_entries)})",
        '        for row in generatedTable.split(separator: "\\n") {',
        '            let columns = row.split(separator: " ")',
        "            guard columns.count >= 2, let rawTag = UInt32(columns[0], radix: 16) else { continue }",
        "            let tag = DICOMTag(group: UInt16(rawTag >> 16), element: UInt16(rawTag & 0xFFFF))",
        "            var overrides: [Int: String] = [:]",
        "            if columns.count >= 3 {",
        "                let characters = Array(columns[2])",
        "                var index = 0",
        "                while index + 1 < characters.count {",
        "                    if let column = characters[index].wholeNumberValue {",
        "                        overrides[column] = String(characters[index + 1])",
        "                    }",
        "                    index += 2",
        "                }",
        "            }",
        "            entries[tag] = Entry(basic: String(columns[1]), overrides: overrides)",
        "        }",
        "        return entries",
        "    }()",
        "",
        "    static let maskedEntries: [MaskedEntry] = [",
    ])
    for group_mask, group_value, element_mask, element_value, basic, overrides in masked_entries:
        overrides_literal = ", ".join(f"{index}: \"{code}\"" for index, code in overrides)
        output.append(
            f"        MaskedEntry(groupMask: 0x{group_mask:04X}, groupValue: 0x{group_value:04X}, "
            f"elementMask: 0x{element_mask:04X}, elementValue: 0x{element_value:04X}, "
            f"basic: \"{basic}\", overrides: [{overrides_literal}]),"
        )
    output.extend([
        "    ]",
        "",
        '    private static let generatedTable = """',
    ])
    for tag_hex, basic, overrides_str in exact_entries:
        line = f"{tag_hex} {basic}"
        if overrides_str:
            line += f" {overrides_str}"
        output.append(line)
    output.extend(['"""', "}", ""])

    Path(destination).write_text("\n".join(output), encoding="utf-8")
    print(f"wrote {len(exact_entries)} exact entries and {len(masked_entries)} masked entries to {destination}")
    print(f"dropped {len(dropped)} row(s): {dropped}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: generate_deidentification_profile.py part15.xml output.swift")
    main(sys.argv[1], sys.argv[2])
