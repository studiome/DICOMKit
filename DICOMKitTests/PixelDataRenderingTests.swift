import CoreGraphics
import Foundation
import Testing
@testable import DICOMKit

/// Rendering of 8-bit monochrome and RGB pixel data, which needs no windowing.
struct PixelDataRenderingTests {
    @Test func rendersPlanarRGBPixelData() throws {
        let pixelData = DICOMPixelData(
            value: Data([255, 0, 0, 255, 0, 0]), // R plane, G plane, B plane
            rows: 1,
            columns: 2,
            samplesPerPixel: 3,
            bitsAllocated: 8,
            photometricInterpretation: .rgb,
            planarConfiguration: 1
        )
        #expect(try imageBytes(pixelData.cgImage()) == Data([255, 0, 0, 0, 255, 0]))
    }
    @Test func renders8BitMonochromePixelData() throws {
        let file = try DICOMFile(data: imageFile(
            rows: 2,
            columns: 2,
            bitsAllocated: 8,
            pixelData: Data([0, 64, 128, 255])
        ))

        let image = try #require(file.pixelData).cgImage()

        #expect(image.width == 2)
        #expect(image.height == 2)
        #expect(image.bitsPerComponent == 8)
        #expect(try imageBytes(image) == Data([0, 64, 128, 255]))
    }

    @Test func rendersInterleavedRGBPixelData() throws {
        let file = try DICOMFile(data: imageFile(
            samplesPerPixel: 3,
            photometricInterpretation: .rgb,
            planarConfiguration: 0,
            rows: 1,
            columns: 2,
            bitsAllocated: 8,
            pixelData: Data([255, 0, 0, 0, 255, 0])
        ))

        let image = try #require(file.pixelData).cgImage()

        #expect(image.width == 2)
        #expect(image.height == 1)
        #expect(try imageBytes(image) == Data([255, 0, 0, 0, 255, 0]))
    }

    @Test(arguments: [
        (PhotometricInterpretation.monochrome1, Data([255, 191, 127, 0])),
        (PhotometricInterpretation.monochrome2, Data([0, 64, 128, 255]))
    ])
    func eightBitMonochromeAppliesExpectedPolarity(
        photometricInterpretation: PhotometricInterpretation,
        expectedBytes: Data
    ) throws {
        let pixelData = DICOMPixelData(
            value: Data([0, 64, 128, 255]),
            rows: 2,
            columns: 2,
            samplesPerPixel: 1,
            bitsAllocated: 8,
            photometricInterpretation: photometricInterpretation
        )

        let image = try pixelData.cgImage()

        #expect(try imageBytes(image) == expectedBytes)
    }
}

// MARK: - Unsupported or inconsistent attributes

struct PixelDataFormatErrorTests {
    @Test func rejectsPixelDataShorterThanDeclaredDimensions() {
        let pixelData = DICOMPixelData(
            value: Data([0, 64]),
            rows: 2,
            columns: 2,
            samplesPerPixel: 1,
            bitsAllocated: 8,
            photometricInterpretation: .monochrome2
        )

        #expect(throws: DICOMImageError.truncatedPixelData) {
            _ = try pixelData.cgImage()
        }
    }

    @Test func rejectsUnsupportedPhotometricInterpretation() {
        let pixelData = DICOMPixelData(
            value: Data([0, 1, 2, 3]),
            rows: 2,
            columns: 2,
            samplesPerPixel: 1,
            bitsAllocated: 8,
            photometricInterpretation: .other("YBR_FULL")
        )

        #expect(throws: DICOMImageError.unsupportedPixelFormat) {
            _ = try pixelData.cgImage()
        }
    }

    @Test func rejectsRGBWithInvalidPlanarConfiguration() {
        let pixelData = DICOMPixelData(
            value: Data(repeating: 0, count: 6),
            rows: 1,
            columns: 2,
            samplesPerPixel: 3,
            bitsAllocated: 8,
            photometricInterpretation: .rgb,
            planarConfiguration: 2
        )

        #expect(throws: DICOMImageError.unsupportedPixelFormat) {
            _ = try pixelData.cgImage()
        }
    }

    @Test(arguments: [0, 17])
    func rejectsBitsStoredOutsideValidRange(bitsStored: Int) {
        let pixelData = DICOMPixelData(
            value: uint16(0),
            rows: 1,
            columns: 1,
            samplesPerPixel: 1,
            bitsAllocated: 16,
            photometricInterpretation: .monochrome2,
            bitsStored: bitsStored
        )

        #expect(throws: DICOMImageError.invalidImageAttributes) {
            _ = try pixelData.cgImage(windowCenter: 0, windowWidth: 10)
        }
    }
}
