import Foundation
@testable import DICOMKit

// Byte-level builders that assemble DICOM streams by hand, so tests can feed
// the reader exactly the bytes they mean to — including malformed ones the
// library itself would never write.

// MARK: - Primitives

/// Little-endian encoding of a 16-bit value.
func uint16(_ value: UInt16) -> Data {
    Data([UInt8(value & 0xFF), UInt8(value >> 8)])
}

/// Little-endian encoding of a 32-bit value.
func uint32(_ value: UInt32) -> Data {
    Data([
        UInt8(value & 0xFF),
        UInt8((value >> 8) & 0xFF),
        UInt8((value >> 16) & 0xFF),
        UInt8((value >> 24) & 0xFF)
    ])
}

private func tagBytes(_ tag: DICOMTag) -> Data {
    uint16(tag.group) + uint16(tag.element)
}

/// Encodes a string value with the DICOM even-length padding byte.
private func paddedValue(_ value: String) -> Data {
    var encoded = Data(value.utf8)
    if encoded.count.isMultiple(of: 2) == false { encoded.append(0) }
    return encoded
}

private let itemTag = DICOMTag(group: 0xFFFE, element: 0xE000)
private let sequenceDelimitationItemTag = DICOMTag(group: 0xFFFE, element: 0xE0DD)
private let undefinedLength = UInt32.max

/// A sequence or encapsulation item: `(FFFE,E000)`, its length, and its payload.
private func item(_ payload: Data) -> Data {
    tagBytes(itemTag) + uint32(UInt32(payload.count)) + payload
}

/// The `(FFFE,E0DD)` marker that closes an undefined-length sequence.
private var sequenceDelimitationItem: Data {
    tagBytes(sequenceDelimitationItemTag) + uint32(0)
}

// MARK: - Part 10

/// Wraps dataset elements in a Part 10 file: a 128-byte preamble, the `DICM`
/// magic, and a File Meta Information group holding only Transfer Syntax UID.
func part10File(transferSyntaxUID: String, datasetElements: [Data]) -> Data {
    var data = Data(repeating: 0, count: 128)
    data.append(contentsOf: "DICM".utf8)
    data.append(element(tag: DICOMTag(group: 0x0002, element: 0x0010), vr: .UI, value: transferSyntaxUID))
    for item in datasetElements { data.append(item) }
    return data
}

/// Builds a Part 10 file whose dataset describes a single image, storing
/// `pixelData` natively with the VR that matches `bitsAllocated`.
func imageFile(
    transferSyntaxUID: String = TransferSyntax.explicitVRLittleEndian.uid,
    samplesPerPixel: UInt16 = 1,
    photometricInterpretation: PhotometricInterpretation = .monochrome2,
    planarConfiguration: UInt16? = nil,
    numberOfFrames: Int? = nil,
    rows: UInt16,
    columns: UInt16,
    bitsAllocated: UInt16,
    windowCenter: String? = nil,
    windowWidth: String? = nil,
    pixelData: Data
) -> Data {
    imageFile(
        transferSyntaxUID: transferSyntaxUID,
        samplesPerPixel: samplesPerPixel,
        photometricInterpretation: photometricInterpretation,
        planarConfiguration: planarConfiguration,
        numberOfFrames: numberOfFrames,
        rows: rows,
        columns: columns,
        bitsAllocated: bitsAllocated,
        windowCenter: windowCenter,
        windowWidth: windowWidth,
        pixelDataElement: element(tag: .pixelData, vr: bitsAllocated > 8 ? .OW : .OB, value: pixelData)
    )
}

/// Builds a Part 10 file whose dataset describes a single image, writing only
/// the attributes the rendering path reads, in ascending tag order.
///
/// `pixelDataElement` is a fully encoded `(7FE0,0010)` element, so callers can
/// supply an encapsulated stream via
/// ``encapsulatedPixelData(basicOffsetTable:fragments:)``.
func imageFile(
    transferSyntaxUID: String = TransferSyntax.explicitVRLittleEndian.uid,
    samplesPerPixel: UInt16 = 1,
    photometricInterpretation: PhotometricInterpretation = .monochrome2,
    planarConfiguration: UInt16? = nil,
    numberOfFrames: Int? = nil,
    rows: UInt16,
    columns: UInt16,
    bitsAllocated: UInt16,
    windowCenter: String? = nil,
    windowWidth: String? = nil,
    pixelDataElement: Data
) -> Data {
    var elements = [
        element(tag: .samplesPerPixel, vr: .US, value: uint16(samplesPerPixel)),
        element(tag: .photometricInterpretation, vr: .CS, value: photometricInterpretation.name)
    ]
    if let numberOfFrames {
        elements.append(element(tag: .numberOfFrames, vr: .IS, value: String(numberOfFrames)))
    }
    if let planarConfiguration {
        elements.append(element(tag: .planarConfiguration, vr: .US, value: uint16(planarConfiguration)))
    }
    elements.append(element(tag: .rows, vr: .US, value: uint16(rows)))
    elements.append(element(tag: .columns, vr: .US, value: uint16(columns)))
    elements.append(element(tag: .bitsAllocated, vr: .US, value: uint16(bitsAllocated)))
    if let windowCenter {
        elements.append(element(tag: .windowCenter, vr: .DS, value: windowCenter))
    }
    if let windowWidth {
        elements.append(element(tag: .windowWidth, vr: .DS, value: windowWidth))
    }
    elements.append(pixelDataElement)

    return part10File(transferSyntaxUID: transferSyntaxUID, datasetElements: elements)
}

// MARK: - Explicit VR elements

func element(tag: DICOMTag, vr: DICOMVR, value: String) -> Data {
    element(tag: tag, vr: vr, value: paddedValue(value))
}

func element(tag: DICOMTag, vr: DICOMVR, value: Data) -> Data {
    explicitVRElement(tag: tag, vr: vr, declaredLength: UInt32(value.count), value: value)
}

/// The VRs that DICOM PS3.5 defines as using a 4-byte length field in
/// Explicit VR encoding. Hardcoded independently of `DICOMVR.uses32BitLength`
/// so that tests built with these helpers actually exercise the production
/// switch statement rather than mirroring whatever it currently says.
let explicitVR32BitLengthVRs: Set<DICOMVR> = [
    .OB, .OD, .OF, .OL, .OV, .OW, .SQ, .SV, .UC, .UN, .UR, .UT, .UV
]

/// Builds a raw Explicit VR element with an attacker/fuzzer-controlled length
/// field that need not match `value.count`, so tests can exercise truncated
/// or undefined-length inputs precisely.
func explicitVRElement(tag: DICOMTag, vr: DICOMVR, declaredLength: UInt32, value: Data = Data()) -> Data {
    var data = tagBytes(tag)
    data.append(contentsOf: vr.rawValue.utf8)
    if explicitVR32BitLengthVRs.contains(vr) {
        data.append(uint16(0))
        data.append(uint32(declaredLength))
    } else {
        data.append(uint16(UInt16(declaredLength)))
    }
    data.append(value)
    return data
}

/// Builds a raw Explicit VR element with a 2-byte VR code that need not be a
/// valid `DICOMVR` case, so tests can exercise `DICOMError.invalidVR`.
func explicitVRElementWithInvalidVR(tag: DICOMTag, vrText: String, length: UInt16) -> Data {
    var data = tagBytes(tag)
    data.append(contentsOf: vrText.utf8)
    data.append(uint16(length))
    return data
}

// MARK: - Implicit VR elements

func implicitElement(tag: DICOMTag, value: String) -> Data {
    implicitElement(tag: tag, value: paddedValue(value))
}

func implicitElement(tag: DICOMTag, value: Data) -> Data {
    tagBytes(tag) + uint32(UInt32(value.count)) + value
}

/// An Implicit VR sequence of undefined length, holding a single item and
/// closed by a Sequence Delimitation Item.
func implicitUndefinedLengthSequence(tag: DICOMTag, itemElements: [Data]) -> Data {
    var data = tagBytes(tag)
    data.append(uint32(undefinedLength))
    data.append(item(itemElements.joinedBytes))
    data.append(sequenceDelimitationItem)
    return data
}

/// An Implicit VR sequence whose length is declared up front, holding a
/// single item.
func implicitDefinedLengthSequence(tag: DICOMTag, itemElements: [Data]) -> Data {
    implicitElement(tag: tag, value: item(itemElements.joinedBytes))
}

// MARK: - Encapsulated pixel data

/// An encapsulated `(7FE0,0010)` element: an undefined-length `OB` element
/// holding a Basic Offset Table item, one item per fragment, and a Sequence
/// Delimitation Item.
func encapsulatedPixelData(basicOffsetTable: Data = Data(), fragments: [Data]) -> Data {
    var data = tagBytes(.pixelData)
    data.append(contentsOf: "OB".utf8)
    data.append(uint16(0))
    data.append(uint32(undefinedLength))

    // The first item is the Basic Offset Table. It may be empty for a
    // single-frame image.
    data.append(item(basicOffsetTable))
    for fragment in fragments {
        var padded = fragment
        if !padded.count.isMultiple(of: 2) { padded.append(0) }
        data.append(item(padded))
    }
    data.append(sequenceDelimitationItem)
    return data
}

/// An RLE frame carrying a single segment.
func rleFrame(segment: Data) -> Data {
    rleFrame(segments: [segment])
}

/// An RLE frame: a 64-byte header of segment count and offsets, followed by
/// the segments themselves.
func rleFrame(segments: [Data]) -> Data {
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

private extension [Data] {
    var joinedBytes: Data {
        reduce(into: Data()) { $0.append($1) }
    }
}
