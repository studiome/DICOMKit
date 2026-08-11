import Foundation

/// Splits the fragments of an encapsulated `(7FE0,0010)` element into frames.
///
/// Encapsulation is compression-agnostic: RLE Lossless and the JPEG-family
/// transfer syntaxes all wrap frames in the same item structure and differ
/// only in what a fragment contains, so frame boundaries are resolved here
/// rather than in any one decoder.
enum EncapsulatedPixelData {
    /// Groups `fragments` into one array of fragments per frame, using the
    /// Basic Offset Table to locate the fragment each frame starts at.
    ///
    /// A single-frame image may omit the Basic Offset Table, in which case
    /// every fragment belongs to that one frame. Multi-frame pixel data
    /// without a Basic Offset Table has no reliable frame boundaries and is
    /// rejected rather than guessed at.
    ///
    /// - Parameters:
    ///   - fragments: The fragment payloads, in stream order.
    ///   - fragmentOffsets: Each fragment's offset from the first fragment's
    ///     item tag, as the Basic Offset Table measures them.
    ///   - basicOffsetTable: The raw Basic Offset Table item value.
    ///   - frameCount: Number of Frames `(0028,0008)`, defaulting to `1`.
    static func frameFragments(
        fragments: [Data],
        fragmentOffsets: [Int],
        basicOffsetTable: Data,
        frameCount: Int
    ) throws -> [[Data]] {
        guard frameCount > 0, fragments.count == fragmentOffsets.count else {
            throw DICOMImageError.invalidImageAttributes
        }
        if frameCount == 1, basicOffsetTable.isEmpty { return [fragments] }
        guard basicOffsetTable.count == frameCount * 4 else { throw DICOMImageError.unsupportedPixelFormat }
        let offsets = stride(from: 0, to: basicOffsetTable.count, by: 4).map {
            Int(basicOffsetTable.littleEndian(at: $0, as: UInt32.self))
        }
        guard offsets.first == 0, offsets == offsets.sorted(), Set(offsets).count == offsets.count else {
            throw DICOMImageError.truncatedPixelData
        }
        let startIndices = try offsets.map { offset -> Int in
            guard let index = fragmentOffsets.firstIndex(of: offset) else {
                throw DICOMImageError.truncatedPixelData
            }
            return index
        }
        return startIndices.enumerated().map { index, start in
            let end = index + 1 < startIndices.count ? startIndices[index + 1] : fragments.count
            return Array(fragments[start..<end])
        }
    }

    /// Groups fragments with 64-bit Extended Offset Table offsets.
    static func frameFragments(
        fragments: [Data],
        fragmentOffsets: [Int],
        extendedOffsets: [UInt64],
        frameCount: Int
    ) throws -> [[Data]] {
        guard extendedOffsets.count == frameCount,
              extendedOffsets.first == 0,
              extendedOffsets == extendedOffsets.sorted(),
              Set(extendedOffsets).count == extendedOffsets.count else {
            throw DICOMImageError.unsupportedPixelFormat
        }
        let startIndices = try extendedOffsets.map { offset -> Int in
            guard offset <= UInt64(Int.max), let index = fragmentOffsets.firstIndex(of: Int(offset)) else {
                throw DICOMImageError.truncatedPixelData
            }
            return index
        }
        return startIndices.enumerated().map { index, start in
            let end = index + 1 < startIndices.count ? startIndices[index + 1] : fragments.count
            return Array(fragments[start..<end])
        }
    }
}
