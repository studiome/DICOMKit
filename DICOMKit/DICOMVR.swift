/// A DICOM Value Representation (VR).
///
/// The raw value of each case is the two-letter code defined by DICOM PS3.5.
public enum DICOMVR: String, Sendable, CaseIterable {
    case AE, AS, AT, CS, DA, DS, DT, FD, FL, IS, LO, LT, OB, OD, OF, OL, OV, OW
    case PN, SH, SL, SQ, SS, ST, SV, TM, UC, UI, UL, UN, UR, US, UT, UV

    var uses32BitLength: Bool {
        switch self {
        case .OB, .OD, .OF, .OL, .OV, .OW, .SQ, .SV, .UC, .UN, .UR, .UT, .UV:
            true
        default:
            false
        }
    }
}
