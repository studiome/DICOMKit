import Foundation
import DICOMKit

/// The benchmarks this target measures, one function per numbered item in
/// the task this file was written for. Every input is either the real
/// `CT_small.dcm` fixture (via ``Fixtures``) or synthesized through
/// ``SyntheticDatasets``; nothing here reaches into `DICOMKit` internals.
enum Benchmarks {
    /// Elements in the synthetic "large flat dataset" parse benchmark.
    /// 8,000 is an order of magnitude past `CT_small.dcm`'s 258 elements --
    /// large enough to make per-element parsing overhead, rather than
    /// process/file-open fixed costs, dominate the measurement.
    static let largeDatasetElementCount = 8_000

    /// Nesting depth for the synthetic "deeply nested sequences" parse
    /// benchmark: half of `Reader.maxSequenceDepth` (64, see
    /// `Reader.swift`), deep enough to be a real stress case for recursive
    /// sequence parsing while leaving a wide, deliberate margin below the
    /// limit designed to reject hostile input.
    static let deepNestingDepth = 32

    /// Instances parsed by the "series open" benchmark. A chest CT series
    /// commonly runs from around a hundred to several hundred slices; 64 is
    /// chosen on the low end of that range so the *default* benchmark run
    /// (see `main.swift`) completes in a few seconds, not because 64 is
    /// claimed to be a typical series size. Pass a larger `--iterations` (or
    /// edit this constant) to trade runtime for a count closer to a real
    /// study.
    static let seriesOpenInstanceCount = 64

    /// Frame geometry for the synthetic multi-frame native dataset used by
    /// the per-frame decode benchmark: 512x512 16-bit samples is a common
    /// in-plane CT/MR matrix size, and 16 frames is enough to amortize
    /// ``DICOMFile/pixelDataFrames``'s one-time-per-call work (functional
    /// group resolution, window preset/VOI LUT lookup) across several
    /// frames without making the fixture large enough to slow the default
    /// run down.
    static let multiFrameRows = 512
    static let multiFrameColumns = 512
    static let multiFrameCount = 16

    /// Frame geometry for the render benchmark, matching the per-frame
    /// decode benchmark's matrix size so the two numbers describe
    /// comparably sized images.
    static let renderRows = 512
    static let renderColumns = 512

    static func runAll(iterations: Int) {
        datasetParseCTSmall(iterations: iterations)
        datasetParseLargeFlatDataset(iterations: iterations)
        datasetParseDeeplyNestedSequences(iterations: iterations)
        seriesOpen(iterations: iterations)
        metadataOnlyOpen(iterations: iterations)
        perFrameDecode(iterations: iterations)
        render(iterations: iterations)
    }

    // MARK: - Dataset parse

    /// `DICOMFile(data:)` over the real `CT_small.dcm` fixture (128x128,
    /// 16-bit `MONOCHROME2`, 258 elements, 39,206 bytes, Explicit VR Little
    /// Endian).
    static func datasetParseCTSmall(iterations: Int) {
        let data = Fixtures.loadCTSmall()
        Benchmark.measure(
            name: "Dataset parse: CT_small.dcm",
            inputSize: "\(data.count) bytes, 258 elements",
            iterations: iterations
        ) {
            guard let file = try? DICOMFile(data: data) else { return 0 }
            return file.dataset.count
        }
    }

    /// `DICOMFile(data:)` over a synthesized dataset with
    /// ``largeDatasetElementCount`` simple, non-sequence elements.
    static func datasetParseLargeFlatDataset(iterations: Int) {
        let dataset = SyntheticDatasets.makeLargeDataset(elementCount: largeDatasetElementCount)
        guard let bytes = try? SyntheticDatasets.part10File(dataset: dataset) else {
            fatalError("Failed to encode the synthetic large dataset")
        }
        Benchmark.measure(
            name: "Dataset parse: large flat dataset",
            inputSize: "\(bytes.count) bytes, \(largeDatasetElementCount) elements",
            iterations: iterations
        ) {
            guard let file = try? DICOMFile(data: bytes) else { return 0 }
            return file.dataset.count
        }
    }

    /// `DICOMFile(data:)` over a synthesized dataset nesting sequences
    /// ``deepNestingDepth`` levels deep.
    static func datasetParseDeeplyNestedSequences(iterations: Int) {
        let dataset = SyntheticDatasets.makeDeeplyNestedDataset(depth: deepNestingDepth)
        guard let bytes = try? SyntheticDatasets.part10File(dataset: dataset) else {
            fatalError("Failed to encode the synthetic deeply nested dataset")
        }
        Benchmark.measure(
            name: "Dataset parse: deeply nested sequences",
            inputSize: "\(bytes.count) bytes, depth \(deepNestingDepth)",
            iterations: iterations
        ) {
            guard let file = try? DICOMFile(data: bytes) else { return 0 }
            return file.dataset.count
        }
    }

    // MARK: - Series open

    /// Parses ``seriesOpenInstanceCount`` copies of `CT_small.dcm` in
    /// sequence with `DICOMFile(data:)`, standing in for opening a study
    /// composed of that many same-sized instances. Using one real file
    /// repeated, rather than `seriesOpenInstanceCount` distinct synthetic
    /// files, keeps this benchmark measuring the same per-file parse cost as
    /// the CT_small.dcm benchmark above, multiplied out -- there is no
    /// second real fixture to substitute, and generating distinct synthetic
    /// instances would just add per-instance size/content variance that
    /// isn't the point of this measurement.
    static func seriesOpen(iterations: Int) {
        let data = Fixtures.loadCTSmall()
        let instanceCount = seriesOpenInstanceCount
        Benchmark.measure(
            name: "Series open: \(instanceCount) instances",
            inputSize: "\(instanceCount) instances x \(data.count) bytes",
            iterations: iterations
        ) {
            var totalElements = 0
            for _ in 0..<instanceCount {
                guard let file = try? DICOMFile(data: data) else { continue }
                totalElements += file.dataset.count
            }
            return totalElements
        }
    }

    // MARK: - Metadata-only open

    /// `DICOMMetadataFile(url:)` over the same `CT_small.dcm` bytes
    /// ``datasetParseCTSmall(iterations:)`` parses fully, so the saving from
    /// skipping Pixel Data is visible against an identical input. This is
    /// the path a viewer uses to open a study without decoding every
    /// instance's image up front.
    static func metadataOnlyOpen(iterations: Int) {
        let url = Fixtures.ctSmallURL
        let byteCount = Fixtures.loadCTSmall().count
        Benchmark.measure(
            name: "Metadata-only open: CT_small.dcm",
            inputSize: "\(byteCount) bytes, 258 elements",
            iterations: iterations
        ) {
            guard let file = try? DICOMMetadataFile(url: url) else { return 0 }
            return file.dataset.count
        }
    }

    // MARK: - Per-frame decode

    /// ``DICOMFile/pixelDataFrames`` over a synthesized uncompressed
    /// multi-frame dataset (see ``multiFrameRows``/``multiFrameColumns``/
    /// ``multiFrameCount``). Reports the whole-call median divided by frame
    /// count, since `pixelDataFrames` decodes every frame in one call and
    /// there is no public per-frame entry point to time directly.
    static func perFrameDecode(iterations: Int) {
        let dataset = SyntheticDatasets.makeMultiFrameDataset(rows: multiFrameRows, columns: multiFrameColumns, frameCount: multiFrameCount)
        guard let bytes = try? SyntheticDatasets.part10File(dataset: dataset),
              let file = try? DICOMFile(data: bytes) else {
            fatalError("Failed to build the synthetic multi-frame dataset")
        }
        let result = Benchmark.measure(
            name: "Per-frame decode: \(multiFrameCount) native frames",
            inputSize: "\(multiFrameCount) frames, \(multiFrameRows)x\(multiFrameColumns) 16-bit",
            iterations: iterations
        ) {
            guard let frames = file.pixelDataFrames else { return 0 }
            return frames.count
        }
        printPerUnit(result, unitCount: multiFrameCount, unitName: "frame")
    }

    // MARK: - Render

    /// `DICOMPixelData.cgImage(windowCenter:windowWidth:)` over one
    /// synthesized 16-bit `MONOCHROME2` frame with a CT-like rescale
    /// (slope 1, intercept -1024) and a soft-tissue window (center 40,
    /// width 400), reported per frame (a single frame per call, so the
    /// per-call median already is the per-frame figure -- printed the same
    /// way as the per-frame decode benchmark for a direct comparison).
    static func render(iterations: Int) {
        let pixelsPerFrame = renderRows * renderColumns
        var value = Data(capacity: pixelsPerFrame * 2)
        for pixel in 0..<pixelsPerFrame {
            // A ramp spanning roughly a CT Hounsfield range, so windowing
            // has real work to do instead of collapsing to one color.
            let hu = Int16(truncatingIfNeeded: (pixel % 4096) - 1024)
            value.append(UInt8(truncatingIfNeeded: hu))
            value.append(UInt8(truncatingIfNeeded: Int(hu) >> 8))
        }
        let pixelData = DICOMPixelData(
            value: value,
            rows: renderRows,
            columns: renderColumns,
            samplesPerPixel: 1,
            bitsAllocated: 16,
            photometricInterpretation: .monochrome2,
            bitsStored: 16,
            pixelRepresentation: 1,
            rescaleSlope: 1,
            rescaleIntercept: -1024
        )
        let result = Benchmark.measure(
            name: "Render: cgImage, 16-bit monochrome frame",
            inputSize: "\(renderRows)x\(renderColumns) 16-bit, 1 frame",
            iterations: iterations
        ) {
            guard let image = try? pixelData.cgImage(windowCenter: 40, windowWidth: 400) else { return 0 }
            return image.width * image.height
        }
        printPerUnit(result, unitCount: 1, unitName: "frame")
    }

    // MARK: - Per-unit reporting

    private static func printPerUnit(_ result: Benchmark.Result, unitCount: Int, unitName: String) {
        guard unitCount > 0 else { return }
        let perUnitMedian = result.median / unitCount
        let seconds = Double(perUnitMedian.components.seconds) + Double(perUnitMedian.components.attoseconds) / 1e18
        print(String(format: "  -> per %@: %.4fms", unitName, seconds * 1000))
    }
}
