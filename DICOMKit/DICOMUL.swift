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

/// User identity credentials included in DICOM User Identity Negotiation.
public enum DICOMUserIdentity: Sendable, Equatable {
    case username(String)
    case usernameAndPassword(username: String, password: String)

    fileprivate var encoded: Data? {
        switch self {
        case .username(let username): return encode(type: 1, primary: Data(username.utf8), secondary: Data())
        case .usernameAndPassword(let username, let password): return encode(type: 2, primary: Data(username.utf8), secondary: Data(password.utf8))
        }
    }

    private func encode(type: UInt8, primary: Data, secondary: Data) -> Data? {
        guard primary.count <= Int(UInt16.max), secondary.count <= Int(UInt16.max) else { return nil }
        var data = Data([type, 0, UInt8(primary.count >> 8), UInt8(primary.count & 0xFF)])
        data.append(primary); data.append(UInt8(secondary.count >> 8)); data.append(UInt8(secondary.count & 0xFF)); data.append(secondary)
        return data
    }

    fileprivate static func decode(_ data: Data) throws -> DICOMUserIdentity {
        guard data.count >= 6 else { throw DICOMULError.malformedPDU }
        let primaryLength = Int(UInt16(data[2]) << 8 | UInt16(data[3]))
        guard data.count >= 6 + primaryLength else { throw DICOMULError.malformedPDU }
        let primary = Data(data[4..<(4 + primaryLength)])
        let secondaryStart = 4 + primaryLength
        let secondaryLength = Int(UInt16(data[secondaryStart]) << 8 | UInt16(data[secondaryStart + 1]))
        guard data.count == secondaryStart + 2 + secondaryLength, let username = String(data: primary, encoding: .utf8) else { throw DICOMULError.malformedPDU }
        switch data[0] {
        case 1: guard secondaryLength == 0 else { throw DICOMULError.malformedPDU }; return .username(username)
        case 2: guard let password = String(data: data[(secondaryStart + 2)..<data.count], encoding: .utf8) else { throw DICOMULError.malformedPDU }; return .usernameAndPassword(username: username, password: password)
        default: throw DICOMULError.malformedPDU
        }
    }
}

/// Implementation Class UID and Version Name carried in User Information (PS3.7 D.3.3.2).
public struct DICOMImplementationIdentification: Sendable, Equatable {
    public let classUID: String
    public let versionName: String?

    public init(classUID: String, versionName: String? = nil) throws {
        if let versionName, versionName.utf8.count > 16 { throw DICOMULError.malformedPDU }
        self.classUID = classUID
        self.versionName = versionName
    }

    /// DICOMKit's Implementation Class UID and Version Name.
    ///
    /// This UID is derived from a UUID under the ISO/IEC 9834-8 UUID arc (2.25), so it squats
    /// on no registered OID arc. Applications shipping their own product SHOULD supply their
    /// own registered Implementation Class UID.
    public static let dicomKit = try! DICOMImplementationIdentification(classUID: "2.25.336190857897896940232253506776282144275", versionName: "DICOMKIT_0_5")
}

/// A proposed or negotiated SCP/SCU role for a SOP Class (PS3.7 D.3.3.4).
public struct DICOMRoleSelection: Sendable, Equatable {
    public let sopClassUID: String
    public let supportsSCURole: Bool
    public let supportsSCPRole: Bool

    public init(sopClassUID: String, supportsSCURole: Bool, supportsSCPRole: Bool) {
        self.sopClassUID = sopClassUID
        self.supportsSCURole = supportsSCURole
        self.supportsSCPRole = supportsSCPRole
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
    public let userIdentity: DICOMUserIdentity?
    public let implementation: DICOMImplementationIdentification
    public let roleSelections: [DICOMRoleSelection]

    public init(
        calledAETitle: String,
        callingAETitle: String,
        applicationContextUID: String = DICOMAssociationRequest.dicomApplicationContextUID,
        presentationContexts: [DICOMPresentationContext],
        maximumPDULength: UInt32 = 16_384,
        userIdentity: DICOMUserIdentity? = nil,
        implementation: DICOMImplementationIdentification = .dicomKit,
        roleSelections: [DICOMRoleSelection] = []
    ) {
        self.calledAETitle = calledAETitle
        self.callingAETitle = callingAETitle
        self.applicationContextUID = applicationContextUID
        self.presentationContexts = presentationContexts
        self.maximumPDULength = maximumPDULength
        self.userIdentity = userIdentity
        self.implementation = implementation
        self.roleSelections = roleSelections
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
    public let implementation: DICOMImplementationIdentification
    public let roleSelections: [DICOMRoleSelection]
    public init(calledAETitle: String, callingAETitle: String, applicationContextUID: String = DICOMAssociationRequest.dicomApplicationContextUID, presentationContexts: [DICOMPresentationContextAcceptance], maximumPDULength: UInt32 = 16_384, implementation: DICOMImplementationIdentification = .dicomKit, roleSelections: [DICOMRoleSelection] = []) {
        self.calledAETitle = calledAETitle; self.callingAETitle = callingAETitle; self.applicationContextUID = applicationContextUID; self.presentationContexts = presentationContexts; self.maximumPDULength = maximumPDULength; self.implementation = implementation; self.roleSelections = roleSelections
    }
}

/// The reason supplied by a peer that refuses an association request.
public struct DICOMAssociationRejection: Sendable, Equatable {
    public enum Result: UInt8, Sendable, Equatable { case permanent = 1, transient = 2 }
    public enum Source: UInt8, Sendable, Equatable { case serviceUser = 1, serviceProviderACSE = 2, serviceProviderPresentation = 3 }
    public let result: Result
    public let source: Source
    public let reason: UInt8
    public init(result: Result, source: Source, reason: UInt8) { self.result = result; self.source = source; self.reason = reason }
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
    case associationRejection(DICOMAssociationRejection)
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
        case .associationRejection(let rejection):
            type = 0x03
            body = Data([0, rejection.result.rawValue, rejection.source.rawValue, rejection.reason])
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
        case 0x03:
            guard body.count == 4, body[body.startIndex] == 0,
                  let result = DICOMAssociationRejection.Result(rawValue: body[body.startIndex + 1]),
                  let source = DICOMAssociationRejection.Source(rawValue: body[body.startIndex + 2]) else { throw DICOMULError.malformedPDU }
            return .associationRejection(DICOMAssociationRejection(result: result, source: source, reason: body[body.startIndex + 3]))
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
        appendImplementation(request.implementation, to: &userInformation)
        for role in request.roleSelections { appendItem(type: 0x54, value: encodeRoleSelection(role), to: &userInformation) }
        if let identity = request.userIdentity?.encoded { appendItem(type: 0x58, value: identity, to: &userInformation) }
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
        var userIdentity: DICOMUserIdentity?
        var implementationClassUID: String?
        var implementationVersionName: String?
        var roleSelections: [DICOMRoleSelection] = []
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
                    if subitem.type == 0x52 { implementationClassUID = try decodeTrimmed(subitem.value, padding: 0x00) }
                    if subitem.type == 0x55 { implementationVersionName = try decodeTrimmed(subitem.value, padding: 0x20) }
                    if subitem.type == 0x54 { roleSelections.append(try decodeRoleSelection(subitem.value)) }
                    if subitem.type == 0x58 { userIdentity = try DICOMUserIdentity.decode(subitem.value) }
                }
            default: continue
            }
        }
        guard let applicationContext, !contexts.isEmpty else { throw DICOMULError.malformedPDU }
        let implementation = try DICOMImplementationIdentification(classUID: implementationClassUID ?? DICOMImplementationIdentification.dicomKit.classUID, versionName: implementationVersionName)
        return DICOMAssociationRequest(calledAETitle: called, callingAETitle: calling, applicationContextUID: applicationContext, presentationContexts: contexts, maximumPDULength: maximumLength, userIdentity: userIdentity, implementation: implementation, roleSelections: roleSelections)
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
        var user = Data(); var maximum = Data(); appendUInt32(acceptance.maximumPDULength, to: &maximum); appendItem(type: 0x51, value: maximum, to: &user)
        appendImplementation(acceptance.implementation, to: &user)
        for role in acceptance.roleSelections { appendItem(type: 0x54, value: encodeRoleSelection(role), to: &user) }
        appendItem(type: 0x50, value: user, to: &body)
        return body
    }

    private static func decodeAssociationAcceptance(_ data: Data) throws -> DICOMAssociationAcceptance {
        guard data.count >= 68, data[0] == 0, data[1] == 1 else { throw DICOMULError.malformedPDU }
        let called = try decodeAETitle(data.subdata(in: 4..<20)); let calling = try decodeAETitle(data.subdata(in: 20..<36))
        var offset = 68; var applicationContext: String?; var contexts: [DICOMPresentationContextAcceptance] = []; var maximum: UInt32 = 16_384
        var implementationClassUID: String?; var implementationVersionName: String?
        var roleSelections: [DICOMRoleSelection] = []
        while offset < data.count {
            let item = try readItem(data, offset: &offset)
            if item.type == 0x10 { applicationContext = String(data: item.value, encoding: .ascii) }
            if item.type == 0x21 { contexts.append(try decodeAcceptedPresentationContext(item.value)) }
            if item.type == 0x50 {
                var userOffset = 0
                while userOffset < item.value.count {
                    let subitem = try readItem(item.value, offset: &userOffset)
                    if subitem.type == 0x51, subitem.value.count == 4 { maximum = readUInt32(subitem.value, at: 0) }
                    if subitem.type == 0x52 { implementationClassUID = try decodeTrimmed(subitem.value, padding: 0x00) }
                    if subitem.type == 0x55 { implementationVersionName = try decodeTrimmed(subitem.value, padding: 0x20) }
                    if subitem.type == 0x54 { roleSelections.append(try decodeRoleSelection(subitem.value)) }
                }
            }
        }
        guard let applicationContext, !contexts.isEmpty else { throw DICOMULError.malformedPDU }
        let implementation = try DICOMImplementationIdentification(classUID: implementationClassUID ?? DICOMImplementationIdentification.dicomKit.classUID, versionName: implementationVersionName)
        return DICOMAssociationAcceptance(calledAETitle: called, callingAETitle: calling, applicationContextUID: applicationContext, presentationContexts: contexts, maximumPDULength: maximum, implementation: implementation, roleSelections: roleSelections)
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

    private static func appendImplementation(_ implementation: DICOMImplementationIdentification, to userInformation: inout Data) {
        var classUID = Data(implementation.classUID.utf8)
        if classUID.count % 2 != 0 { classUID.append(0x00) }
        appendItem(type: 0x52, value: classUID, to: &userInformation)
        if let versionName = implementation.versionName {
            var name = Data(versionName.utf8)
            if name.count % 2 != 0 { name.append(0x20) }
            appendItem(type: 0x55, value: name, to: &userInformation)
        }
    }

    private static func decodeTrimmed(_ data: Data, padding: UInt8) throws -> String {
        guard let value = String(data: data, encoding: .utf8) else { throw DICOMULError.malformedPDU }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: String(UnicodeScalar(padding))))
    }

    private static func encodeRoleSelection(_ role: DICOMRoleSelection) -> Data {
        let uid = Data(role.sopClassUID.utf8)
        var data = Data(); appendUInt16(UInt16(uid.count), to: &data); data.append(uid)
        data.append(role.supportsSCURole ? 1 : 0); data.append(role.supportsSCPRole ? 1 : 0)
        return data
    }

    private static func decodeRoleSelection(_ data: Data) throws -> DICOMRoleSelection {
        guard data.count >= 2 else { throw DICOMULError.malformedPDU }
        let uidLength = Int(UInt16(data[data.startIndex]) << 8 | UInt16(data[data.startIndex + 1]))
        let uidStart = data.startIndex + 2
        guard data.count == uidLength + 4, let uid = String(data: data.subdata(in: uidStart..<(uidStart + uidLength)), encoding: .ascii) else { throw DICOMULError.malformedPDU }
        let scu = data[uidStart + uidLength]; let scp = data[uidStart + uidLength + 1]
        return DICOMRoleSelection(sopClassUID: uid, supportsSCURole: scu != 0, supportsSCPRole: scp != 0)
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
