import Foundation

/// Errors reported when File Meta Information does not match its dataset.
public enum DICOMFileMetaValidationError: Error, Sendable, Equatable {
    /// The File Meta Information lacks a required non-empty identifier.
    case missingRequiredIdentifier
    /// Media Storage SOP Class UID does not match the dataset SOP Class UID.
    case sopClassUIDMismatch
    /// Media Storage SOP Instance UID does not match the dataset SOP Instance UID.
    case sopInstanceUIDMismatch
}

/// Required File Meta Information identifiers for writing an interoperable
/// DICOM Part 10 file.
public struct DICOMFileMetaInformation: Sendable, Equatable {
    public let mediaStorageSOPClassUID: String
    public let mediaStorageSOPInstanceUID: String
    public let implementationClassUID: String
    public let implementationVersionName: String?

    public init(mediaStorageSOPClassUID: String, mediaStorageSOPInstanceUID: String, implementationClassUID: String, implementationVersionName: String? = nil) {
        self.mediaStorageSOPClassUID = mediaStorageSOPClassUID
        self.mediaStorageSOPInstanceUID = mediaStorageSOPInstanceUID
        self.implementationClassUID = implementationClassUID
        self.implementationVersionName = implementationVersionName
    }

    /// Derives media-storage identifiers from a dataset's SOP identifiers.
    public init(dataset: DICOMDataset, implementationClassUID: String, implementationVersionName: String? = nil) throws {
        guard let sopClassUID = dataset[.sopClassUID]?.stringValue, !sopClassUID.isEmpty else {
            throw DICOMError.missingSOPClassUID
        }
        guard let sopInstanceUID = dataset[.sopInstanceUID]?.stringValue, !sopInstanceUID.isEmpty else {
            throw DICOMError.missingSOPInstanceUID
        }
        self.init(
            mediaStorageSOPClassUID: sopClassUID,
            mediaStorageSOPInstanceUID: sopInstanceUID,
            implementationClassUID: implementationClassUID,
            implementationVersionName: implementationVersionName
        )
    }

    /// Validates required File Meta identifiers and their consistency with a dataset.
    public func validate(against dataset: DICOMDataset) throws {
        guard !mediaStorageSOPClassUID.isEmpty, !mediaStorageSOPInstanceUID.isEmpty, !implementationClassUID.isEmpty else {
            throw DICOMFileMetaValidationError.missingRequiredIdentifier
        }
        guard dataset[.sopClassUID]?.stringValue == mediaStorageSOPClassUID else {
            throw DICOMFileMetaValidationError.sopClassUIDMismatch
        }
        guard dataset[.sopInstanceUID]?.stringValue == mediaStorageSOPInstanceUID else {
            throw DICOMFileMetaValidationError.sopInstanceUIDMismatch
        }
    }
}
