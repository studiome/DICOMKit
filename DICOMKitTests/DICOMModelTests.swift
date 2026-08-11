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
