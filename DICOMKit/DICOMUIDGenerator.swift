import Foundation

/// Generates numeric DICOM UIDs below an organization-controlled root.
public struct DICOMUIDGenerator: Sendable {
    public let root: String

    /// Creates a UID generator for an ISO OID root such as `1.2.826.0.1`.
    public init(root: String) throws {
        guard Self.isValidRoot(root) else { throw DICOMError.invalidUIDRoot }
        self.root = root
    }

    /// Generates a unique, numeric UID no longer than 64 characters.
    public func generate() -> String {
        let milliseconds = UInt64(Date().timeIntervalSince1970 * 1_000)
        let random = UInt64.random(in: .min ... .max)
        return "\(root).\(milliseconds).\(random)"
    }

    private static func isValidRoot(_ root: String) -> Bool {
        // A generated suffix needs two separators, 13 decimal digits for
        // milliseconds, and up to 20 for a UInt64 random component.
        guard !root.isEmpty, root.count <= 29 else { return false }
        return root.split(separator: ".", omittingEmptySubsequences: false).allSatisfy {
            !$0.isEmpty && $0.allSatisfy(\.isNumber) && ($0 == "0" || $0.first != "0")
        }
    }
}
