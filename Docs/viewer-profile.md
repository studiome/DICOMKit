# Viewer profile

A scoping note for using DICOMKit as a **viewer-only** library: what a viewer
actually needs, what it does not, and how to separate the two without forking.

Status: proposal. Nothing here is implemented yet.

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
