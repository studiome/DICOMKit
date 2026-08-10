// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DICOMKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "DICOMKit",
            targets: ["DICOMKit"]
        )
    ],
    targets: [
        .target(
            name: "CharLS",
            path: "Vendor/CharLS",
            exclude: [
                "benchmark", "cli", "doc", "fuzzing", "samples", "test",
                "CMakeLists.txt", "CMakePresets.json", "LICENSES", "README.md",
                "src/charls.rc", "src/charls-template.pc", "src/charls.vcxproj",
                "src/charls.vcxproj.filters"
            ],
            publicHeadersPath: "include/charls",
            cxxSettings: [
                .headerSearchPath("include")
            ]
        ),
        .target(
            name: "DICOMKit",
            dependencies: ["CharLS"],
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
    ],
    cxxLanguageStandard: .cxx17
)
