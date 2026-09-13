import Foundation
import Testing
@testable import DICOMKit
import DICOMKitNetworking
import DICOMKitAuthoring

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

    // MARK: - Task 2: the remaining value types

    private func wrapAsChild(valueType: String, elements: [DICOMElement]) -> DICOMDataset {
        DICOMDataset(elements: [relationshipTypeElement("CONTAINS"), valueTypeElement(valueType)] + elements)
    }

    private func referencedSOPSequenceElement(sopClassUID: String, sopInstanceUID: String, extra: [DICOMElement] = []) -> DICOMElement {
        let item = DICOMDataset(elements: [
            DICOMElement(tag: .referencedSOPClassUID, vr: .UI, value: Data(sopClassUID.utf8)),
            DICOMElement(tag: .referencedSOPInstanceUID, vr: .UI, value: Data(sopInstanceUID.utf8))
        ] + extra)
        return DICOMElement(tag: DICOMTag(group: 0x0008, element: 0x1199), vr: .SQ, value: Data(), sequenceItems: [item])
    }

    @Test func dateValueParsesRawDicomString() throws {
        let child = wrapAsChild(valueType: "DATE", elements: [
            DICOMElement(tag: DICOMTag(group: 0x0040, element: 0xA121), vr: .DA, value: Data("20240115".utf8))
        ])
        let item = try parse(DICOMDataset(elements: [valueTypeElement("CONTAINER"), contentSequenceElement([child])]))

        #expect(item.children.first?.value == .date("20240115"))
    }

    @Test func timeValueParsesRawDicomString() throws {
        let child = wrapAsChild(valueType: "TIME", elements: [
            DICOMElement(tag: DICOMTag(group: 0x0040, element: 0xA122), vr: .TM, value: Data("143000".utf8))
        ])
        let item = try parse(DICOMDataset(elements: [valueTypeElement("CONTAINER"), contentSequenceElement([child])]))

        #expect(item.children.first?.value == .time("143000"))
    }

    @Test func dateTimeValueParsesRawDicomString() throws {
        let child = wrapAsChild(valueType: "DATETIME", elements: [
            DICOMElement(tag: DICOMTag(group: 0x0040, element: 0xA120), vr: .DT, value: Data("20240115143000".utf8))
        ])
        let item = try parse(DICOMDataset(elements: [valueTypeElement("CONTAINER"), contentSequenceElement([child])]))

        #expect(item.children.first?.value == .dateTime("20240115143000"))
    }

    @Test func uidRefValueParses() throws {
        let child = wrapAsChild(valueType: "UIDREF", elements: [
            DICOMElement(tag: DICOMTag(group: 0x0040, element: 0xA124), vr: .UI, value: Data("1.2.3.4.5".utf8))
        ])
        let item = try parse(DICOMDataset(elements: [valueTypeElement("CONTAINER"), contentSequenceElement([child])]))

        #expect(item.children.first?.value == .uidRef("1.2.3.4.5"))
    }

    @Test func personNameValueDecodesWithItemCharacterSet() throws {
        let child = wrapAsChild(valueType: "PNAME", elements: [
            DICOMElement(tag: DICOMTag(group: 0x0040, element: 0xA123), vr: .PN, value: Data("Yamada^Taro".utf8))
        ])
        let item = try parse(DICOMDataset(elements: [valueTypeElement("CONTAINER"), contentSequenceElement([child])]))

        #expect(item.children.first?.value == .personName(DICOMPersonName("Yamada^Taro")))
    }

    @Test func imageValueParsesReferenceAndFrameNumbers() throws {
        let child = wrapAsChild(valueType: "IMAGE", elements: [
            referencedSOPSequenceElement(
                sopClassUID: "1.2.840.10008.5.1.4.1.1.7",
                sopInstanceUID: "1.2.3.100",
                extra: [DICOMElement(tag: DICOMTag(group: 0x0008, element: 0x1160), vr: .IS, value: Data("1\\3".utf8))]
            )
        ])
        let item = try parse(DICOMDataset(elements: [valueTypeElement("CONTAINER"), contentSequenceElement([child])]))

        guard case let .image(reference, frameNumbers, segmentNumbers) = item.children.first?.value else {
            Issue.record("expected .image")
            return
        }
        #expect(reference == DICOMSOPReference(sopClassUID: "1.2.840.10008.5.1.4.1.1.7", sopInstanceUID: "1.2.3.100"))
        #expect(frameNumbers == [1, 3])
        #expect(segmentNumbers == nil)
    }

    @Test func waveformValueParsesReferenceAndChannels() throws {
        let child = wrapAsChild(valueType: "WAVEFORM", elements: [
            referencedSOPSequenceElement(
                sopClassUID: "1.2.840.10008.5.1.4.1.1.9.1.1",
                sopInstanceUID: "1.2.3.200",
                extra: [DICOMElement(tag: DICOMTag(group: 0x0040, element: 0xA0B0), vr: .US, value: uint16(1) + uint16(2) + uint16(3))]
            )
        ])
        let item = try parse(DICOMDataset(elements: [valueTypeElement("CONTAINER"), contentSequenceElement([child])]))

        guard case let .waveform(reference, channels) = item.children.first?.value else {
            Issue.record("expected .waveform")
            return
        }
        #expect(reference == DICOMSOPReference(sopClassUID: "1.2.840.10008.5.1.4.1.1.9.1.1", sopInstanceUID: "1.2.3.200"))
        #expect(channels == [1, 2, 3])
    }

    @Test func compositeValueParsesReference() throws {
        let child = wrapAsChild(valueType: "COMPOSITE", elements: [
            referencedSOPSequenceElement(sopClassUID: "1.2.840.10008.5.1.4.1.1.104.1", sopInstanceUID: "1.2.3.300")
        ])
        let item = try parse(DICOMDataset(elements: [valueTypeElement("CONTAINER"), contentSequenceElement([child])]))

        #expect(item.children.first?.value == .composite(DICOMSOPReference(sopClassUID: "1.2.840.10008.5.1.4.1.1.104.1", sopInstanceUID: "1.2.3.300")))
    }

    @Test func spatialCoordinatesParsesPolylineWithFourPoints() throws {
        let points: [Float] = [0, 0, 10, 0, 10, 10, 0, 10]
        let data = points.reduce(into: Data()) { $0.append(float32($1)) }
        let child = wrapAsChild(valueType: "SCOORD", elements: [
            DICOMElement(tag: DICOMTag(group: 0x0070, element: 0x0023), vr: .CS, value: Data("POLYLINE".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0070, element: 0x0022), vr: .FL, value: data)
        ])
        let item = try parse(DICOMDataset(elements: [valueTypeElement("CONTAINER"), contentSequenceElement([child])]))

        guard case let .spatialCoordinates(graphicType, coordinateData) = item.children.first?.value else {
            Issue.record("expected .spatialCoordinates")
            return
        }
        #expect(graphicType == "POLYLINE")
        #expect(coordinateData == points.map(Double.init))
    }

    @Test func spatialCoordinates3DParsesPointsAndFrameOfReference() throws {
        let points: [Float] = [1, 2, 3]
        let data = points.reduce(into: Data()) { $0.append(float32($1)) }
        let child = wrapAsChild(valueType: "SCOORD3D", elements: [
            DICOMElement(tag: DICOMTag(group: 0x0070, element: 0x0023), vr: .CS, value: Data("POINT".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0070, element: 0x0022), vr: .FL, value: data),
            DICOMElement(tag: DICOMTag(group: 0x3006, element: 0x0024), vr: .UI, value: Data("1.2.3.999".utf8))
        ])
        let item = try parse(DICOMDataset(elements: [valueTypeElement("CONTAINER"), contentSequenceElement([child])]))

        guard case let .spatialCoordinates3D(graphicType, coordinateData, frameOfReferenceUID) = item.children.first?.value else {
            Issue.record("expected .spatialCoordinates3D")
            return
        }
        #expect(graphicType == "POINT")
        #expect(coordinateData == points.map(Double.init))
        #expect(frameOfReferenceUID == "1.2.3.999")
    }

    @Test func temporalCoordinatesParsesSamplePositions() throws {
        let child = wrapAsChild(valueType: "TCOORD", elements: [
            DICOMElement(tag: DICOMTag(group: 0x0040, element: 0xA130), vr: .CS, value: Data("MULTIPOINT".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0040, element: 0xA132), vr: .UL, value: uint32(10) + uint32(20))
        ])
        let item = try parse(DICOMDataset(elements: [valueTypeElement("CONTAINER"), contentSequenceElement([child])]))

        guard case let .temporalCoordinates(rangeType, samplePositions, timeOffsets, dateTimes) = item.children.first?.value else {
            Issue.record("expected .temporalCoordinates")
            return
        }
        #expect(rangeType == "MULTIPOINT")
        #expect(samplePositions == [10, 20])
        #expect(timeOffsets == nil)
        #expect(dateTimes == nil)
    }
}

/// ``DICOMStructuredReport``: the report root — completion/verification
/// flags, content date/time, and the parsed Content Tree — plus the guards
/// that make it safe to run over untrusted input.
struct DICOMStructuredReportDocumentTests {
    private func valueTypeElement(_ valueType: String) -> DICOMElement {
        DICOMElement(tag: DICOMTag(group: 0x0040, element: 0xA040), vr: .CS, value: Data(valueType.utf8))
    }

    private func relationshipTypeElement(_ relationshipType: String) -> DICOMElement {
        DICOMElement(tag: DICOMTag(group: 0x0040, element: 0xA010), vr: .CS, value: Data(relationshipType.utf8))
    }

    private func contentSequenceElement(_ items: [DICOMDataset]) -> DICOMElement {
        DICOMElement(tag: DICOMTag(group: 0x0040, element: 0xA730), vr: .SQ, value: Data(), sequenceItems: items)
    }

    private func parse(_ dataset: DICOMDataset) throws -> DICOMStructuredReport {
        try DICOMStructuredReport(file: DICOMFile(data: DICOMWriter.write(dataset: dataset)))
    }

    private func conceptNameElement(codeMeaning: String) -> DICOMElement {
        let item = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0008, element: 0x0104), vr: .LO, value: Data(codeMeaning.utf8))
        ])
        return DICOMElement(tag: DICOMTag(group: 0x0040, element: 0xA043), vr: .SQ, value: Data(), sequenceItems: [item])
    }

    private func measuredValueSequenceElement(value: Double, unitsCodeMeaning: String) -> DICOMElement {
        let unitsItem = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0008, element: 0x0104), vr: .LO, value: Data(unitsCodeMeaning.utf8))
        ])
        let measuredValueItem = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0040, element: 0xA30A), vr: .DS, value: Data("\(value)".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0040, element: 0x08EA), vr: .SQ, value: Data(), sequenceItems: [unitsItem])
        ])
        return DICOMElement(tag: DICOMTag(group: 0x0040, element: 0xA300), vr: .SQ, value: Data(), sequenceItems: [measuredValueItem])
    }

    @Test func basicTextSRParsesFlagsAndTwoLevelTree() throws {
        let grandchild = DICOMDataset(elements: [
            relationshipTypeElement("CONTAINS"),
            valueTypeElement("TEXT"),
            DICOMElement(tag: DICOMTag(group: 0x0040, element: 0xA160), vr: .UT, value: Data("Impression: normal".utf8))
        ])
        let child = DICOMDataset(elements: [
            relationshipTypeElement("CONTAINS"),
            valueTypeElement("CONTAINER"),
            DICOMElement(tag: DICOMTag(group: 0x0040, element: 0xA050), vr: .CS, value: Data("SEPARATE".utf8)),
            contentSequenceElement([grandchild])
        ])
        let root = DICOMDataset(elements: [
            DICOMElement(tag: .sopClassUID, vr: .UI, value: Data(DICOMSOPClass.basicTextSRStorage.utf8)),
            valueTypeElement("CONTAINER"),
            DICOMElement(tag: DICOMTag(group: 0x0040, element: 0xA491), vr: .CS, value: Data("COMPLETE".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0040, element: 0xA493), vr: .CS, value: Data("VERIFIED".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0008, element: 0x0023), vr: .DA, value: Data("20240115".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0008, element: 0x0033), vr: .TM, value: Data("143000".utf8)),
            contentSequenceElement([child])
        ])

        let report = try parse(root)

        #expect(report.sopClassUID == DICOMSOPClass.basicTextSRStorage)
        #expect(report.completionFlag == "COMPLETE")
        #expect(report.verificationFlag == "VERIFIED")
        #expect(report.contentDate == "20240115")
        #expect(report.contentTime == "143000")
        #expect(report.root.valueType == "CONTAINER")
        #expect(report.root.children.first?.valueType == "CONTAINER")
        #expect(report.root.children.first?.children.first?.value == .text("Impression: normal"))
    }

    @Test func datasetWithNoValueTypeThrows() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .sopClassUID, vr: .UI, value: Data(DICOMSOPClass.basicTextSRStorage.utf8))
        ])

        #expect(throws: DICOMError.invalidStructuredReport) {
            try self.parse(dataset)
        }
    }

    @Test func nestingPastDepthLimitThrowsInsteadOfCrashing() throws {
        func nestedContainer(remainingDepth: Int) -> DICOMDataset {
            guard remainingDepth > 0 else {
                return DICOMDataset(elements: [
                    relationshipTypeElement("CONTAINS"),
                    valueTypeElement("CONTAINER")
                ])
            }
            let child = nestedContainer(remainingDepth: remainingDepth - 1)
            return DICOMDataset(elements: [
                relationshipTypeElement("CONTAINS"),
                valueTypeElement("CONTAINER"),
                contentSequenceElement([child])
            ])
        }

        // Comfortably past DICOMDataset.structuredReportMaxDepth (64), but
        // still well short of triggering a stack overflow while *building*
        // this in-memory tree — this test's purpose is to prove
        // DICOMStructuredReport's own guard fires, not to stress-test the
        // general-purpose sequence reader (which has its own, separate
        // depth guard -- see ReaderNestingDepthTests -- and would reject
        // this same nesting first if it were round-tripped through
        // DICOMWriter/DICOMFile, since both bounds happen to be 64).
        // Calling `structuredReportContentItem` directly on the in-memory
        // dataset, instead of going through `parse` (which does that
        // round-trip), keeps this test isolated to SR's own recursion.
        let root = DICOMDataset(elements: [
            valueTypeElement("CONTAINER"),
            contentSequenceElement([nestedContainer(remainingDepth: 90)])
        ])

        #expect(throws: DICOMError.invalidStructuredReport) {
            _ = try root.structuredReportContentItem(isRoot: true, inheriting: .default, depth: 0)
        }
    }

    // MARK: - Task 4: rendering and walking

    private func threeLevelReport() throws -> DICOMStructuredReport {
        let numItem = DICOMDataset(elements: [
            relationshipTypeElement("CONTAINS"),
            valueTypeElement("NUM"),
            conceptNameElement(codeMeaning: "Length"),
            measuredValueSequenceElement(value: 12.5, unitsCodeMeaning: "millimeter")
        ])
        let findingsContainer = DICOMDataset(elements: [
            relationshipTypeElement("CONTAINS"),
            valueTypeElement("CONTAINER"),
            conceptNameElement(codeMeaning: "Findings"),
            DICOMElement(tag: DICOMTag(group: 0x0040, element: 0xA050), vr: .CS, value: Data("SEPARATE".utf8)),
            contentSequenceElement([numItem])
        ])
        let root = DICOMDataset(elements: [
            valueTypeElement("CONTAINER"),
            conceptNameElement(codeMeaning: "Report"),
            contentSequenceElement([findingsContainer])
        ])
        return try parse(root)
    }

    @Test func plainTextRendersNestedReportWithStableIndentationAndNumValue() throws {
        let report = try threeLevelReport()

        let lines = report.plainText().split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        #expect(lines.count == 3)
        #expect(lines[0] == "Report")
        #expect(lines[1] == "  Findings")
        #expect(lines[2].hasPrefix("    "))
        #expect(lines[2].contains("Length"))
        #expect(lines[2].contains("12.5"))
        #expect(lines[2].contains("millimeter"))
    }

    @Test func walkVisitsEveryItemOnceWithCorrectDepths() throws {
        let report = try threeLevelReport()

        var visited: [(valueType: String, depth: Int)] = []
        report.walk { item, depth in visited.append((item.valueType, depth)) }

        #expect(visited.map(\.valueType) == ["CONTAINER", "CONTAINER", "NUM"])
        #expect(visited.map(\.depth) == [0, 1, 2])
    }

    @Test func itemsWithValueTypeFindsNestedMatches() throws {
        let text1 = DICOMDataset(elements: [
            relationshipTypeElement("CONTAINS"),
            valueTypeElement("TEXT"),
            DICOMElement(tag: DICOMTag(group: 0x0040, element: 0xA160), vr: .UT, value: Data("first".utf8))
        ])
        let text2 = DICOMDataset(elements: [
            relationshipTypeElement("CONTAINS"),
            valueTypeElement("TEXT"),
            DICOMElement(tag: DICOMTag(group: 0x0040, element: 0xA160), vr: .UT, value: Data("second".utf8))
        ])
        let nestedContainer = DICOMDataset(elements: [
            relationshipTypeElement("CONTAINS"),
            valueTypeElement("CONTAINER"),
            contentSequenceElement([text2])
        ])
        let root = DICOMDataset(elements: [
            valueTypeElement("CONTAINER"),
            contentSequenceElement([text1, nestedContainer])
        ])
        let report = try parse(root)

        let textItems = report.items(withValueType: "TEXT")

        #expect(textItems.count == 2)
        #expect(textItems.map(\.value) == [.text("first"), .text("second")])
    }
}
