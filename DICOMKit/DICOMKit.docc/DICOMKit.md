# ``DICOMKit``

Swift-first utilities for reading DICOM Part 10 files on iPadOS and macOS.

This module — parsing, rendering, navigation, and dataset serialization — is
the one product a viewer needs; it has no networking and no file-writing code
path. Two sibling products build on top of it in the same package:
`DICOMKitAuthoring` (Part 10 file writing, the anonymizer, the PS3.15
confidentiality profile, module validation, and UID generation) and
`DICOMKitNetworking` (DIMSE association services and DICOMweb/DICOM JSON).
Both depend only on `DICOMKit`; `DICOMKitNetworking` does not depend on
`DICOMKitAuthoring`. See each product's own documentation for what it adds.

## Overview

DICOMKit provides a small, type-safe DICOM object model and a reader for
Part 10 files encoded with Explicit VR Little Endian, Implicit VR Little
Endian, Explicit VR Big Endian, or Deflated Explicit VR Little Endian transfer
syntax. It also renders supported uncompressed monochrome and RGB Pixel Data,
plus 16-bit monochrome data, as `CGImage`. The 16-bit path
correctly handles signed (`Pixel Representation`) samples, `Bits Stored`
masking, and `Rescale Slope`/`Rescale Intercept` before windowing.

Implicit VR parsing resolves 5,092 public tags with unambiguous VRs from the
generated DICOM PS3.6 2025a dictionary. Context-dependent and private tags
remain `UN` unless supplied through DICOMKit's explicit handling.

``DICOMReadOptions`` controls two further, independently switchable
resolutions performed while parsing, both `nil`/on by default and passed as
a trailing parameter to `DICOMFile`/`DICOMMetadataFile`:

- `reinterpretsUnknownVR` re-derives a defined-length `UN` element's VR from
  the dictionary under Explicit VR Little Endian (PS3.5 6.2.2) — the usual
  symptom of data that passed through middleware which converted Implicit VR
  to Explicit VR without a dictionary of its own. A `UN` element the
  dictionary resolves to `SQ` is parsed as an Implicit VR Little Endian
  sequence, since that's the encoding such a conversion preserves; unparseable
  bytes fall back to `UN` rather than failing the whole dataset. This never
  applies to Pixel Data, private (odd-group) tags, tags the dictionary
  doesn't know, or Explicit VR **Big** Endian, since a `UN` value's bytes are
  always little-endian even there.
- `privateDictionary` resolves a private element's VR under Implicit VR
  using a caller-supplied ``DICOMPrivateDictionary``, matched against the
  Private Creator recorded earlier in the same dataset or sequence item.
  DICOMKit ships none of its own: private attribute meanings are
  vendor-specific, and a dictionary sourced from reverse engineering can
  make DICOMKit read a vendor's bytes as the wrong type. Being unable to
  read a private attribute is safer than reading it wrongly.

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
- ``DICOMReadOptions`` — Control `UN` re-interpretation and private VR resolution while parsing.
- ``DICOMDataset`` — Look up and iterate over data elements.
- ``DICOMStudy`` — Group and order instances by study and series.
- ``DICOMPixelData`` — Render supported uncompressed Pixel Data.
- ``DICOMFloatingPixelData`` — Access native Float and Double Float Pixel Data.
- ``DICOMFrameAttributes`` — Inspect Enhanced Multi-frame display attributes.
- ``DICOMFrameFunctionalGroups`` — Resolve every Enhanced Multi-frame macro
  DICOMKit understands, shared-then-per-frame.
- ``DICOMRealWorldValueMap`` — Convert a stored pixel value to a real-world
  value such as PET SUV.
- ``DICOMOverlay`` — Access embedded Overlay Plane bitmaps.
- ``DICOMPresentationLUTShape`` — Inspect presentation polarity.
- ``DICOMModalityLUT`` — Apply the Modality LUT Sequence ahead of windowing.
- ``DICOMCineAttributes`` — Inspect Cine module playback attributes.
- ``DICOMDisplayShutter`` — Inspect and apply the Display Shutter module.
- ``DICOMPresentationState`` — Parse and apply a Grayscale Softcopy
  Presentation State.
- ``DICOMLazyPixelData`` — Defer Pixel Data frame decoding until it is needed.
- ``DICOMMetadataFile`` — Retain metadata and reopen local Pixel Data on demand.

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
encapsulated images use a Basic Offset Table, Extended Offset Table, or an
empty Basic Offset Table when each frame consists of exactly one fragment, and
are available through ``DICOMFile/pixelDataFrames``. libjpeg-turbo is pinned as a checksum-verified
SwiftPM binary target. The previous Process 14 decoder remains as a temporary
fallback while fixture-output comparisons are accumulated.

The three High-Throughput JPEG 2000 (HTJ2K) transfer syntaxes — HTJ2K Lossless
Only (`.201`), HTJ2K with RPCL Options Lossless Only (`.202`), and HTJ2K
(`.203`) — are recognized and open normally: their File Meta Information
parses, and their encapsulated Pixel Data fragments are reachable through
``DICOMElement/encapsulatedFragments`` like any other encapsulated transfer
syntax. Because HTJ2K (PS3.5 Annex A.4.4) is a JPEG 2000 codestream that only
swaps in a different block coder, its Pixel Data is routed through the same
ImageIO `CGImageSource` path as JPEG 2000 Lossless / JPEG 2000, on the
assumption that any platform support for HTJ2K goes through that same API.
DICOMKit does not bundle an HTJ2K codec and has no HTJ2K fixture to verify
against, so whether a given HTJ2K stream actually decodes depends entirely on
the host platform's ImageIO; a stream ImageIO rejects surfaces as `nil` from
``DICOMFile/pixelDataFrames`` — the same as any other undecodable frame —
rather than as a parsing failure. ``TransferSyntax/hasPixelDataDecoder``
reports `true` for HTJ2K to say DICOMKit will attempt a decode, without
promising any particular stream succeeds.

Pixel Padding Value `(0028,0120)`
and Pixel Padding Range Limit `(0028,0121)` are excluded from automatically
computed windows.

``DICOMFile/frameFunctionalGroups`` resolves every Enhanced Multi-frame
functional group macro DICOMKit understands (PS3.3 C.7.6.16) shared-then-
per-frame, so Enhanced CT/MR objects can be measured and reformatted, not
just displayed: Pixel Value Transformation and Frame VOI LUT (also exposed
through the older ``DICOMFrameAttributes``), Pixel Measures and Plane
Position/Orientation (combined per frame into ``DICOMImageGeometry`` by
``DICOMFile/frameGeometries``), Frame Content (Stack ID, In-Stack Position
Number, Temporal Position Index — resolved into display order by
``DICOMFile/frameOrder()``), Frame Anatomy, and a Frame Display Shutter that
``DICOMFile/pixelDataFrames`` prefers over the dataset-level
``DICOMDisplayShutter`` when present. ``DICOMFile/frameOrder()`` does not
consult the Dimension Index Sequence `(0020,9222)`: raw
``DICOMFrameContent/dimensionIndexValues`` are exposed without interpretation
because that requires a dimension organization DICOMKit does not model.
``DICOMRealWorldValueMap`` reads the Real World Value Mapping Sequence
`(0040,9096)`, both at the top level and per frame — the transform a PET
viewer uses for Standardized Uptake Value, kept separate from the Modality
LUT because a real-world value is reported, not windowed.

Use ``DICOMFile/makeLazyPixelData()`` when image frames may not be displayed
immediately. It defers and memoizes frame decoding; the parsed file's encoded
Pixel Data remains retained, so it is not a streaming file-I/O API.

DICOMKit serializes a dataset alone through
``DICOMWriter/encodeDataset(_:transferSyntax:sequenceLengthEncoding:)`` —
Explicit VR Little Endian, Explicit VR Big Endian, Deflated Explicit VR Little
Endian, and Implicit VR Little Endian, defined- and undefined-length
sequences, and native Pixel Data — without a 128-byte preamble, `DICM` magic,
or File Meta Information; this is the payload a DIMSE service such as C-STORE
transfers. It can also serialize caller-supplied compressed fragments through
``DICOMElement/init(encapsulatedPixelDataFrames:vr:)`` with a generated Basic
Offset Table, without compressing samples itself. Assembling a complete Part
10 file — preamble, File Meta Information, and all — is `DICOMWriter.write`
and `DICOMFile.encodedData(sequenceLengthEncoding:)`, both added by
`DICOMKitAuthoring`.

``DICOMStructuredReport/init(file:)`` parses a Structured Report's Content
Tree (PS3.3 C.17.3): the dataset itself is the root ``DICOMContentItem``, and
each item's Content Sequence `(0040,A730)` holds its children recursively.
Every SR Value Type is modeled by ``DICOMContentItemValue`` — `CONTAINER`,
`TEXT`, `CODE`, `NUM`, `DATE`/`TIME`/`DATETIME`, `UIDREF`, `PNAME`, `IMAGE`,
`WAVEFORM`, `COMPOSITE`, `SCOORD`/`SCOORD3D`, and `TCOORD` — with any Value
Type DICOMKit doesn't recognize falling back to `.unsupported(valueType:)`
without dropping its children. Text values are decoded with the item's own
(possibly inherited) Specific Character Set, the same inheritance rule used
elsewhere in DICOMKit (PS3.5 7.5.3). Parsing bounds its own recursion at
`DICOMDataset.structuredReportMaxDepth`, throwing
``DICOMError/invalidStructuredReport`` rather than exhausting the stack on a
malformed or hostile Content Sequence; the same error is thrown when a
dataset has no Value Type at all, since that means it isn't an SR.
``DICOMStructuredReport/plainText(indent:)``,
``DICOMStructuredReport/walk(_:)``, and
``DICOMStructuredReport/items(withValueType:)`` read the parsed tree —
`plainText` is a debugging/fallback rendering, not a clinical presentation.
DICOMKit deliberately does **not** interpret SR templates (TID 1500 and
similar) or impose meaning on a concept name: that is a much larger,
standards-heavy job on its own, and a wrong interpretation of a measurement
is worse than none. By-reference relationships
(``DICOMContentItem/referencedContentItemIdentifier``) are exposed raw and
not resolved into ``DICOMContentItem/children``, since doing so would turn a
tree into a graph the `children` model cannot represent.

## Topics

### File reading

- ``DICOMFile``
- ``DICOMWriter``
- ``DICOMReadOptions``
- ``DICOMPrivateDictionary``
- ``DICOMPrivateTagEntry``
- ``DICOMDataset``
- ``DICOMDirectory``
- ``DICOMDirectoryRecord``
- ``DICOMElement``
- ``DICOMTag``
- ``DICOMVR``
- ``TransferSyntax``
- ``DICOMError``
- ``DICOMFileMetaInformation``
- ``DICOMFileMetaValidationError``

### SOP identification

- ``DICOMSOPClass``
- ``DICOMSOPReference``

### Image rendering

- ``DICOMPixelData``
- ``PhotometricInterpretation``
- ``DICOMImageError``

### Enhanced Multi-frame

- ``DICOMFrameAttributes``
- ``DICOMFrameFunctionalGroups``
- ``DICOMPixelMeasures``
- ``DICOMFrameContent``
- ``DICOMFrameAnatomy``
- ``DICOMCodeSequenceItem``
- ``DICOMRealWorldValueMap``

### Structured Reports

- ``DICOMStructuredReport``
- ``DICOMContentItem``
- ``DICOMContentItemValue``
