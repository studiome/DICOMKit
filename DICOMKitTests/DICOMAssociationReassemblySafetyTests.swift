import Foundation
import Testing
@testable import DICOMKit
import DICOMKitNetworking

/// A peer's command set or data set is reassembled from as many P-DATA-TF
/// PDVs as it sends, with no ceiling on the total — so a peer that never
/// sets the last-fragment bit could otherwise force unbounded growth of the
/// accumulator in `receiveRequest()`, `receiveCommand(contextID:)`, and
/// `receiveDataset(contextID:)`.
///
/// This only exercises the fix, not the "before" behavior: without the
/// ceiling, the flooding transport below drives a genuine infinite loop —
/// nothing rechecks it (there's no timeout, and unlike a real `NWConnection`
/// there's no `close()` callback to force it to unblock either) — so running
/// it against unpatched code would hang the test suite forever, not just
/// slowly. The vulnerability was confirmed by code inspection: the
/// accumulator had no size check anywhere in its loop, only a check for the
/// last-fragment bit a hostile peer controls.
struct DICOMAssociationReassemblySafetyTests {
    @Test func receiveRequestRejectsACommandSetThatNeverSetsTheLastFragmentBit() async throws {
        let transport = DICOMULFloodingTransport(contextID: 1, chunkSize: 64 * 1024, isCommand: true)
        let association = DICOMAssociation(transport: transport)
        let policy = DICOMAssociationPolicy(supportedAbstractSyntaxes: [DICOMSOPClass.verification], supportedTransferSyntaxes: ["1.2.840.10008.1.2"])
        let request = DICOMAssociationRequest(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, abstractSyntaxUID: DICOMSOPClass.verification, transferSyntaxUIDs: ["1.2.840.10008.1.2"])])
        _ = try await association.accept(request, policy: policy)

        await #expect(throws: DICOMAssociationError.reassembledMessageTooLarge) {
            _ = try await association.receiveRequest()
        }
    }

    @Test func receiveRequestRejectsADatasetThatNeverSetsTheLastFragmentBit() async throws {
        let transport = DICOMULCommandThenFloodingTransport(contextID: 1, chunkSize: 64 * 1024)
        let association = DICOMAssociation(transport: transport)
        let policy = DICOMAssociationPolicy(supportedAbstractSyntaxes: [DICOMSOPClass.ctImageStorage], supportedTransferSyntaxes: ["1.2.840.10008.1.2"])
        let request = DICOMAssociationRequest(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, abstractSyntaxUID: DICOMSOPClass.ctImageStorage, transferSyntaxUIDs: ["1.2.840.10008.1.2"])])
        _ = try await association.accept(request, policy: policy)

        await #expect(throws: DICOMAssociationError.reassembledMessageTooLarge) {
            _ = try await association.receiveRequest()
        }
    }
}

/// Endlessly returns same-context PDVs whose last-fragment bit is never set.
private actor DICOMULFloodingTransport: DICOMULTransport {
    private let contextID: UInt8
    private let chunkSize: Int
    private let isCommand: Bool

    init(contextID: UInt8, chunkSize: Int, isCommand: Bool) {
        self.contextID = contextID
        self.chunkSize = chunkSize
        self.isCommand = isCommand
    }

    func send(_ pdu: DICOMULPDU) async throws {}

    func receive() async throws -> DICOMULPDU {
        .pData([DICOMPDataValue(contextID: contextID, isCommand: isCommand, isLastFragment: false, data: Data(count: chunkSize))])
    }

    func close() async {}
}

/// Delivers one complete, valid C-STORE command set (declaring a dataset
/// follows), then floods data PDVs whose last-fragment bit is never set.
private actor DICOMULCommandThenFloodingTransport: DICOMULTransport {
    private let contextID: UInt8
    private let chunkSize: Int
    private var sentCommand = false

    init(contextID: UInt8, chunkSize: Int) {
        self.contextID = contextID
        self.chunkSize = chunkSize
    }

    func send(_ pdu: DICOMULPDU) async throws {}

    func receive() async throws -> DICOMULPDU {
        if !sentCommand {
            sentCommand = true
            let command = DICOMDIMSECommand.cStoreRequest(messageID: 1, affectedSOPClassUID: DICOMSOPClass.ctImageStorage, affectedSOPInstanceUID: "1.2.3")
            return .pData(try command.commandPDVs(contextID: contextID, maximumPayloadLength: 16_384))
        }
        return .pData([DICOMPDataValue(contextID: contextID, isCommand: false, isLastFragment: false, data: Data(count: chunkSize))])
    }

    func close() async {}
}
