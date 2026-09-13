# ``DICOMKit``

Swift-first utilities for reading DICOM Part 10 files on iPadOS and macOS.

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
- ``DICOMAnonymizer`` — Apply caller-defined recursive de-identification rules.
- ``DICOMDeidentificationProfile`` — Use conservative PS3.15-inspired presets.
- ``DICOMJSONDataset`` — Convert supported values to and from typed DICOM JSON.
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
- ``DICOMAssociation`` — Perform DIMSE association and service operations.
- ``NetworkDICOMULTransport`` — Connect a DIMSE association over TCP or TLS.

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

DICOMKit also writes Part 10 files through ``DICOMWriter`` and
``DICOMFile/encodedData(sequenceLengthEncoding:)``. The writer supports
Explicit VR Little Endian, Explicit VR Big Endian, Deflated Explicit VR Little
Endian, and Implicit VR Little Endian, defined- and undefined-length
sequences, and native Pixel Data. It can also serialize
caller-supplied compressed fragments through
``DICOMElement/init(encapsulatedPixelDataFrames:vr:)`` with a generated Basic
Offset Table; it does not compress samples itself.

``DICOMwebClient`` provides an async HTTP foundation for QIDO-RS study,
series, and instance searches; WADO-RS instance, metadata, rendered image,
thumbnail, frame, and BulkData retrieval; and STOW-RS multipart storage.
Inject a ``DICOMwebTransport`` to add application-specific authentication or
to test requests without a network connection.

``DICOMAssociation`` is a transport-independent DIMSE actor backed by a
caller-supplied ``DICOMULTransport``. ``NetworkDICOMULTransport`` implements TCP
or explicitly configured TLS with Network.framework, and
``NetworkDICOMULListener`` accepts inbound connections. Association negotiation
covers Implementation Class UID and Version Name, SCP/SCU Role Selection,
Asynchronous Operations Window, and User Identity, and the actor reports a peer
A-ABORT or A-RELEASE-RQ rather than treating it as an unexpected PDU.

As an SCU, ``DICOMAssociation`` performs C-ECHO, C-STORE, C-FIND, C-MOVE,
C-GET, and C-CANCEL, returning a classified ``DICOMDIMSEStatus`` and, for
C-MOVE and C-GET, ``DICOMSubOperationCounts``. C-GET takes an `onStore`
handler: the peer returns each matching instance as a C-STORE sub-operation on
a storage presentation context, and the handler's returned status is sent back
in the C-STORE-RSP. As an SCP, it accepts an
association against a ``DICOMAssociationPolicy``, receives requests through
``DICOMAssociation/receiveRequest()``, and answers them with the matching
`respondTo…` method. Applications negotiate one presentation context per SOP
Class — ``DICOMSOPClass`` lists the common UIDs — and can use the SOP Class
convenience overloads instead of passing context identifiers. This is a
protocol foundation, not a clinical interoperability or PACS conformance claim.

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
- ``DICOMModuleValidator``
- ``DICOMIODValidator``
- ``DICOMModuleRequirement``
- ``DICOMValidationIssue``

### DICOMweb

- ``DICOMwebClient``
- ``DICOMQIDOPagination``
- ``DICOMwebRetryPolicy``
- ``DICOMwebTransport``
- ``DICOMwebError``
- ``DICOMJSONDataset``
- ``DICOMJSONBulkDataResolver``

### DIMSE networking

- ``DICOMAssociation``
- ``DICOMAssociationPolicy``
- ``DICOMAssociationNegotiation``
- ``DICOMAssociationRequest``
- ``DICOMAssociationAcceptance``
- ``DICOMAssociationRejection``
- ``DICOMPresentationContext``
- ``DICOMPresentationContextAcceptance``
- ``DICOMRoleSelection``
- ``DICOMUserIdentity``
- ``DICOMUserIdentityNegotiation``
- ``DICOMImplementationIdentification``
- ``DICOMAsynchronousOperationsWindow``
- ``DICOMDIMSECommand``
- ``DICOMDIMSEStatus``
- ``DICOMDIMSERequest``
- ``DICOMSubOperationCounts``
- ``DICOMCFindResult``
- ``DICOMCMoveResult``
- ``DICOMCGetResult``
- ``DICOMCStoreRequest``
- ``DICOMSOPClass``
- ``DICOMULPDU``
- ``DICOMPDataValue``
- ``DICOMULTransport``
- ``NetworkDICOMULTransport``
- ``NetworkDICOMULListener``
- ``DICOMAssociationError``
- ``DICOMDIMSEError``
- ``DICOMULError``
- ``DICOMNetworkError``

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
