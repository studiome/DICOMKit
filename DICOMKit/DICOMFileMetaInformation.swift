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
}
