import Foundation

/// Errors raised while handling DIMSE command sets.
public enum DICOMDIMSEError: Error, Sendable, Equatable {
    case malformedCommandSet
    case unsupportedCommand(UInt16)
    case invalidMaximumPayloadLength
}

/// DIMSE commands currently supported by the association-independent codec.
///
/// C-ECHO is deliberately available without a dataset, making it a useful
/// verification operation before applications add storage or query services.
public enum DICOMDIMSECommand: Sendable, Equatable {
    case cEchoRequest(messageID: UInt16)
    case cEchoResponse(messageIDBeingRespondedTo: UInt16, status: UInt16)
    case cStoreRequest(messageID: UInt16, affectedSOPClassUID: String, affectedSOPInstanceUID: String)
    case cStoreResponse(messageIDBeingRespondedTo: UInt16, status: UInt16)

    /// Serializes this command set using the mandatory Implicit VR Little Endian syntax.
    public func encodedCommandSet() throws -> Data {
        var content = Data()
        switch self {
        case .cEchoRequest(let messageID):
            Self.appendElement(tag: 0x01000000, value: Self.uint16(0x0030), to: &content)
            Self.appendElement(tag: 0x01100000, value: Self.uint16(messageID), to: &content)
            Self.appendElement(tag: 0x08000000, value: Self.uint16(0x0101), to: &content)
        case .cEchoResponse(let messageID, let status):
            Self.appendElement(tag: 0x01000000, value: Self.uint16(0x8030), to: &content)
            Self.appendElement(tag: 0x01200000, value: Self.uint16(messageID), to: &content)
            Self.appendElement(tag: 0x08000000, value: Self.uint16(0x0101), to: &content)
            Self.appendElement(tag: 0x09000000, value: Self.uint16(status), to: &content)
        case .cStoreRequest(let messageID, let sopClassUID, let sopInstanceUID):
            Self.appendElement(tag: 0x00020000, value: Self.ui(sopClassUID), to: &content)
            Self.appendElement(tag: 0x01000000, value: Self.uint16(0x0001), to: &content)
            Self.appendElement(tag: 0x01100000, value: Self.uint16(messageID), to: &content)
            Self.appendElement(tag: 0x07000000, value: Self.uint16(0), to: &content)
            Self.appendElement(tag: 0x08000000, value: Self.uint16(0), to: &content)
            Self.appendElement(tag: 0x10000000, value: Self.ui(sopInstanceUID), to: &content)
        case .cStoreResponse(let messageID, let status):
            Self.appendElement(tag: 0x01000000, value: Self.uint16(0x8001), to: &content)
            Self.appendElement(tag: 0x01200000, value: Self.uint16(messageID), to: &content)
            Self.appendElement(tag: 0x08000000, value: Self.uint16(0x0101), to: &content)
            Self.appendElement(tag: 0x09000000, value: Self.uint16(status), to: &content)
        }
        var result = Data()
        Self.appendElement(tag: 0x00000000, value: Self.uint32(UInt32(content.count)), to: &result)
        result.append(content)
        return result
    }

    /// Decodes a complete DIMSE command set encoded with Implicit VR Little Endian.
    public static func decodeCommandSet(_ data: Data) throws -> DICOMDIMSECommand {
        var offset = 0
        var values: [UInt32: Data] = [:]
        while offset < data.count {
            guard data.count - offset >= 8 else { throw DICOMDIMSEError.malformedCommandSet }
            let tag = UInt32(data[offset]) | UInt32(data[offset + 1]) << 8 | UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
            let length = Int(UInt32(data[offset + 4]) | UInt32(data[offset + 5]) << 8 | UInt32(data[offset + 6]) << 16 | UInt32(data[offset + 7]) << 24)
            offset += 8
            guard length <= data.count - offset else { throw DICOMDIMSEError.malformedCommandSet }
            values[tag] = data.subdata(in: offset..<(offset + length)); offset += length
        }
        guard let field = values[0x01000000].flatMap(readUInt16) else { throw DICOMDIMSEError.malformedCommandSet }
        switch field {
        case 0x0030:
            guard values[0x08000000].flatMap(readUInt16) == 0x0101, let messageID = values[0x01100000].flatMap(readUInt16) else { throw DICOMDIMSEError.malformedCommandSet }
            return .cEchoRequest(messageID: messageID)
        case 0x8030:
            guard values[0x08000000].flatMap(readUInt16) == 0x0101, let messageID = values[0x01200000].flatMap(readUInt16), let status = values[0x09000000].flatMap(readUInt16) else { throw DICOMDIMSEError.malformedCommandSet }
            return .cEchoResponse(messageIDBeingRespondedTo: messageID, status: status)
        case 0x0001:
            guard let messageID = values[0x01100000].flatMap(readUInt16),
                  values[0x08000000].flatMap(readUInt16) == 0,
                  let sopClassUID = values[0x00020000].flatMap(readUI),
                  let sopInstanceUID = values[0x10000000].flatMap(readUI) else { throw DICOMDIMSEError.malformedCommandSet }
            return .cStoreRequest(messageID: messageID, affectedSOPClassUID: sopClassUID, affectedSOPInstanceUID: sopInstanceUID)
        case 0x8001:
            guard values[0x08000000].flatMap(readUInt16) == 0x0101, let messageID = values[0x01200000].flatMap(readUInt16), let status = values[0x09000000].flatMap(readUInt16) else { throw DICOMDIMSEError.malformedCommandSet }
            return .cStoreResponse(messageIDBeingRespondedTo: messageID, status: status)
        default: throw DICOMDIMSEError.unsupportedCommand(field)
        }
    }

    /// Splits the command set into command PDVs suitable for a P-DATA-TF PDU.
    public func commandPDVs(contextID: UInt8, maximumPayloadLength: Int) throws -> [DICOMPDataValue] {
        guard maximumPayloadLength > 0 else { throw DICOMDIMSEError.invalidMaximumPayloadLength }
        let command = try encodedCommandSet()
        let chunks = stride(from: 0, to: command.count, by: maximumPayloadLength).map {
            command.subdata(in: $0..<min($0 + maximumPayloadLength, command.count))
        }
        return chunks.enumerated().map { index, data in
            DICOMPDataValue(contextID: contextID, isCommand: true, isLastFragment: index == chunks.count - 1, data: data)
        }
    }

    private static func appendElement(tag: UInt32, value: Data, to data: inout Data) {
        data.append(UInt8(tag & 0xFF)); data.append(UInt8((tag >> 8) & 0xFF)); data.append(UInt8((tag >> 16) & 0xFF)); data.append(UInt8((tag >> 24) & 0xFF))
        data.append(UInt8(value.count & 0xFF)); data.append(UInt8((value.count >> 8) & 0xFF)); data.append(UInt8((value.count >> 16) & 0xFF)); data.append(UInt8((value.count >> 24) & 0xFF))
        data.append(value)
    }
    private static func uint16(_ value: UInt16) -> Data { Data([UInt8(value & 0xFF), UInt8(value >> 8)]) }
    private static func uint32(_ value: UInt32) -> Data { Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8(value >> 24)]) }
    private static func readUInt16(_ value: Data) -> UInt16? { guard value.count == 2 else { return nil }; return UInt16(value[0]) | UInt16(value[1]) << 8 }
    private static func ui(_ value: String) -> Data { var bytes = Data(value.utf8); if bytes.count % 2 != 0 { bytes.append(0) }; return bytes }
    private static func readUI(_ value: Data) -> String? { String(data: value, encoding: .ascii)?.trimmingCharacters(in: CharacterSet(charactersIn: "\u{0} ")) }
}
