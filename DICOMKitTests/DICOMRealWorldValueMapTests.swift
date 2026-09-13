import Foundation
import Testing
@testable import DICOMKit

/// Real World Value Mapping Sequence `(0040,9096)`: the transform a PET
/// viewer uses to convert a stored pixel value to a Standardized Uptake
/// Value (SUV), separate from the Modality LUT.
struct DICOMRealWorldValueMapTests {
    @Test func slopeInterceptMapConvertsAndReturnsNilOutsideRange() throws {
        let map = DICOMRealWorldValueMap(firstValueMapped: 0, lastValueMapped: 100, slope: 2, intercept: 1)

        #expect(map.value(for: 0) == 1)
        #expect(map.value(for: 10) == 21)
        #expect(map.value(for: 100) == 201)
        #expect(map.value(for: -1) == nil)
        #expect(map.value(for: 101) == nil)
    }

    @Test func lutValuedMapIndexesCorrectlyAndClampsNothingOutsideDeclaredRange() throws {
        let map = DICOMRealWorldValueMap(firstValueMapped: 10, lastValueMapped: 12, lutData: [1.5, 2.5, 3.5])

        #expect(map.value(for: 10) == 1.5)
        #expect(map.value(for: 11) == 2.5)
        #expect(map.value(for: 12) == 3.5)
        #expect(map.value(for: 9) == nil)
        #expect(map.value(for: 13) == nil)
    }

    // MARK: - Dataset parsing

    private func realWorldValueMapItem(
        firstValueMapped: Data,
        lastValueMapped: Data,
        firstLastVR: DICOMVR,
        slope: Double? = nil,
        intercept: Double? = nil,
        lutData: [Double]? = nil,
        label: String? = nil,
        explanation: String? = nil,
        measurementUnits: DICOMDataset? = nil
    ) -> DICOMDataset {
        var elements: [DICOMElement] = [
            DICOMElement(tag: DICOMTag(group: 0x0040, element: 0x9216), vr: firstLastVR, value: firstValueMapped),
            DICOMElement(tag: DICOMTag(group: 0x0040, element: 0x9211), vr: firstLastVR, value: lastValueMapped)
        ]
        if let slope { elements.append(DICOMElement(tag: DICOMTag(group: 0x0040, element: 0x9225), vr: .FD, value: float64(slope))) }
        if let intercept { elements.append(DICOMElement(tag: DICOMTag(group: 0x0040, element: 0x9224), vr: .FD, value: float64(intercept))) }
        if let lutData {
            let bytes = lutData.reduce(into: Data()) { $0.append(float64($1)) }
            elements.append(DICOMElement(tag: DICOMTag(group: 0x0040, element: 0x9212), vr: .FD, value: bytes))
        }
        if let label { elements.append(DICOMElement(tag: DICOMTag(group: 0x0040, element: 0x9210), vr: .SH, value: Data(label.utf8))) }
        if let explanation { elements.append(DICOMElement(tag: .lutExplanation, vr: .LO, value: Data(explanation.utf8))) }
        if let measurementUnits {
            elements.append(DICOMElement(tag: DICOMTag(group: 0x0040, element: 0x08EA), vr: .SQ, value: Data(), sequenceItems: [measurementUnits]))
        }
        return DICOMDataset(elements: elements)
    }

    @Test func datasetWithSlopeInterceptExposesRealWorldValueMap() throws {
        let item = realWorldValueMapItem(
            firstValueMapped: uint16(0), lastValueMapped: uint16(32_767), firstLastVR: .US,
            slope: 0.001, intercept: 0,
            label: "SUV", explanation: "Body Weight SUV"
        )
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0040, element: 0x9096), vr: .SQ, value: Data(), sequenceItems: [item])
        ])
        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))

        let map = try #require(file.realWorldValueMaps.first)
        #expect(map.firstValueMapped == 0)
        #expect(map.lastValueMapped == 32_767)
        #expect(map.slope == 0.001)
        #expect(map.intercept == 0)
        #expect(map.label == "SUV")
        #expect(map.explanation == "Body Weight SUV")
        #expect(map.value(for: 1_000) == 1.0)
    }

    @Test func negativeFirstValueMappedWithSignedPixelRepresentationDecodesCorrectly() throws {
        // -1000 as signed 16-bit two's complement is 0xFC18.
        let item = realWorldValueMapItem(
            firstValueMapped: Data([0x18, 0xFC]), lastValueMapped: uint16(1_000), firstLastVR: .SS,
            slope: 1, intercept: 0
        )
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .pixelRepresentation, vr: .US, value: uint16(1)),
            DICOMElement(tag: DICOMTag(group: 0x0040, element: 0x9096), vr: .SQ, value: Data(), sequenceItems: [item])
        ])
        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))

        let map = try #require(file.realWorldValueMaps.first)
        #expect(map.firstValueMapped == -1_000)
        #expect(map.lastValueMapped == 1_000)
        #expect(map.value(for: -1_000) == -1_000)
    }

    @Test func measurementUnitsCodeTripletParses() throws {
        let units = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0008, element: 0x0100), vr: .SH, value: Data("g/ml".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0008, element: 0x0102), vr: .SH, value: Data("UCUM".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0008, element: 0x0104), vr: .LO, value: Data("grams per milliliter".utf8))
        ])
        let item = realWorldValueMapItem(
            firstValueMapped: uint16(0), lastValueMapped: uint16(100), firstLastVR: .US,
            slope: 1, intercept: 0,
            measurementUnits: units
        )
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0040, element: 0x9096), vr: .SQ, value: Data(), sequenceItems: [item])
        ])
        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))

        let measurementUnits = try #require(file.realWorldValueMaps.first?.measurementUnits)
        #expect(measurementUnits.codeValue == "g/ml")
        #expect(measurementUnits.codingSchemeDesignator == "UCUM")
        #expect(measurementUnits.codeMeaning == "grams per milliliter")
    }

    @Test func perFrameRealWorldValueMapIsExposedThroughFunctionalGroups() throws {
        let item = realWorldValueMapItem(
            firstValueMapped: uint16(0), lastValueMapped: uint16(100), firstLastVR: .US,
            slope: 2, intercept: 0
        )
        let functionalGroupItem = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0040, element: 0x9096), vr: .SQ, value: Data(), sequenceItems: [item])
        ])
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .numberOfFrames, vr: .IS, value: Data("1".utf8)),
            DICOMElement(tag: .perFrameFunctionalGroupsSequence, vr: .SQ, value: Data(), sequenceItems: [functionalGroupItem])
        ])
        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))

        let map = try #require(file.frameFunctionalGroups.first?.realWorldValueMaps.first)
        #expect(map.value(for: 10) == 20)
    }
}
