import Foundation

/// Decodes the baseline JPEG-LS lossless interchange format used by DICOM
/// Transfer Syntax `1.2.840.10008.1.2.4.80`.
///
/// The first implementation intentionally accepts a single monochrome scan,
/// default JPEG-LS coding parameters, and `NEAR == 0`. JPEG-LS near-lossless,
/// color interleave modes, custom preset parameters, and restart intervals are
/// rejected rather than being decoded with altered pixel values.
enum JPEGLSDecoder {
    struct DecodedFrame {
        let value: Data
        let precision: Int
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

        let samples: [Int]
        switch (header.componentCount, header.interleaveMode) {
        case (1, 0):
            var decoder = ScanDecoder(
                reader: EntropyBitReader(data: data, offset: parser.offset),
                width: expectedWidth,
                height: expectedHeight,
                precision: header.precision,
                parameters: header.parameters,
                restartInterval: header.restartInterval
            )
            samples = try decoder.decode()
        case (3, 2):
            var decoder = RGBScanDecoder(
                reader: EntropyBitReader(data: data, offset: parser.offset),
                width: expectedWidth,
                height: expectedHeight,
                precision: header.precision,
                parameters: header.parameters,
                restartInterval: header.restartInterval
            )
            samples = try decoder.decode()
        default:
            throw DICOMImageError.unsupportedPixelFormat
        }

        var value = Data()
        value.reserveCapacity(samples.count * (bitsAllocated / 8))
        for sample in samples {
            if bitsAllocated == 8 {
                value.append(UInt8(sample))
            } else {
                value.append(UInt8(sample & 0xFF))
                value.append(UInt8(sample >> 8))
            }
        }
        return DecodedFrame(value: value, precision: header.precision, samplesPerPixel: header.componentCount)
    }
}

private extension JPEGLSDecoder {
    struct Header {
        let precision: Int
        let parameters: CodingParameters
        let restartInterval: Int
        let componentCount: Int
        let interleaveMode: Int
    }

    struct CodingParameters {
        let maximumValue: Int
        let threshold1: Int
        let threshold2: Int
        let threshold3: Int
        let resetValue: Int
    }

    struct Parser {
        let data: Data
        var offset = 0
        var precision: Int?
        var componentIdentifiers: [UInt8] = []
        var parameters: CodingParameters?
        var restartInterval = 0

        mutating func readHeader(expectedWidth: Int, expectedHeight: Int) throws -> Header {
            guard try readMarker() == 0xD8 else { throw DICOMImageError.unsupportedPixelFormat }
            while true {
                switch try readMarker() {
                case 0xF7:
                    try readFrameHeader(expectedWidth: expectedWidth, expectedHeight: expectedHeight)
                case 0xDA:
                    return try readScanHeader()
                case 0xF8:
                    try readPresetCodingParameters()
                case 0xDD:
                    try readRestartInterval()
                case 0xD8, 0xD9, 0xD0...0xD7, 0x01:
                    throw DICOMImageError.unsupportedPixelFormat
                default:
                    try skipVariableLengthSegment()
                }
            }
        }

        mutating func readFrameHeader(expectedWidth: Int, expectedHeight: Int) throws {
            let end = try readSegmentEnd()
            guard end - offset >= 9 else { throw DICOMImageError.unsupportedPixelFormat }
            let parsedPrecision = Int(try readByte())
            let parsedHeight = Int(try readUInt16())
            let parsedWidth = Int(try readUInt16())
            let componentCount = try readByte()
            guard (2...16).contains(parsedPrecision), parsedWidth == expectedWidth,
                  parsedHeight == expectedHeight, componentCount == 1 || componentCount == 3,
                  end - offset == Int(componentCount) * 3 else {
                throw DICOMImageError.unsupportedPixelFormat
            }
            var identifiers: [UInt8] = []
            for _ in 0..<componentCount {
                let identifier = try readByte()
                let sampling = try readByte()
                let mappingTable = try readByte()
                guard sampling == 0x11, mappingTable == 0 else { throw DICOMImageError.unsupportedPixelFormat }
                identifiers.append(identifier)
            }
            precision = parsedPrecision
            componentIdentifiers = identifiers
        }

        mutating func readScanHeader() throws -> Header {
            let end = try readSegmentEnd()
            guard let precision, end - offset >= 6 else {
                throw DICOMImageError.unsupportedPixelFormat
            }
            let componentCount = try readByte()
            guard componentCount == componentIdentifiers.count, end - offset == 3 + componentCount * 2 else {
                throw DICOMImageError.unsupportedPixelFormat
            }
            var scanComponentIdentifiers: [UInt8] = []
            for _ in 0..<componentCount {
                let identifier = try readByte()
                let mappingTable = try readByte()
                guard mappingTable == 0 else { throw DICOMImageError.unsupportedPixelFormat }
                scanComponentIdentifiers.append(identifier)
            }
            let near = try readByte()
            let interleaveMode = try readByte()
            let pointTransform = try readByte()
            guard scanComponentIdentifiers == componentIdentifiers, near == 0,
                  (componentCount == 1 && interleaveMode == 0) || (componentCount == 3 && interleaveMode == 2),
                  pointTransform == 0 else {
                throw DICOMImageError.unsupportedPixelFormat
            }
            let defaultParameters = CodingParameters(
                maximumValue: (1 << precision) - 1,
                threshold1: 3,
                threshold2: 7,
                threshold3: 21,
                resetValue: 64
            )
            let parameters = parameters ?? defaultParameters
            guard parameters.maximumValue == defaultParameters.maximumValue else {
                throw DICOMImageError.unsupportedPixelFormat
            }
            return Header(
                precision: precision,
                parameters: parameters,
                restartInterval: restartInterval,
                componentCount: Int(componentCount),
                interleaveMode: Int(interleaveMode)
            )
        }

        mutating func readRestartInterval() throws {
            let end = try readSegmentEnd()
            guard end - offset == 2 else { throw DICOMImageError.unsupportedPixelFormat }
            restartInterval = Int(try readUInt16())
            guard restartInterval > 0 else { throw DICOMImageError.unsupportedPixelFormat }
        }

        mutating func readPresetCodingParameters() throws {
            let end = try readSegmentEnd()
            guard end - offset == 11, try readByte() == 1 else {
                throw DICOMImageError.unsupportedPixelFormat
            }
            let maximumValue = Int(try readUInt16())
            let threshold1 = Int(try readUInt16())
            let threshold2 = Int(try readUInt16())
            let threshold3 = Int(try readUInt16())
            let resetValue = Int(try readUInt16())
            guard parameters == nil, threshold1 >= 0, threshold1 <= threshold2,
                  threshold2 <= threshold3, resetValue >= 3, resetValue <= 64 else {
                throw DICOMImageError.unsupportedPixelFormat
            }
            parameters = CodingParameters(
                maximumValue: maximumValue,
                threshold1: threshold1,
                threshold2: threshold2,
                threshold3: threshold3,
                resetValue: resetValue
            )
        }

        mutating func skipVariableLengthSegment() throws { offset = try readSegmentEnd() }

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
            UInt16(try readByte()) << 8 | UInt16(try readByte())
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

        mutating func readBit() throws -> Int {
            if bitsRemaining == 0 { try loadByte() }
            bitsRemaining -= 1
            return (currentByte >> bitsRemaining) & 1
        }

        mutating func readBits(count: Int) throws -> Int {
            guard (0...16).contains(count) else { throw DICOMImageError.unsupportedPixelFormat }
            var value = 0
            for _ in 0..<count { value = (value << 1) | (try readBit()) }
            return value
        }

        mutating func readUnaryCode() throws -> Int {
            var count = 0
            while try readBit() == 0 {
                count += 1
                guard count <= 65_535 else { throw DICOMImageError.unsupportedPixelFormat }
            }
            return count
        }

        mutating func consumeRestartMarker(expectedIndex: Int) throws {
            bitsRemaining = 0
            guard offset + 1 < data.count, data[offset] == 0xFF,
                  data[offset + 1] == UInt8(0xD0 + expectedIndex) else {
                throw DICOMImageError.unsupportedPixelFormat
            }
            offset += 2
        }

        private mutating func loadByte() throws {
            guard offset < data.count else { throw DICOMImageError.truncatedPixelData }
            let byte = data[offset]
            offset += 1
            if byte == 0xFF {
                guard offset < data.count, data[offset] == 0x00 else {
                    throw DICOMImageError.unsupportedPixelFormat
                }
                offset += 1
            }
            currentByte = Int(byte)
            bitsRemaining = byte == 0xFF ? 7 : 8
        }
    }

    struct RegularContext {
        var a: Int
        var b = 0
        var c = 0
        var n = 1
    }

    struct RunContext {
        let interruptionType: Int
        var a: Int
        var n = 1
        var nn = 0
    }

    struct ScanDecoder {
        fileprivate static let runIndexJ = [0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 9, 10, 11, 12, 13, 14, 15]

        var reader: EntropyBitReader
        let width: Int
        let height: Int
        let precision: Int
        let maximumValue: Int
        let initialA: Int
        let limit: Int
        let parameters: CodingParameters
        let restartInterval: Int
        var regularContexts: [RegularContext]
        var runContexts: [RunContext]
        var runIndex = 0

        init(reader: EntropyBitReader, width: Int, height: Int, precision: Int, parameters: CodingParameters, restartInterval: Int = 0) {
            self.reader = reader
            self.width = width
            self.height = height
            self.precision = precision
            self.parameters = parameters
            self.restartInterval = restartInterval
            maximumValue = (1 << precision) - 1
            initialA = max(2, (parameters.maximumValue + 1 + 32) / 64)
            limit = 2 * (precision + max(8, precision))
            regularContexts = Array(repeating: RegularContext(a: initialA), count: 365)
            runContexts = [
                RunContext(interruptionType: 0, a: initialA),
                RunContext(interruptionType: 1, a: initialA)
            ]
        }

        mutating func decode() throws -> [Int] {
            var previous = [Int](repeating: 0, count: width)
            var output = [Int]()
            output.reserveCapacity(width * height)

            var decodedCount = 0
            var restartIndex = 0
            var resetPreviousLine = false
            for _ in 0..<height {
                var current = [Int](repeating: 0, count: width)
                var x = 0
                while x < width {
                    let ra = x > 0 ? current[x - 1] : previous[x]
                    let rb = previous[x]
                    let rc = x > 0 ? previous[x - 1] : rb
                    let rd = x + 1 < width ? previous[x + 1] : rb
                    let q1 = quantize(rd - rb)
                    let q2 = quantize(rb - rc)
                    let q3 = quantize(rc - ra)
                    if q1 == 0, q2 == 0, q3 == 0 {
                        let nextX = try decodeRun(from: x, ra: ra, rb: rb, into: &current)
                        decodedCount += nextX - x
                        x = nextX
                    } else {
                        current[x] = try decodeRegular(ra: ra, rb: rb, rc: rc, q1: q1, q2: q2, q3: q3)
                        x += 1
                        decodedCount += 1
                    }
                    if restartInterval > 0, decodedCount.isMultiple(of: restartInterval), decodedCount < width * height {
                        try reader.consumeRestartMarker(expectedIndex: restartIndex)
                        restartIndex = (restartIndex + 1) % 8
                        resetContexts()
                        resetPreviousLine = true
                    }
                }
                output.append(contentsOf: current)
                previous = resetPreviousLine ? [Int](repeating: 0, count: width) : current
                resetPreviousLine = false
            }
            return output
        }

        private mutating func resetContexts() {
            regularContexts = Array(repeating: RegularContext(a: initialA), count: 365)
            runContexts = [
                RunContext(interruptionType: 0, a: initialA),
                RunContext(interruptionType: 1, a: initialA)
            ]
            runIndex = 0
        }

        private mutating func decodeRegular(ra: Int, rb: Int, rc: Int, q1: Int, q2: Int, q3: Int) throws -> Int {
            let signedContext = (q1 * 9 + q2) * 9 + q3
            let sign = signedContext < 0 ? -1 : 1
            let index = abs(signedContext)
            var context = regularContexts[index]
            let prediction = clamp(predict(ra, rb, rc) + sign * context.c)
            let k = golombParameter(a: context.a, n: context.n)
            var error = unmap(try decodeMappedError(k: k, limit: limit))
            if k == 0, 2 * context.b + context.n - 1 < 0 { error = -error - 1 }
            updateRegular(&context, error: error)
            regularContexts[index] = context
            return reconstruct(prediction: prediction, error: sign * error)
        }

        private mutating func decodeRun(from start: Int, ra: Int, rb: Int, into line: inout [Int]) throws -> Int {
            var length = 0
            let remaining = width - start
            while try reader.readBit() == 1 {
                let count = min(1 << Self.runIndexJ[runIndex], remaining - length)
                length += count
                if count == 1 << Self.runIndexJ[runIndex], runIndex < Self.runIndexJ.count - 1 { runIndex += 1 }
                if length == remaining { break }
            }
            if length < remaining, Self.runIndexJ[runIndex] > 0 {
                length += try reader.readBits(count: Self.runIndexJ[runIndex])
            }
            guard length <= remaining else { throw DICOMImageError.unsupportedPixelFormat }
            if length > 0 {
                for index in start..<(start + length) { line[index] = ra }
            }
            let interruption = start + length
            guard interruption < width else { return width }
            let contextIndex = abs(ra - rb) == 0 ? 1 : 0
            var context = runContexts[contextIndex]
            let k = golombParameter(a: context.a + (context.n >> 1) * context.interruptionType, n: context.n)
            let mapped = try decodeMappedError(k: k, limit: limit - Self.runIndexJ[runIndex] - 1)
            let error = runInterruptionError(mapped: mapped + context.interruptionType, k: k, context: context)
            updateRun(&context, error: error, mapped: mapped)
            runContexts[contextIndex] = context
            line[interruption] = reconstruct(prediction: contextIndex == 1 ? ra : rb, error: contextIndex == 1 ? error : error * sign(of: rb - ra))
            if runIndex > 0 { runIndex -= 1 }
            return interruption + 1
        }

        private mutating func decodeMappedError(k: Int, limit: Int) throws -> Int {
            let unary = try reader.readUnaryCode()
            if unary < limit - precision - 1 {
                return k == 0 ? unary : (unary << k) + (try reader.readBits(count: k))
            }
            return (try reader.readBits(count: precision)) + 1
        }

        private func quantize(_ gradient: Int) -> Int {
            switch gradient {
            case ...(-parameters.threshold3): -4
            case ...(-parameters.threshold2): -3
            case ...(-parameters.threshold1): -2
            case ..<0: -1
            case 0: 0
            case ..<parameters.threshold1: 1
            case ..<parameters.threshold2: 2
            case ..<parameters.threshold3: 3
            default: 4
            }
        }

        private func predict(_ ra: Int, _ rb: Int, _ rc: Int) -> Int {
            if rc >= max(ra, rb) { return min(ra, rb) }
            if rc <= min(ra, rb) { return max(ra, rb) }
            return ra + rb - rc
        }

        private func golombParameter(a: Int, n: Int) -> Int {
            var k = 0
            while n << k < a { k += 1 }
            return k
        }

        private func unmap(_ mapped: Int) -> Int { mapped.isMultiple(of: 2) ? mapped / 2 : -(mapped + 1) / 2 }

        private func runInterruptionError(mapped: Int, k: Int, context: RunContext) -> Int {
            let map = !mapped.isMultiple(of: 2)
            let magnitude = (mapped + (map ? 1 : 0)) / 2
            return (k != 0 || 2 * context.nn >= context.n) == map ? -magnitude : magnitude
        }

        private mutating func updateRegular(_ context: inout RegularContext, error: Int) {
            context.a += abs(error)
            context.b += error
            if context.n == parameters.resetValue {
                context.a >>= 1
                context.b >>= 1
                context.n >>= 1
            }
            context.n += 1
            if context.b + context.n <= 0 {
                context.b += context.n
                if context.b <= -context.n { context.b = -context.n + 1 }
                context.c = max(-128, context.c - 1)
            } else if context.b > 0 {
                context.b -= context.n
                if context.b > 0 { context.b = 0 }
                context.c = min(127, context.c + 1)
            }
        }

        private func updateRun(_ context: inout RunContext, error: Int, mapped: Int) {
            if error < 0 { context.nn += 1 }
            context.a += (mapped + 1 - context.interruptionType) >> 1
            if context.n == parameters.resetValue {
                context.a >>= 1
                context.n >>= 1
                context.nn >>= 1
            }
            context.n += 1
        }

        private func reconstruct(prediction: Int, error: Int) -> Int {
            let value = prediction + error
            if value < 0 { return value + maximumValue + 1 }
            if value > maximumValue { return value - maximumValue - 1 }
            return value
        }

        private func clamp(_ value: Int) -> Int { min(max(0, value), maximumValue) }
        private func sign(of value: Int) -> Int { value < 0 ? -1 : 1 }
    }

    /// Baseline JPEG-LS sample-interleaved RGB scan decoder. Each component
    /// maintains independent regular and run-interruption contexts; run length
    /// state is shared by the interleaved pixel triplet.
    struct RGBScanDecoder {
        var reader: EntropyBitReader
        let width: Int
        let height: Int
        let precision: Int
        let maximumValue: Int
        let initialA: Int
        let limit: Int
        let parameters: CodingParameters
        let restartInterval: Int
        var regularContexts: [RegularContext]
        var runContexts: [RunContext]
        var runIndex = 0

        init(reader: EntropyBitReader, width: Int, height: Int, precision: Int, parameters: CodingParameters, restartInterval: Int) {
            self.reader = reader
            self.width = width
            self.height = height
            self.precision = precision
            maximumValue = (1 << precision) - 1
            initialA = max(2, (parameters.maximumValue + 1 + 32) / 64)
            limit = 2 * (precision + max(8, precision))
            self.parameters = parameters
            self.restartInterval = restartInterval
            regularContexts = Array(repeating: RegularContext(a: initialA), count: 365)
            runContexts = [RunContext(interruptionType: 0, a: initialA), RunContext(interruptionType: 1, a: initialA)]
        }

        mutating func decode() throws -> [Int] {
            var previous = Array(repeating: [Int](repeating: 0, count: width), count: 3)
            var output: [Int] = []
            output.reserveCapacity(width * height * 3)
            var decodedPixels = 0
            var restartMarker = 0
            var resetPreviousLine = false

            for _ in 0..<height {
                var current = Array(repeating: [Int](repeating: 0, count: width), count: 3)
                var x = 0
                while x < width {
                    let gradients = (0..<3).map { component -> (Int, Int, Int) in
                        let ra = x > 0 ? current[component][x - 1] : previous[component][x]
                        let rb = previous[component][x]
                        let rc = x > 0 ? previous[component][x - 1] : rb
                        let rd = x + 1 < width ? previous[component][x + 1] : rb
                        return (quantize(rd - rb), quantize(rb - rc), quantize(rc - ra))
                    }
                    if gradients.allSatisfy({ $0.0 == 0 && $0.1 == 0 && $0.2 == 0 }) {
                        let nextX = try decodeRun(from: x, previous: previous, current: &current)
                        decodedPixels += nextX - x
                        x = nextX
                    } else {
                        for component in 0..<3 {
                            let ra = x > 0 ? current[component][x - 1] : previous[component][x]
                            let rb = previous[component][x]
                            let rc = x > 0 ? previous[component][x - 1] : rb
                            current[component][x] = try decodeRegular(component: component, ra: ra, rb: rb, rc: rc, gradients: gradients[component])
                        }
                        x += 1
                        decodedPixels += 1
                    }
                    if restartInterval > 0, decodedPixels.isMultiple(of: restartInterval), decodedPixels < width * height {
                        try reader.consumeRestartMarker(expectedIndex: restartMarker)
                        restartMarker = (restartMarker + 1) % 8
                        resetContexts()
                        resetPreviousLine = true
                    }
                }
                for pixel in 0..<width {
                    output.append(current[0][pixel])
                    output.append(current[1][pixel])
                    output.append(current[2][pixel])
                }
                previous = resetPreviousLine ? Array(repeating: [Int](repeating: 0, count: width), count: 3) : current
                resetPreviousLine = false
            }
            return output
        }

        private mutating func decodeRegular(component: Int, ra: Int, rb: Int, rc: Int, gradients: (Int, Int, Int)) throws -> Int {
            let signedContext = (gradients.0 * 9 + gradients.1) * 9 + gradients.2
            let sign = signedContext < 0 ? -1 : 1
            let index = abs(signedContext)
            var context = regularContexts[index]
            let prediction = clamp(predict(ra, rb, rc) + sign * context.c)
            let k = golombParameter(a: context.a, n: context.n)
            var error = unmap(try decodeMappedError(k: k, limit: limit))
            if k == 0, 2 * context.b + context.n - 1 < 0 { error = -error - 1 }
            updateRegular(&context, error: error)
            regularContexts[index] = context
            return reconstruct(prediction: prediction, error: sign * error)
        }

        private mutating func decodeRun(from start: Int, previous: [[Int]], current: inout [[Int]]) throws -> Int {
            var length = 0
            let remaining = width - start
            while try reader.readBit() == 1 {
                let count = min(1 << ScanDecoder.runIndexJ[runIndex], remaining - length)
                length += count
                if count == 1 << ScanDecoder.runIndexJ[runIndex], runIndex < ScanDecoder.runIndexJ.count - 1 { runIndex += 1 }
                if length == remaining { break }
            }
            if length < remaining, ScanDecoder.runIndexJ[runIndex] > 0 {
                length += try reader.readBits(count: ScanDecoder.runIndexJ[runIndex])
            }
            guard length <= remaining else { throw DICOMImageError.unsupportedPixelFormat }
            for component in 0..<3 {
                let ra = start > 0 ? current[component][start - 1] : previous[component][start]
                if length > 0 {
                    for index in start..<(start + length) { current[component][index] = ra }
                }
            }
            let interruption = start + length
            guard interruption < width else { return width }
            for component in 0..<3 {
                let ra = interruption > 0 ? current[component][interruption - 1] : previous[component][interruption]
                let rb = previous[component][interruption]
                // JPEG-LS sample-interleaved components always use the
                // component run-interruption context (RI type 0).
                let contextIndex = 0
                var context = runContexts[contextIndex]
                let k = golombParameter(a: context.a + (context.n >> 1) * context.interruptionType, n: context.n)
                let mapped = try decodeMappedError(k: k, limit: limit - ScanDecoder.runIndexJ[runIndex] - 1)
                let error = runInterruptionError(mapped: mapped + context.interruptionType, k: k, context: context)
                updateRun(&context, error: error, mapped: mapped)
                runContexts[contextIndex] = context
                current[component][interruption] = reconstruct(prediction: rb, error: error * sign(of: rb - ra))
            }
            if runIndex > 0 { runIndex -= 1 }
            return interruption + 1
        }

        private mutating func decodeMappedError(k: Int, limit: Int) throws -> Int {
            let unary = try reader.readUnaryCode()
            if unary < limit - precision - 1 { return k == 0 ? unary : (unary << k) + (try reader.readBits(count: k)) }
            return (try reader.readBits(count: precision)) + 1
        }
        private func quantize(_ value: Int) -> Int {
            if value <= -parameters.threshold3 { return -4 }; if value <= -parameters.threshold2 { return -3 }; if value <= -parameters.threshold1 { return -2 }; if value < 0 { return -1 }; if value == 0 { return 0 }; if value < parameters.threshold1 { return 1 }; if value < parameters.threshold2 { return 2 }; if value < parameters.threshold3 { return 3 }; return 4
        }
        private func predict(_ ra: Int, _ rb: Int, _ rc: Int) -> Int { rc >= max(ra, rb) ? min(ra, rb) : (rc <= min(ra, rb) ? max(ra, rb) : ra + rb - rc) }
        private func golombParameter(a: Int, n: Int) -> Int { var k = 0; while n << k < a { k += 1 }; return k }
        private func unmap(_ value: Int) -> Int { value.isMultiple(of: 2) ? value / 2 : -(value + 1) / 2 }
        private func runInterruptionError(mapped: Int, k: Int, context: RunContext) -> Int { let map = !mapped.isMultiple(of: 2); let magnitude = (mapped + (map ? 1 : 0)) / 2; return (k != 0 || 2 * context.nn >= context.n) == map ? -magnitude : magnitude }
        private mutating func updateRegular(_ context: inout RegularContext, error: Int) { context.a += abs(error); context.b += error; if context.n == parameters.resetValue { context.a >>= 1; context.b >>= 1; context.n >>= 1 }; context.n += 1; if context.b + context.n <= 0 { context.b += context.n; if context.b <= -context.n { context.b = -context.n + 1 }; context.c = max(-128, context.c - 1) } else if context.b > 0 { context.b -= context.n; if context.b > 0 { context.b = 0 }; context.c = min(127, context.c + 1) } }
        private func updateRun(_ context: inout RunContext, error: Int, mapped: Int) { if error < 0 { context.nn += 1 }; context.a += (mapped + 1 - context.interruptionType) >> 1; if context.n == parameters.resetValue { context.a >>= 1; context.n >>= 1; context.nn >>= 1 }; context.n += 1 }
        private func reconstruct(prediction: Int, error: Int) -> Int { let value = prediction + error; if value < 0 { return value + maximumValue + 1 }; if value > maximumValue { return value - maximumValue - 1 }; return value }
        private func clamp(_ value: Int) -> Int { min(max(0, value), maximumValue) }
        private func sign(of value: Int) -> Int { value < 0 ? -1 : 1 }
        private mutating func resetContexts() { regularContexts = Array(repeating: RegularContext(a: initialA), count: 365); runContexts = [RunContext(interruptionType: 0, a: initialA), RunContext(interruptionType: 1, a: initialA)]; runIndex = 0 }
    }
}
