import Foundation

/// Metadata retained from a file while Pixel Data is loaded only on demand.
///
/// Construct this value from a local URL when a browser or worklist needs
/// metadata before it needs image bytes. Initial parsing validates the source
/// file, then releases the parsed Pixel Data value. `makeLazyPixelData()`
/// reopens the URL only when a consumer requests frames.
public struct DICOMMetadataFile: Sendable {
    public let metaInformation: DICOMDataset
    public let dataset: DICOMDataset
    public let transferSyntax: TransferSyntax
    private let sourceURL: URL

    /// Parses a local Part 10 file with mapped-data preference and drops Pixel Data after metadata extraction.
    public init(url: URL) throws {
        let file = try DICOMFile(url: url)
        metaInformation = file.metaInformation
        dataset = DICOMDataset(elements: file.dataset.filter { $0.tag != .pixelData && $0.tag != .floatPixelData && $0.tag != .doubleFloatPixelData })
        transferSyntax = file.transferSyntax
        sourceURL = url
    }

    /// Returns a frame loader that reopens the source URL on its first load.
    public func makeLazyPixelData() -> DICOMLazyPixelData? {
        guard transferSyntax.usesEncapsulatedPixelData || dataset[.rows] != nil else { return nil }
        return DICOMLazyPixelData { try? DICOMFile(url: sourceURL).pixelDataFrames }
    }
}
