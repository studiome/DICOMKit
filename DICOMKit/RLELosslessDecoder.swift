import Foundation

/// Decodes single-frame monochrome RLE Lossless images. DICOM PS3.5 Annex G
/// defines each RLE frame as a 64-byte header followed by PackBits-encoded
/// byte segments, ordered from most-significant byte to least-significant byte.
enum RLELosslessDecoder {
    static func decode8BitMonochrome(fragments: [Data], pixelCount: Int) throws -> Data {
        try decodedSegments(fragments: fragments, count: 1, pixelCount: pixelCount)[0]
    }

    static func decode16BitMonochrome(fragments: [Data], pixelCount: Int) throws -> Data {
        let segments = try decodedSegments(fragments: fragments, count: 2, pixelCount: pixelCount)
        var output = Data()
        output.reserveCapacity(pixelCount * 2)
        for index in 0..<pixelCount {
            // DICOM RLE stores the most-significant byte in the first
            // segment, while native uncompressed Pixel Data is little-endian.
            output.append(segments[1][index])
            output.append(segments[0][index])
        }
        return output
    }

    static func decode8BitRGB(fragments: [Data], pixelCount: Int) throws -> Data {
        let segments = try decodedSegments(fragments: fragments, count: 3, pixelCount: pixelCount)
        var output = Data()
        output.reserveCapacity(pixelCount * 3)
        for index in 0..<pixelCount {
            output.append(segments[0][index])
            output.append(segments[1][index])
            output.append(segments[2][index])
        }
        return output
    }

    private static func decodedSegments(fragments: [Data], count: Int, pixelCount: Int) throws -> [Data] {
        guard pixelCount > 0 else { throw DICOMImageError.invalidImageAttributes }
        let frame = fragments.reduce(into: Data()) { $0.append($1) }
        guard frame.count >= 64, frame.littleEndian(at: 0, as: UInt32.self) == count else {
            throw DICOMImageError.unsupportedPixelFormat
        }
        let offsets = try (0..<count).map { index -> Int in
            let offset = Int(frame.littleEndian(at: 4 + index * 4, as: UInt32.self))
            guard offset >= 64, offset < frame.count else { throw DICOMImageError.truncatedPixelData }
            return offset
        }
        guard offsets == offsets.sorted(), Set(offsets).count == offsets.count else {
            throw DICOMImageError.truncatedPixelData
        }
        return try offsets.enumerated().map { index, offset in
            let end = index + 1 < offsets.count ? offsets[index + 1] : frame.count
            return try decodePackBits(frame.subdata(in: offset..<end), expectedCount: pixelCount)
        }
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
