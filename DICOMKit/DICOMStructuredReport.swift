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

        default:
            return .unsupported(valueType: valueType)
        }
    }
}
