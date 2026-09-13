import DICOMKit
import Foundation

extension DICOMFile {
    /// Serializes this file as a DICOM Part 10 byte stream.
    ///
    /// This calls into ``DICOMWriter/write(metaInformation:dataset:transferSyntax:requiredMetaInformation:sequenceLengthEncoding:)``,
    /// the Part 10 file-assembly half of `DICOMWriter` that lives in
    /// `DICOMKitAuthoring`. A caller that only needs a raw dataset payload
    /// (for example a DIMSE service such as C-STORE) should use
    /// ``encodedDatasetData(transferSyntax:sequenceLengthEncoding:)``
    /// instead, which stays in `DICOMKit` and needs no authoring dependency.
    public func encodedData(sequenceLengthEncoding: DICOMWriter.SequenceLengthEncoding = .defined) throws -> Data {
        try DICOMWriter.write(metaInformation: metaInformation, dataset: dataset, transferSyntax: transferSyntax, sequenceLengthEncoding: sequenceLengthEncoding)
    }
}
