import Foundation

/// A byte range for native Pixel Data in a local Part 10 file.
///
/// The range starts at the Pixel Data value, after its data-element header.
/// Reading it does not parse or retain the rest of the file again.
public struct DICOMNativePixelDataReference: Sendable, Equatable {
    public let url: URL
    public let range: Range<Int>

    /// Reads exactly the native Pixel Data value from disk.
    public func load() throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(range.lowerBound))
        let data = try handle.read(upToCount: range.count) ?? Data()
        guard data.count == range.count else { throw DICOMError.truncatedData }
        return data
    }
}

/// Metadata retained from a file while Pixel Data is loaded only on demand.
///
/// For ordinary (non-deflated) native Pixel Data, parsing skips the value
/// entirely and retains only its file range. This avoids both the encoded
/// Pixel Data allocation and a second complete-file parse before a caller
/// actually asks for the bytes.
public struct DICOMMetadataFile: Sendable {
    public let metaInformation: DICOMDataset
    public let dataset: DICOMDataset
    public let transferSyntax: TransferSyntax
    public let nativePixelDataReference: DICOMNativePixelDataReference?
    private let sourceURL: URL

    public init(url: URL) throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count >= 132, data[128...131] == Data("DICM".utf8) else { throw DICOMError.missingPart10Preamble }
        var reader = Reader(data: data, offset: 132)
        var meta: [DICOMElement] = []
        while reader.peekTag()?.group == 0x0002 { meta.append(try reader.readElement(transferSyntax: .explicitVRLittleEndian)) }
        let metadata = DICOMDataset(elements: meta)
        guard let uid = metadata[.transferSyntaxUID]?.stringValue else { throw DICOMError.missingTransferSyntaxUID }
        let syntax = TransferSyntax(uid: uid)
        guard syntax.isSupported else { throw DICOMError.unsupportedTransferSyntax(uid) }
        metaInformation = metadata
        transferSyntax = syntax
        sourceURL = url

        if syntax == .deflatedExplicitVRLittleEndian {
            let decoded = try DeflateCodec.inflateRaw(data.subdata(in: reader.offset..<data.count))
            var inflated = Reader(data: decoded, offset: 0)
            dataset = DICOMDataset(elements: try inflated.readDataset(transferSyntax: .explicitVRLittleEndian))
            nativePixelDataReference = nil
        } else {
            reader.skipsNativePixelData = !syntax.usesEncapsulatedPixelData
            dataset = DICOMDataset(elements: try reader.readDataset(transferSyntax: syntax).filter { $0.tag != .pixelData && $0.tag != .floatPixelData && $0.tag != .doubleFloatPixelData })
            nativePixelDataReference = reader.skippedNativePixelDataRange.map { DICOMNativePixelDataReference(url: url, range: $0) }
        }
    }

    /// Returns a frame loader. Prefer ``nativePixelDataReference`` for native
    /// Pixel Data when callers only need its encoded bytes.
    public func makeLazyPixelData() -> DICOMLazyPixelData? {
        guard transferSyntax.usesEncapsulatedPixelData || nativePixelDataReference != nil else { return nil }
        return DICOMLazyPixelData { try? DICOMFile(url: sourceURL).pixelDataFrames }
    }
}
