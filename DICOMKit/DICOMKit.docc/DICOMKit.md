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
- ``DICOMElement`` — Access a value, its VR, or its sequence items.
- ``DICOMTag`` — Use a named tag or create a custom tag.
- ``DICOMError`` — Handle malformed or unsupported input.
- ``DICOMPixelData`` — Render supported uncompressed Pixel Data.
- ``DICOMImageError`` — Handle malformed or unsupported image data.

The library supports defined-length and undefined-length sequences, and a
focused set of uncompressed image formats. It intentionally excludes compressed
pixel decoding, writing, DIMSE, and DICOMweb. Those will be added as isolated
capabilities after the file model is stable. Pixel Padding Value
`(0028,0120)` is also not yet applied.

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
