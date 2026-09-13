# Viewer profile

A scoping note for using DICOMKit as a **viewer-only** library: what a viewer
actually needs, what it does not, and how to separate the two without forking.

Status: implemented. See [Implementation notes](#implementation-notes) at the
end of this document for what was actually built and how it differs from the
proposal below.

## Why separate at all

DICOMKit currently ships one target. A viewer that links it also links a DIMSE
association state machine, a TCP/TLS listener, and an HTTP client it will never
call.

The saving is **not** mainly binary size. A viewer cannot drop the codecs, and
the codecs are what cost megabytes:

| Bucket | Lines | Note |
| --- | ---: | --- |
| Generated PS3.6 dictionary | 5,109 | Required for Implicit VR parsing |
| Core parse + render + hierarchy | 2,931 | Required |
| Codecs (RLE / JPEG / JPEG-LS) | 805 | Required; pulls CharLS and libjpeg-turbo |
| DIMSE + DICOMweb + DICOM JSON | 2,429 | **Removable for a viewer** |
| Writer / anonymizer / validator / UID | 436 | **Removable for a viewer** |
| Total | 11,727 | |

Removing the last two buckets drops 2,865 lines — 24% of the package, and 43%
of everything that is not the generated dictionary.

The real wins are the ones that are hard to measure in bytes:

1. **No network code path at all.** A viewer that cannot open a socket is much
   easier to argue about in a medical-device or App Store review, and removes
   an entire class of vulnerability from a target that parses untrusted files.
2. **No write path.** A viewer that cannot serialize a dataset cannot
   accidentally emit a corrupted or mis-anonymized study.
3. **Smaller API surface to keep stable.** The DIMSE API is the least settled
   part of the package and is still changing shape; a viewer should not be
   coupled to that churn.

## Necessary for a viewer

Everything below is required. None of it should move out of the core target.

**Parsing and object model** — `DICOMFile`, `Reader`, `DICOMDataset`,
`DICOMElement`, `DICOMTag`, `DICOMVR`, `DICOMError`,
`DICOMFileMetaInformation`, `TransferSyntax`, and the generated PS3.6
dictionary. The dictionary is large but not optional: without it, Implicit VR
Little Endian datasets cannot be typed, and Implicit VR is still what a great
deal of archived data is stored in.

**Text** — `DICOMCharacterSet`, `DICOMPersonName`. A viewer displays patient
names; for Japanese data the three-component person name and Shift_JIS /
ISO 2022 IR 87 handling are load-bearing, not decorative.

**Rendering** — `DICOMPixelData`, `PhotometricInterpretation`,
`DICOMPaletteColorLUT`, `DICOMVOILUT`, `DICOMWindowPreset`,
`DICOMImageGeometry`, `DICOMDisplayMetadata`, `DICOMImageError`,
`EncapsulatedPixelData`.

**Codecs** — RLE, JPEG Baseline, JPEG Lossless Process 14, JPEG-LS, JPEG 2000.
None can be dropped for a general-purpose viewer:

- JPEG Lossless `.57` / `.70` is common in CT and MR archives.
- JPEG-LS `.80` / `.81` is used by Japanese CR/DX vendors; dropping CharLS
  would break real local data.
- JPEG 2000 rides on ImageIO and therefore costs nothing extra.

**Memory discipline** — `DICOMLazyPixelData`, `DICOMMetadataFile`. On iPadOS
these are what make a large series openable at all, so they belong in the
minimum set rather than in an "advanced" tier.

**Navigation** — `DICOMHierarchy` (study/series/instance grouping and ordering)
and `DICOMDirectory` (opening a DICOMDIR from removable media or a folder).

**Compression plumbing** — `DeflateCodec` / `CZlib`. Deflated Explicit VR is
uncommon, but zlib is a system library, so the cost of keeping it is zero.

## Not necessary for a viewer

| Component | Lines | Why a viewer does not need it |
| --- | ---: | --- |
| `DICOMUL`, `DICOMAssociation`, `DICOMDIMSE`, `DICOMAssociationPolicy`, `NetworkDICOMULTransport`, `NetworkDICOMULListener`, `DICOMSOPClass` | 1,756 | A local-file viewer never opens an association. |
| `DICOMwebClient` | 293 | Same, over HTTP. |
| `DICOMJSON` | 380 | Exists to serve DICOMweb metadata; nothing in the display path reads it. |
| `DICOMWriter`, `DICOMUIDGenerator` | 220 | A viewer does not serialize datasets or mint UIDs. |
| `DICOMAnonymizer` | 97 | De-identification matters when data leaves the device. A viewer that cannot export cannot leak. |
| `DICOMModuleValidator` | 119 | Conformance validation is the *creator's* responsibility. A viewer should render what it is given and degrade gracefully, not refuse. |

`DICOMFloatingPixelData` (17 lines) is borderline — Float and Double Float
Pixel Data appear almost only in parametric maps — but it is small enough that
splitting it out is not worth the seam. Keep it in core.

### The judgement calls

Two of these flip depending on what "viewer" means:

- **If the viewer retrieves from a PACS**, then C-FIND / C-MOVE / C-GET and
  `DICOMSOPClass` come back in, and only the SCP half (listener, association
  acceptance, `DICOMAssociationPolicy`, the `respondTo…` helpers) is dead
  weight. A DICOMweb-only viewer needs `DICOMwebClient` and `DICOMJSON` but
  still no DIMSE.
- **If the viewer exports** — burn-in annotations to a Secondary Capture, share
  an anonymized study — then `DICOMWriter`, `DICOMUIDGenerator`, and
  `DICOMAnonymizer` all come back, as a set.

So the split should not be viewer-vs-everything. It should be **core /
networking / authoring**, and a given app picks the products it needs.

## Proposed shape

Split the single target into three, in one package:

```
DICOMKit            parse + render + navigate      (no networking, no writing)
DICOMKitNetworking  DIMSE + DICOMweb + DICOM JSON  depends on DICOMKit
DICOMKitAuthoring   writer + UID + anonymizer + validator
                                                   depends on DICOMKit
```

Expose all three as products so a viewer declares only `DICOMKit`.

This is preferable to deleting code on a fork: the code stays in one place, one
test suite, one CI run, and the viewer's dependency is enforced by the module
boundary rather than by discipline.

### Seams to cut

The split is mostly mechanical, with three real seams:

1. `DICOMFile.encodedData(sequenceLengthEncoding:)` and
   `DICOMFile.encodedDatasetData(transferSyntax:sequenceLengthEncoding:)` call
   `DICOMWriter`. Move both to an extension in `DICOMKitAuthoring`. Cross-module
   extensions on a public type make this source-compatible for anyone who
   imports both.
2. `DICOMAssociation.cStore(messageID:file:)` needs `DICOMFile` *and*
   `DICOMWriter`, so it lands in `DICOMKitNetworking` with a dependency on
   `DICOMKitAuthoring` — or the encoding step moves to the caller. Prefer the
   latter: it keeps networking independent of authoring.
3. `Package.swift` currently attaches CharLS, libjpeg-turbo, and CZlib to one
   target. All three follow the core, since they are codec dependencies.

Nothing in the current test suite crosses these seams except the tests for the
moved APIs themselves, which move with them.

## What a viewer is actually missing

Trimming is the smaller half of the work. Measured against what a clinical
viewer is expected to do, these gaps matter more than any of the removals
above, roughly in order of how often they bite:

1. **Modality LUT Sequence.** Only Rescale Slope / Intercept is honoured. A
   dataset carrying a Modality LUT Sequence instead renders with the wrong
   value scale.
2. **Grayscale Softcopy Presentation State.** `DICOMSOPClass` names the UID,
   but nothing reads a GSPS and applies it — annotations, shutters, spatial
   flip/rotate, and the VOI it prescribes are all ignored. A viewer that shows
   an image without its presentation state can show something clinically
   different from what the sender intended.
3. **Display Shutter Module.** Circular, rectangular, and polygonal shutters
   are not applied, so irrelevant image periphery stays visible.
4. **Cine attributes.** Frame Time, Frame Time Vector, and Recommended Display
   Frame Rate are not surfaced, so multi-frame playback has no timebase.
5. **Per-frame Functional Groups.** Enhanced multi-frame resolution is partial;
   per-frame geometry and pixel-value transforms are not fully resolved.
6. **Character set code extensions.** `(0008,0005)` is read as a single value,
   so a dataset that switches character sets mid-name decodes incorrectly.
   Korean, Chinese, Cyrillic, and Arabic are not covered at all.
7. **HTJ2K `.201`–`.203`.** Increasingly common in DICOMweb delivery.
8. **Structured Report display.** No content-tree model, so reports stored as
   SR cannot be shown at all.
9. **Ultrasound Region Calibration.** Needed before on-image measurement is
   trustworthy for US.

Items 1–4 are small and high-value; they are the natural first work on this
branch.

## Implementation notes

The split above is implemented as proposed, in three commits: raising
internal declarations shared across the future module boundary to `package`
access (and relocating two declarations that turned out to be misplaced,
below), the physical `git mv` and `Package.swift` changes, and this
documentation. `Package.swift` declares three library products —
`DICOMKit`, `DICOMKitAuthoring`, `DICOMKitNetworking` — each also a target at
the repository root (`DICOMKit/`, `DICOMKitAuthoring/`, `DICOMKitNetworking/`),
matching the existing `path:` convention. `CharLS`, `CTurboJPEG`, and `CZlib`
stay attached to `DICOMKit`, as this document originally said they should.

### The `DICOMWriter` seam, as actually cut

The clean split held: `DICOMWriter.encodeDataset(_:transferSyntax:sequenceLengthEncoding:)`,
`DICOMWriter.SequenceLengthEncoding`, and the private `append`/
`encodedSequence`/`paddedValue`/`bigEndianValue`/`appendItem` machinery it
needs all stayed in `DICOMKit`. `DICOMWriter.write(metaInformation:dataset:transferSyntax:requiredMetaInformation:sequenceLengthEncoding:)`
and `DICOMFile.encodedData(sequenceLengthEncoding:)` moved to
`DICOMKitAuthoring`, each as an extension in a new file
(`DICOMWriter+Part10.swift`, `DICOMFile+Authoring.swift`) — cross-module
extensions on public core types, exactly as this document predicted, needed
no fallback to keeping the whole of `DICOMWriter` in core. The only addition
needed inside core: `DICOMWriter.append` and `TransferSyntax.isWritable` (both
used by the Part 10 assembly code that moved out) went from `private`/
`internal` to `package`, since a same-file `private` no longer works once the
caller is in a different file *and* a different module.

### Where this document's assumption about networking was wrong

This document assumed, in "Seams to cut" above, that `DICOMAssociation.cStore(messageID:file:)`
would force a choice between `DICOMKitNetworking` depending on
`DICOMKitAuthoring` or moving the encoding step to the caller, and recommended
the latter. That choice turned out to already be made: `cStore(messageID:file:)`
was already calling `DICOMFile.encodedDatasetData(transferSyntax:sequenceLengthEncoding:)`
— the core-only, non-Part-10 encoder — rather than `DICOMFile.encodedData(sequenceLengthEncoding:)`.
So `DICOMKitNetworking` needed no change at this seam and has no dependency on
`DICOMKitAuthoring`, as required.

### Two reverse dependencies this document didn't anticipate

Mapping every file to a target surfaced two core types that had been living
in what was about to become a sibling module, each because a core file used
them:

- `DICOMSOPReference` (SOP Class UID + SOP Instance UID pair) was declared in
  `DICOMStorageCommitment.swift`, but `DICOMStructuredReport.swift` — core —
  uses it for IMAGE, WAVEFORM, and COMPOSITE content items. It moved to
  `DICOMSOPClass.swift`, staying in core.
- `DICOMBurnedInAnnotationStatus` and the `DICOMDataset.burnedInAnnotation`
  extension were declared in `DICOMDeidentificationModel.swift`, but
  `DICOMFile.burnedInAnnotation` — core, and itself part of the viewer's
  necessary-for-a-viewer surface — exposes them directly. Both moved to
  `DICOMDataset.swift`, staying in core; `DICOMConfidentialityProfile.deidentify(_:replacement:)`
  in `DICOMKitAuthoring` now just consumes `DICOMFile.burnedInAnnotation` as
  public core API rather than owning its type.

Neither move changed any public API's module in a way existing call sites
would notice differently from the rest of the split — both symbols were
already `public`; only the file (and now the module) they live in changed.

### Documentation

Each product has its own DocC catalog (`DICOMKit/DICOMKit.docc`,
`DICOMKitAuthoring/DICOMKitAuthoring.docc`, `DICOMKitNetworking/DICOMKitNetworking.docc`),
rather than one catalog covering all three. This was necessary, not stylistic:
DocC's `--additional-symbol-graph-dir` resolves a `` ``Symbol`` `` doc-link
only within the primary module a catalog documents, so a single catalog fed
all three modules' symbol graphs left every cross-module doc-comment link
unresolved in both directions, including a module's own doc comments
referencing its own sibling declarations. Each catalog now documents exactly
its own module's symbols, with all remaining cross-module mentions in doc
comments written as plain text rather than doc-links; `.github/workflows/publish-docs.yml`
builds all three, merges them with `docc merge` into one archive with a
synthesized landing page, and publishes that with
`docc process-archive transform-for-static-hosting`.
