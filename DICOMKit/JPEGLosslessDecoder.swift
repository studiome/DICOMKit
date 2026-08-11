import Foundation

/// Decodes JPEG Lossless, Non-Hierarchical (Process 14) frames used by DICOM
/// Transfer Syntaxes `.57` and `.70`.
enum JPEGLosslessDecoder {
    struct DecodedFrame {
        let value: Data
        let precision: Int
        let selectionValue: Int
        let samplesPerPixel: Int
    }

    static func decodeLossless(
        fragments: [Data],
        width expectedWidth: Int,
        height expectedHeight: Int,
        bitsAllocated: Int
    ) throws -> DecodedFrame {
        guard expectedWidth > 0, expectedHeight > 0, bitsAllocated == 8 || bitsAllocated == 16 else {
            throw DICOMImageError.invalidImageAttributes
        }
        let data = fragments.reduce(into: Data()) { $0.append($1) }
        var parser = Parser(data: data)
        let header = try parser.readHeader(expectedWidth: expectedWidth, expectedHeight: expectedHeight)
        guard header.precision <= bitsAllocated else { throw DICOMImageError.invalidImageAttributes }

        let pixelCount = try checkedProduct(expectedWidth, expectedHeight)
        let sampleCount = try checkedProduct(pixelCount, header.components.count)
        var reader = EntropyBitReader(data: data, offset: parser.offset)
        let initialPredictor = 1 << (header.precision - header.pointTransform - 1)
        let maximumReducedSample = (1 << (header.precision - header.pointTransform)) - 1
        var reducedSamples = [Int](repeating: 0, count: sampleCount)
        var resetPrediction = true

        for pixelIndex in 0..<pixelCount {
            let x = pixelIndex % expectedWidth
            for component in header.components {
                let index = pixelIndex * header.components.count + component.outputIndex
                let predictor: Int
                if resetPrediction {
                    predictor = initialPredictor
                } else if x == 0 {
                    predictor = reducedSamples[(pixelIndex - expectedWidth) * header.components.count + component.outputIndex]
                } else if pixelIndex < expectedWidth {
                    predictor = reducedSamples[(pixelIndex - 1) * header.components.count + component.outputIndex]
                } else {
                    predictor = predictedValue(
                        selectionValue: header.selectionValue,
                        left: reducedSamples[(pixelIndex - 1) * header.components.count + component.outputIndex],
                        above: reducedSamples[(pixelIndex - expectedWidth) * header.components.count + component.outputIndex],
                        upperLeft: reducedSamples[(pixelIndex - expectedWidth - 1) * header.components.count + component.outputIndex]
                    )
                }
                let category = try component.huffmanTable.decodeSymbol(from: &reader)
                guard category <= header.precision else { throw DICOMImageError.unsupportedPixelFormat }
                let difference = try readDifference(category: category, from: &reader)
                let sample = predictor + difference
                guard (0...maximumReducedSample).contains(sample) else { throw DICOMImageError.unsupportedPixelFormat }
                reducedSamples[index] = sample
            }
            resetPrediction = false

            if header.restartInterval > 0,
               pixelIndex + 1 < pixelCount,
               (pixelIndex + 1).isMultiple(of: header.restartInterval) {
                try reader.consumeRestartMarker(expectedIndex: ((pixelIndex + 1) / header.restartInterval - 1) % 8)
                resetPrediction = true
            }
        }
        try reader.finishFrame()

        var output = Data()
        output.reserveCapacity(sampleCount * (bitsAllocated / 8))
        for reducedSample in reducedSamples {
            let sample = reducedSample << header.pointTransform
            if bitsAllocated == 8 {
                output.append(UInt8(sample))
            } else {
                output.append(UInt8(sample & 0xFF))
                output.append(UInt8(sample >> 8))
            }
        }
        return DecodedFrame(
            value: output,
            precision: header.precision,
            selectionValue: header.selectionValue,
            samplesPerPixel: header.components.count
        )
    }

    private static func predictedValue(selectionValue: Int, left: Int, above: Int, upperLeft: Int) -> Int {
        switch selectionValue {
        case 1: left
        case 2: above
        case 3: upperLeft
        case 4: left + above - upperLeft
        case 5: left + ((above - upperLeft) >> 1)
        case 6: above + ((left - upperLeft) >> 1)
        case 7: (left + above) >> 1
        default: preconditionFailure("Validated JPEG Lossless selection value")
        }
    }

    private static func readDifference(category: Int, from reader: inout EntropyBitReader) throws -> Int {
        guard category > 0 else { return 0 }
        let bits = try reader.readBits(count: category)
        let threshold = 1 << (category - 1)
        return bits >= threshold ? bits : bits - ((1 << category) - 1)
    }

    private static func checkedProduct(_ lhs: Int, _ rhs: Int) throws -> Int {
        let product = lhs.multipliedReportingOverflow(by: rhs)
        guard !product.overflow, product.partialValue > 0 else { throw DICOMImageError.invalidImageAttributes }
        return product.partialValue
    }
}

private extension JPEGLosslessDecoder {
    struct Header {
        let precision: Int
        let pointTransform: Int
        let restartInterval: Int
        let selectionValue: Int
        let components: [ScanComponent]
    }

    struct FrameComponent {
        let identifier: UInt8
    }

    struct ScanComponent {
        let outputIndex: Int
        let huffmanTable: HuffmanTable
    }

    struct Parser {
        let data: Data
        var offset = 0
        var tables: [Int: HuffmanTable] = [:]
        var precision: Int?
        var components: [FrameComponent] = []
        var restartInterval = 0

        mutating func readHeader(expectedWidth: Int, expectedHeight: Int) throws -> Header {
            guard try readMarker() == 0xD8 else { throw DICOMImageError.unsupportedPixelFormat }
            while true {
                let marker = try readMarker()
                switch marker {
                case 0xC4:
                    try readHuffmanTables()
                case 0xC3:
                    try readFrameHeader(expectedWidth: expectedWidth, expectedHeight: expectedHeight)
                case 0xDD:
                    try readRestartInterval()
                case 0xDA:
                    return try readScanHeader()
                case 0xD0...0xD7, 0xD8, 0xD9, 0x01:
                    throw DICOMImageError.unsupportedPixelFormat
                default:
                    try skipVariableLengthSegment()
                }
            }
        }

        mutating func readHuffmanTables() throws {
            let end = try readSegmentEnd()
            while offset < end {
                let tableInfo = try readByte()
                let tableClass = Int(tableInfo >> 4)
                let tableIdentifier = Int(tableInfo & 0x0F)
                guard tableClass == 0, tableIdentifier <= 3 else { throw DICOMImageError.unsupportedPixelFormat }
                var counts: [Int] = []
                counts.reserveCapacity(16)
                for _ in 0..<16 { counts.append(Int(try readByte())) }
                let valueCount = counts.reduce(0, +)
                guard valueCount > 0, offset + valueCount <= end else { throw DICOMImageError.truncatedPixelData }
                let values = try readBytes(count: valueCount)
                tables[tableIdentifier] = try HuffmanTable(counts: counts, values: values)
            }
            guard offset == end else { throw DICOMImageError.unsupportedPixelFormat }
        }

        mutating func readFrameHeader(expectedWidth: Int, expectedHeight: Int) throws {
            let end = try readSegmentEnd()
            guard end - offset >= 9 else { throw DICOMImageError.unsupportedPixelFormat }
            let parsedPrecision = Int(try readByte())
            let parsedHeight = Int(try readUInt16())
            let parsedWidth = Int(try readUInt16())
            let componentCount = Int(try readByte())
            guard (2...16).contains(parsedPrecision), parsedWidth == expectedWidth,
                  parsedHeight == expectedHeight, (1...3).contains(componentCount),
                  end - offset == 3 * componentCount else {
                throw DICOMImageError.unsupportedPixelFormat
            }
            var parsedComponents: [FrameComponent] = []
            for _ in 0..<componentCount {
                let identifier = try readByte()
                let sampling = try readByte()
                let quantizationTable = try readByte()
                guard sampling == 0x11, quantizationTable == 0,
                      !parsedComponents.contains(where: { $0.identifier == identifier }) else {
                    throw DICOMImageError.unsupportedPixelFormat
                }
                parsedComponents.append(FrameComponent(identifier: identifier))
            }
            precision = parsedPrecision
            components = parsedComponents
        }

        mutating func readRestartInterval() throws {
            let end = try readSegmentEnd()
            guard end - offset == 2 else { throw DICOMImageError.unsupportedPixelFormat }
            restartInterval = Int(try readUInt16())
        }

        mutating func readScanHeader() throws -> Header {
            let end = try readSegmentEnd()
            guard let precision, !components.isEmpty else {
                throw DICOMImageError.unsupportedPixelFormat
            }
            let componentCount = Int(try readByte())
            guard componentCount == components.count, end - offset == componentCount * 2 + 3 else {
                throw DICOMImageError.unsupportedPixelFormat
            }
            var scanComponents: [ScanComponent] = []
            for _ in 0..<componentCount {
                let scanComponentIdentifier = try readByte()
                let tableSelectors = try readByte()
                let tableIdentifier = Int(tableSelectors >> 4)
                guard tableSelectors & 0x0F == 0,
                      let outputIndex = components.firstIndex(where: { $0.identifier == scanComponentIdentifier }),
                      !scanComponents.contains(where: { $0.outputIndex == outputIndex }),
                      let huffmanTable = tables[tableIdentifier] else {
                    throw DICOMImageError.unsupportedPixelFormat
                }
                scanComponents.append(ScanComponent(outputIndex: outputIndex, huffmanTable: huffmanTable))
            }
            let selectionValue = try readByte()
            let spectralEnd = try readByte()
            let successiveApproximation = try readByte()
            let pointTransform = Int(successiveApproximation & 0x0F)
            guard (1...7).contains(Int(selectionValue)), spectralEnd == 0,
                  successiveApproximation >> 4 == 0, pointTransform < precision,
                  scanComponents.count == components.count else {
                throw DICOMImageError.unsupportedPixelFormat
            }
            return Header(
                precision: precision,
                pointTransform: pointTransform,
                restartInterval: restartInterval,
                selectionValue: Int(selectionValue),
                components: scanComponents
            )
        }

        mutating func skipVariableLengthSegment() throws {
            offset = try readSegmentEnd()
        }

        mutating func readSegmentEnd() throws -> Int {
            let length = Int(try readUInt16())
            guard length >= 2 else { throw DICOMImageError.unsupportedPixelFormat }
            let end = offset + length - 2
            guard end <= data.count else { throw DICOMImageError.truncatedPixelData }
            return end
        }

        mutating func readMarker() throws -> UInt8 {
            guard try readByte() == 0xFF else { throw DICOMImageError.unsupportedPixelFormat }
            var marker = try readByte()
            while marker == 0xFF { marker = try readByte() }
            guard marker != 0 else { throw DICOMImageError.unsupportedPixelFormat }
            return marker
        }

        mutating func readByte() throws -> UInt8 {
            guard offset < data.count else { throw DICOMImageError.truncatedPixelData }
            defer { offset += 1 }
            return data[offset]
        }

        mutating func readUInt16() throws -> UInt16 {
            let high = UInt16(try readByte())
            let low = UInt16(try readByte())
            return high << 8 | low
        }

        mutating func readBytes(count: Int) throws -> [UInt8] {
            guard count >= 0, offset + count <= data.count else { throw DICOMImageError.truncatedPixelData }
            defer { offset += count }
            return Array(data[offset..<(offset + count)])
        }
    }

    struct HuffmanTable {
        private let entries: [(code: Int, length: Int, value: UInt8)]

        init(counts: [Int], values: [UInt8]) throws {
            guard counts.count == 16, counts.reduce(0, +) == values.count else {
                throw DICOMImageError.unsupportedPixelFormat
            }
            var entries: [(Int, Int, UInt8)] = []
            var code = 0
            var valueIndex = 0
            for length in 1...16 {
                for _ in 0..<counts[length - 1] {
                    guard code < (1 << length) else { throw DICOMImageError.unsupportedPixelFormat }
                    entries.append((code, length, values[valueIndex]))
                    code += 1
                    valueIndex += 1
                }
                code <<= 1
            }
            self.entries = entries
        }

        func decodeSymbol(from reader: inout EntropyBitReader) throws -> Int {
            var code = 0
            for length in 1...16 {
                code = (code << 1) | (try reader.readBits(count: 1))
                if let entry = entries.first(where: { $0.length == length && $0.code == code }) {
                    return Int(entry.value)
                }
            }
            throw DICOMImageError.unsupportedPixelFormat
        }
    }

    struct EntropyBitReader {
        let data: Data
        var offset: Int
        private var currentByte = 0
        private var bitsRemaining = 0

        init(data: Data, offset: Int) {
            self.data = data
            self.offset = offset
        }

        mutating func readBits(count: Int) throws -> Int {
            guard count >= 0, count <= 16 else { throw DICOMImageError.unsupportedPixelFormat }
            var result = 0
            for _ in 0..<count {
                if bitsRemaining == 0 { try loadByte() }
                bitsRemaining -= 1
                result = (result << 1) | ((currentByte >> bitsRemaining) & 1)
            }
            return result
        }

        mutating func consumeRestartMarker(expectedIndex: Int) throws {
            bitsRemaining = 0
            guard offset + 1 < data.count, data[offset] == 0xFF else {
                throw DICOMImageError.truncatedPixelData
            }
            offset += 1
            while offset < data.count, data[offset] == 0xFF { offset += 1 }
            guard offset < data.count, data[offset] == UInt8(0xD0 + expectedIndex) else {
                throw DICOMImageError.unsupportedPixelFormat
            }
            offset += 1
        }

        mutating func finishFrame() throws {
            bitsRemaining = 0
            // The final entropy byte may contain unused fill bits, so it is
            // not necessarily consumed by the sample decoder. Require an EOI
            // marker at the actual end of the interchange stream instead.
            let endMarkerOffset = data.last == 0 ? data.count - 3 : data.count - 2
            guard endMarkerOffset >= 0,
                  offset <= endMarkerOffset,
                  data[endMarkerOffset] == 0xFF,
                  data[endMarkerOffset + 1] == 0xD9 else {
                throw DICOMImageError.truncatedPixelData
            }
            offset = data.count
        }

        private mutating func loadByte() throws {
            guard offset < data.count else { throw DICOMImageError.truncatedPixelData }
            let byte = data[offset]
            offset += 1
            if byte == 0xFF {
                guard offset < data.count else { throw DICOMImageError.truncatedPixelData }
                let following = data[offset]
                if following == 0x00 {
                    offset += 1
                } else {
                    throw DICOMImageError.unsupportedPixelFormat
                }
            }
            currentByte = Int(byte)
            bitsRemaining = 8
        }
    }
}
