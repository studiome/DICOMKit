import DICOMKit
import Foundation

extension DICOMWriter {
    /// Serializes File Meta Information and a dataset into a Part 10 file.
    ///
    /// Supports native Explicit/Implicit VR Little Endian datasets and
    /// already-encapsulated Pixel Data for the supported compressed transfer
    /// syntaxes. Compression is supplied by the caller; this writer only
    /// serializes the fragments and their Basic Offset Table.
    ///
    /// This is the Part 10 file-assembly half of ``DICOMWriter``, split out
    /// into `DICOMKitAuthoring` from the dataset-serialization half
    /// (``encodeDataset(_:transferSyntax:sequenceLengthEncoding:)``), which
    /// stays in `DICOMKit` because DIMSE services such as C-STORE need it
    /// without pulling in the rest of authoring.
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
}
