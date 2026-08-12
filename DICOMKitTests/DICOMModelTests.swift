import Foundation
import Testing
@testable import DICOMKit

struct DICOMULTests {
    @Test func encodesAndDecodesAssociationRequest() throws {
        let request = DICOMAssociationRequest(
            calledAETitle: "PACS",
            callingAETitle: "DICOMKIT",
            presentationContexts: [
                DICOMPresentationContext(
                    id: 1,
                    abstractSyntaxUID: "1.2.840.10008.1.1",
                    transferSyntaxUIDs: ["1.2.840.10008.1.2"]
                )
            ]
        )

        let encoded = try DICOMULPDU.associationRequest(request).encoded()
        #expect(encoded.first == 0x01)
        #expect(try DICOMULPDU.decode(encoded) == .associationRequest(request))
    }

    @Test func encodesAndDecodesPDataValues() throws {
        let pdu = DICOMULPDU.pData([DICOMPDataValue(contextID: 3, isCommand: true, isLastFragment: true, data: Data([1, 2, 3]))])
        #expect(try DICOMULPDU.decode(pdu.encoded()) == pdu)
    }

    @Test func encodesCEchoCommandAndSplitsItIntoCommandPDVs() throws {
        let request = DICOMDIMSECommand.cEchoRequest(messageID: 7)
        let encoded = try request.encodedCommandSet()
        #expect(try DICOMDIMSECommand.decodeCommandSet(encoded) == request)

        let values = try request.commandPDVs(contextID: 1, maximumPayloadLength: 10)
        #expect(values.allSatisfy { $0.isCommand })
        #expect(values.last?.isLastFragment == true)
        #expect(Data(values.flatMap { Array($0.data) }) == encoded)
    }

    @Test func encodesAndDecodesAssociationAcceptance() throws {
        let acceptance = DICOMAssociationAcceptance(
            calledAETitle: "PACS",
            callingAETitle: "DICOMKIT",
            presentationContexts: [DICOMPresentationContextAcceptance(id: 1, result: .acceptance, transferSyntaxUID: "1.2.840.10008.1.2")]
        )
        let pdu = DICOMULPDU.associationAcceptance(acceptance)
        #expect(try DICOMULPDU.decode(pdu.encoded()) == pdu)
    }

    @Test func encodesAndDecodesAssociationRejection() throws {
        let pdu = DICOMULPDU.associationRejection(DICOMAssociationRejection(result: .permanent, source: .serviceUser, reason: 7))
        #expect(try DICOMULPDU.decode(pdu.encoded()) == pdu)
    }

    @Test func associationNegotiatesAndPerformsCEcho() async throws {
        let transport = DICOMULMockTransport(received: [
            .associationAcceptance(DICOMAssociationAcceptance(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, result: .acceptance, transferSyntaxUID: "1.2.840.10008.1.2")])),
            .pData(try DICOMDIMSECommand.cEchoResponse(messageIDBeingRespondedTo: 9, status: .success).commandPDVs(contextID: 1, maximumPayloadLength: 1024))
        ])
        let association = DICOMAssociation(transport: transport)
        _ = try await association.request(DICOMAssociationRequest(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, abstractSyntaxUID: "1.2.840.10008.1.1", transferSyntaxUIDs: ["1.2.840.10008.1.2"])]))
        #expect(try await association.cEcho(messageID: 9, contextID: 1) == .success)
        #expect(await transport.sent.count == 2)
    }

    @Test func encodesAndDecodesCStoreCommand() throws {
        let request = DICOMDIMSECommand.cStoreRequest(
            messageID: 11,
            affectedSOPClassUID: "1.2.840.10008.5.1.4.1.1.2",
            affectedSOPInstanceUID: "1.2.3.4"
        )
        #expect(try DICOMDIMSECommand.decodeCommandSet(request.encodedCommandSet()) == request)
    }

    @Test func associationSendsCStoreDataset() async throws {
        let transport = DICOMULMockTransport(received: [
            .associationAcceptance(DICOMAssociationAcceptance(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, result: .acceptance, transferSyntaxUID: "1.2.840.10008.1.2")])),
            .pData(try DICOMDIMSECommand.cStoreResponse(messageIDBeingRespondedTo: 12, status: .success).commandPDVs(contextID: 1, maximumPayloadLength: 1024))
        ])
        let association = DICOMAssociation(transport: transport)
        _ = try await association.request(DICOMAssociationRequest(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, abstractSyntaxUID: "1.2.840.10008.5.1.4.1.1.2", transferSyntaxUIDs: ["1.2.840.10008.1.2"])]))
        let status = try await association.cStore(messageID: 12, contextID: 1, sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3", dataset: Data([1, 2, 3]))
        #expect(status == .success)
        #expect(await transport.sent.count == 3)
    }

    @Test func encodesAndDecodesCFindRequest() throws {
        let request = DICOMDIMSECommand.cFindRequest(messageID: 13, affectedSOPClassUID: "1.2.840.10008.5.1.4.1.2.2.1")
        #expect(try DICOMDIMSECommand.decodeCommandSet(request.encodedCommandSet()) == request)
    }

    @Test func associationCollectsCFindResponses() async throws {
        let transport = DICOMULMockTransport(received: [
            .associationAcceptance(DICOMAssociationAcceptance(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, result: .acceptance, transferSyntaxUID: "1.2.840.10008.1.2")])),
            .pData(try DICOMDIMSECommand.cFindResponse(messageIDBeingRespondedTo: 14, status: .pending, identifierFollows: true, errorComment: nil).commandPDVs(contextID: 1, maximumPayloadLength: 1024)),
            .pData([DICOMPDataValue(contextID: 1, isCommand: false, isLastFragment: true, data: Data([4, 5]))]),
            .pData(try DICOMDIMSECommand.cFindResponse(messageIDBeingRespondedTo: 14, status: .success, identifierFollows: false, errorComment: nil).commandPDVs(contextID: 1, maximumPayloadLength: 1024))
        ])
        let association = DICOMAssociation(transport: transport)
        _ = try await association.request(DICOMAssociationRequest(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, abstractSyntaxUID: "1.2.840.10008.5.1.4.1.2.2.1", transferSyntaxUIDs: ["1.2.840.10008.1.2"])]))
        let result = try await association.cFind(messageID: 14, contextID: 1, sopClassUID: "1.2.840.10008.5.1.4.1.2.2.1", identifier: Data([1]))
        #expect(result.status == .success)
        #expect(result.identifiers == [Data([4, 5])])
    }

    @Test func encodesAndDecodesCMoveRequest() throws {
        let request = DICOMDIMSECommand.cMoveRequest(messageID: 15, affectedSOPClassUID: "1.2.840.10008.5.1.4.1.2.2.2", moveDestination: "STORE-SCP")
        #expect(try DICOMDIMSECommand.decodeCommandSet(request.encodedCommandSet()) == request)
    }

    @Test func associationPerformsCMove() async throws {
        let transport = DICOMULMockTransport(received: [
            .associationAcceptance(DICOMAssociationAcceptance(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, result: .acceptance, transferSyntaxUID: "1.2.840.10008.1.2")])),
            .pData(try DICOMDIMSECommand.cMoveResponse(messageIDBeingRespondedTo: 16, status: .success, identifierFollows: false, subOperations: nil, errorComment: nil).commandPDVs(contextID: 1, maximumPayloadLength: 1024))
        ])
        let association = DICOMAssociation(transport: transport)
        _ = try await association.request(DICOMAssociationRequest(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, abstractSyntaxUID: "1.2.840.10008.5.1.4.1.2.2.2", transferSyntaxUIDs: ["1.2.840.10008.1.2"])]))
        #expect(try await association.cMove(messageID: 16, contextID: 1, sopClassUID: "1.2.840.10008.5.1.4.1.2.2.2", destination: "STORE-SCP", identifier: Data()).status == .success)
    }

    @Test func encodesAndDecodesCGetRequest() throws {
        let request = DICOMDIMSECommand.cGetRequest(messageID: 17, affectedSOPClassUID: "1.2.840.10008.5.1.4.1.2.2.3")
        #expect(try DICOMDIMSECommand.decodeCommandSet(request.encodedCommandSet()) == request)
    }

    @Test func associationPerformsCGet() async throws {
        let transport = DICOMULMockTransport(received: [
            .associationAcceptance(DICOMAssociationAcceptance(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, result: .acceptance, transferSyntaxUID: "1.2.840.10008.1.2")])),
            .pData(try DICOMDIMSECommand.cGetResponse(messageIDBeingRespondedTo: 18, status: .success, identifierFollows: false, subOperations: nil, errorComment: nil).commandPDVs(contextID: 1, maximumPayloadLength: 1024))
        ])
        let association = DICOMAssociation(transport: transport)
        _ = try await association.request(DICOMAssociationRequest(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, abstractSyntaxUID: "1.2.840.10008.5.1.4.1.2.2.3", transferSyntaxUIDs: ["1.2.840.10008.1.2"])]))
        #expect(try await association.cGet(messageID: 18, contextID: 1, sopClassUID: "1.2.840.10008.5.1.4.1.2.2.3", identifier: Data()).status == .success)
    }

    @Test func associationReceivesCStoreAndReplies() async throws {
        let store = DICOMDIMSECommand.cStoreRequest(messageID: 19, affectedSOPClassUID: "1.2.840.10008.5.1.4.1.1.2", affectedSOPInstanceUID: "1.2.3")
        let transport = DICOMULMockTransport(received: [
            .associationAcceptance(DICOMAssociationAcceptance(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, result: .acceptance, transferSyntaxUID: "1.2.840.10008.1.2")])),
            .pData(try store.commandPDVs(contextID: 1, maximumPayloadLength: 1024)),
            .pData([DICOMPDataValue(contextID: 1, isCommand: false, isLastFragment: true, data: Data([7, 8]))])
        ])
        let association = DICOMAssociation(transport: transport)
        _ = try await association.request(DICOMAssociationRequest(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, abstractSyntaxUID: "1.2.840.10008.5.1.4.1.1.2", transferSyntaxUIDs: ["1.2.840.10008.1.2"])]))
        let received = try await association.receiveCStore()
        #expect(received.dataset == Data([7, 8]))
        #expect(received.sopInstanceUID == "1.2.3")
        try await association.respond(to: received, status: .success)
        #expect(await transport.sent.count == 2)
    }

    @Test func encodesAndSendsCCancel() async throws {
        let cancel = DICOMDIMSECommand.cCancelRequest(messageIDBeingRespondedTo: 20)
        #expect(try DICOMDIMSECommand.decodeCommandSet(cancel.encodedCommandSet()) == cancel)
        let transport = DICOMULMockTransport(received: [.associationAcceptance(DICOMAssociationAcceptance(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, result: .acceptance, transferSyntaxUID: "1.2.840.10008.1.2")]))])
        let association = DICOMAssociation(transport: transport)
        _ = try await association.request(DICOMAssociationRequest(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, abstractSyntaxUID: "1.2.840.10008.1.1", transferSyntaxUIDs: ["1.2.840.10008.1.2"])]))
        try await association.cCancel(messageIDBeingRespondedTo: 20, contextID: 1)
        #expect(await transport.sent.count == 2)
    }

    @Test func associationTimesOutWhileAwaitingResponse() async throws {
        let transport = DICOMULNeverRespondingTransport()
        let association = DICOMAssociation(transport: transport, responseTimeout: .milliseconds(1))
        let request = DICOMAssociationRequest(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, abstractSyntaxUID: "1.2.840.10008.1.1", transferSyntaxUIDs: ["1.2.840.10008.1.2"])])
        await #expect(throws: DICOMAssociationError.timedOut) { try await association.request(request) }
    }

    @Test func associationSelectsAcceptedPresentationContextForSOPClass() async throws {
        let transport = DICOMULMockTransport(received: [
            .associationAcceptance(DICOMAssociationAcceptance(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [
                .init(id: 1, result: .abstractSyntaxNotSupported, transferSyntaxUID: "1.2.840.10008.1.2"),
                .init(id: 3, result: .acceptance, transferSyntaxUID: "1.2.840.10008.1.2")
            ]))
        ])
        let association = DICOMAssociation(transport: transport)
        let sopClass = "1.2.840.10008.5.1.4.1.1.2"
        _ = try await association.request(DICOMAssociationRequest(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [
            .init(id: 1, abstractSyntaxUID: "1.2.840.10008.1.1", transferSyntaxUIDs: ["1.2.840.10008.1.2"]),
            .init(id: 3, abstractSyntaxUID: sopClass, transferSyntaxUIDs: ["1.2.840.10008.1.2"])
        ]))
        #expect(await association.presentationContextID(for: sopClass) == 3)
    }

    @Test func associationSelectsPresentationContextForCStore() async throws {
        let sopClass = "1.2.840.10008.5.1.4.1.1.2"
        let transport = DICOMULMockTransport(received: [
            .associationAcceptance(DICOMAssociationAcceptance(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 3, result: .acceptance, transferSyntaxUID: "1.2.840.10008.1.2")])),
            .pData(try DICOMDIMSECommand.cStoreResponse(messageIDBeingRespondedTo: 21, status: .success).commandPDVs(contextID: 3, maximumPayloadLength: 1024))
        ])
        let association = DICOMAssociation(transport: transport)
        _ = try await association.request(DICOMAssociationRequest(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 3, abstractSyntaxUID: sopClass, transferSyntaxUIDs: ["1.2.840.10008.1.2"])]))
        #expect(try await association.cStore(messageID: 21, sopClassUID: sopClass, sopInstanceUID: "1.2.3", dataset: Data()) == .success)
    }

    @Test func associationSelectsPresentationContextForCFind() async throws {
        let sopClass = "1.2.840.10008.5.1.4.1.2.2.1"
        let transport = DICOMULMockTransport(received: [
            .associationAcceptance(DICOMAssociationAcceptance(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 5, result: .acceptance, transferSyntaxUID: "1.2.840.10008.1.2")])),
            .pData(try DICOMDIMSECommand.cFindResponse(messageIDBeingRespondedTo: 22, status: .success, identifierFollows: false, errorComment: nil).commandPDVs(contextID: 5, maximumPayloadLength: 1024))
        ])
        let association = DICOMAssociation(transport: transport)
        _ = try await association.request(DICOMAssociationRequest(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 5, abstractSyntaxUID: sopClass, transferSyntaxUIDs: ["1.2.840.10008.1.2"])]))
        #expect(try await association.cFind(messageID: 22, sopClassUID: sopClass, identifier: Data()).status == .success)
    }

    @Test func encodesAssociationUserIdentity() throws {
        let identity = DICOMUserIdentityNegotiation(identity: .usernameAndPassword(username: "dicom", password: "secret"))
        let request = DICOMAssociationRequest(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, abstractSyntaxUID: "1.2.840.10008.1.1", transferSyntaxUIDs: ["1.2.840.10008.1.2"])], userIdentity: identity)
        #expect(try DICOMULPDU.decode(DICOMULPDU.associationRequest(request).encoded()) == .associationRequest(request))
    }

    @Test func encodesAndDecodesImplementationIdentificationInRequest() throws {
        let implementation = try DICOMImplementationIdentification(classUID: "1.2.3.4.5", versionName: "MY_APP_1_0")
        let request = DICOMAssociationRequest(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, abstractSyntaxUID: "1.2.840.10008.1.1", transferSyntaxUIDs: ["1.2.840.10008.1.2"])], implementation: implementation)
        #expect(try DICOMULPDU.decode(DICOMULPDU.associationRequest(request).encoded()) == .associationRequest(request))
    }

    @Test func encodesAndDecodesImplementationIdentificationInAcceptance() throws {
        let implementation = try DICOMImplementationIdentification(classUID: "1.2.3.4.5", versionName: "MY_APP_1_0")
        let acceptance = DICOMAssociationAcceptance(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, result: .acceptance, transferSyntaxUID: "1.2.840.10008.1.2")], implementation: implementation)
        #expect(try DICOMULPDU.decode(DICOMULPDU.associationAcceptance(acceptance).encoded()) == .associationAcceptance(acceptance))
    }

    @Test func defaultsToDicomKitImplementationIdentification() throws {
        let request = DICOMAssociationRequest(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, abstractSyntaxUID: "1.2.840.10008.1.1", transferSyntaxUIDs: ["1.2.840.10008.1.2"])])
        #expect(request.implementation == .dicomKit)
    }

    @Test func defaultsImplementationClassUIDWhenPeerOmitsSubItem() throws {
        var userInformation = Data()
        userInformation.append(ulItem(0x51, ulUInt32(16_384)))
        let pdu = rawAssociationRequestPDU(userInformation: userInformation)
        let decoded = try DICOMULPDU.decode(pdu)
        guard case .associationRequest(let request) = decoded else { Issue.record("expected associationRequest"); return }
        #expect(request.implementation.classUID == DICOMImplementationIdentification.dicomKit.classUID)
        #expect(request.implementation.versionName == nil)
    }

    @Test func throwsForOversizedImplementationVersionName() {
        #expect(throws: DICOMULError.malformedPDU) {
            try DICOMImplementationIdentification(classUID: "1.2.3", versionName: "01234567890123456")
        }
    }

    @Test func encodesAndDecodesRoleSelectionInRequest() throws {
        let role = DICOMRoleSelection(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", supportsSCURole: true, supportsSCPRole: true)
        let request = DICOMAssociationRequest(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, abstractSyntaxUID: "1.2.840.10008.1.1", transferSyntaxUIDs: ["1.2.840.10008.1.2"])], roleSelections: [role])
        #expect(try DICOMULPDU.decode(DICOMULPDU.associationRequest(request).encoded()) == .associationRequest(request))
    }

    @Test func encodesAndDecodesRoleSelectionInAcceptance() throws {
        let role = DICOMRoleSelection(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", supportsSCURole: false, supportsSCPRole: true)
        let acceptance = DICOMAssociationAcceptance(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, result: .acceptance, transferSyntaxUID: "1.2.840.10008.1.2")], roleSelections: [role])
        #expect(try DICOMULPDU.decode(DICOMULPDU.associationAcceptance(acceptance).encoded()) == .associationAcceptance(acceptance))
    }

    @Test func associationReturnsNegotiatedRoleForSOPClass() async throws {
        let sopClass = "1.2.840.10008.5.1.4.1.1.2"
        let acceptedRole = DICOMRoleSelection(sopClassUID: sopClass, supportsSCURole: false, supportsSCPRole: true)
        let transport = DICOMULMockTransport(received: [
            .associationAcceptance(DICOMAssociationAcceptance(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, result: .acceptance, transferSyntaxUID: "1.2.840.10008.1.2")], roleSelections: [acceptedRole]))
        ])
        let association = DICOMAssociation(transport: transport)
        _ = try await association.request(DICOMAssociationRequest(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, abstractSyntaxUID: sopClass, transferSyntaxUIDs: ["1.2.840.10008.1.2"])], roleSelections: [DICOMRoleSelection(sopClassUID: sopClass, supportsSCURole: true, supportsSCPRole: true)]))
        #expect(await association.negotiatedRoles(for: sopClass) == acceptedRole)
        #expect(await association.negotiatedRoles(for: "1.2.3.4.5") == nil)
    }

    @Test func throwsForMalformedRoleSelectionBody() throws {
        var userInformation = Data()
        userInformation.append(ulItem(0x51, ulUInt32(16_384)))
        var malformedRole = Data([0, 20])
        malformedRole.append(Data("1.2.3".utf8))
        malformedRole.append(Data([1, 1]))
        userInformation.append(ulItem(0x54, malformedRole))
        let pdu = rawAssociationRequestPDU(userInformation: userInformation)
        #expect(throws: DICOMULError.malformedPDU) { try DICOMULPDU.decode(pdu) }
    }

    @Test func encodesAndDecodesAsyncOperationsWindowInRequest() throws {
        let window = DICOMAsynchronousOperationsWindow(maximumInvoked: 3, maximumPerformed: 5)
        let request = DICOMAssociationRequest(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, abstractSyntaxUID: "1.2.840.10008.1.1", transferSyntaxUIDs: ["1.2.840.10008.1.2"])], asynchronousOperationsWindow: window)
        #expect(try DICOMULPDU.decode(DICOMULPDU.associationRequest(request).encoded()) == .associationRequest(request))
    }

    @Test func encodesAndDecodesAsyncOperationsWindowInAcceptance() throws {
        let window = DICOMAsynchronousOperationsWindow(maximumInvoked: 0, maximumPerformed: 0)
        let acceptance = DICOMAssociationAcceptance(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, result: .acceptance, transferSyntaxUID: "1.2.840.10008.1.2")], asynchronousOperationsWindow: window)
        #expect(try DICOMULPDU.decode(DICOMULPDU.associationAcceptance(acceptance).encoded()) == .associationAcceptance(acceptance))
    }

    @Test func throwsForMalformedAsyncOperationsWindowBody() throws {
        var userInformation = Data()
        userInformation.append(ulItem(0x51, ulUInt32(16_384)))
        userInformation.append(ulItem(0x53, Data([0, 1, 0])))
        let pdu = rawAssociationRequestPDU(userInformation: userInformation)
        #expect(throws: DICOMULError.malformedPDU) { try DICOMULPDU.decode(pdu) }
    }

    @Test func roundTripsEachUserIdentityType() throws {
        let identities: [DICOMUserIdentity] = [
            .username("dicom"),
            .usernameAndPassword(username: "dicom", password: "secret"),
            .kerberos(Data([0x01, 0x02, 0x03, 0x04])),
            .saml("<Assertion/>"),
            .jwt("eyJhbGciOiJIUzI1NiJ9.e30.abc")
        ]
        for identity in identities {
            let negotiation = DICOMUserIdentityNegotiation(identity: identity)
            let request = DICOMAssociationRequest(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, abstractSyntaxUID: "1.2.840.10008.1.1", transferSyntaxUIDs: ["1.2.840.10008.1.2"])], userIdentity: negotiation)
            #expect(try DICOMULPDU.decode(DICOMULPDU.associationRequest(request).encoded()) == .associationRequest(request))
        }
    }

    @Test func positiveResponseRequestedSurvivesRoundTrip() throws {
        let negotiation = DICOMUserIdentityNegotiation(identity: .username("dicom"), positiveResponseRequested: true)
        let request = DICOMAssociationRequest(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, abstractSyntaxUID: "1.2.840.10008.1.1", transferSyntaxUIDs: ["1.2.840.10008.1.2"])], userIdentity: negotiation)
        let decoded = try DICOMULPDU.decode(DICOMULPDU.associationRequest(request).encoded())
        guard case .associationRequest(let decodedRequest) = decoded else { Issue.record("expected associationRequest"); return }
        #expect(decodedRequest.userIdentity?.positiveResponseRequested == true)
    }

    @Test func encodesAndDecodesUserIdentityResponseInAcceptance() throws {
        let acceptance = DICOMAssociationAcceptance(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, result: .acceptance, transferSyntaxUID: "1.2.840.10008.1.2")], userIdentityResponse: Data([0xAA, 0xBB, 0xCC]))
        #expect(try DICOMULPDU.decode(DICOMULPDU.associationAcceptance(acceptance).encoded()) == .associationAcceptance(acceptance))
    }

    @Test func peerAbortDuringDIMSEOperationThrowsAborted() async throws {
        let transport = DICOMULMockTransport(received: [
            .associationAcceptance(DICOMAssociationAcceptance(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, result: .acceptance, transferSyntaxUID: "1.2.840.10008.1.2")])),
            .abort(source: 2, reason: 1)
        ])
        let association = DICOMAssociation(transport: transport)
        _ = try await association.request(DICOMAssociationRequest(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, abstractSyntaxUID: "1.2.840.10008.1.1", transferSyntaxUIDs: ["1.2.840.10008.1.2"])]))
        await #expect(throws: DICOMAssociationError.aborted(source: 2, reason: 1)) { try await association.cEcho(messageID: 9, contextID: 1) }
    }

    @Test func peerReleaseRequestDuringDIMSEOperationThrowsReleasedByPeerAndRepliesWithReleaseResponse() async throws {
        let transport = DICOMULMockTransport(received: [
            .associationAcceptance(DICOMAssociationAcceptance(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, result: .acceptance, transferSyntaxUID: "1.2.840.10008.1.2")])),
            .releaseRequest
        ])
        let association = DICOMAssociation(transport: transport)
        _ = try await association.request(DICOMAssociationRequest(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, abstractSyntaxUID: "1.2.840.10008.1.1", transferSyntaxUIDs: ["1.2.840.10008.1.2"])]))
        await #expect(throws: DICOMAssociationError.releasedByPeer) { try await association.cEcho(messageID: 9, contextID: 1) }
        #expect(await transport.sent.last == .releaseResponse)
    }

    @Test func abortSendsAAbortAndTearsDownAssociation() async throws {
        let transport = DICOMULMockTransport(received: [
            .associationAcceptance(DICOMAssociationAcceptance(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, result: .acceptance, transferSyntaxUID: "1.2.840.10008.1.2")]))
        ])
        let association = DICOMAssociation(transport: transport)
        _ = try await association.request(DICOMAssociationRequest(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, abstractSyntaxUID: "1.2.840.10008.1.1", transferSyntaxUIDs: ["1.2.840.10008.1.2"])]))
        try await association.abort(source: 0, reason: 0)
        #expect(await transport.sent.last == .abort(source: 0, reason: 0))
        await #expect(throws: DICOMAssociationError.notAssociated) { try await association.cEcho(messageID: 9, contextID: 1) }
    }

    @Test func releaseAfterAbortIsIdempotent() async throws {
        let transport = DICOMULMockTransport(received: [
            .associationAcceptance(DICOMAssociationAcceptance(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, result: .acceptance, transferSyntaxUID: "1.2.840.10008.1.2")]))
        ])
        let association = DICOMAssociation(transport: transport)
        _ = try await association.request(DICOMAssociationRequest(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, abstractSyntaxUID: "1.2.840.10008.1.1", transferSyntaxUIDs: ["1.2.840.10008.1.2"])]))
        try await association.abort()
        try await association.release()
    }

    @Test func classifiesDIMSEStatusCodesByCategory() {
        #expect(DICOMDIMSEStatus(rawValue: 0x0000).category == .success)
        #expect(DICOMDIMSEStatus(rawValue: 0xFF00).category == .pending)
        #expect(DICOMDIMSEStatus(rawValue: 0xFF01).category == .pending)
        #expect(DICOMDIMSEStatus(rawValue: 0xFF00).isPending)
        #expect(DICOMDIMSEStatus(rawValue: 0xFE00).category == .cancel)
        #expect(DICOMDIMSEStatus(rawValue: 0x0001).category == .warning)
        #expect(DICOMDIMSEStatus(rawValue: 0x0107).category == .warning)
        #expect(DICOMDIMSEStatus(rawValue: 0x0116).category == .warning)
        #expect(DICOMDIMSEStatus(rawValue: 0xB000).category == .warning)
        #expect(DICOMDIMSEStatus(rawValue: 0xBFFF).category == .warning)
        #expect(DICOMDIMSEStatus(rawValue: 0xC000).category == .failure)
        #expect(DICOMDIMSEStatus.errorCannotUnderstand.category == .failure)
        #expect(DICOMDIMSEStatus.refusedOutOfResources.category == .failure)
        #expect(DICOMDIMSEStatus.refusedSOPClassNotSupported.category == .failure)
        #expect(DICOMDIMSEStatus.errorDataSetDoesNotMatchSOPClass.category == .failure)
        #expect(!DICOMDIMSEStatus.success.isPending)
    }

    @Test func roundTripsCMoveResponseWithSubOperationCountsAndErrorComment() throws {
        let response = DICOMDIMSECommand.cMoveResponse(
            messageIDBeingRespondedTo: 23,
            status: .refusedOutOfResources,
            identifierFollows: true,
            subOperations: DICOMSubOperationCounts(remaining: 1, completed: 4, failed: 2, warning: 3),
            errorComment: "out of resources"
        )
        #expect(try DICOMDIMSECommand.decodeCommandSet(response.encodedCommandSet()) == response)
    }

    @Test func cMoveResponseWithoutCountElementsDecodesNilSubOperations() throws {
        let response = DICOMDIMSECommand.cMoveResponse(messageIDBeingRespondedTo: 24, status: .success, identifierFollows: false, subOperations: nil, errorComment: nil)
        guard case .cMoveResponse(_, _, _, let subOperations, _) = try DICOMDIMSECommand.decodeCommandSet(response.encodedCommandSet()) else {
            Issue.record("expected cMoveResponse"); return
        }
        #expect(subOperations == nil)
    }

    /// Proves the wire tags used for the sub-operation counts and Error Comment match the
    /// real DICOM (group, element) layout — group and element each little-endian, per
    /// PS3.4 Annex C.4.2.3 — independent of whichever `UInt32` key the codec uses internally.
    @Test func decodesSubOperationCountsAndErrorCommentAtTheirStandardWireTags() throws {
        func element(group: UInt16, element: UInt16, value: Data) -> Data {
            var data = Data([UInt8(group & 0xFF), UInt8(group >> 8), UInt8(element & 0xFF), UInt8(element >> 8)])
            var padded = value
            if padded.count % 2 != 0 { padded.append(0) }
            data.append(UInt8(padded.count & 0xFF)); data.append(UInt8((padded.count >> 8) & 0xFF)); data.append(UInt8((padded.count >> 16) & 0xFF)); data.append(UInt8(padded.count >> 24))
            data.append(padded)
            return data
        }
        func uint16(_ value: UInt16) -> Data { Data([UInt8(value & 0xFF), UInt8(value >> 8)]) }

        var raw = Data()
        raw.append(element(group: 0x0000, element: 0x0100, value: uint16(0x8021))) // Command Field: C-MOVE-RSP
        raw.append(element(group: 0x0000, element: 0x0120, value: uint16(25))) // Message ID Being Responded To
        raw.append(element(group: 0x0000, element: 0x0800, value: uint16(0x0101))) // Data Set Type
        raw.append(element(group: 0x0000, element: 0x0900, value: uint16(0xFF00))) // Status: Pending
        raw.append(element(group: 0x0000, element: 0x1020, value: uint16(3))) // Number of Remaining Sub-operations
        raw.append(element(group: 0x0000, element: 0x1021, value: uint16(4))) // Number of Completed Sub-operations
        raw.append(element(group: 0x0000, element: 0x1022, value: uint16(1))) // Number of Failed Sub-operations
        raw.append(element(group: 0x0000, element: 0x1023, value: uint16(2))) // Number of Warning Sub-operations
        raw.append(element(group: 0x0000, element: 0x0902, value: Data("oops".utf8))) // Error Comment

        guard case .cMoveResponse(let messageID, let status, let identifierFollows, let subOperations, let errorComment) = try DICOMDIMSECommand.decodeCommandSet(raw) else {
            Issue.record("expected cMoveResponse"); return
        }
        #expect(messageID == 25)
        #expect(status == .pending)
        #expect(!identifierFollows)
        #expect(subOperations == DICOMSubOperationCounts(remaining: 3, completed: 4, failed: 1, warning: 2))
        #expect(errorComment == "oops")
    }

    @Test func cMoveSurfacesSubOperationCountsFromFinalResponseAfterPendingResponse() async throws {
        let transport = DICOMULMockTransport(received: [
            .associationAcceptance(DICOMAssociationAcceptance(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, result: .acceptance, transferSyntaxUID: "1.2.840.10008.1.2")])),
            .pData(try DICOMDIMSECommand.cMoveResponse(messageIDBeingRespondedTo: 26, status: .pending, identifierFollows: false, subOperations: DICOMSubOperationCounts(remaining: 2, completed: 0, failed: 0, warning: 0), errorComment: nil).commandPDVs(contextID: 1, maximumPayloadLength: 1024)),
            .pData(try DICOMDIMSECommand.cMoveResponse(messageIDBeingRespondedTo: 26, status: .success, identifierFollows: false, subOperations: DICOMSubOperationCounts(remaining: 0, completed: 2, failed: 0, warning: 0), errorComment: nil).commandPDVs(contextID: 1, maximumPayloadLength: 1024))
        ])
        let association = DICOMAssociation(transport: transport)
        _ = try await association.request(DICOMAssociationRequest(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, abstractSyntaxUID: "1.2.840.10008.5.1.4.1.2.2.2", transferSyntaxUIDs: ["1.2.840.10008.1.2"])]))
        let result = try await association.cMove(messageID: 26, contextID: 1, sopClassUID: "1.2.840.10008.5.1.4.1.2.2.2", destination: "STORE-SCP", identifier: Data())
        #expect(result.status == .success)
        #expect(result.subOperations == DICOMSubOperationCounts(remaining: 0, completed: 2, failed: 0, warning: 0))
    }

    /// Proves Command Data Set Type (0000,0800) is encoded from `identifierFollows` per
    /// PS3.7 E.2 (`0x0101` means no dataset follows; any other value means one does),
    /// not hardcoded, and that decoding recovers the same flag.
    @Test func cFindResponseEncodesDataSetTypeFromIdentifierFollows() throws {
        let pending = DICOMDIMSECommand.cFindResponse(messageIDBeingRespondedTo: 30, status: .pending, identifierFollows: true, errorComment: nil)
        let pendingEncoded = try pending.encodedCommandSet()
        #expect(commandSetUInt16(tag: 0x08000000, in: pendingEncoded) == 0x0000)
        #expect(try DICOMDIMSECommand.decodeCommandSet(pendingEncoded) == pending)
        #expect(pending.hasDataset)

        let final = DICOMDIMSECommand.cFindResponse(messageIDBeingRespondedTo: 30, status: .success, identifierFollows: false, errorComment: nil)
        let finalEncoded = try final.encodedCommandSet()
        #expect(commandSetUInt16(tag: 0x08000000, in: finalEncoded) == 0x0101)
        #expect(try DICOMDIMSECommand.decodeCommandSet(finalEncoded) == final)
        #expect(!final.hasDataset)
    }

    @Test func cMoveAndCGetResponsesEncodeDataSetTypeFromIdentifierFollows() throws {
        let moveWithIdentifier = DICOMDIMSECommand.cMoveResponse(messageIDBeingRespondedTo: 31, status: DICOMDIMSEStatus(rawValue: 0xB000), identifierFollows: true, subOperations: nil, errorComment: nil)
        #expect(commandSetUInt16(tag: 0x08000000, in: try moveWithIdentifier.encodedCommandSet()) == 0x0000)
        #expect(moveWithIdentifier.hasDataset)

        let getWithoutIdentifier = DICOMDIMSECommand.cGetResponse(messageIDBeingRespondedTo: 32, status: .success, identifierFollows: false, subOperations: nil, errorComment: nil)
        #expect(commandSetUInt16(tag: 0x08000000, in: try getWithoutIdentifier.encodedCommandSet()) == 0x0101)
        #expect(!getWithoutIdentifier.hasDataset)
    }

    @Test func hasDatasetReflectsCommandKind() {
        #expect(!DICOMDIMSECommand.cEchoRequest(messageID: 1).hasDataset)
        #expect(!DICOMDIMSECommand.cEchoResponse(messageIDBeingRespondedTo: 1, status: .success).hasDataset)
        #expect(DICOMDIMSECommand.cStoreRequest(messageID: 1, affectedSOPClassUID: "1.2", affectedSOPInstanceUID: "1.3").hasDataset)
        #expect(!DICOMDIMSECommand.cStoreResponse(messageIDBeingRespondedTo: 1, status: .success).hasDataset)
        #expect(DICOMDIMSECommand.cFindRequest(messageID: 1, affectedSOPClassUID: "1.2").hasDataset)
        #expect(DICOMDIMSECommand.cFindResponse(messageIDBeingRespondedTo: 1, status: .pending, identifierFollows: true, errorComment: nil).hasDataset)
        #expect(!DICOMDIMSECommand.cFindResponse(messageIDBeingRespondedTo: 1, status: .success, identifierFollows: false, errorComment: nil).hasDataset)
        #expect(DICOMDIMSECommand.cMoveRequest(messageID: 1, affectedSOPClassUID: "1.2", moveDestination: "DEST").hasDataset)
        #expect(DICOMDIMSECommand.cMoveResponse(messageIDBeingRespondedTo: 1, status: .success, identifierFollows: true, subOperations: nil, errorComment: nil).hasDataset)
        #expect(!DICOMDIMSECommand.cMoveResponse(messageIDBeingRespondedTo: 1, status: .success, identifierFollows: false, subOperations: nil, errorComment: nil).hasDataset)
        #expect(DICOMDIMSECommand.cGetRequest(messageID: 1, affectedSOPClassUID: "1.2").hasDataset)
        #expect(DICOMDIMSECommand.cGetResponse(messageIDBeingRespondedTo: 1, status: .success, identifierFollows: true, subOperations: nil, errorComment: nil).hasDataset)
        #expect(!DICOMDIMSECommand.cGetResponse(messageIDBeingRespondedTo: 1, status: .success, identifierFollows: false, subOperations: nil, errorComment: nil).hasDataset)
        #expect(!DICOMDIMSECommand.cCancelRequest(messageIDBeingRespondedTo: 1).hasDataset)
    }

    @Test func receiveRequestReturnsCEchoWithNilDataset() async throws {
        let echo = DICOMDIMSECommand.cEchoRequest(messageID: 40)
        let transport = DICOMULMockTransport(received: [
            .associationAcceptance(DICOMAssociationAcceptance(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, result: .acceptance, transferSyntaxUID: "1.2.840.10008.1.2")])),
            .pData(try echo.commandPDVs(contextID: 1, maximumPayloadLength: 1024))
        ])
        let association = DICOMAssociation(transport: transport)
        _ = try await association.request(DICOMAssociationRequest(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, abstractSyntaxUID: "1.2.840.10008.1.1", transferSyntaxUIDs: ["1.2.840.10008.1.2"])]))
        let request = try await association.receiveRequest()
        #expect(request.command == echo)
        #expect(request.contextID == 1)
        #expect(request.dataset == nil)
    }

    @Test func receiveRequestReassemblesCFindIdentifierFromFragments() async throws {
        let find = DICOMDIMSECommand.cFindRequest(messageID: 41, affectedSOPClassUID: "1.2.840.10008.5.1.4.1.2.2.1")
        let transport = DICOMULMockTransport(received: [
            .associationAcceptance(DICOMAssociationAcceptance(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, result: .acceptance, transferSyntaxUID: "1.2.840.10008.1.2")])),
            .pData(try find.commandPDVs(contextID: 1, maximumPayloadLength: 1024)),
            .pData([DICOMPDataValue(contextID: 1, isCommand: false, isLastFragment: false, data: Data([1, 2]))]),
            .pData([DICOMPDataValue(contextID: 1, isCommand: false, isLastFragment: true, data: Data([3, 4]))])
        ])
        let association = DICOMAssociation(transport: transport)
        _ = try await association.request(DICOMAssociationRequest(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, abstractSyntaxUID: "1.2.840.10008.5.1.4.1.2.2.1", transferSyntaxUIDs: ["1.2.840.10008.1.2"])]))
        let request = try await association.receiveRequest()
        #expect(request.command == find)
        #expect(request.contextID == 1)
        #expect(request.dataset == Data([1, 2, 3, 4]))
    }

    @Test func receiveCStoreRejectsNonCStoreRequest() async throws {
        let echo = DICOMDIMSECommand.cEchoRequest(messageID: 42)
        let transport = DICOMULMockTransport(received: [
            .associationAcceptance(DICOMAssociationAcceptance(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, result: .acceptance, transferSyntaxUID: "1.2.840.10008.1.2")])),
            .pData(try echo.commandPDVs(contextID: 1, maximumPayloadLength: 1024))
        ])
        let association = DICOMAssociation(transport: transport)
        _ = try await association.request(DICOMAssociationRequest(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, abstractSyntaxUID: "1.2.840.10008.1.1", transferSyntaxUIDs: ["1.2.840.10008.1.2"])]))
        await #expect(throws: DICOMAssociationError.unexpectedDIMSECommand) { try await association.receiveCStore() }
    }

    @Test func respondToCFindSendsIdentifierOnlyWhenPending() async throws {
        let transport = DICOMULMockTransport(received: [
            .associationAcceptance(DICOMAssociationAcceptance(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, result: .acceptance, transferSyntaxUID: "1.2.840.10008.1.2")]))
        ])
        let association = DICOMAssociation(transport: transport)
        _ = try await association.request(DICOMAssociationRequest(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, abstractSyntaxUID: "1.2.840.10008.5.1.4.1.2.2.1", transferSyntaxUIDs: ["1.2.840.10008.1.2"])]))

        try await association.respondToCFind(messageIDBeingRespondedTo: 43, contextID: 1, status: .pending, identifier: Data([9, 9]))
        var sent = await transport.sent
        #expect(sent.count == 3) // association request, command PDV, identifier PDV
        guard case .pData(let commandValues) = sent[1] else { Issue.record("expected command pData"); return }
        #expect(commandValues.allSatisfy { $0.isCommand })
        guard case .pData(let identifierValues) = sent[2] else { Issue.record("expected identifier pData"); return }
        #expect(identifierValues.allSatisfy { !$0.isCommand })

        try await association.respondToCFind(messageIDBeingRespondedTo: 43, contextID: 1, status: .success, identifier: nil)
        sent = await transport.sent
        #expect(sent.count == 4) // + final command PDV only
        guard case .pData(let finalCommandValues) = sent[3] else { Issue.record("expected final command pData"); return }
        #expect(finalCommandValues.allSatisfy { $0.isCommand })
    }

    @Test func respondToCMoveEncodesSubOperationCounts() async throws {
        let transport = DICOMULMockTransport(received: [
            .associationAcceptance(DICOMAssociationAcceptance(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, result: .acceptance, transferSyntaxUID: "1.2.840.10008.1.2")]))
        ])
        let association = DICOMAssociation(transport: transport)
        _ = try await association.request(DICOMAssociationRequest(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, abstractSyntaxUID: "1.2.840.10008.5.1.4.1.2.2.2", transferSyntaxUIDs: ["1.2.840.10008.1.2"])]))
        let counts = DICOMSubOperationCounts(remaining: 1, completed: 2, failed: 0, warning: 0)
        try await association.respondToCMove(messageIDBeingRespondedTo: 44, contextID: 1, status: .pending, subOperations: counts)
        let sent = await transport.sent
        guard case .pData(let values) = sent.last else { Issue.record("expected pData"); return }
        let commandData = Data(values.flatMap { Array($0.data) })
        guard case .cMoveResponse(_, _, _, let decodedCounts, _) = try DICOMDIMSECommand.decodeCommandSet(commandData) else {
            Issue.record("expected cMoveResponse"); return
        }
        #expect(decodedCounts == counts)
    }

    @Test func responderThrowsNotAssociatedForUnacceptedContext() async throws {
        let transport = DICOMULMockTransport(received: [
            .associationAcceptance(DICOMAssociationAcceptance(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, result: .abstractSyntaxNotSupported, transferSyntaxUID: "1.2.840.10008.1.2")]))
        ])
        let association = DICOMAssociation(transport: transport)
        _ = try await association.request(DICOMAssociationRequest(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, abstractSyntaxUID: "1.2.840.10008.1.1", transferSyntaxUIDs: ["1.2.840.10008.1.2"])]))
        await #expect(throws: DICOMAssociationError.notAssociated) { try await association.respondToCEcho(messageIDBeingRespondedTo: 45, contextID: 1, status: .success) }
        await #expect(throws: DICOMAssociationError.notAssociated) { try await association.respondToCFind(messageIDBeingRespondedTo: 45, contextID: 1, status: .success, identifier: nil) }
        await #expect(throws: DICOMAssociationError.notAssociated) { try await association.respondToCMove(messageIDBeingRespondedTo: 45, contextID: 1, status: .success, subOperations: nil) }
        await #expect(throws: DICOMAssociationError.notAssociated) { try await association.respondToCGet(messageIDBeingRespondedTo: 45, contextID: 1, status: .success, subOperations: nil) }
    }
}

/// Reads a single element's value from an encoded DIMSE command set by tag, to assert exact
/// wire bytes independent of the codec under test.
private func commandSetElementValue(tag: UInt32, in data: Data) -> Data? {
    var offset = 0
    while offset + 8 <= data.count {
        let elementTag = UInt32(data[offset]) | UInt32(data[offset + 1]) << 8 | UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
        let length = Int(UInt32(data[offset + 4]) | UInt32(data[offset + 5]) << 8 | UInt32(data[offset + 6]) << 16 | UInt32(data[offset + 7]) << 24)
        offset += 8
        guard offset + length <= data.count else { return nil }
        if elementTag == tag { return data.subdata(in: offset..<(offset + length)) }
        offset += length
    }
    return nil
}

private func commandSetUInt16(tag: UInt32, in data: Data) -> UInt16? {
    guard let value = commandSetElementValue(tag: tag, in: data), value.count == 2 else { return nil }
    return UInt16(value[0]) | UInt16(value[1]) << 8
}

/// Builds a raw Upper Layer sub-item / item (4-byte header: type, reserved, 2-byte BE length).
private func ulItem(_ type: UInt8, _ value: Data) -> Data {
    var data = Data([type, 0, UInt8(value.count >> 8), UInt8(value.count & 0xFF)])
    data.append(value)
    return data
}

private func ulUInt32(_ value: UInt32) -> Data {
    Data([UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)])
}

private func ulAETitle(_ value: String) -> Data {
    Data(value.utf8) + Data(repeating: 0x20, count: 16 - value.utf8.count)
}

/// Builds a complete, well-formed A-ASSOCIATE-RQ PDU with a caller-supplied User Information
/// item body, to simulate peers whose extended negotiation sub-items differ from DICOMKit's own.
private func rawAssociationRequestPDU(userInformation: Data) -> Data {
    var body = Data([0, 1, 0, 0])
    body.append(ulAETitle("PACS"))
    body.append(ulAETitle("DICOMKIT"))
    body.append(Data(repeating: 0, count: 32))
    body.append(ulItem(0x10, Data(DICOMAssociationRequest.dicomApplicationContextUID.utf8)))
    var context = Data([1, 0, 0, 0])
    context.append(ulItem(0x30, Data("1.2.840.10008.1.1".utf8)))
    context.append(ulItem(0x40, Data("1.2.840.10008.1.2".utf8)))
    body.append(ulItem(0x20, context))
    body.append(ulItem(0x50, userInformation))
    var pdu = Data([0x01, 0])
    pdu.append(ulUInt32(UInt32(body.count)))
    pdu.append(body)
    return pdu
}

/// Builds a complete, well-formed A-ASSOCIATE-AC PDU with a caller-supplied User Information
/// item body, to simulate peers whose extended negotiation sub-items differ from DICOMKit's own.
private func rawAssociationAcceptancePDU(userInformation: Data) -> Data {
    var body = Data([0, 1, 0, 0])
    body.append(ulAETitle("PACS"))
    body.append(ulAETitle("DICOMKIT"))
    body.append(Data(repeating: 0, count: 32))
    body.append(ulItem(0x10, Data(DICOMAssociationRequest.dicomApplicationContextUID.utf8)))
    var context = Data([1, 0, 0, 0])
    context.append(ulItem(0x40, Data("1.2.840.10008.1.2".utf8)))
    body.append(ulItem(0x21, context))
    body.append(ulItem(0x50, userInformation))
    var pdu = Data([0x02, 0])
    pdu.append(ulUInt32(UInt32(body.count)))
    pdu.append(body)
    return pdu
}

private actor DICOMULMockTransport: DICOMULTransport {
    var received: [DICOMULPDU]
    var sent: [DICOMULPDU] = []
    init(received: [DICOMULPDU]) { self.received = received }
    func send(_ pdu: DICOMULPDU) async throws { sent.append(pdu) }
    func receive() async throws -> DICOMULPDU { received.removeFirst() }
    func close() async {}
}

private actor DICOMULNeverRespondingTransport: DICOMULTransport {
    func send(_ pdu: DICOMULPDU) async throws {}
    func receive() async throws -> DICOMULPDU { try await Task.sleep(for: .seconds(60)); throw DICOMNetworkError.connectionClosed }
    func close() async {}
}

struct DICOMTagTests {
    @Test func tagHasCanonicalNotation() {
        #expect(DICOMTag.patientName.description == "(0010,0010)")
        #expect(DICOMTag(group: 0x7FE0, element: 0x0010) == .pixelData)
    }
}

struct DICOMElementValueTests {
    @Test func doubleValueParsesFirstComponentOfMultiValuedDS() {
        let element = DICOMElement(tag: .windowCenter, vr: .DS, value: Data("40\\400".utf8))

        #expect(element.doubleValue == 40)
        #expect(element.doubleValues == [40, 400])
    }

    @Test func decodesDatasetTextUsingSpecificCharacterSet() {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .specificCharacterSet, vr: .CS, value: Data("ISO_IR 100".utf8)),
            DICOMElement(tag: .patientName, vr: .PN, value: Data([0x4A, 0xF6, 0x72, 0x67]) )
        ])
        #expect(dataset.stringValue(for: .patientName) == "Jörg")
    }

    @Test func exposesMultiValuedUS() {
        let element = DICOMElement(tag: .rows, vr: .US, value: Data([1, 0, 2, 0]))
        #expect(element.uint16Values == [1, 2])
    }

    @Test func exposesBinaryNumericAndAttributeTagValues() {
        let signed = DICOMElement(tag: .pixelRepresentation, vr: .SL, value: Data([0xFF, 0xFF, 0xFF, 0xFF, 2, 0, 0, 0]))
        #expect(signed.int32Values == [-1, 2])

        let floating = DICOMElement(tag: .rescaleSlope, vr: .FD, value: Data([0, 0, 0, 0, 0, 0, 0xF0, 0x3F]))
        #expect(floating.float64Values == [1])

        let attributes = DICOMElement(tag: .pixelData, vr: .AT, value: Data([0x10, 0, 0x10, 0, 0x28, 0, 0x10, 0]))
        #expect(attributes.attributeTagValues == [.patientName, .rows])
    }

    @Test func parsesPersonNameAndDICOMDateTime() {
        let name = DICOMElement(tag: .patientName, vr: .PN, value: Data("Yamada^Taro=山田^太郎=やまだ^たろう".utf8))
        #expect(name.personNameValue == DICOMPersonName("Yamada^Taro=山田^太郎=やまだ^たろう"))

        let dateTime = DICOMElement(tag: DICOMTag(group: 0x0008, element: 0x002A), vr: .DT, value: Data("20260812093015.25+0900".utf8))
        #expect(dateTime.dateComponentsValue?.year == 2026)
        #expect(dateTime.dateComponentsValue?.nanosecond == 250_000_000)
        #expect(dateTime.dateComponentsValue?.timeZone?.secondsFromGMT() == 32_400)
    }

    @Test func generatesNumericUIDBelowOrganizationRoot() throws {
        let generator = try DICOMUIDGenerator(root: "1.2.826.0.1.3680043.10.543")
        let uid = generator.generate()
        #expect(uid.hasPrefix("1.2.826.0.1.3680043.10.543."))
        #expect(uid.count <= 64)
        #expect(uid.allSatisfy { $0.isNumber || $0 == "." })
        #expect(throws: DICOMError.invalidUIDRoot) { try DICOMUIDGenerator(root: "1.02.3") }
    }

    @Test func resolvesCommonImplicitVRDictionaryEntries() {
        #expect(DICOMDictionary.vr(for: DICOMTag(group: 0x0010, element: 0x0020)) == .LO) // Patient ID
        #expect(DICOMDictionary.vr(for: DICOMTag(group: 0x0008, element: 0x0060)) == .CS) // Modality
        #expect(DICOMDictionary.vr(for: DICOMTag(group: 0x0020, element: 0x000D)) == .UI) // Study UID
        #expect(DICOMDictionary.vr(for: DICOMTag(group: 0x5200, element: 0x9230)) == .SQ) // Per-frame FG
        #expect(DICOMDictionary.vr(for: DICOMTag(group: 0x0008, element: 0x1030)) == .LO) // Study Description
        #expect(DICOMDictionary.vr(for: DICOMTag(group: 0x0018, element: 0x0050)) == .DS) // Slice Thickness
        #expect(DICOMDictionary.vr(for: DICOMTag(group: 0x0020, element: 0x0032)) == .DS) // Image Position (Patient)
        #expect(DICOMDictionary.vr(for: DICOMTag(group: 0x0040, element: 0x0244)) == .DA) // Performed Procedure Step Start Date
        #expect(DICOMDictionary.vr(for: DICOMTag(group: 0x0054, element: 0x0016)) == .SQ) // Radiopharmaceutical Information Sequence
        #expect(DICOMDictionary.vr(for: DICOMTag(group: 0x0062, element: 0x0001)) == .CS) // Segmentation Type
    }

    @Test func doubleValueParsesNegativeNumber() {
        let element = DICOMElement(tag: .rescaleIntercept, vr: .DS, value: Data("-1024".utf8))

        #expect(element.doubleValue == -1024)
    }

    @Test func doubleValueReturnsNilForUnparsableValue() {
        let element = DICOMElement(tag: .rescaleIntercept, vr: .DS, value: Data("abc".utf8))

        #expect(element.doubleValue == nil)
    }

    @Test func int16ValueDecodesTwosComplementNegativeValue() {
        let element = DICOMElement(tag: DICOMTag(group: 0x0028, element: 0x0120), vr: .SS, value: Data([0x18, 0xFC]))

        #expect(element.int16Value == -1000)
    }

    @Test func int16ValueReturnsNilWhenValueIsTooShort() {
        let element = DICOMElement(tag: DICOMTag(group: 0x0028, element: 0x0120), vr: .SS, value: Data([0x18]))

        #expect(element.int16Value == nil)
    }
}

struct DICOMDatasetTests {
    @Test func exposesOverlayICCProfileAndPresentationLUT() throws {
        let overlayGroup: UInt16 = 0x6000
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: overlayGroup, element: 0x0010), vr: .US, value: uint16(2)),
            DICOMElement(tag: DICOMTag(group: overlayGroup, element: 0x0011), vr: .US, value: uint16(3)),
            DICOMElement(tag: DICOMTag(group: overlayGroup, element: 0x0050), vr: .SS, value: Data([0xFF, 0xFF, 2, 0])),
            DICOMElement(tag: DICOMTag(group: overlayGroup, element: 0x3000), vr: .OW, value: Data([0xA0])),
            DICOMElement(tag: DICOMTag(group: 0x0028, element: 0x2000), vr: .OB, value: Data([1, 2, 3])),
            DICOMElement(tag: DICOMTag(group: 0x2050, element: 0x0020), vr: .CS, value: Data("INVERSE".utf8))
        ])
        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))

        #expect(file.overlays == [DICOMOverlay(group: overlayGroup, rows: 2, columns: 3, origin: [-1, 2], data: Data([0xA0, 0]))])
        #expect(file.iccProfile == Data([1, 2, 3, 0]))
        #expect(file.presentationLUTShape == .inverse)
    }

    @Test func appliesBasicConfidentialityProfileWithStableUIDRemapping() {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .patientName, vr: .PN, value: Data("Doe^Jane".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0010, element: 0x0020), vr: .LO, value: Data("PAT-42".utf8)),
            DICOMElement(tag: .studyInstanceUID, vr: .UI, value: Data("1.2.3.4".utf8)),
            DICOMElement(tag: .seriesInstanceUID, vr: .UI, value: Data("1.2.3.4".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0008, element: 0x0050), vr: .SH, value: Data("ACC-9".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0010, element: 0x0030), vr: .DA, value: Data("19700101".utf8))
        ])

        let result = DICOMDeidentificationProfile.basicApplicationLevelConfidentiality().anonymize(dataset)

        #expect(result[.patientName]?.stringValue == "Anonymous")
        #expect(result[DICOMTag(group: 0x0010, element: 0x0020)]?.stringValue == "Anonymous")
        #expect(result[.studyInstanceUID]?.stringValue == result[.seriesInstanceUID]?.stringValue)
        #expect(result[.studyInstanceUID]?.stringValue?.hasPrefix("2.25.") == true)
        #expect(result[DICOMTag(group: 0x0008, element: 0x0050)] == nil)
        #expect(result[DICOMTag(group: 0x0010, element: 0x0030)] == nil)
    }

    @Test func validatesCommonCTImageIODRequirements() {
        let validator = DICOMIODValidator.ctImageStorage
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .sopClassUID, vr: .UI, value: Data("1.2.840.10008.5.1.4.1.1.2".utf8)),
            DICOMElement(tag: .sopInstanceUID, vr: .UI, value: Data("1.2.3".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0008, element: 0x0060), vr: .CS, value: Data("CT".utf8)),
            DICOMElement(tag: .patientName, vr: .PN, value: Data()),
            DICOMElement(tag: DICOMTag(group: 0x0010, element: 0x0020), vr: .LO, value: Data()),
            DICOMElement(tag: .studyInstanceUID, vr: .UI, value: Data("1.2.4".utf8)),
            DICOMElement(tag: .seriesInstanceUID, vr: .UI, value: Data("1.2.5".utf8)),
            DICOMElement(tag: .rows, vr: .US, value: uint16(1)),
            DICOMElement(tag: .columns, vr: .US, value: uint16(1)),
            DICOMElement(tag: .bitsAllocated, vr: .US, value: uint16(16)),
            DICOMElement(tag: .bitsStored, vr: .US, value: uint16(12)),
            DICOMElement(tag: .highBit, vr: .US, value: uint16(11)),
            DICOMElement(tag: .pixelRepresentation, vr: .US, value: uint16(0)),
            DICOMElement(tag: .pixelData, vr: .OW, value: uint16(0))
        ])

        #expect(validator.validate(dataset) == [])
    }

    @Test func validatesFileMetaSOPIdentifiersAgainstDataset() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .sopClassUID, vr: .UI, value: Data("1.2.3".utf8)),
            DICOMElement(tag: .sopInstanceUID, vr: .UI, value: Data("4.5.6".utf8))
        ])
        let metadata = DICOMFileMetaInformation(
            mediaStorageSOPClassUID: "1.2.3", mediaStorageSOPInstanceUID: "4.5.6",
            implementationClassUID: "1.2.826.0.1"
        )

        try metadata.validate(against: dataset)
    }

    @Test func resolvesDICOMJSONBulkDataOnlyThroughExplicitResolver() async throws {
        let uri = URL(string: "https://example.test/bulk/pixel-data")!
        let json = DICOMJSONDataset(elements: [
            "7FE00010": DICOMJSONElement(vr: .OW, bulkDataURI: uri.absoluteString)
        ])

        let dataset = try await json.dicomDataset(resolvingBulkDataWith: StaticBulkDataResolver(data: Data([1, 2, 3, 4])))

        #expect(dataset[.pixelData]?.value == Data([1, 2, 3, 4]))
    }

    @Test func readsDICOMDirectoryRecords() throws {
        let imageRecord = DICOMDataset(elements: [
            DICOMElement(tag: .directoryRecordType, vr: .CS, value: Data("IMAGE".utf8)),
            DICOMElement(tag: .referencedFileID, vr: .CS, value: Data("IMAGES\\0001".utf8)),
            DICOMElement(tag: .referencedSOPClassUIDInFile, vr: .UI, value: Data("1.2.840.10008.5.1.4.1.1.2".utf8)),
            DICOMElement(tag: .referencedSOPInstanceUIDInFile, vr: .UI, value: Data("1.2.3.4".utf8))
        ])
        let patientRecord = DICOMDataset(elements: [
            DICOMElement(tag: .directoryRecordType, vr: .CS, value: Data("PATIENT".utf8)),
            DICOMElement(tag: .offsetOfReferencedLowerLevelDirectoryEntity, vr: .UL, value: uint32(200))
        ])
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .offsetOfTheFirstDirectoryRecordOfTheRootDirectoryEntity, vr: .UL, value: uint32(100)),
            DICOMElement(tag: .directoryRecordSequence, vr: .SQ, value: Data(), sequenceItems: [patientRecord, imageRecord], sequenceItemOffsets: [100, 200])
        ])

        let directory = try DICOMDirectory(dataset: dataset)

        #expect(directory.records == [DICOMDirectoryRecord(recordType: "PATIENT", itemOffset: 100), DICOMDirectoryRecord(
            recordType: "IMAGE", referencedFileID: ["IMAGES", "0001"],
            referencedSOPClassUID: "1.2.840.10008.5.1.4.1.1.2", referencedSOPInstanceUID: "1.2.3.4", itemOffset: 200
        )])
        #expect(directory.rootRecords == [DICOMDirectoryNode(record: DICOMDirectoryRecord(recordType: "PATIENT", itemOffset: 100), children: [DICOMDirectoryNode(record: DICOMDirectoryRecord(
            recordType: "IMAGE", referencedFileID: ["IMAGES", "0001"],
            referencedSOPClassUID: "1.2.840.10008.5.1.4.1.1.2", referencedSOPInstanceUID: "1.2.3.4", itemOffset: 200
        ))])])
    }

    @Test func rejectsDICOMJSONWithNonTagTopLevelKey() {
        let json = Data("{\"not-a-tag\":{\"vr\":\"PN\"}}".utf8)

        #expect(throws: DICOMError.invalidDICOMJSON) {
            try JSONDecoder().decode(DICOMJSONDataset.self, from: json)
        }
    }

    @Test func validatesTypeOneAndTypeTwoModuleRequirements() {
        let validator = DICOMModuleValidator(requirements: [
            DICOMModuleRequirement(tag: .patientName, vr: .PN, requirement: .type1),
            DICOMModuleRequirement(tag: .studyInstanceUID, vr: .UI, requirement: .type1),
            DICOMModuleRequirement(tag: .sopInstanceUID, vr: .UI, requirement: .type2)
        ])
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .patientName, vr: .PN, value: Data()),
            DICOMElement(tag: .sopInstanceUID, vr: .LO, value: Data())
        ])

        #expect(validator.validate(dataset) == [
            DICOMValidationIssue(tag: .patientName, kind: .emptyRequiredElement),
            DICOMValidationIssue(tag: .studyInstanceUID, kind: .missingRequiredElement),
            DICOMValidationIssue(tag: .sopInstanceUID, kind: .unexpectedVR(expected: .UI, actual: .LO))
        ])
    }

    @Test func anonymizesNestedTagsAndPrivateElements() {
        let privateTag = DICOMTag(group: 0x0019, element: 0x1001)
        let nested = DICOMDataset(elements: [DICOMElement(tag: .patientName, vr: .PN, value: Data("Doe^Jane".utf8))])
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .patientName, vr: .PN, value: Data("Doe^Jane".utf8)),
            DICOMElement(tag: privateTag, vr: .LO, value: Data("secret".utf8)),
            DICOMElement(tag: .referencedStudySequence, vr: .SQ, value: Data(), sequenceItems: [nested])
        ])
        let anonymizer = DICOMAnonymizer(actions: [.patientName: .replace("Anonymous")])
        let result = anonymizer.anonymize(dataset)

        #expect(result[.patientName]?.stringValue == "Anonymous")
        #expect(result[privateTag] == nil)
        #expect(result[.referencedStudySequence]?.sequenceItems?.first?[.patientName]?.stringValue == "Anonymous")
    }
    @Test func groupsAndSortsStudyInstances() throws {
        func file(uid: String, instance: String, z: String) throws -> DICOMFile {
            try DICOMFile(data: DICOMWriter.write(dataset: DICOMDataset(elements: [
                DICOMElement(tag: .studyInstanceUID, vr: .UI, value: Data("1.2.3".utf8)),
                DICOMElement(tag: .seriesInstanceUID, vr: .UI, value: Data("4.5.6".utf8)),
                DICOMElement(tag: .sopInstanceUID, vr: .UI, value: Data(uid.utf8)),
                DICOMElement(tag: .instanceNumber, vr: .IS, value: Data(instance.utf8)),
                DICOMElement(tag: .imagePositionPatient, vr: .DS, value: Data("0\\0\\\(z)".utf8))
            ])))
        }
        let study = try DICOMStudy(studyInstanceUID: "1.2.3", files: [file(uid: "b", instance: "2", z: "10"), file(uid: "a", instance: "1", z: "0")])

        #expect(study.series.count == 1)
        #expect(study.series[0].instances.map(\.sopInstanceUID) == ["a", "b"])
    }
    @Test func convertsTypedDICOMJSONDatasets() throws {
        let nested = DICOMDataset(elements: [DICOMElement(tag: .referencedSOPClassUID, vr: .UI, value: Data("1.2.3".utf8))])
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .patientName, vr: .PN, value: Data("Doe^Jane".utf8)),
            DICOMElement(tag: .rows, vr: .US, value: uint16(512)),
            DICOMElement(tag: .referencedStudySequence, vr: .SQ, value: Data(), sequenceItems: [nested])
        ])
        let json = DICOMJSONDataset(dataset: dataset)

        #expect(json.elements["00100010"]?.value == [.personName(DICOMJSONPersonName(alphabetic: "Doe^Jane"))])
        #expect(json.elements["00280010"]?.value == [.number(512)])
        #expect(try json.dicomDataset() == dataset)
    }

    @Test func convertsAllJSONScalarVRFamiliesWithoutBinaryFallback() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0009, element: 0x1001), vr: .SS, value: Data([0xFE, 0xFF])),
            DICOMElement(tag: DICOMTag(group: 0x0009, element: 0x1002), vr: .UL, value: Data([0x78, 0x56, 0x34, 0x12])),
            DICOMElement(tag: DICOMTag(group: 0x0009, element: 0x1003), vr: .FL, value: Data([0x00, 0x00, 0xA0, 0x3F])),
            DICOMElement(tag: DICOMTag(group: 0x0009, element: 0x1004), vr: .AT, value: Data([0x10, 0x00, 0x10, 0x00])),
            DICOMElement(tag: DICOMTag(group: 0x0009, element: 0x1005), vr: .DS, value: Data("1.250".utf8))
        ])

        let json = DICOMJSONDataset(dataset: dataset)

        #expect(json.elements["00091001"]?.value == [.number(-2)])
        #expect(json.elements["00091002"]?.value == [.number(305_419_896)])
        #expect(json.elements["00091003"]?.value == [.number(1.25)])
        #expect(json.elements["00091004"]?.value == [.string("00100010")])
        #expect(json.elements["00091005"]?.value == [.string("1.250")])
        #expect(json.elements["00091001"]?.inlineBinary == nil)
        #expect(try json.dicomDataset() == dataset)
    }

    @Test func exposesImageGeometry() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .pixelSpacing, vr: .DS, value: Data("0.5\\0.75".utf8)),
            DICOMElement(tag: .pixelAspectRatio, vr: .IS, value: Data("4\\3".utf8)),
            DICOMElement(tag: .imagePositionPatient, vr: .DS, value: Data("1\\2\\3".utf8)),
            DICOMElement(tag: .imageOrientationPatient, vr: .DS, value: Data("1\\0\\0\\0\\1\\0".utf8))
        ])
        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))

        #expect(file.imageGeometry == DICOMImageGeometry(
            pixelSpacing: [0.5, 0.75], pixelAspectRatio: [4, 3],
            imagePositionPatient: [1, 2, 3], imageOrientationPatient: [1, 0, 0, 0, 1, 0]
        ))
    }

    @Test func resolvesPrivateCreatorAndPrivateElement() throws {
        let creatorTag = DICOMTag(group: 0x0019, element: 0x0010)
        let privateTag = DICOMTag(group: 0x0019, element: 0x1001)
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: creatorTag, vr: .LO, value: Data("ACME 1.0".utf8)),
            DICOMElement(tag: privateTag, vr: .DS, value: Data("42".utf8))
        ])

        #expect(dataset.privateCreator(for: privateTag) == "ACME 1.0")
        #expect(dataset.privateElement(creator: "ACME 1.0", group: 0x0019, element: 0x01)?.doubleValue == 42)
    }

    @Test func datasetInitRetainsLastElementForDuplicateTags() {
        let first = DICOMElement(tag: .patientName, vr: .PN, value: Data("Doe^Jane".utf8))
        let second = DICOMElement(tag: .patientName, vr: .PN, value: Data("Doe^John".utf8))

        let dataset = DICOMDataset(elements: [first, second])

        #expect(dataset[.patientName]?.stringValue == "Doe^John")
    }
}

struct DICOMVRTests {
    @Test func uses32BitLengthMatchesPS3_5ExtraLengthVRs() {
        // `explicitVR32BitLengthVRs` is the tests' own copy of the PS3.5 set,
        // hardcoded independently of the production switch this compares it
        // against (see its declaration).
        let actual = Set(DICOMVR.allCases.filter(\.uses32BitLength))

        #expect(actual == explicitVR32BitLengthVRs)
    }
}

private struct StaticBulkDataResolver: DICOMJSONBulkDataResolver {
    let data: Data

    func retrieveBulkData(uri: URL) async throws -> Data { data }
}
