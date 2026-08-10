import Foundation

/// A cursor-based decoder for DICOM Part 10 datasets.
///
/// Not `public`: `DICOMFile` is the library's only entry point for parsing,
/// so this stays an implementation detail shared internally with
/// ``DICOMDictionary``.
struct Reader {
    let data: Data
    var offset: Int

    mutating func readDataset(transferSyntax: TransferSyntax, endingAt endOffset: Int? = nil) throws -> [DICOMElement] {
        var elements: [DICOMElement] = []
        while true {
            if let endOffset {
                guard offset <= endOffset else { throw DICOMError.truncatedData }
                if offset == endOffset { return elements }
            }
            guard offset < data.count else {
                guard endOffset == nil else { throw DICOMError.truncatedData }
                return elements
            }
            elements.append(try readElement(transferSyntax: transferSyntax))
        }
    }

    mutating func readElement(transferSyntax: TransferSyntax) throws -> DICOMElement {
        let tag = try readTag()
        let vr: DICOMVR
        let length: UInt32

        switch transferSyntax {
        case .explicitVRLittleEndian:
            let vrText = String(bytes: try readData(count: 2), encoding: .ascii) ?? ""
            guard let parsedVR = DICOMVR(rawValue: vrText) else { throw DICOMError.invalidVR(vrText) }
            vr = parsedVR
            if vr.uses32BitLength {
                _ = try readUInt16()
                length = try readUInt32()
            } else {
                length = UInt32(try readUInt16())
            }
        case .implicitVRLittleEndian:
            // Read the length before resolving the VR: when a tag isn't in
            // DICOMDictionary and its length is undefined (0xFFFFFFFF), the
            // Implicit VR convention is to treat it as a sequence (SQ) rather
            // than as unknown (UN), since UN elements cannot have undefined
            // length under this reader (see `unsupportedUndefinedLength`).
            // This lets sequences outside the small built-in dictionary
            // (e.g. Referenced Image Sequence) still be parsed.
            length = try readUInt32()
            vr = DICOMDictionary.vr(for: tag) ?? (length == .max ? .SQ : .UN)
        default:
            throw DICOMError.unsupportedTransferSyntax(transferSyntax.uid)
        }

        if vr == .SQ {
            return DICOMElement(tag: tag, vr: vr, value: Data(), sequenceItems: try readSequence(transferSyntax: transferSyntax, length: length))
        }
        guard length != .max else { throw DICOMError.unsupportedUndefinedLength(tag) }
        return DICOMElement(tag: tag, vr: vr, value: try readData(count: Int(length)))
    }

    mutating func readSequence(transferSyntax: TransferSyntax, length: UInt32) throws -> [DICOMDataset] {
        let endOffset: Int?
        if length == .max {
            endOffset = nil
        } else {
            let candidate = offset + Int(length)
            guard candidate <= data.count else { throw DICOMError.truncatedData }
            endOffset = candidate
        }

        var items: [DICOMDataset] = []
        while offset < data.count {
            if let endOffset, offset == endOffset { return items }
            let itemTag = try readTag()
            let itemLength = try readUInt32()
            if itemTag == DICOMTag(group: 0xFFFE, element: 0xE0DD) {
                guard endOffset == nil, itemLength == 0 else { throw DICOMError.invalidSequenceItem(itemTag) }
                return items
            }
            guard itemTag == DICOMTag(group: 0xFFFE, element: 0xE000) else {
                throw DICOMError.invalidSequenceItem(itemTag)
            }

            let itemElements: [DICOMElement]
            if itemLength == .max {
                itemElements = try readUndefinedLengthItem(transferSyntax: transferSyntax)
            } else {
                let itemEndOffset = offset + Int(itemLength)
                guard itemEndOffset <= data.count else { throw DICOMError.truncatedData }
                itemElements = try readDataset(transferSyntax: transferSyntax, endingAt: itemEndOffset)
            }
            items.append(DICOMDataset(elements: itemElements))
        }
        if let endOffset, offset == endOffset { return items }
        throw DICOMError.truncatedData
    }

    mutating func readUndefinedLengthItem(transferSyntax: TransferSyntax) throws -> [DICOMElement] {
        var elements: [DICOMElement] = []
        while offset < data.count {
            if peekTag() == DICOMTag(group: 0xFFFE, element: 0xE00D) {
                _ = try readTag()
                guard try readUInt32() == 0 else { throw DICOMError.truncatedData }
                return elements
            }
            elements.append(try readElement(transferSyntax: transferSyntax))
        }
        throw DICOMError.truncatedData
    }

    func peekTag() -> DICOMTag? {
        guard offset + 4 <= data.count else { return nil }
        return DICOMTag(
            group: data.littleEndian(at: offset),
            element: data.littleEndian(at: offset + 2)
        )
    }

    mutating func readTag() throws -> DICOMTag {
        DICOMTag(group: try readUInt16(), element: try readUInt16())
    }

    mutating func readUInt16() throws -> UInt16 {
        try readData(count: 2).littleEndian(at: 0)
    }

    mutating func readUInt32() throws -> UInt32 {
        try readData(count: 4).littleEndian(at: 0)
    }

    mutating func readData(count: Int) throws -> Data {
        guard count >= 0, count <= data.count - offset else { throw DICOMError.truncatedData }
        defer { offset += count }
        return data.subdata(in: offset..<(offset + count))
    }
}
