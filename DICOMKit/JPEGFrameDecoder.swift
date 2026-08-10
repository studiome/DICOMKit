import CoreGraphics
import Foundation
import ImageIO

/// Decodes one encapsulated JPEG-family frame through ImageIO.
///
/// ImageIO hands back 8-bit samples for the transfer syntaxes DICOMKit
/// supports, so both entry points produce 8-bit output and callers must
/// reject frames that declare any other Bits Allocated.
enum JPEGFrameDecoder {
    /// Decodes a frame into interleaved 8-bit RGB.
    ///
    /// ImageIO converts the JPEG's own color space, so this also covers the
    /// `YBR_*` Photometric Interpretations that JPEG Baseline pixel data
    /// normally uses; the decoded frame is RGB regardless of what the dataset
    /// declared.
    static func decodeRGB(fragments: [Data], width: Int, height: Int) throws -> Data {
        let rgba = try drawnBytes(
            fragments: fragments,
            width: width,
            height: height,
            bytesPerPixel: 4,
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        )

        // Drop the alpha byte ImageIO requires in its RGB layouts.
        var rgb = Data()
        rgb.reserveCapacity(width * height * 3)
        for offset in stride(from: 0, to: rgba.count, by: 4) {
            rgb.append(contentsOf: rgba[offset..<(offset + 3)])
        }
        return rgb
    }

    /// Decodes a frame into 8-bit grayscale, one sample per pixel.
    ///
    /// The samples keep the stored polarity, so a `MONOCHROME1` frame still
    /// needs the inversion that ``DICOMPixelData/cgImage(windowCenter:windowWidth:)``
    /// applies.
    static func decodeMonochrome(fragments: [Data], width: Int, height: Int) throws -> Data {
        try drawnBytes(
            fragments: fragments,
            width: width,
            height: height,
            bytesPerPixel: 1,
            colorSpace: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )
    }

    /// Decodes the concatenated fragments and redraws them into a bitmap of
    /// the requested layout, so the output is independent of however ImageIO
    /// chose to represent the image.
    private static func drawnBytes(
        fragments: [Data],
        width: Int,
        height: Int,
        bytesPerPixel: Int,
        colorSpace: CGColorSpace,
        bitmapInfo: UInt32
    ) throws -> Data {
        let data = fragments.reduce(into: Data()) { $0.append($1) }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              // A frame whose decoded size disagrees with Rows/Columns would
              // silently misrender, so treat the mismatch as unsupported.
              image.width == width, image.height == height,
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * bytesPerPixel,
                space: colorSpace,
                bitmapInfo: bitmapInfo
              ) else {
            throw DICOMImageError.unsupportedPixelFormat
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let bytes = context.data else { throw DICOMImageError.imageCreationFailed }
        return Data(bytes: bytes, count: width * height * bytesPerPixel)
    }
}
