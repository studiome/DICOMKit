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
    let bitsStored: Int?
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
    /// JPEG Baseline frames are decoded through libjpeg-turbo and JPEG 2000
    /// frames through ImageIO. Both produce 8-bit samples: frames declaring
    /// any other Bits Allocated yield `nil` rather than pixel data whose
    /// attributes contradict its bytes. Three-sample frames are relabelled
    /// `RGB` because both decoders convert the JPEG's own color space (JPEG
    /// Baseline pixel data is usually `YBR_FULL_422`); single-sample frames keep their
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
        let paletteColorLUT = sourcePhotometric == .paletteColor ? makePaletteColorLUT() : nil
        let windowPresets = makeWindowPresets()
        let voiLUTs = makeVOILUTs()
        guard sourcePhotometric != .paletteColor || paletteColorLUT != nil else { return nil }
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
                case (3, 16): value = try? RLELosslessDecoder.decode16BitRGB(fragments: fragments, pixelCount: pixelCount)
                default: value = nil
                }
                guard let value else { return nil }
                return DecodedPixelDataFrame(
                    value: value,
                    samplesPerPixel: sourceSamplesPerPixel,
                    bitsAllocated: sourceBitsAllocated,
                    bitsStored: nil,
                    photometricInterpretation: sourcePhotometric,
                    planarConfiguration: sourceSamplesPerPixel == 3 ? 0 : sourcePlanarConfiguration
                )
            }

        case .jpegBaseline, .jpeg2000Lossless, .jpeg2000:
            // These backends decode their transfer syntaxes to 8-bit samples, so a
            // frame declaring any other Bits Allocated can't be represented
            // faithfully; saying so here beats handing back pixel data whose
            // attributes contradict its own bytes.
            guard bitsAllocated == 8,
                  let fragmentFrames = encapsulatedFrames(of: pixelElement, frameCount: frameCount) else { return nil }
            let decodeRGB: ([Data], Int, Int) throws -> Data = { fragments, width, height in
                switch transferSyntax {
                case .jpegBaseline:
                    return try TurboJPEGDecoder.decodeRGB(fragments: fragments, width: width, height: height)
                case .jpeg2000Lossless, .jpeg2000:
                    return try JPEGFrameDecoder.decodeRGB(fragments: fragments, width: width, height: height)
                default:
                    preconditionFailure("Validated JPEG-family transfer syntax")
                }
            }
            let decodeMonochrome: ([Data], Int, Int) throws -> Data = { fragments, width, height in
                switch transferSyntax {
                case .jpegBaseline:
                    return try TurboJPEGDecoder.decodeMonochrome(fragments: fragments, width: width, height: height)
                case .jpeg2000Lossless, .jpeg2000:
                    return try JPEGFrameDecoder.decodeMonochrome(fragments: fragments, width: width, height: height)
                default:
                    preconditionFailure("Validated JPEG-family transfer syntax")
                }
            }
            switch (samplesPerPixel, sourcePhotometric) {
            case (3, _):
                frames = fragmentFrames.compactMap {
                    guard let value = try? decodeRGB($0, Int(columns), Int(rows)) else {
                        return nil
                    }
                    return DecodedPixelDataFrame(
                        value: value,
                        samplesPerPixel: 3,
                        bitsAllocated: 8,
                        bitsStored: nil,
                        photometricInterpretation: .rgb,
                        planarConfiguration: 0
                    )
                }
                // The decoder converts the JPEG's own color space, so the decoded
                // frame is interleaved RGB whatever the dataset declared
                // (JPEG Baseline pixel data is usually `YBR_FULL_422`).
            case (1, .monochrome1), (1, .monochrome2):
                // Decoded as single-sample grayscale, keeping the stored
                // polarity so `MONOCHROME1` still inverts when rendered.
                frames = fragmentFrames.compactMap {
                    guard let value = try? decodeMonochrome($0, Int(columns), Int(rows)) else {
                        return nil
                    }
                    return DecodedPixelDataFrame(
                        value: value,
                        samplesPerPixel: 1,
                        bitsAllocated: 8,
                        bitsStored: nil,
                        photometricInterpretation: sourcePhotometric,
                        planarConfiguration: sourcePlanarConfiguration
                    )
                }
            default:
                return nil
            }

        case .jpegLosslessSV1:
            let isMonochrome = sourceSamplesPerPixel == 1 && (sourcePhotometric == .monochrome1 || sourcePhotometric == .monochrome2)
            let isRGB = sourceSamplesPerPixel == 3 && sourcePhotometric == .rgb && sourcePlanarConfiguration == 0
            guard isMonochrome || isRGB,
                  let fragmentFrames = encapsulatedFrames(of: pixelElement, frameCount: frameCount) else {
                return nil
            }
            frames = fragmentFrames.compactMap { fragments in
                let turboDecoded = try? TurboJPEGDecoder.decodeLossless(
                    fragments: fragments,
                    width: Int(columns),
                    height: Int(rows),
                    bitsAllocated: sourceBitsAllocated,
                    samplesPerPixel: sourceSamplesPerPixel
                )
                let legacyDecoded = turboDecoded == nil ? try? JPEGLosslessDecoder.decodeLossless(
                    fragments: fragments,
                    width: Int(columns),
                    height: Int(rows),
                    bitsAllocated: sourceBitsAllocated
                ) : nil
                let decoded: (value: Data, precision: Int, selectionValue: Int, samplesPerPixel: Int)?
                if let turboDecoded {
                    decoded = (turboDecoded.value, turboDecoded.precision, turboDecoded.selectionValue, turboDecoded.samplesPerPixel)
                } else if let legacyDecoded {
                    decoded = (legacyDecoded.value, legacyDecoded.precision, legacyDecoded.selectionValue, 1)
                } else {
                    decoded = nil
                }
                guard let decoded else {
                    return nil
                }
                guard decoded.selectionValue == 1 else { return nil }
                if let declaredBitsStored = dataset[.bitsStored]?.uint16Value,
                   Int(declaredBitsStored) != decoded.precision {
                    return nil
                }
                guard decoded.samplesPerPixel == sourceSamplesPerPixel else { return nil }
                return DecodedPixelDataFrame(
                    value: decoded.value,
                    samplesPerPixel: decoded.samplesPerPixel,
                    bitsAllocated: sourceBitsAllocated,
                    bitsStored: decoded.precision,
                    photometricInterpretation: sourcePhotometric,
                    planarConfiguration: sourcePlanarConfiguration
                )
            }

        case .jpegLSLossless, .jpegLSNearLossless:
            let isMonochrome = sourceSamplesPerPixel == 1 && (sourcePhotometric == .monochrome1 || sourcePhotometric == .monochrome2)
            let isRGB = sourceSamplesPerPixel == 3 && (sourcePhotometric == .rgb || sourcePhotometric == .ybrFull) && sourcePlanarConfiguration == 0
            guard isMonochrome || isRGB,
                  let fragmentFrames = encapsulatedFrames(of: pixelElement, frameCount: frameCount) else {
                return nil
            }
            frames = fragmentFrames.compactMap { fragments in
                guard let decoded = try? JPEGLSDecoder.decodeLossless(
                    fragments: fragments,
                    width: Int(columns),
                    height: Int(rows),
                    bitsAllocated: sourceBitsAllocated
                ) else {
                    return nil
                }
                if let declaredBitsStored = dataset[.bitsStored]?.uint16Value,
                   Int(declaredBitsStored) != decoded.precision {
                    return nil
                }
                guard decoded.samplesPerPixel == sourceSamplesPerPixel else { return nil }
                let value = sourcePhotometric == .ybrFull ? ybrFullToRGB(decoded.value) : decoded.value
                return DecodedPixelDataFrame(
                    value: value,
                    samplesPerPixel: decoded.samplesPerPixel,
                    bitsAllocated: sourceBitsAllocated,
                    bitsStored: decoded.precision,
                    photometricInterpretation: sourcePhotometric == .ybrFull ? .rgb : sourcePhotometric,
                    planarConfiguration: sourcePlanarConfiguration
                )
            }

        case .jpegLossless:
            let isMonochrome = sourceSamplesPerPixel == 1 && (sourcePhotometric == .monochrome1 || sourcePhotometric == .monochrome2)
            let isRGB = sourceSamplesPerPixel == 3 && sourcePhotometric == .rgb && sourcePlanarConfiguration == 0
            guard isMonochrome || isRGB,
                  let fragmentFrames = encapsulatedFrames(of: pixelElement, frameCount: frameCount) else {
                return nil
            }
            frames = fragmentFrames.compactMap { fragments in
                let turboDecoded = try? TurboJPEGDecoder.decodeLossless(
                    fragments: fragments,
                    width: Int(columns),
                    height: Int(rows),
                    bitsAllocated: sourceBitsAllocated,
                    samplesPerPixel: sourceSamplesPerPixel
                )
                let legacyDecoded = turboDecoded == nil ? try? JPEGLosslessDecoder.decodeLossless(
                    fragments: fragments,
                    width: Int(columns),
                    height: Int(rows),
                    bitsAllocated: sourceBitsAllocated
                ) : nil
                let decoded: (value: Data, precision: Int, selectionValue: Int, samplesPerPixel: Int)?
                if let turboDecoded {
                    decoded = (turboDecoded.value, turboDecoded.precision, turboDecoded.selectionValue, turboDecoded.samplesPerPixel)
                } else if let legacyDecoded {
                    decoded = (legacyDecoded.value, legacyDecoded.precision, legacyDecoded.selectionValue, 1)
                } else {
                    decoded = nil
                }
                guard let decoded else {
                    return nil
                }
                if let declaredBitsStored = dataset[.bitsStored]?.uint16Value,
                   Int(declaredBitsStored) != decoded.precision {
                    return nil
                }
                guard decoded.samplesPerPixel == sourceSamplesPerPixel else { return nil }
                return DecodedPixelDataFrame(
                    value: decoded.value,
                    samplesPerPixel: decoded.samplesPerPixel,
                    bitsAllocated: sourceBitsAllocated,
                    bitsStored: decoded.precision,
                    photometricInterpretation: sourcePhotometric,
                    planarConfiguration: sourcePlanarConfiguration
                )
            }

        default:
            guard bitsAllocated.isMultiple(of: 8) else { return nil }
            let bytesPerFrame = pixelCount * Int(samplesPerPixel) * (Int(bitsAllocated) / 8)
            guard bytesPerFrame > 0, pixelElement.value.count >= bytesPerFrame * frameCount else { return nil }
            frames = (0..<frameCount).map { frame in
                DecodedPixelDataFrame(
                    value: pixelElement.value.subdata(in: frame * bytesPerFrame..<(frame + 1) * bytesPerFrame),
                    samplesPerPixel: sourceSamplesPerPixel,
                    bitsAllocated: sourceBitsAllocated,
                    bitsStored: nil,
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
            bitsStored: frame.bitsStored ?? dataset[.bitsStored]?.uint16Value.map(Int.init),
            pixelRepresentation: Int(dataset[.pixelRepresentation]?.uint16Value ?? 0),
            rescaleSlope: dataset[.rescaleSlope]?.doubleValue ?? 1.0,
            rescaleIntercept: dataset[.rescaleIntercept]?.doubleValue ?? 0.0,
            defaultWindowCenter: windowPresets.first?.center ?? dataset[.windowCenter]?.doubleValue,
            defaultWindowWidth: windowPresets.first?.width ?? dataset[.windowWidth]?.doubleValue,
            windowPresets: windowPresets,
            voiLUTs: voiLUTs,
            paletteColorLUT: paletteColorLUT
        ) }
    }

    private func makeWindowPresets() -> [DICOMWindowPreset] {
        guard let centers = dataset[.windowCenter]?.doubleValues,
              let widths = dataset[.windowWidth]?.doubleValues,
              centers.count == widths.count else { return [] }
        let explanations = dataset[.windowCenterWidthExplanation]?.stringValues ?? []
        return zip(centers.indices, zip(centers, widths)).map { index, values in
            DICOMWindowPreset(center: values.0, width: values.1, explanation: explanations.indices.contains(index) ? explanations[index] : nil)
        }
    }

    private func makeVOILUTs() -> [DICOMVOILUT] {
        guard let items = dataset[.voiLUTSequence]?.sequenceItems else { return [] }
        return items.compactMap { item in
            guard let descriptor = item[.lutDescriptor]?.uint16Values,
                  descriptor.count == 3,
                  let dataElement = item[.lutData] else { return nil }
            let count = descriptor[0] == 0 ? 65_536 : Int(descriptor[0])
            let bitsPerEntry = Int(descriptor[2])
            let data: [UInt16]?
            if bitsPerEntry <= 8, dataElement.vr == .OB, dataElement.value.count >= count {
                data = dataElement.value.prefix(count).map(UInt16.init)
            } else if let words = dataElement.uint16Values, words.count >= count {
                data = Array(words.prefix(count))
            } else {
                data = nil
            }
            guard let data else { return nil }
            return try? DICOMVOILUT(
                firstMappedValue: Int16(bitPattern: descriptor[1]),
                bitsPerEntry: bitsPerEntry,
                entries: data,
                explanation: item[.lutExplanation]?.stringValue
            )
        }
    }

    /// Builds the palette lookup tables carried by a `PALETTE COLOR` dataset.
    /// The three standard descriptors must agree. Both modern `OB` 8-bit LUT
    /// data and `OW` data with 16-bit entries are accepted.
    private func makePaletteColorLUT() -> DICOMPaletteColorLUT? {
        guard let redDescriptor = dataset[.redPaletteColorLookupTableDescriptor]?.uint16Values,
              let greenDescriptor = dataset[.greenPaletteColorLookupTableDescriptor]?.uint16Values,
              let blueDescriptor = dataset[.bluePaletteColorLookupTableDescriptor]?.uint16Values,
              redDescriptor.count == 3,
              redDescriptor == greenDescriptor,
              redDescriptor == blueDescriptor else { return nil }
        let entryCount = redDescriptor[0] == 0 ? 65_536 : Int(redDescriptor[0])
        let firstMappedValue = redDescriptor[1]
        let bitsPerEntry = Int(redDescriptor[2])
        guard bitsPerEntry == 8 || bitsPerEntry == 16,
              let red = paletteEntries(for: .redPaletteColorLookupTableData, count: entryCount, bitsPerEntry: bitsPerEntry),
              let green = paletteEntries(for: .greenPaletteColorLookupTableData, count: entryCount, bitsPerEntry: bitsPerEntry),
              let blue = paletteEntries(for: .bluePaletteColorLookupTableData, count: entryCount, bitsPerEntry: bitsPerEntry) else {
            return nil
        }
        return try? DICOMPaletteColorLUT(
            firstMappedValue: firstMappedValue,
            bitsPerEntry: bitsPerEntry,
            red: red,
            green: green,
            blue: blue
        )
    }

    private func paletteEntries(for tag: DICOMTag, count: Int, bitsPerEntry: Int) -> [UInt16]? {
        guard let element = dataset[tag] else { return nil }
        if bitsPerEntry == 8, element.vr == .OB, element.value.count >= count {
            return element.value.prefix(count).map(UInt16.init)
        }
        guard let values = element.uint16Values, values.count >= count else { return nil }
        return Array(values.prefix(count))
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
        if basicOffsetTable.isEmpty,
           let extendedOffsets = dataset[.extendedOffsetTable]?.uint64Values,
           !extendedOffsets.isEmpty {
            return try? EncapsulatedPixelData.frameFragments(
                fragments: fragments,
                fragmentOffsets: fragmentOffsets,
                extendedOffsets: extendedOffsets,
                frameCount: frameCount
            )
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

    /// Parses a dataset that isn't wrapped in a DICOM Part 10 preamble and
    /// File Meta Information.
    ///
    /// The caller must supply its transfer syntax because a raw dataset has
    /// no authoritative syntax declaration. For ordinary exchange files use
    /// ``init(data:)`` instead.
    public init(datasetData input: Data, transferSyntax: TransferSyntax) throws {
        guard transferSyntax.isSupported else {
            throw DICOMError.unsupportedTransferSyntax(transferSyntax.uid)
        }
        var reader = Reader(data: Data(input), offset: 0)
        self.metaInformation = DICOMDataset()
        self.transferSyntax = transferSyntax
        self.dataset = DICOMDataset(elements: try reader.readDataset(transferSyntax: transferSyntax))
    }

    /// Serializes this file as a DICOM Part 10 byte stream.
    public func encodedData(sequenceLengthEncoding: DICOMWriter.SequenceLengthEncoding = .defined) throws -> Data {
        try DICOMWriter.write(metaInformation: metaInformation, dataset: dataset, transferSyntax: transferSyntax, sequenceLengthEncoding: sequenceLengthEncoding)
    }
}

private func ybrFullToRGB(_ value: Data) -> Data {
    var output = Data()
    output.reserveCapacity(value.count)
    for index in stride(from: 0, to: value.count, by: 3) where index + 2 < value.count {
        let y = Double(value[index])
        let cb = Double(value[index + 1]) - 128
        let cr = Double(value[index + 2]) - 128
        output.append(UInt8(clamping: Int((y + 1.402 * cr).rounded())))
        output.append(UInt8(clamping: Int((y - 0.344_136 * cb - 0.714_136 * cr).rounded())))
        output.append(UInt8(clamping: Int((y + 1.772 * cb).rounded())))
    }
    return output
}
