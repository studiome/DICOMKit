import Foundation
import Testing
@testable import DICOMKit
import DICOMKitAuthoring

/// Enhanced Multi-frame functional group resolution (PS3.3 C.7.6.16):
/// Shared Functional Groups Sequence `(5200,9229)` supplies per-file
/// defaults that Per-frame Functional Groups Sequence `(5200,9230)`
/// overrides for the matching frame index.
struct DICOMFrameFunctionalGroupsTests {
    @Test func resolvesSharedTransformationWithPerFrameOverrideForOneFrame() throws {
        func transformationGroup(intercept: String) -> DICOMDataset {
            DICOMDataset(elements: [
                DICOMElement(tag: .pixelValueTransformationSequence, vr: .SQ, value: Data(), sequenceItems: [DICOMDataset(elements: [
                    DICOMElement(tag: .rescaleSlope, vr: .DS, value: Data("1".utf8)),
                    DICOMElement(tag: .rescaleIntercept, vr: .DS, value: Data(intercept.utf8))
                ])])
            ])
        }
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .numberOfFrames, vr: .IS, value: Data("2".utf8)),
            DICOMElement(tag: .sharedFunctionalGroupsSequence, vr: .SQ, value: Data(), sequenceItems: [transformationGroup(intercept: "-1000")]),
            DICOMElement(tag: .perFrameFunctionalGroupsSequence, vr: .SQ, value: Data(), sequenceItems: [
                DICOMDataset(elements: []),
                transformationGroup(intercept: "-500")
            ])
        ])
        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))

        let groups = file.frameFunctionalGroups

        #expect(groups.count == 2)
        #expect(groups[0].rescaleSlope == 1)
        #expect(groups[0].rescaleIntercept == -1000) // shared value, no per-frame override
        #expect(groups[1].rescaleSlope == 1)
        #expect(groups[1].rescaleIntercept == -500) // per-frame override wins
    }

    @Test func datasetWithNoFunctionalGroupsYieldsOneAllNilEntry() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .rows, vr: .US, value: uint16(1))
        ])
        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))

        #expect(file.frameFunctionalGroups == [DICOMFrameFunctionalGroups()])
    }

    @Test func frameAttributesReturnsSameValuesAsBeforeGeneralization() throws {
        func group(intercept: String, center: String) -> DICOMDataset {
            DICOMDataset(elements: [
                DICOMElement(tag: .pixelValueTransformationSequence, vr: .SQ, value: Data(), sequenceItems: [DICOMDataset(elements: [
                    DICOMElement(tag: .rescaleSlope, vr: .DS, value: Data("1".utf8)),
                    DICOMElement(tag: .rescaleIntercept, vr: .DS, value: Data(intercept.utf8))
                ])]),
                DICOMElement(tag: .frameVOILUTSequence, vr: .SQ, value: Data(), sequenceItems: [DICOMDataset(elements: [
                    DICOMElement(tag: .windowCenter, vr: .DS, value: Data(center.utf8)),
                    DICOMElement(tag: .windowWidth, vr: .DS, value: Data("100".utf8))
                ])])
            ])
        }
        let file = try DICOMFile(data: DICOMWriter.write(dataset: DICOMDataset(elements: [
            DICOMElement(tag: .numberOfFrames, vr: .IS, value: Data("2".utf8)),
            DICOMElement(tag: .perFrameFunctionalGroupsSequence, vr: .SQ, value: Data(), sequenceItems: [group(intercept: "-1000", center: "-950"), group(intercept: "0", center: "50")])
        ])))

        #expect(file.frameAttributes == [
            DICOMFrameAttributes(rescaleSlope: 1, rescaleIntercept: -1000, windowCenter: -950, windowWidth: 100),
            DICOMFrameAttributes(rescaleSlope: 1, rescaleIntercept: 0, windowCenter: 50, windowWidth: 100)
        ])
    }
}
