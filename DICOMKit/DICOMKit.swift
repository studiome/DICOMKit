import Foundation

public struct DICOMTag: Hashable, Sendable, CustomStringConvertible {
    public let group: UInt16
    public let element: UInt16

    public init(group: UInt16, element: UInt16) {
        self.group = group
        self.element = element
    }

    public var description: String { String(format: "(%04X,%04X)", group, element) }

    public static let transferSyntaxUID = DICOMTag(group: 0x0002, element: 0x0010)
    public static let patientName = DICOMTag(group: 0x0010, element: 0x0010)
    public static let rows = DICOMTag(group: 0x0028, element: 0x0010)
    public static let columns = DICOMTag(group: 0x0028, element: 0x0011)
    public static let pixelData = DICOMTag(group: 0x7FE0, element: 0x0010)
}

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

public struct DICOMElement: Sendable, Hashable {
    public let tag: DICOMTag
    public let vr: DICOMVR
    public let value: Data

    public var stringValue: String? {
        var trimmedValue = value
        while let last = trimmedValue.last, last == 0 || last == 0x20 {
            trimmedValue.removeLast()
        }
        return String(data: trimmedValue, encoding: .utf8)
    }

    public var uint16Value: UInt16? {
        guard value.count >= 2 else { return nil }
        return UInt16(value[value.startIndex]) | (UInt16(value[value.startIndex + 1]) << 8)
    }
}

public struct DICOMDataset: Sendable, Sequence {
    private var storage: [DICOMTag: DICOMElement]

    public init(elements: [DICOMElement] = []) {
        storage = Dictionary(uniqueKeysWithValues: elements.map { ($0.tag, $0) })
    }

    public subscript(tag: DICOMTag) -> DICOMElement? { storage[tag] }

    public func makeIterator() -> Dictionary<DICOMTag, DICOMElement>.Values.Iterator {
        storage.values.makeIterator()
    }
}

public enum TransferSyntax: Sendable, Equatable {
    case implicitVRLittleEndian
    case explicitVRLittleEndian
    case explicitVRBigEndian
    case unknown(String)

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

public enum DICOMError: Error, Sendable, Equatable {
    case missingPart10Preamble
    case truncatedData
    case invalidVR(String)
    case unsupportedTransferSyntax(String)
}

public struct DICOMFile: Sendable {
    public let metaInformation: DICOMDataset
    public let dataset: DICOMDataset
    public let transferSyntax: TransferSyntax

    public init(data: Data) throws {
        guard data.count >= 132, data[128...131] == Data("DICM".utf8) else {
            throw DICOMError.missingPart10Preamble
        }

        var reader = Reader(data: data, offset: 132)
        var metaElements: [DICOMElement] = []
        while reader.offset + 4 <= data.count, reader.peekGroup() == 0x0002 {
            metaElements.append(try reader.readExplicitLittleEndianElement())
        }
        metaInformation = DICOMDataset(elements: metaElements)

        guard let uid = metaInformation[.transferSyntaxUID]?.stringValue else {
            throw DICOMError.unsupportedTransferSyntax("missing Transfer Syntax UID")
        }
        transferSyntax = TransferSyntax(uid: uid)
        guard transferSyntax == .explicitVRLittleEndian else {
            throw DICOMError.unsupportedTransferSyntax(uid)
        }

        var elements: [DICOMElement] = []
        while reader.offset < data.count {
            elements.append(try reader.readExplicitLittleEndianElement())
        }
        dataset = DICOMDataset(elements: elements)
    }
}

private struct Reader {
    let data: Data
    var offset: Int

    mutating func readExplicitLittleEndianElement() throws -> DICOMElement {
        let tag = DICOMTag(group: try readUInt16(), element: try readUInt16())
        let vrText = String(bytes: try readData(count: 2), encoding: .ascii) ?? ""
        guard let vr = DICOMVR(rawValue: vrText) else { throw DICOMError.invalidVR(vrText) }
        let length: Int
        if vr.uses32BitLength {
            _ = try readUInt16()
            length = Int(try readUInt32())
        } else {
            length = Int(try readUInt16())
        }
        return DICOMElement(tag: tag, vr: vr, value: try readData(count: length))
    }

    func peekGroup() -> UInt16? {
        guard offset + 2 <= data.count else { return nil }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
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
        guard count >= 0, offset + count <= data.count else { throw DICOMError.truncatedData }
        defer { offset += count }
        return data.subdata(in: offset..<(offset + count))
    }
}
