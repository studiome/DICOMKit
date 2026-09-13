import Foundation

/// The standard DICOM coded-concept triplet (PS3.3 Section 8.9), reused by
/// every macro that identifies a concept through a coding scheme rather than
/// free text — for example an anatomic region or a measurement unit.
public struct DICOMCodeSequenceItem: Sendable, Equatable {
    /// Code Value `(0008,0100)`.
    public let codeValue: String?
    /// Coding Scheme Designator `(0008,0102)`.
    public let codingSchemeDesignator: String?
    /// Code Meaning `(0008,0104)`.
    public let codeMeaning: String?

    public init(codeValue: String? = nil, codingSchemeDesignator: String? = nil, codeMeaning: String? = nil) {
        self.codeValue = codeValue
        self.codingSchemeDesignator = codingSchemeDesignator
        self.codeMeaning = codeMeaning
    }
}

extension DICOMDataset {
    /// Parses `self` as a code sequence item (PS3.3 Section 8.9): Code Value
    /// `(0008,0100)`, Coding Scheme Designator `(0008,0102)`, and Code
    /// Meaning `(0008,0104)`.
    ///
    /// Code Meaning is `LO` and therefore charset-sensitive: it is decoded
    /// using this item's own Specific Character Set declaration, inheriting
    /// `parent`'s when this item names none (PS3.5 7.5.3).
    ///
    /// `nil` when none of the three attributes is present.
    func codeSequenceItem(inheriting parent: DICOMCharacterSet) -> DICOMCodeSequenceItem? {
        let codeValue = self[DICOMTag(group: 0x0008, element: 0x0100)]?.stringValue
        let codingSchemeDesignator = self[DICOMTag(group: 0x0008, element: 0x0102)]?.stringValue
        let codeMeaning = stringValue(for: DICOMTag(group: 0x0008, element: 0x0104), inheriting: parent)
        guard codeValue != nil || codingSchemeDesignator != nil || codeMeaning != nil else { return nil }
        return DICOMCodeSequenceItem(codeValue: codeValue, codingSchemeDesignator: codingSchemeDesignator, codeMeaning: codeMeaning)
    }
}
