import DICOMKit

/// Minimal framework used only to make the local DICOMKit package available
/// to Xcode Cloud, which cannot build a standalone Swift package directly.
public enum DICOMKitCloudHost {
    /// A package symbol referenced by the host smoke test.
    public static let explicitVRLittleEndianUID = TransferSyntax.explicitVRLittleEndian.uid
}
