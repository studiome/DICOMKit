import Foundation
import Testing
@testable import DICOMKit

struct DICOMWriterTests {
    @Test func writesExplicitVRLittleEndianPart10File() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .patientName, vr: .PN, value: Data("Doe^Jane".utf8)),
            DICOMElement(tag: .rows, vr: .US, value: uint16(2)),
            DICOMElement(tag: .columns, vr: .US, value: uint16(3))
        ])

        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))

        #expect(file.transferSyntax == .explicitVRLittleEndian)
        #expect(file.dataset == dataset)
    }

    @Test func writesRequiredFileMetaInformation() throws {
        let meta = DICOMFileMetaInformation(
            mediaStorageSOPClassUID: "1.2.840.10008.5.1.4.1.1.2",
            mediaStorageSOPInstanceUID: "1.2.3.4",
            implementationClassUID: "1.2.826.0.1.3680043.10.543.1",
            implementationVersionName: "DICOMKIT_1"
        )
        let file = try DICOMFile(data: DICOMWriter.write(dataset: DICOMDataset(), requiredMetaInformation: meta))
        #expect(file.metaInformation[.mediaStorageSOPClassUID]?.stringValue == meta.mediaStorageSOPClassUID)
        #expect(file.metaInformation[.mediaStorageSOPInstanceUID]?.stringValue == meta.mediaStorageSOPInstanceUID)
        #expect(file.metaInformation[.implementationClassUID]?.stringValue == meta.implementationClassUID)
        #expect(file.metaInformation[.implementationVersionName]?.stringValue == meta.implementationVersionName)
        #expect(file.metaInformation[DICOMTag(group: 0x0002, element: 0x0001)]?.value == Data([0, 1]))
        #expect(file.metaInformation[DICOMTag(group: 0x0002, element: 0x0000)]?.uint32Values?.first != nil)
    }

    @Test func derivesRequiredFileMetaInformationFromDataset() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .sopClassUID, vr: .UI, value: Data("1.2.840.10008.5.1.4.1.1.2".utf8)),
            DICOMElement(tag: .sopInstanceUID, vr: .UI, value: Data("1.2.3.4".utf8))
        ])
        let meta = try DICOMFileMetaInformation(dataset: dataset, implementationClassUID: "1.2.826.0.1.3680043.10.543.1")

        #expect(meta.mediaStorageSOPClassUID == "1.2.840.10008.5.1.4.1.1.2")
        #expect(meta.mediaStorageSOPInstanceUID == "1.2.3.4")
    }

    @Test func writesDefinedLengthSequence() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(
                tag: .referencedStudySequence,
                vr: .SQ,
                value: Data(),
                sequenceItems: [DICOMDataset(elements: [
                    DICOMElement(tag: .referencedSOPClassUID, vr: .UI, value: Data("1.2.840.10008.5.1.4.1.1.2".utf8))
                ])]
            )
        ])

        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))

        let items = try #require(file.dataset[.referencedStudySequence]?.sequenceItems)
        #expect(items.count == 1)
        #expect(items[0][.referencedSOPClassUID]?.stringValue == "1.2.840.10008.5.1.4.1.1.2")
    }

    @Test func writesImplicitVRLittleEndianPart10File() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .patientName, vr: .PN, value: Data("Doe^Jane".utf8)),
            DICOMElement(tag: .rows, vr: .US, value: uint16(2))
        ])

        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset, transferSyntax: .implicitVRLittleEndian))

        #expect(file.transferSyntax == .implicitVRLittleEndian)
        #expect(file.dataset == dataset)
    }

    @Test func writesDeflatedExplicitVRLittleEndianPart10File() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .patientName, vr: .PN, value: Data("Doe^Jane".utf8)),
            DICOMElement(tag: .rows, vr: .US, value: uint16(2))
        ])

        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset, transferSyntax: .deflatedExplicitVRLittleEndian))

        #expect(file.transferSyntax == .deflatedExplicitVRLittleEndian)
        #expect(file.dataset == dataset)
    }

    @Test func writesExplicitVRBigEndianPart10File() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .patientName, vr: .PN, value: Data("Doe^Jane".utf8)),
            DICOMElement(tag: .rows, vr: .US, value: uint16(512))
        ])

        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset, transferSyntax: .explicitVRBigEndian))

        #expect(file.transferSyntax == .explicitVRBigEndian)
        #expect(file.dataset == dataset)
    }

    @Test func writesNativePixelData() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .rows, vr: .US, value: uint16(1)),
            DICOMElement(tag: .columns, vr: .US, value: uint16(2)),
            DICOMElement(tag: .samplesPerPixel, vr: .US, value: uint16(1)),
            DICOMElement(tag: .photometricInterpretation, vr: .CS, value: Data("MONOCHROME2".utf8)),
            DICOMElement(tag: .bitsAllocated, vr: .US, value: uint16(8)),
            DICOMElement(tag: .pixelData, vr: .OB, value: Data([10, 20]))
        ])

        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))

        #expect(file.pixelData?.value == Data([10, 20]))
    }

    @Test func writesEncapsulatedPixelDataWithGeneratedBasicOffsetTable() throws {
        let firstFrame = rleFrame(segment: Data([0x00, 0x12]))
        let secondFrame = rleFrame(segment: Data([0x00, 0x34]))
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .rows, vr: .US, value: uint16(1)),
            DICOMElement(tag: .columns, vr: .US, value: uint16(1)),
            DICOMElement(tag: .samplesPerPixel, vr: .US, value: uint16(1)),
            DICOMElement(tag: .numberOfFrames, vr: .IS, value: Data("2".utf8)),
            DICOMElement(tag: .photometricInterpretation, vr: .CS, value: Data("MONOCHROME2".utf8)),
            DICOMElement(tag: .bitsAllocated, vr: .US, value: uint16(8)),
            try DICOMElement(encapsulatedPixelDataFrames: [[firstFrame], [secondFrame]])
        ])

        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset, transferSyntax: .rleLossless))
        let frames = try #require(file.pixelDataFrames)

        #expect(frames.map(\.value) == [Data([0x12]), Data([0x34])])
        #expect(file.dataset[.pixelData]?.basicOffsetTable == uint32(0) + uint32(74))
    }

    @Test func rejectsNativePixelDataForEncapsulatedTransferSyntax() {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .pixelData, vr: .OB, value: Data([10, 20]))
        ])

        #expect(throws: DICOMError.invalidEncapsulatedPixelData) {
            _ = try DICOMWriter.write(dataset: dataset, transferSyntax: .rleLossless)
        }
    }

    @Test func writesUndefinedLengthSequenceAndDICOMFileConvenienceAPI() throws {
        let dataset = DICOMDataset(elements: [DICOMElement(tag: .referencedStudySequence, vr: .SQ, value: Data(), sequenceItems: [DICOMDataset(elements: [DICOMElement(tag: .patientName, vr: .PN, value: Data("Doe^Jane".utf8))])])])
        let original = try DICOMFile(data: DICOMWriter.write(dataset: dataset))
        let reread = try DICOMFile(data: original.encodedData(sequenceLengthEncoding: .undefined))

        #expect(reread.dataset[.referencedStudySequence]?.sequenceItems?.first?[.patientName]?.stringValue == "Doe^Jane")
    }
}
