/// A minimal built-in dictionary of VRs for tags used in Implicit VR decoding.
///
/// Not `public`: only `Reader` needs to resolve a VR for a tag that Implicit
/// VR encoding doesn't declare explicitly.
enum DICOMDictionary {
    static func vr(for tag: DICOMTag) -> DICOMVR? {
        entries[tag]
    }

    /// Standard public tags required by the reader's supported object model.
    /// Keep this data table separate from parser control flow so it can be
    /// replaced by a PS3.6-generated dictionary without changing `Reader`.
    private static let entries: [DICOMTag: DICOMVR] = [
        DICOMTag(group: 0x0002, element: 0x0000): .UL,
        DICOMTag(group: 0x0002, element: 0x0001): .OB,
        DICOMTag(group: 0x0002, element: 0x0002): .UI,
        DICOMTag(group: 0x0002, element: 0x0003): .UI,
        .transferSyntaxUID: .UI,
        DICOMTag(group: 0x0002, element: 0x0012): .UI,
        DICOMTag(group: 0x0002, element: 0x0013): .SH,
        .specificCharacterSet: .CS,
        DICOMTag(group: 0x0008, element: 0x0008): .CS,
        DICOMTag(group: 0x0008, element: 0x0016): .UI,
        DICOMTag(group: 0x0008, element: 0x0018): .UI,
        DICOMTag(group: 0x0008, element: 0x0020): .DA,
        DICOMTag(group: 0x0008, element: 0x0030): .TM,
        DICOMTag(group: 0x0008, element: 0x0050): .SH,
        DICOMTag(group: 0x0008, element: 0x0060): .CS,
        DICOMTag(group: 0x0008, element: 0x1030): .LO,
        DICOMTag(group: 0x0008, element: 0x103E): .LO,
        .referencedStudySequence: .SQ,
        .referencedSOPClassUID: .UI,
        DICOMTag(group: 0x0008, element: 0x1155): .UI,
        .patientName: .PN,
        DICOMTag(group: 0x0010, element: 0x0020): .LO,
        DICOMTag(group: 0x0010, element: 0x0030): .DA,
        DICOMTag(group: 0x0010, element: 0x0040): .CS,
        DICOMTag(group: 0x0020, element: 0x000D): .UI,
        DICOMTag(group: 0x0020, element: 0x000E): .UI,
        DICOMTag(group: 0x0020, element: 0x0010): .SH,
        DICOMTag(group: 0x0020, element: 0x0011): .IS,
        DICOMTag(group: 0x0020, element: 0x0013): .IS,
        .samplesPerPixel: .US,
        .numberOfFrames: .IS,
        .photometricInterpretation: .CS,
        .planarConfiguration: .US,
        .rows: .US, .columns: .US,
        DICOMTag(group: 0x0028, element: 0x0030): .DS,
        .bitsAllocated: .US, .bitsStored: .US, .highBit: .US, .pixelRepresentation: .US,
        .redPaletteColorLookupTableDescriptor: .US,
        .greenPaletteColorLookupTableDescriptor: .US,
        .bluePaletteColorLookupTableDescriptor: .US,
        .redPaletteColorLookupTableData: .OW,
        .greenPaletteColorLookupTableData: .OW,
        .bluePaletteColorLookupTableData: .OW,
        .windowCenter: .DS, .windowWidth: .DS, .rescaleIntercept: .DS, .rescaleSlope: .DS,
        .windowCenterWidthExplanation: .LO,
        .voiLUTSequence: .SQ,
        .lutDescriptor: .SS, .lutExplanation: .LO, .lutData: .OW,
        DICOMTag(group: 0x0028, element: 0x1056): .CS,
        DICOMTag(group: 0x5200, element: 0x9229): .SQ,
        DICOMTag(group: 0x5200, element: 0x9230): .SQ,
        .pixelData: .OW
        , .extendedOffsetTable: .OV
    ]
}
