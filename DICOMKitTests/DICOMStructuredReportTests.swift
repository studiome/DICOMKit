import Foundation
import Testing
@testable import DICOMKit

/// Structured Report Content Item parsing (PS3.3 C.17.3): the recursive
/// Content Sequence tree that carries an SR's actual payload.
struct DICOMStructuredReportTests {
    private func valueTypeElement(_ valueType: String) -> DICOMElement {
        DICOMElement(tag: DICOMTag(group: 0x0040, element: 0xA040), vr: .CS, value: Data(valueType.utf8))
    }

    private func relationshipTypeElement(_ relationshipType: String) -> DICOMElement {
        DICOMElement(tag: DICOMTag(group: 0x0040, element: 0xA010), vr: .CS, value: Data(relationshipType.utf8))
    }

    private func contentSequenceElement(_ items: [DICOMDataset]) -> DICOMElement {
        DICOMElement(tag: DICOMTag(group: 0x0040, element: 0xA730), vr: .SQ, value: Data(), sequenceItems: items)
    }

    private func parse(_ dataset: DICOMDataset) throws -> DICOMContentItem {
        try dataset.structuredReportContentItem(isRoot: true, inheriting: .default, depth: 0)
    }

    // MARK: - CONTAINER with TEXT children

    @Test func containerRootWithTwoTextChildrenParsesRelationshipsAndText() throws {
        let child1 = DICOMDataset(elements: [
            relationshipTypeElement("CONTAINS"),
            valueTypeElement("TEXT"),
            DICOMElement(tag: DICOMTag(group: 0x0040, element: 0xA160), vr: .UT, value: Data("Finding one".utf8))
        ])
        let child2 = DICOMDataset(elements: [
            relationshipTypeElement("HAS PROPERTIES"),
            valueTypeElement("TEXT"),
            DICOMElement(tag: DICOMTag(group: 0x0040, element: 0xA160), vr: .UT, value: Data("Finding two".utf8))
        ])
        let root = DICOMDataset(elements: [
            valueTypeElement("CONTAINER"),
            DICOMElement(tag: DICOMTag(group: 0x0040, element: 0xA050), vr: .CS, value: Data("SEPARATE".utf8)),
            contentSequenceElement([child1, child2])
        ])

        let item = try parse(root)

        #expect(item.relationshipType == nil)
        #expect(item.valueType == "CONTAINER")
        #expect(item.value == .container(continuity: "SEPARATE"))
        #expect(item.children.count == 2)
        #expect(item.children[0].relationshipType == "CONTAINS")
        #expect(item.children[0].valueType == "TEXT")
        #expect(item.children[0].value == .text("Finding one"))
        #expect(item.children[1].relationshipType == "HAS PROPERTIES")
        #expect(item.children[1].value == .text("Finding two"))
    }

    // MARK: - CODE

    @Test func codeItemParsesConceptCodeSequenceTriplet() throws {
        let codeItem = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0008, element: 0x0100), vr: .SH, value: Data("R-408C3".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0008, element: 0x0102), vr: .SH, value: Data("SRT".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0008, element: 0x0104), vr: .LO, value: Data("Right".utf8))
        ])
        let child = DICOMDataset(elements: [
            relationshipTypeElement("HAS PROPERTIES"),
            valueTypeElement("CODE"),
            DICOMElement(tag: DICOMTag(group: 0x0040, element: 0xA168), vr: .SQ, value: Data(), sequenceItems: [codeItem])
        ])
        let root = DICOMDataset(elements: [
            valueTypeElement("CONTAINER"),
            contentSequenceElement([child])
        ])

        let item = try parse(root)

        #expect(item.children.first?.value == .code(DICOMCodeSequenceItem(codeValue: "R-408C3", codingSchemeDesignator: "SRT", codeMeaning: "Right")))
    }

    // MARK: - NUM

    @Test func numItemWithValueAndUnitsParses() throws {
        let unitsItem = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0008, element: 0x0100), vr: .SH, value: Data("mm".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0008, element: 0x0102), vr: .SH, value: Data("UCUM".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0008, element: 0x0104), vr: .LO, value: Data("millimeter".utf8))
        ])
        let measuredValueItem = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0040, element: 0xA30A), vr: .DS, value: Data("12.5".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0040, element: 0x08EA), vr: .SQ, value: Data(), sequenceItems: [unitsItem])
        ])
        let child = DICOMDataset(elements: [
            relationshipTypeElement("CONTAINS"),
            valueTypeElement("NUM"),
            DICOMElement(tag: DICOMTag(group: 0x0040, element: 0xA300), vr: .SQ, value: Data(), sequenceItems: [measuredValueItem])
        ])
        let root = DICOMDataset(elements: [
            valueTypeElement("CONTAINER"),
            contentSequenceElement([child])
        ])

        let item = try parse(root)

        guard case let .num(value, units, qualifier) = item.children.first?.value else {
            Issue.record("expected .num")
            return
        }
        #expect(value == 12.5)
        #expect(units == DICOMCodeSequenceItem(codeValue: "mm", codingSchemeDesignator: "UCUM", codeMeaning: "millimeter"))
        #expect(qualifier == nil)
    }

    @Test func numItemWithOnlyQualifierParsesWithNilValue() throws {
        let qualifierItem = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0008, element: 0x0100), vr: .SH, value: Data("121112".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0008, element: 0x0102), vr: .SH, value: Data("DCM".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0008, element: 0x0104), vr: .LO, value: Data("Not a number".utf8))
        ])
        let measuredValueItem = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0040, element: 0xA301), vr: .SQ, value: Data(), sequenceItems: [qualifierItem])
        ])
        let child = DICOMDataset(elements: [
            relationshipTypeElement("CONTAINS"),
            valueTypeElement("NUM"),
            DICOMElement(tag: DICOMTag(group: 0x0040, element: 0xA300), vr: .SQ, value: Data(), sequenceItems: [measuredValueItem])
        ])
        let root = DICOMDataset(elements: [
            valueTypeElement("CONTAINER"),
            contentSequenceElement([child])
        ])

        let item = try parse(root)

        guard case let .num(value, units, qualifier) = item.children.first?.value else {
            Issue.record("expected .num")
            return
        }
        #expect(value == nil)
        #expect(units == nil)
        #expect(qualifier == DICOMCodeSequenceItem(codeValue: "121112", codingSchemeDesignator: "DCM", codeMeaning: "Not a number"))
    }

    // MARK: - Unrecognised value type

    @Test func unrecognisedValueTypeBecomesUnsupportedButKeepsChildren() throws {
        let grandchild = DICOMDataset(elements: [
            relationshipTypeElement("CONTAINS"),
            valueTypeElement("TEXT"),
            DICOMElement(tag: DICOMTag(group: 0x0040, element: 0xA160), vr: .UT, value: Data("nested".utf8))
        ])
        let child = DICOMDataset(elements: [
            relationshipTypeElement("CONTAINS"),
            valueTypeElement("SOMETHING_NEW"),
            contentSequenceElement([grandchild])
        ])
        let root = DICOMDataset(elements: [
            valueTypeElement("CONTAINER"),
            contentSequenceElement([child])
        ])

        let item = try parse(root)

        let unsupportedItem = try #require(item.children.first)
        #expect(unsupportedItem.value == .unsupported(valueType: "SOMETHING_NEW"))
        #expect(unsupportedItem.children.count == 1)
        #expect(unsupportedItem.children.first?.value == .text("nested"))
    }

    // MARK: - Character set

    @Test func japaneseTextValueDecodesWithDeclaredCharacterSet() throws {
        // "田中" (JIS X 0208-escaped; see DICOMCharacterSetTests.tanakaKanjiBytes).
        var text = Data()
        text.append(contentsOf: [0x1B, 0x24, 0x42]) // ESC $ B: G0 = JIS X 0208 Kanji
        text.append(contentsOf: [0x45, 0x44, 0x43, 0x66]) // 田中
        text.append(contentsOf: [0x1B, 0x28, 0x42]) // ESC ( B: back to ASCII

        let child = DICOMDataset(elements: [
            relationshipTypeElement("CONTAINS"),
            valueTypeElement("TEXT"),
            DICOMElement(tag: DICOMTag(group: 0x0040, element: 0xA160), vr: .UT, value: text)
        ])
        let root = DICOMDataset(elements: [
            DICOMElement(tag: .specificCharacterSet, vr: .CS, value: Data("ISO 2022 IR 6\\ISO 2022 IR 87".utf8)),
            valueTypeElement("CONTAINER"),
            contentSequenceElement([child])
        ])

        let item = try parse(root)

        #expect(item.children.first?.value == .text("田中"))
    }
}
