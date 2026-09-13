import Foundation

/// A single PS3.15 Table E.1-1 action, as resolved for one attribute.
///
/// These mirror the six action codes PS3.15 Table E.1-1 defines (`D`,
/// `Z`, `X`, `K`, `C`, `U`) plus the table's slashed combinations (e.g.
/// `X/Z/D`), which the standard defines as "apply the first, unless the
/// IOD in use requires a later alternative" (PS3.15 Section E.1). DICOMKit
/// has no notion of "the IOD in use" when resolving a bare tag, so
/// anything that must collapse ``alternatives`` to one concrete choice
/// (``DICOMConfidentialityProfile/makeAnonymizer(replacement:)``) always
/// takes the first alternative.
public enum DICOMDeidentificationAction: Sendable, Equatable {
    /// `X`: remove the attribute entirely.
    case remove
    /// `Z`: replace the attribute's value with a zero-length value.
    case replaceWithZeroLength
    /// `D`: replace the attribute's value with a non-zero-length dummy value.
    case replaceWithDummy
    /// `K`: keep the attribute as-is.
    case keep
    /// `C`: clean — the value may be retained only if it is first stripped
    /// of any identifying information it contains. DICOMKit cannot make
    /// that determination on free text, structured content, or graphics,
    /// so every entry point that turns this into a concrete transformation
    /// treats `clean` as conservatively as `remove` rather than as `keep`.
    /// See ``DICOMConfidentialityProfile/makeAnonymizer(replacement:)``.
    case clean
    /// `U`: replace a UID with another, consistently within one dataset.
    case replaceUID
    /// A slashed combination such as `X/Z/D`: PS3.15 says to apply
    /// `alternatives.first`, unless the IOD in use requires a later
    /// alternative. `alternatives` is never empty and never itself
    /// contains a nested `.alternatives`.
    case alternatives([DICOMDeidentificationAction])
}

/// One PS3.15 Basic Application Level Confidentiality Profile option —
/// one of Table E.1-1's ten "Opt." columns (PS3.15 Section E.1).
public enum DICOMDeidentificationOption: String, Sendable, Equatable, Hashable, CaseIterable {
    case retainSafePrivate
    case retainUIDs
    case retainDeviceIdentity
    case retainInstitutionIdentity
    case retainPatientCharacteristics
    case retainLongitudinalFullDates
    case retainLongitudinalModifiedDates
    case cleanDescriptors
    case cleanStructuredContent
    case cleanGraphics

    /// This option's 0-based column index within Table E.1-1, matching
    /// the keys of `DICOMDeidentificationTable.Entry.overrides`. Also the
    /// order `action(for:)` applies overrides in — see its documentation
    /// for why that order is the precedence rule.
    fileprivate var columnIndex: Int {
        switch self {
        case .retainSafePrivate: 0
        case .retainUIDs: 1
        case .retainDeviceIdentity: 2
        case .retainInstitutionIdentity: 3
        case .retainPatientCharacteristics: 4
        case .retainLongitudinalFullDates: 5
        case .retainLongitudinalModifiedDates: 6
        case .cleanDescriptors: 7
        case .cleanStructuredContent: 8
        case .cleanGraphics: 9
        }
    }

    /// A short, human-readable label used to build De-identification Method
    /// `(0012,0063)`.
    fileprivate var label: String {
        switch self {
        case .retainSafePrivate: "Retain Safe Private"
        case .retainUIDs: "Retain UIDs"
        case .retainDeviceIdentity: "Retain Device Identity"
        case .retainInstitutionIdentity: "Retain Institution Identity"
        case .retainPatientCharacteristics: "Retain Patient Characteristics"
        case .retainLongitudinalFullDates: "Retain Longitudinal Full Dates"
        case .retainLongitudinalModifiedDates: "Retain Longitudinal Modified Dates"
        case .cleanDescriptors: "Clean Descriptors"
        case .cleanStructuredContent: "Clean Structured Content"
        case .cleanGraphics: "Clean Graphics"
        }
    }

    /// The PS3.16 CID 7050 "De-identification Method" code for selecting
    /// this option, written into De-identification Method Code Sequence
    /// `(0012,0064)` alongside code `113100` "Basic Application
    /// Confidentiality Profile", which is always present.
    ///
    /// `nil` for ``retainInstitutionIdentity``: CID 7050 has no code for
    /// PS3.15's Retain Institution Identity Option, even though the option
    /// itself is a real column of Table E.1-1 — this is a gap in the
    /// standard's own coding scheme, not an omission here. Selecting that
    /// option still changes the resolved actions
    /// ``DICOMConfidentialityProfile/action(for:)`` returns; it just has no
    /// corresponding code to record.
    ///
    /// CID 7050 also defines `113101` "Clean Pixel Data" and `113102`
    /// "Clean Recognizable Visual Features", for de-identification methods
    /// that modify pixel data. DICOMKit never emits either code, because it
    /// never modifies pixel data — see
    /// ``DICOMConfidentialityProfile/deidentify(_:replacement:)``, which
    /// refuses outright rather than claim to have handled burned-in pixel
    /// content.
    fileprivate var deidentificationMethodCode: DICOMCodeSequenceItem? {
        switch self {
        case .retainSafePrivate:
            DICOMCodeSequenceItem(codeValue: "113111", codingSchemeDesignator: "DCM", codeMeaning: "Retain Safe Private Option")
        case .retainUIDs:
            DICOMCodeSequenceItem(codeValue: "113110", codingSchemeDesignator: "DCM", codeMeaning: "Retain UIDs Option")
        case .retainDeviceIdentity:
            DICOMCodeSequenceItem(codeValue: "113109", codingSchemeDesignator: "DCM", codeMeaning: "Retain Device Identity Option")
        case .retainInstitutionIdentity:
            nil
        case .retainPatientCharacteristics:
            DICOMCodeSequenceItem(codeValue: "113108", codingSchemeDesignator: "DCM", codeMeaning: "Retain Patient Characteristics Option")
        case .retainLongitudinalFullDates:
            DICOMCodeSequenceItem(codeValue: "113106", codingSchemeDesignator: "DCM", codeMeaning: "Retain Longitudinal Temporal Information Full Dates Option")
        case .retainLongitudinalModifiedDates:
            DICOMCodeSequenceItem(codeValue: "113107", codingSchemeDesignator: "DCM", codeMeaning: "Retain Longitudinal Temporal Information Modified Dates Option")
        case .cleanDescriptors:
            DICOMCodeSequenceItem(codeValue: "113105", codingSchemeDesignator: "DCM", codeMeaning: "Clean Descriptors Option")
        case .cleanStructuredContent:
            DICOMCodeSequenceItem(codeValue: "113104", codingSchemeDesignator: "DCM", codeMeaning: "Clean Structured Content Option")
        case .cleanGraphics:
            DICOMCodeSequenceItem(codeValue: "113103", codingSchemeDesignator: "DCM", codeMeaning: "Clean Graphics Option")
        }
    }
}

/// A PS3.15 Basic Application Level Confidentiality Profile, optionally
/// extended with one or more of PS3.15's Retain/Clean options (PS3.15
/// Section E.1), backed by the full Table E.1-1 attribute table generated
/// by `Tools/generate_deidentification_profile.py` into
/// `DICOMDeidentification.generated.swift`.
///
/// Unlike ``DICOMDeidentificationProfile/basicApplicationLevelConfidentiality(replacement:)``,
/// which hand-picked about twenty tags, this type resolves every one of
/// Table E.1-1's 631 attribute rows (627 exact tags plus 3 repeating-group
/// tags matched by mask).
public struct DICOMConfidentialityProfile: Sendable {
    /// The Retain/Clean options selected in addition to the Basic Profile.
    public let options: Set<DICOMDeidentificationOption>

    public init(options: Set<DICOMDeidentificationOption> = []) {
        self.options = options
    }

    /// Resolves the action Table E.1-1, plus this profile's selected
    /// options, prescribes for `tag`.
    ///
    /// The Basic Profile action is looked up first, then each selected
    /// option's override is applied **in the order `DICOMDeidentificationOption.allCases`
    /// declares its cases — the same left-to-right order as Table E.1-1's
    /// ten option columns.** When two selected options both override the
    /// same attribute (this happens for real rows — e.g. Content Date has
    /// both a Retain Longitudinal Full Dates override, `K`, and a Retain
    /// Longitudinal Modified Dates override, `C`), the **later column
    /// wins**. This is a deliberate, deterministic tie-break rather than
    /// an accident of iteration order: in every row of the table where two
    /// option columns overlap, the later column is also the more
    /// conservative of the two (e.g. `C` "clean" rather than `K` "keep"),
    /// so combining two Retain-style options never produces a result
    /// weaker than selecting just one of them would.
    ///
    /// Returns `nil` when `tag` does not appear in Table E.1-1 at all —
    /// the caller should keep such an attribute rather than assume some
    /// default action.
    public func action(for tag: DICOMTag) -> DICOMDeidentificationAction? {
        guard let entry = resolvedEntry(for: tag) else { return nil }
        var resolved = Self.action(forRawCode: entry.basic)
        for option in DICOMDeidentificationOption.allCases where options.contains(option) {
            if let overrideCode = entry.overrides[option.columnIndex] {
                resolved = Self.action(forSingleCode: overrideCode)
            }
        }
        return resolved
    }

    private func resolvedEntry(for tag: DICOMTag) -> DICOMDeidentificationTable.Entry? {
        if let entry = DICOMDeidentificationTable.entries[tag] { return entry }
        guard let masked = DICOMDeidentificationTable.maskedEntries.first(where: { $0.matches(tag) }) else { return nil }
        return DICOMDeidentificationTable.Entry(basic: masked.basic, overrides: masked.overrides)
    }

    private static func action(forSingleCode code: String) -> DICOMDeidentificationAction {
        switch code {
        case "D": .replaceWithDummy
        case "Z": .replaceWithZeroLength
        case "X": .remove
        case "K": .keep
        case "C": .clean
        case "U": .replaceUID
        default: .remove
        }
    }

    private static func action(forRawCode raw: String) -> DICOMDeidentificationAction {
        let parts = raw.split(separator: "/").map { action(forSingleCode: String($0)) }
        return parts.count == 1 ? parts[0] : .alternatives(parts)
    }

    /// Builds a `DICOMAnonymizer` that applies this profile's resolved
    /// action to every exact tag Table E.1-1 lists.
    ///
    /// Table E.1-1's three repeating-group ("xx") tags (Curve Data,
    /// Overlay Comments, Overlay Data) are **not** included here:
    /// `DICOMAnonymizer.actions` is a plain `[DICOMTag: Action]`
    /// dictionary and cannot represent a masked match. Use
    /// ``deidentify(_:replacement:)`` for coverage that includes those
    /// tags too.
    ///
    /// PS3.15's six action codes are compressed onto `DICOMAnonymizer.Action`'s
    /// five cases as follows:
    /// - `D` (replace with dummy) maps to `.replace(replacement)`.
    /// - `Z` (replace with zero-length) maps to `.emptyValue`: the element
    ///   stays present, with its original VR and a zero-length value (an
    ///   empty sequence, for a `Z`-coded sequence attribute), instead of
    ///   being dropped. This is not about disclosure — a present-but-empty
    ///   element and an absent one both disclose nothing about the original
    ///   value — it is about conformance: Table E.1-1 codes `Z` almost
    ///   exclusively for attributes that are Type 2 in their IOD, meaning
    ///   the IOD requires the element to be present even when its value is
    ///   unknown. Mapping `Z` to `.remove` would make the output invalid
    ///   DICOM for those IODs, which is not an acceptable trade for
    ///   conservatism.
    /// - `X` (remove) maps to `.remove`.
    /// - `K` (keep) maps to `.keep`.
    /// - `C` (clean) maps to `.remove`, the most conservative action
    ///   available. DICOMKit does not implement true PS3.15 cleaning —
    ///   which requires understanding free text, structured content, or
    ///   graphics well enough to redact only the identifying parts of a
    ///   value — so selecting a Clean option is a request DICOMKit
    ///   satisfies conservatively, by removing the whole attribute,
    ///   rather than a promise that identifying content was found and
    ///   stripped out while the rest was preserved.
    /// - `U` (replace UID) maps to `.remapUID`.
    /// - A slashed combination maps using its first alternative, per
    ///   PS3.15's "unless the IOD requires otherwise" rule — this API has
    ///   no IOD context to decide otherwise.
    public func makeAnonymizer(replacement: String) -> DICOMAnonymizer {
        var actions: [DICOMTag: DICOMAnonymizer.Action] = [:]
        actions.reserveCapacity(DICOMDeidentificationTable.entries.count)
        for tag in DICOMDeidentificationTable.entries.keys {
            guard let resolved = action(for: tag) else { continue }
            actions[tag] = Self.anonymizerAction(for: resolved, replacement: replacement)
        }
        return DICOMAnonymizer(actions: actions)
    }

    private static func anonymizerAction(for action: DICOMDeidentificationAction, replacement: String) -> DICOMAnonymizer.Action {
        switch action {
        case .remove, .clean:
            .remove
        case .replaceWithZeroLength:
            .emptyValue
        case .replaceWithDummy:
            .replace(replacement)
        case .keep:
            .keep
        case .replaceUID:
            .remapUID
        case .alternatives(let alternatives):
            anonymizerAction(for: alternatives.first ?? .remove, replacement: replacement)
        }
    }

    /// The result of ``deidentify(_:replacement:)``.
    ///
    /// This deliberately is not a bare `DICOMDataset`: a caller who only
    /// ever looks at `.dataset` and never at `.warnings` would silently
    /// treat a weaker claim (Burned In Annotation was never declared, so
    /// its absence could not be confirmed) the same as the strongest one
    /// (it was declared absent). Requiring `result.dataset` to be reached
    /// through a value that also carries `warnings` keeps that gap visible
    /// at the call site instead of letting it disappear into a discarded
    /// second return value or a log line nobody reads.
    public struct DeidentificationResult: Sendable, Equatable {
        /// The de-identified dataset.
        public let dataset: DICOMDataset
        /// Non-fatal caveats about the strength of the de-identification
        /// claim this result represents. Empty only when nothing weakens
        /// it — for example, a non-empty array whenever Burned In
        /// Annotation `(0028,0301)` was absent rather than explicitly `NO`.
        public let warnings: [String]
    }

    /// De-identifies `file`'s dataset under this profile, first checking
    /// whether pixel data can be trusted not to carry rendered identifying
    /// text.
    ///
    /// A dataset whose pixels contain burned-in identifiers (patient name
    /// overlays, annotated ultrasound measurements, scanned document
    /// photos, and the like) is not de-identified no matter what this
    /// method does to its attributes — and DICOMKit cannot detect or
    /// redact such pixel content, because that requires image
    /// understanding, not attribute manipulation. So:
    ///
    /// - When Burned In Annotation `(0028,0301)` is `YES`
    ///   (``DICOMBurnedInAnnotationStatus/declaredPresent``), this throws
    ///   ``DICOMError/burnedInAnnotationPresent`` instead of producing
    ///   output that would misrepresent the result as de-identified.
    /// - When `(0028,0301)` is absent
    ///   (``DICOMBurnedInAnnotationStatus/undeclared``), this proceeds —
    ///   refusing outright would reject the enormous number of real-world
    ///   files that simply never populated this optional attribute — but
    ///   the returned ``DeidentificationResult/warnings`` says so, because
    ///   the resulting claim is weaker than when `(0028,0301)` is `NO`.
    /// - When `(0028,0301)` is `NO`
    ///   (``DICOMBurnedInAnnotationStatus/declaredAbsent``), this proceeds
    ///   with no warning.
    ///
    /// Unlike ``makeAnonymizer(replacement:)``, this also applies Table
    /// E.1-1's three repeating-group ("xx") tags wherever they appear in
    /// `file.dataset` (recursively, including inside sequence items),
    /// since here — working from a whole dataset rather than building a
    /// tag-keyed `DICOMAnonymizer` up front — there is no need to give up
    /// mask matching for a plain dictionary.
    public func deidentify(_ file: DICOMFile, replacement: String) throws -> DeidentificationResult {
        var warnings: [String] = []
        switch file.burnedInAnnotation {
        case .declaredPresent:
            throw DICOMError.burnedInAnnotationPresent
        case .undeclared:
            warnings.append(
                "Burned In Annotation (0028,0301) is not present, so it is not confirmed that pixel data is free of "
                    + "identifying text. This de-identification claim covers dataset attributes only."
            )
        case .declaredAbsent:
            break
        }

        var actions = makeAnonymizer(replacement: replacement).actions
        for tag in Self.allTags(in: file.dataset) where actions[tag] == nil {
            if let resolved = action(for: tag) {
                actions[tag] = Self.anonymizerAction(for: resolved, replacement: replacement)
            }
        }
        let anonymized = DICOMAnonymizer(actions: actions).anonymize(file.dataset)
        let dataset = DICOMDataset(elements: Array(anonymized) + recordingElements)
        return DeidentificationResult(dataset: dataset, warnings: warnings)
    }

    /// Patient Identity Removed `(0012,0062)`, De-identification Method
    /// `(0012,0063)`, and De-identification Method Code Sequence
    /// `(0012,0064)` (PS3.15 Section E.1.1): a de-identification claim is
    /// only meaningful if the output records what was actually applied.
    private var recordingElements: [DICOMElement] {
        [
            DICOMElement(tag: DICOMTag(group: 0x0012, element: 0x0062), vr: .CS, value: Data("YES".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0012, element: 0x0063), vr: .LO, value: Data(methodDescription.utf8)),
            DICOMElement(
                tag: DICOMTag(group: 0x0012, element: 0x0064), vr: .SQ, value: Data(),
                sequenceItems: methodCodes.map { $0.makeDataset() }
            )
        ]
    }

    /// A human-readable description of the Basic Profile plus every
    /// selected option, for De-identification Method `(0012,0063)`.
    /// Truncated defensively to `LO`'s 64-character limit (PS3.5 Section
    /// 6.2) — the untruncated content is always in
    /// ``methodCodes``/`(0012,0064)` regardless.
    private var methodDescription: String {
        var parts = ["Basic Application Level Confidentiality Profile"]
        for option in DICOMDeidentificationOption.allCases where options.contains(option) {
            parts.append(option.label)
        }
        let description = parts.joined(separator: "; ")
        return description.count > 64 ? String(description.prefix(64)) : description
    }

    /// The PS3.16 CID 7050 codes for De-identification Method Code Sequence
    /// `(0012,0064)`: `113100` "Basic Application Confidentiality Profile"
    /// always, plus one code per selected option that has one (see
    /// ``DICOMDeidentificationOption/deidentificationMethodCode``).
    private var methodCodes: [DICOMCodeSequenceItem] {
        var codes = [DICOMCodeSequenceItem(codeValue: "113100", codingSchemeDesignator: "DCM", codeMeaning: "Basic Application Confidentiality Profile")]
        for option in DICOMDeidentificationOption.allCases where options.contains(option) {
            if let code = option.deidentificationMethodCode {
                codes.append(code)
            }
        }
        return codes
    }

    /// Every tag present anywhere in `dataset`, including inside sequence
    /// items, recursively. Used only to discover which of Table E.1-1's
    /// masked (repeating-group) entries actually apply to this dataset, so
    /// ``deidentify(_:replacement:)`` can add them to an otherwise
    /// exact-tag `DICOMAnonymizer.actions` dictionary.
    private static func allTags(in dataset: DICOMDataset) -> Set<DICOMTag> {
        var tags = Set(dataset.tags)
        for element in dataset {
            guard let items = element.sequenceItems else { continue }
            for item in items {
                tags.formUnion(allTags(in: item))
            }
        }
        return tags
    }
}

// DICOMBurnedInAnnotationStatus and DICOMDataset.burnedInAnnotation live in
// DICOMDataset.swift: DICOMFile.burnedInAnnotation (core) depends on both,
// and core cannot depend on this file once it moves to DICOMKitAuthoring.
