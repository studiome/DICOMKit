import Foundation

/// A cursor-based decoder for DICOM Part 10 datasets.
///
/// Not `public`: `DICOMFile` is the library's only entry point for parsing,
/// so this stays an implementation detail shared internally with
/// ``DICOMDictionary``.
struct Reader {
    let data: Data
    var offset: Int
    /// Controls how ambiguous VRs (`UN`, private tags) are resolved while
    /// reading. Set by the caller (``DICOMFile``, ``DICOMMetadataFile``)
    /// right after constructing the reader.
    var options: DICOMReadOptions = .default
    /// When enabled, native Pixel Data is skipped rather than copied and its
    /// source range is retained for an offset-based reader.
    var skipsNativePixelData = false
    var skippedNativePixelDataRange: Range<Int>?
    var skipsEncapsulatedPixelData = false
    var skippedEncapsulatedFragmentRanges: [Range<Int>]?
    var skippedBasicOffsetTable: Data?

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
        let byteOrder: ByteOrder = transferSyntax == .explicitVRBigEndian ? .bigEndian : .littleEndian
        let tag = try readTag(byteOrder: byteOrder)
        var vr: DICOMVR
        let length: UInt32
        let isExplicitVRWireFormat: Bool

        // Listed exhaustively rather than with a `default`, so that adding a
        // transfer syntax has to state which encoding its datasets use
        // instead of silently inheriting one. Every encapsulated syntax
        // encodes its elements as Explicit VR Little Endian.
        switch transferSyntax {
        case .explicitVRLittleEndian, .explicitVRBigEndian, .deflatedExplicitVRLittleEndian, .rleLossless, .jpegBaseline,
             .jpegLossless, .jpegLosslessSV1, .jpegLSLossless,
             .jpegLSNearLossless, .jpeg2000Lossless, .jpeg2000:
            isExplicitVRWireFormat = true
            let vrText = String(bytes: try readData(count: 2), encoding: .ascii) ?? ""
            guard let parsedVR = DICOMVR(rawValue: vrText) else { throw DICOMError.invalidVR(vrText) }
            vr = parsedVR
            if vr.uses32BitLength {
                // These 2 reserved bytes are defined as 0 by DICOM PS3.5,
                // but some real-world writers don't zero them; rejecting
                // non-zero reserved bytes would needlessly break
                // compatibility with such files, so they're discarded
                // without validation.
                _ = try readUInt16(byteOrder: byteOrder)
                length = try readUInt32(byteOrder: byteOrder)
            } else {
                length = UInt32(try readUInt16(byteOrder: byteOrder))
            }
        case .implicitVRLittleEndian:
            isExplicitVRWireFormat = false
            // Read the length before resolving the VR: when a tag isn't in
            // DICOMDictionary and its length is undefined (0xFFFFFFFF), the
            // Implicit VR convention is to treat it as a sequence (SQ) rather
            // than as unknown (UN). This lets sequences outside the small
            // built-in dictionary still be parsed.
            // This lets sequences outside the small built-in dictionary
            // (e.g. Referenced Image Sequence) still be parsed.
            length = try readUInt32(byteOrder: .littleEndian)
            vr = DICOMDictionary.vr(for: tag) ?? (length == .max ? .SQ : .UN)
        case .unknown:
            throw DICOMError.unsupportedTransferSyntax(transferSyntax.uid)
        }

        // PS3.5 6.2.2: data that passed through middleware which converted
        // Implicit VR to Explicit VR without a dictionary of its own
        // typically leaves every attribute it didn't recognize tagged `UN`,
        // even though the attribute has a well-defined VR. Re-derive it from
        // DICOMDictionary so typed accessors work on it.
        //
        // This is restricted to little-endian byte order (every wire format
        // here except Explicit VR Big Endian): a `UN` value's bytes are
        // always encoded little-endian by convention, even inside an
        // Explicit VR Big Endian dataset, so re-tagging a `UN` element read
        // under a big-endian reader would make numeric accessors interpret
        // its bytes with the wrong byte order.
        if isExplicitVRWireFormat, byteOrder == .littleEndian, vr == .UN, length != .max, options.reinterpretsUnknownVR,
           let dictVR = reinterpretedVR(for: tag) {
            if dictVR == .SQ {
                // The dictionary says this defined-length `UN` element is
                // actually a sequence. PS3.5 doesn't define how such a
                // sequence's *items* are encoded, but in practice this VR
                // loss happens when something converted Implicit VR data to
                // Explicit VR without a dictionary: it copied the item bytes
                // through unchanged, so they remain Implicit VR Little
                // Endian regardless of the enclosing dataset's transfer
                // syntax. Reuse `readSequence` with that transfer syntax
                // rather than writing a second sequence reader.
                if let sequence = parseUnknownSequence(length: length) {
                    return DICOMElement(tag: tag, vr: .SQ, value: Data(), sequenceItems: sequence.items, sequenceItemOffsets: sequence.itemOffsets)
                }
                // If the bytes don't actually parse as a well-formed
                // Implicit VR sequence, fall back to keeping the element
                // `UN` with its original bytes rather than propagating the
                // parse error: a single unparseable nested sequence
                // shouldn't prevent the rest of the dataset from opening.
            } else {
                vr = dictVR
            }
        }

        if vr == .SQ || (vr == .UN && length == .max) {
            let sequence = try readSequence(transferSyntax: transferSyntax, length: length)
            return DICOMElement(tag: tag, vr: vr, value: Data(), sequenceItems: sequence.items, sequenceItemOffsets: sequence.itemOffsets)
        }
        if tag == .pixelData, length == .max {
            if skipsEncapsulatedPixelData {
                try skipEncapsulatedPixelData(byteOrder: byteOrder)
                return DICOMElement(tag: tag, vr: vr, value: Data())
            }
            let encapsulated = try readEncapsulatedPixelData(byteOrder: byteOrder)
            return DICOMElement(
                tag: tag,
                vr: vr,
                value: Data(),
                encapsulatedFragments: encapsulated.fragments,
                encapsulatedFragmentOffsets: encapsulated.fragmentOffsets,
                basicOffsetTable: encapsulated.basicOffsetTable
            )
        }
        guard length != .max else { throw DICOMError.unsupportedUndefinedLength(tag) }
        if skipsNativePixelData, tag == .pixelData {
            let valueStart = offset
            guard Int(length) <= data.count - offset else { throw DICOMError.truncatedData }
            offset += Int(length)
            skippedNativePixelDataRange = valueStart..<offset
            return DICOMElement(tag: tag, vr: vr, value: Data())
        }
        let value = try readData(count: Int(length))
        return DICOMElement(tag: tag, vr: vr, value: byteOrder == .bigEndian ? canonicalLittleEndian(value, vr: vr) : value)
    }

    mutating func skipEncapsulatedPixelData(byteOrder: ByteOrder) throws {
        var isBasicOffsetTable = true
        var basicOffsetTable: Data?
        var ranges: [Range<Int>] = []
        while offset < data.count {
            let itemTag = try readTag(byteOrder: byteOrder)
            let itemLength = try readUInt32(byteOrder: byteOrder)
            if itemTag == DICOMTag(group: 0xFFFE, element: 0xE0DD) {
                guard itemLength == 0, !isBasicOffsetTable, let basicOffsetTable else { throw DICOMError.invalidEncapsulatedPixelData }
                skippedBasicOffsetTable = basicOffsetTable
                skippedEncapsulatedFragmentRanges = ranges
                return
            }
            guard itemTag == DICOMTag(group: 0xFFFE, element: 0xE000), itemLength != .max, Int(itemLength) <= data.count - offset else { throw DICOMError.invalidEncapsulatedPixelData }
            let range = offset..<(offset + Int(itemLength))
            if isBasicOffsetTable {
                basicOffsetTable = try readData(count: Int(itemLength))
                isBasicOffsetTable = false
            } else {
                ranges.append(range)
                offset = range.upperBound
            }
        }
        throw DICOMError.truncatedData
    }

    /// Reads the item sequence used by compressed Pixel Data. The first item
    /// is the Basic Offset Table and isn't returned with the frame fragments.
    mutating func readEncapsulatedPixelData(byteOrder: ByteOrder) throws -> (basicOffsetTable: Data, fragments: [Data], fragmentOffsets: [Int]) {
        var fragments: [Data] = []
        var fragmentOffsets: [Int] = []
        var basicOffsetTable: Data?
        var firstFragmentItemOffset: Int?
        var isBasicOffsetTable = true
        while offset < data.count {
            let itemOffset = offset
            let itemTag = try readTag(byteOrder: byteOrder)
            let itemLength = try readUInt32(byteOrder: byteOrder)
            if itemTag == DICOMTag(group: 0xFFFE, element: 0xE0DD) {
                guard itemLength == 0, !isBasicOffsetTable, let basicOffsetTable, !fragments.isEmpty else { throw DICOMError.invalidEncapsulatedPixelData }
                return (basicOffsetTable, fragments, fragmentOffsets)
            }
            guard itemTag == DICOMTag(group: 0xFFFE, element: 0xE000), itemLength != .max else {
                throw DICOMError.invalidEncapsulatedPixelData
            }
            let item = try readData(count: Int(itemLength))
            if isBasicOffsetTable {
                isBasicOffsetTable = false
                basicOffsetTable = item
            } else {
                if firstFragmentItemOffset == nil { firstFragmentItemOffset = itemOffset }
                guard let firstFragmentItemOffset else { throw DICOMError.invalidEncapsulatedPixelData }
                fragments.append(item)
                fragmentOffsets.append(itemOffset - firstFragmentItemOffset)
            }
        }
        throw DICOMError.truncatedData
    }

    mutating func readSequence(transferSyntax: TransferSyntax, length: UInt32) throws -> (items: [DICOMDataset], itemOffsets: [UInt32]) {
        let endOffset: Int?
        if length == .max {
            endOffset = nil
        } else {
            let candidate = offset + Int(length)
            guard candidate <= data.count else { throw DICOMError.truncatedData }
            endOffset = candidate
        }

        var items: [DICOMDataset] = []
        var itemOffsets: [UInt32] = []
        while offset < data.count {
            if let endOffset, offset == endOffset { return (items, itemOffsets) }
            let byteOrder: ByteOrder = transferSyntax == .explicitVRBigEndian ? .bigEndian : .littleEndian
            let itemOffset = offset
            let itemTag = try readTag(byteOrder: byteOrder)
            let itemLength = try readUInt32(byteOrder: byteOrder)
            if itemTag == DICOMTag(group: 0xFFFE, element: 0xE0DD) {
                guard endOffset == nil, itemLength == 0 else { throw DICOMError.invalidSequenceItem(itemTag) }
                return (items, itemOffsets)
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
            guard itemOffset <= Int(UInt32.max) else { throw DICOMError.truncatedData }
            itemOffsets.append(UInt32(itemOffset))
        }
        if let endOffset, offset == endOffset { return (items, itemOffsets) }
        throw DICOMError.truncatedData
    }

    mutating func readUndefinedLengthItem(transferSyntax: TransferSyntax) throws -> [DICOMElement] {
        var elements: [DICOMElement] = []
        while offset < data.count {
            let byteOrder: ByteOrder = transferSyntax == .explicitVRBigEndian ? .bigEndian : .littleEndian
            if peekTag(byteOrder: byteOrder) == DICOMTag(group: 0xFFFE, element: 0xE00D) {
                _ = try readTag(byteOrder: byteOrder)
                guard try readUInt32(byteOrder: byteOrder) == 0 else { throw DICOMError.truncatedData }
                return elements
            }
            elements.append(try readElement(transferSyntax: transferSyntax))
        }
        throw DICOMError.truncatedData
    }

    func peekTag(byteOrder: ByteOrder = .littleEndian) -> DICOMTag? {
        guard offset + 4 <= data.count else { return nil }
        return DICOMTag(group: byteOrder.uint16(in: data, at: offset), element: byteOrder.uint16(in: data, at: offset + 2))
    }

    mutating func readTag(byteOrder: ByteOrder = .littleEndian) throws -> DICOMTag {
        DICOMTag(group: try readUInt16(byteOrder: byteOrder), element: try readUInt16(byteOrder: byteOrder))
    }

    mutating func readUInt16(byteOrder: ByteOrder = .littleEndian) throws -> UInt16 {
        byteOrder.uint16(in: try readData(count: 2), at: 0)
    }

    mutating func readUInt32(byteOrder: ByteOrder = .littleEndian) throws -> UInt32 {
        byteOrder.uint32(in: try readData(count: 4), at: 0)
    }

    /// Looks up the VR `DICOMDictionary` associates with `tag`, for
    /// re-interpreting a defined-length `UN` element (see
    /// ``DICOMReadOptions/reinterpretsUnknownVR``).
    ///
    /// Returns `nil` (leaving the element `UN`) for Pixel Data, for any tag
    /// in an odd (private) group, or for a tag the dictionary doesn't know —
    /// none of those can be safely re-derived.
    private func reinterpretedVR(for tag: DICOMTag) -> DICOMVR? {
        guard tag != .pixelData, tag.group.isMultiple(of: 2) else { return nil }
        guard let dictVR = DICOMDictionary.vr(for: tag), dictVR != .UN else { return nil }
        return dictVR
    }

    /// Parses a defined-length `UN` element's value bytes as a sequence
    /// encoded in Implicit VR Little Endian (see the comment at the call
    /// site in ``readElement(transferSyntax:)`` for why that encoding, and
    /// not the enclosing dataset's, is the correct one to try).
    ///
    /// Returns `nil` without any visible side effect on `offset` if the
    /// bytes don't parse as a well-formed sequence occupying exactly
    /// `length` bytes, so the caller can fall back to treating the element
    /// as opaque `UN` data.
    private mutating func parseUnknownSequence(length: UInt32) -> (items: [DICOMDataset], itemOffsets: [UInt32])? {
        let startOffset = offset
        let expectedEndOffset = startOffset + Int(length)
        guard expectedEndOffset <= data.count,
              let sequence = try? readSequence(transferSyntax: .implicitVRLittleEndian, length: length),
              offset == expectedEndOffset
        else {
            offset = startOffset
            return nil
        }
        return sequence
    }

    mutating func readData(count: Int) throws -> Data {
        guard count >= 0, count <= data.count - offset else { throw DICOMError.truncatedData }
        defer { offset += count }
        return data.subdata(in: offset..<(offset + count))
    }
}

enum ByteOrder: Equatable {
    case littleEndian
    case bigEndian

    func uint16(in data: Data, at offset: Int) -> UInt16 {
        switch self {
        case .littleEndian: data.littleEndian(at: offset)
        case .bigEndian: UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
        }
    }

    func uint32(in data: Data, at offset: Int) -> UInt32 {
        switch self {
        case .littleEndian: data.littleEndian(at: offset)
        case .bigEndian:
            UInt32(data[offset]) << 24 | UInt32(data[offset + 1]) << 16 | UInt32(data[offset + 2]) << 8 | UInt32(data[offset + 3])
        }
    }
}

private func canonicalLittleEndian(_ value: Data, vr: DICOMVR) -> Data {
    let width: Int
    switch vr {
    case .US, .SS, .OW: width = 2
    case .UL, .SL, .FL, .OL, .OF: width = 4
    case .UV, .SV, .FD, .OD, .OV: width = 8
    case .AT: width = 2
    default: return value
    }
    guard value.count.isMultiple(of: width) else { return value }
    var canonical = Data()
    canonical.reserveCapacity(value.count)
    for offset in stride(from: 0, to: value.count, by: width) {
        canonical.append(contentsOf: value[offset..<(offset + width)].reversed())
    }
    return canonical
}
