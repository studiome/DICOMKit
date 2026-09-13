import Foundation

/// One node of a Structured Report Content Tree (PS3.3 C.17.3).
///
/// An SR object's payload is a tree: the dataset itself is the root item,
/// and each item's Content Sequence `(0040,A730)` holds its children
/// recursively. DICOMKit parses this tree faithfully but does **not**
/// interpret templates (for example TID 1500 and its relatives) or impose
/// semantics on a concept name — that is a much larger, standards-heavy job,
/// and a wrong interpretation of a measurement is worse than no
/// interpretation at all. Consumers that need template-aware behavior must
/// walk ``children`` and ``conceptName`` themselves.
public struct DICOMContentItem: Sendable, Equatable {
    /// Relationship Type `(0040,A010)`, describing how this item relates to
    /// its parent (for example `CONTAINS` or `HAS PROPERTIES`). `nil` on the
    /// root item, which has no parent to relate to.
    public let relationshipType: String?
    /// Value Type `(0040,A040)`, naming the kind of payload this item
    /// carries (`CONTAINER`, `TEXT`, `NUM`, …).
    public let valueType: String
    /// Concept Name Code Sequence `(0040,A043)`: what this item's value
    /// means, coded rather than free text.
    public let conceptName: DICOMCodeSequenceItem?
    /// The item's payload, typed by ``valueType``.
    public let value: DICOMContentItemValue
    /// Content Sequence `(0040,A730)`: this item's children.
    public let children: [DICOMContentItem]
    /// Referenced Content Item Identifier `(0040,DB73)`, present on a
    /// by-reference relationship (`SELECTED FROM`, `INFERRED FROM`) that
    /// points at another item elsewhere in the tree by its path of item
    /// numbers.
    ///
    /// DICOMKit exposes this raw and does **not** resolve it into
    /// ``children`` — doing so would turn a tree into a graph, which the
    /// `children` model cannot represent (and which could cycle for a
    /// hostile or malformed document).
    public let referencedContentItemIdentifier: [Int]?

    public init(
        relationshipType: String? = nil,
        valueType: String,
        conceptName: DICOMCodeSequenceItem? = nil,
        value: DICOMContentItemValue,
        children: [DICOMContentItem] = [],
        referencedContentItemIdentifier: [Int]? = nil
    ) {
        self.relationshipType = relationshipType
        self.valueType = valueType
        self.conceptName = conceptName
        self.value = value
        self.children = children
        self.referencedContentItemIdentifier = referencedContentItemIdentifier
    }
}

/// The typed payload of a ``DICOMContentItem``, one case per SR Value Type
/// PS3.3 defines (C.17.3).
///
/// This is `indirect` because a `container` item's children are themselves
/// full content items, giving the tree unbounded depth.
public indirect enum DICOMContentItemValue: Sendable, Equatable {
    /// `CONTAINER`: Continuity of Content `(0040,A050)`, `SEPARATE` or
    /// `CONTINUOUS`.
    case container(continuity: String?)
    /// `TEXT`: Text Value `(0040,A160)`.
    case text(String)
    /// `CODE`: Concept Code Sequence `(0040,A168)`.
    case code(DICOMCodeSequenceItem)
    /// `NUM`: Measured Value Sequence `(0040,A300)`. `value`/`units` come
    /// from Numeric Value `(0040,A30A)` and Measurement Units Code Sequence
    /// `(0040,08EA)` when a measurement is present; `qualifier` comes from
    /// Numeric Value Qualifier Code Sequence `(0040,A301)` when it is not
    /// (for example to record why a measurement couldn't be made).
    case num(value: Double?, units: DICOMCodeSequenceItem?, qualifier: DICOMCodeSequenceItem?)
    /// `DATE`: Date `(0040,A121)`, kept in its raw `DA` string form. Use
    /// ``DICOMElement/dateComponentsValue`` on the source element if you
    /// need `DateComponents` instead of re-deriving them here.
    case date(String)
    /// `TIME`: Time `(0040,A122)`, kept in its raw `TM` string form.
    case time(String)
    /// `DATETIME`: DateTime `(0040,A120)`, kept in its raw `DT` string form.
    case dateTime(String)
    /// `UIDREF`: UID `(0040,A124)`.
    case uidRef(String)
    /// `PNAME`: Person Name `(0040,A123)`, decoded with this item's
    /// (possibly inherited) Specific Character Set.
    case personName(DICOMPersonName)
    /// `IMAGE`: Referenced SOP Sequence `(0008,1199)`, plus Referenced Frame
    /// Number `(0008,1160)` and Referenced Segment Number `(0062,000B)`
    /// when the reference is scoped to specific frames or segments.
    case image(reference: DICOMSOPReference, frameNumbers: [Int]?, segmentNumbers: [Int]?)
    /// `WAVEFORM`: Referenced SOP Sequence `(0008,1199)`, plus Referenced
    /// Waveform Channels `(0040,A0B0)` when scoped to specific channels.
    case waveform(reference: DICOMSOPReference, channels: [Int]?)
    /// `COMPOSITE`: Referenced SOP Sequence `(0008,1199)`, for a reference
    /// to a whole non-image SOP Instance.
    case composite(DICOMSOPReference)
    /// `SCOORD`: Graphic Type `(0070,0023)` and Graphic Data `(0070,0022)`,
    /// a list of (row, column) or (x, y) pairs flattened into one array.
    case spatialCoordinates(graphicType: String, data: [Double])
    /// `SCOORD3D`: like `SCOORD`, plus Referenced Frame of Reference UID
    /// `(3006,0024)` giving the 3D data's frame of reference.
    case spatialCoordinates3D(graphicType: String, data: [Double], frameOfReferenceUID: String?)
    /// `TCOORD`: Temporal Range Type `(0040,A130)`, plus whichever of
    /// Referenced Sample Positions `(0040,A132)`, Referenced Time Offsets
    /// `(0040,A138)`, or Referenced DateTime `(0040,A13A)` the range uses to
    /// name its points.
    case temporalCoordinates(rangeType: String, samplePositions: [UInt32]?, timeOffsets: [Double]?, dateTimes: [String]?)
    /// Any Value Type DICOMKit does not yet model. The item's ``DICOMContentItem/children``
    /// are still parsed, so an unrecognised item never drops its subtree.
    case unsupported(valueType: String)
}

extension DICOMDataset {
    /// Recursion depth limit for Content Sequence parsing.
    ///
    /// PS3.3 does not itself cap how deeply an SR tree may nest, but real
    /// reports — including deeply nested TID 1500 measurement groups — stay
    /// well under this. `DICOMStructuredReport.init(file:)` parses untrusted
    /// input, so nesting past this depth is treated as malformed rather than
    /// walked, which keeps a hostile or corrupt Content Sequence from
    /// blowing the call stack.
    static let structuredReportMaxDepth = 64

    /// Parses `self` as one Structured Report Content Item (PS3.3 C.17.3),
    /// recursing into Content Sequence `(0040,A730)` for its children.
    ///
    /// `isRoot` suppresses reading Relationship Type on the dataset that
    /// represents the report's root item, which has no parent to relate to.
    /// `parentCharacterSet` is the enclosing item's effective Specific
    /// Character Set, inherited per PS3.5 7.5.3 when this item declares
    /// none of its own.
    func structuredReportContentItem(isRoot: Bool, inheriting parentCharacterSet: DICOMCharacterSet, depth: Int) throws -> DICOMContentItem {
        guard depth <= DICOMDataset.structuredReportMaxDepth else {
            throw DICOMError.invalidStructuredReport
        }
        let characterSet = self.characterSet(inheriting: parentCharacterSet)
        let valueType = self[DICOMTag(group: 0x0040, element: 0xA040)]?.stringValue ?? ""
        let relationshipType = isRoot ? nil : self[DICOMTag(group: 0x0040, element: 0xA010)]?.stringValue
        let conceptName = self[DICOMTag(group: 0x0040, element: 0xA043)]?.sequenceItems?.first?.codeSequenceItem(inheriting: characterSet)
        let value = contentItemValue(valueType: valueType, characterSet: characterSet)
        let children = try (self[DICOMTag(group: 0x0040, element: 0xA730)]?.sequenceItems ?? []).map {
            try $0.structuredReportContentItem(isRoot: false, inheriting: characterSet, depth: depth + 1)
        }
        let referencedContentItemIdentifier = self[DICOMTag(group: 0x0040, element: 0xDB73)]?.uint32Values?.map(Int.init)

        return DICOMContentItem(
            relationshipType: relationshipType,
            valueType: valueType,
            conceptName: conceptName,
            value: value,
            children: children,
            referencedContentItemIdentifier: referencedContentItemIdentifier
        )
    }

    /// Parses this item's payload per its Value Type. Falls back to
    /// ``DICOMContentItemValue/unsupported(valueType:)`` for any Value Type
    /// DICOMKit does not yet model.
    private func contentItemValue(valueType: String, characterSet: DICOMCharacterSet) -> DICOMContentItemValue {
        switch valueType {
        case "CONTAINER":
            let continuity = self[DICOMTag(group: 0x0040, element: 0xA050)]?.stringValue
            return .container(continuity: continuity)

        case "TEXT":
            let text = self[DICOMTag(group: 0x0040, element: 0xA160)]?.stringValue(characterSet: characterSet) ?? ""
            return .text(text)

        case "CODE":
            let code = self[DICOMTag(group: 0x0040, element: 0xA168)]?.sequenceItems?.first?.codeSequenceItem(inheriting: characterSet) ?? DICOMCodeSequenceItem()
            return .code(code)

        case "NUM":
            let measuredValueItem = self[DICOMTag(group: 0x0040, element: 0xA300)]?.sequenceItems?.first
            let value = measuredValueItem?[DICOMTag(group: 0x0040, element: 0xA30A)]?.doubleValue
            let units = measuredValueItem?[DICOMTag(group: 0x0040, element: 0x08EA)]?.sequenceItems?.first?.codeSequenceItem(inheriting: characterSet)
            let qualifier = measuredValueItem?[DICOMTag(group: 0x0040, element: 0xA301)]?.sequenceItems?.first?.codeSequenceItem(inheriting: characterSet)
            return .num(value: value, units: units, qualifier: qualifier)

        case "DATE":
            return .date(self[DICOMTag(group: 0x0040, element: 0xA121)]?.stringValue ?? "")

        case "TIME":
            return .time(self[DICOMTag(group: 0x0040, element: 0xA122)]?.stringValue ?? "")

        case "DATETIME":
            return .dateTime(self[DICOMTag(group: 0x0040, element: 0xA120)]?.stringValue ?? "")

        case "UIDREF":
            return .uidRef(self[DICOMTag(group: 0x0040, element: 0xA124)]?.stringValue ?? "")

        case "PNAME":
            let personName = self[DICOMTag(group: 0x0040, element: 0xA123)]?.personNameValue(characterSet: characterSet) ?? DICOMPersonName("")
            return .personName(personName)

        case "IMAGE":
            guard let reference = self.referencedSOPReference(sequenceTag: DICOMTag(group: 0x0008, element: 0x1199)) else {
                return .unsupported(valueType: valueType)
            }
            let item = self[DICOMTag(group: 0x0008, element: 0x1199)]?.sequenceItems?.first
            let frameNumbers = item?[DICOMTag(group: 0x0008, element: 0x1160)]?.stringValues?.compactMap(Int.init)
            let segmentNumbers = item?[DICOMTag(group: 0x0062, element: 0x000B)]?.uint16Values?.map(Int.init)
            return .image(reference: reference, frameNumbers: frameNumbers, segmentNumbers: segmentNumbers)

        case "WAVEFORM":
            guard let reference = self.referencedSOPReference(sequenceTag: DICOMTag(group: 0x0008, element: 0x1199)) else {
                return .unsupported(valueType: valueType)
            }
            let item = self[DICOMTag(group: 0x0008, element: 0x1199)]?.sequenceItems?.first
            let channels = item?[DICOMTag(group: 0x0040, element: 0xA0B0)]?.uint16Values?.map(Int.init)
            return .waveform(reference: reference, channels: channels)

        case "COMPOSITE":
            guard let reference = self.referencedSOPReference(sequenceTag: DICOMTag(group: 0x0008, element: 0x1199)) else {
                return .unsupported(valueType: valueType)
            }
            return .composite(reference)

        case "SCOORD":
            let graphicType = self[DICOMTag(group: 0x0070, element: 0x0023)]?.stringValue ?? ""
            let data = self[DICOMTag(group: 0x0070, element: 0x0022)]?.float32Values?.map(Double.init) ?? []
            return .spatialCoordinates(graphicType: graphicType, data: data)

        case "SCOORD3D":
            let graphicType = self[DICOMTag(group: 0x0070, element: 0x0023)]?.stringValue ?? ""
            let data = self[DICOMTag(group: 0x0070, element: 0x0022)]?.float32Values?.map(Double.init) ?? []
            let frameOfReferenceUID = self[DICOMTag(group: 0x3006, element: 0x0024)]?.stringValue
            return .spatialCoordinates3D(graphicType: graphicType, data: data, frameOfReferenceUID: frameOfReferenceUID)

        case "TCOORD":
            let rangeType = self[DICOMTag(group: 0x0040, element: 0xA130)]?.stringValue ?? ""
            let samplePositions = self[DICOMTag(group: 0x0040, element: 0xA132)]?.uint32Values
            let timeOffsets = self[DICOMTag(group: 0x0040, element: 0xA138)]?.doubleValues
            let dateTimes = self[DICOMTag(group: 0x0040, element: 0xA13A)]?.stringValues
            return .temporalCoordinates(rangeType: rangeType, samplePositions: samplePositions, timeOffsets: timeOffsets, dateTimes: dateTimes)

        default:
            return .unsupported(valueType: valueType)
        }
    }

    /// Reads a `DICOMSOPReference` from the first item of the sequence at
    /// `sequenceTag` — shared by `IMAGE`, `WAVEFORM`, and `COMPOSITE`, whose
    /// Referenced SOP Sequence all use the same Referenced SOP Class/Instance
    /// UID pair as ``DICOMStorageCommitment``'s references.
    private func referencedSOPReference(sequenceTag: DICOMTag) -> DICOMSOPReference? {
        guard let item = self[sequenceTag]?.sequenceItems?.first,
              let sopClassUID = item[.referencedSOPClassUID]?.stringValue,
              let sopInstanceUID = item[.referencedSOPInstanceUID]?.stringValue else { return nil }
        return DICOMSOPReference(sopClassUID: sopClassUID, sopInstanceUID: sopInstanceUID)
    }
}

/// A DICOM Structured Report (PS3.3 A.35): document-level attributes plus
/// the Content Tree rooted at ``root``.
///
/// DICOMKit parses the tree faithfully — every Content Item, its value, and
/// its children — but does **not** interpret templates (for example TID
/// 1500 and its relatives) or impose meaning on a concept name. That is a
/// much larger, standards-heavy job on its own, and a wrong interpretation
/// of a measurement is worse than none at all. Consumers that need
/// template-aware behavior should walk ``root`` themselves, guided by
/// ``DICOMContentItem/conceptName``.
public struct DICOMStructuredReport: Sendable, Equatable {
    /// SOP Class UID `(0008,0016)`.
    public let sopClassUID: String?
    /// Completion Flag `(0040,A491)`: `PARTIAL` or `COMPLETE`.
    public let completionFlag: String?
    /// Verification Flag `(0040,A493)`: `UNVERIFIED` or `VERIFIED`.
    public let verificationFlag: String?
    /// Content Date `(0008,0023)`.
    public let contentDate: String?
    /// Content Time `(0008,0033)`.
    public let contentTime: String?
    /// The root Content Item. Its attributes — Value Type, Concept Name
    /// Code Sequence, Continuity of Content, and Content Sequence — live
    /// directly on the report's dataset, since the dataset itself *is* the
    /// root item (PS3.3 C.17.3).
    public let root: DICOMContentItem

    /// Parses a Structured Report from a file's dataset.
    ///
    /// - Throws: ``DICOMError/invalidStructuredReport`` when the dataset has
    ///   no Value Type `(0040,A040)` at all (it isn't an SR), or when a
    ///   Content Sequence nests deeper than
    ///   `DICOMDataset.structuredReportMaxDepth` — a guard against a
    ///   malformed or hostile document driving unbounded recursion.
    public init(file: DICOMFile) throws {
        let dataset = file.dataset
        guard dataset[DICOMTag(group: 0x0040, element: 0xA040)] != nil else {
            throw DICOMError.invalidStructuredReport
        }

        sopClassUID = dataset[.sopClassUID]?.stringValue
        completionFlag = dataset[DICOMTag(group: 0x0040, element: 0xA491)]?.stringValue
        verificationFlag = dataset[DICOMTag(group: 0x0040, element: 0xA493)]?.stringValue
        contentDate = dataset[DICOMTag(group: 0x0008, element: 0x0023)]?.stringValue
        contentTime = dataset[DICOMTag(group: 0x0008, element: 0x0033)]?.stringValue
        root = try dataset.structuredReportContentItem(isRoot: true, inheriting: .default, depth: 0)
    }
}
