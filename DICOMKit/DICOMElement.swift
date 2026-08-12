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

    /// Creates encapsulated Pixel Data from already-compressed frame fragments.
    ///
    /// Each nested array represents one frame and may contain one or more
    /// fragments. The initializer calculates the Basic Offset Table using
    /// DICOM item-header and even-length padding rules; it does not compress
    /// pixel samples itself.
    public init(encapsulatedPixelDataFrames frames: [[Data]], vr: DICOMVR = .OB) throws {
        guard !frames.isEmpty, frames.allSatisfy({ !$0.isEmpty }), (vr == .OB || vr == .OW) else {
            throw DICOMError.invalidEncapsulatedPixelData
        }
        var fragments: [Data] = []
        var offsets: [Int] = []
        var basicOffsetTable = Data()
        var offset = 0
        for frame in frames {
            guard offset <= Int(UInt32.max) else { throw DICOMError.invalidEncapsulatedPixelData }
            let offset32 = UInt32(offset)
            basicOffsetTable.append(UInt8(offset32 & 0xFF)); basicOffsetTable.append(UInt8(offset32 >> 8))
            basicOffsetTable.append(UInt8(offset32 >> 16)); basicOffsetTable.append(UInt8(offset32 >> 24))
            for fragment in frame {
                offsets.append(offset)
                fragments.append(fragment)
                let paddedLength = fragment.count + (fragment.count.isMultiple(of: 2) ? 0 : 1)
                guard offset <= Int.max - 8 - paddedLength else { throw DICOMError.invalidEncapsulatedPixelData }
                offset += 8 + paddedLength
            }
        }
        self.init(tag: .pixelData, vr: vr, value: Data(), encapsulatedFragments: fragments, encapsulatedFragmentOffsets: offsets, basicOffsetTable: basicOffsetTable)
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
        values(as: UInt16.self)
    }

    /// All little-endian signed 16-bit components.
    public var int16Values: [Int16]? { uint16Values?.map { Int16(bitPattern: $0) } }

    /// All little-endian unsigned 32-bit components.
    public var uint32Values: [UInt32]? { values(as: UInt32.self) }

    /// All little-endian unsigned 64-bit components.
    public var uint64Values: [UInt64]? { values(as: UInt64.self) }

    /// All little-endian signed 32-bit components.
    public var int32Values: [Int32]? { uint32Values?.map { Int32(bitPattern: $0) } }

    /// All little-endian IEEE 754 single-precision components.
    public var float32Values: [Float]? { uint32Values?.map { Float(bitPattern: $0) } }

    /// All little-endian IEEE 754 double-precision components.
    public var float64Values: [Double]? {
        guard let values = values(as: UInt64.self) else { return nil }
        return values.map { Double(bitPattern: $0) }
    }

    /// All Attribute Tag `(gggg,eeee)` values stored in little-endian order.
    public var attributeTagValues: [DICOMTag]? {
        guard value.count.isMultiple(of: 4) else { return nil }
        return stride(from: 0, to: value.count, by: 4).map {
            DICOMTag(group: value.littleEndian(at: $0), element: value.littleEndian(at: $0 + 2))
        }
    }

    /// The three representation groups of a `PN` value.
    public var personNameValue: DICOMPersonName? {
        guard vr == .PN, let stringValue else { return nil }
        return DICOMPersonName(stringValue)
    }

    /// Parses a `DA`, `TM`, or `DT` value without discarding its offset.
    public var dateComponentsValue: DateComponents? {
        guard let text = stringValue else { return nil }
        switch vr {
        case .DA: return Self.dateComponents(from: text)
        case .TM: return Self.timeComponents(from: text)
        case .DT: return Self.dateTimeComponents(from: text)
        default: return nil
        }
    }

    private func values<T: FixedWidthInteger & UnsignedInteger>(as type: T.Type) -> [T]? {
        let width = MemoryLayout<T>.size
        guard value.count.isMultiple(of: width) else { return nil }
        return stride(from: 0, to: value.count, by: width).map { value.littleEndian(at: $0, as: T.self) }
    }

    private static func dateComponents(from text: String) -> DateComponents? {
        guard text.count == 8, let year = Int(text.prefix(4)), let month = Int(text.dropFirst(4).prefix(2)), let day = Int(text.suffix(2)) else { return nil }
        return DateComponents(year: year, month: month, day: day)
    }

    private static func timeComponents(from text: String) -> DateComponents? {
        let parts = text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let time = String(parts[0])
        guard (2...6).contains(time.count), time.allSatisfy(\.isNumber), let hour = Int(time.prefix(2)) else { return nil }
        let minute = time.count >= 4 ? Int(time.dropFirst(2).prefix(2)) : nil
        let second = time.count >= 6 ? Int(time.suffix(2)) : nil
        let nanosecond = parts.count == 2 ? Int((String(parts[1]) + String(repeating: "0", count: max(0, 9 - parts[1].count))).prefix(9)) : nil
        return DateComponents(hour: hour, minute: minute, second: second, nanosecond: nanosecond)
    }

    private static func dateTimeComponents(from text: String) -> DateComponents? {
        let offsetIndex = text.firstIndex(where: { $0 == "+" || $0 == "-" })
        let dateTime = String(offsetIndex.map { text[..<$0] } ?? text[...])
        guard dateTime.count >= 8, var result = dateComponents(from: String(dateTime.prefix(8))) else { return nil }
        let timeText = String(dateTime.dropFirst(8))
        if !timeText.isEmpty {
            guard let time = timeComponents(from: timeText) else { return nil }
            result.hour = time.hour; result.minute = time.minute; result.second = time.second; result.nanosecond = time.nanosecond
        }
        if let offsetIndex {
            let offset = text[offsetIndex...]
            guard offset.count == 5, let hours = Int(offset.dropFirst().prefix(2)), let minutes = Int(offset.suffix(2)) else { return nil }
            result.timeZone = TimeZone(secondsFromGMT: (text[offsetIndex] == "+" ? 1 : -1) * (hours * 3600 + minutes * 60))
        }
        return result
    }
}
