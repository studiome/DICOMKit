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

extension DICOMDataset {
    /// The VOI LUTs declared by VOI LUT Sequence `(0028,3010)` directly on
    /// this dataset.
    ///
    /// Shared by ``DICOMFile/pixelDataFrames`` and ``DICOMPresentationState``,
    /// since a Softcopy VOI LUT Sequence item can carry its own nested VOI
    /// LUT Sequence just as an image does.
    func makeVOILUTs() -> [DICOMVOILUT] {
        guard let items = self[.voiLUTSequence]?.sequenceItems else { return [] }
        return items.compactMap { item in
            guard let descriptor = item[.lutDescriptor]?.uint16Values,
                  descriptor.count == 3,
                  let dataElement = item[.lutData] else { return nil }
            let count = descriptor[0] == 0 ? 65_536 : Int(descriptor[0])
            let bitsPerEntry = Int(descriptor[2])
            let data: [UInt16]?
            if bitsPerEntry <= 8, dataElement.vr == .OB, dataElement.value.count >= count {
                data = dataElement.value.prefix(count).map(UInt16.init)
            } else if let words = dataElement.uint16Values, words.count >= count {
                data = Array(words.prefix(count))
            } else {
                data = nil
            }
            guard let data else { return nil }
            return try? DICOMVOILUT(
                firstMappedValue: Int16(bitPattern: descriptor[1]),
                bitsPerEntry: bitsPerEntry,
                entries: data,
                explanation: item[.lutExplanation]?.stringValue
            )
        }
    }
}
