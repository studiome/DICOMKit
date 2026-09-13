/// Errors produced while reading a DICOM Part 10 file.
public enum DICOMError: Error, Sendable, Equatable {
    case invalidUIDRoot
    /// A Deflated Explicit VR Little Endian dataset could not be decompressed.
    case invalidDeflatedData
    /// A DICOM JSON representation cannot be converted to a DICOM element.
    case invalidDICOMJSON
    /// A DICOMDIR dataset does not contain a valid Directory Record Sequence.
    case invalidDICOMDirectory
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
    /// A dataset's SOP Class UID `(0008,0016)` is present but is not
    /// Grayscale Softcopy Presentation State Storage.
    case invalidPresentationState
    /// A ``DICOMPrivateTagEntry`` declares an even group; private attributes
    /// live only in odd groups.
    case invalidPrivateDictionary
    /// A dataset has no Value Type `(0040,A040)` at all, so it isn't a
    /// Structured Report, or its Content Sequence nests deeper than
    /// ``DICOMStructuredReport`` is willing to recurse.
    case invalidStructuredReport
    /// A sequence nests deeper than `Reader` is willing to recurse. Every
    /// dataset-parsing entry point (``DICOMFile``, ``DICOMMetadataFile``,
    /// and the `UN`-to-`SQ` re-interpretation of a defined-length unknown
    /// sequence) shares this bound, guarding against a malformed or hostile
    /// dataset driving unbounded recursion and overflowing the call stack.
    case sequenceNestingTooDeep
}
