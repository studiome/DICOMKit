import Foundation
import CoreGraphics
import ImageIO
import Testing
@testable import DICOMKit

struct DICOMKitTests {
    @Test func tagHasCanonicalNotation() {
        #expect(DICOMTag.patientName.description == "(0010,0010)")
        #expect(DICOMTag(group: 0x7FE0, element: 0x0010) == .pixelData)
    }

    @Test func readsExplicitVRLittleEndianPart10File() throws {
        let file = try DICOMFile(data: part10File(
            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid,
            datasetElements: [
                element(tag: .patientName, vr: .PN, value: "Doe^Jane"),
                element(tag: .rows, vr: .US, value: uint16(512)),
                element(tag: .columns, vr: .US, value: uint16(256))
            ]
        ))

        #expect(file.transferSyntax == .explicitVRLittleEndian)
        #expect(file.dataset[.patientName]?.stringValue == "Doe^Jane")
        #expect(file.dataset[.rows]?.uint16Value == 512)
        #expect(file.dataset[.columns]?.uint16Value == 256)
    }

    @Test func readsPydicomExplicitVRLittleEndianCTFixture() throws {
        let file = try ctFixture()

        #expect(file.transferSyntax == .explicitVRLittleEndian)
        #expect(file.dataset[.rows]?.uint16Value == 128)
        #expect(file.dataset[.columns]?.uint16Value == 128)
    }

    @Test func rendersPydicomCTFixtureWithCorrectPolarityAndRescale() throws {
        // Regression test for the bug this phase fixes: CT_small.dcm is
        // signed (Pixel Representation 1) with Rescale Intercept -1024, so
        // its stored values must be sign-extended and rescaled to Hounsfield
        // Units before windowing. Before the fix, the 16-bit path ignored
        // both, so the outer corners (low stored values, around -850 HU
        // after correct rescale) rendered as mid-gray instead of black under
        // a soft-tissue window, since they were windowed as raw unsigned
        // storage values with no rescale applied.
        let file = try ctFixture()
        let pixelData = try #require(file.pixelData)

        #expect(pixelData.pixelRepresentation == 1)
        #expect(pixelData.bitsStored == 16)
        #expect(pixelData.rescaleIntercept == -1024)
        #expect(pixelData.rescaleSlope == 1)

        let image = try pixelData.cgImage(windowCenter: 40, windowWidth: 400)
        #expect(image.width == 128)
        #expect(image.height == 128)
        #expect(image.bitsPerComponent == 8)

        let bytes = try imageBytes(image)
        func pixel(row: Int, column: Int) -> UInt8 { bytes[row * 128 + column] }

        // The top corners and this background pixel are outside the scan
        // field (air, well below -160 HU, the soft-tissue window's lower
        // bound) and must render black. Verified against the fixture's raw
        // stored values directly: (0,0)=175, (0,127)=216, (10,10)=224, which
        // rescale to roughly -849, -808, and -800 HU respectively. Before
        // the fix (no sign extension, no rescale), these rendered as
        // mid-to-high gray (214, 240, and non-zero) instead of black.
        #expect(pixel(row: 0, column: 0) == 0)
        #expect(pixel(row: 0, column: 127) == 0)
        #expect(pixel(row: 10, column: 10) == 0)

        // (64,61) is the fixture's densest (bone-range) pixel: raw 2191,
        // which rescales to 1167 HU, well above the window's upper bound.
        #expect(pixel(row: 64, column: 61) == 255)

        // The body itself must show actual tissue detail, i.e. not be a single flat value.
        #expect(Set(bytes).count > 1)
    }

    @Test func readsImplicitVRLittleEndianDatasetAndUndefinedLengthSequence() throws {
        let referencedSOPClassUID = "1.2.840.10008.5.1.4.1.1.2"
        let file = try DICOMFile(data: part10File(
            transferSyntaxUID: TransferSyntax.implicitVRLittleEndian.uid,
            datasetElements: [
                implicitElement(tag: .patientName, value: "Doe^Jane"),
                implicitUndefinedLengthSequence(
                    tag: .referencedStudySequence,
                    itemElements: [
                        implicitElement(tag: .referencedSOPClassUID, value: referencedSOPClassUID)
                    ]
                )
            ]
        ))

        #expect(file.transferSyntax == .implicitVRLittleEndian)
        #expect(file.dataset[.patientName]?.stringValue == "Doe^Jane")
        #expect(file.dataset[.referencedStudySequence]?.sequenceItems?.count == 1)
        #expect(file.dataset[.referencedStudySequence]?.sequenceItems?.first?[.referencedSOPClassUID]?.stringValue == referencedSOPClassUID)
    }

    @Test func readsDefinedLengthSequenceAtEndOfDataset() throws {
        let file = try DICOMFile(data: part10File(
            transferSyntaxUID: TransferSyntax.implicitVRLittleEndian.uid,
            datasetElements: [
                implicitDefinedLengthSequence(
                    tag: .referencedStudySequence,
                    itemElements: [implicitElement(tag: .referencedSOPClassUID, value: "1.2.840.10008.5.1.4.1.1.4")]
                )
            ]
        ))

        #expect(file.dataset[.referencedStudySequence]?.sequenceItems?.count == 1)
    }

    @Test func rejectsDataWithoutPart10Preamble() {
        #expect(throws: DICOMError.missingPart10Preamble) {
            _ = try DICOMFile(data: Data())
        }
    }

    @Test func implicitVRTreatsUndefinedLengthUnregisteredTagAsSequence() throws {
        // (0008,1140) Referenced Image Sequence isn't in DICOMDictionary. In
        // Implicit VR, an unregistered tag with undefined length (0xFFFFFFFF)
        // must still be parsed as a sequence by convention.
        let referencedImageSequence = DICOMTag(group: 0x0008, element: 0x1140)
        let file = try DICOMFile(data: part10File(
            transferSyntaxUID: TransferSyntax.implicitVRLittleEndian.uid,
            datasetElements: [
                implicitUndefinedLengthSequence(
                    tag: referencedImageSequence,
                    itemElements: [implicitElement(tag: .referencedSOPClassUID, value: "1.2.840.10008.5.1.4.1.1.4")]
                )
            ]
        ))

        #expect(file.dataset[referencedImageSequence]?.vr == .SQ)
        #expect(file.dataset[referencedImageSequence]?.sequenceItems?.count == 1)
        #expect(file.dataset[referencedImageSequence]?.sequenceItems?.first?[.referencedSOPClassUID]?.stringValue == "1.2.840.10008.5.1.4.1.1.4")
    }

    @Test func uses32BitLengthMatchesPS3_5ExtraLengthVRs() {
        // DICOM PS3.5 defines exactly these VRs as using a 4-byte length field
        // in Explicit VR encoding (the same set pydicom calls `extra_length_VRs`).
        let expected: Set<DICOMVR> = [
            .OB, .OD, .OF, .OL, .OV, .OW, .SQ, .SV, .UC, .UN, .UR, .UT, .UV
        ]

        let actual = Set(DICOMVR.allCases.filter(\.uses32BitLength))

        #expect(actual == expected)
    }

    @Test func explicitVRElementsAfterSVAndUVAreReadCorrectly() throws {
        let file = try DICOMFile(data: part10File(
            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid,
            datasetElements: [
                element(tag: DICOMTag(group: 0x0009, element: 0x0001), vr: .SV, value: Data(repeating: 0, count: 8)),
                element(tag: DICOMTag(group: 0x0009, element: 0x0002), vr: .UV, value: Data(repeating: 0, count: 8)),
                element(tag: .patientName, vr: .PN, value: "Doe^Jane")
            ]
        ))

        #expect(file.dataset[.patientName]?.stringValue == "Doe^Jane")
    }

    @Test func duplicateTagRetainsLastElementInsteadOfCrashing() throws {
        let file = try DICOMFile(data: part10File(
            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid,
            datasetElements: [
                element(tag: .patientName, vr: .PN, value: "Doe^Jane"),
                element(tag: .patientName, vr: .PN, value: "Doe^John")
            ]
        ))

        #expect(file.dataset[.patientName]?.stringValue == "Doe^John")
    }

    @Test func datasetInitRetainsLastElementForDuplicateTags() {
        let first = DICOMElement(tag: .patientName, vr: .PN, value: Data("Doe^Jane".utf8))
        let second = DICOMElement(tag: .patientName, vr: .PN, value: Data("Doe^John".utf8))

        let dataset = DICOMDataset(elements: [first, second])

        #expect(dataset[.patientName]?.stringValue == "Doe^John")
    }

    @Test func parsesDataSliceWithNonZeroStartIndex() throws {
        let fullFile = part10File(
            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid,
            datasetElements: [
                element(tag: .patientName, vr: .PN, value: "Doe^Jane"),
                element(tag: .rows, vr: .US, value: uint16(512))
            ]
        )
        var padded = Data(repeating: 0xAA, count: 500)
        padded.append(fullFile)
        let slice = padded[500...]
        #expect(slice.startIndex == 500)

        let file = try DICOMFile(data: slice)

        #expect(file.transferSyntax == .explicitVRLittleEndian)
        #expect(file.dataset[.patientName]?.stringValue == "Doe^Jane")
        #expect(file.dataset[.rows]?.uint16Value == 512)
    }

    @Test func doubleValueParsesFirstComponentOfMultiValuedDS() {
        let element = DICOMElement(tag: .windowCenter, vr: .DS, value: Data("40\\400".utf8))

        #expect(element.doubleValue == 40)
    }

    @Test func doubleValueParsesNegativeNumber() {
        let element = DICOMElement(tag: .rescaleIntercept, vr: .DS, value: Data("-1024".utf8))

        #expect(element.doubleValue == -1024)
    }

    @Test func doubleValueReturnsNilForUnparsableValue() {
        let element = DICOMElement(tag: .rescaleIntercept, vr: .DS, value: Data("abc".utf8))

        #expect(element.doubleValue == nil)
    }

    @Test func int16ValueDecodesTwosComplementNegativeValue() {
        let element = DICOMElement(tag: DICOMTag(group: 0x0028, element: 0x0120), vr: .SS, value: Data([0x18, 0xFC]))

        #expect(element.int16Value == -1000)
    }

    @Test func int16ValueReturnsNilWhenValueIsTooShort() {
        let element = DICOMElement(tag: DICOMTag(group: 0x0028, element: 0x0120), vr: .SS, value: Data([0x18]))

        #expect(element.int16Value == nil)
    }

    @Test func renders8BitMonochromePixelData() throws {
        let file = try DICOMFile(data: part10File(
            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid,
            datasetElements: [
                element(tag: .samplesPerPixel, vr: .US, value: uint16(1)),
                element(tag: .photometricInterpretation, vr: .CS, value: "MONOCHROME2"),
                element(tag: .rows, vr: .US, value: uint16(2)),
                element(tag: .columns, vr: .US, value: uint16(2)),
                element(tag: .bitsAllocated, vr: .US, value: uint16(8)),
                element(tag: .pixelData, vr: .OB, value: Data([0, 64, 128, 255]))
            ]
        ))

        let image = try #require(file.pixelData).cgImage()

        #expect(image.width == 2)
        #expect(image.height == 2)
        #expect(image.bitsPerComponent == 8)
        #expect(try imageBytes(image) == Data([0, 64, 128, 255]))
    }

    @Test func rendersInterleavedRGBPixelData() throws {
        let file = try DICOMFile(data: part10File(
            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid,
            datasetElements: [
                element(tag: .samplesPerPixel, vr: .US, value: uint16(3)),
                element(tag: .photometricInterpretation, vr: .CS, value: "RGB"),
                element(tag: .planarConfiguration, vr: .US, value: uint16(0)),
                element(tag: .rows, vr: .US, value: uint16(1)),
                element(tag: .columns, vr: .US, value: uint16(2)),
                element(tag: .bitsAllocated, vr: .US, value: uint16(8)),
                element(tag: .pixelData, vr: .OB, value: Data([255, 0, 0, 0, 255, 0]))
            ]
        ))

        let image = try #require(file.pixelData).cgImage()

        #expect(image.width == 2)
        #expect(image.height == 1)
        #expect(try imageBytes(image) == Data([255, 0, 0, 0, 255, 0]))
    }

    @Test(arguments: [
        ("MONOCHROME1", Data([255, 191, 127, 0])),
        ("MONOCHROME2", Data([0, 64, 128, 255]))
    ])
    func eightBitMonochromeAppliesExpectedPolarity(photometricInterpretation: String, expectedBytes: Data) throws {
        let pixelData = DICOMPixelData(
            value: Data([0, 64, 128, 255]),
            rows: 2,
            columns: 2,
            samplesPerPixel: 1,
            bitsAllocated: 8,
            photometricInterpretation: PhotometricInterpretation(name: photometricInterpretation),
            planarConfiguration: 0
        )

        let image = try pixelData.cgImage()

        #expect(try imageBytes(image) == expectedBytes)
    }

    @Test(arguments: [
        ("MONOCHROME1", Data([255, 0])),
        ("MONOCHROME2", Data([0, 255]))
    ])
    func sixteenBitMonochromeAppliesExpectedPolarityAfterWindowing(photometricInterpretation: String, expectedBytes: Data) throws {
        let pixelData = DICOMPixelData(
            value: uint16(0) + uint16(1_000),
            rows: 1,
            columns: 2,
            samplesPerPixel: 1,
            bitsAllocated: 16,
            photometricInterpretation: PhotometricInterpretation(name: photometricInterpretation),
            planarConfiguration: 0
        )

        let image = try pixelData.cgImage(windowCenter: 500, windowWidth: 1_000)

        #expect(try imageBytes(image) == expectedBytes)
    }

    @Test func rejectsPart10DataWithoutTransferSyntaxUID() {
        var data = Data(repeating: 0, count: 128)
        data.append(contentsOf: "DICM".utf8)

        #expect(throws: DICOMError.missingTransferSyntaxUID) {
            _ = try DICOMFile(data: data)
        }
    }

    @Test func rejectsNonFiniteWindowCenter() throws {
        let file = try DICOMFile(data: part10File(
            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid,
            datasetElements: [
                element(tag: .samplesPerPixel, vr: .US, value: uint16(1)),
                element(tag: .photometricInterpretation, vr: .CS, value: "MONOCHROME2"),
                element(tag: .rows, vr: .US, value: uint16(1)),
                element(tag: .columns, vr: .US, value: uint16(2)),
                element(tag: .bitsAllocated, vr: .US, value: uint16(16)),
                element(tag: .pixelData, vr: .OW, value: uint16(0) + uint16(1_000))
            ]
        ))
        let pixelData = try #require(file.pixelData)

        #expect(throws: DICOMImageError.invalidWindowSettings) {
            _ = try pixelData.cgImage(windowCenter: .nan, windowWidth: 1_000)
        }
        #expect(throws: DICOMImageError.invalidWindowSettings) {
            _ = try pixelData.cgImage(windowCenter: .infinity, windowWidth: 1_000)
        }
    }

    @Test func rejectsNonFiniteWindowWidth() throws {
        let file = try DICOMFile(data: part10File(
            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid,
            datasetElements: [
                element(tag: .samplesPerPixel, vr: .US, value: uint16(1)),
                element(tag: .photometricInterpretation, vr: .CS, value: "MONOCHROME2"),
                element(tag: .rows, vr: .US, value: uint16(1)),
                element(tag: .columns, vr: .US, value: uint16(2)),
                element(tag: .bitsAllocated, vr: .US, value: uint16(16)),
                element(tag: .pixelData, vr: .OW, value: uint16(0) + uint16(1_000))
            ]
        ))
        let pixelData = try #require(file.pixelData)

        #expect(throws: DICOMImageError.invalidWindowSettings) {
            _ = try pixelData.cgImage(windowCenter: 500, windowWidth: .nan)
        }
        #expect(throws: DICOMImageError.invalidWindowSettings) {
            _ = try pixelData.cgImage(windowCenter: 500, windowWidth: .infinity)
        }
    }

    @Test func appliesWindowLevelTo16BitMonochromePixelData() throws {
        let file = try DICOMFile(data: part10File(
            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid,
            datasetElements: [
                element(tag: .samplesPerPixel, vr: .US, value: uint16(1)),
                element(tag: .photometricInterpretation, vr: .CS, value: "MONOCHROME2"),
                element(tag: .rows, vr: .US, value: uint16(1)),
                element(tag: .columns, vr: .US, value: uint16(2)),
                element(tag: .bitsAllocated, vr: .US, value: uint16(16)),
                element(tag: .pixelData, vr: .OW, value: uint16(0) + uint16(1_000))
            ]
        ))

        let image = try #require(file.pixelData).cgImage(windowCenter: 500, windowWidth: 1_000)

        #expect(try imageBytes(image) == Data([0, 255]))
    }

    @Test func signedSixteenBitSampleIsSignExtendedBeforeWindowing() throws {
        // 0xFC18 is -1000 as a signed 16-bit two's complement value, but
        // 64536 if (incorrectly) treated as unsigned. A window centered on
        // -500 distinguishes the two: -1000 clamps to black, 64536 clamps to
        // white.
        let pixelData = DICOMPixelData(
            value: uint16(0) + Data([0x18, 0xFC]),
            rows: 1,
            columns: 2,
            samplesPerPixel: 1,
            bitsAllocated: 16,
            photometricInterpretation: .monochrome2,
            planarConfiguration: 0,
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

        let pixelData = DICOMPixelData(
            value: slice,
            rows: 1,
            columns: 2,
            samplesPerPixel: 1,
            bitsAllocated: 16,
            photometricInterpretation: .monochrome2,
            planarConfiguration: 0
        )

        let image = try pixelData.cgImage(windowCenter: 500, windowWidth: 1_000)

        #expect(try imageBytes(image) == Data([0, 255]))
    }

    @Test func appliesRescaleSlopeAndInterceptBeforeWindowing() throws {
        let pixelData = DICOMPixelData(
            value: uint16(0) + uint16(150),
            rows: 1,
            columns: 2,
            samplesPerPixel: 1,
            bitsAllocated: 16,
            photometricInterpretation: .monochrome2,
            planarConfiguration: 0,
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
        let pixelData = DICOMPixelData(
            value: Data([0x23, 0xF1]),
            rows: 1,
            columns: 1,
            samplesPerPixel: 1,
            bitsAllocated: 16,
            photometricInterpretation: .monochrome2,
            planarConfiguration: 0,
            bitsStored: 12
        )

        let image = try pixelData.cgImage(windowCenter: 292, windowWidth: 2)

        #expect(try imageBytes(image) == Data([0]))
    }

    @Test func masksAndSignExtendsSignedBitsStoredNarrowerThanBitsAllocated() throws {
        // Raw stored word 0xA800 with Bits Stored = 12 masks to 0x800; with
        // Pixel Representation 1 the 12-bit sign bit is set, so the value
        // sign-extends to -2048, not the unmasked unsigned 43008.
        let pixelData = DICOMPixelData(
            value: Data([0x00, 0xA8]),
            rows: 1,
            columns: 1,
            samplesPerPixel: 1,
            bitsAllocated: 16,
            photometricInterpretation: .monochrome2,
            planarConfiguration: 0,
            bitsStored: 12,
            pixelRepresentation: 1
        )

        let image = try pixelData.cgImage(windowCenter: 0, windowWidth: 4_096)

        #expect(try imageBytes(image) == Data([0]))
    }

    @Test func datasetDefaultWindowIsUsedWhenCallerOmitsWindow() throws {
        let file = try DICOMFile(data: part10File(
            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid,
            datasetElements: [
                element(tag: .samplesPerPixel, vr: .US, value: uint16(1)),
                element(tag: .photometricInterpretation, vr: .CS, value: "MONOCHROME2"),
                element(tag: .rows, vr: .US, value: uint16(1)),
                element(tag: .columns, vr: .US, value: uint16(2)),
                element(tag: .bitsAllocated, vr: .US, value: uint16(16)),
                element(tag: .windowCenter, vr: .DS, value: "500"),
                element(tag: .windowWidth, vr: .DS, value: "1000"),
                element(tag: .pixelData, vr: .OW, value: uint16(0) + uint16(1_000))
            ]
        ))

        let image = try #require(file.pixelData).cgImage()

        #expect(try imageBytes(image) == Data([0, 255]))
    }

    @Test func fallsBackToComputedMinMaxWindowWhenNoDefaultsPresent() throws {
        let pixelData = DICOMPixelData(
            value: uint16(100) + uint16(200) + uint16(300),
            rows: 1,
            columns: 3,
            samplesPerPixel: 1,
            bitsAllocated: 16,
            photometricInterpretation: .monochrome2,
            planarConfiguration: 0
        )

        // No explicit window and no dataset default: falls back to
        // center = (min+max)/2 = 200, width = max-min = 200.
        let image = try pixelData.cgImage()

        #expect(try imageBytes(image) == Data([0, 128, 255]))
    }

    @Test func degenerateAllPixelsSameValueDoesNotCrashAndProducesFlatImage() throws {
        let pixelData = DICOMPixelData(
            value: uint16(500) + uint16(500),
            rows: 1,
            columns: 2,
            samplesPerPixel: 1,
            bitsAllocated: 16,
            photometricInterpretation: .monochrome2,
            planarConfiguration: 0
        )

        // min == max: the computed fallback window must not divide by zero
        // or throw invalidWindowWidth, and every pixel should render the
        // same value.
        let image = try pixelData.cgImage()

        #expect(Set(try imageBytes(image)).count == 1)
    }

    @Test(arguments: [0, 17])
    func rejectsBitsStoredOutsideValidRange(bitsStored: Int) {
        let pixelData = DICOMPixelData(
            value: uint16(0),
            rows: 1,
            columns: 1,
            samplesPerPixel: 1,
            bitsAllocated: 16,
            photometricInterpretation: .monochrome2,
            planarConfiguration: 0,
            bitsStored: bitsStored
        )

        #expect(throws: DICOMImageError.invalidImageAttributes) {
            _ = try pixelData.cgImage(windowCenter: 0, windowWidth: 10)
        }
    }

    // MARK: - Malformed input error cases

    @Test func rejectsElementWhoseLengthExceedsRemainingData() {
        let data = part10File(
            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid,
            datasetElements: [
                explicitVRElementWithDeclaredLength(tag: .patientName, vr: .PN, length: 100, value: Data("Doe".utf8))
            ]
        )

        #expect(throws: DICOMError.truncatedData) {
            _ = try DICOMFile(data: data)
        }
    }

    @Test func rejectsUndefinedLengthSequenceThatNeverCloses() {
        let data = part10File(
            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid,
            datasetElements: [
                explicitVRElementWithDeclaredLength(tag: .referencedStudySequence, vr: .SQ, length: .max)
            ]
        )

        #expect(throws: DICOMError.truncatedData) {
            _ = try DICOMFile(data: data)
        }
    }

    @Test func rejectsUnrecognizedExplicitVRCode() {
        let data = part10File(
            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid,
            datasetElements: [
                explicitVRElementWithInvalidVR(tag: .patientName, vrText: "ZZ", length: 0)
            ]
        )

        #expect(throws: DICOMError.invalidVR("ZZ")) {
            _ = try DICOMFile(data: data)
        }
    }

    @Test func rejectsExplicitVRBigEndianTransferSyntax() {
        let data = part10File(transferSyntaxUID: TransferSyntax.explicitVRBigEndian.uid, datasetElements: [])

        #expect(throws: DICOMError.unsupportedTransferSyntax(TransferSyntax.explicitVRBigEndian.uid)) {
            _ = try DICOMFile(data: data)
        }
    }

    @Test func rejectsUnknownTransferSyntaxUID() {
        let unknownUID = "1.2.3.4.5.6.7.8.9"
        let data = part10File(transferSyntaxUID: unknownUID, datasetElements: [])

        #expect(throws: DICOMError.unsupportedTransferSyntax(unknownUID)) {
            _ = try DICOMFile(data: data)
        }
    }

    @Test func decodesSingleFrame8BitRLELosslessPixelData() throws {
        let data = part10File(
            transferSyntaxUID: TransferSyntax.rleLossless.uid,
            datasetElements: [
                element(tag: .samplesPerPixel, vr: .US, value: uint16(1)),
                element(tag: .photometricInterpretation, vr: .CS, value: "MONOCHROME2"),
                element(tag: .rows, vr: .US, value: uint16(2)),
                element(tag: .columns, vr: .US, value: uint16(2)),
                element(tag: .bitsAllocated, vr: .US, value: uint16(8)),
                encapsulatedPixelData(fragments: [rleFrame(segment: Data([0x03, 0, 64, 128, 255]))])
            ]
        )

        let file = try DICOMFile(data: data)
        let image = try #require(file.pixelData).cgImage()

        #expect(file.transferSyntax == .rleLossless)
        #expect(try imageBytes(image) == Data([0, 64, 128, 255]))
    }

    @Test func decodesSingleFrame16BitRLELosslessPixelData() throws {
        let data = part10File(
            transferSyntaxUID: TransferSyntax.rleLossless.uid,
            datasetElements: [
                element(tag: .samplesPerPixel, vr: .US, value: uint16(1)),
                element(tag: .photometricInterpretation, vr: .CS, value: "MONOCHROME2"),
                element(tag: .rows, vr: .US, value: uint16(1)),
                element(tag: .columns, vr: .US, value: uint16(2)),
                element(tag: .bitsAllocated, vr: .US, value: uint16(16)),
                // RLE segments are stored most-significant byte first. The
                // two segments below represent little-endian samples 0 and
                // 1000 once reconstructed: [00 00] and [E8 03].
                encapsulatedPixelData(fragments: [rleFrame(segments: [
                    Data([0x01, 0x00, 0x03]),
                    Data([0x01, 0x00, 0xE8])
                ])])
            ]
        )

        let file = try DICOMFile(data: data)
        let image = try #require(file.pixelData).cgImage(windowCenter: 500, windowWidth: 1_000)

        #expect(try imageBytes(image) == Data([0, 255]))
    }

    @Test func decodesSingleFrame8BitRGBRLELosslessPixelData() throws {
        let data = part10File(
            transferSyntaxUID: TransferSyntax.rleLossless.uid,
            datasetElements: [
                element(tag: .samplesPerPixel, vr: .US, value: uint16(3)),
                element(tag: .photometricInterpretation, vr: .CS, value: "RGB"),
                element(tag: .planarConfiguration, vr: .US, value: uint16(0)),
                element(tag: .rows, vr: .US, value: uint16(1)),
                element(tag: .columns, vr: .US, value: uint16(2)),
                element(tag: .bitsAllocated, vr: .US, value: uint16(8)),
                // RLE stores each color component in its own segment. These
                // planes reconstruct to interleaved pixels [255,0,0, 0,255,0].
                encapsulatedPixelData(fragments: [rleFrame(segments: [
                    Data([0x01, 255, 0]),
                    Data([0x01, 0, 255]),
                    Data([0x01, 0, 0])
                ])])
            ]
        )

        let file = try DICOMFile(data: data)
        let image = try #require(file.pixelData).cgImage()

        #expect(try imageBytes(image) == Data([255, 0, 0, 0, 255, 0]))
    }

    @Test func decodesMultiFrame8BitRLELosslessPixelDataUsingBasicOffsetTable() throws {
        let firstFrame = rleFrame(segment: Data([0x00, 0x12]))
        let secondFrame = rleFrame(segment: Data([0x00, 0x34]))
        let data = part10File(
            transferSyntaxUID: TransferSyntax.rleLossless.uid,
            datasetElements: [
                element(tag: .numberOfFrames, vr: .IS, value: "2"),
                element(tag: .samplesPerPixel, vr: .US, value: uint16(1)),
                element(tag: .photometricInterpretation, vr: .CS, value: "MONOCHROME2"),
                element(tag: .rows, vr: .US, value: uint16(1)),
                element(tag: .columns, vr: .US, value: uint16(1)),
                element(tag: .bitsAllocated, vr: .US, value: uint16(8)),
                // Each serialized fragment is 8 bytes of item header plus a
                // 66-byte RLE frame. BOT offsets are relative to the first
                // fragment item tag, as defined for encapsulated Pixel Data.
                encapsulatedPixelData(
                    basicOffsetTable: uint32(0) + uint32(74),
                    fragments: [firstFrame, secondFrame]
                )
            ]
        )

        let file = try DICOMFile(data: data)
        let frames = try #require(file.pixelDataFrames)

        #expect(frames.count == 2)
        #expect(try imageBytes(frames[0].cgImage()) == Data([0x12]))
        #expect(try imageBytes(frames[1].cgImage()) == Data([0x34]))
    }

    @Test func recognizesJPEGBaselineTransferSyntax() throws {
        let file = try DICOMFile(data: part10File(
            transferSyntaxUID: TransferSyntax.jpegBaseline.uid,
            datasetElements: []
        ))

        #expect(file.transferSyntax == .jpegBaseline)
    }

    @Test func rejectsSequenceItemTagThatIsNeitherItemNorDelimiter() {
        let data = part10File(
            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid,
            datasetElements: [
                element(
                    tag: .referencedStudySequence,
                    vr: .SQ,
                    value: uint16(DICOMTag.patientName.group) + uint16(DICOMTag.patientName.element) + uint32(0)
                )
            ]
        )

        #expect(throws: DICOMError.invalidSequenceItem(.patientName)) {
            _ = try DICOMFile(data: data)
        }
    }

    @Test func rejectsPixelDataShorterThanDeclaredDimensions() {
        let pixelData = DICOMPixelData(
            value: Data([0, 64]),
            rows: 2,
            columns: 2,
            samplesPerPixel: 1,
            bitsAllocated: 8,
            photometricInterpretation: .monochrome2,
            planarConfiguration: 0
        )

        #expect(throws: DICOMImageError.truncatedPixelData) {
            _ = try pixelData.cgImage()
        }
    }

    @Test func rejectsUnsupportedPhotometricInterpretation() {
        let pixelData = DICOMPixelData(
            value: Data([0, 1, 2, 3]),
            rows: 2,
            columns: 2,
            samplesPerPixel: 1,
            bitsAllocated: 8,
            photometricInterpretation: .other("YBR_FULL"),
            planarConfiguration: 0
        )

        #expect(throws: DICOMImageError.unsupportedPixelFormat) {
            _ = try pixelData.cgImage()
        }
    }

    @Test func rejectsRGBWithPlanarConfigurationOne() {
        let pixelData = DICOMPixelData(
            value: Data(repeating: 0, count: 6),
            rows: 1,
            columns: 2,
            samplesPerPixel: 3,
            bitsAllocated: 8,
            photometricInterpretation: .rgb,
            planarConfiguration: 1
        )

        #expect(throws: DICOMImageError.unsupportedPixelFormat) {
            _ = try pixelData.cgImage()
        }
    }

    @Test func rejectsWindowWidthOfOneOrLess() {
        let pixelData = DICOMPixelData(
            value: uint16(0),
            rows: 1,
            columns: 1,
            samplesPerPixel: 1,
            bitsAllocated: 16,
            photometricInterpretation: .monochrome2,
            planarConfiguration: 0
        )

        #expect(throws: DICOMImageError.invalidWindowWidth) {
            _ = try pixelData.cgImage(windowCenter: 500, windowWidth: 1)
        }
    }
}

private func part10File(transferSyntaxUID: String, datasetElements: [Data]) -> Data {
    var data = Data(repeating: 0, count: 128)
    data.append(contentsOf: "DICM".utf8)
    data.append(element(tag: DICOMTag(group: 0x0002, element: 0x0010), vr: .UI, value: transferSyntaxUID))
    for item in datasetElements { data.append(item) }
    return data
}

private func element(tag: DICOMTag, vr: DICOMVR, value: String) -> Data {
    var encoded = Data(value.utf8)
    if encoded.count.isMultiple(of: 2) == false { encoded.append(0) }
    return element(tag: tag, vr: vr, value: encoded)
}

/// The VRs that DICOM PS3.5 defines as using a 4-byte length field in
/// Explicit VR encoding. Hardcoded independently of `DICOMVR.uses32BitLength`
/// so that tests built with this helper actually exercise the production
/// switch statement rather than mirroring whatever it currently says.
private let explicitVR32BitLengthVRs: Set<DICOMVR> = [
    .OB, .OD, .OF, .OL, .OV, .OW, .SQ, .SV, .UC, .UN, .UR, .UT, .UV
]

private func element(tag: DICOMTag, vr: DICOMVR, value: Data) -> Data {
    var data = uint16(tag.group)
    data.append(uint16(tag.element))
    data.append(contentsOf: vr.rawValue.utf8)
    if explicitVR32BitLengthVRs.contains(vr) {
        data.append(uint16(0))
        data.append(uint32(UInt32(value.count)))
    } else {
        data.append(uint16(UInt16(value.count)))
    }
    data.append(value)
    return data
}

/// Builds a raw Explicit VR element with an attacker/fuzzer-controlled length
/// field that need not match `value.count`, so tests can exercise truncated
/// or undefined-length inputs precisely.
private func explicitVRElementWithDeclaredLength(tag: DICOMTag, vr: DICOMVR, length: UInt32, value: Data = Data()) -> Data {
    var data = uint16(tag.group)
    data.append(uint16(tag.element))
    data.append(contentsOf: vr.rawValue.utf8)
    if explicitVR32BitLengthVRs.contains(vr) {
        data.append(uint16(0))
        data.append(uint32(length))
    } else {
        data.append(uint16(UInt16(length)))
    }
    data.append(value)
    return data
}

/// Builds a raw Explicit VR element with a 2-byte VR code that need not be a
/// valid `DICOMVR` case, so tests can exercise `DICOMError.invalidVR`.
private func explicitVRElementWithInvalidVR(tag: DICOMTag, vrText: String, length: UInt16) -> Data {
    var data = uint16(tag.group)
    data.append(uint16(tag.element))
    data.append(contentsOf: vrText.utf8)
    data.append(uint16(length))
    return data
}

private func encapsulatedPixelData(basicOffsetTable: Data = Data(), fragments: [Data]) -> Data {
    var data = uint16(DICOMTag.pixelData.group)
    data.append(uint16(DICOMTag.pixelData.element))
    data.append(contentsOf: "OB".utf8)
    data.append(uint16(0))
    data.append(uint32(.max))

    // The first item is the Basic Offset Table. It may be empty for a
    // single-frame image.
    data.append(uint16(0xFFFE))
    data.append(uint16(0xE000))
    data.append(uint32(UInt32(basicOffsetTable.count)))
    data.append(basicOffsetTable)
    for fragment in fragments {
        var padded = fragment
        if !padded.count.isMultiple(of: 2) { padded.append(0) }
        data.append(uint16(0xFFFE))
        data.append(uint16(0xE000))
        data.append(uint32(UInt32(padded.count)))
        data.append(padded)
    }
    data.append(uint16(0xFFFE))
    data.append(uint16(0xE0DD))
    data.append(uint32(0))
    return data
}

private func rleFrame(segment: Data) -> Data {
    rleFrame(segments: [segment])
}

private func rleFrame(segments: [Data]) -> Data {
    var frame = uint32(UInt32(segments.count))
    var offset = 64
    for segment in segments {
        frame.append(uint32(UInt32(offset)))
        offset += segment.count
    }
    frame.append(Data(repeating: 0, count: 64 - frame.count))
    for segment in segments { frame.append(segment) }
    return frame
}

private func implicitElement(tag: DICOMTag, value: String) -> Data {
    var encoded = Data(value.utf8)
    if encoded.count.isMultiple(of: 2) == false { encoded.append(0) }
    return implicitElement(tag: tag, value: encoded)
}

private func implicitElement(tag: DICOMTag, value: Data) -> Data {
    var data = uint16(tag.group)
    data.append(uint16(tag.element))
    data.append(uint32(UInt32(value.count)))
    data.append(value)
    return data
}

private func implicitUndefinedLengthSequence(tag: DICOMTag, itemElements: [Data]) -> Data {
    var data = uint16(tag.group)
    data.append(uint16(tag.element))
    data.append(uint32(.max))
    data.append(uint16(0xFFFE))
    data.append(uint16(0xE000))
    let item = itemElements.reduce(into: Data()) { $0.append($1) }
    data.append(uint32(UInt32(item.count)))
    data.append(item)
    data.append(uint16(0xFFFE))
    data.append(uint16(0xE0DD))
    data.append(uint32(0))
    return data
}

private func implicitDefinedLengthSequence(tag: DICOMTag, itemElements: [Data]) -> Data {
    let item = itemElements.reduce(into: Data()) { $0.append($1) }
    var sequence = uint16(0xFFFE)
    sequence.append(uint16(0xE000))
    sequence.append(uint32(UInt32(item.count)))
    sequence.append(item)

    var data = uint16(tag.group)
    data.append(uint16(tag.element))
    data.append(uint32(UInt32(sequence.count)))
    data.append(sequence)
    return data
}

private func uint16(_ value: UInt16) -> Data {
    Data([UInt8(value & 0xFF), UInt8(value >> 8)])
}

private func uint32(_ value: UInt32) -> Data {
    Data([
        UInt8(value & 0xFF),
        UInt8((value >> 8) & 0xFF),
        UInt8((value >> 16) & 0xFF),
        UInt8((value >> 24) & 0xFF)
    ])
}

private func imageBytes(_ image: CGImage) throws -> Data {
    Data(try #require(image.dataProvider?.data) as Data)
}

private final class FixtureBundleToken: NSObject {}

private enum FixtureError: Error {
    case missing(String)
}

/// Resolves a test fixture from the test bundle instead of the source tree.
/// Xcode Cloud checks out and builds source in a different location, whereas
/// copied test resources are always available from this bundle.
private func fixtureURL() throws -> URL {
    #if SWIFT_PACKAGE
    let bundle = Bundle.module
    #else
    let bundle = Bundle(for: FixtureBundleToken.self)
    #endif
    // Xcode copies the synchronized test resource group directly into the
    // bundle root, while SwiftPM preserves the `Fixtures` directory. Support
    // both layouts so local SwiftPM, Xcode, and Xcode Cloud share this test.
    for subdirectory in [nil, "Fixtures"] {
        if let url = bundle.url(forResource: "CT_small", withExtension: "dcm", subdirectory: subdirectory) {
            return url
        }
    }
    throw FixtureError.missing("CT_small.dcm")
}

private func ctFixture() throws -> DICOMFile {
    try DICOMFile(data: Data(contentsOf: try fixtureURL()))
}
