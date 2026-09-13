import Foundation

/// Performed Procedure Step Status `(0040,0252)` — the three states an MPPS
/// instance moves through (PS3.4 F.7.2.1).
public enum DICOMPerformedProcedureStepStatus: String, Sendable, Equatable {
    case inProgress = "IN PROGRESS"
    case completed = "COMPLETED"
    case discontinued = "DISCONTINUED"
}

extension DICOMAssociation {
    /// Sends N-CREATE to start a Modality Performed Procedure Step, setting
    /// Performed Procedure Step Status `(0040,0252)` to `IN PROGRESS` in
    /// `attributes` — replacing any value it already carries, since N-CREATE
    /// for MPPS always starts a step `IN PROGRESS` (PS3.4 F.7.2.1.1).
    ///
    /// Assembling the rest of the MPPS attribute set (its Type 1/2 attributes
    /// — Performed Procedure Step ID, Performed Station AE Title, Scheduled
    /// Step Attributes Sequence, and so on, per PS3.3 C.4.14) is the caller's
    /// responsibility. That set is long and modality-specific; guessing at it
    /// here would produce data sets that look conformant without actually
    /// being so. Use ``DICOMModuleValidator`` to check `attributes` against
    /// the module definitions that apply before sending it.
    public func createPerformedProcedureStep(messageID: UInt16, contextID: UInt8, sopInstanceUID: String?, attributes: DICOMDataset, transferSyntax: TransferSyntax) async throws -> DICOMNServiceResult {
        let dataset = DICOMDataset(elements: Array(attributes) + [
            DICOMElement(tag: DICOMTag(group: 0x0040, element: 0x0252), vr: .CS, value: Data(DICOMPerformedProcedureStepStatus.inProgress.rawValue.utf8))
        ])
        let encoded = try DICOMWriter.encodeDataset(dataset, transferSyntax: transferSyntax)
        return try await nCreate(messageID: messageID, contextID: contextID, sopClassUID: DICOMSOPClass.modalityPerformedProcedureStep, sopInstanceUID: sopInstanceUID, attributes: encoded)
    }

    /// Sends N-SET to move a Modality Performed Procedure Step to a final
    /// state, setting Performed Procedure Step Status `(0040,0252)` to
    /// `status` in `attributes` — replacing any value it already carries.
    /// Throws ``DICOMAssociationError/invalidProcedureStepTransition`` when
    /// `status` is `.inProgress`, since N-SET may only move a step to
    /// `.completed` or `.discontinued` (PS3.4 F.7.2.1.3) — a step becomes
    /// `IN PROGRESS` exactly once, via N-CREATE.
    ///
    /// As with ``createPerformedProcedureStep(messageID:contextID:sopInstanceUID:attributes:transferSyntax:)``,
    /// assembling whatever attributes the transition itself requires (for
    /// example Performed Series Sequence on completion) is the caller's
    /// responsibility; use ``DICOMModuleValidator`` to check them.
    public func updatePerformedProcedureStep(messageID: UInt16, contextID: UInt8, sopInstanceUID: String, status: DICOMPerformedProcedureStepStatus, attributes: DICOMDataset, transferSyntax: TransferSyntax) async throws -> DICOMNServiceResult {
        guard status != .inProgress else { throw DICOMAssociationError.invalidProcedureStepTransition }
        let dataset = DICOMDataset(elements: Array(attributes) + [
            DICOMElement(tag: DICOMTag(group: 0x0040, element: 0x0252), vr: .CS, value: Data(status.rawValue.utf8))
        ])
        let modifications = try DICOMWriter.encodeDataset(dataset, transferSyntax: transferSyntax)
        return try await nSet(messageID: messageID, contextID: contextID, sopClassUID: DICOMSOPClass.modalityPerformedProcedureStep, sopInstanceUID: sopInstanceUID, modifications: modifications)
    }
}
