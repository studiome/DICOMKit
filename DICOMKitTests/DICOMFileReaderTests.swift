import Foundation
import Testing
@testable import DICOMKit

struct DICOMFileReaderTests {
    @Test func readsExplicitVRBigEndianDataset() throws {
        var data = Data(repeating: 0, count: 128)
        data.append(Data("DICM".utf8))
        data.append(element(tag: .transferSyntaxUID, vr: .UI, value: TransferSyntax.explicitVRBigEndian.uid))
        data.append(bigEndianElement(tag: .patientName, vr: .PN, value: Data("Doe^Jane".utf8)))
        data.append(bigEndianElement(tag: .rows, vr: .US, value: Data([0x02, 0x00])))

        let file = try DICOMFile(data: data)

        #expect(file.transferSyntax == .explicitVRBigEndian)
        #expect(file.dataset[.patientName]?.stringValue == "Doe^Jane")
        #expect(file.dataset[.rows]?.uint16Value == 512)
    }

    @Test func readsDeflatedExplicitVRLittleEndianDataset() throws {
        let rawDataset = element(tag: .patientName, vr: .PN, value: "Doe^Jane")
        var data = Data(repeating: 0, count: 128)
        data.append(Data("DICM".utf8))
        data.append(element(tag: .transferSyntaxUID, vr: .UI, value: TransferSyntax.deflatedExplicitVRLittleEndian.uid))
        data.append(try DeflateCodec.deflateRaw(rawDataset))

        let file = try DICOMFile(data: data)

        #expect(file.transferSyntax == .deflatedExplicitVRLittleEndian)
        #expect(file.dataset[.patientName]?.stringValue == "Doe^Jane")
    }

    @Test func readsRawDatasetWithExplicitTransferSyntax() throws {
        let rawDataset = element(tag: .patientName, vr: .PN, value: "Doe^Jane") +
            element(tag: .rows, vr: .US, value: uint16(512))

        let file = try DICOMFile(datasetData: rawDataset, transferSyntax: .explicitVRLittleEndian)

        #expect(file.metaInformation.isEmpty)
        #expect(file.dataset[.patientName]?.stringValue == "Doe^Jane")
        #expect(file.dataset[.rows]?.uint16Value == 512)
    }

    @Test func readsExplicitVRLittleEndianPart10File() throws {
        let file = try DICOMFile(data: part10File(
            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid,
            datasetElements: [
                element(tag: .patientName, vr: .PN, value: "Doe^Jane"),
                element(tag: .rows, vr: .US, value: uint16(512)),
                element(tag: .columns, vr: .US, value: uint16(256))
            ]
        ))

        #expect(file.transferSyntax == .explicitVRLittleEndian)
        #expect(file.dataset[.patientName]?.stringValue == "Doe^Jane")
        #expect(file.dataset[.rows]?.uint16Value == 512)
        #expect(file.dataset[.columns]?.uint16Value == 256)
    }

    @Test func readsImplicitVRLittleEndianDatasetAndUndefinedLengthSequence() throws {
        let referencedSOPClassUID = "1.2.840.10008.5.1.4.1.1.2"
        let file = try DICOMFile(data: part10File(
            transferSyntaxUID: TransferSyntax.implicitVRLittleEndian.uid,
            datasetElements: [
                implicitElement(tag: .patientName, value: "Doe^Jane"),
                implicitUndefinedLengthSequence(
                    tag: .referencedStudySequence,
                    itemElements: [
                        implicitElement(tag: .referencedSOPClassUID, value: referencedSOPClassUID)
                    ]
                )
            ]
        ))

        #expect(file.transferSyntax == .implicitVRLittleEndian)
        #expect(file.dataset[.patientName]?.stringValue == "Doe^Jane")
        #expect(file.dataset[.referencedStudySequence]?.sequenceItems?.count == 1)
        #expect(file.dataset[.referencedStudySequence]?.sequenceItems?.first?[.referencedSOPClassUID]?.stringValue == referencedSOPClassUID)
    }

    @Test func readsDefinedLengthSequenceAtEndOfDataset() throws {
        let file = try DICOMFile(data: part10File(
            transferSyntaxUID: TransferSyntax.implicitVRLittleEndian.uid,
            datasetElements: [
                implicitDefinedLengthSequence(
                    tag: .referencedStudySequence,
                    itemElements: [implicitElement(tag: .referencedSOPClassUID, value: "1.2.840.10008.5.1.4.1.1.4")]
                )
            ]
        ))

        #expect(file.dataset[.referencedStudySequence]?.sequenceItems?.count == 1)
    }

    @Test func implicitVRTreatsUndefinedLengthUnregisteredTagAsSequence() throws {
        // (0008,1140) Referenced Image Sequence isn't in DICOMDictionary. In
        // Implicit VR, an unregistered tag with undefined length (0xFFFFFFFF)
        // must still be parsed as a sequence by convention.
        let referencedImageSequence = DICOMTag(group: 0x0008, element: 0x1140)
        let file = try DICOMFile(data: part10File(
            transferSyntaxUID: TransferSyntax.implicitVRLittleEndian.uid,
            datasetElements: [
                implicitUndefinedLengthSequence(
                    tag: referencedImageSequence,
                    itemElements: [implicitElement(tag: .referencedSOPClassUID, value: "1.2.840.10008.5.1.4.1.1.4")]
                )
            ]
        ))

        #expect(file.dataset[referencedImageSequence]?.vr == .SQ)
        #expect(file.dataset[referencedImageSequence]?.sequenceItems?.count == 1)
        #expect(file.dataset[referencedImageSequence]?.sequenceItems?.first?[.referencedSOPClassUID]?.stringValue == "1.2.840.10008.5.1.4.1.1.4")
    }

    @Test func explicitVRElementsAfterSVAndUVAreReadCorrectly() throws {
        let file = try DICOMFile(data: part10File(
            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid,
            datasetElements: [
                element(tag: DICOMTag(group: 0x0009, element: 0x0001), vr: .SV, value: Data(repeating: 0, count: 8)),
                element(tag: DICOMTag(group: 0x0009, element: 0x0002), vr: .UV, value: Data(repeating: 0, count: 8)),
                element(tag: .patientName, vr: .PN, value: "Doe^Jane")
            ]
        ))

        #expect(file.dataset[.patientName]?.stringValue == "Doe^Jane")
    }

    @Test func duplicateTagRetainsLastElementInsteadOfCrashing() throws {
        let file = try DICOMFile(data: part10File(
            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid,
            datasetElements: [
                element(tag: .patientName, vr: .PN, value: "Doe^Jane"),
                element(tag: .patientName, vr: .PN, value: "Doe^John")
            ]
        ))

        #expect(file.dataset[.patientName]?.stringValue == "Doe^John")
    }

    @Test func parsesDataSliceWithNonZeroStartIndex() throws {
        let fullFile = part10File(
            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid,
            datasetElements: [
                element(tag: .patientName, vr: .PN, value: "Doe^Jane"),
                element(tag: .rows, vr: .US, value: uint16(512))
            ]
        )
        var padded = Data(repeating: 0xAA, count: 500)
        padded.append(fullFile)
        let slice = padded[500...]
        #expect(slice.startIndex == 500)

        let file = try DICOMFile(data: slice)

        #expect(file.transferSyntax == .explicitVRLittleEndian)
        #expect(file.dataset[.patientName]?.stringValue == "Doe^Jane")
        #expect(file.dataset[.rows]?.uint16Value == 512)
    }

    @Test func recognizesJPEGBaselineTransferSyntax() throws {
        let file = try DICOMFile(data: part10File(
            transferSyntaxUID: TransferSyntax.jpegBaseline.uid,
            datasetElements: []
        ))

        #expect(file.transferSyntax == .jpegBaseline)
    }
}

private func bigEndianElement(tag: DICOMTag, vr: DICOMVR, value: Data) -> Data {
    var result = Data([
        UInt8(tag.group >> 8), UInt8(tag.group & 0xFF),
        UInt8(tag.element >> 8), UInt8(tag.element & 0xFF)
    ])
    result.append(Data(vr.rawValue.utf8))
    if vr.uses32BitLength {
        result.append(Data([0, 0, 0, 0]))
        let length = UInt32(value.count)
        result.append(Data([UInt8(length >> 24), UInt8(length >> 16), UInt8(length >> 8), UInt8(length & 0xFF)]))
    } else {
        let length = UInt16(value.count)
        result.append(Data([UInt8(length >> 8), UInt8(length & 0xFF)]))
    }
    result.append(value)
    return result
}

// MARK: - Malformed input

struct DICOMFileReaderErrorTests {
    @Test func rejectsDataWithoutPart10Preamble() {
        #expect(throws: DICOMError.missingPart10Preamble) {
            _ = try DICOMFile(data: Data())
        }
    }

    @Test func rejectsPart10DataWithoutTransferSyntaxUID() {
        var data = Data(repeating: 0, count: 128)
        data.append(contentsOf: "DICM".utf8)

        #expect(throws: DICOMError.missingTransferSyntaxUID) {
            _ = try DICOMFile(data: data)
        }
    }

    @Test func rejectsElementWhoseLengthExceedsRemainingData() {
        let data = part10File(
            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid,
            datasetElements: [
                explicitVRElement(tag: .patientName, vr: .PN, declaredLength: 100, value: Data("Doe".utf8))
            ]
        )

        #expect(throws: DICOMError.truncatedData) {
            _ = try DICOMFile(data: data)
        }
    }

    @Test func rejectsUndefinedLengthSequenceThatNeverCloses() {
        let data = part10File(
            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid,
            datasetElements: [
                explicitVRElement(tag: .referencedStudySequence, vr: .SQ, declaredLength: .max)
            ]
        )

        #expect(throws: DICOMError.truncatedData) {
            _ = try DICOMFile(data: data)
        }
    }

    @Test func rejectsUnrecognizedExplicitVRCode() {
        let data = part10File(
            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid,
            datasetElements: [
                explicitVRElementWithInvalidVR(tag: .patientName, vrText: "ZZ", length: 0)
            ]
        )

        #expect(throws: DICOMError.invalidVR("ZZ")) {
            _ = try DICOMFile(data: data)
        }
    }

    @Test func rejectsSequenceItemTagThatIsNeitherItemNorDelimiter() {
        let data = part10File(
            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid,
            datasetElements: [
                element(
                    tag: .referencedStudySequence,
                    vr: .SQ,
                    value: uint16(DICOMTag.patientName.group) + uint16(DICOMTag.patientName.element) + uint32(0)
                )
            ]
        )

        #expect(throws: DICOMError.invalidSequenceItem(.patientName)) {
            _ = try DICOMFile(data: data)
        }
    }

    @Test func acceptsExplicitVRBigEndianTransferSyntax() throws {
        let data = part10File(transferSyntaxUID: TransferSyntax.explicitVRBigEndian.uid, datasetElements: [])

        #expect(try DICOMFile(data: data).transferSyntax == .explicitVRBigEndian)
    }

    @Test func rejectsUnknownTransferSyntaxUID() {
        let unknownUID = "1.2.3.4.5.6.7.8.9"
        let data = part10File(transferSyntaxUID: unknownUID, datasetElements: [])

        #expect(throws: DICOMError.unsupportedTransferSyntax(unknownUID)) {
            _ = try DICOMFile(data: data)
        }
    }
}
