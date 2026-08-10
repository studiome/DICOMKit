/// A minimal built-in dictionary of VRs for tags used in Implicit VR decoding.
///
/// Not `public`: only `Reader` needs to resolve a VR for a tag that Implicit
/// VR encoding doesn't declare explicitly.
enum DICOMDictionary {
    static func vr(for tag: DICOMTag) -> DICOMVR? {
        switch tag {
        case .transferSyntaxUID, .referencedSOPClassUID: .UI
        case .patientName: .PN
        case .rows, .columns, .samplesPerPixel, .planarConfiguration, .bitsAllocated,
             .bitsStored, .highBit, .pixelRepresentation: .US
        case .photometricInterpretation: .CS
        case .pixelData: .OW
        case .windowCenter, .windowWidth, .rescaleIntercept, .rescaleSlope: .DS
        case .referencedStudySequence: .SQ
        default: nil
        }
    }
}
