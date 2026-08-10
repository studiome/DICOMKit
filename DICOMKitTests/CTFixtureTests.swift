import CoreGraphics
import Foundation
import Testing
@testable import DICOMKit

/// End-to-end tests against pydicom's `CT_small.dcm`, which exercises the
/// reader and the 16-bit rendering path on a real acquisition rather than a
/// hand-built dataset.
struct CTFixtureTests {
    @Test func readsPydicomExplicitVRLittleEndianCTFixture() throws {
        let file = try ctFixture()

        #expect(file.transferSyntax == .explicitVRLittleEndian)
        #expect(file.dataset[.rows]?.uint16Value == 128)
        #expect(file.dataset[.columns]?.uint16Value == 128)
    }

    @Test func rendersPydicomCTFixtureWithCorrectPolarityAndRescale() throws {
        // Regression test for the bug this phase fixes: CT_small.dcm is
        // signed (Pixel Representation 1) with Rescale Intercept -1024, so
        // its stored values must be sign-extended and rescaled to Hounsfield
        // Units before windowing. Before the fix, the 16-bit path ignored
        // both, so the outer corners (low stored values, around -850 HU
        // after correct rescale) rendered as mid-gray instead of black under
        // a soft-tissue window, since they were windowed as raw unsigned
        // storage values with no rescale applied.
        let file = try ctFixture()
        let pixelData = try #require(file.pixelData)

        #expect(pixelData.pixelRepresentation == 1)
        #expect(pixelData.bitsStored == 16)
        #expect(pixelData.rescaleIntercept == -1024)
        #expect(pixelData.rescaleSlope == 1)

        let image = try pixelData.cgImage(windowCenter: 40, windowWidth: 400)
        #expect(image.width == 128)
        #expect(image.height == 128)
        #expect(image.bitsPerComponent == 8)

        let bytes = try imageBytes(image)
        func pixel(row: Int, column: Int) -> UInt8 { bytes[row * 128 + column] }

        // The top corners and this background pixel are outside the scan
        // field (air, well below -160 HU, the soft-tissue window's lower
        // bound) and must render black. Verified against the fixture's raw
        // stored values directly: (0,0)=175, (0,127)=216, (10,10)=224, which
        // rescale to roughly -849, -808, and -800 HU respectively. Before
        // the fix (no sign extension, no rescale), these rendered as
        // mid-to-high gray (214, 240, and non-zero) instead of black.
        #expect(pixel(row: 0, column: 0) == 0)
        #expect(pixel(row: 0, column: 127) == 0)
        #expect(pixel(row: 10, column: 10) == 0)

        // (64,61) is the fixture's densest (bone-range) pixel: raw 2191,
        // which rescales to 1167 HU, well above the window's upper bound.
        #expect(pixel(row: 64, column: 61) == 255)

        // The body itself must show actual tissue detail, i.e. not be a single flat value.
        #expect(Set(bytes).count > 1)
    }
}
