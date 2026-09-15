import Foundation
import Testing
@testable import DICOMKit
import DICOMKitAuthoring

/// Number of Frames `(0028,0008)` is attacker-controlled input: PS3.5 places
/// no ceiling on it, and several `DICOMFile` properties allocate one array
/// entry per frame before Pixel Data is even consulted. These tests guard
/// against a malformed or hostile file turning a short attribute into an
/// unbounded allocation or a trapping integer overflow.
struct DICOMFrameCountSafetyTests {
    private func datasetWithFrameCount(_ frameCount: String) throws -> Data {
        try DICOMWriter.write(dataset: DICOMDataset(elements: [
            DICOMElement(tag: .numberOfFrames, vr: .IS, value: Data(frameCount.utf8))
        ]))
    }

    @Test func frameFunctionalGroupsRejectsAnAstronomicalFrameCountInsteadOfAllocating() throws {
        let file = try DICOMFile(data: try datasetWithFrameCount("9223372036854775807"))

        #expect(file.frameFunctionalGroups.isEmpty)
        #expect(file.frameGeometries.isEmpty)
    }

    @Test func frameAttributesRejectsAnAstronomicalFrameCountInsteadOfAllocating() throws {
        let file = try DICOMFile(data: try datasetWithFrameCount("9223372036854775807"))

        #expect(file.frameAttributes.isEmpty)
    }

    @Test func frameFunctionalGroupsRejectsAFrameCountJustOverTheCap() throws {
        let file = try DICOMFile(data: try datasetWithFrameCount(String(DICOMFile.maxFrameCount + 1)))

        #expect(file.frameFunctionalGroups.isEmpty)
    }

    @Test func pixelDataFramesDoesNotTrapWhenByteMathWouldOverflow() throws {
        // Rows, Columns, and Samples per Pixel maxed out at their `US` range,
        // combined with a small frame count, makes `bytesPerFrame * frameCount`
        // overflow `Int` -- this must produce `nil`, not a runtime trap.
        let data = imageFile(
            samplesPerPixel: 65535,
            numberOfFrames: 5,
            rows: 65535,
            columns: 65535,
            bitsAllocated: 65528,
            pixelData: Data([0, 0])
        )
        let file = try DICOMFile(data: data)

        #expect(file.pixelDataFrames == nil)
    }

    @Test func floatingPixelDataFramesRejectsAnAstronomicalFrameCountInsteadOfAllocating() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .numberOfFrames, vr: .IS, value: Data("9223372036854775807".utf8)),
            DICOMElement(tag: .rows, vr: .US, value: uint16(1)),
            DICOMElement(tag: .columns, vr: .US, value: uint16(1)),
            DICOMElement(tag: .floatPixelData, vr: .OF, value: float32(1))
        ])
        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))

        #expect(file.floatingPixelDataFrames == nil)
    }
}
