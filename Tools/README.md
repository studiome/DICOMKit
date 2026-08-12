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
