import Foundation

/// A decoded encapsulated frame together with the storage attributes that
/// describe the decoder's output bytes.
///
/// Decoders must declare these rather than assuming every compressed syntax
/// produces 8-bit data. JPEG Lossless and JPEG-LS will use this to return
/// 16-bit samples without changing the surrounding Pixel Data pipeline.
private struct DecodedPixelDataFrame {
    let value: Data
    let samplesPerPixel: Int
    let bitsAllocated: Int
    let photometricInterpretation: PhotometricInterpretation
    let planarConfiguration: Int
}

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
    /// For encapsulated pixel data, this uses the Pixel Data Basic Offset
    /// Table to recover fragment boundaries. Multi-frame encapsulated images
    /// without a Basic Offset Table aren't currently supported because their
    /// frame boundaries cannot be determined reliably.
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
        let sourceSamplesPerPixel = Int(samplesPerPixel)
        let sourceBitsAllocated = Int(bitsAllocated)
        let sourcePhotometric = PhotometricInterpretation(name: photometricInterpretation)
        let sourcePlanarConfiguration = Int(dataset[.planarConfiguration]?.uint16Value ?? 0)
        let frames: [DecodedPixelDataFrame]
        switch transferSyntax {
        case .rleLossless:
            guard let fragmentFrames = encapsulatedFrames(of: pixelElement, frameCount: frameCount) else { return nil }
            frames = fragmentFrames.compactMap { fragments in
                let value: Data?
                switch (samplesPerPixel, bitsAllocated) {
                case (1, 8): value = try? RLELosslessDecoder.decode8BitMonochrome(fragments: fragments, pixelCount: pixelCount)
                case (1, 16): value = try? RLELosslessDecoder.decode16BitMonochrome(fragments: fragments, pixelCount: pixelCount)
                case (3, 8): value = try? RLELosslessDecoder.decode8BitRGB(fragments: fragments, pixelCount: pixelCount)
                default: value = nil
                }
                guard let value else { return nil }
                return DecodedPixelDataFrame(
                    value: value,
                    samplesPerPixel: sourceSamplesPerPixel,
                    bitsAllocated: sourceBitsAllocated,
                    photometricInterpretation: sourcePhotometric,
                    planarConfiguration: sourcePlanarConfiguration
                )
            }

        case .jpegBaseline, .jpeg2000Lossless, .jpeg2000:
            // ImageIO decodes these transfer syntaxes to 8-bit samples, so a
            // frame declaring any other Bits Allocated can't be represented
            // faithfully; saying so here beats handing back pixel data whose
            // attributes contradict its own bytes.
            guard bitsAllocated == 8,
                  let fragmentFrames = encapsulatedFrames(of: pixelElement, frameCount: frameCount) else { return nil }
            switch (samplesPerPixel, sourcePhotometric) {
            case (3, _):
                frames = fragmentFrames.compactMap {
                    guard let value = try? JPEGFrameDecoder.decodeRGB(fragments: $0, width: Int(columns), height: Int(rows)) else {
                        return nil
                    }
                    return DecodedPixelDataFrame(
                        value: value,
                        samplesPerPixel: 3,
                        bitsAllocated: 8,
                        photometricInterpretation: .rgb,
                        planarConfiguration: 0
                    )
                }
                // ImageIO converts the JPEG's own color space, so the decoded
                // frame is interleaved RGB whatever the dataset declared
                // (JPEG Baseline pixel data is usually `YBR_FULL_422`).
            case (1, .monochrome1), (1, .monochrome2):
                // Decoded as single-sample grayscale, keeping the stored
                // polarity so `MONOCHROME1` still inverts when rendered.
                frames = fragmentFrames.compactMap {
                    guard let value = try? JPEGFrameDecoder.decodeMonochrome(fragments: $0, width: Int(columns), height: Int(rows)) else {
                        return nil
                    }
                    return DecodedPixelDataFrame(
                        value: value,
                        samplesPerPixel: 1,
                        bitsAllocated: 8,
                        photometricInterpretation: sourcePhotometric,
                        planarConfiguration: sourcePlanarConfiguration
                    )
                }
            default:
                return nil
            }

        case .jpegLossless, .jpegLosslessSV1, .jpegLSLossless, .jpegLSNearLossless:
            // These syntaxes must never fall through to the raw-data path or
            // ImageIO. Both decoders are intentionally added in later phases.
            return nil

        default:
            guard bitsAllocated.isMultiple(of: 8) else { return nil }
            let bytesPerFrame = pixelCount * Int(samplesPerPixel) * (Int(bitsAllocated) / 8)
            guard bytesPerFrame > 0, pixelElement.value.count >= bytesPerFrame * frameCount else { return nil }
            frames = (0..<frameCount).map { frame in
                DecodedPixelDataFrame(
                    value: pixelElement.value.subdata(in: frame * bytesPerFrame..<(frame + 1) * bytesPerFrame),
                    samplesPerPixel: sourceSamplesPerPixel,
                    bitsAllocated: sourceBitsAllocated,
                    photometricInterpretation: sourcePhotometric,
                    planarConfiguration: sourcePlanarConfiguration
                )
            }
        }
        guard frames.count == frameCount else { return nil }

        return frames.map { frame in DICOMPixelData(
            value: frame.value,
            rows: Int(rows),
            columns: Int(columns),
            samplesPerPixel: frame.samplesPerPixel,
            bitsAllocated: frame.bitsAllocated,
            photometricInterpretation: frame.photometricInterpretation,
            planarConfiguration: frame.planarConfiguration,
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
