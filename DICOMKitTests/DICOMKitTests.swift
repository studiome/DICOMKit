import Foundation
import CoreGraphics
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
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/CT_small.dcm")

        let file = try DICOMFile(data: Data(contentsOf: fixtureURL))

        #expect(file.transferSyntax == .explicitVRLittleEndian)
        #expect(file.dataset[.rows]?.uint16Value == 128)
        #expect(file.dataset[.columns]?.uint16Value == 128)
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
            photometricInterpretation: photometricInterpretation,
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
            photometricInterpretation: photometricInterpretation,
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

    @Test func rejectsUndefinedLengthOnNonSequenceExplicitVRElement() {
        // An OB Pixel Data element with an undefined length is how encapsulated
        // (compressed) Pixel Data is signalled; this reader doesn't support it.
        let data = part10File(
            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid,
            datasetElements: [
                explicitVRElementWithDeclaredLength(tag: .pixelData, vr: .OB, length: .max)
            ]
        )

        #expect(throws: DICOMError.unsupportedUndefinedLength(.pixelData)) {
            _ = try DICOMFile(data: data)
        }
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
            photometricInterpretation: "MONOCHROME2",
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
            photometricInterpretation: "YBR_FULL",
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
            photometricInterpretation: "RGB",
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
            photometricInterpretation: "MONOCHROME2",
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
