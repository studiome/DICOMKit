import Foundation

/// Errors raised while encoding or decoding DICOM Upper Layer (PS3.8) PDUs.
public enum DICOMULError: Error, Sendable, Equatable {
    case malformedPDU
    case unsupportedPDU(UInt8)
    case invalidAETitle
    case invalidPresentationContext
    case pduTooLarge
}

/// A presentation context proposed during DICOM association negotiation.
public struct DICOMPresentationContext: Sendable, Equatable {
    /// The odd, non-zero presentation-context identifier.
    public let id: UInt8
    public let abstractSyntaxUID: String
    public let transferSyntaxUIDs: [String]

    public init(id: UInt8, abstractSyntaxUID: String, transferSyntaxUIDs: [String]) {
        self.id = id
        self.abstractSyntaxUID = abstractSyntaxUID
        self.transferSyntaxUIDs = transferSyntaxUIDs
    }
}

/// The information carried by an A-ASSOCIATE-RQ PDU.
public struct DICOMAssociationRequest: Sendable, Equatable {
    public static let dicomApplicationContextUID = "1.2.840.10008.3.1.1.1"

    public let calledAETitle: String
    public let callingAETitle: String
    public let applicationContextUID: String
    public let presentationContexts: [DICOMPresentationContext]
    public let maximumPDULength: UInt32

    public init(
        calledAETitle: String,
        callingAETitle: String,
        applicationContextUID: String = DICOMAssociationRequest.dicomApplicationContextUID,
        presentationContexts: [DICOMPresentationContext],
        maximumPDULength: UInt32 = 16_384
    ) {
        self.calledAETitle = calledAETitle
        self.callingAETitle = callingAETitle
        self.applicationContextUID = applicationContextUID
        self.presentationContexts = presentationContexts
        self.maximumPDULength = maximumPDULength
    }
}

/// A negotiated presentation context returned in an A-ASSOCIATE-AC PDU.
public struct DICOMPresentationContextAcceptance: Sendable, Equatable {
    public enum Result: UInt8, Sendable, Equatable { case acceptance = 0, abstractSyntaxNotSupported = 3, transferSyntaxesNotSupported = 4 }
    public let id: UInt8
    public let result: Result
    public let transferSyntaxUID: String
    public init(id: UInt8, result: Result, transferSyntaxUID: String) { self.id = id; self.result = result; self.transferSyntaxUID = transferSyntaxUID }
}

/// The information carried by an A-ASSOCIATE-AC PDU.
public struct DICOMAssociationAcceptance: Sendable, Equatable {
    public let calledAETitle: String
    public let callingAETitle: String
    public let applicationContextUID: String
    public let presentationContexts: [DICOMPresentationContextAcceptance]
    public let maximumPDULength: UInt32
    public init(calledAETitle: String, callingAETitle: String, applicationContextUID: String = DICOMAssociationRequest.dicomApplicationContextUID, presentationContexts: [DICOMPresentationContextAcceptance], maximumPDULength: UInt32 = 16_384) {
        self.calledAETitle = calledAETitle; self.callingAETitle = callingAETitle; self.applicationContextUID = applicationContextUID; self.presentationContexts = presentationContexts; self.maximumPDULength = maximumPDULength
    }
}

/// One PDV in a P-DATA-TF PDU.
public struct DICOMPDataValue: Sendable, Equatable {
    public let contextID: UInt8
    public let isCommand: Bool
    public let isLastFragment: Bool
    public let data: Data

    public init(contextID: UInt8, isCommand: Bool, isLastFragment: Bool, data: Data) {
        self.contextID = contextID
        self.isCommand = isCommand
        self.isLastFragment = isLastFragment
        self.data = data
    }
}

/// DICOM Upper Layer protocol data units used to establish, carry, and close an association.
///
/// This type intentionally models the wire protocol independently from a socket. Applications
/// can use it with their own TLS or Network.framework transport while tests can exercise fully
/// deterministic byte sequences.
public enum DICOMULPDU: Sendable, Equatable {
    case associationRequest(DICOMAssociationRequest)
    case associationAcceptance(DICOMAssociationAcceptance)
    case pData([DICOMPDataValue])
    case releaseRequest
    case releaseResponse
    case abort(source: UInt8, reason: UInt8)

    /// Encodes a complete PDU, including its six-byte Upper Layer header.
    public func encoded() throws -> Data {
        let type: UInt8
        let body: Data
        switch self {
        case .associationRequest(let request):
            type = 0x01
            body = try Self.encodeAssociationRequest(request)
        case .associationAcceptance(let acceptance):
            type = 0x02
            body = try Self.encodeAssociationAcceptance(acceptance)
        case .pData(let values):
            type = 0x04
            body = try Self.encodePData(values)
        case .releaseRequest:
            type = 0x05; body = Data(repeating: 0, count: 4)
        case .releaseResponse:
            type = 0x06; body = Data(repeating: 0, count: 4)
        case .abort(let source, let reason):
            type = 0x07; body = Data([0, 0, source, reason])
        }
        guard body.count <= Int(UInt32.max) else { throw DICOMULError.pduTooLarge }
        var result = Data([type, 0])
        Self.appendUInt32(UInt32(body.count), to: &result)
        result.append(body)
        return result
    }

    /// Decodes exactly one complete PDU.
    public static func decode(_ data: Data) throws -> DICOMULPDU {
        guard data.count >= 6, data[1] == 0 else { throw DICOMULError.malformedPDU }
        let length = Int(readUInt32(data, at: 2))
        guard data.count == length + 6 else { throw DICOMULError.malformedPDU }
        let body = data.dropFirst(6)
        switch data[0] {
        case 0x01: return .associationRequest(try decodeAssociationRequest(Data(body)))
        case 0x02: return .associationAcceptance(try decodeAssociationAcceptance(Data(body)))
        case 0x04: return .pData(try decodePData(Data(body)))
        case 0x05:
            guard body.count == 4 else { throw DICOMULError.malformedPDU }; return .releaseRequest
        case 0x06:
            guard body.count == 4 else { throw DICOMULError.malformedPDU }; return .releaseResponse
        case 0x07:
            guard body.count == 4 else { throw DICOMULError.malformedPDU }; return .abort(source: body[body.startIndex + 2], reason: body[body.startIndex + 3])
        default: throw DICOMULError.unsupportedPDU(data[0])
        }
    }

    private static func encodeAssociationRequest(_ request: DICOMAssociationRequest) throws -> Data {
        var body = Data([0, 1, 0, 0])
        body.append(try aeTitle(request.calledAETitle))
        body.append(try aeTitle(request.callingAETitle))
        body.append(Data(repeating: 0, count: 32))
        appendItem(type: 0x10, value: Data(request.applicationContextUID.utf8), to: &body)
        for context in request.presentationContexts {
            guard context.id != 0, context.id % 2 == 1, !context.abstractSyntaxUID.isEmpty, !context.transferSyntaxUIDs.isEmpty else {
                throw DICOMULError.invalidPresentationContext
            }
            var value = Data([context.id, 0, 0, 0])
            appendItem(type: 0x30, value: Data(context.abstractSyntaxUID.utf8), to: &value)
            for syntax in context.transferSyntaxUIDs {
                appendItem(type: 0x40, value: Data(syntax.utf8), to: &value)
            }
            appendItem(type: 0x20, value: value, to: &body)
        }
        var userInformation = Data()
        var maximumLength = Data()
        appendUInt32(request.maximumPDULength, to: &maximumLength)
        appendItem(type: 0x51, value: maximumLength, to: &userInformation)
        appendItem(type: 0x50, value: userInformation, to: &body)
        return body
    }

    private static func decodeAssociationRequest(_ data: Data) throws -> DICOMAssociationRequest {
        guard data.count >= 68, data[0] == 0, data[1] == 1 else { throw DICOMULError.malformedPDU }
        let called = try decodeAETitle(data.subdata(in: 4..<20))
        let calling = try decodeAETitle(data.subdata(in: 20..<36))
        var offset = 68
        var applicationContext: String?
        var contexts: [DICOMPresentationContext] = []
        var maximumLength: UInt32 = 16_384
        while offset < data.count {
            let item = try readItem(data, offset: &offset)
            switch item.type {
            case 0x10:
                applicationContext = String(data: item.value, encoding: .ascii)
            case 0x20:
                contexts.append(try decodePresentationContext(item.value))
            case 0x50:
                var userOffset = 0
                while userOffset < item.value.count {
                    let subitem = try readItem(item.value, offset: &userOffset)
                    if subitem.type == 0x51, subitem.value.count == 4 { maximumLength = readUInt32(subitem.value, at: 0) }
                }
            default: continue
            }
        }
        guard let applicationContext, !contexts.isEmpty else { throw DICOMULError.malformedPDU }
        return DICOMAssociationRequest(calledAETitle: called, callingAETitle: calling, applicationContextUID: applicationContext, presentationContexts: contexts, maximumPDULength: maximumLength)
    }

    private static func encodeAssociationAcceptance(_ acceptance: DICOMAssociationAcceptance) throws -> Data {
        var body = Data([0, 1, 0, 0])
        body.append(try aeTitle(acceptance.calledAETitle)); body.append(try aeTitle(acceptance.callingAETitle)); body.append(Data(repeating: 0, count: 32))
        appendItem(type: 0x10, value: Data(acceptance.applicationContextUID.utf8), to: &body)
        for context in acceptance.presentationContexts {
            guard context.id != 0, context.id % 2 == 1 else { throw DICOMULError.invalidPresentationContext }
            var value = Data([context.id, 0, context.result.rawValue, 0])
            appendItem(type: 0x40, value: Data(context.transferSyntaxUID.utf8), to: &value)
            appendItem(type: 0x21, value: value, to: &body)
        }
        var user = Data(); var maximum = Data(); appendUInt32(acceptance.maximumPDULength, to: &maximum); appendItem(type: 0x51, value: maximum, to: &user); appendItem(type: 0x50, value: user, to: &body)
        return body
    }

    private static func decodeAssociationAcceptance(_ data: Data) throws -> DICOMAssociationAcceptance {
        guard data.count >= 68, data[0] == 0, data[1] == 1 else { throw DICOMULError.malformedPDU }
        let called = try decodeAETitle(data.subdata(in: 4..<20)); let calling = try decodeAETitle(data.subdata(in: 20..<36))
        var offset = 68; var applicationContext: String?; var contexts: [DICOMPresentationContextAcceptance] = []; var maximum: UInt32 = 16_384
        while offset < data.count {
            let item = try readItem(data, offset: &offset)
            if item.type == 0x10 { applicationContext = String(data: item.value, encoding: .ascii) }
            if item.type == 0x21 { contexts.append(try decodeAcceptedPresentationContext(item.value)) }
            if item.type == 0x50 { var userOffset = 0; while userOffset < item.value.count { let subitem = try readItem(item.value, offset: &userOffset); if subitem.type == 0x51, subitem.value.count == 4 { maximum = readUInt32(subitem.value, at: 0) } } }
        }
        guard let applicationContext, !contexts.isEmpty else { throw DICOMULError.malformedPDU }
        return DICOMAssociationAcceptance(calledAETitle: called, callingAETitle: calling, applicationContextUID: applicationContext, presentationContexts: contexts, maximumPDULength: maximum)
    }

    private static func decodeAcceptedPresentationContext(_ data: Data) throws -> DICOMPresentationContextAcceptance {
        guard data.count >= 4, let result = DICOMPresentationContextAcceptance.Result(rawValue: data[2]) else { throw DICOMULError.invalidPresentationContext }
        var offset = 4; let item = try readItem(data, offset: &offset)
        guard offset == data.count, item.type == 0x40, let syntax = String(data: item.value, encoding: .ascii) else { throw DICOMULError.invalidPresentationContext }
        return DICOMPresentationContextAcceptance(id: data[0], result: result, transferSyntaxUID: syntax)
    }

    private static func decodePresentationContext(_ data: Data) throws -> DICOMPresentationContext {
        guard data.count >= 4 else { throw DICOMULError.malformedPDU }
        var offset = 4
        var abstract: String?
        var transferSyntaxes: [String] = []
        while offset < data.count {
            let item = try readItem(data, offset: &offset)
            if item.type == 0x30 { abstract = String(data: item.value, encoding: .ascii) }
            if item.type == 0x40, let uid = String(data: item.value, encoding: .ascii) { transferSyntaxes.append(uid) }
        }
        guard let abstract, !transferSyntaxes.isEmpty else { throw DICOMULError.invalidPresentationContext }
        return DICOMPresentationContext(id: data[0], abstractSyntaxUID: abstract, transferSyntaxUIDs: transferSyntaxes)
    }

    private static func encodePData(_ values: [DICOMPDataValue]) throws -> Data {
        var result = Data()
        for value in values {
            guard value.contextID != 0, value.data.count <= Int(UInt32.max) - 2 else { throw DICOMULError.malformedPDU }
            appendUInt32(UInt32(value.data.count + 2), to: &result)
            result.append(value.contextID)
            result.append((value.isLastFragment ? 0x02 : 0) | (value.isCommand ? 0x01 : 0))
            result.append(value.data)
        }
        return result
    }

    private static func decodePData(_ data: Data) throws -> [DICOMPDataValue] {
        var offset = 0
        var values: [DICOMPDataValue] = []
        while offset < data.count {
            guard data.count - offset >= 4 else { throw DICOMULError.malformedPDU }
            let length = Int(readUInt32(data, at: offset)); offset += 4
            guard length >= 2, length <= data.count - offset else { throw DICOMULError.malformedPDU }
            let contextID = data[offset]
            let control = data[offset + 1]
            guard contextID != 0, control & 0xFC == 0 else { throw DICOMULError.malformedPDU }
            let payload = data.subdata(in: (offset + 2)..<(offset + length))
            values.append(DICOMPDataValue(contextID: contextID, isCommand: control & 1 != 0, isLastFragment: control & 2 != 0, data: payload))
            offset += length
        }
        return values
    }

    private static func aeTitle(_ value: String) throws -> Data {
        guard value.utf8.count <= 16, value.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value <= 0x7E }) else { throw DICOMULError.invalidAETitle }
        return Data(value.utf8) + Data(repeating: 0x20, count: 16 - value.utf8.count)
    }

    private static func decodeAETitle(_ value: Data) throws -> String {
        guard let title = String(data: value, encoding: .ascii) else { throw DICOMULError.invalidAETitle }
        return title.trimmingCharacters(in: .whitespaces)
    }

    private static func appendItem(type: UInt8, value: Data, to data: inout Data) {
        data.append(type); data.append(0); appendUInt16(UInt16(value.count), to: &data); data.append(value)
    }

    private static func readItem(_ data: Data, offset: inout Int) throws -> (type: UInt8, value: Data) {
        guard data.count - offset >= 4 else { throw DICOMULError.malformedPDU }
        let type = data[offset]
        let length = Int(UInt16(data[offset + 2]) << 8 | UInt16(data[offset + 3]))
        offset += 4
        guard length <= data.count - offset else { throw DICOMULError.malformedPDU }
        defer { offset += length }
        return (type, data.subdata(in: offset..<(offset + length)))
    }

    private static func appendUInt16(_ value: UInt16, to data: inout Data) { data.append(UInt8(value >> 8)); data.append(UInt8(value & 0xFF)) }
    private static func appendUInt32(_ value: UInt32, to data: inout Data) { data.append(UInt8(value >> 24)); data.append(UInt8((value >> 16) & 0xFF)); data.append(UInt8((value >> 8) & 0xFF)); data.append(UInt8(value & 0xFF)) }
    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 { UInt32(data[offset]) << 24 | UInt32(data[offset + 1]) << 16 | UInt32(data[offset + 2]) << 8 | UInt32(data[offset + 3]) }
}
