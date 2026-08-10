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
