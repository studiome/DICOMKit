import Foundation
import Testing
@testable import DICOMKit

/// Frame Content macro `(0020,9111)` parsing and ``DICOMFile/frameOrder()``.
struct DICOMFrameOrderTests {
    private func frameContentGroup(stackID: String? = nil, inStackPosition: UInt32? = nil, temporalPositionIndex: UInt32? = nil) -> DICOMDataset {
        var elements: [DICOMElement] = []
        if let stackID {
            elements.append(DICOMElement(tag: DICOMTag(group: 0x0020, element: 0x9056), vr: .SH, value: Data(stackID.utf8)))
        }
        if let inStackPosition {
            elements.append(DICOMElement(tag: DICOMTag(group: 0x0020, element: 0x9057), vr: .UL, value: uint32(inStackPosition)))
        }
        if let temporalPositionIndex {
            elements.append(DICOMElement(tag: DICOMTag(group: 0x0020, element: 0x9128), vr: .UL, value: uint32(temporalPositionIndex)))
        }
        return DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0020, element: 0x9111), vr: .SQ, value: Data(), sequenceItems: [DICOMDataset(elements: elements)])
        ])
    }

    private func file(withPerFrameGroups groups: [DICOMDataset]) throws -> DICOMFile {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .numberOfFrames, vr: .IS, value: Data(String(groups.count).utf8)),
            DICOMElement(tag: .perFrameFunctionalGroupsSequence, vr: .SQ, value: Data(), sequenceItems: groups)
        ])
        return try DICOMFile(data: DICOMWriter.write(dataset: dataset))
    }

    @Test func parsesFrameContentAttributes() throws {
        let item = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0020, element: 0x9056), vr: .SH, value: Data("STACK1".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0020, element: 0x9057), vr: .UL, value: uint32(2)),
            DICOMElement(tag: DICOMTag(group: 0x0020, element: 0x9128), vr: .UL, value: uint32(1)),
            DICOMElement(tag: DICOMTag(group: 0x0020, element: 0x9157), vr: .UL, value: uint32(1) + uint32(2)),
            DICOMElement(tag: DICOMTag(group: 0x0020, element: 0x9156), vr: .US, value: uint16(7)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x9220), vr: .FD, value: float64(12.5))
        ])
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .numberOfFrames, vr: .IS, value: Data("1".utf8)),
            DICOMElement(tag: .perFrameFunctionalGroupsSequence, vr: .SQ, value: Data(), sequenceItems: [
                DICOMDataset(elements: [
                    DICOMElement(tag: DICOMTag(group: 0x0020, element: 0x9111), vr: .SQ, value: Data(), sequenceItems: [item])
                ])
            ])
        ])
        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))

        let content = try #require(file.frameFunctionalGroups.first?.frameContent)
        #expect(content.stackID == "STACK1")
        #expect(content.inStackPositionNumber == 2)
        #expect(content.temporalPositionIndex == 1)
        #expect(content.dimensionIndexValues == [1, 2])
        #expect(content.frameAcquisitionNumber == 7)
        #expect(content.frameAcquisitionDuration == 12.5)
    }

    @Test func threeFramesOrderByInStackPositionNumber() throws {
        let file = try file(withPerFrameGroups: [
            frameContentGroup(inStackPosition: 3),
            frameContentGroup(inStackPosition: 1),
            frameContentGroup(inStackPosition: 2)
        ])

        #expect(file.frameOrder() == [1, 2, 0])
    }

    @Test func twoStacksInterleaveIntoContiguousPerStackRuns() throws {
        let file = try file(withPerFrameGroups: [
            frameContentGroup(stackID: "A", inStackPosition: 1),
            frameContentGroup(stackID: "B", inStackPosition: 1),
            frameContentGroup(stackID: "A", inStackPosition: 2),
            frameContentGroup(stackID: "B", inStackPosition: 2)
        ])

        #expect(file.frameOrder() == [0, 2, 1, 3])
    }

    @Test func framesWithNoFrameContentKeepStoredOrder() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .numberOfFrames, vr: .IS, value: Data("3".utf8))
        ])
        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))

        #expect(file.frameOrder() == [0, 1, 2])
    }

    @Test func temporalPositionBreaksTieOnEqualInStackPosition() throws {
        let file = try file(withPerFrameGroups: [
            frameContentGroup(inStackPosition: 1, temporalPositionIndex: 2),
            frameContentGroup(inStackPosition: 1, temporalPositionIndex: 1)
        ])

        #expect(file.frameOrder() == [1, 0])
    }
}
