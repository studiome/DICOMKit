import Foundation
import Testing
@testable import DICOMKit

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
    @Test func readsDICOMDirectoryRecords() throws {
        let record = DICOMDataset(elements: [
            DICOMElement(tag: .directoryRecordType, vr: .CS, value: Data("IMAGE".utf8)),
            DICOMElement(tag: .referencedFileID, vr: .CS, value: Data("IMAGES\\0001".utf8)),
            DICOMElement(tag: .referencedSOPClassUIDInFile, vr: .UI, value: Data("1.2.840.10008.5.1.4.1.1.2".utf8)),
            DICOMElement(tag: .referencedSOPInstanceUIDInFile, vr: .UI, value: Data("1.2.3.4".utf8))
        ])
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .directoryRecordSequence, vr: .SQ, value: Data(), sequenceItems: [record])
        ])

        let directory = try DICOMDirectory(dataset: dataset)

        #expect(directory.records == [DICOMDirectoryRecord(
            recordType: "IMAGE", referencedFileID: ["IMAGES", "0001"],
            referencedSOPClassUID: "1.2.840.10008.5.1.4.1.1.2", referencedSOPInstanceUID: "1.2.3.4"
        )])
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
