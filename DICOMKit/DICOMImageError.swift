/// Errors produced while creating an image from uncompressed DICOM Pixel Data.
///
/// ``invalidImageAttributes`` and ``unsupportedPixelFormat`` are distinguished
/// by *why* the attributes can't be rendered:
/// - ``invalidImageAttributes`` means the attribute combination is
///   inconsistent with the DICOM standard itself, for example a `RGB`
///   Photometric Interpretation with Samples per Pixel other than `3`, or a
///   Bits Stored value outside `1...bitsAllocated`.
/// - ``unsupportedPixelFormat`` means the attributes are individually valid
///   under DICOM, but describe a combination this renderer doesn't handle,
///   for example interleaved `RGB` with Planar Configuration `1`, or a
///   Photometric Interpretation this renderer doesn't model at all.
public enum DICOMImageError: Error, Sendable, Equatable {
    /// The attribute combination is inconsistent with the DICOM standard.
    case invalidImageAttributes
    /// The attributes are valid DICOM, but this renderer doesn't support the resulting format.
    case unsupportedPixelFormat
    /// The Pixel Data value is shorter than required by its image metadata.
    case truncatedPixelData
    /// A window width of one or less was supplied.
    case invalidWindowWidth
    /// A window center or width that isn't a finite number (`NaN` or infinite) was supplied.
    case invalidWindowSettings
    /// Core Graphics failed to create an image from attributes and data that
    /// had already passed validation.
    case imageCreationFailed
}
