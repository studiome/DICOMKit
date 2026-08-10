# Changelog

All notable changes to DICOMKit are documented here.

## v0.5 — Unreleased

- Added `DICOMwebClient` for QIDO-RS study searches, WADO-RS single-instance
  retrieval, and STOW-RS multipart instance storage.
- Added injectable `DICOMwebTransport` and response validation for testable
  application-specific authentication and networking policies.
- Added JPEG-LS Lossless plane-interleaved RGB decoding, including
  multi-SOS encapsulated frames.
- Rewrote the JPEG-LS decoder as a from-scratch, pure Swift implementation
  of ITU-T T.87 and removed the vendored CharLS C++ codec entirely: DICOMKit
  now has no C/C++ dependency and no native library to build or ship.
- Fixed three lossless decoding bugs that the prior CharLS-backed decoder's
  compact 2x2 test fixtures were too small to expose: double bit-unstuffing
  of the byte following an 0xFF entropy byte, a missing NEAR dead zone in
  the gradient quantizer (T.87 Annex A.3.3), and a missing post-modulo clamp
  to `[0, MAXVAL]` in sample reconstruction.
- Fixed a Near-Lossless decoding bug where the regular mode's k=0 sign-bias
  correction (T.87 Annex A, code segment A.13) was applied unconditionally
  instead of being gated to `NEAR == 0` as the standard specifies, which
  silently corrupted adaptive context statistics under Near-Lossless coding
  until an unrelated later sample decoded outside the declared error bound.
- Added 13 real-size (up to 64x64, 3-component) JPEG-LS regression fixtures
  under `DICOMKitTests/Fixtures/JPEGLS/`, covering both interleave mode and
  Near-Lossless combinations the previous 1x1/2x2 fixtures could not
  exercise; their expected samples are regenerated deterministically from a
  seed rather than committed as literal arrays.

## v0.4 — Complete

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

- Multi-component JPEG Lossless remains unsupported.
- Encapsulated multi-frame pixel data requires a Basic Offset Table.
