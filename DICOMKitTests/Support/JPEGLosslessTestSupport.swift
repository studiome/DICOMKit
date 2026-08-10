import Foundation

/// Produces a minimal, single-component JPEG Lossless Process 14 stream with
/// Selection Value 1. It is intentionally test-only: its job is to generate
/// controlled inputs for the independent production decoder.
func jpegLosslessSV1Data(
    samples: [UInt16],
    width: Int,
    height: Int,
    precision: Int,
    pointTransform: Int = 0,
    restartInterval: Int = 0
) -> Data {
    precondition(width > 0 && height > 0 && samples.count == width * height)
    precondition((2...16).contains(precision))
    precondition((0..<precision).contains(pointTransform))
    precondition(restartInterval >= 0)
    let maximum = (1 << precision) - 1
    precondition(samples.allSatisfy { Int($0) <= maximum && Int($0) & ((1 << pointTransform) - 1) == 0 })

    var output = Data([0xFF, 0xD8]) // SOI
    output.append(contentsOf: [
        0xFF, 0xC4, 0x00, 0x24, // DHT: one DC table, 17 five-bit codes
        0x00, 0, 0, 0, 0, 17, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    ])
    output.append(contentsOf: 0...16)
    output.append(contentsOf: [
        0xFF, 0xC3, 0x00, 0x0B, UInt8(precision),
        UInt8(height >> 8), UInt8(height & 0xFF),
        UInt8(width >> 8), UInt8(width & 0xFF),
        0x01, 0x01, 0x11, 0x00
    ])
    if restartInterval > 0 {
        output.append(contentsOf: [
            0xFF, 0xDD, 0x00, 0x04,
            UInt8(restartInterval >> 8), UInt8(restartInterval & 0xFF)
        ])
    }
    output.append(contentsOf: [
        0xFF, 0xDA, 0x00, 0x08,
        0x01, 0x01, 0x00, 0x01, 0x00, UInt8(pointTransform)
    ])

    var writer = LosslessJPEGTestBitWriter()
    let initialPredictor = 1 << (precision - pointTransform - 1)
    for index in samples.indices {
        if restartInterval > 0, index > 0, index.isMultiple(of: restartInterval) {
            writer.finish(into: &output)
            output.append(0xFF)
            output.append(0xD0 + UInt8((index / restartInterval - 1) % 8))
        }
        let reduced = Int(samples[index]) >> pointTransform
        let predictor: Int
        if index == 0 || (restartInterval > 0 && index.isMultiple(of: restartInterval)) {
            predictor = initialPredictor
        } else if index.isMultiple(of: width) {
            predictor = Int(samples[index - width]) >> pointTransform
        } else {
            predictor = Int(samples[index - 1]) >> pointTransform
        }
        let difference = reduced - predictor
        let category = magnitudeBitCount(difference)
        writer.write(category, bits: 5, into: &output) // canonical DHT code equals category
        if category > 0 {
            let amplitude = difference >= 0 ? difference : difference + (1 << category) - 1
            writer.write(amplitude, bits: category, into: &output)
        }
    }
    writer.finish(into: &output)
    output.append(contentsOf: [0xFF, 0xD9]) // EOI
    return output
}

private func magnitudeBitCount(_ value: Int) -> Int {
    var magnitude = value < 0 ? -value : value
    var count = 0
    while magnitude > 0 {
        count += 1
        magnitude >>= 1
    }
    return count
}

private struct LosslessJPEGTestBitWriter {
    private var bits = 0
    private var count = 0

    mutating func write(_ value: Int, bits bitCount: Int, into output: inout Data) {
        precondition(bitCount == 0 || value >= 0 && value < (1 << bitCount))
        bits = (bits << bitCount) | value
        count += bitCount
        while count >= 8 {
            let remaining = count - 8
            appendByte(UInt8(bits >> remaining), into: &output)
            bits &= (1 << remaining) - 1
            count = remaining
        }
    }

    mutating func finish(into output: inout Data) {
        if count > 0 {
            bits <<= 8 - count
            bits |= (1 << (8 - count)) - 1 // JPEG pads entropy data with 1 bits.
            appendByte(UInt8(bits), into: &output)
        }
        bits = 0
        count = 0
    }

    private func appendByte(_ byte: UInt8, into output: inout Data) {
        output.append(byte)
        if byte == 0xFF { output.append(0x00) }
    }
}
