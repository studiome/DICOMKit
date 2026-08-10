import Foundation
import Testing
@testable import DICOMKit

/// Regression coverage against real-size JPEG-LS streams under
/// `Fixtures/JPEGLS/`.
///
/// The hand-built streams in `Support/JPEGLSTestSupport.swift` are all 1x1 or
/// 2x2, which is too small to ever produce an 0xFF entropy byte, hit the NEAR
/// dead zone's boundary, or exercise the run/regular adaptive statistics
/// beyond their first update — exactly the blind spots that let three
/// lossless bugs (bit-stuffing, the NEAR dead zone, and post-modulo
/// clamping) and a Near-Lossless bug (an unconditional k=0 bias correction
/// that T.87 reserves for NEAR=0) ship undetected. These fixtures are large
/// enough to exercise all of that, while staying small enough to commit as
/// binary files. See `Fixtures/THIRD_PARTY_NOTICES.md` for their provenance.
struct JPEGLSRealSizeFixtureTests {
    @Test(arguments: JPEGLSRealSizeFixture.all)
    func decodesRealSizeFixture(fixture: JPEGLSRealSizeFixture) throws {
        let url = try fixtureURL(resource: fixture.name, extension: "jls", subdirectory: "Fixtures/JPEGLS")
        let stream = try Data(contentsOf: url)
        let expected = fixture.expectedSamples()

        let frame = try JPEGLSDecoder.decode(
            fragments: [stream],
            width: fixture.width,
            height: fixture.height,
            bitsAllocated: fixture.bitsAllocated
        )

        #expect(frame.precision == fixture.precision)
        #expect(frame.samplesPerPixel == fixture.componentCount)

        let decoded: [Int]
        if fixture.bitsAllocated == 8 {
            decoded = frame.value.map { Int($0) }
        } else {
            let bytes = [UInt8](frame.value)
            decoded = stride(from: 0, to: bytes.count, by: 2).map { Int(bytes[$0]) | (Int(bytes[$0 + 1]) << 8) }
        }

        #expect(decoded.count == expected.count)
        guard decoded.count == expected.count else { return }

        if fixture.near == 0 {
            #expect(decoded == expected, "fixture=\(fixture.name)")
        } else {
            var maxError = 0
            var worstIndex = -1
            for index in decoded.indices {
                let error = abs(decoded[index] - expected[index])
                if error > maxError { maxError = error; worstIndex = index }
            }
            #expect(maxError <= fixture.near,
                    "fixture=\(fixture.name) worst |error|=\(maxError) at index \(worstIndex) (NEAR=\(fixture.near))")
        }
    }
}
