/// An entry from a DICOMDIR Directory Record Sequence.
///
/// This value exposes each record's attributes in on-disk sequence order.
public struct DICOMDirectoryRecord: Sendable, Equatable {
    /// The Directory Record Type, such as `PATIENT`, `STUDY`, `SERIES`, or `IMAGE`.
    public let recordType: String
    /// Components of Referenced File ID, if the record refers to a file.
    public let referencedFileID: [String]?
    /// Referenced SOP Class UID in File, if present.
    public let referencedSOPClassUID: String?
    /// Referenced SOP Instance UID in File, if present.
    public let referencedSOPInstanceUID: String?
    /// The on-disk Item offset used by DICOMDIR offset links, if available.
    public let itemOffset: UInt32?

    /// Creates a directory record.
    public init(recordType: String, referencedFileID: [String]? = nil, referencedSOPClassUID: String? = nil, referencedSOPInstanceUID: String? = nil, itemOffset: UInt32? = nil) {
        self.recordType = recordType
        self.referencedFileID = referencedFileID
        self.referencedSOPClassUID = referencedSOPClassUID
        self.referencedSOPInstanceUID = referencedSOPInstanceUID
        self.itemOffset = itemOffset
    }
}

/// A DICOMDIR record together with its linked lower-level records.
public struct DICOMDirectoryNode: Sendable, Equatable {
    /// The directory record at this node.
    public let record: DICOMDirectoryRecord
    /// The record's lower-level directory entities.
    public let children: [DICOMDirectoryNode]

    /// Creates a DICOMDIR node.
    public init(record: DICOMDirectoryRecord, children: [DICOMDirectoryNode] = []) {
        self.record = record
        self.children = children
    }
}

/// A DICOMDIR view with both flat and offset-linked record hierarchies.
public struct DICOMDirectory: Sendable, Equatable {
    /// Records in the order they occur in the Directory Record Sequence.
    public let records: [DICOMDirectoryRecord]
    /// Root records reconstructed from standard DICOMDIR offset links.
    public let rootRecords: [DICOMDirectoryNode]

    /// Reads directory records from a DICOMDIR dataset.
    ///
    /// - Throws: ``DICOMError/invalidDICOMDirectory`` when the required
    ///   sequence or a record type is missing.
    public init(dataset: DICOMDataset) throws {
        guard let sequence = dataset[.directoryRecordSequence], let items = sequence.sequenceItems else {
            throw DICOMError.invalidDICOMDirectory
        }
        let offsets = sequence.sequenceItemOffsets ?? []
        guard offsets.isEmpty || offsets.count == items.count else { throw DICOMError.invalidDICOMDirectory }
        records = try items.enumerated().map { index, item in
            guard let recordType = item[.directoryRecordType]?.stringValue, !recordType.isEmpty else {
                throw DICOMError.invalidDICOMDirectory
            }
            return DICOMDirectoryRecord(
                recordType: recordType,
                referencedFileID: item[.referencedFileID]?.stringValues,
                referencedSOPClassUID: item[.referencedSOPClassUIDInFile]?.stringValue,
                referencedSOPInstanceUID: item[.referencedSOPInstanceUIDInFile]?.stringValue,
                itemOffset: offsets.isEmpty ? nil : offsets[index]
            )
        }
        guard let rootOffset = dataset[.offsetOfTheFirstDirectoryRecordOfTheRootDirectoryEntity]?.uint32Values?.first else {
            rootRecords = []
            return
        }
        guard !offsets.isEmpty else { throw DICOMError.invalidDICOMDirectory }
        let sourceRecords = Dictionary(uniqueKeysWithValues: items.enumerated().map { (offsets[$0.offset], $0.element) })
        let recordByOffset = Dictionary(uniqueKeysWithValues: records.compactMap { record in record.itemOffset.map { ($0, record) } })
        rootRecords = try Self.nodes(startingAt: rootOffset, recordByOffset: recordByOffset, sourceRecords: sourceRecords, visited: [])
    }

    private static func nodes(startingAt offset: UInt32, recordByOffset: [UInt32: DICOMDirectoryRecord], sourceRecords: [UInt32: DICOMDataset], visited: Set<UInt32>) throws -> [DICOMDirectoryNode] {
        guard offset != 0 else { return [] }
        var result: [DICOMDirectoryNode] = []
        var nextOffset: UInt32? = offset
        var visited = visited
        while let currentOffset = nextOffset, currentOffset != 0 {
            guard visited.insert(currentOffset).inserted,
                  let record = recordByOffset[currentOffset], let source = sourceRecords[currentOffset] else {
                throw DICOMError.invalidDICOMDirectory
            }
            let children = try nodes(
                startingAt: source[.offsetOfReferencedLowerLevelDirectoryEntity]?.uint32Values?.first ?? 0,
                recordByOffset: recordByOffset,
                sourceRecords: sourceRecords,
                visited: visited
            )
            result.append(DICOMDirectoryNode(record: record, children: children))
            nextOffset = source[.offsetOfTheNextDirectoryRecord]?.uint32Values?.first
        }
        return result
    }
}
