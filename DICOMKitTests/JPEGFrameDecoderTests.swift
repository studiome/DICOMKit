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

    @Test(arguments: [TransferSyntax.jpeg2000Lossless, .jpeg2000])
    func decodesJPEG2000PixelData(transferSyntax: TransferSyntax) throws {
        let encoded = compressedImageData(
            rgb: Data([255, 0, 0, 0, 255, 0]),
            width: 2,
            height: 1,
            type: "public.jpeg-2000"
        )
        let data = imageFile(
            transferSyntaxUID: transferSyntax.uid,
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

    @Test func decodesMonochromeJPEGBaselineAsSingleSampleGrayscale() throws {
        // A grayscale JPEG must stay single-sample monochrome pixel data:
        // inflating it to RGB throws away the Photometric Interpretation the
        // 8-bit monochrome rendering path needs.
        let data = monochromeJPEGFile(
            photometricInterpretation: .monochrome2,
            gray: Data([0, 64, 128, 255])
        )

        let pixelData = try #require(try DICOMFile(data: data).pixelData)

        #expect(pixelData.samplesPerPixel == 1)
        #expect(pixelData.photometricInterpretation == .monochrome2)

        let bytes = try imageBytes(pixelData.cgImage())

        #expect(bytes.count == 4)
        #expect(bytes[0] < 40)
        #expect(bytes[3] > 215)
    }

    @Test func monochrome1JPEGBaselineRendersInvertedPolarity() throws {
        // MONOCHROME1 displays the minimum stored value as white. Decoding a
        // grayscale JPEG as if it were RGB skips that inversion and renders
        // the image with the polarity reversed.
        let data = monochromeJPEGFile(
            photometricInterpretation: .monochrome1,
            gray: Data([0, 0, 255, 255])
        )

        let bytes = try imageBytes(try #require(try DICOMFile(data: data).pixelData).cgImage())

        #expect(bytes.count == 4)
        #expect(bytes[0] > 215)
        #expect(bytes[3] < 40)
    }

    @Test func decodesYBRJPEGBaselineAsRGB() throws {
        // JPEG Baseline pixel data is usually YBR_FULL_422 in DICOM. ImageIO
        // hands back RGB samples, so the decoded frame must be relabelled.
        let data = imageFile(
            transferSyntaxUID: TransferSyntax.jpegBaseline.uid,
            samplesPerPixel: 3,
            photometricInterpretation: .other("YBR_FULL_422"),
            planarConfiguration: 0,
            rows: 1,
            columns: 1,
            bitsAllocated: 8,
            pixelDataElement: encapsulatedPixelData(fragments: [jpegData(rgb: Data([255, 0, 0]), width: 1, height: 1)])
        )

        let pixelData = try #require(try DICOMFile(data: data).pixelData)

        #expect(pixelData.photometricInterpretation == .rgb)

        let bytes = try imageBytes(pixelData.cgImage())

        #expect(bytes[0] > 200)
        #expect(bytes[1] < 50)
    }

    @Test(arguments: [16, 12])
    func rejectsEncapsulatedJPEGWithBitsAllocatedOtherThan8(bitsAllocated: UInt16) throws {
        // ImageIO decodes encapsulated JPEG and JPEG 2000 to 8-bit samples,
        // so a frame declaring any other Bits Allocated can't be represented
        // faithfully. Returning `nil` says so up front, instead of handing
        // back pixel data whose attributes contradict its bytes and only
        // fails once the caller tries to render it.
        let data = imageFile(
            transferSyntaxUID: TransferSyntax.jpeg2000Lossless.uid,
            samplesPerPixel: 1,
            photometricInterpretation: .monochrome2,
            rows: 1,
            columns: 2,
            bitsAllocated: bitsAllocated,
            pixelDataElement: encapsulatedPixelData(fragments: [compressedImageData(
                gray: Data([0, 255]),
                width: 2,
                height: 1,
                type: "public.jpeg-2000"
            )])
        )

        #expect(try DICOMFile(data: data).pixelDataFrames == nil)
    }

    @Test(arguments: [
        TransferSyntax.jpegLossless,
        .jpegLosslessSV1,
        .jpegLSLossless,
        .jpegLSNearLossless
    ])
    func recognizesUnimplementedLosslessJPEGSyntaxWithoutUsingImageIO(transferSyntax: TransferSyntax) throws {
        // This is deliberately a decodable JPEG Baseline bitstream. If an
        // unimplemented lossless syntax were accidentally routed through
        // ImageIO, this test would incorrectly produce pixel data rather
        // than fail safely.
        let data = imageFile(
            transferSyntaxUID: transferSyntax.uid,
            rows: 1,
            columns: 1,
            bitsAllocated: 8,
            pixelDataElement: encapsulatedPixelData(fragments: [
                jpegData(gray: Data([128]), width: 1, height: 1)
            ])
        )

        let file = try DICOMFile(data: data)

        #expect(file.transferSyntax == transferSyntax)
        #expect(file.pixelDataFrames == nil)
    }

    @Test func rejectsMultiFrameJPEGWithoutBasicOffsetTable() throws {
        // Without a Basic Offset Table there's no reliable way to tell which
        // fragment starts which frame.
        let data = imageFile(
            transferSyntaxUID: TransferSyntax.jpegBaseline.uid,
            numberOfFrames: 2,
            rows: 1,
            columns: 1,
            bitsAllocated: 8,
            pixelDataElement: encapsulatedPixelData(fragments: [
                jpegData(gray: Data([0]), width: 1, height: 1),
                jpegData(gray: Data([255]), width: 1, height: 1)
            ])
        )

        #expect(try DICOMFile(data: data).pixelDataFrames == nil)
    }
}

/// A single-frame monochrome JPEG Baseline file, 2x2 with 8-bit samples.
private func monochromeJPEGFile(photometricInterpretation: PhotometricInterpretation, gray: Data) -> Data {
    imageFile(
        transferSyntaxUID: TransferSyntax.jpegBaseline.uid,
        samplesPerPixel: 1,
        photometricInterpretation: photometricInterpretation,
        rows: 2,
        columns: 2,
        bitsAllocated: 8,
        pixelDataElement: encapsulatedPixelData(fragments: [jpegData(gray: gray, width: 2, height: 2)])
    )
}
