import Testing
import Foundation
@testable import DICOMKit
import DICOMKitNetworking

struct DICOMPerformedProcedureStepTests {
    private func acceptedAssociation(transport: DICOMULMPPSMockTransport) async throws -> DICOMAssociation {
        let association = DICOMAssociation(transport: transport)
        _ = try await association.request(DICOMAssociationRequest(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, abstractSyntaxUID: DICOMSOPClass.modalityPerformedProcedureStep, transferSyntaxUIDs: ["1.2.840.10008.1.2"])]))
        return association
    }

    private func statusValue(in data: Data, transferSyntax: TransferSyntax) throws -> String? {
        try DICOMFile(datasetData: data, transferSyntax: transferSyntax).dataset[DICOMTag(group: 0x0040, element: 0x0252)]?.stringValue
    }

    @Test func createSendsNCreateWhoseDataSetCarriesInProgressEvenWhenCallerSaidOtherwise() async throws {
        let transport = DICOMULMPPSMockTransport(received: [
            .associationAcceptance(DICOMAssociationAcceptance(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, result: .acceptance, transferSyntaxUID: "1.2.840.10008.1.2")])),
            .pData(try DICOMDIMSECommand.nCreateResponse(messageIDBeingRespondedTo: 400, affectedSOPClassUID: DICOMSOPClass.modalityPerformedProcedureStep, affectedSOPInstanceUID: "1.2.3", status: .success, datasetFollows: false).commandPDVs(contextID: 1, maximumPayloadLength: 1024))
        ])
        let association = try await acceptedAssociation(transport: transport)
        let callerDataset = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0040, element: 0x0252), vr: .CS, value: Data("COMPLETED".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0040, element: 0x0253), vr: .SH, value: Data("STEP1".utf8))
        ])
        let result = try await association.createPerformedProcedureStep(messageID: 400, contextID: 1, sopInstanceUID: "1.2.3", attributes: callerDataset, transferSyntax: .implicitVRLittleEndian)
        #expect(result.status == .success)

        let sent = await transport.sent
        guard case .pData(let dataValues) = sent[2] else { Issue.record("expected attributes pData"); return }
        let sentData = Data(dataValues.flatMap { Array($0.data) })
        #expect(try statusValue(in: sentData, transferSyntax: .implicitVRLittleEndian) == "IN PROGRESS")
        let sentDataset = try DICOMFile(datasetData: sentData, transferSyntax: .implicitVRLittleEndian).dataset
        #expect(sentDataset[DICOMTag(group: 0x0040, element: 0x0253)]?.stringValue == "STEP1")
    }

    @Test func updateToCompletedSendsNSetWithCompleted() async throws {
        let transport = DICOMULMPPSMockTransport(received: [
            .associationAcceptance(DICOMAssociationAcceptance(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, result: .acceptance, transferSyntaxUID: "1.2.840.10008.1.2")])),
            .pData(try DICOMDIMSECommand.nSetResponse(messageIDBeingRespondedTo: 401, affectedSOPClassUID: DICOMSOPClass.modalityPerformedProcedureStep, affectedSOPInstanceUID: "1.2.3", status: .success, datasetFollows: false).commandPDVs(contextID: 1, maximumPayloadLength: 1024))
        ])
        let association = try await acceptedAssociation(transport: transport)
        let callerDataset = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0040, element: 0x0253), vr: .SH, value: Data("STEP1".utf8))
        ])
        let result = try await association.updatePerformedProcedureStep(messageID: 401, contextID: 1, sopInstanceUID: "1.2.3", status: .completed, attributes: callerDataset, transferSyntax: .implicitVRLittleEndian)
        #expect(result.status == .success)

        let sent = await transport.sent
        guard case .pData(let dataValues) = sent[2] else { Issue.record("expected modification-list pData"); return }
        let sentData = Data(dataValues.flatMap { Array($0.data) })
        #expect(try statusValue(in: sentData, transferSyntax: .implicitVRLittleEndian) == "COMPLETED")
        let sentDataset = try DICOMFile(datasetData: sentData, transferSyntax: .implicitVRLittleEndian).dataset
        #expect(sentDataset[DICOMTag(group: 0x0040, element: 0x0253)]?.stringValue == "STEP1")
    }

    @Test func updateToInProgressThrowsInvalidProcedureStepTransition() async throws {
        let transport = DICOMULMPPSMockTransport(received: [
            .associationAcceptance(DICOMAssociationAcceptance(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, result: .acceptance, transferSyntaxUID: "1.2.840.10008.1.2")]))
        ])
        let association = try await acceptedAssociation(transport: transport)
        await #expect(throws: DICOMAssociationError.invalidProcedureStepTransition) {
            _ = try await association.updatePerformedProcedureStep(messageID: 402, contextID: 1, sopInstanceUID: "1.2.3", status: .inProgress, attributes: DICOMDataset(), transferSyntax: .implicitVRLittleEndian)
        }
        #expect(await transport.sent.count == 1) // association request only; nothing was sent for the rejected transition
    }
}

private actor DICOMULMPPSMockTransport: DICOMULTransport {
    var received: [DICOMULPDU]
    var sent: [DICOMULPDU] = []
    init(received: [DICOMULPDU]) { self.received = received }
    func send(_ pdu: DICOMULPDU) async throws { sent.append(pdu) }
    func receive() async throws -> DICOMULPDU { received.removeFirst() }
    func close() async {}
}
