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
| Specific Character Set code extensions | **A** | `DICOMDataset` reads only the **first** value of `(0008,0005)`, so a multi-valued declaration — the normal case for Japanese Person Names — decodes the ideographic and phonetic components with the wrong encoding. Only ISO_IR 6/100/13 and ISO 2022 IR 87 are modelled; Korean (IR 149), GB18030, Cyrillic (IR 144), Arabic (IR 127), Greek (IR 126), Hebrew (IR 138), Thai (IR 166) and Latin 2–5 (IR 101/109/110/148) are all missing. |
| `UN` re-interpretation in Explicit VR | **B** | An element that arrives as `UN` with a defined length is kept as `UN`. PS3.5 6.2.2 allows re-deriving the VR from the dictionary, which is what makes data readable after it has passed through middleware that strips VRs. |
| Private Creator block resolution | **B** | Private tags are always `UN` under Implicit VR; there is no `(gggg,00xx)` Private Creator lookup and no vendor dictionary, so GE/Siemens/Philips/Canon/FUJIFILM private attributes are unreadable. |
| Icon Image Sequence `(0088,0200)` | **C** | The cheapest possible thumbnail source for a series picker. |
| Frame Increment Pointer `(0028,0009)` | **C** | Declares what the frames of a multi-frame image vary along. |

### 2. Image and display

| Gap | Impact | Note |
| --- | :---: | --- |
| ~~Pixel spacing precedence~~ | **A** | ~~Only Pixel Spacing `(0028,0030)` is read. Imager Pixel Spacing `(0018,1164)`, Pixel Spacing Calibration Type/Description `(0028,0A02)`/`(0028,0A04)`, and Ultrasound Region Calibration `(0018,6011)` are ignored, so on-image measurement silently uses the wrong scale for projection radiography and ultrasound.~~ **Done** — see Phase 1, item 2. |
| Enhanced multi-frame functional groups | **A** | Only Pixel Value Transformation and Frame VOI LUT are resolved. Pixel Measures, Plane Position/Orientation, Frame Content, Frame Anatomy, Real World Value Mapping, Frame Display Shutter and Derivation Image are not, so an Enhanced CT/MR object can be displayed but not measured, stacked, or reformatted. |
| Real World Value Mapping `(0040,9096)` | **B** | Quantitative readout — PET SUV above all. |
| Segmented Palette Color LUT | **B** | `(0028,1221)`–`(0028,1223)` in segmented form is not decoded. |
| Presentation LUT Sequence `(2050,0010)` | **B** | Only the LUT *Shape* is honoured; a table-valued Presentation LUT is ignored. |
| Bitmap Display Shutter | **C** | Parsed as a shape but never applied (documented in the API). |
| Overlay completeness | **C** | Bitmap planes are read, but not Overlay Activation Layer, ROI-type overlays, or multi-frame overlays. |
| Presentation states other than GSPS | **C** | Color, Pseudo-Color, Blending, XA/XRF and Advanced Blending softcopy presentation states. |
| Mask Module `(0028,6100)` | **C** | XA/XRF subtraction. |

### 3. Codecs

| Gap | Impact | Note |
| --- | :---: | --- |
| HTJ2K `.201`/`.202`/`.203` | **B** | Increasingly the default in DICOMweb delivery. |
| MPEG-4 / H.264 / H.265 `.100`–`.107` | **B** | Endoscopy and ultrasound cine. |
| JPEG Extended (Process 2 & 4) `.51` | **C** | 12-bit baseline. |
| JPEG 2000 Part 2 `.92`/`.93` | **C** | Rare. |
| Encoding of any kind | **C** | The writer serializes caller-supplied fragments; it never compresses. |

### 4. Networking

| Gap | Impact | Note |
| --- | :---: | --- |
| DIMSE N-services | **B** | N-CREATE/N-SET/N-GET/N-ACTION/N-DELETE/N-EVENT-REPORT are all absent, so MPPS, Storage Commitment, Print and UPS are impossible. This is the standing README roadmap item. |
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
| Fuzz testing | **A** | DICOMKit parses untrusted files and has no fuzzing. Several trap-on-malformed-input defects have already been found by hand; a fuzzer would find the rest. |
| Three-product split | **C** | Proposed in [viewer-profile.md](viewer-profile.md), not started. |
| Performance benchmarks | **C** | No measurements, so regressions are invisible. |

## Plan

Each phase is a series of small Red/Green TDD commits on `main`, in the order listed. Commit counts are estimates of natural units of work, not time.

### Phase 1 — Correctness and safety (impact A)

The three gaps here can make DICOMKit produce output that is wrong in a way a
user cannot see, or crash on a hostile file. Nothing else should go first.

1. **Character set code extensions** (~5 commits)
   - Model `(0008,0005)` as an ordered list of code elements rather than a single value.
   - Add the missing single-byte sets (IR 101/109/110/126/127/138/144/148/166) and the multi-byte sets (IR 87, IR 159, IR 149, GB18030, UTF-8).
   - Implement ISO 2022 escape-sequence switching between G0/G1 within one value, which is what makes a Japanese `PN` decode correctly across its alphabetic, ideographic and phonetic components.
   - Apply the dataset's character set to nested sequence items, which inherit it.
   - Verify with round-trip fixtures for a Japanese `PN` and a Korean `PN`.

2. **Pixel spacing precedence** — **Done** (3 commits: `1b1ca0c`, `95c6e41`, and this section's own "Resolve measurement scale per ultrasound region")
   - Add `DICOMImageGeometry.spacingSource` distinguishing Pixel Spacing, Imager Pixel Spacing, calibrated spacing, and none. — `1b1ca0c` "Resolve pixel spacing precedence"
   - Resolve precedence per PS3.3 C.7.6.1.1.2 and C.8.11.3.1.2, honouring Pixel Spacing Calibration Type. — `1b1ca0c` "Resolve pixel spacing precedence"
   - Add Ultrasound Region Calibration, exposing each region's physical units and deltas. — `95c6e41` "Read ultrasound region calibration"
   - Document that a caller must not measure when the source is `none`. — "Resolve measurement scale per ultrasound region" (a commit can't record its own final hash; see `git log` for it)

3. **Fuzz testing** (~3 commits)
   - Add a `swift-testing`-driven corpus fuzzer over `DICOMFile(data:)`, `DICOMULPDU.decode`, and `DICOMDIMSECommand.decodeCommandSet`, seeded from the existing fixtures with structure-aware mutation.
   - Assert the invariant "never trap, never hang" — every input either parses or throws.
   - Wire a short run into CI and keep any crashing input as a regression fixture.

### Phase 2 — Enhanced multi-frame (impact A/B)

Modern CT and MR ship as Enhanced objects. Today they render but cannot be
measured or reformatted, which is the single largest functional hole for a
viewer.

4. **Full functional group resolution** (~6 commits)
   - Generalize `renderingAttributes(frameCount:)` into a `DICOMFrameFunctionalGroups` type resolving shared-then-per-frame for every macro DICOMKit needs.
   - Add Pixel Measures (per-frame pixel spacing, slice thickness, spacing between slices), Plane Position/Orientation (per-frame geometry), Frame Content (stack ID, in-stack position, temporal index), Frame Anatomy, and Frame Display Shutter.
   - Expose per-frame `DICOMImageGeometry`, so `DICOMHierarchy` can order Enhanced frames the way it already orders single-frame instances.
   - Add Real World Value Mapping with its LUT and slope/intercept forms, and a `realWorldValue(for:)` accessor alongside the existing modality/VOI pipeline.

### Phase 3 — Interoperability with real archives (impact B)

5. **`UN` re-interpretation and private tags** (~5 commits)
   - Re-derive a defined-length `UN` element's VR from the dictionary when the tag is known, per PS3.5 6.2.2, behind an explicitly documented opt-out.
   - Resolve Private Creator blocks and expose `dataset[privateCreator:group:element:]`.
   - Add a small, sourced private dictionary for the vendors that matter locally, generated by the same `Tools/generate_dicom_dictionary.py` pattern rather than hand-maintained.

6. **HTJ2K** (~4 commits)
   - Add `.201`/`.202`/`.203` to `TransferSyntax`.
   - Decode through ImageIO where the OS supports it, and otherwise report the frames as undecodable rather than failing the parse — the same contract the other codecs already follow.
   - Verify against reference streams the way the JPEG-LS coverage is verified against CharLS output.

### Phase 4 — DIMSE N-services (impact B)

The standing README roadmap item. Design notes are already written up in the
previous session's analysis; the key structural change comes first.

7. **N-service foundation** (~4 commits)
   - Generalize `hasDataset` from a per-case constant to the decoded Command Data Set Type, because unlike the C-services, an N-service's data set is conditional.
   - Add the six request/response pairs with their distinct command elements: Requested vs Affected SOP Class/Instance UID, Event Type ID, Action Type ID, Attribute Identifier List.
   - Extend `DICOMDIMSEStatus` with the N-service codes (`0x0110`, `0x0112`, `0x0119`, `0x0121`, `0x0213`).

8. **Storage Commitment and MPPS** (~4 commits)
   - Storage Commitment Push Model: N-ACTION request, Transaction UID handling, and N-EVENT-REPORT receipt both on the same association (via the already-implemented role selection) and on a separate inbound association (via the already-implemented listener).
   - MPPS: N-CREATE `IN PROGRESS` and N-SET `COMPLETED`/`DISCONTINUED`, with the required attribute set.

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
