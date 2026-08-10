/// A DICOM transfer syntax identified by its UID.
public enum TransferSyntax: Sendable, Equatable {
    /// Implicit VR Little Endian (`1.2.840.10008.1.2`).
    case implicitVRLittleEndian
    /// Explicit VR Little Endian (`1.2.840.10008.1.2.1`).
    case explicitVRLittleEndian
    /// Explicit VR Big Endian (`1.2.840.10008.1.2.2`).
    case explicitVRBigEndian
    /// RLE Lossless (`1.2.840.10008.1.2.5`).
    case rleLossless
    /// A transfer syntax not modelled by DICOMKit.
    case unknown(String)

    /// The transfer syntax UID.
    public var uid: String {
        switch self {
        case .implicitVRLittleEndian: "1.2.840.10008.1.2"
        case .explicitVRLittleEndian: "1.2.840.10008.1.2.1"
        case .explicitVRBigEndian: "1.2.840.10008.1.2.2"
        case .rleLossless: "1.2.840.10008.1.2.5"
        case .unknown(let uid): uid
        }
    }

    init(uid: String) {
        switch uid {
        case Self.implicitVRLittleEndian.uid: self = .implicitVRLittleEndian
        case Self.explicitVRLittleEndian.uid: self = .explicitVRLittleEndian
        case Self.explicitVRBigEndian.uid: self = .explicitVRBigEndian
        case Self.rleLossless.uid: self = .rleLossless
        default: self = .unknown(uid)
        }
    }
}
