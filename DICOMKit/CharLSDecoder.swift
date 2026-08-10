import Foundation
import CharLS

/// Thin Swift wrapper around the vendored CharLS JPEG-LS decoder.
enum CharLSDecoder {
    static func decode(
        _ data: Data,
        expectedWidth: Int,
        expectedHeight: Int,
        bitsAllocated: Int
    ) throws -> (value: Data, precision: Int, samplesPerPixel: Int) {
        guard let decoder = charls_jpegls_decoder_create() else { throw DICOMImageError.unsupportedPixelFormat }
        defer { charls_jpegls_decoder_destroy(decoder) }

        return try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { throw DICOMImageError.truncatedPixelData }
            guard charls_jpegls_decoder_set_source_buffer(decoder, baseAddress, data.count).rawValue == 0,
                  charls_jpegls_decoder_read_header(decoder).rawValue == 0 else {
                throw DICOMImageError.unsupportedPixelFormat
            }

            var frame = charls_frame_info()
            guard charls_jpegls_decoder_get_frame_info(decoder, &frame).rawValue == 0,
                  Int(frame.width) == expectedWidth,
                  Int(frame.height) == expectedHeight,
                  (2...bitsAllocated).contains(Int(frame.bits_per_sample)) else {
                throw DICOMImageError.invalidImageAttributes
            }
            var mode = charls_interleave_mode(rawValue: 0)
            guard charls_jpegls_decoder_get_interleave_mode(decoder, 0, &mode).rawValue == 0 else {
                throw DICOMImageError.unsupportedPixelFormat
            }
            var sourceCount = 0
            guard charls_jpegls_decoder_get_destination_size(decoder, 0, &sourceCount).rawValue == 0 else {
                throw DICOMImageError.unsupportedPixelFormat
            }
            var decoded = Data(repeating: 0, count: sourceCount)
            let status = decoded.withUnsafeMutableBytes {
                charls_jpegls_decoder_decode_to_buffer(decoder, $0.baseAddress, sourceCount, 0)
            }
            guard status.rawValue == 0 else { throw DICOMImageError.truncatedPixelData }

            let sourceBytesPerSample = (Int(frame.bits_per_sample) + 7) / 8
            let targetBytesPerSample = bitsAllocated / 8
            let pixelCount = expectedWidth * expectedHeight
            let sampleCount = pixelCount * Int(frame.component_count)
            guard decoded.count == sampleCount * sourceBytesPerSample else { throw DICOMImageError.truncatedPixelData }
            var result = Data(repeating: 0, count: sampleCount * targetBytesPerSample)
            result.withUnsafeMutableBytes { destination in
                decoded.withUnsafeBytes { source in
                    let destinationBytes = destination.bindMemory(to: UInt8.self)
                    let sourceBytes = source.bindMemory(to: UInt8.self)
                    for sample in 0..<sampleCount {
                        let sourceOffset: Int
                        if mode.rawValue == 0, frame.component_count > 1 {
                            let pixel = sample / Int(frame.component_count)
                            let component = sample % Int(frame.component_count)
                            sourceOffset = (component * pixelCount + pixel) * sourceBytesPerSample
                        } else {
                            sourceOffset = sample * sourceBytesPerSample
                        }
                        let destinationOffset = sample * targetBytesPerSample
                        for byte in 0..<sourceBytesPerSample {
                            destinationBytes[destinationOffset + byte] = sourceBytes[sourceOffset + byte]
                        }
                    }
                }
            }
            return (result, Int(frame.bits_per_sample), Int(frame.component_count))
        }
    }
}
