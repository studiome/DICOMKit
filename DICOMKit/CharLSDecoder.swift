import Foundation
import CharLS

/// Thin Swift wrapper around the vendored CharLS JPEG-LS decoder.
enum CharLSDecoder {
    static func decode(_ data: Data) throws -> (value: Data, precision: Int, samplesPerPixel: Int) {
        guard let decoder = charls_jpegls_decoder_create() else { throw DICOMImageError.unsupportedPixelFormat }
        defer { charls_jpegls_decoder_destroy(decoder) }

        let status: charls_jpegls_errc = try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { throw DICOMImageError.truncatedPixelData }
            let setSource = charls_jpegls_decoder_set_source_buffer(decoder, baseAddress, data.count)
            guard setSource.rawValue == 0 else { throw DICOMImageError.unsupportedPixelFormat }
            let readHeader = charls_jpegls_decoder_read_header(decoder)
            guard readHeader.rawValue == 0 else { throw DICOMImageError.unsupportedPixelFormat }
            return readHeader
        }
        guard status.rawValue == 0 else { throw DICOMImageError.unsupportedPixelFormat }

        var frame = charls_frame_info()
        guard charls_jpegls_decoder_get_frame_info(decoder, &frame).rawValue == 0 else { throw DICOMImageError.unsupportedPixelFormat }
        var mode = charls_interleave_mode(rawValue: 0)
        guard charls_jpegls_decoder_get_interleave_mode(decoder, 0, &mode).rawValue == 0 else { throw DICOMImageError.unsupportedPixelFormat }
        var count = 0
        guard charls_jpegls_decoder_get_destination_size(decoder, 0, &count).rawValue == 0 else { throw DICOMImageError.unsupportedPixelFormat }
        var result = Data(repeating: 0, count: count)
        let decodeStatus = result.withUnsafeMutableBytes { bytes in
            charls_jpegls_decoder_decode_to_buffer(decoder, bytes.baseAddress, count, 0)
        }
        guard decodeStatus.rawValue == 0 else { throw DICOMImageError.truncatedPixelData }
        let bytesPerSample = (Int(frame.bits_per_sample) + 7) / 8
        if mode.rawValue == 0, frame.component_count > 1 {
            let pixelCount = Int(frame.width) * Int(frame.height)
            var interleaved = Data(repeating: 0, count: result.count)
            for pixel in 0..<pixelCount {
                for component in 0..<Int(frame.component_count) {
                    let source: Int
                    source = (component * pixelCount + pixel) * bytesPerSample
                    let destination = (pixel * Int(frame.component_count) + component) * bytesPerSample
                    interleaved.replaceSubrange(destination..<(destination + bytesPerSample), with: result[source..<(source + bytesPerSample)])
                }
            }
            result = interleaved
        }
        return (result, Int(frame.bits_per_sample), Int(frame.component_count))
    }
}
