import Foundation
import Testing
@testable import DICOMKit

/// Applying a Grayscale Softcopy Presentation State to rendered pixel data:
/// `DICOMPixelData/presentationLUTShape` composes with `MONOCHROME1`
/// polarity, and `DICOMFile.pixelData(applying:)` /
/// `pixelDataFrames(applying:)` substitute a state's shutter, VOI, and
/// Presentation LUT Shape into the frames the file would normally produce.
struct DICOMPresentationStateApplicationTests {
    // MARK: - DICOMPixelData.presentationLUTShape

    @Test func presentationLUTShapeInverseInvertsMonochrome2Rendering() throws {
        let pixelData = DICOMPixelData(
            value: uint16(0) + uint16(1_000), rows: 1, columns: 2,
            samplesPerPixel: 1, bitsAllocated: 16,
            photometricInterpretation: .monochrome2,
            presentationLUTShape: .inverse
        )

        let image = try pixelData.cgImage(windowCenter: 500, windowWidth: 1_000)

        #expect(try imageBytes(image) == Data([255, 0]))
    }

    @Test func presentationLUTShapeInverseCancelsMonochrome1Rendering() throws {
        let pixelData = DICOMPixelData(
            value: uint16(0) + uint16(1_000), rows: 1, columns: 2,
            samplesPerPixel: 1, bitsAllocated: 16,
            photometricInterpretation: .monochrome1,
            presentationLUTShape: .inverse
        )

        let image = try pixelData.cgImage(windowCenter: 500, windowWidth: 1_000)

        // MONOCHROME1's own inversion and the GSPS INVERSE shape cancel out,
        // rendering the same bytes MONOCHROME2 would produce with no shape.
        #expect(try imageBytes(image) == Data([0, 255]))
    }

    // MARK: - DICOMFile.pixelData(applying:) / pixelDataFrames(applying:)

    private func monochromeFile(
        sopInstanceUID: String,
        rows: UInt16 = 1,
        columns: UInt16,
        numberOfFrames: Int? = nil,
        windowCenter: String? = nil,
        windowWidth: String? = nil,
        pixelData: Data
    ) throws -> DICOMFile {
        var elements = [
            DICOMElement(tag: .sopInstanceUID, vr: .UI, value: Data(sopInstanceUID.utf8)),
            DICOMElement(tag: .samplesPerPixel, vr: .US, value: uint16(1)),
            DICOMElement(tag: .photometricInterpretation, vr: .CS, value: Data("MONOCHROME2".utf8))
        ]
        if let numberOfFrames {
            elements.append(DICOMElement(tag: .numberOfFrames, vr: .IS, value: Data(String(numberOfFrames).utf8)))
        }
        elements.append(DICOMElement(tag: .rows, vr: .US, value: uint16(rows)))
        elements.append(DICOMElement(tag: .columns, vr: .US, value: uint16(columns)))
        elements.append(DICOMElement(tag: .bitsAllocated, vr: .US, value: uint16(16)))
        if let windowCenter {
            elements.append(DICOMElement(tag: .windowCenter, vr: .DS, value: Data(windowCenter.utf8)))
        }
        if let windowWidth {
            elements.append(DICOMElement(tag: .windowWidth, vr: .DS, value: Data(windowWidth.utf8)))
        }
        elements.append(DICOMElement(tag: .pixelData, vr: .OW, value: pixelData))
        return try DICOMFile(data: DICOMWriter.write(dataset: DICOMDataset(elements: elements)))
    }

    private func monochrome8BitFile(sopInstanceUID: String, rows: UInt16, columns: UInt16, pixelData: Data) throws -> DICOMFile {
        try DICOMFile(data: DICOMWriter.write(dataset: DICOMDataset(elements: [
            DICOMElement(tag: .sopInstanceUID, vr: .UI, value: Data(sopInstanceUID.utf8)),
            DICOMElement(tag: .samplesPerPixel, vr: .US, value: uint16(1)),
            DICOMElement(tag: .photometricInterpretation, vr: .CS, value: Data("MONOCHROME2".utf8)),
            DICOMElement(tag: .rows, vr: .US, value: uint16(rows)),
            DICOMElement(tag: .columns, vr: .US, value: uint16(columns)),
            DICOMElement(tag: .bitsAllocated, vr: .US, value: uint16(8)),
            DICOMElement(tag: .pixelData, vr: .OB, value: pixelData)
        ])))
    }

    @Test func softcopyVOIReplacesTheImagesOwnWindowPresets() throws {
        let file = try monochromeFile(sopInstanceUID: "1.2.3.1", columns: 2, windowCenter: "10", windowWidth: "20", pixelData: uint16(0) + uint16(1_000))
        let state = DICOMPresentationState(
            referencedImages: [DICOMPresentationStateReference(sopInstanceUID: "1.2.3.1")],
            softcopyVOI: [DICOMSoftcopyVOI(windowPresets: [DICOMWindowPreset(center: 500, width: 1_000)])]
        )

        let applied = try #require(file.pixelData(applying: state))

        #expect(applied.windowPresets == [DICOMWindowPreset(center: 500, width: 1_000)])
        #expect(applied.defaultWindowCenter == 500)
        #expect(applied.defaultWindowWidth == 1_000)
    }

    @Test func softcopyVOIWindowChangesRenderedPixelsComparedToNoState() throws {
        let file = try monochromeFile(sopInstanceUID: "1.2.3.1", columns: 2, pixelData: uint16(0) + uint16(1_000))
        let withoutState = try imageBytes(try #require(file.pixelData).cgImage())
        // A wide window centered away from the data's own min/max avoids
        // clamping both samples to the same 0/255 extremes the auto-computed
        // window (center 500, width 1000) already produces.
        let state = DICOMPresentationState(
            referencedImages: [DICOMPresentationStateReference(sopInstanceUID: "1.2.3.1")],
            softcopyVOI: [DICOMSoftcopyVOI(windowPresets: [DICOMWindowPreset(center: 1_000, width: 2_000)])]
        )

        let withState = try imageBytes(try #require(file.pixelData(applying: state)).cgImage())

        #expect(withState != withoutState)
    }

    @Test func catchAllSoftcopyVOIStillApplies() throws {
        let file = try monochromeFile(sopInstanceUID: "1.2.3.1", columns: 2, pixelData: uint16(0) + uint16(1_000))
        // No referencedSOPInstanceUIDs on this item: it's a catch-all.
        let state = DICOMPresentationState(
            referencedImages: [DICOMPresentationStateReference(sopInstanceUID: "1.2.3.1")],
            softcopyVOI: [DICOMSoftcopyVOI(windowPresets: [DICOMWindowPreset(center: 900, width: 50)])]
        )

        let applied = try #require(file.pixelData(applying: state))

        #expect(applied.windowPresets == [DICOMWindowPreset(center: 900, width: 50)])
    }

    @Test func stateShutterMasksCornersOfRenderedFile() throws {
        let file = try monochrome8BitFile(sopInstanceUID: "1.2.3.1", rows: 3, columns: 3, pixelData: Data(repeating: 50, count: 9))
        let state = DICOMPresentationState(
            referencedImages: [DICOMPresentationStateReference(sopInstanceUID: "1.2.3.1")],
            displayShutter: DICOMDisplayShutter(shapes: [.rectangular(left: 2, right: 2, upper: 2, lower: 2)])
        )

        let applied = try #require(file.pixelData(applying: state))
        let bytes = try imageBytes(try applied.cgImage())

        #expect(bytes == Data([0, 0, 0, 0, 50, 0, 0, 0, 0]))
    }

    @Test func statePresentationLUTShapeReplacesTheImagesOwn() throws {
        let file = try monochromeFile(sopInstanceUID: "1.2.3.1", columns: 2, pixelData: uint16(0) + uint16(1_000))
        let state = DICOMPresentationState(
            referencedImages: [DICOMPresentationStateReference(sopInstanceUID: "1.2.3.1")],
            presentationLUTShape: .inverse
        )

        let applied = try #require(file.pixelData(applying: state))

        #expect(applied.presentationLUTShape == .inverse)
    }

    @Test func returnsNilWhenStateDoesNotReferenceTheFile() throws {
        let file = try monochromeFile(sopInstanceUID: "1.2.3.1", columns: 1, pixelData: uint16(0))
        let state = DICOMPresentationState(referencedImages: [DICOMPresentationStateReference(sopInstanceUID: "9.9.9.9")])

        #expect(file.pixelData(applying: state) == nil)
        #expect(file.pixelDataFrames(applying: state) == nil)
    }

    @Test func returnsNilWhenFileHasNoPixelData() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .sopInstanceUID, vr: .UI, value: Data("1.2.3.1".utf8))
        ])
        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))
        let state = DICOMPresentationState(referencedImages: [DICOMPresentationStateReference(sopInstanceUID: "1.2.3.1")])

        #expect(file.pixelData(applying: state) == nil)
    }

    @Test func pixelDataFramesAppliesStateToEveryFrame() throws {
        let file = try monochromeFile(sopInstanceUID: "1.2.3.1", columns: 1, numberOfFrames: 2, pixelData: uint16(0) + uint16(1_000))
        let state = DICOMPresentationState(
            referencedImages: [DICOMPresentationStateReference(sopInstanceUID: "1.2.3.1")],
            softcopyVOI: [DICOMSoftcopyVOI(windowPresets: [DICOMWindowPreset(center: 500, width: 1_000)])]
        )

        let frames = try #require(file.pixelDataFrames(applying: state))

        #expect(frames.count == 2)
        #expect(frames.allSatisfy { $0.defaultWindowCenter == 500 })
    }
}
