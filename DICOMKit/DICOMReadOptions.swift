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

    /// Vendor-specific VRs for private attributes, supplied by the caller.
    ///
    /// `nil` (the default) means private elements decode using only the
    /// standard `UN`/`SQ` Implicit VR convention: DICOMKit ships no private
    /// dictionary of its own. See ``DICOMPrivateDictionary`` for why.
    public var privateDictionary: DICOMPrivateDictionary?

    /// Creates a set of read options.
    public init(reinterpretsUnknownVR: Bool = true, privateDictionary: DICOMPrivateDictionary? = nil) {
        self.reinterpretsUnknownVR = reinterpretsUnknownVR
        self.privateDictionary = privateDictionary
    }

    /// The default options: `UN` re-interpretation enabled, no private
    /// dictionary.
    public static let `default` = DICOMReadOptions()
}
