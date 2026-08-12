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
