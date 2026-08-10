import Foundation

/// Decodes the single-byte RLE Lossless form needed for 8-bit monochrome
/// images. DICOM PS3.5 Annex G defines each RLE frame as a 64-byte header
/// followed by PackBits-encoded byte segments.
enum RLELosslessDecoder {
    static func decode8BitMonochrome(fragments: [Data], pixelCount: Int) throws -> Data {
        guard pixelCount > 0 else { throw DICOMImageError.invalidImageAttributes }
        let frame = fragments.reduce(into: Data()) { $0.append($1) }
        guard frame.count >= 64 else { throw DICOMImageError.truncatedPixelData }
        let segmentCount: UInt32 = frame.littleEndian(at: 0)
        guard segmentCount == 1 else { throw DICOMImageError.unsupportedPixelFormat }
        let offset: UInt32 = frame.littleEndian(at: 4)
        guard offset >= 64, offset < frame.count else { throw DICOMImageError.truncatedPixelData }
        return try decodePackBits(frame.subdata(in: Int(offset)..<frame.count), expectedCount: pixelCount)
    }

    private static func decodePackBits(_ encoded: Data, expectedCount: Int) throws -> Data {
        var sourceOffset = encoded.startIndex
        var output = Data()
        output.reserveCapacity(expectedCount)

        while sourceOffset < encoded.endIndex, output.count < expectedCount {
            let control = Int(Int8(bitPattern: encoded[sourceOffset]))
            sourceOffset += 1
            switch control {
            case 0...127:
                let count = control + 1
                guard sourceOffset + count <= encoded.endIndex, output.count + count <= expectedCount else {
                    throw DICOMImageError.truncatedPixelData
                }
                output.append(encoded.subdata(in: sourceOffset..<(sourceOffset + count)))
                sourceOffset += count
            case -127 ... -1:
                guard sourceOffset < encoded.endIndex else { throw DICOMImageError.truncatedPixelData }
                let count = 1 - control
                guard output.count + count <= expectedCount else { throw DICOMImageError.truncatedPixelData }
                output.append(Data(repeating: encoded[sourceOffset], count: count))
                sourceOffset += 1
            default:
                // -128 is a PackBits no-op.
                continue
            }
        }
        guard output.count == expectedCount else { throw DICOMImageError.truncatedPixelData }
        return output
    }
}
