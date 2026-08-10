import Foundation
import Testing

/// Describes one real-size JPEG-LS interchange stream fixture under
/// `Fixtures/JPEGLS/`. Unlike the hand-built 2x2 streams in
/// `JPEGLSTestSupport.swift` (too small to exercise bit-stuffing, the NEAR
/// dead zone, or the run/regular statistics reset), these fixtures are large
/// enough to hit those paths, but the *expected* sample values are never
/// stored as a literal array: `expectedSamples()` regenerates them
/// deterministically from `seed`, so the repository only carries the encoded
/// bitstream, not a duplicate of the pixel data it decodes to.
struct JPEGLSRealSizeFixture: Sendable, CustomTestStringConvertible {
    /// File name under `Fixtures/JPEGLS/`, without extension.
    let name: String
    let width: Int
    let height: Int
    /// Bits allocated for DICOM storage (8 or 16); `precision` (JPEG-LS's
    /// sample precision) may be narrower, as with 12-bit-in-16-bit storage.
    let bitsAllocated: Int
    let precision: Int
    let componentCount: Int
    /// JPEG-LS interleave mode: 0 (none/plane), 1 (line), or 2 (sample).
    let interleaveMode: Int
    /// NEAR error bound; 0 means lossless.
    let near: Int
    let seed: UInt64

    var maximumValue: Int { (1 << precision) - 1 }

    /// Identifies the test case by fixture name in Swift Testing's output.
    var testDescription: String { name }

    /// Regenerates this fixture's original samples with the same
    /// gradient-plus-noise generator used when the fixture was produced
    /// (`Lab.samples` in the CharLS-dependent generation harness), so the
    /// expected values never need to be committed as a literal array.
    /// Interleaved as pixel-major (component fastest-varying) for
    /// `componentCount > 1`, matching `JPEGLSDecoder.decode`'s output order.
    func expectedSamples() -> [Int] {
        let count = width * height * componentCount
        var rng = 0x9E37_79B9_7F4A_7C15 &+ seed
        return (0..<count).map { index in
            rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
            return index % 3 == 0 ? (index * 7) % (maximumValue + 1) : Int(rng >> 33) % (maximumValue + 1)
        }
    }

    /// All fixtures under `Fixtures/JPEGLS/`. Covers: 8-bit and 16-bit
    /// (12-bit precision) monochrome, all three RGB interleave modes,
    /// Near-Lossless monochrome and RGB (including the NEAR=7 monochrome and
    /// NEAR=2 RGB cases that exposed the k=0 bias-correction and dead-zone
    /// bugs), and non-square/extreme aspect ratios.
    static let all: [JPEGLSRealSizeFixture] = [
        JPEGLSRealSizeFixture(name: "mono8_lossless_64x64", width: 64, height: 64, bitsAllocated: 8,
                              precision: 8, componentCount: 1, interleaveMode: 0, near: 0, seed: 64),
        JPEGLSRealSizeFixture(name: "mono16_12bit_lossless_64x64", width: 64, height: 64, bitsAllocated: 16,
                              precision: 12, componentCount: 1, interleaveMode: 0, near: 0, seed: 12),
        JPEGLSRealSizeFixture(name: "rgb_lossless_interleave0_64x64", width: 64, height: 64, bitsAllocated: 8,
                              precision: 8, componentCount: 3, interleaveMode: 0, near: 0, seed: 100),
        JPEGLSRealSizeFixture(name: "rgb_lossless_interleave1_64x64", width: 64, height: 64, bitsAllocated: 8,
                              precision: 8, componentCount: 3, interleaveMode: 1, near: 0, seed: 101),
        JPEGLSRealSizeFixture(name: "rgb_lossless_interleave2_64x64", width: 64, height: 64, bitsAllocated: 8,
                              precision: 8, componentCount: 3, interleaveMode: 2, near: 0, seed: 102),
        JPEGLSRealSizeFixture(name: "mono8_nearlossless_near7_64x64", width: 64, height: 64, bitsAllocated: 8,
                              precision: 8, componentCount: 1, interleaveMode: 0, near: 7, seed: 207),
        JPEGLSRealSizeFixture(name: "rgb_nearlossless_near2_interleave0_32x32", width: 32, height: 32, bitsAllocated: 8,
                              precision: 8, componentCount: 3, interleaveMode: 0, near: 2, seed: 320),
        JPEGLSRealSizeFixture(name: "rgb_nearlossless_near2_interleave1_32x32", width: 32, height: 32, bitsAllocated: 8,
                              precision: 8, componentCount: 3, interleaveMode: 1, near: 2, seed: 321),
        JPEGLSRealSizeFixture(name: "rgb_nearlossless_near2_interleave2_32x32", width: 32, height: 32, bitsAllocated: 8,
                              precision: 8, componentCount: 3, interleaveMode: 2, near: 2, seed: 322),
        JPEGLSRealSizeFixture(name: "mono8_lossless_nonsquare_97x61", width: 97, height: 61, bitsAllocated: 8,
                              precision: 8, componentCount: 1, interleaveMode: 0, near: 0, seed: 9761),
        JPEGLSRealSizeFixture(name: "mono8_nearlossless_near3_nonsquare_97x61", width: 97, height: 61, bitsAllocated: 8,
                              precision: 8, componentCount: 1, interleaveMode: 0, near: 3, seed: 9762),
        JPEGLSRealSizeFixture(name: "mono8_lossless_1x256", width: 1, height: 256, bitsAllocated: 8,
                              precision: 8, componentCount: 1, interleaveMode: 0, near: 0, seed: 1256),
        JPEGLSRealSizeFixture(name: "mono8_lossless_256x1", width: 256, height: 1, bitsAllocated: 8,
                              precision: 8, componentCount: 1, interleaveMode: 0, near: 0, seed: 2561)
    ]
}
