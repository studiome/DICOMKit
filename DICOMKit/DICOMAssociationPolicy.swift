import Foundation

/// Determines how a DICOM SCP responds to an inbound A-ASSOCIATE-RQ.
public struct DICOMAssociationPolicy: Sendable {
    /// Called AE titles this SCP accepts. `nil` accepts any called AE title.
    public let calledAETitles: Set<String>?
    public let supportedAbstractSyntaxes: Set<String>
    /// Supported transfer syntaxes, in descending preference order.
    public let supportedTransferSyntaxes: [String]
    /// SOP Classes for which this implementation will act as SCP when the peer
    /// proposes SCP/SCU role selection.
    public let scpRoleAbstractSyntaxes: Set<String>
    public let maximumPDULength: UInt32
    public let implementation: DICOMImplementationIdentification

    public init(
        calledAETitles: Set<String>? = nil,
        supportedAbstractSyntaxes: Set<String>,
        supportedTransferSyntaxes: [String],
        scpRoleAbstractSyntaxes: Set<String> = [],
        maximumPDULength: UInt32 = 16_384,
        implementation: DICOMImplementationIdentification = .dicomKit
    ) {
        self.calledAETitles = calledAETitles
        self.supportedAbstractSyntaxes = supportedAbstractSyntaxes
        self.supportedTransferSyntaxes = supportedTransferSyntaxes
        self.scpRoleAbstractSyntaxes = scpRoleAbstractSyntaxes
        self.maximumPDULength = maximumPDULength
        self.implementation = implementation
    }
}

/// The outcome of applying a ``DICOMAssociationPolicy`` to a proposed association.
public enum DICOMAssociationNegotiation: Sendable, Equatable {
    case accept(DICOMAssociationAcceptance)
    case reject(DICOMAssociationRejection)
}

extension DICOMAssociationPolicy {
    /// Negotiates `request` against this policy per PS3.8 Table 9-21. Pure function; no I/O.
    public func negotiate(_ request: DICOMAssociationRequest) -> DICOMAssociationNegotiation {
        guard request.applicationContextUID == DICOMAssociationRequest.dicomApplicationContextUID else {
            return .reject(DICOMAssociationRejection(result: .permanent, source: .serviceUser, reason: 2)) // application-context-name-not-supported
        }
        if let calledAETitles, !calledAETitles.contains(request.calledAETitle) {
            return .reject(DICOMAssociationRejection(result: .permanent, source: .serviceUser, reason: 7)) // called-AE-title-not-recognized
        }
        let presentationContexts = request.presentationContexts.map(negotiate)
        let roleSelections = request.roleSelections.compactMap { role -> DICOMRoleSelection? in
            guard supportedAbstractSyntaxes.contains(role.sopClassUID) else { return nil }
            return DICOMRoleSelection(sopClassUID: role.sopClassUID, supportsSCURole: role.supportsSCURole, supportsSCPRole: role.supportsSCPRole && scpRoleAbstractSyntaxes.contains(role.sopClassUID))
        }
        return .accept(DICOMAssociationAcceptance(
            calledAETitle: request.calledAETitle,
            callingAETitle: request.callingAETitle,
            presentationContexts: presentationContexts,
            maximumPDULength: maximumPDULength,
            implementation: implementation,
            roleSelections: roleSelections
        ))
    }

    /// Negotiates a single presentation context. The transfer syntax field of a
    /// non-accepted context is meaningless per PS3.8 but must still be present on
    /// the wire, so a rejected context echoes the proposal's first transfer syntax —
    /// or the empty string when the proposal listed none, which is harmless since
    /// PS3.8 says the field is not tested for a non-accepted context.
    private func negotiate(_ context: DICOMPresentationContext) -> DICOMPresentationContextAcceptance {
        guard supportedAbstractSyntaxes.contains(context.abstractSyntaxUID) else {
            return DICOMPresentationContextAcceptance(id: context.id, result: .abstractSyntaxNotSupported, transferSyntaxUID: context.transferSyntaxUIDs.first ?? "")
        }
        guard let transferSyntax = supportedTransferSyntaxes.first(where: context.transferSyntaxUIDs.contains) else {
            return DICOMPresentationContextAcceptance(id: context.id, result: .transferSyntaxesNotSupported, transferSyntaxUID: context.transferSyntaxUIDs.first ?? "")
        }
        return DICOMPresentationContextAcceptance(id: context.id, result: .acceptance, transferSyntaxUID: transferSyntax)
    }
}
