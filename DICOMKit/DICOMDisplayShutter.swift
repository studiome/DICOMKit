import Foundation

/// A 1-based `(row, column)` coordinate, matching DICOM's own pixel
/// addressing for shutter shapes.
public struct DICOMShutterVertex: Sendable, Equatable {
    public let row: Int
    public let column: Int

    public init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }
}

/// One shape named by Shutter Shape `(0018,1600)` (PS3.3 C.7.6.11).
public enum DICOMShutterShape: Sendable, Equatable {
    case rectangular(left: Int, right: Int, upper: Int, lower: Int)
    case circular(center: DICOMShutterVertex, radius: Int)
    case polygonal(vertices: [DICOMShutterVertex])
    /// A shutter masked by the Overlay Plane bitmap of the named `60xx`
    /// group. ``DICOMDisplayShutter/obscures(row:column:)`` never treats a
    /// `bitmap` shape as obscuring anything: applying the referenced overlay
    /// bitmap as a mask isn't implemented.
    case bitmap(overlayGroup: UInt16)
}

/// The Display Shutter module (PS3.3 C.7.6.11): one or more shutter shapes
/// that combine as an intersection to obscure irrelevant image periphery.
public struct DICOMDisplayShutter: Sendable, Equatable {
    public let shapes: [DICOMShutterShape]
    /// Shutter Presentation Value `(0018,1622)`, a 16-bit P-Value used to
    /// paint the obscured region. `nil` means the obscured region is black.
    public let presentationValue: UInt16?

    public init(shapes: [DICOMShutterShape], presentationValue: UInt16? = nil) {
        self.shapes = shapes
        self.presentationValue = presentationValue
    }

    /// Whether the pixel at the 1-based `(row, column)` coordinate is
    /// obscured by this shutter.
    ///
    /// Multiple shapes combine as an intersection: a pixel is visible only
    /// when every shape's own region includes it, so it's obscured when any
    /// single shape excludes it. ``DICOMShutterShape/bitmap(overlayGroup:)``
    /// shapes never obscure anything.
    public func obscures(row: Int, column: Int) -> Bool {
        for shape in shapes {
            switch shape {
            case let .rectangular(left, right, upper, lower):
                // DICOM doesn't state whether the boundary row/column itself
                // is inside the shutter; DICOMKit treats the edges as visible.
                if !(left <= column && column <= right && upper <= row && row <= lower) {
                    return true
                }
            case let .circular(center, radius):
                let deltaRow = row - center.row
                let deltaColumn = column - center.column
                if deltaRow * deltaRow + deltaColumn * deltaColumn > radius * radius {
                    return true
                }
            case let .polygonal(vertices):
                if !Self.pointInPolygon(row: row, column: column, vertices: vertices) {
                    return true
                }
            case .bitmap:
                continue
            }
        }
        return false
    }

    /// Even-odd ray casting over the closed polygon described by `vertices`.
    private static func pointInPolygon(row: Int, column: Int, vertices: [DICOMShutterVertex]) -> Bool {
        guard vertices.count >= 3 else { return false }
        var inside = false
        var previous = vertices.count - 1
        for current in 0..<vertices.count {
            let vi = vertices[current]
            let vj = vertices[previous]
            if (vi.row > row) != (vj.row > row) {
                let intersectColumn = Double(vj.column - vi.column) * Double(row - vi.row) / Double(vj.row - vi.row) + Double(vi.column)
                if Double(column) < intersectColumn {
                    inside.toggle()
                }
            }
            previous = current
        }
        return inside
    }
}
