import Foundation
import Testing
@testable import DICOMKit

/// Covers `DICOMReadOptions.reinterpretsUnknownVR`: re-deriving a
/// defined-length `UN` element's VR from `DICOMDictionary` under Explicit VR
/// Little Endian, per PS3.5 6.2.2.
struct DICOMUnknownVRReinterpretationTests {
    @Test func reinterpretsUnknownVRForKnownPublicTagUnderExplicitVRLittleEndian() throws {
        let data = part10File(transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid, datasetElements: [
            element(tag: .rows, vr: .UN, value: uint16(512))
        ])

        let file = try DICOMFile(data: data)

        #expect(file.dataset[.rows]?.vr == .US)
        #expect(file.dataset[.rows]?.uint16Value == 512)
    }

    @Test func keepsUnknownVRForPrivateGroupTag() throws {
        let privateTag = DICOMTag(group: 0x0009, element: 0x1001)
        let data = part10File(transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid, datasetElements: [
            element(tag: privateTag, vr: .UN, value: Data([0x01, 0x02]))
        ])

        let file = try DICOMFile(data: data)

        #expect(file.dataset[privateTag]?.vr == .UN)
    }

    @Test func keepsUnknownVRForTagAbsentFromDictionary() throws {
        let unknownTag = DICOMTag(group: 0x0008, element: 0x9999)
        let data = part10File(transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid, datasetElements: [
            element(tag: unknownTag, vr: .UN, value: Data([0x01, 0x02]))
        ])

        let file = try DICOMFile(data: data)

        #expect(file.dataset[unknownTag]?.vr == .UN)
    }

    @Test func keepsUnknownVRForPixelData() throws {
        let data = part10File(transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid, datasetElements: [
            element(tag: .pixelData, vr: .UN, value: Data([0x01, 0x02]))
        ])

        let file = try DICOMFile(data: data)

        #expect(file.dataset[.pixelData]?.vr == .UN)
    }

    @Test func keepsUnknownVRUnderExplicitVRBigEndian() throws {
        var data = Data(repeating: 0, count: 128)
        data.append(Data("DICM".utf8))
        data.append(element(tag: .transferSyntaxUID, vr: .UI, value: TransferSyntax.explicitVRBigEndian.uid))
        data.append(bigEndianUNElement(tag: .rows, value: Data([0x02, 0x00])))

        let file = try DICOMFile(data: data)

        #expect(file.transferSyntax == .explicitVRBigEndian)
        #expect(file.dataset[.rows]?.vr == .UN)
    }

    @Test func disablingReinterpretsUnknownVRKeepsUN() throws {
        let data = part10File(transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid, datasetElements: [
            element(tag: .rows, vr: .UN, value: uint16(512))
        ])

        let file = try DICOMFile(data: data, options: DICOMReadOptions(reinterpretsUnknownVR: false))

        #expect(file.dataset[.rows]?.vr == .UN)
    }
}

/// Builds a raw Explicit VR Big Endian `UN` element. `UN`'s 2-byte VR code
/// and 4-byte length always use the enclosing dataset's byte order for the
/// header, but this helper only needs to exercise the header path since the
/// re-interpretation restriction under test is about the *value* bytes.
private func bigEndianUNElement(tag: DICOMTag, value: Data) -> Data {
    var result = Data([
        UInt8(tag.group >> 8), UInt8(tag.group & 0xFF),
        UInt8(tag.element >> 8), UInt8(tag.element & 0xFF)
    ])
    result.append(Data("UN".utf8))
    result.append(Data([0, 0]))
    let length = UInt32(value.count)
    result.append(Data([UInt8(length >> 24), UInt8(length >> 16), UInt8(length >> 8), UInt8(length & 0xFF)]))
    result.append(value)
    return result
}
