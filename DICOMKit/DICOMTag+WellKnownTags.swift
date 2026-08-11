/// Named constants for commonly used DICOM tags.
///
/// Declared in ascending tag order.
extension DICOMTag {
    /// Specific Character Set `(0008,0005)`.
    public static let specificCharacterSet = DICOMTag(group: 0x0008, element: 0x0005)
    /// Transfer Syntax UID `(0002,0010)` in File Meta Information.
    public static let transferSyntaxUID = DICOMTag(group: 0x0002, element: 0x0010)
    public static let mediaStorageSOPClassUID = DICOMTag(group: 0x0002, element: 0x0002)
    public static let mediaStorageSOPInstanceUID = DICOMTag(group: 0x0002, element: 0x0003)
    public static let implementationClassUID = DICOMTag(group: 0x0002, element: 0x0012)
    public static let implementationVersionName = DICOMTag(group: 0x0002, element: 0x0013)
    public static let sopClassUID = DICOMTag(group: 0x0008, element: 0x0016)
    public static let sopInstanceUID = DICOMTag(group: 0x0008, element: 0x0018)
    /// Referenced Study Sequence `(0008,1110)`.
    public static let referencedStudySequence = DICOMTag(group: 0x0008, element: 0x1110)
    /// Referenced SOP Class UID `(0008,1150)`.
    public static let referencedSOPClassUID = DICOMTag(group: 0x0008, element: 0x1150)
    /// Patient's Name `(0010,0010)`.
    public static let patientName = DICOMTag(group: 0x0010, element: 0x0010)
    /// Samples per Pixel `(0028,0002)`.
    public static let samplesPerPixel = DICOMTag(group: 0x0028, element: 0x0002)
    /// Number of Frames `(0028,0008)`.
    public static let numberOfFrames = DICOMTag(group: 0x0028, element: 0x0008)
    /// Photometric Interpretation `(0028,0004)`.
    public static let photometricInterpretation = DICOMTag(group: 0x0028, element: 0x0004)
    /// Planar Configuration `(0028,0006)`.
    public static let planarConfiguration = DICOMTag(group: 0x0028, element: 0x0006)
    /// Rows `(0028,0010)`.
    public static let rows = DICOMTag(group: 0x0028, element: 0x0010)
    /// Columns `(0028,0011)`.
    public static let columns = DICOMTag(group: 0x0028, element: 0x0011)
    /// Bits Allocated `(0028,0100)`.
    public static let bitsAllocated = DICOMTag(group: 0x0028, element: 0x0100)
    /// Bits Stored `(0028,0101)`.
    public static let bitsStored = DICOMTag(group: 0x0028, element: 0x0101)
    /// High Bit `(0028,0102)`.
    public static let highBit = DICOMTag(group: 0x0028, element: 0x0102)
    /// Pixel Representation `(0028,0103)`: `0` for unsigned integer, `1` for
    /// 2's complement signed integer.
    public static let pixelRepresentation = DICOMTag(group: 0x0028, element: 0x0103)
    /// Red Palette Color Lookup Table Descriptor `(0028,1101)`.
    public static let redPaletteColorLookupTableDescriptor = DICOMTag(group: 0x0028, element: 0x1101)
    /// Green Palette Color Lookup Table Descriptor `(0028,1102)`.
    public static let greenPaletteColorLookupTableDescriptor = DICOMTag(group: 0x0028, element: 0x1102)
    /// Blue Palette Color Lookup Table Descriptor `(0028,1103)`.
    public static let bluePaletteColorLookupTableDescriptor = DICOMTag(group: 0x0028, element: 0x1103)
    /// Red Palette Color Lookup Table Data `(0028,1201)`.
    public static let redPaletteColorLookupTableData = DICOMTag(group: 0x0028, element: 0x1201)
    /// Green Palette Color Lookup Table Data `(0028,1202)`.
    public static let greenPaletteColorLookupTableData = DICOMTag(group: 0x0028, element: 0x1202)
    /// Blue Palette Color Lookup Table Data `(0028,1203)`.
    public static let bluePaletteColorLookupTableData = DICOMTag(group: 0x0028, element: 0x1203)
    /// Window Center `(0028,1050)`.
    public static let windowCenter = DICOMTag(group: 0x0028, element: 0x1050)
    /// Window Width `(0028,1051)`.
    public static let windowWidth = DICOMTag(group: 0x0028, element: 0x1051)
    /// Window Center & Width Explanation `(0028,1055)`.
    public static let windowCenterWidthExplanation = DICOMTag(group: 0x0028, element: 0x1055)
    /// Rescale Intercept `(0028,1052)`.
    public static let rescaleIntercept = DICOMTag(group: 0x0028, element: 0x1052)
    /// Rescale Slope `(0028,1053)`.
    public static let rescaleSlope = DICOMTag(group: 0x0028, element: 0x1053)
    /// Pixel Data `(7FE0,0010)`.
    public static let pixelData = DICOMTag(group: 0x7FE0, element: 0x0010)
}
