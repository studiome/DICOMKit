import Foundation

/// A grayscale Modality LUT from the Modality LUT Sequence `(0028,3000)`.
///
/// Per PS3.3 C.11.1, Modality LUT Sequence and Rescale Slope/Intercept
/// `(0028,1053)`/`(0028,1052)` are mutually exclusive: when the sequence is
/// present it maps each stored pixel value to a value in a modality unit
/// (Hounsfield Units, optical density, ...) before the VOI/windowing stage,
/// replacing the rescale transform entirely.
///
/// Unlike ``DICOMVOILUT``, entries are *not* normalized to 0–255: a Modality
/// LUT's output feeds windowing rather than direct display, so it must retain
/// its actual numeric modality-unit value.
public struct DICOMModalityLUT: Sendable, Equatable {
    /// The stored value addressed by the first table entry.
    public let firstMappedValue: Int
    /// The number of entries in the table.
    public let entryCount: Int
    /// Modality LUT Type `(0028,3004)`, for example `"HU"`.
    public let type: String?
    /// An optional LUT Explanation `(0028,3003)`.
    public let explanation: String?
    private let entries: [Double]

    /// Creates a Modality LUT from its descriptor and unsigned LUT entries.
    public init(firstMappedValue: Int, bitsPerEntry: Int, entries: [UInt16], type: String? = nil, explanation: String? = nil) throws {
        guard (8...16).contains(bitsPerEntry), !entries.isEmpty else {
            throw DICOMImageError.invalidImageAttributes
        }
        self.firstMappedValue = firstMappedValue
        self.entryCount = entries.count
        self.type = type
        self.explanation = explanation
        self.entries = entries.map(Double.init)
    }

    /// Maps a stored pixel value to its modality-unit output, clamping to the
    /// first or final entry when `storedValue` falls outside the mapped range.
    func mappedValue(for storedValue: Int64) -> Double {
        let offset = Int(storedValue) - firstMappedValue
        return entries[min(max(offset, 0), entryCount - 1)]
    }
}
