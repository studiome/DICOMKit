import Foundation
import Testing
@testable import DICOMKit

/// `DICOMFile.measurementSpacing(atColumn:row:)`: resolving the scale to
/// measure at a specific point, honoring per-region ultrasound calibration
/// before falling back to `DICOMImageGeometry.measurementSpacing`.
struct DICOMMeasurementSpacingTests {
    private func regionElement(
        minX0: UInt32, minY0: UInt32, maxX1: UInt32, maxY1: UInt32,
        unitsX: DICOMUltrasoundRegion.PhysicalUnit, unitsY: DICOMUltrasoundRegion.PhysicalUnit,
        deltaX: Double, deltaY: Double
    ) -> DICOMDataset {
        DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x6018), vr: .UL, value: uint32(minX0)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x601A), vr: .UL, value: uint32(minY0)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x601C), vr: .UL, value: uint32(maxX1)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x601E), vr: .UL, value: uint32(maxY1)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x6024), vr: .US, value: uint16(unitsX.rawValue)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x6026), vr: .US, value: uint16(unitsY.rawValue)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x602C), vr: .FD, value: float64(deltaX)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x602E), vr: .FD, value: float64(deltaY))
        ])
    }

    @Test func pointInsideSpatiallyCalibratedRegionReturnsRegionDeltasAndIndex() throws {
        let region = regionElement(
            minX0: 0, minY0: 0, maxX1: 199, maxY1: 299,
            unitsX: .centimeters, unitsY: .centimeters,
            deltaX: 0.02, deltaY: 0.03
        )
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x6011), vr: .SQ, value: Data(), sequenceItems: [region])
        ])
        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))

        let result = try #require(file.measurementSpacing(atColumn: 50, row: 50))

        // Row spacing first, then column spacing — matching every other
        // spacing attribute's ordering. Values stay in centimetres, unlike
        // every other DICOM spacing attribute (millimetres).
        #expect(result.spacing == [0.03, 0.02])
        #expect(result.source == .ultrasoundRegion(index: 0))
    }

    @Test func pointOutsideEveryRegionFallsBackToPixelSpacing() throws {
        let region = regionElement(
            minX0: 0, minY0: 0, maxX1: 99, maxY1: 99,
            unitsX: .centimeters, unitsY: .centimeters,
            deltaX: 0.02, deltaY: 0.03
        )
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x6011), vr: .SQ, value: Data(), sequenceItems: [region]),
            DICOMElement(tag: .pixelSpacing, vr: .DS, value: Data("0.5\\0.5".utf8))
        ])
        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))

        let result = try #require(file.measurementSpacing(atColumn: 500, row: 500))

        #expect(result.spacing == [0.5, 0.5])
        #expect(result.source == .pixelSpacing)
    }

    @Test func pointInsideDopplerRegionFallsBackRatherThanReturningMeaninglessScale() throws {
        let region = regionElement(
            minX0: 0, minY0: 0, maxX1: 199, maxY1: 299,
            unitsX: .seconds, unitsY: .centimeters,
            deltaX: 0.001, deltaY: 0.03
        )
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x6011), vr: .SQ, value: Data(), sequenceItems: [region]),
            DICOMElement(tag: .pixelSpacing, vr: .DS, value: Data("0.4\\0.4".utf8))
        ])
        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))

        let result = try #require(file.measurementSpacing(atColumn: 50, row: 50))

        #expect(result.spacing == [0.4, 0.4])
        #expect(result.source == .pixelSpacing)
    }

    @Test func imageWithNoSpacingAtAllReturnsNil() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .rows, vr: .US, value: uint16(1))
        ])
        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))

        #expect(file.measurementSpacing(atColumn: 0, row: 0) == nil)
    }
}
