import Foundation

/// Decodes DICOM JPEG-LS frames through the vendored CharLS implementation.
///
/// CharLS is the sole JPEG-LS decoder in DICOMKit. Keeping one standards-tested
/// implementation avoids different behavior for malformed and edge-case frames.
enum JPEGLSDecoder {
    struct DecodedFrame {
        let value: Data
        let precision: Int
        let samplesPerPixel: Int
    }

    static func decodeLossless(
        fragments: [Data],
        width: Int,
        height: Int,
        bitsAllocated: Int
    ) throws -> DecodedFrame {
        guard width > 0, height > 0, bitsAllocated == 8 || bitsAllocated == 16 else {
            throw DICOMImageError.invalidImageAttributes
        }
        let stream = fragments.reduce(into: Data()) { $0.append($1) }
        let decoded = try CharLSDecoder.decode(
            stream,
            expectedWidth: width,
            expectedHeight: height,
            bitsAllocated: bitsAllocated
        )
        return DecodedFrame(value: decoded.value, precision: decoded.precision, samplesPerPixel: decoded.samplesPerPixel)
    }
}
