/// An entry from a DICOMDIR Directory Record Sequence.
///
/// This value exposes each record's attributes in on-disk sequence order. It
/// does not interpret the offset links that form the DICOMDIR hierarchy.
public struct DICOMDirectoryRecord: Sendable, Equatable {
    /// The Directory Record Type, such as `PATIENT`, `STUDY`, `SERIES`, or `IMAGE`.
    public let recordType: String
    /// Components of Referenced File ID, if the record refers to a file.
    public let referencedFileID: [String]?
    /// Referenced SOP Class UID in File, if present.
    public let referencedSOPClassUID: String?
    /// Referenced SOP Instance UID in File, if present.
    public let referencedSOPInstanceUID: String?

    /// Creates a directory record.
    public init(recordType: String, referencedFileID: [String]? = nil, referencedSOPClassUID: String? = nil, referencedSOPInstanceUID: String? = nil) {
        self.recordType = recordType
        self.referencedFileID = referencedFileID
        self.referencedSOPClassUID = referencedSOPClassUID
        self.referencedSOPInstanceUID = referencedSOPInstanceUID
    }
}

/// A flat view of the DICOMDIR Directory Record Sequence.
public struct DICOMDirectory: Sendable, Equatable {
    /// Records in the order they occur in the Directory Record Sequence.
    public let records: [DICOMDirectoryRecord]

    /// Reads directory records from a DICOMDIR dataset.
    ///
    /// - Throws: ``DICOMError/invalidDICOMDirectory`` when the required
    ///   sequence or a record type is missing.
    public init(dataset: DICOMDataset) throws {
        guard let items = dataset[.directoryRecordSequence]?.sequenceItems else {
            throw DICOMError.invalidDICOMDirectory
        }
        records = try items.map { item in
            guard let recordType = item[.directoryRecordType]?.stringValue, !recordType.isEmpty else {
                throw DICOMError.invalidDICOMDirectory
            }
            return DICOMDirectoryRecord(
                recordType: recordType,
                referencedFileID: item[.referencedFileID]?.stringValues,
                referencedSOPClassUID: item[.referencedSOPClassUIDInFile]?.stringValue,
                referencedSOPInstanceUID: item[.referencedSOPInstanceUIDInFile]?.stringValue
            )
        }
    }
}
