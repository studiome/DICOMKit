# ``DICOMKit``

Pure Swift utilities for reading DICOM Part 10 files on iPadOS and macOS.

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
- ``DICOMPixelData`` — Render supported uncompressed Pixel Data.

The library supports defined-length and undefined-length sequences, a focused
set of uncompressed image formats and 8-bit/16-bit monochrome plus 8-bit RGB
RLE Lossless decoding. JPEG Lossless (Transfer Syntaxes `.57` and `.70`)
supports single-component `MONOCHROME1` / `MONOCHROME2` Process 14 frames with
Selection Values 1–7, 2–16-bit precision, Point Transform, and restart
markers; `.70` is limited to Selection Value 1. JPEG-LS Lossless and
Near-Lossless (Transfer Syntaxes `.80` and `.81`) are decoded by a pure
Swift, dependency-free implementation of ITU-T T.87: monochrome 2- through
16-bit frames and 8-bit `RGB`/`YBR_FULL` (returned as `RGB`) frames, in all
three JPEG-LS interleave modes (plane, line, and sample), with default or
explicit Preset Coding Parameters and restart markers. Near-Lossless
(`NEAR > 0`) is supported for both monochrome and `RGB`.
Multi-frame JPEG-LS data requires a Basic Offset Table and is available through
``DICOMFile/pixelDataFrames``.
JPEG Baseline (Process 1), JPEG 2000 Lossless, and
JPEG 2000 Pixel Data are decoded through ImageIO, which produces 8-bit
samples: `RGB` for three-sample frames and grayscale for `MONOCHROME1` /
`MONOCHROME2` frames, while frames declaring any other `Bits Allocated` are
reported as undecodable. Multi-frame encapsulated images require a Basic
Offset Table and are available through ``DICOMFile/pixelDataFrames``. JPEG
Multi-component JPEG Lossless and DIMSE
remain outside the current scope.
Pixel Padding Value
`(0028,0120)` is also not yet applied.

DICOMKit also writes Part 10 files through ``DICOMWriter`` and
``DICOMFile/encodedData(sequenceLengthEncoding:)``. The writer supports
Explicit VR Little Endian and Implicit VR Little Endian, defined- and
undefined-length sequences, and native Pixel Data.

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

### DICOMweb

- ``DICOMwebClient``
- ``DICOMwebTransport``
- ``DICOMwebError``

### Image rendering

- ``DICOMPixelData``
- ``PhotometricInterpretation``
- ``DICOMImageError``
