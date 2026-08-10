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
}
