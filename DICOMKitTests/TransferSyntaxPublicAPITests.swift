import Testing
// Deliberately a plain `import`, not `@testable import` — this file should
// see only what an external consumer sees, not `internal` members.
//
// That said, this alone does NOT prove `init(uid:)` is `public` rather than
// `package`: SwiftPM's `package` access level is visible package-wide, and
// `DICOMKitTests` is a target inside the same `Package.swift` as `DICOMKit`,
// so a plain `import DICOMKit` here resolves `package` symbols exactly as it
// resolves `public` ones (verified empirically — this file compiled
// unchanged while `init(uid:)` was still `package`). So if this initializer
// ever regresses from `public` back to `package`, this test keeps compiling
// and keeps passing; it would not catch that regression.
//
// The actual compile-time gate for "is this `public`" is a consumer outside
// this package: a separate Swift package (its own `Package.swift`, not a
// target listed here) that depends on DICOMKit via `.package(path:)` and
// calls `TransferSyntax(uid:)`. Only that build fails if this initializer
// ever stops being `public` — it is not something `swift test` runs, so
// treat it as a manual check to repeat after touching this access level.
import DICOMKit

/// Confirms `TransferSyntax.init(uid:)` is usable from outside the package,
/// and that it maps UIDs the way external consumers depend on: every known
/// UID to its case, and anything else to `.unknown` rather than failing.
struct TransferSyntaxPublicAPITests {
    static let knownCases: [(TransferSyntax, String)] = [
        (.implicitVRLittleEndian, "1.2.840.10008.1.2"),
        (.explicitVRLittleEndian, "1.2.840.10008.1.2.1"),
        (.explicitVRBigEndian, "1.2.840.10008.1.2.2"),
        (.deflatedExplicitVRLittleEndian, "1.2.840.10008.1.2.1.99"),
        (.rleLossless, "1.2.840.10008.1.2.5"),
        (.jpegBaseline, "1.2.840.10008.1.2.4.50"),
        (.jpegLossless, "1.2.840.10008.1.2.4.57"),
        (.jpegLosslessSV1, "1.2.840.10008.1.2.4.70"),
        (.jpegLSLossless, "1.2.840.10008.1.2.4.80"),
        (.jpegLSNearLossless, "1.2.840.10008.1.2.4.81"),
        (.jpeg2000Lossless, "1.2.840.10008.1.2.4.90"),
        (.jpeg2000, "1.2.840.10008.1.2.4.91"),
        (.htj2kLossless, "1.2.840.10008.1.2.4.201"),
        (.htj2kLosslessRPCL, "1.2.840.10008.1.2.4.202"),
        (.htj2k, "1.2.840.10008.1.2.4.203")
    ]

    @Test(arguments: knownCases)
    func knownUIDMapsToItsCase(transferSyntax: TransferSyntax, uid: String) {
        #expect(TransferSyntax(uid: uid) == transferSyntax)
    }

    @Test func unrecognisedUIDBecomesUnknown() {
        let uid = "1.2.9999.not.a.real.syntax"
        #expect(TransferSyntax(uid: uid) == .unknown(uid))
    }
}
