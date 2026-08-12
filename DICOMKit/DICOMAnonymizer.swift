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
        /// Replaces a UI using a stable, non-reversible `2.25` pseudonymous UID.
        case remapUID
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
        case .remapUID:
            guard element.vr == .UI, let uid = element.stringValue, !uid.isEmpty else { return nil }
            return DICOMElement(tag: element.tag, vr: .UI, value: Data(Self.pseudonymousUID(for: uid).utf8))
        case .keep:
            guard let items = element.sequenceItems else { return element }
            return DICOMElement(tag: element.tag, vr: element.vr, value: Data(), sequenceItems: items.map(anonymize), sequenceItemOffsets: element.sequenceItemOffsets)
        }
    }

    private static func pseudonymousUID(for value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return "2.25.\(hash)"
    }
}

/// Conservative, profile-inspired de-identification presets.
///
/// These presets map the most common direct identifiers in PS3.15's Basic
/// Application Level Confidentiality Profile to DICOMKit actions. They do not
/// constitute a PS3.15 conformance claim: applications must still account for
/// burned-in annotations, private semantics, dates, and local policy.
public enum DICOMDeidentificationProfile {
    /// Returns a conservative Basic Application Level Confidentiality preset.
    ///
    /// Direct patient identifiers are replaced or removed. Study, series, SOP,
    /// and referenced SOP UIDs are deterministically remapped to `2.25` UIDs
    /// so internal references remain consistent.
    public static func basicApplicationLevelConfidentiality(replacement: String = "Anonymous") -> DICOMAnonymizer {
        let remove = DICOMAnonymizer.Action.remove
        let replace = DICOMAnonymizer.Action.replace(replacement)
        let remap = DICOMAnonymizer.Action.remapUID
        return DICOMAnonymizer(actions: [
            .patientName: replace,
            DICOMTag(group: 0x0010, element: 0x0020): replace,
            DICOMTag(group: 0x0010, element: 0x0030): remove,
            DICOMTag(group: 0x0010, element: 0x0032): remove,
            DICOMTag(group: 0x0010, element: 0x1000): remove,
            DICOMTag(group: 0x0010, element: 0x1001): remove,
            DICOMTag(group: 0x0010, element: 0x1040): remove,
            DICOMTag(group: 0x0010, element: 0x2154): remove,
            DICOMTag(group: 0x0008, element: 0x0050): remove,
            DICOMTag(group: 0x0008, element: 0x0080): remove,
            DICOMTag(group: 0x0008, element: 0x0090): remove,
            DICOMTag(group: 0x0008, element: 0x1048): remove,
            DICOMTag(group: 0x0008, element: 0x1050): remove,
            DICOMTag(group: 0x0008, element: 0x1060): remove,
            DICOMTag(group: 0x0008, element: 0x1070): remove,
            DICOMTag(group: 0x0032, element: 0x1032): remove,
            DICOMTag(group: 0x0038, element: 0x0010): remove,
            DICOMTag(group: 0x0040, element: 0x0006): remove,
            .studyInstanceUID: remap,
            .seriesInstanceUID: remap,
            .sopInstanceUID: remap,
            .referencedSOPInstanceUID: remap,
            .mediaStorageSOPInstanceUID: remap
        ])
    }
}
