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
    /// For encapsulated pixel data (RLE Lossless, JPEG Baseline, and JPEG
    /// 2000), this uses the Pixel Data Basic Offset Table to recover fragment
    /// boundaries. Multi-frame encapsulated images without a Basic Offset
    /// Table aren't currently supported because their frame boundaries cannot
    /// be determined reliably.
    ///
    /// JPEG Baseline and JPEG 2000 frames are decoded through ImageIO, which
    /// produces 8-bit samples: frames declaring any other Bits Allocated
    /// yield `nil` rather than pixel data whose attributes contradict its
    /// bytes. Three-sample frames are relabelled `RGB` because ImageIO
    /// converts the JPEG's own color space (JPEG Baseline pixel data is
    /// usually `YBR_FULL_422`); single-sample frames keep their
    /// `MONOCHROME1` / `MONOCHROME2` interpretation and stored polarity.
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
        var outputPhotometric = PhotometricInterpretation(name: photometricInterpretation)
        var outputPlanarConfiguration = Int(dataset[.planarConfiguration]?.uint16Value ?? 0)
        switch transferSyntax {
        case .rleLossless:
            guard let frames = encapsulatedFrames(of: pixelElement, frameCount: frameCount) else { return nil }
            values = frames.compactMap { fragments in
                switch (samplesPerPixel, bitsAllocated) {
                case (1, 8): try? RLELosslessDecoder.decode8BitMonochrome(fragments: fragments, pixelCount: pixelCount)
                case (1, 16): try? RLELosslessDecoder.decode16BitMonochrome(fragments: fragments, pixelCount: pixelCount)
                case (3, 8): try? RLELosslessDecoder.decode8BitRGB(fragments: fragments, pixelCount: pixelCount)
                default: nil
                }
            }

        case .jpegBaseline, .jpeg2000Lossless, .jpeg2000:
            // ImageIO decodes these transfer syntaxes to 8-bit samples, so a
            // frame declaring any other Bits Allocated can't be represented
            // faithfully; saying so here beats handing back pixel data whose
            // attributes contradict its own bytes.
            guard bitsAllocated == 8,
                  let frames = encapsulatedFrames(of: pixelElement, frameCount: frameCount) else { return nil }
            switch (samplesPerPixel, outputPhotometric) {
            case (3, _):
                values = frames.compactMap {
                    try? JPEGFrameDecoder.decodeRGB(fragments: $0, width: Int(columns), height: Int(rows))
                }
                // ImageIO converts the JPEG's own color space, so the decoded
                // frame is interleaved RGB whatever the dataset declared
                // (JPEG Baseline pixel data is usually `YBR_FULL_422`).
                outputPhotometric = .rgb
                outputPlanarConfiguration = 0
            case (1, .monochrome1), (1, .monochrome2):
                // Decoded as single-sample grayscale, keeping the stored
                // polarity so `MONOCHROME1` still inverts when rendered.
                values = frames.compactMap {
                    try? JPEGFrameDecoder.decodeMonochrome(fragments: $0, width: Int(columns), height: Int(rows))
                }
            default:
                return nil
            }

        default:
            guard bitsAllocated.isMultiple(of: 8) else { return nil }
            let bytesPerFrame = pixelCount * Int(samplesPerPixel) * (Int(bitsAllocated) / 8)
            guard bytesPerFrame > 0, pixelElement.value.count >= bytesPerFrame * frameCount else { return nil }
            values = (0..<frameCount).map { frame in
                pixelElement.value.subdata(in: frame * bytesPerFrame..<(frame + 1) * bytesPerFrame)
            }
        }
        guard values.count == frameCount else { return nil }

        return values.map { value in DICOMPixelData(
            value: value,
            rows: Int(rows),
            columns: Int(columns),
            samplesPerPixel: Int(samplesPerPixel),
            bitsAllocated: Int(bitsAllocated),
            photometricInterpretation: outputPhotometric,
            planarConfiguration: outputPlanarConfiguration,
            bitsStored: dataset[.bitsStored]?.uint16Value.map(Int.init),
            pixelRepresentation: Int(dataset[.pixelRepresentation]?.uint16Value ?? 0),
            rescaleSlope: dataset[.rescaleSlope]?.doubleValue ?? 1.0,
            rescaleIntercept: dataset[.rescaleIntercept]?.doubleValue ?? 0.0,
            defaultWindowCenter: dataset[.windowCenter]?.doubleValue,
            defaultWindowWidth: dataset[.windowWidth]?.doubleValue
        ) }
    }

    /// The fragments of an encapsulated Pixel Data element, grouped per
    /// frame. `nil` if the element isn't encapsulated or its Basic Offset
    /// Table doesn't describe `frameCount` frames.
    private func encapsulatedFrames(of element: DICOMElement, frameCount: Int) -> [[Data]]? {
        guard let fragments = element.encapsulatedFragments,
              let fragmentOffsets = element.encapsulatedFragmentOffsets,
              let basicOffsetTable = element.basicOffsetTable else {
            return nil
        }
        return try? EncapsulatedPixelData.frameFragments(
            fragments: fragments,
            fragmentOffsets: fragmentOffsets,
            basicOffsetTable: basicOffsetTable,
            frameCount: frameCount
        )
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
        guard transferSyntax.isSupported else {
            throw DICOMError.unsupportedTransferSyntax(uid)
        }

        dataset = DICOMDataset(elements: try reader.readDataset(transferSyntax: transferSyntax))
    }
}
