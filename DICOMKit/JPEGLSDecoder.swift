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
    }

    static func decodeLossless(
        fragments: [Data],
        width expectedWidth: Int,
        height expectedHeight: Int,
        bitsAllocated: Int
    ) throws -> DecodedFrame {
        guard expectedWidth > 0, expectedHeight > 0, bitsAllocated == 8 else {
            throw DICOMImageError.invalidImageAttributes
        }

        let data = fragments.reduce(into: Data()) { $0.append($1) }
        var parser = Parser(data: data)
        let header = try parser.readHeader(expectedWidth: expectedWidth, expectedHeight: expectedHeight)
        guard header.precision <= bitsAllocated else { throw DICOMImageError.invalidImageAttributes }

        var decoder = ScanDecoder(
            reader: EntropyBitReader(data: data, offset: parser.offset),
            width: expectedWidth,
            height: expectedHeight,
            precision: header.precision
        )
        let samples = try decoder.decode()

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
        return DecodedFrame(value: value, precision: header.precision)
    }
}

private extension JPEGLSDecoder {
    struct Header {
        let precision: Int
    }

    struct Parser {
        let data: Data
        var offset = 0
        var precision: Int?
        var componentIdentifier: UInt8?

        mutating func readHeader(expectedWidth: Int, expectedHeight: Int) throws -> Header {
            guard try readMarker() == 0xD8 else { throw DICOMImageError.unsupportedPixelFormat }
            while true {
                switch try readMarker() {
                case 0xF7:
                    try readFrameHeader(expectedWidth: expectedWidth, expectedHeight: expectedHeight)
                case 0xDA:
                    return try readScanHeader()
                // JPEG-LS preset coding parameters and restart intervals are
                // deliberately postponed until they have independent vectors.
                case 0xF8, 0xDD:
                    throw DICOMImageError.unsupportedPixelFormat
                case 0xD8, 0xD9, 0xD0...0xD7, 0x01:
                    throw DICOMImageError.unsupportedPixelFormat
                default:
                    try skipVariableLengthSegment()
                }
            }
        }

        mutating func readFrameHeader(expectedWidth: Int, expectedHeight: Int) throws {
            let end = try readSegmentEnd()
            guard end - offset == 9 else { throw DICOMImageError.unsupportedPixelFormat }
            let parsedPrecision = Int(try readByte())
            let parsedHeight = Int(try readUInt16())
            let parsedWidth = Int(try readUInt16())
            let componentCount = try readByte()
            guard (2...16).contains(parsedPrecision), parsedWidth == expectedWidth,
                  parsedHeight == expectedHeight, componentCount == 1 else {
                throw DICOMImageError.unsupportedPixelFormat
            }
            let identifier = try readByte()
            let sampling = try readByte()
            let mappingTable = try readByte()
            guard sampling == 0x11, mappingTable == 0 else { throw DICOMImageError.unsupportedPixelFormat }
            precision = parsedPrecision
            componentIdentifier = identifier
        }

        mutating func readScanHeader() throws -> Header {
            let end = try readSegmentEnd()
            guard let precision, let componentIdentifier, end - offset == 6 else {
                throw DICOMImageError.unsupportedPixelFormat
            }
            let componentCount = try readByte()
            let scanComponentIdentifier = try readByte()
            let mappingTable = try readByte()
            let near = try readByte()
            let interleaveMode = try readByte()
            let pointTransform = try readByte()
            guard componentCount == 1, scanComponentIdentifier == componentIdentifier,
                  mappingTable == 0, near == 0, interleaveMode == 0, pointTransform == 0 else {
                throw DICOMImageError.unsupportedPixelFormat
            }
            return Header(precision: precision)
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
        private static let runIndexJ = [0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 9, 10, 11, 12, 13, 14, 15]

        var reader: EntropyBitReader
        let width: Int
        let height: Int
        let precision: Int
        let maximumValue: Int
        let initialA: Int
        let limit: Int
        var regularContexts: [RegularContext]
        var runContexts: [RunContext]
        var runIndex = 0

        init(reader: EntropyBitReader, width: Int, height: Int, precision: Int) {
            self.reader = reader
            self.width = width
            self.height = height
            self.precision = precision
            maximumValue = (1 << precision) - 1
            initialA = max(2, ((1 << precision) + 32) / 64)
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
                        x = try decodeRun(from: x, ra: ra, rb: rb, into: &current)
                    } else {
                        current[x] = try decodeRegular(ra: ra, rb: rb, rc: rc, q1: q1, q2: q2, q3: q3)
                        x += 1
                    }
                }
                output.append(contentsOf: current)
                previous = current
            }
            return output
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
            case ...(-21): -4
            case ...(-7): -3
            case ...(-3): -2
            case ..<0: -1
            case 0: 0
            case ..<3: 1
            case ..<7: 2
            case ..<21: 3
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
            if context.n == 64 {
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
            if context.n == 64 {
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
}
