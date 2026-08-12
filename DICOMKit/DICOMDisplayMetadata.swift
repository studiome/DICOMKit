import Foundation

/// A bitmap Overlay Plane carried in group `60xx`.
public struct DICOMOverlay: Sendable, Equatable {
    /// The even overlay group number, from `6000` through `60FE`.
    public let group: UInt16
    public let rows: Int
    public let columns: Int
    /// One-based overlay origin `[row, column]`, when supplied.
    public let origin: [Int]?
    /// Packed overlay bitmap data.
    public let data: Data

    public init(group: UInt16, rows: Int, columns: Int, origin: [Int]? = nil, data: Data) {
        self.group = group
        self.rows = rows
        self.columns = columns
        self.origin = origin
        self.data = data
    }
}

/// Presentation LUT Shape values directly usable by a display pipeline.
public enum DICOMPresentationLUTShape: Sendable, Equatable {
    case identity
    case inverse
}

extension DICOMDataset {
    /// The Presentation LUT Shape `(2050,0020)`, when it is supported.
    ///
    /// Shared by ``DICOMFile/presentationLUTShape`` and
    /// ``DICOMPresentationState``, since a GSPS dataset carries this same
    /// attribute at its top level.
    var presentationLUTShape: DICOMPresentationLUTShape? {
        switch self[DICOMTag(group: 0x2050, element: 0x0020)]?.stringValue?.uppercased() {
        case "IDENTITY": .identity
        case "INVERSE": .inverse
        default: nil
        }
    }
}
