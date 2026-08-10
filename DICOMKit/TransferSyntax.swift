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
    /// JPEG Baseline (Process 1, 8-bit) (`1.2.840.10008.1.2.4.50`).
    case jpegBaseline
    /// JPEG Lossless, Non-Hierarchical (Process 14) (`1.2.840.10008.1.2.4.57`).
    case jpegLossless
    /// JPEG Lossless, Non-Hierarchical, First-Order Prediction (Process 14,
    /// Selection Value 1) (`1.2.840.10008.1.2.4.70`).
    case jpegLosslessSV1
    /// JPEG-LS Lossless Image Compression (`1.2.840.10008.1.2.4.80`).
    case jpegLSLossless
    /// JPEG-LS Near-Lossless Image Compression (`1.2.840.10008.1.2.4.81`).
    case jpegLSNearLossless
    /// JPEG 2000 Image Compression (Lossless Only) (`1.2.840.10008.1.2.4.90`).
    case jpeg2000Lossless
    /// JPEG 2000 Image Compression (`1.2.840.10008.1.2.4.91`).
    case jpeg2000
    /// A transfer syntax not modelled by DICOMKit.
    case unknown(String)

    /// The transfer syntax UID.
    public var uid: String {
        switch self {
        case .implicitVRLittleEndian: "1.2.840.10008.1.2"
        case .explicitVRLittleEndian: "1.2.840.10008.1.2.1"
        case .explicitVRBigEndian: "1.2.840.10008.1.2.2"
        case .rleLossless: "1.2.840.10008.1.2.5"
        case .jpegBaseline: "1.2.840.10008.1.2.4.50"
        case .jpegLossless: "1.2.840.10008.1.2.4.57"
        case .jpegLosslessSV1: "1.2.840.10008.1.2.4.70"
        case .jpegLSLossless: "1.2.840.10008.1.2.4.80"
        case .jpegLSNearLossless: "1.2.840.10008.1.2.4.81"
        case .jpeg2000Lossless: "1.2.840.10008.1.2.4.90"
        case .jpeg2000: "1.2.840.10008.1.2.4.91"
        case .unknown(let uid): uid
        }
    }

    /// Whether ``DICOMFile`` can read a dataset encoded in this transfer
    /// syntax.
    ///
    /// Being readable says nothing about Pixel Data: a readable file may
    /// still hold pixel data this library can't decode, in which case
    /// ``DICOMFile/pixelDataFrames`` is `nil`.
    var isSupported: Bool {
        switch self {
        case .implicitVRLittleEndian, .explicitVRLittleEndian, .rleLossless,
             .jpegBaseline, .jpegLossless, .jpegLosslessSV1, .jpegLSLossless,
             .jpegLSNearLossless, .jpeg2000Lossless, .jpeg2000:
            true
        case .explicitVRBigEndian, .unknown:
            false
        }
    }

    init(uid: String) {
        switch uid {
        case Self.implicitVRLittleEndian.uid: self = .implicitVRLittleEndian
        case Self.explicitVRLittleEndian.uid: self = .explicitVRLittleEndian
        case Self.explicitVRBigEndian.uid: self = .explicitVRBigEndian
        case Self.rleLossless.uid: self = .rleLossless
        case Self.jpegBaseline.uid: self = .jpegBaseline
        case Self.jpegLossless.uid: self = .jpegLossless
        case Self.jpegLosslessSV1.uid: self = .jpegLosslessSV1
        case Self.jpegLSLossless.uid: self = .jpegLSLossless
        case Self.jpegLSNearLossless.uid: self = .jpegLSNearLossless
        case Self.jpeg2000Lossless.uid: self = .jpeg2000Lossless
        case Self.jpeg2000.uid: self = .jpeg2000
        default: self = .unknown(uid)
        }
    }
}
