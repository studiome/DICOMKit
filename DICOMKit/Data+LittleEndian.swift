import Foundation

extension Data {
    /// Reads an unsigned little-endian integer of `T`'s width, at `offset`
    /// bytes past `startIndex`.
    ///
    /// `Data` slices retain the absolute indices of their underlying buffer
    /// (for example, `data[500...]` has `startIndex == 500`, not `0`), so
    /// `offset` here is always relative to `startIndex` rather than a
    /// zero-based byte position. Writing this with a zero-based index would
    /// either trap or silently read the wrong bytes when called on a slice.
    ///
    /// - Precondition: `offset + MemoryLayout<T>.size <= count`.
    func littleEndian<T: FixedWidthInteger & UnsignedInteger>(at offset: Int, as type: T.Type = T.self) -> T {
        var result: T = 0
        for byteIndex in stride(from: MemoryLayout<T>.size - 1, through: 0, by: -1) {
            result = (result << 8) | T(self[startIndex + offset + byteIndex])
        }
        return result
    }
}
