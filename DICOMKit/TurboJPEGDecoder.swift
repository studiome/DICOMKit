import CTurboJPEG
import Foundation

/// Decodes JPEG Baseline and JPEG Lossless Process 14 frames through the
/// TurboJPEG C API supplied by libjpeg-turbo.
enum TurboJPEGDecoder {
    struct DecodedLosslessFrame {
        let value: Data
        let precision: Int
        let selectionValue: Int
        let samplesPerPixel: Int
    }

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

    static func decodeLossless(
        fragments: [Data],
        width: Int,
        height: Int,
        bitsAllocated: Int,
        samplesPerPixel: Int
    ) throws -> DecodedLosslessFrame {
        let sampleCount = try sampleCount(width: width, height: height, samplesPerPixel: samplesPerPixel)
        let source = fragments.reduce(into: Data()) { $0.append($1) }
        guard !source.isEmpty, bitsAllocated == 8 || bitsAllocated == 16,
              samplesPerPixel == 1 || samplesPerPixel == 3 else {
            throw DICOMImageError.invalidImageAttributes
        }

        var precision: Int32 = 0
        var selectionValue: Int32 = 0
        if bitsAllocated == 8 {
            var output = Data(count: sampleCount)
            let outputCount = sampleCount
            let result = source.withUnsafeBytes { sourceBuffer in
                output.withUnsafeMutableBytes { outputBuffer in
                    dicomkit_turbojpeg_decode_lossless8(
                        sourceBuffer.bindMemory(to: UInt8.self).baseAddress,
                        source.count,
                        outputBuffer.bindMemory(to: UInt8.self).baseAddress,
                        outputCount,
                        Int32(width), Int32(height), Int32(samplesPerPixel), &precision, &selectionValue
                    )
                }
            }
            guard result == 0, precision <= 8, (1...7).contains(selectionValue) else { throw DICOMImageError.unsupportedPixelFormat }
            return DecodedLosslessFrame(value: output, precision: Int(precision), selectionValue: Int(selectionValue), samplesPerPixel: samplesPerPixel)
        }

        var samples = [UInt16](repeating: 0, count: sampleCount)
        let result = source.withUnsafeBytes { sourceBuffer in
            samples.withUnsafeMutableBufferPointer { outputBuffer in
                dicomkit_turbojpeg_decode_lossless16(
                    sourceBuffer.bindMemory(to: UInt8.self).baseAddress,
                    source.count,
                    outputBuffer.baseAddress,
                    outputBuffer.count,
                    Int32(width), Int32(height), Int32(samplesPerPixel), &precision, &selectionValue
                )
            }
        }
        guard result == 0, precision > 8, precision <= 16, (1...7).contains(selectionValue) else { throw DICOMImageError.unsupportedPixelFormat }
        var value = Data()
        value.reserveCapacity(sampleCount * 2)
        for sample in samples {
            value.append(UInt8(sample & 0xFF))
            value.append(UInt8(sample >> 8))
        }
        return DecodedLosslessFrame(value: value, precision: Int(precision), selectionValue: Int(selectionValue), samplesPerPixel: samplesPerPixel)
    }

    private static func decode(
        fragments: [Data],
        width: Int,
        height: Int,
        samplesPerPixel: Int,
        operation: (UnsafePointer<UInt8>?, Int, UnsafeMutablePointer<UInt8>?, Int, Int32, Int32) -> Int32
    ) throws -> Data {
        let outputCount = try sampleCount(width: width, height: height, samplesPerPixel: samplesPerPixel)
        let source = fragments.reduce(into: Data()) { $0.append($1) }
        guard !source.isEmpty else { throw DICOMImageError.truncatedPixelData }

        let byteCount = outputCount
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

    private static func sampleCount(width: Int, height: Int, samplesPerPixel: Int) throws -> Int {
        let pixelCount = width.multipliedReportingOverflow(by: height)
        let sampleCount = pixelCount.partialValue.multipliedReportingOverflow(by: samplesPerPixel)
        guard width > 0, height > 0, samplesPerPixel > 0,
              !pixelCount.overflow, !sampleCount.overflow else {
            throw DICOMImageError.invalidImageAttributes
        }
        return sampleCount.partialValue
    }
}
