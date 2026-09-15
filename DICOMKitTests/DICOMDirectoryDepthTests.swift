import Foundation
import Testing
@testable import DICOMKit

/// A DICOMDIR's lower-level directory entity offsets are attacker-controlled
/// input, and PS3.3 places no ceiling on how many levels they may chain
/// through. `DICOMDirectory.nodes(startingAt:)` walks that chain recursively,
/// guarding only against cycles -- so a long, acyclic chain of records can
/// still blow the call stack. This guards against that the same way
/// `Reader.maxSequenceDepth` guards nested sequences.
struct DICOMDirectoryDepthTests {
    private func chainedDataset(depth: Int) -> DICOMDataset {
        var items: [DICOMDataset] = []
        var offsets: [UInt32] = []
        for level in 0..<depth {
            let offset = UInt32(100 + level * 100)
            offsets.append(offset)
            let isLast = level == depth - 1
            var elements = [
                DICOMElement(tag: .directoryRecordType, vr: .CS, value: Data("PATIENT".utf8))
            ]
            if !isLast {
                elements.append(DICOMElement(tag: .offsetOfReferencedLowerLevelDirectoryEntity, vr: .UL, value: uint32(offset + 100)))
            }
            items.append(DICOMDataset(elements: elements))
        }
        return DICOMDataset(elements: [
            DICOMElement(tag: .offsetOfTheFirstDirectoryRecordOfTheRootDirectoryEntity, vr: .UL, value: uint32(offsets[0])),
            DICOMElement(tag: .directoryRecordSequence, vr: .SQ, value: Data(), sequenceItems: items, sequenceItemOffsets: offsets)
        ])
    }

    @Test func deeplyChainedLowerLevelEntitiesAreRejectedRatherThanBlowingTheStack() {
        // Comfortably past any real Patient/Study/Series/Image hierarchy, and
        // past the depth this fix caps at.
        let dataset = chainedDataset(depth: 500)

        #expect(throws: DICOMError.invalidDICOMDirectory) {
            _ = try DICOMDirectory(dataset: dataset)
        }
    }

    @Test func aReasonablyDeepChainStillParses() throws {
        let dataset = chainedDataset(depth: 10)

        let directory = try DICOMDirectory(dataset: dataset)

        #expect(directory.records.count == 10)
        var node = directory.rootRecords.first
        var depth = 0
        while let current = node {
            depth += 1
            node = current.children.first
        }
        #expect(depth == 10)
    }
}
