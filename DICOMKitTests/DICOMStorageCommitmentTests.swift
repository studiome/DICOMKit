import Testing
import Foundation
@testable import DICOMKit

struct DICOMStorageCommitmentTests {
    @Test func actionInformationRoundTripsTransactionUIDAndReferences() throws {
        let request = DICOMStorageCommitmentRequest(
            transactionUID: "1.2.3.999",
            references: [
                DICOMSOPReference(sopClassUID: DICOMSOPClass.ctImageStorage, sopInstanceUID: "1.2.3.1"),
                DICOMSOPReference(sopClassUID: DICOMSOPClass.mrImageStorage, sopInstanceUID: "1.2.3.2")
            ]
        )
        let encoded = try request.actionInformation(transferSyntax: .explicitVRLittleEndian)
        let dataset = try DICOMFile(datasetData: encoded, transferSyntax: .explicitVRLittleEndian).dataset

        #expect(dataset[DICOMTag(group: 0x0008, element: 0x1195)]?.stringValue == "1.2.3.999")
        let items = dataset[DICOMTag(group: 0x0008, element: 0x1199)]?.sequenceItems
        #expect(items?.count == 2)
        #expect(items?.first?[.referencedSOPClassUID]?.stringValue == DICOMSOPClass.ctImageStorage)
        #expect(items?.first?[.referencedSOPInstanceUID]?.stringValue == "1.2.3.1")
        #expect(items?.last?[.referencedSOPClassUID]?.stringValue == DICOMSOPClass.mrImageStorage)
        #expect(items?.last?[.referencedSOPInstanceUID]?.stringValue == "1.2.3.2")
    }

    @Test func eventInformationWithOnlySuccessesParsesWithEmptyFailed() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0008, element: 0x1195), vr: .UI, value: Data("1.2.3.999".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0008, element: 0x1199), vr: .SQ, value: Data(), sequenceItems: [
                DICOMDataset(elements: [
                    DICOMElement(tag: .referencedSOPClassUID, vr: .UI, value: Data(DICOMSOPClass.ctImageStorage.utf8)),
                    DICOMElement(tag: .referencedSOPInstanceUID, vr: .UI, value: Data("1.2.3.1".utf8))
                ])
            ])
        ])
        let encoded = try DICOMWriter.encodeDataset(dataset, transferSyntax: .explicitVRLittleEndian)
        let result = try DICOMStorageCommitmentResult(eventInformation: encoded, transferSyntax: .explicitVRLittleEndian)
        #expect(result.transactionUID == "1.2.3.999")
        #expect(result.successful == [DICOMSOPReference(sopClassUID: DICOMSOPClass.ctImageStorage, sopInstanceUID: "1.2.3.1")])
        #expect(result.failed.isEmpty)
    }

    @Test func eventInformationWithFailuresParsesBothSequencesAndFailureReason() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0008, element: 0x1195), vr: .UI, value: Data("1.2.3.999".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0008, element: 0x1199), vr: .SQ, value: Data(), sequenceItems: [
                DICOMDataset(elements: [
                    DICOMElement(tag: .referencedSOPClassUID, vr: .UI, value: Data(DICOMSOPClass.ctImageStorage.utf8)),
                    DICOMElement(tag: .referencedSOPInstanceUID, vr: .UI, value: Data("1.2.3.1".utf8))
                ])
            ]),
            DICOMElement(tag: DICOMTag(group: 0x0008, element: 0x1198), vr: .SQ, value: Data(), sequenceItems: [
                DICOMDataset(elements: [
                    DICOMElement(tag: .referencedSOPClassUID, vr: .UI, value: Data(DICOMSOPClass.mrImageStorage.utf8)),
                    DICOMElement(tag: .referencedSOPInstanceUID, vr: .UI, value: Data("1.2.3.2".utf8)),
                    DICOMElement(tag: DICOMTag(group: 0x0008, element: 0x1197), vr: .US, value: Data([0x12, 0x02]))
                ])
            ])
        ])
        let encoded = try DICOMWriter.encodeDataset(dataset, transferSyntax: .explicitVRLittleEndian)
        let result = try DICOMStorageCommitmentResult(eventInformation: encoded, transferSyntax: .explicitVRLittleEndian)
        #expect(result.transactionUID == "1.2.3.999")
        #expect(result.successful == [DICOMSOPReference(sopClassUID: DICOMSOPClass.ctImageStorage, sopInstanceUID: "1.2.3.1")])
        #expect(result.failed == [DICOMStorageCommitmentFailure(reference: DICOMSOPReference(sopClassUID: DICOMSOPClass.mrImageStorage, sopInstanceUID: "1.2.3.2"), failureReason: 0x0212)])
    }

    @Test func requestStorageCommitmentSendsNActionWithActionTypeOneAndWellKnownInstance() async throws {
        let transport = DICOMULStorageCommitmentMockTransport(received: [
            .associationAcceptance(DICOMAssociationAcceptance(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, result: .acceptance, transferSyntaxUID: "1.2.840.10008.1.2")])),
            .pData(try DICOMDIMSECommand.nActionResponse(messageIDBeingRespondedTo: 300, affectedSOPClassUID: DICOMSOPClass.storageCommitmentPushModel, affectedSOPInstanceUID: DICOMSOPClass.storageCommitmentPushModelInstance, actionTypeID: 1, status: .success, datasetFollows: false).commandPDVs(contextID: 1, maximumPayloadLength: 1024))
        ])
        let association = DICOMAssociation(transport: transport)
        _ = try await association.request(DICOMAssociationRequest(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, abstractSyntaxUID: DICOMSOPClass.storageCommitmentPushModel, transferSyntaxUIDs: ["1.2.840.10008.1.2"])]))
        let request = DICOMStorageCommitmentRequest(transactionUID: "1.2.3.999", references: [DICOMSOPReference(sopClassUID: DICOMSOPClass.ctImageStorage, sopInstanceUID: "1.2.3.1")])
        let status = try await association.requestStorageCommitment(messageID: 300, contextID: 1, request)
        #expect(status == .success)

        let sent = await transport.sent
        guard case .pData(let commandValues) = sent[1] else { Issue.record("expected command pData"); return }
        let commandData = Data(commandValues.flatMap { Array($0.data) })
        guard case .nActionRequest(let messageID, let sopClassUID, let sopInstanceUID, let actionTypeID, let datasetFollows) = try DICOMDIMSECommand.decodeCommandSet(commandData) else {
            Issue.record("expected nActionRequest"); return
        }
        #expect(messageID == 300)
        #expect(sopClassUID == DICOMSOPClass.storageCommitmentPushModel)
        #expect(sopInstanceUID == DICOMSOPClass.storageCommitmentPushModelInstance)
        #expect(actionTypeID == 1)
        #expect(datasetFollows)

        guard case .pData(let dataValues) = sent[2] else { Issue.record("expected action-information pData"); return }
        let actionInformationData = Data(dataValues.flatMap { Array($0.data) })
        let actionInformation = try DICOMFile(datasetData: actionInformationData, transferSyntax: .implicitVRLittleEndian).dataset
        #expect(actionInformation[DICOMTag(group: 0x0008, element: 0x1195)]?.stringValue == "1.2.3.999")
    }
}

private actor DICOMULStorageCommitmentMockTransport: DICOMULTransport {
    var received: [DICOMULPDU]
    var sent: [DICOMULPDU] = []
    init(received: [DICOMULPDU]) { self.received = received }
    func send(_ pdu: DICOMULPDU) async throws { sent.append(pdu) }
    func receive() async throws -> DICOMULPDU { received.removeFirst() }
    func close() async {}
}
