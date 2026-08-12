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
