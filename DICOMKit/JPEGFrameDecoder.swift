import CoreGraphics
import Foundation
import ImageIO

enum JPEGFrameDecoder {
    static func decodeRGB(fragments: [Data], width: Int, height: Int) throws -> Data {
        let data = fragments.reduce(into: Data()) { $0.append($1) }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width == width, image.height == height,
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { throw DICOMImageError.unsupportedPixelFormat }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let bytes = context.data else { throw DICOMImageError.imageCreationFailed }
        let rgba = Data(bytes: bytes, count: width * height * 4)
        var rgb = Data(); rgb.reserveCapacity(width * height * 3)
        for offset in stride(from: 0, to: rgba.count, by: 4) { rgb.append(rgba[offset]); rgb.append(rgba[offset + 1]); rgb.append(rgba[offset + 2]) }
        return rgb
    }
}
