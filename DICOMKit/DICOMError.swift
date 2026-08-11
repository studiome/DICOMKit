/// Errors produced while reading a DICOM Part 10 file.
public enum DICOMError: Error, Sendable, Equatable {
    case invalidUIDRoot
    /// A Deflated Explicit VR Little Endian dataset could not be decompressed.
    case invalidDeflatedData
    /// A DICOM JSON representation cannot be converted to a DICOM element.
    case invalidDICOMJSON
    /// The dataset doesn't contain the SOP Class UID needed for File Meta Information.
    case missingSOPClassUID
    /// The dataset doesn't contain the SOP Instance UID needed for File Meta Information.
    case missingSOPInstanceUID
    /// The file doesn't contain the 128-byte preamble followed by `DICM`.
    case missingPart10Preamble
    /// The input ended before the declared structure could be read.
    case truncatedData
    /// An Explicit VR element contains an unrecognised VR code.
    case invalidVR(String)
    /// The file uses a transfer syntax that the reader doesn't support.
    case unsupportedTransferSyntax(String)
    /// The File Meta Information doesn't contain a Transfer Syntax UID `(0002,0010)`.
    case missingTransferSyntaxUID
    /// A non-sequence element declares an undefined length.
    case unsupportedUndefinedLength(DICOMTag)
    /// A sequence contains an invalid Item or Sequence Delimitation Item.
    case invalidSequenceItem(DICOMTag)
    /// Encapsulated Pixel Data does not contain valid fragments.
    case invalidEncapsulatedPixelData
}
