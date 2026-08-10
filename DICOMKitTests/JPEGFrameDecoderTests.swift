import CoreGraphics
import Foundation
import Testing
@testable import DICOMKit

struct JPEGFrameDecoderTests {
    @Test func decodesSingleFrameJPEGBaselinePixelData() throws {
        let data = imageFile(
            transferSyntaxUID: TransferSyntax.jpegBaseline.uid,
            samplesPerPixel: 3,
            photometricInterpretation: .rgb,
            planarConfiguration: 0,
            rows: 2,
            columns: 2,
            bitsAllocated: 8,
            pixelDataElement: encapsulatedPixelData(fragments: [jpegData(
                rgb: Data([255, 0, 0, 255, 0, 0, 255, 0, 0, 255, 0, 0]),
                width: 2,
                height: 2
            )])
        )

        let image = try #require(try DICOMFile(data: data).pixelData).cgImage()
        let bytes = try imageBytes(image)

        #expect(image.width == 2)
        #expect(image.height == 2)
        #expect(bytes.count == 12)
        #expect(bytes[0] > 200)
        #expect(bytes[1] < 50)
        #expect(bytes[2] < 50)
    }

    @Test func decodesMultiFrameJPEGBaselinePixelDataUsingBasicOffsetTable() throws {
        let firstFrame = jpegData(
            rgb: Data([255, 0, 0]),
            width: 1,
            height: 1
        )
        let secondFrame = jpegData(
            rgb: Data([0, 255, 0]),
            width: 1,
            height: 1
        )
        let secondFrameOffset = 8 + ((firstFrame.count + 1) / 2 * 2)
        let data = imageFile(
            transferSyntaxUID: TransferSyntax.jpegBaseline.uid,
            samplesPerPixel: 3,
            photometricInterpretation: .rgb,
            planarConfiguration: 0,
            numberOfFrames: 2,
            rows: 1,
            columns: 1,
            bitsAllocated: 8,
            pixelDataElement: encapsulatedPixelData(
                basicOffsetTable: uint32(0) + uint32(UInt32(secondFrameOffset)),
                fragments: [firstFrame, secondFrame]
            )
        )

        let file = try DICOMFile(data: data)
        let frames = try #require(file.pixelDataFrames)

        #expect(frames.count == 2)
        let firstBytes = try imageBytes(frames[0].cgImage())
        let secondBytes = try imageBytes(frames[1].cgImage())
        #expect(firstBytes[0] > 200)
        #expect(firstBytes[1] < 50)
        #expect(secondBytes[0] < 50)
        #expect(secondBytes[1] > 200)
    }

    @Test func decodesJPEG2000LosslessPixelData() throws {
        let encoded = compressedImageData(
            rgb: Data([255, 0, 0, 0, 255, 0]),
            width: 2,
            height: 1,
            type: "public.jpeg-2000"
        )
        let data = imageFile(
            transferSyntaxUID: TransferSyntax.jpeg2000Lossless.uid,
            samplesPerPixel: 3,
            photometricInterpretation: .rgb,
            planarConfiguration: 0,
            rows: 1,
            columns: 2,
            bitsAllocated: 8,
            pixelDataElement: encapsulatedPixelData(fragments: [encoded])
        )

        let image = try #require(try DICOMFile(data: data).pixelData).cgImage()
        let bytes = try imageBytes(image)

        #expect(bytes.count == 6)
        #expect(bytes[0] > 200)
        #expect(bytes[1] < 50)
        #expect(bytes[3] < 50)
        #expect(bytes[4] > 200)
    }

    @Test func decodesJPEG2000PixelData() throws {
        let encoded = compressedImageData(
            rgb: Data([0, 0, 255]),
            width: 1,
            height: 1,
            type: "public.jpeg-2000"
        )
        let data = imageFile(
            transferSyntaxUID: TransferSyntax.jpeg2000.uid,
            samplesPerPixel: 3,
            photometricInterpretation: .rgb,
            planarConfiguration: 0,
            rows: 1,
            columns: 1,
            bitsAllocated: 8,
            pixelDataElement: encapsulatedPixelData(fragments: [encoded])
        )

        let image = try #require(try DICOMFile(data: data).pixelData).cgImage()
        let bytes = try imageBytes(image)

        #expect(bytes.count == 3)
        #expect(bytes[0] < 50)
        #expect(bytes[1] < 50)
        #expect(bytes[2] > 200)
    }
}
