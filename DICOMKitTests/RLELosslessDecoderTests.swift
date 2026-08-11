import Foundation
import Testing
@testable import DICOMKit

struct RLELosslessDecoderTests {
    @Test func decodesSingleFrame16BitRGBRLELosslessPixelData() throws {
        let data = imageFile(
            transferSyntaxUID: TransferSyntax.rleLossless.uid,
            samplesPerPixel: 3,
            photometricInterpretation: .rgb,
            rows: 1,
            columns: 1,
            bitsAllocated: 16,
            pixelDataElement: encapsulatedPixelData(fragments: [rleFrame(segments: [
                Data([0x00, 0xFF]), Data([0x00, 0x00]), // red: 0xFF00
                Data([0x00, 0x00]), Data([0x00, 0x00]),
                Data([0x00, 0x00]), Data([0x00, 0x00])
            ])])
        )

        #expect(try imageBytes(#require(DICOMFile(data: data).pixelData).cgImage()) == Data([255, 0, 0]))
    }
    @Test func decodesSingleFrame8BitRLELosslessPixelData() throws {
        let data = imageFile(
            transferSyntaxUID: TransferSyntax.rleLossless.uid,
            rows: 2,
            columns: 2,
            bitsAllocated: 8,
            pixelDataElement: encapsulatedPixelData(fragments: [rleFrame(segment: Data([0x03, 0, 64, 128, 255]))])
        )

        let file = try DICOMFile(data: data)
        let image = try #require(file.pixelData).cgImage()

        #expect(file.transferSyntax == .rleLossless)
        #expect(try imageBytes(image) == Data([0, 64, 128, 255]))
    }

    @Test func decodesSingleFrame16BitRLELosslessPixelData() throws {
        let data = imageFile(
            transferSyntaxUID: TransferSyntax.rleLossless.uid,
            rows: 1,
            columns: 2,
            bitsAllocated: 16,
            // RLE segments are stored most-significant byte first. The two
            // segments below represent little-endian samples 0 and 1000 once
            // reconstructed: [00 00] and [E8 03].
            pixelDataElement: encapsulatedPixelData(fragments: [rleFrame(segments: [
                Data([0x01, 0x00, 0x03]),
                Data([0x01, 0x00, 0xE8])
            ])])
        )

        let file = try DICOMFile(data: data)
        let image = try #require(file.pixelData).cgImage(windowCenter: 500, windowWidth: 1_000)

        #expect(try imageBytes(image) == Data([0, 255]))
    }

    @Test func decodesSingleFrame8BitRGBRLELosslessPixelData() throws {
        let data = imageFile(
            transferSyntaxUID: TransferSyntax.rleLossless.uid,
            samplesPerPixel: 3,
            photometricInterpretation: .rgb,
            planarConfiguration: 0,
            rows: 1,
            columns: 2,
            bitsAllocated: 8,
            // RLE stores each color component in its own segment. These
            // planes reconstruct to interleaved pixels [255,0,0, 0,255,0].
            pixelDataElement: encapsulatedPixelData(fragments: [rleFrame(segments: [
                Data([0x01, 255, 0]),
                Data([0x01, 0, 255]),
                Data([0x01, 0, 0])
            ])])
        )

        let file = try DICOMFile(data: data)
        let image = try #require(file.pixelData).cgImage()

        #expect(try imageBytes(image) == Data([255, 0, 0, 0, 255, 0]))
    }

    @Test func decodesMultiFrame8BitRLELosslessPixelDataUsingBasicOffsetTable() throws {
        let firstFrame = rleFrame(segment: Data([0x00, 0x12]))
        let secondFrame = rleFrame(segment: Data([0x00, 0x34]))
        let data = imageFile(
            transferSyntaxUID: TransferSyntax.rleLossless.uid,
            numberOfFrames: 2,
            rows: 1,
            columns: 1,
            bitsAllocated: 8,
            // Each serialized fragment is 8 bytes of item header plus a
            // 66-byte RLE frame. BOT offsets are relative to the first
            // fragment item tag, as defined for encapsulated Pixel Data.
            pixelDataElement: encapsulatedPixelData(
                basicOffsetTable: uint32(0) + uint32(74),
                fragments: [firstFrame, secondFrame]
            )
        )

        let file = try DICOMFile(data: data)
        let frames = try #require(file.pixelDataFrames)

        #expect(frames.count == 2)
        #expect(try imageBytes(frames[0].cgImage()) == Data([0x12]))
        #expect(try imageBytes(frames[1].cgImage()) == Data([0x34]))
    }

    @Test func rejectsMultiFrameRLEWithoutBasicOffsetTable() throws {
        // An empty Basic Offset Table leaves the frame boundaries undefined
        // once there's more than one frame, so the fragments must not be
        // guessed at.
        let data = imageFile(
            transferSyntaxUID: TransferSyntax.rleLossless.uid,
            numberOfFrames: 2,
            rows: 1,
            columns: 1,
            bitsAllocated: 8,
            pixelDataElement: encapsulatedPixelData(fragments: [
                rleFrame(segment: Data([0x00, 0x12])),
                rleFrame(segment: Data([0x00, 0x34]))
            ])
        )

        #expect(try DICOMFile(data: data).pixelDataFrames == nil)
    }
}
