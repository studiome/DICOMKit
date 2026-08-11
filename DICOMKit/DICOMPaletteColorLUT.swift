import Foundation

/// The three lookup tables that render `PALETTE COLOR` Pixel Data as RGB.
///
/// A palette entry is normalized to an 8-bit display component when this
/// value is created. Pixel samples below or above the descriptor's mapped
/// range use the first or final LUT entry, as required for palette lookup.
public struct DICOMPaletteColorLUT: Sendable, Equatable {
    /// The stored pixel value addressed by the first table entry.
    public let firstMappedValue: UInt16
    /// The number of entries in each color table.
    public let entryCount: Int
    private let red: [UInt8]
    private let green: [UInt8]
    private let blue: [UInt8]

    /// Creates a palette LUT from its descriptor and component entries.
    ///
    /// `bitsPerEntry` must be either 8 or 16. The three component arrays
    /// must have the same nonzero number of entries.
    public init(
        firstMappedValue: UInt16,
        bitsPerEntry: Int,
        red: [UInt16],
        green: [UInt16],
        blue: [UInt16]
    ) throws {
        guard bitsPerEntry == 8 || bitsPerEntry == 16,
              !red.isEmpty,
              red.count == green.count,
              red.count == blue.count else {
            throw DICOMImageError.invalidImageAttributes
        }
        self.firstMappedValue = firstMappedValue
        self.entryCount = red.count
        let maximum = bitsPerEntry == 8 ? 255.0 : 65_535.0
        self.red = red.map { UInt8(clamping: Int((Double($0) * 255 / maximum).rounded())) }
        self.green = green.map { UInt8(clamping: Int((Double($0) * 255 / maximum).rounded())) }
        self.blue = blue.map { UInt8(clamping: Int((Double($0) * 255 / maximum).rounded())) }
    }

    func rgb(for storedValue: UInt16) -> (UInt8, UInt8, UInt8) {
        let offset = Int(storedValue) - Int(firstMappedValue)
        let index = min(max(offset, 0), entryCount - 1)
        return (red[index], green[index], blue[index])
    }
}
