# Changelog

All notable changes to DICOMKit are documented here.

## v0.5 — Unreleased

- Added the three High-Throughput JPEG 2000 (HTJ2K) transfer syntaxes —
  `.201` (Lossless Only), `.202` (RPCL Options, Lossless Only), and `.203` —
  to `TransferSyntax`. A dataset declaring any of these now opens and its
  encapsulated Pixel Data fragments are reachable; previously such a file
  failed to open at all. Pixel Data is routed through the same
  ImageIO-backed decoder as JPEG 2000 Lossless / JPEG 2000, since HTJ2K is a
  JPEG 2000 codestream that only changes the block coder — but DICOMKit
  bundles no HTJ2K codec, so whether a given stream actually decodes depends
  on the host platform's ImageIO. Added `TransferSyntax.hasPixelDataDecoder`
  so callers can tell "DICOMKit cannot show this kind of image" (`false`)
  from "DICOMKit could not show this particular image"
  (`true`, but `DICOMFile.pixelDataFrames` is `nil`).
- Added `DICOMReadOptions`, passed as a trailing parameter to `DICOMFile` and
  `DICOMMetadataFile` (existing call sites are unaffected by the default).
  `reinterpretsUnknownVR` (on by default) re-derives a defined-length `UN`
  element's VR from the dictionary under Explicit VR Little Endian, per
  PS3.5 6.2.2 — the usual fix for data that passed through middleware which
  converted Implicit VR to Explicit VR without a dictionary of its own. A
  `UN` element the dictionary resolves to `SQ` is parsed as an Implicit VR
  Little Endian sequence, reusing the existing sequence reader, since that's
  the encoding such a conversion preserves; unparseable bytes fall back to
  `UN` instead of failing the whole dataset. This never touches Pixel Data,
  private tags, tags absent from the dictionary, or Explicit VR **Big**
  Endian, where a `UN` value's always-little-endian bytes would otherwise be
  read with the wrong byte order.
- Added `DICOMPrivateDictionary` and `DICOMPrivateTagEntry`, a mechanism for
  an application to supply its own vendor-documented private attribute VRs
  via `DICOMReadOptions.privateDictionary`. DICOMKit ships none itself:
  private attribute meanings are vendor-specific and unpublished, and a
  dictionary sourced from reverse engineering can make DICOMKit read a
  vendor's bytes as the wrong type — being unable to read a private
  attribute is safer than reading it wrongly. When supplied, a private
  element's VR under Implicit VR is resolved from the Private Creator
  recorded earlier in the same dataset or sequence item; `Reader` tracks
  creators in a single forward pass and resets them at each sequence item
  boundary, since a creator declared in a parent dataset doesn't extend into
  an item. `DICOMDataset.privateCreator(for:)` and
  `privateElement(creator:group:element:)`, which already existed, are
  unaffected.
- Added full Enhanced Multi-frame functional group resolution. Generalized
  the shared-then-per-frame merge that previously only handled Pixel Value
  Transformation and Frame VOI LUT into `DICOMFrameFunctionalGroups`
  (`DICOMFile.frameFunctionalGroups`), and used it to resolve: Pixel
  Measures and Plane Position/Orientation, combined per frame into
  `DICOMImageGeometry` by `DICOMFile.frameGeometries`; Frame Content (Stack
  ID, In-Stack Position Number, Temporal Position Index), resolved into
  display order by `DICOMFile.frameOrder()`, which groups frames by stack
  and leaves a group with no ordering keys in stored order rather than
  reordering it arbitrarily; Frame Anatomy (laterality and anatomic region,
  via the new shared `DICOMCodeSequenceItem`); and a per-frame Frame
  Display Shutter that `pixelDataFrames` now prefers over the dataset-level
  `DICOMDisplayShutter` when a frame declares one.
- Added `DICOMRealWorldValueMap` for the Real World Value Mapping Sequence
  `(0040,9096)`, exposed both on `DICOMFile` and per frame on
  `DICOMFrameFunctionalGroups`. Handles the US/SS Pixel Representation
  dependency for First/Last Value Mapped and the mutually exclusive
  slope/intercept and LUT-data forms. This is the transform a PET viewer
  uses for Standardized Uptake Value, kept separate from the Modality LUT
  because it produces a value to report, not one to window.
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
- Fixed C-GET discarding every instance it retrieved. The C-STORE
  sub-operations the peer sends on the storage presentation contexts were
  filtered out of the receive loop and never answered, so the operation
  reported success while delivering nothing. `cGet` now takes an `onStore`
  handler, reassembles each sub-operation, and sends the C-STORE-RSP.
- Fixed `responseTimeout` never firing against `NetworkDICOMULTransport`: the
  timeout task group awaited a receive that ignores cancellation, so the call
  hung instead of throwing. `DICOMULTransport.close()` is now documented to
  unblock an in-flight `receive()`, and a timeout closes the transport.
- Fixed a trap when a User Information sub-item exceeded 64 KB; oversized user
  identity credentials and server responses now throw `pduTooLarge`.
- Fixed `cFind` reporting each fragment of a split identifier as a separate
  match, invalid presentation context IDs being accepted on decode and only
  rejected while encoding the response, a crash negotiating a presentation
  context proposed with no transfer syntaxes, a missing Command Data Set Type
  being read as "a data set follows", and a peer's absent Implementation Class
  UID being reported as DICOMKit's own.
- Fixed `NetworkDICOMULListener` leaking a continuation when the task awaiting
  `accept()` was cancelled, and leaving queued connections open on `stop()`.
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
- Added `DICOMFile.pixelDataFrames` support for the Modality LUT Sequence
  `(0028,3000)`, `DICOMFile.cineAttributes` for the Cine module (PS3.3
  C.7.6.5), and `DICOMFile.displayShutter` for the Display Shutter module
  (PS3.3 C.7.6.11), applied during 16-bit and 8-bit rendering.
- Added `DICOMPresentationState` to parse Grayscale Softcopy Presentation
  States (SOP Class `1.2.840.10008.5.1.4.1.1.11.1`): referenced images,
  spatial transformation, Presentation LUT Shape, Display Shutter, Softcopy
  VOI, Displayed Area, Graphic Layers, and Graphic Annotations. Added
  `DICOMFile.pixelData(applying:)` / `pixelDataFrames(applying:)` to
  substitute a presentation state's shutter, VOI, and Presentation LUT Shape
  into a referenced file's rendered pixel data, and
  `DICOMPixelData.presentationLUTShape`, which composes with `MONOCHROME1`
  polarity as an exclusive-or rather than replacing it.
- Added the DIMSE-N (Normalized) services to `DICOMAssociation`: N-CREATE,
  N-SET, N-GET, N-ACTION, N-DELETE, and N-EVENT-REPORT, as both SCU
  (`nCreate`/`nSet`/`nGet`/`nAction`/`nDelete`/`nEventReport`, each with a
  SOP-Class convenience overload, returning a new `DICOMNServiceResult`) and
  SCP (`respondToNCreate`/`NSet`/`NGet`/`NAction`/`NDelete`/`NEventReport`).
  `receiveRequest()` needed no change, since its `DICOMDIMSECommand.hasDataset`-
  driven reassembly already generalizes to the N-services, whose data set is
  conditional rather than fixed by command kind. Built on top:
  - Storage Commitment Push Model (`1.2.840.10008.1.20.1`):
    `DICOMStorageCommitmentRequest.actionInformation(transferSyntax:)` builds
    the N-ACTION Action Information (Transaction UID and Referenced SOP
    Sequence), `DICOMStorageCommitmentResult.init(eventInformation:transferSyntax:)`
    parses the eventual N-EVENT-REPORT's Event Information (committed and
    failed SOP references, with failure reasons), and
    `DICOMAssociation.requestStorageCommitment(messageID:contextID:_:)` sends
    the N-ACTION against the well-known SOP Instance
    (`DICOMSOPClass.storageCommitmentPushModelInstance`, also added). Its doc
    comment calls out explicitly that the commitment result is *not* the
    N-ACTION response — it arrives later as an N-EVENT-REPORT, either on the
    same association via SCP/SCU role selection or a fresh inbound one via
    `NetworkDICOMULListener`, both already supported.
  - Modality Performed Procedure Step (`1.2.840.10008.3.1.2.3.3`):
    `createPerformedProcedureStep` sends N-CREATE, forcing Performed
    Procedure Step Status `(0040,0252)` to `IN PROGRESS` regardless of what
    the caller's dataset carried; `updatePerformedProcedureStep` sends
    N-SET to move the status to `.completed` or `.discontinued`, throwing
    the new `DICOMAssociationError.invalidProcedureStepTransition` for
    `.inProgress`, since a step only ever enters `IN PROGRESS` through
    N-CREATE. Neither method assembles the rest of the required MPPS
    attribute set — that stays the caller's responsibility, checked with
    `DICOMModuleValidator` — since the set is long and modality-specific and
    guessing at it would produce data that looks conformant without being so.
- Added `DICOMStructuredReport` and `DICOMContentItem`/`DICOMContentItemValue`,
  parsing an SR's Content Tree (PS3.3 C.17.3): the dataset itself is the root
  Content Item, and each item's Content Sequence `(0040,A730)` holds its
  children recursively. Every SR Value Type is modeled — `CONTAINER`, `TEXT`,
  `CODE`, `NUM` (Measured Value Sequence, with a Numeric Value Qualifier Code
  Sequence fallback when there's no measurement), `DATE`/`TIME`/`DATETIME`,
  `UIDREF`, `PNAME`, `IMAGE`, `WAVEFORM`, `COMPOSITE`, `SCOORD`/`SCOORD3D`, and
  `TCOORD` — with an unrecognized Value Type falling back to
  `.unsupported(valueType:)` without dropping its children. Text and Person
  Name values are decoded with the item's own Specific Character Set,
  inherited from the enclosing item when it declares none, the same rule
  already used for Presentation States. Parsing bounds its own recursion
  depth, throwing the new `DICOMError.invalidStructuredReport` instead of
  exhausting the stack on a malformed or hostile Content Sequence, and on a
  dataset with no Value Type at all (which means it isn't an SR).
  `DICOMStructuredReport.plainText(indent:)` renders a debugging/fallback
  view of the tree; `walk(_:)` and `items(withValueType:)` read it
  programmatically. Added `DICOMSOPClass.structuredReport` (Basic Text,
  Enhanced, and Comprehensive SR). This is deliberately a faithful tree
  parse, not template interpretation: TID 1500 and similar templates are not
  understood, no meaning is imposed on a concept name, and by-reference
  relationships (Referenced Content Item Identifier `(0040,DB73)`) are
  exposed raw rather than resolved into `children`, since that would turn a
  tree into a graph the `children` model cannot represent.

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
