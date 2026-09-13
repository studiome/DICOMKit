# ``DICOMKitAuthoring``

Part 10 file writing, de-identification, module validation, and UID
generation for DICOMKit — the write path a viewer does not need.

## Overview

This product adds everything `DICOMKit` deliberately leaves out because a
read-only viewer has no use for it: producing a complete Part 10 file,
stripping or replacing identifying attributes, checking a dataset against an
IOD's module requirements, and minting new UIDs. It depends only on
`DICOMKit`.

`DICOMWriter.write(metaInformation:dataset:transferSyntax:requiredMetaInformation:sequenceLengthEncoding:)`
and `DICOMFile.encodedData(sequenceLengthEncoding:)` are added here as
extensions on `DICOMWriter` and `DICOMFile` — both types are defined in
`DICOMKit`, which already serializes a bare dataset through
`DICOMWriter.encodeDataset(_:transferSyntax:sequenceLengthEncoding:)`. This
product layers the 128-byte preamble, `DICM` magic, and File Meta Information
assembly on top, supporting the same transfer syntaxes `encodeDataset`
does.

``DICOMAnonymizer`` applies a caller-supplied `[DICOMTag: Action]` map
recursively across a dataset and its sequence items, with actions to remove,
replace, keep, empty, or remap a UID to a stable, non-reversible `2.25`
pseudonym. ``DICOMConfidentialityProfile`` resolves PS3.15's full Basic
Application Level Confidentiality Profile attribute table (Table E.1-1: 627
exact tags plus 3 repeating-group tags), together with any of its ten
Retain/Clean options, into that action map; ``DICOMConfidentialityProfile/deidentify(_:replacement:)``
also refuses to proceed when Burned In Annotation `(0028,0301)` declares
identifying pixel content — reading `DICOMFile.burnedInAnnotation` from
`DICOMKit` — and records what was applied in Patient Identity Removed,
De-identification Method, and De-identification Method Code Sequence. This is
real attribute-table coverage, not an end-to-end conformance claim: it does
not clean free text, structured content, or graphics (a selected Clean option
is applied conservatively, as a removal) and never modifies pixel data, so an
object with burned-in identifiers, or identifying free text in an attribute
this profile keeps, is not de-identified just because this ran.
``DICOMDeidentificationProfile/basicApplicationLevelConfidentiality(replacement:)``
remains as a convenience preset built on the same generated table.

``DICOMModuleValidator`` checks a dataset against caller-supplied Type 1 and
Type 2 module requirements — useful for the long, modality-specific attribute
sets that `DICOMKitNetworking`'s Modality Performed Procedure Step helpers
deliberately leave to the caller. ``DICOMUIDGenerator`` mints numeric UIDs
below an organization-controlled root.

## Topics

### Writing

- ``DICOMAnonymizer``
- ``DICOMDeidentificationProfile``
- ``DICOMDeidentificationAction``
- ``DICOMDeidentificationOption``
- ``DICOMConfidentialityProfile``
- ``DICOMUIDGenerator``

### Validation

- ``DICOMModuleValidator``
- ``DICOMIODValidator``
- ``DICOMModuleRequirement``
- ``DICOMValidationIssue``
