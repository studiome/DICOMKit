/// A collection of DICOM elements indexed by tag.
///
/// Iterating a dataset (for example with `for element in dataset`) visits
/// its elements in ascending tag order, since DICOM datasets are
/// conventionally interpreted that way.
public struct DICOMDataset: Sendable, Sequence, Equatable {
    private var storage: [DICOMTag: DICOMElement]

    /// Creates a dataset containing the supplied elements.
    ///
    /// If multiple elements use the same tag, the last element is retained.
    public init(elements: [DICOMElement] = []) {
        storage = Dictionary(elements.map { ($0.tag, $0) }, uniquingKeysWith: { _, latest in latest })
    }

    /// Returns the element for `tag`, if present.
    public subscript(tag: DICOMTag) -> DICOMElement? { storage[tag] }

    /// The number of elements in the dataset.
    public var count: Int { storage.count }

    /// Whether the dataset contains no elements.
    public var isEmpty: Bool { storage.isEmpty }

    /// The character set declared by `(0008,0005)`, or UTF-8 when absent.
    public var characterSet: DICOMCharacterSet {
        guard let declaration = storage[.specificCharacterSet]?.stringValue,
              let first = declaration.split(separator: "\\", maxSplits: 1).first,
              let characterSet = DICOMCharacterSet(dicomName: String(first)) else {
            return .utf8
        }
        return characterSet
    }

    /// Decodes a text value using this dataset's Specific Character Set.
    public func stringValue(for tag: DICOMTag) -> String? {
        storage[tag]?.stringValue(characterSet: characterSet)
    }

    /// Returns the Private Creator that owns a private data element.
    ///
    /// `nil` is returned unless `tag` is in an odd private group and has an
    /// element number in the private data range `(gggg,10xx–FFxx)`.
    public func privateCreator(for tag: DICOMTag) -> String? {
        guard tag.group % 2 == 1, tag.element >= 0x1000 else { return nil }
        let block = UInt16(tag.element >> 8)
        guard block >= 0x10 else { return nil }
        let creatorTag = DICOMTag(group: tag.group, element: block)
        return storage[creatorTag]?.stringValue(characterSet: characterSet)
    }

    /// Resolves a private data element owned by `creator`.
    ///
    /// `element` is the low byte of the private tag (`ee` in
    /// `(gggg,xxee)`). The first matching private creator block is used.
    public func privateElement(creator: String, group: UInt16, element: UInt8) -> DICOMElement? {
        guard group % 2 == 1 else { return nil }
        for block in UInt16(0x10)...UInt16(0xFF) {
            let creatorTag = DICOMTag(group: group, element: block)
            guard storage[creatorTag]?.stringValue(characterSet: characterSet) == creator else { continue }
            let tag = DICOMTag(group: group, element: (block << 8) | UInt16(element))
            return storage[tag]
        }
        return nil
    }

    /// The dataset's tags, in ascending order.
    public var tags: [DICOMTag] { storage.keys.sorted() }

    /// Returns an iterator that visits the dataset's elements in ascending tag order.
    ///
    /// The return type is deliberately opaque instead of exposing the
    /// dictionary-backed storage, so the underlying storage representation
    /// can change in a future version without being an ABI-breaking change.
    public func makeIterator() -> some IteratorProtocol<DICOMElement> {
        storage.values.sorted { $0.tag < $1.tag }.makeIterator()
    }
}
