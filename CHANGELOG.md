# Changelog

All notable changes to DICOMKit are documented here.

## v0.5 — Unreleased

- Added `DICOMwebClient` for QIDO-RS study searches, WADO-RS single-instance
  retrieval, and STOW-RS multipart instance storage.
- Added injectable `DICOMwebTransport` and response validation for testable
  application-specific authentication and networking policies.
- Replaced the experimental Pure Swift JPEG-LS decoder with the vendored
  BSD-3-Clause CharLS decoder. JPEG-LS Lossless and Near-Lossless now use one
  standards-tested implementation for sample, line, and plane interleave
  modes.
- Added dimensions, sample-precision, and DICOM `Bits Allocated` validation
  to JPEG-LS decoding; 8-bit JPEG-LS samples are safely expanded for 16-bit
  DICOM storage when required.
- Made CharLS source-buffer lifetime safe through the complete decode call.
- Replaced target unsafe C++ flags with the package-level C++17 language
  setting so tagged SwiftPM releases remain consumable.
- Added top-level CharLS BSD-3-Clause attribution and license notice.
- Added interleaved 1:1:1 RGB JPEG Lossless Process 14 decoding for Transfer
  Syntaxes `.57` and `.70`, including 8-bit and 16-bit DICOM storage.
- Replaced ImageIO with the checksum-pinned libjpeg-turbo 3.1.3 TurboJPEG API
  for JPEG Baseline (Process 1) decoding. JPEG 2000 remains on ImageIO and
  JPEG Lossless Process 14 remains on the DICOMKit decoder.

## v0.4 — Complete

- Added `DICOMWriter` and `DICOMFile.encodedData()` for Explicit and Implicit
  VR Little Endian Part 10 output, defined- and undefined-length Sequences,
  and native Pixel Data.

## v0.3 — Complete

- Added JPEG Lossless, Non-Hierarchical Process 14 decoding for DICOM
  Transfer Syntaxes `.57` and `.70`, including Selection Values 1–7,
  Point Transform, restart markers, and 2–16-bit monochrome samples.
- Added JPEG-LS Lossless `.80` decoding for monochrome 8-bit/16-bit and
  sample-interleaved 8-bit RGB frames, including preset parameters, restart
  markers, and Basic Offset Table multi-frame data.
- Added monochrome 8-bit JPEG-LS Near-Lossless `.81` decoding.
- Hardened JPEG Lossless and JPEG-LS decoding against truncated data and
  missing end-of-image markers.
- Added sample-interleaved 8-bit `RGB` JPEG-LS Near-Lossless `.81` decoding,
  including streams with a nonzero `NEAR` error bound.

## Compatibility notes

- JPEG Lossless only supports single-scan, 1:1:1 component sampling; subsampled
  and multi-scan frames remain unsupported.
- Encapsulated multi-frame pixel data requires a Basic Offset Table.
- CharLS does not support JPEG-LS subsampled scans or Point Transform.
- libjpeg-turbo is currently used only for 8-bit JPEG Baseline Pixel Data;
  DICOMKit does not expose its encoding or non-Baseline modes.
