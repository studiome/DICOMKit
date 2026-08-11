import Foundation

/// A DICOM Person Name (PN) split into its three representation groups.
public struct DICOMPersonName: Sendable, Equatable {
    public let alphabetic: String?
    public let ideographic: String?
    public let phonetic: String?

    init(_ value: String) {
        let groups = value.split(separator: "=", maxSplits: 2, omittingEmptySubsequences: false)
        alphabetic = groups.indices.contains(0) ? String(groups[0]) : nil
        ideographic = groups.indices.contains(1) ? String(groups[1]) : nil
        phonetic = groups.indices.contains(2) ? String(groups[2]) : nil
    }
}
