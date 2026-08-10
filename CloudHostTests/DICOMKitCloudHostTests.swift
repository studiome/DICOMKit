import Testing
@testable import DICOMKitCloudHost

struct DICOMKitCloudHostTests {
    @Test func linksLocalDICOMKitPackage() {
        #expect(DICOMKitCloudHost.explicitVRLittleEndianUID == "1.2.840.10008.1.2.1")
    }
}
