/// Well-known SOP Class UIDs used by DIMSE services.
///
/// This is a convenience subset for the SOP Classes DICOMKit's DIMSE
/// support exercises directly — not the complete PS3.6 Annex A registry.
public enum DICOMSOPClass {
    /// Verification SOP Class.
    public static let verification = "1.2.840.10008.1.1"
    /// Patient Root Query/Retrieve Information Model – FIND.
    public static let patientRootQueryRetrieveFind = "1.2.840.10008.5.1.4.1.2.1.1"
    /// Patient Root Query/Retrieve Information Model – MOVE.
    public static let patientRootQueryRetrieveMove = "1.2.840.10008.5.1.4.1.2.1.2"
    /// Patient Root Query/Retrieve Information Model – GET.
    public static let patientRootQueryRetrieveGet = "1.2.840.10008.5.1.4.1.2.1.3"
    /// Study Root Query/Retrieve Information Model – FIND.
    public static let studyRootQueryRetrieveFind = "1.2.840.10008.5.1.4.1.2.2.1"
    /// Study Root Query/Retrieve Information Model – MOVE.
    public static let studyRootQueryRetrieveMove = "1.2.840.10008.5.1.4.1.2.2.2"
    /// Study Root Query/Retrieve Information Model – GET.
    public static let studyRootQueryRetrieveGet = "1.2.840.10008.5.1.4.1.2.2.3"
    /// Modality Worklist Information Model – FIND.
    public static let modalityWorklistFind = "1.2.840.10008.5.1.4.31"
    /// Computed Radiography Image Storage.
    public static let computedRadiographyImageStorage = "1.2.840.10008.5.1.4.1.1.1"
    /// Digital X-Ray Image Storage – For Presentation.
    public static let digitalXRayImageStorageForPresentation = "1.2.840.10008.5.1.4.1.1.1.1"
    /// Digital X-Ray Image Storage – For Processing.
    public static let digitalXRayImageStorageForProcessing = "1.2.840.10008.5.1.4.1.1.1.1.1"
    /// Digital Mammography X-Ray Image Storage – For Presentation.
    public static let digitalMammographyXRayImageStorageForPresentation = "1.2.840.10008.5.1.4.1.1.1.2"
    /// Digital Mammography X-Ray Image Storage – For Processing.
    public static let digitalMammographyXRayImageStorageForProcessing = "1.2.840.10008.5.1.4.1.1.1.2.1"
    /// CT Image Storage.
    public static let ctImageStorage = "1.2.840.10008.5.1.4.1.1.2"
    /// Enhanced CT Image Storage.
    public static let enhancedCTImageStorage = "1.2.840.10008.5.1.4.1.1.2.1"
    /// Ultrasound Multi-frame Image Storage.
    public static let ultrasoundMultiFrameImageStorage = "1.2.840.10008.5.1.4.1.1.3.1"
    /// MR Image Storage.
    public static let mrImageStorage = "1.2.840.10008.5.1.4.1.1.4"
    /// Enhanced MR Image Storage.
    public static let enhancedMRImageStorage = "1.2.840.10008.5.1.4.1.1.4.1"
    /// Ultrasound Image Storage.
    public static let ultrasoundImageStorage = "1.2.840.10008.5.1.4.1.1.6.1"
    /// Secondary Capture Image Storage.
    public static let secondaryCaptureImageStorage = "1.2.840.10008.5.1.4.1.1.7"
    /// Grayscale Softcopy Presentation State Storage.
    public static let grayscaleSoftcopyPresentationStateStorage = "1.2.840.10008.5.1.4.1.1.11.1"
    /// X-Ray Angiographic Image Storage.
    public static let xRayAngiographicImageStorage = "1.2.840.10008.5.1.4.1.1.12.1"
    /// X-Ray Radiofluoroscopic Image Storage.
    public static let xRayRadiofluoroscopicImageStorage = "1.2.840.10008.5.1.4.1.1.12.2"
    /// Nuclear Medicine Image Storage.
    public static let nuclearMedicineImageStorage = "1.2.840.10008.5.1.4.1.1.20"
    /// Segmentation Storage.
    public static let segmentationStorage = "1.2.840.10008.5.1.4.1.1.66.4"
    /// Basic Text SR Storage.
    public static let basicTextSRStorage = "1.2.840.10008.5.1.4.1.1.88.11"
    /// Enhanced SR Storage.
    public static let enhancedSRStorage = "1.2.840.10008.5.1.4.1.1.88.22"
    /// Comprehensive SR Storage.
    public static let comprehensiveSRStorage = "1.2.840.10008.5.1.4.1.1.88.33"
    /// Encapsulated PDF Storage.
    public static let encapsulatedPDFStorage = "1.2.840.10008.5.1.4.1.1.104.1"
    /// Positron Emission Tomography Image Storage.
    public static let petImageStorage = "1.2.840.10008.5.1.4.1.1.128"
    /// RT Image Storage.
    public static let rtImageStorage = "1.2.840.10008.5.1.4.1.1.481.1"
    /// Storage Commitment Push Model SOP Class.
    public static let storageCommitmentPushModel = "1.2.840.10008.1.20.1"
    /// Modality Performed Procedure Step SOP Class.
    public static let modalityPerformedProcedureStep = "1.2.840.10008.3.1.2.3.3"

    /// Every Storage SOP Class above, convenient for building a storage
    /// SCP's `supportedAbstractSyntaxes`.
    public static let imageStorage: Set<String> = [
        computedRadiographyImageStorage,
        digitalXRayImageStorageForPresentation,
        digitalXRayImageStorageForProcessing,
        digitalMammographyXRayImageStorageForPresentation,
        digitalMammographyXRayImageStorageForProcessing,
        ctImageStorage,
        enhancedCTImageStorage,
        ultrasoundMultiFrameImageStorage,
        mrImageStorage,
        enhancedMRImageStorage,
        ultrasoundImageStorage,
        secondaryCaptureImageStorage,
        grayscaleSoftcopyPresentationStateStorage,
        xRayAngiographicImageStorage,
        xRayRadiofluoroscopicImageStorage,
        nuclearMedicineImageStorage,
        segmentationStorage,
        basicTextSRStorage,
        enhancedSRStorage,
        comprehensiveSRStorage,
        encapsulatedPDFStorage,
        petImageStorage,
        rtImageStorage
    ]
}
