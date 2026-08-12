# Changelog

All notable changes to DICOMKit are documented here.

## v0.5 — Unreleased

- Added a DIMSE SCU and SCP foundation on top of the DICOM Upper Layer
  protocol: association PDUs, a Network.framework TCP/TLS transport, an
  inbound `NetworkDICOMULListener`, and C-ECHO, C-STORE, C-FIND, C-MOVE,
  C-GET, and C-CANCEL.
- Added the remaining User Information negotiation sub-items: Implementation
  Class UID and Version Name, SCP/SCU Role Selection, Asynchronous Operations
  Window, and the User Identity server response. DICOMKit's default
  Implementation Class UID is derived from a UUID under the ISO/IEC 9834-8
  arc; applications shipping a product should supply their own.
- Added A-ABORT and peer-initiated A-RELEASE handling, so an aborted or
  peer-released association reports `DICOMAssociationError.aborted` or
  `.releasedByPeer` instead of an unexpected-PDU error.
- Added `DICOMDIMSEStatus` status classification and C-MOVE / C-GET
  sub-operation counts and Error Comment, and corrected the Command Data Set
  Type element emitted on query and retrieve responses.
- Added SCP-side association acceptance driven by a `DICOMAssociationPolicy`,
  `DICOMAssociation.receiveRequest()`, and C-ECHO, C-STORE, C-FIND, C-MOVE,
  and C-GET response helpers.
- Added `DICOMSOPClass` well-known SOP Class UIDs,
  `DICOMWriter.encodeDataset` for bare datasets without File Meta
  Information, and `DICOMAssociation.cStore(messageID:file:)`.
- Fixed a `NetworkDICOMULTransport.connect()` crash: its connection state
  handler stayed attached after the connection settled, so a later
  cancellation resumed the same continuation twice.
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
  libjpeg-turbo is also the primary decoder for JPEG Lossless Process 14.
  The prior Process 14 decoder remains as a temporary fallback while fixture
  output is compared, including for restart-marker streams TurboJPEG rejects.
- Added native Float Pixel Data and Double Float Pixel Data access, pixel
  padding-aware automatic windowing, palette color and additional YBR rendering,
  and enhanced multi-frame rendering attributes.
- Added Explicit VR Big Endian and Deflated Explicit VR Little Endian reading
  and writing, encapsulated Pixel Data serialization, and empty/extended
  offset-table multi-frame support where frame boundaries are unambiguous.
- Added typed PS3.18 DICOM JSON conversion and typed WADO-RS metadata
  retrieval, plus QIDO-RS series and instance searches, WADO-RS frame and
  BulkData retrieval, and study-scoped STOW-RS.
- Added lightweight study/series/instance grouping, configurable recursive
  anonymization, Type 1/Type 2 module-requirement validation, and flat
  DICOMDIR Directory Record Sequence reading.
- Raised the minimum deployment target to iPadOS 16.0 because the
  association response timeout uses `Duration`.

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
- Encapsulated multi-frame pixel data supports a Basic Offset Table, Extended
  Offset Table, or an empty Basic Offset Table only when every frame occupies
  exactly one fragment; ambiguous empty-table streams remain unsupported.
- CharLS does not support JPEG-LS subsampled scans or Point Transform.
- libjpeg-turbo decodes JPEG Baseline and JPEG Lossless Process 14; DICOMKit
  does not expose codec encoding.
