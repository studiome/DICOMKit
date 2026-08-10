import Foundation

/// Decodes the JPEG-LS interchange formats used by DICOM Transfer Syntaxes
/// `1.2.840.10008.1.2.4.80` (Lossless) and `1.2.840.10008.1.2.4.81`
/// (Near-Lossless). This is a from-scratch, pure Swift implementation of the
/// ITU-T T.87 / ISO/IEC 14495-1 decoding process — it has no C/C++
/// dependency and links no third-party codec.
///
/// Supported: 1- and 3-component scans in all three JPEG-LS interleave
/// modes (plane, line, and sample), 2- through 16-bit sample precision,
/// Near-Lossless coding (`NEAR > 0`, verified for both monochrome and RGB
/// against real-size CharLS-encoded reference streams; see
/// `Fixtures/JPEGLS/` in the test target), default and explicit preset
/// coding parameters, and restart intervals.
///
/// Not supported: mapping tables (a non-zero mapping table ID is rejected),
/// a non-zero Point Transform, SPIFF headers, and more than 3 components per
/// frame.
enum JPEGLSDecoder {
    /// The result of decoding one frame: raw samples in pixel-major order
    /// (component fastest-varying), the bit precision each sample was coded
    /// at, and the number of components per pixel.
    struct DecodedFrame {
        let value: Data
        let precision: Int
        let samplesPerPixel: Int
    }

    /// Decodes a JPEG-LS interchange stream (Lossless or Near-Lossless) into
    /// raw samples.
    static func decode(
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

        let samples: [Int32]
        switch (header.frameComponentCount, header.scanComponentIdentifiers.count, header.interleaveMode) {
        case (1, 1, 0):
            var decoder = SampleDecoder(
                reader: EntropyBitReader(data: data, offset: parser.offset),
                width: expectedWidth,
                height: expectedHeight,
                componentCount: 1,
                interleaveMode: 0,
                precision: header.precision,
                parameters: header.parameters,
                restartInterval: header.restartInterval,
                near: header.near
            )
            samples = try decoder.decode()
            try decoder.finishFrame()
        case (3, 3, 1), (3, 3, 2):
            var decoder = SampleDecoder(
                reader: EntropyBitReader(data: data, offset: parser.offset),
                width: expectedWidth,
                height: expectedHeight,
                componentCount: 3,
                interleaveMode: header.interleaveMode,
                precision: header.precision,
                parameters: header.parameters,
                restartInterval: header.restartInterval,
                near: header.near
            )
            samples = try decoder.decode()
            try decoder.finishFrame()
        case (3, 1, 0):
            var planes = [[Int32]](repeating: [], count: 3)
            var scan = header
            for scanIndex in 0..<3 {
                var decoder = SampleDecoder(
                    reader: EntropyBitReader(data: data, offset: parser.offset),
                    width: expectedWidth,
                    height: expectedHeight,
                    componentCount: 1,
                    interleaveMode: 0,
                    precision: header.precision,
                    parameters: header.parameters,
                    restartInterval: header.restartInterval,
                    near: header.near
                )
                let plane = try decoder.decode()
                let nextMarkerOffset = try decoder.finishScan()
                guard scan.scanComponentIdentifiers.count == 1,
                      let componentIndex = header.componentIdentifiers.firstIndex(of: scan.scanComponentIdentifiers[0]) else {
                    throw DICOMImageError.unsupportedPixelFormat
                }
                planes[componentIndex] = plane
                if scanIndex < 2 {
                    parser.offset = nextMarkerOffset
                    guard try parser.readMarker() == 0xDA else { throw DICOMImageError.unsupportedPixelFormat }
                    scan = try parser.readScanHeader()
                    guard scan.frameComponentCount == 3, scan.scanComponentIdentifiers.count == 1, scan.interleaveMode == 0 else {
                        throw DICOMImageError.unsupportedPixelFormat
                    }
                } else {
                    parser.offset = nextMarkerOffset
                    guard try parser.readMarker() == 0xD9 else { throw DICOMImageError.truncatedPixelData }
                }
            }
            let pixelCount = expectedWidth * expectedHeight
            guard planes.allSatisfy({ $0.count == pixelCount }) else {
                throw DICOMImageError.truncatedPixelData
            }
            samples = [Int32](unsafeUninitializedCapacity: pixelCount * 3) { buffer, initializedCount in
                planes[0].withUnsafeBufferPointer { plane0 in
                    planes[1].withUnsafeBufferPointer { plane1 in
                        planes[2].withUnsafeBufferPointer { plane2 in
                            for pixel in 0..<pixelCount {
                                buffer[pixel * 3] = plane0[pixel]
                                buffer[pixel * 3 + 1] = plane1[pixel]
                                buffer[pixel * 3 + 2] = plane2[pixel]
                            }
                        }
                    }
                }
                initializedCount = pixelCount * 3
            }
        default:
            throw DICOMImageError.unsupportedPixelFormat
        }

        let bytesPerSample = bitsAllocated / 8
        var value = Data(count: samples.count * bytesPerSample)
        value.withUnsafeMutableBytes { (destination: UnsafeMutableRawBufferPointer) in
            samples.withUnsafeBufferPointer { source in
                if bytesPerSample == 1 {
                    for index in 0..<source.count {
                        destination[index] = UInt8(truncatingIfNeeded: source[index])
                    }
                } else {
                    let destination16 = destination.bindMemory(to: UInt16.self)
                    for index in 0..<source.count {
                        destination16[index] = UInt16(truncatingIfNeeded: source[index]).littleEndian
                    }
                }
            }
        }
        return DecodedFrame(value: value, precision: header.precision, samplesPerPixel: header.frameComponentCount)
    }
}

private extension JPEGLSDecoder {
    struct Header {
        let precision: Int
        let parameters: CodingParameters
        let restartInterval: Int
        let frameComponentCount: Int
        let componentIdentifiers: [UInt8]
        let scanComponentIdentifiers: [UInt8]
        let interleaveMode: Int
        let near: Int
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
            guard componentCount > 0, componentCount <= componentIdentifiers.count,
                  end - offset == 3 + componentCount * 2 else {
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
            guard Set(scanComponentIdentifiers).count == scanComponentIdentifiers.count,
                  scanComponentIdentifiers.allSatisfy(componentIdentifiers.contains),
                  (componentIdentifiers.count == 1 && componentCount == 1 && interleaveMode == 0) ||
                  (componentIdentifiers.count == 3 && componentCount == 1 && interleaveMode == 0) ||
                  (componentIdentifiers.count == 3 && componentCount == 3 && (interleaveMode == 1 || interleaveMode == 2)),
                  pointTransform == 0 else {
                throw DICOMImageError.unsupportedPixelFormat
            }
            guard Int(near) <= ((1 << precision) - 1) / 2 else { throw DICOMImageError.unsupportedPixelFormat }
            let maximumValue = (1 << precision) - 1
            let defaultParameters = Self.defaultCodingParameters(maximumValue: maximumValue, near: Int(near))
            let parameters = parameters ?? defaultParameters
            guard parameters.maximumValue == defaultParameters.maximumValue else {
                throw DICOMImageError.unsupportedPixelFormat
            }
            return Header(
                precision: precision,
                parameters: parameters,
                restartInterval: restartInterval,
                frameComponentCount: componentIdentifiers.count,
                componentIdentifiers: componentIdentifiers,
                scanComponentIdentifiers: scanComponentIdentifiers,
                interleaveMode: Int(interleaveMode),
                near: Int(near)
            )
        }

        /// Default coding threshold values, per T.87 C.2.4.1.1.1. Below a
        /// maximum sample value of 128 the standard scales the basic
        /// thresholds (3, 7, 21) *down* by an integer factor derived from
        /// how many bits narrower than 8 the alphabet is; at or above 128 it
        /// scales them *up* by a factor derived from how many bits wider.
        private static func defaultCodingParameters(maximumValue: Int, near: Int) -> CodingParameters {
            func clamp(_ value: Int, _ low: Int, _ high: Int) -> Int {
                value > high || value < low ? low : value
            }
            let threshold1: Int
            let threshold2: Int
            let threshold3: Int
            if maximumValue >= 128 {
                let factor = (min(maximumValue, 4095) + 128) / 256
                threshold1 = clamp(factor * 1 + 2 + 3 * near, near + 1, maximumValue)
                threshold2 = clamp(factor * 4 + 3 + 5 * near, threshold1, maximumValue)
                threshold3 = clamp(factor * 17 + 4 + 7 * near, threshold2, maximumValue)
            } else {
                let factor = 256 / (maximumValue + 1)
                threshold1 = clamp(max(2, 3 / factor + 3 * near), near + 1, maximumValue)
                threshold2 = clamp(max(3, 7 / factor + 5 * near), threshold1, maximumValue)
                threshold3 = clamp(max(4, 21 / factor + 7 * near), threshold2, maximumValue)
            }
            return CodingParameters(
                maximumValue: maximumValue,
                threshold1: threshold1,
                threshold2: threshold2,
                threshold3: threshold3,
                resetValue: 64
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
        // T.87 Annex A.1 bit-stuffing: whenever the entropy coder would
        // emit a literal 0xFF byte, the *following* byte carries a forced
        // leading 0 bit (this is exactly what distinguishes it from a
        // marker) and only 7 real data bits. That reduced byte can never
        // itself equal 0xFF (its top bit is always 0), so the stuffing
        // effect never cascades past one byte.
        private var previousByteWasFF = false

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

        mutating func finishScan() throws -> Int {
            bitsRemaining = 0
            var markerOffset = offset
            while markerOffset + 1 < data.count {
                guard data[markerOffset] == 0xFF else {
                    markerOffset += 1
                    continue
                }
                if data[markerOffset + 1] == 0x00 {
                    markerOffset += 2
                    continue
                }
                guard data[markerOffset + 1] == 0xDA || data[markerOffset + 1] == 0xD9 else {
                    throw DICOMImageError.unsupportedPixelFormat
                }
                return markerOffset
            }
            throw DICOMImageError.truncatedPixelData
        }

        private mutating func loadByte() throws {
            guard offset < data.count else { throw DICOMImageError.truncatedPixelData }
            let byte = data[offset]
            if byte == 0xFF {
                // Per T.87 Annex A.1, 0xFF is entropy data (not the start of
                // a marker) only when the following byte's top bit is 0:
                // that forced-0 bit is exactly the stuffed bit consumed
                // below on the next call, once this FF's own 7 bits are
                // exhausted. If the stream ends right after this 0xFF, or
                // the following bit is 1, more bits were requested than the
                // entropy segment actually has left.
                guard offset + 1 < data.count, data[offset + 1] & 0x80 == 0 else {
                    throw DICOMImageError.truncatedPixelData
                }
            }
            offset += 1
            if previousByteWasFF {
                // The byte immediately after an 0xFF carries a forced
                // leading 0 stuff bit; only its low 7 bits are real data.
                currentByte = Int(byte) & 0x7F
                bitsRemaining = 7
            } else {
                currentByte = Int(byte)
                bitsRemaining = 8
            }
            previousByteWasFF = byte == 0xFF
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

    /// Decodes one JPEG-LS scan: a single monochrome component, a plane of a
    /// plane-interleaved (interleave mode 0, 3 scans) RGB frame, a
    /// line-interleaved (interleave mode 1) RGB frame, or a sample-interleaved
    /// (interleave mode 2) RGB frame. `componentCount` is 1 for the first two
    /// cases and 3 for the interleaved-RGB cases; `interleaveMode` selects
    /// between the pixel-interleaved decode path (modes 0 and 2, where every
    /// component of a pixel is decoded together) and the line-interleaved
    /// path (mode 1, where each component's full line is decoded in turn).
    ///
    /// Regular-mode and run-mode statistics (`regularContexts`/`runContexts`)
    /// are shared across components in every interleave mode: JPEG-LS keeps
    /// one set of adaptive contexts per scan, not per component. The run
    /// index, by contrast, is scoped per component only for line interleave
    /// (each component's run-length state evolves independently down its own
    /// column of lines); for a single component or for sample interleave
    /// there is exactly one shared run index because all components of a
    /// pixel run and interrupt together. `runIndex` is therefore sized
    /// `componentCount` but the pixel-interleaved path only ever touches
    /// slot 0.
    struct SampleDecoder {
        fileprivate static let runIndexJ = [0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 9, 10, 11, 12, 13, 14, 15]

        var reader: EntropyBitReader
        let width: Int
        let height: Int
        let componentCount: Int
        let interleaveMode: Int
        let precision: Int
        let maximumValue: Int
        let initialA: Int
        let limit: Int
        let parameters: CodingParameters
        let restartInterval: Int
        let near: Int
        let range: Int
        let quantizedBits: Int
        var regularContexts: [RegularContext]
        var runContexts: [RunContext]
        var runIndex: [Int]

        init(
            reader: EntropyBitReader,
            width: Int,
            height: Int,
            componentCount: Int,
            interleaveMode: Int,
            precision: Int,
            parameters: CodingParameters,
            restartInterval: Int = 0,
            near: Int = 0
        ) {
            self.reader = reader
            self.width = width
            self.height = height
            self.componentCount = componentCount
            self.interleaveMode = interleaveMode
            self.precision = precision
            self.parameters = parameters
            self.restartInterval = restartInterval
            self.near = near
            maximumValue = (1 << precision) - 1
            range = (parameters.maximumValue + 2 * near) / (2 * near + 1) + 1
            quantizedBits = Self.bitsRequired(range)
            initialA = max(2, (range + 32) / 64)
            limit = 2 * (precision + max(8, precision))
            regularContexts = Array(repeating: RegularContext(a: initialA), count: 365)
            runContexts = [
                RunContext(interruptionType: 0, a: initialA),
                RunContext(interruptionType: 1, a: initialA)
            ]
            runIndex = Array(repeating: 0, count: componentCount)
        }

        mutating func decode() throws -> [Int32] {
            interleaveMode == 1 ? try decodeLineInterleaved() : try decodePixelInterleaved()
        }

        mutating func finishFrame() throws {
            try reader.finishFrame()
        }

        mutating func finishScan() throws -> Int {
            try reader.finishScan()
        }

        // MARK: - Pixel-interleaved decoding (mode 0: single component; mode 2: sample-interleaved RGB)

        /// Decodes a scan whose samples are grouped by pixel: for a single
        /// component this is a plain raster scan, and for sample-interleaved
        /// RGB every component of a pixel is decoded together (entering run
        /// mode only when all components agree, per T.87's triplet coding).
        /// Returns samples in pixel-major order (component fastest-varying).
        private mutating func decodePixelInterleaved() throws -> [Int32] {
            // Flat, component-major buffers (component c's row occupies
            // [c*width, c*width+width)) instead of [[Int]]: one contiguous
            // allocation per buffer for the whole scan rather than a nested
            // array of per-component arrays.
            var previous = [Int32](repeating: 0, count: componentCount * width)
            var current = [Int32](repeating: 0, count: componentCount * width)
            var leftEdgeA = [Int32](repeating: 0, count: componentCount)
            var leftEdgeC = [Int32](repeating: 0, count: componentCount)
            // Scratch reused across every pixel instead of allocating fresh
            // per-pixel arrays for the gradient categories and the run's
            // starting Ra per component.
            var q1s = [Int](repeating: 0, count: componentCount)
            var q2s = [Int](repeating: 0, count: componentCount)
            var q3s = [Int](repeating: 0, count: componentCount)
            var startRa = [Int](repeating: 0, count: componentCount)
            var output = [Int32](repeating: 0, count: width * height * componentCount)

            var decodedPixels = 0
            var restartIndex = 0
            var resetPreviousLine = false
            for row in 0..<height {
                // Every index of `current` is written exactly once below
                // (by run-fill or regular decode) before this row ends, so
                // it needs no clearing — the loop only ever reads positions
                // it has already written within the same row.
                var x = 0
                while x < width {
                    var allZero = true
                    for component in 0..<componentCount {
                        let base = component * width
                        let ra = x > 0 ? Int(current[base + x - 1]) : Int(leftEdgeA[component])
                        let rb = Int(previous[base + x])
                        let rc = x > 0 ? Int(previous[base + x - 1]) : Int(leftEdgeC[component])
                        let rd = x + 1 < width ? Int(previous[base + x + 1]) : rb
                        let q1 = quantize(rd - rb)
                        let q2 = quantize(rb - rc)
                        let q3 = quantize(rc - ra)
                        q1s[component] = q1
                        q2s[component] = q2
                        q3s[component] = q3
                        if q1 != 0 || q2 != 0 || q3 != 0 { allZero = false }
                    }
                    if allZero {
                        let nextX = try decodeRunPixel(from: x, leftEdgeA: leftEdgeA, previous: previous, current: &current, startRa: &startRa)
                        decodedPixels += nextX - x
                        x = nextX
                    } else {
                        for component in 0..<componentCount {
                            let base = component * width
                            let ra = x > 0 ? Int(current[base + x - 1]) : Int(leftEdgeA[component])
                            let rb = Int(previous[base + x])
                            let rc = x > 0 ? Int(previous[base + x - 1]) : Int(leftEdgeC[component])
                            current[base + x] = Int32(try decodeRegular(ra: ra, rb: rb, rc: rc, q1: q1s[component], q2: q2s[component], q3: q3s[component]))
                        }
                        x += 1
                        decodedPixels += 1
                    }
                    if restartInterval > 0, decodedPixels.isMultiple(of: restartInterval), decodedPixels < width * height {
                        try reader.consumeRestartMarker(expectedIndex: restartIndex)
                        restartIndex = (restartIndex + 1) % 8
                        resetContexts()
                        resetPreviousLine = true
                    }
                }
                output.withUnsafeMutableBufferPointer { output in
                    current.withUnsafeBufferPointer { current in
                        for pixel in 0..<width {
                            let destinationBase = (row * width + pixel) * componentCount
                            for component in 0..<componentCount {
                                output[destinationBase + component] = current[component * width + pixel]
                            }
                        }
                    }
                }
                for component in 0..<componentCount {
                    leftEdgeC[component] = resetPreviousLine ? 0 : leftEdgeA[component]
                    leftEdgeA[component] = resetPreviousLine ? 0 : current[component * width]
                }
                if resetPreviousLine {
                    for index in previous.indices { previous[index] = 0 }
                } else {
                    swap(&previous, &current)
                }
                resetPreviousLine = false
            }
            return output
        }

        /// Decodes a run whose length and continuation are shared by every
        /// component of the pixel group, using run index slot 0. The
        /// run-interruption sample's context is chosen dynamically
        /// (`|Ra-Rb| <= NEAR`) only for a lone component; T.87 fixes it to
        /// context 0 for every component of a multi-component pixel, since
        /// the run's all-components-equal-Ra condition already captures the
        /// smoothness that the dynamic check exists to detect.
        private mutating func decodeRunPixel(from start: Int, leftEdgeA: [Int32], previous: [Int32], current: inout [Int32], startRa: inout [Int]) throws -> Int {
            for component in 0..<componentCount {
                startRa[component] = start > 0 ? Int(current[component * width + start - 1]) : Int(leftEdgeA[component])
            }
            let length = try decodeRunLength(runIndexSlot: 0, remaining: width - start)
            if length > 0 {
                for component in 0..<componentCount {
                    let base = component * width
                    let value = Int32(startRa[component])
                    for index in (base + start)..<(base + start + length) { current[index] = value }
                }
            }
            let interruption = start + length
            guard interruption < width else { return width }
            for component in 0..<componentCount {
                let ra = startRa[component]
                let rb = Int(previous[component * width + interruption])
                let contextIndex = componentCount == 1 ? (abs(ra - rb) <= near ? 1 : 0) : 0
                current[component * width + interruption] = Int32(try decodeRunInterruptionSample(ra: ra, rb: rb, contextIndex: contextIndex, runIndexSlot: 0))
            }
            if runIndex[0] > 0 { runIndex[0] -= 1 }
            return interruption + 1
        }

        // MARK: - Line-interleaved decoding (mode 1)

        /// Decodes a scan whose samples are grouped by line: every sample of
        /// component 0's line, then every sample of component 1's line, and
        /// so on. Each component's line is decoded exactly as a standalone
        /// single-component raster line (its own Ra/Rb/Rc/Rd, its own run
        /// index and edge state), sharing only the adaptive regular/run
        /// contexts with the other components. Returns samples in
        /// pixel-major order (component fastest-varying).
        private mutating func decodeLineInterleaved() throws -> [Int32] {
            // Flat, component-major buffers as in decodePixelInterleaved.
            var previous = [Int32](repeating: 0, count: componentCount * width)
            var current = [Int32](repeating: 0, count: componentCount * width)
            var leftEdgeA = [Int32](repeating: 0, count: componentCount)
            var leftEdgeC = [Int32](repeating: 0, count: componentCount)
            var output = [Int32](repeating: 0, count: width * height * componentCount)

            var decodedSamples = 0
            var restartIndex = 0
            var resetPreviousLine = false
            let totalSamples = width * height * componentCount
            for row in 0..<height {
                for component in 0..<componentCount {
                    let base = component * width
                    var x = 0
                    while x < width {
                        let ra = x > 0 ? Int(current[base + x - 1]) : Int(leftEdgeA[component])
                        let rb = Int(previous[base + x])
                        let rc = x > 0 ? Int(previous[base + x - 1]) : Int(leftEdgeC[component])
                        let rd = x + 1 < width ? Int(previous[base + x + 1]) : rb
                        let q1 = quantize(rd - rb)
                        let q2 = quantize(rb - rc)
                        let q3 = quantize(rc - ra)
                        if q1 == 0, q2 == 0, q3 == 0 {
                            let nextX = try decodeRunComponent(component: component, from: x, ra: ra, previous: previous, current: &current)
                            decodedSamples += nextX - x
                            x = nextX
                        } else {
                            current[base + x] = Int32(try decodeRegular(ra: ra, rb: rb, rc: rc, q1: q1, q2: q2, q3: q3))
                            x += 1
                            decodedSamples += 1
                        }
                        if restartInterval > 0, decodedSamples.isMultiple(of: restartInterval), decodedSamples < totalSamples {
                            try reader.consumeRestartMarker(expectedIndex: restartIndex)
                            restartIndex = (restartIndex + 1) % 8
                            resetContexts()
                            resetPreviousLine = true
                        }
                    }
                    leftEdgeC[component] = resetPreviousLine ? 0 : leftEdgeA[component]
                    leftEdgeA[component] = resetPreviousLine ? 0 : current[base]
                }
                output.withUnsafeMutableBufferPointer { output in
                    current.withUnsafeBufferPointer { current in
                        for pixel in 0..<width {
                            let destinationBase = (row * width + pixel) * componentCount
                            for component in 0..<componentCount {
                                output[destinationBase + component] = current[component * width + pixel]
                            }
                        }
                    }
                }
                if resetPreviousLine {
                    for index in previous.indices { previous[index] = 0 }
                } else {
                    swap(&previous, &current)
                }
                resetPreviousLine = false
            }
            return output
        }

        /// Decodes a run within a single component's own line, using that
        /// component's own run index slot. The run-interruption context is
        /// always chosen dynamically here: line interleave decodes each
        /// component as an independent single-component scan.
        private mutating func decodeRunComponent(component: Int, from start: Int, ra: Int, previous: [Int32], current: inout [Int32]) throws -> Int {
            let base = component * width
            let length = try decodeRunLength(runIndexSlot: component, remaining: width - start)
            if length > 0 {
                let value = Int32(ra)
                for index in (base + start)..<(base + start + length) { current[index] = value }
            }
            let interruption = start + length
            guard interruption < width else { return width }
            let rb = Int(previous[base + interruption])
            let contextIndex = abs(ra - rb) <= near ? 1 : 0
            current[base + interruption] = Int32(try decodeRunInterruptionSample(ra: ra, rb: rb, contextIndex: contextIndex, runIndexSlot: component))
            if runIndex[component] > 0 { runIndex[component] -= 1 }
            return interruption + 1
        }

        // MARK: - Shared run/regular decoding primitives

        /// Reads the run-length prefix code from the bitstream (T.87's
        /// melcode over the run-index table), advancing `runIndex[slot]` as
        /// runs of increasing length are confirmed. Shared by both
        /// interleave paths; they differ only in which run index slot
        /// advances and in how many components fill with `Ra` afterward.
        private mutating func decodeRunLength(runIndexSlot: Int, remaining: Int) throws -> Int {
            var length = 0
            while try reader.readBit() == 1 {
                let count = min(1 << Self.runIndexJ[runIndex[runIndexSlot]], remaining - length)
                length += count
                if count == 1 << Self.runIndexJ[runIndex[runIndexSlot]], runIndex[runIndexSlot] < Self.runIndexJ.count - 1 {
                    runIndex[runIndexSlot] += 1
                }
                if length == remaining { break }
            }
            if length < remaining, Self.runIndexJ[runIndex[runIndexSlot]] > 0 {
                length += try reader.readBits(count: Self.runIndexJ[runIndex[runIndexSlot]])
            }
            guard length <= remaining else { throw DICOMImageError.unsupportedPixelFormat }
            return length
        }

        /// Decodes the single sample that interrupts a run, given the
        /// already-chosen run-interruption context.
        private mutating func decodeRunInterruptionSample(ra: Int, rb: Int, contextIndex: Int, runIndexSlot: Int) throws -> Int {
            var context = runContexts[contextIndex]
            let k = golombParameter(a: context.a + (context.n >> 1) * context.interruptionType, n: context.n)
            let mapped = try decodeMappedError(k: k, limit: limit - Self.runIndexJ[runIndex[runIndexSlot]] - 1)
            let error = runInterruptionError(mapped: mapped + context.interruptionType, k: k, context: context)
            updateRun(&context, error: error, mapped: mapped)
            runContexts[contextIndex] = context
            return reconstruct(prediction: contextIndex == 1 ? ra : rb, error: contextIndex == 1 ? error : error * sign(of: rb - ra))
        }

        private mutating func decodeRegular(ra: Int, rb: Int, rc: Int, q1: Int, q2: Int, q3: Int) throws -> Int {
            let signedContext = (q1 * 9 + q2) * 9 + q3
            let sign = signedContext < 0 ? -1 : 1
            let index = abs(signedContext)
            var context = regularContexts[index]
            let prediction = clamp(predict(ra, rb, rc) + sign * context.c)
            let k = golombParameter(a: context.a, n: context.n)
            var error = unmap(try decodeMappedError(k: k, limit: limit))
            // T.87 Annex A's k=0 sign-bias correction (code segment A.13) is a
            // lossless-only refinement of the regular-mode error value: the
            // standard's own encoder pseudocode gates this correction on k == 0
            // *and* NEAR == 0 together, not on k == 0 alone. Applying it at
            // NEAR > 0 corrupts B[Q]/N[Q] for the shared regular context
            // without necessarily corrupting the immediate reconstructed
            // sample (near-lossless's coarser quantization step can absorb a
            // wrong correction for a while), so the divergence only becomes
            // visible once that context is reused under different B/N state.
            if near == 0, k == 0, 2 * context.b + context.n - 1 < 0 { error = -error - 1 }
            updateRegular(&context, error: error)
            regularContexts[index] = context
            return reconstruct(prediction: prediction, error: sign * error)
        }

        private mutating func decodeMappedError(k: Int, limit: Int) throws -> Int {
            let unary = try reader.readUnaryCode()
            if unary < limit - quantizedBits - 1 {
                return k == 0 ? unary : (unary << k) + (try reader.readBits(count: k))
            }
            return (try reader.readBits(count: quantizedBits)) + 1
        }

        private func quantize(_ gradient: Int) -> Int {
            switch gradient {
            case ...(-parameters.threshold3): -4
            case ...(-parameters.threshold2): -3
            case ...(-parameters.threshold1): -2
            case ..<(-near): -1
            case ...near: 0
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
            context.b += error * (2 * near + 1)
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
            var value = prediction + error * (2 * near + 1)
            if value < -near {
                value += range * (2 * near + 1)
            } else if value > maximumValue + near {
                value -= range * (2 * near + 1)
            }
            return clamp(value)
        }

        private func clamp(_ value: Int) -> Int { min(max(0, value), maximumValue) }
        private func sign(of value: Int) -> Int { value < 0 ? -1 : 1 }

        private mutating func resetContexts() {
            regularContexts = Array(repeating: RegularContext(a: initialA), count: 365)
            runContexts = [
                RunContext(interruptionType: 0, a: initialA),
                RunContext(interruptionType: 1, a: initialA)
            ]
            runIndex = Array(repeating: 0, count: componentCount)
        }

        private static func bitsRequired(_ value: Int) -> Int {
            var bits = 0
            var limit = 1
            while limit < value { bits += 1; limit <<= 1 }
            return bits
        }
    }
}
