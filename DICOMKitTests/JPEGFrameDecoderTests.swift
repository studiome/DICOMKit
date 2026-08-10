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

    @Test func decodes8BitJPEGLosslessSV1PixelData() throws {
        let source = Data([12, 15, 5, 240, 238, 255])
        let data = imageFile(
            transferSyntaxUID: TransferSyntax.jpegLosslessSV1.uid,
            rows: 2,
            columns: 3,
            bitsAllocated: 8,
            pixelDataElement: encapsulatedPixelData(fragments: [
                jpegLosslessSV1Data(samples: source.map(UInt16.init), width: 3, height: 2, precision: 8)
            ])
        )

        let pixelData = try #require(try DICOMFile(data: data).pixelData)

        #expect(pixelData.bitsAllocated == 8)
        #expect(pixelData.bitsStored == 8)
        #expect(pixelData.value == source)
    }

    @Test(arguments: [2, 3, 4, 5, 6, 7])
    func decodesJPEGLosslessOtherPredictors(selectionValue: Int) throws {
        let samples: [UInt16] = [12, 20, 35, 18, 27, 40, 30, 36, 50]
        let data = imageFile(
            transferSyntaxUID: TransferSyntax.jpegLossless.uid,
            rows: 3,
            columns: 3,
            bitsAllocated: 8,
            pixelDataElement: encapsulatedPixelData(fragments: [
                jpegLosslessSV1Data(
                    samples: samples,
                    width: 3,
                    height: 3,
                    precision: 8,
                    selectionValue: selectionValue
                )
            ])
        )

        let pixelData = try #require(try DICOMFile(data: data).pixelData)

        #expect(pixelData.value == Data(samples.map(UInt8.init)))
    }

    @Test(arguments: [1, 2, 5, 8])
    func rejectsTruncatedJPEGLosslessEntropyData(droppedByteCount: Int) {
        let encoded = jpegLosslessSV1Data(
            samples: [12, 20, 35, 18],
            width: 2,
            height: 2,
            precision: 8,
            selectionValue: 4
        )
        let truncated = encoded.dropLast(droppedByteCount)

        #expect(throws: (any Error).self) {
            try JPEGLosslessDecoder.decodeLossless(
                fragments: [Data(truncated)],
                width: 2,
                height: 2,
                bitsAllocated: 8
            )
        }
    }

    @Test(arguments: [1, 2, 5, 8])
    func rejectsTruncatedJPEGLSEntropyData(droppedByteCount: Int) {
        let truncated = charLSMonochrome2x2.dropLast(droppedByteCount)

        #expect(throws: (any Error).self) {
            try JPEGLSDecoder.decodeLossless(
                fragments: [Data(truncated)],
                width: 2,
                height: 2,
                bitsAllocated: 8
            )
        }
    }

    @Test func rejectsJPEGLSStreamWithInvalidStartMarker() {
        var malformed = charLSMonochrome2x2
        malformed[0] = 0

        #expect(throws: DICOMImageError.unsupportedPixelFormat) {
            try JPEGLSDecoder.decodeLossless(
                fragments: [malformed],
                width: 2,
                height: 2,
                bitsAllocated: 8
            )
        }
    }

    @Test func decodesReferenceJPEGLSLosslessMonochromeFrame() throws {
        let frame = try JPEGLSDecoder.decodeLossless(
            fragments: [charLSMonochrome2x2],
            width: 2,
            height: 2,
            bitsAllocated: 8
        )
        #expect(frame.value == Data([1, 2, 3, 4]))

        let data = imageFile(
            transferSyntaxUID: TransferSyntax.jpegLSLossless.uid,
            rows: 2,
            columns: 2,
            bitsAllocated: 8,
            pixelDataElement: encapsulatedPixelData(fragments: [charLSMonochrome2x2])
        )

        let pixelData = try #require(try DICOMFile(data: data).pixelData)

        #expect(pixelData.bitsAllocated == 8)
        #expect(pixelData.bitsStored == 8)
        #expect(pixelData.value == Data([1, 2, 3, 4]))
    }

    @Test func decodesReference12BitJPEGLSLosslessFrameInto16BitDICOMStorage() throws {
        let expected: [UInt16] = [1, 2, 4_095, 1_024]
        let data = imageFile(
            transferSyntaxUID: TransferSyntax.jpegLSLossless.uid,
            rows: 2,
            columns: 2,
            bitsAllocated: 16,
            bitsStored: 12,
            pixelDataElement: encapsulatedPixelData(fragments: [charLS12BitMonochrome2x2])
        )

        let pixelData = try #require(try DICOMFile(data: data).pixelData)

        #expect(pixelData.bitsAllocated == 16)
        #expect(pixelData.bitsStored == 12)
        #expect(pixelData.value == Data(expected.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }))
    }

    @Test func decodesJPEGLSLosslessWithCustomPresetCodingParameters() throws {
        let data = imageFile(
            transferSyntaxUID: TransferSyntax.jpegLSLossless.uid,
            rows: 2,
            columns: 2,
            bitsAllocated: 8,
            pixelDataElement: encapsulatedPixelData(fragments: [charLSCustomParametersMonochrome2x2])
        )

        let pixelData = try #require(try DICOMFile(data: data).pixelData)

        #expect(pixelData.value == Data([1, 2, 3, 4]))
    }

    @Test func decodesJPEGLSLosslessWithRestartMarkers() throws {
        let data = imageFile(
            transferSyntaxUID: TransferSyntax.jpegLSLossless.uid,
            rows: 2,
            columns: 1,
            bitsAllocated: 8,
            pixelDataElement: encapsulatedPixelData(fragments: [charLSRestartMonochrome1x2])
        )

        let pixelData = try #require(try DICOMFile(data: data).pixelData)

        #expect(pixelData.value == Data([1, 2]))
    }

    @Test func decodesSampleInterleavedRGBJPEGLSLossless() throws {
        let data = imageFile(
            transferSyntaxUID: TransferSyntax.jpegLSLossless.uid,
            samplesPerPixel: 3,
            photometricInterpretation: .rgb,
            planarConfiguration: 0,
            rows: 1,
            columns: 1,
            bitsAllocated: 8,
            pixelDataElement: encapsulatedPixelData(fragments: [charLSRGBSampleInterleaved1x1])
        )
        let pixelData = try #require(try DICOMFile(data: data).pixelData)
        #expect(pixelData.value == Data([10, 20, 30]))
    }

    @Test func decodesYBRFullJPEGLSLosslessAsRGB() throws {
        let data = imageFile(
            transferSyntaxUID: TransferSyntax.jpegLSLossless.uid,
            samplesPerPixel: 3,
            photometricInterpretation: .ybrFull,
            planarConfiguration: 0,
            rows: 1,
            columns: 1,
            bitsAllocated: 8,
            pixelDataElement: encapsulatedPixelData(fragments: [charLSRGBSampleInterleaved1x1])
        )

        let pixelData = try #require(try DICOMFile(data: data).pixelData)

        #expect(pixelData.photometricInterpretation == .rgb)
        #expect(pixelData.value == Data([0, 117, 0]))
    }

    @Test func decodesJPEGLSNearLosslessMonochrome() throws {
        let data = imageFile(
            transferSyntaxUID: TransferSyntax.jpegLSNearLossless.uid,
            rows: 2,
            columns: 2,
            bitsAllocated: 8,
            pixelDataElement: encapsulatedPixelData(fragments: [charLSNearLosslessMonochrome2x2])
        )
        let pixelData = try #require(try DICOMFile(data: data).pixelData)
        #expect(pixelData.value == Data([9, 21, 30, 39]))
    }

    @Test func decodesJPEGLSNearLosslessRGBWithZeroErrorBound() throws {
        let data = imageFile(
            transferSyntaxUID: TransferSyntax.jpegLSNearLossless.uid,
            samplesPerPixel: 3,
            photometricInterpretation: .rgb,
            planarConfiguration: 0,
            rows: 1,
            columns: 1,
            bitsAllocated: 8,
            pixelDataElement: encapsulatedPixelData(fragments: [charLSRGBSampleInterleaved1x1])
        )

        let pixelData = try #require(try DICOMFile(data: data).pixelData)

        #expect(pixelData.value == Data([10, 20, 30]))
    }

    @Test func decodesJPEGLSNearLosslessRGBWithinDeclaredErrorBound() throws {
        let data = imageFile(
            transferSyntaxUID: TransferSyntax.jpegLSNearLossless.uid,
            samplesPerPixel: 3,
            photometricInterpretation: .rgb,
            planarConfiguration: 0,
            rows: 1,
            columns: 1,
            bitsAllocated: 8,
            pixelDataElement: encapsulatedPixelData(fragments: [charLSNearLosslessRGBSampleInterleaved1x1])
        )

        let reconstructed = try #require(try DICOMFile(data: data).pixelData).value
        let source = [10, 20, 30]

        #expect(reconstructed.count == source.count)
        for (decoded, original) in zip(reconstructed, source) {
            #expect(abs(Int(decoded) - original) <= 1)
        }
    }

    @Test func decodesMultiFrameJPEGLSLosslessUsingBasicOffsetTable() throws {
        let firstFrame = charLSMonochrome2x2
        let secondFrame = charLSMonochrome2x2
        let secondFrameOffset = 8 + ((firstFrame.count + 1) / 2 * 2)
        let data = imageFile(
            transferSyntaxUID: TransferSyntax.jpegLSLossless.uid,
            numberOfFrames: 2,
            rows: 2,
            columns: 2,
            bitsAllocated: 8,
            pixelDataElement: encapsulatedPixelData(
                basicOffsetTable: uint32(0) + uint32(UInt32(secondFrameOffset)),
                fragments: [firstFrame, secondFrame]
            )
        )

        let frames = try #require(try DICOMFile(data: data).pixelDataFrames)

        #expect(frames.map(\.value) == [Data([1, 2, 3, 4]), Data([1, 2, 3, 4])])
    }

    @Test func decodes12BitJPEGLosslessSV1Into16BitDICOMStorage() throws {
        let samples: [UInt16] = [0, 1, 2_047, 2_048, 4_095, 2_000]
        let data = imageFile(
            transferSyntaxUID: TransferSyntax.jpegLosslessSV1.uid,
            rows: 2,
            columns: 3,
            bitsAllocated: 16,
            bitsStored: 12,
            pixelDataElement: encapsulatedPixelData(fragments: [
                jpegLosslessSV1Data(samples: samples, width: 3, height: 2, precision: 12)
            ])
        )

        let pixelData = try #require(try DICOMFile(data: data).pixelData)

        #expect(pixelData.bitsAllocated == 16)
        #expect(pixelData.bitsStored == 12)
        #expect(pixelData.value == Data(samples.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }))
    }

    @Test func decodesJPEGLosslessSV1WithRestartMarkers() throws {
        let samples: [UInt16] = [40, 41, 42, 200, 199, 198]
        let data = imageFile(
            transferSyntaxUID: TransferSyntax.jpegLosslessSV1.uid,
            rows: 1,
            columns: 6,
            bitsAllocated: 8,
            pixelDataElement: encapsulatedPixelData(fragments: [
                jpegLosslessSV1Data(samples: samples, width: 6, height: 1, precision: 8, restartInterval: 2)
            ])
        )

        let pixelData = try #require(try DICOMFile(data: data).pixelData)

        #expect(pixelData.value == Data(samples.map(UInt8.init)))
    }

    @Test func decodesJPEGLosslessSV1WithPointTransform() throws {
        let samples: [UInt16] = [0, 16, 128, 240]
        let data = imageFile(
            transferSyntaxUID: TransferSyntax.jpegLosslessSV1.uid,
            rows: 1,
            columns: 4,
            bitsAllocated: 8,
            pixelDataElement: encapsulatedPixelData(fragments: [
                jpegLosslessSV1Data(samples: samples, width: 4, height: 1, precision: 8, pointTransform: 4)
            ])
        )

        let pixelData = try #require(try DICOMFile(data: data).pixelData)

        #expect(pixelData.value == Data(samples.map(UInt8.init)))
    }

    @Test func decodesMultiFrameJPEGLosslessSV1PixelDataUsingBasicOffsetTable() throws {
        let firstFrame = jpegLosslessSV1Data(samples: [10], width: 1, height: 1, precision: 8)
        let secondFrame = jpegLosslessSV1Data(samples: [200], width: 1, height: 1, precision: 8)
        let secondFrameOffset = 8 + ((firstFrame.count + 1) / 2 * 2)
        let data = imageFile(
            transferSyntaxUID: TransferSyntax.jpegLosslessSV1.uid,
            numberOfFrames: 2,
            rows: 1,
            columns: 1,
            bitsAllocated: 8,
            pixelDataElement: encapsulatedPixelData(
                basicOffsetTable: uint32(0) + uint32(UInt32(secondFrameOffset)),
                fragments: [firstFrame, secondFrame]
            )
        )

        let frames = try #require(try DICOMFile(data: data).pixelDataFrames)

        #expect(frames.map(\.value) == [Data([10]), Data([200])])
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
