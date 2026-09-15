import Foundation
import Testing
@testable import DICOMKit

/// JPEG Lossless and RLE Lossless both decode into a buffer sized from the
/// *declared* image dimensions before the actual compressed payload has been
/// checked for plausibility. Pairing huge declared dimensions with a tiny
/// fragment can otherwise force a multi-gigabyte allocation ahead of the
/// (later) truncation failure. These confirm the fix rejects that pairing
/// before allocating, rather than after.
///
/// The "before" behavior isn't exercised at full attacker scale here: doing
/// so would actually attempt the multi-gigabyte allocation this fix exists
/// to prevent, which risks exhausting memory on whatever machine runs the
/// suite. The vulnerability was confirmed by code inspection instead (the
/// allocation unconditionally preceded any check relating its size to the
/// input payload).
struct CompressedPixelDataAllocationSafetyTests {
    @Test func jpegLosslessRejectsHugeDeclaredDimensionsWithNoEntropyData() {
        // A syntactically valid header declaring the maximum representable
        // width and height, immediately followed by EOI: no entropy-coded
        // data backs the declared ~4.3 billion samples.
        var stream = Data([0xFF, 0xD8]) // SOI
        stream.append(contentsOf: [
            0xFF, 0xC4, 0x00, 0x24,
            0x00, 0, 0, 0, 0, 17, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        ])
        stream.append(contentsOf: 0...16)
        stream.append(contentsOf: [
            0xFF, 0xC3, 0x00, 0x0B, 8,
            0xFF, 0xFF, // height 65535
            0xFF, 0xFF, // width 65535
            0x01, 0x01, 0x11, 0x00
        ])
        stream.append(contentsOf: [
            0xFF, 0xDA, 0x00, 0x08,
            0x01, 0x01, 0x00, 0x01, 0x00, 0x00
        ])
        stream.append(contentsOf: [0xFF, 0xD9]) // EOI, no entropy data

        #expect(throws: DICOMImageError.truncatedPixelData) {
            _ = try JPEGLosslessDecoder.decodeLossless(fragments: [stream], width: 65535, height: 65535, bitsAllocated: 8)
        }
    }

    @Test func rleLosslessRejectsHugePixelCountWithATinySegment() {
        // A single-byte PackBits segment (one literal byte) can produce at
        // most 1 byte of output, nowhere near the declared pixel count.
        let frame = rleFrame(segment: Data([0x00, 0x2A]))

        #expect(throws: DICOMImageError.truncatedPixelData) {
            _ = try RLELosslessDecoder.decode8BitMonochrome(fragments: [frame], pixelCount: 999_999_999_999)
        }
    }
}
