# Implementation roadmap

What DICOMKit does not yet implement, and the order in which to close the gaps.

Baseline: `b3a8c93`, 289 tests in 24 suites, iPadOS 16 / macOS 14.

Impact ratings below mean:

- **A** — produces clinically wrong output, or exposes the parser to untrusted input
- **B** — a real workflow is impossible
- **C** — convenience or completeness

## Gaps

### 1. Text and the data model

| Gap | Impact | Note |
| --- | :---: | --- |
| ~~Specific Character Set code extensions~~ | **A** | ~~`DICOMDataset` reads only the **first** value of `(0008,0005)`, so a multi-valued declaration — the normal case for Japanese Person Names — decodes the ideographic and phonetic components with the wrong encoding. Only ISO_IR 6/100/13 and ISO 2022 IR 87 are modelled; Korean (IR 149), GB18030, Cyrillic (IR 144), Arabic (IR 127), Greek (IR 126), Hebrew (IR 138), Thai (IR 166) and Latin 2–5 (IR 101/109/110/148) are all missing.~~ **Done** — see Phase 1, item 1. |
| ~~`UN` re-interpretation in Explicit VR~~ | **B** | ~~An element that arrives as `UN` with a defined length is kept as `UN`. PS3.5 6.2.2 allows re-deriving the VR from the dictionary, which is what makes data readable after it has passed through middleware that strips VRs.~~ **Done** — see Phase 3, item 5. `b757050` "Reinterpret unknown VRs from the dictionary", `157c859` "Parse defined-length unknown sequences". |
| ~~Private VR resolution under Implicit VR~~ | **B** | ~~`DICOMDataset.privateCreator(for:)` and `privateElement(creator:group:element:)` already resolve which Private Creator owns a private element and locate it by name — this row previously (and incorrectly) described that lookup itself as missing. The actual gap was VR resolution: Implicit VR parsing had no way to learn a private element's VR, so it always decoded as `UN` (or `SQ` at undefined length) regardless of what the owning creator's documentation says the type is, and there was no way for a caller to supply that documentation.~~ **Done** — see Phase 3, item 5. `cd06c82` "Add a caller-supplied private dictionary", `1fe604c` "Resolve private VRs from the dictionary". |
| Icon Image Sequence `(0088,0200)` | **C** | The cheapest possible thumbnail source for a series picker. |
| Frame Increment Pointer `(0028,0009)` | **C** | Declares what the frames of a multi-frame image vary along. |

### 2. Image and display

| Gap | Impact | Note |
| --- | :---: | --- |
| ~~Pixel spacing precedence~~ | **A** | ~~Only Pixel Spacing `(0028,0030)` is read. Imager Pixel Spacing `(0018,1164)`, Pixel Spacing Calibration Type/Description `(0028,0A02)`/`(0028,0A04)`, and Ultrasound Region Calibration `(0018,6011)` are ignored, so on-image measurement silently uses the wrong scale for projection radiography and ultrasound.~~ **Done** — see Phase 1, item 2. |
| ~~Enhanced multi-frame functional groups~~ | **A** | ~~Only Pixel Value Transformation and Frame VOI LUT are resolved. Pixel Measures, Plane Position/Orientation, Frame Content, Frame Anatomy, Real World Value Mapping, Frame Display Shutter and Derivation Image are not, so an Enhanced CT/MR object can be displayed but not measured, stacked, or reformatted.~~ **Done** — see Phase 2, item 4. Derivation Image remains unresolved. |
| ~~Real World Value Mapping `(0040,9096)`~~ | **B** | ~~Quantitative readout — PET SUV above all.~~ **Done** — see Phase 2, item 4. |
| Segmented Palette Color LUT | **B** | `(0028,1221)`–`(0028,1223)` in segmented form is not decoded. |
| Presentation LUT Sequence `(2050,0010)` | **B** | Only the LUT *Shape* is honoured; a table-valued Presentation LUT is ignored. |
| Bitmap Display Shutter | **C** | Parsed as a shape but never applied (documented in the API). |
| Overlay completeness | **C** | Bitmap planes are read, but not Overlay Activation Layer, ROI-type overlays, or multi-frame overlays. |
| Presentation states other than GSPS | **C** | Color, Pseudo-Color, Blending, XA/XRF and Advanced Blending softcopy presentation states. |
| Mask Module `(0028,6100)` | **C** | XA/XRF subtraction. |

### 3. Codecs

| Gap | Impact | Note |
| --- | :---: | --- |
| ~~HTJ2K `.201`/`.202`/`.203`~~ | **B** | ~~Increasingly the default in DICOMweb delivery.~~ **Done** — see Phase 3, item 6. `cdd81f6` "Recognise HTJ2K transfer syntaxes", `9d2fa6c` "Route HTJ2K through the JPEG 2000 decoder". Decoding depends on the host platform's ImageIO; DICOMKit has no HTJ2K encoder or fixture to verify decode against, so "done" here means recognized/opened/routed, not verified-to-render. |
| MPEG-4 / H.264 / H.265 `.100`–`.107` | **B** | Endoscopy and ultrasound cine. |
| JPEG Extended (Process 2 & 4) `.51` | **C** | 12-bit baseline. |
| JPEG 2000 Part 2 `.92`/`.93` | **C** | Rare. |
| Encoding of any kind | **C** | The writer serializes caller-supplied fragments; it never compresses. |

### 4. Networking

| Gap | Impact | Note |
| --- | :---: | --- |
| ~~DIMSE N-services~~ | **B** | ~~N-CREATE/N-SET/N-GET/N-ACTION/N-DELETE/N-EVENT-REPORT are all absent, so MPPS, Storage Commitment, Print and UPS are impossible. This is the standing README roadmap item.~~ **Done** — see Phase 4, items 7–8. MPPS and Storage Commitment are implemented; Print and UPS are not, since neither has a consumer yet and both would need their own SOP-Class-specific attribute modeling on top of the N-services themselves. |
| WADO-URI | **B** | Legacy but still widely deployed. |
| Extended negotiation `0x56` / SOP Class Common Extended `0x57` | **C** | Announcing relational-query support to a Q/R SCP. |
| Asynchronous operations | **C** | The window is negotiated but `DICOMAssociation` is still strictly serial. |
| STOW-RS response parsing | **C** | `store(instances:)` returns raw `Data`; failed instances are not surfaced. |
| QIDO-RS typed query builders | **C** | Callers assemble `URLQueryItem`s by hand. |

### 5. Object types

| Gap | Impact | Note |
| --- | :---: | --- |
| Structured Report content tree | **B** | Reports stored as SR cannot be shown at all. |
| Waveform `(5400,0100)` | **C** | ECG and similar. |
| Segmentation frame resolution | **C** | Segment Identification functional group. |
| RT objects | **C** | RTSTRUCT/RTPLAN/RTDOSE. |
| Encapsulated PDF/CDA/STL extraction | **C** | The SOP Class UIDs exist; nothing extracts the payload. |

### 6. Conformance

| Gap | Impact | Note |
| --- | :---: | --- |
| PS3.15 profile options | **B** | `DICOMDeidentificationProfile` is a conservative preset, not the Basic Application Level Confidentiality Profile with its options (Retain Longitudinal Temporal Information, Retain UIDs, Clean Pixel Data, …). |
| Burned-in annotation handling | **B** | `(0028,0301)` is not inspected and pixel-level text is never detected, so "anonymized" exports can still carry identifiers in the image. |
| Full IOD conformance validation | **C** | Module-level Type 1/2 checks only. |

### 7. Infrastructure

| Gap | Impact | Note |
| --- | :---: | --- |
| ~~Fuzz testing~~ | **A** | ~~DICOMKit parses untrusted files and has no fuzzing. Several trap-on-malformed-input defects have already been found by hand; a fuzzer would find the rest.~~ **Done** — see Phase 1, item 3. A long local campaign (~9M mutations across 15 seeds, including `0` and `UInt64.max`) found nothing further to fix. |
| Three-product split | **C** | Proposed in [viewer-profile.md](viewer-profile.md), not started. |
| Performance benchmarks | **C** | No measurements, so regressions are invisible. |

## Plan

Each phase is a series of small Red/Green TDD commits on `main`, in the order listed. Commit counts are estimates of natural units of work, not time.

### Phase 1 — Correctness and safety (impact A)

The three gaps here can make DICOMKit produce output that is wrong in a way a
user cannot see, or crash on a hostile file. Nothing else should go first.

1. **Character set code extensions** — **Done** (7 commits: `cf7f806`, `e703e7a`, `82e8173`, `7ffc9e9`, `e464e28`, `15f29aa`, `20213b8`)
   - Add the missing single-byte sets. — `cf7f806` "Decode single-byte specific character sets"
   - Implement ISO 2022 escape-sequence switching between G0/G1 within one value, which is what makes a Japanese `PN` decode correctly across its alphabetic, ideographic and phonetic components. — `e703e7a` "Switch character sets on ISO 2022 escapes"
   - Add the multi-byte sets (IR 87, IR 159, IR 149, GB18030, UTF-8). — `82e8173` "Decode multi-byte character set extensions"
   - Reset character set state at value delimiters. — `7ffc9e9` "Reset character set state at value delimiters"
   - Apply the dataset's character set to nested sequence items, which inherit it. — `e464e28` "Inherit the character set into sequence items"
   - Extend character set decoding to DICOM JSON and Presentation State text. — `15f29aa` "Decode text with the dataset character set in JSON", `20213b8` "Decode presentation state text with its character set"

2. **Pixel spacing precedence** — **Done** (3 commits: `1b1ca0c`, `95c6e41`, and this section's own "Resolve measurement scale per ultrasound region")
   - Add `DICOMImageGeometry.spacingSource` distinguishing Pixel Spacing, Imager Pixel Spacing, calibrated spacing, and none. — `1b1ca0c` "Resolve pixel spacing precedence"
   - Resolve precedence per PS3.3 C.7.6.1.1.2 and C.8.11.3.1.2, honouring Pixel Spacing Calibration Type. — `1b1ca0c` "Resolve pixel spacing precedence"
   - Add Ultrasound Region Calibration, exposing each region's physical units and deltas. — `95c6e41` "Read ultrasound region calibration"
   - Document that a caller must not measure when the source is `none`. — "Resolve measurement scale per ultrasound region" (a commit can't record its own final hash; see `git log` for it)

3. **Fuzz testing** — **Done** (3 commits: `5707a39`, `b4d1036`, and this section's own "Run the fuzzer in CI")
   - Add a `swift-testing`-driven, deterministically-seeded (SplitMix64) corpus fuzzer over `DICOMFile(data:)`, with bit-flip, byte-substitution, truncation, insert/delete, splice, and DICOM-aware length-field-corruption mutation strategies. — `5707a39` "Add a deterministic parser fuzzer"
   - Extend the same engine to `DICOMULPDU.decode` and `DICOMDIMSECommand.decodeCommandSet`. — `b4d1036` "Fuzz the upper layer and DIMSE decoders"
   - Assert the invariant "never trap, never hang" — every input either parses or throws — and wire a bounded (~400k-iteration, run-seeded) campaign into CI. — "Run the fuzzer in CI" (a commit can't record its own final hash; see `git log` for it)
   - A local campaign of ~9M mutations across 15 seeds (including `0` and `UInt64.max`, at up to 300k iterations per target per seed) found no crashing or invariant-violating input, so this phase adds no regression fixtures under `DICOMKitTests/Fixtures/Fuzz/`.

### Phase 2 — Enhanced multi-frame (impact A/B) — **Done**

Modern CT and MR ship as Enhanced objects. Before this phase they rendered
but could not be measured or reformatted, which was the single largest
functional hole for a viewer.

4. **Full functional group resolution** — **Done** (5 commits: `602def3`, `2901d85`, `37bcc07`, `c9cba30`, `61fc962`)
   - Generalize `renderingAttributes(frameCount:)` into a `DICOMFrameFunctionalGroups` type resolving shared-then-per-frame for every macro DICOMKit needs. — `602def3` "Generalize functional group resolution"
   - Add Pixel Measures (per-frame pixel spacing, slice thickness, spacing between slices) and Plane Position/Orientation, combined per frame into `DICOMImageGeometry` by `DICOMFile.frameGeometries`. — `2901d85` "Resolve per-frame geometry from functional groups"
   - Add Frame Content (stack ID, in-stack position, temporal index) and `DICOMFile.frameOrder()`, which groups frames by stack and orders each group by in-stack position then temporal position, leaving a group with no ordering keys in stored order. — `37bcc07` "Resolve frame content and order frames"
   - Add Frame Anatomy (laterality and anatomic region, via the new shared `DICOMCodeSequenceItem`) and per-frame Frame Display Shutter, which `pixelDataFrames` prefers over the dataset-level shutter when present. — `c9cba30` "Resolve frame anatomy and display shutter"
   - Add Real World Value Mapping with its LUT and slope/intercept forms (`DICOMRealWorldValueMap.value(for:)`), exposed on `DICOMFile` and per frame on `DICOMFrameFunctionalGroups`. — `61fc962` "Read real world value mappings"
   - Derivation Image `(0008,9124)` remains unresolved; expose per-frame `DICOMImageGeometry` through `DICOMHierarchy` ordering is future work, not part of this phase.

### Phase 3 — Interoperability with real archives (impact B)

5. **`UN` re-interpretation and private tags** — **Done** (4 commits: `b757050`, `157c859`, `cd06c82`, `1fe604c`)
   - Re-derive a defined-length `UN` element's VR from the dictionary when the tag is known, per PS3.5 6.2.2, behind `DICOMReadOptions.reinterpretsUnknownVR` (default on). — `b757050` "Reinterpret unknown VRs from the dictionary"
   - When the dictionary resolves a defined-length `UN` element to `SQ`, parse its bytes as Implicit VR Little Endian — the encoding such a conversion preserves — reusing the existing sequence reader; fall back to `UN` if the bytes don't parse, rather than failing the whole dataset. — `157c859` "Parse defined-length unknown sequences"
   - Add `DICOMPrivateDictionary`/`DICOMPrivateTagEntry`: a mechanism for an application to supply its *own* vendor-documented private VRs. DICOMKit ships none itself — a table built from reverse engineering risks reading a vendor's bytes as the wrong type, and staying `UN` is safer than that. — `cd06c82` "Add a caller-supplied private dictionary"
   - Resolve a private element's VR under Implicit VR from `options.privateDictionary`, tracking Private Creator blocks in one forward pass per PS3.5 7.8.1 and resetting them at each sequence item boundary per PS3.5 7.5.3; `DICOMDataset.privateCreator(for:)` and `privateElement(creator:group:element:)` needed no change since they already existed. — `1fe604c` "Resolve private VRs from the dictionary"

6. **HTJ2K** — **Done** (2 commits: `cdd81f6`, `9d2fa6c`)
   - Add `.201`/`.202`/`.203` to `TransferSyntax`, including `uid`, `init(uid:)`, `isSupported`, `isWritable`, and `usesEncapsulatedPixelData` — a dataset declaring one of these now opens and its encapsulated fragments are reachable, where before it failed `DICOMFile(data:)` outright. — `cdd81f6` "Recognise HTJ2K transfer syntaxes"
   - Add `TransferSyntax.hasPixelDataDecoder` (true for every syntax DICOMKit attempts to decode, false only for `.unknown`) so a caller can distinguish "DICOMKit doesn't know this compression" from "this particular stream failed to decode". Route HTJ2K Pixel Data through the same ImageIO `CGImageSource` path as JPEG 2000 Lossless/JPEG 2000, since PS3.5 Annex A.4.4 describes HTJ2K as the same codestream structure with a different (FBCOT) block coder — an undecodable stream still surfaces as `nil` frames rather than a thrown error, the same contract the other codecs already follow. — `9d2fa6c` "Route HTJ2K through the JPEG 2000 decoder"
   - **Not done, deliberately: verification against a real HTJ2K reference stream.** Unlike JPEG-LS's CharLS-generated fixtures, DICOMKit has no HTJ2K encoder and no way to author a genuine HT-coded codestream, so there is no fixture to decode and no way to *prove* ImageIO decodes real HTJ2K on any given platform. `HTJ2KTests.reportsImageIOJPEG2000CapabilityAsHTJ2KProxy` records what `CGImageSourceCopyTypeIdentifiers()` reports for `public.jpeg-2000` as a diagnostic (not an assertion, since platform capability shouldn't turn the suite red) — on the machine this shipped from, ImageIO advertises JPEG 2000 container support, but that says nothing about whether it accepts HT-coded blocks specifically. A future reader with a real HTJ2K sample should add it as a fixture and turn that diagnostic into a real decode assertion.

### Phase 4 — DIMSE N-services (impact B) — **Done**

The standing README roadmap item. Design notes are already written up in the
previous session's analysis; the key structural change comes first.

7. **N-service foundation** — **Done** (4 commits: `ab4e162`, `e010694`, `8307369`, `6bf3784`)
   - Generalize `hasDataset` from a per-case constant to the decoded Command Data Set Type, because unlike the C-services, an N-service's data set is conditional. — `ab4e162` "Carry the command data set type on N-services"
   - Add the six request/response pairs with their distinct command elements: Requested vs Affected SOP Class/Instance UID, Event Type ID, Action Type ID, Attribute Identifier List. — `e010694` "Add N-GET and N-SET commands", `8307369` "Add N-ACTION, N-CREATE and N-DELETE commands"
   - Extend `DICOMDIMSEStatus` with the N-service codes (`0x0105`–`0x0213`). — `6bf3784` "Add N-service status codes"

8. **Storage Commitment and MPPS** — **Done** (4 commits: `76aadf5`, `ff1847b`, `355ba31`, and this section's own "Add modality performed procedure step support")
   - Wire the six N-services into `DICOMAssociation` as SCU operations (`nCreate`/`nSet`/`nGet`/`nAction`/`nDelete`/`nEventReport`, each with a SOP-Class convenience overload) returning a new `DICOMNServiceResult`. — `76aadf5` "Add N-service SCU operations"
   - Add the matching SCP responders (`respondToNCreate`/`NSet`/`NGet`/`NAction`/`NDelete`/`NEventReport`); `receiveRequest()` needed no change, since its `hasDataset`-driven reassembly already covered the N-services generically. — `ff1847b` "Add N-service SCP responses"
   - Storage Commitment Push Model: `DICOMStorageCommitmentRequest`/`Result` model the N-ACTION Action Information and N-EVENT-REPORT Event Information, and `requestStorageCommitment(messageID:contextID:_:)` sends N-ACTION with Action Type ID 1 against the well-known SOP Instance. The result arrives later via N-EVENT-REPORT — on the same association (via the already-implemented role selection) or a fresh inbound one (via the already-implemented `NetworkDICOMULListener`) — not in the N-ACTION response, which the doc comment calls out explicitly. — `355ba31` "Add storage commitment support"
   - MPPS: `createPerformedProcedureStep` sends N-CREATE forcing Performed Procedure Step Status `(0040,0252)` to `IN PROGRESS`; `updatePerformedProcedureStep` sends N-SET to `COMPLETED`/`DISCONTINUED` and throws `DICOMAssociationError.invalidProcedureStepTransition` for `.inProgress`. Neither method assembles the rest of the required MPPS attribute set — that stays the caller's responsibility, checked with `DICOMModuleValidator` — since the set is long and modality-specific. — "Add modality performed procedure step support" (a commit can't record its own final hash; see `git log` for it)

### Phase 5 — Reporting and conformance (impact B)

9. **Structured Report content tree** (~5 commits)
   - Model Content Item, its value types, and relationship types as a tree.
   - Parse Content Sequence recursively with reference resolution.
   - Render to plain text and to a structure a UI can walk, without imposing a rendering.

10. **PS3.15 profile options** (~4 commits)
    - Restructure `DICOMDeidentificationProfile` around the Basic Application Level Confidentiality Profile plus explicitly selected options.
    - Inspect Burned In Annotation `(0028,0301)` and refuse — loudly — to claim de-identification for an instance that declares burned-in text.
    - Record what was applied in the De-identification Method Code Sequence, since a profile claim is only meaningful if it is recorded.

### Phase 6 — Packaging and the long tail (impact C)

11. **Three-product split** (~3 commits) — as specified in [viewer-profile.md](viewer-profile.md).
12. **Performance benchmarks** (~2 commits) — measure large-series open time and per-frame decode, so later work has a baseline.
13. Remaining C-rated items, pulled forward whenever a consumer actually needs one.

## Deliberately out of scope for now

- **Encoding (compression).** DICOMKit is a reading library; adding encoders doubles the codec surface and the conformance burden for no current consumer.
- **RT objects.** A different domain with its own geometry model; it should be a separate package if it is ever needed.
- **MPEG/H.26x transfer syntaxes.** AVFoundation can decode these, but the DICOM framing, and the question of whether a frame-accurate viewer is wanted at all, should be settled by a real requirement first.
