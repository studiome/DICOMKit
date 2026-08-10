import CoreGraphics
import Foundation
import ImageIO

/// Produces a deterministic RGB JPEG for decoder tests without committing a
/// binary fixture to the repository.
func jpegData(rgb: Data, width: Int, height: Int) -> Data {
    compressedImageData(rgb: rgb, width: width, height: height, type: "public.jpeg")
}

/// Produces a deterministic grayscale JPEG for decoder tests.
func jpegData(gray: Data, width: Int, height: Int) -> Data {
    compressedImageData(gray: gray, width: width, height: height, type: "public.jpeg")
}

/// Produces a deterministic RGB image using the requested ImageIO format.
func compressedImageData(rgb: Data, width: Int, height: Int, type: String) -> Data {
    precondition(rgb.count == width * height * 3)
    return encoded(
        image(bytes: rgb, width: width, height: height, bitsPerPixel: 24, space: CGColorSpaceCreateDeviceRGB()),
        type: type
    )
}

/// Produces a deterministic grayscale image using the requested ImageIO format.
///
/// Only 8-bit samples: ImageIO's JPEG 2000 encoder downsamples a 16-bit
/// grayscale source to 8 bits, so it can't produce a trustworthy 16-bit
/// fixture.
func compressedImageData(gray: Data, width: Int, height: Int, type: String) -> Data {
    precondition(gray.count == width * height)
    return encoded(
        image(bytes: gray, width: width, height: height, bitsPerPixel: 8, space: CGColorSpaceCreateDeviceGray()),
        type: type
    )
}

private func image(bytes: Data, width: Int, height: Int, bitsPerPixel: Int, space: CGColorSpace) -> CGImage {
    let provider = CGDataProvider(data: bytes as CFData)!
    return CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: bitsPerPixel,
        bytesPerRow: width * bitsPerPixel / 8,
        space: space,
        bitmapInfo: .byteOrderDefault,
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )!
}

private func encoded(_ image: CGImage, type: String) -> Data {
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, type as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary)
    precondition(CGImageDestinationFinalize(destination))
    return data as Data
}
