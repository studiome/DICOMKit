/// A DICOM Photometric Interpretation `(0028,0004)`, identifying how stored
/// pixel samples map to a displayed color.
public enum PhotometricInterpretation: Sendable, Equatable {
    /// `MONOCHROME1`: single-sample grayscale where the minimum stored value
    /// is displayed as white and the maximum as black.
    case monochrome1
    /// `MONOCHROME2`: single-sample grayscale where the minimum stored value
    /// is displayed as black and the maximum as white.
    case monochrome2
    /// `RGB`: three interleaved or planar red, green, and blue samples.
    case rgb
    /// `YBR_FULL`: three full-resolution Y, Cb, and Cr samples.
    case ybrFull
    /// A Photometric Interpretation not modelled by DICOMKit.
    case other(String)

    /// The Photometric Interpretation name, as it appears in `(0028,0004)`.
    public var name: String {
        switch self {
        case .monochrome1: "MONOCHROME1"
        case .monochrome2: "MONOCHROME2"
        case .rgb: "RGB"
        case .ybrFull: "YBR_FULL"
        case .other(let name): name
        }
    }

    /// Creates a Photometric Interpretation from its `(0028,0004)` name.
    ///
    /// `name` must already have any DICOM space or NUL padding removed, for
    /// example via ``DICOMElement/stringValue``; this initializer doesn't
    /// trim it itself. A name that isn't one of the well-known cases becomes
    /// ``other(_:)``.
    public init(name: String) {
        switch name {
        case Self.monochrome1.name: self = .monochrome1
        case Self.monochrome2.name: self = .monochrome2
        case Self.rgb.name: self = .rgb
        case Self.ybrFull.name: self = .ybrFull
        default: self = .other(name)
        }
    }
}
