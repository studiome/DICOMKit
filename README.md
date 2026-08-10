# DICOMKit

Pure Swift utilities for reading DICOM Part 10 files on iPadOS and macOS.

[Read the API documentation](https://studiome.github.io/DICOMKit/)

> **Status: early development.** DICOMKit is not yet suitable for clinical use.

## Current capabilities

- Validates the DICOM Part 10 preamble and `DICM` prefix
- Reads File Meta Information
- Parses datasets encoded with Explicit VR Little Endian and Implicit VR Little Endian
- Parses defined-length and undefined-length sequences recursively
- Exposes a lightweight Swift object model: `DICOMFile`, `DICOMDataset`,
  `DICOMElement`, `DICOMTag`, and `DICOMVR`
- Provides typed access for common string and `UInt16` values

```swift
let file = try DICOMFile(data: data)

let patientName = file.dataset[.patientName]?.stringValue
let rows = file.dataset[.rows]?.uint16Value
let columns = file.dataset[.columns]?.uint16Value
let referencedStudies = file.dataset[.referencedStudySequence]?.sequenceItems
```

## Requirements

- Xcode 26.6 or later
- iPadOS 15.0 or later
- macOS 11.0 or later

## Development

Open [DICOMKit.xcodeproj](DICOMKit.xcodeproj) in Xcode and run the `DICOMKit`
scheme. To run the test suite from the command line:

```bash
xcodebuild test \
  -project DICOMKit.xcodeproj \
  -scheme DICOMKit \
  -destination 'platform=macOS'
```

## Roadmap

1. Native pixel data, windowing, and `CGImage` output
2. RLE and compressed transfer syntaxes
3. DICOM writing and DICOMweb support

## Non-goals for v0.1

Compressed pixel decoding, DICOM networking (DIMSE), DICOMweb, and writing are
intentionally outside the initial release scope.

## License

DICOMKit is available under the [MIT License](LICENSE).
