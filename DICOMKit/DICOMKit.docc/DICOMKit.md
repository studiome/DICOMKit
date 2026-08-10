# ``DICOMKit``

Pure Swift utilities for reading DICOM Part 10 files on iPadOS and macOS.

## Overview

DICOMKit provides a small, type-safe DICOM object model and a reader for
Part 10 files encoded with Explicit VR Little Endian or Implicit VR Little
Endian transfer syntax. It also renders uncompressed 8-bit monochrome and RGB
Pixel Data, plus 16-bit monochrome data with windowing, as `CGImage`.

```swift
let file = try DICOMFile(data: data)
let name = file.dataset[.patientName]?.stringValue
let rows = file.dataset[.rows]?.uint16Value

if let pixelData = file.pixelData {
    let image = try pixelData.cgImage(windowCenter: 40, windowWidth: 400)
}
```

## Essentials

- ``DICOMFile`` — Parse a DICOM Part 10 file.
- ``DICOMDataset`` — Look up and iterate over data elements.
- ``DICOMElement`` — Access a value, its VR, or its sequence items.
- ``DICOMTag`` — Use a named tag or create a custom tag.
- ``DICOMError`` — Handle malformed or unsupported input.
- ``DICOMPixelData`` — Render supported uncompressed Pixel Data.
- ``DICOMImageError`` — Handle malformed or unsupported image data.

The library supports defined-length and undefined-length sequences, and a
focused set of uncompressed image formats. It intentionally excludes compressed
pixel decoding, writing, DIMSE, and DICOMweb. Those will be added as isolated
capabilities after the file model is stable.

## Topics

### File reading

- ``DICOMFile``
- ``DICOMDataset``
- ``DICOMElement``
- ``DICOMTag``
- ``DICOMVR``
- ``TransferSyntax``
- ``DICOMError``

### Image rendering

- ``DICOMPixelData``
- ``DICOMImageError``
