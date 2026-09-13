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

    public init(
        rescaleSlope: Double? = nil,
        rescaleIntercept: Double? = nil,
        windowCenter: Double? = nil,
        windowWidth: Double? = nil
    ) {
        self.rescaleSlope = rescaleSlope
        self.rescaleIntercept = rescaleIntercept
        self.windowCenter = windowCenter
        self.windowWidth = windowWidth
    }
}
