import Foundation

/// A named Window Center and Window Width pair from a DICOM dataset.
///
/// DICOM permits multiple window presets. The first remains available through
/// ``DICOMPixelData/defaultWindowCenter`` and
/// ``DICOMPixelData/defaultWindowWidth`` for source compatibility.
public struct DICOMWindowPreset: Sendable, Equatable {
    /// Window Center `(0028,1050)` in rescaled modality units.
    public let center: Double
    /// Window Width `(0028,1051)` in rescaled modality units.
    public let width: Double
    /// The optional matching Window Center & Width Explanation `(0028,1055)`.
    public let explanation: String?

    public init(center: Double, width: Double, explanation: String? = nil) {
        self.center = center
        self.width = width
        self.explanation = explanation
    }
}
