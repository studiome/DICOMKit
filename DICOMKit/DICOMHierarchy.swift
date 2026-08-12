import Foundation

/// A DICOM instance with fields used for deterministic series ordering.
public struct DICOMInstance: Sendable {
    public let file: DICOMFile
    public let sopInstanceUID: String?
    public let instanceNumber: Int?
    public let imagePositionPatient: [Double]?

    public init(file: DICOMFile) {
        self.file = file
        sopInstanceUID = file.dataset.stringValue(for: .sopInstanceUID)
        instanceNumber = file.dataset[.instanceNumber]?.stringValue.flatMap(Int.init)
        imagePositionPatient = file.imageGeometry?.imagePositionPatient
    }
}

/// A DICOM series that keeps its instances in display order.
public struct DICOMSeries: Sendable {
    public let seriesInstanceUID: String
    public let instances: [DICOMInstance]

    public init(seriesInstanceUID: String, instances: [DICOMInstance]) {
        self.seriesInstanceUID = seriesInstanceUID
        self.instances = instances.sorted(by: Self.isOrderedBefore)
    }

    private static func isOrderedBefore(_ lhs: DICOMInstance, _ rhs: DICOMInstance) -> Bool {
        if let left = lhs.imagePositionPatient?.last, let right = rhs.imagePositionPatient?.last, left != right { return left < right }
        if let left = lhs.instanceNumber, let right = rhs.instanceNumber, left != right { return left < right }
        return (lhs.sopInstanceUID ?? "") < (rhs.sopInstanceUID ?? "")
    }
}

/// A DICOM study grouped into its contained series.
public struct DICOMStudy: Sendable {
    public let studyInstanceUID: String
    public let series: [DICOMSeries]

    /// Groups files sharing the supplied Study Instance UID into series.
    public init(studyInstanceUID: String, files: [DICOMFile]) {
        self.studyInstanceUID = studyInstanceUID
        let grouped = Dictionary(grouping: files, by: { $0.dataset.stringValue(for: .seriesInstanceUID) ?? "" })
        series = grouped.keys.sorted().map { uid in DICOMSeries(seriesInstanceUID: uid, instances: grouped[uid]!.map(DICOMInstance.init)) }
    }
}
