import Foundation
import Testing
@testable import DICOMKit

/// Frame Anatomy macro `(0020,9071)` parsing and per-frame Frame Display
/// Shutter macro `(0018,9472)` wiring into rendering.
struct DICOMFrameAnatomyAndShutterTests {
    // MARK: - Frame Anatomy

    @Test func frameAnatomyParsesLateralityAndAnatomicRegionCodeTriplet() throws {
        let anatomicRegion = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0008, element: 0x0100), vr: .SH, value: Data("T-D3000".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0008, element: 0x0102), vr: .SH, value: Data("SRT".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0008, element: 0x0104), vr: .LO, value: Data("Chest".utf8))
        ])
        let frameAnatomy = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0020, element: 0x9072), vr: .CS, value: Data("R".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0008, element: 0x2218), vr: .SQ, value: Data(), sequenceItems: [anatomicRegion])
        ])
        let functionalGroupItem = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0020, element: 0x9071), vr: .SQ, value: Data(), sequenceItems: [frameAnatomy])
        ])
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .numberOfFrames, vr: .IS, value: Data("1".utf8)),
            DICOMElement(tag: .perFrameFunctionalGroupsSequence, vr: .SQ, value: Data(), sequenceItems: [functionalGroupItem])
        ])
        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))

        let anatomy = try #require(file.frameFunctionalGroups.first?.frameAnatomy)
        #expect(anatomy.laterality == "R")
        #expect(anatomy.anatomicRegion == DICOMCodeSequenceItem(codeValue: "T-D3000", codingSchemeDesignator: "SRT", codeMeaning: "Chest"))
    }

    /// Code Meaning `(0008,0104)` is `LO`, so it is charset-sensitive; an ISO
    /// 2022 escape sequence in the value must decode using the dataset's
    /// Specific Character Set, not the UTF-8-only default (which would
    /// produce mojibake for a Japanese declaration).
    @Test func codeMeaningWithISO2022EscapeDecodesCorrectly() throws {
        // "田中" (JIS X 0208-escaped; see DICOMCharacterSetTests.tanakaKanjiBytes).
        var codeMeaning = Data()
        codeMeaning.append(contentsOf: [0x1B, 0x24, 0x42]) // ESC $ B: G0 = JIS X 0208 Kanji
        codeMeaning.append(contentsOf: [0x45, 0x44, 0x43, 0x66]) // 田中
        codeMeaning.append(contentsOf: [0x1B, 0x28, 0x42]) // ESC ( B: back to ASCII

        let anatomicRegion = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0008, element: 0x0104), vr: .LO, value: codeMeaning)
        ])
        let frameAnatomy = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0008, element: 0x2218), vr: .SQ, value: Data(), sequenceItems: [anatomicRegion])
        ])
        let functionalGroupItem = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0020, element: 0x9071), vr: .SQ, value: Data(), sequenceItems: [frameAnatomy])
        ])
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .specificCharacterSet, vr: .CS, value: Data("ISO 2022 IR 6\\ISO 2022 IR 87".utf8)),
            DICOMElement(tag: .numberOfFrames, vr: .IS, value: Data("1".utf8)),
            DICOMElement(tag: .perFrameFunctionalGroupsSequence, vr: .SQ, value: Data(), sequenceItems: [functionalGroupItem])
        ])
        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))

        #expect(file.frameFunctionalGroups.first?.frameAnatomy?.anatomicRegion?.codeMeaning == "田中")
    }

    // MARK: - Frame Display Shutter wiring

    private func shutterFunctionalGroupItem(left: Int, right: Int, upper: Int, lower: Int, presentationValue: UInt16?) -> DICOMDataset {
        var shutterElements: [DICOMElement] = [
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x1600), vr: .CS, value: Data("RECTANGULAR".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x1602), vr: .IS, value: Data(String(left).utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x1604), vr: .IS, value: Data(String(right).utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x1606), vr: .IS, value: Data(String(upper).utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x1608), vr: .IS, value: Data(String(lower).utf8))
        ]
        if let presentationValue {
            shutterElements.append(DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x1622), vr: .US, value: uint16(presentationValue)))
        }
        let shutterItem = DICOMDataset(elements: shutterElements)
        return DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x9472), vr: .SQ, value: Data(), sequenceItems: [shutterItem])
        ])
    }

    /// One nine-pixel 8-bit monochrome frame's raw bytes, all set to 50.
    private var nineGrayPixels: Data { Data(repeating: 50, count: 9) }

    @Test func perFrameDisplayShutterMasksOnlyThatFrameLeavingSiblingUntouched() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .samplesPerPixel, vr: .US, value: uint16(1)),
            DICOMElement(tag: .numberOfFrames, vr: .IS, value: Data("2".utf8)),
            DICOMElement(tag: .photometricInterpretation, vr: .CS, value: Data("MONOCHROME2".utf8)),
            DICOMElement(tag: .rows, vr: .US, value: uint16(3)),
            DICOMElement(tag: .columns, vr: .US, value: uint16(3)),
            DICOMElement(tag: .bitsAllocated, vr: .US, value: uint16(8)),
            DICOMElement(tag: .perFrameFunctionalGroupsSequence, vr: .SQ, value: Data(), sequenceItems: [
                DICOMDataset(elements: []), // frame 0: no shutter of its own
                shutterFunctionalGroupItem(left: 2, right: 2, upper: 2, lower: 2, presentationValue: nil)
            ]),
            DICOMElement(tag: .pixelData, vr: .OB, value: nineGrayPixels + nineGrayPixels)
        ])
        let frames = try #require(DICOMFile(data: DICOMWriter.write(dataset: dataset)).pixelDataFrames)

        #expect(try imageBytes(frames[0].cgImage()) == nineGrayPixels) // untouched: no shutter at all
        #expect(try imageBytes(frames[1].cgImage()) == Data([0, 0, 0, 0, 50, 0, 0, 0, 0])) // corners masked to black
    }

    @Test func datasetLevelShutterStillAppliesToFramesThatDeclareNone() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .samplesPerPixel, vr: .US, value: uint16(1)),
            DICOMElement(tag: .numberOfFrames, vr: .IS, value: Data("1".utf8)),
            DICOMElement(tag: .photometricInterpretation, vr: .CS, value: Data("MONOCHROME2".utf8)),
            DICOMElement(tag: .rows, vr: .US, value: uint16(3)),
            DICOMElement(tag: .columns, vr: .US, value: uint16(3)),
            DICOMElement(tag: .bitsAllocated, vr: .US, value: uint16(8)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x1600), vr: .CS, value: Data("RECTANGULAR".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x1602), vr: .IS, value: Data("2".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x1604), vr: .IS, value: Data("2".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x1606), vr: .IS, value: Data("2".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x1608), vr: .IS, value: Data("2".utf8)),
            DICOMElement(tag: .pixelData, vr: .OB, value: nineGrayPixels)
        ])
        let frames = try #require(DICOMFile(data: DICOMWriter.write(dataset: dataset)).pixelDataFrames)

        #expect(try imageBytes(frames[0].cgImage()) == Data([0, 0, 0, 0, 50, 0, 0, 0, 0]))
    }
}
