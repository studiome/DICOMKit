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
}
