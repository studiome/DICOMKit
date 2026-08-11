import CTurboJPEG
import Foundation

/// Decodes JPEG Baseline frames through the TurboJPEG C API supplied by
/// libjpeg-turbo.
enum TurboJPEGDecoder {
    static func decodeRGB(fragments: [Data], width: Int, height: Int) throws -> Data {
        try decode(fragments: fragments, width: width, height: height, samplesPerPixel: 3) {
            dicomkit_turbojpeg_decode_rgb8($0, $1, $2, $3, $4, $5)
        }
    }

    static func decodeMonochrome(fragments: [Data], width: Int, height: Int) throws -> Data {
        try decode(fragments: fragments, width: width, height: height, samplesPerPixel: 1) {
            dicomkit_turbojpeg_decode_gray8($0, $1, $2, $3, $4, $5)
        }
    }

    private static func decode(
        fragments: [Data],
        width: Int,
        height: Int,
        samplesPerPixel: Int,
        operation: (UnsafePointer<UInt8>?, Int, UnsafeMutablePointer<UInt8>?, Int, Int32, Int32) -> Int32
    ) throws -> Data {
        let pixelCount = width.multipliedReportingOverflow(by: height)
        let outputCount = pixelCount.partialValue.multipliedReportingOverflow(by: samplesPerPixel)
        guard width > 0, height > 0, !pixelCount.overflow, !outputCount.overflow else {
            throw DICOMImageError.invalidImageAttributes
        }
        let source = fragments.reduce(into: Data()) { $0.append($1) }
        guard !source.isEmpty else { throw DICOMImageError.truncatedPixelData }

        let byteCount = outputCount.partialValue
        var output = Data(count: byteCount)
        let result = source.withUnsafeBytes { sourceBuffer in
            output.withUnsafeMutableBytes { outputBuffer in
                operation(
                    sourceBuffer.bindMemory(to: UInt8.self).baseAddress,
                    source.count,
                    outputBuffer.bindMemory(to: UInt8.self).baseAddress,
                    byteCount,
                    Int32(width),
                    Int32(height)
                )
            }
        }
        guard result == 0 else { throw DICOMImageError.unsupportedPixelFormat }
        return output
    }
}
