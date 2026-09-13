/// One vendor-documented private attribute: the Private Creator that owns
/// its block, its group and low byte, its VR, and an optional human-readable
/// name.
public struct DICOMPrivateTagEntry: Sendable, Equatable, Hashable {
    /// The Private Creator value that owns this attribute's block, for
    /// example `"ACME 3D"`. Compared after trimming trailing spaces and
    /// NULs, since Private Creator values are `LO` and are padded on the
    /// wire to an even length.
    public let privateCreator: String
    /// The private group this attribute lives in. Must be odd.
    public let group: UInt16
    /// The low byte of the private tag: `ee` in `(gggg,xxee)`, where `xx` is
    /// the block assigned to `privateCreator`.
    public let elementLowByte: UInt8
    /// The vendor-documented VR for this attribute.
    public let vr: DICOMVR
    /// An optional human-readable name for this attribute.
    public let name: String?

    /// Creates a private tag entry.
    public init(privateCreator: String, group: UInt16, elementLowByte: UInt8, vr: DICOMVR, name: String? = nil) {
        self.privateCreator = privateCreator
        self.group = group
        self.elementLowByte = elementLowByte
        self.vr = vr
        self.name = name
    }
}

/// A caller-supplied table of vendor-specific private attribute VRs.
///
/// Private attributes are not published as part of the DICOM standard: each
/// vendor documents (or fails to document) its own meaning for the private
/// blocks it registers under a Private Creator. Because of that, DICOMKit
/// ships **no** vendor entries of its own, on purpose. A private dictionary
/// assembled from reverse engineering, rather than from a vendor's own
/// documentation, can make DICOMKit read a vendor's bytes as the wrong
/// type — for example decoding binary data as text, or a signed value as
/// unsigned. Being unable to read a private attribute (it stays `UN`) is
/// safer than reading it wrongly, so this type exists purely as a mechanism:
/// applications that can vouch for a vendor's documentation supply their own
/// entries via ``DICOMReadOptions/privateDictionary``.
public struct DICOMPrivateDictionary: Sendable, Equatable {
    private struct Key: Hashable {
        let privateCreator: String
        let group: UInt16
        let elementLowByte: UInt8
    }

    private var entriesByKey: [Key: DICOMPrivateTagEntry]

    /// Builds a dictionary from `entries`.
    ///
    /// - Throws: ``DICOMError/invalidPrivateDictionary`` if any entry
    ///   declares an even group; private attributes live only in odd groups.
    public init(_ entries: [DICOMPrivateTagEntry]) throws {
        var entriesByKey: [Key: DICOMPrivateTagEntry] = [:]
        for entry in entries {
            guard entry.group % 2 == 1 else { throw DICOMError.invalidPrivateDictionary }
            let key = Key(privateCreator: Self.normalize(entry.privateCreator), group: entry.group, elementLowByte: entry.elementLowByte)
            entriesByKey[key] = entry
        }
        self.entriesByKey = entriesByKey
    }

    /// The registered VR for `(group,elementLowByte)` under `privateCreator`, if any.
    public func vr(privateCreator: String, group: UInt16, elementLowByte: UInt8) -> DICOMVR? {
        entry(privateCreator: privateCreator, group: group, elementLowByte: elementLowByte)?.vr
    }

    /// The registered human-readable name for `(group,elementLowByte)` under
    /// `privateCreator`, if any.
    public func name(privateCreator: String, group: UInt16, elementLowByte: UInt8) -> String? {
        entry(privateCreator: privateCreator, group: group, elementLowByte: elementLowByte)?.name
    }

    private func entry(privateCreator: String, group: UInt16, elementLowByte: UInt8) -> DICOMPrivateTagEntry? {
        entriesByKey[Key(privateCreator: Self.normalize(privateCreator), group: group, elementLowByte: elementLowByte)]
    }

    /// Trims trailing DICOM padding (space or NUL) so a creator read off the
    /// wire matches a registered creator regardless of which padding byte
    /// (or whether any) was used to reach an even length.
    private static func normalize(_ creator: String) -> String {
        var trimmed = Substring(creator)
        while let last = trimmed.last, last == " " || last == "\0" {
            trimmed.removeLast()
        }
        return String(trimmed)
    }
}
