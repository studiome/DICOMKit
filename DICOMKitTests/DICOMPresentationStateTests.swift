import Foundation
import Testing
@testable import DICOMKit

/// Grayscale Softcopy Presentation State (PS3.3 A.33.2, SOP Class
/// `1.2.840.10008.5.1.4.1.1.11.1`) parsing: how a sender prescribes the
/// display of referenced images independently of the images themselves.
struct DICOMPresentationStateTests {
    /// Referenced Image Sequence `(0008,1140)` items, shared by every module
    /// that scopes itself to a subset of referenced images (Softcopy VOI,
    /// Displayed Area, Graphic Annotation).
    private func referencedImageItem(sopInstanceUID: String, frameNumbers: String? = nil) -> DICOMDataset {
        var elements = [
            DICOMElement(tag: .referencedSOPClassUID, vr: .UI, value: Data("1.2.840.10008.5.1.4.1.1.7".utf8)),
            DICOMElement(tag: .referencedSOPInstanceUID, vr: .UI, value: Data(sopInstanceUID.utf8))
        ]
        if let frameNumbers {
            elements.append(DICOMElement(tag: DICOMTag(group: 0x0008, element: 0x1160), vr: .IS, value: Data(frameNumbers.utf8)))
        }
        return DICOMDataset(elements: elements)
    }

    private func referencedImageSequence(_ items: [DICOMDataset]) -> DICOMElement {
        DICOMElement(tag: DICOMTag(group: 0x0008, element: 0x1140), vr: .SQ, value: Data(), sequenceItems: items)
    }

    /// Builds a full GSPS dataset exercising every module the parser reads:
    /// two referenced images (one with frame numbers, one without), rotation
    /// and flip, an IDENTITY Presentation LUT Shape, a circular shutter, two
    /// Softcopy VOI items (instance-specific and catch-all), one displayed
    /// area, two graphic layers, and one graphic annotation with a text
    /// object and a polyline graphic object.
    private func gspsDataset() -> DICOMDataset {
        let seriesItem = DICOMDataset(elements: [
            DICOMElement(tag: .seriesInstanceUID, vr: .UI, value: Data("1.2.3.999".utf8)),
            referencedImageSequence([
                referencedImageItem(sopInstanceUID: "1.2.3.1", frameNumbers: "1\\2"),
                referencedImageItem(sopInstanceUID: "1.2.3.2")
            ])
        ])

        let instanceSpecificVOI = DICOMDataset(elements: [
            referencedImageSequence([referencedImageItem(sopInstanceUID: "1.2.3.1")]),
            DICOMElement(tag: .windowCenter, vr: .DS, value: Data("200".utf8)),
            DICOMElement(tag: .windowWidth, vr: .DS, value: Data("400".utf8))
        ])
        let catchAllVOI = DICOMDataset(elements: [
            DICOMElement(tag: .windowCenter, vr: .DS, value: Data("50".utf8)),
            DICOMElement(tag: .windowWidth, vr: .DS, value: Data("100".utf8))
        ])

        let displayedArea = DICOMDataset(elements: [
            referencedImageSequence([referencedImageItem(sopInstanceUID: "1.2.3.1")]),
            DICOMElement(tag: DICOMTag(group: 0x0070, element: 0x0052), vr: .SL, value: int32(10) + int32(20)),
            DICOMElement(tag: DICOMTag(group: 0x0070, element: 0x0053), vr: .SL, value: int32(500) + int32(400)),
            DICOMElement(tag: DICOMTag(group: 0x0070, element: 0x0100), vr: .CS, value: Data("SCALE TO FIT".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0070, element: 0x0101), vr: .DS, value: Data("0.5\\0.5".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0070, element: 0x0102), vr: .IS, value: Data("1\\1".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0070, element: 0x0103), vr: .FL, value: float32(1.5))
        ])

        let layer1 = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0070, element: 0x0002), vr: .CS, value: Data("LAYER1".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0070, element: 0x0062), vr: .IS, value: Data("1".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0070, element: 0x0066), vr: .US, value: uint16(0xFFFF)),
            DICOMElement(tag: DICOMTag(group: 0x0070, element: 0x0068), vr: .LO, value: Data("First layer".utf8))
        ])
        let layer2 = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0070, element: 0x0002), vr: .CS, value: Data("LAYER2".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0070, element: 0x0062), vr: .IS, value: Data("2".utf8))
        ])

        let textObject = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0070, element: 0x0006), vr: .ST, value: Data("Hello".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0070, element: 0x0010), vr: .FL, value: float32(10) + float32(20)),
            DICOMElement(tag: DICOMTag(group: 0x0070, element: 0x0011), vr: .FL, value: float32(100) + float32(120)),
            DICOMElement(tag: DICOMTag(group: 0x0070, element: 0x0014), vr: .FL, value: float32(50) + float32(60)),
            DICOMElement(tag: DICOMTag(group: 0x0070, element: 0x0003), vr: .CS, value: Data("DISPLAY".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0070, element: 0x0004), vr: .CS, value: Data("PIXEL".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0070, element: 0x0015), vr: .CS, value: Data("Y".utf8))
        ])
        let graphicObject = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0070, element: 0x0005), vr: .CS, value: Data("PIXEL".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0070, element: 0x0020), vr: .US, value: uint16(2)),
            DICOMElement(tag: DICOMTag(group: 0x0070, element: 0x0021), vr: .US, value: uint16(3)),
            DICOMElement(tag: DICOMTag(group: 0x0070, element: 0x0022), vr: .FL, value: float32(0) + float32(0) + float32(10) + float32(10) + float32(20) + float32(0)),
            DICOMElement(tag: DICOMTag(group: 0x0070, element: 0x0023), vr: .CS, value: Data("POLYLINE".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0070, element: 0x0024), vr: .CS, value: Data("N".utf8))
        ])
        let annotation = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0070, element: 0x0002), vr: .CS, value: Data("LAYER1".utf8)),
            referencedImageSequence([referencedImageItem(sopInstanceUID: "1.2.3.1")]),
            DICOMElement(tag: DICOMTag(group: 0x0070, element: 0x0008), vr: .SQ, value: Data(), sequenceItems: [textObject]),
            DICOMElement(tag: DICOMTag(group: 0x0070, element: 0x0009), vr: .SQ, value: Data(), sequenceItems: [graphicObject])
        ])
        let catchAllAnnotation = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0070, element: 0x0002), vr: .CS, value: Data("LAYER2".utf8))
        ])

        return DICOMDataset(elements: [
            DICOMElement(tag: .sopClassUID, vr: .UI, value: Data(DICOMSOPClass.grayscaleSoftcopyPresentationStateStorage.utf8)),
            DICOMElement(tag: .sopInstanceUID, vr: .UI, value: Data("1.2.3.500".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0070, element: 0x0080), vr: .CS, value: Data("LABEL".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0070, element: 0x0081), vr: .LO, value: Data("A description".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0008, element: 0x1115), vr: .SQ, value: Data(), sequenceItems: [seriesItem]),
            DICOMElement(tag: DICOMTag(group: 0x0070, element: 0x0042), vr: .US, value: uint16(90)),
            DICOMElement(tag: DICOMTag(group: 0x0070, element: 0x0041), vr: .CS, value: Data("Y".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x2050, element: 0x0020), vr: .CS, value: Data("IDENTITY".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x1600), vr: .CS, value: Data("CIRCULAR".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x1610), vr: .IS, value: Data("50\\60".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x1612), vr: .IS, value: Data("40".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0028, element: 0x3110), vr: .SQ, value: Data(), sequenceItems: [instanceSpecificVOI, catchAllVOI]),
            DICOMElement(tag: DICOMTag(group: 0x0070, element: 0x005A), vr: .SQ, value: Data(), sequenceItems: [displayedArea]),
            DICOMElement(tag: DICOMTag(group: 0x0070, element: 0x0060), vr: .SQ, value: Data(), sequenceItems: [layer1, layer2]),
            DICOMElement(tag: DICOMTag(group: 0x0070, element: 0x0001), vr: .SQ, value: Data(), sequenceItems: [annotation, catchAllAnnotation])
        ])
    }

    private func makeState() throws -> DICOMPresentationState {
        try DICOMPresentationState(file: DICOMFile(data: DICOMWriter.write(dataset: gspsDataset())))
    }

    @Test func parsesIdentificationAndReferencedImages() throws {
        let state = try makeState()

        #expect(state.sopInstanceUID == "1.2.3.500")
        #expect(state.contentLabel == "LABEL")
        #expect(state.contentDescription == "A description")
        #expect(state.referencedImages == [
            DICOMPresentationStateReference(seriesInstanceUID: "1.2.3.999", sopClassUID: "1.2.840.10008.5.1.4.1.1.7", sopInstanceUID: "1.2.3.1", frameNumbers: [1, 2]),
            DICOMPresentationStateReference(seriesInstanceUID: "1.2.3.999", sopClassUID: "1.2.840.10008.5.1.4.1.1.7", sopInstanceUID: "1.2.3.2", frameNumbers: nil)
        ])
        #expect(state.appliesTo(sopInstanceUID: "1.2.3.1"))
        #expect(state.appliesTo(sopInstanceUID: "1.2.3.2"))
        #expect(state.appliesTo(sopInstanceUID: "1.2.3.999") == false)
    }

    @Test func parsesSpatialTransformationAndPresentationLUTShape() throws {
        let state = try makeState()

        #expect(state.rotation == 90)
        #expect(state.horizontalFlip == true)
        #expect(state.presentationLUTShape == .identity)
    }

    @Test func parsesCircularDisplayShutter() throws {
        let state = try makeState()

        #expect(state.displayShutter?.shapes == [.circular(center: DICOMShutterVertex(row: 50, column: 60), radius: 40)])
    }

    @Test func softcopyVOILookupPrefersInstanceSpecificOverCatchAll() throws {
        let state = try makeState()

        let specific = try #require(state.softcopyVOI(for: "1.2.3.1"))
        #expect(specific.windowPresets == [DICOMWindowPreset(center: 200, width: 400)])

        let catchAll = try #require(state.softcopyVOI(for: "1.2.3.2"))
        #expect(catchAll.windowPresets == [DICOMWindowPreset(center: 50, width: 100)])
    }

    @Test func parsesDisplayedAreaWithColumnRowOrderedTheOppositeOfTheShutterModule() throws {
        let state = try makeState()

        let area = try #require(state.displayedArea(for: "1.2.3.1"))
        // (0070,0052)/(0070,0053) are encoded column-first; the shutter
        // module's coordinates are row-first, hence the individually named
        // properties instead of a shared vertex type.
        #expect(area.topLeftColumn == 10)
        #expect(area.topLeftRow == 20)
        #expect(area.bottomRightColumn == 500)
        #expect(area.bottomRightRow == 400)
        #expect(area.presentationSizeMode == "SCALE TO FIT")
        #expect(area.presentationPixelSpacing == [0.5, 0.5])
        #expect(area.presentationPixelAspectRatio == [1, 1])
        #expect(area.presentationPixelMagnificationRatio == 1.5)
    }

    @Test func parsesGraphicLayersInOrder() throws {
        let state = try makeState()

        #expect(state.graphicLayers == [
            DICOMGraphicLayer(name: "LAYER1", order: 1, recommendedDisplayGrayscaleValue: 0xFFFF, description: "First layer"),
            DICOMGraphicLayer(name: "LAYER2", order: 2, recommendedDisplayGrayscaleValue: nil, description: nil)
        ])
    }

    @Test func parsesGraphicAnnotationWithTextAndGraphicObjects() throws {
        let state = try makeState()

        let annotation = try #require(state.graphicAnnotations.first)
        #expect(annotation.layer == "LAYER1")
        #expect(annotation.referencedSOPInstanceUIDs == ["1.2.3.1"])

        let text = try #require(annotation.textObjects.first)
        #expect(text.text == "Hello")
        #expect(text.boundingBoxTopLeft == [10, 20])
        #expect(text.boundingBoxBottomRight == [100, 120])
        #expect(text.anchorPoint == [50, 60])
        #expect(text.boundingBoxUnits == .display)
        #expect(text.anchorPointUnits == .pixel)
        #expect(text.anchorPointVisible == true)

        let graphic = try #require(annotation.graphicObjects.first)
        #expect(graphic.units == .pixel)
        #expect(graphic.dimensions == 2)
        #expect(graphic.pointCount == 3)
        #expect(graphic.points == [0, 0, 10, 10, 20, 0])
        #expect(graphic.type == .polyline)
        #expect(graphic.filled == false)
    }

    @Test func graphicAnnotationsForReturnsBothInstanceSpecificAndCatchAll() throws {
        let state = try makeState()

        let forSpecific = state.graphicAnnotations(for: "1.2.3.1")
        #expect(forSpecific.map(\.layer) == ["LAYER1", "LAYER2"])

        let forOther = state.graphicAnnotations(for: "1.2.3.2")
        #expect(forOther.map(\.layer) == ["LAYER2"])
    }

    @Test func unknownRotationValueFallsBackToZero() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0070, element: 0x0042), vr: .US, value: uint16(45))
        ])
        let state = try DICOMPresentationState(file: DICOMFile(data: DICOMWriter.write(dataset: dataset)))

        #expect(state.rotation == 0)
    }

    @Test func nonGSPSSOPClassUIDThrows() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .sopClassUID, vr: .UI, value: Data(DICOMSOPClass.secondaryCaptureImageStorage.utf8))
        ])
        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))

        #expect(throws: DICOMError.invalidPresentationState) {
            try DICOMPresentationState(file: file)
        }
    }

    @Test func datasetWithNoSOPClassUIDStillParses() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .sopInstanceUID, vr: .UI, value: Data("1.2.3.1".utf8))
        ])
        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))

        let state = try DICOMPresentationState(file: file)
        #expect(state.sopInstanceUID == "1.2.3.1")
    }
}
