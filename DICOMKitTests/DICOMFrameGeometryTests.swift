import Foundation
import Testing
@testable import DICOMKit
import DICOMKitAuthoring

/// Per-frame Pixel Measures `(0028,9110)`, Plane Position (Patient)
/// `(0020,9113)`, and Plane Orientation (Patient) `(0020,9116)` functional
/// groups, and the ``DICOMImageGeometry`` each frame resolves to.
struct DICOMFrameGeometryTests {
    private func planePositionGroup(position: String) -> DICOMDataset {
        DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0020, element: 0x9113), vr: .SQ, value: Data(), sequenceItems: [DICOMDataset(elements: [
                DICOMElement(tag: .imagePositionPatient, vr: .DS, value: Data(position.utf8))
            ])])
        ])
    }

    private func pixelMeasuresGroup(spacing: String) -> DICOMDataset {
        DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0028, element: 0x9110), vr: .SQ, value: Data(), sequenceItems: [DICOMDataset(elements: [
                DICOMElement(tag: .pixelSpacing, vr: .DS, value: Data(spacing.utf8))
            ])])
        ])
    }

    @Test func perFrameFunctionalGroupsExposePixelMeasuresAndPlaneGeometry() throws {
        let item = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0028, element: 0x9110), vr: .SQ, value: Data(), sequenceItems: [DICOMDataset(elements: [
                DICOMElement(tag: .pixelSpacing, vr: .DS, value: Data("0.5\\0.5".utf8)),
                DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x0050), vr: .DS, value: Data("1.5".utf8)),
                DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x0088), vr: .DS, value: Data("2.0".utf8))
            ])]),
            DICOMElement(tag: DICOMTag(group: 0x0020, element: 0x9113), vr: .SQ, value: Data(), sequenceItems: [DICOMDataset(elements: [
                DICOMElement(tag: .imagePositionPatient, vr: .DS, value: Data("1\\2\\3".utf8))
            ])]),
            DICOMElement(tag: DICOMTag(group: 0x0020, element: 0x9116), vr: .SQ, value: Data(), sequenceItems: [DICOMDataset(elements: [
                DICOMElement(tag: .imageOrientationPatient, vr: .DS, value: Data("1\\0\\0\\0\\1\\0".utf8))
            ])])
        ])
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .numberOfFrames, vr: .IS, value: Data("1".utf8)),
            DICOMElement(tag: .perFrameFunctionalGroupsSequence, vr: .SQ, value: Data(), sequenceItems: [item])
        ])
        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))

        let group = try #require(file.frameFunctionalGroups.first)
        #expect(group.pixelMeasures == DICOMPixelMeasures(pixelSpacing: [0.5, 0.5], sliceThickness: 1.5, spacingBetweenSlices: 2.0))
        #expect(group.planePosition == [1, 2, 3])
        #expect(group.planeOrientation == [1, 0, 0, 0, 1, 0])
    }

    @Test func twoFramesWithDifferentPlanePositionsProduceTwoGeometries() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .pixelSpacing, vr: .DS, value: Data("0.5\\0.5".utf8)),
            DICOMElement(tag: .numberOfFrames, vr: .IS, value: Data("2".utf8)),
            DICOMElement(tag: .perFrameFunctionalGroupsSequence, vr: .SQ, value: Data(), sequenceItems: [
                planePositionGroup(position: "0\\0\\0"),
                planePositionGroup(position: "0\\0\\5")
            ])
        ])
        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))

        let geometries = file.frameGeometries

        #expect(geometries.count == 2)
        #expect(geometries[0].imagePositionPatient == [0, 0, 0])
        #expect(geometries[1].imagePositionPatient == [0, 0, 5])
        // Neither frame declares its own Pixel Measures, so both inherit the
        // top-level Pixel Spacing.
        #expect(geometries[0].pixelSpacing == [0.5, 0.5])
        #expect(geometries[1].pixelSpacing == [0.5, 0.5])
    }

    @Test func frameWithNoPixelMeasuresInheritsTopLevelPixelSpacing() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .pixelSpacing, vr: .DS, value: Data("0.8\\0.8".utf8)),
            DICOMElement(tag: .numberOfFrames, vr: .IS, value: Data("1".utf8)),
            DICOMElement(tag: .perFrameFunctionalGroupsSequence, vr: .SQ, value: Data(), sequenceItems: [DICOMDataset(elements: [])])
        ])
        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))

        #expect(file.frameGeometries.first?.pixelSpacing == [0.8, 0.8])
    }

    @Test func sharedPixelMeasuresAppliesToEveryFrame() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .numberOfFrames, vr: .IS, value: Data("2".utf8)),
            DICOMElement(tag: .sharedFunctionalGroupsSequence, vr: .SQ, value: Data(), sequenceItems: [pixelMeasuresGroup(spacing: "0.3\\0.3")])
        ])
        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))

        let geometries = file.frameGeometries

        #expect(geometries.count == 2)
        #expect(geometries[0].pixelSpacing == [0.3, 0.3])
        #expect(geometries[1].pixelSpacing == [0.3, 0.3])
    }

    @Test func singleFrameFileFrameGeometriesMatchesImageGeometry() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .pixelSpacing, vr: .DS, value: Data("0.5\\0.5".utf8)),
            DICOMElement(tag: .imagePositionPatient, vr: .DS, value: Data("1\\2\\3".utf8)),
            DICOMElement(tag: .imageOrientationPatient, vr: .DS, value: Data("1\\0\\0\\0\\1\\0".utf8))
        ])
        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))

        let geometry = try #require(file.imageGeometry)

        #expect(file.frameGeometries == [geometry])
    }
}
