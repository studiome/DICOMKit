import Foundation

/// The provenance of ``DICOMImageGeometry/measurementSpacing``, so a caller
/// can distinguish "no measurable spacing" from "spacing measured relative
/// to some plane other than the patient."
public enum DICOMPixelSpacingSource: Sendable, Equatable {
    /// Pixel Spacing `(0028,0030)`, with no calibration declared. For
    /// cross-sectional modalities (CT, MR, ...) this is spacing in the
    /// patient.
    case pixelSpacing
    /// Pixel Spacing `(0028,0030)`, alongside Pixel Spacing Calibration Type
    /// `(0028,0A02)` (`GEOMETRY` or `FIDUCIAL`) and Pixel Spacing Calibration
    /// Description `(0028,0A04)`.
    case calibrated(type: String, description: String?)
    /// Imager Pixel Spacing `(0018,1164)`: spacing at the detector plane,
    /// not in the patient.
    case imagerPixelSpacing
    /// Nominal Scanned Pixel Spacing `(0018,2010)`.
    case nominalScannedPixelSpacing
    /// No spacing attribute is present.
    case none
}

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
    /// Imager Pixel Spacing `(0018,1164)`, in millimetres, at the detector plane.
    public let imagerPixelSpacing: [Double]?
    /// Nominal Scanned Pixel Spacing `(0018,2010)`, in millimetres.
    public let nominalScannedPixelSpacing: [Double]?
    /// Pixel Spacing Calibration Type `(0028,0A02)`: `GEOMETRY` or `FIDUCIAL`.
    public let pixelSpacingCalibrationType: String?
    /// Pixel Spacing Calibration Description `(0028,0A04)`.
    public let pixelSpacingCalibrationDescription: String?

    public init(
        pixelSpacing: [Double]? = nil,
        pixelAspectRatio: [Int]? = nil,
        imagePositionPatient: [Double]? = nil,
        imageOrientationPatient: [Double]? = nil,
        imagerPixelSpacing: [Double]? = nil,
        nominalScannedPixelSpacing: [Double]? = nil,
        pixelSpacingCalibrationType: String? = nil,
        pixelSpacingCalibrationDescription: String? = nil
    ) {
        self.pixelSpacing = pixelSpacing
        self.pixelAspectRatio = pixelAspectRatio
        self.imagePositionPatient = imagePositionPatient
        self.imageOrientationPatient = imageOrientationPatient
        self.imagerPixelSpacing = imagerPixelSpacing
        self.nominalScannedPixelSpacing = nominalScannedPixelSpacing
        self.pixelSpacingCalibrationType = pixelSpacingCalibrationType
        self.pixelSpacingCalibrationDescription = pixelSpacingCalibrationDescription
    }

    /// The spacing to measure with, resolved in precedence order: Pixel
    /// Spacing `(0028,0030)`, then Imager Pixel Spacing `(0018,1164)`, then
    /// Nominal Scanned Pixel Spacing `(0018,2010)`; `nil` when none of them
    /// is present. Row spacing first, then column spacing, matching
    /// ``pixelSpacing``'s own ordering.
    ///
    /// When ``measurementSpacingSource`` is
    /// ``DICOMPixelSpacingSource/imagerPixelSpacing``, this value is the
    /// spacing *at the detector*, not in the patient: a measurement taken
    /// with it is in the detector plane and is magnified relative to the
    /// patient by the source-to-detector versus source-to-patient distance
    /// ratio. DICOMKit reports the source rather than silently correcting
    /// for it, because the correction needs geometry DICOMKit does not have.
    ///
    /// A caller must not measure when ``measurementSpacingSource`` is
    /// ``DICOMPixelSpacingSource/none``.
    public var measurementSpacing: [Double]? {
        switch measurementSpacingSource {
        case .pixelSpacing, .calibrated:
            return pixelSpacing
        case .imagerPixelSpacing:
            return imagerPixelSpacing
        case .nominalScannedPixelSpacing:
            return nominalScannedPixelSpacing
        case .none:
            return nil
        }
    }

    /// Which attribute ``measurementSpacing`` was resolved from.
    public var measurementSpacingSource: DICOMPixelSpacingSource {
        if pixelSpacing != nil {
            if let type = pixelSpacingCalibrationType {
                return .calibrated(type: type, description: pixelSpacingCalibrationDescription)
            }
            return .pixelSpacing
        }
        if imagerPixelSpacing != nil {
            return .imagerPixelSpacing
        }
        if nominalScannedPixelSpacing != nil {
            return .nominalScannedPixelSpacing
        }
        return .none
    }
}
