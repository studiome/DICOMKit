import Foundation
import CoreGraphics
import Testing
@testable import DICOMKit

struct DICOMKitTests {
    @Test func tagHasCanonicalNotation() {
        #expect(DICOMTag.patientName.description == "(0010,0010)")
        #expect(DICOMTag(group: 0x7FE0, element: 0x0010) == .pixelData)
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

    @Test func readsPydicomExplicitVRLittleEndianCTFixture() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/CT_small.dcm")

        let file = try DICOMFile(data: Data(contentsOf: fixtureURL))

        #expect(file.transferSyntax == .explicitVRLittleEndian)
        #expect(file.dataset[.rows]?.uint16Value == 128)
        #expect(file.dataset[.columns]?.uint16Value == 128)
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

    @Test func rejectsDataWithoutPart10Preamble() {
        #expect(throws: DICOMError.self) {
            _ = try DICOMFile(data: Data())
        }
    }

    @Test func renders8BitMonochromePixelData() throws {
        let file = try DICOMFile(data: part10File(
            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid,
            datasetElements: [
                element(tag: DICOMTag(group: 0x0028, element: 0x0002), vr: .US, value: uint16(1)),
                element(tag: DICOMTag(group: 0x0028, element: 0x0004), vr: .CS, value: "MONOCHROME2"),
                element(tag: .rows, vr: .US, value: uint16(2)),
                element(tag: .columns, vr: .US, value: uint16(2)),
                element(tag: DICOMTag(group: 0x0028, element: 0x0100), vr: .US, value: uint16(8)),
                element(tag: .pixelData, vr: .OB, value: Data([0, 64, 128, 255]))
            ]
        ))

        let image = try #require(file.pixelData).cgImage()

        #expect(image.width == 2)
        #expect(image.height == 2)
        #expect(image.bitsPerComponent == 8)
        #expect(imageBytes(image) == Data([0, 64, 128, 255]))
    }

    @Test func rendersInterleavedRGBPixelData() throws {
        let file = try DICOMFile(data: part10File(
            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid,
            datasetElements: [
                element(tag: DICOMTag(group: 0x0028, element: 0x0002), vr: .US, value: uint16(3)),
                element(tag: DICOMTag(group: 0x0028, element: 0x0004), vr: .CS, value: "RGB"),
                element(tag: DICOMTag(group: 0x0028, element: 0x0006), vr: .US, value: uint16(0)),
                element(tag: .rows, vr: .US, value: uint16(1)),
                element(tag: .columns, vr: .US, value: uint16(2)),
                element(tag: DICOMTag(group: 0x0028, element: 0x0100), vr: .US, value: uint16(8)),
                element(tag: .pixelData, vr: .OB, value: Data([255, 0, 0, 0, 255, 0]))
            ]
        ))

        let image = try #require(file.pixelData).cgImage()

        #expect(image.width == 2)
        #expect(image.height == 1)
        #expect(imageBytes(image) == Data([255, 0, 0, 0, 255, 0]))
    }

    @Test func appliesWindowLevelTo16BitMonochromePixelData() throws {
        let file = try DICOMFile(data: part10File(
            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid,
            datasetElements: [
                element(tag: DICOMTag(group: 0x0028, element: 0x0002), vr: .US, value: uint16(1)),
                element(tag: DICOMTag(group: 0x0028, element: 0x0004), vr: .CS, value: "MONOCHROME2"),
                element(tag: .rows, vr: .US, value: uint16(1)),
                element(tag: .columns, vr: .US, value: uint16(2)),
                element(tag: DICOMTag(group: 0x0028, element: 0x0100), vr: .US, value: uint16(16)),
                element(tag: .pixelData, vr: .OW, value: uint16(0) + uint16(1_000))
            ]
        ))

        let image = try #require(file.pixelData).cgImage(windowCenter: 500, windowWidth: 1_000)

        #expect(imageBytes(image) == Data([0, 255]))
    }
}

private func part10File(transferSyntaxUID: String, datasetElements: [Data]) -> Data {
    var data = Data(repeating: 0, count: 128)
    data.append(contentsOf: "DICM".utf8)
    data.append(element(tag: DICOMTag(group: 0x0002, element: 0x0010), vr: .UI, value: transferSyntaxUID))
    for item in datasetElements { data.append(item) }
    return data
}

private func element(tag: DICOMTag, vr: DICOMVR, value: String) -> Data {
    var encoded = Data(value.utf8)
    if encoded.count.isMultiple(of: 2) == false { encoded.append(0) }
    return element(tag: tag, vr: vr, value: encoded)
}

private func element(tag: DICOMTag, vr: DICOMVR, value: Data) -> Data {
    var data = uint16(tag.group)
    data.append(uint16(tag.element))
    data.append(contentsOf: vr.rawValue.utf8)
    if vr.uses32BitLength {
        data.append(uint16(0))
        data.append(uint32(UInt32(value.count)))
    } else {
        data.append(uint16(UInt16(value.count)))
    }
    data.append(value)
    return data
}

private func implicitElement(tag: DICOMTag, value: String) -> Data {
    var encoded = Data(value.utf8)
    if encoded.count.isMultiple(of: 2) == false { encoded.append(0) }
    return implicitElement(tag: tag, value: encoded)
}

private func implicitElement(tag: DICOMTag, value: Data) -> Data {
    var data = uint16(tag.group)
    data.append(uint16(tag.element))
    data.append(uint32(UInt32(value.count)))
    data.append(value)
    return data
}

private func implicitUndefinedLengthSequence(tag: DICOMTag, itemElements: [Data]) -> Data {
    var data = uint16(tag.group)
    data.append(uint16(tag.element))
    data.append(uint32(.max))
    data.append(uint16(0xFFFE))
    data.append(uint16(0xE000))
    let item = itemElements.reduce(into: Data()) { $0.append($1) }
    data.append(uint32(UInt32(item.count)))
    data.append(item)
    data.append(uint16(0xFFFE))
    data.append(uint16(0xE0DD))
    data.append(uint32(0))
    return data
}

private func implicitDefinedLengthSequence(tag: DICOMTag, itemElements: [Data]) -> Data {
    let item = itemElements.reduce(into: Data()) { $0.append($1) }
    var sequence = uint16(0xFFFE)
    sequence.append(uint16(0xE000))
    sequence.append(uint32(UInt32(item.count)))
    sequence.append(item)

    var data = uint16(tag.group)
    data.append(uint16(tag.element))
    data.append(uint32(UInt32(sequence.count)))
    data.append(sequence)
    return data
}

private func uint16(_ value: UInt16) -> Data {
    Data([UInt8(value & 0xFF), UInt8(value >> 8)])
}

private func uint32(_ value: UInt32) -> Data {
    Data([
        UInt8(value & 0xFF),
        UInt8((value >> 8) & 0xFF),
        UInt8((value >> 16) & 0xFF),
        UInt8((value >> 24) & 0xFF)
    ])
}

private func imageBytes(_ image: CGImage) -> Data {
    Data(image.dataProvider!.data! as Data)
}
