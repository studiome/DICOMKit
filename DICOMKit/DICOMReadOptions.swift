/// Options controlling how ``DICOMFile`` and ``DICOMMetadataFile`` resolve
/// ambiguous Value Representations while parsing a dataset.
public struct DICOMReadOptions: Sendable {
    /// When `true` (the default), a defined-length element whose wire VR is
    /// `UN` under Explicit VR Little Endian is re-tagged using the VR
    /// `DICOMDictionary` associates with its tag, per PS3.5 6.2.2.
    ///
    /// This commonly recovers typed values from data that passed through
    /// middleware which converted Implicit VR to Explicit VR without a
    /// dictionary of its own, leaving every attribute it didn't recognize
    /// tagged `UN` even though the attribute has a well-defined VR.
    public var reinterpretsUnknownVR: Bool

    /// Creates a set of read options.
    public init(reinterpretsUnknownVR: Bool = true) {
        self.reinterpretsUnknownVR = reinterpretsUnknownVR
    }

    /// The default options: `UN` re-interpretation enabled, no private
    /// dictionary.
    public static let `default` = DICOMReadOptions()
}
