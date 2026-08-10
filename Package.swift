// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DICOMKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v11)
    ],
    products: [
        .library(
            name: "DICOMKit",
            targets: ["DICOMKit"]
        )
    ],
    targets: [
        .target(
            name: "DICOMKit",
            path: "DICOMKit",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "DICOMKitTests",
            dependencies: ["DICOMKit"],
            path: "DICOMKitTests",
            // Fixtures are resolved from the test bundle, which also makes
            // them available in Xcode Cloud rather than depending on a
            // source-tree path.
            resources: [
                .copy("Fixtures")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
