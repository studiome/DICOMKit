import Foundation
@testable import DICOMKit

private final class FixtureBundleToken: NSObject {}

enum FixtureError: Error {
    case missing(String)
}

/// Resolves a test fixture from the test bundle instead of the source tree.
/// Xcode Cloud checks out and builds source in a different location, whereas
/// copied test resources are always available from this bundle.
func fixtureURL(resource: String, extension fileExtension: String) throws -> URL {
    #if SWIFT_PACKAGE
    let bundle = Bundle.module
    #else
    let bundle = Bundle(for: FixtureBundleToken.self)
    #endif
    // Xcode copies the synchronized test resource group directly into the
    // bundle root, while SwiftPM preserves the `Fixtures` directory. Support
    // both layouts so local SwiftPM, Xcode, and Xcode Cloud share these tests.
    for subdirectory in [nil, "Fixtures"] {
        if let url = bundle.url(forResource: resource, withExtension: fileExtension, subdirectory: subdirectory) {
            return url
        }
    }
    throw FixtureError.missing("\(resource).\(fileExtension)")
}

/// pydicom's `CT_small.dcm`: a 128x128 Explicit VR Little Endian CT slice with
/// signed samples and a -1024 Rescale Intercept.
func ctFixture() throws -> DICOMFile {
    try DICOMFile(data: Data(contentsOf: try fixtureURL(resource: "CT_small", extension: "dcm")))
}
