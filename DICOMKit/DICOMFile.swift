import Foundation

/// A parsed DICOM Part 10 file.
public struct DICOMFile: Sendable {
    /// The File Meta Information dataset (group `0002`).
    public let metaInformation: DICOMDataset
    /// The main DICOM dataset.
    public let dataset: DICOMDataset
    /// The transfer syntax declared by the File Meta Information.
    public let transferSyntax: TransferSyntax

    /// The first frame of ``pixelDataFrames``, if available.
    ///
    /// `nil` if `(7FE0,0010)` Pixel Data is absent, or if any of the
    /// following required attributes is absent: Rows `(0028,0010)`, Columns
    /// `(0028,0011)`, Samples per Pixel `(0028,0002)`, Bits Allocated
    /// `(0028,0100)`, or Photometric Interpretation `(0028,0004)`. Because
    /// both causes produce the same `nil` result, this property alone can't
    /// distinguish "no Pixel Data in this file" from "Pixel Data is present
    /// but its metadata is incomplete"; inspect `dataset[.pixelData]`
    /// directly if that distinction matters.
    ///
    /// Planar Configuration, Bits Stored, Pixel Representation, Rescale
    /// Slope, Rescale Intercept, Window Center, and Window Width are optional
    /// and fall back to their DICOM default (or `nil`, for the window
    /// values) when absent, so their absence never causes this property to
    /// return `nil`.
    public var pixelData: DICOMPixelData? {
        pixelDataFrames?.first
    }

    /// The image frames contained by Pixel Data.
    ///
    /// For RLE Lossless multi-frame images, this uses the encapsulated Pixel
    /// Data Basic Offset Table to retain fragment boundaries. Multi-frame RLE
    /// images without a Basic Offset Table aren't currently supported because
    /// their frame boundaries cannot be determined reliably.
    public var pixelDataFrames: [DICOMPixelData]? {
        guard let pixelElement = dataset[.pixelData],
              let rows = dataset[.rows]?.uint16Value,
              let columns = dataset[.columns]?.uint16Value,
              let samplesPerPixel = dataset[.samplesPerPixel]?.uint16Value,
              let bitsAllocated = dataset[.bitsAllocated]?.uint16Value,
              let photometricInterpretation = dataset[.photometricInterpretation]?.stringValue else {
            return nil
        }
        guard let frameCount = Int(dataset[.numberOfFrames]?.stringValue ?? "1"), frameCount > 0 else { return nil }
        let pixelCount = Int(rows) * Int(columns)
        let values: [Data]
        switch transferSyntax {
        case .rleLossless:
            guard let fragments = pixelElement.encapsulatedFragments,
                  let fragmentOffsets = pixelElement.encapsulatedFragmentOffsets,
                  let basicOffsetTable = pixelElement.basicOffsetTable,
                  let frameFragments = try? RLELosslessDecoder.frameFragments(
                    fragments: fragments,
                    fragmentOffsets: fragmentOffsets,
                    basicOffsetTable: basicOffsetTable,
                    frameCount: frameCount
                  ) else {
                return nil
            }
            values = frameFragments.compactMap { fragments in
                switch (samplesPerPixel, bitsAllocated) {
                case (1, 8): try? RLELosslessDecoder.decode8BitMonochrome(fragments: fragments, pixelCount: pixelCount)
                case (1, 16): try? RLELosslessDecoder.decode16BitMonochrome(fragments: fragments, pixelCount: pixelCount)
                case (3, 8): try? RLELosslessDecoder.decode8BitRGB(fragments: fragments, pixelCount: pixelCount)
                default: nil
                }
            }
            guard values.count == frameCount else { return nil }
        default:
            guard bitsAllocated.isMultiple(of: 8) else { return nil }
            let bytesPerFrame = pixelCount * Int(samplesPerPixel) * (Int(bitsAllocated) / 8)
            guard bytesPerFrame > 0, pixelElement.value.count >= bytesPerFrame * frameCount else { return nil }
            values = (0..<frameCount).map { frame in
                pixelElement.value.subdata(in: frame * bytesPerFrame..<(frame + 1) * bytesPerFrame)
            }
        }
        return values.map { value in DICOMPixelData(
            value: value,
            rows: Int(rows),
            columns: Int(columns),
            samplesPerPixel: Int(samplesPerPixel),
            bitsAllocated: Int(bitsAllocated),
            photometricInterpretation: PhotometricInterpretation(name: photometricInterpretation),
            planarConfiguration: Int(dataset[.planarConfiguration]?.uint16Value ?? 0),
            bitsStored: dataset[.bitsStored]?.uint16Value.map(Int.init),
            pixelRepresentation: Int(dataset[.pixelRepresentation]?.uint16Value ?? 0),
            rescaleSlope: dataset[.rescaleSlope]?.doubleValue ?? 1.0,
            rescaleIntercept: dataset[.rescaleIntercept]?.doubleValue ?? 0.0,
            defaultWindowCenter: dataset[.windowCenter]?.doubleValue,
            defaultWindowWidth: dataset[.windowWidth]?.doubleValue
        ) }
    }

    /// Parses a DICOM Part 10 file from memory.
    ///
    /// The reader supports Explicit VR Little Endian and Implicit VR Little
    /// Endian datasets, including defined-length and undefined-length sequences.
    ///
    /// - Parameter input: The complete contents of a DICOM Part 10 file.
    /// - Throws: ``DICOMError`` if the file is malformed or uses an unsupported syntax.
    public init(data input: Data) throws {
        // `Data` slices retain the absolute indices of their underlying buffer,
        // so a slice such as `buffer[500...]` has `startIndex == 500`. Reading
        // it with fixed offsets (like the preamble check below, or the `Reader`
        // that follows) would either trap on an out-of-bounds index or silently
        // read the wrong bytes. Copying into a fresh, zero-based buffer here
        // makes every subsequent offset in this initializer and in `Reader`
        // safe regardless of what kind of `Data` the caller passed in.
        let data = Data(input)
        guard data.count >= 132, data[128...131] == Data("DICM".utf8) else {
            throw DICOMError.missingPart10Preamble
        }

        var reader = Reader(data: data, offset: 132)
        var metaElements: [DICOMElement] = []
        while reader.peekTag()?.group == 0x0002 {
            metaElements.append(try reader.readElement(transferSyntax: .explicitVRLittleEndian))
        }
        metaInformation = DICOMDataset(elements: metaElements)

        guard let uid = metaInformation[.transferSyntaxUID]?.stringValue else {
            throw DICOMError.missingTransferSyntaxUID
        }
        transferSyntax = TransferSyntax(uid: uid)
        guard transferSyntax == .explicitVRLittleEndian || transferSyntax == .implicitVRLittleEndian || transferSyntax == .rleLossless else {
            throw DICOMError.unsupportedTransferSyntax(uid)
        }

        dataset = DICOMDataset(elements: try reader.readDataset(transferSyntax: transferSyntax))
    }
}
