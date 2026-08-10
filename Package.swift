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
            // Copied as a directory so fixtures resolve from the test bundle
            // rather than from a source-tree path, which CI checkouts don't
            // share.
            resources: [
                .copy("Fixtures")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
