/// Errors produced while creating an image from uncompressed DICOM Pixel Data.
public enum DICOMImageError: Error, Sendable, Equatable {
    /// Required image metadata is absent or inconsistent.
    case invalidImageAttributes
    /// The image format is not currently supported by the renderer.
    case unsupportedPixelFormat
    /// The Pixel Data value is shorter than required by its image metadata.
    case truncatedPixelData
    /// A window width of one or less was supplied.
    case invalidWindowWidth
    /// A window center or width that isn't a finite number (`NaN` or infinite) was supplied.
    case invalidWindowSettings
}
