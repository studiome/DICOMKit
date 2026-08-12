import Foundation

/// Native IEEE 754 floating-point Pixel Data.
public struct DICOMFloatingPixelData: Sendable, Equatable {
    /// The image height in pixels.
    public let rows: Int
    /// The image width in pixels.
    public let columns: Int
    /// One sample per pixel, in row-major order.
    public let values: [Double]

    init(rows: Int, columns: Int, values: [Double]) {
        self.rows = rows
        self.columns = columns
        self.values = values
    }
}
