import Foundation
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

    @Test func rejectsDataWithoutPart10Preamble() {
        #expect(throws: DICOMError.self) {
            _ = try DICOMFile(data: Data())
        }
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
    data.append(uint16(UInt16(value.count)))
    data.append(value)
    return data
}

private func uint16(_ value: UInt16) -> Data {
    Data([UInt8(value & 0xFF), UInt8(value >> 8)])
}
