import Foundation
import Testing
@testable import DICOMKit

/// Covers resolving a private element's VR from `options.privateDictionary`
/// while reading an Implicit VR dataset, using the Private Creator recorded
/// earlier in the same dataset (or sequence item).
struct DICOMPrivateVRResolutionTests {
    private static let creatorTag = DICOMTag(group: 0x0009, element: 0x0010)
    private static let dataTag = DICOMTag(group: 0x0009, element: 0x1001)

    private static func makeDictionary() throws -> DICOMPrivateDictionary {
        try DICOMPrivateDictionary([
            DICOMPrivateTagEntry(privateCreator: "ACME", group: 0x0009, elementLowByte: 0x01, vr: .DS, name: "Acme Value")
        ])
    }

    @Test func resolvesPrivateVRFromDictionaryUnderImplicitVR() throws {
        let dictionary = try Self.makeDictionary()
        let datasetData = implicitElement(tag: Self.creatorTag, value: "ACME") + implicitElement(tag: Self.dataTag, value: "3.14")

        let file = try DICOMFile(
            datasetData: datasetData,
            transferSyntax: .implicitVRLittleEndian,
            options: DICOMReadOptions(privateDictionary: dictionary)
        )

        #expect(file.dataset[Self.dataTag]?.vr == .DS)
        #expect(file.dataset[Self.dataTag]?.doubleValue == 3.14)
    }

    @Test func keepsUnknownVRForPrivateElementWithoutDictionary() throws {
        let datasetData = implicitElement(tag: Self.creatorTag, value: "ACME") + implicitElement(tag: Self.dataTag, value: "3.14")

        let file = try DICOMFile(datasetData: datasetData, transferSyntax: .implicitVRLittleEndian)

        #expect(file.dataset[Self.dataTag]?.vr == .UN)
    }

    @Test func keepsUnknownVRWhenBlockHasNoRecordedCreator() throws {
        let dictionary = try Self.makeDictionary()
        // No Private Creator element for group 0009 block 0x10 precedes this.
        let datasetData = implicitElement(tag: Self.dataTag, value: "3.14")

        let file = try DICOMFile(
            datasetData: datasetData,
            transferSyntax: .implicitVRLittleEndian,
            options: DICOMReadOptions(privateDictionary: dictionary)
        )

        #expect(file.dataset[Self.dataTag]?.vr == .UN)
    }

    @Test func doesNotLeakParentPrivateCreatorIntoSequenceItem() throws {
        let dictionary = try Self.makeDictionary()
        let itemElement = implicitElement(tag: Self.dataTag, value: "3.14")
        let datasetData = implicitElement(tag: Self.creatorTag, value: "ACME")
            + implicitDefinedLengthSequence(tag: .referencedStudySequence, itemElements: [itemElement])

        let file = try DICOMFile(
            datasetData: datasetData,
            transferSyntax: .implicitVRLittleEndian,
            options: DICOMReadOptions(privateDictionary: dictionary)
        )

        let itemDataset = try #require(file.dataset[.referencedStudySequence]?.sequenceItems?.first)
        #expect(itemDataset[Self.dataTag]?.vr == .UN)
    }

    @Test func keepsWireVRForExplicitVRPrivateElementsRegardlessOfDictionary() throws {
        let dictionary = try Self.makeDictionary()
        let data = part10File(transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid, datasetElements: [
            element(tag: Self.creatorTag, vr: .LO, value: "ACME"),
            element(tag: Self.dataTag, vr: .SH, value: "hello")
        ])

        let file = try DICOMFile(data: data, options: DICOMReadOptions(privateDictionary: dictionary))

        #expect(file.dataset[Self.dataTag]?.vr == .SH)
        #expect(file.dataset[Self.dataTag]?.stringValue == "hello")
    }
}
