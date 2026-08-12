import Foundation

/// A deterministic, caller-configured DICOM dataset de-identifier.
///
/// This is a transformation primitive, not a PS3.15 conformance claim.
/// Applications remain responsible for choosing an appropriate profile,
/// handling burned-in annotations, and retaining required clinical metadata.
public struct DICOMAnonymizer: Sendable {
    public enum Action: Sendable, Equatable {
        case remove
        case replace(String)
        case keep
    }

    public let actions: [DICOMTag: Action]
    public let removePrivateTags: Bool

    public init(actions: [DICOMTag: Action], removePrivateTags: Bool = true) {
        self.actions = actions
        self.removePrivateTags = removePrivateTags
    }

    /// Applies actions recursively to a dataset and all sequence items.
    public func anonymize(_ dataset: DICOMDataset) -> DICOMDataset {
        DICOMDataset(elements: dataset.compactMap(transform))
    }

    private func transform(_ element: DICOMElement) -> DICOMElement? {
        if removePrivateTags, element.tag.group.isMultiple(of: 2) == false { return nil }
        switch actions[element.tag] ?? .keep {
        case .remove: return nil
        case .replace(let text):
            return DICOMElement(tag: element.tag, vr: element.vr, value: Data(text.utf8))
        case .keep:
            guard let items = element.sequenceItems else { return element }
            return DICOMElement(tag: element.tag, vr: element.vr, value: Data(), sequenceItems: items.map(anonymize))
        }
    }
}
