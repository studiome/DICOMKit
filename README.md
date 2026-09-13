# DICOMKit

[![Tests](https://github.com/studiome/DICOMKit/actions/workflows/tests.yml/badge.svg)](https://github.com/studiome/DICOMKit/actions/workflows/tests.yml)

Swift-first utilities for reading DICOM Part 10 files on iPadOS and macOS.

Read the API documentation for
[DICOMKit](https://studiome.github.io/DICOMKit/documentation/dicomkit/),
[DICOMKitAuthoring](https://studiome.github.io/DICOMKit/documentation/dicomkitauthoring/),
and [DICOMKitNetworking](https://studiome.github.io/DICOMKit/documentation/dicomkitnetworking/).

> **Status: early development.** DICOMKit is not yet suitable for clinical use.

See the [changelog](CHANGELOG.md) for the current implementation status.

## Current capabilities

- Validates the DICOM Part 10 preamble and `DICM` prefix
- Reads File Meta Information
- Parses datasets encoded with Explicit VR Little Endian and Implicit VR Little Endian
- Resolves a curated set of frequently used PS3.6 Value Representations during
  Implicit VR parsing, plus 5,092 unambiguous public-tag VRs generated from
  DICOM PS3.6 2025a; context-dependent or unknown defined-length attributes
  remain `UN`
- Re-derives a defined-length `UN` element's VR from the dictionary under
  Explicit VR Little Endian (PS3.5 6.2.2), including parsing a `UN` element
  the dictionary resolves to `SQ` as an Implicit VR Little Endian sequence —
  the encoding such conversions preserve. Controlled by
  `DICOMReadOptions.reinterpretsUnknownVR` (on by default) and passed to
  `DICOMFile`/`DICOMMetadataFile`; never applied to Pixel Data, private
  tags, or under Explicit VR Big Endian, where a `UN` value's always-little-endian
  bytes would be misread
- Resolves a private element's VR under Implicit VR from a caller-supplied
  `DICOMPrivateDictionary` (`DICOMReadOptions.privateDictionary`), matched
  against the Private Creator recorded earlier in the same dataset or
  sequence item. DICOMKit ships no private dictionary of its own: private
  attribute meanings are vendor-specific, and a table built from reverse
  engineering risks decoding a vendor's bytes as the wrong type
- Parses defined-length and undefined-length sequences recursively
- Exposes a lightweight Swift object model: `DICOMFile`, `DICOMDataset`,
  `DICOMElement`, `DICOMTag`, and `DICOMVR`
- Groups files into `DICOMStudy` / `DICOMSeries` / `DICOMInstance` models and
  sorts instances by image position, instance number, then SOP Instance UID
- Reads DICOMDIR Directory Record Sequences as ordered flat records, including
  record type and referenced file/SOP identifiers, and rebuilds the
  patient/study/series/instance tree from the standard offset links
- Provides a caller-configured recursive `DICOMAnonymizer` for removing or
  replacing attributes, including private tags, plus `DICOMConfidentialityProfile`,
  which resolves PS3.15's full Basic Application Level Confidentiality Profile
  attribute table (Table E.1-1, generated from the standard: 627 exact tags
  plus 3 repeating-group tags) together with any of its ten Retain/Clean
  options; `deidentify(_:replacement:)` also refuses to proceed when Burned In
  Annotation `(0028,0301)` declares identifying pixel content, and records
  what was applied in Patient Identity Removed, De-identification Method, and
  De-identification Method Code Sequence. This is real attribute-table
  coverage, not an end-to-end conformance claim: DICOMKit does not clean free
  text, structured content, or graphics (a selected Clean option is applied
  conservatively, as a removal) and never modifies pixel data, so an object
  with burned-in identifiers, or identifying free text in an attribute this
  profile keeps, is not de-identified just because this ran.
  `DICOMDeidentificationProfile.basicApplicationLevelConfidentiality` remains
  as a convenience preset built on the same generated table
- Validates caller-supplied DICOM module Type 1 and Type 2 requirements,
  including missing attributes, empty Type 1 values, and unexpected VRs; this
  is a reusable building block rather than complete IOD conformance validation;
  includes focused common validators for CT, MR, and Secondary Capture images
- Provides typed access for common string and `UInt16` values
- Converts supported in-memory datasets to and from typed DICOM JSON
  (PS3.18 Annex F), including string VRs, `US`, sequences, and inline binary
  values; resolves `BulkDataURI` only through a caller-supplied resolver
- Renders uncompressed 8-bit `MONOCHROME1`, `MONOCHROME2`, and interleaved
  `RGB` Pixel Data as `CGImage`
- Renders uncompressed 16-bit monochrome Pixel Data with correct handling of
  signed (`Pixel Representation`) samples, `Bits Stored` masking, and
  `Rescale Slope` / `Rescale Intercept`, with caller-supplied or
  dataset-derived window center and width
- Decodes single-frame 8-bit and 16-bit monochrome, plus 8-bit RGB RLE
  Lossless Pixel Data
- Decodes multi-frame RLE Lossless Pixel Data when it includes a Basic Offset
  Table, exposed as `DICOMFile.pixelDataFrames`
- Provides `DICOMFile.makeLazyPixelData()` to defer Pixel Data frame decoding
  until a consumer requests it, with thread-safe memoization of the result
- Provides `DICOMMetadataFile(url:)` to retain only metadata after initial URL
  parsing and reopen local Pixel Data when a consumer requests frames
- Exposes native Float and Double Float Pixel Data frames through
  `DICOMFile.floatingPixelDataFrames`, preserving IEEE 754 values
- Exposes Overlay Plane bitmaps, ICC Profile data, and Presentation LUT Shape
  for display layers
- Resolves Enhanced Multi-frame functional groups shared-then-per-frame
  (`DICOMFile.frameFunctionalGroups`): Pixel Value Transformation and Frame
  VOI LUT, Pixel Measures and Plane Position/Orientation (per-frame
  `DICOMFile.frameGeometries`), Frame Content (stack ID, in-stack position,
  temporal position index — resolved into display order by
  `DICOMFile.frameOrder()`), Frame Anatomy, and a per-frame Display Shutter
  that `pixelDataFrames` prefers over the dataset-level one
- Reads the Real World Value Mapping Sequence `(0040,9096)`
  (`DICOMRealWorldValueMap`), both top-level and per-frame, for quantitative
  readouts such as PET SUV — a transform separate from the Modality LUT
- Applies the Modality LUT Sequence `(0028,3000)` in the 16-bit rendering
  path, taking precedence over Rescale Slope/Intercept per PS3.3 C.11.1, and
  exposes Cine module attributes (`DICOMFile.cineAttributes`) and the Display
  Shutter module (`DICOMFile.displayShutter`), including rectangular,
  circular, and polygonal shutter shapes applied during rendering
- Parses Grayscale Softcopy Presentation States (`DICOMPresentationState`,
  SOP Class `1.2.840.10008.5.1.4.1.1.11.1`) — referenced images, spatial
  transformation, Presentation LUT Shape, Display Shutter, Softcopy VOI,
  Displayed Area, Graphic Layers, and Graphic Annotations — and applies a
  presentation state's shutter, VOI, and Presentation LUT Shape to a
  referenced file's rendered pixel data through
  `DICOMFile.pixelData(applying:)` / `pixelDataFrames(applying:)`
- Parses Structured Report Content Trees (`DICOMStructuredReport`,
  `DICOMSOPClass.structuredReport`: Basic Text/Enhanced/Comprehensive SR) —
  the recursive Content Item tree (PS3.3 C.17.3) covering every SR Value
  Type (`CONTAINER`, `TEXT`, `CODE`, `NUM`, `DATE`/`TIME`/`DATETIME`,
  `UIDREF`, `PNAME`, `IMAGE`, `WAVEFORM`, `COMPOSITE`, `SCOORD`/`SCOORD3D`,
  `TCOORD`), plus `plainText()`/`walk(_:)`/`items(withValueType:)` for
  reading it. A bounded recursion depth guard keeps a malformed or hostile
  Content Sequence from exhausting the stack. Templates (TID 1500 and
  similar) are not interpreted and no meaning is imposed on a concept name;
  by-reference relationships (`Referenced Content Item Identifier`) are
  exposed but not resolved into the tree
- Decodes JPEG Lossless, Non-Hierarchical (Process 14) Pixel Data for `.57`
  and `.70`: single-component `MONOCHROME1` / `MONOCHROME2` and interleaved
  1:1:1 `RGB`, with 2–16-bit precision, Selection Values 1–7, Point Transform,
  restart markers, and multi-frame Basic Offset Tables. `.70` is constrained
  to Selection Value 1 as required by its transfer syntax.
- Decodes JPEG-LS Lossless (`.80`) monochrome 8-bit and 16-bit Pixel Data,
  plus sample-interleaved 8-bit `RGB` and `YBR_FULL` (returned as `RGB`); supports default and explicit Preset
  Coding Parameters, restart markers, multi-frame Basic Offset Tables, and
  plane-interleaved 8-bit `RGB` frames.
  JPEG-LS Near-Lossless (`.81`) supports monochrome and sample-interleaved
  `RGB` 8-bit Pixel Data. The
  JPEG-LS coverage is verified with BSD-3-Clause CharLS-generated reference
  streams.
- Decodes 8-bit JPEG Baseline (Process 1) Pixel Data with libjpeg-turbo 3.1.3,
  and JPEG 2000 Lossless / JPEG 2000 Pixel Data with ImageIO, as either
  interleaved `RGB` (whatever color space the JPEG itself uses, including
  `YBR_FULL_422`) or single-sample
  `MONOCHROME1` / `MONOCHROME2`; multiple frames use a Basic Offset Table,
  Extended Offset Table, or one-fragment-per-frame empty Basic Offset Table
- Recognises and opens the three High-Throughput JPEG 2000 (HTJ2K) transfer
  syntaxes (`.201`, `.202`, `.203`), exposing their encapsulated fragments
  like any other transfer syntax. Pixel Data is routed through the same
  ImageIO path as JPEG 2000, since HTJ2K is a JPEG 2000 codestream with a
  different block coder — but DICOMKit bundles no HTJ2K codec of its own, so
  whether a given HTJ2K stream actually decodes depends entirely on the
  host platform's ImageIO. `TransferSyntax.hasPixelDataDecoder` reports
  `true` for HTJ2K (DICOMKit will attempt a decode) without promising that
  attempt succeeds; `DICOMFile.pixelDataFrames` is `nil` for a stream
  ImageIO can't decode, the same as any other unsupported Pixel Data
- Writes DICOM Part 10 files using Explicit VR Little Endian, Explicit VR Big
  Endian, Deflated Explicit VR Little Endian, or Implicit VR Little Endian,
  including defined- or undefined-length Sequences and native Pixel Data;
  writes caller-supplied compressed fragments with generated Basic Offset
  Tables for supported encapsulated transfer syntaxes; `DICOMWriter.encodeDataset`
  emits a bare dataset without File Meta Information for DIMSE transfer
- Provides async DICOMweb clients for QIDO-RS study/series/instance searches,
  WADO-RS instance/metadata/rendered-image/thumbnail/frame/BulkData retrieval, and STOW-RS multipart
  instance storage; WADO metadata can also be decoded as typed DICOM JSON;
  QIDO-RS `limit` / `offset` pagination and transports are injectable for
  application authentication and testing; callers can opt into transient HTTP
  response retries
- Provides a DIMSE SCU and SCP foundation:
  - DICOM Upper Layer association PDUs, including Implementation Class UID and
    Version Name, SCP/SCU Role Selection, Asynchronous Operations Window, and
    User Identity negotiation with its server response
  - A-ABORT and peer-initiated A-RELEASE handling, plus response timeouts
  - Network.framework TCP/TLS transport, and `NetworkDICOMULListener` for
    inbound connections
  - SCU services: C-ECHO, C-STORE, C-FIND, C-MOVE, C-GET, and C-CANCEL, with
    classified DIMSE statuses and C-MOVE / C-GET sub-operation counts; C-GET
    delivers each retrieved instance to a caller-supplied handler and answers
    the peer with the status it returns
  - SCP services: association acceptance and presentation-context negotiation
    driven by a `DICOMAssociationPolicy`, `receiveRequest()`, and C-ECHO,
    C-STORE, C-FIND, C-MOVE, and C-GET responses
  - DIMSE-N (Normalized) services on both sides: N-CREATE, N-SET, N-GET,
    N-ACTION, N-DELETE, and N-EVENT-REPORT, returning/accepting a
    `DICOMNServiceResult`; Storage Commitment Push Model
    (`requestStorageCommitment(messageID:contextID:_:)`,
    `DICOMStorageCommitmentRequest`/`Result`) and Modality Performed
    Procedure Step (`createPerformedProcedureStep`,
    `updatePerformedProcedureStep`) are built on top
  - `DICOMSOPClass` well-known SOP Class UIDs, and file-based C-STORE through
    `DICOMFile.encodedDatasetData(transferSyntax:)`
  - This is a protocol foundation, not a PACS conformance claim
- Uses the BSD-3-Clause CharLS codec through a Git submodule for JPEG-LS
  decoding, including sample, line, and plane interleave modes

## Codec backends

| DICOM transfer syntax | Decoder | Current scope |
| --- | --- | --- |
| JPEG Baseline `.50` | libjpeg-turbo 3.1.3 (TurboJPEG API) | 8-bit `RGB` and monochrome output; JPEG color spaces are converted to output RGB. |
| JPEG Lossless `.57`, `.70` | libjpeg-turbo 3.1.3 (TurboJPEG API) | 2–16-bit monochrome and single-scan, 1:1:1 interleaved `RGB`; `.70` requires Selection Value 1. |
| JPEG-LS `.80`, `.81` | CharLS Git submodule | Lossless and Near-Lossless; supported interleave modes are listed above. |
| JPEG 2000 `.90`, `.91` | ImageIO | 8-bit `RGB` or monochrome output. |
| HTJ2K `.201`, `.202`, `.203` | ImageIO (same path as JPEG 2000) | Recognised, opened, and routed to ImageIO; decoding depends on the host platform's ImageIO supporting HTJ2K's block coder — DICOMKit ships no HTJ2K codec and has no HTJ2K fixture to verify decode against. `pixelDataFrames` is `nil` when ImageIO rejects the stream. |

libjpeg-turbo is the primary decoder for JPEG Baseline and JPEG Lossless
Process 14. DICOMKit retains responsibility for fragment reassembly, transfer
syntax restrictions, dimensions, component count, `Bits Allocated`, `Bits
Stored`, and 16-bit little-endian storage. The previous Process 14 decoder is
kept as a temporary fallback for streams that TurboJPEG rejects (including the
current restart-marker regression fixture) while both implementations are
compared against fixtures.

```swift
let file = try DICOMFile(data: data)

let patientName = file.dataset[.patientName]?.stringValue
let rows = file.dataset[.rows]?.uint16Value
let columns = file.dataset[.columns]?.uint16Value
let referencedStudies = file.dataset[.referencedStudySequence]?.sequenceItems

let dicomJSON = DICOMJSONDataset(dataset: file.dataset)
let restoredDataset = try dicomJSON.dicomDataset()

if let pixelData = file.pixelData {
    // For 16-bit monochrome data, windowCenter/windowWidth are in the
    // *rescaled* unit (Hounsfield Units for CT), not raw stored values,
    // since each sample is rescaled as `storedValue * rescaleSlope +
    // rescaleIntercept` before windowing. 40/400 here is a typical CT
    // soft-tissue window. If omitted, the window defaults to the dataset's
    // own Window Center/Width `(0028,1050)`/`(0028,1051)` when present, or
    // otherwise to a window computed from the rescaled pixel data's
    // min/max value.
    let image = try pixelData.cgImage(windowCenter: 40, windowWidth: 400)
}
```

For views that may never display an image, defer frame decoding until it is
needed:

```swift
let lazyPixelData = file.makeLazyPixelData()
let firstFrame = lazyPixelData?.loadFirstFrame()
```

```swift
let client = DICOMwebClient(baseURL: URL(string: "https://pacs.example.com/dicomweb")!)
let studies = try await client.searchStudies(query: [
    URLQueryItem(name: "PatientName", value: "Doe*")
])
let instance = try await client.retrieveInstance(
    studyInstanceUID: "1.2.3",
    seriesInstanceUID: "4.5.6",
    sopInstanceUID: "7.8.9"
)
```

Query a remote Application Entity over DIMSE, then release the association:

```swift
let transport = try NetworkDICOMULTransport(host: "pacs.example.com", port: 104)
let association = DICOMAssociation(transport: transport, responseTimeout: .seconds(30))
try await association.request(DICOMAssociationRequest(
    calledAETitle: "PACS",
    callingAETitle: "DICOMKIT",
    presentationContexts: [
        DICOMPresentationContext(
            id: 1,
            abstractSyntaxUID: DICOMSOPClass.studyRootQueryRetrieveFind,
            transferSyntaxUIDs: [TransferSyntax.explicitVRLittleEndian.uid]
        )
    ]
))
let matches = try await association.cFind(
    messageID: 1,
    sopClassUID: DICOMSOPClass.studyRootQueryRetrieveFind,
    identifier: try DICOMWriter.encodeDataset(query)
)
try await association.release()
```

Accept inbound associations and store what a peer sends:

```swift
let policy = DICOMAssociationPolicy(
    calledAETitles: ["DICOMKIT"],
    supportedAbstractSyntaxes: DICOMSOPClass.imageStorage,
    supportedTransferSyntaxes: [TransferSyntax.explicitVRLittleEndian.uid]
)
let listener = try NetworkDICOMULListener(port: 11112)
try await listener.start()

let transport = try await listener.accept()
let association = DICOMAssociation(transport: transport)
try await association.accept(try await association.receiveAssociationRequest(), policy: policy)
let store = try await association.receiveCStore()
try await association.respond(to: store, status: .success)
```

## Requirements

- Xcode 26.6 or later
- Swift 6 (language mode) / Swift Package Manager 6.0 or later
- iPadOS 16.0 or later
- macOS 14.0 or later

## Installation

The package ships three products, so a consumer links only what it needs:

| Product | Adds | Depends on | Needed by |
| --- | --- | --- | --- |
| `DICOMKit` | Parsing, rendering, navigation, dataset serialization | — | Every consumer, including a read-only viewer |
| `DICOMKitAuthoring` | Part 10 file writing, the anonymizer, the PS3.15 confidentiality profile, module validation, UID generation | `DICOMKit` | An app that writes files, de-identifies datasets, or validates against module requirements |
| `DICOMKitNetworking` | DIMSE association services (C-ECHO/C-STORE/C-FIND/C-MOVE/C-GET, N-service SCU/SCP), DICOMweb, DICOM JSON | `DICOMKit` | An app that talks to a PACS or a DICOMweb server |

`DICOMKitNetworking` does not depend on `DICOMKitAuthoring`: a DIMSE service
that needs to encode a dataset (C-STORE) uses `DICOMKit`'s own
`DICOMFile.encodedDatasetData(transferSyntax:sequenceLengthEncoding:)`, not a
Part 10 file writer. A viewer that only opens local files needs `DICOMKit`
alone; an app that also retrieves from a PACS and exports de-identified
studies links all three.

### Swift Package Manager

Add DICOMKit as a dependency in `Package.swift`:

```swift
dependencies: [
    // No tagged release yet; pin to a commit once DICOMKit cuts one.
    .package(url: "https://github.com/studiome/DICOMKit", branch: "main")
]
```

Then add the products your target actually needs to its `dependencies` — for
example, a viewer:

```swift
.target(
    name: "MyViewer",
    dependencies: [.product(name: "DICOMKit", package: "DICOMKit")]
)
```

or an app that also writes files and talks to a PACS:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "DICOMKit", package: "DICOMKit"),
        .product(name: "DICOMKitAuthoring", package: "DICOMKit"),
        .product(name: "DICOMKitNetworking", package: "DICOMKit")
    ]
)
```

### Xcode

Alternatively, add `https://github.com/studiome/DICOMKit` via
**File > Add Package Dependencies…** in Xcode, then check the products your
target needs (`DICOMKit`, `DICOMKitAuthoring`, `DICOMKitNetworking`) in the
package's product picker.

## Development

DICOMKit is defined exclusively by `Package.swift`: it owns the three library
targets and the test target, platform versions, resources, dependencies, and
CI build inputs. The library targets live in `DICOMKit/`, `DICOMKitAuthoring/`,
and `DICOMKitNetworking/` at the repository root, each with its own DocC
catalog; the single `DICOMKitTests` target covers all three, importing
whichever products each test file exercises. Open `Package.swift` directly in
Xcode for normal development, or run the test suite from the command line:

```bash
swift test
```

CharLS is a Git submodule pinned to an exact upstream commit, rather than a
source copy maintained in this repository. Clone DICOMKit with
`--recurse-submodules`, or initialize it after cloning:

```bash
git submodule update --init --recursive
```

To deliberately update CharLS, provide an upstream tag or commit to the helper
script. Review the resulting submodule SHA and run the test suite before
committing it:

```bash
./Scripts/update-charls.sh <tag-or-commit>
swift test
```

libjpeg-turbo is a SwiftPM binary target, downloaded from the pinned 3.1.3
release URL and verified with the SHA-256 checksum in `Package.swift`. No
system installation is required. To update it, change both the release URL and
checksum together, then run the macOS tests and the iOS build below.

To compile the package for iOS and iPadOS:

```bash
swift build \
  --triple arm64-apple-ios16.0 \
  --sdk "$(xcrun --sdk iphoneos --show-sdk-path)"
```

To run the same test suite on the iOS Simulator:

```bash
xcodebuild test \
  -scheme DICOMKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

### Performance benchmarks

`DICOMKitBenchmark`, an executable target depending on `DICOMKit` alone,
measures dataset parse, series open, metadata-only open, per-frame decode,
and render. It is a developer tool, not a `swift test` gate — see
[Docs/benchmarks.md](Docs/benchmarks.md) for why timing assertions don't
belong in the test suite, and for the recorded baseline. Always build
release; a debug build's numbers are dominated by unoptimized bounds
checking and are not representative:

```bash
swift build -c release
swift run -c release DICOMKitBenchmark            # default iteration count
swift run -c release DICOMKitBenchmark 50         # override: 50 iterations
```

### Continuous integration

GitHub Actions runs the same commands on every push to `main` and on every
pull request:

- `.github/workflows/tests.yml` builds and tests the package on macOS, builds
  it for iOS and iPadOS, and runs `DICOMKitTests` on the iOS Simulator.
- `.github/workflows/publish-docs.yml` builds all three products' DocC
  catalogs, merges them into one documentation archive with a combined
  landing page, and publishes it to GitHub Pages on every push to `main`.

## Roadmap

No outstanding high-impact (B-rated) gaps. See [Docs/roadmap.md](Docs/roadmap.md)
for lower-priority (C-rated) items and how they are prioritized.

## License

DICOMKit is available under the [MIT License](LICENSE).
Its JPEG codec dependencies, CharLS and libjpeg-turbo, have their own license
terms; see [third-party notices](THIRD_PARTY_NOTICES.md).
