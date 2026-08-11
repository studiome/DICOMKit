import Foundation

/// A DICOM data element and its decoded structural information.
public struct DICOMElement: Sendable, Equatable {
    /// The element's DICOM tag.
    public let tag: DICOMTag
    /// The element's Value Representation.
    public let vr: DICOMVR
    /// The raw encoded value for non-sequence elements.
    ///
    /// This value is empty for elements whose VR is ``DICOMVR/SQ``.
    public let value: Data
    /// The datasets contained by a sequence element, or `nil` for a non-sequence element.
    public let sequenceItems: [DICOMDataset]?
    /// The compressed fragments of encapsulated Pixel Data, or `nil` for all
    /// other elements. The Basic Offset Table is not included.
    public let encapsulatedFragments: [Data]?
    /// Byte offsets of encapsulated Pixel Data fragments, measured from the
    /// first fragment's Item tag. `nil` for non-encapsulated elements.
    public let encapsulatedFragmentOffsets: [Int]?
    /// The Basic Offset Table from encapsulated Pixel Data, if present.
    public let basicOffsetTable: Data?

    /// Creates an element from its tag, VR, raw value, and optional sequence items.
    public init(tag: DICOMTag, vr: DICOMVR, value: Data, sequenceItems: [DICOMDataset]? = nil, encapsulatedFragments: [Data]? = nil, encapsulatedFragmentOffsets: [Int]? = nil, basicOffsetTable: Data? = nil) {
        self.tag = tag
        self.vr = vr
        self.value = value
        self.sequenceItems = sequenceItems
        self.encapsulatedFragments = encapsulatedFragments
        self.encapsulatedFragmentOffsets = encapsulatedFragmentOffsets
        self.basicOffsetTable = basicOffsetTable
    }

    /// The UTF-8 string value with DICOM space and NUL padding removed.
    ///
    /// Returns `nil` for sequence elements or values that aren't valid UTF-8.
    public var stringValue: String? {
        stringValue(characterSet: .utf8)
    }

    /// Decodes this text element with a DICOM character set.
    public func stringValue(characterSet: DICOMCharacterSet) -> String? {
        guard sequenceItems == nil else { return nil }
        var trimmedValue = value
        while let last = trimmedValue.last, last == 0 || last == 0x20 {
            trimmedValue.removeLast()
        }
        return characterSet.decode(trimmedValue)
    }

    /// Backslash-separated text components in this element.
    public var stringValues: [String]? {
        stringValues(characterSet: .utf8)
    }

    /// Backslash-separated text components decoded with a DICOM character set.
    public func stringValues(characterSet: DICOMCharacterSet) -> [String]? {
        guard let value = stringValue(characterSet: characterSet) else { return nil }
        return value.split(separator: "\\", omittingEmptySubsequences: false).map(String.init)
    }

    /// The first 16-bit unsigned little-endian value, if the value contains one.
    public var uint16Value: UInt16? {
        guard value.count >= 2 else { return nil }
        return value.littleEndian(at: 0)
    }

    /// The first 16-bit signed little-endian value, if the value contains one.
    ///
    /// Intended for the `SS` VR.
    public var int16Value: Int16? {
        guard let bitPattern = uint16Value else { return nil }
        return Int16(bitPattern: bitPattern)
    }

    /// The first numeric value parsed from a string-encoded numeric VR such as
    /// `DS` or `IS`.
    ///
    /// DICOM allows `DS` (Decimal String) and `IS` (Integer String) values to
    /// contain multiple backslash-separated values; only the first value is
    /// returned. Surrounding whitespace is trimmed. Returns `nil` if the value
    /// is empty, isn't valid UTF-8, or the first component can't be parsed as
    /// a `Double`.
    public var doubleValue: Double? {
        doubleValues?.first
    }

    /// All `DS` or `IS` components parsed as `Double` values.
    public var doubleValues: [Double]? {
        guard let values = stringValues else { return nil }
        let result = values.map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard result.allSatisfy({ $0 != nil }) else { return nil }
        return result.compactMap { $0 }
    }

    /// All little-endian unsigned 16-bit components.
    public var uint16Values: [UInt16]? {
        guard value.count.isMultiple(of: 2) else { return nil }
        return stride(from: 0, to: value.count, by: 2).map { value.littleEndian(at: $0) }
    }
}
