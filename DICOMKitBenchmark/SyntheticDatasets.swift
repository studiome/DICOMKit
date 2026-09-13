import Foundation
import DICOMKit

/// Builds every synthetic dataset this benchmark measures, entirely through
/// `DICOMKit`'s public API (`DICOMElement`, `DICOMDataset`,
/// `DICOMWriter.encodeDataset`) plus a hand-written Part 10 wrapper for the
/// handful of bytes -- the 128-byte preamble, `DICM` magic, and a one-element
/// File Meta Information group -- that sit outside any dataset and so aren't
/// reachable through `DICOMWriter` at all (`DICOMWriter.encodeDataset`
/// deliberately skips group `0002`; assembling File Meta Information into a
/// full Part 10 file is `DICOMKitAuthoring`'s job, which this benchmark
/// target does not depend on). No bytes here are hand-decoded -- only
/// hand-encoded, and only the minimum needed to satisfy
/// `DICOMFile.init(data:)`'s two preconditions: the preamble/magic, and a
/// Transfer Syntax UID in group `0002`.
enum SyntheticDatasets {

    // MARK: - Part 10 wrapping

    /// Wraps already-encoded dataset bytes in the minimum valid Part 10
    /// envelope: a zeroed 128-byte preamble, the `DICM` magic, and a File
    /// Meta Information group containing only Transfer Syntax UID `(0002,0010)`.
    ///
    /// `DICOMFile.init(data:)` reads File Meta Information as Explicit VR
    /// Little Endian regardless of the main dataset's transfer syntax (PS3.10
    /// 7.1) and only requires Transfer Syntax UID out of the whole group, so
    /// that is all this writes.
    static func wrapPart10(datasetBytes: Data, transferSyntax: TransferSyntax) -> Data {
        var file = Data(repeating: 0, count: 128)
        file.append(contentsOf: "DICM".utf8)
        file.append(explicitVRShortElement(tag: .transferSyntaxUID, vr: .UI, value: Data(transferSyntax.uid.utf8)))
        file.append(datasetBytes)
        return file
    }

    /// Encodes `dataset` in `transferSyntax` and wraps it as a full Part 10
    /// file, ready for `DICOMFile.init(data:)`.
    static func part10File(dataset: DICOMDataset, transferSyntax: TransferSyntax = .explicitVRLittleEndian) throws -> Data {
        let encoded = try DICOMWriter.encodeDataset(dataset, transferSyntax: transferSyntax)
        return wrapPart10(datasetBytes: encoded, transferSyntax: transferSyntax)
    }

    /// A single Explicit VR Little Endian element with a short (2-byte)
    /// length field, even-padded per PS3.5 7.1.1. Used only for the File
    /// Meta Information element above -- every other element in this file
    /// goes through `DICOMWriter`, which pads on its own.
    private static func explicitVRShortElement(tag: DICOMTag, vr: DICOMVR, value: Data) -> Data {
        var padded = value
        if !padded.count.isMultiple(of: 2) { padded.append(vr == .UI ? 0 : 0x20) }
        var data = Data()
        data.append(UInt8(tag.group & 0xFF)); data.append(UInt8(tag.group >> 8))
        data.append(UInt8(tag.element & 0xFF)); data.append(UInt8(tag.element >> 8))
        data.append(contentsOf: vr.rawValue.utf8)
        data.append(UInt8(padded.count & 0xFF)); data.append(UInt8(padded.count >> 8))
        data.append(padded)
        return data
    }

    // MARK: - Large flat dataset

    /// A dataset of `elementCount` simple, non-sequence elements spanning a
    /// handful of common VRs (`LO`, `SH`, `US`, `DA`, `DS`, `UI`) cycled in
    /// turn, standing in for a dataset carrying a large, flat block of
    /// descriptive/demographic/acquisition attributes -- the shape that
    /// stresses per-element parsing overhead rather than any one decoder.
    static func makeLargeDataset(elementCount: Int) -> DICOMDataset {
        var elements: [DICOMElement] = []
        elements.reserveCapacity(elementCount)
        for index in 0..<elementCount {
            let group = UInt16(0x0009 + (index / 2000))
            let element = UInt16(0x0010 + 2 * (index % 2000))
            let tag = DICOMTag(group: group, element: element)
            switch index % 6 {
            case 0: elements.append(DICOMElement(tag: tag, vr: .LO, value: Data("Synthetic Value \(index)".utf8)))
            case 1: elements.append(DICOMElement(tag: tag, vr: .SH, value: Data("SH\(index)".utf8)))
            case 2:
                let value = UInt16(index % 65536)
                elements.append(DICOMElement(tag: tag, vr: .US, value: Data([UInt8(value & 0xFF), UInt8(value >> 8)])))
            case 3: elements.append(DICOMElement(tag: tag, vr: .DA, value: Data("20240101".utf8)))
            case 4: elements.append(DICOMElement(tag: tag, vr: .DS, value: Data("\(Double(index) / 3.0)".utf8)))
            default: elements.append(DICOMElement(tag: tag, vr: .UI, value: Data("1.2.840.10008.5.\(index)".utf8)))
            }
        }
        return DICOMDataset(elements: elements)
    }

    // MARK: - Deeply nested sequences

    /// A dataset containing one sequence element nested `depth` levels deep,
    /// each level holding a single item with one leaf `LO` element alongside
    /// the nested sequence, well within `Reader.maxSequenceDepth` (64,
    /// documented in `Reader.swift` from a direct-measurement stack-depth
    /// experiment). `depth` well under that limit -- this benchmark uses
    /// half of it -- keeps the case representative of deeply hierarchical
    /// real data (Referenced/Source Image and Directory Record sequences)
    /// without wandering into the pathological territory that constant
    /// exists to guard against.
    static func makeDeeplyNestedDataset(depth: Int) -> DICOMDataset {
        let leafTag = DICOMTag(group: 0x0011, element: 0x0010)
        let sequenceTag = DICOMTag(group: 0x0011, element: 0x0020)
        var innermost = DICOMDataset(elements: [
            DICOMElement(tag: leafTag, vr: .LO, value: Data("leaf".utf8))
        ])
        for level in stride(from: depth, through: 1, by: -1) {
            let item = DICOMDataset(elements: [
                DICOMElement(tag: leafTag, vr: .LO, value: Data("level \(level)".utf8)),
                DICOMElement(tag: sequenceTag, vr: .SQ, value: Data(), sequenceItems: [innermost])
            ])
            innermost = item
        }
        return DICOMDataset(elements: [
            DICOMElement(tag: sequenceTag, vr: .SQ, value: Data(), sequenceItems: [innermost])
        ])
    }

    // MARK: - Multi-frame native pixel data

    /// An uncompressed multi-frame dataset: `frameCount` frames of 16-bit
    /// `MONOCHROME2` pixel data, `rows` x `columns` each, filled with a ramp
    /// pattern so no frame is degenerate all-zero data. Matches
    /// `CT_small.dcm`'s own Bits Allocated/Stored/Pixel Representation
    /// (16/16, signed) so the per-frame decode path this exercises
    /// (``DICOMFile/pixelDataFrames``, native branch) is the same one real
    /// CT/MR multi-frame series use.
    static func makeMultiFrameDataset(rows: Int, columns: Int, frameCount: Int) -> DICOMDataset {
        let pixelsPerFrame = rows * columns
        var pixelBytes = Data(capacity: pixelsPerFrame * frameCount * 2)
        for frame in 0..<frameCount {
            for pixel in 0..<pixelsPerFrame {
                let sample = Int16(truncatingIfNeeded: pixel + frame * 37)
                pixelBytes.append(UInt8(truncatingIfNeeded: sample))
                pixelBytes.append(UInt8(truncatingIfNeeded: Int(sample) >> 8))
            }
        }
        let elements: [DICOMElement] = [
            DICOMElement(tag: .samplesPerPixel, vr: .US, value: uint16LE(1)),
            DICOMElement(tag: .photometricInterpretation, vr: .CS, value: Data("MONOCHROME2".utf8)),
            DICOMElement(tag: .numberOfFrames, vr: .IS, value: Data("\(frameCount)".utf8)),
            DICOMElement(tag: .rows, vr: .US, value: uint16LE(UInt16(rows))),
            DICOMElement(tag: .columns, vr: .US, value: uint16LE(UInt16(columns))),
            DICOMElement(tag: .bitsAllocated, vr: .US, value: uint16LE(16)),
            DICOMElement(tag: .bitsStored, vr: .US, value: uint16LE(16)),
            DICOMElement(tag: .pixelRepresentation, vr: .US, value: uint16LE(1)),
            DICOMElement(tag: .rescaleSlope, vr: .DS, value: Data("1".utf8)),
            DICOMElement(tag: .rescaleIntercept, vr: .DS, value: Data("-1024".utf8)),
            DICOMElement(tag: .pixelData, vr: .OW, value: pixelBytes)
        ]
        return DICOMDataset(elements: elements)
    }

    private static func uint16LE(_ value: UInt16) -> Data {
        Data([UInt8(value & 0xFF), UInt8(value >> 8)])
    }
}
