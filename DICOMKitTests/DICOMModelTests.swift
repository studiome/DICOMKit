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
