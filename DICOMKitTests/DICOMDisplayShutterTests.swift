import CoreGraphics
import Foundation
import Testing
@testable import DICOMKit

/// The Display Shutter module (PS3.3 C.7.6.11): rectangular, circular, and
/// polygonal shutters obscure irrelevant image periphery.
struct DICOMDisplayShutterTests {
    @Test func rectangularShutterTreatsEdgesAsVisible() {
        let shutter = DICOMDisplayShutter(shapes: [.rectangular(left: 2, right: 4, upper: 2, lower: 4)])

        // Exactly on an edge: visible.
        #expect(shutter.obscures(row: 2, column: 2) == false)
        #expect(shutter.obscures(row: 4, column: 4) == false)
        // Just outside an edge: obscured.
        #expect(shutter.obscures(row: 1, column: 2) == true)
        #expect(shutter.obscures(row: 2, column: 5) == true)
    }

    @Test func circularShutterTreatsExactRadiusAsVisible() {
        let shutter = DICOMDisplayShutter(shapes: [.circular(center: DICOMShutterVertex(row: 5, column: 5), radius: 3)])

        // (5,8): distance 3, exactly on the radius: visible.
        #expect(shutter.obscures(row: 5, column: 8) == false)
        // (5,9): distance 4, past the radius: obscured.
        #expect(shutter.obscures(row: 5, column: 9) == true)
        #expect(shutter.obscures(row: 5, column: 5) == false)
    }

    @Test func polygonalShutterObscuresOutsideVertices() {
        let vertices = [
            DICOMShutterVertex(row: 1, column: 1),
            DICOMShutterVertex(row: 1, column: 5),
            DICOMShutterVertex(row: 5, column: 5),
            DICOMShutterVertex(row: 5, column: 1)
        ]
        let shutter = DICOMDisplayShutter(shapes: [.polygonal(vertices: vertices)])

        #expect(shutter.obscures(row: 3, column: 3) == false)
        #expect(shutter.obscures(row: 10, column: 10) == true)
    }

    @Test func multipleShapesCombineAsIntersection() {
        let shutter = DICOMDisplayShutter(shapes: [
            .rectangular(left: 0, right: 10, upper: 0, lower: 10),
            .circular(center: DICOMShutterVertex(row: 5, column: 5), radius: 2)
        ])

        // Inside the rectangle but outside the circle: obscured.
        #expect(shutter.obscures(row: 5, column: 9) == true)
        // Inside both: visible.
        #expect(shutter.obscures(row: 5, column: 6) == false)
    }

    @Test func bitmapShutterNeverObscuresAnything() {
        let shutter = DICOMDisplayShutter(shapes: [.bitmap(overlayGroup: 0x6000)])

        #expect(shutter.obscures(row: 1, column: 1) == false)
        #expect(shutter.obscures(row: 1_000, column: 1_000) == false)
    }

    // MARK: - Rendering

    @Test func rendered8BitMonochromeImageHasCornersReplacedByPresentationValueWhileCentreIsUntouched() throws {
        let shutter = DICOMDisplayShutter(
            shapes: [.rectangular(left: 2, right: 2, upper: 2, lower: 2)],
            presentationValue: 0x8000
        )
        let pixelData = DICOMPixelData(
            value: Data(repeating: 50, count: 9),
            rows: 3, columns: 3,
            samplesPerPixel: 1, bitsAllocated: 8,
            photometricInterpretation: .monochrome2,
            displayShutter: shutter
        )

        let bytes = try imageBytes(pixelData.cgImage())

        // Only the centre pixel (row 2, column 2) is inside the 1x1 shutter;
        // every corner and edge pixel is obscured to 0x8000 >> 8 = 0x80.
        #expect(bytes == Data([0x80, 0x80, 0x80, 0x80, 50, 0x80, 0x80, 0x80, 0x80]))
    }

    @Test func rendered8BitMonochromeImageDefaultsObscuredRegionToBlackWithoutAPresentationValue() throws {
        let shutter = DICOMDisplayShutter(shapes: [.rectangular(left: 2, right: 2, upper: 2, lower: 2)])
        let pixelData = DICOMPixelData(
            value: Data(repeating: 50, count: 9),
            rows: 3, columns: 3,
            samplesPerPixel: 1, bitsAllocated: 8,
            photometricInterpretation: .monochrome2,
            displayShutter: shutter
        )

        let bytes = try imageBytes(pixelData.cgImage())

        #expect(bytes == Data([0, 0, 0, 0, 50, 0, 0, 0, 0]))
    }

    @Test func renderedRGBImageHasAllThreeComponentsReplacedInObscuredRegion() throws {
        let shutter = DICOMDisplayShutter(shapes: [.rectangular(left: 2, right: 2, upper: 2, lower: 2)])
        var value = Data()
        for _ in 0..<9 { value.append(contentsOf: [10, 20, 30]) }
        let pixelData = DICOMPixelData(
            value: value,
            rows: 3, columns: 3,
            samplesPerPixel: 3, bitsAllocated: 8,
            photometricInterpretation: .rgb,
            displayShutter: shutter
        )

        let bytes = try imageBytes(pixelData.cgImage())

        // Corner pixel (row 1, column 1): all three components obscured to black.
        #expect(bytes[0...2] == Data([0, 0, 0]))
        // Centre pixel (row 2, column 2), index 4: untouched.
        #expect(bytes[12...14] == Data([10, 20, 30]))
    }

    @Test func monochrome1ShutteredRegionCarriesThePresentationValueUnInverted() throws {
        let shutter = DICOMDisplayShutter(shapes: [.rectangular(left: 2, right: 2, upper: 1, lower: 1)], presentationValue: 0x1000)
        let pixelData = DICOMPixelData(
            value: Data([0, 200]),
            rows: 1, columns: 2,
            samplesPerPixel: 1, bitsAllocated: 8,
            photometricInterpretation: .monochrome1,
            displayShutter: shutter
        )

        let bytes = try imageBytes(pixelData.cgImage())

        // Column 1 is obscured: the raw presentation value (0x1000 >> 8 =
        // 0x10) must appear un-inverted, not MONOCHROME1-inverted to 0xEF.
        #expect(bytes[0] == 0x10)
        // Column 2 is visible and still gets ordinary MONOCHROME1 inversion:
        // stored 200 -> 255 - 200 = 55.
        #expect(bytes[1] == 55)
    }

    // MARK: - Dataset parsing

    @Test func datasetParsesRectangularShutterWithPresentationValue() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x1600), vr: .CS, value: Data("RECTANGULAR".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x1602), vr: .IS, value: Data("10".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x1604), vr: .IS, value: Data("90".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x1606), vr: .IS, value: Data("10".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x1608), vr: .IS, value: Data("90".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x1622), vr: .US, value: uint16(0x2000))
        ])
        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))
        let shutter = try #require(file.displayShutter)

        #expect(shutter.shapes == [.rectangular(left: 10, right: 90, upper: 10, lower: 90)])
        #expect(shutter.presentationValue == 0x2000)
    }

    @Test func datasetParsesCircularShutter() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x1600), vr: .CS, value: Data("CIRCULAR".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x1610), vr: .IS, value: Data("50\\60".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x1612), vr: .IS, value: Data("40".utf8))
        ])
        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))
        let shutter = try #require(file.displayShutter)

        #expect(shutter.shapes == [.circular(center: DICOMShutterVertex(row: 50, column: 60), radius: 40)])
    }

    @Test func datasetParsesPolygonalShutter() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x1600), vr: .CS, value: Data("POLYGONAL".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x1620), vr: .IS, value: Data("1\\1\\1\\5\\5\\5\\5\\1".utf8))
        ])
        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))
        let shutter = try #require(file.displayShutter)

        #expect(shutter.shapes == [.polygonal(vertices: [
            DICOMShutterVertex(row: 1, column: 1),
            DICOMShutterVertex(row: 1, column: 5),
            DICOMShutterVertex(row: 5, column: 5),
            DICOMShutterVertex(row: 5, column: 1)
        ])])
    }

    @Test func datasetBitmapShutterParsesButObscuresNothing() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x1600), vr: .CS, value: Data("BITMAP".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x1623), vr: .US, value: uint16(0x6000))
        ])
        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))
        let shutter = try #require(file.displayShutter)

        #expect(shutter.shapes == [.bitmap(overlayGroup: 0x6000)])
        #expect(shutter.obscures(row: 1, column: 1) == false)
    }

    @Test func datasetReturnsNilDisplayShutterWhenShutterShapeIsAbsent() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .rows, vr: .US, value: uint16(1))
        ])
        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))

        #expect(file.displayShutter == nil)
    }
}
