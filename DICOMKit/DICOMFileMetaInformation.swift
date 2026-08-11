import Foundation

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
}
