import Foundation

/// Patient-space and display geometry associated with a DICOM image.
public struct DICOMImageGeometry: Sendable, Equatable {
    /// Row and column spacing in millimetres from `(0028,0030)`.
    public let pixelSpacing: [Double]?
    /// Vertical and horizontal display aspect-ratio components from `(0028,0034)`.
    public let pixelAspectRatio: [Int]?
    /// Image Position (Patient), in millimetres, from `(0020,0032)`.
    public let imagePositionPatient: [Double]?
    /// Image Orientation (Patient) row/column direction cosines from `(0020,0037)`.
    public let imageOrientationPatient: [Double]?

    public init(pixelSpacing: [Double]? = nil, pixelAspectRatio: [Int]? = nil, imagePositionPatient: [Double]? = nil, imageOrientationPatient: [Double]? = nil) {
        self.pixelSpacing = pixelSpacing
        self.pixelAspectRatio = pixelAspectRatio
        self.imagePositionPatient = imagePositionPatient
        self.imageOrientationPatient = imageOrientationPatient
    }
}
