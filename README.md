# DICOMKit

[![Tests](https://github.com/studiome/DICOMKit/actions/workflows/tests.yml/badge.svg)](https://github.com/studiome/DICOMKit/actions/workflows/tests.yml)

Swift-first utilities for reading DICOM Part 10 files on iPadOS and macOS.

[Read the API documentation](https://studiome.github.io/DICOMKit/documentation/dicomkit/)

> **Status: early development.** DICOMKit is not yet suitable for clinical use.

See the [changelog](CHANGELOG.md) for the current implementation status.

## Current capabilities

- Validates the DICOM Part 10 preamble and `DICM` prefix
- Reads File Meta Information
- Parses datasets encoded with Explicit VR Little Endian and Implicit VR Little Endian
- Parses defined-length and undefined-length sequences recursively
- Exposes a lightweight Swift object model: `DICOMFile`, `DICOMDataset`,
  `DICOMElement`, `DICOMTag`, and `DICOMVR`
- Groups files into `DICOMStudy` / `DICOMSeries` / `DICOMInstance` models and
  sorts instances by image position, instance number, then SOP Instance UID
- Provides a caller-configured recursive `DICOMAnonymizer` for removing or
  replacing attributes, including private tags; it is not a PS3.15 profile
  conformance claim
- Validates caller-supplied DICOM module Type 1 and Type 2 requirements,
  including missing attributes, empty Type 1 values, and unexpected VRs; this
  is a reusable building block rather than complete IOD conformance validation
- Provides typed access for common string and `UInt16` values
- Converts supported in-memory datasets to and from typed DICOM JSON
  (PS3.18 Annex F), including string VRs, `US`, sequences, and inline binary
  values
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
- Provides `DICOMFile.makeLazyPixelData()` to defer Pixel Data frame decoding
  until a consumer requests it, with thread-safe memoization of the result
- Exposes native Float and Double Float Pixel Data frames through
  `DICOMFile.floatingPixelDataFrames`, preserving IEEE 754 values
- Decodes JPEG Lossless, Non-Hierarchical (Process 14) Pixel Data for `.57`
  and `.70`: single-component `MONOCHROME1` / `MONOCHROME2` and interleaved
  1:1:1 `RGB`, with 2–16-bit precision, Selection Values 1–7, Point Transform,
  restart markers, and multi-frame Basic Offset Tables. `.70` is constrained
  to Selection Value 1 as required by its transfer syntax.
- Decodes JPEG-LS Lossless (`.80`) monochrome 8-bit and 16-bit Pixel Data,
  plus sample-interleaved 8-bit `RGB` and `YBR_FULL` (returned as `RGB`); supports default and explicit Preset
  Coding Parameters, restart markers, multi-frame Basic Offset Tables, and
  plane-interleaved 8-bit `RGB` frames.
  JPEG-LS Near-Lossless (`.81`) supports monochrome and sample-interleaved
  `RGB` 8-bit Pixel Data. The
  JPEG-LS coverage is verified with BSD-3-Clause CharLS-generated reference
  streams.
- Decodes 8-bit JPEG Baseline (Process 1) Pixel Data with libjpeg-turbo 3.1.3,
  and JPEG 2000 Lossless / JPEG 2000 Pixel Data with ImageIO, as either
  interleaved `RGB` (whatever color space the JPEG itself uses, including
  `YBR_FULL_422`) or single-sample
  `MONOCHROME1` / `MONOCHROME2`; multiple frames use a Basic Offset Table,
  Extended Offset Table, or one-fragment-per-frame empty Basic Offset Table
- Writes DICOM Part 10 files using Explicit VR Little Endian, Explicit VR Big
  Endian, Deflated Explicit VR Little Endian, or Implicit VR Little Endian,
  including defined- or undefined-length Sequences and native Pixel Data;
  writes caller-supplied compressed fragments with generated Basic Offset
  Tables for supported encapsulated transfer syntaxes
- Provides async DICOMweb clients for QIDO-RS study/series/instance searches,
  WADO-RS instance/metadata/frame/BulkData retrieval, and STOW-RS multipart
  instance storage; WADO metadata can also be decoded as typed DICOM JSON;
  transports are injectable for application authentication and testing
- Uses the BSD-3-Clause CharLS codec through a Git submodule for JPEG-LS
  decoding, including sample, line, and plane interleave modes

## Codec backends

| DICOM transfer syntax | Decoder | Current scope |
| --- | --- | --- |
| JPEG Baseline `.50` | libjpeg-turbo 3.1.3 (TurboJPEG API) | 8-bit `RGB` and monochrome output; JPEG color spaces are converted to output RGB. |
| JPEG Lossless `.57`, `.70` | libjpeg-turbo 3.1.3 (TurboJPEG API) | 2–16-bit monochrome and single-scan, 1:1:1 interleaved `RGB`; `.70` requires Selection Value 1. |
| JPEG-LS `.80`, `.81` | CharLS Git submodule | Lossless and Near-Lossless; supported interleave modes are listed above. |
| JPEG 2000 `.90`, `.91` | ImageIO | 8-bit `RGB` or monochrome output. |

libjpeg-turbo is the primary decoder for JPEG Baseline and JPEG Lossless
Process 14. DICOMKit retains responsibility for fragment reassembly, transfer
syntax restrictions, dimensions, component count, `Bits Allocated`, `Bits
Stored`, and 16-bit little-endian storage. The previous Process 14 decoder is
kept as a temporary fallback for streams that TurboJPEG rejects (including the
current restart-marker regression fixture) while both implementations are
compared against fixtures.

```swift
let file = try DICOMFile(data: data)

let patientName = file.dataset[.patientName]?.stringValue
let rows = file.dataset[.rows]?.uint16Value
let columns = file.dataset[.columns]?.uint16Value
let referencedStudies = file.dataset[.referencedStudySequence]?.sequenceItems

let dicomJSON = DICOMJSONDataset(dataset: file.dataset)
let restoredDataset = try dicomJSON.dicomDataset()

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

For views that may never display an image, defer frame decoding until it is
needed:

```swift
let lazyPixelData = file.makeLazyPixelData()
let firstFrame = lazyPixelData?.loadFirstFrame()
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

CharLS is a Git submodule pinned to an exact upstream commit, rather than a
source copy maintained in this repository. Clone DICOMKit with
`--recurse-submodules`, or initialize it after cloning:

```bash
git submodule update --init --recursive
```

To deliberately update CharLS, provide an upstream tag or commit to the helper
script. Review the resulting submodule SHA and run the test suite before
committing it:

```bash
./Scripts/update-charls.sh <tag-or-commit>
swift test
```

libjpeg-turbo is a SwiftPM binary target, downloaded from the pinned 3.1.3
release URL and verified with the SHA-256 checksum in `Package.swift`. No
system installation is required. To update it, change both the release URL and
checksum together, then run the macOS tests and the iOS build below.

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

1. DIMSE networking

## License

DICOMKit is available under the [MIT License](LICENSE).
Its JPEG codec dependencies, CharLS and libjpeg-turbo, have their own license
terms; see [third-party notices](THIRD_PARTY_NOTICES.md).
