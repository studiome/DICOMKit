import Foundation

/// Errors raised while handling DIMSE command sets.
public enum DICOMDIMSEError: Error, Sendable, Equatable {
    case malformedCommandSet
    case unsupportedCommand(UInt16)
    case invalidMaximumPayloadLength
}

/// A DIMSE status code (PS3.7 C.4.1), classified per PS3.4 Annex C.
public struct DICOMDIMSEStatus: Sendable, Equatable, RawRepresentable {
    /// The broad outcome a status code signals.
    public enum Category: Sendable, Equatable { case success, pending, cancel, warning, failure }

    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }

    /// Classifies this code per PS3.4 Annex C: `0x0000` is success; `0xFF00`/`0xFF01`
    /// are pending; `0xFE00` is cancel; `0x0001`, `0x0107`, `0x0116`, and the
    /// `0xB000...0xBFFF` range are warning; everything else is failure.
    public var category: Category {
        switch rawValue {
        case 0x0000: return .success
        case 0xFF00, 0xFF01: return .pending
        case 0xFE00: return .cancel
        case 0x0001, 0x0107, 0x0116: return .warning
        case 0xB000...0xBFFF: return .warning
        default: return .failure
        }
    }

    /// `true` when further responses are expected for this operation.
    public var isPending: Bool { category == .pending }

    /// Success: the operation completed with no error (PS3.7 C.4.1).
    public static let success = DICOMDIMSEStatus(rawValue: 0x0000)
    /// Cancel: the operation was terminated by a C-CANCEL request (PS3.7 C.4.1).
    public static let cancel = DICOMDIMSEStatus(rawValue: 0xFE00)
    /// Pending: further responses for this operation are expected (PS3.7 C.4.1).
    public static let pending = DICOMDIMSEStatus(rawValue: 0xFF00)
    /// Pending, with a warning that one or more optional keys were not supported (PS3.4 C.4.1).
    public static let pendingWithWarning = DICOMDIMSEStatus(rawValue: 0xFF01)
    /// Refused: Out of Resources (PS3.4 Annex C).
    public static let refusedOutOfResources = DICOMDIMSEStatus(rawValue: 0xA700)
    /// Refused: SOP Class Not Supported (PS3.7 C.4.1).
    public static let refusedSOPClassNotSupported = DICOMDIMSEStatus(rawValue: 0x0122)
    /// Error: Cannot Understand (PS3.7 C.4.1).
    public static let errorCannotUnderstand = DICOMDIMSEStatus(rawValue: 0xC000)
    /// Error: Data Set does not match SOP Class (PS3.4 Annex C).
    public static let errorDataSetDoesNotMatchSOPClass = DICOMDIMSEStatus(rawValue: 0xA900)
}

/// The sub-operation progress counters carried by pending and final C-MOVE/C-GET
/// responses: Number of Remaining/Completed/Failed/Warning Sub-operations (PS3.4 Annex C).
public struct DICOMSubOperationCounts: Sendable, Equatable {
    public let remaining: UInt16
    public let completed: UInt16
    public let failed: UInt16
    public let warning: UInt16
    public init(remaining: UInt16, completed: UInt16, failed: UInt16, warning: UInt16) {
        self.remaining = remaining; self.completed = completed; self.failed = failed; self.warning = warning
    }
}

/// DIMSE commands currently supported by the association-independent codec.
///
/// C-ECHO is deliberately available without a dataset, making it a useful
/// verification operation before applications add storage or query services.
public enum DICOMDIMSECommand: Sendable, Equatable {
    case cEchoRequest(messageID: UInt16)
    case cEchoResponse(messageIDBeingRespondedTo: UInt16, status: DICOMDIMSEStatus)
    case cStoreRequest(messageID: UInt16, affectedSOPClassUID: String, affectedSOPInstanceUID: String)
    case cStoreResponse(messageIDBeingRespondedTo: UInt16, status: DICOMDIMSEStatus)
    case cFindRequest(messageID: UInt16, affectedSOPClassUID: String)
    case cFindResponse(messageIDBeingRespondedTo: UInt16, status: DICOMDIMSEStatus, identifierFollows: Bool, errorComment: String?)
    case cMoveRequest(messageID: UInt16, affectedSOPClassUID: String, moveDestination: String)
    case cMoveResponse(messageIDBeingRespondedTo: UInt16, status: DICOMDIMSEStatus, identifierFollows: Bool, subOperations: DICOMSubOperationCounts?, errorComment: String?)
    case cGetRequest(messageID: UInt16, affectedSOPClassUID: String)
    case cGetResponse(messageIDBeingRespondedTo: UInt16, status: DICOMDIMSEStatus, identifierFollows: Bool, subOperations: DICOMSubOperationCounts?, errorComment: String?)
    case cCancelRequest(messageIDBeingRespondedTo: UInt16)

    /// `true` when a data set follows this command's PDVs, per the Command Data Set
    /// Type element (0000,0800): fixed by command kind for requests, and by
    /// `identifierFollows` for the C-FIND/C-MOVE/C-GET responses.
    public var hasDataset: Bool {
        switch self {
        case .cEchoRequest, .cEchoResponse, .cStoreResponse, .cCancelRequest: return false
        case .cStoreRequest, .cFindRequest, .cMoveRequest, .cGetRequest: return true
        case .cFindResponse(_, _, let identifierFollows, _): return identifierFollows
        case .cMoveResponse(_, _, let identifierFollows, _, _): return identifierFollows
        case .cGetResponse(_, _, let identifierFollows, _, _): return identifierFollows
        }
    }

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
            Self.appendElement(tag: 0x09000000, value: Self.uint16(status.rawValue), to: &content)
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
            Self.appendElement(tag: 0x09000000, value: Self.uint16(status.rawValue), to: &content)
        case .cFindRequest(let messageID, let sopClassUID):
            Self.appendElement(tag: 0x00020000, value: Self.ui(sopClassUID), to: &content)
            Self.appendElement(tag: 0x01000000, value: Self.uint16(0x0020), to: &content)
            Self.appendElement(tag: 0x01100000, value: Self.uint16(messageID), to: &content)
            Self.appendElement(tag: 0x07000000, value: Self.uint16(0), to: &content)
            Self.appendElement(tag: 0x08000000, value: Self.uint16(0), to: &content)
        case .cFindResponse(let messageID, let status, let identifierFollows, let errorComment):
            Self.appendElement(tag: 0x01000000, value: Self.uint16(0x8020), to: &content)
            Self.appendElement(tag: 0x01200000, value: Self.uint16(messageID), to: &content)
            Self.appendElement(tag: 0x08000000, value: Self.uint16(identifierFollows ? 0x0000 : 0x0101), to: &content)
            Self.appendElement(tag: 0x09000000, value: Self.uint16(status.rawValue), to: &content)
            if let errorComment { Self.appendElement(tag: 0x09020000, value: Self.lo(errorComment), to: &content) }
        case .cMoveRequest(let messageID, let sopClassUID, let destination):
            guard destination.utf8.count <= 16 else { throw DICOMDIMSEError.malformedCommandSet }
            Self.appendElement(tag: 0x00020000, value: Self.ui(sopClassUID), to: &content)
            Self.appendElement(tag: 0x01000000, value: Self.uint16(0x0021), to: &content)
            Self.appendElement(tag: 0x01100000, value: Self.uint16(messageID), to: &content)
            Self.appendElement(tag: 0x06000000, value: Self.ae(destination), to: &content)
            Self.appendElement(tag: 0x07000000, value: Self.uint16(0), to: &content)
            Self.appendElement(tag: 0x08000000, value: Self.uint16(0), to: &content)
        case .cMoveResponse(let messageID, let status, let identifierFollows, let subOperations, let errorComment):
            Self.appendElement(tag: 0x01000000, value: Self.uint16(0x8021), to: &content)
            Self.appendElement(tag: 0x01200000, value: Self.uint16(messageID), to: &content)
            Self.appendElement(tag: 0x08000000, value: Self.uint16(identifierFollows ? 0x0000 : 0x0101), to: &content)
            Self.appendElement(tag: 0x09000000, value: Self.uint16(status.rawValue), to: &content)
            if let subOperations { Self.appendSubOperationCounts(subOperations, to: &content) }
            if let errorComment { Self.appendElement(tag: 0x09020000, value: Self.lo(errorComment), to: &content) }
        case .cGetRequest(let messageID, let sopClassUID):
            Self.appendElement(tag: 0x00020000, value: Self.ui(sopClassUID), to: &content)
            Self.appendElement(tag: 0x01000000, value: Self.uint16(0x0010), to: &content)
            Self.appendElement(tag: 0x01100000, value: Self.uint16(messageID), to: &content)
            Self.appendElement(tag: 0x07000000, value: Self.uint16(0), to: &content)
            Self.appendElement(tag: 0x08000000, value: Self.uint16(0), to: &content)
        case .cGetResponse(let messageID, let status, let identifierFollows, let subOperations, let errorComment):
            Self.appendElement(tag: 0x01000000, value: Self.uint16(0x8010), to: &content)
            Self.appendElement(tag: 0x01200000, value: Self.uint16(messageID), to: &content)
            Self.appendElement(tag: 0x08000000, value: Self.uint16(identifierFollows ? 0x0000 : 0x0101), to: &content)
            Self.appendElement(tag: 0x09000000, value: Self.uint16(status.rawValue), to: &content)
            if let subOperations { Self.appendSubOperationCounts(subOperations, to: &content) }
            if let errorComment { Self.appendElement(tag: 0x09020000, value: Self.lo(errorComment), to: &content) }
        case .cCancelRequest(let messageID):
            Self.appendElement(tag: 0x01000000, value: Self.uint16(0x0FFF), to: &content)
            Self.appendElement(tag: 0x01200000, value: Self.uint16(messageID), to: &content)
            Self.appendElement(tag: 0x08000000, value: Self.uint16(0x0101), to: &content)
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
            return .cEchoResponse(messageIDBeingRespondedTo: messageID, status: DICOMDIMSEStatus(rawValue: status))
        case 0x0001:
            guard let messageID = values[0x01100000].flatMap(readUInt16),
                  values[0x08000000].flatMap(readUInt16) == 0,
                  let sopClassUID = values[0x00020000].flatMap(readUI),
                  let sopInstanceUID = values[0x10000000].flatMap(readUI) else { throw DICOMDIMSEError.malformedCommandSet }
            return .cStoreRequest(messageID: messageID, affectedSOPClassUID: sopClassUID, affectedSOPInstanceUID: sopInstanceUID)
        case 0x8001:
            guard values[0x08000000].flatMap(readUInt16) == 0x0101, let messageID = values[0x01200000].flatMap(readUInt16), let status = values[0x09000000].flatMap(readUInt16) else { throw DICOMDIMSEError.malformedCommandSet }
            return .cStoreResponse(messageIDBeingRespondedTo: messageID, status: DICOMDIMSEStatus(rawValue: status))
        case 0x0020:
            guard let messageID = values[0x01100000].flatMap(readUInt16), values[0x08000000].flatMap(readUInt16) == 0, let sopClassUID = values[0x00020000].flatMap(readUI) else { throw DICOMDIMSEError.malformedCommandSet }
            return .cFindRequest(messageID: messageID, affectedSOPClassUID: sopClassUID)
        case 0x8020:
            guard let messageID = values[0x01200000].flatMap(readUInt16), let status = values[0x09000000].flatMap(readUInt16) else { throw DICOMDIMSEError.malformedCommandSet }
            let identifierFollows = values[0x08000000].flatMap(readUInt16) != 0x0101
            return .cFindResponse(messageIDBeingRespondedTo: messageID, status: DICOMDIMSEStatus(rawValue: status), identifierFollows: identifierFollows, errorComment: values[0x09020000].flatMap(readLO))
        case 0x0021:
            guard let messageID = values[0x01100000].flatMap(readUInt16), values[0x08000000].flatMap(readUInt16) == 0, let sopClassUID = values[0x00020000].flatMap(readUI), let destination = values[0x06000000].flatMap(readAE) else { throw DICOMDIMSEError.malformedCommandSet }
            return .cMoveRequest(messageID: messageID, affectedSOPClassUID: sopClassUID, moveDestination: destination)
        case 0x8021:
            guard let messageID = values[0x01200000].flatMap(readUInt16), let status = values[0x09000000].flatMap(readUInt16) else { throw DICOMDIMSEError.malformedCommandSet }
            let identifierFollows = values[0x08000000].flatMap(readUInt16) != 0x0101
            return .cMoveResponse(messageIDBeingRespondedTo: messageID, status: DICOMDIMSEStatus(rawValue: status), identifierFollows: identifierFollows, subOperations: Self.readSubOperationCounts(values), errorComment: values[0x09020000].flatMap(readLO))
        case 0x0010:
            guard let messageID = values[0x01100000].flatMap(readUInt16), values[0x08000000].flatMap(readUInt16) == 0, let sopClassUID = values[0x00020000].flatMap(readUI) else { throw DICOMDIMSEError.malformedCommandSet }
            return .cGetRequest(messageID: messageID, affectedSOPClassUID: sopClassUID)
        case 0x8010:
            guard let messageID = values[0x01200000].flatMap(readUInt16), let status = values[0x09000000].flatMap(readUInt16) else { throw DICOMDIMSEError.malformedCommandSet }
            let identifierFollows = values[0x08000000].flatMap(readUInt16) != 0x0101
            return .cGetResponse(messageIDBeingRespondedTo: messageID, status: DICOMDIMSEStatus(rawValue: status), identifierFollows: identifierFollows, subOperations: Self.readSubOperationCounts(values), errorComment: values[0x09020000].flatMap(readLO))
        case 0x0FFF:
            guard values[0x08000000].flatMap(readUInt16) == 0x0101, let messageID = values[0x01200000].flatMap(readUInt16) else { throw DICOMDIMSEError.malformedCommandSet }
            return .cCancelRequest(messageIDBeingRespondedTo: messageID)
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
    private static func ae(_ value: String) -> Data { Data(value.utf8) + Data(repeating: 0x20, count: 16 - value.utf8.count) }
    private static func readAE(_ value: Data) -> String? { guard value.count == 16 else { return nil }; return String(data: value, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) }
    private static func lo(_ value: String) -> Data { var bytes = Data(value.utf8); if bytes.count % 2 != 0 { bytes.append(0x20) }; return bytes }
    private static func readLO(_ value: Data) -> String? { String(data: value, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) }

    private static func appendSubOperationCounts(_ counts: DICOMSubOperationCounts, to data: inout Data) {
        appendElement(tag: 0x10200000, value: uint16(counts.remaining), to: &data)
        appendElement(tag: 0x10210000, value: uint16(counts.completed), to: &data)
        appendElement(tag: 0x10220000, value: uint16(counts.failed), to: &data)
        appendElement(tag: 0x10230000, value: uint16(counts.warning), to: &data)
    }

    private static func readSubOperationCounts(_ values: [UInt32: Data]) -> DICOMSubOperationCounts? {
        let remaining = values[0x10200000].flatMap(readUInt16)
        let completed = values[0x10210000].flatMap(readUInt16)
        let failed = values[0x10220000].flatMap(readUInt16)
        let warning = values[0x10230000].flatMap(readUInt16)
        guard remaining != nil || completed != nil || failed != nil || warning != nil else { return nil }
        return DICOMSubOperationCounts(remaining: remaining ?? 0, completed: completed ?? 0, failed: failed ?? 0, warning: warning ?? 0)
    }
}
