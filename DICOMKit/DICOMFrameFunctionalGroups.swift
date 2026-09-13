import Foundation

/// The macros DICOMKit resolves for one frame of an Enhanced Multi-frame
/// object (PS3.3 C.7.6.16).
///
/// A value is resolved shared-first: Shared Functional Groups Sequence
/// `(5200,9229)` supplies the default for every frame, and Per-frame
/// Functional Groups Sequence `(5200,9230)` overrides it for the matching
/// frame index. See ``DICOMFile/frameFunctionalGroups``.
public struct DICOMFrameFunctionalGroups: Sendable, Equatable {
    /// Rescale Slope `(0028,1053)` from the Pixel Value Transformation macro `(0028,9145)`.
    public var rescaleSlope: Double?
    /// Rescale Intercept `(0028,1052)` from the Pixel Value Transformation macro `(0028,9145)`.
    public var rescaleIntercept: Double?
    /// Window Center `(0028,1050)` from the Frame VOI LUT macro `(0028,9132)`.
    public var windowCenter: Double?
    /// Window Width `(0028,1051)` from the Frame VOI LUT macro `(0028,9132)`.
    public var windowWidth: Double?
    /// The Pixel Measures macro `(0028,9110)`.
    public var pixelMeasures: DICOMPixelMeasures?
    /// Image Position (Patient) `(0020,0032)` from the Plane Position
    /// (Patient) macro `(0020,9113)`.
    public var planePosition: [Double]?
    /// Image Orientation (Patient) `(0020,0037)` from the Plane Orientation
    /// (Patient) macro `(0020,9116)`.
    public var planeOrientation: [Double]?

    public init(
        rescaleSlope: Double? = nil,
        rescaleIntercept: Double? = nil,
        windowCenter: Double? = nil,
        windowWidth: Double? = nil,
        pixelMeasures: DICOMPixelMeasures? = nil,
        planePosition: [Double]? = nil,
        planeOrientation: [Double]? = nil
    ) {
        self.rescaleSlope = rescaleSlope
        self.rescaleIntercept = rescaleIntercept
        self.windowCenter = windowCenter
        self.windowWidth = windowWidth
        self.pixelMeasures = pixelMeasures
        self.planePosition = planePosition
        self.planeOrientation = planeOrientation
    }
}

/// The Pixel Measures macro `(0028,9110)`: per-frame spacing attributes for
/// an Enhanced Multi-frame object.
public struct DICOMPixelMeasures: Sendable, Equatable {
    /// Pixel Spacing `(0028,0030)`.
    public let pixelSpacing: [Double]?
    /// Slice Thickness `(0018,0050)`.
    public let sliceThickness: Double?
    /// Spacing Between Slices `(0018,0088)`.
    public let spacingBetweenSlices: Double?

    public init(pixelSpacing: [Double]? = nil, sliceThickness: Double? = nil, spacingBetweenSlices: Double? = nil) {
        self.pixelSpacing = pixelSpacing
        self.sliceThickness = sliceThickness
        self.spacingBetweenSlices = spacingBetweenSlices
    }
}
