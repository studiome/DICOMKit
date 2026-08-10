// Intentionally empty.
//
// This framework exists only to give Xcode Cloud a buildable product named
// DICOMKit; linking the local package is what makes Xcode Cloud resolve and
// build it, and the scheme's test action runs the package's own DICOMKitTests.
//
// It deliberately doesn't re-export DICOMKit: the product is named DICOMKit,
// so this module is too, and importing DICOMKit here would import itself.
