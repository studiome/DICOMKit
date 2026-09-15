import Foundation
import Testing
@testable import DICOMKit

/// Rescale Slope/Intercept `(0028,1053)`/`(0028,1052)` are `DS` strings, and
/// `Double.init(String)` happily parses `"nan"` and overflowing exponents to
/// `.infinity`. A rescaled sample built from either is non-finite, and both
/// the VOI LUT and windowing paths eventually convert a sample to `UInt8` --
/// which traps for a non-finite `Double`. These guard against that, matching
/// how `computedWindow`/`resolvedWindow` already avoid crashing on
/// degenerate input rather than turning it into a thrown error, since a
/// single bad sample among otherwise-valid ones shouldn't fail the whole frame.
struct PixelDataNonFiniteSampleTests {
    @Test func voiLUTRenderingDoesNotTrapOnANonFiniteSample() throws {
        let lut = try DICOMVOILUT(firstMappedValue: 0, bitsPerEntry: 8, entries: [0, 255])
        let pixelData = DICOMPixelData(
            value: uint16(0), rows: 1, columns: 1,
            samplesPerPixel: 1, bitsAllocated: 16,
            photometricInterpretation: .monochrome2,
            rescaleSlope: .nan,
            voiLUTs: [lut]
        )

        _ = try pixelData.cgImage()
    }

    @Test func windowedRenderingDoesNotTrapOnANonFiniteSample() throws {
        let pixelData = DICOMPixelData(
            value: uint16(0), rows: 1, columns: 1,
            samplesPerPixel: 1, bitsAllocated: 16,
            photometricInterpretation: .monochrome2,
            rescaleSlope: .nan
        )

        _ = try pixelData.cgImage(windowCenter: 0, windowWidth: 100)
    }

    @Test func voiLUTRenderedValueClampsInfinityInsteadOfTrapping() throws {
        let lut = try DICOMVOILUT(firstMappedValue: 0, bitsPerEntry: 8, entries: [10, 20, 30])

        #expect(lut.renderedValue(for: .infinity) == 30)
        #expect(lut.renderedValue(for: -.infinity) == 10)
        #expect(lut.renderedValue(for: .nan) == 30)
    }
}
