/// A collection of DICOM elements indexed by tag.
public struct DICOMDataset: Sendable, Sequence {
    private var storage: [DICOMTag: DICOMElement]

    /// Creates a dataset containing the supplied elements.
    ///
    /// If multiple elements use the same tag, the last element is retained.
    public init(elements: [DICOMElement] = []) {
        storage = Dictionary(elements.map { ($0.tag, $0) }, uniquingKeysWith: { _, latest in latest })
    }

    /// Returns the element for `tag`, if present.
    public subscript(tag: DICOMTag) -> DICOMElement? { storage[tag] }

    /// Returns an iterator over the dataset's elements.
    public func makeIterator() -> Dictionary<DICOMTag, DICOMElement>.Values.Iterator {
        storage.values.makeIterator()
    }
}
