# DICOMKit

[![Tests](https://github.com/studiome/DICOMKit/actions/workflows/tests.yml/badge.svg)](https://github.com/studiome/DICOMKit/actions/workflows/tests.yml)

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
- Renders uncompressed 8-bit `MONOCHROME1`, `MONOCHROME2`, and interleaved
  `RGB` Pixel Data as `CGImage`
- Renders uncompressed 16-bit monochrome Pixel Data with correct handling of
  signed (`Pixel Representation`) samples, `Bits Stored` masking, and
  `Rescale Slope` / `Rescale Intercept`, with caller-supplied or
  dataset-derived window center and width
- Decodes single-frame 8-bit and 16-bit monochrome, plus 8-bit RGB RLE
  Lossless Pixel Data

```swift
let file = try DICOMFile(data: data)

let patientName = file.dataset[.patientName]?.stringValue
let rows = file.dataset[.rows]?.uint16Value
let columns = file.dataset[.columns]?.uint16Value
let referencedStudies = file.dataset[.referencedStudySequence]?.sequenceItems

if let pixelData = file.pixelData {
    // For 16-bit monochrome data, windowCenter/windowWidth are in the
    // *rescaled* unit (Hounsfield Units for CT), not raw stored values,
    // since each sample is rescaled as `storedValue * rescaleSlope +
    // rescaleIntercept` before windowing. 40/400 here is a typical CT
    // soft-tissue window. If omitted, the window defaults to the dataset's
    // own Window Center/Width `(0028,1050)`/`(0028,1051)` when present, or
    // otherwise to a window computed from the rescaled pixel data's
    // min/max value.
    let image = try pixelData.cgImage(windowCenter: 40, windowWidth: 400)
}
```

## Requirements

- Xcode 26.6 or later
- Swift 6 (language mode) / Swift Package Manager 6.0 or later
- iPadOS 15.0 or later
- macOS 11.0 or later

## Installation

### Swift Package Manager

Add DICOMKit as a dependency in `Package.swift`:

```swift
dependencies: [
    // No tagged release yet; pin to a commit once DICOMKit cuts one.
    .package(url: "https://github.com/studiome/DICOMKit", branch: "main")
]
```

Then add `"DICOMKit"` to your target's `dependencies`.

### Xcode

Alternatively, add `https://github.com/studiome/DICOMKit` via
**File > Add Package Dependencies…** in Xcode.

## Development

DICOMKit ships both an Xcode project and a `Package.swift`, kept in sync and
targeting the same sources under `DICOMKit/`. Use whichever fits your
workflow.

Open [DICOMKit.xcodeproj](DICOMKit.xcodeproj) in Xcode and run the `DICOMKit`
scheme, or open the package directly from `Package.swift`. To run the test
suite from the command line:

```bash
xcodebuild test \
  -project DICOMKit.xcodeproj \
  -scheme DICOMKit \
  -destination 'platform=macOS'
```

or, using Swift Package Manager:

```bash
swift test
```

## Roadmap

1. Multi-frame RLE Lossless Pixel Data
2. JPEG-family and JPEG 2000 transfer syntaxes
3. DICOM writing and DICOMweb support

## Non-goals for v0.1

JPEG-family and JPEG 2000 decoding, DICOM networking (DIMSE), DICOMweb, and
writing are intentionally outside the current release scope. RLE Lossless is
currently limited to single-frame 8-bit and 16-bit monochrome, plus 8-bit RGB
Pixel Data. Pixel Padding Value
`(0028,0120)` is also not applied: padding samples are rendered like any
other sample rather than being excluded or specially colored. The 8-bit and
`RGB` rendering paths don't apply `Pixel Representation` or rescale, either;
this is a deliberate simplification, since signed or rescaled 8-bit Pixel
Data is essentially unused in practice.

## License

DICOMKit is available under the [MIT License](LICENSE).
