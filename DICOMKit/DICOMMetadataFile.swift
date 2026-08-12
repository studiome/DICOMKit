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

/// File ranges for encapsulated Pixel Data fragments without retained JPEG,
/// JPEG-LS, JPEG 2000, or RLE payload bytes.
public struct DICOMEncapsulatedPixelDataReference: Sendable, Equatable {
    public let url: URL
    public let basicOffsetTable: Data
    public let fragmentRanges: [Range<Int>]

    /// Loads one compressed fragment on demand.
    public func loadFragment(at index: Int) throws -> Data {
        guard fragmentRanges.indices.contains(index) else { throw DICOMError.invalidEncapsulatedPixelData }
        let range = fragmentRanges[index]
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(range.lowerBound))
        let data = try handle.read(upToCount: range.count) ?? Data()
        guard data.count == range.count else { throw DICOMError.truncatedData }
        return data
    }

    /// Loads just the compressed fragments belonging to one Basic Offset Table
    /// frame. An empty offset table is unambiguous only for a single frame.
    public func loadFrameFragments(frameIndex: Int, numberOfFrames: Int = 1) throws -> [Data] {
        guard frameIndex >= 0, numberOfFrames > 0 else { throw DICOMError.invalidEncapsulatedPixelData }
        guard !basicOffsetTable.isEmpty else {
            guard numberOfFrames == 1, frameIndex == 0 else { throw DICOMError.invalidEncapsulatedPixelData }
            return try fragmentRanges.indices.map(loadFragment(at:))
        }
        guard basicOffsetTable.count.isMultiple(of: 4) else { throw DICOMError.invalidEncapsulatedPixelData }
        var offsets: [Int] = []
        for index in stride(from: 0, to: basicOffsetTable.count, by: 4) {
            let low = UInt32(basicOffsetTable[index]) | UInt32(basicOffsetTable[index + 1]) << 8
            let high = UInt32(basicOffsetTable[index + 2]) << 16 | UInt32(basicOffsetTable[index + 3]) << 24
            offsets.append(Int(low | high))
        }
        guard offsets.indices.contains(frameIndex), let firstRange = fragmentRanges.first else { throw DICOMError.invalidEncapsulatedPixelData }
        let lower = offsets[frameIndex]
        let upper = frameIndex + 1 < offsets.count ? offsets[frameIndex + 1] : .max
        let base = firstRange.lowerBound - 8
        let indexes = fragmentRanges.indices.filter { index in
            let relativeItemOffset = fragmentRanges[index].lowerBound - 8 - base
            return relativeItemOffset >= lower && relativeItemOffset < upper
        }
        guard !indexes.isEmpty else { throw DICOMError.invalidEncapsulatedPixelData }
        return try indexes.map(loadFragment(at:))
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
    public let encapsulatedPixelDataReference: DICOMEncapsulatedPixelDataReference?
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
            encapsulatedPixelDataReference = nil
        } else {
            reader.skipsNativePixelData = !syntax.usesEncapsulatedPixelData
            reader.skipsEncapsulatedPixelData = syntax.usesEncapsulatedPixelData
            dataset = DICOMDataset(elements: try reader.readDataset(transferSyntax: syntax).filter { $0.tag != .pixelData && $0.tag != .floatPixelData && $0.tag != .doubleFloatPixelData })
            nativePixelDataReference = reader.skippedNativePixelDataRange.map { DICOMNativePixelDataReference(url: url, range: $0) }
            if let table = reader.skippedBasicOffsetTable, let ranges = reader.skippedEncapsulatedFragmentRanges {
                encapsulatedPixelDataReference = DICOMEncapsulatedPixelDataReference(url: url, basicOffsetTable: table, fragmentRanges: ranges)
            } else {
                encapsulatedPixelDataReference = nil
            }
        }
    }

    /// Returns a frame loader. Prefer ``nativePixelDataReference`` for native
    /// Pixel Data when callers only need its encoded bytes.
    public func makeLazyPixelData() -> DICOMLazyPixelData? {
        guard transferSyntax.usesEncapsulatedPixelData || nativePixelDataReference != nil else { return nil }
        return DICOMLazyPixelData { try? DICOMFile(url: sourceURL).pixelDataFrames }
    }

    /// Loads native frames directly from ``nativePixelDataReference`` without
    /// reparsing the Part 10 file. Returns `nil` when required image metadata
    /// is absent or the Pixel Data value does not match its declared geometry.
    public func nativePixelDataFrames() throws -> [DICOMPixelData]? {
        guard let reference = nativePixelDataReference,
              let rows = dataset[.rows]?.uint16Value,
              let columns = dataset[.columns]?.uint16Value,
              let samples = dataset[.samplesPerPixel]?.uint16Value,
              let bits = dataset[.bitsAllocated]?.uint16Value,
              let photometricName = dataset[.photometricInterpretation]?.stringValue,
              bits.isMultiple(of: 8),
              let frames = Int(dataset[.numberOfFrames]?.stringValue ?? "1"), frames > 0 else { return nil }
        let bytesPerFrame = Int(rows) * Int(columns) * Int(samples) * (Int(bits) / 8)
        guard bytesPerFrame > 0 else { return nil }
        let value = try reference.load()
        guard value.count >= bytesPerFrame * frames else { return nil }
        return (0..<frames).map { index in
            DICOMPixelData(
                value: value.subdata(in: index * bytesPerFrame..<(index + 1) * bytesPerFrame),
                rows: Int(rows), columns: Int(columns), samplesPerPixel: Int(samples), bitsAllocated: Int(bits),
                photometricInterpretation: PhotometricInterpretation(name: photometricName),
                planarConfiguration: Int(dataset[.planarConfiguration]?.uint16Value ?? 0),
                bitsStored: dataset[.bitsStored]?.uint16Value.map(Int.init),
                pixelRepresentation: Int(dataset[.pixelRepresentation]?.uint16Value ?? 0),
                rescaleSlope: dataset[.rescaleSlope]?.doubleValue ?? 1,
                rescaleIntercept: dataset[.rescaleIntercept]?.doubleValue ?? 0,
                defaultWindowCenter: dataset[.windowCenter]?.doubleValue,
                defaultWindowWidth: dataset[.windowWidth]?.doubleValue
            )
        }
    }
}
