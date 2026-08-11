import Foundation

/// Character sets supported for DICOM text values.
public enum DICOMCharacterSet: Sendable, Equatable {
    case utf8
    case isoIR100
    case isoIR13
    case iso2022IR87

    init?(dicomName: String) {
        switch dicomName.trimmingCharacters(in: .whitespaces) {
        case "", "ISO_IR 6": self = .utf8
        case "ISO_IR 100": self = .isoIR100
        case "ISO_IR 13": self = .isoIR13
        case "ISO 2022 IR 87": self = .iso2022IR87
        case "ISO_IR 192": self = .utf8
        default: return nil
        }
    }

    func decode(_ data: Data) -> String? {
        let encoding: String.Encoding
        switch self {
        case .utf8: encoding = .utf8
        case .isoIR100: encoding = .isoLatin1
        case .isoIR13: encoding = .shiftJIS
        case .iso2022IR87: encoding = .iso2022JP
        }
        return String(data: data, encoding: encoding)
    }
}
