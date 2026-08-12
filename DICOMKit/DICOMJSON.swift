import Foundation

/// A typed DICOM JSON dataset (PS3.18 Annex F).
public struct DICOMJSONDataset: Codable, Sendable, Equatable {
    public var elements: [String: DICOMJSONElement]

    public init(elements: [String: DICOMJSONElement] = [:]) { self.elements = elements }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DICOMJSONTagCodingKey.self)
        elements = try Dictionary(uniqueKeysWithValues: container.allKeys.map { key in
            (key.stringValue, try container.decode(DICOMJSONElement.self, forKey: key))
        })
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DICOMJSONTagCodingKey.self)
        for (tag, element) in elements {
            guard let key = DICOMJSONTagCodingKey(stringValue: tag) else { throw DICOMError.invalidDICOMJSON }
            try container.encode(element, forKey: key)
        }
    }

    public init(dataset: DICOMDataset) {
        self.elements = Dictionary(uniqueKeysWithValues: dataset.compactMap { element in
            // Group Length is explicitly excluded by PS3.18 F.2.2.
            guard element.tag.element != 0 else { return nil }
            return (String(format: "%04X%04X", element.tag.group, element.tag.element), DICOMJSONElement(element: element))
        })
    }

    /// Converts JSON elements with in-memory `Value` or `InlineBinary`
    /// representations to a DICOM dataset.
    ///
    /// `BulkDataURI` deliberately has no implicit network fetch. A caller must
    /// resolve it through its own authenticated WADO-RS transport before
    /// constructing an in-memory dataset.
    public func dicomDataset() throws -> DICOMDataset {
        try DICOMDataset(elements: elements.map { key, value in
            guard key.count == 8,
                  let group = UInt16(key.prefix(4), radix: 16),
                  let element = UInt16(key.suffix(4), radix: 16) else {
                throw DICOMError.invalidDICOMJSON
            }
            return try value.dicomElement(tag: DICOMTag(group: group, element: element))
        })
    }
}

private struct DICOMJSONTagCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) { nil }
}

/// A typed DICOM JSON element.
public struct DICOMJSONElement: Codable, Sendable, Equatable {
    public let vr: DICOMVR
    public let value: [DICOMJSONValue]?
    public let inlineBinary: String?
    public let bulkDataURI: String?

    public init(vr: DICOMVR, value: [DICOMJSONValue]? = nil, inlineBinary: String? = nil, bulkDataURI: String? = nil) {
        self.vr = vr; self.value = value; self.inlineBinary = inlineBinary; self.bulkDataURI = bulkDataURI
    }

    private enum CodingKeys: String, CodingKey { case vr, value = "Value", inlineBinary = "InlineBinary", bulkDataURI = "BulkDataURI" }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let parsedVR = DICOMVR(rawValue: try container.decode(String.self, forKey: .vr)) else { throw DICOMError.invalidDICOMJSON }
        vr = parsedVR
        value = try container.decodeIfPresent([DICOMJSONValue].self, forKey: .value)
        inlineBinary = try container.decodeIfPresent(String.self, forKey: .inlineBinary)
        bulkDataURI = try container.decodeIfPresent(String.self, forKey: .bulkDataURI)
        guard [value != nil, inlineBinary != nil, bulkDataURI != nil].filter({ $0 }).count <= 1 else { throw DICOMError.invalidDICOMJSON }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(vr.rawValue, forKey: .vr)
        try container.encodeIfPresent(value, forKey: .value)
        try container.encodeIfPresent(inlineBinary, forKey: .inlineBinary)
        try container.encodeIfPresent(bulkDataURI, forKey: .bulkDataURI)
    }

    init(element: DICOMElement) {
        vr = element.vr
        bulkDataURI = nil
        if let items = element.sequenceItems {
            value = items.map { .sequence(DICOMJSONDataset(dataset: $0)) }
            inlineBinary = nil
        } else if Self.isInlineBinaryVR(element.vr) {
            value = nil
            inlineBinary = element.value.base64EncodedString()
        } else {
            value = Self.values(for: element)
            inlineBinary = nil
        }
    }

    fileprivate func dicomElement(tag: DICOMTag) throws -> DICOMElement {
        guard bulkDataURI == nil else { throw DICOMError.invalidDICOMJSON }
        if vr == .SQ {
            let items = try (value ?? []).map { item -> DICOMDataset in
                guard case .sequence(let dataset) = item else { throw DICOMError.invalidDICOMJSON }
                return try dataset.dicomDataset()
            }
            return DICOMElement(tag: tag, vr: vr, value: Data(), sequenceItems: items)
        }
        if Self.isInlineBinaryVR(vr) {
            guard let inlineBinary, let data = Data(base64Encoded: inlineBinary) else { throw DICOMError.invalidDICOMJSON }
            return DICOMElement(tag: tag, vr: vr, value: data)
        }
        return DICOMElement(tag: tag, vr: vr, value: try Self.encodedValue(for: vr, values: value ?? []))
    }

    private static func values(for element: DICOMElement) -> [DICOMJSONValue]? {
        switch element.vr {
        case .PN:
            return element.stringValues?.map { .personName(DICOMJSONPersonName(dicomValue: $0)) }
        case .AT:
            return element.attributeTagValues?.map { .string(String(format: "%04X%04X", $0.group, $0.element)) }
        case .US: return element.uint16Values?.map { .number(Double($0)) }
        case .SS: return element.int16Values?.map { .number(Double($0)) }
        case .UL: return element.uint32Values?.map { .number(Double($0)) }
        case .SL: return element.int32Values?.map { .number(Double($0)) }
        case .FL: return element.float32Values?.map { .number(Double($0)) }
        case .FD: return element.float64Values?.map(DICOMJSONValue.number)
        case .UV: return element.uint64Values?.map { .string(String($0)) }
        case .SV: return element.uint64Values?.map { .string(String(Int64(bitPattern: $0))) }
        case .AE, .AS, .CS, .DA, .DS, .DT, .IS, .LO, .LT, .SH, .ST, .TM, .UC, .UI, .UR, .UT:
            return element.stringValues?.map(DICOMJSONValue.string)
        default:
            return nil
        }
    }

    private static func encodedValue(for vr: DICOMVR, values: [DICOMJSONValue]) throws -> Data {
        switch vr {
        case .PN:
            return Data(try values.map { item in
                guard case .personName(let name) = item else { throw DICOMError.invalidDICOMJSON }
                return name.dicomValue
            }.joined(separator: "\\").utf8)
        case .AT:
            var data = Data()
            for item in values {
                guard case .string(let value) = item,
                      value.count == 8,
                      let group = UInt16(value.prefix(4), radix: 16),
                      let element = UInt16(value.suffix(4), radix: 16),
                      value == value.uppercased() else { throw DICOMError.invalidDICOMJSON }
                data.append(UInt8(group & 0xFF)); data.append(UInt8(group >> 8))
                data.append(UInt8(element & 0xFF)); data.append(UInt8(element >> 8))
            }
            return data
        case .US: return try integerData(values, type: UInt16.self)
        case .SS: return try signedIntegerData(values, type: Int16.self)
        case .UL: return try integerData(values, type: UInt32.self)
        case .SL: return try signedIntegerData(values, type: Int32.self)
        case .UV: return try unsigned64Data(values)
        case .SV: return try signed64Data(values)
        case .FL: return try float32Data(values)
        case .FD: return try float64Data(values)
        case .AE, .AS, .CS, .DA, .DS, .DT, .IS, .LO, .LT, .SH, .ST, .TM, .UC, .UI, .UR, .UT:
            return Data(try values.map(stringValue).joined(separator: "\\").utf8)
        default:
            guard values.isEmpty else { throw DICOMError.invalidDICOMJSON }
            return Data()
        }
    }

    private static func stringValue(_ value: DICOMJSONValue) throws -> String {
        guard case .string(let string) = value else { throw DICOMError.invalidDICOMJSON }
        return string
    }

    private static func numberValue(_ value: DICOMJSONValue) throws -> Double {
        guard case .number(let number) = value, number.isFinite else { throw DICOMError.invalidDICOMJSON }
        return number
    }

    private static func integerData<T: FixedWidthInteger & UnsignedInteger>(_ values: [DICOMJSONValue], type: T.Type) throws -> Data {
        var data = Data()
        for value in values {
            let number = try numberValue(value)
            guard number.rounded() == number, number >= 0, number <= Double(T.max) else { throw DICOMError.invalidDICOMJSON }
            let integer = T(number)
            for offset in 0..<MemoryLayout<T>.size { data.append(UInt8(truncatingIfNeeded: integer >> (offset * 8))) }
        }
        return data
    }

    private static func signedIntegerData<T: FixedWidthInteger & SignedInteger>(_ values: [DICOMJSONValue], type: T.Type) throws -> Data {
        var data = Data()
        for value in values {
            let number = try numberValue(value)
            guard number.rounded() == number, number >= Double(T.min), number <= Double(T.max) else { throw DICOMError.invalidDICOMJSON }
            let integer = T(number)
            let bits = T.Magnitude(truncatingIfNeeded: integer)
            for offset in 0..<MemoryLayout<T>.size { data.append(UInt8(truncatingIfNeeded: bits >> (offset * 8))) }
        }
        return data
    }

    private static func unsigned64Data(_ values: [DICOMJSONValue]) throws -> Data {
        var data = Data()
        for value in values {
            let integer: UInt64
            switch value { case .string(let text): guard let parsed = UInt64(text) else { throw DICOMError.invalidDICOMJSON }; integer = parsed
            case .number(let number): guard number.isFinite, number.rounded() == number, number >= 0, number <= Double(UInt64.max) else { throw DICOMError.invalidDICOMJSON }; integer = UInt64(number)
            default: throw DICOMError.invalidDICOMJSON }
            for offset in 0..<8 { data.append(UInt8(truncatingIfNeeded: integer >> (offset * 8))) }
        }
        return data
    }

    private static func signed64Data(_ values: [DICOMJSONValue]) throws -> Data {
        var data = Data()
        for value in values {
            let integer: Int64
            switch value { case .string(let text): guard let parsed = Int64(text) else { throw DICOMError.invalidDICOMJSON }; integer = parsed
            case .number(let number): guard number.isFinite, number.rounded() == number, number >= Double(Int64.min), number <= Double(Int64.max) else { throw DICOMError.invalidDICOMJSON }; integer = Int64(number)
            default: throw DICOMError.invalidDICOMJSON }
            let bits = UInt64(bitPattern: integer)
            for offset in 0..<8 { data.append(UInt8(truncatingIfNeeded: bits >> (offset * 8))) }
        }
        return data
    }

    private static func float32Data(_ values: [DICOMJSONValue]) throws -> Data {
        var data = Data()
        for value in values {
            let number = try numberValue(value)
            let bits = Float(number).bitPattern
            for offset in 0..<4 { data.append(UInt8(truncatingIfNeeded: bits >> (offset * 8))) }
        }
        return data
    }

    private static func float64Data(_ values: [DICOMJSONValue]) throws -> Data {
        var data = Data()
        for value in values {
            let bits = try numberValue(value).bitPattern
            for offset in 0..<8 { data.append(UInt8(truncatingIfNeeded: bits >> (offset * 8))) }
        }
        return data
    }

    private static func isInlineBinaryVR(_ vr: DICOMVR) -> Bool {
        switch vr { case .OB, .OD, .OF, .OL, .OV, .OW, .UN: true; default: false }
    }
}

/// A Person Name value in DICOM JSON's three representation groups.
public struct DICOMJSONPersonName: Codable, Sendable, Equatable {
    public let alphabetic: String?
    public let ideographic: String?
    public let phonetic: String?

    public init(alphabetic: String? = nil, ideographic: String? = nil, phonetic: String? = nil) {
        self.alphabetic = alphabetic; self.ideographic = ideographic; self.phonetic = phonetic
    }

    private enum CodingKeys: String, CodingKey { case alphabetic = "Alphabetic", ideographic = "Ideographic", phonetic = "Phonetic" }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        alphabetic = try container.decodeIfPresent(String.self, forKey: .alphabetic)
        ideographic = try container.decodeIfPresent(String.self, forKey: .ideographic)
        phonetic = try container.decodeIfPresent(String.self, forKey: .phonetic)
        guard alphabetic != nil || ideographic != nil || phonetic != nil else { throw DICOMError.invalidDICOMJSON }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(alphabetic, forKey: .alphabetic)
        try container.encodeIfPresent(ideographic, forKey: .ideographic)
        try container.encodeIfPresent(phonetic, forKey: .phonetic)
    }

    fileprivate init(dicomValue: String) {
        let groups = dicomValue.split(separator: "=", maxSplits: 2, omittingEmptySubsequences: false)
        alphabetic = groups.indices.contains(0) ? String(groups[0]) : nil
        ideographic = groups.indices.contains(1) ? String(groups[1]) : nil
        phonetic = groups.indices.contains(2) ? String(groups[2]) : nil
    }

    fileprivate var dicomValue: String {
        let values = [alphabetic, ideographic, phonetic]
        guard let last = values.lastIndex(where: { $0 != nil }) else { return "" }
        return values[...last].map { $0 ?? "" }.joined(separator: "=")
    }
}

/// A DICOM JSON `Value` item.
public enum DICOMJSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case personName(DICOMJSONPersonName)
    case sequence(DICOMJSONDataset)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) { self = .string(string) }
        else if let number = try? container.decode(Double.self) { self = .number(number) }
        else if let name = try? container.decode(DICOMJSONPersonName.self) { self = .personName(name) }
        else { self = .sequence(try container.decode(DICOMJSONDataset.self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .personName(let value): try container.encode(value)
        case .sequence(let value): try container.encode(value)
        }
    }
}
