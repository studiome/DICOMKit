import Foundation

/// Writes DICOM Part 10 files using supported Little Endian transfer syntaxes.
public enum DICOMWriter {
    /// The length representation used for sequence and item containers.
    public enum SequenceLengthEncoding: Sendable {
        /// Emit calculated element and item lengths.
        case defined
        /// Emit delimiters after undefined-length elements and items.
        case undefined
    }
    /// Serializes File Meta Information and a dataset into a Part 10 file.
    ///
    /// Supports native Explicit/Implicit VR Little Endian datasets and
    /// already-encapsulated Pixel Data for the supported compressed transfer
    /// syntaxes. Compression is supplied by the caller; this writer only
    /// serializes the fragments and their Basic Offset Table.
    public static func write(
        metaInformation: DICOMDataset = DICOMDataset(),
        dataset: DICOMDataset,
        transferSyntax: TransferSyntax = .explicitVRLittleEndian,
        requiredMetaInformation: DICOMFileMetaInformation? = nil,
        sequenceLengthEncoding: SequenceLengthEncoding = .defined
    ) throws -> Data {
        guard transferSyntax.isWritable else {
            throw DICOMError.unsupportedTransferSyntax(transferSyntax.uid)
        }

        var metaElements = Array(metaInformation).filter { $0.tag.group == 0x0002 && $0.tag != .transferSyntaxUID }
        if let requiredMetaInformation {
            metaElements.removeAll {
                $0.tag == .mediaStorageSOPClassUID || $0.tag == .mediaStorageSOPInstanceUID ||
                $0.tag == .implementationClassUID || $0.tag == .implementationVersionName
            }
            metaElements.append(DICOMElement(tag: .mediaStorageSOPClassUID, vr: .UI, value: Data(requiredMetaInformation.mediaStorageSOPClassUID.utf8)))
            metaElements.append(DICOMElement(tag: .mediaStorageSOPInstanceUID, vr: .UI, value: Data(requiredMetaInformation.mediaStorageSOPInstanceUID.utf8)))
            metaElements.append(DICOMElement(tag: .implementationClassUID, vr: .UI, value: Data(requiredMetaInformation.implementationClassUID.utf8)))
            if let implementationVersionName = requiredMetaInformation.implementationVersionName {
                metaElements.append(DICOMElement(tag: .implementationVersionName, vr: .SH, value: Data(implementationVersionName.utf8)))
            }
        }
        metaElements.removeAll { $0.tag == DICOMTag(group: 0x0002, element: 0x0000) || $0.tag == DICOMTag(group: 0x0002, element: 0x0001) }
        metaElements.append(DICOMElement(tag: DICOMTag(group: 0x0002, element: 0x0001), vr: .OB, value: Data([0, 1])))
        metaElements.append(DICOMElement(tag: .transferSyntaxUID, vr: .UI, value: Data(transferSyntax.uid.utf8)))
        var encodedMeta = Data()
        for element in metaElements.sorted(by: { $0.tag < $1.tag }) {
            try append(element, to: &encodedMeta, explicitVR: true, sequenceLengthEncoding: .defined)
        }
        var output = Data(repeating: 0, count: 128)
        output.append(contentsOf: "DICM".utf8)
        let metaLength = UInt32(encodedMeta.count)
        let groupLength = Data([
            UInt8(metaLength & 0xFF), UInt8((metaLength >> 8) & 0xFF),
            UInt8((metaLength >> 16) & 0xFF), UInt8((metaLength >> 24) & 0xFF)
        ])
        try append(
            DICOMElement(tag: DICOMTag(group: 0x0002, element: 0x0000), vr: .UL, value: groupLength),
            to: &output,
            explicitVR: true,
            sequenceLengthEncoding: .defined
        )
        output.append(encodedMeta)
        output.append(try encodeDataset(dataset, transferSyntax: transferSyntax, sequenceLengthEncoding: sequenceLengthEncoding))
        return output
    }

    /// Serializes a dataset alone, without a 128-byte preamble, `DICM` magic,
    /// or File Meta Information.
    ///
    /// This is the payload a DIMSE service such as C-STORE transfers — it is
    /// NOT a Part 10 file. Use ``write(metaInformation:dataset:transferSyntax:requiredMetaInformation:sequenceLengthEncoding:)``
    /// to produce a complete file.
    public static func encodeDataset(
        _ dataset: DICOMDataset,
        transferSyntax: TransferSyntax = .explicitVRLittleEndian,
        sequenceLengthEncoding: SequenceLengthEncoding = .defined
    ) throws -> Data {
        guard transferSyntax.isWritable else {
            throw DICOMError.unsupportedTransferSyntax(transferSyntax.uid)
        }
        var encodedDataset = Data()
        for element in dataset where element.tag.group != 0x0002 {
            if element.tag == .pixelData,
               transferSyntax.usesEncapsulatedPixelData,
               element.encapsulatedFragments == nil {
                throw DICOMError.invalidEncapsulatedPixelData
            }
            try append(element, to: &encodedDataset, explicitVR: transferSyntax != .implicitVRLittleEndian, sequenceLengthEncoding: sequenceLengthEncoding, byteOrder: transferSyntax == .explicitVRBigEndian ? .bigEndian : .littleEndian)
        }
        return transferSyntax == .deflatedExplicitVRLittleEndian ? try DeflateCodec.deflateRaw(encodedDataset) : encodedDataset
    }

    private static func append(_ element: DICOMElement, to output: inout Data, explicitVR: Bool, sequenceLengthEncoding: SequenceLengthEncoding, byteOrder: ByteOrder = .littleEndian) throws {
        if element.tag == .pixelData, let fragments = element.encapsulatedFragments {
            guard explicitVR, let basicOffsetTable = element.basicOffsetTable else { throw DICOMError.invalidEncapsulatedPixelData }
            appendUInt16(element.tag.group, to: &output, byteOrder: byteOrder)
            appendUInt16(element.tag.element, to: &output, byteOrder: byteOrder)
            output.append(contentsOf: element.vr.rawValue.utf8)
            output.append(contentsOf: [0, 0])
            appendUInt32(.max, to: &output, byteOrder: byteOrder)
            appendItem(basicOffsetTable, to: &output, byteOrder: byteOrder)
            for fragment in fragments { appendItem(fragment, to: &output, byteOrder: byteOrder) }
            appendItemTag(0xE0DD, to: &output, byteOrder: byteOrder)
            return
        }
        appendUInt16(element.tag.group, to: &output, byteOrder: byteOrder)
        appendUInt16(element.tag.element, to: &output, byteOrder: byteOrder)
        let value: Data
        if element.vr == .SQ {
            value = try encodedSequence(element.sequenceItems ?? [], explicitVR: explicitVR, sequenceLengthEncoding: sequenceLengthEncoding, byteOrder: byteOrder)
        } else {
            value = paddedValue(byteOrder == .bigEndian ? bigEndianValue(element.value, vr: element.vr) : element.value, vr: element.vr)
        }
        if element.vr == .SQ, sequenceLengthEncoding == .undefined {
            if explicitVR { output.append(contentsOf: element.vr.rawValue.utf8); output.append(contentsOf: [0, 0]) }
            appendUInt32(.max, to: &output, byteOrder: byteOrder)
        } else if !explicitVR {
            appendUInt32(UInt32(value.count), to: &output, byteOrder: byteOrder)
        } else if element.vr.uses32BitLength {
            output.append(contentsOf: element.vr.rawValue.utf8)
            output.append(contentsOf: [0, 0])
            appendUInt32(UInt32(value.count), to: &output, byteOrder: byteOrder)
        } else {
            output.append(contentsOf: element.vr.rawValue.utf8)
            guard value.count <= Int(UInt16.max) else { throw DICOMError.truncatedData }
            appendUInt16(UInt16(value.count), to: &output, byteOrder: byteOrder)
        }
        output.append(value)
        if element.vr == .SQ, sequenceLengthEncoding == .undefined { appendItemTag(0xE0DD, to: &output, byteOrder: byteOrder) }
    }

    private static func encodedSequence(_ items: [DICOMDataset], explicitVR: Bool, sequenceLengthEncoding: SequenceLengthEncoding, byteOrder: ByteOrder) throws -> Data {
        var output = Data()
        for item in items {
            var encodedItem = Data()
            for element in item { try append(element, to: &encodedItem, explicitVR: explicitVR, sequenceLengthEncoding: sequenceLengthEncoding, byteOrder: byteOrder) }
            appendUInt16(0xFFFE, to: &output, byteOrder: byteOrder)
            appendUInt16(0xE000, to: &output, byteOrder: byteOrder)
            appendUInt32(sequenceLengthEncoding == .undefined ? .max : UInt32(encodedItem.count), to: &output, byteOrder: byteOrder)
            output.append(encodedItem)
            if sequenceLengthEncoding == .undefined { appendItemTag(0xE00D, to: &output, byteOrder: byteOrder) }
        }
        return output
    }

    private static func paddedValue(_ value: Data, vr: DICOMVR) -> Data {
        guard !value.count.isMultiple(of: 2) else { return value }
        var padded = value
        padded.append(vr == .UI ? 0 : (vr.uses32BitLength ? 0 : 0x20))
        return padded
    }

    private static func appendUInt16(_ value: UInt16, to data: inout Data, byteOrder: ByteOrder = .littleEndian) {
        switch byteOrder {
        case .littleEndian: data.append(UInt8(value & 0xFF)); data.append(UInt8(value >> 8))
        case .bigEndian: data.append(UInt8(value >> 8)); data.append(UInt8(value & 0xFF))
        }
    }
    private static func appendUInt32(_ value: UInt32, to data: inout Data, byteOrder: ByteOrder = .littleEndian) {
        switch byteOrder {
        case .littleEndian: data.append(UInt8(value & 0xFF)); data.append(UInt8((value >> 8) & 0xFF)); data.append(UInt8((value >> 16) & 0xFF)); data.append(UInt8(value >> 24))
        case .bigEndian: data.append(UInt8(value >> 24)); data.append(UInt8((value >> 16) & 0xFF)); data.append(UInt8((value >> 8) & 0xFF)); data.append(UInt8(value & 0xFF))
        }
    }
    private static func appendItemTag(_ element: UInt16, to data: inout Data, byteOrder: ByteOrder = .littleEndian) {
        appendUInt16(0xFFFE, to: &data, byteOrder: byteOrder); appendUInt16(element, to: &data, byteOrder: byteOrder); appendUInt32(0, to: &data, byteOrder: byteOrder)
    }

    private static func appendItem(_ value: Data, to data: inout Data, byteOrder: ByteOrder = .littleEndian) {
        let padded = paddedValue(value, vr: .OB)
        appendUInt16(0xFFFE, to: &data, byteOrder: byteOrder); appendUInt16(0xE000, to: &data, byteOrder: byteOrder)
        appendUInt32(UInt32(padded.count), to: &data, byteOrder: byteOrder)
        data.append(padded)
    }

    private static func bigEndianValue(_ value: Data, vr: DICOMVR) -> Data {
        let width: Int
        switch vr {
        case .US, .SS, .OW, .AT: width = 2
        case .UL, .SL, .FL, .OL, .OF: width = 4
        case .UV, .SV, .FD, .OD, .OV: width = 8
        default: return value
        }
        guard value.count.isMultiple(of: width) else { return value }
        var output = Data()
        output.reserveCapacity(value.count)
        for offset in stride(from: 0, to: value.count, by: width) {
            output.append(contentsOf: value[offset..<(offset + width)].reversed())
        }
        return output
    }
}
