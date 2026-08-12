/// A validation problem found while applying a set of DICOM module requirements.
public struct DICOMValidationIssue: Sendable, Equatable {
    /// The kind of requirement violation.
    public enum Kind: Sendable, Equatable {
        /// A Type 1 or Type 2 attribute was not present.
        case missingRequiredElement
        /// A Type 1 attribute was present but had no value.
        case emptyRequiredElement
        /// The element used a Value Representation other than the required one.
        case unexpectedVR(expected: DICOMVR, actual: DICOMVR)
    }

    /// The tag that did not satisfy its requirement.
    public let tag: DICOMTag
    /// The violation detected for ``tag``.
    public let kind: Kind

    /// Creates a validation issue.
    public init(tag: DICOMTag, kind: Kind) {
        self.tag = tag
        self.kind = kind
    }
}

/// A Type 1 or Type 2 attribute requirement from a DICOM module.
public struct DICOMModuleRequirement: Sendable, Equatable {
    /// DICOM requirement types supported by the validator.
    public enum Requirement: Sendable, Equatable {
        /// The attribute must be present and contain a value.
        case type1
        /// The attribute must be present; its value may be empty.
        case type2
    }

    /// The required attribute tag.
    public let tag: DICOMTag
    /// The expected Value Representation.
    public let vr: DICOMVR
    /// Whether the attribute is Type 1 or Type 2.
    public let requirement: Requirement

    /// Creates a module requirement.
    public init(tag: DICOMTag, vr: DICOMVR, requirement: Requirement) {
        self.tag = tag
        self.vr = vr
        self.requirement = requirement
    }
}

/// Validates explicitly supplied Type 1 and Type 2 DICOM module requirements.
///
/// This type intentionally does not claim complete IOD or SOP Class validation.
/// Callers provide the requirements for the module or profile they support, and
/// use the returned issues to report missing, empty, or incorrectly encoded
/// attributes.
public struct DICOMModuleValidator: Sendable {
    /// The requirements checked by this validator, in validation order.
    public let requirements: [DICOMModuleRequirement]

    /// Creates a validator for the supplied module requirements.
    public init(requirements: [DICOMModuleRequirement]) {
        self.requirements = requirements
    }

    /// Validates a dataset against the configured requirements.
    public func validate(_ dataset: DICOMDataset) -> [DICOMValidationIssue] {
        requirements.compactMap { requirement in
            guard let element = dataset[requirement.tag] else {
                return DICOMValidationIssue(tag: requirement.tag, kind: .missingRequiredElement)
            }
            guard element.vr == requirement.vr else {
                return DICOMValidationIssue(
                    tag: requirement.tag,
                    kind: .unexpectedVR(expected: requirement.vr, actual: element.vr)
                )
            }
            guard requirement.requirement == .type1, isEmpty(element) else { return nil }
            return DICOMValidationIssue(tag: requirement.tag, kind: .emptyRequiredElement)
        }
    }

    private func isEmpty(_ element: DICOMElement) -> Bool {
        if let sequenceItems = element.sequenceItems {
            return sequenceItems.isEmpty
        }
        return element.value.isEmpty
    }
}

/// Focused Type 1/Type 2 requirement sets for commonly exchanged image IODs.
///
/// These validators cover the shared identification and image-pixel modules
/// that DICOMKit uses. They are not a claim of full SOP Class conformance;
/// conditional and modality-specific modules remain application responsibilities.
public enum DICOMIODValidator {
    /// Common requirements for CT Image Storage datasets.
    public static let ctImageStorage = DICOMModuleValidator(requirements: commonImageRequirements)
    /// Common requirements for MR Image Storage datasets.
    public static let mrImageStorage = DICOMModuleValidator(requirements: commonImageRequirements)
    /// Common requirements for Secondary Capture Image Storage datasets.
    public static let secondaryCaptureImageStorage = DICOMModuleValidator(requirements: commonImageRequirements)

    private static let commonImageRequirements: [DICOMModuleRequirement] = [
        .init(tag: .sopClassUID, vr: .UI, requirement: .type1),
        .init(tag: .sopInstanceUID, vr: .UI, requirement: .type1),
        .init(tag: DICOMTag(group: 0x0008, element: 0x0060), vr: .CS, requirement: .type1),
        .init(tag: .patientName, vr: .PN, requirement: .type2),
        .init(tag: DICOMTag(group: 0x0010, element: 0x0020), vr: .LO, requirement: .type2),
        .init(tag: .studyInstanceUID, vr: .UI, requirement: .type1),
        .init(tag: .seriesInstanceUID, vr: .UI, requirement: .type1),
        .init(tag: .rows, vr: .US, requirement: .type1),
        .init(tag: .columns, vr: .US, requirement: .type1),
        .init(tag: .bitsAllocated, vr: .US, requirement: .type1),
        .init(tag: .bitsStored, vr: .US, requirement: .type1),
        .init(tag: .highBit, vr: .US, requirement: .type1),
        .init(tag: .pixelRepresentation, vr: .US, requirement: .type1),
        .init(tag: .pixelData, vr: .OW, requirement: .type1)
    ]
}
