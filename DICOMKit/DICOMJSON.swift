import Foundation

/// A typed DICOM JSON dataset (PS3.18 Annex F).
public struct DICOMJSONDataset: Codable, Sendable, Equatable {
    public var elements: [String: DICOMJSONElement]

    public init(elements: [String: DICOMJSONElement] = [:]) { self.elements = elements }

    public init(dataset: DICOMDataset) {
        self.elements = Dictionary(uniqueKeysWithValues: dataset.map { element in
            (String(format: "%04X%04X", element.tag.group, element.tag.element), DICOMJSONElement(element: element))
        })
    }

    /// Converts JSON elements that have in-memory `Value` representations to a DICOM dataset.
    public func dicomDataset() throws -> DICOMDataset {
        try DICOMDataset(elements: elements.map { key, value in
            guard key.count == 8, let group = UInt16(key.prefix(4), radix: 16), let element = UInt16(key.suffix(4), radix: 16) else { throw DICOMError.invalidDICOMJSON }
            return try value.dicomElement(tag: DICOMTag(group: group, element: element))
        })
    }
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
        inlineBinary = element.sequenceItems == nil && !Self.isJSONScalar(vr) ? element.value.base64EncodedString() : nil
        bulkDataURI = nil
        if let items = element.sequenceItems {
            value = items.map { .sequence(DICOMJSONDataset(dataset: $0)) }
        } else if Self.isJSONScalar(vr), let strings = element.stringValues {
            value = strings.map(DICOMJSONValue.string)
        } else if vr == .US, let values = element.uint16Values {
            value = values.map { .number(Double($0)) }
        } else {
            value = nil
        }
    }

    fileprivate func dicomElement(tag: DICOMTag) throws -> DICOMElement {
        if vr == .SQ {
            let items = try (value ?? []).map { value -> DICOMDataset in
                guard case .sequence(let dataset) = value else { throw DICOMError.invalidDICOMJSON }
                return try dataset.dicomDataset()
            }
            return DICOMElement(tag: tag, vr: vr, value: Data(), sequenceItems: items)
        }
        if let inlineBinary, let data = Data(base64Encoded: inlineBinary) { return DICOMElement(tag: tag, vr: vr, value: data) }
        guard let value else { return DICOMElement(tag: tag, vr: vr, value: Data()) }
        if vr == .US {
            var data = Data()
            for item in value {
                guard case .number(let number) = item, number.rounded() == number, (0...65535).contains(number) else { throw DICOMError.invalidDICOMJSON }
                let integer = UInt16(number)
                data.append(UInt8(integer & 0xFF)); data.append(UInt8(integer >> 8))
            }
            return DICOMElement(tag: tag, vr: vr, value: data)
        }
        guard value.allSatisfy({ if case .string = $0 { return true }; return false }) else { throw DICOMError.invalidDICOMJSON }
        let text = value.compactMap { if case .string(let string) = $0 { return string }; return nil }.joined(separator: "\\")
        return DICOMElement(tag: tag, vr: vr, value: Data(text.utf8))
    }

    private static func isJSONScalar(_ vr: DICOMVR) -> Bool {
        switch vr { case .AE, .AS, .CS, .DA, .DS, .DT, .IS, .LO, .LT, .PN, .SH, .ST, .TM, .UC, .UI, .UR, .UT: true; default: false }
    }
}

/// A DICOM JSON `Value` item.
public enum DICOMJSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case sequence(DICOMJSONDataset)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) { self = .string(string) }
        else if let number = try? container.decode(Double.self) { self = .number(number) }
        else { self = .sequence(try container.decode(DICOMJSONDataset.self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self { case .string(let value): try container.encode(value); case .number(let value): try container.encode(value); case .sequence(let value): try container.encode(value) }
    }
}
