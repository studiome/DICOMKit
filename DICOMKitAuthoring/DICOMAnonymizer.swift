import DICOMKit
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
        /// PS3.15's `Z`: the element is retained with its original VR and a
        /// zero-length value, rather than removed.
        ///
        /// Table E.1-1 codes `Z` almost exclusively for attributes that are
        /// Type 2 in their IOD — the IOD requires the element to be present
        /// even when its value is unknown — so dropping it, as `.remove`
        /// does, would make the output non-conformant DICOM rather than
        /// merely conservative. For a sequence element this produces an
        /// empty sequence (present, zero items), not an absent one.
        case emptyValue
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
        case .emptyValue:
            if element.sequenceItems != nil {
                return DICOMElement(tag: element.tag, vr: element.vr, value: Data(), sequenceItems: [])
            }
            return DICOMElement(tag: element.tag, vr: element.vr, value: Data())
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
/// These presets apply PS3.15's Basic Application Level Confidentiality
/// Profile (Table E.1-1, all 631 attribute rows — see
/// ``DICOMConfidentialityProfile``) to DICOMKit's action model. They still do
/// not constitute a full PS3.15 conformance claim on their own: DICOMKit does
/// not clean free text, structured content, graphics, or pixel data (see
/// ``DICOMDeidentificationAction/clean``), and a caller working from burned-in
/// image content must handle that separately (see
/// ``DICOMConfidentialityProfile/deidentify(_:replacement:)``).
public enum DICOMDeidentificationProfile {
    /// Returns a conservative Basic Application Level Confidentiality preset.
    ///
    /// Built from ``DICOMConfidentialityProfile/makeAnonymizer(replacement:)``
    /// with no options selected, so every one of Table E.1-1's 627 exact
    /// tags gets its real Basic Profile action — not a hand-picked subset,
    /// and with no per-tag special-casing. Patient's Name `(0010,0010)` and
    /// Patient ID `(0010,0020)`, in particular, get exactly the action Table
    /// E.1-1 prescribes (`Z` and `Z/D` respectively, both resolving to
    /// present-but-zero-length) rather than a visible dummy value — an
    /// earlier version of this preset overrode them with `replacement` text
    /// purely to keep a pre-existing test passing, which this no longer
    /// does. Study, series, SOP, and referenced SOP UIDs are deterministically
    /// remapped to `2.25` UIDs so internal references remain consistent.
    public static func basicApplicationLevelConfidentiality(replacement: String = "Anonymous") -> DICOMAnonymizer {
        DICOMConfidentialityProfile().makeAnonymizer(replacement: replacement)
    }
}
