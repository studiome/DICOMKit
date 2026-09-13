# Dictionary generation

`generate_dicom_dictionary.py` generates
`DICOMKit/DICOMDictionary.generated.swift` from the official DICOM PS3.6
Table 6-1 source. The checked-in dictionary was generated from the
[DICOM PS3.6 2025a DocBook XML](https://dicom.nema.org/medical/dicom/2025a/source/docbook/part06/part06.xml).

Run:

```sh
curl -L --fail https://dicom.nema.org/medical/dicom/2025a/source/docbook/part06/part06.xml -o /tmp/part06.xml
python3 Tools/generate_dicom_dictionary.py /tmp/part06.xml DICOMKit/DICOMDictionary.generated.swift
```

Only exact public tags with one VR are generated. Tags whose PS3.6 VR is
context-dependent or repeating-pattern based remain in `DICOMDictionary.swift`
as explicit overrides, or decode as `UN` when unknown.

# De-identification profile generation

`generate_deidentification_profile.py` generates
`DICOMKit/DICOMDeidentification.generated.swift` from the official DICOM
PS3.15 Table E.1-1 source (the Basic Application Level Confidentiality
Profile attribute table). The checked-in table was generated from the
[DICOM PS3.15 2025a DocBook XML](https://dicom.nema.org/medical/dicom/2025a/source/docbook/part15/part15.xml).

Run:

```sh
curl -L --fail https://dicom.nema.org/medical/dicom/2025a/source/docbook/part15/part15.xml -o /tmp/part15.xml
python3 Tools/generate_deidentification_profile.py /tmp/part15.xml DICOMKit/DICOMDeidentification.generated.swift
```

Every one of the table's 631 attribute rows is accounted for: exact tags
become entries in `DICOMDeidentificationTable.entries`; the table's three
repeating-group ("xx") tags (Curve Data, Overlay Comments, Overlay Data)
become masked entries in `DICOMDeidentificationTable.maskedEntries`,
matched by group/element nibble mask instead of being dropped; and the one
row that is neither ("Private Attributes", whose Tag column is prose, not
a tag) is dropped, with the drop recorded in a comment at the top of the
generated file so the omission is never silent. The raw per-row action
codes (`D`, `Z`, `X`, `K`, `C`, `U`, and slashed combinations like
`X/Z/D`) are interpreted by `DICOMConfidentialityProfile`
(`DICOMDeidentificationModel.swift`), not by the generator.
