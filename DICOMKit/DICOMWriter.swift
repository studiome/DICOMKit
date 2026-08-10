import Foundation

/// Writes uncompressed DICOM Part 10 files using Little Endian transfer syntaxes.
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
    /// The v0.4 writer supports Explicit and Implicit VR Little Endian datasets, including
    /// recursively defined-length sequences and native Pixel Data.
    public static func write(
        metaInformation: DICOMDataset = DICOMDataset(),
        dataset: DICOMDataset,
        transferSyntax: TransferSyntax = .explicitVRLittleEndian,
        sequenceLengthEncoding: SequenceLengthEncoding = .defined
    ) throws -> Data {
        guard transferSyntax == .explicitVRLittleEndian || transferSyntax == .implicitVRLittleEndian else {
            throw DICOMError.unsupportedTransferSyntax(transferSyntax.uid)
        }

        var output = Data(repeating: 0, count: 128)
        output.append(contentsOf: "DICM".utf8)

        var metaElements = Array(metaInformation).filter { $0.tag.group == 0x0002 && $0.tag != .transferSyntaxUID }
        metaElements.append(DICOMElement(tag: .transferSyntaxUID, vr: .UI, value: Data(transferSyntax.uid.utf8)))
        for element in metaElements.sorted(by: { $0.tag < $1.tag }) {
            try append(element, to: &output, explicitVR: true, sequenceLengthEncoding: .defined)
        }
        for element in dataset where element.tag.group != 0x0002 {
            try append(element, to: &output, explicitVR: transferSyntax == .explicitVRLittleEndian, sequenceLengthEncoding: sequenceLengthEncoding)
        }
        return output
    }

    private static func append(_ element: DICOMElement, to output: inout Data, explicitVR: Bool, sequenceLengthEncoding: SequenceLengthEncoding) throws {
        appendUInt16(element.tag.group, to: &output)
        appendUInt16(element.tag.element, to: &output)
        let value: Data
        if element.vr == .SQ {
            value = try encodedSequence(element.sequenceItems ?? [], explicitVR: explicitVR, sequenceLengthEncoding: sequenceLengthEncoding)
        } else {
            value = paddedValue(element.value, vr: element.vr)
        }
        if element.vr == .SQ, sequenceLengthEncoding == .undefined {
            if explicitVR { output.append(contentsOf: element.vr.rawValue.utf8); output.append(contentsOf: [0, 0]) }
            appendUInt32(.max, to: &output)
        } else if !explicitVR {
            appendUInt32(UInt32(value.count), to: &output)
        } else if element.vr.uses32BitLength {
            output.append(contentsOf: element.vr.rawValue.utf8)
            output.append(contentsOf: [0, 0])
            appendUInt32(UInt32(value.count), to: &output)
        } else {
            output.append(contentsOf: element.vr.rawValue.utf8)
            guard value.count <= Int(UInt16.max) else { throw DICOMError.truncatedData }
            appendUInt16(UInt16(value.count), to: &output)
        }
        output.append(value)
        if element.vr == .SQ, sequenceLengthEncoding == .undefined { appendItemTag(0xE0DD, to: &output) }
    }

    private static func encodedSequence(_ items: [DICOMDataset], explicitVR: Bool, sequenceLengthEncoding: SequenceLengthEncoding) throws -> Data {
        var output = Data()
        for item in items {
            var encodedItem = Data()
            for element in item { try append(element, to: &encodedItem, explicitVR: explicitVR, sequenceLengthEncoding: sequenceLengthEncoding) }
            appendUInt16(0xFFFE, to: &output)
            appendUInt16(0xE000, to: &output)
            appendUInt32(sequenceLengthEncoding == .undefined ? .max : UInt32(encodedItem.count), to: &output)
            output.append(encodedItem)
            if sequenceLengthEncoding == .undefined { appendItemTag(0xE00D, to: &output) }
        }
        return output
    }

    private static func paddedValue(_ value: Data, vr: DICOMVR) -> Data {
        guard !value.count.isMultiple(of: 2) else { return value }
        var padded = value
        padded.append(vr == .UI ? 0 : (vr.uses32BitLength ? 0 : 0x20))
        return padded
    }

    private static func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0xFF)); data.append(UInt8(value >> 8))
    }
    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0xFF)); data.append(UInt8((value >> 8) & 0xFF)); data.append(UInt8((value >> 16) & 0xFF)); data.append(UInt8(value >> 24))
    }
    private static func appendItemTag(_ element: UInt16, to data: inout Data) {
        appendUInt16(0xFFFE, to: &data); appendUInt16(element, to: &data); appendUInt32(0, to: &data)
    }
}
