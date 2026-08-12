import Testing
@testable import DICOMKit

struct DICOMSOPClassTests {
    @Test func exposesExactUIDsForEachWellKnownSOPClass() {
        let expected: [(String, String)] = [
            (DICOMSOPClass.verification, "1.2.840.10008.1.1"),
            (DICOMSOPClass.patientRootQueryRetrieveFind, "1.2.840.10008.5.1.4.1.2.1.1"),
            (DICOMSOPClass.patientRootQueryRetrieveMove, "1.2.840.10008.5.1.4.1.2.1.2"),
            (DICOMSOPClass.patientRootQueryRetrieveGet, "1.2.840.10008.5.1.4.1.2.1.3"),
            (DICOMSOPClass.studyRootQueryRetrieveFind, "1.2.840.10008.5.1.4.1.2.2.1"),
            (DICOMSOPClass.studyRootQueryRetrieveMove, "1.2.840.10008.5.1.4.1.2.2.2"),
            (DICOMSOPClass.studyRootQueryRetrieveGet, "1.2.840.10008.5.1.4.1.2.2.3"),
            (DICOMSOPClass.modalityWorklistFind, "1.2.840.10008.5.1.4.31"),
            (DICOMSOPClass.computedRadiographyImageStorage, "1.2.840.10008.5.1.4.1.1.1"),
            (DICOMSOPClass.digitalXRayImageStorageForPresentation, "1.2.840.10008.5.1.4.1.1.1.1"),
            (DICOMSOPClass.digitalXRayImageStorageForProcessing, "1.2.840.10008.5.1.4.1.1.1.1.1"),
            (DICOMSOPClass.digitalMammographyXRayImageStorageForPresentation, "1.2.840.10008.5.1.4.1.1.1.2"),
            (DICOMSOPClass.digitalMammographyXRayImageStorageForProcessing, "1.2.840.10008.5.1.4.1.1.1.2.1"),
            (DICOMSOPClass.ctImageStorage, "1.2.840.10008.5.1.4.1.1.2"),
            (DICOMSOPClass.enhancedCTImageStorage, "1.2.840.10008.5.1.4.1.1.2.1"),
            (DICOMSOPClass.ultrasoundMultiFrameImageStorage, "1.2.840.10008.5.1.4.1.1.3.1"),
            (DICOMSOPClass.mrImageStorage, "1.2.840.10008.5.1.4.1.1.4"),
            (DICOMSOPClass.enhancedMRImageStorage, "1.2.840.10008.5.1.4.1.1.4.1"),
            (DICOMSOPClass.ultrasoundImageStorage, "1.2.840.10008.5.1.4.1.1.6.1"),
            (DICOMSOPClass.secondaryCaptureImageStorage, "1.2.840.10008.5.1.4.1.1.7"),
            (DICOMSOPClass.grayscaleSoftcopyPresentationStateStorage, "1.2.840.10008.5.1.4.1.1.11.1"),
            (DICOMSOPClass.xRayAngiographicImageStorage, "1.2.840.10008.5.1.4.1.1.12.1"),
            (DICOMSOPClass.xRayRadiofluoroscopicImageStorage, "1.2.840.10008.5.1.4.1.1.12.2"),
            (DICOMSOPClass.nuclearMedicineImageStorage, "1.2.840.10008.5.1.4.1.1.20"),
            (DICOMSOPClass.segmentationStorage, "1.2.840.10008.5.1.4.1.1.66.4"),
            (DICOMSOPClass.basicTextSRStorage, "1.2.840.10008.5.1.4.1.1.88.11"),
            (DICOMSOPClass.enhancedSRStorage, "1.2.840.10008.5.1.4.1.1.88.22"),
            (DICOMSOPClass.comprehensiveSRStorage, "1.2.840.10008.5.1.4.1.1.88.33"),
            (DICOMSOPClass.encapsulatedPDFStorage, "1.2.840.10008.5.1.4.1.1.104.1"),
            (DICOMSOPClass.petImageStorage, "1.2.840.10008.5.1.4.1.1.128"),
            (DICOMSOPClass.rtImageStorage, "1.2.840.10008.5.1.4.1.1.481.1"),
            (DICOMSOPClass.storageCommitmentPushModel, "1.2.840.10008.1.20.1"),
            (DICOMSOPClass.modalityPerformedProcedureStep, "1.2.840.10008.3.1.2.3.3")
        ]
        for (actual, expectedUID) in expected {
            #expect(actual == expectedUID)
        }
    }

    @Test func imageStorageContainsStorageSOPClassesOnly() {
        #expect(DICOMSOPClass.imageStorage.contains(DICOMSOPClass.ctImageStorage))
        #expect(DICOMSOPClass.imageStorage.contains(DICOMSOPClass.mrImageStorage))
        #expect(!DICOMSOPClass.imageStorage.contains(DICOMSOPClass.verification))
        #expect(!DICOMSOPClass.imageStorage.contains(DICOMSOPClass.studyRootQueryRetrieveFind))
    }

    @Test func imageStorageMembersAreDistinctAndNonEmpty() {
        let members = Array(DICOMSOPClass.imageStorage)
        #expect(members.allSatisfy { !$0.isEmpty })
        #expect(Set(members).count == members.count)
    }
}
