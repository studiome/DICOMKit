# DICOMKit

[![Tests](https://github.com/studiome/DICOMKit/actions/workflows/tests.yml/badge.svg)](https://github.com/studiome/DICOMKit/actions/workflows/tests.yml)

Swift-first utilities for reading DICOM Part 10 files on iPadOS and macOS.

[Read the API documentation](https://studiome.github.io/DICOMKit/documentation/dicomkit/)

> **Status: early development.** DICOMKit is not yet suitable for clinical use.

See the [changelog](CHANGELOG.md) for the v0.3 implementation status.

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
- Decodes multi-frame RLE Lossless Pixel Data when it includes a Basic Offset
  Table, exposed as `DICOMFile.pixelDataFrames`
- Decodes single-component monochrome JPEG Lossless, Non-Hierarchical
  (Process 14) Pixel Data for `.57` and `.70`, including Selection Values 1–7,
  2–16-bit precision, Point Transform, restart markers, and multi-frame Basic
  Offset Tables. `.70` is constrained to Selection Value 1 as required by its
  transfer syntax.
- Decodes JPEG-LS Lossless (`.80`) monochrome 8-bit and 16-bit Pixel Data,
  plus sample-interleaved 8-bit `RGB` and `YBR_FULL` (returned as `RGB`); supports default and explicit Preset
  Coding Parameters, restart markers, multi-frame Basic Offset Tables, and
  plane-interleaved 8-bit `RGB` frames.
  JPEG-LS Near-Lossless (`.81`) supports monochrome and sample-interleaved
  `RGB` 8-bit Pixel Data. The
  JPEG-LS coverage is verified with BSD-3-Clause CharLS-generated reference
  streams.
- Decodes 8-bit JPEG Baseline (Process 1), JPEG 2000 Lossless, and JPEG 2000
  Pixel Data via ImageIO, as either interleaved `RGB` (whatever color space
  the JPEG itself uses, including `YBR_FULL_422`) or single-sample
  `MONOCHROME1` / `MONOCHROME2`; multiple frames require a Basic Offset Table
- Writes DICOM Part 10 files using Explicit VR Little Endian or Implicit VR
  Little Endian, including defined- or undefined-length Sequences and native
  Pixel Data
- Provides async DICOMweb clients for QIDO-RS study searches, WADO-RS
  instance retrieval, and STOW-RS multipart instance storage; transports are
  injectable for application authentication and testing
- Uses the vendored BSD-3-Clause CharLS codec for standards-complete JPEG-LS
  decoding, including sample, line, and plane interleave modes

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

```swift
let client = DICOMwebClient(baseURL: URL(string: "https://pacs.example.com/dicomweb")!)
let studies = try await client.searchStudies(query: [
    URLQueryItem(name: "PatientName", value: "Doe*")
])
let instance = try await client.retrieveInstance(
    studyInstanceUID: "1.2.3",
    seriesInstanceUID: "4.5.6",
    sopInstanceUID: "7.8.9"
)
```

## Requirements

- Xcode 26.6 or later
- Swift 6 (language mode) / Swift Package Manager 6.0 or later
- iPadOS 15.0 or later
- macOS 14.0 or later

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

DICOMKit is defined exclusively by `Package.swift`: it owns the library and
test targets, platform versions, resources, dependencies, and CI build inputs.
Open `Package.swift` directly in Xcode for normal development, or run the test
suite from the command line:

```bash
swift test
```

To compile the package for iOS and iPadOS:

```bash
swift build \
  --triple arm64-apple-ios15.0 \
  --sdk "$(xcrun --sdk iphoneos --show-sdk-path)"
```

To run the same test suite on the iOS Simulator:

```bash
xcodebuild test \
  -scheme DICOMKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

### Continuous integration

GitHub Actions runs the same commands on every push to `main` and on every
pull request:

- `.github/workflows/tests.yml` builds and tests the package on macOS, builds
  it for iOS and iPadOS, and runs `DICOMKitTests` on the iOS Simulator.
- `.github/workflows/publish-docs.yml` builds the DocC catalog and publishes
  it to GitHub Pages on every push to `main`.

## Roadmap

1. Multi-component JPEG Lossless Process 14
2. DIMSE networking

## License

DICOMKit is available under the [MIT License](LICENSE).
