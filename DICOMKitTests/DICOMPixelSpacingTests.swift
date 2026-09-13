import Foundation
import Testing
@testable import DICOMKit

/// Pixel spacing precedence: which attribute a measurement should use, and
/// whether it is already spacing in the patient or needs correction
/// DICOMKit doesn't have (PS3.3 C.7.6.1.1.2, C.8.11.3.1.2).
struct DICOMPixelSpacingTests {
    @Test func pixelSpacingAloneResolvesToPixelSpacingSource() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .pixelSpacing, vr: .DS, value: Data("0.5\\0.5".utf8))
        ])
        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))
        let geometry = try #require(file.imageGeometry)

        #expect(geometry.measurementSpacing == [0.5, 0.5])
        #expect(geometry.measurementSpacingSource == .pixelSpacing)
    }

    @Test func pixelSpacingWithCalibrationTypeResolvesToCalibrated() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .pixelSpacing, vr: .DS, value: Data("0.5\\0.5".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0028, element: 0x0A02), vr: .CS, value: Data("GEOMETRY".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0028, element: 0x0A04), vr: .LO, value: Data("Calibrated to table top".utf8))
        ])
        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))
        let geometry = try #require(file.imageGeometry)

        #expect(geometry.measurementSpacing == [0.5, 0.5])
        #expect(geometry.measurementSpacingSource == .calibrated(type: "GEOMETRY", description: "Calibrated to table top"))
        #expect(geometry.pixelSpacingCalibrationType == "GEOMETRY")
        #expect(geometry.pixelSpacingCalibrationDescription == "Calibrated to table top")
    }

    @Test func imagerPixelSpacingAloneResolvesToImagerPixelSpacingSource() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x1164), vr: .DS, value: Data("0.2\\0.2".utf8))
        ])
        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))
        let geometry = try #require(file.imageGeometry)

        #expect(geometry.imagerPixelSpacing == [0.2, 0.2])
        #expect(geometry.measurementSpacing == [0.2, 0.2])
        #expect(geometry.measurementSpacingSource == .imagerPixelSpacing)
    }

    /// `(0028,0030)` wins the precedence race, but Imager Pixel Spacing must
    /// still be readable on its own — a caller comparing the two (e.g. to
    /// detect suspicious calibration) needs both values, not just the winner.
    @Test func pixelSpacingTakesPrecedenceButImagerPixelSpacingStaysExposed() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .pixelSpacing, vr: .DS, value: Data("0.5\\0.5".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x1164), vr: .DS, value: Data("0.2\\0.2".utf8))
        ])
        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))
        let geometry = try #require(file.imageGeometry)

        #expect(geometry.measurementSpacing == [0.5, 0.5])
        #expect(geometry.measurementSpacingSource == .pixelSpacing)
        #expect(geometry.imagerPixelSpacing == [0.2, 0.2])
    }

    @Test func nominalScannedPixelSpacingAloneResolvesToItsOwnSource() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x2010), vr: .DS, value: Data("0.1\\0.1".utf8))
        ])
        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))
        let geometry = try #require(file.imageGeometry)

        #expect(geometry.nominalScannedPixelSpacing == [0.1, 0.1])
        #expect(geometry.measurementSpacing == [0.1, 0.1])
        #expect(geometry.measurementSpacingSource == .nominalScannedPixelSpacing)
    }

    @Test func datasetWithGeometryButNoSpacingResolvesToNone() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .imagePositionPatient, vr: .DS, value: Data("1\\2\\3".utf8))
        ])
        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))
        let geometry = try #require(file.imageGeometry)

        #expect(geometry.measurementSpacing == nil)
        #expect(geometry.measurementSpacingSource == .none)
    }

    /// Pixel Spacing carries exactly two values (row, column); a malformed
    /// three-valued entry must be rejected rather than partially trusted.
    @Test func threeValuedPixelSpacingIsRejected() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .pixelSpacing, vr: .DS, value: Data("0.5\\0.5\\0.5".utf8))
        ])
        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))
        let geometry = try #require(file.imageGeometry)

        #expect(geometry.pixelSpacing == nil)
        #expect(geometry.measurementSpacing == nil)
        #expect(geometry.measurementSpacingSource == .none)
    }

    /// The four new geometry attributes must be enough to make
    /// `imageGeometry` non-nil on their own, not only the original four.
    @Test func imagerPixelSpacingAloneMakesImageGeometryNonNil() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x1164), vr: .DS, value: Data("0.2\\0.2".utf8))
        ])
        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))

        #expect(file.imageGeometry != nil)
    }
}
