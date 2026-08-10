import Foundation
@testable import DICOMKit

enum FixtureError: Error {
    case missing(String)
}

/// Resolves a test fixture from the test bundle rather than the source tree,
/// so tests don't depend on where a checkout happens to live.
///
/// `Package.swift` copies `Fixtures` as a directory, so the resource keeps
/// that subdirectory (and any subdirectories nested under it, such as
/// `Fixtures/JPEGLS`) inside the bundle.
func fixtureURL(resource: String, extension fileExtension: String, subdirectory: String = "Fixtures") throws -> URL {
    guard let url = Bundle.module.url(
        forResource: resource,
        withExtension: fileExtension,
        subdirectory: subdirectory
    ) else {
        throw FixtureError.missing("\(subdirectory)/\(resource).\(fileExtension)")
    }
    return url
}

/// pydicom's `CT_small.dcm`: a 128x128 Explicit VR Little Endian CT slice with
/// signed samples and a -1024 Rescale Intercept.
func ctFixture() throws -> DICOMFile {
    try DICOMFile(data: Data(contentsOf: try fixtureURL(resource: "CT_small", extension: "dcm")))
}
