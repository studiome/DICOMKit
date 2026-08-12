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
            .pData(try DICOMDIMSECommand.cEchoResponse(messageIDBeingRespondedTo: 9, status: 0).commandPDVs(contextID: 1, maximumPayloadLength: 1024))
        ])
        let association = DICOMAssociation(transport: transport)
        _ = try await association.request(DICOMAssociationRequest(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, abstractSyntaxUID: "1.2.840.10008.1.1", transferSyntaxUIDs: ["1.2.840.10008.1.2"])]))
        #expect(try await association.cEcho(messageID: 9, contextID: 1) == 0)
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
            .pData(try DICOMDIMSECommand.cStoreResponse(messageIDBeingRespondedTo: 12, status: 0).commandPDVs(contextID: 1, maximumPayloadLength: 1024))
        ])
        let association = DICOMAssociation(transport: transport)
        _ = try await association.request(DICOMAssociationRequest(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, abstractSyntaxUID: "1.2.840.10008.5.1.4.1.1.2", transferSyntaxUIDs: ["1.2.840.10008.1.2"])]))
        let status = try await association.cStore(messageID: 12, contextID: 1, sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3", dataset: Data([1, 2, 3]))
        #expect(status == 0)
        #expect(await transport.sent.count == 3)
    }

    @Test func encodesAndDecodesCFindRequest() throws {
        let request = DICOMDIMSECommand.cFindRequest(messageID: 13, affectedSOPClassUID: "1.2.840.10008.5.1.4.1.2.2.1")
        #expect(try DICOMDIMSECommand.decodeCommandSet(request.encodedCommandSet()) == request)
    }

    @Test func associationCollectsCFindResponses() async throws {
        let transport = DICOMULMockTransport(received: [
            .associationAcceptance(DICOMAssociationAcceptance(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, result: .acceptance, transferSyntaxUID: "1.2.840.10008.1.2")])),
            .pData(try DICOMDIMSECommand.cFindResponse(messageIDBeingRespondedTo: 14, status: 0xFF00).commandPDVs(contextID: 1, maximumPayloadLength: 1024)),
            .pData([DICOMPDataValue(contextID: 1, isCommand: false, isLastFragment: true, data: Data([4, 5]))]),
            .pData(try DICOMDIMSECommand.cFindResponse(messageIDBeingRespondedTo: 14, status: 0).commandPDVs(contextID: 1, maximumPayloadLength: 1024))
        ])
        let association = DICOMAssociation(transport: transport)
        _ = try await association.request(DICOMAssociationRequest(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, abstractSyntaxUID: "1.2.840.10008.5.1.4.1.2.2.1", transferSyntaxUIDs: ["1.2.840.10008.1.2"])]))
        let result = try await association.cFind(messageID: 14, contextID: 1, sopClassUID: "1.2.840.10008.5.1.4.1.2.2.1", identifier: Data([1]))
        #expect(result.status == 0)
        #expect(result.identifiers == [Data([4, 5])])
    }

    @Test func encodesAndDecodesCMoveRequest() throws {
        let request = DICOMDIMSECommand.cMoveRequest(messageID: 15, affectedSOPClassUID: "1.2.840.10008.5.1.4.1.2.2.2", moveDestination: "STORE-SCP")
        #expect(try DICOMDIMSECommand.decodeCommandSet(request.encodedCommandSet()) == request)
    }

    @Test func associationPerformsCMove() async throws {
        let transport = DICOMULMockTransport(received: [
            .associationAcceptance(DICOMAssociationAcceptance(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, result: .acceptance, transferSyntaxUID: "1.2.840.10008.1.2")])),
            .pData(try DICOMDIMSECommand.cMoveResponse(messageIDBeingRespondedTo: 16, status: 0).commandPDVs(contextID: 1, maximumPayloadLength: 1024))
        ])
        let association = DICOMAssociation(transport: transport)
        _ = try await association.request(DICOMAssociationRequest(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, abstractSyntaxUID: "1.2.840.10008.5.1.4.1.2.2.2", transferSyntaxUIDs: ["1.2.840.10008.1.2"])]))
        #expect(try await association.cMove(messageID: 16, contextID: 1, sopClassUID: "1.2.840.10008.5.1.4.1.2.2.2", destination: "STORE-SCP", identifier: Data()) == 0)
    }

    @Test func encodesAndDecodesCGetRequest() throws {
        let request = DICOMDIMSECommand.cGetRequest(messageID: 17, affectedSOPClassUID: "1.2.840.10008.5.1.4.1.2.2.3")
        #expect(try DICOMDIMSECommand.decodeCommandSet(request.encodedCommandSet()) == request)
    }

    @Test func associationPerformsCGet() async throws {
        let transport = DICOMULMockTransport(received: [
            .associationAcceptance(DICOMAssociationAcceptance(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, result: .acceptance, transferSyntaxUID: "1.2.840.10008.1.2")])),
            .pData(try DICOMDIMSECommand.cGetResponse(messageIDBeingRespondedTo: 18, status: 0).commandPDVs(contextID: 1, maximumPayloadLength: 1024))
        ])
        let association = DICOMAssociation(transport: transport)
        _ = try await association.request(DICOMAssociationRequest(calledAETitle: "PACS", callingAETitle: "DICOMKIT", presentationContexts: [.init(id: 1, abstractSyntaxUID: "1.2.840.10008.5.1.4.1.2.2.3", transferSyntaxUIDs: ["1.2.840.10008.1.2"])]))
        #expect(try await association.cGet(messageID: 18, contextID: 1, sopClassUID: "1.2.840.10008.5.1.4.1.2.2.3", identifier: Data()) == 0)
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
        try await association.respond(to: received, status: 0)
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
