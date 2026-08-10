# Changelog

All notable changes to DICOMKit are documented here.

## v0.4 — Unreleased

- Added `DICOMWriter` and `DICOMFile.encodedData()` for Explicit and Implicit
  VR Little Endian Part 10 output, defined- and undefined-length Sequences,
  and native Pixel Data.

## v0.3 — Unreleased

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

- JPEG-LS Near-Lossless RGB, other JPEG-LS interleave modes, and
  multi-component JPEG Lossless remain unsupported.
- Encapsulated multi-frame pixel data requires a Basic Offset Table.
