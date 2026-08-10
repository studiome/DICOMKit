# ``DICOMKit``

Pure Swift utilities for reading DICOM Part 10 files on iPadOS and macOS.

## Overview

DICOMKit v0.1 provides a small, type-safe DICOM object model and a reader for
Part 10 files encoded with Explicit VR Little Endian or Implicit VR Little
Endian transfer syntax.

```swift
let file = try DICOMFile(data: data)
let name = file.dataset[.patientName]?.stringValue
let rows = file.dataset[.rows]?.uint16Value
```

The initial release supports defined-length and undefined-length sequences.
It intentionally excludes pixel decoding, compressed transfer syntaxes,
writing, DIMSE, and DICOMweb. Those will be added as isolated capabilities
after the file model is stable.

## Topics

### File reading

- ``DICOMFile``
- ``DICOMDataset``
- ``DICOMElement``
- ``DICOMTag``
