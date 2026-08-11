import Foundation

/// A grayscale Value of Interest lookup table from a `VOI LUT Sequence` item.
public struct DICOMVOILUT: Sendable, Equatable {
    /// The stored value addressed by the first table entry.
    public let firstMappedValue: Int16
    /// The number of entries in the table.
    public let entryCount: Int
    /// An optional LUT Explanation `(0028,3003)`.
    public let explanation: String?
    private let entries: [UInt8]

    /// Creates a VOI LUT from its descriptor and unsigned LUT entries.
    public init(firstMappedValue: Int16, bitsPerEntry: Int, entries: [UInt16], explanation: String? = nil) throws {
        guard (8...16).contains(bitsPerEntry), !entries.isEmpty else {
            throw DICOMImageError.invalidImageAttributes
        }
        self.firstMappedValue = firstMappedValue
        self.entryCount = entries.count
        self.explanation = explanation
        let maximum = Double((UInt32(1) << bitsPerEntry) - 1)
        self.entries = entries.map { UInt8(clamping: Int((Double($0) * 255 / maximum).rounded())) }
    }

    func renderedValue(for value: Double) -> UInt8 {
        let offset = Int(value.rounded(.towardZero)) - Int(firstMappedValue)
        return entries[min(max(offset, 0), entryCount - 1)]
    }
}
