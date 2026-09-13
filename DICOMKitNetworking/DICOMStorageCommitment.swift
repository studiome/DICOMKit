import DICOMKit
import Foundation

// DICOMSOPReference lives in DICOMSOPClass.swift (core): DICOMStructuredReport
// (core) references it for IMAGE/WAVEFORM/COMPOSITE content items, and core
// cannot depend on this file once it moves to DICOMKitNetworking.

/// Errors raised while building or parsing Storage Commitment data sets.
public enum DICOMStorageCommitmentError: Error, Sendable, Equatable {
    /// Event Information is missing Transaction UID `(0008,1195)`.
    case missingTransactionUID
}

/// A Storage Commitment Push Model request (PS3.4 Annex J): the Transaction
/// UID the SCU assigns to correlate the eventual N-EVENT-REPORT, and the SOP
/// Instances committal is being requested for.
public struct DICOMStorageCommitmentRequest: Sendable, Equatable {
    public let transactionUID: String
    public let references: [DICOMSOPReference]
    public init(transactionUID: String, references: [DICOMSOPReference]) {
        self.transactionUID = transactionUID
        self.references = references
    }

    /// Builds the N-ACTION Action Information data set: Transaction UID
    /// `(0008,1195)` and Referenced SOP Sequence `(0008,1199)`, whose items
    /// each carry Referenced SOP Class UID `(0008,1150)` and Referenced SOP
    /// Instance UID `(0008,1155)`.
    public func actionInformation(transferSyntax: TransferSyntax) throws -> Data {
        let items = references.map { reference in
            DICOMDataset(elements: [
                DICOMElement(tag: .referencedSOPClassUID, vr: .UI, value: Data(reference.sopClassUID.utf8)),
                DICOMElement(tag: .referencedSOPInstanceUID, vr: .UI, value: Data(reference.sopInstanceUID.utf8))
            ])
        }
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0008, element: 0x1195), vr: .UI, value: Data(transactionUID.utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0008, element: 0x1199), vr: .SQ, value: Data(), sequenceItems: items)
        ])
        return try DICOMWriter.encodeDataset(dataset, transferSyntax: transferSyntax)
    }
}

/// One instance the peer could not commit, from the Failed SOP Sequence
/// `(0008,1198)` of an N-EVENT-REPORT Event Information data set.
public struct DICOMStorageCommitmentFailure: Sendable, Equatable {
    public let reference: DICOMSOPReference
    /// Failure Reason `(0008,1197)`.
    public let failureReason: UInt16
    public init(reference: DICOMSOPReference, failureReason: UInt16) {
        self.reference = reference
        self.failureReason = failureReason
    }
}

/// The outcome of a Storage Commitment request.
///
/// This does **not** come back in the N-ACTION response — see
/// ``DICOMAssociation/requestStorageCommitment(messageID:contextID:_:)`` for
/// where and how the SCP actually reports it.
public struct DICOMStorageCommitmentResult: Sendable, Equatable {
    public let transactionUID: String
    public let successful: [DICOMSOPReference]
    public let failed: [DICOMStorageCommitmentFailure]

    /// Parses an N-EVENT-REPORT Event Information data set (PS3.4 Annex J):
    /// Transaction UID `(0008,1195)`, Referenced SOP Sequence `(0008,1199)`
    /// for the committed instances, and Failed SOP Sequence `(0008,1198)`
    /// for the rest, each of whose items also carries Failure Reason
    /// `(0008,1197)`.
    public init(eventInformation: Data, transferSyntax: TransferSyntax) throws {
        let dataset = try DICOMFile(datasetData: eventInformation, transferSyntax: transferSyntax).dataset
        guard let transactionUID = dataset[DICOMTag(group: 0x0008, element: 0x1195)]?.stringValue else {
            throw DICOMStorageCommitmentError.missingTransactionUID
        }
        self.transactionUID = transactionUID
        self.successful = (dataset[DICOMTag(group: 0x0008, element: 0x1199)]?.sequenceItems ?? []).compactMap { item in
            guard let sopClassUID = item[.referencedSOPClassUID]?.stringValue, let sopInstanceUID = item[.referencedSOPInstanceUID]?.stringValue else { return nil }
            return DICOMSOPReference(sopClassUID: sopClassUID, sopInstanceUID: sopInstanceUID)
        }
        self.failed = (dataset[DICOMTag(group: 0x0008, element: 0x1198)]?.sequenceItems ?? []).compactMap { item in
            guard let sopClassUID = item[.referencedSOPClassUID]?.stringValue,
                  let sopInstanceUID = item[.referencedSOPInstanceUID]?.stringValue,
                  let failureReason = item[DICOMTag(group: 0x0008, element: 0x1197)]?.uint16Value else { return nil }
            return DICOMStorageCommitmentFailure(reference: DICOMSOPReference(sopClassUID: sopClassUID, sopInstanceUID: sopInstanceUID), failureReason: failureReason)
        }
    }
}

