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
    /// The Frame Content macro `(0020,9111)`.
    public var frameContent: DICOMFrameContent?

    public init(
        rescaleSlope: Double? = nil,
        rescaleIntercept: Double? = nil,
        windowCenter: Double? = nil,
        windowWidth: Double? = nil,
        pixelMeasures: DICOMPixelMeasures? = nil,
        planePosition: [Double]? = nil,
        planeOrientation: [Double]? = nil,
        frameContent: DICOMFrameContent? = nil
    ) {
        self.rescaleSlope = rescaleSlope
        self.rescaleIntercept = rescaleIntercept
        self.windowCenter = windowCenter
        self.windowWidth = windowWidth
        self.pixelMeasures = pixelMeasures
        self.planePosition = planePosition
        self.planeOrientation = planeOrientation
        self.frameContent = frameContent
    }
}

/// The Frame Content macro `(0020,9111)`: frame-level identification and
/// stack/temporal placement for an Enhanced Multi-frame object.
public struct DICOMFrameContent: Sendable, Equatable {
    /// Stack ID `(0020,9056)`.
    public let stackID: String?
    /// In-Stack Position Number `(0020,9057)`.
    public let inStackPositionNumber: Int?
    /// Temporal Position Index `(0020,9128)`.
    public let temporalPositionIndex: Int?
    /// Dimension Index Values `(0020,9157)`, exposed raw.
    ///
    /// Interpreting these values requires the Dimension Index Sequence
    /// `(0020,9222)`'s dimension organization, which DICOMKit does not
    /// model; treat this as opaque data rather than an understood ordering
    /// key. See ``DICOMFile/frameOrder()``.
    public let dimensionIndexValues: [Int]?
    /// Frame Acquisition Number `(0020,9156)`.
    public let frameAcquisitionNumber: Int?
    /// Frame Acquisition Duration `(0018,9220)`, in milliseconds.
    public let frameAcquisitionDuration: Double?

    public init(
        stackID: String? = nil,
        inStackPositionNumber: Int? = nil,
        temporalPositionIndex: Int? = nil,
        dimensionIndexValues: [Int]? = nil,
        frameAcquisitionNumber: Int? = nil,
        frameAcquisitionDuration: Double? = nil
    ) {
        self.stackID = stackID
        self.inStackPositionNumber = inStackPositionNumber
        self.temporalPositionIndex = temporalPositionIndex
        self.dimensionIndexValues = dimensionIndexValues
        self.frameAcquisitionNumber = frameAcquisitionNumber
        self.frameAcquisitionDuration = frameAcquisitionDuration
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
