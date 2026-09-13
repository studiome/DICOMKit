import Foundation
import Testing
@testable import DICOMKit

/// Ultrasound Region Calibration `(0018,6011)` (PS3.3 C.8.5.5.1.15): each
/// region of an ultrasound image can carry its own physical scale,
/// independent of `(0028,0030)`.
struct DICOMUltrasoundRegionTests {
    // MARK: - contains(column:row:)

    @Test func containsIsInclusiveAtEachEdgeAndFalseOutside() {
        let region = DICOMUltrasoundRegion(minX0: 10, minY0: 20, maxX1: 110, maxY1: 220)

        #expect(region.contains(column: 10, row: 20)) // top-left corner
        #expect(region.contains(column: 110, row: 220)) // bottom-right corner
        #expect(region.contains(column: 60, row: 120)) // interior
        #expect(!region.contains(column: 9, row: 20))
        #expect(!region.contains(column: 10, row: 19))
        #expect(!region.contains(column: 111, row: 220))
        #expect(!region.contains(column: 110, row: 221))
    }

    // MARK: - isSpatialCalibration

    @Test func dopplerRegionWithSecondsXAxisIsNotSpatialCalibration() {
        let region = DICOMUltrasoundRegion(
            minX0: 0, minY0: 0, maxX1: 100, maxY1: 100,
            physicalUnitsX: .seconds, physicalUnitsY: .centimeters,
            physicalDeltaX: 0.01, physicalDeltaY: 0.02
        )

        #expect(region.isSpatialCalibration == false)
    }

    @Test func bothAxesInCentimetersWithNonZeroDeltasIsSpatialCalibration() {
        let region = DICOMUltrasoundRegion(
            minX0: 0, minY0: 0, maxX1: 100, maxY1: 100,
            physicalUnitsX: .centimeters, physicalUnitsY: .centimeters,
            physicalDeltaX: 0.01, physicalDeltaY: 0.02
        )

        #expect(region.isSpatialCalibration == true)
    }

    @Test func zeroDeltaIsNotSpatialCalibration() {
        let region = DICOMUltrasoundRegion(
            minX0: 0, minY0: 0, maxX1: 100, maxY1: 100,
            physicalUnitsX: .centimeters, physicalUnitsY: .centimeters,
            physicalDeltaX: 0, physicalDeltaY: 0.02
        )

        #expect(region.isSpatialCalibration == false)
    }

    // MARK: - Dataset parsing

    @Test func twoRegionSequenceParsesBothWithBoundsDeltasAndUnits() throws {
        let firstRegion = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x6018), vr: .UL, value: uint32(0)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x601A), vr: .UL, value: uint32(0)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x601C), vr: .UL, value: uint32(199)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x601E), vr: .UL, value: uint32(299)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x6024), vr: .US, value: uint16(DICOMUltrasoundRegion.PhysicalUnit.centimeters.rawValue)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x6026), vr: .US, value: uint16(DICOMUltrasoundRegion.PhysicalUnit.centimeters.rawValue)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x602C), vr: .FD, value: float64(0.02)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x602E), vr: .FD, value: float64(0.03))
        ])
        let secondRegion = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x6018), vr: .UL, value: uint32(200)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x601A), vr: .UL, value: uint32(0)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x601C), vr: .UL, value: uint32(399)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x601E), vr: .UL, value: uint32(99)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x6024), vr: .US, value: uint16(DICOMUltrasoundRegion.PhysicalUnit.seconds.rawValue)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x6026), vr: .US, value: uint16(DICOMUltrasoundRegion.PhysicalUnit.centimeters.rawValue)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x602C), vr: .FD, value: float64(0.001)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x602E), vr: .FD, value: float64(0.05))
        ])
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x6011), vr: .SQ, value: Data(), sequenceItems: [firstRegion, secondRegion])
        ])
        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))

        #expect(file.ultrasoundRegions.count == 2)
        #expect(file.ultrasoundRegions[0] == DICOMUltrasoundRegion(
            minX0: 0, minY0: 0, maxX1: 199, maxY1: 299,
            physicalUnitsX: .centimeters, physicalUnitsY: .centimeters,
            physicalDeltaX: 0.02, physicalDeltaY: 0.03
        ))
        #expect(file.ultrasoundRegions[1] == DICOMUltrasoundRegion(
            minX0: 200, minY0: 0, maxX1: 399, maxY1: 99,
            physicalUnitsX: .seconds, physicalUnitsY: .centimeters,
            physicalDeltaX: 0.001, physicalDeltaY: 0.05
        ))
        #expect(file.ultrasoundRegions[0].isSpatialCalibration == true)
        #expect(file.ultrasoundRegions[1].isSpatialCalibration == false)
    }

    @Test func itemMissingMinX0IsSkippedWhileSiblingStillParses() throws {
        let incomplete = DICOMDataset(elements: [
            // Missing (0018,6018) Region Location Min X0.
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x601A), vr: .UL, value: uint32(0)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x601C), vr: .UL, value: uint32(199)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x601E), vr: .UL, value: uint32(299))
        ])
        let complete = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x6018), vr: .UL, value: uint32(0)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x601A), vr: .UL, value: uint32(0)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x601C), vr: .UL, value: uint32(99)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x601E), vr: .UL, value: uint32(99))
        ])
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x6011), vr: .SQ, value: Data(), sequenceItems: [incomplete, complete])
        ])
        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))

        #expect(file.ultrasoundRegions.count == 1)
        #expect(file.ultrasoundRegions[0].minX0 == 0)
        #expect(file.ultrasoundRegions[0].maxX1 == 99)
    }

    @Test func absentSequenceYieldsEmptyRegions() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .rows, vr: .US, value: uint16(1))
        ])
        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))

        #expect(file.ultrasoundRegions.isEmpty)
    }
}
