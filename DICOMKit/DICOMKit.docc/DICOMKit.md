# ``DICOMKit``

Swift-first utilities for reading DICOM Part 10 files on iPadOS and macOS.

## Overview

DICOMKit provides a small, type-safe DICOM object model and a reader for
Part 10 files encoded with Explicit VR Little Endian or Implicit VR Little
Endian transfer syntax. It also renders uncompressed 8-bit monochrome and RGB
Pixel Data, plus 16-bit monochrome data, as `CGImage`. The 16-bit path
correctly handles signed (`Pixel Representation`) samples, `Bits Stored`
masking, and `Rescale Slope`/`Rescale Intercept` before windowing.

```swift
let file = try DICOMFile(data: data)
let name = file.dataset[.patientName]?.stringValue
let rows = file.dataset[.rows]?.uint16Value

if let pixelData = file.pixelData {
    // windowCenter/windowWidth are in the *rescaled* unit (Hounsfield
    // Units for CT), since each 16-bit sample is rescaled as `storedValue
    // * rescaleSlope + rescaleIntercept` before windowing. If omitted, the
    // window defaults to the dataset's own Window Center/Width when
    // present, or otherwise to a window computed from the pixel data.
    let image = try pixelData.cgImage(windowCenter: 40, windowWidth: 400)
}
```

## Essentials

- ``DICOMFile`` — Parse a DICOM Part 10 file.
- ``DICOMDataset`` — Look up and iterate over data elements.
- ``DICOMStudy`` — Group and order instances by study and series.
- ``DICOMAnonymizer`` — Apply caller-defined recursive de-identification rules.
- ``DICOMJSONDataset`` — Convert supported values to and from typed DICOM JSON.
- ``DICOMPixelData`` — Render supported uncompressed Pixel Data.
- ``DICOMFloatingPixelData`` — Access native Float and Double Float Pixel Data.
- ``DICOMLazyPixelData`` — Defer Pixel Data frame decoding until it is needed.

The library supports defined-length and undefined-length sequences, a focused
set of uncompressed image formats and 8-bit/16-bit monochrome plus 8-bit RGB
RLE Lossless decoding. JPEG Lossless (Transfer Syntaxes `.57` and `.70`)
supports single-component `MONOCHROME1` / `MONOCHROME2` and interleaved 1:1:1
`RGB` Process 14 frames with Selection Values 1–7, 2–16-bit precision, Point
Transform, and restart markers; `.70` is limited to Selection Value 1.
JPEG-LS Lossless (Transfer
Syntax `.80`) supports monochrome 8-bit and 16-bit frames and
sample-interleaved and plane-interleaved 8-bit `RGB` and sample-interleaved
`YBR_FULL` (returned as `RGB`), with default or explicit Preset Coding
Parameters and restart markers. The vendored CharLS decoder supports JPEG-LS
Lossless and Near-Lossless sample, line, and plane interleave modes, including
multi-component 8-bit and 16-bit frames.
Multi-frame JPEG-LS data requires a Basic Offset Table, Extended Offset Table,
or one fragment per frame with an empty Basic Offset Table, and is available through
``DICOMFile/pixelDataFrames``.
JPEG Baseline (Process 1) and JPEG Lossless Process 14 are decoded through
libjpeg-turbo's TurboJPEG API; JPEG 2000 Lossless and JPEG 2000 are decoded
through ImageIO. The Baseline and JPEG 2000 backends produce 8-bit samples:
`RGB` for three-sample frames and grayscale for `MONOCHROME1` / `MONOCHROME2`
frames, while frames declaring any other `Bits Allocated` are reported as
undecodable. DICOMKit normalizes Process 14 output into the declared DICOM
storage and preserves its transfer-syntax and component validations. Multi-frame
encapsulated images require a Basic Offset Table and are available through
``DICOMFile/pixelDataFrames``. libjpeg-turbo is pinned as a checksum-verified
SwiftPM binary target. The previous Process 14 decoder remains as a temporary
fallback while fixture-output comparisons are accumulated. JPEG
DIMSE remains outside the current scope.
Pixel Padding Value
`(0028,0120)` is also not yet applied.

Use ``DICOMFile/makeLazyPixelData()`` when image frames may not be displayed
immediately. It defers and memoizes frame decoding; the parsed file's encoded
Pixel Data remains retained, so it is not a streaming file-I/O API.

DICOMKit also writes Part 10 files through ``DICOMWriter`` and
``DICOMFile/encodedData(sequenceLengthEncoding:)``. The writer supports
Explicit VR Little Endian, Explicit VR Big Endian, Deflated Explicit VR Little
Endian, and Implicit VR Little Endian, defined- and undefined-length
sequences, and native Pixel Data. It can also serialize
caller-supplied compressed fragments through
``DICOMElement/init(encapsulatedPixelDataFrames:vr:)`` with a generated Basic
Offset Table; it does not compress samples itself.

``DICOMwebClient`` provides an async HTTP foundation for QIDO-RS study
searches, WADO-RS single-instance retrieval, and STOW-RS multipart storage.
Inject a ``DICOMwebTransport`` to add application-specific authentication or
to test requests without a network connection.

## Topics

### File reading

- ``DICOMFile``
- ``DICOMWriter``
- ``DICOMDataset``
- ``DICOMElement``
- ``DICOMTag``
- ``DICOMVR``
- ``TransferSyntax``
- ``DICOMError``
- ``DICOMModuleValidator``
- ``DICOMModuleRequirement``
- ``DICOMValidationIssue``

### DICOMweb

- ``DICOMwebClient``
- ``DICOMwebTransport``
- ``DICOMwebError``

### Image rendering

- ``DICOMPixelData``
- ``PhotometricInterpretation``
- ``DICOMImageError``
