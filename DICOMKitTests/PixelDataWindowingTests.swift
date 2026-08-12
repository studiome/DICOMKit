import Foundation
import Testing
@testable import DICOMKit

/// The 16-bit monochrome path, where stored samples are masked, sign-extended,
/// rescaled, and windowed before they become 8-bit gray.
struct PixelDataWindowingTests {
    @Test func excludesPixelPaddingFromAutomaticWindow() throws {
        let pixelData = DICOMPixelData(
            value: uint16(0) + uint16(100) + uint16(200), rows: 1, columns: 3,
            samplesPerPixel: 1, bitsAllocated: 16, photometricInterpretation: .monochrome2,
            pixelPaddingRange: 0...0
        )

        #expect(try imageBytes(pixelData.cgImage()) == Data([0, 0, 255]))
    }

    @Test func readsPixelPaddingRangeFromDataset() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .samplesPerPixel, vr: .US, value: uint16(1)),
            DICOMElement(tag: .photometricInterpretation, vr: .CS, value: Data("MONOCHROME2".utf8)),
            DICOMElement(tag: .rows, vr: .US, value: uint16(1)),
            DICOMElement(tag: .columns, vr: .US, value: uint16(3)),
            DICOMElement(tag: .bitsAllocated, vr: .US, value: uint16(16)),
            DICOMElement(tag: .pixelPaddingValue, vr: .US, value: uint16(0)),
            DICOMElement(tag: .pixelData, vr: .OW, value: uint16(0) + uint16(100) + uint16(200))
        ])
        let pixelData = try #require(DICOMFile(data: DICOMWriter.write(dataset: dataset)).pixelData)

        #expect(pixelData.pixelPaddingRange == 0...0)
        #expect(try imageBytes(pixelData.cgImage()) == Data([0, 0, 255]))
    }
    @Test func appliesPerFrameFunctionalGroupRenderingAttributes() throws {
        func group(intercept: String, center: String) -> DICOMDataset {
            let transform = DICOMDataset(elements: [
                DICOMElement(tag: .rescaleSlope, vr: .DS, value: Data("1".utf8)),
                DICOMElement(tag: .rescaleIntercept, vr: .DS, value: Data(intercept.utf8))
            ])
            let voi = DICOMDataset(elements: [
                DICOMElement(tag: .windowCenter, vr: .DS, value: Data(center.utf8)),
                DICOMElement(tag: .windowWidth, vr: .DS, value: Data("100".utf8))
            ])
            return DICOMDataset(elements: [
                DICOMElement(tag: .pixelValueTransformationSequence, vr: .SQ, value: Data(), sequenceItems: [transform]),
                DICOMElement(tag: .frameVOILUTSequence, vr: .SQ, value: Data(), sequenceItems: [voi])
            ])
        }
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .samplesPerPixel, vr: .US, value: uint16(1)),
            DICOMElement(tag: .numberOfFrames, vr: .IS, value: Data("2".utf8)),
            DICOMElement(tag: .photometricInterpretation, vr: .CS, value: Data("MONOCHROME2".utf8)),
            DICOMElement(tag: .rows, vr: .US, value: uint16(1)),
            DICOMElement(tag: .columns, vr: .US, value: uint16(1)),
            DICOMElement(tag: .bitsAllocated, vr: .US, value: uint16(16)),
            DICOMElement(tag: .perFrameFunctionalGroupsSequence, vr: .SQ, value: Data(), sequenceItems: [group(intercept: "-1000", center: "-950"), group(intercept: "0", center: "50")]),
            DICOMElement(tag: .pixelData, vr: .OW, value: uint16(50) + uint16(50))
        ])
        let frames = try #require(DICOMFile(data: DICOMWriter.write(dataset: dataset)).pixelDataFrames)

        #expect(frames.map(\.rescaleIntercept) == [-1000, 0])
        #expect(frames.map(\.defaultWindowCenter) == [-950, 50])
    }

    @Test func appliesVOILUTWhenNoExplicitWindowIsRequested() throws {
        let lut = try DICOMVOILUT(firstMappedValue: 0, bitsPerEntry: 8, entries: [0, 255])
        let pixelData = DICOMPixelData(
            value: uint16(0) + uint16(1), rows: 1, columns: 2,
            samplesPerPixel: 1, bitsAllocated: 16,
            photometricInterpretation: .monochrome2, voiLUTs: [lut]
        )

        #expect(try imageBytes(pixelData.cgImage()) == Data([0, 255]))
        #expect(try imageBytes(pixelData.cgImage(windowCenter: 0, windowWidth: 2)) != Data([0, 255]))
    }

    @Test func readsVOILUTSequenceFromDataset() throws {
        let item = DICOMDataset(elements: [
            DICOMElement(tag: .lutDescriptor, vr: .SS, value: uint16(2) + uint16(0) + uint16(8)),
            DICOMElement(tag: .lutExplanation, vr: .LO, value: Data("Binary".utf8)),
            DICOMElement(tag: .lutData, vr: .OB, value: Data([0, 255]))
        ])
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .samplesPerPixel, vr: .US, value: uint16(1)),
            DICOMElement(tag: .photometricInterpretation, vr: .CS, value: Data("MONOCHROME2".utf8)),
            DICOMElement(tag: .rows, vr: .US, value: uint16(1)),
            DICOMElement(tag: .columns, vr: .US, value: uint16(2)),
            DICOMElement(tag: .bitsAllocated, vr: .US, value: uint16(16)),
            DICOMElement(tag: .voiLUTSequence, vr: .SQ, value: Data(), sequenceItems: [item]),
            DICOMElement(tag: .pixelData, vr: .OW, value: uint16(0) + uint16(1))
        ])
        let data = try DICOMWriter.write(dataset: dataset)
        let pixelData = try #require(DICOMFile(data: data).pixelData)

        #expect(pixelData.voiLUTs.first?.explanation == "Binary")
        #expect(try imageBytes(pixelData.cgImage()) == Data([0, 255]))
    }

    @Test func exposesMultipleDatasetWindowPresets() throws {
        let file = try DICOMFile(data: imageFile(
            rows: 1,
            columns: 1,
            bitsAllocated: 16,
            windowCenter: "40\\200",
            windowWidth: "400\\1000",
            windowCenterWidthExplanation: "Soft\\Bone",
            pixelData: uint16(0)
        ))

        let pixelData = try #require(file.pixelData)
        #expect(pixelData.windowPresets == [
            DICOMWindowPreset(center: 40, width: 400, explanation: "Soft"),
            DICOMWindowPreset(center: 200, width: 1000, explanation: "Bone")
        ])
        #expect(pixelData.defaultWindowCenter == 40)
        #expect(pixelData.defaultWindowWidth == 400)
    }

    @Test(arguments: [
        (PhotometricInterpretation.monochrome1, Data([255, 0])),
        (PhotometricInterpretation.monochrome2, Data([0, 255]))
    ])
    func sixteenBitMonochromeAppliesExpectedPolarityAfterWindowing(
        photometricInterpretation: PhotometricInterpretation,
        expectedBytes: Data
    ) throws {
        let pixelData = monochrome16Bit(
            value: uint16(0) + uint16(1_000),
            photometricInterpretation: photometricInterpretation
        )

        let image = try pixelData.cgImage(windowCenter: 500, windowWidth: 1_000)

        #expect(try imageBytes(image) == expectedBytes)
    }

    @Test func appliesWindowLevelTo16BitMonochromePixelData() throws {
        let file = try DICOMFile(data: twoSampleImageFile())

        let image = try #require(file.pixelData).cgImage(windowCenter: 500, windowWidth: 1_000)

        #expect(try imageBytes(image) == Data([0, 255]))
    }

    @Test func signedSixteenBitSampleIsSignExtendedBeforeWindowing() throws {
        // 0xFC18 is -1000 as a signed 16-bit two's complement value, but
        // 64536 if (incorrectly) treated as unsigned. A window centered on
        // -500 distinguishes the two: -1000 clamps to black, 64536 clamps to
        // white.
        let pixelData = monochrome16Bit(
            value: uint16(0) + Data([0x18, 0xFC]),
            pixelRepresentation: 1
        )

        let image = try pixelData.cgImage(windowCenter: -500, windowWidth: 1_000)

        #expect(try imageBytes(image) == Data([255, 0]))
    }

    @Test func rendersPixelDataFromDataSliceWithNonZeroStartIndex() throws {
        // `DICOMPixelData.value` set from `dataset[.pixelData]?.value` is
        // always zero-based (it comes from `Data.subdata`), but a caller
        // assembling `DICOMPixelData` directly might pass a slice instead.
        // The 16-bit decode path must resolve sample offsets relative to
        // `startIndex`, not assume `0`, or it reads garbage bytes from
        // before the slice. Regression test for the same class of bug
        // `parsesDataSliceWithNonZeroStartIndex` covers for the Part 10 reader.
        var padded = Data(repeating: 0xAA, count: 10)
        padded.append(uint16(0) + uint16(1_000))
        let slice = padded[10...]
        #expect(slice.startIndex == 10)

        let pixelData = monochrome16Bit(value: slice)

        let image = try pixelData.cgImage(windowCenter: 500, windowWidth: 1_000)

        #expect(try imageBytes(image) == Data([0, 255]))
    }

    @Test func appliesRescaleSlopeAndInterceptBeforeWindowing() throws {
        let pixelData = monochrome16Bit(
            value: uint16(0) + uint16(150),
            rescaleSlope: 2,
            rescaleIntercept: -100
        )

        // Rescaled: 0 * 2 - 100 = -100; 150 * 2 - 100 = 200.
        let image = try pixelData.cgImage(windowCenter: 0, windowWidth: 200)

        #expect(try imageBytes(image) == Data([0, 255]))
    }

    @Test func masksGarbageUpperBitsWhenBitsStoredIsNarrowerThanBitsAllocated() throws {
        // Raw stored word 0xF123 with Bits Stored = 12 must be masked to
        // 0x123 (291) before use; the garbage high nibble (0xF) must not
        // leak into the sample value.
        let pixelData = monochrome16Bit(value: Data([0x23, 0xF1]), columns: 1, bitsStored: 12)

        let image = try pixelData.cgImage(windowCenter: 292, windowWidth: 2)

        #expect(try imageBytes(image) == Data([0]))
    }

    @Test func masksAndSignExtendsSignedBitsStoredNarrowerThanBitsAllocated() throws {
        // Raw stored word 0xA800 with Bits Stored = 12 masks to 0x800; with
        // Pixel Representation 1 the 12-bit sign bit is set, so the value
        // sign-extends to -2048, not the unmasked unsigned 43008.
        let pixelData = monochrome16Bit(
            value: Data([0x00, 0xA8]),
            columns: 1,
            bitsStored: 12,
            pixelRepresentation: 1
        )

        let image = try pixelData.cgImage(windowCenter: 0, windowWidth: 4_096)

        #expect(try imageBytes(image) == Data([0]))
    }
}

// MARK: - Window selection

struct PixelDataDefaultWindowTests {
    @Test func datasetDefaultWindowIsUsedWhenCallerOmitsWindow() throws {
        let file = try DICOMFile(data: twoSampleImageFile(windowCenter: "500", windowWidth: "1000"))

        let image = try #require(file.pixelData).cgImage()

        #expect(try imageBytes(image) == Data([0, 255]))
    }

    @Test func fallsBackToComputedMinMaxWindowWhenNoDefaultsPresent() throws {
        let pixelData = monochrome16Bit(value: uint16(100) + uint16(200) + uint16(300), columns: 3)

        // No explicit window and no dataset default: falls back to
        // center = (min+max)/2 = 200, width = max-min = 200.
        let image = try pixelData.cgImage()

        #expect(try imageBytes(image) == Data([0, 128, 255]))
    }

    @Test func degenerateAllPixelsSameValueDoesNotCrashAndProducesFlatImage() throws {
        let pixelData = monochrome16Bit(value: uint16(500) + uint16(500))

        // min == max: the computed fallback window must not divide by zero
        // or throw invalidWindowWidth, and every pixel should render the
        // same value.
        let image = try pixelData.cgImage()

        #expect(Set(try imageBytes(image)).count == 1)
    }
}

// MARK: - Invalid windows

struct PixelDataWindowErrorTests {
    @Test(arguments: [
        (Double.nan, 1_000.0),
        (.infinity, 1_000.0),
        (500.0, .nan),
        (500.0, .infinity)
    ])
    func rejectsNonFiniteWindowSettings(windowCenter: Double, windowWidth: Double) throws {
        let file = try DICOMFile(data: twoSampleImageFile())
        let pixelData = try #require(file.pixelData)

        #expect(throws: DICOMImageError.invalidWindowSettings) {
            _ = try pixelData.cgImage(windowCenter: windowCenter, windowWidth: windowWidth)
        }
    }

    @Test func rejectsWindowWidthOfOneOrLess() {
        let pixelData = monochrome16Bit(value: uint16(0), columns: 1)

        #expect(throws: DICOMImageError.invalidWindowWidth) {
            _ = try pixelData.cgImage(windowCenter: 500, windowWidth: 1)
        }
    }
}

// MARK: - Helpers

/// 16-bit MONOCHROME2 pixel data, defaulting every attribute the 16-bit path
/// consults so each test only spells out the one it exercises.
private func monochrome16Bit(
    value: Data,
    columns: Int = 2,
    photometricInterpretation: PhotometricInterpretation = .monochrome2,
    bitsStored: Int? = nil,
    pixelRepresentation: Int = 0,
    rescaleSlope: Double = 1,
    rescaleIntercept: Double = 0
) -> DICOMPixelData {
    DICOMPixelData(
        value: value,
        rows: 1,
        columns: columns,
        samplesPerPixel: 1,
        bitsAllocated: 16,
        photometricInterpretation: photometricInterpretation,
        bitsStored: bitsStored,
        pixelRepresentation: pixelRepresentation,
        rescaleSlope: rescaleSlope,
        rescaleIntercept: rescaleIntercept
    )
}

/// A Part 10 file holding two 16-bit MONOCHROME2 samples, 0 and 1000: the
/// smallest input that shows both ends of a window.
private func twoSampleImageFile(windowCenter: String? = nil, windowWidth: String? = nil) -> Data {
    imageFile(
        rows: 1,
        columns: 2,
        bitsAllocated: 16,
        windowCenter: windowCenter,
        windowWidth: windowWidth,
        pixelData: uint16(0) + uint16(1_000)
    )
}
