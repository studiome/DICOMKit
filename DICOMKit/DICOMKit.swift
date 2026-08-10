import Foundation

/// A DICOM data-element identifier consisting of a group and element number.
public struct DICOMTag: Hashable, Sendable, CustomStringConvertible {
    /// The 16-bit DICOM group number.
    public let group: UInt16
    /// The 16-bit DICOM element number.
    public let element: UInt16

    /// Creates a tag from its group and element numbers.
    public init(group: UInt16, element: UInt16) {
        self.group = group
        self.element = element
    }

    /// The canonical hexadecimal representation, for example `(0010,0010)`.
    public var description: String { String(format: "(%04X,%04X)", group, element) }

    /// Transfer Syntax UID `(0002,0010)` in File Meta Information.
    public static let transferSyntaxUID = DICOMTag(group: 0x0002, element: 0x0010)
    /// Patient's Name `(0010,0010)`.
    public static let patientName = DICOMTag(group: 0x0010, element: 0x0010)
    /// Rows `(0028,0010)`.
    public static let rows = DICOMTag(group: 0x0028, element: 0x0010)
    /// Columns `(0028,0011)`.
    public static let columns = DICOMTag(group: 0x0028, element: 0x0011)
    /// Pixel Data `(7FE0,0010)`.
    public static let pixelData = DICOMTag(group: 0x7FE0, element: 0x0010)
    /// Referenced Study Sequence `(0008,1110)`.
    public static let referencedStudySequence = DICOMTag(group: 0x0008, element: 0x1110)
    /// Referenced SOP Class UID `(0008,1150)`.
    public static let referencedSOPClassUID = DICOMTag(group: 0x0008, element: 0x1150)
}

/// A DICOM Value Representation (VR).
///
/// The raw value of each case is the two-letter code defined by DICOM PS3.5.
public enum DICOMVR: String, Sendable, CaseIterable {
    case AE, AS, AT, CS, DA, DS, DT, FD, FL, IS, LO, LT, OB, OD, OF, OL, OV, OW
    case PN, SH, SL, SQ, SS, ST, SV, TM, UC, UI, UL, UN, UR, US, UT, UV

    var uses32BitLength: Bool {
        switch self {
        case .OB, .OD, .OF, .OL, .OV, .OW, .SQ, .UC, .UN, .UR, .UT:
            true
        default:
            false
        }
    }
}

/// A DICOM data element and its decoded structural information.
public struct DICOMElement: Sendable {
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

    /// Creates an element from its tag, VR, raw value, and optional sequence items.
    public init(tag: DICOMTag, vr: DICOMVR, value: Data, sequenceItems: [DICOMDataset]? = nil) {
        self.tag = tag
        self.vr = vr
        self.value = value
        self.sequenceItems = sequenceItems
    }

    /// The UTF-8 string value with DICOM space and NUL padding removed.
    ///
    /// Returns `nil` for sequence elements or values that aren't valid UTF-8.
    public var stringValue: String? {
        guard sequenceItems == nil else { return nil }
        var trimmedValue = value
        while let last = trimmedValue.last, last == 0 || last == 0x20 {
            trimmedValue.removeLast()
        }
        return String(data: trimmedValue, encoding: .utf8)
    }

    /// The first 16-bit unsigned little-endian value, if the value contains one.
    public var uint16Value: UInt16? {
        guard value.count >= 2 else { return nil }
        return UInt16(value[value.startIndex]) | (UInt16(value[value.startIndex + 1]) << 8)
    }
}

/// A collection of DICOM elements indexed by tag.
public struct DICOMDataset: Sendable, Sequence {
    private var storage: [DICOMTag: DICOMElement]

    /// Creates a dataset containing the supplied elements.
    ///
    /// If multiple elements use the same tag, the last element is retained.
    public init(elements: [DICOMElement] = []) {
        storage = Dictionary(uniqueKeysWithValues: elements.map { ($0.tag, $0) })
    }

    /// Returns the element for `tag`, if present.
    public subscript(tag: DICOMTag) -> DICOMElement? { storage[tag] }

    /// Returns an iterator over the dataset's elements.
    public func makeIterator() -> Dictionary<DICOMTag, DICOMElement>.Values.Iterator {
        storage.values.makeIterator()
    }
}

/// A DICOM transfer syntax identified by its UID.
public enum TransferSyntax: Sendable, Equatable {
    /// Implicit VR Little Endian (`1.2.840.10008.1.2`).
    case implicitVRLittleEndian
    /// Explicit VR Little Endian (`1.2.840.10008.1.2.1`).
    case explicitVRLittleEndian
    /// Explicit VR Big Endian (`1.2.840.10008.1.2.2`).
    case explicitVRBigEndian
    /// A transfer syntax not modelled by DICOMKit.
    case unknown(String)

    /// The transfer syntax UID.
    public var uid: String {
        switch self {
        case .implicitVRLittleEndian: "1.2.840.10008.1.2"
        case .explicitVRLittleEndian: "1.2.840.10008.1.2.1"
        case .explicitVRBigEndian: "1.2.840.10008.1.2.2"
        case .unknown(let uid): uid
        }
    }

    init(uid: String) {
        switch uid {
        case Self.implicitVRLittleEndian.uid: self = .implicitVRLittleEndian
        case Self.explicitVRLittleEndian.uid: self = .explicitVRLittleEndian
        case Self.explicitVRBigEndian.uid: self = .explicitVRBigEndian
        default: self = .unknown(uid)
        }
    }
}

/// Errors produced while reading a DICOM Part 10 file.
public enum DICOMError: Error, Sendable, Equatable {
    /// The file doesn't contain the 128-byte preamble followed by `DICM`.
    case missingPart10Preamble
    /// The input ended before the declared structure could be read.
    case truncatedData
    /// An Explicit VR element contains an unrecognised VR code.
    case invalidVR(String)
    /// The file uses a transfer syntax that the reader doesn't support.
    case unsupportedTransferSyntax(String)
    /// A non-sequence element declares an undefined length.
    case unsupportedUndefinedLength(DICOMTag)
    /// A sequence contains an invalid Item or Sequence Delimitation Item.
    case invalidSequenceItem(DICOMTag)
}

/// A parsed DICOM Part 10 file.
public struct DICOMFile: Sendable {
    /// The File Meta Information dataset (group `0002`).
    public let metaInformation: DICOMDataset
    /// The main DICOM dataset.
    public let dataset: DICOMDataset
    /// The transfer syntax declared by the File Meta Information.
    public let transferSyntax: TransferSyntax

    /// Parses a DICOM Part 10 file from memory.
    ///
    /// The reader supports Explicit VR Little Endian and Implicit VR Little
    /// Endian datasets, including defined-length and undefined-length sequences.
    ///
    /// - Parameter data: The complete contents of a DICOM Part 10 file.
    /// - Throws: ``DICOMError`` if the file is malformed or uses an unsupported syntax.
    public init(data: Data) throws {
        guard data.count >= 132, data[128...131] == Data("DICM".utf8) else {
            throw DICOMError.missingPart10Preamble
        }

        var reader = Reader(data: data, offset: 132)
        var metaElements: [DICOMElement] = []
        while reader.peekTag()?.group == 0x0002 {
            metaElements.append(try reader.readElement(transferSyntax: .explicitVRLittleEndian))
        }
        metaInformation = DICOMDataset(elements: metaElements)

        guard let uid = metaInformation[.transferSyntaxUID]?.stringValue else {
            throw DICOMError.unsupportedTransferSyntax("missing Transfer Syntax UID")
        }
        transferSyntax = TransferSyntax(uid: uid)
        guard transferSyntax == .explicitVRLittleEndian || transferSyntax == .implicitVRLittleEndian else {
            throw DICOMError.unsupportedTransferSyntax(uid)
        }

        dataset = DICOMDataset(elements: try reader.readDataset(transferSyntax: transferSyntax))
    }
}

private struct Reader {
    let data: Data
    var offset: Int

    mutating func readDataset(transferSyntax: TransferSyntax, endingAt endOffset: Int? = nil) throws -> [DICOMElement] {
        var elements: [DICOMElement] = []
        while true {
            if let endOffset {
                guard offset <= endOffset else { throw DICOMError.truncatedData }
                if offset == endOffset { return elements }
            }
            guard offset < data.count else {
                guard endOffset == nil else { throw DICOMError.truncatedData }
                return elements
            }
            elements.append(try readElement(transferSyntax: transferSyntax))
        }
    }

    mutating func readElement(transferSyntax: TransferSyntax) throws -> DICOMElement {
        let tag = try readTag()
        let vr: DICOMVR
        let length: UInt32

        switch transferSyntax {
        case .explicitVRLittleEndian:
            let vrText = String(bytes: try readData(count: 2), encoding: .ascii) ?? ""
            guard let parsedVR = DICOMVR(rawValue: vrText) else { throw DICOMError.invalidVR(vrText) }
            vr = parsedVR
            if vr.uses32BitLength {
                _ = try readUInt16()
                length = try readUInt32()
            } else {
                length = UInt32(try readUInt16())
            }
        case .implicitVRLittleEndian:
            vr = DICOMDictionary.vr(for: tag) ?? .UN
            length = try readUInt32()
        default:
            throw DICOMError.unsupportedTransferSyntax(transferSyntax.uid)
        }

        if vr == .SQ {
            return DICOMElement(tag: tag, vr: vr, value: Data(), sequenceItems: try readSequence(transferSyntax: transferSyntax, length: length))
        }
        guard length != .max else { throw DICOMError.unsupportedUndefinedLength(tag) }
        return DICOMElement(tag: tag, vr: vr, value: try readData(count: Int(length)))
    }

    mutating func readSequence(transferSyntax: TransferSyntax, length: UInt32) throws -> [DICOMDataset] {
        let endOffset: Int?
        if length == .max {
            endOffset = nil
        } else {
            let candidate = offset + Int(length)
            guard candidate <= data.count else { throw DICOMError.truncatedData }
            endOffset = candidate
        }

        var items: [DICOMDataset] = []
        while offset < data.count {
            if let endOffset, offset == endOffset { return items }
            let itemTag = try readTag()
            let itemLength = try readUInt32()
            if itemTag == DICOMTag(group: 0xFFFE, element: 0xE0DD) {
                guard endOffset == nil, itemLength == 0 else { throw DICOMError.invalidSequenceItem(itemTag) }
                return items
            }
            guard itemTag == DICOMTag(group: 0xFFFE, element: 0xE000) else {
                throw DICOMError.invalidSequenceItem(itemTag)
            }

            let itemElements: [DICOMElement]
            if itemLength == .max {
                itemElements = try readUndefinedLengthItem(transferSyntax: transferSyntax)
            } else {
                let itemEndOffset = offset + Int(itemLength)
                guard itemEndOffset <= data.count else { throw DICOMError.truncatedData }
                itemElements = try readDataset(transferSyntax: transferSyntax, endingAt: itemEndOffset)
            }
            items.append(DICOMDataset(elements: itemElements))
        }
        if let endOffset, offset == endOffset { return items }
        throw DICOMError.truncatedData
    }

    mutating func readUndefinedLengthItem(transferSyntax: TransferSyntax) throws -> [DICOMElement] {
        var elements: [DICOMElement] = []
        while offset < data.count {
            if peekTag() == DICOMTag(group: 0xFFFE, element: 0xE00D) {
                _ = try readTag()
                guard try readUInt32() == 0 else { throw DICOMError.truncatedData }
                return elements
            }
            elements.append(try readElement(transferSyntax: transferSyntax))
        }
        throw DICOMError.truncatedData
    }

    func peekTag() -> DICOMTag? {
        guard offset + 4 <= data.count else { return nil }
        return DICOMTag(
            group: UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8),
            element: UInt16(data[offset + 2]) | (UInt16(data[offset + 3]) << 8)
        )
    }

    mutating func readTag() throws -> DICOMTag {
        DICOMTag(group: try readUInt16(), element: try readUInt16())
    }

    mutating func readUInt16() throws -> UInt16 {
        let value = try readData(count: 2)
        return UInt16(value[value.startIndex]) | (UInt16(value[value.startIndex + 1]) << 8)
    }

    mutating func readUInt32() throws -> UInt32 {
        let value = try readData(count: 4)
        return UInt32(value[value.startIndex])
            | (UInt32(value[value.startIndex + 1]) << 8)
            | (UInt32(value[value.startIndex + 2]) << 16)
            | (UInt32(value[value.startIndex + 3]) << 24)
    }

    mutating func readData(count: Int) throws -> Data {
        guard count >= 0, count <= data.count - offset else { throw DICOMError.truncatedData }
        defer { offset += count }
        return data.subdata(in: offset..<(offset + count))
    }
}

private enum DICOMDictionary {
    static func vr(for tag: DICOMTag) -> DICOMVR? {
        switch tag {
        case .transferSyntaxUID, .referencedSOPClassUID: .UI
        case .patientName: .PN
        case .rows, .columns: .US
        case .pixelData: .OW
        case .referencedStudySequence: .SQ
        default: nil
        }
    }
}
