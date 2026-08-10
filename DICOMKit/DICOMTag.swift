import Foundation

/// A DICOM data-element identifier consisting of a group and element number.
public struct DICOMTag: Hashable, Sendable, CustomStringConvertible {
    /// The 16-bit DICOM group number.
    public let group: UInt16
    /// The 16-bit DICOM element number.
    public let element: UInt16

    /// Creates a tag from its group and element numbers.
    public init(group: UInt16, element: UInt16) {
        self.group = group
        self.element = element
    }

    /// The canonical hexadecimal representation, for example `(0010,0010)`.
    public var description: String { String(format: "(%04X,%04X)", group, element) }
}
