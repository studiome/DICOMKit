import CoreGraphics
import Foundation
import ImageIO

/// Produces a deterministic RGB JPEG for decoder tests without committing a
/// binary fixture to the repository.
func jpegData(rgb: Data, width: Int, height: Int) -> Data {
    compressedImageData(rgb: rgb, width: width, height: height, type: "public.jpeg")
}

/// Produces a deterministic RGB image using the requested ImageIO format.
func compressedImageData(rgb: Data, width: Int, height: Int, type: String) -> Data {
    precondition(rgb.count == width * height * 3)
    let provider = CGDataProvider(data: rgb as CFData)!
    let image = CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 24,
        bytesPerRow: width * 3,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: .byteOrderDefault,
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )!
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, type as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary)
    precondition(CGImageDestinationFinalize(destination))
    return data as Data
}
